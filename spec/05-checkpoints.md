---
title: Checkpoint data contracts
section: 5
version: 0.53
status: draft
normative: true
depends_on: [02-conventions.md, 06-lifecycle.md, 10-composition.md, 15-manifest.md]
---

# 5. Canonical Checkpoint Data Contracts

Every checkpoint frame carries `timestamp_ns` (`uint64`, simulation time in nanoseconds) and `actor_id` (`uint64`). `IntentFrame`, `KinematicControlFrame`, and `ActuatorControlFrame` also carry a `valid_mask` bitmask, so a consumer can tell an asserted `0.0` from a field that the producer does not request. `KinematicState` has no `valid_mask` because physics fills every field.

**Field Groups:** Each `valid_mask` bit belongs to one field group. The `+` operator ([§10.2](10-composition.md)) uses these groups.

| Frame | `LON` Bits | `LAT` Bits | `COUPLED` Bits |
| :--- | :--- | :--- | :--- |
| `IntentFrame` | `0x01`, `0x04` | `0x02`, `0x10` | `0x08` |
| `KinematicControlFrame` | `0x01`, `0x02` | `0x04`, `0x08` | none |
| `ActuatorControlFrame` | `0x01`, `0x02`, `0x10` | `0x04`, `0x08` | none |

**Cleared Bits Downstream (Hold Rule):** A cleared bit means that the producer makes no new request for that field in this frame. Arbiters read the raw bits ([§10.3](10-composition.md)). Every other consumer uses the last value that it received with the bit set. Before it receives such a value, the consumer uses the value from the latched frame in its init context ([§6.2](06-lifecycle.md)). For example, if an intent component emits only a longitudinal deceleration, the downstream controller keeps tracking the last lateral target.

## 5.1 Checkpoint 1: `IntentFrame`
Produced by Stage 1 (Intent) components.

| Field Group | Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- | :--- |
| **Header** | `actor_id` | `uint64` | — | Unique actor entity identifier. |
| | `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation time when the intent frame was evaluated. |
| | `valid_mask` | `uint32` | bitmask | `0x01`: Lon active, `0x02`: Lat active, `0x04`: `s_stop` valid, `0x08`: `trajectory` valid, `0x10`: `turn_signal` active. |
| **Longitudinal** | `lon_mode` | `enum` | — | `ACCEL_TARGET` ($0$), `VELOCITY_TARGET` ($1$), or `GAP_PROFILE` ($2$). |
| | `a_ref` | `float64` | $\text{m/s}^2$ | Target longitudinal acceleration (`ACCEL_TARGET`). |
| | `v_ref` | `float64` | $\text{m/s}$ | Target cruise speed (`VELOCITY_TARGET` or `GAP_PROFILE` ceiling). |
| | `s_stop` | `float64` | $\text{m}$ | Target stopping distance ahead (valid if `valid_mask & 0x04`). |
| | `gap_target_actor_id` | `uint64` | — | Perceived lead actor ID for `GAP_PROFILE` ($0$ if none). |
| | `time_gap_ref` | `float64` | $\text{s}$ | Desired time headway $T_{\text{gap}}$ for `GAP_PROFILE`. |
| | `distance_gap_min` | `float64` | $\text{m}$ | Minimum standstill gap $s_0$ for `GAP_PROFILE`. |
| **Lateral** | `lat_mode` | `enum` | — | `LANE_OFFSET` ($0$), `POLYLINE_PATH` ($1$), or `SPATIOTEMPORAL_TRAJECTORY` ($2$). |
| | `target_road_id` | `char[64]` | — | Target OpenDRIVE road identifier. |
| | `target_lane_id` | `int32` | — | Signed OpenDRIVE lane index. |
| | `d_ref` | `float64` | $\text{m}$ | Target lateral offset from the `target_lane_id` centerline, with the sign convention of `d` in [§2](02-conventions.md): positive to the left of the reference line direction, whatever the lane's driving direction. |
| | `path_points` | `Waypoint[64]` | $\text{m}, \text{rad}, \text{m}^{-1}$ | Array of $(X, Y, \psi_{\text{ref}}, \kappa_{\text{ref}})$ geometric path targets. |
| **Coupled Horizon** | `trajectory` | `TrajPoint[64]` | $\text{s}, \text{m}, \text{m/s}$ | Time-indexed array $(t_k, X_k, Y_k, \psi_k, v_k, a_k, \kappa_k)$. |
| **Auxiliary** | `turn_signal` | `enum` | — | `NONE` ($0$), `LEFT` ($1$), `RIGHT` ($2$), `HAZARD` ($3$). |

**Bit Coverage:** Each `valid_mask` bit covers these fields. The hold rule applies to all fields that a bit covers, as one unit.

| Bit | Group | Fields |
| :--- | :--- | :--- |
| `0x01` | `LON` | `lon_mode`, `a_ref`, `v_ref`, `gap_target_actor_id`, `time_gap_ref`, `distance_gap_min` |
| `0x04` | `LON` | `s_stop` |
| `0x02` | `LAT` | `lat_mode`, `target_road_id`, `target_lane_id`, `d_ref`, `num_waypoints`, `path_points` |
| `0x10` | `LAT` | `turn_signal` |
| `0x08` | `COUPLED` | `num_traj_points`, `trajectory` |

**Trajectory Exclusivity:** If `0x08` is set, `trajectory` governs both longitudinal and lateral motion. Then `lat_mode` must be `SPATIOTEMPORAL_TRAJECTORY`, and `0x01` and `0x02` must be clear. If `0x08` is clear, `lat_mode` must not be `SPATIOTEMPORAL_TRAJECTORY`. Any other combination is invalid, and the consumer returns `DL_STATUS_ERR_INVALID_ARG`.

**Array Semantics:** `path_points` holds `num_waypoints` entries and `trajectory` holds `num_traj_points` entries, each at most 64. Entries beyond the count are ignored. A count above 64 is invalid. Both arrays are in the World frame and ordered along the direction of travel. Each `trajectory` time $t_k$ is in seconds after the frame's `timestamp_ns`, starts at $t_0 \ge 0$, and strictly increases.

**Stop Distance:** `s_stop` is the distance along the actor's intended path from its rear-axle origin to the point where the rear-axle origin must stop.

**Measured Gap for `GAP_PROFILE`:** `IntentFrame` carries the gap target and the desired gap. It does not carry the measured gap. A Stage 2 component that tracks `GAP_PROFILE` must declare a `SliceBuffer` input port whose slice type contains `tracks[]`. It reads the measured gap from the track whose `target_actor_id` equals `gap_target_actor_id`.

**Unsupported Modes:** A component's manifest lists the modes it implements ([§15](15-manifest.md)). If a Stage 2 component receives a `lon_mode` or `lat_mode` that it does not implement, `dl_do_step` returns `DL_STATUS_ERR_UNSUPPORTED_MODE`, and the runtime stops the scenario.

## 5.2 Checkpoint 2: `ControlFrame` (Strict Two-Tier Typing)

### Tier A: `KinematicControlFrame`
| Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- |
| `actor_id` | `uint64` | — | Unique actor entity identifier. |
| `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation timestamp. |
| `valid_mask` | `uint32` | bitmask | `0x01`: `a_lon_cmd` valid, `0x02`: `jerk_lon_cmd` valid, `0x04`: `steer_angle_cmd` valid, `0x08`: `steer_rate_cmd` valid. |
| `a_lon_cmd` | `float64` | $\text{m/s}^2$ | Commanded longitudinal acceleration at rear-axle origin in body $+x$. |
| `jerk_lon_cmd` | `float64` | $\text{m/s}^3$ | If `0x01` is also set, the maximum jerk used to reach `a_lon_cmd`. If only `0x02` is set, a jerk command that physics integrates. |
| `steer_angle_cmd` | `float64` | $\text{rad}$ | Front road-wheel steering angle target $\delta_{\text{cmd}}$ (valid if `0x04` set). |
| `steer_rate_cmd` | `float64` | $\text{rad/s}$ | If `0x04` is also set, the maximum rate used to reach `steer_angle_cmd`. If only `0x08` is set, a rate command that physics integrates. |

### Tier B: `ActuatorControlFrame`
| Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- |
| `actor_id` | `uint64` | — | Unique actor entity identifier. |
| `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation timestamp. |
| `valid_mask` | `uint32` | bitmask | `0x01`: `throttle` active, `0x02`: `brake` active, `0x04`: `steering_wheel_norm` active, `0x08`: `steering_torque_nm` active, `0x10`: `gear_mode` active. |
| `throttle` | `float64` | $[0.0, 1.0]$ | Normalized propulsion demand relative to `max_drive_torque` $T_{\text{drive,max}}$. |
| `brake` | `float64` | $[0.0, 1.0]$ | Normalized brake demand relative to `max_brake_torque` $T_{\text{brake,max}}$. |
| `steering_wheel_norm` | `float64` | $[-1.0, 1.0]$ | Steering wheel angle normalized against $(\delta_{\max} \cdot i_s)$. |
| `steering_torque_nm` | `float64` | $\text{N}\cdot\text{m}$ | Optional column steering torque (used when `valid_mask & 0x08` is set). Setting both `0x04` and `0x08` is invalid. The consumer returns `DL_STATUS_ERR_INVALID_ARG`. |
| `gear_mode` | `enum` | — | `PARK` ($0$), `REVERSE` ($1$), `NEUTRAL` ($2$), `DRIVE` ($3$). |
| `manual_gear_index` | `int8` | — | Explicit gear index ($1..$`num_gears`, or $0$ for automatic selection in `DRIVE`). Bit `0x10` covers both `gear_mode` and `manual_gear_index`. |

## 5.3 Checkpoint 3: `KinematicState` & Reference-Point Continuity
Produced by Stage 3 (Physical Compute) at the end of every simulation step $t + \Delta t$.

* **Resolution of Rear-Axle vs. CG Reference Point:** All pose and twist quantities (`position`, `v_lon`, `v_lat`, `a_lon`, `a_lat`) in `KinematicState` are measured at the **rear-axle reference origin** $(x_{\text{ra}}, y_{\text{ra}}, z_{\text{ra}})$. Simultaneously, `slip_angle_beta_cg` stores the sideslip angle at the **Center of Gravity (CG)** $\beta_{\text{cg}}$.
* **Rigid-Body Transform Between Rear Axle and CG:** Given rear-axle velocities $(v_{\text{lon}}, v_{\text{lat}})$ and yaw rate $\dot{\psi}$, the velocity and sideslip at the CG are related by exact rigid-body kinematics:
  $$v_{x,\text{cg}} = v_{\text{lon}}, \qquad v_{y,\text{cg}} = v_{\text{lat}} + l_r \dot{\psi}, \qquad \beta_{\text{cg}} = \operatorname{atan2}\!\left(\operatorname{sgn}(v_{\text{lon}})\, v_{y,\text{cg}},\ |v_{\text{lon}}|\right)$$
  with $\operatorname{sgn}(0) = +1$ and $\beta_{\text{cg}} = 0$ when $v_{\text{lon}} = v_{y,\text{cg}} = 0$. This equals $\arctan(v_{y,\text{cg}} / v_{\text{lon}})$ whenever $v_{\text{lon}} \ne 0$, including reverse driving, and stays defined at a standstill.
  For a non-slipping `KinematicBicycle` (`KS`), rear-axle lateral velocity is genuinely $v_{\text{lat}} = 0$, while yaw rate is $\dot{\psi} = \frac{v_{\text{lon}}}{L}\tan\delta$ and CG sideslip is $\beta_{\text{cg}} = \arctan\!\left(\frac{l_r}{L}\tan\delta\right) \ne 0$ for $v_{\text{lon}} \ne 0$. Reporting rear-axle $v_{\text{lat}} = 0$ alongside the true $\dot{\psi}$ and $\beta_{\text{cg}}$ is physically consistent. It does not by itself make a Tier 0 $\leftrightarrow$ Tier 1/2 swap continuous. [§6.2.4](06-lifecycle.md) defines which fields change during a swap and by how much.

| Field Group | Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- | :--- |
| **Header** | `actor_id` | `uint64` | — | Unique actor entity identifier. |
| | `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation time $t + \Delta t$. |
| **World Pose** | `position` | `Vec3` | $\text{m}$ | $(X, Y, Z)$ position of rear-axle center in World Frame. |
| | `orientation` | `Vec3` | $\text{rad}$ | $(\text{roll } \phi, \text{pitch } \theta, \text{yaw } \psi)$ intrinsic $Z\text{-}Y'\text{-}X''$ Euler angles. |
| **Rear-Axle Twist** | `v_lon` | `float64` | $\text{m/s}$ | Longitudinal velocity $v_{x,\text{ra}}$ at rear-axle origin in Body Frame. |
| | `v_lat` | `float64` | $\text{m/s}$ | Lateral slip velocity $v_{y,\text{ra}}$ at rear-axle origin ($0$ for non-slip `KS`, $-l_r\dot{\psi} + v_{y,\text{cg}}$ for `ST`/`MB`). |
| | `yaw_rate` | `float64` | $\text{rad/s}$ | Yaw angular velocity $\dot{\psi}$ about vehicle $+z$ axis. |
| **Rear-Axle Accel** | `a_lon`, `a_lat` | `float64` | $\text{m/s}^2$ | Achieved accelerations $(a_{x,\text{ra}}, a_{y,\text{ra}})$ at rear-axle origin. |
| **Chassis Angles** | `front_wheel_angle` | `float64` | $\text{rad}$ | Actual front road-wheel steer angle $\delta$ persisted across ticks. |
| | `slip_angle_beta_cg` | `float64` | $\text{rad}$ | Sideslip angle at the Center of Gravity $\beta_{\text{cg}}$. |
| **Map Cache** | `road_id` | `char[64]` | — | Current OpenDRIVE road ID cached by World. |
| | `lane_id` | `int32` | — | Current signed OpenDRIVE lane ID cached by World. |
| | `frenet_s`, `frenet_d` | `float64` | $\text{m}$ | Cached $(s, d)$ coordinates for $O(1)$ spatial queries. |
