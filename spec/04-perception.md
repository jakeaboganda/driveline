---
title: Priors, sensors, and SliceBuffer
section: 4
version: 0.7
status: draft
normative: true
depends_on: [02-conventions.md]
---

# 4. Actor Perception: Priors, Sensors, & `SliceBuffer<T, N>`

Pipeline components cannot access the global World state. Actors perceive external reality solely through mounted **Priors** and **Sensors**:

## 4.1 Priors (`priors`)
Static or slow-updating contextual memory mounted on the actor:
* `RouteNodes`: Ordered array of up to 64 lanes (`dl_route_t`, [§9](09-abi.md)) that the actor intends to drive through. Each node is a `dl_lane_ref_t` `(road_id, lane_id)`. The DSL writes nodes as lane reference strings ([§2](02-conventions.md)).

## 4.2 Timestamped Ring Buffers (`SliceBuffer<T, N>`)
Every mounted sensor has a compile-time capacity $N \in [1, 64]$ declared in its port signature `SliceBuffer<T, N>`. A sensor with capacity $N_s$ can bind to any component input port expecting `SliceBuffer<T, N_c>` provided $N_s \ge N_c$. Each entry is a `Timestamped<T>` struct containing `{ uint64 t_ns; T data; }`. In the DSL, `slice.t` is the entry's `Time`, and `slice.field` is shorthand for `slice.data.field`. [§9](09-abi.md) defines the memory layout (`dl_slice_buffer_view_t`).

**Timestamp Invariant:** Timestamps in a buffer strictly decrease from $s[0]$ to $s[\text{count}-1]$. The runtime never pushes two samples with the same `t_ns`. Cold initialization ([§6.2](06-lifecycle.md)) relies on this rule.

All `SliceBuffer<T, N>` ports enforce deterministic edge-case semantics across four query primitives:
1. `buffer.latest() -> Timestamped<T>`: Equivalent to `buffer[0]`. Guaranteed valid from $t = 0$ because cold initialization Pass 1 performs the Tick 0 sensor projection ([§6.2](06-lifecycle.md)).
2. `buffer[k] / buffer.history(k) -> Timestamped<T>`:
   * **Compile-Time Bounds Check:** If $k$ is a compile-time constant and $k \ge N$, compilation fails.
   * **Early-Tick Underflow Rule ($k \ge \text{count}$):** Before $k+1$ samples have been recorded (e.g., on Tick 0 when $\text{count} == 1$), `buffer[k]` clamps to the oldest available sample `buffer[count - 1]` and sets `buffer.underflow = true`.
3. `buffer.rate_of(field_selector, window: k = 1) -> Rate`: Finite-difference derivative helper. `Rate` is `{ float64 value; bool valid; }`. With $m = \min(k, \text{count}-1)$:
   $$\text{rate\_of}(f, k) = \begin{cases} \{0.0, \text{false}\} & \text{if } \text{count} < 2 \\ \left\{\dfrac{s[0].f - s[m].f}{s[0].t - s[m].t}, \text{true}\right\} & \text{otherwise} \end{cases}$$
   The timestamp invariant makes the denominator positive whenever $\text{count} \ge 2$. Consumers must check `valid`. A `value` of $0.0$ with `valid = false` means "no estimate", not "no motion".
4. `buffer.at(t_query, mode: Interpolate | Floor) -> Timestamped<T>`:
   * **Clamping:** If $t_{\text{query}} \ge s[0].t$, returns $s[0]$. If $t_{\text{query}} \le s[\text{count}-1].t$, returns $s[\text{count}-1]$. `t_query` is a signed `Time` and may be negative. A negative query returns the oldest sample.
   * **`Floor` Mode:** Returns the newest sample $s[k]$ where $s[k].t \le t_{\text{query}}$.
   * **`Interpolate` Mode:** For bracket $s[k+1].t \le t_{\text{query}} < s[k].t$ with $\alpha = \frac{t_{\text{query}} - s[k+1].t}{s[k].t - s[k+1].t} \in [0, 1)$, each field follows its interpolation class from [§4.3](04-perception.md):
     * **`LINEAR`:** $(1 - \alpha) v_{k+1} + \alpha v_k$.
     * **`ANGLE`:** Linear interpolation along the shorter arc, wrapped to $(-\pi, \pi]$.
     * **`HOLD`:** Value from $s[k+1]$. Every integer, enum, flag, and `char[]` field is `HOLD`.
     * **Road-Relative Fields:** A `LINEAR` field marked with a road dependency (for example `ego_s` depends on `ego_road_id`) is interpolated only when the dependency fields are equal in both samples. Otherwise the whole sample is taken from $s[k+1]$.
     * **Non-Finite Values:** If a `LINEAR` or `ANGLE` field is not finite in either sample, the field takes its value from $s[k+1]$.
     * **Target Track Arrays (`TargetTrack[32]`):** Matched across $s[k+1]$ and $s[k]$ by `target_actor_id`. Tracks present in both samples interpolate field by field under the rules above. Tracks present in only one sample are taken from $s[k+1]$, or dropped if absent from $s[k+1]$.

## 4.3 Normative Sensor Slice Schemas (and ASAM OSI Mapping)
Driveline defines four standard sensor slice payloads, one track element type (`TargetTrack`), and one composite (`SensorBundle`). All are defined in `driveline_abi.h` ([§9](09-abi.md)). Conforming runtimes may also fill them from **ASAM OSI** `osi3::SensorView` / `osi3::SensorData` messages. Appendix A lists the OSI mappings that still need checking against the OSI release.

| Slice Type | C-ABI Struct | Fields & Semantics | ASAM OSI Equivalent |
| :--- | :--- | :--- | :--- |
| **`TargetTrack`** *(Element)* | `dl_target_track_t` | `target_actor_id` (`uint64`), `rel_x`, `rel_y`, `rel_z` ($\text{m}$, sensor frame), `rel_vx`, `rel_vy` ($\text{m/s}$), `rel_yaw` ($\text{rad}$), `range` $r$ ($\text{m}$), `bearing` ($\text{rad}$), `ttc_lon` ($\text{s}$, `+INFINITY` when the gap is not closing), `road_id` (`char[64]`), `lane_id` (`int32`), `object_class` (`uint32`), `confidence` ($[0,1]$). | `osi3::DetectedMovingObject` / `osi3::MovingObject` |
| **`VisualSlice`** | `dl_visual_slice_t` | `ego_road_id` (`char[64]`), `ego_lane_id` (`int32`), `ego_s`, `ego_d` ($\text{m}$), `left_lane_free`, `right_lane_free` (`uint8`), `lead_ttc` ($\text{s}$, `+INFINITY` when there is no lead vehicle or the gap is not closing), `num_tracks` (`uint32`), `tracks[32]` (`dl_target_track_t`). | `osi3::SensorView` (Host + MovingObjects + LaneBoundary) |
| **`RadarSlice`** | `dl_radar_slice_t` | `has_primary_target` (`uint8`), `primary_range` ($\text{m}$), `primary_azimuth` ($\text{rad}$), `primary_rcs` ($\text{dBsm}$), `num_tracks` (`uint32`), `tracks[32]` (`dl_target_track_t`). | `osi3::RadarSensorView` / `osi3::DetectedMovingObject` |
| **`CameraSlice`** | `dl_camera_slice_t` | `obstacle_confidence` ($[0,1]$), `lane_line_confidence` ($[0,1]$), `d_lane_center_est` ($\text{m}$), `heading_error_est` ($\text{rad}$), `num_tracks` (`uint32`), `tracks[32]` (`dl_target_track_t`). | `osi3::CameraSensorView` / `osi3::DetectedLaneBoundary` |
| **`SurfaceSlice`** | `dl_surface_slice_t` | `mu_fl`, `mu_fr`, `mu_rl`, `mu_rr` (per-corner friction $\mu \in [0, 2]$), `mu_mean` (dimensionless), `road_grade` $\theta_{\text{road}}$ ($\text{rad}$), `road_bank` $\phi_{\text{road}}$ ($\text{rad}$), `elevation_z` ($\text{m}$). | No single OSI field. Derived from OpenDRIVE elevation and superelevation and the runtime friction field. |
| **`SensorBundle`** | `dl_sensor_bundle_t` | Composite struct containing one `VisualSlice`, one `RadarSlice`, one `CameraSlice`, and one `SurfaceSlice` for full-stack bridges. | Complete `osi3::SensorView` |

**Interpolation Classes:** Every `float64` field is `LINEAR` unless listed here. Integer, enum, flag, and `char[]` fields are `HOLD`.
* `ANGLE`: `rel_yaw`, `bearing`, `primary_azimuth`, `heading_error_est`.
* Road-relative `LINEAR` fields: `ego_s` depends on `ego_road_id`. `ego_d` depends on `ego_road_id` and `ego_lane_id`. `primary_range`, `primary_azimuth`, and `primary_rcs` depend on `has_primary_target` being `1` in both samples.
