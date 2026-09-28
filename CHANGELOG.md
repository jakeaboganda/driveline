---
title: Changelog
---

# Changelog

Section numbers refer to the v0.4 document layout.

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
