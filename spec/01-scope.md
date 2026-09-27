---
title: Scope, principles, and related work
section: 1
version: 0.5
status: draft
normative: false
depends_on: []
---

# 1. Scope, Architectural Principles, & Related Work

**Driveline** is a deterministic, component-first scenario description language and execution architecture for road-driving simulation. It separates ground-truth world state from per-actor behavioral, control, and physical compute pipelines, and it specifies the control and vehicle-dynamics contracts that existing scenario standards leave to the host simulator.

## 1.1 Core Architectural Principles

This section summarizes the design. It states no requirements. The normative sections govern ([§0](00-conformance.md)).

1. **Three-Level World vs. Actor Separation:**
   * **Lexical Level:** A `.dline` scenario file serves as the top-level simulation manifest: it declares the physical world (`map`, `environment`, `static_object`), spawns actor entities with initial physical states, and binds each actor's initial component graph.
   * **Type Level:** World truth types (`OpenDriveMap`, `FrictionField`) cannot be passed as inputs to Stage 1 (Intent) or Stage 2 (Control) components.
   * **Runtime Memory Level:** Pipeline components execute in isolated memory contexts and cannot query global world state directly. They access external context only through actor-mounted `SliceBuffer<T, N>` sensor ports, `priors`, and the read-only host map callbacks ([§9](09-abi.md)).
   * **Stated Ground-Truth Exceptions:** Two inputs are ground truth by design. The host map callbacks give every component the exact OpenDRIVE geometry (a perfect-map prior). Standard sensors report the true `target_actor_id` of each track (ideal data association). A sensor model that simulates map error or association error must produce those errors itself.
2. **Intra-Tick Acyclic Dataflow Chains (`>>`):** Within any single simulation tick $t$, an actor's motion pipeline is a strictly typed Directed Acyclic Graph (DAG) of signal transformers connected via the pipe operator (`>>`). Across ticks, the loop closes through the World ($X(t) \xrightarrow{\text{Phase 1}} \text{SensorSlice}(t) \xrightarrow{\text{Phase 2}} \text{IntentFrame}(t) \xrightarrow{\text{Phase 2}} \text{ControlFrame}(t) \xrightarrow{\text{Phase 3}} X(t + \Delta t)$), imposing a well-defined one-tick ($1 \cdot \Delta t_{\text{base}}$) sensing-to-actuation latency.
3. **Zero Implicit Control Glue:** The runtime prohibits hidden controller conversions (such as unparameterized speed-to-acceleration gains or implicit pedal maps) between mismatched components. All cross-tier conversions must be declared as explicit, parameterized adapter blocks in the chain, while pure geometric map queries are provided via deterministic host callbacks.
4. **FMI 3.0 Layered Component Model & Cardinality Agnosticism:** Driveline standardizes port data contracts and lifecycle transitions rather than internal component implementations, allowing native DSL state trees, Behavior Trees, ONNX models, Simulink FMUs, or C++ binaries to be swapped freely. Components support $1\text{:}1$ per-actor bindings, $1\text{:}N$ centralized coordination ("Hive Mind" intent), and $N\text{:}N$ vectorized batch execution.

## 1.2 Related Work & Standards Positioning

The table below states what each related standard covers and where Driveline differs. The comparative claims in the third column describe scope. They are not measured results. Appendix A lists the claims that still need a checked reference.

| Standard / Framework | Scope Covered | Not Covered | How Driveline Relates |
| :--- | :--- | :--- | :--- |
| **ASAM OpenSCENARIO (v1.x XML & v2.x DSL)** | Scenario orchestration, actor spawning, and composable behavior modifiers. | Controller and vehicle-dynamics models. The host simulator supplies them, so two tools can run the same scenario with different dynamics. | Adds per-actor `Intent >> Control >> Physics` pipelines with typed control and physics contracts. |
| **ASAM OSI (Open Simulation Interface)** | Protobuf schemas (`SensorView`, `SensorData`, `TrafficCommand`, `TrafficUpdate`) for sensor and traffic co-simulation. | Intra-actor control arbitration, mid-run component swaps, and a scenario authoring DSL. | Sensor slices ([§4.3](04-perception.md)) follow OSI object semantics. Runtimes may fill them from OSI messages. |
| **CommonRoad Vehicle Models (Althoff et al.)** | Model equations and parameter sets for Point-Mass (`PM`), Kinematic Single-Track (`KS`), Single-Track (`ST`), and Multi-Body (`MB`) vehicles. | Multi-rate co-simulation and component lifecycle. | Tiers 0–2 follow the same model ladder (`KS`, `ST`, `MB`). Driveline parameter names and units are its own. A mapping to CommonRoad parameter sets is not yet specified. |
| **FMI 3.0 & ASAM SSP** | Binary packaging (`.fmu`), clocks, `fmi3Binary` variables, and static system topology (`SystemStructure.ssd`). | OpenDRIVE queries, timestamped sensor history, and component swaps during a run. | Native components use the Driveline C-ABI ([§9](09-abi.md)). Components packaged as FMUs use the layered standard `org.driveline.dcm` ([§7](07-fmu-packaging.md)), which uses only standard FMI 3.0 functions. |
