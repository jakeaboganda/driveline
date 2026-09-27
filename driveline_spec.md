# Driveline Scenario Description Language & Component Architecture
**Formal Specification, Draft v0.3**
* **File Extensions:** `.dline`, `.dl`
* **Binary Interface:** Driveline C-ABI (`driveline_abi.h`, ABI v0.3), with FMU packaging as the FMI 3.0 layered standard `org.driveline.dcm` (§6.3)

---

## 1. Scope, Architectural Principles, & Related Work

**Driveline** is a deterministic, component-first scenario description language and execution architecture for road-driving simulation. It separates ground-truth world state from per-actor behavioral, control, and physical compute pipelines, and it specifies the control and vehicle-dynamics contracts that existing scenario standards leave to the host simulator.

### 1.1 Core Architectural Principles

1. **Three-Level World vs. Actor Separation:**
   * **Lexical Level:** A `.dline` scenario file serves as the top-level simulation manifest: it declares the physical world (`map`, `environment`, `static_object`), spawns actor entities with initial physical states, and binds each actor's initial component graph.
   * **Type Level:** World truth types (`OpenDriveMap`, `FrictionField`) cannot be passed as inputs to Stage 1 (Intent) or Stage 2 (Control) components.
   * **Runtime Memory Level:** Pipeline components execute in isolated memory contexts and cannot query global world state directly. They access external context only through actor-mounted `SliceBuffer<T, N>` sensor ports, `priors`, and the read-only host map callbacks (§7).
   * **Stated Ground-Truth Exceptions:** Two inputs are ground truth by design. The host map callbacks give every component the exact OpenDRIVE geometry (a perfect-map prior). Standard sensors report the true `target_actor_id` of each track (ideal data association). A sensor model that simulates map error or association error must produce those errors itself.
2. **Intra-Tick Acyclic Dataflow Chains (`>>`):** Within any single simulation tick $t$, an actor's motion pipeline is a strictly typed Directed Acyclic Graph (DAG) of signal transformers connected via the pipe operator (`>>`). Across ticks, the loop closes through the World ($X(t) \xrightarrow{\text{Phase 1}} \text{SensorSlice}(t) \xrightarrow{\text{Phase 2}} \text{IntentFrame}(t) \xrightarrow{\text{Phase 2}} \text{ControlFrame}(t) \xrightarrow{\text{Phase 3}} X(t + \Delta t)$), imposing a well-defined one-tick ($1 \cdot \Delta t_{\text{base}}$) sensing-to-actuation latency.
3. **Zero Implicit Control Glue:** The runtime prohibits hidden controller conversions (such as unparameterized speed-to-acceleration gains or implicit pedal maps) between mismatched components. All cross-tier conversions must be declared as explicit, parameterized adapter blocks in the chain, while pure geometric map queries are provided via deterministic host callbacks.
4. **FMI 3.0 Layered Component Model & Cardinality Agnosticism:** Driveline standardizes port data contracts and lifecycle transitions rather than internal component implementations, allowing native DSL state trees, Behavior Trees, ONNX models, Simulink FMUs, or C++ binaries to be swapped freely. Components support $1\text{:}1$ per-actor bindings, $1\text{:}N$ centralized coordination ("Hive Mind" intent), and $N\text{:}N$ vectorized batch execution.

### 1.2 Related Work & Standards Positioning

The table below states what each related standard covers and where Driveline differs. The comparative claims in the third column describe scope. They are not measured results. Appendix A lists the claims that still need a checked reference.

| Standard / Framework | Scope Covered | Not Covered | How Driveline Relates |
| :--- | :--- | :--- | :--- |
| **ASAM OpenSCENARIO (v1.x XML & v2.x DSL)** | Scenario orchestration, actor spawning, and composable behavior modifiers. | Controller and vehicle-dynamics models. The host simulator supplies them, so two tools can run the same scenario with different dynamics. | Adds per-actor `Intent >> Control >> Physics` pipelines with typed control and physics contracts. |
| **ASAM OSI (Open Simulation Interface)** | Protobuf schemas (`SensorView`, `SensorData`, `TrafficCommand`, `TrafficUpdate`) for sensor and traffic co-simulation. | Intra-actor control arbitration, mid-run component swaps, and a scenario authoring DSL. | Sensor slices (§4.3) follow OSI object semantics. Runtimes may fill them from OSI messages. |
| **CommonRoad Vehicle Models (Althoff et al.)** | Model equations and parameter sets for Point-Mass (`PM`), Kinematic Single-Track (`KS`), Single-Track (`ST`), and Multi-Body (`MB`) vehicles. | Multi-rate co-simulation and component lifecycle. | Tiers 0–2 follow the same model ladder (`KS`, `ST`, `MB`). Driveline parameter names and units are its own. A mapping to CommonRoad parameter sets is not yet specified. |
| **FMI 3.0 & ASAM SSP** | Binary packaging (`.fmu`), clocks, `fmi3Binary` variables, and static system topology (`SystemStructure.ssd`). | OpenDRIVE queries, timestamped sensor history, and component swaps during a run. | Native components use the Driveline C-ABI (§7). Components packaged as FMUs use the layered standard `org.driveline.dcm` (§6.3), which uses only standard FMI 3.0 functions. |

---

## 2. Global Units & Coordinate Conventions

All compliant runtimes and components must enforce the following mathematical conventions at every port boundary:

* **Strict SI Units:** Distance in meters ($\text{m}$), time in seconds ($\text{s}$), mass in kilograms ($\text{kg}$), force in newtons ($\text{N}$), pressure in pascals ($\text{Pa}$), torque in newton-meters ($\text{N}\cdot\text{m}$), angles in radians ($\text{rad}$), angular velocity in radians per second ($\text{rad/s}$), velocity in meters per second ($\text{m/s}$), acceleration in meters per second squared ($\text{m/s}^2$), and jerk in meters per second cubed ($\text{m/s}^3$). Non-SI units in the DSL (such as `deg` or `Hz`) are syntactic sugar converted to SI (`rad`, $\text{s}^{-1}$) at compile time.
* **Time Representation:** Every timestamp, and every value of the DSL type `Time`, is an unsigned 64-bit count of nanoseconds. The compiler converts time literals such as `0.18s` to nanoseconds exactly. Components convert to seconds only inside their own arithmetic.
* **Inertial World Frame (ISO 8855):** Right-handed Cartesian coordinate system $(X, Y, Z)$ aligned with the OpenDRIVE inertial frame ($+X$ East, $+Y$ North, $+Z$ Up).
* **Vehicle Body Frame & Euler Sequence (ISO 8855):** Orthogonal right-handed frame anchored to the vehicle with $+x$ longitudinal forward, $+y$ lateral left, and $+z$ vertical up. World orientation $(\text{roll } \phi, \text{pitch } \theta, \text{yaw } \psi)$ follows the **ISO 8855 intrinsic $Z\text{-}Y'\text{-}X''$ (yaw $\psi \rightarrow$ pitch $\theta \rightarrow$ roll $\phi$) rotation sequence**. All angles are counter-clockwise positive and normalized to $(-\pi, \pi]$.
* **Actor Reference Origin:** Standardized at the **center of the rear axle projected onto the ground plane** $(x_{\text{ra}}, y_{\text{ra}}, z_{\text{ra}})$. The Center of Gravity (CG) is located at longitudinal distance $l_r$ forward of the rear axle, $l_f$ behind the front axle, and height $h_{\text{cg}}$ above the ground plane.
* **OpenDRIVE Road & Lane Referencing `(road_id, lane_id, s, d)`:**
  * `road_id` (`char[64]`): Null-terminated OpenDRIVE `<road id="...">` identifier.
  * `lane_id` (`int32_t`): Signed OpenDRIVE lane index ($-1, -2, \dots$ right of reference line; $+1, +2, \dots$ left of reference line; $0$ is the road reference line).
  * `s` (`float64`, $\text{m}$): Arc-length measured along the **OpenDRIVE road reference line** (`lane_id = 0`) from the start of `road_id`.
  * `d` (`float64`, $\text{m}$): Orthogonal lateral offset measured from the **centerline of `lane_id`** (positive to the left in the reference line direction).
  * **Lane Reference String:** Where the DSL writes a lane as a string, the format is `"<road_id>:<lane_id>"`. The text after the last colon is the signed lane index. Junction connecting roads are roads and use their own `road_id`.
* **Driving Direction & Spawn Heading:** A lane's driving direction comes from the OpenDRIVE road `rule` attribute. For `RHT`, negative lanes drive toward increasing $s$. For `LHT`, positive lanes drive toward increasing $s$. `spawn` places an actor facing its lane's driving direction, so the actor's `frenet_s` increases with time only on lanes that drive toward increasing $s$.
* **Road Grade & Bank Signs:** `road_grade` $\theta_{\text{road}}$ is positive when the road rises in the actor's direction of travel. `road_bank` $\phi_{\text{road}}$ is positive when the road's left edge is higher than its right edge. These are road properties. They are not the vehicle's ISO 8855 Euler angles. On an uphill road, a vehicle's ISO 8855 pitch is $\theta = -\theta_{\text{road}}$ because positive ISO pitch is nose-down.

---

## 3. Stratified Vehicle Parameter Specification (`vehicle_spec`)

Borrowing the hierarchical model structure of CommonRoad, Driveline defines a four-tier parameter specification attached to the actor entity. Higher tiers strictly require all lower numeric tiers (Tier 2 requires Tiers 0 and 1; Tier 1 requires Tier 0).

| Tier | C-ABI Struct | Target Fidelity Models | Mandatory Parameters & Invariants |
| :--- | :--- | :--- | :--- |
| **Tier 0** *(Mandatory Base)* | `dl_kinematic_params_t` | Point-Mass (`PM`), Kinematic Bicycle (`KS`), Path Trackers (`Stanley`, `PurePursuit`) | `bbox_length` $L_{\text{bbox}}$, `bbox_width` $W_{\text{bbox}}$, `bbox_height` $H_{\text{bbox}}$, `wheelbase` $L$, `overhang_front` $o_f$, `overhang_rear` $o_r$, `max_steer_angle` $\delta_{\max}$, `max_steer_rate` $\dot{\delta}_{\max}$, `steering_ratio` $i_s$.<br>**Invariant:** $L_{\text{bbox}} == L + o_f + o_r$. |
| **Tier 1** *(Dynamic Single-Track)* | `dl_single_track_params_t` | Dynamic Single-Track (`ST`), Linear Tire Slip Models, Dynamic MPC | Total `mass` $m$, `cg_dist_front` $l_f$, `cg_dist_rear` $l_r$, `cg_height` $h_{\text{cg}}$, yaw inertia `inertia_zz` $I_{zz}$, linear cornering stiffnesses `cornering_stiffness_f` $C_{\alpha f}$ and `cornering_stiffness_r` $C_{\alpha r}$, `aero_cd` $C_d$, `aero_area` $A_f$, `rolling_resistance_coeff` $C_{rr}$.<br>**Invariant:** $l_f + l_r == L$. |
| **Tier 2** *(Multi-Body & Powertrain)* | `dl_multibody_params_t` | 14-DOF / 29-DOF Multi-Body (`MB`), SimpleDrivetrain, Full Powertrain & Brake Hydraulics | `sprung_mass` $m_s$, per-axle unsprung masses `unsprung_mass_f` $m_{uf}$ and `unsprung_mass_r` $m_{ur}$, roll/pitch/cross inertias $[I_{xx}, I_{yy}, I_{xz}]$, track widths $(t_f, t_r)$, per-wheel suspension stiffness $(K_{sf}, K_{sr})$ and damping $(C_{sf}, C_{sr})$, anti-roll stiffness $(K_{\text{arb},f}, K_{\text{arb},r})$, `tire_effective_radius` $R_{\text{eff}}$, `wheel_polar_inertia` $I_w$, `max_drive_torque` $T_{\text{drive,max}}$ (peak engine or motor output-shaft torque, before the gearbox), `max_brake_torque` $T_{\text{brake,max}}$ (total brake torque summed over all wheels, at the wheels), `final_drive_ratio` $i_{\text{fd}}$, `gear_ratios[10]` $i_g$. Peak drive torque at the wheels in gear $g$ is $T_{\text{drive,max}} \, i_g \, i_{\text{fd}}$.<br>**Invariant:** $m_s + m_{uf} + m_{ur} == m$. |
| **Tier 3** *(External Solver Deck)* | `dl_custom_deck_t` | Pacejka Magic Formula `.tir`, IPG CarMaker, Adams/Car | `deck_type` (`NONE`, `PACEJKA_TIR`, `SOLVER_URI`), `precedence_mode` (`OVERRIDE_TIER1_2` or `SUPPLEMENT_ONLY`), and `uri[256]`, a null-terminated path or URI to the deck file. Deck contents are never inlined. |

### 3.1 Compile-Time Tier Verification & Single Source of Truth
1. **Compile-Time Tier Check:** Every physics and control component declares its minimum required `vehicle_spec` tier (`required_tier: 0 | 1 | 2`). Binding or splicing a component whose `required_tier` is not populated in the actor's `vehicle_spec` is a **compile-time error**.
2. **Control-to-Physics Tier Compatibility:**
   * A Tier 0 physics model (`KinematicBicycle`) accepts **only** Tier A `KinematicControlFrame`. Wiring an `ActuatorControlFrame` into `KinematicBicycle` is rejected at compile time.
   * A Tier 1 physics model (`DynamicSingleTrack`) accepts `KinematicControlFrame` natively (using only Tier 0 + Tier 1 parameters), or accepts `ActuatorControlFrame` when preceded by an explicit drivetrain adapter. The standard adapter is `SimpleDrivetrain: ActuatorControlFrame -> KinematicControlFrame`. It requires Tier 2 powertrain parameters $T_{\text{drive,max}}, T_{\text{brake,max}}, R_{\text{eff}}, i_g, i_{\text{fd}}$, and it converts steering with $\delta = $ `steering_wheel_norm` $\cdot \, \delta_{\max}$.
3. **No Divergent Geometry Overrides:** Physical geometry and mass parameters (`Tier 0`, `Tier 1`, `Tier 2`) belong exclusively to the actor's `vehicle_spec` and **cannot** be overridden inline on individual controller or physics blocks. This guarantees that World collision detection, warm-start trim, and all pipeline stages share a single immutable source of truth.

---

## 4. Actor Perception: Priors, Sensors, & `SliceBuffer<T, N>`

Pipeline components cannot access the global World state. Actors perceive external reality solely through mounted **Priors** and **Sensors**:

### 4.1 Priors (`priors`)
Static or slow-updating contextual memory mounted on the actor:
* `RouteNodes`: Ordered array of up to 64 lanes (`dl_route_t`, §7) that the actor intends to drive through. Each node is a `dl_lane_ref_t` `(road_id, lane_id)`. The DSL writes nodes as lane reference strings (§2).

### 4.2 Timestamped Ring Buffers (`SliceBuffer<T, N>`)
Every mounted sensor has a compile-time capacity $N \in [1, 64]$ declared in its port signature `SliceBuffer<T, N>`. A sensor with capacity $N_s$ can bind to any component input port expecting `SliceBuffer<T, N_c>` provided $N_s \ge N_c$. Each entry is a `Timestamped<T>` struct containing `{ uint64 t_ns; T data; }`. In the DSL, `slice.t` is the entry's `Time`, and `slice.field` is shorthand for `slice.data.field`. §7 defines the memory layout (`dl_slice_buffer_view_t`).

**Timestamp Invariant:** Timestamps in a buffer strictly decrease from $s[0]$ to $s[\text{count}-1]$. The runtime never pushes two samples with the same `t_ns`. Cold initialization (§6.2) relies on this rule.

All `SliceBuffer<T, N>` ports enforce deterministic edge-case semantics across four query primitives:
1. `buffer.latest() -> Timestamped<T>`: Equivalent to `buffer[0]`. Guaranteed valid from $t = 0$ because cold initialization Pass 1 performs the Tick 0 sensor projection (§6.2).
2. `buffer[k] / buffer.history(k) -> Timestamped<T>`:
   * **Compile-Time Bounds Check:** If $k$ is a compile-time constant and $k \ge N$, compilation fails.
   * **Early-Tick Underflow Rule ($k \ge \text{count}$):** Before $k+1$ samples have been recorded (e.g., on Tick 0 when $\text{count} == 1$), `buffer[k]` clamps to the oldest available sample `buffer[count - 1]` and sets `buffer.underflow = true`.
3. `buffer.rate_of(field_selector, window: k = 1) -> Rate`: Finite-difference derivative helper. `Rate` is `{ float64 value; bool valid; }`. With $m = \min(k, \text{count}-1)$:
   $$\text{rate\_of}(f, k) = \begin{cases} \{0.0, \text{false}\} & \text{if } \text{count} < 2 \\ \left\{\dfrac{s[0].f - s[m].f}{s[0].t - s[m].t}, \text{true}\right\} & \text{otherwise} \end{cases}$$
   The timestamp invariant makes the denominator positive whenever $\text{count} \ge 2$. Consumers must check `valid`. A `value` of $0.0$ with `valid = false` means "no estimate", not "no motion".
4. `buffer.at(t_query, mode: Interpolate | Floor) -> Timestamped<T>`:
   * **Clamping:** If $t_{\text{query}} \ge s[0].t$, returns $s[0]$. If $t_{\text{query}} \le s[\text{count}-1].t$, returns $s[\text{count}-1]$.
   * **`Floor` Mode:** Returns the newest sample $s[k]$ where $s[k].t \le t_{\text{query}}$.
   * **`Interpolate` Mode:** For bracket $s[k+1].t \le t_{\text{query}} < s[k].t$ with $\alpha = \frac{t_{\text{query}} - s[k+1].t}{s[k].t - s[k+1].t} \in [0, 1)$, each field follows its interpolation class from §4.3:
     * **`LINEAR`:** $(1 - \alpha) v_{k+1} + \alpha v_k$.
     * **`ANGLE`:** Linear interpolation along the shorter arc, wrapped to $(-\pi, \pi]$.
     * **`HOLD`:** Value from $s[k+1]$. Every integer, enum, flag, and `char[]` field is `HOLD`.
     * **Road-Relative Fields:** A `LINEAR` field marked with a road dependency (for example `ego_s` depends on `ego_road_id`) is interpolated only when the dependency fields are equal in both samples. Otherwise the whole sample is taken from $s[k+1]$.
     * **Non-Finite Values:** If a `LINEAR` or `ANGLE` field is not finite in either sample, the field takes its value from $s[k+1]$.
     * **Target Track Arrays (`TargetTrack[32]`):** Matched across $s[k+1]$ and $s[k]$ by `target_actor_id`. Tracks present in both samples interpolate field by field under the rules above. Tracks present in only one sample are taken from $s[k+1]$, or dropped if absent from $s[k+1]$.

### 4.3 Normative Sensor Slice Schemas (and ASAM OSI Mapping)
Driveline defines four standard sensor slice payloads, one track element type (`TargetTrack`), and one composite (`SensorBundle`). All are defined in `driveline_abi.h` (§7). Compliant runtimes may also fill them from **ASAM OSI** `osi3::SensorView` / `osi3::SensorData` messages. Appendix A lists the OSI mappings that still need checking against the OSI release.

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

---

## 5. Canonical Checkpoint Data Contracts

Every checkpoint frame carries `timestamp_ns` (`uint64`, simulation time in nanoseconds) and `actor_id` (`uint64`). `IntentFrame`, `KinematicControlFrame`, and `ActuatorControlFrame` also carry a `valid_mask` bitmask, so a consumer can tell an asserted `0.0` from a field that the producer does not request. `KinematicState` has no `valid_mask` because physics fills every field.

**Field Groups:** Each `valid_mask` bit belongs to one field group. The `+` operator (§8.2) uses these groups.

| Frame | `LON` Bits | `LAT` Bits | `COUPLED` Bits |
| :--- | :--- | :--- | :--- |
| `IntentFrame` | `0x01`, `0x04` | `0x02`, `0x10` | `0x08` |
| `KinematicControlFrame` | `0x01`, `0x02` | `0x04`, `0x08` | none |
| `ActuatorControlFrame` | `0x01`, `0x02`, `0x10` | `0x04`, `0x08` | none |

**Cleared Bits Downstream (Hold Rule):** A cleared bit means that the producer makes no new request for that field in this frame. Arbiters read the raw bits (§8.3). Every other consumer uses the last value that it received with the bit set. Before it receives such a value, the consumer uses the value from the latched frame in its init context (§6.2). For example, if an intent component emits only a longitudinal deceleration, the downstream controller keeps tracking the last lateral target.

### 5.1 Checkpoint 1: `IntentFrame`
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
| | `d_ref` | `float64` | $\text{m}$ | Target lateral offset from `target_lane_id` centerline. |
| | `path_points` | `Waypoint[64]` | $\text{m}, \text{rad}, \text{m}^{-1}$ | Array of $(X, Y, \psi_{\text{ref}}, \kappa_{\text{ref}})$ geometric path targets. |
| **Coupled Horizon** | `trajectory` | `TrajPoint[64]` | $\text{s}, \text{m}, \text{m/s}$ | Time-indexed array $(t_k, X_k, Y_k, \psi_k, v_k, a_k, \kappa_k)$. |
| **Auxiliary** | `turn_signal` | `enum` | — | `NONE` ($0$), `LEFT` ($1$), `RIGHT` ($2$), `HAZARD` ($3$). |

**Measured Gap for `GAP_PROFILE`:** `IntentFrame` carries the gap target and the desired gap. It does not carry the measured gap. A Stage 2 component that tracks `GAP_PROFILE` must declare a `SliceBuffer` input port whose slice type contains `tracks[]`. It reads the measured gap from the track whose `target_actor_id` equals `gap_target_actor_id`.

**Unsupported Modes:** If a Stage 2 component receives a `lon_mode` or `lat_mode` that it does not implement, `dl_do_step` returns `DL_STATUS_ERR_UNSUPPORTED_MODE`, and the runtime stops the scenario.

### 5.2 Checkpoint 2: `ControlFrame` (Strict Two-Tier Typing)

#### Tier A: `KinematicControlFrame`
| Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- |
| `actor_id` | `uint64` | — | Unique actor entity identifier. |
| `timestamp_ns` | `uint64` | $\text{ns}$ | Simulation timestamp. |
| `valid_mask` | `uint32` | bitmask | `0x01`: `a_lon_cmd` valid, `0x02`: `jerk_lon_cmd` valid, `0x04`: `steer_angle_cmd` valid, `0x08`: `steer_rate_cmd` valid. |
| `a_lon_cmd` | `float64` | $\text{m/s}^2$ | Commanded longitudinal acceleration at rear-axle origin in body $+x$. |
| `jerk_lon_cmd` | `float64` | $\text{m/s}^3$ | If `0x01` is also set, the maximum jerk used to reach `a_lon_cmd`. If only `0x02` is set, a jerk command that physics integrates. |
| `steer_angle_cmd` | `float64` | $\text{rad}$ | Front road-wheel steering angle target $\delta_{\text{cmd}}$ (valid if `0x04` set). |
| `steer_rate_cmd` | `float64` | $\text{rad/s}$ | If `0x04` is also set, the maximum rate used to reach `steer_angle_cmd`. If only `0x08` is set, a rate command that physics integrates. |

#### Tier B: `ActuatorControlFrame`
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
| `manual_gear_index` | `int8` | — | Explicit gear index ($1..10$, or $0$ for automatic selection in `DRIVE`). |

### 5.3 Checkpoint 3: `KinematicState` & Reference-Point Continuity
Produced by Stage 3 (Physical Compute) at the end of every simulation step $t + \Delta t$.

* **Resolution of Rear-Axle vs. CG Reference Point:** All pose and twist quantities (`position`, `v_lon`, `v_lat`, `a_lon`, `a_lat`) in `KinematicState` are measured at the **rear-axle reference origin** $(x_{\text{ra}}, y_{\text{ra}}, z_{\text{ra}})$. Simultaneously, `slip_angle_beta_cg` stores the sideslip angle at the **Center of Gravity (CG)** $\beta_{\text{cg}}$.
* **Rigid-Body Transform Between Rear Axle and CG:** Given rear-axle velocities $(v_{\text{lon}}, v_{\text{lat}})$ and yaw rate $\dot{\psi}$, the velocity and sideslip at the CG are related by exact rigid-body kinematics:
  $$v_{x,\text{cg}} = v_{\text{lon}}, \qquad v_{y,\text{cg}} = v_{\text{lat}} + l_r \dot{\psi}, \qquad \beta_{\text{cg}} = \arctan\!\left(\frac{v_{\text{lat}} + l_r \dot{\psi}}{v_{\text{lon}}}\right)$$
  For a non-slipping `KinematicBicycle` (`KS`), rear-axle lateral velocity is genuinely $v_{\text{lat}} = 0$, while yaw rate is $\dot{\psi} = \frac{v_{\text{lon}}}{L}\tan\delta$ and CG sideslip is $\beta_{\text{cg}} = \arctan\!\left(\frac{l_r}{L}\tan\delta\right) \ne 0$. Reporting rear-axle $v_{\text{lat}} = 0$ alongside the true $\dot{\psi}$ and $\beta_{\text{cg}}$ is physically consistent. It does not by itself make a Tier 0 $\leftrightarrow$ Tier 1/2 swap continuous. §6.2.4 defines which fields change during a swap and by how much.

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

---

## 6. Driveline Component Model (DCM) & Lifecycle

The **Driveline Component Model (DCM)** is a C-ABI (§7). Native components export the `dl_*` entry points. Components packaged as `.fmu` files export only standard FMI 3.0 functions, and the runtime master drives them as §6.3 describes.

### 6.1 Component Lifecycle State Machine

```text
                  ┌──────────────────────┐
                  │   1. Uninstantiated  │◄──────────────────────────┐
                  └──────────┬───────────┘                           │
                             │ dl_instantiate(abi, name, cb, &inst)  │
                             ▼                                       │
                  ┌──────────────────────┐                           │
                  │   2. Instantiated    │ dl_set_parameters(...)    │
                  └──────────┬───────────┘                           │
                             │ dl_configure_structure(inst, &cfg)    │
                             ▼                                       │
                  ┌──────────────────────┐                           │
                  │ 3. StructuralConfig  │                           │
                  └──────────┬───────────┘                           │
        ┌────────────────────┴────────────────────┐                  │
        │ At t = 0                                │ At t > 0         │
        │ dl_enter_cold_init(inst, M, ctx[])      │ dl_enter_warm_start(inst, M, ctx[])
        ▼                                         ▼                  │
┌──────────────────────┐                 ┌──────────────────────┐    │
│ 4a. ColdInitMode     │                 │ 4b. WarmStartMode    │◄─┐ │
│  (Coupled Trim)      │                 │ (Bumpless Transfer)  │  │ │
└───────┬──────────────┘                 └────────┬─────────────┘  │ │
        └────────────────────┬────────────────────┘                │ │
                             │ dl_exit_init_mode(inst)             │ │
                             ▼                                     │ │
                  ┌──────────────────────┐   re-trim (§6.2.4)      │ │
              ┌──►│     5. StepMode      │─────────────────────────┘ │
              │   └────┬────────────┬────┘◄──┐                       │
 dl_do_step() │        │            │        │ dl_on_membership_change(inst, &change)
   (Clocked)  └────────┘            └────────┘ (Actor Join / Leave on 1:N or N:N)
                             │                                       │
                             │ dl_terminate(inst)                    │
                             ▼                                       │
                  ┌──────────────────────┐                           │
                  │    6. Terminated     │───────────────────────────┘
                  └──────────────────────┘   dl_free_instance(inst)
```

### 6.2 Detailed Lifecycle Transition Rules

1. **`Instantiated` (`dl_instantiate`, `dl_set_parameters`):** `dl_instantiate` verifies `abi_version` and stores the host map callback table (`dl_host_map_callbacks_t`) and its `host_ctx`. The runtime then passes every component parameter from the DSL (for example `kp: 1.8` or `reaction_delay: 0.18s`) through `dl_set_parameters`, by name, in SI units. `dl_set_parameters` is valid in `Instantiated` and `StructuralConfig`. An unknown name or a wrong type returns `DL_STATUS_ERR_INVALID_ARG`.
2. **`StructuralConfig` (`dl_configure_structure`):** Passes the input port count, the per-port ring buffer capacities `port_history_depths[]`, and the bound actor count $M$ (`max_actors`). Multi-input components such as `BoschPCS_v4` get one depth per port, for example $N_0 = 8$ and $N_1 = 5$. Non-buffer ports have depth $0$.
3. **`ColdInitMode` (`dl_enter_cold_init` at $t = 0$), Coupled Trim Protocol:**
   The runtime initializes the pipeline in three passes. Each pass covers all actors in ascending `actor_id` order, and components within an actor in topological order.
   * **Pass 1 (Host Steady State & Tick 0 Sensor Projection):**
     1. For each actor, the host calls `frenet_to_world` at the spawn `(road_id, lane_id, s_0, d_0)`. It uses the returned `kappa_lane` as $\kappa_0$, so the curvature matches the lane the actor spawns in. It also reads the road grade $\theta_{\text{road}}$ and bank $\phi_{\text{road}}$ (sign conventions in §2).
     2. It sets $\dot{\psi}_0 = v_0 \kappa_0$ and solves the steady state of §6.4 for the tier of the actor's physics component. That solve gives $v_{\text{lat,ra}}$, $\delta_{\text{ss}}$, and $\beta_{\text{cg}}$.
     3. It computes static axle normal loads:
     $$F_{z,f} = m g \cos\theta_{\text{road}}\cos\phi_{\text{road}} \frac{l_r}{L} - m g \sin\theta_{\text{road}} \frac{h_{\text{cg}}}{L}, \qquad F_{z,r} = m g \cos\theta_{\text{road}}\cos\phi_{\text{road}} \frac{l_f}{L} + m g \sin\theta_{\text{road}} \frac{h_{\text{cg}}}{L}$$
     With the §2 sign convention, an uphill road ($\theta_{\text{road}} > 0$) moves load to the rear axle.
     4. If Tier 2 is populated, it sets `num_wheels = 4`, splits each axle load evenly between left and right wheels, and sets wheel speeds $\omega_{i,0} = v_0 / R_{\text{eff}}$. Otherwise it sets `num_wheels = 0`, and the `wheels[]` entries are unused.
     5. It fills each actor's `dl_init_context_t`. `chassis_state` holds the spawn pose, $v_0$, $\dot{\psi}_0$, $v_{\text{lat,ra}}$, $a_{\text{lat}} = v_0 \dot{\psi}_0$, `front_wheel_angle` $= \delta_{\text{ss}}$, and $\beta_{\text{cg}}$. `latched_intent` is `VELOCITY_TARGET` with `v_ref` $= v_0$ and `LANE_OFFSET` on the spawn lane with `d_ref` $= d_0$ (`valid_mask = 0x03`). `latched_kinematic_ctrl` has `a_lon_cmd` $= 0$ and `steer_angle_cmd` $= \delta_{\text{ss}}$ (`valid_mask = 0x05`). `latched_actuator_ctrl` has `steering_wheel_norm` $= \delta_{\text{ss}} / \delta_{\max}$ and `gear_mode = DRIVE` (`valid_mask = 0x14`).
     6. It runs sensor projection at $t = 0$. This projection is Tick 0's Phase 1. Tick 0 does not run Phase 1 again, so no buffer holds two samples at $t = 0$.
   * **Pass 2 (Stage 1 and Stage 2 Cold Init):** Stage 1 and Stage 2 components enter `dl_enter_cold_init`. Each component sets its internal state, such as integrators and filters, so that its output at $t = 0$ equals the latched frame of its output type. Longitudinal pedal trim for steady speed (drag and rolling resistance) is the job of the component that produces `ActuatorControlFrame`. After Pass 2, the runtime compares each Stage 2 output with the latched frame. If the road-wheel steering angles differ by more than $10^{-3}\text{ rad}$, the runtime logs `WARN_TRIM_MISMATCH` and continues.
   * **Pass 3 (Stage 3 Physics Trim):** Physics components enter `dl_enter_cold_init` and solve their internal states, such as suspension deflection $z_{i,0}$ and tire relaxation, at the Pass 1 steady state. Physics does not re-solve $\delta$. If Pass 2 logged no `WARN_TRIM_MISMATCH`, Tick 0 starts at the linear-tire steady state of §6.4. Otherwise the first ticks contain a transient.
4. **`WarmStartMode` (`dl_enter_warm_start` at $t > 0$), Fidelity Promotion & Demotion:**
   * **Promotion, Tier 0 (`KS`) $\rightarrow$ Tier 1/2 (`ST` / `MB`):** The runtime keeps the pose, $v_{\text{lon}}$, and $\dot{\psi}$. It solves the `ST` steady state of §6.4 at $(v_{\text{lon}}, \dot{\psi})$ and passes it to the incoming physics component. Three fields change: $v_{\text{lat,ra}}$ goes from $0$ to the solved value, `front_wheel_angle` goes from $\delta_{\text{KS}}$ to $\delta_{\text{ss}}$, and $\beta_{\text{cg}}$ follows from both. With linear tires, the lateral force and yaw moment of the incoming model are balanced at the first step.
   * **Demotion, Tier 1/2 $\rightarrow$ Tier 0:** The runtime keeps the pose, $v_{\text{lon}}$, and $\dot{\psi}$. It sets $v_{\text{lat,ra}} = 0$ and `front_wheel_angle` $= \delta_{\text{KS}} = \arctan(L \dot{\psi} / v_{\text{lon}})$. These two fields and $\beta_{\text{cg}}$ change.
   * **Re-Trim of Upstream Controllers:** A promotion or demotion changes `front_wheel_angle`. In the same inter-tick window, the runtime moves each Stage 2 component that feeds the new physics component from `StepMode` back into `WarmStartMode`. It passes `latched_kinematic_ctrl.steer_angle_cmd` $= $ the new `front_wheel_angle`, and it passes the matching `latched_actuator_ctrl`. Each re-trimmed component resets its internal state so that its next output equals the new steering angle. A component that cannot re-trim (a Mode B FMU, §6.3) gets `WARN_TRIM_MISMATCH`.
   * **Size of the Change:** For linear tires, $\delta_{\text{ss}} - \delta_{\text{KS}} \approx K_{\text{us}}\, v_{\text{lon}} \dot{\psi}$, where $K_{\text{us}} = \frac{m}{L}\left(\frac{l_r}{C_{\alpha f}} - \frac{l_f}{C_{\alpha r}}\right)$ is the understeer gradient. §6.4 gives a test vector.
   * **Full-Stack Bridge (`SensorBundle -> KinematicState`):** Allowed only as a static $t = 0$ actor binding, for replay actors or external HiL ego bridges. Splicing a `SensorBundle -> KinematicState` component at $t > 0$ is a compile-time error unless the scenario declares `allow_pose_override = true;`.
5. **Membership Mutation (`dl_on_membership_change`):** Actors can join or leave a $1\text{:}N$ or $N\text{:}N$ component at $t > 0$. `dl_membership_change_t` lists the full active actor set after the change and the init contexts of the added actors. An actor absent from the new active set has left. The component warm-starts each added actor's slot and does not reset the other members.

### 6.3 FMU Packaging (`org.driveline.dcm`)

A `component ... from_fmu("...")` declaration uses one of two modes. The compiler picks the mode from the declaration. A declaration with `bind_inputs` or `bind_outputs` blocks is Mode B. A declaration without them is Mode A.

* **Mode A (Driveline-Aware FMU):** The FMU implements the FMI 3.0 layered standard `org.driveline.dcm`. It ships a manifest at `extra/org.driveline.dcm/manifest.xml` that lists its Driveline ports. A Mode A declaration whose FMU has no manifest is a compile-time error.
  * Each checkpoint port is an `fmi3Binary` variable with MIME type `application/x-driveline.<checkpoint-type>;version=0.3`. The value is the §7 struct, byte for byte.
  * Each `SliceBuffer` port is an `fmi3Binary` variable with MIME type `application/x-driveline.slice-buffer.<slice-type>;version=0.3`. The value is a `dl_slice_buffer_header_t` followed by `count` entries, newest first. Each entry is a `uint64_t t_ns` followed by the slice struct.
  * Initialization uses the `fmi3Binary` input `dl_init_context` (MIME type `application/x-driveline.init-context;version=0.3`). The master sets it in initialization mode at $t = 0$ for cold init and at $t = t_{\text{splice}}$ for warm start. `is_warm_start` tells the two apart.
  * Component parameters are FMI parameters with the same names.
  * Mode A FMUs are $1\text{:}1$ only. They cannot be bound to a group.
* **Mode B (Scalar-Pin FMU):** A legacy FMU with scalar `Float64` pins. `bind_inputs` maps `SliceBuffer` expressions onto input pins. `bind_outputs` maps output pins onto a checkpoint frame. Cold init uses the FMU's own start values. Splicing a Mode B FMU at $t > 0$ uses the first case that applies:
  1. **Restore a Saved State:** If this FMU instance was spliced out earlier in the same run, and the FMU declares `canGetAndSetFMUState="true"`, the master saved its state with `fmi3GetFMUState` at splice-out. The master restores that state with `fmi3SetFMUState`. The restored state is from the splice-out time, not the current time. The master logs `WARN_FMU_COLD_SPLICE`.
  2. **Cold Splice:** Otherwise the master calls `fmi3Reset`, or creates a new instance, and sets the input start values by evaluating `bind_inputs` at $t_{\text{splice}}$. It then calls `fmi3EnterInitializationMode` with `startTime` $= t_{\text{splice}}$, then `fmi3ExitInitializationMode`, and logs `WARN_FMU_COLD_SPLICE`.

  A Mode B FMU cannot be re-trimmed (§6.2.4). An FMU state saved with `fmi3GetFMUState` is opaque, so the master cannot build one from `dl_init_context_t`.

### 6.4 Steady-State Cornering Solution

Cold init (§6.2.3) and promotion and demotion (§6.2.4) use one steady-state solution. The inputs are $v = v_{\text{lon}}$, the yaw rate $\dot{\psi}$, and the physics tier. The lateral acceleration is $a_y = v \dot{\psi}$.

* **Tier 0 (`KS`), and every tier when $|v| < 1.0\text{ m/s}$:** $v_{\text{lat,ra}} = 0$, $\delta_{\text{ss}} = \delta_{\text{KS}} = \arctan(L \dot{\psi} / v)$, and $\delta_{\text{ss}} = 0$ when $v = 0$. The slip-angle formulas below are singular as $v \to 0$, so the kinematic solution applies at low speed.
* **Tier 1 and Tier 2 (`ST`, `MB`), linear tires:**
  $$F_{yf} = m a_y \frac{l_r}{L}, \quad F_{yr} = m a_y \frac{l_f}{L}, \quad \alpha_f = \frac{F_{yf}}{C_{\alpha f}}, \quad \alpha_r = \frac{F_{yr}}{C_{\alpha r}}$$
  $$v_{\text{lat,ra}} = -v \tan\alpha_r, \qquad \delta_{\text{ss}} = \alpha_f + \arctan\!\left(\frac{v_{\text{lat,ra}} + L \dot{\psi}}{v}\right), \qquad \beta_{\text{cg}} = \arctan\!\left(\frac{v_{\text{lat,ra}} + l_r \dot{\psi}}{v}\right)$$
  At this state the axle forces sum to $m a_y$ and the yaw moment $l_f F_{yf} - l_r F_{yr}$ is zero. Models with nonlinear tires, or with a Tier 3 deck, may refine the solution in their own trim. They must keep $v_{\text{lon}}$ and $\dot{\psi}$.
* **Test Vector (`Sedan_2026`, §10.2):** $v = 28.0\text{ m/s}$ and $\dot{\psi} = 0.056\text{ rad/s}$ (radius $500\text{ m}$) give $a_y = 1.568\text{ m/s}^2$, $v_{\text{lat,ra}} = -0.3728\text{ m/s}$, $\delta_{\text{KS}} = 0.00560\text{ rad}$, $\delta_{\text{ss}} = 0.01015\text{ rad}$, and $\beta_{\text{cg}} = -0.01022\text{ rad}$. Keeping $\delta_{\text{KS}}$ with this $v_{\text{lat,ra}}$ would leave the front axle about 25% short of its steady-state force.

---

## 7. Normative C-ABI Header (`driveline_abi.h`)

All structs in `driveline_abi.h` use fixed-width types and explicit padding, so the compiler inserts no padding. Data structs contain no pointers: vehicle parameters, sensor slices, checkpoint frames, `dl_route_t`, and `dl_init_context_t`. Their layout is identical on 32-bit and 64-bit targets, and Mode A FMUs exchange them byte for byte (§6.3). Call descriptors (`dl_slice_buffer_view_t`, `dl_batch_step_io_t`, `dl_membership_change_t`, `dl_structural_config_t`) and the callback table contain pointers. They are valid only inside one process.

```c
#ifndef DRIVELINE_ABI_H
#define DRIVELINE_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 8)

#define DL_ABI_VERSION_0_3 0x00000300U

typedef enum {
    DL_STATUS_OK              = 0,
    DL_STATUS_WARN_UNDERFLOW  = 1,
    DL_STATUS_WARN_COLD_FMU   = 2,
    DL_STATUS_WARN_TRIM_MISMATCH = 3,
    DL_STATUS_ERR_INVALID_ARG = -1,
    DL_STATUS_ERR_TIER_MISSING= -2,
    DL_STATUS_ERR_NUMERIC     = -3,
    DL_STATUS_ERR_UNSUPPORTED_MODE = -4
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
    double max_drive_torque;                     /* Engine/motor shaft peak [N*m] */
    double max_brake_torque;                     /* Sum over wheels, at wheels [N*m] */
    double final_drive_ratio;                    /* i_fd [-] */
    double gear_ratios[10];                      /* Forward gears 1..10 [-] */
    uint32_t num_gears, _pad;
} dl_multibody_params_t;

typedef struct {
    uint8_t  deck_type;        /* 0:NONE, 1:PACEJKA_TIR, 2:SOLVER_URI */
    uint8_t  precedence_mode;  /* 0:SUPPLEMENT_ONLY, 1:OVERRIDE_TIER1_2 */
    uint16_t _pad;
    uint32_t _pad2;
    char     uri[256];         /* Null-terminated path or URI */
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
 * 2. MAP REFERENCES, PRIORS, & PERCEPTION SLICE CONTRACTS
 * ========================================================================== */

typedef struct {
    char     road_id[64];
    int32_t  lane_id;
    uint32_t _pad;
} dl_lane_ref_t;

typedef struct {
    uint32_t      count;                         /* Valid entries in nodes[] */
    uint32_t      _pad;
    dl_lane_ref_t nodes[64];
} dl_route_t;

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

typedef struct {
    dl_visual_slice_t  visual;
    dl_radar_slice_t   radar;
    dl_camera_slice_t  camera;
    dl_surface_slice_t surface;
} dl_sensor_bundle_t;

/* Serialized SliceBuffer prefix. Followed by count entries, newest first.
 * Each entry is uint64_t t_ns followed by the slice struct. */
typedef struct {
    uint32_t capacity;                           /* N */
    uint32_t count;                              /* Valid entries, <= N */
    uint32_t entry_size;                         /* 8 + sizeof(slice struct) */
    uint32_t _pad;
} dl_slice_buffer_header_t;

/* In-process ring view. Entry k (k = 0 newest) starts at
 * entries + ((head + capacity - k) % capacity) * entry_size. */
typedef struct {
    dl_slice_buffer_header_t hdr;
    uint32_t       head;                         /* Slot of the newest entry */
    uint32_t       _pad;
    const uint8_t* entries;
} dl_slice_buffer_view_t;

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
    uint32_t abi_version;                        /* Must equal DL_ABI_VERSION_0_3 */
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

/* One input port, one entry per actor. kind 0: frame or prior struct.
 * kind 1: dl_slice_buffer_view_t. */
typedef struct {
    const void*    data;                         /* Array [actor_count] */
    uint32_t       stride;                       /* Bytes between actor entries */
    uint32_t       kind;
} dl_port_io_t;

/* Step I/O for every cardinality. A 1:1 component has actor_count = 1. */
typedef struct {
    uint64_t            sim_time_ns;
    uint64_t            dt_step_ns;
    uint32_t            actor_count;             /* Active actors M */
    uint32_t            num_inputs;              /* Declared input port count */
    const uint64_t*     actor_ids;               /* Array [actor_count], ascending */
    const dl_port_io_t* inputs;                  /* Array [num_inputs], declared order */
    void*               outputs;                 /* Array [actor_count] of output frames */
    uint32_t            output_stride;
    uint32_t            _pad;
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

/* host_ctx is passed back unchanged as the first argument of every callback. */
typedef struct {
    void* host_ctx;

    dl_status_t (*world_to_frenet)(void* host_ctx,
        double X, double Y, double psi, const char* hint_road_id,
        char out_road_id[64], int32_t* out_lane_id, double* out_s, double* out_d, double* out_psi_lane);

    dl_status_t (*frenet_to_world)(void* host_ctx,
        const char* road_id, int32_t lane_id, double s, double d,
        double* out_X, double* out_Y, double* out_Z, double* out_psi_lane, double* out_kappa_lane);

    dl_status_t (*sample_lane_path)(void* host_ctx,
        const char* road_id, int32_t lane_id, double s_start, double d_offset,
        double ds, uint32_t count, dl_waypoint_t* out_waypoints);

    /* Writes up to max_successors successors; *out_num_successors is the total. */
    dl_status_t (*query_lane_topology)(void* host_ctx,
        const char* road_id, int32_t lane_id,
        int32_t* out_left_lane_id, int32_t* out_right_lane_id,
        uint32_t max_successors, dl_lane_ref_t* out_successors,
        uint32_t* out_num_successors);
} dl_host_map_callbacks_t;

typedef struct {
    uint32_t        max_actors;                  /* M (1 for 1:1, N for 1:N / N:N) */
    uint32_t        num_input_ports;
    const uint32_t* port_history_depths;         /* Array [num_input_ports]; 0 = not a buffer */
} dl_structural_config_t;

typedef struct {
    char     name[56];                           /* Null-terminated DSL parameter name */
    uint32_t type;                               /* 0: f64 (SI), 1: i64 */
    uint32_t _pad;
    double   f64;
    int64_t  i64;
} dl_param_t;

/* Normative C-ABI Lifecycle Entry Points */
dl_status_t dl_instantiate(uint32_t abi_version, const char* instance_name, const dl_host_map_callbacks_t* callbacks, dl_component_handle_t* out_inst);
dl_status_t dl_set_parameters(dl_component_handle_t inst, const dl_param_t* params, uint32_t count);
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

1. **Sequential Chaining (`>>`):** Connects $A: T_1 \rightarrow T_2$ and $B: T_2 \rightarrow T_3$ into $A \gg B: T_1 \rightarrow T_3$. A component's cardinality is `OneToOne` unless its declaration (`cardinality:` clause, §10.1) or its library manifest says otherwise. When a `OneToMany` component feeds $M$ actors into a `OneToOne` downstream component (e.g., `PincerHiveMind >> kinematic_coupled_control()`), the runtime creates $M$ independent instances of the downstream chain, one per bound actor.
2. **Parallel Split-Merge Operator (`+`):** For $T$ equal to `IntentFrame` or `KinematicControlFrame`, the partial types `Lon<T>` and `Lat<T>` are frames of type $T$ restricted to the `LON` or `LAT` field group of §5. A component with output type `Lon<T>` may set only `LON` bits, and the runtime clears any other bits it sets. `Lat<T>` works the same way.
   * **Typing:** $(A + B)$ requires one branch of type $T_{\text{in}} \rightarrow$ `Lon<T>` and one branch of type $T_{\text{in}} \rightarrow$ `Lat<T>`, in either order. The result has type $T_{\text{in}} \rightarrow T$. Two `LON` branches, two `LAT` branches, or more than two branches are compile-time errors, so the two branches can never write the same field.
   * **Evaluation:** The runtime passes the same $T_{\text{in}}$ to both branches. The merged frame takes `LON` fields from the `Lon` branch and `LAT` fields from the `Lat` branch, with `valid_mask = (lon.valid_mask & LON) | (lat.valid_mask & LAT)`. A `+` merge never sets `COUPLED` bits.
   * **Chaining Within a Branch:** A branch can chain partial types, for example `PIDSpeedController: IntentFrame -> Lon<KinematicControlFrame>` followed by `JerkLimiter: Lon<KinematicControlFrame> -> Lon<KinematicControlFrame>`.
3. **Multi-Chain Arbitration (`Arbitrate`):** Merges two parallel chains producing the same checkpoint type $T_{\text{check}}$ (`IntentFrame`, `KinematicControlFrame`, or `ActuatorControlFrame`) via an explicit `Arbiter` component. Arbiters read raw `valid_mask` bits and do not apply the hold rule of §5. For example, `BrakeOverrideArbiter` uses the secondary's `throttle` and `brake` when `secondary.valid_mask & 0x02` is set. It passes `primary.steering_wheel_norm` through whenever `secondary.valid_mask & 0x04 == 0`.
4. **Type-Safe Splicing:** When the runtime splices a component or sub-chain $C_{\text{new}}: T_{\text{in}} \rightarrow T_{\text{out}}$ into an actor's pipeline at $t > 0$, it matches $(T_{\text{in}}, T_{\text{out}})$ against the replaced sub-chain. It moves the outgoing sub-chain to `Terminated`, initializes $C_{\text{new}}$ through `WarmStartMode` (§6.2.4), and swaps the two between ticks. Appendix A lists the DSL syntax for splice triggers as an open item.
5. **Physics Assignment Rule:** Each actor gets exactly one Stage 3 physics component, from either its `physics` declaration or one `bind` statement. An actor with zero or two physics components is a compile-time error.

---

## 9. Deterministic Integer-Tick Execution Model

1. **Integer Nanosecond Base Clock & Tick Divisors:** The simulation clock advances by integer tick index $k_{\text{tick}} \in \{0, 1, 2, \dots\}$ with base period $\Delta t_{\text{base\_ns}} \in \mathbb{Z}^+$ nanoseconds ($t_{\text{ns}} = k_{\text{tick}} \cdot \Delta t_{\text{base\_ns}}$).
   * **Exact Rate Divisibility Rule:** A sensor or component rate $f_{\text{comp}}$ is valid only if some positive integer $k_{\text{div}}$ satisfies $k_{\text{div}} \cdot \Delta t_{\text{base\_ns}} \cdot f_{\text{comp}} = 10^9$ exactly. The compiler checks this rule with exact rational arithmetic. Any other rate (such as `30Hz` on a `500Hz` base clock) is a **compile-time error**.
   * **Default Component Rate:** Any component that omits a `(rate: ...)` clause inherits the base clock rate ($k_{\text{div}} = 1$).
   * **Scheduling Rule:** A component with divisor $k_{\text{div}}$ executes on tick $k_{\text{tick}}$ if and only if $(k_{\text{tick}} \bmod k_{\text{div}}) == 0$, and holds its output constant via Zero-Order Hold (ZOH) on intermediate ticks.
2. **Phases Within a Tick:** Each tick runs four phases in this order:
   1. **Phase 1 (Sensor Projection):** Scheduled sensors project World state $X(t)$ into each actor's `SliceBuffer`s. Tick 0 skips Phase 1 because cold initialization Pass 1 has done it (§6.2.3).
   2. **Phase 2 (Intent, Control, & Arbitration):** Scheduled Stage 1, Stage 2, and Arbiter components step.
   3. **Phase 3 (Physics):** Scheduled Stage 3 components compute $X(t + \Delta t)$.
   4. **Phase 4 (World Commit & Termination Check):** The runtime commits $X(t + \Delta t)$, updates cached Frenet coordinates, and evaluates `terminate when`.
3. **Deterministic Intra-Phase Ordering & Seeding:**
   * Within Phase 1, Phase 2, and Phase 3, actors and $1\text{:}N$ groups are evaluated in ascending order of `actor_id` (and topological chain order within each actor). A group sorts by its smallest member `actor_id`. Because Phase 2 components only read Phase 1 `SliceBuffer` snapshots from $X(t)$ and write to actor-local checkpoint buffers, Phase 2 is data-race-free and parallelizable across actors.
   * Each stochastic sensor gets a 64-bit seed per tick: `SipHash-2-4(key, msg)`. The 128-bit `key` is `scenario_seed` as a little-endian `uint64` followed by 8 zero bytes. The 24-byte `msg` is `actor_id` (little-endian `uint64`), `sensor_port_index` (little-endian `uint32`), 4 zero bytes, and `k_tick` (little-endian `uint64`). The sensor's random generator algorithm is part of the sensor's versioned implementation.
4. **Determinism Guarantee & Scope:**
   * **Same Build, Same Platform:** A compliant runtime produces bit-identical results for the same scenario, seed, runtime build, component binaries, and platform.
   * **Across Platforms:** Bit-identical results across platforms or compilers are guaranteed only if the runtime and every component meet three conditions. They use one correctly rounded math library for transcendental functions (`sin`, `atan`, `exp`, and the rest), because platform `libm` implementations differ in the last bit. They are compiled without fast-math and without floating-point contraction (`-ffp-contract=off`), so no compiler fuses operations into FMA. They use IEEE 754 binary64 arithmetic with round-to-nearest-even.
   * **External Components:** FMUs and ONNX models must run single-threaded. ONNX Runtime components run on the CPU execution provider with `ORT_SEQUENTIAL` and one intra-op thread. GPU inference is not compliant in this version.

---

## 10. Normative EBNF Grammar & Reference Scenario

### 10.1 Complete EBNF Grammar
```ebnf
ScenarioFile     ::= ImportDecl* VehicleSpecDecl* (ComponentDecl | FnDecl)* ScenarioDecl
ImportDecl       ::= "use" ScopedIdent "::" "{" IdentList "}" ";"
VehicleSpecDecl  ::= "vehicle_spec" Ident "{" (Ident "=" Expr ";")* "}"

ComponentDecl    ::= "component" Ident FmuClause? RateClause? TierClause? CardinalityClause? ":" "(" PortList? ")" "->" TypeSpec (Block | ";")
FmuClause        ::= "from_fmu" "(" StringLit ")"
RateClause       ::= "(" "rate" ":" FreqLit ")"
TierClause       ::= "(" "required_tier" ":" IntLit ")"
CardinalityClause::= "(" "cardinality" ":" ("OneToOne" | "OneToMany" | "ManyToMany") ")"
PortList         ::= PortDecl ("," PortDecl)*
PortDecl         ::= (Ident ":")? TypeSpec
TypeSpec         ::= Ident ("<" TypeSpec ("," (TypeSpec | IntLit))* ">")?

FnDecl           ::= "fn" Ident "(" PortList? ")" "->" TypeSpec "{" "return" PipeExpr ";" "}"
Block            ::= "{" (ParamDecl | BindInputsBlock | BindOutputsBlock | StepBlock)* "}"
ParamDecl        ::= "param" Ident ":" TypeSpec "=" Expr ";"
BindInputsBlock  ::= "bind_inputs" "{" (StringLit "=" Expr ";")* "}"
BindOutputsBlock ::= "bind_outputs" "->" TypeSpec "{" (Ident "=" Expr ";")* "}"
StepBlock        ::= "step" "(" PortList ")" "->" TypeSpec "{" Stmt* "}"

ScenarioDecl     ::= "scenario" Ident "{" WorldStmt* ActorDecl* BindStmt* TerminateStmt "}"
WorldStmt        ::= ("map" "=" Expr ";") | ("timestep" "=" TimeLit ";") | ("seed" "=" IntLit ";")
                   | ("allow_pose_override" "=" BoolLit ";") | EnvBlock | StaticObjDecl
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
PrimaryPipe      ::= CallExpr | "(" PipeExpr ("+" PipeExpr)* ")" | ArbitrateExpr | Ident
ArbitrateExpr    ::= "Arbitrate" "(" PipeExpr "," PipeExpr "," "via" ":" CallExpr ")"
TerminateStmt    ::= "terminate" "when" "(" Expr ")" ";"

Stmt             ::= LetStmt | IfStmt | ReturnStmt
LetStmt          ::= "let" Ident "=" Expr ";"
IfStmt           ::= "if" Expr "{" Stmt* "}" ("else" "{" Stmt* "}")?
ReturnStmt       ::= "return" Expr ";"

Expr             ::= AndExpr ("or" AndExpr)*
AndExpr          ::= NotExpr ("and" NotExpr)*
NotExpr          ::= "not" NotExpr | CmpExpr
CmpExpr          ::= AddExpr (("<" | "<=" | ">" | ">=" | "==" | "!=") AddExpr)?
AddExpr          ::= MulExpr (("+" | "-") MulExpr)*
MulExpr          ::= UnaryExpr (("*" | "/") UnaryExpr)*
UnaryExpr        ::= "-" UnaryExpr | PostfixExpr
PostfixExpr      ::= PrimaryExpr ("." Ident | "(" ArgList? ")" | "[" Expr "]")*
PrimaryExpr      ::= Literal | ScopedIdent | "(" Expr ")" | ArrayLit | RecordLit
ArrayLit         ::= "[" (Expr ("," Expr)*)? "]"
RecordLit        ::= "{" (Ident ":" Expr ("," Ident ":" Expr)*)? "}"
CallExpr         ::= ScopedIdent "(" ArgList? ")"
ArgList          ::= Arg ("," Arg)*
Arg              ::= (Ident ":")? Expr
ScopedIdent      ::= Ident ("::" Ident)*
IdentList        ::= Ident ("," Ident)*
Literal          ::= QuantityLit | FloatLit | HexLit | IntLit | StringLit | BoolLit
BoolLit          ::= "true" | "false"
```

**Lexical Rules:**
* `Ident` is `[A-Za-z_][A-Za-z0-9_]*` and is not a reserved word. The reserved words are `use`, `fn`, `component`, `scenario`, `actor`, `let`, `if`, `else`, `return`, `or`, `and`, `not`, `true`, `false`, and `Arbitrate`. Every other quoted word in the grammar is a contextual keyword. It is a keyword only where the grammar expects it and is an `Ident` elsewhere, so `rate: 20Hz` in a sensor call and `std::physics` in an import are valid.
* `IntLit` is `[0-9]+`. `HexLit` is `0x[0-9A-Fa-f]+`. `FloatLit` is `[0-9]+ "." [0-9]+`. `StringLit` is a double-quoted string with `\"` and `\\` escapes.
* `QuantityLit ::= (FloatLit | IntLit) UnitExpr`, with no whitespace anywhere inside it. `UnitExpr ::= UnitAtom (("*" | "/") UnitAtom)*` and `UnitAtom ::= UnitName ("^" [0-9]+)?`. `UnitName` is one of `m`, `s`, `ms`, `us`, `ns`, `kg`, `N`, `Pa`, `rad`, `deg`, `Hz`. The lexer takes the longest match, and a `QuantityLit` must not be followed directly by a letter, digit, or `_`. So `0.45rad/s` and `2850.0kg*m^2` are single tokens. To divide a quantity by a variable named `s`, write spaces: `2.0m / s`.
* `FreqLit` is a `QuantityLit` whose unit is `Hz`. `TimeLit` is a `QuantityLit` whose unit is `s`, `ms`, `us`, or `ns`.
* `//` starts a comment that runs to the end of the line. Whitespace separates tokens and is otherwise ignored.

### 10.2 Normative Reference Scenario (`kanagawa_pinch_test.dline`)
This scenario parses under the §10.1 grammar. Its port capacities, clock divisors, parameter tiers, and control-to-physics connections follow the rules of Sections 1–9. The map `kanagawa_expressway.xodr` uses `rule="LHT"`, so positive lanes drive toward increasing $s$ (§2).

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
        max_drive_torque: 320.0N*m, max_brake_torque: 6500.0N*m,
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
            // Sets LON bits only. Downstream keeps the last lateral target (hold rule, §5).
            return IntentFrame::decelerate(a_ref: -5.5m/s^2);
        } else {
            return IntentFrame::follow_route(route: route, v_ref: desired_speed);
        }
    }
}

// Mode A FMU (ships the org.driveline.dcm manifest, no bind blocks)
component HumanControl from_fmu("fmus/HumanDriverControl.fmu") (rate: 100Hz) (required_tier: 0): (
    intent: IntentFrame
) -> ActuatorControlFrame;

// Mode B scalar-pin FMU. Target and range-rate validity go to the FMU as pins.
// Brake normalization assumes 120 bar corresponds to max_brake_torque.
component BoschPCS_v4 from_fmu("fmus/BoschPCS_v4.fmu") (rate: 50Hz) (required_tier: 0): (
    radar:  SliceBuffer<RadarSlice, 8>,
    camera: SliceBuffer<CameraSlice, 5>
) -> ActuatorControlFrame {
    bind_inputs {
        "Radar_TargetValid" = select(radar.latest().has_primary_target == 1, 1.0, 0.0);
        "Radar_Range_m"     = radar.latest().primary_range;
        "Radar_RangeRate"   = radar.rate_of(primary_range, window: 1).value;
        "Radar_RateValid"   = select(radar.rate_of(primary_range, window: 1).valid, 1.0, 0.0);
        "Cam_ObstacleConf"  = camera.latest().obstacle_confidence;
    }
    bind_outputs -> ActuatorControlFrame {
        valid_mask          = select(fmu.out("AEB_Active") > 0.5, 0x03, 0x00);
        throttle            = 0.0;
        brake               = clamp(fmu.out("AEB_BrakePressure_Pa") / 12000000.0, 0.0, 1.0);
        steering_wheel_norm = 0.0;
        gear_mode           = GearMode::DRIVE;
    }
}

// Tier A control chain for the Tier 0 KinematicBicycle challengers.
// Lon branch: PIDSpeedController (VELOCITY_TARGET only) >> JerkLimiter, both Lon<KinematicControlFrame>.
// Lat branch: StanleyLat, Lat<KinematicControlFrame>.
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
    actor ego = spawn(id: 1, spec: Sedan_2026, road: "road_10", lane: 2, s: 15.0m, v: 28.0m/s) with {
        priors {
            nav_route = RouteNodes(["road_10:2", "road_40:1", "road_11:2"]); // road_40: junction connecting road
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
    actor blocker = spawn(id: 2, spec: Sedan_2026, road: "road_10", lane: 1, s: 30.0m, v: 26.0m/s) with {
        sensors {
            surround = SurroundVisualSensor(range: 150.0m, rate: 25Hz, history: 5);
        }
    };

    actor challenger = spawn(id: 3, spec: Sedan_2026, road: "road_10", lane: 3, s: 35.0m, v: 25.0m/s) with {
        sensors {
            surround = SurroundVisualSensor(range: 150.0m, rate: 25Hz, history: 5);
        }
    };

    // PincerHiveMind is OneToMany (library manifest). Its vision port gets one buffer
    // per bound actor. It emits VELOCITY_TARGET + LANE_OFFSET intents only.
    bind [blocker, challenger] -> PincerHiveMind(
                                      vision: [blocker.sensors.surround, challenger.sensors.surround],
                                      target_actor_id: ego.id,
                                      pinch_gap: 12.0m
                                  )
                               >> kinematic_coupled_control()
                               >> KinematicBicycle();

    terminate when (sim_time > 25.0s or collision(ego, any) or ego.state.v_lon < 0.1m/s);
}
```
---

## Appendix A. Open Items

These items are unresolved in v0.3.

**External facts to check against the current standard documents:**
* ASAM OSI message names and the slice mappings in §4.3.
* The mapping from Tiers 0–2 to CommonRoad parameter sets (§1.2). CommonRoad may define cornering stiffness differently from `cornering_stiffness_f` in N/rad.
* OpenDRIVE `rule` semantics for lane driving direction (§2).
* The FMI 3.0 layered-standard file location `extra/<name>/` and the `fmi3Reset` and `fmi3GetFMUState` behavior that §6.3 relies on.
* The §1.2 statement that OpenSCENARIO leaves controller and vehicle-dynamics models to the host simulator.

**Design items:**
* The DSL has no syntax for splice triggers (§8.4).
* Native components cannot run out of process. Only Mode A FMUs (§6.3) have a serialized port encoding.
* `RadarSlice` has no primary target ID. `rate_of(primary_range)` returns a wrong rate on the tick where the primary target changes.

## Appendix B. Changes From v0.2

* Removed the `[cite: 1]` tags and rewrote the related-work claims as scope statements (§1.2).
* Added sign conventions for road grade and bank, spawn heading from the OpenDRIVE `rule` attribute, a lane reference string format, and nanosecond `Time` (§2).
* Defined `max_drive_torque` at the engine or motor shaft and `max_brake_torque` as the wheel total. Tier 3 decks are referenced by `uri` only (§3). Set `SimpleDrivetrain` to output `KinematicControlFrame` (§3.1).
* Changed `Timestamped<T>` to integer nanoseconds. Added the timestamp invariant, `Rate` validity for `rate_of`, and interpolation classes per field (§4).
* Added field groups, the hold rule for cleared bits, rules for combining steering and jerk bits, and `GAP_PROFILE` measurement rules (§5).
* Replaced the promotion formula with a steady-state solve that balances force and yaw moment, with a test vector (§6.4). Added demotion and controller re-trim (§6.2.4). Removed the double Tick 0 sensor projection and the $R_{\text{nom}}$ default (§6.2.3).
* Separated the native C-ABI from FMU packaging, and rewrote the Mode B warm-start fallback so that it relies only on standard FMI calls (§6.3).
* ABI v0.3 (§7): `dl_set_parameters`, a `host_ctx` for callbacks, successor lists, typed per-port step I/O, the SliceBuffer layout, `dl_route_t`, `dl_sensor_bundle_t`, and two new status codes.
* Made `+` a typed merge of `Lon<T>` and `Lat<T>`, restored splicing, and added the physics assignment rule (§8).
* Restored the four tick phases, defined the SipHash-2-4 encoding, and narrowed the determinism guarantee (§9).
* Added expression and lexical grammar, grouping parentheses, and a cardinality clause (§10.1). Moved the reference scenario to LHT lanes and fixed its Bosch bindings and hard-coded actor ID (§10.2).
