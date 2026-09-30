---
title: Standard library
section: 17
version: 0.254
status: draft
normative: true
depends_on: [00-conformance.md, 02-conventions.md, 03-vehicle-parameters.md, 04-perception.md, 05-checkpoints.md, 06-lifecycle.md, 08-steady-state.md, 09-abi.md, 11-execution.md, 15-manifest.md, 16-static-semantics.md, 19-modules.md]
---

# 17. Standard Library

Every conforming runtime provides the names in this section. Builtins and constructors need no import. Sensors and components are imported from `std::sensors` (17.2), `std::intent` (17.3), `std::control` (17.4), and `std::physics` (17.5). Each component's signature in [§17.3](17-standard-library.md) to [§17.5](17-standard-library.md) is its manifest ([§15](15-manifest.md)). Sensors are not components and have no manifest, and their signatures are the [§17.2](17-standard-library.md) table. The behavior is normative: two conforming runtimes produce the same outputs from the same inputs, within the determinism scope of [§11](11-execution.md).

An input written without a name, such as the pipe input, is the port named `input` in the manifest. Common notation: $\Delta t = \Delta t_{\text{base}}$, $dt$ is the component's own period $k_{\text{div}} \cdot \Delta t_{\text{base}}$ ([§11](11-execution.md)), $g = 9.80665\text{ m/s}^2$, and $\rho_{\text{air}} = 1.225\text{ kg/m}^3$. `own` is the actor's `own_state` ([§9.1](09-abi.md)). $\sigma$ is the direction sign of the actor's current lane ([§2](02-conventions.md)).

## 17.1 Builtins and Constructors

| Name | Signature | Meaning |
| :--- | :--- | :--- |
| `load_xodr` | `(path: String) -> OpenDriveMap` | Loads an ASAM OpenDRIVE file. A relative path resolves by [§19.1](19-modules.md). |
| `spawn` | `(id: Int, spec: EntitySpec, road: String, lane: Int, s: Length, d: Length = 0m, v: Velocity = 0m/s) -> Actor` | Places the actor's reference origin at `(road, lane, s, d)`, moving in its lane's driving direction, with speed `v` ≥ 0 ([§2](02-conventions.md)). A negative `v` is a compile-time error. An unknown road or lane, or an `s` off the road, is a compile-time error. |
| `place` | `(id: Int, spec: EntitySpec, road: String, lane: Int, s: Length, d: Length = 0m) -> Actor` | Creates a static actor at rest at `(road, lane, s, d)`, facing its lane's driving direction, with the compile-time checks of `spawn`. A static actor has no sensors, priors, or components, and its state never changes ([§6.2](06-lifecycle.md)). Sensors see it, and it takes part in contact ([§11](11-execution.md)). |
| `RouteNodes` | `(nodes: [String]) -> RouteNodes` | At most 64 lane reference strings, each naming a lane of the map. More, or an unknown lane, is a compile-time error ([§2](02-conventions.md)). |
| `friction_zone` | `(road: String, s_start: Length, s_end: Length, mu: Scalar)` | Inside `environment`. Sets $\mu$ on every lane of `road` for $s_{\text{start}} \le s < s_{\text{end}}$. Where zones overlap, the later statement wins. |
| `default_friction` | `Scalar` | Inside `environment`. $\mu$ everywhere that no zone covers. The default is `1.0`. |
| `collision` | `(a: Actor, b: Actor) -> Bool`, where `b` may also be `any` ([§16.4](16-static-semantics.md)) | True if `a` and `b` have been in contact ([§11](11-execution.md)) on the current tick or an earlier one. `any` matches every other actor. |
| `select` | `(c: Bool, a: T, b: T) -> T` | `a` if `c`, else `b`. |
| `clamp` | `(x: T, lo: T, hi: T) -> T` | $\min(\max(x, lo), hi)$ for a quantity type `T`. |
| `IntentFrame::decelerate` | `(a_ref: Acceleration, route: RouteNodes, from: KinematicState) -> IntentFrame` | `lon_mode = ACCEL_TARGET` with `a_ref`, and the lateral and signal groups of `follow_route` with the same `route` and `from`. |
| `IntentFrame::follow_route` | `(route: RouteNodes, from: KinematicState, v_ref: Velocity) -> IntentFrame` | `lon_mode = VELOCITY_TARGET` with `v_ref`. `lat_mode = LANE_OFFSET` with `d_ref = 0`. The target lane is the first route node whose `road_id` equals `from.road_id`, or `from`'s own lane if no node matches. `turn_signal = OFF`. |

Both constructors set `stop_at_odometer` to `+INFINITY`.

The world friction field is $\mu(X, Y)$: the zone or default value at the lane that `world_to_frenet` returns for $(X, Y)$, called with the actor's yaw as `psi` and its current `road_id` as `hint_road_id`.

## 17.2 Sensors

Sensors are part of the runtime ([§0](00-conformance.md)). Every standard sensor is ideal. It has no noise, no occlusion, and no latency beyond its rate. Every sensor takes `rate: Frequency`, written as a single `FreqLit` token as in a `RateClause`, never as another expression, and `history: Int` ($N$), and it samples in Phase 1 at its scheduled ticks. A sensor call with slice type `S` has type `SliceBuffer<S, N>`, where `history` must be a constant from 1 to 64 ([§4.2](04-perception.md)).

**Mounts:** A sensor frame has the heading frame's axes ([§2](02-conventions.md)) and its origin at the mount point, given in heading-frame coordinates from the rear-axle origin. Roll and pitch never tilt it.

| Mount | Position $(x, y, z)$ |
| :--- | :--- |
| `FrontBumper` | $(L + o_f,\ 0,\ 0.5\text{ m})$ |
| `Windshield` | $(0.5 L,\ 0,\ 0.9 H_{\text{bbox}})$ |
| `Center` | $(0.5 L,\ 0,\ 0.5 H_{\text{bbox}})$ |

**Detection:** A target is every other actor. Its reference point is its footprint center on the ground. A target is detected if its reference point lies within `range` of the sensor origin and its bearing $\operatorname{atan2}(y, x)$ in the sensor frame lies within $\pm$`fov`/2. Track fields ([§4.3](04-perception.md)): `rel_x`, `rel_y`, and `rel_z` are the reference point in the sensor frame. `rel_vx` and `rel_vy` are the time derivatives of `rel_x` and `rel_y` in the sensor frame, which turns with the actor: the World velocity of the target's reference point minus the World velocity of the sensor origin, rotated into the sensor frame, minus $\dot{\psi}\,\hat{z} \times (x, y)$, so `rel_vx` gains $\dot{\psi}\, y$ and `rel_vy` loses $\dot{\psi}\, x$. Two actors that keep a constant gap on a curve therefore have zero relative velocity, and their `ttc_lon` is `+INFINITY`. Each point velocity follows by rigid-body kinematics from the committed `KinematicState`: $\vec{v}_P = \vec{v}_{\text{ra}} + \dot{\psi}\,\hat{z} \times \vec{r}_P$, with $\vec{r}_P$ the point's offset from the rear-axle origin. The sensor frame's yaw is the actor's yaw, as in the Mounts rule above. `rel_yaw` is the target's yaw minus the actor's yaw, wrapped. `range` is $\sqrt{x^2 + y^2 + z^2}$ and `bearing` is $\operatorname{atan2}(y, x)$. `ttc_lon` is $\max(0,\ x - L_{\text{bbox,target}}/2 - x_{\text{front}}) / (-v_x)$ if $x > 0$ and $v_x < 0$, else `+INFINITY`, where $x_{\text{front}} = L + o_f - x_{\text{mount}}$ is the ego's extent ahead of the mount, so the time runs to bumper contact. `road_id` and `lane_id` come from the target's committed map cache. `object_class` is the target's class ([§3](03-vehicle-parameters.md)), and `confidence` is `1.0`.

| Sensor | Parameters | Slice | Mount | Additional Fields |
| :--- | :--- | :--- | :--- | :--- |
| `HumanVisualSensor` | `fov: Angle`, `range: Length` | `VisualSlice` | `Windshield` | See below. |
| `SurroundVisualSensor` | `range: Length` | `VisualSlice` | `Center` | `fov` is $2\pi$. See below. |
| `MillimeterRadar` | `mount: Mount`, `fov: Angle`, `range: Length = 200m` | `RadarSlice` | `mount` | The primary target is the nearest of the slice's tracks, by `range` and then smaller `target_actor_id`, with $x > 0$ and $|y| \le W_{\text{bbox}}/2 + 0.5\text{ m}$ with the ego's $W_{\text{bbox}}$. `primary_target_id` is its `target_actor_id`, `primary_range` its `range`, and `primary_azimuth` its `bearing`. `primary_rcs` is $10\text{ dBsm}$ when a primary target exists, and 0 otherwise ([§4.3](04-perception.md)). |
| `MonoCamera` | `mount: Mount`, `fov: Angle`, `range: Length = 120m` | `CameraSlice` | `mount` | `obstacle_confidence` is 1 if a primary target, defined as for the radar, exists and 0 otherwise. `lane_line_confidence` is 1. `d_lane_center_est` is $\sigma \cdot$ `own.frenet_d`. `heading_error_est` is the actor's yaw minus the lane heading in its driving direction, wrapped. |
| `SurfaceContactSensor` | none | `SurfaceSlice` | none | `mu_fl` through `mu_rr` are $\mu$ at the four contact points: `fl` at $(L, +t/2)$, `fr` at $(L, -t/2)$, `rl` at $(0, +t/2)$, and `rr` at $(0, -t/2)$ in the heading frame, with $t$ the Tier 2 track width of that axle (`track_width_f` or `track_width_r`) if present, else $0.85\, W_{\text{bbox}}$. `mu_mean` is their mean. `road_grade`, `road_bank`, and `elevation_z` are map values at the rear-axle origin. |

**`VisualSlice` fields:** `ego_*` come from `own`. `lead_ttc` is the `ttc_lon` of the lead track, which is the track with the smallest positive `rel_x`, then the smaller `target_actor_id`, whose `road_id` and `lane_id` equal the actor's. It is `+INFINITY` if there is none. `left_lane_free` is 1 if the lane to the actor's left in its driving direction exists and has no track whose `road_id` and `lane_id` are that lane's and whose $|$`rel_x`$| \le 20\text{ m}$. That lane is `out_left_lane_id` of `query_lane_topology` at the actor's `(road_id, lane_id, s)` if $\sigma = +1$, and `out_right_lane_id` if $\sigma = -1$ ([§9.2](09-abi.md)). A neighbor whose direction sign differs from $\sigma$ counts as absent. `right_lane_free` works the same way on the other side.

## 17.3 Stage 1 Components

**`PincerHiveMind`:** Cardinality `OneToMany`. Tier 0. Input `vision: SliceBuffer<VisualSlice, 5>`. Output `IntentFrame`. Parameters `target_actor_id: i64`, `pinch_gap: f64 [m]`. Modes: it emits `VELOCITY_TARGET` and `LANE_OFFSET` only.

For group member $j = 0, \dots, M-1$, in `bind` order, it finds the track with `target_actor_id` in `vision[j].latest()`. Here `own` is member $j$'s `own_states[j]`. If there is none, it sets `v_ref` to `own.v_lon`. Otherwise it sets
$$o_j = \text{pinch\_gap} \cdot \left(j - \tfrac{M-1}{2}\right), \quad \Delta x_j = -x, \quad v_{\text{target}} = \text{own.v\_lon} + v_x, \quad v_{\text{ref}} = \max\!\left(0,\ v_{\text{target}} + 0.5\text{ s}^{-1} \cdot (o_j - \Delta x_j)\right)$$
where $x$ and $v_x$ are the track's `rel_x` and `rel_vx`. In both cases, `stop_at_odometer` is `+INFINITY`, laterally it holds the member's current lane with `LANE_OFFSET` on `(own.road_id, own.lane_id)` and `d_ref = 0`, and `turn_signal = OFF`.

## 17.4 Stage 2 Components

**Modes:** Each component lists the modes it implements, which are its manifest's `modes` ([§15](15-manifest.md)). Any other mode of a listed field returns `DL_STATUS_ERR_UNSUPPORTED_MODE` ([§5](05-checkpoints.md)), and a mode field that a component does not list accepts every mode ([§15](15-manifest.md)). Every output below states its groups in full, with each no-bound field `+INFINITY`.

All Stage 2 components are `OneToOne`.

**`PIDSpeedController`:** Tier 0. Input `IntentFrame`. Output `Lon<KinematicControlFrame>`. Parameters `kp: f64 [Hz]`, `ki: f64 [Hz^2]`, `kd: f64 [1]`. Modes `ACCEL_TARGET`, `VELOCITY_TARGET`.
* **State:** the integral $I$, the previous error $e_{\text{prev}}$, the previous output $a_{\text{prev}}$, and a flag `rebase`. Cold init and warm start set $a_{\text{prev}}$ to the latched `a_lon_cmd` and set `rebase`.
* `ACCEL_TARGET`: $a = $ `a_ref`. The step sets $a_{\text{prev}} = a$ and sets `rebase`. $I$ and $e_{\text{prev}}$ keep their values.
* `VELOCITY_TARGET`: $e = v_{\text{ref}} - \text{own.v\_lon}$. It ignores `stop_at_odometer`, in both modes. If `rebase` is set, the step first sets $e_{\text{prev}} = e$ and $I = (a_{\text{prev}} - k_p e)/k_i - e\, dt$, or $I = 0$ if $k_i = 0$, and clears `rebase`. Then $I \leftarrow I + e\, dt$, $a = k_p e + k_i I + k_d (e - e_{\text{prev}}) / dt$, $e_{\text{prev}} \leftarrow e$, and $a_{\text{prev}} \leftarrow a$. So the first velocity step after initialization or after `ACCEL_TARGET` continues from the previous output without a step when $k_i \ne 0$.
* Output `ACCEL` with `a_lon_cmd` $= a$.

**`JerkLimiter`:** Tier 0. Input and output `Lon<KinematicControlFrame>`. Parameter `max_jerk: f64 [m/s^3]` (above zero). Output $a_k = a_{k-1} + \operatorname{clamp}(a_{\text{in}} - a_{k-1}, \pm \text{max\_jerk} \cdot dt)$. Initialization sets $a_{k-1}$ to the latched `a_lon_cmd`, and each step then stores $a_k$ as the next $a_{k-1}$. Modes `ACCEL`. It ignores its input's `jerk_lon_cmd`. Output `ACCEL` with `a_lon_cmd` $= a_k$ and `jerk_lon_cmd` $=$ `+INFINITY`.

**`StanleyLat`:** Tier 0. Input `IntentFrame`. Output `Lat<KinematicControlFrame>`. Parameters `k: f64 [Hz]`, `sample_step: f64 [m]` (above zero), `k_soft: f64 [m/s] = 1.0` (above zero). Modes `LANE_OFFSET`, `POLYLINE_PATH`. The reference path is `path_points` for `POLYLINE_PATH`. For `LANE_OFFSET`, it is 64 points from `sample_lane_path` on the target lane at `d_offset = d_ref`, with `ds` $= \sigma_t \cdot$ `sample_step`, where $\sigma_t$ is the target lane's direction sign. Sampling starts at the start point of the Lane Target rule of [§5.1](05-checkpoints.md). The reference point is the rear-axle origin $(X, Y)$. Let $p = (x_p, y_p)$ be the path point nearest to it, with the smallest index winning ties, and let $\psi_p$ and $\kappa_p$ be its heading and curvature. Then $e = -\sin\psi_p\,(X - x_p) + \cos\psi_p\,(Y - y_p)$ is the lateral offset of the rear axle, positive to the path's left, and $\psi_e = \psi_p - \chi$, wrapped to $(-\pi, \pi]$, where $\chi = \psi + \operatorname{atan2}(\text{own.v\_lat}, \text{own.v\_lon})$ is the rear axle's course angle, with $\operatorname{atan2}(0, 0) = 0$. Then
$$\delta = \operatorname{clamp}\!\left(\arctan(L \kappa_p) + \psi_e + \arctan\!\left(\frac{-k\, e}{k_{\text{soft}} + |\text{own.v\_lon}|}\right),\ \pm\delta_{\max}\right)$$
Output `ANGLE` with `steer_angle_cmd` $= \delta$. On a path that the rear axle already follows, $e = 0$ and $\psi_e = 0$, so the output is $\arctan(L\kappa_p)$, which is $\delta_{\text{KS}}$ ([§8](08-steady-state.md)). It does not reproduce $\delta_{\text{ss}}$, so with Tier 1 or 2 physics, at cold init or after a promotion, the trim check reports `DL_STATUS_WARN_TRIM_MISMATCH` ([§6.2](06-lifecycle.md)) when $\delta_{\text{ss}}$ and $\delta_{\text{KS}}$ differ by more than its tolerance. A reference path with no points, or a failed `sample_lane_path` call, is `DL_STATUS_ERR_INVALID_ARG`.

**`SimpleDrivetrain`:** Tier 2. Input `ActuatorControlFrame`. Output `KinematicControlFrame`. No parameters. It implements `PEDALS`, the `ANGLE` wheel mode, and every gear mode. `TORQUE` returns `DL_STATUS_ERR_UNSUPPORTED_MODE`. With $v = $ `own.v_lon`:
* **Gear ratio $i$:** `DRIVE` with `manual_gear_index` $= 0$ uses the largest gear index $g$ with $(v / R_{\text{eff}})\, i_g\, i_{\text{fd}} \ge 157.08\text{ rad/s}$, or gear 1 if none qualifies. `DRIVE` with an index $n$ from 1 to `num_gears` uses gear $n$. Any other index makes the frame invalid by [§5.2](05-checkpoints.md), so it never reaches `SimpleDrivetrain`. `REVERSE` uses $-i_R$. `NEUTRAL` and `PARK` use no drive force.
* **Forces:** $F_{\text{drive}} = \text{throttle} \cdot T_{\text{drive,max}}\, i\, i_{\text{fd}} / R_{\text{eff}}$. $F_{\text{brake}} = \text{brake} \cdot T_{\text{brake,max}} / R_{\text{eff}}$, or $T_{\text{brake,max}} / R_{\text{eff}}$ in `PARK`. $F_{\text{res}} = \tfrac{1}{2}\rho_{\text{air}} C_d A_f v |v| + C_{rr}\, m\, g \operatorname{sgn}(v)$, with $\operatorname{sgn}(0) = 0$ here and in every `SimpleDrivetrain` formula.
* **Output:** $a = (F_{\text{drive}} - F_{\text{res}} - F_{\text{brake}} \operatorname{sgn}(v)) / m + (\text{own.v\_lat} + l_r\, \text{own.yaw\_rate}) \cdot \text{own.yaw\_rate}$, where the last term, the CG lateral velocity times the yaw rate, turns the net-force acceleration of the CG into $\dot{v}_{\text{lon}}$ ([§5.3](05-checkpoints.md)). If $|v| < 0.01\text{ m/s}$, the brake and rolling resistance instead oppose the drive force. With $F_{\text{hold}} = F_{\text{brake}} + C_{rr}\, m\, g$: if $|F_{\text{drive}}| > F_{\text{hold}}$, then $a = \operatorname{sgn}(F_{\text{drive}}) (|F_{\text{drive}}| - F_{\text{hold}}) / m$. Otherwise $a = -\operatorname{sgn}(v) \min(|v| / dt,\ (F_{\text{hold}} - |F_{\text{drive}}|) / m)$, so the actor comes to rest instead of creeping. Output `ACCEL` with `a_lon_cmd` $= a$, and `ANGLE` with `steer_angle_cmd` $= $ `steering_wheel_norm` $\cdot\, \delta_{\max}$.

**`BrakeOverrideArbiter`:** Tier 0. Inputs `primary: ActuatorControlFrame` and `secondary: Override<ActuatorControlFrame>`. Output `ActuatorControlFrame`. Each group, `PEDALS`, `WHEEL`, and `GEAR`, comes whole from `secondary` if its mode there is not `NONE`, and from `primary` otherwise.

## 17.5 Stage 3 Components

Every physics component is `OneToOne` and runs every tick ([§11](11-execution.md)). `KinematicBicycle` and `DynamicSingleTrack` are vehicle physics components, and `PointMassWalker` is an object physics component ([§3.2](03-vehicle-parameters.md)). Each step of the two vehicle components from $t$ to $t + \Delta t$ runs in this order:

1. Update the actuator states $\delta$ and $a$ from the command frame, as below.
2. Evaluate the derivatives at the state of tick $t$, using the updated $\delta$ and $a$.
3. Apply one explicit Euler step of length $\Delta t$ to every integrated state.
4. Clamp $v_{\text{lon}} \leftarrow \max(0, v_{\text{lon}})$. An init context with $v_{\text{lon}} < 0$ makes the enter call return `DL_STATUS_ERR_INVALID_ARG`, because the standard physics does not model reversing. If the new $v_{\text{lon}}$ is 0, also set $a \leftarrow \max(0, a)$, so a stopped actor reports no deceleration. The standard physics does not drive in reverse.
5. Set $Z$ to the map elevation at the new $(X, Y)$, and roll and pitch to 0. The standard physics is planar: neither component applies gravity along the grade or bank.
6. Report the new state. Reported fields that are derivatives (`yaw_rate` where it is not a state, `a_lon`, `a_lat`) are evaluated at the new state with the $\delta$ and $a$ of steps 1 and 4. `slip_angle_beta_cg` follows [§5.3](05-checkpoints.md), and the map cache is left to the runtime ([§11](11-execution.md)).

**Initialization:** On cold init or warm start, each component sets its internal state from `chassis_state` in its init context: the pose, $v_{\text{lon}}$, $\dot{\psi}$, $\delta$ from `front_wheel_angle`, $a$ from $\dot{v}_{\text{lon}} = $ `chassis_state.a_lon` $+ v_{\text{lat}} \dot{\psi}$ ([§5.3](05-checkpoints.md)), and, for `DynamicSingleTrack`, $v_y = v_{\text{lat}} + l_r \dot{\psi}$.

**Actuator dynamics (both):** Both components implement every `AccelMode` and `SteerMode`.
* **Steering:** Under `ANGLE`, $\delta \leftarrow \delta + \operatorname{clamp}(\delta_{\text{cmd}} - \delta, \pm \rho\, \Delta t)$, where $\rho = \min(\dot{\delta}_{\max},\ $ `steer_rate_cmd`$)$. Under `RATE`, $\delta \leftarrow \delta + \operatorname{clamp}(\dot{\delta}_{\text{cmd}}, \pm\dot{\delta}_{\max})\, \Delta t$. Then $|\delta| \le \delta_{\max}$.
* **Longitudinal:** Under `ACCEL`, $a$ moves toward $a_{\text{cmd}}$ by at most `jerk_lon_cmd` $\cdot\, \Delta t$, so it reaches $a_{\text{cmd}}$ at once when the bound is `+INFINITY`. Under `JERK`, $a \leftarrow a + j_{\text{cmd}}\, \Delta t$.

**`KinematicBicycle`:** Tier 0. Input `KinematicControlFrame`. Output `KinematicState`. With rear-axle speed $v$:
$$\dot{X} = v\cos\psi, \quad \dot{Y} = v\sin\psi, \quad \dot{\psi} = \frac{v}{L}\tan\delta, \quad \dot{v} = a$$
It reports $v_{\text{lat}} = 0$, `a_lon` $= a$, and `a_lat` $= v\dot{\psi}$. It ignores friction, grade, and bank.

**`DynamicSingleTrack`:** Tier 1. Inputs `KinematicControlFrame` (the pipe input) and `surface: SliceBuffer<SurfaceSlice, 1>`. Output `KinematicState`. The state is the pose, $v_x$ ($= v_{\text{lon}}$), the CG lateral velocity $v_y$, the yaw rate $r$, $\delta$, and $a$. From `surface.latest()`: $\mu_f$ and $\mu_r$ are the axle means of the corner values, $\bar{\mu}$ is `mu_mean`, and $F_{zf}$ and $F_{zr}$ are the static axle loads of [§6.2](06-lifecycle.md) at its grade and bank. For $v_x \ge 1\text{ m/s}$:
$$\alpha_f = \delta - \arctan\frac{v_y + l_f r}{v_x}, \quad \alpha_r = -\arctan\frac{v_y - l_r r}{v_x}, \quad F_{yi} = \operatorname{clamp}(C_{\alpha i}\, \alpha_i,\ \pm\mu_i \max(0, F_{zi}))$$
$$\dot{v}_y = \frac{F_{yf} + F_{yr}}{m} - v_x r, \quad \dot{r} = \frac{l_f F_{yf} - l_r F_{yr}}{I_{zz}}, \quad \dot{v}_x = \operatorname{clamp}(a,\ \pm \bar{\mu} g)$$
The front lateral force acts along the body $y$ axis. This small-angle model matches [§8](08-steady-state.md). Explicit Euler is stable only if $|1 + \lambda \Delta t| < 1$ for each eigenvalue $\lambda$ of the linearized lateral dynamics, that is $\Delta t < 2|\operatorname{Re}\lambda| / |\lambda|^2$. The bound is smallest at $v_x = 1\text{ m/s}$: about $15\text{ ms}$ for `Sedan_2026`. Scenario authors choose `timestep` accordingly. The rear-axle lateral velocity is $v_{\text{lat}} = v_y - l_r r$, and the pose moves with $\dot{X} = v_x\cos\psi - v_{\text{lat}}\sin\psi$, $\dot{Y} = v_x\sin\psi + v_{\text{lat}}\cos\psi$, $\dot{\psi} = r$. It reports `a_lon` $= \dot{v}_x - v_{\text{lat}}\, r$ and `a_lat` $= \dot{v}_{\text{lat}} + v_x r$. The regime follows $v_x$ at tick $t$: for $v_x < 1\text{ m/s}$, step 2 uses the `KinematicBicycle` equations with $\dot{v} = \operatorname{clamp}(a, \pm\bar{\mu} g)$, so the friction limit is the same in both regimes. After step 4, if $v_x$ at tick $t$ or the new $v_x$ is below $1\text{ m/s}$, the component sets $r = v_x \tan\delta / L$ and $v_y = l_r r$ from the new $v_x$ and $\delta$. It reports the `KinematicBicycle` outputs, with `a_lon` $= \dot{v}$, on any step where it made this reset, and the dynamic outputs otherwise. Crossing downward, the reported `a_lat` and yaw rate step once to their kinematic values. Crossing upward, the reset leaves both slip angles at 0, so the tire forces build up from 0 over the next few steps and the reported `a_lat` departs from the kinematic value for one or more steps.

**`PointMassWalker`:** Tier 0. Object physics component ([§3.2](03-vehicle-parameters.md)). Input `IntentFrame`. Output `KinematicState`. Parameters `sample_step: f64 [m] = 0.5` (above zero), `lookahead: f64 [m] = 2.0` (above zero), and `max_turn_rate: f64 [Hz] = 3.0` (above zero), the largest heading rate in rad/s. Modes `VELOCITY_TARGET`, `LANE_OFFSET`, `POLYLINE_PATH`. $v_{\max}$ and $a_{\max}$ are the object's limits. The walker faces its direction of travel. Its state is the position, the heading $\psi$, and the speed $v \ge 0$. The reference path, its nearest point $p$ with heading $\psi_p$, and the offset $e$ are those of `StanleyLat` ([§17.4](17-standard-library.md)) with this `sample_step`. Let $w(x)$ wrap $x$ to $(-\pi, \pi]$. Each step from $t$ to $t + \Delta t$:
1. The target speed is $v_t = \min(\text{v\_ref},\ v_{\max},\ \sqrt{2 a_{\max} \max(0,\ \text{stop\_at\_odometer} - \text{own.odometer\_m})})$, where the square root of `+INFINITY` is `+INFINITY`.
2. $v' = \max(0,\ v + \operatorname{clamp}(v_t - v, \pm a_{\max} \Delta t))$.
3. The desired heading is $\psi_d = \psi_p - \arctan(e / \text{lookahead})$, and $\psi' = w(\psi + \operatorname{clamp}(w(\psi_d - \psi), \pm \text{max\_turn\_rate}\, \Delta t))$.
4. $X' = X + v' \cos\psi'\, \Delta t$ and $Y' = Y + v' \sin\psi'\, \Delta t$. $Z$, roll, and pitch follow step 5 of the vehicle components.
5. It reports $v_{\text{lon}} = v'$, $v_{\text{lat}} = 0$, `yaw_rate` $= w(\psi' - \psi) / \Delta t$, `a_lon` $= (v' - v) / \Delta t$, `a_lat` $= v' \cdot$ `yaw_rate`, and `front_wheel_angle` and `slip_angle_beta_cg` equal to 0.

On cold init or warm start it sets $X$, $Y$, $\psi$, and $v$ from `chassis_state`. An init context with $v_{\text{lon}} < 0$ makes the enter call return `DL_STATUS_ERR_INVALID_ARG`.
