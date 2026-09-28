---
title: DSL static semantics
section: 16
version: 0.156
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
* **Structured types:** The checkpoint frames of [§5](05-checkpoints.md), the slice types of [§4.3](04-perception.md), `Timestamped<T>`, `SliceBuffer<T, N>`, `Rate`, and `RouteNodes`. `Timestamped<T>` has the members `t` (`Time`) and `data` (`T`), and `x.f` means `x.data.f` for every field `f` of `T` ([§4.2](04-perception.md)). A struct field has the type its table gives. A `float64` field is a quantity with the dimension of its unit column, an integer field is `Int`, a `bool` field is `Bool`, a `char[]` field is `String`, an enum field has its enum type, and a struct field has its struct type. A `float64` field whose unit column gives a range such as $[0, 1]$, a logarithmic unit such as dBsm, or no unit is a dimensionless quantity. An array field `f[N]` of a struct is read only as `x.f[i]`, where `i` is an `Int`. A constant `i` outside $[0, N)$ is a compile-time error, and a computed one makes the step return `DL_STATUS_ERR_INVALID_ARG`. Entries at or beyond `num_tracks` are zero-filled ([§4.3](04-perception.md)).
* **Enum types:** `LonMode`, `LatMode`, `TurnSignal`, `GearMode`, `InterpMode` (`Interpolate`, `Floor`), and `Mount` (`FrontBumper`, `Windshield`, `Center`), with the constants listed in [§4](04-perception.md), [§5](05-checkpoints.md), and [§17](17-standard-library.md).
* **`VehicleSpec`:** The type of a `vehicle_spec` name ([§16.6](16-static-semantics.md)). **`OpenDriveMap`:** The type of `load_xodr`, a world-truth type ([§0](00-conformance.md)).
* **`Chain<A, B>`:** A chain whose pipe input has type `A` and whose output has type `B`. A chain whose head binds every input port by name is a source chain, with type `Chain<(), B>`. `()` is written only as the first argument of `Chain`.
* **Arrays:** `[T]` is an array of `T`. An array literal has type `[T]` when every element has type `T`, and `[]` takes its type from the expected array type. Arrays are allowed only where a signature or rule names an array type: `RouteNodes(nodes: [String])`, `gear_ratios`, and per-actor arguments of a group chain ([§10](10-composition.md)). Any other array literal is a compile-time error.
* **`Lon<T>` and `Lat<T>`:** Partial frame types ([§10.2](10-composition.md)), where `T` is `IntentFrame` or `KinematicControlFrame`. They may be a component's output type, a port type, or a `Chain` type argument.
* **Records:** A record literal is allowed only as a `vehicle_spec` tier value ([§16.6](16-static-semantics.md)). Any other record literal is a compile-time error.
* **`Actor`:** The type of an actor name. It has the members `id` (`Int`), `state` (`KinematicState`), and `sensors.<name>` (the sensor's `SliceBuffer<T, N>`).

## 16.2 Literals

* A `QuantityLit` has the dimension of its unit, and its value is converted to SI.
* A `QuantityLit` with dimension s has type `Time` where the expected type is `Time`. The expected type of an operand of `+`, `-`, or a comparison is the type of the other operand, so `t - 0.1s` is `Time`. Elsewhere it is a quantity. A `Time` literal must be a whole number of nanoseconds.
* An `IntLit` or `HexLit` has type `Int`. Where a quantity is expected, an `Int` converts to a dimensionless quantity.
* A `FloatLit` is a dimensionless quantity.

## 16.3 Expressions

* A postfix `.name`, `(...)`, or `[...]` that no rule of this section types is a compile-time error, in every expression.
* `+` and `-` require two `Time` values, which give a `Time`, or two quantities of the same dimension. A `Time` and a quantity of dimension s is a compile-time error, because the result would need rounding to nanoseconds. A literal of dimension s takes `Time` from the other operand ([§16.2](16-static-semantics.md)). `*` and `/` multiply and divide dimensions. `Time * Int`, `Int * Time`, and `Time / Int` are `Time`. When `Time` meets any other operand of `*` or `/`, it converts to a quantity in seconds, so `v * dt` is a `Length`, and `Time / Time` is a dimensionless quantity.
* Comparisons require operands of the same dimension. When a `Time` meets a quantity of dimension s, the `Time` converts to seconds.
* `-x` has the type of `x`, and `x` gets the expected type of `-x`, so `-0.1s` is `Time` where `Time` is expected.
* Comparisons have type `Bool`. `and`, `or`, and `not` take and return `Bool`. `==` and `!=` also accept `Int`, `Bool`, `String`, and enum operands of the same type.
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
| `fn` body | The `fn`'s parameter names. |
| Component body | Input port names and `param` names. Inside `bind_outputs`, also `fmu`, usable only as `fmu.out(...)`. Inside `bind_inputs` and `step`, also `own_state` (`KinematicState`, the actor's own committed state, [§9.1](09-abi.md)). Inside `step`, also its parameters and `let` names. |

* **Imports:** `use std::m::{...}` must name a module and components or sensors of [§17](17-standard-library.md). Other imports follow [§15.2](15-manifest.md).
* **Actors:** An actor name is visible in the whole scenario, including before its declaration. `a.sensors.n` may appear only in `a`'s own actor body, in a `bind` statement whose list contains `a`, or in a `splice` whose target belongs to `a`. Any other use is a compile-time error.
* **World Separation:** `actor.state`, `sim_time`, and calls to `collision` are allowed only in `terminate when` and `on` conditions. `any` is allowed only as the second argument of `collision`. Using them anywhere else, including as a component argument, is a compile-time error. Components see the World only through sensors, priors, host map callbacks, and their own actor's `own_state` ([§1.1](01-scope.md)).
* **Field Selectors:** The first argument of `rate_of` is a field name of the buffer's slice type, resolved in that type's scope. It must name a top-level `float64` field of the slice type, so track fields inside `tracks[]` cannot be selected. `window` must be an `Int` of at least 1. `Rate.value` has the field's dimension divided by time, and `Rate.valid` is `Bool`.
* **Actor IDs:** Every `spawn` must pass `id:` as an `Int` literal of at least 1. IDs must be unique within the scenario. `0` means "no actor" in frame fields such as `gap_target_actor_id`.

## 16.5 Calls and Chains

* **Component calls** take named arguments only. A named argument is either an input port of the component or a parameter ([§15.4](15-manifest.md)). Builtin functions and constructors take zero or more arguments positionally in the order of their [§17](17-standard-library.md) signature, followed by any named arguments. `SliceBuffer` queries, whose signatures follow, and `fmu.out(name: String)` take arguments the same way. An argument given both ways, or missing without a default, is a compile-time error. `select` and `clamp` need arguments of one type `T`, which for `clamp` must be a quantity type. Only if at least one of those arguments is a quantity does an `Int` argument convert to a dimensionless quantity, so `select(c, 0x03, 0x00)` is an `Int` and `clamp(n, 0, 5)` with an `Int` `n` is a compile-time error. A `SliceBuffer<T, N>` port has exactly the queries of [§4.2](04-perception.md): `latest()`, `b[k]` and `history(k)` with an `Int` `k`, `at(t_query: Time, mode: InterpMode)`, and `rate_of(field, window: Int = 1)` with a `window` of at least 1, plus the member `count` (`Int`). A constant `k` outside $[0, N)$ is a compile-time error, and a computed negative `k` makes the step return `DL_STATUS_ERR_INVALID_ARG`. A `Timestamped<T>`'s `t` is the sample's `t_ns` as a `Time`.
* **Pipe input:** In `A >> B(...)` where `B` is a component, the value from `A` goes to the one input port of `B` that the call does not bind by name. If the number of unbound ports is not exactly one, that is a compile-time error. The head of a source chain binds every input port by name. The head of any other chain, and the head of each `+` branch, leaves exactly one port unbound, and that port is the chain's pipe input.
* **`+`:** Both branches receive the same pipe input ([§10.2](10-composition.md)).
* **`Arbitrate(p, s, via: A())`:** `p` and `s` must have the same chain type `Chain<X, T>`. `T` must be `IntentFrame`, `KinematicControlFrame`, or `ActuatorControlFrame` ([§10](10-composition.md)). The arbiter `A` must have exactly the input ports `primary: T` and `secondary: T`, both unbound in the call, and output `T`. The result has type `Chain<X, T>`. If `X` is not `()`, the pipe input goes to both `p` and `s`.
* **Grouping:** `(P)` with no `+` has the chain type of `P`.
* **Named chains:** An `Ident` in a pipe expression must name a chain declared earlier in the same actor body. Any other name there, including a component written without `(...)`, is a compile-time error. Each named chain must be used exactly once, in the actor's `physics` declaration or in another chain.
* **`fn`:** A call to a `fn` substitutes its body chain. In `A >> f(...)`, the value from `A` goes to the body chain's pipe input, and `fn` parameters are never pipe inputs. `fn` parameters bind by name, never positionally, to values, such as sensor buffers. The body's type must equal the declared `Chain<A, B>`. A `fn` must not call itself, directly or through other `fn`s.
* **Physics and groups:** An actor's `physics` declaration, and the chain in a `bind` statement, must have type `Chain<(), KinematicState>`.
* **Component forms:** A `component` declaration has one of these forms. Any other combination is a compile-time error.

  | Form | `from_fmu` | Body |
  | :--- | :--- | :--- |
  | Native | Absent | A block with exactly one `step` block, any number of `param` declarations, and no bind blocks. |
  | Mode A FMU ([§7](07-fmu-packaging.md)) | Present | `;` |
  | Mode B FMU ([§7](07-fmu-packaging.md)) | Present | A block with exactly one `bind_inputs` and exactly one `bind_outputs`, and nothing else. |

* **Declaration clauses:** An omitted `required_tier` clause means `required_tier: 0`. Its value must be 0, 1, or 2. An omitted `rate` clause means the base rate ([§11](11-execution.md)).
* **`param`:** A parameter's type must be a quantity type, `Time`, `Int`, `Bool`, or an enum. Its initializer must have that type and be a constant expression: literals, enum constants, arithmetic on them, and array literals of constant expressions, with no names. A manifest parameter ([§15](15-manifest.md)) of type `f64` with unit $u$ is a quantity of $u$'s dimension, `i64` is `Int`, `Time` is `Time`, `Bool` is `Bool`, and an enum name is that enum type. A call-site argument for a parameter, of a declared or a library component, must have the parameter's type, where quantity types match by dimension, and must be a constant expression. An actor's `id` counts as a constant.
* **`step`:** Its signature must be `step(t: Time, dt: Time) -> T`, with `T` the component's output type. `t` is the tick time and `dt` the component's period ([§9.1](09-abi.md)). The block must return a value of type `T` on every path. `let` names are immutable. Each `{ ... }` block opens a nested scope.
* **`bind_inputs`:** Each expression must be a quantity, an `Int`, or a `Bool`. The runtime writes it to the `Float64` pin as its SI value, as the integer's value, or as 1.0 for true and 0.0 for false. Each pin name must be an input variable in the FMU's `modelDescription.xml`.
* **`bind_outputs`:** `fmu.out("name")` is the value of the named output variable after `fmi3DoStep` ([§7.1](07-fmu-packaging.md)), as a dimensionless quantity. It is allowed only inside `bind_outputs`, and the name must be an output variable of the FMU. In `bind_outputs -> T`, `T` must be the component's output type, and each assigned name must be a field of `T`, assigned at most once. Unassigned fields, including `valid_mask`, follow [§7](07-fmu-packaging.md). Each assignment's value must have the field's type, except that a dimensionless quantity may be assigned to a quantity field and is taken as SI.

## 16.6 Scenario and Vehicle Specification Rules

* **World statements:** A scenario has exactly one `map`, exactly one `timestep`, a `Time` above zero, at most one `seed` (an `Int` from 0 to $2^{63} - 1$), and at most one `environment`.
* **`environment`:** The block may contain `default_friction = ...;` at most once and any number of `friction_zone(...)` calls ([§17.1](17-standard-library.md)), and nothing else. Every $\mu$ must be a constant expression ([§16.5](16-static-semantics.md)) in $[0, 2]$. A `friction_zone` must name a road of the map and have `s_start` < `s_end`.
* **Actor bodies:** Names in one actor's `sensors` block are unique, and so are names in its `priors` block. Each `sensors` entry must call a sensor of [§17.2](17-standard-library.md), with named arguments of the types its table gives. A chain may not be named `physics_model`, which [§10.4](10-composition.md) reserves as a splice target. Each prior value must be a `RouteNodes(...)` call with constant arguments, since `RouteNodes` is the only prior type ([§4.1](04-perception.md)).
* **`vehicle_spec` keys:** The only keys are `tier0`, `tier1`, `tier2`, and `tier3`. `tier0` is required, `tier2` requires `tier1`, and `tier3` requires `tier1`. A present key populates that tier, and the tier rules of [§3](03-vehicle-parameters.md) apply.
* **Tier 0–2 records:** Each value is a record literal. Its field names must be exactly the member names of `dl_kinematic_params_t`, `dl_single_track_params_t`, or `dl_multibody_params_t` in [`abi/driveline_abi.h`](../abi/driveline_abi.h). Padding members and `num_gears` are excluded. Each value must have the dimension of the unit in that member's header comment. `gear_ratios` is an array literal of 1 to 10 dimensionless values, and `num_gears` is its length.
* **Tier 3 record:** Fields `deck_type` (`"PACEJKA_TIR"` or `"SOLVER_URI"`), `precedence_mode` (`"SUPPLEMENT_ONLY"` or `"OVERRIDE_TIER1_2"`), and `uri` (a `String`, with the length limit of [§3](03-vehicle-parameters.md)).
