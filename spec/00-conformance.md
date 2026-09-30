---
title: Conformance and terminology
section: 0
version: 0.250
status: draft
normative: true
depends_on: [02-conventions.md, 04-perception.md, 05-checkpoints.md, 06-lifecycle.md, 07-fmu-packaging.md, 09-abi.md, 10-composition.md, 11-execution.md, 12-grammar.md, 14-diagnostics.md, 15-manifest.md, 16-static-semantics.md, 17-standard-library.md, 18-run-record.md]
---

# 0. Conformance and Terminology

## 0.1 Normative Language

A document whose front-matter says `normative: true` states requirements. A document that says `normative: false` states none. If a non-normative document disagrees with a normative one, the normative document governs.

In normative documents, these words have fixed meanings:
* **must** and **must not** state a requirement.
* **is a compile-time error** means that a conforming compiler rejects the scenario with a diagnostic.
* **is invalid** means that the receiver returns the status code that the sentence names.
* **may** states a permission. **should** states a recommendation that a conforming implementation can ignore.

**Section References:** `§N.M` names the heading numbered N.M. If no such heading exists, it names numbered item M of the list under heading N. For example, [§6.2.4](06-lifecycle.md) is item 4 under heading 6.2.

## 0.2 Conformance Classes

* **Conforming compiler:** Accepts a scenario if and only if it parses under [§12](12-grammar.md) and breaks no rule that the specification calls a compile-time error. Every "must" about scenario text, a declaration, or a manifest is such a rule, wherever it appears. It reports every compile-time error with the rule's section number.
* **Conforming runtime:** Runs an accepted scenario as [§2](02-conventions.md) through [§11](11-execution.md), [§14](14-diagnostics.md), [§15](15-manifest.md), [§18](18-run-record.md), and the run-time rules of [§16](16-static-semantics.md) describe, and provides the standard library of [§17](17-standard-library.md). It calls components only through [§9](09-abi.md) or [§7](07-fmu-packaging.md).
* **Conforming component:** Implements the [§9](09-abi.md) C-ABI or the [§7](07-fmu-packaging.md) FMU packaging, and meets the frame rules of [§5](05-checkpoints.md) and the lifecycle rules of [§6](06-lifecycle.md).

## 0.3 Terms

* **World:** The ground truth that the runtime owns: the map, the friction field, and every actor's `KinematicState`. $X(t)$ is the World state at time $t$.
* **World-truth types:** `OpenDriveMap` (the type of `map`) and `FrictionField` (the type of `environment`). They appear only in scenario world statements. Passing a value of a world-truth type to a component port is a compile-time error.
* **Actor:** A vehicle that the scenario spawns. Each actor has a unique `actor_id`, a `vehicle_spec`, sensors, priors, and exactly one physics component.
* **Tick:** One step of the base clock ([§11](11-execution.md)). Tick $k$ starts at $t = k \cdot \Delta t_{\text{base}}$.
* **Runtime:** The program that runs a compiled scenario. FMI documents call it the importer or master. This specification says runtime.
* **Component:** A unit with typed input ports and one typed output. Its stage follows from its output type:
  * **Sensor (Stage 0):** Projects World state into a `SliceBuffer`. Sensors are part of the runtime and are not called through the C-ABI.
  * **Stage 1 (Intent):** Output `IntentFrame`, `Lon<IntentFrame>`, or `Lat<IntentFrame>`.
  * **Stage 2 (Control):** Output `KinematicControlFrame`, `ActuatorControlFrame`, `Lon<KinematicControlFrame>`, or `Lat<KinematicControlFrame>`. Drivetrain adapters such as `SimpleDrivetrain` are Stage 2.
  * **Stage 3 (Physics):** Output `KinematicState`.
  * An output `Override<T>` has the stage of `T`.
* **Arbiter:** A component with exactly the input ports `primary` of type $T$ and `secondary` of type `Override<T>`, and output type $T$, where $T$ is `IntentFrame`, `KinematicControlFrame`, or `ActuatorControlFrame` ([§16.1](16-static-semantics.md)). Its stage is the stage of $T$.
* **Chain:** A `>>` expression of components ([§10](10-composition.md)).
* **Group:** The actors listed in one `bind [a, b, ...]` statement.
* **Prior:** Actor-mounted data that does not change during a run, such as `RouteNodes` ([§4](04-perception.md)).
