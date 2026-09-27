---
title: FMU packaging
section: 7
version: 0.49
status: draft
normative: true
depends_on: [06-lifecycle.md, 09-abi.md]
---

# 7. FMU Packaging (`org.driveline.dcm`)

A `component ... from_fmu("...")` declaration uses one of two modes. The compiler picks the mode from the declaration. A declaration with `bind_inputs` or `bind_outputs` blocks is Mode B. A declaration without them is Mode A.

* **Mode A (Driveline-Aware FMU):** The FMU implements the FMI 3.0 layered standard `org.driveline.dcm`. It ships a manifest at `extra/org.driveline.dcm/manifest.json` in the format of [§15](15-manifest.md). A Mode A declaration whose FMU has no manifest is a compile-time error.
  * Each checkpoint port is an `fmi3Binary` variable with MIME type `application/x-driveline.<checkpoint-type>;version=0.11`. The value is the [§9](09-abi.md) struct, byte for byte.
  * Each `SliceBuffer` port is an `fmi3Binary` variable with MIME type `application/x-driveline.slice-buffer.<slice-type>;version=0.11`. The value is a `dl_slice_buffer_header_t` followed by `count` entries, newest first. Each entry is a `uint64_t t_ns` followed by the slice struct.
  * Initialization uses the `fmi3Binary` input `dl_init_context` (MIME type `application/x-driveline.init-context;version=0.11`). The runtime sets it in initialization mode, at $t = 0$ for cold init and at $t = t_{\text{splice}}$ for warm start. `is_warm_start` tells the two apart. For a splice, the runtime creates a new FMU instance. For a re-trim ([§6.2.4](06-lifecycle.md)), it calls `fmi3Reset` and initializes again with the re-trim context.
  * Component parameters are FMI parameters with the same names.
  * The actor's own state ([§9.1](09-abi.md)) is the `fmi3Binary` input `own_state` with MIME type `application/x-driveline.kinematic-state;version=0.11`. The runtime sets it on every step.
  * Mode A FMUs are $1\text{:}1$ only. They cannot be bound to a group.
* **Mode B (Scalar-Pin FMU):** A legacy FMU with scalar `Float64` pins. `bind_inputs` maps expressions over the `SliceBuffer` ports and `own_state` onto input pins. `bind_outputs` maps output pins onto a checkpoint frame. Cold init uses the FMU's own start values. Splicing a Mode B FMU at $t > 0$ uses the first case that applies:
  1. **Restore a Saved State:** If this FMU instance was spliced out earlier in the same run, and the FMU declares `canGetAndSetFMUState="true"`, the runtime saved its state with `fmi3GetFMUState` at splice-out. The runtime restores that state with `fmi3SetFMUState`. The restored state is from the splice-out time, not the current time. The runtime reports `DL_STATUS_WARN_FMU_COLD_SPLICE`.
  2. **Cold Splice:** Otherwise the runtime calls `fmi3Reset`, or creates a new instance, and sets the input start values by evaluating `bind_inputs` at $t_{\text{splice}}$. It then calls `fmi3EnterInitializationMode` with `startTime` $= t_{\text{splice}}$, then `fmi3ExitInitializationMode`, and reports `DL_STATUS_WARN_FMU_COLD_SPLICE`.

  In `bind_outputs`, a frame field that no assignment names is zero. If `valid_mask` is not assigned, it is the union of the bits that cover the assigned fields ([§5](05-checkpoints.md)). Named call-site arguments that are not input ports are FMI parameters with the same names, set before initialization.

  A Mode B FMU cannot be re-trimmed ([§6.2.4](06-lifecycle.md)). An FMU state saved with `fmi3GetFMUState` is opaque, so the runtime cannot build one from `dl_init_context_t`.

## 7.1 Stepping and Output Timing

Both modes use FMI 3.0 Co-Simulation. On each tick $t$ where the component is scheduled, with period $h = k_{\text{div}} \cdot \Delta t_{\text{base}}$ ([§11](11-execution.md)), the runtime does three things in order:

1. It sets the inputs for tick $t$.
2. It calls `fmi3DoStep` with `currentCommunicationPoint` $= t$ and `communicationStepSize` $= h$.
3. It reads the outputs and uses them as the component's output for tick $t$.

The outputs read in step 3 describe the FMU at $t + h$ computed from inputs held over $[t, t + h)$. An FMU component therefore reacts to its inputs one period later than a native component with the same logic. Scenario authors who compare FMU and native components must account for this delay of $h$.
