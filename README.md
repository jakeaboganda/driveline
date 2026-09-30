---
title: Driveline specification
spec_version: 0.262
abi_version: 0.19
status: draft
---

# Driveline specification

Driveline is a scenario description language and execution architecture for road-driving simulation. The scenario file owns the world: map, friction, and actor spawn states. Each actor owns a typed pipeline of intent, control, and physics components, and the specification defines the contracts between them.

Driveline scenario files use the extensions `.dline` and `.dl`.

## Documents

| Section | Document | Normative |
| :--- | :--- | :--- |
| 0 | [Conformance and terminology](spec/00-conformance.md) | Yes |
| 1 | [Scope, principles, and related work](spec/01-scope.md) | No |
| 2 | [Units and coordinate conventions](spec/02-conventions.md) | Yes |
| 3 | [Vehicle parameter tiers](spec/03-vehicle-parameters.md) | Yes |
| 4 | [Priors, sensors, and SliceBuffer](spec/04-perception.md) | Yes |
| 5 | [Checkpoint data contracts](spec/05-checkpoints.md) | Yes |
| 6 | [Component lifecycle](spec/06-lifecycle.md) | Yes |
| 7 | [FMU packaging](spec/07-fmu-packaging.md) | Yes |
| 8 | [Steady-state cornering solution](spec/08-steady-state.md) | Yes |
| 9 | [C-ABI](spec/09-abi.md) | Yes |
| 10 | [Composition, arbitration, and splicing](spec/10-composition.md) | Yes |
| 11 | [Execution model and determinism](spec/11-execution.md) | Yes |
| 12 | [DSL grammar](spec/12-grammar.md) | Yes |
| 13 | [Reference scenario](spec/13-reference-scenario.md) | Yes |
| 14 | [Status codes and error handling](spec/14-diagnostics.md) | Yes |
| 15 | [Component manifests and packaging](spec/15-manifest.md) | Yes |
| 16 | [DSL static semantics](spec/16-static-semantics.md) | Yes |
| 17 | [Standard library](spec/17-standard-library.md) | Yes |
| 18 | [Run record](spec/18-run-record.md) | Yes |
| 19 | [Modules, catalogs, and the lockfile](spec/19-modules.md) | Yes |
| | [Open items](spec/open-items.md) | No |
| | [Changelog](CHANGELOG.md) | No |

The C header [`abi/driveline_abi.h`](abi/driveline_abi.h) and the scenario [`examples/kanagawa_pinch_test.dline`](examples/kanagawa_pinch_test.dline) are normative artifacts. The documents refer to them and do not copy them.

## Versioning

* `spec_version` in this file increases by one minor step (0.4, 0.5, and so on) for every atomic change to the specification. One change, one version, one commit.
* Each document's front-matter `version` is the `spec_version` in which that document last changed.
* `abi_version` increases when `abi/driveline_abi.h` changes. It equals the `DL_ABI_VERSION_*` macro in the header.
* [`CHANGELOG.md`](CHANGELOG.md) has one entry per `spec_version`.
* `depends_on` lists the normative documents that a document links to. `tools/sync_deps.py` derives it, and `tools/bump.py` runs it and stamps any document whose `depends_on` changed.
* `tools/bump.py` applies these rules for one change: `tools/bump.py [--abi] "Changelog line" -- spec/<changed>.md ...`.

## Checks

`tools/check.py` enforces the versioning rules and checks the artifacts:

* Front-matter, `depends_on` against each document's links, links, and section references down to numbered list items.
* No spec versions or bare section numbers in prose.
* The header compiles for 64-bit and 32-bit targets with padding warnings as errors, and struct sizes match.
* The section 4 and section 5 field tables match the header structs, and the example's tier records match the tier structs.
* Every scenario in `examples/` parses with the section 12 grammar, and every file in its subdirectories parses as a module. Every non-`std` import of an example names a declaration of an existing module. The example's rates divide the base clock, its actor IDs are unique, and each sensor history covers the port it feeds.
* The section 8 test vector recomputes, and the standard `DynamicSingleTrack` derivatives vanish at that steady state.
* SipHash reference vectors and the seed vectors pass.

A check that finds nothing to check fails.

```sh
python3 -m venv .venv
.venv/bin/pip install -r tools/requirements.txt
.venv/bin/python tools/check.py
```

To run the checks before every commit, link the hook: `ln -s ../../tools/pre-commit .git/hooks/pre-commit`.

The 32-bit build needs `gcc -m32` support. If it is missing, the check reports the 32-bit step as skipped.
