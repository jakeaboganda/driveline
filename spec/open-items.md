---
title: Open items
version: 0.4
status: draft
normative: false
depends_on: []
---

# Open Items

These items are unresolved in v0.3.

**External facts to check against the current standard documents:**
* ASAM OSI message names and the slice mappings in [§4.3](04-perception.md).
* The mapping from Tiers 0–2 to CommonRoad parameter sets ([§1.2](01-scope.md)). CommonRoad may define cornering stiffness differently from `cornering_stiffness_f` in N/rad.
* OpenDRIVE `rule` semantics for lane driving direction ([§2](02-conventions.md)).
* The FMI 3.0 layered-standard file location `extra/<name>/` and the `fmi3Reset` and `fmi3GetFMUState` behavior that [§7](07-fmu-packaging.md) relies on.
* The [§1.2](01-scope.md) statement that OpenSCENARIO leaves controller and vehicle-dynamics models to the host simulator.

**Design items:**
* The DSL has no syntax for splice triggers ([§10.4](10-composition.md)).
* Native components cannot run out of process. Only Mode A FMUs ([§7](07-fmu-packaging.md)) have a serialized port encoding.
* `RadarSlice` has no primary target ID. `rate_of(primary_range)` returns a wrong rate on the tick where the primary target changes.
