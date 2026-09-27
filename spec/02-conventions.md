---
title: Units and coordinate conventions
section: 2
version: 0.4
status: draft
normative: true
depends_on: []
---

# 2. Global Units & Coordinate Conventions

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
