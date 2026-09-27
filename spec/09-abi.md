---
title: C-ABI
section: 9
version: 0.25
status: draft
normative: true
depends_on: [05-checkpoints.md, 04-perception.md]
---

# 9. Normative C-ABI Header (`driveline_abi.h`)

All structs in `driveline_abi.h` use fixed-width types and explicit padding, so the compiler inserts no padding. Data structs contain no pointers: vehicle parameters, sensor slices, checkpoint frames, `dl_route_t`, and `dl_init_context_t`. Their layout is identical on 32-bit and 64-bit targets, and Mode A FMUs exchange them byte for byte ([§7](07-fmu-packaging.md)). Call descriptors (`dl_slice_buffer_view_t`, `dl_batch_step_io_t`, `dl_structural_config_t`) and the callback table contain pointers. They are valid only inside one process.

The normative header is [`abi/driveline_abi.h`](../abi/driveline_abi.h). This section does not copy it.

## 9.1 Calling Rules

1. **Version Encoding:** `DL_ABI_VERSION_<major>_<minor>` has the value `(major << 16) | (minor << 8)`. Before version 1.0, a component and a runtime work together only if their versions are equal. `dl_instantiate` returns `DL_STATUS_ERR_INVALID_ARG` for any other version. `struct_size` in `dl_init_context_t` must equal the component's `sizeof(dl_init_context_t)`.
2. **Strings:** `const char*` arguments are null-terminated UTF-8. A `char[N]` field holds at most $N - 1$ bytes plus a terminating null. A scenario that names a road ID longer than 63 bytes is a compile-time error.
3. **Pointer Lifetime:** A pointer that the runtime passes into a call, including every pointer inside a call descriptor, is valid only until that call returns. A component must not keep it. The callback table and `host_ctx` are the exception: they stay valid from `dl_instantiate` until `dl_free_instance`.
4. **Output Memory:** The runtime allocates `outputs` in `dl_batch_step_io_t` with `actor_count` entries, `output_stride` bytes apart, in the order of `actor_ids`. `dl_do_step` must write every entry. Callback out-parameters are allocated by the caller.
5. **Header Fields:** After `dl_do_step` returns, the runtime writes `actor_id` and `timestamp_ns` into every output frame. The component's values for these two fields are ignored. `timestamp_ns` is the tick time $t$ of the step, except for `KinematicState`, where it is $t + \Delta t_{\text{base}}$ ([§5.3](05-checkpoints.md)).
6. **Step Times:** `sim_time_ns` is the tick time $t$. `dt_step_ns` is $k_{\text{div}} \cdot \Delta t_{\text{base\_ns}}$, the component's period ([§11](11-execution.md)), including on the first step.
7. **Threads:** The runtime never calls one instance from two threads at the same time. It may call different instances at the same time. Host callbacks must be thread-safe and deterministic. A component calls host callbacks only during a `dl_*` call and on the thread that made it.
