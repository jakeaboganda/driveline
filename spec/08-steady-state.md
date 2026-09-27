---
title: Steady-state cornering solution
section: 8
version: 0.4
status: draft
normative: true
depends_on: [03-vehicle-parameters.md]
---

# 8. Steady-State Cornering Solution

Cold init ([§6.2.3](06-lifecycle.md)) and promotion and demotion ([§6.2.4](06-lifecycle.md)) use one steady-state solution. The inputs are $v = v_{\text{lon}}$, the yaw rate $\dot{\psi}$, and the physics tier. The lateral acceleration is $a_y = v \dot{\psi}$.

* **Tier 0 (`KS`), and every tier when $|v| < 1.0\text{ m/s}$:** $v_{\text{lat,ra}} = 0$, $\delta_{\text{ss}} = \delta_{\text{KS}} = \arctan(L \dot{\psi} / v)$, and $\delta_{\text{ss}} = 0$ when $v = 0$. The slip-angle formulas below are singular as $v \to 0$, so the kinematic solution applies at low speed.
* **Tier 1 and Tier 2 (`ST`, `MB`), linear tires:**
  $$F_{yf} = m a_y \frac{l_r}{L}, \quad F_{yr} = m a_y \frac{l_f}{L}, \quad \alpha_f = \frac{F_{yf}}{C_{\alpha f}}, \quad \alpha_r = \frac{F_{yr}}{C_{\alpha r}}$$
  $$v_{\text{lat,ra}} = -v \tan\alpha_r, \qquad \delta_{\text{ss}} = \alpha_f + \arctan\!\left(\frac{v_{\text{lat,ra}} + L \dot{\psi}}{v}\right), \qquad \beta_{\text{cg}} = \arctan\!\left(\frac{v_{\text{lat,ra}} + l_r \dot{\psi}}{v}\right)$$
  At this state the axle forces sum to $m a_y$ and the yaw moment $l_f F_{yf} - l_r F_{yr}$ is zero. Models with nonlinear tires, or with a Tier 3 deck, may refine the solution in their own trim. They must keep $v_{\text{lon}}$ and $\dot{\psi}$.
* **Test Vector (`Sedan_2026`, [§13](13-reference-scenario.md)):** $v = 28.0\text{ m/s}$ and $\dot{\psi} = 0.056\text{ rad/s}$ (radius $500\text{ m}$) give $a_y = 1.568\text{ m/s}^2$, $v_{\text{lat,ra}} = -0.3728\text{ m/s}$, $\delta_{\text{KS}} = 0.00560\text{ rad}$, $\delta_{\text{ss}} = 0.01015\text{ rad}$, and $\beta_{\text{cg}} = -0.01022\text{ rad}$. Keeping $\delta_{\text{KS}}$ with this $v_{\text{lat,ra}}$ would leave the front axle about 25% short of its steady-state force.
