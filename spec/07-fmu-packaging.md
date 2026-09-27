---
title: FMU packaging
section: 7
version: 0.4
status: draft
normative: true
depends_on: [06-lifecycle.md, 09-abi.md]
---

# 7. FMU Packaging (`org.driveline.dcm`)

A `component ... from_fmu("...")` declaration uses one of two modes. The compiler picks the mode from the declaration. A declaration with `bind_inputs` or `bind_outputs` blocks is Mode B. A declaration without them is Mode A.

* **Mode A (Driveline-Aware FMU):** The FMU implements the FMI 3.0 layered standard `org.driveline.dcm`. It ships a manifest at `extra/org.driveline.dcm/manifest.xml` that lists its Driveline ports. A Mode A declaration whose FMU has no manifest is a compile-time error.
  * Each checkpoint port is an `fmi3Binary` variable with MIME type `application/x-driveline.<checkpoint-type>;version=0.3`. The value is the [§9](09-abi.md) struct, byte for byte.
  * Each `SliceBuffer` port is an `fmi3Binary` variable with MIME type `application/x-driveline.slice-buffer.<slice-type>;version=0.3`. The value is a `dl_slice_buffer_header_t` followed by `count` entries, newest first. Each entry is a `uint64_t t_ns` followed by the slice struct.
  * Initialization uses the `fmi3Binary` input `dl_init_context` (MIME type `application/x-driveline.init-context;version=0.3`). The master sets it in initialization mode at $t = 0$ for cold init and at $t = t_{\text{splice}}$ for warm start. `is_warm_start` tells the two apart.
  * Component parameters are FMI parameters with the same names.
  * Mode A FMUs are $1\text{:}1$ only. They cannot be bound to a group.
* **Mode B (Scalar-Pin FMU):** A legacy FMU with scalar `Float64` pins. `bind_inputs` maps `SliceBuffer` expressions onto input pins. `bind_outputs` maps output pins onto a checkpoint frame. Cold init uses the FMU's own start values. Splicing a Mode B FMU at $t > 0$ uses the first case that applies:
  1. **Restore a Saved State:** If this FMU instance was spliced out earlier in the same run, and the FMU declares `canGetAndSetFMUState="true"`, the master saved its state with `fmi3GetFMUState` at splice-out. The master restores that state with `fmi3SetFMUState`. The restored state is from the splice-out time, not the current time. The master logs `WARN_FMU_COLD_SPLICE`.
  2. **Cold Splice:** Otherwise the master calls `fmi3Reset`, or creates a new instance, and sets the input start values by evaluating `bind_inputs` at $t_{\text{splice}}$. It then calls `fmi3EnterInitializationMode` with `startTime` $= t_{\text{splice}}$, then `fmi3ExitInitializationMode`, and logs `WARN_FMU_COLD_SPLICE`.

  A Mode B FMU cannot be re-trimmed ([§6.2.4](06-lifecycle.md)). An FMU state saved with `fmi3GetFMUState` is opaque, so the master cannot build one from `dl_init_context_t`.
