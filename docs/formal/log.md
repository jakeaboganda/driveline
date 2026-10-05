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
