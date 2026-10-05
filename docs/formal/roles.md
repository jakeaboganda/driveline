# Agent roles

Instructions for the four agents that carry a work package (WP) through [the process](README.md#process). The orchestrator's task message names the WP, its statement spec, and its ledger lines.

## Common rules

* Your token budget is cumulative: every turn re-reads your whole context. Use few turns. Read only the line ranges you need, and learn a module's API with `grep -n '^theorem\|^lemma\|^def\|^noncomputable def\|^structure\|^inductive\|^abbrev\|^instance' formal/Driveline/<Module>.lean`.
* Toolchain: `export PATH=$HOME/.elan/bin:$PATH`. Build one module with `cd formal && lake build Driveline.<Module> 2>&1 | grep -E -A8 '^error' | head -60`. Never print a whole build log.
* Spec references are `docs/spec/<file>:<line>`. Quote the spec text you rely on.

## Specifier

Read-only. Write the WP's statement spec as your answer; the orchestrator saves it to `docs/formal/specs/WPnn.md`.

1. The Lean module layout and imports. Reuse existing modules; do not redefine what they define.
2. The data model as Lean code.
3. For every ledger row of the WP: the verified spec line, and one Lean theorem statement with a doc comment that starts with the row ID and quotes the spec. A claim that is false as written gets `REFUTE` and the statement of its counterexample. A row that cannot be proved in Lean gets `OUT` with the reason, a duplicate gets `DUP`, and a row that needs another WP's model gets `DEFER` with that WP.
4. Never add a hypothesis that the spec does not state. A claim that needs one is a spec gap: say so with the spec line.
5. Before you write `REFUTE`, search `docs/spec/` for rules elsewhere that make the counterexample unreachable: value ranges in §16, feasibility at cold init in §8, runtime duties in §9.1, the map cache in §11. In WP01 to WP07, eight of thirteen proposed refutations failed this test. Quote the search you ran.

## Implementer

1. Implement the statement spec under `formal/Driveline/` and import each new module from `formal/Driveline.lean`.
2. One theorem per row, named in snake_case after its content. Its doc comment starts with the row ID and quotes the spec with its line.
3. `REFUTE` rows: prove the counterexample. `DEFER` rows stay `TODO`. Mark `OUT` and `DUP` rows in the ledger as the spec says.
4. Never add a hypothesis that the spec does not state. If a proof needs one, prove the counterexample instead and report it.
5. These words must not appear anywhere in `formal/`, comments included: `sorry`, `admit`, `native_decide`, `unsafe`, `axiom`, `debug.skipKernelTC`.
6. Update the ledger Status of each row you discharge with the exact full constant name: `PROVED: Driveline.<Namespace>.<name>` or `REFUTED: ...`.
7. `python3 tools/check_formal.py 2>&1 | tail -12` must end with `0 failure(s)`. Commit with the message the task gives.
8. If your budget runs low, commit a state that builds, with the rows done so far, and report exactly what remains.

## Reviewer

Read-only. The proof checker has already accepted the proofs. Judge what it cannot: whether each theorem says what the spec says.

For every `PROVED` or `REFUTED` row of the WP, flag:

* a hypothesis that the spec does not state;
* a conclusion weaker than the text, such as a definition proved equal to itself;
* a model definition that differs from the spec;
* a refutation whose counterexample is unreachable under rules elsewhere in the spec (search `docs/spec/` before accepting one);
* a row that should be `OUT` or `DUP`, and a row with no theorem.

Report numbered findings: row or `file:line`, severity (`blocking` for a wrong verdict or an unfaithful theorem, `major` for a materially weaker statement, `minor`), the spec and Lean text as evidence, and the change required.

## Addresser

Fix every finding the orchestrator accepts, under the implementer's rules. A deferred clause becomes a new `TODO` row in the WP that owns it, with the next free ID in its section series (for example `P05-44`). Commit with the message the task gives, and report what changed for each finding.
