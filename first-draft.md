# Driveline Scenario Description Language & Component Architecture
**Formal Specification — Draft v0.1**
* **File Extensions:** `.dline`, `.dl`
* **Binary Interface Baseline:** FMI 3.0 Co-Simulation Superset (`driveline_abi.h`)

---

## 1. Scope & Architectural Principles

**Driveline** is a deterministic, component-first scenario description language and execution architecture for road-driving simulation. It eliminates the kinematic ambiguity and simulator lock-in of existing scenario standards by separating ground-truth world physics from per-actor behavioral, control, and physical compute pipelines.

1. **Strict World vs. Actor Encapsulation:** The `scenario` block owns only ground-truth physical reality—road network topology, spatial surface friction $\mu(x,y)$, static obstacles, initial actor spawn states, and physical termination predicates. Behavioral reflexes (such as Time-To-Collision thresholds or gap acceptance) are forbidden at the scenario level and must reside inside actor-mounted components.
2. **Typed Dataflow Chains Over Rigid Slots:** An actor's motion pipeline is a strictly typed Directed Acyclic Graph (DAG) of signal transformers connected via the pipe operator (`>>`). Rather than enforcing rigid container slots, **Intent**, **Control**, and **Physics** are defined as **Canonical Checkpoint Types** along the chain:
   $$\text{SensorSlice} \xrightarrow{f_1} \text{IntentFrame} \xrightarrow{f_2} \text{ControlFrame} \xrightarrow{f_3} \text{KinematicState}$$
3. **Zero Implicit Control Glue:** The runtime prohibits hidden controller conversions (such as implicit proportional gains or unparameterized pedal maps) between mismatched components. All cross-tier conversions must be declared as explicit, parameterized adapter blocks in the chain, while pure geometric map queries (such as sampling an OpenDRIVE lane centerline into waypoints) are provided as deterministic host map utilities.
4. **Extended FMI 3.0 Component Model & Cardinality Agnosticism:** Driveline standardizes port data contracts and lifecycle state machines rather than internal component implementations, allowing native DSL state trees, Behavior Trees, ONNX neural networks, Simulink FMUs, or C++ binaries to be swapped freely. Components support $1\text{:}1$ per-actor bindings, $1\text{:}N$ centralized coordination ("Hive Mind" intent), and $N\text{:}N$ vectorized execution (batch physics).

---

## 2. Global Units & Coordinate Conventions

All compliant runtimes and components must enforce the following mathematical conventions at every port boundary:

* **SI Units:** Distance in meters ($\text{m}$), time in seconds ($\text{s}$), mass in kilograms ($\text{kg}$), force in newtons ($\text{N}$), torque in newton-meters ($\text{N}\cdot\text{m}$), angles in radians ($\text{rad}$), velocity in meters per second ($\text{m/s}$), acceleration in meters per second squared ($\text{m/s}^2$), and jerk in meters per second cubed ($\text{m/s}^3$). Angles are counter-clockwise positive and normalized to the interval $(-\pi, \pi]$.
* **Inertial World Frame (ISO 8855):** Right-handed Cartesian coordinate system $(X, Y, Z)$ aligned with the underlying OpenDRIVE inertial frame ($+X$ East, $+Y$ North, $+Z$ Up).
* **Vehicle Body Frame (ISO 8855):** Orthogonal right-handed frame anchored to the vehicle with $+x$ longitudinal forward, $+y$ lateral left, and $+z$ vertical up.
* **Actor Reference Origin:** Standardized at the **center of the rear axle projected onto the ground plane**, with the Center of Gravity (CG) offsets $(l_f, l_r, h_{\text{cg}})$ stored in the actor's static vehicle specification.
* **Road Frenet Frame $(s, d)$:** Arc-length $s$ ($\text{m}$) measured along the reference OpenDRIVE lane centerline, and orthogonal lateral offset $d$ ($\text{m}$) positive to the left.

---

## 3. Stratified Vehicle Parameter Specification (`vehicle_spec`)

To scale seamlessly from 1D point-mass background traffic to 29-DOF multi-body vehicle dynamics without duplicating parameters across blocks, Driveline defines a four-tier hierarchical parameter model attached to the actor entity:

| Tier | C-ABI Struct | Target Fidelity Models | Standardized Parameters |
| :--- | :--- | :--- | :--- |
| **Tier 0** *(Mandatory Base)* | `dl_kinematic_params_t` | Point-Mass, Kinematic Bicycle (`KS`), Path Trackers (`Stanley`, `PurePursuit`) | Bounding box $(L, W, H)$, `wheelbase` $L$, front/rear overhangs, `max_steer_angle` $\delta_{\max}$, `max_steer_rate` $\dot{\delta}_{\max}$, `steering_ratio`. |
| **Tier 1** *(Dynamic Single-Track)* | `dl_single_track_params_t` | Dynamic Single-Track (`ST`), Linear/Nonlinear Tire Slip Models, MPC Controllers | Total `mass` $m$, CG coordinates $(l_f, l_r, h_{\text{cg}})$, yaw polar inertia $I_{zz}$, linear cornering stiffness $(C_{\alpha f}, C_{\alpha r})$, aero drag $(C_d, A_f)$, rolling resistance $C_{rr}$. |
| **Tier 2** *(Multi-Body & Powertrain)* | `dl_multibody_params_t` | 14-DOF / 29-DOF Multi-Body (`MB`), Full Powertrain & Brake Hydraulics | Sprung vs. unsprung mass $(m_s, m_{uf}, m_{ur})$, $3\times 3$ inertia tensor $[I_{xx}, I_{yy}, I_{zz}, I_{xz}]$, track widths $(t_f, t_r)$, suspension stiffness/damping $(K_s, C_s)$, anti-roll stiffness $K_{\text{arb}}$, effective tire radius $R_{\text{eff}}$, wheel polar inertia $I_w$, gear ratios, max propulsion torque, max brake torque. |
| **Tier 3** *(External Solver Deck)* | `dl_custom_deck_t` | IPG CarMaker, Adams/Car, Pacejka `.tir`, Multi-Axle Heavy Trucks | URI file path or raw `fmi3Binary` payload pointing to a native solver parameter deck. |

* **Inheritance & Override Rule:** Components automatically inherit their bound actor's `vehicle_spec` parameters at instantiation. If a component instance declares an explicit inline parameter in the scenario script (e.g., `KinematicBicycle(wheelbase: 2.85m)`), the inline parameter overrides the inherited `vehicle_spec` value for that instance.

---

## 4. Actor Perception: Priors, Sensors, & `SliceBuffer<T, N>`

Pipeline components cannot query the global world state directly. An actor accesses external context exclusively through mounted **Priors** and **Sensors**:

1. **Priors (`priors`):** Static or slow-updating contextual memory mounted on the actor, such as `RouteNodes` (an ordered sequence of OpenDRIVE road and lane topological IDs representing navigation directions).
2. **Sensors (`sensors`):** World-to-actor projection components (`WorldTruth -> SensorSlice`) parameterized by mount location, field of view, range, tick rate ($f_s$), and ring-buffer history depth ($N$).
3. **Timestamped Ring Buffers (`SliceBuffer<T, N>`):** Every sensor populates a bounded ring buffer of timestamped slices $(t_k, \text{data}_k)$ ordered newest ($k=0$) to oldest ($k=N-1$). All `SliceBuffer<T, N>` ports expose three deterministic query primitives:
   * `buffer.latest() -> Timestamped<T>`: Returns the most recent sample $(t_0, \text{data}_0)$.
   * `buffer.history(k) / buffer[k] -> Timestamped<T>`: Returns the $k\text{-th}$ previous sample ($k \in [0, N-1]$) for stateless finite-difference derivative calculations (e.g., range-rate $\dot{r} = \frac{s[0].r - s[1].r}{s[0].t - s[1].t}$).
   * `buffer.at(t_query, mode: Interpolate | Floor) -> Timestamped<T>`: Retrieves the perceived world state at a past timestamp to model sensor processing latency or human visual-motor reaction delay (e.g., `eyes.at(now - 180ms)`).

---

## 5. Canonical Checkpoint Data Contracts

### 5.1 Checkpoint 1: `IntentFrame`
Produced by Stage 1 (Intent) components to express an actor's short-term motion plan. Parallel longitudinal and lateral sub-intents can be merged via the tuple operator `(LonIntent + LatIntent) -> IntentFrame`.

| Field Group | Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- | :--- |
| **Header** | `actor_id` | `uint64` | — | Unique actor entity identifier. |
| | `timestamp` | `float64` | $\text{s}$ | Simulation time $t$ when the intent frame was evaluated. |
| **Longitudinal** | `lon_mode` | `enum` | — | `ACCEL_TARGET`, `VELOCITY_TARGET`, or `GAP_PROFILE`. |
| | `a_ref` | `float64` | $\text{m/s}^2$ | Target longitudinal acceleration. |
| | `v_ref` | `float64` | $\text{m/s}$ | Target cruise velocity. |
| | `s_stop` | `float64` | $\text{m}$ | Optional target stopping distance along current route/lane. |
| **Lateral** | `lat_mode` | `enum` | — | `LANE_OFFSET`, `POLYLINE_PATH`, or `SPATIOTEMPORAL_TRAJECTORY`. |
| | `target_lane_id` | `string` | — | Target OpenDRIVE lane identifier. |
| | `d_ref` | `float64` | $\text{m}$ | Target lateral offset from `target_lane_id` centerline. |
| | `path_points` | `Waypoint[64]` | $\text{m}, \text{rad}, \text{m}^{-1}$ | Array of $(X, Y, \psi_{\text{ref}}, \kappa_{\text{ref}})$ geometric path targets. |
| **Coupled Horizon** | `trajectory` | `TrajPoint[64]` | $\text{s}, \text{m}, \text{m/s}$ | Optional time-indexed array $(t_k, X_k, Y_k, \psi_k, v_k, a_k, \kappa_k)$ for coupled MPC trackers. |
| **Auxiliary** | `turn_signal` | `enum` | — | `NONE`, `LEFT`, `RIGHT`, `HAZARD`. |

### 5.2 Checkpoint 2: `ControlFrame` (Strict Two-Tier Typing)
To prevent mismatched connections between kinematic controllers and dynamic powertrain models, Checkpoint 2 is split into two distinct compile-time types. Bridging from Tier A to Tier B requires an explicit adapter block (e.g., `LinearPedalMapper`).

#### Tier A: `KinematicControlFrame`
| Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- |
| `actor_id` | `uint64` | — | Unique actor entity identifier. |
| `a_lon_cmd` | `float64` | $\text{m/s}^2$ | Commanded longitudinal acceleration in vehicle body $+x$. |
| `jerk_lon_cmd` | `float64` | $\text{m/s}^3$ | Optional commanded longitudinal jerk. |
| `steer_angle_cmd` | `float64` | $\text{rad}$ | Equivalent front road-wheel steering angle $\delta_{\text{cmd}}$. |
| `steer_rate_cmd` | `float64` | $\text{rad/s}$ | Commanded front road-wheel steering rate $\dot{\delta}_{\text{cmd}}$. |

#### Tier B: `ActuatorControlFrame`
| Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- |
| `actor_id` | `uint64` | — | Unique actor entity identifier. |
| `throttle` | `float64` | $[0.0, 1.0]$ | Normalized accelerator pedal position (dimensionless). |
| `brake` | `float64` | $[0.0, 1.0]$ | Normalized brake demand / master cylinder pressure. |
| `steering_wheel` | `float64` | $[-1.0, 1.0]$ | Normalized steering wheel angle command (or torque in $\text{N}\cdot\text{m}$). |
| `gear` | `enum` | — | `PARK` ($0$), `REVERSE` ($-1$), `NEUTRAL` ($0$), `DRIVE` ($1..N$). |

### 5.3 Checkpoint 3: `KinematicState`
Produced by Stage 3 (Physical Compute) at the end of every simulation step $t + \Delta t$. Low-fidelity physics models (such as 1D point-mass or kinematic bicycles) must zero-initialize unused dynamic fields ($v_{\text{lat}} = 0$, $\beta = 0$) so physics blocks can be hot-swapped mid-simulation without state discontinuity.

| Field Group | Field Name | Type | Unit | Specification & Semantics |
| :--- | :--- | :--- | :--- | :--- |
| **World Pose** | `position` | `Vec3` | $\text{m}$ | $(X, Y, Z)$ position of rear-axle center in World Frame. |
| | `orientation` | `Vec3` | $\text{rad}$ | $(\text{roll } \phi, \text{pitch } \theta, \text{yaw } \psi)$ Euler angles in World Frame. |
| **Body Twist** | `v_lon` | `float64` | $\text{m/s}$ | Longitudinal velocity $v_x$ in Vehicle Body Frame. |
| | `v_lat` | `float64` | $\text{m/s}$ | Lateral slip velocity $v_y$ in Vehicle Body Frame. |
| | `yaw_rate` | `float64` | $\text{rad/s}$ | Angular velocity $\dot{\psi}$ about vehicle vertical $+z$ axis. |
| **Body Accel** | `a_lon` | `float64` | $\text{m/s}^2$ | Achieved longitudinal acceleration $a_x$. |
| | `a_lat` | `float64` | $\text{m/s}^2$ | Achieved lateral acceleration $a_y$. |
| **Internal Chassis** | `front_wheel_angle` | `float64` | $\text{rad}$ | Actual front road-wheel angle $\delta$ persisted across ticks. |
| | `slip_angle_beta` | `float64` | $\text{rad}$ | Vehicle sideslip angle $\beta = \arctan(v_y / v_x)$. |
| **Map Projection** | `lane_id` | `string` | — | Current OpenDRIVE lane ID resolved and cached by World. |
| | `frenet_s`, `frenet_d` | `float64` | $\text{m}$ | Cached $(s, d)$ coordinates for $O(1)$ spatial queries. |

---

## 6. Driveline Component Model (DCM) & Extended FMI 3.0 Lifecycle

The **Driveline Component Model (DCM)** is a strict domain superset of the **FMI 3.0 Co-Simulation** specification. It adopts FMI 3.0’s causality/variability model, synchronous clocks, and `fmi3Binary` transport, while extending it with a **Warm-Start Handoff Mode**, **3-Layer State Initialization**, **Quasi-Static Equilibrium Trim**, and **Host Map Utilities**.

### 6.1 Component Lifecycle State Machine

```text
                  ┌──────────────────────┐
                  │   1. Uninstantiated  │
                  └──────────┬───────────┘
                             │ dl_instantiate(host_callbacks)
                             ▼
                  ┌──────────────────────┐
                  │   2. Instantiated    │
                  └──────────┬───────────┘
                             │ dl_configure_structure(N_history, N_actors)
                             ▼
                  ┌──────────────────────┐
                  │ 3. StructuralConfig  │
                  └──────────┬───────────┘
        ┌────────────────────┴────────────────────┐
        │ At t = t_0                              │ Spliced in at t > t_0
        │ dl_enter_cold_init(init_ctx)            │ dl_enter_warm_start(init_ctx)
        ▼                                         ▼
┌──────────────────────┐                 ┌──────────────────────┐
│ 4a. ColdInitMode     │                 │ 4b. WarmStartMode    │
│  (Quasi-Static Trim) │                 │ (Bumpless Transfer)  │
└───────┬──────────────┘                 └────────┬─────────────┘
        └────────────────────┬────────────────────┘
                             │ dl_exit_init_mode()
                             ▼
                  ┌──────────────────────┐
              ┌──►│     5. StepMode      │◄──┐
              │   └────┬────────────┬────┘   │
 dl_do_step() │        │            │        │ dl_on_membership_change(active_actors)
   (Clocked)  └────────┘            └────────┘ (For 1:N / N:N components)
                             │
                             │ dl_terminate() / splice_out()
                             ▼
                  ┌──────────────────────┐
                  │    6. Terminated     │
                  └──────────────────────┘
```

### 6.2 Lifecycle Transition Rules

1. **`Instantiated` (`dl_instantiate`):** The runtime binds the component instance and injects the read-only host map callback table (`dl_host_map_callbacks_t`).
2. **`StructuralConfig` (`dl_configure_structure`):** Maps to `fmi3EnterConfigurationMode`. Configures structural array dimensions prior to buffer allocation: ring buffer history depth $N$ for each `SliceBuffer<T, N>` port and actor count $M$ for $1\text{:}N$ / $N\text{:}N$ components.
3. **`ColdInitMode` (`dl_enter_cold_init` at $t = t_0$):** Maps to `fmi3EnterInitializationMode`. The runtime passes `dl_init_context_t` with `is_warm_start = 0` and `trim_equilibrium = 1`.
   * **Step A (Host Kinematic Pre-Population):** Before invoking `dl_enter_cold_init`, the runtime queries the OpenDRIVE map at $(s_0, d_0)$ for road curvature $\kappa_0$, bank $\phi_{\text{road}}$, and grade $\theta_{\text{road}}$, pre-populating steady-state yaw rate $\dot{\psi}_0 = v_0 \cdot \kappa_0$, lateral acceleration $a_{\text{lat},0} = v_0^2 \cdot \kappa_0$, nominal rolling wheel speeds $\omega_{i,0} = v_0 / R_{\text{eff}}$, and static axle normal loads $F_{z,f} = m g \frac{l_r}{L}, F_{z,r} = m g \frac{l_f}{L}$.
   * **Step B (Component Internal Equilibrium Trim):** High-fidelity physics models (`DynamicSingleTrack`, `MultiBody`) algebraically solve their internal unobservables (initial suspension deflection $z_{i,0}$, lateral load transfer $\Delta F_z$, and tire relaxation states) so that vertical/rotational derivatives are zeroed out on Tick 1.
4. **`WarmStartMode` (`dl_enter_warm_start` at $t > t_0$):** Invoked when a component is dynamically spliced into an active chain (`splice`) or activated by an `Arbiter` mid-simulation. The runtime passes `dl_init_context_t` with `is_warm_start = 1`, containing the actor's live `chassis_state`, `wheels[8]`, `powertrain` state, and the latest latched upstream `IntentFrame` and `ControlFrame`.
   * **Bumpless Transfer Requirement:** Incoming controllers and physics blocks must back-calculate internal integrators from the live state so that the output at $t + \Delta t$ is $C^0$-continuous.
   * **Fidelity Promotion & Demotion:** When promoting from `KinematicBicycle` (Tier 0) to `DynamicSingleTrack` (Tier 1) or `MultiBody` (Tier 2) mid-run, the host reconstructs nominal wheel speeds $\omega_i = v_{\text{lon}} / R_{\text{eff}}$ and static corner loads from the actor's `vehicle_spec` before entering `WarmStartMode`.
5. **`StepMode` (`dl_do_step` & `dl_on_membership_change`):** Maps to `fmi3DoStep`. Executes on every tick $t$ where the component's synchronous clock divisor fires ($t \bmod \Delta t_{\text{comp}} == 0$). If a single actor is spliced out of a $1\text{:}N$ component (such as yanking `challenger` out of `PincerHiveMind` while `blocker` remains bound), the runtime calls `dl_on_membership_change(active_actor_ids[], count)` prior to stepping without resetting remaining actors.
6. **`Terminated` (`dl_terminate`):** Maps to `fmi3Terminate`. Flushes telemetry and releases memory when spliced out or when the scenario terminates.

### 6.3 Legacy FMI 3.0 Scalar Pin Compatibility
Components packaged as standard `.fmu` archives support two binding modes:
* **Mode A (Native Binary Port):** The FMU exposes `fmi3Binary` inputs/outputs carrying MIME type `application/x-driveline.<checkpoint-type>;version=0.1`, exchanging zero-copy `driveline_abi.h` structs directly.
* **Mode B (Scalar Pin Mapping):** Legacy Simulink/OEM FMUs with scalar `Float64` pins are wrapped in a `component ... from_fmu("...")` block that maps `SliceBuffer` expressions onto scalar inputs (`bind_inputs`) and maps scalar outputs onto the canonical checkpoint struct (`bind_outputs`).

### 6.4 Read-Only Host Map & Spatial Callbacks (`dl_host_map_callbacks_t`)
Injected at instantiation so components can perform deterministic geometric queries without bundling an OpenDRIVE parser:
* `world_to_frenet(X, Y, psi, hint_lane_id) -> (lane_id, s, d, psi_lane)`
* `frenet_to_world(lane_id, s, d) -> (X, Y, Z, psi_lane, kappa_lane)`
* `sample_lane_path(lane_id, s_start, d_offset, ds, count, out_waypoints[])`
* `query_lane_topology(lane_id) -> (left_lane_id, right_lane_id, successor_ids[])`

---

## 7. Normative C-ABI Header (`driveline_abi.h`)

```c
#ifndef DRIVELINE_ABI_H
#define DRIVELINE_ABI_H

#include <stdint.h>

#pragma pack(push, 8)

/* ==========================================================================
 * 1. STRATIFIED VEHICLE PARAMETER TIERS (vehicle_spec)
 * ========================================================================== */

typedef struct {
    double bbox_length, bbox_width, bbox_height; /* [m] */
    double wheelbase;                            /* L [m] */
    double overhang_front, overhang_rear;        /* [m] */
    double max_steer_angle;                      /* delta_max [rad] */
    double max_steer_rate;                       /* delta_dot_max [rad/s] */
    double steering_ratio;                       /* [-] */
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
    double unsprung_mass_f, unsprung_mass_r;     /* m_uf, m_ur [kg] */
    double inertia_xx, inertia_yy, inertia_xz;   /* [kg*m^2] */
    double track_width_f, track_width_r;         /* t_f, t_r [m] */
    double susp_stiffness_f, susp_stiffness_r;   /* K_sf, K_sr [N/m] */
    double susp_damping_f, susp_damping_r;       /* C_sf, C_sr [N*s/m] */
    double arb_stiffness_f, arb_stiffness_r;     /* [N*m/rad] */
    double tire_effective_radius;                /* R_eff [m] */
    double wheel_polar_inertia;                  /* I_w [kg*m^2] */
    double max_drive_torque, max_brake_torque;   /* [N*m] */
} dl_multibody_params_t;

/* ==========================================================================
 * 2. CANONICAL CHECKPOINT STRUCTS
 * ========================================================================== */

typedef struct {
    double x, y, psi_ref, kappa_ref;             /* [m, m, rad, 1/m] */
} dl_waypoint_t;

typedef struct {
    uint64_t actor_id;
    double   timestamp;                          /* [s] */
    uint8_t  lon_mode;                           /* 0:ACCEL, 1:VEL, 2:GAP */
    uint8_t  lat_mode;                           /* 0:LANE, 1:PATH, 2:TRAJ */
    uint8_t  turn_signal;                        /* 0:NONE, 1:L, 2:R, 3:HAZ */
    uint8_t  _reserved[5];
    double   a_ref, v_ref, s_stop;               /* [m/s^2, m/s, m] */
    char     target_lane_id[32];
    double   d_ref;                              /* [m] */
    uint32_t num_waypoints, _pad;
    dl_waypoint_t path_points[64];
} dl_intent_frame_t;

typedef struct {
    uint64_t actor_id;
    double   a_lon_cmd, jerk_lon_cmd;            /* [m/s^2, m/s^3] */
    double   steer_angle_cmd, steer_rate_cmd;    /* [rad, rad/s] */
} dl_kinematic_control_frame_t;

typedef struct {
    uint64_t actor_id;
    double   throttle, brake;                    /* [0.0, 1.0] */
    double   steering_wheel;                     /* [-1.0, 1.0] */
    int8_t   gear;                               /* -1:R, 0:P/N, 1..N:D */
    uint8_t  _reserved[7];
} dl_actuator_control_frame_t;

typedef struct {
    uint64_t actor_id;
    double   pos_x, pos_y, pos_z;                /* Rear-axle World [m] */
    double   roll, pitch, yaw;                   /* World Euler [rad] */
    double   v_lon, v_lat, yaw_rate;             /* Body Twist [m/s, rad/s] */
    double   a_lon, a_lat;                       /* Body Accel [m/s^2] */
    double   front_wheel_angle;                  /* delta [rad] */
    double   slip_angle_beta;                    /* beta [rad] */
    char     lane_id[32];
    double   frenet_s, frenet_d;                 /* Cached Frenet [m] */
} dl_kinematic_state_t;

/* ==========================================================================
 * 3. MULTI-FIDELITY INITIALIZATION & WARM-START CONTEXT
 * ========================================================================== */

typedef struct {
    double omega;                                /* Wheel spin [rad/s] */
    double steer_angle;                          /* Corner steer [rad] */
    double slip_ratio_kappa, slip_angle_alpha;   /* [-], [rad] */
    double susp_deflection_z, susp_velocity_dz;  /* [m], [m/s] */
    double normal_load_fz, surface_mu;           /* [N], [-] */
} dl_wheel_corner_state_t;

typedef struct {
    double engine_rpm;                           /* [rad/s] */
    double actual_drive_torque;                  /* [N*m] */
    double brake_pressure_bar[8];                /* [bar] */
    int8_t current_gear;
    uint8_t _pad[7];
} dl_powertrain_state_t;

typedef struct {
    double   sim_time;                           /* [s] */
    uint8_t  is_warm_start;                      /* 0:ColdInit, 1:WarmStart */
    uint8_t  trim_equilibrium;                   /* 1:Solve quasi-static trim */
    uint8_t  _pad[2];
    uint32_t num_wheels;                         /* 4 for passenger car, up to 8 */

    dl_kinematic_state_t          chassis_state;
    dl_wheel_corner_state_t       wheels[8];
    dl_powertrain_state_t         powertrain;

    dl_intent_frame_t             latched_intent;
    dl_kinematic_control_frame_t  latched_kinematic_ctrl;
    dl_actuator_control_frame_t   latched_actuator_ctrl;

    const dl_kinematic_params_t*    params_tier0; /* Mandatory non-null */
    const dl_single_track_params_t* params_tier1; /* Optional (NULL if unset) */
    const dl_multibody_params_t*    params_tier2; /* Optional (NULL if unset) */
    const void*                     custom_deck;  /* Optional Tier 3 blob/URI */
    uint32_t                        custom_deck_size;
    uint32_t                        _reserved;
} dl_init_context_t;

#pragma pack(pop)
#endif /* DRIVELINE_ABI_H */
```

---

## 8. Composition, Checkpoint Skipping, Arbitration, & Splicing

1. **Sequential Chaining (`>>`):** Connects two components $A: T_1 \rightarrow T_2$ and $B: T_2 \rightarrow T_3$ into a composite chain $A \gg B: T_1 \rightarrow T_3$. Compile-time type checking rejects any connection where the output type of $A$ does not match the input port of $B$.
2. **Parallel Sub-Intent Merging (`+`):** Independent longitudinal and lateral intent blocks can be evaluated in parallel and combined via `(LonBlock + LatBlock) -> IntentFrame`.
3. **Checkpoint Skipping (Merged Black-Box Components):** Components may span multiple conceptual stages to wrap OEM binaries, Tier-1 supplier FMUs, or end-to-end policies:
   * *Merged Intent + Control (e.g., Pre-Collision System ECU):* `SliceBuffer<RadarSlice> -> ActuatorControlFrame` (skips `IntentFrame`).
   * *Merged Full-Stack Bridge:* `SliceBuffer<SensorBundle> -> KinematicState` (skips `IntentFrame` and `ControlFrame`).
4. **Multi-Chain Arbitration (`Arbitrate`):** An actor may execute concurrent chains (such as an organic human driver alongside an artificial active-safety ECU) that converge at a shared checkpoint type via an explicit `Arbiter` component:
   $$\text{Arbitrate}\big(\text{primary}: T_{\text{check}}, \text{secondary}: T_{\text{check}}, \text{via}: (T_{\text{check}}, T_{\text{check}}) \rightarrow T_{\text{check}}\big)$$
5. **Type-Safe Dynamic Splicing (`splice`):** When a component or sub-chain $C_{\text{new}}: T_{\text{in}} \rightarrow T_{\text{out}}$ is spliced into an actor's pipeline at $t > t_0$, the runtime matches $(T_{\text{in}}, T_{\text{out}})$ against the actor's active checkpoint boundaries, transitions the outgoing sub-chain to `Terminated`, initializes $C_{\text{new}}$ via `WarmStartMode` (`dl_enter_warm_start`), and swaps the sub-chain atomically between ticks.

---

## 9. Deterministic Multi-Rate Execution Model

A compliant Driveline runtime executes in deterministic lockstep governed by a base simulation clock $\Delta t_{\text{base}}$ (e.g., $1000\text{ Hz} / 0.001\text{ s}$):

1. **Multi-Rate Sub-Stepping & Zero-Order Hold (ZOH):** Components declare independent execution rates ($f_{\text{intent}} \le f_{\text{control}} \le f_{\text{physics}}$). Because `IntentFrame` and `ControlFrame` are pure value structs, the runtime latches (zero-order holds) the latest output frame across faster downstream ticks until the upstream component's next scheduled evaluation.
2. **Intra-Tick Evaluation Order:** At each simulation step $t$, the runtime executes four strictly ordered phases:
   * **Phase 1 (Sensor Projection):** Evaluate active sensors against World state $X(t)$ and push new slices into each actor's `SliceBuffer<T, N>`.
   * **Phase 2 (Intent, Control, & Arbitration Chains):** Step all scheduled Stage 1, Stage 2, and Arbiter components across $1\text{:}1$ and $1\text{:}N$ bindings.
   * **Phase 3 (Physical Compute):** Step all Stage 3 physics integrators (using local surface friction $\mu(x,y)$ from `SurfaceContactSensor`) to compute $X(t + \Delta t)$.
   * **Phase 4 (World Commit & Termination Check):** Commit $X(t + \Delta t)$ to the World, update cached Frenet $(s, d)$ projections, and evaluate global `terminate when` predicates.

---

## 10. Formal Grammar (EBNF) & Normative Reference Scenario

### 10.1 Core Grammar Subset
```ebnf
ScenarioFile    ::= ImportDecl* VehicleSpecDecl* (ComponentDecl | FnDecl)* ScenarioDecl
VehicleSpecDecl ::= "vehicle_spec" Ident "{" (Ident "=" Expr ";")* "}"
ComponentDecl   ::= "component" Ident FmuClause? RateClause? ":" "(" PortList ")" "->" TypeIdent Block?
FmuClause       ::= "from_fmu" "(" StringLit ")"
RateClause      ::= "(" "rate:" FreqLit ")"
FnDecl          ::= "fn" Ident "(" ParamList? ")" "->" ChainType Block
ScenarioDecl    ::= "scenario" Ident "{" WorldStmt* ActorDecl* BindStmt* TerminateStmt "}"

ActorDecl       ::= "actor" Ident ("[" IntLit "]")? "=" "spawn" "(" ArgList ")" ("with" ActorBody)? ";"
ActorBody       ::= "{" PriorsBlock? SensorsBlock? ChainDecl* PhysicsDecl "}"
PriorsBlock     ::= "priors" "{" (Ident "=" Expr ";")* "}"
SensorsBlock    ::= "sensors" "{" (Ident "=" ComponentInst ";")* "}"

ChainDecl       ::= "chain" Ident "=" PipeExpr ";"
PhysicsDecl     ::= "physics" "=" PipeExpr ";"
PipeExpr        ::= PrimaryExpr (">>" PrimaryExpr)*
PrimaryExpr     ::= ComponentInst | "(" PipeExpr ("+" PipeExpr)+ ")" | ArbitrateExpr | Ident
ArbitrateExpr   ::= "Arbitrate" "(" PipeExpr "," PipeExpr "," "via:" ComponentInst ")"
TerminateStmt   ::= "terminate" "when" "(" BoolExpr ")" ";"
```

### 10.2 Normative Reference Scenario (`kanagawa_pinch_test.dline`)
```rust
use std::sensors::{HumanVisualSensor, MillimeterRadar, MonoCamera, SurfaceContactSensor}
use std::intent::{PincerHiveMind}
use std::control::{JerkLimiter, StanleyLat, LinearPedalMapper, BrakeOverrideArbiter}
use std::physics::{DynamicSingleTrack, KinematicBicycle}

// ============================================================================
// 1. STRATIFIED VEHICLE SPECIFICATION (Tier 0, Tier 1, Tier 2, & Tier 3)
// ============================================================================
vehicle_spec Sedan_2026 {
    // Tier 0: Geometry & Kinematic Steering Limits
    geometry   = { length: 4.75m, width: 1.85m, height: 1.45m, wheelbase: 2.80m };
    steering   = { max_angle: 0.62rad, max_rate: 0.45rad/s, ratio: 14.5 };

    // Tier 1: Lumped Mass & Single-Track Cornering Dynamics
    mass_props = { mass: 1750kg, l_f: 1.25m, l_r: 1.55m, h_cg: 0.52m, i_zz: 2850kg*m^2 };
    tires_st   = { c_alpha_f: 85000N/rad, c_alpha_r: 92000N/rad };

    // Tier 2: Multi-Body & Wheel-Corner Extensions (Used for Equilibrium Trim)
    chassis_mb = {
        sprung_mass: 1510kg, unsprung_mass_f: 120kg, unsprung_mass_r: 120kg,
        track_width_f: 1.58m, track_width_r: 1.59m,
        susp_k: [32000N/m, 36000N/m], susp_c: [2800N*s/m, 3100N*s/m],
        tire_radius: 0.33m, wheel_inertia: 1.15kg*m^2
    };
    tire_deck  = "tires/pacejka_235_45_R18.tir"; // Tier 3 external solver deck
}

// ============================================================================
// 2. NATIVE & EXTERNAL FMU COMPONENT DECLARATIONS
// ============================================================================

// Native DSL Intent Component using SliceBuffer time-interpolation for reaction delay
component HumanIntent (rate: 20Hz): (
    eyes:  SliceBuffer<VisualSlice>,
    route: RouteNodes
) -> IntentFrame {
    param reaction_delay: Time = 0.18s;
    param desired_speed: Velocity = 28.0m/s;

    step(t: Time, dt: Time) -> IntentFrame {
        let perceived = eyes.at(t - reaction_delay, mode: Interpolate);
        if perceived.lead_ttc < 2.2s {
            return IntentFrame::decelerate(a_ref: -5.5m/s^2);
        }
        return IntentFrame::follow_route(route, v_ref: desired_speed);
    }
}

component HumanControl (rate: 100Hz): (IntentFrame) -> ActuatorControlFrame;

// External OEM Pre-Collision System FMU (Merged Intent+Control skipping IntentFrame)
component BoschPCS_v4 from_fmu("fmus/BoschPCS_v4.fmu") (rate: 50Hz): (
    radar:  SliceBuffer<RadarSlice>,
    camera: SliceBuffer<CameraSlice>
) -> ActuatorControlFrame {
    bind_inputs {
        "Radar_Range_m"    = radar.latest().range,
        "Radar_RangeRate"  = (radar[0].range - radar[1].range) / (radar[0].t - radar[1].t),
        "Cam_ObstacleConf" = camera.latest().confidence
    }
    bind_outputs -> ActuatorControlFrame {
        throttle       = 0.0,
        brake          = clamp(fmu.out("AEB_BrakePressure_Bar") / 120.0, 0.0, 1.0),
        steering_wheel = 0.0,
        gear           = Gear::DRIVE
    }
}

// Explicit Parameterized Adapter Sub-Chain (Tier A Kinematic -> Tier B Actuator)
fn kinematic_to_pedal_control() -> Chain<IntentFrame, ActuatorControlFrame> {
    return (JerkLimiter(max_jerk: 4.0m/s^3) + StanleyLat(k: 2.5, sample_step: 1.0m))
        >> LinearPedalMapper(max_accel: 4.5m/s^2, max_decel: 9.0m/s^2);
}

// ============================================================================
// 3. SCENARIO DEFINITION (Owns Ground-Truth Physical World Only)
// ============================================================================
scenario KanagawaExpresswayPinchTest {
    map = load_xodr("maps/kanagawa_expressway.xodr");
    timestep = 0.002s; // 500 Hz base physics clock

    environment {
        default_friction = 0.85;
        friction_zone(s_start: 150.0m, s_end: 250.0m, mu: 0.25); // Ice patch
    }

    // --- Actor 1: Ego Vehicle (Organic Human + Arbitrated OEM PCS ECU) ---
    actor ego = spawn(spec: Sedan_2026, lane: 2, s: 15.0m, v: 28.0m/s) with {
        priors {
            nav_route = RouteNodes(["road_10:lane_2", "road_11:lane_1", "jct_4:exit"]);
        }
        sensors {
            eyes        = HumanVisualSensor(fov: 140deg, range: 180m, rate: 20Hz, history: 10);
            front_radar = MillimeterRadar(mount: FrontBumper, fov: 45deg, rate: 50Hz, history: 8);
            front_cam   = MonoCamera(mount: Windshield, fov: 60deg, rate: 30Hz, history: 5);
            tire_patch  = SurfaceContactSensor(rate: 500Hz, history: 1);
        }

        chain human_driver  = HumanIntent(eyes: sensors.eyes, route: priors.nav_route)
                           >> HumanControl();

        chain active_safety = BoschPCS_v4(
            radar:  sensors.front_radar,
            camera: sensors.front_cam
        );

        // Arbitrate at Checkpoint 2 (ActuatorControlFrame) and step Tier-1 Single-Track Physics
        physics = Arbitrate(human_driver, active_safety, via: BrakeOverrideArbiter())
               >> DynamicSingleTrack(surface: sensors.tire_patch);
    };

    // --- Actors 2 & 3: Challengers Coordinated by a 1:N Hive Mind Intent ---
    actor blocker    = spawn(spec: Sedan_2026, lane: 1, s: 30.0m, v: 26.0m/s);
    actor challenger = spawn(spec: Sedan_2026, lane: 3, s: 35.0m, v: 25.0m/s);

    bind [blocker, challenger] -> PincerHiveMind(target: ego, pinch_gap: 12.0m)
                               >> kinematic_to_pedal_control()
                               >> KinematicBicycle();

    // Physical Termination Predicates
    terminate when (sim_time > 25.0s or collision(ego, any) or ego.state.v_lon < 0.1m/s);
}
```