---
title: Execution model and determinism
section: 11
version: 0.57
status: draft
normative: true
depends_on: [06-lifecycle.md, 09-abi.md, 10-composition.md]
---

# 11. Deterministic Integer-Tick Execution Model

1. **Integer Nanosecond Base Clock & Tick Divisors:** The simulation clock advances by integer tick index $k_{\text{tick}} \in \{0, 1, 2, \dots\}$ with base period $\Delta t_{\text{base\_ns}} \in \mathbb{Z}^+$ nanoseconds ($t_{\text{ns}} = k_{\text{tick}} \cdot \Delta t_{\text{base\_ns}}$).
   * **Exact Rate Divisibility Rule:** A sensor or component rate $f_{\text{comp}}$ is valid only if some positive integer $k_{\text{div}}$ satisfies $k_{\text{div}} \cdot \Delta t_{\text{base\_ns}} \cdot f_{\text{comp}} = 10^9$ exactly. The compiler checks this rule with exact rational arithmetic. Any other rate (such as `30Hz` on a `500Hz` base clock) is a **compile-time error**.
   * **Default Component Rate:** Any component that omits a `(rate: ...)` clause inherits the base clock rate ($k_{\text{div}} = 1$).
   * **Scheduling Rule:** A component with divisor $k_{\text{div}}$ executes on tick $k_{\text{tick}}$ if and only if $(k_{\text{tick}} \bmod k_{\text{div}}) == 0$, and holds its output constant via Zero-Order Hold (ZOH) on intermediate ticks.
   * **Physics Rate:** Stage 3 components run on every tick ($k_{\text{div}} = 1$). A `rate` clause on a Stage 3 component is a compile-time error.
   * **Same-Tick Dataflow:** In Phase 2, a component reads each upstream output as it stands after the upstream's most recent step at or before the current tick. That includes a step earlier in the same Phase 2, because components run in topological order. So within one tick, an intent change reaches the controller and then physics with no added delay.
   * **Step Arguments:** A scenario-declared component's `step(t, dt)` receives $t$, the tick time, and $dt = k_{\text{div}} \cdot \Delta t_{\text{base}}$, its own period.
2. **Phases Within a Tick:** Each tick runs four phases in this order:
   1. **Phase 1 (Sensor Projection):** Scheduled sensors project World state $X(t)$ into each actor's `SliceBuffer`s. Tick 0 skips Phase 1 because cold initialization Pass 1 has done it ([§6.2.3](06-lifecycle.md)).
   2. **Phase 2 (Intent, Control, & Arbitration):** Scheduled Stage 1, Stage 2, and Arbiter components step.
   3. **Phase 3 (Physics):** Scheduled Stage 3 components compute $X(t + \Delta t)$.
   4. **Phase 4 (World Commit & Termination Check):** The runtime commits $X(t + \Delta t)$ and updates each actor's map cache (`road_id`, `lane_id`, `frenet_s`, `frenet_d`) with `world_to_frenet` at the new pose, passing the actor's yaw as `psi` and its previous `road_id` as `hint_road_id` ([§9.2](09-abi.md)). Then it evaluates `terminate when`. Inside the predicate, and inside `on` conditions, `sim_time` is $t + \Delta t$ and `actor.state` is the committed `KinematicState`. If the predicate is true, the run ends successfully after this phase, and no `on` statement fires on this tick. Otherwise the runtime evaluates `on` statements ([§10.4](10-composition.md)).
   * **No Contact Model:** The runtime does not model contact between actors. Actors can overlap. `collision(...)` is a predicate on committed state that a scenario can use to end the run.
3. **Deterministic Intra-Phase Ordering & Seeding:**
   * Within Phase 1, Phase 2, and Phase 3, actors and groups are evaluated in ascending order of `actor_id` (and topological chain order within each actor). A group sorts by its smallest member `actor_id`, and within a group, per-actor instances run in `bind` order. Because Phase 2 components only read Phase 1 `SliceBuffer` snapshots from $X(t)$ and write to actor-local checkpoint buffers, Phase 2 is data-race-free and parallelizable across actors.
   * Each stochastic sensor gets a 64-bit seed per tick: `SipHash-2-4(key, msg)`. The 128-bit `key` is `scenario_seed` as a little-endian `uint64` followed by 8 zero bytes. The 24-byte `msg` is `actor_id` (little-endian `uint64`), `sensor_port_index` (little-endian `uint32`), 4 zero bytes, and `k_tick` (little-endian `uint64`). `sensor_port_index` is the zero-based position of the sensor in its actor's `sensors` block, in source order. `scenario_seed` is the value of the scenario's `seed` statement, or 0 if the scenario has none. The sensor's random generator algorithm is part of the sensor's versioned implementation. Test vectors: `scenario_seed = 42`, `actor_id = 1`, `sensor_port_index = 0`, `k_tick = 0` gives `0x5cc6f959467d3eca`. `scenario_seed = 42`, `actor_id = 3`, `sensor_port_index = 1`, `k_tick = 25` gives `0xb818879e7dfe5b11`.
4. **Determinism Guarantee & Scope:**
   * **Same Build, Same Platform:** A conforming runtime produces bit-identical results for the same scenario, seed, runtime build, component binaries, and platform.
   * **Across Platforms:** Bit-identical results across platforms or compilers are guaranteed only if the runtime and every component meet three conditions. They use one correctly rounded math library for transcendental functions (`sin`, `atan`, `exp`, and the rest), because platform `libm` implementations differ in the last bit. They are compiled without fast-math and without floating-point contraction (`-ffp-contract=off`), so no compiler fuses operations into FMA. They use IEEE 754 binary64 arithmetic with round-to-nearest-even.
   * **External Components:** FMUs and ONNX models must run single-threaded. ONNX Runtime components run on the CPU execution provider with `ORT_SEQUENTIAL` and one intra-op thread. GPU inference does not conform in this version.
