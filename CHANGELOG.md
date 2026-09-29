---
title: Changelog
---

# Changelog

Section numbers refer to the v0.4 document layout.

## 0.203

* An Arbiter's `primary` input is hold-filled and its `secondary` stays raw. With both raw, a single secondary brake could stay held after the override ended. Every producer output updates stored values even if the consumer doesn't step, held trajectories drop expired points as forwarded ones do, and `Lon<T>`/`Lat<T>` edges keep only their group's units.

## 0.202

* Minor fixes: group-instance trim checks are per actor, and FMU communication points restart at each initialization.

## 0.201

* Declared slots (params, call arguments, returns, `bind_outputs`, record fields, world statements) give their expressions an expected type, which the example's `0.18s` param and unqualified enum arguments rely on. `select`'s condition is excluded from the one-type rule, and an example comment no longer contradicts §17.

## 0.200

* The two branches of `+` must end at the same rate, so a merge is an ordinary output. This replaces v0.197's per-branch assertion, which dropped `s_stop` and could hold a stale turn signal. Components that forward time- or pose-relative fields rebase them to their own tick. Latched `LON` units count as held, and a replacement's pre-step latched output is delivered as is.

## 0.199

* Minor fixes: reverse warm-start powertrain values, the map cache unchanged by a tier change, teardown reports reuse the ending error's tick, and PIDSpeedController ignores `s_stop`.

## 0.198

* Fixed two contradictions from v0.186 and v0.194. Nanosecond `uint64` fields are only `Time`, and a `select`/`clamp` call's expected type never converts `Int` arguments. Pipe calls must name components or `fn`s, and `bind_outputs` cannot assign padding or header fields.

## 0.197

* A `+` merge is a new output whenever either branch steps, and it asserts only the stepped branch's units. `s_stop` is measured from the pose at the frame's timestamp, and held repeats are not new outputs. Lane 0 as a `LANE_OFFSET` target is in the §5.1 validity list.

## 0.196

* A splice keeps the edge into an unchanged consumer, with its stored hold values. Latched frames are filled on the connection they travelled, including connections into Arbiters. Minor fixes: sensor import wording and distinct `bind` lists.

## 0.195

* `SimpleDrivetrain` converts CG net force to $\dot{v}_{\text{lon}}$ with the CG lateral velocity $v_{\text{lat}} + l_r \dot{\psi}$. The v0.187 form missed $l_r \dot{\psi}^2$, about 0.39 m/s² at 10 m/s on a 20 m radius. Standard physics rejects an init context with negative $v_{\text{lon}}$.

## 0.194

* Enum-typed frame fields have their named enum type whatever their C type, which keeps the example's `gear_mode = GearMode::DRIVE` valid. Nanosecond `uint64` fields such as `timestamp_ns` are `Time`.

## 0.193

* Minor fixes: `fn` parameter declared types, field C types come from the header, no positional arguments after named ones, and `environment` entries are uses of prelude names.

## 0.192

* Tier changes keep $\psi + \arctan(v_{\text{lat,ra}}/v_{\text{lon}})$, which keeps the path in reverse. The v0.189 `|v_lon|` form did not. Below 1 m/s a tier change keeps the committed wheel angle. Teardown reports carry the ending tick, warm starts in reverse latch `REVERSE`, and the regime-crossing text drops step sizes that simulation did not bear out.

## 0.191

* Only a new producer output updates hold-rule state, and a held output keeps its first filled frame. A connection is the edge into one consumer port for one actor, and a splice keeps the edge into a replaced physics component or chain input. A trajectory frame carries at least one point.

## 0.190

* Frame validity is checked once, by the runtime, on every produced frame in output validation, and a failure is `ERR_INVALID_ARG` of the producer. Consumers, FMUs, and Arbiters receive only valid frames, and the hold rule preserves validity. This replaces per-consumer checks that disagreed across native, FMU, and Arbiter consumers.

## 0.189

* Negative spawn speeds are compile-time errors, and tier-change headings use |v_lon|, so reversing physics can't flip the heading by π. Minor fixes: wrapped demotion yaw, window report times, lane 0 invalid, enum defaults as numbers, accurate crossing descriptions, header unit comments, and no lexer backtracking.

## 0.188

* The hold rule keeps one stored value per hold unit per connection, and a `COUPLED`/`LON`/`LAT` switch clears the other side's stored values. A turn-signal-only frame after a trajectory now fills to `0x18`. Before, the literal rule could revive the latched `LON`/`LAT` units and produce an invalid frame.

## 0.187

* The FMU Units rule covers every parameter variable in both modes, and an `Int` meeting a quantity in `*` or `/` converts. Minor fixes: lane tie-break ordering, the `abi_version` check, report ticks for cold init and splice windows, the full prelude-clash rule, `Enumeration` variables, multi-unit header comments, `uint8` flag typing, `SimpleDrivetrain` emitting $\dot{v}_{\text{lon}}$, and the size of the downward-crossing step.

## 0.186

* Minor fixes: `Time` literals with no typed operand are quantities, and `clamp` never takes `Time`. Longest match covers every token, group chains may bind actors' priors, `history` is capped at 64, and the Mode B `KinematicState` ban is a compile-time error. Also: the downward-crossing claim is accurate, heading distance is defined, reserved FMI names are guarded, cold-init FMU inputs are named, re-trimmed steering bits are set, and the stamping link is fixed.

## 0.185

* Manifest defaults are written in their unit and always sent, so FMU start values never apply. Mode checks cover only asserted units, and a set `0x08` counts as `SPATIOTEMPORAL_TRAJECTORY`. An FMU's missing-unit failure is `ERR_FMU`.

## 0.184

* Cold init projects sensors once, after every actor's spawn state exists, so no sensor sees a half-spawned World.

## 0.183

* Minor fixes: the upward 1 m/s crossing is described correctly (v0.181 overstated it), `FreqLit`/`TimeLit` are single unit atoms, constant arrays are scoped to their two uses, actor names may not shadow file-scope names, the `Time` parameter encoding, the `world_to_frenet` exception, `count` up to $N_c$, frame time offsets, PincerHiveMind's per-member `own`, and `own_state` after a splice window.

## 0.182

* A Mode B FMU cannot be physics, because it has no init context. For FMU consumers, the runtime runs the §5 validity and mode checks before stepping and reports the same codes a native consumer returns.

## 0.181

* Minor fixes: `DynamicSingleTrack` reports kinematic outputs on any step with the low-speed reset, which removes the one-tick `a_lat` drop. A `struct_size` mismatch names its error, jerk and steer-rate limits must be positive, and the pitch sign covers vehicles facing against their lane.

## 0.180

* Quantity literals round once from their exact decimal value. Unit expressions apply left to right. Integer literals must fit 64 bits, and `Int` values must fit narrower fields. A sensor `rate` is a single `FreqLit`.

## 0.179

* The §7.2 parameter setters depend on the mode. Mode A follows its manifest, with `Time` as nanoseconds. Mode B follows each variable's type, with `Time` as seconds on a `Float64`, and takes only `Float64`, `Int64`, and `Boolean` variables. This removes the contradiction that v0.175 introduced.

## 0.178

* Minor fixes: splice setup call order, heading-frame contact points, a well-typed `collision` signature, clearer `a_lon` updates, manifest units for `Bool`/enum/`Time`, compile-time map checks for spawns and routes, and `select`/`clamp` pass on `Time` to literals.

## 0.177

* Wheel slip at a warm start after tick 0 comes from the committed state, with no steady-state solve. Grade and bank signs follow the lane's driving direction, which matches the σ formula. `Time` values reach `Float64` pins and parameters in seconds. FMU initialization inputs are read in the splice window.

## 0.176

* Minor fixes: splice teardown and instantiation order, per-actor physics in `bind` order, §14 FMU teardown links §7.2, oversized array counts name their error, `a_ref` and trajectory $a_k$ are speed rates, path curvature is positive left, trajectory speeds are non-negative, and pitch excludes the gimbal points.

## 0.175

* Input ports are limited to frame, buffer, and route types. Frame ports are fed only by pipes, and by-name port arguments must be sensor buffers or priors. `bind a` means `bind [a]`. Other fixes: qualified component calls are errors, `uint64` fields fit `Int`, and Mode B `Float64` parameters take the dimension of their declared unit.

## 0.174

* `ttc_lon` runs to bumper contact by subtracting the ego's extent ahead of the mount. Before, Windshield-mounted sensors reported a positive TTC at contact. `JerkLimiter` stores its output as the next step's state.

## 0.173

* The header names the heading frame for `KinematicState` velocities and accelerations, matching §5.3. Sensor frames use heading-frame axes, so roll and pitch never tilt a mount.
* ABI version 0.15.

## 0.172

* An FMU that never reached Step Mode gets no `fmi3Terminate` at teardown. A failed run reports exactly what sequential §11 order produces up to the first error. A re-trim checks only the actors whose tier changed. Init calls finish per instance in Phase 2 order, including multi-component splices.

## 0.171

* Minor fixes: `has_primary_target` is 1 exactly when there is a primary id, and `manual_gear_index` is bounded by `num_gears` in `DRIVE`.

## 0.170

* Mode B parameters take their names and types from `modelDescription.xml`. A full frame converts to `Lon<T>`/`Lat<T>` where one is expected, but a partial frame becomes `T` only through `+`. `fn` buffer arguments may be per-actor arrays. Other fixes: enum constants take precedence where their type is expected, `select`/`clamp` pass on the expected type, sensor `rate` and `history` are required, and a Mode A body is `;`.

## 0.169

* When several calls fail, the reported error is the first in §11 order, so parallel and sequential runtimes agree. Other fixes: the §14 `ERR_FMU` row lists every trigger, a spawn at or past the center of curvature is an error, and the KS heading clause reads as either-or.

## 0.168

* `KinematicState` velocities, accelerations, and yaw rate use a new yaw-only heading frame from §2, which removes the roll and pitch ambiguity for multibody physics. The `GAP_PROFILE` gap comes from the latest sample of the first declared track-bearing port.

## 0.167

* Minor fixes: string and bool literal types, `Int` meeting a quantity in sums and comparisons, a constant `rate_of` window, `FreqLit` sensor rates, `[-]` header units, error codes for `world_to_frenet` and null FMU instances, the FMU context time, the complex-eigenvalue Euler bound, and a §8 typo.

## 0.166

* A splice window solves all tier-change updates in `actor_id` order before it writes any of them, so a failed solve leaves the committed state unchanged. §10 links the Mode A `OneToOne` rule.

## 0.165

* The runtime, not physics, writes `KinematicState`'s map cache, and `KinematicState` outputs ignore the physics values. A Mode A output of the wrong length is `DL_STATUS_ERR_FMU`, and inputs are always exact sizes.

## 0.164

* Builtins live in a prelude scope that user names cannot shadow. Sensors and standard components must be imported from their own section. `spawn` appears only as an actor initializer, and per-actor array elements follow the port's binding and capacity rules.

## 0.163

* Rebuilt latched intents target the committed lane. FMUs run without event mode or early return, and termination flags are errors. Other fixes: padding is zeroed before any read, bounds use $N_c$, standstill braking uses the drivetrain period, and array counts and trajectory order are in the validity list.

## 0.162

* `a_lon_cmd` is the commanded $\dot{v}_{\text{lon}}$, which the physics, init, and latched frames already assume. It is not the body-frame acceleration that `a_lon` reports.

## 0.161

* Minor fixes: a stopped actor reports no deceleration however the stop rounds, `manual_gear_index` is checked only with `0x10` set, and the radar primary target comes from the slice's kept tracks.

## 0.160

* Typed `Int` arithmetic and comparison, with truncating division. Literal sums and products take the expected type. `fn` parameters are limited to buffer, prior, and parameter types, with constant arguments, and the `rate_of` window is a constant. Other fixes: `map` and `let` typing, component output types, and the `input` port name for unnamed standard inputs.

## 0.159

* `sample_lane_path` continues through road links and junction connections as well as lane links, the same way the successor rule does.

## 0.158

* `dl_exit_init_mode` maps to `fmi3ExitInitializationMode` after every initialization. This removes a reading that re-initialized warm-started FMUs at $t = 0$. $t_{\text{first}}$ has a precise definition, and Mode B splices initialize there.

## 0.157

* Minor fixes: the re-trim set is defined by data paths to the physics instance, low-speed `DynamicSingleTrack` reports its clamped acceleration, opposing neighbors don't count as free lanes, the ring layout is in-process only, and a Mode B `valid_mask` that §5 forbids is a compile-time error.

## 0.156

* Splice typing compares the pipe-input and output types, and other ports must be bound by name, as in the example's `DynamicSingleTrack` splice. Array literals of constants are constant, which covers the example's `RouteNodes` prior. Other fixes: a computed negative buffer index is an error, `fn` arguments are named, `[]` takes its expected type, and the untyped-postfix rule covers every expression.

## 0.155

* `fmi3DoStep` uses the running communication point from §7 Times. At initialization, FMU checkpoint ports hold the latched frames, and buffer ports, `own_state`, and `bind_inputs` read the current state.

## 0.154

* At a standstill, `SimpleDrivetrain` decelerates toward zero, capped by the brake and rolling resistance, when the drive force cannot overcome them. Under the previous rule a braking car crept forward below 1 cm/s indefinitely.

## 0.153

* Minor fixes: `Int * Time` is `Time`, `SimpleDrivetrain` uses sgn(0)=0 throughout, the radar primary target and visual lead track break ties by id, physics holds $a$ with no longitudinal bit, steering commands are positive left, FMU units ignore `rad`, and manifests may declare `Bool` and enum parameters.

## 0.152

* Sensors are not components and have no manifest. Their §17.2 table is their signature, a sensor call is a `SliceBuffer<S, N>` with a constant `history`, and `sensors` entries must call sensors.

## 0.151

* Lane sections are half-open in $s$, and `sample_lane_path` keeps its direction across a lane-section boundary. It reverses only by a road link's contact point. `frenet_to_world` names its error code.

## 0.150

* An FMU warm start begins at the component's first scheduled tick, and its communication points are a running binary64 sum from `startTime`, so they stay contiguous.

## 0.149

* Minor fixes: held trajectory shifts take the nanosecond difference first, control frames reject unknown mask bits, `rate_of` windows are at least 1, `timestep` is a `Time`, radar `primary_range`/`primary_azimuth` are defined, contact corners are named, and `left_lane_free` matches tracks by lane.

## 0.148

* Manifest parameter types map to DSL types (`f64` with a unit is a quantity, `i64` is `Int`, `Time` is `Time`) for every call site. A bare pipe identifier must name a chain.

## 0.147

* Components with no data path between them run in source order after `fn` substitution, so call, error, and teardown order are total. A Mode B FMU in a re-trim set keeps its last output, and the latched powertrain gear is `DRIVE`.

## 0.146

* Minor fixes: `environment` friction values link to the constant-expression rule, and untyped postfix forms are errors.

## 0.145

* Output validation runs after the runtime clears out-of-group partial bits. A Mode A re-trim sets priors again after `fmi3Reset`. Physics instances are instantiated after their Stage 2, and a re-trimmed group instance holds its last output for actors whose tier did not change.

## 0.144

* Spawn yaw rate and `sample_lane_path` curvature use the offset curve $\kappa/(1-\kappa d)$, not the centerline, so an offset spawn on a tight curve stays on its path and `StanleyLat` agrees with it.

## 0.143

* A lane's driving-direction successors come from its OpenDRIVE `predecessor` link when it drives against $s$. The `world_to_frenet` tie-break compares `psi` with the driving heading.

## 0.142

* Typed parenthesized chains without `+`, range- and dBsm-valued fields as dimensionless, and prior values as constant `RouteNodes` calls. `bind_outputs` links to §7 for unassigned fields.

## 0.141

* Standard-library gains use `Hz` and `Hz^2`, because `1/s` is not a manifest `UnitExpr`. `check.py` now parses every standard-library parameter unit.

## 0.140

* Minor fixes: `let` block scopes, the `rate_of` time difference and endpoint rule, the clamped `at` result time, the PincerHiveMind and AEB ambiguities, the teardown order in groups, partial-output latching, and table precedence over the state diagram.

## 0.139

* `SliceBuffer` queries and `fmu.out` take positional then named arguments, as builtins do, which covers the example's `eyes.at(...)` and `rate_of(...)`.

## 0.138

* The pre-Pass-1 calls run per instance in Phase 2 order, so the first error and the teardown set are fixed. A re-trimmed rate-divided component holds its latched frame until its next step.

## 0.137

* Minor fixes: latched frames count as the asserting frame for the hold rule, FMU output reading does not shift times, `DynamicSingleTrack` clamps longitudinal acceleration in both regimes, and unused route nodes are zero.

## 0.136

* A `fn` call in a pipe feeds its body's pipe input, which keeps the example's `>> kinematic_coupled_control()` valid. `SliceBuffer` queries have static types and bounds, and builtins may take only named arguments.

## 0.135

* Only a net tier change across a window triggers a re-trim, and the re-trim set holds only instances that serve the changed actor. Each instance gets init contexts only for the actors it serves. §11 explains why an actor never ties with its group in the Phase 2 order.

## 0.134

* Minor fixes: StanleyLat `k` is in 1/s (the example now writes `2.5Hz`), `max_jerk` must be positive, enum fields must hold a listed value, `manual_gear_index` is 0 outside `DRIVE`, manifest modes use the enum names, and frame validation comes before `SimpleDrivetrain`'s torque check.

## 0.133

* Standard physics seeds $a$ from $\dot{v}_{\text{lon}}$ always. The latched command jumped $a$ when a jerk limit was set. At a standstill, `SimpleDrivetrain`'s brake and rolling resistance oppose the drive force, so a partial brake no longer vanishes.

## 0.132

* Held trajectory times are rebased to the filled frame's timestamp, and a held `LON` unit drops `s_stop`, which cannot be moved from an old pose. `rate_of` in §4 links to the rule that limits it to top-level fields.

## 0.131

* Minor fixes: `Bool` equality, `Arbitrate` pipe delivery, one trim warning for a Mode B FMU, the steering wheel sign, and the friction link.

## 0.130

* Tier changes keep $\dot{v}_{\text{lon}}$ by shifting `a_lon` with $v_{\text{lat,ra}}$, and standard physics seeds its acceleration state the same way. Slip angles are 0 below 1 m/s, and `StanleyLat` requires `k_soft` above zero.

## 0.129

* String fields compare up to the null. The runtime zeroes the bytes after it and every padding member, so byte comparisons and FMU payloads are deterministic.

## 0.128

* FMUs get no host map callbacks. Bound FMI variables must use SI units, FMI times are the nearest binary64 seconds, and Mode A values follow the struct layout in little-endian order.

## 0.127

* Actor names are visible across the scenario. An actor's sensors may be used only in its own body, in a `bind` that lists it, or in a `splice` of its targets, and `physics_model` is reserved as a chain name.

## 0.126

* Typed `bool`, struct, and array fields and track indexing. `Time` mixed with a seconds quantity in `+`/`-` is an error. `clamp` needs a quantity, and `Lon<T>`/`Lat<T>` are limited to the two frame types but allowed in `Chain`.

## 0.125

* Every latched frame rebuilt after tick 0 uses the committed speed, offset, and wheel angle. A replacement spliced again before it steps passes on its latched frames.

## 0.124

* `DynamicSingleTrack` sets $r$ and $v_y$ from the kinematic relation whenever the step starts or ends below 1 m/s, so crossing the regime boundary is defined. Steering holds when no steering bit is set, and `sample_step` must be positive.

## 0.123

* `select` and `clamp` convert `Int` only when mixed with a quantity, which keeps the example's `valid_mask` an `Int`. Parameter arguments are constants that match by dimension. `fn` parameters and `fmu` have scopes, buffer methods have signatures, and `use` no longer depends on a greedy `ScopedIdent`.

## 0.122

* Defined `a_lon` and `a_lat` as the rear axle's inertial acceleration in body axes, which is what the standard physics reports. The `KinematicState` timestamp notes that physics runs at the base rate.

## 0.121

* `rate_of` selects only top-level slice fields. Track slots reorder every sample, so a `tracks[i]` difference could span two targets.

## 0.120

* A splice window's tier change is net, and it is applied once. A failed window keeps its committed state update, and a cold-init failure has no committed state. Re-trims exit init mode explicitly in Phase 2 order, warm-start wheel loads use the current grade, `dl_free_instance` is exempt from `ERR_STATE`, and teardown errors do not change the run's outcome.

## 0.119

* Promotion and demotion keep the rear-axle course angle instead of the yaw, as spawn does, so the actor keeps its path. `StanleyLat`'s re-trim mismatch is then exactly $\delta_{\text{ss}} - \delta_{\text{KS}}$.

## 0.118

* Dropped `String` parameters, which `dl_param_t` cannot carry. `Bool` and enum parameters pass as integers natively and have a defined FMI type.

## 0.117

* Completed expression typing: positional builtin arguments (which the example uses), `Time` in `*` and `/`, `select`/`clamp` unification, record literals only in `vehicle_spec`, the `Actor` and `Lon<T>`/`Lat<T>` types, `std` import checks, and named ports.

## 0.116

* Promotions in a splice window update the committed state before any statement runs, and every warm-start context for that actor gets the new steering angle. Latched frames are hold-filled. Types a component never saw are built from the committed state. Hold history survives splices. Only Stage 2 arbiters are re-trimmed, and spliced Stage 2 components get the trim check.

## 0.115

* The hold rule's discard applies to hold units, so a turn-signal-only frame keeps a held trajectory. A component whose required unit stays clear after filling returns `DL_STATUS_ERR_UNSUPPORTED_MODE`, and section 17 lists each standard component's units.

## 0.114

* A Tier 1 or 2 spawn on a curve now points its rear-axle velocity along the lane, so the actor follows the lane instead of drifting 0.37 m/s off it in the test vector. `StanleyLat` measures heading error against the rear axle's course angle. The cold-init `a_lon` is the steady-circle value.

## 0.113

* Tightened physics rules. Jerk limits use $|j_{\text{cmd}}|$, the contact points use each axle's track width, `ttc_lon` is never negative, and `DynamicSingleTrack` states its Euler stability limit.

## 0.112

* Tightened data rules. Positive steering torque turns left, a port's ring has exactly $N_c$ entries, `at` defines the time of its result, and parameter names fit `dl_param_t`.

## 0.111

* Tightened runtime rules. The trim check and range checks apply only to fields whose bits are set, teardown goes instance by instance, cold init orders groups as Phase 2 does, and runtime conformance includes sections 8 and 15.

## 0.110

* Standard physics seeds its acceleration state from the latched command, not the reported `a_lon`. `DynamicSingleTrack` chooses its regime from the tick-$t$ speed and overwrites $r$ and $v_y$ after the step.

## 0.109

* At standstill, cold init steers to the spawn curvature and a tier swap keeps the committed steering angle, instead of snapping to 0.

## 0.108

* Defined what an `environment` block may contain and the range of $\mu$. The `spawn` and sensor signatures type `spec` and `mount`.

## 0.107

* Defined the defaults and range of the `required_tier` and `rate` clauses, `param` types and constant initializers, unary minus typing, and the frame types that `Arbitrate` allows.

## 0.106

* Defined the measured gap for `GAP_PROFILE` as the track's `rel_x`, the quantity that the gap targets refer to. A missing gap target falls back to `v_ref`.

## 0.105

* Mode A binds ports by variable name, and the output is named `output`. FMU parameters use a fixed FMI type for each DSL type, with SI units and nanoseconds for `Time`.

## 0.104

* Listed every valid `IntentFrame` mask. `s_stop` requires `0x01` and is excluded by a trajectory, and `turn_signal` goes with anything.

## 0.103

* `rate_of` wraps angle differences and is invalid across non-finite samples. `ANGLE` interpolation defines the tie at exactly $\pi$.

## 0.102

* `world_to_frenet` succeeds for every finite point, so the Phase 4 map cache update cannot fail when an actor leaves the road.

## 0.101

* Defined the splice window. Each statement finishes, from terminate to exit init, before the next starts. One re-trim follows, and it skips new instances. Latched frames come from the outgoing target's boundary, and a replacement holds its latched frame until its first step.

## 0.100

* Defined every `dl_init_context_t` field at cold init and warm start, including the wheel order FL, FR, RL, RR and `powertrain`. Removed the unused `trim_equilibrium` flag.
* ABI version 0.14.

## 0.99

* A promotion or demotion writes its changed fields into the committed state before warm start, so the physics, the re-trimmed controllers, and the next tick's sensors agree. Defined which splices change tier, including ones made through a chain. The balanced-first-step claim holds only when the re-trim matches.

## 0.98

* `sample_lane_path` continues through the lane link at whichever end it reaches, and handles roads whose reference lines run the other way by keeping `d_offset` on the same side of the path.

## 0.97

* `any` is a reserved word allowed only as `collision`'s second argument, and `collision` reads the World, so it is allowed only in `on` and `terminate when` conditions.

## 0.96

* Defined the three valid component forms (native, Mode A, and Mode B), the `step` signature, and the target type of `bind_outputs`.

## 0.95

* A time literal takes type `Time` when the other operand of `+`, `-`, or a comparison is `Time`.

## 0.94

* Completed the type list: `Timestamped<T>` members, a grammar spelling for `Chain<(), B>`, and array types `[T]` with the places they are allowed.

## 0.93

* Mode A defines the byte order and float format of every `fmi3Binary` value, and a MIME type for prior ports. Times inside frames are relative to the stamped tick time.

## 0.92

* `turn_signal` has its own `AUX` hold unit, so a trajectory frame can signal and a turn-signal-only frame no longer discards a held trajectory. It stays in the `LAT` field group for `+`.

## 0.91

* A component sees its port's `SliceBuffer` view with capacity $N_c$, natively and in Mode A. `rate_of` is per second. Interpolated track lists are re-sorted by the track list rules.

## 0.90

* Defined `PIDSpeedController` state across mode switches. Its integral is rebased on the first velocity step after initialization or `ACCEL_TARGET`, so the output does not jump and no unasserted `v_ref` is read.

## 0.89

* `SimpleDrivetrain` treats a pedal with a clear bit as 0 and rejects gear indexes that are out of range. `BrakeOverrideArbiter` asserts both pedal bits when it takes the secondary's pedals.

## 0.88

* $\beta_{\text{cg}}$ is 0 without Tier 1 and comes from the section 5.3 transform everywhere else. Standard physics reports derivative fields at the new state, so a stopped `DynamicSingleTrack` actor reports no deceleration. The low-speed branch reports the `KinematicBicycle` outputs.

## 0.87

* Defined one teardown for every run end, including success. It calls terminate only where section 6.1 allows, frees every instantiated instance, orders components within an actor, and continues past errors.

## 0.86

* Latched frames prefer the component's own last output, which settles `JerkLimiter`. When no frame of a type has flowed, the runtime builds the frame from the committed state by the cold-init rules.

## 0.85

* A `physics_model` splice of an actor whose physics is a shared group instance is a compile-time error. Per-actor `OneToOne` instances in a group can still be spliced, as the example does.

## 0.84

* Defined the re-trim set: every non-`Lon<T>` Stage 2 instance upstream of the new physics component. The trim check skips `Lon<T>` outputs, which carry no steering. A Mode B FMU is skipped with a warning.

## 0.83

* Section 10 had its own, different summary of `BrakeOverrideArbiter`'s steering rule. It now points to the definition in section 17.

## 0.82

* The example gives the PID gains their units (`1.8Hz`, `0.1Hz^2`). Bare numbers are dimensionless, so the example did not compile. `tools/check.py` now requires units on dimensioned std arguments in the example.

## 0.81

* The primary-target clause of the dependency condition applies only to the `primary_*` fields, so `ego_s` and `ego_d` interpolate again. Primary fields are zero when there is no primary target.

## 0.80

* `StanleyLat` measures its error at the rear axle. At the front axle, the heading error and the curvature term both counted $\delta_{\text{KS}}$, so every curved spawn failed the trim check. An empty path is `DL_STATUS_ERR_INVALID_ARG`.

## 0.79

* Priors no longer read as slow-updating, matching the section 0 definition. `object_class` points to its values in the header.

## 0.78

* Defined the dependency condition once. Interpolation falls back to the older sample only for the dependent fields, not the whole sample. `rate_of` is invalid when no primary target exists.

## 0.77

* Defined section references that name numbered list items, such as §6.2.4. `tools/check.py` verifies that each referenced item exists.

## 0.76

* Declared components are `OneToOne` and read no Tier 3 deck. Mode B declarations accept only `SliceBuffer` inputs.

## 0.75

* Fixed the pipe-input rule. Only a source chain's head binds every port, and other chain heads leave exactly one port unbound as the pipe input.

## 0.74

* Typed `rate_of`: a `float64` field, a window of at least 1, and `Rate.value` with the field's dimension per second. An invalid rate always has `value = 0.0`.

## 0.73

* Comparisons have type `Bool`, and `if`, `on`, and `terminate when` conditions must be `Bool`.

## 0.72

* Splice targets on one actor must not nest, because an earlier splice could remove the later target. Repeated splices of one target are allowed.

## 0.71

* Defined $\bar{\mu}$ in `DynamicSingleTrack`. Stated that `KinematicBicycle` ignores friction, grade, and bank, and that neither model applies grade gravity. A stopped actor keeps no negative acceleration.

## 0.70

* Defined how the runtime computes road grade and bank from the map. Bank is now relative to the direction of travel. The lane direction sign $\sigma$ is defined once, in section 2.

## 0.69

* Defined how the runtime encodes `vehicle_spec`: `populated_tiers_mask`, zeroed absent tiers, `num_gears`, Tier 3 enum values, and the resolved `uri`. `tier2` and `tier3` require `tier1`.

## 0.68

* A conforming runtime also follows sections 4, 5, 7, and 14, and provides the section 17 standard library.

## 0.67

* Trajectory Exclusivity no longer asks for `lat_mode` under a clear `LAT` bit. Bit `0x08` alone requests a trajectory. The hold rule zeroes discarded units and keeps its memory per actor.

## 0.66

* A map road ID longer than 63 bytes is a compile-time error, so every callback's road ID fits `char[64]`.

## 0.65

* Map callbacks follow OpenDRIVE lane links across lane sections within a road, not only at road ends. `query_lane_topology` defines truncation at `max_successors`.

## 0.64

* Added `DL_STATUS_ERR_FMU` for failed FMI calls and bad-sized Mode A outputs. FMU outputs get the same header fields and output validation as native ones, so Mode B frames no longer go out with `timestamp_ns = 0`.
* ABI version 0.13.

## 0.63

* Added section 7.2, which maps each lifecycle call to its FMI 3.0 calls. Parameters are set again after `fmi3Reset`. Mode B cold init now evaluates `bind_inputs` at $t = 0$, the same way a splice does.

## 0.62

* Fixed two stale Stage 3 phrases. Physics runs on every tick, so Phase 3 no longer says "scheduled".

## 0.61

* The section 5 frame tables use the header's field names: `pos_x`…`yaw` instead of `position` and `orientation`, and they now list `num_waypoints` and `num_traj_points`. `tools/check.py` compares every table with its header struct.

## 0.60

* Updated the FMI fact-check item to the FMI calls that section 7 now uses.

## 0.59

* Native components run in process. Out-of-process execution uses Mode A FMUs. This closes the last open design item.

## 0.58

* Added `primary_target_id` to `RadarSlice`. Primary fields interpolate only within one target, and `rate_of` is invalid across a target or road change.
* ABI version 0.12.

## 0.57

* Phase 4 updates each actor's map cache with `world_to_frenet` and a defined hint, so actors in junctions resolve to the same road in every runtime.

## 0.56

* Defined the typing of `bind_inputs` expressions, `fmu.out`, and `bind_outputs` assignments. Pin names must exist in the FMU's model description.

## 0.55

* A re-trim reproduces the new steering angle where the component can, and the runtime checks it with the same tolerance as cold init. Stateless components and Mode B FMUs get a warning instead of breaking a requirement they cannot meet.

## 0.54

* The runtime now applies the hold rule, by hold unit instead of per bit. A per-bit hold could revive a stale steering angle after a switch to rate commands, and could break trajectory exclusivity. Arbiters still see raw frames.
* Latched actuator frames assert pedals, steering, and gear, so every consumer starts with complete frames.

## 0.53

* Derived every `depends_on` from the document's links with `tools/sync_deps.py`. `tools/check.py` requires them to match.
* `tools/check.py` also checks the example's rate divisibility, actor IDs, and sensor history against port capacity.

## 0.52

* Replaced a stale section range in the reference scenario text. `tools/check.py` rejects section numbers written without a link.

## 0.51

* Mode B splices always start a fresh FMU instance. The saved-state restore case is gone. Defined MIME subtype names. A Mode A manifest must be `OneToOne`. Error teardown uses the FMI calls for FMUs.

## 0.50

* Removed a stale version reference from the open items. `tools/check.py` rejects spec-version literals in prose.

## 0.49

* Removed `SensorBundle`, the full-stack bridge rule, and `allow_pose_override`. No sensor produced a `SensorBundle`. A replay actor needs no special rule: it is a source physics chain.
* ABI version 0.11.

## 0.48

* `sim_time` and `actor.state` mean the same in `on` conditions as in `terminate when`. Instances within a group run in `bind` order.

## 0.47

* Defined the latched frames in splice and re-trim contexts. A re-trim replaces only the steering fields, so longitudinal control continues without a step.

## 0.46

* Cold init instantiates and configures every component before Pass 1, physics exits init mode in Pass 3, and Pass 1 fills every `chassis_state` field, including the map cache.

## 0.45

* `PIDSpeedController` initialization computes the integrator from the latched intent and state. Stated `JerkLimiter`'s output mask. `follow_route` takes the first matching route node.

## 0.44

* Added section 16.6: multiplicity of world statements, uniqueness of sensor and prior names, and `vehicle_spec` keys and record fields, taken from the header structs. Added the `VehicleSpec`, `OpenDriveMap`, and `Mount` types.
* `tools/check.py` checks that the example's tier records name exactly the header's fields.

## 0.43

* Removed `static_object`. No section defined its geometry, detection, or collision, and no scenario used it.

## 0.42

* Defined track relative velocity by rigid-body kinematics, the sensor frame orientation, and the arguments of the friction lookup.

## 0.41

* Defined `StanleyLat`'s sampling start and direction, the front-axle point, nearest-point tie-breaking, and the lateral and heading errors. `d_ref` uses the reference-line sign convention of section 2.

## 0.40

* Fixed the order of a standard physics step: actuators first, then derivatives at the old state with the new actuator values, then Euler, then the speed clamp and the planar Z. Defined physics initialization from `chassis_state` and the symbol `dt`.

## 0.39

* Fixed a stale comment in the reference scenario about what `SimpleDrivetrain` outputs.

## 0.38

* Pitch lies in $[-\pi/2, \pi/2]$. Listed the non-SI port fields: normalized commands, confidences, and dBsm.

## 0.37

* Section 3 now defines where the Tier 0 bounding box sits in the body frame. The collision footprint refers to it instead of restating it.

## 0.36

* Added section 17, the standard library: builtins, constructors, and the friction field; ideal sensor models with mounts, detection, and every slice field; and the manifests and equations of `PincerHiveMind`, `PIDSpeedController`, `JerkLimiter`, `StanleyLat`, `SimpleDrivetrain`, `BrakeOverrideArbiter`, `KinematicBicycle`, and `DynamicSingleTrack`.
* `tools/check.py` verifies that the `DynamicSingleTrack` derivatives vanish at the section 8 steady state.
* The reference scenario imports `SimpleDrivetrain` from `std::control` and passes `own_state` to `follow_route`.

## 0.35

* Added section 9.2: semantics, tie-breaking, and out-of-map behavior for the four host map callbacks.
* `query_lane_topology` takes `s`, because OpenDRIVE lane IDs change between lane sections.
* ABI version 0.10.

## 0.34

* Every component now receives its own actor's committed `KinematicState`: `own_states` in `dl_batch_step_io_t`, `own_state` in the DSL, and an `own_state` input on Mode A FMUs. Before this, controllers could not read their own speed.
* `actor_ids` follows group order, not ascending order.
* ABI version 0.9.

## 0.33

* Removed the actor array syntax `actor x[N]`. It had no defined meaning and conflicts with unique literal actor IDs.

## 0.32

* Added section 16, DSL static semantics: types and dimensions, `Time` versus seconds, literals, expression typing, scopes, world separation as a compile-time rule, required unique actor IDs, pipe-input binding, chain types, and `fn` rules.

## 0.31

* Added SipHash-2-4 seed test vectors. `tools/check.py` verifies them against a SipHash implementation that is itself checked against the reference vectors.

## 0.30

* Defined `sensor_port_index` and the default `scenario_seed`.

## 0.29

* Defined the termination check: `sim_time` is $t + \Delta t$, the run ends before `on` statements fire, and the runtime has no contact model.

## 0.28

* Physics runs on every tick. Defined same-tick dataflow in Phase 2 and the values of `t` and `dt` passed to `step`.

## 0.27

* Defined the three cardinalities by instance count and data dependence, the instances in a group chain, and per-actor arrays of arguments.
* Removed the grammar's `cardinality:` clause: scenario-declared components are always `OneToOne`, and library components get their cardinality from their manifest.

## 0.26

* Defined FMU stepping order and the resulting delay of one period, the Mode A splice and re-trim paths, the defaults for unassigned `bind_outputs` fields, and FMU parameter passing.

## 0.25

* Added ABI calling rules for version encoding and equality, strings, pointer lifetimes, output allocation, frame header ownership, step times, and threads.

## 0.24

* Added section 15: JSON component manifests, one component per shared library, resolution of `use` paths, and parameter checking and passing.
* Mode A FMU manifests use the same JSON format.

## 0.23

* Removed the last stale appendix reference. `tools/check.py` now rejects appendix references.

## 0.22

* Track lists have unique IDs, a fixed sort order (range, then ID), truncation to 32, and zero-filled unused entries.

## 0.21

* Replaced the `buffer.underflow` flag with a read-only `buffer.count`. Removed `DL_STATUS_WARN_UNDERFLOW`.
* ABI version 0.8.

## 0.20

* Added `on (...) { splice ... }` statements with chain and `physics_model` targets, type rules, edge-triggered firing, and splice timing. The reference scenario promotes the blocker at 4 s.

## 0.19

* Added a table of legal lifecycle calls. `dl_terminate` is legal from every live state, which the error handling in section 14 needs.

## 0.18

* Removed `dl_on_membership_change` and `dl_membership_change_t`, because no scenario statement can change a group's members.
* Redrew the lifecycle diagram.
* ABI version 0.7.

## 0.17

* Warm start and re-trim pass one init context per affected actor. Components match contexts to slots by `actor_id` and keep the other actors' state.

## 0.16

* Only Stage 2 components must reproduce the latched trim, and the runtime checks it on the first Tick 0 output, since initialization returns no output.

## 0.15

* Added a bit coverage table for `IntentFrame`, rules making `trajectory` exclusive of the `LON` and `LAT` bits, array count limits, the time base for `trajectory`, and the reference point for `s_stop`.

## 0.14

* Defined Tier 3 deck semantics: which components read a deck, what the two precedence modes mean, how a relative `uri` resolves, and which values a deck never overrides.

## 0.13

* Added `reverse_gear_ratio` to Tier 2 and to the reference vehicle.
* ABI version 0.6.

## 0.12

* Tiers 0–2 describe two-axle, four-wheel vehicles. Tier 3 requires Tier 0. `num_wheels` is 0 or 4.
* Cold init skips axle loads and wheel seeding for Tier-0-only actors, which have no mass.
* ABI version 0.5.

## 0.11

* Added a feasibility rule to the steady-state solve: steering beyond $\delta_{\max}$, or lateral acceleration beyond $\mu g$, fails with `DL_STATUS_ERR_NUMERIC`.

## 0.10

* Cold init now takes spawn heading and curvature relative to the lane's driving direction. Before this, actors on lanes that drive toward decreasing $s$ started with a yaw rate of the wrong sign.

## 0.9

* Defined `slip_angle_beta_cg` with atan2 so it stays finite at a standstill and in reverse.
* The single-track steady state applies only at $v \ge 1$ m/s. Reverse and low speeds use the kinematic solution.

## 0.8

* Invariants in the vehicle parameter tiers hold within a relative tolerance of 1e-6, so the result no longer depends on summation order.

## 0.7

* Made the DSL type `Time` signed so that `t - reaction_delay` near $t = 0$ does not wrap. Stored timestamps stay unsigned.

## 0.6

* Added section 14: status code table, runtime handling of warnings and errors, output validation, and report fields.
* Renamed `DL_STATUS_WARN_COLD_FMU` to `DL_STATUS_WARN_FMU_COLD_SPLICE` and added `DL_STATUS_ERR_STATE`. Prose now uses the header names only.
* ABI version 0.4.

## 0.5

* Added section 0: normative language, conformance classes for compilers, runtimes, and components, and a glossary that defines stages by output type.
* Replaced "compliant" with "conforming" and "master" with "runtime".

## 0.4

* Split the single specification file into one document per concern under `spec/`, each with front-matter. Section 6 of v0.3 became sections 6, 7, and 8. Sections 7 to 10 of v0.3 became sections 9 to 13.
* Moved the C header to `abi/driveline_abi.h` and the reference scenario to `examples/kanagawa_pinch_test.dline`.
* Added `tools/check.py`.

## 0.3

* Removed the `[cite: 1]` tags and rewrote the related-work claims as scope statements (§1.2).
* Added sign conventions for road grade and bank, spawn heading from the OpenDRIVE `rule` attribute, a lane reference string format, and nanosecond `Time` (§2).
* Defined `max_drive_torque` at the engine or motor shaft and `max_brake_torque` as the wheel total. Tier 3 decks are referenced by `uri` only (§3). Set `SimpleDrivetrain` to output `KinematicControlFrame` (§3.1).
* Changed `Timestamped<T>` to integer nanoseconds. Added the timestamp invariant, `Rate` validity for `rate_of`, and interpolation classes per field (§4).
* Added field groups, the hold rule for cleared bits, rules for combining steering and jerk bits, and `GAP_PROFILE` measurement rules (§5).
* Replaced the promotion formula with a steady-state solve that balances force and yaw moment, with a test vector (§8). Added demotion and controller re-trim (§6.2.4). Removed the double Tick 0 sensor projection and the $R_{\text{nom}}$ default (§6.2.3).
* Separated the native C-ABI from FMU packaging, and rewrote the Mode B warm-start fallback so that it relies only on standard FMI calls (§7).
* ABI v0.3 (§9): `dl_set_parameters`, a `host_ctx` for callbacks, successor lists, typed per-port step I/O, the SliceBuffer layout, `dl_route_t`, `dl_sensor_bundle_t`, and two new status codes.
* Made `+` a typed merge of `Lon<T>` and `Lat<T>`, restored splicing, and added the physics assignment rule (§10).
* Restored the four tick phases, defined the SipHash-2-4 encoding, and narrowed the determinism guarantee (§11).
* Added expression and lexical grammar, grouping parentheses, and a cardinality clause (§12). Moved the reference scenario to LHT lanes and fixed its Bosch bindings and hard-coded actor ID (§13).

## 0.2

* Revised the first draft after review.

## 0.1

* First draft.
