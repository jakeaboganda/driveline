---
title: DSL static semantics
section: 16
version: 0.94
status: draft
normative: true
depends_on: [00-conformance.md, 02-conventions.md, 03-vehicle-parameters.md, 04-perception.md, 05-checkpoints.md, 07-fmu-packaging.md, 09-abi.md, 10-composition.md, 11-execution.md, 12-grammar.md, 15-manifest.md, 17-standard-library.md]
---

# 16. DSL Static Semantics

[§12](12-grammar.md) defines which texts parse. This section defines which parsed scenarios are valid and what their names and expressions mean. Every "must" in this section that a scenario breaks is a compile-time error.

## 16.1 Types

* **Quantities:** A quantity is a binary64 value with a dimension over meters, kilograms, and seconds. Radians and degrees are dimensionless, so `rad/s` and `Hz` have the same dimension. The compiler stores every quantity in SI units ([§2](02-conventions.md)).
* **Named quantity types:** `Scalar` (dimensionless), `Angle` (dimensionless), `Length` (m), `Velocity` (m/s), `Acceleration` (m/s²), `Jerk` (m/s³), `AngularVelocity` (1/s), `Frequency` (1/s), `Mass` (kg), `Force` (N), `Torque` (N·m), and `Pressure` (Pa).
* **`Time`:** A signed 64-bit count of nanoseconds ([§2](02-conventions.md)). It has dimension s but is an integer type.
* **Other scalar types:** `Int` (signed 64-bit), `Bool`, and `String`.
* **Structured types:** The checkpoint frames of [§5](05-checkpoints.md), the slice types of [§4.3](04-perception.md), `Timestamped<T>`, `SliceBuffer<T, N>`, `Rate`, and `RouteNodes`. `Timestamped<T>` has the members `t` (`Time`) and `data` (`T`), and `x.f` means `x.data.f` for every field `f` of `T` ([§4.2](04-perception.md)). A struct field has the type its table gives. A `float64` field is a quantity with the dimension of its unit column, an integer field is `Int`, a `char[]` field is `String`, and an enum field has its enum type.
* **Enum types:** `LonMode`, `LatMode`, `TurnSignal`, `GearMode`, `InterpMode` (`Interpolate`, `Floor`), and `Mount` (`FrontBumper`, `Windshield`, `Center`), with the constants listed in [§4](04-perception.md), [§5](05-checkpoints.md), and [§17](17-standard-library.md).
* **`VehicleSpec`:** The type of a `vehicle_spec` name ([§16.6](16-static-semantics.md)). **`OpenDriveMap`:** The type of `load_xodr`, a world-truth type ([§0](00-conformance.md)).
* **`Chain<A, B>`:** A chain whose pipe input has type `A` and whose output has type `B`. A chain whose head binds every input port by name is a source chain, with type `Chain<(), B>`. `()` is written only as the first argument of `Chain`.
* **Arrays:** `[T]` is an array of `T`. An array literal has type `[T]` when every element has type `T`. Arrays are allowed only where a signature or rule names an array type: `RouteNodes(nodes: [String])`, `gear_ratios`, and per-actor arguments of a group chain ([§10](10-composition.md)). Any other array literal is a compile-time error.
* **Actor:** An actor name has the members `id` (`Int`), `state` (`KinematicState`), and `sensors.<name>` (the sensor's `SliceBuffer<T, N>`).

## 16.2 Literals

* A `QuantityLit` has the dimension of its unit, and its value is converted to SI.
* A `QuantityLit` with dimension s has type `Time` where the expected type is `Time`. Elsewhere it is a quantity. A `Time` literal must be a whole number of nanoseconds.
* An `IntLit` or `HexLit` has type `Int`. Where a quantity is expected, an `Int` converts to a dimensionless quantity.
* A `FloatLit` is a dimensionless quantity.

## 16.3 Expressions

* `+` and `-` require operands of the same dimension, or two `Time` values. `*` and `/` multiply and divide dimensions. `Time * Int` and `Time / Int` are `Time`.
* Comparisons require operands of the same dimension. When a `Time` meets a quantity of dimension s, the `Time` converts to seconds.
* Comparisons have type `Bool`. `and`, `or`, and `not` take and return `Bool`. `==` and `!=` also accept `Int`, `String`, and enum operands of the same type.
* The condition of `if`, `on`, and `terminate when` must have type `Bool`.
* An unqualified enum constant, such as `Interpolate`, is allowed where the expected type is that enum. Elsewhere it must be qualified, as in `GearMode::DRIVE`.
* A dimension mismatch, or an operand of the wrong type, is a compile-time error.

## 16.4 Names and Scopes

Names resolve from the innermost scope outward. A name declared twice in one scope is a compile-time error.

| Scope | Names |
| :--- | :--- |
| File | Imported components, `vehicle_spec` names, `component` names, and `fn` names. |
| Scenario | Actor names. In `terminate when` and `on` conditions only: `sim_time` (`Time`, [§11](11-execution.md)). |
| Actor body | `sensors.<name>`, `priors.<name>`, and the actor's chain names. |
| Component body | Input port names and `param` names. Inside `bind_inputs` and `step`, also `own_state` (`KinematicState`, the actor's own committed state, [§9.1](09-abi.md)). Inside `step`, also its parameters and `let` names. |

* **World Separation:** `actor.state` and `sim_time` are allowed only in `terminate when` and `on` conditions. Using them anywhere else, including as a component argument, is a compile-time error. Components see the World only through sensors, priors, host map callbacks, and their own actor's `own_state` ([§1.1](01-scope.md)).
* **Field Selectors:** The first argument of `rate_of` is a field name of the buffer's slice type, resolved in that type's scope. It must name a `float64` field. `window` must be an `Int` of at least 1. `Rate.value` has the field's dimension divided by time, and `Rate.valid` is `Bool`.
* **Actor IDs:** Every `spawn` must pass `id:` as an `Int` literal of at least 1. IDs must be unique within the scenario. `0` means "no actor" in frame fields such as `gap_target_actor_id`.

## 16.5 Calls and Chains

* **Component calls** take named arguments only. A named argument is either an input port of the component or a parameter ([§15.4](15-manifest.md)). Builtin functions and constructors take the positional or named arguments that the standard library defines for each of them.
* **Pipe input:** In `A >> B(...)`, the value from `A` goes to the one input port of `B` that the call does not bind by name. If the number of unbound ports is not exactly one, that is a compile-time error. The head of a source chain binds every input port by name. The head of any other chain, and the head of each `+` branch, leaves exactly one port unbound, and that port is the chain's pipe input.
* **`+`:** Both branches receive the same pipe input ([§10.2](10-composition.md)).
* **`Arbitrate(p, s, via: A())`:** `p` and `s` must have the same chain type `Chain<X, T>`. The arbiter `A` must have ports `primary: T` and `secondary: T`, both unbound in the call, and output `T`. The result has type `Chain<X, T>`.
* **Named chains:** An `Ident` in a pipe expression names a chain declared earlier in the same actor body. Each named chain must be used exactly once, in the actor's `physics` declaration or in another chain.
* **`fn`:** A call to a `fn` substitutes its body chain. `fn` parameters bind by name to values, such as sensor buffers. The body's type must equal the declared `Chain<A, B>`. A `fn` must not call itself, directly or through other `fn`s.
* **Physics and groups:** An actor's `physics` declaration, and the chain in a `bind` statement, must have type `Chain<(), KinematicState>`.
* **`step`:** A `step` block must return a value of the component's output type on every path. `let` names are immutable.
* **`bind_inputs`:** Each expression must be a quantity, an `Int`, or a `Bool`. The runtime writes it to the `Float64` pin as its SI value, as the integer's value, or as 1.0 for true and 0.0 for false. Each pin name must be an input variable in the FMU's `modelDescription.xml`.
* **`bind_outputs`:** `fmu.out("name")` is the value of the named output variable after `fmi3DoStep` ([§7.1](07-fmu-packaging.md)), as a dimensionless quantity. It is allowed only inside `bind_outputs`, and the name must be an output variable of the FMU. Each assignment's value must have the field's type, except that a dimensionless quantity may be assigned to a quantity field and is taken as SI.

## 16.6 Scenario and Vehicle Specification Rules

* **World statements:** A scenario has exactly one `map`, exactly one `timestep` with a value above zero, at most one `seed` (an `Int` from 0 to $2^{63} - 1$), and at most one `environment`.
* **Actor bodies:** Names in one actor's `sensors` block are unique, and so are names in its `priors` block.
* **`vehicle_spec` keys:** The only keys are `tier0`, `tier1`, `tier2`, and `tier3`. `tier0` is required, `tier2` requires `tier1`, and `tier3` requires `tier1`. A present key populates that tier, and the tier rules of [§3](03-vehicle-parameters.md) apply.
* **Tier 0–2 records:** Each value is a record literal. Its field names must be exactly the member names of `dl_kinematic_params_t`, `dl_single_track_params_t`, or `dl_multibody_params_t` in [`abi/driveline_abi.h`](../abi/driveline_abi.h). Padding members and `num_gears` are excluded. Each value must have the dimension of the unit in that member's header comment. `gear_ratios` is an array literal of 1 to 10 dimensionless values, and `num_gears` is its length.
* **Tier 3 record:** Fields `deck_type` (`"PACEJKA_TIR"` or `"SOLVER_URI"`), `precedence_mode` (`"SUPPLEMENT_ONLY"` or `"OVERRIDE_TIER1_2"`), and `uri` (a `String`, with the length limit of [§3](03-vehicle-parameters.md)).
