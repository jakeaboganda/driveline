---
title: Checkpoint data contracts
section: 5
version: 0.191
status: draft
normative: true
depends_on: [02-conventions.md, 06-lifecycle.md, 07-fmu-packaging.md, 09-abi.md, 10-composition.md, 11-execution.md, 14-diagnostics.md, 15-manifest.md, 17-standard-library.md]
---

# 5. Canonical Checkpoint Data Contracts

Every checkpoint frame carries `timestamp_ns` (`uint64`, simulation time in nanoseconds) and `actor_id` (`uint64`). `IntentFrame`, `KinematicControlFrame`, and `ActuatorControlFrame` also carry a `valid_mask` bitmask, so a consumer can tell an asserted `0.0` from a field that the producer does not request. `KinematicState` has no `valid_mask` because physics fills every field except the header and the map cache, which the runtime writes ([§9.1](09-abi.md)).

**Field Groups:** Each `valid_mask` bit belongs to one field group. The `+` operator ([§10.2](10-composition.md)) uses these groups.

| Frame | `LON` Bits | `LAT` Bits | `COUPLED` Bits |
| :--- | :--- | :--- | :--- |
| `IntentFrame` | `0x01`, `0x04` | `0x02`, `0x10` | `0x08` |
| `KinematicControlFrame` | `0x01`, `0x02` | `0x04`, `0x08` | none |
| `ActuatorControlFrame` | `0x01`, `0x02`, `0x10` | `0x04`, `0x08` | none |

**Hold Units:** Bits are held or replaced together in hold units:

| Frame | Hold Units |
| :--- | :--- |
| `IntentFrame` | `LON` $\{$`0x01`, `0x04`$\}$, `LAT` $\{$`0x02`$\}$, `COUPLED` $\{$`0x08`$\}$, `AUX` $\{$`0x10`$\}$ |
| `KinematicControlFrame` | `LON` $\{$`0x01`, `0x02`$\}$, `LAT` $\{$`0x04`, `0x08`$\}$ |
| `ActuatorControlFrame` | `PEDALS` $\{$`0x01`, `0x02`$\}$, `STEER` $\{$`0x04`, `0x08`$\}$, `GEAR` $\{$`0x10`$\}$ |

**Hold Rule (applied by the runtime):** A frame asserts a unit if it sets any bit of that unit. Before the runtime delivers a frame to a consumer that is not an Arbiter, it fills the frame unit by unit. For a unit that the frame asserts, the unit's bits and fields come from the frame, and a clear bit inside that unit stays clear. The runtime keeps a stored value of each hold unit for each connection and actor. A frame that asserts a unit replaces its stored value with the frame's bits and fields for that unit. For a unit that the frame does not assert, the filled frame takes the stored value. Only a new output of a producer step updates the stored values. On ticks where the producer holds its output ([§11](11-execution.md)), the consumer receives the frame as filled at that output's first delivery. A connection is the edge into one consumer input port for one actor. A splice keeps a connection, with its stored values, when the replacement's component takes the place of the old one on that edge: the edge into a replaced physics component, or into the pipe input of a replaced chain. Every other edge of a replacement chain is a new connection. A held unit keeps its fields, with two exceptions that keep them relative to the filled frame. In a held `COUPLED` unit stored from a frame stamped $t_0$, the runtime subtracts the binary64 value nearest to $(t - t_0)/10^9$, with the nanosecond difference taken first, from each `trajectory` time, where $t$ is the filled frame's `timestamp_ns`, so early points may be negative. A held `LON` unit drops `0x04` and sets `s_stop` to 0, because the runtime cannot move a distance measured from an old pose. When the connection is created, each stored value starts as that unit of the latched frame of the consumer's init context ([§6.2](06-lifecycle.md)), stamped with that frame's `timestamp_ns`. In `IntentFrame`, a frame that asserts the `COUPLED` hold unit clears the stored `LON` and `LAT` values, and a frame that asserts `LON` or `LAT` clears the stored `COUPLED` value, before the frame is filled. The cleared values stay clear until a later frame asserts those units. `AUX` never clears another unit and is never cleared, so a turn-signal-only frame keeps a held trajectory. Hold units, not the field groups above, decide assertion and clearing. A cleared value has its bits clear and its fields zero, so a filled frame never combines `COUPLED` with `LON` or `LAT` (see Valid Masks below). A turn-signal-only frame after a trajectory therefore fills to `0x18`. Arbiters receive raw frames ([§10.3](10-composition.md)). Consumers read a field whose bit is clear after filling as not requested. A component that needs a hold unit that is still clear after filling returns `DL_STATUS_ERR_UNSUPPORTED_MODE`. A manifest cannot declare needed units, so an FMU that needs one fails through its FMI status as `DL_STATUS_ERR_FMU` ([§7.1](07-fmu-packaging.md)). [§17](17-standard-library.md) names the units that each standard component needs. For example, if an intent component emits only a longitudinal deceleration, the controller receives the last lateral target with it, unless a trajectory frame has cleared it.

## 5.1 Checkpoint 1: `IntentFrame`
Produced by Stage 1 (Intent) components.

| Field Group | Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- | :--- |
| **Header** | `actor_id` | `uint64` | — | Unique actor entity identifier. |
| | `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation time when the intent frame was evaluated. |
| | `valid_mask` | `uint32` | bitmask | `0x01`: Lon active, `0x02`: Lat active, `0x04`: `s_stop` valid, `0x08`: `trajectory` valid, `0x10`: `turn_signal` active. |
| **Longitudinal** | `lon_mode` | `enum` | — | `ACCEL_TARGET` ($0$), `VELOCITY_TARGET` ($1$), or `GAP_PROFILE` ($2$). |
| | `a_ref` | `float64` | $\text{m/s}^2$ | Target rate of change $\dot{v}_{\text{lon}}$ of `v_lon` (`ACCEL_TARGET`), as for `a_lon_cmd` in [§5.2](05-checkpoints.md). |
| | `v_ref` | `float64` | $\text{m/s}$ | Target cruise speed (`VELOCITY_TARGET` or `GAP_PROFILE` ceiling). |
| | `s_stop` | `float64` | $\text{m}$ | Target stopping distance ahead (valid if `valid_mask & 0x04`). |
| | `gap_target_actor_id` | `uint64` | — | Perceived lead actor ID for `GAP_PROFILE` ($0$ if none). |
| | `time_gap_ref` | `float64` | $\text{s}$ | Desired time headway $T_{\text{gap}}$ for `GAP_PROFILE`. |
| | `distance_gap_min` | `float64` | $\text{m}$ | Minimum standstill gap $s_0$ for `GAP_PROFILE`. |
| **Lateral** | `lat_mode` | `enum` | — | `LANE_OFFSET` ($0$), `POLYLINE_PATH` ($1$), or `SPATIOTEMPORAL_TRAJECTORY` ($2$). |
| | `target_road_id` | `char[64]` | — | Target OpenDRIVE road identifier. |
| | `target_lane_id` | `int32` | — | Signed OpenDRIVE lane index. |
| | `d_ref` | `float64` | $\text{m}$ | Target lateral offset from the `target_lane_id` centerline, with the sign convention of `d` in [§2](02-conventions.md): positive to the left of the reference line direction, whatever the lane's driving direction. |
| | `num_waypoints` | `uint32` | — | Number of valid entries in `path_points`, at most 64. |
| | `path_points` | `Waypoint[64]` | $\text{m}, \text{rad}, \text{m}^{-1}$ | Array of $(X, Y, \psi_{\text{ref}}, \kappa_{\text{ref}})$ geometric path targets. |
| **Coupled Horizon** | `num_traj_points` | `uint32` | — | Number of valid entries in `trajectory`, at most 64. |
| | `trajectory` | `TrajPoint[64]` | $\text{s}, \text{m}, \text{m/s}$ | Time-indexed array $(t_k, X_k, Y_k, \psi_k, v_k, a_k, \kappa_k)$. |
| **Auxiliary** | `turn_signal` | `enum` | — | `NONE` ($0$), `LEFT` ($1$), `RIGHT` ($2$), `HAZARD` ($3$). |

**Bit Coverage:** Each `valid_mask` bit covers these fields. The hold rule moves a bit and its fields together.

| Bit | Group | Fields |
| :--- | :--- | :--- |
| `0x01` | `LON` | `lon_mode`, `a_ref`, `v_ref`, `gap_target_actor_id`, `time_gap_ref`, `distance_gap_min` |
| `0x04` | `LON` | `s_stop` |
| `0x02` | `LAT` | `lat_mode`, `target_road_id`, `target_lane_id`, `d_ref`, `num_waypoints`, `path_points` |
| `0x10` | `LAT` | `turn_signal` |
| `0x08` | `COUPLED` | `num_traj_points`, `trajectory` |

**Frame Validity:** The validity rules of this section apply to every frame a component produces. The runtime checks them in output validation ([§14.2](14-diagnostics.md)) and reports a failure as `DL_STATUS_ERR_INVALID_ARG` of the producing call, so every consumer, native, FMU, or Arbiter, receives only valid frames. The hold rule keeps them valid, because each filled unit comes from a valid frame and clearing keeps `COUPLED` apart from `LON` and `LAT`.

**Valid Masks:** An `IntentFrame` is valid if and only if every rule below holds.
* Bits outside `0x1F` are clear.
* Every enum field whose bit is set holds one of its listed values.
* `0x04` (`s_stop`) is set only together with `0x01`. It refines the longitudinal request.
* If `0x08` is set, `num_traj_points` is at least 1 and `trajectory` governs both longitudinal and lateral motion, and `0x01`, `0x02`, and `0x04` are clear. The frame requests `SPATIOTEMPORAL_TRAJECTORY` by this bit alone, and consumers ignore `lon_mode` and `lat_mode`.
* If `0x02` is set, `lat_mode` is not `SPATIOTEMPORAL_TRAJECTORY`.
* `0x10` (`turn_signal`) may accompany any combination.
* `num_waypoints` and `num_traj_points` are at most 64, and the `trajectory` times follow the Array Semantics below.

A component implements trajectories if its manifest's `lat_modes` lists `SPATIOTEMPORAL_TRAJECTORY` ([§15](15-manifest.md)).

**Array Semantics:** `path_points` holds `num_waypoints` entries and `trajectory` holds `num_traj_points` entries, each at most 64. Entries beyond the count are ignored. A count above 64 is invalid. Both arrays are in the World frame and ordered along the direction of travel. Their curvatures are positive when the path turns left in that direction, each trajectory $v_k \ge 0$, and each $a_k$ is a $\dot{v}_{\text{lon}}$ like `a_ref`. Each `trajectory` time $t_k$ is in seconds after the frame's `timestamp_ns`. In a produced frame the times start at $t_0 \ge 0$ and strictly increase. After the hold rule's shift they do not decrease.

**Stop Distance:** `s_stop` is the distance along the actor's intended path from its rear-axle origin to the point where the rear-axle origin must stop.

**Measured Gap for `GAP_PROFILE`:** `IntentFrame` carries the gap target and the desired gap. It does not carry the measured gap. A Stage 2 component that tracks `GAP_PROFILE` must declare a `SliceBuffer` input port whose slice type contains `tracks[]`. It reads the measured gap $g$ from the `latest()` sample of its first declared such port, from the track whose `target_actor_id` equals `gap_target_actor_id`: $g$ is that track's `rel_x`, the distance along the sensor's $x$ axis from the mount point to the target's footprint center ([§17.2](17-standard-library.md)). `distance_gap_min` and `time_gap_ref` are targets for this same $g$, so they include the sensor's offset from the front bumper and half the target's length. If no such track exists, the component treats the gap target as absent and tracks `v_ref`.

**Unsupported Modes:** A component's manifest lists the modes it implements ([§15](15-manifest.md)). The check covers only asserted units. `lon_mode` counts only when `0x01` is set, `lat_mode` only when `0x02` is set, and a set `0x08` counts as `SPATIOTEMPORAL_TRAJECTORY` for `lat_modes`. If a Stage 2 component receives a `lon_mode` or `lat_mode` that it does not implement, `dl_do_step` returns `DL_STATUS_ERR_UNSUPPORTED_MODE`, and the runtime stops the scenario.

## 5.2 Checkpoint 2: `ControlFrame` (Strict Two-Tier Typing)

### Tier A: `KinematicControlFrame`
| Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- |
| `actor_id` | `uint64` | — | Unique actor entity identifier. |
| `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation timestamp. |
| `valid_mask` | `uint32` | bitmask | `0x01`: `a_lon_cmd` valid, `0x02`: `jerk_lon_cmd` valid, `0x04`: `steer_angle_cmd` valid, `0x08`: `steer_rate_cmd` valid. A frame with bits outside `0x0F` is invalid. |
| `a_lon_cmd` | `float64` | $\text{m/s}^2$ | Commanded rate of change $\dot{v}_{\text{lon}}$ of `v_lon` ([§5.3](05-checkpoints.md)). In a turn it differs from the reported `a_lon` of [§5.3](05-checkpoints.md) by $v_{\text{lat}} \dot{\psi}$. |
| `jerk_lon_cmd` | `float64` | $\text{m/s}^3$ | If `0x01` is also set, the maximum jerk used to reach `a_lon_cmd`, which must be above zero, or the frame is invalid. If only `0x02` is set, a jerk command that physics integrates. |
| `steer_angle_cmd` | `float64` | $\text{rad}$ | Front road-wheel steering angle target $\delta_{\text{cmd}}$, positive to the left (valid if `0x04` set). |
| `steer_rate_cmd` | `float64` | $\text{rad/s}$ | If `0x04` is also set, the maximum rate used to reach `steer_angle_cmd`, which must be above zero, or the frame is invalid. If only `0x08` is set, a rate command that physics integrates. |

### Tier B: `ActuatorControlFrame`
| Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- |
| `actor_id` | `uint64` | — | Unique actor entity identifier. |
| `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation timestamp. |
| `valid_mask` | `uint32` | bitmask | `0x01`: `throttle` active, `0x02`: `brake` active, `0x04`: `steering_wheel_norm` active, `0x08`: `steering_torque_nm` active, `0x10`: `gear_mode` active. A frame with bits outside `0x1F` is invalid. |
| `throttle` | `float64` | $[0.0, 1.0]$ | Normalized propulsion demand relative to `max_drive_torque` $T_{\text{drive,max}}$. |
| `brake` | `float64` | $[0.0, 1.0]$ | Normalized brake demand relative to `max_brake_torque` $T_{\text{brake,max}}$. |
| `steering_wheel_norm` | `float64` | $[-1.0, 1.0]$ | Steering wheel angle normalized against $(\delta_{\max} \cdot i_s)$, positive to the left. |
| `steering_torque_nm` | `float64` | $\text{N}\cdot\text{m}$ | Optional column steering torque (used when `valid_mask & 0x08` is set). Positive torque turns the wheels left. Setting both `0x04` and `0x08` is invalid. |
| `gear_mode` | `enum` | — | `PARK` ($0$), `REVERSE` ($1$), `NEUTRAL` ($2$), `DRIVE` ($3$). |
| `manual_gear_index` | `int8` | — | Explicit gear index ($1..$`num_gears`, or $0$ for automatic selection in `DRIVE`). When `0x10` is set, it is $0$ outside `DRIVE` and at most `num_gears` in `DRIVE` (so $0$ without Tier 2), and any other value makes the frame invalid. Bit `0x10` covers both `gear_mode` and `manual_gear_index`. |

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
