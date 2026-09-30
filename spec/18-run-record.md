---
title: Run record
section: 18
version: 0.257
status: draft
normative: true
depends_on: [11-execution.md, 14-diagnostics.md, 19-modules.md]
---

# 18. Run Record

Every run writes one run record: the header that identifies the run, the reports of [§14](14-diagnostics.md), the events of the run, and its outcome. Where the runtime writes the record is implementation-defined. Two runs that [§11](11-execution.md) requires to be bit-identical write records that differ only in the `detail` text of reports.

## 18.1 Encoding

The record is UTF-8 text in JSON Lines form. Each line is one JSON object followed by `\n`, with no other whitespace. Members appear in the order that [§18.2](18-run-record.md) lists them, and every listed member is present. A string escapes `"` as `\"`, `\` as `\\`, and each character from U+0000 to U+001F as `\u00` followed by two lowercase hexadecimal digits. Every other character is written as itself. An integer is written in decimal with no leading zeros. A binary64 value is written as the shortest decimal that converts back to the same value, in the form that ECMAScript `Number::toString` produces, with `-0` written as `0`. Every binary64 value in the record is finite.

## 18.2 Lines

1. **Header:** The first line. Members: `record` (`"header"`), `spec_version` (the `spec_version` in the front matter of the specification's README that the runtime implements, as written there), `abi_version` (`"<major>.<minor>"` from the name of the header's `DL_ABI_VERSION_<major>_<minor>` macro), `scenario_sha256` (the lowercase hexadecimal SHA-256 of the scenario file's bytes), `seed` (the `scenario_seed` of [§11](11-execution.md)), `timestep_ns` ($\Delta t_{\text{base\_ns}}$), and `files` (the lockfile entries of [§19.2](19-modules.md), in the same order and form).
2. **Report:** One line per report of [§14.2](14-diagnostics.md). Members: `record` (`"report"`), then the report fields in the order that [§14.2](14-diagnostics.md) lists them.
3. **Collision:** One line per pair of actors on the first tick that they are in contact ([§11](11-execution.md)). Members: `record` (`"collision"`), `tick` and `sim_time_ns` of the committed state, `actor_a` and `actor_b` (the two `actor_id`s, ascending), and `vx_a`, `vy_a`, `vx_b`, `vy_b`, the World-frame horizontal velocity of each actor's reference origin, $(v_{\text{lon}}\cos\psi - v_{\text{lat}}\sin\psi,\ v_{\text{lon}}\sin\psi + v_{\text{lat}}\cos\psi)$. Lines of one tick follow the pair order of [§11](11-execution.md).
4. **End:** The last line. Members: `record` (`"end"`), `outcome` (`"success"` or `"failure"`), `tick`, and `sim_time_ns` of the last committed state, or 0 and 0 for a run that fails during cold init.

The committed state after Phase 4 of tick $k$ has tick $k + 1$ and time $(k + 1)\,\Delta t_{\text{base\_ns}}$. Lines between the header and the end line appear in the order that sequential execution in the order of [§11](11-execution.md) produces them. Teardown reports come after every other report and before the end line.
