---
title: Composition, arbitration, and splicing
section: 10
version: 0.4
status: draft
normative: true
depends_on: [05-checkpoints.md]
---

# 10. Composition, Fan-Out (`+`), Arbitration, & Splicing

1. **Sequential Chaining (`>>`):** Connects $A: T_1 \rightarrow T_2$ and $B: T_2 \rightarrow T_3$ into $A \gg B: T_1 \rightarrow T_3$. A component's cardinality is `OneToOne` unless its declaration (`cardinality:` clause, [§12](12-grammar.md)) or its library manifest says otherwise. When a `OneToMany` component feeds $M$ actors into a `OneToOne` downstream component (e.g., `PincerHiveMind >> kinematic_coupled_control()`), the runtime creates $M$ independent instances of the downstream chain, one per bound actor.
2. **Parallel Split-Merge Operator (`+`):** For $T$ equal to `IntentFrame` or `KinematicControlFrame`, the partial types `Lon<T>` and `Lat<T>` are frames of type $T$ restricted to the `LON` or `LAT` field group of [§5](05-checkpoints.md). A component with output type `Lon<T>` may set only `LON` bits, and the runtime clears any other bits it sets. `Lat<T>` works the same way.
   * **Typing:** $(A + B)$ requires one branch of type $T_{\text{in}} \rightarrow$ `Lon<T>` and one branch of type $T_{\text{in}} \rightarrow$ `Lat<T>`, in either order. The result has type $T_{\text{in}} \rightarrow T$. Two `LON` branches, two `LAT` branches, or more than two branches are compile-time errors, so the two branches can never write the same field.
   * **Evaluation:** The runtime passes the same $T_{\text{in}}$ to both branches. The merged frame takes `LON` fields from the `Lon` branch and `LAT` fields from the `Lat` branch, with `valid_mask = (lon.valid_mask & LON) | (lat.valid_mask & LAT)`. A `+` merge never sets `COUPLED` bits.
   * **Chaining Within a Branch:** A branch can chain partial types, for example `PIDSpeedController: IntentFrame -> Lon<KinematicControlFrame>` followed by `JerkLimiter: Lon<KinematicControlFrame> -> Lon<KinematicControlFrame>`.
3. **Multi-Chain Arbitration (`Arbitrate`):** Merges two parallel chains producing the same checkpoint type $T_{\text{check}}$ (`IntentFrame`, `KinematicControlFrame`, or `ActuatorControlFrame`) via an explicit `Arbiter` component. Arbiters read raw `valid_mask` bits and do not apply the hold rule of [§5](05-checkpoints.md). For example, `BrakeOverrideArbiter` uses the secondary's `throttle` and `brake` when `secondary.valid_mask & 0x02` is set. It passes `primary.steering_wheel_norm` through whenever `secondary.valid_mask & 0x04 == 0`.
4. **Type-Safe Splicing:** When the runtime splices a component or sub-chain $C_{\text{new}}: T_{\text{in}} \rightarrow T_{\text{out}}$ into an actor's pipeline at $t > 0$, it matches $(T_{\text{in}}, T_{\text{out}})$ against the replaced sub-chain. It moves the outgoing sub-chain to `Terminated`, initializes $C_{\text{new}}$ through `WarmStartMode` ([§6.2.4](06-lifecycle.md)), and swaps the two between ticks. Appendix A lists the DSL syntax for splice triggers as an open item.
5. **Physics Assignment Rule:** Each actor gets exactly one Stage 3 physics component, from either its `physics` declaration or one `bind` statement. An actor with zero or two physics components is a compile-time error.
