---
title: Steady-state cornering solution
section: 8
version: 0.88
status: draft
normative: true
depends_on: [05-checkpoints.md, 06-lifecycle.md, 13-reference-scenario.md, 14-diagnostics.md]
---

# 8. Steady-State Cornering Solution

Cold init ([§6.2.3](06-lifecycle.md)) and promotion and demotion ([§6.2.4](06-lifecycle.md)) use one steady-state solution. The inputs are $v = v_{\text{lon}}$, the yaw rate $\dot{\psi}$, and the physics tier. The lateral acceleration is $a_y = v \dot{\psi}$.

* **Tier 0 (`KS`), and every tier when $v < 1.0\text{ m/s}$:** $v_{\text{lat,ra}} = 0$, $\delta_{\text{ss}} = \delta_{\text{KS}} = \arctan(L \dot{\psi} / v)$ for $v \ne 0$, and $\delta_{\text{ss}} = 0$ when $v = 0$. $\beta_{\text{cg}}$ follows from the transform of [§5.3](05-checkpoints.md). The condition $v < 1.0\text{ m/s}$ includes every reverse speed. The slip-angle formulas below are singular as $v \to 0$ and are not defined for reverse driving, so the kinematic solution applies there.
* **Tier 1 and Tier 2 (`ST`, `MB`), linear tires, $v \ge 1.0\text{ m/s}$:**
  $$F_{yf} = m a_y \frac{l_r}{L}, \quad F_{yr} = m a_y \frac{l_f}{L}, \quad \alpha_f = \frac{F_{yf}}{C_{\alpha f}}, \quad \alpha_r = \frac{F_{yr}}{C_{\alpha r}}$$
  $$v_{\text{lat,ra}} = -v \tan\alpha_r, \qquad \delta_{\text{ss}} = \alpha_f + \arctan\!\left(\frac{v_{\text{lat,ra}} + L \dot{\psi}}{v}\right), \qquad \beta_{\text{cg}} = \arctan\!\left(\frac{v_{\text{lat,ra}} + l_r \dot{\psi}}{v}\right)$$
  At this state the axle forces sum to $m a_y$ and the yaw moment $l_f F_{yf} - l_r F_{yr}$ is zero. Models with nonlinear tires, or with a Tier 3 deck, may refine the solution in their own trim. They must keep $v_{\text{lon}}$ and $\dot{\psi}$.
* **Feasibility:** A steady state is infeasible if $|\delta_{\text{ss}}| > \delta_{\max}$, or if $|a_y| > \mu g$ with $g = 9.80665\text{ m/s}^2$ and $\mu$ the friction coefficient of the friction field at the actor's reference origin. During cold init, an infeasible spawn state is `DL_STATUS_ERR_NUMERIC`, and the run fails before Tick 0 ([§14](14-diagnostics.md)). During promotion or demotion, an infeasible state is also `DL_STATUS_ERR_NUMERIC`.
* **Test Vector (`Sedan_2026`, [§13](13-reference-scenario.md)):** $v = 28.0\text{ m/s}$ and $\dot{\psi} = 0.056\text{ rad/s}$ (radius $500\text{ m}$) give $a_y = 1.568\text{ m/s}^2$, $v_{\text{lat,ra}} = -0.3728\text{ m/s}$, $\delta_{\text{KS}} = 0.00560\text{ rad}$, $\delta_{\text{ss}} = 0.01015\text{ rad}$, and $\beta_{\text{cg}} = -0.01022\text{ rad}$. Keeping $\delta_{\text{KS}}$ with this $v_{\text{lat,ra}}$ would leave the front axle about 25% short of its steady-state force.
