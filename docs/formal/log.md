# Work package log

One entry per landed work package, newest last.

## WP00 Component lifecycle

`Driveline.Lifecycle` models the §6.1 Allowed Calls table. Eight theorems, rows L06-01 to L06-08. Found one spec defect: the §6.1 note named only omitted `dl_free_instance` edges, and the diagram also omits four `dl_terminate` edges. Fixed in spec v0.283.

## WP-tools Ledger checker

`tools/check_formal.py` gates the ledger. The first version matched theorem names with regular expressions; review showed that nested comments, string literals, indented `axiom`, and `sorryAx` all got past it. It now asks Lean: each `PROVED` or `REFUTED` name must be a theorem constant, and `#print axioms` must list nothing beyond `propext`, `Classical.choice`, and `Quot.sound`. A build that reports `declaration uses` fails too.

## WP01 Frames, validity, merge, arbiter (§5, §10.2–10.3)

Modules `F64`, `Frames`, `Validity`, `Merge`, `Arbiter`. `F64` models binary64 values as finite reals plus the infinities and NaN, with IEEE comparisons and no rounding. 36 rows proved, including §10.2's "two valid partial frames always merge into a valid full frame" (`Driveline.Merge.merge_valid`).

Review changed two verdicts:

* P10-12 had been refuted with an arbiter baseline on a lane that is not in the map. The committed lane always comes from `world_to_frenet` (§11 Phase 4, §9.2) or the spawn lane, so that state is unreachable. The model now carries the map-lane invariant and the row is proved.
* P05-20 had been reported as a spec gap: a NaN `v_ref` passes the §5 rule "not negative". §14.2 checks finiteness before §5 validity, so a NaN never reaches that rule. The model now has the §14.2 pipeline (`outputCheck`), and the bound-field rows are stated on it.

Deferred clauses became rows in their owning packages: P05-40 (WP04), P05-41, P05-42, P10-40 (WP08), P05-43 (WP12).

No spec defect found in WP01.

## WP02 Vehicle and object spec encoding (§3)

Module `VehicleSpec`: the DSL-level spec, the `dl_vehicle_spec_t` encoding, the tier mask, the §3.1 tolerance, and the object encoding. 29 rows proved, 2 refuted, 2 deferred to WP10 (steady state of objects, `num_wheels`).

Review rejected one refutation. P03-22 claimed that `steering_wheel_norm · δ_max` can exceed `δ_max` when `δ_max < 0`. Every spawned actor passes the §8 feasibility check at cold init (`08-steady-state.md:19`, `|δ_ss| ≤ δ_max`), which forces `δ_max ≥ 0` before any component steps. The row is proved from feasibility.

Spec defects found (queued for the spec-fix pass):

* **P02-09** `03-vehicle-parameters.md` and `02-conventions.md:19`. The CG is placed both at `l_r` ahead of the rear axle and at `l_f` behind the front axle, and the §3.1 tolerance lets the two readings differ. Two implementations can place the CG at different points (`Driveline.VehicleSpec.cg_readings_disagree`).
* **P03-12** `03-vehicle-parameters.md` Tier 2. Only `i_R > 0` is constrained. A negative `max_drive_torque` or `final_drive_ratio` passes every check and turns the reverse drive torque toward `+x` (`Driveline.VehicleSpec.rev_torque_toward_pos_x`).

## WP03 SliceBuffer queries and track lists (§4)

Modules `Angles` (`wrap` to `(-π, π]`), `SliceBuffer` (buffer views, `latest`, history clamp, `rate_of`, `at` in both modes, the ring index), and `Tracks` (per-slice interpolation, dependency conditions, track matching, sort and truncation). 26 rows proved, plus P04-11 and P04-18 in WP09 through `wrap`.

The specifier had refuted P04-09 with `rate_of(window: 0)`, which divides by zero. The implementer found that `16-static-semantics.md:69` requires `window ≥ 1`, so the counterexample is unreachable; the row is proved under that rule.

Review added theorems for the `rate_of` value rules (P04-42 to P04-45), the glue from `at()` to each slice's interpolation, and the unmatched-track rule. It moved P02-12 to WP07 and P02-13, P02-14 to WP09. P04-41 (non-finite samples in `at()`) stays open.

No spec defect found in WP03.

## WP04 Tick schedule and FMU time (§11, §7)

Modules `Schedule` (tick times, rate validity over ℚ, scheduling and zero-order hold, same-tick dataflow, phase order, actor and group order, chain order, Phase 2 commutation) and `FmuTime` (communication points under an abstract rounding, `t_first`, the FMI call mapping). All 25 rows proved, plus P05-40 (redelivery on ticks where the producer does not step).

The specifier had refuted P11-25: read pair by pair, the 11:27 tie-break could order calls in a cycle. The implementer modeled chain expressions from the grammar and proved that every data path runs from an earlier call to a later one, because frame ports are bound only through `>>`, `+`, and `Arbitrate` (`16-static-semantics.md:75`). Under that model the 11:27 order is the left-to-right call order, so the row is proved.

Review strengthened P07-08 and P07-09: FMI contiguity is now a predicate over the call sequence the runtime emits, not the definition of the points restated.

Spec gaps found (queued for the spec-fix pass):

* **P11-25** `11-execution.md:27`. "Call order in the chain expression after `fn` substitution" does not say where a named chain sits once inlined. For `Arbitrate(Pri(), s, ...)` with `chain s = Sec()`, inlining gives Pri before Sec and source order gives Sec before Pri. Two runtimes can order independent components differently, which changes report order.
* **P07-40** `07-fmu-packaging.md:46`. "One period later than a native component with the same logic" names no comparator. Informative text; it should say so or be dropped.

## WP05 Diagnostics and run record (§14, §18)

Modules `Diagnostics` (status severity, first failing call, parallel reports, teardown order, output-validation order, report ticks) and `RunRecord` (the JSON Lines encoding, line framing, record structure, collision lines, tick rules). 22 rows proved; P14-08 is a duplicate of the WP00 teardown theorem.

The specifier had proposed five refutations, among them "overlapping static actors get no collision line" and "teardown reports come after the error". Each turned out to be behavior the spec states on purpose (the static-pair exception in 11:24, the report order in 18:25), so all five rows are proved as written.

Review strengthened P18-01 (header `files` entries are typed, and a framing theorem shows `\n` only ends a line and whitespace appears only inside strings), P14-12 (teardown reports carry the tick of the error that ended the run), and P14-07 (teardown order is descending by smallest `actor_id`). Binary64 number formatting is P18-40, `OUT: external`. P11-40 (deriving the run model's contact pairs from the contact test) stays open.

No spec defect found in WP05.

## WP06 Manifest, types, units (§15, §16)

Modules `Units` (dimension vectors, unit atoms, the left-to-right `UnitExpr` fold, the §3.1 tolerance over ℝ), `Types` (DSL types, the conversion relation, `Time` arithmetic with truncating division and overflow, literal ranges), and `Manifest` (signature sources, manifest validity, mode lists, parameter passing). 37 rows proved.

The specifier had refuted P15-13: the `dl_param_t` type tag does not tell `i64`, `Time`, `Bool`, and enum apart, and long names do not fit. The receiver reads each value by the type its own manifest declares (`15-manifest.md:48`), and `09-abi.md:21` makes a name over 55 bytes a compile-time error, so the row is proved as a typed round trip. P16-05 was a claim the inventory guessed (a preorder); the spec states only the conversion rules and one output covariance, and those are proved.

Review added Int64 range checks on `i64` and `Time` defaults, typed the parameter round trip, and let a field without a `modes` entry accept `NONE`.

Spec gaps found (queued for the spec-fix pass):

* **P15-13** `15-manifest.md:48`. An enum parameter's `default` is "its numeric value", and no rule says the number must name a member of the enum. One compiler can reject `9` for `GearMode` while another passes it to `dl_set_parameters`.
* **P15-11** `15-manifest.md:49`. A `modes` entry for a mode field that the component's inputs do not have, or a misspelled key, is neither required to be rejected nor allowed. An ignored misspelling also silently means "accepts every mode" for the real field.
* **P03-41** `03-vehicle-parameters.md:31`. With no upper bound on tier values, an invariant whose sum overflows to infinity passes the binary64 tolerance (`inf ≤ inf`). Recorded `OUT: external`; the spec may want a finiteness or magnitude rule.

## WP07 C-ABI rules (§9)

Module `Abi`: version encoding, `char[N]` strings as zero-padded bytes, `fmi3Binary` payload sizes and little-endian words, the ring view in `uint32_t`, output memory layout, header stamping, lane-section partition, the `world_to_frenet` tie-break, successor truncation, MIME subtype names. 21 rows proved, 2 refuted.

Review rejected one refutation. P09-06 had shown overlapping outputs with `output_stride = 0`. §9.1 has the runtime write `actor_id` into every output frame after `dl_do_step` writes every entry, so a stride below `sizeof(T)` makes the runtime's own duties unsatisfiable. The row is proved: entries are disjoint for every write order exactly when the stride is at least `sizeof(T)`.

Spec defects found (queued for the spec-fix pass):

* **P09-02, P09-03** `09-abi.md:20`. `(major << 16) | (minor << 8)` collides once `minor` reaches 256: version 0.256 encodes as 1.0. Nothing bounds `minor`, and `tools/bump.py` increments it without limit. The §15.3 manifest check compares the strings and rejects; `dl_instantiate` and the init-context check compare the integers and accept (`Driveline.Abi.refute_compatible`).
* **P09-21** `09-abi.md:33`. A lane can contain a point at two values of `s` (a loop or a helical ramp). The tie-break key has no `s` component, so `world_to_frenet` may return either `(s, d)` (`Driveline.Abi.refute_unique_s`).
* **P09-23** `09-abi.md:35`. `sample_lane_path` defines no result when `κ·d ≥ 1`, where the offset curvature has a pole. §6.2 makes the same case an error at spawn.
* **P09-06** (note) `09-abi.md:23` should state `output_stride ≥ sizeof(T)`, and a multiple of 8 so `double` fields stay aligned.

## WP08 Splice, init contexts, tier change (§6.2, §10.4)

Modules `InitContext` (Pass 1 spawn geometry, slip and gear rules, latched frames, conversion at t > 0, contexts per actor), `TierChange` (promotion and demotion field updates, steering after a tier change, the re-trim set), and `Splice` (splice typing, conflicts, firing, the all-or-nothing committed update, ordering). 41 rows proved, including P06-40 and P06-41, which review added: at t > 0 every latched frame of a non-`Override` type is again in baseline modes in every group.

Promotion and demotion write at most the five stated fields and keep `v_lon`, `ψ̇`, the course angle `χ`, and `v̇_lon` (`Driveline.TierChange.promote_fields`, `promote_chi`). The P10-16 refutation was withdrawn: `16-static-semantics.md:27` lets a `Chain` convert only to a non-partial output, so a partial target admits only an equal type.

Spec defects found (queued for the spec-fix pass):

* **P06-04** `06-lifecycle.md:73`. "So the rear-axle velocity is tangent to the lane and the actor follows it." With `ψ̇₀ = v₀ κ₀` and a nonzero rear-axle lateral speed, the rear axle moves at `√(v₀² + v_lat²)`, so its path curvature is `κ₀ v₀ / √(v₀² + v_lat²)`, not `κ₀`. Tangency holds at spawn; following the lane does not. With the §8 test vector the error is about 0.009 %.
* **P06-21** `06-lifecycle.md:84`. "Five fields change." At most five change; below 1 m/s, none do.
* **P06-19, P06-22** `06-lifecycle.md:84`. `γ` is defined as 0 at `v_lon = 0`, so demoting a state with `v_lon = 0` and `v_lat ≠ 0` drops the lateral speed without keeping the path.
* **P06-32** `06-lifecycle.md:88`. "A component whose input and output types are equal ... gets its own last output." For `Lon<T> → Lon<T>` the latched frame is the merged frame at its `+`, which matches its own output only in the stated group.

## WP09 Angles and rigid-body kinematics (§2, §5.3)

Module `Kinematics`, with additions to `Angles` (the ISO 8855 rotation and the body x axis), `Tracks` (lane reference strings, driving direction, road grade and bank), and `SliceBuffer` (angle interpolation). 24 rows proved, 1 refuted.

The rotation is shown to be the intrinsic Z-Y'-X'' sequence and to lie in SO(3). `a_lon` and `a_lat` are proved to be the heading-frame components of the derivative of the world velocity (`HasDerivAt`), not just restated. Review added the §2 pitch relation: a vehicle facing its lane's driving direction on a road of grade `θ_road` has ISO pitch `−θ_road` (`Driveline.Angles.pitch_of_road_grade`, P02-40), and the bank sign (P02-41, which takes the OpenDRIVE superelevation as an angle in `(−π/2, π/2)`, recorded as P02-42 `OUT: external`). The odometer is proved never to decrease under any monotone rounding.

Spec defect found (queued for the spec-fix pass):

* **P05-35** `05-checkpoints.md:124`. "`β_cg = arctan(l_r/L · tan δ) ≠ 0` for `v_lon ≠ 0`" is false for straight-ahead steering, which a straight-lane spawn reaches (`Driveline.Kinematics.ks_betaCg_ne_zero_false`). The intended reading, "need not be 0", is proved for `tan δ ≠ 0` (P05-46).

## WP10 Steady state and axle loads (§6.2, §8)

Modules `SteadyState` (the `KS` and `ST` solutions, feasibility, the understeer approximation, the steady-circle accelerations) and `AxleLoad` (static axle loads, the facing test, per-wheel loads). 11 rows proved, 4 refuted, 1 duplicate; P03-40 (the solve reads Tier 1, never deck values) stays open.

Spec defects found (queued for the spec-fix pass):

* **P08-03, P06-23** `08-steady-state.md:16-18`, `06-lifecycle.md:84`. §8 divides by the wheelbase `L`, and §3.1 accepts `l_f + l_r` within `10⁻⁶` of `L`. The axle forces then sum to `m a_y (l_f + l_r)/L` rather than `m a_y`, and `DynamicSingleTrack` is not balanced at the first step even with the exact `δ_ss`. `tools/check.py`'s `1e-9` "derivatives vanish" check passes only because the Sedan values sum exactly in binary64; with an accepted `L` scaled by `1 + 10⁻⁶` the residuals are about `10⁻⁶`. Same root cause as P02-09.
* **P06-23** `06-lifecycle.md:84`. "Balanced at the first step if the upstream steering command reproduces `δ_ss`, that is, if the re-trim reports no `DL_STATUS_WARN_TRIM_MISMATCH`." The trim check passes within `10⁻³` rad, where the front lateral force is off by about `C_αf · 10⁻³` (`Driveline.SteadyState.dst_not_balanced`).
* **P06-07** `06-lifecycle.md:76`. "An uphill road moves load to the rear axle" needs `h_cg > 0`, and §3 and §16 set no range for Tier 1 values (`Driveline.AxleLoad.uphill_no_transfer`). Same root cause as P03-12: vehicle parameters have no sign or positivity rules.
* **P06-03** `06-lifecycle.md:73`. Confirms the WP08 finding P06-04: with `ψ̇₀ = v₀ κ₀` the rear axle does not follow the lane when `v_lat ≠ 0` (`Driveline.SteadyState.rear_path_not_followed`).

## WP11 Contact test (§11)

Module `Contact`. 9 rows proved, including P11-40 from WP05: the run model's collision lines are derived from the contact test over the committed states, so a pair gets at most one line, on its first tick in contact, and a run that fails before Phase 4 of its last tick tests no state it never committed.

The central theorem is `Driveline.Contact.footprintContact_iff_inter`: the §11 separating-axis test over the four edge normals holds exactly when the two closed footprints intersect, so "touching counts" is exact. It is proved with Helly's theorem over the four slabs. The test is symmetric in the two actors, exactly, even in binary64, because the axis set and the projections do not depend on argument order. Rotation invariance holds over ℝ only; the binary64 clause is `OUT: external`.

No spec defect found in WP11.
