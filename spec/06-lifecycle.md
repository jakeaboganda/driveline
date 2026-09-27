---
title: Component lifecycle
section: 6
version: 0.16
status: draft
normative: true
depends_on: [05-checkpoints.md, 08-steady-state.md, 09-abi.md]
---

# 6. Driveline Component Model (DCM) & Lifecycle

The **Driveline Component Model (DCM)** is a C-ABI ([§9](09-abi.md)). Native components export the `dl_*` entry points. Components packaged as `.fmu` files export only standard FMI 3.0 functions, and the runtime drives them as [§7](07-fmu-packaging.md) describes.

## 6.1 Component Lifecycle State Machine

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

## 6.2 Detailed Lifecycle Transition Rules

1. **`Instantiated` (`dl_instantiate`, `dl_set_parameters`):** `dl_instantiate` verifies `abi_version` and stores the host map callback table (`dl_host_map_callbacks_t`) and its `host_ctx`. The runtime then passes every component parameter from the DSL (for example `kp: 1.8` or `reaction_delay: 0.18s`) through `dl_set_parameters`, by name, in SI units. `dl_set_parameters` is valid in `Instantiated` and `StructuralConfig`. An unknown name or a wrong type returns `DL_STATUS_ERR_INVALID_ARG`.
2. **`StructuralConfig` (`dl_configure_structure`):** Passes the input port count, the per-port ring buffer capacities `port_history_depths[]`, and the bound actor count $M$ (`max_actors`). Multi-input components such as `BoschPCS_v4` get one depth per port, for example $N_0 = 8$ and $N_1 = 5$. Non-buffer ports have depth $0$.
3. **`ColdInitMode` (`dl_enter_cold_init` at $t = 0$), Coupled Trim Protocol:**
   The runtime initializes the pipeline in three passes. Each pass covers all actors in ascending `actor_id` order, and components within an actor in topological order.
   * **Pass 1 (Host Steady State & Tick 0 Sensor Projection):**
     1. For each actor, the host calls `frenet_to_world` at the spawn `(road_id, lane_id, s_0, d_0)`. The returned `psi_lane` and `kappa_lane` are the lane's heading and signed curvature in the direction of increasing $s$, with positive curvature turning left. Let $\sigma = +1$ if the spawn lane drives toward increasing $s$ and $\sigma = -1$ otherwise ([§2](02-conventions.md)). The spawn heading is $\psi_0 = $ `psi_lane` for $\sigma = +1$ and `psi_lane` $+ \pi$, wrapped to $(-\pi, \pi]$, for $\sigma = -1$. The curvature along the direction of travel is $\kappa_0 = \sigma \cdot$ `kappa_lane`, because a curve that turns left toward increasing $s$ turns right toward decreasing $s$. The host also reads the road grade $\theta_{\text{road}}$ and bank $\phi_{\text{road}}$ (sign conventions in [§2](02-conventions.md)).
     2. It sets $\dot{\psi}_0 = v_0 \kappa_0$ and solves the steady state of [§8](08-steady-state.md) for the tier of the actor's physics component. That solve gives $v_{\text{lat,ra}}$, $\delta_{\text{ss}}$, and $\beta_{\text{cg}}$.
     3. If Tier 1 is populated, it computes static axle normal loads. Tier 0 has no mass, so a Tier-0-only actor skips this step and step 4:
     $$F_{z,f} = m g \cos\theta_{\text{road}}\cos\phi_{\text{road}} \frac{l_r}{L} - m g \sin\theta_{\text{road}} \frac{h_{\text{cg}}}{L}, \qquad F_{z,r} = m g \cos\theta_{\text{road}}\cos\phi_{\text{road}} \frac{l_f}{L} + m g \sin\theta_{\text{road}} \frac{h_{\text{cg}}}{L}$$
     With the [§2](02-conventions.md) sign convention, an uphill road ($\theta_{\text{road}} > 0$) moves load to the rear axle.
     4. If Tier 2 is populated, it sets `num_wheels = 4`, splits each axle load evenly between left and right wheels, and sets wheel speeds $\omega_{i,0} = v_0 / R_{\text{eff}}$. Otherwise it sets `num_wheels = 0`, and the `wheels[]` entries are unused.
     5. It fills each actor's `dl_init_context_t`. `chassis_state` holds the spawn pose, $v_0$, $\dot{\psi}_0$, $v_{\text{lat,ra}}$, $a_{\text{lat}} = v_0 \dot{\psi}_0$, `front_wheel_angle` $= \delta_{\text{ss}}$, and $\beta_{\text{cg}}$. `latched_intent` is `VELOCITY_TARGET` with `v_ref` $= v_0$ and `LANE_OFFSET` on the spawn lane with `d_ref` $= d_0$ (`valid_mask = 0x03`). `latched_kinematic_ctrl` has `a_lon_cmd` $= 0$ and `steer_angle_cmd` $= \delta_{\text{ss}}$ (`valid_mask = 0x05`). `latched_actuator_ctrl` has `steering_wheel_norm` $= \delta_{\text{ss}} / \delta_{\max}$ and `gear_mode = DRIVE` (`valid_mask = 0x14`).
     6. It runs sensor projection at $t = 0$. This projection is Tick 0's Phase 1. Tick 0 does not run Phase 1 again, so no buffer holds two samples at $t = 0$.
   * **Pass 2 (Stage 1 and Stage 2 Cold Init):** Stage 1 and Stage 2 components enter `dl_enter_cold_init` and then `dl_exit_init_mode`. Stage 1 components initialize freely, because their output comes from perception. Each Stage 2 component sets its internal state, such as integrators and filters, so that its first output reproduces the steering of the latched frame of its output type. A `Lon<T>` component reproduces the longitudinal fields instead, and a `Lat<T>` component reproduces the steering. Longitudinal pedal trim for steady speed (drag and rolling resistance) is the job of the component that produces `ActuatorControlFrame`. Initialization returns no output, so the runtime checks the trim on Tick 0: after each Stage 2 component's first `dl_do_step`, it compares the output's road-wheel steering angle with the latched one. For `ActuatorControlFrame`, the road-wheel angle is `steering_wheel_norm` $\cdot \, \delta_{\max}$. If the two differ by more than $10^{-3}\text{ rad}$, the runtime reports `DL_STATUS_WARN_TRIM_MISMATCH` ([§14](14-diagnostics.md)) and continues.
   * **Pass 3 (Stage 3 Physics Trim):** Physics components enter `dl_enter_cold_init` and solve their internal states, such as suspension deflection $z_{i,0}$ and tire relaxation, at the Pass 1 steady state. Physics does not re-solve $\delta$. If the Tick 0 check reports no `DL_STATUS_WARN_TRIM_MISMATCH`, Tick 0 starts at the linear-tire steady state of [§8](08-steady-state.md). Otherwise the first ticks contain a transient.
4. **`WarmStartMode` (`dl_enter_warm_start` at $t > 0$), Fidelity Promotion & Demotion:**
   * **Promotion, Tier 0 (`KS`) $\rightarrow$ Tier 1/2 (`ST` / `MB`):** The runtime keeps the pose, $v_{\text{lon}}$, and $\dot{\psi}$. It solves the `ST` steady state of [§8](08-steady-state.md) at $(v_{\text{lon}}, \dot{\psi})$ and passes it to the incoming physics component. Three fields change: $v_{\text{lat,ra}}$ goes from $0$ to the solved value, `front_wheel_angle` goes from $\delta_{\text{KS}}$ to $\delta_{\text{ss}}$, and $\beta_{\text{cg}}$ follows from both. With linear tires, the lateral force and yaw moment of the incoming model are balanced at the first step.
   * **Demotion, Tier 1/2 $\rightarrow$ Tier 0:** The runtime keeps the pose, $v_{\text{lon}}$, and $\dot{\psi}$. It sets $v_{\text{lat,ra}} = 0$ and `front_wheel_angle` $= \delta_{\text{KS}}$ from [§8](08-steady-state.md). These two fields and $\beta_{\text{cg}}$ change.
   * **Re-Trim of Upstream Controllers:** A promotion or demotion changes `front_wheel_angle`. In the same inter-tick window, the runtime moves each Stage 2 component that feeds the new physics component from `StepMode` back into `WarmStartMode`. It passes `latched_kinematic_ctrl.steer_angle_cmd` $= $ the new `front_wheel_angle`, and it passes the matching `latched_actuator_ctrl`. Each re-trimmed component resets its internal state so that its next output equals the new steering angle. A component that cannot re-trim (a Mode B FMU, [§7](07-fmu-packaging.md)) causes `DL_STATUS_WARN_TRIM_MISMATCH`.
   * **Size of the Change:** For linear tires, $\delta_{\text{ss}} - \delta_{\text{KS}} \approx K_{\text{us}}\, v_{\text{lon}} \dot{\psi}$, where $K_{\text{us}} = \frac{m}{L}\left(\frac{l_r}{C_{\alpha f}} - \frac{l_f}{C_{\alpha r}}\right)$ is the understeer gradient. [§8](08-steady-state.md) gives a test vector.
   * **Full-Stack Bridge (`SensorBundle -> KinematicState`):** Allowed only as a static $t = 0$ actor binding, for replay actors or external HiL ego bridges. Splicing a `SensorBundle -> KinematicState` component at $t > 0$ is a compile-time error unless the scenario declares `allow_pose_override = true;`.
5. **Membership Mutation (`dl_on_membership_change`):** Actors can join or leave a $1\text{:}N$ or $N\text{:}N$ component at $t > 0$. `dl_membership_change_t` lists the full active actor set after the change and the init contexts of the added actors. An actor absent from the new active set has left. The component warm-starts each added actor's slot and does not reset the other members.
