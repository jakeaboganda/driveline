---
title: FMU packaging
section: 7
version: 0.157
status: draft
normative: true
depends_on: [05-checkpoints.md, 06-lifecycle.md, 09-abi.md, 10-composition.md, 11-execution.md, 14-diagnostics.md, 15-manifest.md]
---

# 7. FMU Packaging (`org.driveline.dcm`)

A `component ... from_fmu("...")` declaration uses one of two modes. The compiler picks the mode from the declaration. A declaration with `bind_inputs` or `bind_outputs` blocks is Mode B. A declaration without them is Mode A.

* **Mode A (Driveline-Aware FMU):** The FMU implements the FMI 3.0 layered standard `org.driveline.dcm`. It ships a manifest at `extra/org.driveline.dcm/manifest.json` in the format of [§15](15-manifest.md). A Mode A declaration whose FMU has no manifest is a compile-time error.
  * Each checkpoint port is an `fmi3Binary` variable with MIME type `application/x-driveline.<checkpoint-type>;version=0.14`. The value is the [§9](09-abi.md) struct layout in the byte order below.
  * Each prior port, such as `RouteNodes`, is an `fmi3Binary` variable with MIME type `application/x-driveline.<prior-type>;version=0.14`, holding its struct (`dl_route_t` for `RouteNodes`). The runtime sets it in initialization mode.
  * Every `fmi3Binary` value uses little-endian byte order and IEEE 754 binary64 for `double`, whatever the host.
  * Times inside a frame, such as `trajectory` offsets ([§5.1](05-checkpoints.md)), are relative to the `timestamp_ns` that the runtime stamps, which is the tick time $t$ ([§7.1](07-fmu-packaging.md)). The runtime does not shift them when it reads the output. Only the hold rule of [§5](05-checkpoints.md) shifts a held trajectory.
  * Each `SliceBuffer` port is an `fmi3Binary` variable with MIME type `application/x-driveline.slice-buffer.<slice-type>;version=0.14`. The value is a `dl_slice_buffer_header_t` followed by `count` entries, newest first. Each entry is a `uint64_t t_ns` followed by the slice struct.
  * Initialization uses the `fmi3Binary` input `dl_init_context` (MIME type `application/x-driveline.init-context;version=0.14`), set in initialization mode ([§7.2](07-fmu-packaging.md)). `is_warm_start` tells cold init from warm start.
  * **Variable names:** Each input port is the FMI variable with the port's manifest name and causality `input`. The output is the single variable named `output` with causality `output`. `dl_init_context` and `own_state` are inputs with those names. A missing variable, or a variable with another type or MIME type, is a compile-time error.
  * Component parameters are FMI parameters with the same names.
  * The actor's own state ([§9.1](09-abi.md)) is the `fmi3Binary` input `own_state` with MIME type `application/x-driveline.kinematic-state;version=0.14`. The runtime sets it on every step.
  * A Mode A manifest's `cardinality` must be `OneToOne`. Any other value is a compile-time error.
  * **MIME subtype names:** `<checkpoint-type>`, `<slice-type>`, and `<prior-type>` are the type names written in lowercase with a hyphen before each inner capital: `IntentFrame` is `intent-frame`, `KinematicControlFrame` is `kinematic-control-frame`, and `RadarSlice` is `radar-slice`.
* **Mode B (Scalar-Pin FMU):** A legacy FMU with scalar `Float64` pins. `bind_inputs` maps expressions over the `SliceBuffer` ports and `own_state` onto input pins. `bind_outputs` maps output pins onto a checkpoint frame. A splice starts a new instance that initializes from `bind_inputs` alone, as at cold init ([§7.2](07-fmu-packaging.md)), and the runtime reports `DL_STATUS_WARN_FMU_COLD_SPLICE`.

  In `bind_outputs`, a frame field that no assignment names is zero. If `valid_mask` is not assigned, it is the union of the bits that cover the assigned fields ([§5](05-checkpoints.md)), and a union that [§5](05-checkpoints.md) forbids, such as `0x04` with `0x08`, is a compile-time error. Named call-site arguments that are not input ports are FMI parameters with the same names, set before initialization.

  A Mode B FMU cannot be re-trimmed ([§6.2.4](06-lifecycle.md)), because it has no input for `dl_init_context_t`.

In both modes:

* **No map callbacks:** An FMU gets no host map callbacks ([§9.2](09-abi.md)), because the callback table holds in-process pointers. Map context reaches an FMU only through its ports, priors, and `own_state`.
* **Units:** Every bound `Float64` variable that declares a unit must declare one whose conversion to base units has factor 1 and offset 0 and whose base-unit exponents match the dimension of the value bound to it, ignoring any `rad` exponent because angles are dimensionless. Any other unit is a compile-time error, so the runtime never converts units.
* **Times:** `startTime` and `communicationStepSize` are the binary64 values nearest to their nanosecond counts divided by $10^9$. The first `currentCommunicationPoint` is `startTime`, and each later one is the previous one plus the previous `communicationStepSize` in binary64, so the points are contiguous as FMI 3.0 requires.

## 7.1 Stepping and Output Timing

Both modes use FMI 3.0 Co-Simulation. On each tick $t$ where the component is scheduled, with period $h = k_{\text{div}} \cdot \Delta t_{\text{base}}$ ([§11](11-execution.md)), the runtime does three things in order:

1. It sets the inputs for tick $t$.
2. It calls `fmi3DoStep` with the `currentCommunicationPoint` of tick $t$ by the Times rule of [§7](07-fmu-packaging.md) and `communicationStepSize` $= h$.
3. It reads the outputs and uses them as the component's output for tick $t$. An FMI return of `fmi3Warning` counts as `fmi3OK`. Any worse return is `DL_STATUS_ERR_FMU` ([§14](14-diagnostics.md)).

The outputs read in step 3 describe the FMU at $t + h$ computed from inputs held over $[t, t + h)$. An FMU component therefore reacts to its inputs one period later than a native component with the same logic. Scenario authors who compare FMU and native components must account for this delay of $h$.

## 7.2 Lifecycle Mapping

The runtime drives an FMU through the [§6](06-lifecycle.md) states with these FMI 3.0 calls. "Initialize at $t$" means: call `fmi3EnterInitializationMode` with `startTime` $= t$, set the inputs, and call `fmi3ExitInitializationMode`. A Mode A FMU's inputs are `dl_init_context`, `own_state`, its ports, and its prior variables, so a re-trim after `fmi3Reset` sets the priors again. A Mode B FMU's inputs are the `bind_inputs` expressions. At initialization, each checkpoint port holds the context's latched frame of its type ([§6.2](06-lifecycle.md)), each `SliceBuffer` port holds the actor's latest buffer, and `own_state` and `bind_inputs` read the committed state, as they stand when the runtime initializes the FMU.

| [§6](06-lifecycle.md) Call | FMU Calls |
| :--- | :--- |
| `dl_instantiate` | `fmi3InstantiateCoSimulation`. |
| `dl_set_parameters` | Set each parameter by name: a quantity with `fmi3SetFloat64` in SI units, an `Int` with `fmi3SetInt64`, a `Time` with `fmi3SetInt64` in nanoseconds, a `Bool` with `fmi3SetBoolean`, and an enum with `fmi3SetInt64` as its numeric value. A parameter whose FMI variable has another type is a compile-time error. |
| `dl_configure_structure` | None. A Mode A FMU reads buffer depths from each `dl_slice_buffer_header_t`. |
| `dl_enter_cold_init`, `dl_exit_init_mode` | Initialize at $t = 0$. |
| `dl_enter_warm_start` (splice) | Initialize at $t_{\text{first}}$, the first tick at or after the next tick at which the component is scheduled ([§11](11-execution.md)), so its first `fmi3DoStep` starts at `startTime`. The new instance has already been instantiated and given its parameters, and the outgoing instance is terminated and freed ([§10](10-composition.md)). |
| `dl_enter_warm_start` (re-trim, Mode A only) | `fmi3Reset`, set the parameters again, and initialize at $t_{\text{first}}$, as for a splice, with the re-trim context ([§6.2.4](06-lifecycle.md)). |
| `dl_do_step` | `fmi3DoStep` as [§7.1](07-fmu-packaging.md) describes. |
| `dl_terminate` | `fmi3Terminate`. |
| `dl_free_instance` | `fmi3FreeInstance`. |
