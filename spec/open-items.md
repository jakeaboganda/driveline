---
title: Open items
version: 0.143
status: draft
normative: false
depends_on: []
---

# Open Items

These items are unresolved in the current version (README `spec_version`).

**External facts to check against the current standard documents:**
* ASAM OSI message names and the slice mappings in [§4.3](04-perception.md).
* The mapping from Tiers 0–2 to CommonRoad parameter sets ([§1.2](01-scope.md)). CommonRoad may define cornering stiffness differently from `cornering_stiffness_f` in N/rad.
* OpenDRIVE `rule` semantics for lane driving direction ([§2](02-conventions.md)).
* The OpenDRIVE superelevation sign: positive when the road is higher on the side of increasing $t$ ([§2](02-conventions.md)).
* OpenDRIVE lane links: lane IDs can change at a lane-section boundary, and each lane names its predecessor and successor lanes, both relative to increasing $s$ whatever the lane's driving direction ([§9.2](09-abi.md)).
* The FMI 3.0 behavior that [§7](07-fmu-packaging.md) relies on: the layered-standard file location `extra/<name>/`, `fmi3Reset` returning an instance to its instantiated state with parameters at their start values, setting inputs, including `fmi3Binary` inputs, in initialization mode, and a variable's declared unit carrying a factor, an offset, and base-unit exponents.
* The [§1.2](01-scope.md) statement that OpenSCENARIO leaves controller and vehicle-dynamics models to the host simulator.

**Design items:** None open.
