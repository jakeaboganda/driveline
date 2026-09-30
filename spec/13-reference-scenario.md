---
title: Reference scenario
section: 13
version: 0.225
status: draft
normative: true
depends_on: [02-conventions.md, 12-grammar.md]
---

# 13. Normative Reference Scenario (`kanagawa_pinch_test.dline`)

This scenario parses under the [§12](12-grammar.md) grammar. `tools/check.py` parses it on every change. Its port capacities, clock divisors, parameter tiers, and control-to-physics connections follow the rules of every normative section. The map `kanagawa_expressway.xodr` uses `rule="LHT"`, so positive lanes drive toward increasing $s$ ([§2](02-conventions.md)).

The scenario file is [`examples/kanagawa_pinch_test.dline`](../examples/kanagawa_pinch_test.dline). This section does not copy it.
