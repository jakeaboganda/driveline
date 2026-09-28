---
title: Composition, arbitration, and splicing
section: 10
version: 0.120
status: draft
normative: true
depends_on: [03-vehicle-parameters.md, 05-checkpoints.md, 06-lifecycle.md, 11-execution.md, 12-grammar.md, 15-manifest.md, 17-standard-library.md]
---

# 10. Composition, Fan-Out (`+`), Arbitration, & Splicing

1. **Sequential Chaining (`>>`):** Connects $A: T_1 \rightarrow T_2$ and $B: T_2 \rightarrow T_3$ into $A \gg B: T_1 \rightarrow T_3$.
   * **Cardinality:** A component declared in the scenario is `OneToOne`. A library component's cardinality comes from its manifest ([§15](15-manifest.md)).

     | Cardinality | Instances | Output for Actor $i$ May Depend On |
     | :--- | :--- | :--- |
     | `OneToOne` | One per actor. `actor_count` is 1. | Actor $i$'s inputs only. |
     | `OneToMany` | One per group. `actor_count` is $M$. | The inputs of every actor in the group. This is centralized coordination. |
     | `ManyToMany` | One per group. `actor_count` is $M$. | Actor $i$'s inputs only. The results must equal those of $M$ `OneToOne` instances. This is batched execution. |

   * **Group Chains:** In `bind [a_1, ..., a_M] -> chain`, each `OneToOne` component in the chain gets $M$ instances, one per actor, and each other component gets one instance for the group. The runtime orders actors by the order of the `bind` list, and `actor_ids` in `dl_batch_step_io_t` follows that order. In an actor's own `chain` or `physics` declaration, every component serves one actor and `actor_count` is 1.
   * **Per-Actor Arguments:** In a group chain, an argument bound to an input port is either one value used by every actor, or an array literal with exactly $M$ elements in `bind` order, such as `vision: [blocker.sensors.surround, challenger.sensors.surround]`. An array of any other length is a compile-time error.
2. **Parallel Split-Merge Operator (`+`):** For $T$ equal to `IntentFrame` or `KinematicControlFrame`, the partial types `Lon<T>` and `Lat<T>` are frames of type $T$ restricted to the `LON` or `LAT` field group of [§5](05-checkpoints.md). A component with output type `Lon<T>` may set only `LON` bits, and the runtime clears any other bits it sets. `Lat<T>` works the same way.
   * **Typing:** $(A + B)$ requires one branch of type $T_{\text{in}} \rightarrow$ `Lon<T>` and one branch of type $T_{\text{in}} \rightarrow$ `Lat<T>`, in either order. The result has type $T_{\text{in}} \rightarrow T$. Two `LON` branches, two `LAT` branches, or more than two branches are compile-time errors, so the two branches can never write the same field.
   * **Evaluation:** The runtime passes the same $T_{\text{in}}$ to both branches. The merged frame takes `LON` fields from the `Lon` branch and `LAT` fields from the `Lat` branch, with `valid_mask = (lon.valid_mask & LON) | (lat.valid_mask & LAT)`. A `+` merge never sets `COUPLED` bits.
   * **Chaining Within a Branch:** A branch can chain partial types, for example `PIDSpeedController: IntentFrame -> Lon<KinematicControlFrame>` followed by `JerkLimiter: Lon<KinematicControlFrame> -> Lon<KinematicControlFrame>`.
3. **Multi-Chain Arbitration (`Arbitrate`):** Merges two parallel chains producing the same checkpoint type $T_{\text{check}}$ (`IntentFrame`, `KinematicControlFrame`, or `ActuatorControlFrame`) via an explicit `Arbiter` component. Arbiters read raw `valid_mask` bits and do not apply the hold rule of [§5](05-checkpoints.md). [§17](17-standard-library.md) defines `BrakeOverrideArbiter`, the standard arbiter.
4. **Type-Safe Splicing:** A scenario replaces components during a run with `on (condition) { splice target = replacement; ... }` ([§12](12-grammar.md)).
   * **Targets:** `actor.name` names a chain that the actor declared with `chain name = ...`, and the replacement is a whole new chain. `actor.physics_model` names the actor's Stage 3 physics component, and the replacement is one Stage 3 component. The splice replaces only that component, and the rest of the physics chain keeps running. If the physics component comes from a `bind` statement and is `OneToMany` or `ManyToMany`, one instance serves the whole group, and a `physics_model` splice of any member is a compile-time error. A `OneToOne` physics component in a group chain has one instance per actor, and the splice replaces that actor's instance only.
   * **Typing:** The replacement must have the same input and output types as the target. A mismatch, an unknown actor, or an unknown chain name is a compile-time error. So are two splice statements on the same actor where one target contains the other: a chain and a chain that it uses, or a chain and `physics_model` when that chain contains the physics component. Two splices of the same target are allowed, and each replaces what is running at the time. The tier check of [§3.1](03-vehicle-parameters.md) applies to the replacement.
   * **Trigger:** The condition is evaluated in Phase 4 of every tick, after the termination check. Each `on` statement fires at most once, on the first tick where its condition is true. Statements that fire on the same tick run in source order.
   * **Timing:** Splices run between ticks, after Phase 4 of the firing tick and before Phase 1 of the next tick. Before the first statement, the runtime finds every promotion and demotion that the window causes and applies their committed state update ([§6.2.4](06-lifecycle.md)). A tier change is net for the window: it compares the actor's physics tier before the first statement with its tier after the last. Every instance warm-started in the window uses that one updated state. It then completes each splice statement, in source order, before it starts the next. For each one it captures the latched frames of the outgoing target ([§6.2.4](06-lifecycle.md)), calls `dl_terminate` and `dl_free_instance` on every outgoing instance, instantiates the replacement, gives it its parameters and structural configuration, and calls `dl_enter_warm_start` and then `dl_exit_init_mode`. After all statements, the runtime performs one re-trim for the actors whose physics tier changed. Instances created in this window are not part of the re-trim set, because their warm start already used the updated state.
   * **Output Before the First Step:** Until a replacement component first steps under the scheduling rule of [§11](11-execution.md), its held output is the latched frame of its output type. A `physics_model` splice between tiers is a promotion or demotion and triggers the re-trim of [§6.2.4](06-lifecycle.md).
5. **Physics Assignment Rule:** Each actor gets exactly one Stage 3 physics component, from either its `physics` declaration or one `bind` statement. An actor with zero or two physics components is a compile-time error.
