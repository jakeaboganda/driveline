---
title: C-ABI
section: 9
version: 0.35
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
7. **Own State:** `own_states[i]` is the committed `KinematicState` of actor `actor_ids[i]` at tick time $t$, as Phase 4 of the previous tick left it. On Tick 0 it is the `chassis_state` from cold init Pass 1 ([§6.2](06-lifecycle.md)). Every component receives it, because controllers and planners need their own vehicle's speed, pose, and lane. It is the only World state that a component receives outside its sensors and the map.
8. **Threads:** The runtime never calls one instance from two threads at the same time. It may call different instances at the same time. Host callbacks must be thread-safe and deterministic. A component calls host callbacks only during a `dl_*` call and on the thread that made it.

## 9.2 Host Map Callbacks

The runtime implements these callbacks over the scenario's OpenDRIVE map. Every heading and curvature is measured in the direction of increasing $s$ unless a rule says otherwise, and positive curvature turns left. An argument outside the map returns `DL_STATUS_ERR_INVALID_ARG` and leaves the outputs unchanged.

* **`world_to_frenet(X, Y, psi, hint_road_id)`:** Returns the lane whose area contains $(X, Y)$, with `s` on that road's reference line, `d` from that lane's centerline, and `psi_lane`, the lane heading at `s`. If several lanes contain the point, as in a junction, the callback prefers `hint_road_id`, then the lane whose heading is closest to `psi`, then the smallest `(road_id, lane_id)` in byte order. If no lane contains the point, it returns the lane with the nearest centerline, using the same tie-breaks.
* **`frenet_to_world(road_id, lane_id, s, d)`:** Returns the point at offset `d` from the lane centerline at `s`, `Z` as the road elevation there, and `psi_lane` and `kappa_lane` of the lane centerline at `s`. An `s` outside $[0, \text{road length}]$ is invalid.
* **`sample_lane_path(road_id, lane_id, s_start, d_offset, ds, count, out)`:** Writes `count` points at $s = s_{\text{start}} + k \cdot ds$. A negative `ds` samples toward decreasing $s$. Each point's heading and curvature are in the sampling direction. When sampling leaves the road, it continues on the successor lane in the sampling direction, choosing the smallest `(road_id, lane_id)` if there are several. If there is no successor, the remaining points repeat the last point.
* **`query_lane_topology(road_id, lane_id, s, ...)`:** Returns the neighboring lanes in the lane section that contains `s`. `out_left_lane_id` is the neighbor on the side of increasing lane ID and `out_right_lane_id` the neighbor on the side of decreasing lane ID, skipping lane 0, with 0 meaning none. Successors are the lanes that this lane connects to at its end in its driving direction, through road links or junction connections, sorted by `(road_id, lane_id)`.
