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
