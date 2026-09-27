# Driveline Scenario Description Language & Component Architecture
**Formal Specification — Draft v0.2 (Revised)**
* **File Extensions:** `.dline`, `.dl`
* **Binary Interface Baseline:** FMI 3.0 Co-Simulation Layered Extension (`driveline_abi.h`, ABI v0.2)

---

## 1. Scope, Architectural Principles, & Related Work

**Driveline** is a deterministic, component-first scenario description language and execution architecture for road-driving simulation[cite: 1]. It eliminates the kinematic ambiguity and simulator lock-in of existing scenario standards by separating ground-truth world state from per-actor behavioral, control, and physical compute pipelines[cite: 1].

### 1.1 Core Architectural Principles

1. **Three-Level World vs. Actor Separation:**
   * **Lexical Level:** A `.dline` scenario file serves as the top-level simulation manifest: it declares the physical world (`map`, `environment`, `static_object`), spawns actor entities with initial physical states, and binds each actor's initial component graph[cite: 1].
   * **Type Level:** World truth types (`OpenDriveMap`, `FrictionField`) cannot be passed as inputs to Stage 1 (Intent) or Stage 2 (Control) components[cite: 1].
   * **Runtime Memory Level:** Pipeline components execute in isolated memory contexts and cannot query global world state directly; they access external context exclusively through actor-mounted `SliceBuffer<T, N>` sensor ports and `priors`[cite: 1].
2. **Intra-Tick Acyclic Dataflow Chains (`>>`):** Within any single simulation tick $t$, an actor's motion pipeline is a strictly typed Directed Acyclic Graph (DAG) of signal transformers connected via the pipe operator (`>>`)[cite: 1]. Across ticks, the loop closes through the World ($X(t) \xrightarrow{\text{Phase 1}} \text{SensorSlice}(t) \xrightarrow{\text{Phase 2}} \text{IntentFrame}(t) \xrightarrow{\text{Phase 2}} \text{ControlFrame}(t) \xrightarrow{\text{Phase 3}} X(t + \Delta t)$), imposing a well-defined one-tick ($1 \cdot \Delta t_{\text{base}}$) sensing-to-actuation latency[cite: 1].
3. **Zero Implicit Control Glue:** The runtime prohibits hidden controller conversions (such as unparameterized speed-to-acceleration gains or implicit pedal maps) between mismatched components[cite: 1]. All cross-tier conversions must be declared as explicit, parameterized adapter blocks in the chain, while pure geometric map queries are provided via deterministic host callbacks[cite: 1].
4. **FMI 3.0 Layered Component Model & Cardinality Agnosticism:** Driveline standardizes port data contracts and lifecycle transitions rather than internal component implementations, allowing native DSL state trees, Behavior Trees, ONNX models, Simulink FMUs, or C++ binaries to be swapped freely[cite: 1]. Components support $1\text{:}1$ per-actor bindings, $1\text{:}N$ centralized coordination ("Hive Mind" intent), and $N\text{:}N$ vectorized batch execution[cite: 1].

### 1.2 Related Work & Standards Positioning

Driveline builds directly upon established automotive simulation standards while resolving their structural fragmentation[cite: 1]:

| Standard / Framework | Scope Covered | Limitation in Standalone Use | How Driveline Integrates or Extends It |
| :--- | :--- | :--- | :--- |
| **ASAM OpenSCENARIO (v1.x XML & v2.x DSL)** | High-level scenario orchestration, actor spawning, and composable behavioral modifiers[cite: 1]. | Delegates Stage 2 (Control) and Stage 3 (Physics) to black-box host simulators, causing divergent trajectories across tools[cite: 1]. | Replaces global puppet-master storyboards with actor-encapsulated `Intent >> Control >> Physics` pipelines and explicit control/physics contracts[cite: 1]. |
| **ASAM OSI (Open Simulation Interface)** | Standardized Protobuf schemas (`SensorView`, `SensorData`, `TrafficCommand`, `TrafficUpdate`) for sensor and traffic co-simulation[cite: 1]. | Defines wire payloads but notintra-actor control arbitration, bumpless pipeline hot-swapping, or a scenario authoring DSL[cite: 1]. | Adopts OSI-compatible spatial track semantics for `SensorSlice` ports while providing zero-copy C-ABI structs (`driveline_abi.h`) and optional OSI Protobuf serialization[cite: 1]. |
| **CommonRoad Vehicle Models (Althoff et al.)** | Standardized mathematical ODEs and parameter sets for Point-Mass (`PM`), Kinematic Single-Track (`KS`), Dynamic Single-Track (`ST`), and 29-DOF Multi-Body (`MB`) vehicles[cite: 1]. | Formulated for motion-planning benchmarks rather than multi-rate reactive co-simulation or FMI orchestration[cite: 1]. | Directly adopts the CommonRoad tiered vehicle parameterization (`KS` $\subset$ `ST` $\subset$ `MB`) as the normative foundation for `vehicle_spec` Tiers 0–2[cite: 1]. |
| **FMI 3.0 & ASAM SSP** | Binary packaging (`.fmu`), synchronous clocks, `fmi3Binary` ports, and static XML system topology (`SystemStructure.ssd`)[cite: 1]. | Road-blind and static; lacks OpenDRIVE Frenet queries, temporal ring buffers (`SliceBuffer`), and mid-scenario stateful hot-swapping (`splice`)[cite: 1]. | Formulated as a domain-specific **FMI 3.0 Layered Standard** that compiles dynamic driving pipelines down to FMI 3.0 Co-Simulation primitives[cite: 1]. |

---

## 2. Global Units & Coordinate Conventions

All compliant runtimes and components must enforce the following mathematical conventions at every port boundary[cite: 1]:

* **Strict SI Units:** Distance in meters ($\text{m}$), time in seconds ($\text{s}$) or integer nanoseconds ($\text{ns}$), mass in kilograms ($\text{kg}$), force in newtons ($\text{N}$), pressure in pascals ($\text{Pa}$), torque in newton-meters ($\text{N}\cdot\text{m}$), angles in radians ($\text{rad}$), angular velocity in radians per second ($\text{rad/s}$), velocity in meters per second ($\text{m/s}$), acceleration in meters per second squared ($\text{m/s}^2$), and jerk in meters per second cubed ($\text{m/s}^3$)[cite: 1]. Non-SI units in the DSL (such as `deg` or `Hz`) are syntactic sugar converted to SI (`rad`, $\text{s}^{-1}$) at compile time.
* **Inertial World Frame (ISO 8855):** Right-handed Cartesian coordinate system $(X, Y, Z)$ aligned with the OpenDRIVE inertial frame ($+X$ East, $+Y$ North, $+Z$ Up)[cite: 1].
* **Vehicle Body Frame & Euler Sequence (ISO 8855):** Orthogonal right-handed frame anchored to the vehicle with $+x$ longitudinal forward, $+y$ lateral left, and $+z$ vertical up[cite: 1]. World orientation $(\text{roll } \phi, \text{pitch } \theta, \text{yaw } \psi)$ follows the **ISO 8855 intrinsic $Z\text{-}Y'\text{-}X''$ (yaw $\psi \rightarrow$ pitch $\theta \rightarrow$ roll $\phi$) rotation sequence**. All angles are counter-clockwise positive and normalized to $(-\pi, \pi]$[cite: 1].
* **Actor Reference Origin:** Standardized at the **center of the rear axle projected onto the ground plane** $(x_{\text{ra}}, y_{\text{ra}}, z_{\text{ra}})$[cite: 1]. The Center of Gravity (CG) is located at longitudinal distance $l_r$ forward of the rear axle, $l_f$ behind the front axle, and height $h_{\text{cg}}$ above the ground plane[cite: 1].
* **OpenDRIVE Road & Lane Referencing `(road_id, lane_id, s, d)`:**
  * `road_id` (`char[64]`): Null-terminated OpenDRIVE `<road id="...">` identifier.
  * `lane_id` (`int32_t`): Signed OpenDRIVE lane index ($-1, -2, \dots$ right of reference line; $+1, +2, \dots$ left of reference line; $0$ is the road reference line).
  * `s` (`float64`, $\text{m}$): Arc-length measured along the **OpenDRIVE road reference line** (`lane_id = 0`) from the start of `road_id`.
  * `d` (`float64`, $\text{m}$): Orthogonal lateral offset measured from the **centerline of `lane_id`** (positive to the left in the reference line direction)[cite: 1].

---

## 3. Stratified Vehicle Parameter Specification (`vehicle_spec`)

Borrowing the hierarchical model structure of CommonRoad[cite: 1], Driveline defines a four-tier parameter specification attached to the actor entity. Higher tiers strictly require all lower numeric tiers (Tier 2 requires Tiers 0 and 1; Tier 1 requires Tier 0).

| Tier | C-ABI Struct | Target Fidelity Models | Mandatory Parameters & Invariants |
| :--- | :--- | :--- | :--- |
| **Tier 0** *(Mandatory Base)* | `dl_kinematic_params_t` | Point-Mass (`PM`), Kinematic Bicycle (`KS`), Path Trackers (`Stanley`, `PurePursuit`)[cite: 1] | `bbox_length` $L_{\text{bbox}}$, `bbox_width` $W_{\text{bbox}}$, `bbox_height` $H_{\text{bbox}}$, `wheelbase` $L$, `overhang_front` $o_f$, `overhang_rear` $o_r$, `max_steer_angle` $\delta_{\max}$, `max_steer_rate` $\dot{\delta}_{\max}$, `steering_ratio` $i_s$[cite: 1].<br>**Invariant:** $L_{\text{bbox}} == L + o_f + o_r$. |
| **Tier 1** *(Dynamic Single-Track)* | `dl_single_track_params_t` | Dynamic Single-Track (`ST`), Linear Tire Slip Models, Dynamic MPC[cite: 1] | Total `mass` $m$, `cg_dist_front` $l_f$, `cg_dist_rear` $l_r$, `cg_height` $h_{\text{cg}}$, yaw inertia `inertia_zz` $I_{zz}$, linear cornering stiffnesses `cornering_stiffness_f` $C_{\alpha f}$ and `cornering_stiffness_r` $C_{\alpha r}$, `aero_cd` $C_d$, `aero_area` $A_f$, `rolling_resistance_coeff` $C_{rr}$.<br>**Invariant:** $l_f + l_r == L$. |
| **Tier 2** *(Multi-Body & Powertrain)* | `dl_multibody_params_t` | 14-DOF / 29-DOF Multi-Body (`MB`), SimpleDrivetrain, Full Powertrain & Brake Hydraulics[cite: 1] | `sprung_mass` $m_s$, per-axle unsprung masses `unsprung_mass_f` $m_{uf}$ and `unsprung_mass_r` $m_{ur}$, roll/pitch/cross inertias $[I_{xx}, I_{yy}, I_{xz}]$, track widths $(t_f, t_r)$, per-wheel suspension stiffness $(K_{sf}, K_{sr})$ and damping $(C_{sf}, C_{sr})$, anti-roll stiffness $(K_{\text{arb},f}, K_{\text{arb},r})$, `tire_effective_radius` $R_{\text{eff}}$, `wheel_polar_inertia` $I_w$, `max_drive_torque` $T_{\text{drive,max}}$, `max_brake_torque` $T_{\text{brake,max}}$, `final_drive_ratio` $i_{\text{fd}}$, `gear_ratios[10]` $i_g$.<br>**Invariant:** $m_s + m_{uf} + m_{ur} == m$. |
| **Tier 3** *(External Solver Deck)* | `dl_custom_deck_t` | Pacejka Magic Formula `.tir`, IPG CarMaker, Adams/Car | `deck_type` (`NONE`, `PACEJKA_TIR`, `SOLVER_URI`, `INLINE_BLOB`), `precedence_mode` (`OVERRIDE_TIER1_2` or `SUPPLEMENT_ONLY`), and fixed buffer `uri_or_blob[256]`. |

### 3.1 Compile-Time Tier Verification & Single Source of Truth
1. **Compile-Time Tier Check:** Every physics and control component declares its minimum required `vehicle_spec` tier (`required_tier: 0 | 1 | 2`). Binding or splicing a component whose `required_tier` is not populated in the actor's `vehicle_spec` is a **compile-time error**.
2. **Control-to-Physics Tier Compatibility:**
   * A Tier 0 physics model (`KinematicBicycle`) accepts **only** Tier A `KinematicControlFrame`[cite: 1]. Wiring an `ActuatorControlFrame` into `KinematicBicycle` is rejected at compile time.
   * A Tier 1 physics model (`DynamicSingleTrack`) accepts `KinematicControlFrame` natively (using only Tier 0 + Tier 1 parameters), OR accepts `ActuatorControlFrame` when preceded by an explicit drivetrain adapter (`SimpleDrivetrain`, which requires Tier 2 powertrain parameters $T_{\text{drive,max}}, T_{\text{brake,max}}, R_{\text{eff}}$).
3. **No Divergent Geometry Overrides:** Physical geometry and mass parameters (`Tier 0`, `Tier 1`, `Tier 2`) belong exclusively to the actor's `vehicle_spec` and **cannot** be overridden inline on individual controller or physics blocks. This guarantees that World collision detection, warm-start trim, and all pipeline stages share a single immutable source of truth.

---

## 4. Actor Perception: Priors, Sensors, & `SliceBuffer<T, N>`

Pipeline components cannot access the global World state[cite: 1]. Actors perceive external reality solely through mounted **Priors** and **Sensors**[cite: 1]:

### 4.1 Priors (`priors`)
Static or slow-updating contextual memory mounted on the actor[cite: 1]:
* `RouteNodes`: Ordered array of `(road_id, lane_id)` topological targets representing navigation directions[cite: 1].

### 4.2 Timestamped Ring Buffers (`SliceBuffer<T, N>`)
Every mounted sensor has a compile-time capacity $N \in [1, 64]$ declared in its port signature `SliceBuffer<T, N>`[cite: 1]. A sensor with capacity $N_s$ can bind to any component input port expecting `SliceBuffer<T, N_c>` provided $N_s \ge N_c$. Each entry is a `Timestamped<T>` struct containing `{ float64 t; T data; }` (with field access sugar allowing `slice.field` as shorthand for `slice.data.field`)[cite: 1].

All `SliceBuffer<T, N>` ports enforce deterministic edge-case semantics across four query primitives:
1. `buffer.latest() -> Timestamped<T>`: Equivalent to `buffer[0]`. Guaranteed valid from $t = t_0$ because Phase 1 (Sensor Projection) executes before Phase 2 on Tick 0[cite: 1].
2. `buffer[k] / buffer.history(k) -> Timestamped<T>`:
   * **Compile-Time Bounds Check:** If $k$ is a compile-time constant and $k \ge N$, compilation fails.
   * **Early-Tick Underflow Rule ($k \ge \text{count}$):** Before $k+1$ samples have been recorded (e.g., on Tick 0 when $\text{count} == 1$), `buffer[k]` clamps to the oldest available sample `buffer[count - 1]` and sets `buffer.underflow = true`.
3. `buffer.rate_of(field_selector, window: k = 1) -> float64`: Safe finite-difference derivative helper:
   $$\text{rate\_of}(f, k) = \begin{cases} 0.0 & \text{if } \text{count} < 2 \text{ or } (s[0].t - s[\min(k, \text{count}-1)].t) \le 10^{-9}\text{ s} \\ \dfrac{s[0].f - s[m].f}{s[0].t - s[m].t} & \text{where } m = \min(k, \text{count}-1) \end{cases}$$
   This eliminates division-by-zero on Tick 0 when computing range-rate $\dot{r}$.
4. `buffer.at(t_query, mode: Interpolate | Floor) -> Timestamped<T>`:
   * **Clamping:** If $t_{\text{query}} \ge s[0].t$, returns $s[0]$. If $t_{\text{query}} \le s[\text{count}-1].t$, returns $s[\text{count}-1]$[cite: 1].
   * **`Floor` Mode:** Returns the newest sample $s[k]$ where $s[k].t \le t_{\text{query}}$[cite: 1].
   * **`Interpolate` Mode:** For bracket $s[k+1].t \le t_{\text{query}} < s[k].t$ with $\alpha = \frac{t_{\text{query}} - s[k+1].t}{s[k].t - s[k+1].t} \in [0, 1)$:
     * **Continuous `float64` fields** (`rel_x`, `rel_v_x`, `range`, `mu`): Linearly interpolated via $(1 - \alpha) v_{k+1} + \alpha v_k$ (angles use shortest-arc slerp on $(-\pi, \pi]$).
     * **Categorical / Discrete fields** (`actor_id`, `lane_id`, `object_class`): Held via Zero-Order Hold (`Floor` from $s[k+1]$).
     * **Target Track Arrays (`TargetTrack[32]`):** Matched across $s[k+1]$ and $s[k]$ by `target_actor_id`. Tracks present in both frames have their continuous fields interpolated; tracks present in only one frame use `Floor` ($s[k+1]$).

### 4.3 Normative Sensor Slice Schemas (and ASAM OSI Mapping)
Driveline defines four standard sensor slice payloads (packed in `driveline_abi.h` §7.2). Compliant runtimes may also populate these directly from **ASAM OSI** `osi3::SensorView` / `osi3::SensorData` messages[cite: 1]:

| Slice Type | C-ABI Struct | Fields & Semantics | ASAM OSI Equivalent |
| :--- | :--- | :--- | :--- |
| **`TargetTrack`** *(Element)* | `dl_target_track_t` | `target_actor_id` (`uint64`), `rel_x`, `rel_y`, `rel_z` ($\text{m}$, sensor frame), `rel_vx`, `rel_vy` ($\text{m/s}$), `rel_yaw` ($\text{rad}$), `range` $r$ ($\text{m}$), `bearing` ($\text{rad}$), `ttc_lon` ($\text{s}$), `road_id` (`char[64]`), `lane_id` (`int32`), `confidence` ($[0,1]$). | `osi3::DetectedMovingObject` / `osi3::MovingObject` |
| **`VisualSlice`** | `dl_visual_slice_t` | `ego_road_id` (`char[64]`), `ego_lane_id` (`int32`), `ego_s`, `ego_d` ($\text{m}$), `left_lane_free`, `right_lane_free` (`uint8`), `lead_ttc` ($\text{s}$), `num_tracks` (`uint32`), `tracks[32]` (`dl_target_track_t`). | `osi3::SensorView` (Host + MovingObjects + LaneBoundary) |
| **`RadarSlice`** | `dl_radar_slice_t` | `has_primary_target` (`uint8`), `primary_range` ($\text{m}$), `primary_azimuth` ($\text{rad}$), `primary_rcs` ($\text{dBsm}$), `num_tracks` (`uint32`), `tracks[32]` (`dl_target_track_t`). | `osi3::RadarSensorView` / `osi3::DetectedMovingObject` |
| **`CameraSlice`** | `dl_camera_slice_t` | `obstacle_confidence` ($[0,1]$), `lane_line_confidence` ($[0,1]$), `d_lane_center_est` ($\text{m}$), `heading_error_est` ($\text{rad}$), `num_tracks` (`uint32`), `tracks[32]` (`dl_target_track_t`). | `osi3::CameraSensorView` / `osi3::DetectedLaneBoundary` |
| **`SurfaceSlice`** | `dl_surface_slice_t` | `mu_fl`, `mu_fr`, `mu_rl`, `mu_rr` (per-corner friction $\mu \in [0, 2]$), `mu_mean` ($\text{m}$), `road_grade` $\theta_{\text{road}}$ ($\text{rad}$), `road_bank` $\phi_{\text{road}}$ ($\text{rad}$), `elevation_z` ($\text{m}$). | `osi3::HostVehicleData` surface / OpenDRIVE elevation & superelevation |
| **`SensorBundle`** | `dl_sensor_bundle_t` | Composite struct containing one `VisualSlice`, one `RadarSlice`, one `CameraSlice`, and one `SurfaceSlice` for full-stack bridges[cite: 1]. | Complete `osi3::SensorView` |

---

## 5. Canonical Checkpoint Data Contracts

Every canonical checkpoint frame includes a `timestamp_ns` (`uint64`, simulation time in nanoseconds), `actor_id` (`uint64`), and an explicit `valid_mask` / `active_request` bitmask so downstream components and arbiters can distinguish an active `0.0` command from an unasserted ("don't care") field.

### 5.1 Checkpoint 1: `IntentFrame`
Produced by Stage 1 (Intent) components[cite: 1].

| Field Group | Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- | :--- |
| **Header** | `actor_id` | `uint64` | — | Unique actor entity identifier[cite: 1]. |
| | `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation time when the intent frame was evaluated[cite: 1]. |
| | `valid_mask` | `uint32` | bitmask | `0x01`: Lon active, `0x02`: Lat active, `0x04`: `s_stop` valid, `0x08`: `trajectory` valid, `0x10`: `turn_signal` active. |
| **Longitudinal** | `lon_mode` | `enum` | — | `ACCEL_TARGET` ($0$), `VELOCITY_TARGET` ($1$), or `GAP_PROFILE` ($2$)[cite: 1]. |
| | `a_ref` | `float64` | $\text{m/s}^2$ | Target longitudinal acceleration (`ACCEL_TARGET`)[cite: 1]. |
| | `v_ref` | `float64` | $\text{m/s}$ | Target cruise speed (`VELOCITY_TARGET` or `GAP_PROFILE` ceiling)[cite: 1]. |
| | `s_stop` | `float64` | $\text{m}$ | Target stopping distance ahead (valid if `valid_mask & 0x04`)[cite: 1]. |
| | `gap_target_actor_id` | `uint64` | — | Perceived lead actor ID for `GAP_PROFILE` ($0$ if none). |
| | `time_gap_ref` | `float64` | $\text{s}$ | Desired time headway $T_{\text{gap}}$ for `GAP_PROFILE`. |
| | `distance_gap_min` | `float64` | $\text{m}$ | Minimum standstill gap $s_0$ for `GAP_PROFILE`. |
| **Lateral** | `lat_mode` | `enum` | — | `LANE_OFFSET` ($0$), `POLYLINE_PATH` ($1$), or `SPATIOTEMPORAL_TRAJECTORY` ($2$)[cite: 1]. |
| | `target_road_id` | `char[64]` | — | Target OpenDRIVE road identifier. |
| | `target_lane_id` | `int32` | — | Signed OpenDRIVE lane index[cite: 1]. |
| | `d_ref` | `float64` | $\text{m}$ | Target lateral offset from `target_lane_id` centerline[cite: 1]. |
| | `path_points` | `Waypoint[64]` | $\text{m}, \text{rad}, \text{m}^{-1}$ | Array of $(X, Y, \psi_{\text{ref}}, \kappa_{\text{ref}})$ geometric path targets[cite: 1]. |
| **Coupled Horizon** | `trajectory` | `TrajPoint[64]` | $\text{s}, \text{m}, \text{m/s}$ | Time-indexed array $(t_k, X_k, Y_k, \psi_k, v_k, a_k, \kappa_k)$[cite: 1]. |
| **Auxiliary** | `turn_signal` | `enum` | — | `NONE` ($0$), `LEFT` ($1$), `RIGHT` ($2$), `HAZARD` ($3$)[cite: 1]. |

### 5.2 Checkpoint 2: `ControlFrame` (Strict Two-Tier Typing)

#### Tier A: `KinematicControlFrame`
| Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- |
| `actor_id` | `uint64` | — | Unique actor entity identifier[cite: 1]. |
| `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation timestamp. |
| `valid_mask` | `uint32` | bitmask | `0x01`: `a_lon_cmd` valid, `0x02`: `jerk_lon_cmd` valid, `0x04`: `steer_angle_cmd` authoritative, `0x08`: `steer_rate_cmd` authoritative. |
| `a_lon_cmd` | `float64` | $\text{m/s}^2$ | Commanded longitudinal acceleration at rear-axle origin in body $+x$[cite: 1]. |
| `jerk_lon_cmd` | `float64` | $\text{m/s}^3$ | Optional longitudinal jerk limit/command (active if `valid_mask & 0x02`)[cite: 1]. |
| `steer_angle_cmd` | `float64` | $\text{rad}$ | Front road-wheel steering angle $\delta_{\text{cmd}}$ (authoritative if `0x04` set)[cite: 1]. |
| `steer_rate_cmd` | `float64` | $\text{rad/s}$ | Front road-wheel steering rate $\dot{\delta}_{\text{cmd}}$ (authoritative if `0x08` set)[cite: 1]. |

#### Tier B: `ActuatorControlFrame`
| Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- |
| `actor_id` | `uint64` | — | Unique actor entity identifier[cite: 1]. |
| `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation timestamp. |
| `valid_mask` | `uint32` | bitmask | `0x01`: `throttle` active, `0x02`: `brake` active, `0x04`: `steering_wheel_norm` active, `0x08`: `steering_torque_nm` active, `0x10`: `gear_mode` active. |
| `throttle` | `float64` | $[0.0, 1.0]$ | Normalized propulsion demand relative to `max_drive_torque` $T_{\text{drive,max}}$[cite: 1]. |
| `brake` | `float64` | $[0.0, 1.0]$ | Normalized brake demand relative to `max_brake_torque` $T_{\text{brake,max}}$[cite: 1]. |
| `steering_wheel_norm` | `float64` | $[-1.0, 1.0]$ | Steering wheel angle normalized against $(\delta_{\max} \cdot i_s)$[cite: 1]. |
| `steering_torque_nm` | `float64` | $\text{N}\cdot\text{m}$ | Optional column steering torque (used when `valid_mask & 0x08` is set). |
| `gear_mode` | `enum` | — | `PARK` ($0$), `REVERSE` ($1$), `NEUTRAL` ($2$), `DRIVE` ($3$)[cite: 1]. |
| `manual_gear_index` | `int8` | — | Explicit gear index ($1..10$, or $0$ for automatic selection in `DRIVE`). |

### 5.3 Checkpoint 3: `KinematicState` & Reference-Point Continuity
Produced by Stage 3 (Physical Compute) at the end of every simulation step $t + \Delta t$[cite: 1].

* **Resolution of Rear-Axle vs. CG Reference Point:** All pose and twist quantities (`position`, `v_lon`, `v_lat`, `a_lon`, `a_lat`) in `KinematicState` are measured at the **rear-axle reference origin** $(x_{\text{ra}}, y_{\text{ra}}, z_{\text{ra}})$[cite: 1]. Simultaneously, `slip_angle_beta_cg` stores the sideslip angle at the **Center of Gravity (CG)** $\beta_{\text{cg}}$.
* **Rigid-Body Transform Between Rear Axle and CG:** Given rear-axle velocities $(v_{\text{lon}}, v_{\text{lat}})$ and yaw rate $\dot{\psi}$, the velocity and sideslip at the CG are related by exact rigid-body kinematics:
  $$v_{x,\text{cg}} = v_{\text{lon}}, \qquad v_{y,\text{cg}} = v_{\text{lat}} + l_r \dot{\psi}, \qquad \beta_{\text{cg}} = \arctan\!\left(\frac{v_{\text{lat}} + l_r \dot{\psi}}{v_{\text{lon}}}\right)$$
  For a non-slipping `KinematicBicycle` (`KS`), rear-axle lateral velocity is genuinely $v_{\text{lat}} = 0$, while yaw rate is $\dot{\psi} = \frac{v_{\text{lon}}}{L}\tan\delta$ and CG sideslip is $\beta_{\text{cg}} = \arctan\!\left(\frac{l_r}{L}\tan\delta\right) \ne 0$. Reporting rear-axle $v_{\text{lat}} = 0$ alongside true $\dot{\psi}$ and $\beta_{\text{cg}}$ is physically consistent and prevents lateral jumps during Tier 0 $\leftrightarrow$ Tier 1/2 hot-swaps (§6.2.4).

| Field Group | Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- | :--- |
| **Header** | `actor_id` | `uint64` | — | Unique actor entity identifier[cite: 1]. |
| | `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation time $t + \Delta t$. |
| **World Pose** | `position` | `Vec3` | $\text{m}$ | $(X, Y, Z)$ position of rear-axle center in World Frame[cite: 1]. |
| | `orientation` | `Vec3` | $\text{rad}$ | $(\text{roll } \phi, \text{pitch } \theta, \text{yaw } \psi)$ intrinsic $Z\text{-}Y'\text{-}X''$ Euler angles[cite: 1]. |
| **Rear-Axle Twist** | `v_lon` | `float64` | $\text{m/s}$ | Longitudinal velocity $v_{x,\text{ra}}$ at rear-axle origin in Body Frame[cite: 1]. |
| | `v_lat` | `float64` | $\text{m/s}$ | Lateral slip velocity $v_{y,\text{ra}}$ at rear-axle origin ($0$ for non-slip `KS`, $-l_r\dot{\psi} + v_{y,\text{cg}}$ for `ST`/`MB`)[cite: 1]. |
| | `yaw_rate` | `float64` | $\text{rad/s}$ | Yaw angular velocity $\dot{\psi}$ about vehicle $+z$ axis[cite: 1]. |
| **Rear-Axle Accel** | `a_lon`, `a_lat` | `float64` | $\text{m/s}^2$ | Achieved accelerations $(a_{x,\text{ra}}, a_{y,\text{ra}})$ at rear-axle origin[cite: 1]. |
| **Chassis Angles** | `front_wheel_angle` | `float64` | $\text{rad}$ | Actual front road-wheel steer angle $\delta$ persisted across ticks[cite: 1]. |
| | `slip_angle_beta_cg` | `float64` | $\text{rad}$ | Sideslip angle at the Center of Gravity $\beta_{\text{cg}}$[cite: 1]. |
| **Map Cache** | `road_id` | `char[64]` | — | Current OpenDRIVE road ID cached by World. |
| | `lane_id` | `int32` | — | Current signed OpenDRIVE lane ID cached by World[cite: 1]. |
| | `frenet_s`, `frenet_d` | `float64` | $\text{m}$ | Cached $(s, d)$ coordinates for $O(1)$ spatial queries[cite: 1]. |

---

## 6. Driveline Component Model (DCM) & FMI 3.0 Layered Lifecycle

The **Driveline Component Model (DCM)** is formulated as an **FMI 3.0 Layered Standard** (`org.driveline.dcm`). Native Driveline components implement the extended lifecycle natively (`dl_*`), while legacy Mode B `.fmu` binaries are adapted by the runtime master using standard FMI 3.0 calls.

### 6.1 Component Lifecycle State Machine

```text
                  ┌──────────────────────┐
                  │   1. Uninstantiated  │
                  └──────────┬───────────┘
                             │ dl_instantiate(desc, callbacks, &inst)
                             ▼
                  ┌──────────────────────┐
                  │   2. Instantiated    │
                  └──────────┬───────────┘
                             │ dl_configure_structure(inst, &struct_cfg)
                             ▼
                  ┌──────────────────────┐
                  │ 3. StructuralConfig  │
                  └──────────┬───────────┘
        ┌────────────────────┴────────────────────┐
        │ At t = 0 (Coupled Trim Loop)            │ Spliced in at t > 0
        │ dl_enter_cold_init(inst, init_ctx[])    │ dl_enter_warm_start(inst, init_ctx[])
        ▼                                         ▼
┌──────────────────────┐                 ┌──────────────────────┐
│ 4a. ColdInitMode     │                 │ 4b. WarmStartMode    │
│  (Coupled Trim)      │                 │ (Bumpless Transfer)  │
└───────┬──────────────┘                 └────────┬─────────────┘
        └────────────────────┬────────────────────┘
                             │ dl_exit_init_mode(inst)
                             ▼
                  ┌──────────────────────┐
              ┌──►│     5. StepMode      │◄──┐
              │   └────┬────────────┬────┘   │
 dl_do_step() │        │            │        │ dl_on_membership_change(inst, delta_ctx)
   (Clocked)  └────────┘            └────────┘ (Actor Join / Leave on 1:N or N:N)
                             │
                             │ dl_terminate(inst) / dl_free_instance(inst)
                             ▼
                  ┌──────────────────────┐
                  │    6. Terminated     │
                  └──────────────────────┘
```

### 6.2 Detailed Lifecycle Transition Rules

1. **`Instantiated` (`dl_instantiate`):** Verifies `abi_version` and `struct_size` and injects the read-only host map callback table (`dl_host_map_callbacks_t`)[cite: 1].
2. **`StructuralConfig` (`dl_configure_structure`):** Maps to `fmi3EnterConfigurationMode`. Passes an array of per-port ring buffer capacities `port_history_depths[]` (allowing multi-input components like `BoschPCS_v4` to bind buffers of different depths, e.g., $N_0 = 8$ and $N_1 = 5$) and bound actor count $M$ (`max_actors`)[cite: 1].
3. **`ColdInitMode` (`dl_enter_cold_init` at $t = 0$) — Coupled Pipeline Trim Protocol:**
   To prevent a mismatch between the physics model's initial cornering equilibrium and the controller's Tick 0 command, Cold Initialization executes in **topological pipeline order** across all actors:
   * **Pass 1 (World & Sensor Seeding):** At $t = 0$, the host queries OpenDRIVE geometry at each actor's spawn `(road_id, lane_id, s_0, d_0)` for curvature $\kappa_0$, road grade $\theta_{\text{road}}$, and superelevation bank $\phi_{\text{road}}$. It computes gravity-and-bank-resolved static axle normal loads:
     $$F_{z,f} = m g \cos\theta_{\text{road}}\cos\phi_{\text{road}} \frac{l_r}{L} - m g \sin\theta_{\text{road}} \frac{h_{\text{cg}}}{L}, \qquad F_{z,r} = m g \cos\theta_{\text{road}}\cos\phi_{\text{road}} \frac{l_f}{L} + m g \sin\theta_{\text{road}} \frac{h_{\text{cg}}}{L}$$
     and nominal wheel speeds $\omega_{i,0} = v_0 / R_{\text{eff}}$ (using $R_{\text{eff}}$ from Tier 2 if present, or default $R_{\text{nom}} = 0.33\text{ m}$ for Tier 0/1). It then runs Phase 1 (Sensor Projection) once to populate `slice[0]` at $t = 0$.
   * **Pass 2 (Stage 1 $\rightarrow$ Stage 2 Cold Init):** Stage 1 (Intent) and Stage 2 (Control) components enter `dl_enter_cold_init` and evaluate their initial steady-state outputs (`latched_intent`, `latched_kinematic_ctrl`, `latched_actuator_ctrl`) at $t = 0$.
   * **Pass 3 (Stage 3 Physics Equilibrium Trim):** Stage 3 (Physics) receives `dl_init_context_t` containing both the road-derived quasi-static state $(\dot{\psi}_0 = v_0 \kappa_0, a_{\text{lat},0} = v_0^2 \kappa_0)$ **and** the controller's Pass 2 initial command, solving internal suspension deflections $z_{i,0}$ and tire slip states so that Tick 0 is free of control/physics transients.
4. **`WarmStartMode` (`dl_enter_warm_start` at $t > 0$) — Reference-Consistent Promotion & Demotion:**
   * **Tier 0 (`KS`) $\rightarrow$ Tier 1/2 (`ST` / `MB`) Promotion:** When promoting from a non-slip `KinematicBicycle` to `DynamicSingleTrack` or `MultiBody` in a curve ($\dot{\psi} \ne 0$), the runtime reconstructs the steady-state dynamic rear-axle lateral velocity from Tier 1 rear cornering stiffness $C_{\alpha r}$:
     $$\alpha_{r,\text{eq}} = \frac{m l_f}{(l_f + l_r) C_{\alpha r}} v_{\text{lon}} \dot{\psi}, \qquad v_{\text{lat,ra}} = -v_{\text{lon}} \tan(\alpha_{r,\text{eq}})$$
     so the incoming dynamic tire model begins at its exact steady-state lateral force equilibrium rather than experiencing a step-force spike from $v_{\text{lat,ra}} = 0$.
   * **Legacy Mode B FMU Fallback:** Because standard scalar-pin FMI 3.0 FMUs do not export `dl_enter_warm_start`, splicing a Mode B FMU at $t > 0$ follows a two-tier fallback: (a) if the FMU sets `canGetAndSetFMUState="true"` and provides a warm-start state setter, the master restores it; (b) otherwise, the master calls `fmi3EnterInitializationMode` at $t = t_{\text{splice}}$, seeds all input and tunable initial-condition pins from `dl_init_context_t`, and logs a compiler/runtime diagnostic `WARN_FMU_COLD_SPLICE`.
   * **Full-Stack Bridge (`SensorBundle -> KinematicState`):** Allowed exclusively as a static $t = 0$ actor binding (for replay actors or external HiL ego bridges)[cite: 1]. Splicing a `SensorBundle -> KinematicState` component mid-simulation is forbidden unless `allow_pose_override = true` is declared in the scenario.
5. **Membership Mutation (`dl_on_membership_change`):** Supports both **actor removal** (`REMOVED`) and **actor addition** (`ADDED`) on $1\text{:}N$ and $N\text{:}N$ components. When a new actor joins an active $1\text{:}N$ group at $t > 0$, `dl_membership_change_t` passes the new actor's full `dl_init_context_t` so the component can warm-start that actor's slot without disturbing existing members.

---

## 7. Normative C-ABI Header (`driveline_abi.h`)

All structs in `driveline_abi.h` are 8-byte aligned with zero implicit compiler padding, use fixed-width integer types, and contain **zero raw memory pointers** inside data frames or `dl_init_context_t`, ensuring identical binary layout across 32-bit/64-bit targets and out-of-process `fmi3Binary` pipes.

```c
#ifndef DRIVELINE_ABI_H
#define DRIVELINE_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 8)

#define DL_ABI_VERSION_0_2 0x00000200U

typedef enum {
    DL_STATUS_OK              = 0,
    DL_STATUS_WARN_UNDERFLOW  = 1,
    DL_STATUS_WARN_COLD_FMU   = 2,
    DL_STATUS_ERR_INVALID_ARG = -1,
    DL_STATUS_ERR_TIER_MISSING= -2,
    DL_STATUS_ERR_NUMERIC     = -3
} dl_status_t;

typedef void* dl_component_handle_t;

/* ==========================================================================
 * 1. STRATIFIED VEHICLE PARAMETER TIERS (Pointer-Free Inline Layout)
 * ========================================================================== */

typedef struct {
    double bbox_length, bbox_width, bbox_height; /* L_bbox, W_bbox, H_bbox [m] */
    double wheelbase;                            /* L = l_f + l_r [m] */
    double overhang_front, overhang_rear;        /* o_f, o_r [m] */
    double max_steer_angle;                      /* delta_max [rad] */
    double max_steer_rate;                       /* delta_dot_max [rad/s] */
    double steering_ratio;                       /* i_s [-] */
} dl_kinematic_params_t;

typedef struct {
    double mass;                                 /* m [kg] */
    double cg_dist_front, cg_dist_rear;          /* l_f, l_r [m] */
    double cg_height;                            /* h_cg [m] */
    double inertia_zz;                           /* I_zz [kg*m^2] */
    double cornering_stiffness_f;                /* C_alpha_f [N/rad] */
    double cornering_stiffness_r;                /* C_alpha_r [N/rad] */
    double aero_cd, aero_area;                   /* [-], [m^2] */
    double rolling_resistance_coeff;             /* C_rr [-] */
} dl_single_track_params_t;

typedef struct {
    double sprung_mass;                          /* m_s [kg] */
    double unsprung_mass_f, unsprung_mass_r;     /* Per-axle m_uf, m_ur [kg] */
    double inertia_xx, inertia_yy, inertia_xz;   /* [kg*m^2] (I_zz in Tier 1) */
    double track_width_f, track_width_r;         /* t_f, t_r [m] */
    double susp_stiffness_f, susp_stiffness_r;   /* Per-wheel K_sf, K_sr [N/m] */
    double susp_damping_f, susp_damping_r;       /* Per-wheel C_sf, C_sr [N*s/m] */
    double arb_stiffness_f, arb_stiffness_r;     /* [N*m/rad] */
    double tire_effective_radius;                /* R_eff [m] */
    double wheel_polar_inertia;                  /* I_w [kg*m^2] */
    double max_drive_torque, max_brake_torque;   /* T_drive_max, T_brake_max [N*m] */
    double final_drive_ratio;                    /* i_fd [-] */
    double gear_ratios[10];                      /* Forward gears 1..10 [-] */
    uint32_t num_gears, _pad;
} dl_multibody_params_t;

typedef struct {
    uint8_t  deck_type;        /* 0:NONE, 1:PACEJKA_TIR, 2:SOLVER_URI, 3:BLOB */
    uint8_t  precedence_mode;  /* 0:SUPPLEMENT_ONLY, 1:OVERRIDE_TIER1_2 */
    uint16_t _pad;
    uint32_t payload_size;
    char     uri_or_blob[256];
} dl_custom_deck_t;

typedef struct {
    uint32_t populated_tiers_mask; /* Bit 0: Tier0, Bit 1: Tier1, Bit 2: Tier2, Bit 3: Tier3 */
    uint32_t _pad;
    dl_kinematic_params_t    tier0;
    dl_single_track_params_t tier1;
    dl_multibody_params_t    tier2;
    dl_custom_deck_t         tier3;
} dl_vehicle_spec_t;

/* ==========================================================================
 * 2. PERCEPTION SLICE CONTRACTS (Stage 0 -> Stage 1/2/3)
 * ========================================================================== */

typedef struct {
    uint64_t target_actor_id;
    double   rel_x, rel_y, rel_z;                /* Sensor frame [m] */
    double   rel_vx, rel_vy;                     /* Sensor frame [m/s] */
    double   rel_yaw;                            /* [rad] */
    double   range, bearing, ttc_lon;            /* [m, rad, s] */
    char     road_id[64];
    int32_t  lane_id;
    uint32_t object_class;                       /* 0:UNKNOWN, 1:CAR, 2:TRUCK, 3:VRU */
    double   confidence;                         /* [0.0, 1.0] */
} dl_target_track_t;

typedef struct {
    char     ego_road_id[64];
    int32_t  ego_lane_id;
    uint8_t  left_lane_free, right_lane_free;
    uint16_t _pad;
    double   ego_s, ego_d, lead_ttc;             /* [m, m, s] */
    uint32_t num_tracks, _pad2;
    dl_target_track_t tracks[32];
} dl_visual_slice_t;

typedef struct {
    uint8_t  has_primary_target;
    uint8_t  _pad[3];
    uint32_t num_tracks;
    double   primary_range, primary_azimuth, primary_rcs; /* [m, rad, dBsm] */
    dl_target_track_t tracks[32];
} dl_radar_slice_t;

typedef struct {
    double   obstacle_confidence, lane_line_confidence;   /* [0.0, 1.0] */
    double   d_lane_center_est, heading_error_est;        /* [m, rad] */
    uint32_t num_tracks, _pad;
    dl_target_track_t tracks[32];
} dl_camera_slice_t;

typedef struct {
    double   mu_fl, mu_fr, mu_rl, mu_rr;         /* Per-corner friction [-] */
    double   mu_mean;                            /* Mean friction under actor [-] */
    double   road_grade, road_bank, elevation_z; /* [rad, rad, m] */
} dl_surface_slice_t;

/* ==========================================================================
 * 3. CANONICAL CHECKPOINT STRUCTS (Stages 1, 2, & 3)
 * ========================================================================== */

typedef struct {
    double x, y, psi_ref, kappa_ref;             /* [m, m, rad, 1/m] */
} dl_waypoint_t;

typedef struct {
    double t, x, y, psi, v, a, kappa, _pad;      /* [s, m, m, rad, m/s, m/s^2, 1/m] */
} dl_traj_point_t;

typedef struct {
    uint64_t actor_id;
    uint64_t timestamp_ns;                       /* [ns] */
    uint32_t valid_mask;                         /* Bitmask of active intent fields */
    uint8_t  lon_mode;                           /* 0:ACCEL, 1:VEL, 2:GAP */
    uint8_t  lat_mode;                           /* 0:LANE, 1:PATH, 2:TRAJ */
    uint8_t  turn_signal;                        /* 0:NONE, 1:L, 2:R, 3:HAZ */
    uint8_t  _pad;
    double   a_ref, v_ref, s_stop;               /* [m/s^2, m/s, m] */
    uint64_t gap_target_actor_id;
    double   time_gap_ref, distance_gap_min;     /* [s, m] */
    char     target_road_id[64];
    int32_t  target_lane_id;
    uint32_t num_waypoints;
    double   d_ref;                              /* [m] */
    uint32_t num_traj_points, _pad2;
    dl_waypoint_t   path_points[64];
    dl_traj_point_t trajectory[64];
} dl_intent_frame_t;

typedef struct {
    uint64_t actor_id;
    uint64_t timestamp_ns;                       /* [ns] */
    uint32_t valid_mask;                         /* 0x1:a_lon, 0x2:jerk, 0x4:angle, 0x8:rate */
    uint32_t _pad;
    double   a_lon_cmd, jerk_lon_cmd;            /* [m/s^2, m/s^3] */
    double   steer_angle_cmd, steer_rate_cmd;    /* [rad, rad/s] */
} dl_kinematic_control_frame_t;

typedef struct {
    uint64_t actor_id;
    uint64_t timestamp_ns;                       /* [ns] */
    uint32_t valid_mask;                         /* 0x1:thr, 0x2:brk, 0x4:steer, 0x8:trq, 0x10:gear */
    uint8_t  gear_mode;                          /* 0:PARK, 1:REVERSE, 2:NEUTRAL, 3:DRIVE */
    int8_t   manual_gear_index;                  /* 0:Auto, 1..10:Manual gear */
    uint16_t _pad;
    double   throttle, brake;                    /* [0.0, 1.0] */
    double   steering_wheel_norm;                /* [-1.0, 1.0] */
    double   steering_torque_nm;                 /* [N*m] */
} dl_actuator_control_frame_t;

typedef struct {
    uint64_t actor_id;
    uint64_t timestamp_ns;                       /* [ns] */
    double   pos_x, pos_y, pos_z;                /* Rear-axle World [m] */
    double   roll, pitch, yaw;                   /* Intrinsic Z-Y'-X'' Euler [rad] */
    double   v_lon, v_lat, yaw_rate;             /* Rear-axle Body Twist [m/s, rad/s] */
    double   a_lon, a_lat;                       /* Rear-axle Body Accel [m/s^2] */
    double   front_wheel_angle;                  /* Road-wheel delta [rad] */
    double   slip_angle_beta_cg;                 /* Sideslip angle at CG beta_cg [rad] */
    char     road_id[64];
    int32_t  lane_id;
    uint32_t _pad;
    double   frenet_s, frenet_d;                 /* Cached Frenet [m] */
} dl_kinematic_state_t;

/* ==========================================================================
 * 4. POINTER-FREE INITIALIZATION, WARM-START, & BATCH CONTEXTS
 * ========================================================================== */

typedef struct {
    double omega;                                /* Wheel spin [rad/s] */
    double steer_angle;                          /* Corner road-wheel steer [rad] */
    double slip_ratio_kappa, slip_angle_alpha;   /* [-], [rad] */
    double susp_deflection_z, susp_velocity_dz;  /* [m], [m/s] */
    double normal_load_fz, surface_mu;           /* [N], [-] */
} dl_wheel_corner_state_t;

typedef struct {
    double   motor_or_engine_speed_rads;         /* [rad/s] (Strict SI) */
    double   actual_drive_torque_nm;             /* [N*m] */
    double   brake_pressure_pa[8];               /* [Pa] (Strict SI) */
    uint8_t  gear_mode;                          /* 0:P, 1:R, 2:N, 3:D */
    int8_t   active_gear_index;                  /* -1:R, 0:N, 1..10:Forward */
    uint8_t  _pad[6];
} dl_powertrain_state_t;

typedef struct {
    uint32_t abi_version;                        /* Must equal DL_ABI_VERSION_0_2 */
    uint32_t struct_size;                        /* sizeof(dl_init_context_t) */
    uint64_t sim_time_ns;                        /* [ns] */
    uint8_t  is_warm_start;                      /* 0:ColdInit, 1:WarmStart */
    uint8_t  trim_equilibrium;                   /* 1:Solve quasi-static trim */
    uint16_t _pad;
    uint32_t num_wheels;                         /* 4 for passenger car, up to 8 */

    dl_kinematic_state_t          chassis_state;
    dl_wheel_corner_state_t       wheels[8];
    dl_powertrain_state_t         powertrain;

    dl_intent_frame_t             latched_intent;
    dl_kinematic_control_frame_t  latched_kinematic_ctrl;
    dl_actuator_control_frame_t   latched_actuator_ctrl;

    dl_vehicle_spec_t             vehicle_spec;  /* Inline pointer-free spec */
} dl_init_context_t;

/* Vectorized Batch I/O Descriptor for 1:N and N:N Components */
typedef struct {
    uint64_t       sim_time_ns;
    uint64_t       dt_step_ns;
    uint32_t       actor_count;                  /* Active actors M */
    uint32_t       num_sensor_ports;
    const void*    sensor_slice_buffers;         /* Contiguous array of SliceBuffer views */
    const void*    upstream_frames_in;           /* Contiguous array [M] of input frames */
    void*          downstream_frames_out;        /* Contiguous array [M] of output frames */
} dl_batch_step_io_t;

/* Membership Mutation Descriptor (Supports both Join and Leave at t > 0) */
typedef struct {
    uint64_t                sim_time_ns;
    uint32_t                active_actor_count;
    uint32_t                added_actor_count;
    const uint64_t*         active_actor_ids;    /* Array [active_actor_count] */
    const dl_init_context_t* added_init_contexts;/* Array [added_actor_count] for warm join */
} dl_membership_change_t;

/* ==========================================================================
 * 5. HOST MAP CALLBACKS & COMPONENT FUNCTION PROTOTYPES
 * ========================================================================== */

typedef struct {
    dl_status_t (*world_to_frenet)(
        double X, double Y, double psi, const char* hint_road_id,
        char out_road_id[64], int32_t* out_lane_id, double* out_s, double* out_d, double* out_psi_lane);

    dl_status_t (*frenet_to_world)(
        const char* road_id, int32_t lane_id, double s, double d,
        double* out_X, double* out_Y, double* out_Z, double* out_psi_lane, double* out_kappa_lane);

    dl_status_t (*sample_lane_path)(
        const char* road_id, int32_t lane_id, double s_start, double d_offset,
        double ds, uint32_t count, dl_waypoint_t* out_waypoints);

    dl_status_t (*query_lane_topology)(
        const char* road_id, int32_t lane_id,
        int32_t* out_left_lane_id, int32_t* out_right_lane_id,
        char out_next_road_id[64], int32_t* out_next_lane_id);
} dl_host_map_callbacks_t;

typedef struct {
    uint32_t        max_actors;                  /* M (1 for 1:1, N for 1:N / N:N) */
    uint32_t        num_sensor_ports;
    const uint32_t* port_history_depths;         /* Array [num_sensor_ports] of depths N_p */
} dl_structural_config_t;

/* Normative C-ABI Lifecycle Entry Points */
dl_status_t dl_instantiate(uint32_t abi_version, const dl_host_map_callbacks_t* callbacks, dl_component_handle_t* out_inst);
dl_status_t dl_configure_structure(dl_component_handle_t inst, const dl_structural_config_t* cfg);
dl_status_t dl_enter_cold_init(dl_component_handle_t inst, uint32_t actor_count, const dl_init_context_t* init_contexts);
dl_status_t dl_enter_warm_start(dl_component_handle_t inst, uint32_t actor_count, const dl_init_context_t* init_contexts);
dl_status_t dl_exit_init_mode(dl_component_handle_t inst);
dl_status_t dl_do_step(dl_component_handle_t inst, const dl_batch_step_io_t* io);
dl_status_t dl_on_membership_change(dl_component_handle_t inst, const dl_membership_change_t* change);
dl_status_t dl_terminate(dl_component_handle_t inst);
void        dl_free_instance(dl_component_handle_t inst);

#pragma pack(pop)

#ifdef __cplusplus
}
#endif
#endif /* DRIVELINE_ABI_H */
```

---

## 8. Composition, Fan-Out (`+`), Arbitration, & Splicing

1. **Sequential Chaining (`>>`):** Connects $A: T_1 \rightarrow T_2$ and $B: T_2 \rightarrow T_3$ into $A \gg B: T_1 \rightarrow T_3$[cite: 1]. For a $1\text{:}N$ component feeding $M$ actors into a $1\text{:}1$ downstream component (e.g., `PincerHiveMind >> kinematic_coupled_control()`), the runtime automatically instantiates $M$ independent instances of the downstream $1\text{:}1$ chain (one per bound actor)[cite: 1].
2. **Parallel Split-Merge Operator (`+`):** Given two components $B_{\text{lon}}: T_{\text{in}} \rightarrow T_{\text{out}}^{\text{lon}}$ and $B_{\text{lat}}: T_{\text{in}} \rightarrow T_{\text{out}}^{\text{lat}}$ that produce orthogonal longitudinal and lateral subsets of a checkpoint frame $T_{\text{out}}$ (either `IntentFrame` or `KinematicControlFrame`), the expression $(B_{\text{lon}} + B_{\text{lat}}): T_{\text{in}} \rightarrow T_{\text{out}}$ broadcasts $T_{\text{in}}$ to both branches in parallel and merges their outputs via bitwise OR of their `valid_mask` fields (`0x01 | 0x02` for `IntentFrame`; `0x01 | 0x02` and `0x04 | 0x08` for `KinematicControlFrame`)[cite: 1].
3. **Multi-Chain Arbitration (`Arbitrate`):** Merges two parallel chains producing the same checkpoint type $T_{\text{check}}$ (`IntentFrame`, `KinematicControlFrame`, or `ActuatorControlFrame`) via an explicit `Arbiter` component[cite: 1]. Because each frame carries `valid_mask`, field-wise arbiters (such as `BrakeOverrideArbiter`) inspect `secondary.valid_mask & 0x02` (`brake` active) to override longitudinal pedals while passing `primary.steering_wheel_norm` untouched when `secondary.valid_mask & 0x04 == 0`[cite: 1].

---

## 9. Deterministic Integer-Tick Execution Model

To guarantee bit-identical execution across platforms and avoid floating-point modulo drift:

1. **Integer Nanosecond Base Clock & Tick Divisors:** The simulation clock advances by integer tick index $k_{\text{tick}} \in \{0, 1, 2, \dots\}$ with base period $\Delta t_{\text{base\_ns}} \in \mathbb{Z}^+$ nanoseconds ($t_{\text{ns}} = k_{\text{tick}} \cdot \Delta t_{\text{base\_ns}}$).
   * **Exact Rate Divisibility Rule:** Every sensor or component rate $f_{\text{comp}}$ must divide the base frequency $f_{\text{base}} = 10^9 / \Delta t_{\text{base\_ns}}$ into an exact integer tick divisor $k_{\text{div}} = f_{\text{base}} / f_{\text{comp}} \in \mathbb{Z}^+$. Specifying a non-integer divisor (such as `30Hz` on a `500Hz` base clock) is a **compile-time error**.
   * **Default Component Rate:** Any component that omits a `(rate: ...)` clause inherits the base clock rate ($k_{\text{div}} = 1$).
   * **Scheduling Rule:** A component with divisor $k_{\text{div}}$ executes on tick $k_{\text{tick}}$ if and only if $(k_{\text{tick}} \bmod k_{\text{div}}) == 0$, and holds its output constant via Zero-Order Hold (ZOH) on intermediate ticks[cite: 1].
2. **Deterministic Intra-Phase Ordering & Seeding:**
   * Within Phase 1, Phase 2, and Phase 3, actors and $1\text{:}N$ groups are evaluated in ascending order of `actor_id` (and topological chain order within each actor). Because Phase 2 components only read Phase 1 `SliceBuffer` snapshots from $X(t)$ and write to actor-local checkpoint buffers, Phase 2 is data-race-free and parallelizable across actors.
   * Stochastic sensors receive a deterministic per-sensor PRNG seed derived via ` SipHash24(scenario_seed, actor_id, sensor_port_index, k_tick)`.
   * External FMUs and ONNX runtimes must execute in single-threaded, deterministic IEEE 754 floating-point mode (`ORT_SEQUENTIAL`, deterministic cuDNN/CPU kernels) to qualify as Driveline-compliant.

---

## 10. Normative EBNF Grammar & Reference Scenario

### 10.1 Complete EBNF Grammar
```ebnf
ScenarioFile     ::= ImportDecl* VehicleSpecDecl* (ComponentDecl | FnDecl)* ScenarioDecl
ImportDecl       ::= "use" ScopedIdent "::" "{" IdentList "}" ";"
VehicleSpecDecl  ::= "vehicle_spec" Ident "{" (Ident "=" Expr ";")* "}"

ComponentDecl    ::= "component" Ident FmuClause? RateClause? TierClause? ":" "(" PortList? ")" "->" TypeIdent (Block | ";")
FmuClause        ::= "from_fmu" "(" StringLit ")"
RateClause       ::= "(" "rate:" FreqLit ")"
TierClause       ::= "(" "required_tier:" IntLit ")"
PortList         ::= PortDecl ("," PortDecl)*
PortDecl         ::= (Ident ":")? TypeSpec
TypeSpec         ::= Ident ("<" TypeSpec ("," (TypeSpec | IntLit))* ">")?

FnDecl           ::= "fn" Ident "(" PortList? ")" "->" TypeSpec "{" "return" PipeExpr ";" "}"
Block            ::= "{" (ParamDecl | BindInputsBlock | BindOutputsBlock | StepBlock)* "}"
ParamDecl        ::= "param" Ident ":" TypeIdent "=" Expr ";"
BindInputsBlock  ::= "bind_inputs" "{" (StringLit "=" Expr ";")* "}"
BindOutputsBlock ::= "bind_outputs" "->" TypeIdent "{" (Ident "=" Expr ";")* "}"
StepBlock        ::= "step" "(" PortList ")" "->" TypeIdent "{" Stmt* "}"

ScenarioDecl     ::= "scenario" Ident "{" WorldStmt* ActorDecl* BindStmt* TerminateStmt "}"
WorldStmt        ::= ("map" "=" Expr ";") | ("timestep" "=" TimeLit ";") | ("seed" "=" IntLit ";") | EnvBlock | StaticObjDecl
EnvBlock         ::= "environment" "{" (Ident "=" Expr ";" | CallExpr ";")* "}"
StaticObjDecl    ::= "static_object" Ident "=" CallExpr ";"

ActorDecl        ::= "actor" Ident ("[" IntLit "]")? "=" CallExpr ("with" ActorBody)? ";"
ActorBody        ::= "{" PriorsBlock? SensorsBlock? ChainDecl* PhysicsDecl? "}"
PriorsBlock      ::= "priors" "{" (Ident "=" Expr ";")* "}"
SensorsBlock     ::= "sensors" "{" (Ident "=" CallExpr ";")* "}"
ChainDecl        ::= "chain" Ident "=" PipeExpr ";"
PhysicsDecl      ::= "physics" "=" PipeExpr ";"

BindStmt         ::= "bind" ("[" IdentList "]" | Ident) "->" PipeExpr ";"
PipeExpr         ::= PrimaryPipe (">>" PrimaryPipe)*
PrimaryPipe      ::= CallExpr | "(" PipeExpr ("+" PipeExpr)+ ")" | ArbitrateExpr | Ident
ArbitrateExpr    ::= "Arbitrate" "(" PipeExpr "," PipeExpr "," "via:" CallExpr ")"
TerminateStmt    ::= "terminate" "when" "(" Expr ")" ";"

Stmt             ::= LetStmt | IfStmt | ReturnStmt
LetStmt          ::= "let" Ident "=" Expr ";"
IfStmt           ::= "if" Expr "{" Stmt* "}" ("else" "{" Stmt* "}")?
ReturnStmt       ::= "return" Expr ";"
```

### 10.2 Normative Reference Scenario (`kanagawa_pinch_test.dline`)
Every component, port capacity `SliceBuffer<T, N>`, clock divisor, parameter tier, and control-to-physics connection in this reference scenario satisfies the normative rules of Sections 1–10:

```rust
use std::sensors::{HumanVisualSensor, SurroundVisualSensor, MillimeterRadar, MonoCamera, SurfaceContactSensor};
use std::intent::{PincerHiveMind};
use std::control::{PIDSpeedController, JerkLimiter, StanleyLat, LinearPedalMapper, BrakeOverrideArbiter};
use std::physics::{SimpleDrivetrain, DynamicSingleTrack, KinematicBicycle};

// ============================================================================
// 1. STRATIFIED VEHICLE SPECIFICATION (Satisfies all Tier 0, 1, 2 invariants)
// ============================================================================
vehicle_spec Sedan_2026 {
    // Tier 0: L_bbox (4.75m) == wheelbase (2.80m) + overhang_f (0.95m) + overhang_r (1.00m)
    tier0 = {
        bbox_length: 4.75m, bbox_width: 1.85m, bbox_height: 1.45m,
        wheelbase: 2.80m, overhang_front: 0.95m, overhang_rear: 1.00m,
        max_steer_angle: 0.62rad, max_steer_rate: 0.45rad/s, steering_ratio: 14.5
    };

    // Tier 1: l_f (1.25m) + l_r (1.55m) == wheelbase (2.80m)
    tier1 = {
        mass: 1750.0kg, cg_dist_front: 1.25m, cg_dist_rear: 1.55m, cg_height: 0.52m,
        inertia_zz: 2850.0kg*m^2, cornering_stiffness_f: 85000.0N/rad, cornering_stiffness_r: 92000.0N/rad,
        aero_cd: 0.28, aero_area: 2.25m^2, rolling_resistance_coeff: 0.012
    };

    // Tier 2: m_s (1510kg) + m_uf (120kg) + m_ur (120kg) == mass (1750kg)
    tier2 = {
        sprung_mass: 1510.0kg, unsprung_mass_f: 120.0kg, unsprung_mass_r: 120.0kg,
        inertia_xx: 580.0kg*m^2, inertia_yy: 2650.0kg*m^2, inertia_xz: 110.0kg*m^2,
        track_width_f: 1.58m, track_width_r: 1.59m,
        susp_stiffness_f: 32000.0N/m, susp_stiffness_r: 36000.0N/m,
        susp_damping_f: 2800.0N*s/m, susp_damping_r: 3100.0N*s/m,
        arb_stiffness_f: 18000.0N*m/rad, arb_stiffness_r: 15000.0N*m/rad,
        tire_effective_radius: 0.33m, wheel_polar_inertia: 1.15kg*m^2,
        max_drive_torque: 3200.0N*m, max_brake_torque: 6500.0N*m,
        final_drive_ratio: 3.90, gear_ratios: [3.60, 2.19, 1.41, 1.00, 0.83]
    };

    // Tier 3: Optional Pacejka Tire Deck (Supplements Tier 1/2 when solver supports .tir)
    tier3 = {
        deck_type: "PACEJKA_TIR", precedence_mode: "SUPPLEMENT_ONLY",
        uri: "tires/pacejka_235_45_R18.tir"
    };
}

// ============================================================================
// 2. COMPONENT DECLARATIONS & REUSABLE CONTROL CHAINS
// ============================================================================

// Native DSL Intent Component with explicit compile-time SliceBuffer capacity N=10
component HumanIntent (rate: 20Hz) (required_tier: 0): (
    eyes:  SliceBuffer<VisualSlice, 10>,
    route: RouteNodes
) -> IntentFrame {
    param reaction_delay: Time = 0.18s;
    param desired_speed: Velocity = 28.0m/s;

    step(t: Time, dt: Time) -> IntentFrame {
        let perceived = eyes.at(t - reaction_delay, mode: Interpolate);
        if perceived.lead_ttc < 2.2s {
            return IntentFrame::decelerate(a_ref: -5.5m/s^2);
        } else {
            return IntentFrame::follow_route(route: route, v_ref: desired_speed);
        }
    }
}

// External Native Binary / Mode-A FMU for Human Control
component HumanControl from_fmu("fmus/HumanDriverControl.fmu") (rate: 100Hz) (required_tier: 0): (
    intent: IntentFrame
) -> ActuatorControlFrame;

// External Legacy Scalar-Pin Mode-B OEM Pre-Collision System FMU
// Uses safe rate_of() helper (zero division risk on Tick 0) and explicit valid_mask
component BoschPCS_v4 from_fmu("fmus/BoschPCS_v4.fmu") (rate: 50Hz) (required_tier: 0): (
    radar:  SliceBuffer<RadarSlice, 8>,
    camera: SliceBuffer<CameraSlice, 5>
) -> ActuatorControlFrame {
    bind_inputs {
        "Radar_Range_m"    = radar.latest().primary_range;
        "Radar_RangeRate"  = radar.rate_of(primary_range, window: 1);
        "Cam_ObstacleConf" = camera.latest().obstacle_confidence;
    }
    bind_outputs -> ActuatorControlFrame {
        valid_mask          = select(fmu.out("AEB_Active") > 0.5, 0x03, 0x00);
        throttle            = 0.0;
        brake               = clamp(fmu.out("AEB_BrakePressure_Pa") / 12000000.0, 0.0, 1.0);
        steering_wheel_norm = 0.0;
        gear_mode           = GearMode::DRIVE;
    }
}

// Pure Tier-A Kinematic Control Chain (For Tier-0 KinematicBicycle challengers)
// Explicitly converts v_ref/GAP_PROFILE -> a_lon_cmd via PIDSpeedController before JerkLimiter
fn kinematic_coupled_control() -> Chain<IntentFrame, KinematicControlFrame> {
    return ((PIDSpeedController(kp: 1.8, ki: 0.1, kd: 0.05) >> JerkLimiter(max_jerk: 4.0m/s^3))
          + StanleyLat(k: 2.5, sample_step: 1.0m));
}

// ============================================================================
// 3. SCENARIO DEFINITION
// ============================================================================
scenario KanagawaExpresswayPinchTest {
    map = load_xodr("maps/kanagawa_expressway.xodr");
    timestep = 0.002s; // 500 Hz base clock (dt_base_ns = 2,000,000 ns)
    seed = 42;

    environment {
        default_friction = 0.85;
        friction_zone(road: "road_10", s_start: 150.0m, s_end: 250.0m, mu: 0.25);
    }

    // --- Actor 1: Ego Vehicle (Tier-B Actuators -> SimpleDrivetrain -> Tier-1 Single-Track) ---
    actor ego = spawn(id: 1, spec: Sedan_2026, road: "road_10", lane: -2, s: 15.0m, v: 28.0m/s) with {
        priors {
            nav_route = RouteNodes(["road_10:-2", "road_11:-1", "jct_4:-1"]);
        }
        sensors {
            // All sensor rates (20Hz, 50Hz, 25Hz, 500Hz) divide 500Hz evenly (divisors: 25, 10, 20, 1)
            eyes        = HumanVisualSensor(fov: 140deg, range: 180.0m, rate: 20Hz, history: 10);
            front_radar = MillimeterRadar(mount: FrontBumper, fov: 45deg, rate: 50Hz, history: 8);
            front_cam   = MonoCamera(mount: Windshield, fov: 60deg, rate: 25Hz, history: 5);
            tire_patch  = SurfaceContactSensor(rate: 500Hz, history: 1);
        }

        chain human_driver  = HumanIntent(eyes: sensors.eyes, route: priors.nav_route)
                           >> HumanControl();

        chain active_safety = BoschPCS_v4(radar: sensors.front_radar, camera: sensors.front_cam);

        // BrakeOverrideArbiter outputs ActuatorControlFrame; SimpleDrivetrain converts pedals
        // to axle forces/angles using Tier-2 powertrain parameters before DynamicSingleTrack
        physics = Arbitrate(human_driver, active_safety, via: BrakeOverrideArbiter())
               >> SimpleDrivetrain()
               >> DynamicSingleTrack(surface: sensors.tire_patch);
    };

    // --- Actors 2 & 3: Challengers with Mounted Sensors & 1:N Hive-Mind Coordination ---
    actor blocker = spawn(id: 2, spec: Sedan_2026, road: "road_10", lane: -1, s: 30.0m, v: 26.0m/s) with {
        sensors {
            surround = SurroundVisualSensor(range: 150.0m, rate: 25Hz, history: 5);
        }
    };

    actor challenger = spawn(id: 3, spec: Sedan_2026, road: "road_10", lane: -3, s: 35.0m, v: 25.0m/s) with {
        sensors {
            surround = SurroundVisualSensor(range: 150.0m, rate: 25Hz, history: 5);
        }
    };

    // 1:N PincerHiveMind reads each challenger's mounted `surround` sensor buffer
    // to track target_actor_id: 1 (no direct World actor handle leak!) and outputs
    // IntentFrame -> Tier-A KinematicControlFrame -> Tier-0 KinematicBicycle
    bind [blocker, challenger] -> PincerHiveMind(
                                      vision: [blocker.sensors.surround, challenger.sensors.surround],
                                      target_actor_id: 1,
                                      pinch_gap: 12.0m
                                  )
                               >> kinematic_coupled_control()
                               >> KinematicBicycle();

    terminate when (sim_time > 25.0s or collision(ego, any) or ego.state.v_lon < 0.1m/s);
}
```