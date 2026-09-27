---
title: Vehicle parameter tiers
section: 3
version: 0.4
status: draft
normative: true
depends_on: [02-conventions.md]
---

# 3. Stratified Vehicle Parameter Specification (`vehicle_spec`)

Borrowing the hierarchical model structure of CommonRoad, Driveline defines a four-tier parameter specification attached to the actor entity. Higher tiers strictly require all lower numeric tiers (Tier 2 requires Tiers 0 and 1; Tier 1 requires Tier 0).

| Tier | C-ABI Struct | Target Fidelity Models | Mandatory Parameters & Invariants |
| :--- | :--- | :--- | :--- |
| **Tier 0** *(Mandatory Base)* | `dl_kinematic_params_t` | Point-Mass (`PM`), Kinematic Bicycle (`KS`), Path Trackers (`Stanley`, `PurePursuit`) | `bbox_length` $L_{\text{bbox}}$, `bbox_width` $W_{\text{bbox}}$, `bbox_height` $H_{\text{bbox}}$, `wheelbase` $L$, `overhang_front` $o_f$, `overhang_rear` $o_r$, `max_steer_angle` $\delta_{\max}$, `max_steer_rate` $\dot{\delta}_{\max}$, `steering_ratio` $i_s$.<br>**Invariant:** $L_{\text{bbox}} == L + o_f + o_r$. |
| **Tier 1** *(Dynamic Single-Track)* | `dl_single_track_params_t` | Dynamic Single-Track (`ST`), Linear Tire Slip Models, Dynamic MPC | Total `mass` $m$, `cg_dist_front` $l_f$, `cg_dist_rear` $l_r$, `cg_height` $h_{\text{cg}}$, yaw inertia `inertia_zz` $I_{zz}$, linear cornering stiffnesses `cornering_stiffness_f` $C_{\alpha f}$ and `cornering_stiffness_r` $C_{\alpha r}$, `aero_cd` $C_d$, `aero_area` $A_f$, `rolling_resistance_coeff` $C_{rr}$.<br>**Invariant:** $l_f + l_r == L$. |
| **Tier 2** *(Multi-Body & Powertrain)* | `dl_multibody_params_t` | 14-DOF / 29-DOF Multi-Body (`MB`), SimpleDrivetrain, Full Powertrain & Brake Hydraulics | `sprung_mass` $m_s$, per-axle unsprung masses `unsprung_mass_f` $m_{uf}$ and `unsprung_mass_r` $m_{ur}$, roll/pitch/cross inertias $[I_{xx}, I_{yy}, I_{xz}]$, track widths $(t_f, t_r)$, per-wheel suspension stiffness $(K_{sf}, K_{sr})$ and damping $(C_{sf}, C_{sr})$, anti-roll stiffness $(K_{\text{arb},f}, K_{\text{arb},r})$, `tire_effective_radius` $R_{\text{eff}}$, `wheel_polar_inertia` $I_w$, `max_drive_torque` $T_{\text{drive,max}}$ (peak engine or motor output-shaft torque, before the gearbox), `max_brake_torque` $T_{\text{brake,max}}$ (total brake torque summed over all wheels, at the wheels), `final_drive_ratio` $i_{\text{fd}}$, `gear_ratios[10]` $i_g$. Peak drive torque at the wheels in gear $g$ is $T_{\text{drive,max}} \, i_g \, i_{\text{fd}}$.<br>**Invariant:** $m_s + m_{uf} + m_{ur} == m$. |
| **Tier 3** *(External Solver Deck)* | `dl_custom_deck_t` | Pacejka Magic Formula `.tir`, IPG CarMaker, Adams/Car | `deck_type` (`NONE`, `PACEJKA_TIR`, `SOLVER_URI`), `precedence_mode` (`OVERRIDE_TIER1_2` or `SUPPLEMENT_ONLY`), and `uri[256]`, a null-terminated path or URI to the deck file. Deck contents are never inlined. |

## 3.1 Compile-Time Tier Verification & Single Source of Truth
1. **Compile-Time Tier Check:** Every physics and control component declares its minimum required `vehicle_spec` tier (`required_tier: 0 | 1 | 2`). Binding or splicing a component whose `required_tier` is not populated in the actor's `vehicle_spec` is a **compile-time error**.
2. **Control-to-Physics Tier Compatibility:**
   * A Tier 0 physics model (`KinematicBicycle`) accepts **only** Tier A `KinematicControlFrame`. Wiring an `ActuatorControlFrame` into `KinematicBicycle` is rejected at compile time.
   * A Tier 1 physics model (`DynamicSingleTrack`) accepts `KinematicControlFrame` natively (using only Tier 0 + Tier 1 parameters), or accepts `ActuatorControlFrame` when preceded by an explicit drivetrain adapter. The standard adapter is `SimpleDrivetrain: ActuatorControlFrame -> KinematicControlFrame`. It requires Tier 2 powertrain parameters $T_{\text{drive,max}}, T_{\text{brake,max}}, R_{\text{eff}}, i_g, i_{\text{fd}}$, and it converts steering with $\delta = $ `steering_wheel_norm` $\cdot \, \delta_{\max}$.
3. **No Divergent Geometry Overrides:** Physical geometry and mass parameters (`Tier 0`, `Tier 1`, `Tier 2`) belong exclusively to the actor's `vehicle_spec` and **cannot** be overridden inline on individual controller or physics blocks. This guarantees that World collision detection, warm-start trim, and all pipeline stages share a single immutable source of truth.
