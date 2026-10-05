# Formal verification

The Lean 4 model in [`formal/`](../../formal/README.md) proves claims of the specification. This directory holds the plan and the record.

* [`obligations.md`](obligations.md) is the ledger: every checkable claim of the spec, its class, and its status.
* [`specs/`](specs/) holds one statement spec per work package: the Lean definitions and theorem statements agreed before implementation.
* [`roles.md`](roles.md) holds the instructions each agent role follows.
* [`log.md`](log.md) records each work package as it lands: what was proved, what the review changed, and which spec defects it found.

## Process

Each work package (WP) in the ledger goes through four roles, each a separate agent:

1. **Specify.** Read the WP's ledger rows and the spec text. Write `docs/formal/specs/WPnn.md`: the data model, and one Lean theorem statement per row, each citing its spec line. A claim that looks false gets a statement of its negation instead.
2. **Implement.** Write `formal/Driveline/<Module>.lean` to that statement spec. No `sorry`, `admit`, `axiom`, or `native_decide`.
3. **Review.** Check that each theorem says what the spec says, with no hypothesis that makes it vacuous or weaker than the text, and that the model matches the spec's definitions.
4. **Address.** Fix every accepted review comment.

The orchestrator then runs `tools/check_formal.py`, updates the ledger and the log, and commits. A refuted claim becomes a spec fix through the same four roles, with `tools/check.py` and `tools/bump.py`.

## Running agents

Agents have a cumulative token budget: every turn re-reads the agent's whole context, so an agent gets about a dozen turns. Implementers keep build output short (`lake build <Module> 2>&1 | grep -E -A8 '^error' | head -60`), read only the line ranges they need, and batch edits. When an agent runs out, the orchestrator commits its work as a work-in-progress commit and resumes the same agent, which keeps its context.

Read-only agents can run in parallel, at most four at a time. Agents that edit files run one at a time, because each takes the repository lock and needs a clean checkout.

## Limits

A proof shows that the Lean model has the property. Whether the model says what the prose says is the reviewer's judgment, recorded in the log. Real-number proofs say nothing about binary64 rounding. Claims about OpenDRIVE, FMI, OSI, the file system, and hashing are marked `OUT: external` with the reason.
