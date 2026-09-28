---
title: Component lifecycle
section: 6
version: 0.138
status: draft
normative: true
depends_on: [02-conventions.md, 05-checkpoints.md, 07-fmu-packaging.md, 08-steady-state.md, 09-abi.md, 10-composition.md, 11-execution.md, 14-diagnostics.md, 17-standard-library.md]
---

# 6. Driveline Component Model (DCM) & Lifecycle

The **Driveline Component Model (DCM)** is a C-ABI ([§9](09-abi.md)). Native components export the `dl_*` entry points. Components packaged as `.fmu` files export only standard FMI 3.0 functions, and the runtime drives them as [§7](07-fmu-packaging.md) describes.

## 6.1 Component Lifecycle State Machine

```text
                 ┌──────────────────────┐
                 │  1. Uninstantiated   │◄───────────────────────────┐
                 └──────────┬───────────┘                            │
                            │ dl_instantiate                         │
                            ▼                                        │
                 ┌──────────────────────┐                            │
                 │   2. Instantiated    │ dl_set_parameters          │
                 └──────────┬───────────┘                            │
                            │ dl_configure_structure                 │
                            ▼                                        │
                 ┌──────────────────────┐                            │
                 │ 3. StructuralConfig  │ dl_set_parameters          │
                 └──────────┬───────────┘                            │
             t = 0          │          t > 0                         │
           ┌────────────────┴────────────────┐                       │
           │ dl_enter_cold_init              │ dl_enter_warm_start   │
           ▼                                 ▼                       │
┌──────────────────────┐          ┌──────────────────────┐           │
│   4a. ColdInitMode   │          │  4b. WarmStartMode   │◄──────┐   │
└──────────┬───────────┘          └──────────┬───────────┘       │   │
           └────────────────┬────────────────┘                   │   │
                            │ dl_exit_init_mode                  │   │
                            ▼                                    │   │
                 ┌──────────────────────┐     re-trim:           │   │
                 │     5. StepMode      │────────────────────────┘   │
                 └──────────┬───────────┘     dl_enter_warm_start    │
                            │ dl_do_step repeats in StepMode         │
                            │ dl_terminate                           │
                            ▼                                        │
                 ┌──────────────────────┐                            │
                 │    6. Terminated     │────────────────────────────┘
                 └──────────────────────┘     dl_free_instance
```

**Allowed Calls:** This table is the complete list of legal calls. Any other call returns `DL_STATUS_ERR_STATE` and leaves the state unchanged. `dl_free_instance` returns nothing, so the runtime never calls it outside the states the table allows. A call that returns an error also leaves the state unchanged.

| Function | Allowed In | Next State |
| :--- | :--- | :--- |
| `dl_instantiate` | Uninstantiated | Instantiated |
| `dl_set_parameters` | Instantiated, StructuralConfig | unchanged |
| `dl_configure_structure` | Instantiated | StructuralConfig |
| `dl_enter_cold_init` | StructuralConfig, at $t = 0$ only | ColdInitMode |
| `dl_enter_warm_start` | StructuralConfig at $t > 0$ (splice), or StepMode (re-trim) | WarmStartMode |
| `dl_exit_init_mode` | ColdInitMode, WarmStartMode | StepMode |
| `dl_do_step` | StepMode | StepMode |
| `dl_terminate` | Instantiated, StructuralConfig, ColdInitMode, WarmStartMode, StepMode | Terminated |
| `dl_free_instance` | every state except Uninstantiated | Uninstantiated; the handle becomes invalid |

## 6.2 Detailed Lifecycle Transition Rules

1. **`Instantiated` (`dl_instantiate`, `dl_set_parameters`):** `dl_instantiate` verifies `abi_version` and stores the host map callback table (`dl_host_map_callbacks_t`) and its `host_ctx`. The runtime then passes every component parameter from the DSL (for example `kp: 1.8` or `reaction_delay: 0.18s`) through `dl_set_parameters`, by name, in SI units. `dl_set_parameters` is valid in `Instantiated` and `StructuralConfig`. An unknown name or a wrong type returns `DL_STATUS_ERR_INVALID_ARG`.
2. **`StructuralConfig` (`dl_configure_structure`):** Passes the input port count, the per-port ring buffer capacities `port_history_depths[]`, and the number of actors that the instance serves (`max_actors`): 1 for a per-actor instance and $M$ for a group instance ([§10](10-composition.md)). Multi-input components such as `BoschPCS_v4` get one depth per port, for example $N_0 = 8$ and $N_1 = 5$. Non-buffer ports have depth $0$.
3. **`ColdInitMode` (`dl_enter_cold_init` at $t = 0$), Coupled Trim Protocol:**
   Before Pass 1, the runtime visits every component instance in Phase 2 order ([§11](11-execution.md)) and calls `dl_instantiate`, `dl_set_parameters`, and `dl_configure_structure` on it before it moves to the next instance. It then initializes the pipeline in three passes. Each pass covers all actors and groups in the Phase 2 order of [§11](11-execution.md): ascending `actor_id`, with a group sorted by its smallest member, and components in topological order.
   * **Pass 1 (Host Steady State & Tick 0 Sensor Projection):**
     1. For each actor, the host calls `frenet_to_world` at the spawn `(road_id, lane_id, s_0, d_0)`. The returned `psi_lane` and `kappa_lane` are the lane's heading and signed curvature in the direction of increasing $s$, with positive curvature turning left. Let $\sigma$ be the spawn lane's direction sign ([§2](02-conventions.md)). The travel direction is $\psi_{\text{travel}} = $ `psi_lane` for $\sigma = +1$ and `psi_lane` $+ \pi$, wrapped to $(-\pi, \pi]$, for $\sigma = -1$. The curvature along the direction of travel is $\kappa_0 = \sigma \cdot$ `kappa_lane`, because a curve that turns left toward increasing $s$ turns right toward decreasing $s$. The runtime also computes the road grade $\theta_{\text{road}}$ and bank $\phi_{\text{road}}$ at the spawn point ([§2](02-conventions.md)).
     2. It sets $\dot{\psi}_0 = v_0 \kappa_0$ and solves the steady state of [§8](08-steady-state.md) for the tier of the actor's physics component. That solve gives $v_{\text{lat,ra}}$, $\delta_{\text{ss}}$, and $\beta_{\text{cg}}$. The spawn heading is $\psi_0 = \psi_{\text{travel}} - \operatorname{atan2}(v_{\text{lat,ra}}, v_0)$, wrapped to $(-\pi, \pi]$, so the rear-axle velocity is tangent to the lane and the actor follows it. For `KS` and at $v_0 = 0$, $\psi_0 = \psi_{\text{travel}}$.
     3. If Tier 1 is populated, it computes static axle normal loads. Tier 0 has no mass, so a Tier-0-only actor skips this step and step 4:
     $$F_{z,f} = m g \cos\theta_{\text{road}}\cos\phi_{\text{road}} \frac{l_r}{L} - m g \sin\theta_{\text{road}} \frac{h_{\text{cg}}}{L}, \qquad F_{z,r} = m g \cos\theta_{\text{road}}\cos\phi_{\text{road}} \frac{l_f}{L} + m g \sin\theta_{\text{road}} \frac{h_{\text{cg}}}{L}$$
     With the [§2](02-conventions.md) sign convention, an uphill road ($\theta_{\text{road}} > 0$) moves load to the rear axle.
     4. If Tier 2 is populated, it sets `num_wheels = 4` and fills `wheels[0..3]` in the header's order: `normal_load_fz` is half of the axle load, `omega` is $v_0 / R_{\text{eff}}$, `steer_angle` is $\delta_{\text{ss}}$ at the front and 0 at the rear, `slip_angle_alpha` is the [§8](08-steady-state.md) axle slip angle ($\alpha_f$ or $\alpha_r$, 0 for `KS` or below $1\text{ m/s}$), `surface_mu` is $\mu$ at the contact point ([§17.1](17-standard-library.md)), and the slip ratio, suspension deflection, and suspension velocity are 0. The physics component solves its own deflection in Pass 3. `powertrain` has `gear_mode` `D`, `active_gear_index` from the `SimpleDrivetrain` gear rule ([§17](17-standard-library.md)), `motor_or_engine_speed_rads` $= (v_0 / R_{\text{eff}})\, i_g\, i_{\text{fd}}$, and zero torque and brake pressures. Otherwise `num_wheels = 0`, and `wheels[]` and `powertrain` are zero.
     5. It fills each actor's `dl_init_context_t`, with `struct_size` and `abi_version` as [§9.1](09-abi.md) requires, `sim_time_ns = 0`, and `is_warm_start = 0`. `chassis_state` holds `actor_id`, `timestamp_ns = 0`, the spawn pose with roll and pitch 0, $v_0$, $\dot{\psi}_0$, $v_{\text{lat,ra}}$, $a_{\text{lon}} = -v_{\text{lat,ra}} \dot{\psi}_0$, $a_{\text{lat}} = v_0 \dot{\psi}_0$ (the rear-axle acceleration on the steady circle), `front_wheel_angle` $= \delta_{\text{ss}}$, $\beta_{\text{cg}}$, and the spawn `road_id`, `lane_id`, $s_0$, and $d_0$ as the map cache. `latched_intent` is `VELOCITY_TARGET` with `v_ref` $= v_0$ and `LANE_OFFSET` on the spawn lane with `d_ref` $= d_0$ (`valid_mask = 0x03`). `latched_kinematic_ctrl` has `a_lon_cmd` $= 0$ and `steer_angle_cmd` $= \delta_{\text{ss}}$ (`valid_mask = 0x05`). `latched_actuator_ctrl` has `throttle` $= 0$, `brake` $= 0$, `steering_wheel_norm` $= \delta_{\text{ss}} / \delta_{\max}$, and `gear_mode = DRIVE` with `manual_gear_index = 0` (`valid_mask = 0x17`). Every latched frame asserts each hold unit that a standard consumer reads, so no consumer starts with an unfilled unit.
     6. It runs sensor projection at $t = 0$. This projection is Tick 0's Phase 1. Tick 0 does not run Phase 1 again, so no buffer holds two samples at $t = 0$.
   * **Pass 2 (Stage 1 and Stage 2 Cold Init):** Stage 1 and Stage 2 components enter `dl_enter_cold_init` and then `dl_exit_init_mode`. Stage 1 components initialize freely, because their output comes from perception. Each Stage 2 component sets its internal state, such as integrators and filters, so that its first output reproduces the steering of the latched frame of its output type. A `Lon<T>` component reproduces the longitudinal fields instead, and a `Lat<T>` component reproduces the steering. Longitudinal pedal trim for steady speed (drag and rolling resistance) is the job of the component that produces `ActuatorControlFrame`. Initialization returns no output, so the runtime checks the trim on Tick 0: after the first `dl_do_step` of each Stage 2 component whose output type is not `Lon<T>`, it compares the output's road-wheel steering angle with the latched one. A `Lon<T>` output carries no steering and is not checked, and neither is an output whose steering angle bit (`0x04`) is clear after the hold rule. For `ActuatorControlFrame`, the road-wheel angle is `steering_wheel_norm` $\cdot \, \delta_{\max}$. If the two differ by more than $10^{-3}\text{ rad}$, the runtime reports `DL_STATUS_WARN_TRIM_MISMATCH` ([§14](14-diagnostics.md)) and continues.
   * **Pass 3 (Stage 3 Physics Trim):** Physics components enter `dl_enter_cold_init`, solve their internal states at the Pass 1 steady state, and then leave through `dl_exit_init_mode`. Internal states include suspension deflection $z_{i,0}$ and tire relaxation. Physics does not re-solve $\delta$. If the Tick 0 check reports no `DL_STATUS_WARN_TRIM_MISMATCH`, Tick 0 starts at the linear-tire steady state of [§8](08-steady-state.md). Otherwise the first ticks contain a transient.
4. **`WarmStartMode` (`dl_enter_warm_start` at $t > 0$), Fidelity Promotion & Demotion:**
   * **Tier Change:** A splice that replaces the actor's physics component, through `physics_model` or through a chain that contains it, is a promotion if the outgoing component's `required_tier` is 0 and the incoming one's is 1 or 2, and a demotion in the reverse case. Tiers 1 and 2 share the `ST` steady state of [§8](08-steady-state.md), so a splice between them changes no field.
   * **Promotion, Tier 0 (`KS`) $\rightarrow$ Tier 1/2 (`ST` / `MB`):** The runtime keeps the position, the rear-axle course angle $\chi = \psi + \operatorname{atan2}(v_{\text{lat,ra}}, v_{\text{lon}})$, $v_{\text{lon}}$, and $\dot{\psi}$. It solves the `ST` steady state of [§8](08-steady-state.md) at $(v_{\text{lon}}, \dot{\psi})$ and passes it to the incoming physics component. Five fields change: $v_{\text{lat,ra}}$ goes from $0$ to the solved value, $a_{\text{lon}}$ drops by $v_{\text{lat,ra}} \dot{\psi}$ so that $\dot{v}_{\text{lon}}$ is kept ([§5.3](05-checkpoints.md)), `front_wheel_angle` goes from $\delta_{\text{KS}}$ to $\delta_{\text{ss}}$, $\beta_{\text{cg}}$ follows from both, and the yaw becomes $\psi = \chi - \operatorname{atan2}(v_{\text{lat,ra}}, v_{\text{lon}})$, so the actor keeps its path, as at spawn. With linear tires, the lateral force and yaw moment of the incoming model are balanced at the first step if the upstream steering command reproduces $\delta_{\text{ss}}$, that is, if the re-trim reports no `DL_STATUS_WARN_TRIM_MISMATCH`.
   * **Demotion, Tier 1/2 $\rightarrow$ Tier 0:** The runtime keeps the position, $\chi$, $v_{\text{lon}}$, and $\dot{\psi}$. It sets $v_{\text{lat,ra}} = 0$, `front_wheel_angle` $= \delta_{\text{KS}}$ from [§8](08-steady-state.md), and $\psi = \chi$, and $a_{\text{lon}}$ rises by the old $v_{\text{lat,ra}} \dot{\psi}$ so that $\dot{v}_{\text{lon}}$ is kept. These four fields and $\beta_{\text{cg}}$ change.
   * **Committed State Update:** For a promotion or demotion, the runtime writes the changed fields into the committed state $X(t)$ before any warm start. The incoming physics component, the re-trim set, the next tick's sensors, `own_state`, and `actor.state` all see the updated state.
   * **Re-Trim of Upstream Controllers:** A promotion or demotion changes `front_wheel_angle`. In the same inter-tick window, the runtime moves the **re-trim set**, in Phase 2 order, from `StepMode` through `dl_enter_warm_start` and `dl_exit_init_mode` back to `StepMode`: every Stage 2 instance upstream of the new physics component in the actor's physics chain, or in its group's chain, that serves the actor and whose output type is not `Lon<T>`. Stage 2 arbiters are included. Stage 1 arbiters are not. Components outside the set keep running unchanged. It passes the latched frames defined below. Each re-trimmed component sets its internal state so that its next output reproduces the new steering angle, to the extent its design allows. Until that next scheduled step, its held output is its latched frame of its output type, as for a splice replacement ([§10.4](10-composition.md)). A stateless component, such as `StanleyLat`, computes its output from its inputs alone. A Mode B FMU cannot be re-trimmed at all ([§7](07-fmu-packaging.md)). The runtime does not call it and reports `DL_STATUS_WARN_TRIM_MISMATCH`. The runtime checks the first output of each re-trimmed component other than a Mode B FMU, and of each Stage 2 component created by a splice, the way it checks Tick 0 in Pass 2, and reports `DL_STATUS_WARN_TRIM_MISMATCH` if the steering angles differ by more than $10^{-3}\text{ rad}$.
   * **Latched Frames at $t > 0$:** For a re-trim, each latched frame in the context is the last frame of that type that left the component's output, or, if the component does not produce that type, the last frame of that type that reached its input. A component whose input and output types are equal, such as `JerkLimiter`, therefore gets its own last output. For a splice, the same rule applies to the outgoing target as a whole: the last frame of each type that left its output or reached its input, and for a type that only flowed inside it, the last frame on the edge of that type nearest its output. Every component of the replacement gets these frames. A replacement that has not stepped yet passes on the latched frames it was given. A latched frame of a type that the rules above do not cover, because it neither reached nor left the component or target, or because no frame of that type has flowed for the actor, is built by the rules of Pass 1 step 5 from the committed state, with $v_0 = v_{\text{lon}}$, $d_0 = $ `frenet_d`, and $\delta_{\text{ss}} = $ `front_wheel_angle`. A replacement chain with a checkpoint type that the old chain lacked is one such case. Every latched frame is the frame as filled by the hold rule ([§5](05-checkpoints.md)), not the raw frame. The chassis state is the committed state. For an actor whose physics tier changes in the window, every warm-start context, whether a splice or a re-trim, then replaces only the steering fields with the new `front_wheel_angle`: `latched_kinematic_ctrl.steer_angle_cmd`, and `latched_actuator_ctrl.steering_wheel_norm` $= $ `front_wheel_angle` $/\, \delta_{\max}$. Longitudinal fields keep their last values, so a re-trimmed speed controller continues without a step.
   * **Warm-Start Context:** A warm-start context is built like a cold-init one, from the committed state at the tick time $t$ of the next tick: `sim_time_ns` $= t$, `is_warm_start = 1`, `chassis_state` is the committed state, and `wheels[]` and `powertrain` follow Pass 1 steps 3 and 4 with $v_0 = v_{\text{lon}}$, the current `front_wheel_angle`, and the grade and bank at the current pose. The latched frames follow the rule above.
   * **Contexts per Actor:** `dl_enter_cold_init` and `dl_enter_warm_start` take one `dl_init_context_t` per actor, and the component matches each context to its actor slot by `chassis_state.actor_id`. An instance gets contexts only for the actors that it serves, in its `actor_ids` order. Cold init and a splice pass one for each of them. A re-trim passes contexts only for the served actors whose physics tier changed, and the component keeps the state of every other actor.
   * **Size of the Change:** For linear tires, $\delta_{\text{ss}} - \delta_{\text{KS}} \approx K_{\text{us}}\, v_{\text{lon}} \dot{\psi}$, where $K_{\text{us}} = \frac{m}{L}\left(\frac{l_r}{C_{\alpha f}} - \frac{l_f}{C_{\alpha r}}\right)$ is the understeer gradient. [§8](08-steady-state.md) gives a test vector.
