---
title: Reference scenario
section: 13
version: 0.258
status: draft
normative: true
depends_on: [02-conventions.md, 12-grammar.md, 17-standard-library.md, 19-modules.md]
---

# 13. Normative Reference Scenario (`kanagawa_pinch_test.dline`)

This scenario parses under the [§12](12-grammar.md) grammar. `tools/check.py` parses it on every change. Its port capacities, clock divisors, parameter tiers, and control-to-physics connections follow the rules of every normative section. The map, FMUs, and tire deck that it names are not shipped with the specification, so the checks that need them, such as the lanes that `spawn` names and the lockfile, apply only where those files exist. Besides the vehicles, it has an object actor (a pedestrian from the catalog module [`examples/catalog/people.dline`](../examples/catalog/people.dline), [§19](19-modules.md)) and a static actor (a stalled car, [§17.1](17-standard-library.md) `place`). The map `kanagawa_expressway.xodr` uses `rule="LHT"`, so positive lanes drive toward increasing $s$ ([§2](02-conventions.md)).

The scenario file is [`examples/kanagawa_pinch_test.dline`](../examples/kanagawa_pinch_test.dline). This section does not copy it.
