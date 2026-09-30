---
title: Checkpoint data contracts
section: 5
version: 0.224
status: draft
normative: true
depends_on: [02-conventions.md, 06-lifecycle.md, 09-abi.md, 10-composition.md, 11-execution.md, 14-diagnostics.md, 15-manifest.md, 17-standard-library.md]
---

# 5. Canonical Checkpoint Data Contracts

Every checkpoint frame carries `timestamp_ns` (`uint64`, simulation time in nanoseconds) and `actor_id` (`uint64`), which the runtime writes ([§9.1](09-abi.md)). For the three command frames, `timestamp_ns` is the tick that produced the frame. `KinematicState` has fixed fields, and physics fills every one except the header, the map cache, and `odometer_m`, which the runtime writes ([§9.1](09-abi.md)).

**Groups and Modes:** `IntentFrame`, `KinematicControlFrame`, and `ActuatorControlFrame` consist of the header and a fixed set of groups. Each group has a mode field that selects one variant, and the mode decides which of the group's fields apply. Every output states every group, so a frame has no optional fields and a consumer reads each frame on its own. A consumer never needs an earlier frame to interpret the current one.

| Frame | Group | Mode Field (DSL Type) | Modes | Fields |
| :--- | :--- | :--- | :--- | :--- |
| `IntentFrame` | `LON` | `lon_mode` (`LonMode`) | `ACCEL_TARGET`, `VELOCITY_TARGET`, `GAP_PROFILE`, `SPATIOTEMPORAL_TRAJECTORY` | `a_ref`, `v_ref`, `stop_at_odometer`, `gap_target_actor_id`, `time_gap_ref`, `distance_gap_min`, and, shared with `LAT`, `num_traj_points` and `trajectory` |
| | `LAT` | `lat_mode` (`LatMode`) | `LANE_OFFSET`, `POLYLINE_PATH`, `SPATIOTEMPORAL_TRAJECTORY` | `target_road_id`, `target_lane_id`, `d_ref`, `num_waypoints`, `path_points` |
| | `SIGNAL` | `turn_signal` (`TurnSignal`) | `OFF`, `LEFT`, `RIGHT`, `HAZARD` | none |
| `KinematicControlFrame` | `LON` | `accel_mode` (`AccelMode`) | `ACCEL`, `JERK` | `a_lon_cmd`, `jerk_lon_cmd` |
| | `LAT` | `steer_mode` (`SteerMode`) | `ANGLE`, `RATE` | `steer_angle_cmd`, `steer_rate_cmd` |
| `ActuatorControlFrame` | `PEDALS` | `pedal_mode` (`PedalMode`) | `PEDALS` | `throttle`, `brake` |
| | `WHEEL` | `wheel_mode` (`WheelMode`) | `ANGLE`, `TORQUE` | `steering_wheel_norm`, `steering_torque_nm` |
| | `GEAR` | `gear_mode` (`GearMode`) | `PARK`, `REVERSE`, `NEUTRAL`, `DRIVE` | `manual_gear_index` |

**Fields per Mode:** A field applies only under the modes listed here, and every other field of the frame is unused.
* `IntentFrame`: `a_ref` under `ACCEL_TARGET`. `v_ref` under `VELOCITY_TARGET` and `GAP_PROFILE`. `gap_target_actor_id`, `time_gap_ref`, and `distance_gap_min` under `GAP_PROFILE`. `stop_at_odometer` under `ACCEL_TARGET`, `VELOCITY_TARGET`, and `GAP_PROFILE`. `target_road_id`, `target_lane_id`, and `d_ref` under `LANE_OFFSET`. `num_waypoints` and `path_points` under `POLYLINE_PATH`. `num_traj_points` and `trajectory` under `SPATIOTEMPORAL_TRAJECTORY`.
* `KinematicControlFrame`: `a_lon_cmd` under `ACCEL`, `jerk_lon_cmd` under `ACCEL` and `JERK`, `steer_angle_cmd` under `ANGLE`, and `steer_rate_cmd` under `ANGLE` and `RATE`.
* `ActuatorControlFrame`: `throttle` and `brake` under `PEDALS`, `steering_wheel_norm` under `ANGLE`, `steering_torque_nm` under `TORQUE`, and `manual_gear_index` under `DRIVE`.

The listed modes are numbered from 1 in the order shown. The **baseline mode** of each mode field is the one that runtime-authored frames use ([§6.2](06-lifecycle.md)): `VELOCITY_TARGET` for `lon_mode`, `LANE_OFFSET` for `lat_mode`, `OFF` for `turn_signal`, `ACCEL` for `accel_mode`, `ANGLE` for `steer_mode` and `wheel_mode`, `PEDALS` for `pedal_mode`, and every mode of `gear_mode`. A frame that the runtime builds by the rules of Pass 1 step 5 uses only baseline modes, and the steering that the runtime writes after a tier change uses `ANGLE`. Every mode enum also has `NONE` ($0$), meaning no request. In `IntentFrame`, `SPATIOTEMPORAL_TRAJECTORY` couples the two motion groups: `num_traj_points` and `trajectory` then govern both, and the other fields of `LON` and `LAT` do not apply.

**Partial and Override Frames:** A `Lon<T>` frame ([§10.2](10-composition.md)) states the `LON` group and has every other group `NONE`. A `Lat<T>` frame states `LAT`, and for `IntentFrame` also `SIGNAL`, and has `LON` `NONE`. A stated group is never `NONE`, and neither uses `SPATIOTEMPORAL_TRAJECTORY`. An `Override<T>` frame ([§10.3](10-composition.md)) may have any group `NONE`. Every other frame has no `NONE` group.

**No-Bound Values:** `jerk_lon_cmd` under `ACCEL`, `steer_rate_cmd` under `ANGLE`, and `stop_at_odometer` bound other fields. The value `+INFINITY` means no bound.

**Frame Validity:** The validity rules of this section apply to every frame a component produces. The runtime checks them in output validation, in the order that [§14.2](14-diagnostics.md) gives, and reports a failure as `DL_STATUS_ERR_INVALID_ARG` of the producing call, so every consumer receives only valid frames. After the check, the runtime sets every field that the frame's modes do not use, and every array entry past its count, to zero, so the bytes that consumers receive are deterministic.

**Delivery:** The runtime delivers each producer's latest output, as validated, zeroed, and stamped, without further change, except for the steering replacement after a tier change and the conversion before a replacement's first step ([§6.2.4](06-lifecycle.md)). A `+` merged frame is formed as [§10.2](10-composition.md) describes. On a tick where a producer does not step ([§11](11-execution.md)), its consumers receive its last output again. Trajectory times and the stop target are absolute, so a frame read on a later tick needs no adjustment. A consumer can compare `timestamp_ns` with its own tick time to see how old a frame is.

## 5.1 Checkpoint 1: `IntentFrame`
Produced by Stage 1 (Intent) components.

| Field Group | Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- | :--- |
| **Header** | `actor_id` | `uint64` | — | Unique actor entity identifier. |
| | `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation time of the tick that produced the frame. |
| **Longitudinal** | `lon_mode` | `enum` | — | `NONE` ($0$), `ACCEL_TARGET` ($1$), `VELOCITY_TARGET` ($2$), `GAP_PROFILE` ($3$), or `SPATIOTEMPORAL_TRAJECTORY` ($4$). |
| | `a_ref` | `float64` | $\text{m/s}^2$ | Target rate of change $\dot{v}_{\text{lon}}$ of `v_lon` (`ACCEL_TARGET`), as for `a_lon_cmd` in [§5.2](05-checkpoints.md). |
| | `v_ref` | `float64` | $\text{m/s}$ | Target cruise speed (`VELOCITY_TARGET` or `GAP_PROFILE` ceiling). |
| | `stop_at_odometer` | `float64` | $\text{m}$ | Stop target: the actor's odometer reading at which it must be at rest, or `+INFINITY` for none. |
| | `gap_target_actor_id` | `uint64` | — | Perceived lead actor ID for `GAP_PROFILE`. |
| | `time_gap_ref` | `float64` | $\text{s}$ | Desired time headway $T_{\text{gap}}$ for `GAP_PROFILE`. |
| | `distance_gap_min` | `float64` | $\text{m}$ | Minimum standstill gap $s_0$ for `GAP_PROFILE`. |
| **Lateral** | `lat_mode` | `enum` | — | `NONE` ($0$), `LANE_OFFSET` ($1$), `POLYLINE_PATH` ($2$), or `SPATIOTEMPORAL_TRAJECTORY` ($3$). |
| | `target_road_id` | `char[64]` | — | Target OpenDRIVE road identifier. |
| | `target_lane_id` | `int32` | — | Signed OpenDRIVE lane index. |
| | `d_ref` | `float64` | $\text{m}$ | Target lateral offset from the `target_lane_id` centerline, with the sign convention of `d` in [§2](02-conventions.md): positive to the left of the reference line direction, whatever the lane's driving direction. |
| | `num_waypoints` | `uint32` | — | Number of valid entries in `path_points`. |
| | `path_points` | `Waypoint[64]` | $\text{m}, \text{rad}, \text{m}^{-1}$ | Array of $(X, Y, \psi_{\text{ref}}, \kappa_{\text{ref}})$ geometric path targets. |
| **Coupled Horizon** | `num_traj_points` | `uint32` | — | Number of valid entries in `trajectory`. |
| | `trajectory` | `TrajPoint[64]` | $\text{ns}, \text{m}, \text{rad}, \text{m/s}, \text{m/s}^2, \text{m}^{-1}$ | Time-indexed array $(t_k, X_k, Y_k, \psi_k, v_k, a_k, \kappa_k)$. |
| **Signal** | `turn_signal` | `enum` | — | `NONE` ($0$), `OFF` ($1$), `LEFT` ($2$), `RIGHT` ($3$), or `HAZARD` ($4$). |

**Valid `IntentFrame`:** An `IntentFrame` is valid if and only if every rule below holds, together with the Partial and Override rule above.
* Each mode field holds one of its listed values.
* `lon_mode` is `SPATIOTEMPORAL_TRAJECTORY` if and only if `lat_mode` is. Then `num_traj_points` is from 1 to 64, and the trajectory follows the Array Semantics below.
* With `LANE_OFFSET`, `target_road_id` names a road of the map and some lane section of it has a lane `target_lane_id`, so the lane ID is not 0. With `POLYLINE_PATH`, `num_waypoints` is from 2 to 64.
* With `GAP_PROFILE`, `gap_target_actor_id` is not 0. Where they apply, `v_ref`, `time_gap_ref`, and `distance_gap_min` are not negative.

**Array Semantics:** `path_points` holds `num_waypoints` entries and `trajectory` holds `num_traj_points` entries. Entries beyond the count are ignored. Both arrays are in the World frame and ordered along the direction of travel. Their curvatures are positive when the path turns left in that direction, each trajectory $v_k \ge 0$, and each $a_k$ is a $\dot{v}_{\text{lon}}$ like `a_ref`. Each `trajectory` time $t_k$ is an absolute simulation time in nanoseconds. The times are not negative and strictly increase. Points earlier than a consumer's tick are in the past, which is normal for a frame that a component forwards or that a consumer reads on a later tick.

**Stop Target:** The actor's odometer is `odometer_m` in its `KinematicState` ([§5.3](05-checkpoints.md)). A consumer's remaining stopping distance is `stop_at_odometer` $-$ `own.odometer_m`, and a value at or below zero means stop now. The target is absolute, so it stays correct on every tick that a consumer reads the frame.

**Measured Gap for `GAP_PROFILE`:** `IntentFrame` carries the gap target and the desired gap. It does not carry the measured gap. A Stage 2 component that tracks `GAP_PROFILE` must declare a `SliceBuffer` input port whose slice type contains `tracks[]`. It reads the measured gap $g$ from the `latest()` sample of its first declared such port, from the track whose `target_actor_id` equals `gap_target_actor_id`: $g$ is that track's `rel_x`, the distance along the sensor's $x$ axis from the mount point to the target's footprint center ([§17.2](17-standard-library.md)). `distance_gap_min` and `time_gap_ref` are targets for this same $g$, so they include the sensor's offset from the front bumper and half the target's length. If no such track exists, the component treats the gap target as absent and tracks `v_ref`.

**Unsupported Modes:** A component's manifest lists, for each mode field of its checkpoint inputs, the modes it implements ([§15](15-manifest.md)), and a field that it does not list accepts every mode. A component that receives a mode it does not implement returns `DL_STATUS_ERR_UNSUPPORTED_MODE` from `dl_do_step`, and the runtime stops the scenario. `NONE` is never checked.

## 5.2 Checkpoint 2: `ControlFrame` (Strict Two-Tier Typing)

### Tier A: `KinematicControlFrame`
| Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- |
| `actor_id` | `uint64` | — | Unique actor entity identifier. |
| `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation time of the tick that produced the frame. |
| `accel_mode` | `enum` | — | `NONE` ($0$), `ACCEL` ($1$), or `JERK` ($2$). |
| `a_lon_cmd` | `float64` | $\text{m/s}^2$ | Under `ACCEL`, the commanded rate of change $\dot{v}_{\text{lon}}$ of `v_lon` ([§5.3](05-checkpoints.md)). In a turn it differs from the reported `a_lon` of [§5.3](05-checkpoints.md) by $v_{\text{lat}} \dot{\psi}$. |
| `jerk_lon_cmd` | `float64` | $\text{m/s}^3$ | Under `ACCEL`, the maximum jerk used to reach `a_lon_cmd`, above zero, or `+INFINITY` for none. Under `JERK`, a jerk command: physics integrates it into its commanded $\dot{v}_{\text{lon}}$, which starts from the committed $\dot{v}_{\text{lon}} = a_{\text{lon}} + v_{\text{lat}}\dot{\psi}$ after each initialization ([§5.3](05-checkpoints.md)). Under `ACCEL`, the bound limits the change of that same quantity. |
| `steer_mode` | `enum` | — | `NONE` ($0$), `ANGLE` ($1$), or `RATE` ($2$). |
| `steer_angle_cmd` | `float64` | $\text{rad}$ | Under `ANGLE`, the front road-wheel steering angle target $\delta_{\text{cmd}}$, positive to the left. |
| `steer_rate_cmd` | `float64` | $\text{rad/s}$ | Under `ANGLE`, the maximum rate used to reach `steer_angle_cmd`, above zero, or `+INFINITY` for none. Under `RATE`, a rate command that physics integrates. |

A `KinematicControlFrame` is valid if and only if each mode field holds one of its listed values, and the bounds under `ACCEL` and `ANGLE` are above zero.

### Tier B: `ActuatorControlFrame`
| Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- |
| `actor_id` | `uint64` | — | Unique actor entity identifier. |
| `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation time of the tick that produced the frame. |
| `pedal_mode` | `enum` | — | `NONE` ($0$) or `PEDALS` ($1$). |
| `throttle` | `float64` | $[0.0, 1.0]$ | Normalized propulsion demand relative to `max_drive_torque` $T_{\text{drive,max}}$. |
| `brake` | `float64` | $[0.0, 1.0]$ | Normalized brake demand relative to `max_brake_torque` $T_{\text{brake,max}}$. |
| `wheel_mode` | `enum` | — | `NONE` ($0$), `ANGLE` ($1$), or `TORQUE` ($2$). |
| `steering_wheel_norm` | `float64` | $[-1.0, 1.0]$ | Under `ANGLE`, the steering wheel angle normalized against $(\delta_{\max} \cdot i_s)$, positive to the left. |
| `steering_torque_nm` | `float64` | $\text{N}\cdot\text{m}$ | Under `TORQUE`, the column steering torque. Positive torque turns the wheels left. |
| `gear_mode` | `enum` | — | `NONE` ($0$), `PARK` ($1$), `REVERSE` ($2$), `NEUTRAL` ($3$), or `DRIVE` ($4$). |
| `manual_gear_index` | `int8` | — | Explicit gear index ($1..$`num_gears`, or $0$ for automatic selection in `DRIVE`). |

An `ActuatorControlFrame` is valid if and only if each mode field holds one of its listed values, `throttle` and `brake` lie in $[0, 1]$ under `PEDALS`, `steering_wheel_norm` lies in $[-1, 1]$ under `ANGLE`, and under `DRIVE` `manual_gear_index` is from 0 to `num_gears` (so 0 without Tier 2).

## 5.3 Checkpoint 3: `KinematicState` & Reference-Point Continuity
Produced by Stage 3 (Physics) at the end of every simulation step $t + \Delta t$.

* **Resolution of Rear-Axle vs. CG Reference Point:** All pose and twist quantities (`pos_x`, `pos_y`, `pos_z`, `v_lon`, `v_lat`, `a_lon`, `a_lat`) in `KinematicState` are measured at the **rear-axle reference origin** $(x_{\text{ra}}, y_{\text{ra}}, z_{\text{ra}})$. Simultaneously, `slip_angle_beta_cg` stores the sideslip angle at the **Center of Gravity (CG)** $\beta_{\text{cg}}$.
* **Rigid-Body Transform Between Rear Axle and CG:** Given rear-axle velocities $(v_{\text{lon}}, v_{\text{lat}})$ and yaw rate $\dot{\psi}$, the velocity and sideslip at the CG are related by exact rigid-body kinematics:
  $$v_{x,\text{cg}} = v_{\text{lon}}, \qquad v_{y,\text{cg}} = v_{\text{lat}} + l_r \dot{\psi}, \qquad \beta_{\text{cg}} = \operatorname{atan2}\!\left(\operatorname{sgn}(v_{\text{lon}})\, v_{y,\text{cg}},\ |v_{\text{lon}}|\right)$$
  with $\operatorname{sgn}(0) = +1$ and $\beta_{\text{cg}} = 0$ when $v_{\text{lon}} = v_{y,\text{cg}} = 0$. $l_r$ is the Tier 1 value. If the actor's `vehicle_spec` has no Tier 1, the CG position is unknown and every producer reports $\beta_{\text{cg}} = 0$. This equals $\arctan(v_{y,\text{cg}} / v_{\text{lon}})$ whenever $v_{\text{lon}} \ne 0$, including reverse driving, and stays defined at a standstill.
  For a non-slipping `KinematicBicycle` (`KS`), rear-axle lateral velocity is genuinely $v_{\text{lat}} = 0$, while yaw rate is $\dot{\psi} = \frac{v_{\text{lon}}}{L}\tan\delta$ and, with Tier 1 populated, CG sideslip is $\beta_{\text{cg}} = \arctan\!\left(\frac{l_r}{L}\tan\delta\right) \ne 0$ for $v_{\text{lon}} \ne 0$. Reporting rear-axle $v_{\text{lat}} = 0$ alongside the true $\dot{\psi}$ and $\beta_{\text{cg}}$ is physically consistent. It does not by itself make a Tier 0 $\leftrightarrow$ Tier 1/2 swap continuous. [§6.2.4](06-lifecycle.md) defines which fields change during a swap and by how much.

| Field Group | Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- | :--- |
| **Header** | `actor_id` | `uint64` | — | Unique actor entity identifier. |
| | `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation time $t + \Delta t$. |
| **World Pose** | `pos_x`, `pos_y`, `pos_z` | `float64` | $\text{m}$ | $(X, Y, Z)$ position of the rear-axle origin in the World frame. |
| | `roll`, `pitch`, `yaw` | `float64` | $\text{rad}$ | $(\phi, \theta, \psi)$ intrinsic $Z\text{-}Y'\text{-}X''$ Euler angles. |
| **Rear-Axle Twist** | `v_lon` | `float64` | $\text{m/s}$ | Longitudinal velocity $v_{x,\text{ra}}$ of the rear-axle origin along the heading frame's $x$ axis ([§2](02-conventions.md)). |
| | `v_lat` | `float64` | $\text{m/s}$ | Lateral slip velocity $v_{y,\text{ra}}$ of the rear-axle origin along the heading frame's $y$ axis ($0$ for non-slip `KS`, $-l_r\dot{\psi} + v_{y,\text{cg}}$ for `ST`/`MB`). |
| | `yaw_rate` | `float64` | $\text{rad/s}$ | Yaw rate $\dot{\psi} = d\psi/dt$ of the yaw angle. |
| **Rear-Axle Accel** | `a_lon`, `a_lat` | `float64` | $\text{m/s}^2$ | Inertial acceleration of the rear-axle origin in heading-frame axes: $a_{\text{lon}} = \dot{v}_{\text{lon}} - v_{\text{lat}}\dot{\psi}$ and $a_{\text{lat}} = \dot{v}_{\text{lat}} + v_{\text{lon}}\dot{\psi}$. |
| **Chassis Angles** | `front_wheel_angle` | `float64` | $\text{rad}$ | Actual front road-wheel steer angle $\delta$ persisted across ticks. |
| | `slip_angle_beta_cg` | `float64` | $\text{rad}$ | Sideslip angle at the Center of Gravity $\beta_{\text{cg}}$. |
| **Map Cache** | `road_id` | `char[64]` | — | Current OpenDRIVE road ID cached by World. |
| | `lane_id` | `int32` | — | Current signed OpenDRIVE lane ID cached by World. |
| | `frenet_s`, `frenet_d` | `float64` | $\text{m}$ | Cached $(s, d)$ coordinates for $O(1)$ spatial queries. |
| **Odometer** | `odometer_m` | `float64` | $\text{m}$ | Horizontal distance travelled by the rear-axle origin since spawn: the sum of the horizontal distances between consecutive committed positions. The runtime writes it in Phase 4 ([§11](11-execution.md)), and 0 at spawn. It never decreases. |
