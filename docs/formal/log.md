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
