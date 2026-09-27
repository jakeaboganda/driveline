---
title: Changelog
---

# Changelog

Section numbers refer to the v0.4 document layout.

## 0.9

* Defined `slip_angle_beta_cg` with atan2 so it stays finite at a standstill and in reverse.
* The single-track steady state applies only at $v \ge 1$ m/s. Reverse and low speeds use the kinematic solution.

## 0.8

* Invariants in the vehicle parameter tiers hold within a relative tolerance of 1e-6, so the result no longer depends on summation order.

## 0.7

* Made the DSL type `Time` signed so that `t - reaction_delay` near $t = 0$ does not wrap. Stored timestamps stay unsigned.

## 0.6

* Added section 14: status code table, runtime handling of warnings and errors, output validation, and report fields.
* Renamed `DL_STATUS_WARN_COLD_FMU` to `DL_STATUS_WARN_FMU_COLD_SPLICE` and added `DL_STATUS_ERR_STATE`. Prose now uses the header names only.
* ABI version 0.4.

## 0.5

* Added section 0: normative language, conformance classes for compilers, runtimes, and components, and a glossary that defines stages by output type.
* Replaced "compliant" with "conforming" and "master" with "runtime".

## 0.4

* Split the single specification file into one document per concern under `spec/`, each with front-matter. Section 6 of v0.3 became sections 6, 7, and 8. Sections 7 to 10 of v0.3 became sections 9 to 13.
* Moved the C header to `abi/driveline_abi.h` and the reference scenario to `examples/kanagawa_pinch_test.dline`.
* Added `tools/check.py`.

## 0.3

* Removed the `[cite: 1]` tags and rewrote the related-work claims as scope statements (§1.2).
* Added sign conventions for road grade and bank, spawn heading from the OpenDRIVE `rule` attribute, a lane reference string format, and nanosecond `Time` (§2).
* Defined `max_drive_torque` at the engine or motor shaft and `max_brake_torque` as the wheel total. Tier 3 decks are referenced by `uri` only (§3). Set `SimpleDrivetrain` to output `KinematicControlFrame` (§3.1).
* Changed `Timestamped<T>` to integer nanoseconds. Added the timestamp invariant, `Rate` validity for `rate_of`, and interpolation classes per field (§4).
* Added field groups, the hold rule for cleared bits, rules for combining steering and jerk bits, and `GAP_PROFILE` measurement rules (§5).
* Replaced the promotion formula with a steady-state solve that balances force and yaw moment, with a test vector (§8). Added demotion and controller re-trim (§6.2.4). Removed the double Tick 0 sensor projection and the $R_{\text{nom}}$ default (§6.2.3).
* Separated the native C-ABI from FMU packaging, and rewrote the Mode B warm-start fallback so that it relies only on standard FMI calls (§7).
* ABI v0.3 (§9): `dl_set_parameters`, a `host_ctx` for callbacks, successor lists, typed per-port step I/O, the SliceBuffer layout, `dl_route_t`, `dl_sensor_bundle_t`, and two new status codes.
* Made `+` a typed merge of `Lon<T>` and `Lat<T>`, restored splicing, and added the physics assignment rule (§10).
* Restored the four tick phases, defined the SipHash-2-4 encoding, and narrowed the determinism guarantee (§11).
* Added expression and lexical grammar, grouping parentheses, and a cardinality clause (§12). Moved the reference scenario to LHT lanes and fixed its Bosch bindings and hard-coded actor ID (§13).

## 0.2

* Revised the first draft after review.

## 0.1

* First draft.
