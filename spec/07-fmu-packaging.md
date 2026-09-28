---
title: FMU packaging
section: 7
version: 0.93
status: draft
normative: true
depends_on: [05-checkpoints.md, 06-lifecycle.md, 09-abi.md, 10-composition.md, 11-execution.md, 14-diagnostics.md, 15-manifest.md]
---

# 7. FMU Packaging (`org.driveline.dcm`)

A `component ... from_fmu("...")` declaration uses one of two modes. The compiler picks the mode from the declaration. A declaration with `bind_inputs` or `bind_outputs` blocks is Mode B. A declaration without them is Mode A.

* **Mode A (Driveline-Aware FMU):** The FMU implements the FMI 3.0 layered standard `org.driveline.dcm`. It ships a manifest at `extra/org.driveline.dcm/manifest.json` in the format of [§15](15-manifest.md). A Mode A declaration whose FMU has no manifest is a compile-time error.
  * Each checkpoint port is an `fmi3Binary` variable with MIME type `application/x-driveline.<checkpoint-type>;version=0.13`. The value is the [§9](09-abi.md) struct, byte for byte.
  * Each prior port, such as `RouteNodes`, is an `fmi3Binary` variable with MIME type `application/x-driveline.<prior-type>;version=0.13`, holding its struct (`dl_route_t` for `RouteNodes`). The runtime sets it in initialization mode.
  * Every `fmi3Binary` value uses little-endian byte order and IEEE 754 binary64 for `double`, whatever the host.
  * Times inside a frame, such as `trajectory` offsets ([§5.1](05-checkpoints.md)), are relative to the `timestamp_ns` that the runtime stamps, which is the tick time $t$ ([§7.1](07-fmu-packaging.md)). The runtime does not shift them.
  * Each `SliceBuffer` port is an `fmi3Binary` variable with MIME type `application/x-driveline.slice-buffer.<slice-type>;version=0.13`. The value is a `dl_slice_buffer_header_t` followed by `count` entries, newest first. Each entry is a `uint64_t t_ns` followed by the slice struct.
  * Initialization uses the `fmi3Binary` input `dl_init_context` (MIME type `application/x-driveline.init-context;version=0.13`), set in initialization mode ([§7.2](07-fmu-packaging.md)). `is_warm_start` tells cold init from warm start.
  * Component parameters are FMI parameters with the same names.
  * The actor's own state ([§9.1](09-abi.md)) is the `fmi3Binary` input `own_state` with MIME type `application/x-driveline.kinematic-state;version=0.13`. The runtime sets it on every step.
  * A Mode A manifest's `cardinality` must be `OneToOne`. Any other value is a compile-time error.
  * **MIME subtype names:** `<checkpoint-type>`, `<slice-type>`, and `<prior-type>` are the type names written in lowercase with a hyphen before each inner capital: `IntentFrame` is `intent-frame`, `KinematicControlFrame` is `kinematic-control-frame`, and `RadarSlice` is `radar-slice`.
* **Mode B (Scalar-Pin FMU):** A legacy FMU with scalar `Float64` pins. `bind_inputs` maps expressions over the `SliceBuffer` ports and `own_state` onto input pins. `bind_outputs` maps output pins onto a checkpoint frame. A splice starts a new instance that initializes from `bind_inputs` alone, as at cold init ([§7.2](07-fmu-packaging.md)), and the runtime reports `DL_STATUS_WARN_FMU_COLD_SPLICE`.

  In `bind_outputs`, a frame field that no assignment names is zero. If `valid_mask` is not assigned, it is the union of the bits that cover the assigned fields ([§5](05-checkpoints.md)). Named call-site arguments that are not input ports are FMI parameters with the same names, set before initialization.

  A Mode B FMU cannot be re-trimmed ([§6.2.4](06-lifecycle.md)), because it has no input for `dl_init_context_t`.

## 7.1 Stepping and Output Timing

Both modes use FMI 3.0 Co-Simulation. On each tick $t$ where the component is scheduled, with period $h = k_{\text{div}} \cdot \Delta t_{\text{base}}$ ([§11](11-execution.md)), the runtime does three things in order:

1. It sets the inputs for tick $t$.
2. It calls `fmi3DoStep` with `currentCommunicationPoint` $= t$ and `communicationStepSize` $= h$.
3. It reads the outputs and uses them as the component's output for tick $t$. An FMI return of `fmi3Warning` counts as `fmi3OK`. Any worse return is `DL_STATUS_ERR_FMU` ([§14](14-diagnostics.md)).

The outputs read in step 3 describe the FMU at $t + h$ computed from inputs held over $[t, t + h)$. An FMU component therefore reacts to its inputs one period later than a native component with the same logic. Scenario authors who compare FMU and native components must account for this delay of $h$.

## 7.2 Lifecycle Mapping

The runtime drives an FMU through the [§6](06-lifecycle.md) states with these FMI 3.0 calls. "Initialize at $t$" means: call `fmi3EnterInitializationMode` with `startTime` $= t$, set the inputs, and call `fmi3ExitInitializationMode`. A Mode A FMU's inputs are `dl_init_context`, `own_state`, and its ports. A Mode B FMU's inputs are the `bind_inputs` expressions evaluated at $t$.

| [§6](06-lifecycle.md) Call | FMU Calls |
| :--- | :--- |
| `dl_instantiate` | `fmi3InstantiateCoSimulation`. |
| `dl_set_parameters` | Set each parameter by name with the matching `fmi3Set<Type>` call. |
| `dl_configure_structure` | None. A Mode A FMU reads buffer depths from each `dl_slice_buffer_header_t`. |
| `dl_enter_cold_init`, `dl_exit_init_mode` | Initialize at $t = 0$. |
| `dl_enter_warm_start` (splice) | Initialize at $t_{\text{splice}}$. The new instance has already been instantiated and given its parameters, and the outgoing instance is terminated and freed ([§10](10-composition.md)). |
| `dl_enter_warm_start` (re-trim, Mode A only) | `fmi3Reset`, set the parameters again, and initialize at the current tick with the re-trim context ([§6.2.4](06-lifecycle.md)). |
| `dl_do_step` | `fmi3DoStep` as [§7.1](07-fmu-packaging.md) describes. |
| `dl_terminate` | `fmi3Terminate`. |
| `dl_free_instance` | `fmi3FreeInstance`. |
