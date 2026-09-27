---
title: Changelog
---

# Changelog

Section numbers refer to the v0.4 document layout.

## 0.23

* Removed the last stale appendix reference. `tools/check.py` now rejects appendix references.

## 0.22

* Track lists have unique IDs, a fixed sort order (range, then ID), truncation to 32, and zero-filled unused entries.

## 0.21

* Replaced the `buffer.underflow` flag with a read-only `buffer.count`. Removed `DL_STATUS_WARN_UNDERFLOW`.
* ABI version 0.8.

## 0.20

* Added `on (...) { splice ... }` statements with chain and `physics_model` targets, type rules, edge-triggered firing, and splice timing. The reference scenario promotes the blocker at 4 s.

## 0.19

* Added a table of legal lifecycle calls. `dl_terminate` is legal from every live state, which the error handling in section 14 needs.

## 0.18

* Removed `dl_on_membership_change` and `dl_membership_change_t`, because no scenario statement can change a group's members.
* Redrew the lifecycle diagram.
* ABI version 0.7.

## 0.17

* Warm start and re-trim pass one init context per affected actor. Components match contexts to slots by `actor_id` and keep the other actors' state.

## 0.16

* Only Stage 2 components must reproduce the latched trim, and the runtime checks it on the first Tick 0 output, since initialization returns no output.

## 0.15

* Added a bit coverage table for `IntentFrame`, rules making `trajectory` exclusive of the `LON` and `LAT` bits, array count limits, the time base for `trajectory`, and the reference point for `s_stop`.

## 0.14

* Defined Tier 3 deck semantics: which components read a deck, what the two precedence modes mean, how a relative `uri` resolves, and which values a deck never overrides.

## 0.13

* Added `reverse_gear_ratio` to Tier 2 and to the reference vehicle.
* ABI version 0.6.

## 0.12

* Tiers 0–2 describe two-axle, four-wheel vehicles. Tier 3 requires Tier 0. `num_wheels` is 0 or 4.
* Cold init skips axle loads and wheel seeding for Tier-0-only actors, which have no mass.
* ABI version 0.5.

## 0.11

* Added a feasibility rule to the steady-state solve: steering beyond $\delta_{\max}$, or lateral acceleration beyond $\mu g$, fails with `DL_STATUS_ERR_NUMERIC`.

## 0.10

* Cold init now takes spawn heading and curvature relative to the lane's driving direction. Before this, actors on lanes that drive toward decreasing $s$ started with a yaw rate of the wrong sign.

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
