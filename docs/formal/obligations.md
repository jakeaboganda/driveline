# Proof-obligation ledger

This file lists every normative claim of [the specification](../spec/) that could be wrong, and how each one is discharged. `tools/check_formal.py` reads it.

## Status values

| Status | Meaning |
| :--- | :--- |
| `TODO` | Not yet discharged. |
| `PROVED: <name>` | A Lean theorem in `formal/` proves the claim. `<name>` is its full name. |
| `REFUTED: <name>` | A Lean theorem proves the claim false as written. The spec was fixed, and the row names the counterexample theorem. |
| `CHECKED` | `tools/check.py` or the C compile already enforces the claim. |
| `OUT: external` | The claim depends on OpenDRIVE, FMI, OSI, the file system, SHA-256, or binary64 rounding, which the Lean model does not include. |
| `OUT: prose` | The text defines a term and has no consequence to check. |
| `DUP: <id>` | Another row covers the claim. |

The spec counts as proven when no row is `TODO`.

Spec references are `<section>:<line>` in `docs/spec/`, as the inventory recorded them. Line numbers can drift by one; the quote is authoritative.

## Rows

### WP00 Component lifecycle (§6.1, done)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| L06-01 | 06:51 | 'The diagram above omits some ... edges, and the table governs' | DECIDE | Driveline.Lifecycle | every drawn edge is allowed by the table | PROVED: Driveline.Lifecycle.diagram_sound |
| L06-02 | 06:51 | 'omits some `dl_terminate` and `dl_free_instance` edges' | DECIDE | Driveline.Lifecycle | every undrawn table edge is a terminate or free edge | PROVED: Driveline.Lifecycle.undrawn_edges |
| L06-03 | 06:70 | cold init call sequence | DECIDE | Driveline.Lifecycle | instantiate, set, configure, cold init, exit reaches StepMode | PROVED: Driveline.Lifecycle.cold_init_sequence |
| L06-04 | 10:185 | splice call sequence at t > 0 | DECIDE | Driveline.Lifecycle | the splice sequence reaches StepMode | PROVED: Driveline.Lifecycle.splice_sequence |
| L06-05 | 06:59 | 'StructuralConfig at t > 0 (splice)' | DECIDE | Driveline.Lifecycle | no warm start from StructuralConfig at t = 0 | PROVED: Driveline.Lifecycle.no_warm_start_at_zero |
| L06-06 | 06:87 | re-trim sequence | DECIDE | Driveline.Lifecycle | warm start and exit from StepMode return to StepMode | PROVED: Driveline.Lifecycle.retrim_sequence |
| L06-07 | 06:53-63 | Allowed Calls table | DECIDE | Driveline.Lifecycle | StepMode is reached only through dl_exit_init_mode | PROVED: Driveline.Lifecycle.stepMode_needs_init |
| L06-08 | 14:395 | teardown visits | DECIDE | Driveline.Lifecycle | teardown ends Uninstantiated with no forbidden call | PROVED: Driveline.Lifecycle.teardown_frees |



### WP01 Frames, validity, merge, arbiter (§5, §10.2–10.3)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P05-01 | 05:12 | 'Every checkpoint frame carries timestamp_ns ... and actor_id' | DECIDE | Driveline.Frames | header struct shared by all frames; header is in no group | PROVED: Driveline.Frames.header_kept |
| P05-02 | 05:14 | 'Every full frame states every group' | DECIDE | Driveline.Frames | valid f .full -> forall g, modeNat f g != 0 (no NONE group) | PROVED: Driveline.Validity.full_states_every_group |
| P05-03 | 05:18-25 | mode table (groups/modes/fields) | DECIDE | Driveline.Frames | enum encodings match ABI comments (abi:187-189, 207-208, 217-219) through ofNat/toNat round trip | PROVED: Driveline.Frames.mode_encodings |
| P05-04 | 05:28-30 | 'A field applies only under the modes listed here' | DECIDE | Driveline.Frames | uses : Mode -> Field -> Bool; jerk_lon_cmd used under ACCEL and JERK; steer_rate_cmd under ANGLE and RATE | PROVED: Driveline.Frames.fields_per_mode |
| P05-05 | 05:32 | 'numbered from 1 in the order shown' | DECIDE | Driveline.Frames | index lemma for each enum | PROVED: Driveline.Frames.modes_numbered |
| P05-06 | 05:32 | baseline modes list; 'every mode of gear_mode' | DECIDE | Driveline.Frames | isBaseline; baseline-mode frames state every group and do not use STT (Pass 1 step 5 and tier-change steering: P05-41, P05-42) | PROVED: Driveline.Frames.baseline_modes |
| P05-07 | 05:32 | 'SPATIOTEMPORAL_TRAJECTORY couples the two motion groups' | DECIDE | Driveline.Frames | STT uses only num_traj_points and trajectory; under the 05:68 coupling, f.lon = STT or f.lat = STT and uses f fld -> fld is one of them | PROVED: Driveline.Frames.stt_couples |
| P05-08 | 05:34 | 'A Lon<T> frame states the LON group and has every other group NONE' | DECIDE | Driveline.Validity | validLon f <-> lon != NONE and lon != STT and all other groups NONE | PROVED: Driveline.Validity.lon_frame_groups |
| P05-09 | 05:34 | 'A Lat<T> frame states LAT, and for IntentFrame also SIGNAL' | DECIDE | Driveline.Validity | same shape as validLon | PROVED: Driveline.Validity.lat_frame_groups |
| P05-10 | 05:34 | 'An Override<T> frame may have any group NONE. Every other frame has no NONE group.' | DECIDE | Driveline.Validity | validFull f -> validOverride f | PROVED: Driveline.Validity.full_is_override |
| P05-11 | 05:34,40 | 'a full frame ... reaches a Lon<T> or Lat<T> port ... valid only if ... it does not use SPATIOTEMPORAL_TRAJECTORY' | DECIDE | Driveline.Validity | validAt f .full (partialPort := true) <-> valid f .full and not usesSTT f; such f converts: validLon (toLon f) and validLat (toLat f) | PROVED: Driveline.Validity.port_conversion |
| P05-12 | 05:36 | 'The value +INFINITY means no bound' | DECIDE | Driveline.Validity | on outputCheck: +inf passes only in stop_at_odometer, jerk_lon_cmd under ACCEL, steer_rate_cmd under ANGLE; other used fields at +inf, -inf or NaN give numeric | PROVED: Driveline.Validity.infinity_no_bound |
| P05-14 | 05:38 | 'sets every field that the frame's modes do not use ... to zero' | DECIDE | Driveline.Validity | zero is idempotent; valid f -> valid (zero f); zero keeps used fields (abstract; byte-level zeroing is §9.1, see WP07) | PROVED: Driveline.Validity.zeroing |
| P05-15 | 05:40 | 'delivers ... without further change, except ...' | MODEL | Driveline.Frames | deliver is id except the port conversions (IntentFrame and KinematicControlFrame toLon/toLat); redelivery on non-stepping ticks: P05-40 | PROVED: Driveline.Frames.delivery |
| P05-17 | 05:66-70 | 'valid if and only if every rule below holds' | DECIDE | Driveline.Validity | validIntent (map : RoadOracle) f is Decidable given decidable map predicates; decide valid = conjunction of the rule decisions | PROVED: Driveline.Validity.intent_valid_decidable |
| P05-18 | 05:68 | 'lon_mode is STT if and only if lat_mode is ... 1 to 64 ... strictly increase ... v_k >= 0 ... (-pi, pi]' | DECIDE | Driveline.Validity | StrictMono on Fin n of t_ns (Int64) | PROVED: Driveline.Validity.stt_trajectory_rule |
| P05-20 | 05:70 | 'gap_target_actor_id is not 0 ... not negative' | DECIDE | Driveline.Validity | not (x < 0) vs 0 <= x | PROVED: Driveline.Validity.gap_rule |
| P05-26 | 05:80 | GAP_PROFILE fallback to VELOCITY_TARGET; g = rel_x | MODEL | Driveline.Frames | effectiveLonMode (g = rel_x: P05-43) | PROVED: Driveline.Frames.effective_lon_mode |
| P05-27 | 05:82 | 'returns DL_STATUS_ERR_UNSUPPORTED_MODE ... NONE is never checked' | MODEL | Driveline.Validity | supported m NONE = true | PROVED: Driveline.Validity.unsupported_mode_check |
| P05-29 | 05:98 | KCF valid: 'bounds under ACCEL and ANGLE are above zero' | DECIDE | Driveline.Validity | NaN rejected, +inf accepted | PROVED: Driveline.Validity.kinematic_bounds_above_zero |
| P05-30 | 05:114 | ACF valid; 'manual_gear_index is from 0 to num_gears' | DECIDE | Driveline.Validity | - | PROVED: Driveline.Validity.actuator_ranges |
| P05-31 | 05:119 | yaw, roll in (-pi, pi]; pitch in (-pi/2, pi/2) | DECIDE | Driveline.Validity | - | PROVED: Driveline.Validity.kinematic_state_angles |
| P10-06 | 10:24 | 'the two branches can never write the same field' | DECIDE | Driveline.Merge | the groups' field sets are disjoint once STT is excluded | PROVED: Driveline.Merge.branches_disjoint |
| P10-07 | 10:25 | 'It states every group ... never uses SPATIOTEMPORAL_TRAJECTORY' | DECIDE | Driveline.Merge | - | PROVED: Driveline.Merge.merge_full_frame |
| P10-08 | 10:25 | 'Two valid partial frames always merge into a valid full frame' | DECIDE | Driveline.Merge | forall m a b, validLon m a -> validLat m b -> validFull m (merge a b); zero (merge a b) = merge (zero a) (zero b) | PROVED: Driveline.Merge.merge_valid |
| P10-09 | 10:25 | merged timestamp rules | MODEL | Driveline.Merge | forming-tick stamp; splice-window stamp: P10-40 | PROVED: Driveline.Merge.merge_timestamps |
| P10-11 | 10:27 | 'a full frame of type T is also a valid override' | DECIDE | Driveline.Validity | same as P05-10 | DUP: P05-10 |
| P10-12 | 10:27 | Arbiter coupled-motion rule | MODEL | Driveline.Arbiter | arbiterOK p s base out; theorem: valid p, valid s and the committed baseline give valid out | PROVED: Driveline.Arbiter.arbiter_output_valid |
| P10-13 | 10:27 | baseline 'v_ref = max(own.v_lon, 0)' and 'd_ref = own.frenet_d' | MODEL | Driveline.Arbiter | - | PROVED: Driveline.Arbiter.committed_baseline |

### WP02 Vehicle and object spec encoding (§3)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P00-02 | 00:37-42 | 'Its stage follows from its output type' / 'Override<T> has the stage of T' | DECIDE | Driveline.VehicleSpec | stage : OutType -> Fin 4 is total; stage (Override T) = stage T; Lon/Lat preserve stage | TODO |
| P00-03 | 00:43 | 'Arbiter ... primary T ... secondary Override<T> ... T is IntentFrame, KinematicControlFrame, or ActuatorControlFrame' | DECIDE | Driveline.VehicleSpec | isArbiter sig <-> sig = (T, Override T) -> T with T in a 3-element set; stage arb = stage T | TODO |
| P00-04 | 00:34 | 'exactly one physics component, except a static actor' | MODEL | Driveline.VehicleSpec | WF actor: static -> sensors=priors=comps=[]; else count physics = 1 | TODO |
| P00-05 | 00:33 | 'Passing a value of a world-truth type to a component port is a compile-time error' | MODEL | Driveline.VehicleSpec | forall port, portType not in {OpenDriveMap, FrictionField} | TODO |
| P02-09 | 02:19 | 'CG ... l_r forward of the rear axle, l_f behind the front axle' | REAL | Driveline.VehicleSpec | with rear axle at x=0, front axle at x=L: cgX = l_r and L - cgX = l_f, so l_f + l_r = L (agrees with P03-07) | TODO |
| P02-10 | 02:19 | 'object actor ... reference origin is the center of its box's footprint' | REAL | Driveline.VehicleSpec | with object values (P03-14) the box x-range is [-len/2, len/2], centred on 0 | TODO |
| P03-01 | 03:12 | 'Tier 2 requires Tiers 0 and 1; Tier 1 requires Tier 0 ... Tier 3 requires Tier 1, and so Tier 0' | DECIDE | Driveline.VehicleSpec | validVehicleMask m <-> m in {1,3,7,11,15}; closure: bit3 -> bit1 -> bit0, bit2 -> bit1 | TODO |
| P03-02 | 03:36 | 'Bit k ... set if and only if Tier k is populated, and bit 4 is clear' | DECIDE | Driveline.VehicleSpec | encode spec mask agrees with populated tiers; mask &&& 16 = 0 for vehicles | TODO |
| P03-03 | 03:44 | 'bits 0 and 4 of populated_tiers_mask set' | DECIDE | Driveline.VehicleSpec | encodeObject mask = 0x11; disjoint from the vehicle masks of P03-01 | TODO |
| P03-04 | 03:36,44 | 'Every field of an unpopulated tier is zero' / 'every other field zero' | MODEL | Driveline.VehicleSpec | not populated k -> tier_k = default zero record | TODO |
| P03-05 | 03:20 | 'bounding box spans x in [-o_r, L+o_f], y in [-W/2, W/2], z in [0, H]' | REAL | Driveline.VehicleSpec | box extents: (L+o_f) - (-o_r) = L_bbox under P03-06; width = W; height = H | TODO |
| P03-06 | 03:20 | 'L_bbox == L + o_f + o_r' | REAL | Driveline.VehicleSpec | approxEq L_bbox (L+o_f+o_r) (approxEq from P03-09) | TODO |
| P03-07 | 03:21 | 'l_f + l_r == L' | REAL | Driveline.VehicleSpec | Tier1 populated -> approxEq (l_f+l_r) L | TODO |
| P03-08 | 03:22 | 'm_s + m_uf + m_ur == m' | REAL | Driveline.VehicleSpec | Tier2 populated -> approxEq (m_s+m_uf+m_ur) m (m from Tier1, guaranteed by P03-01) | TODO |
| P03-11 | 03:22 | 'reverse_gear_ratio i_R > 0' | MODEL | Driveline.VehicleSpec | Tier2 WF: 0 < i_R | TODO |
| P03-12 | 03:22 | 'Peak drive torque ... T*i_g*i_fd ... In reverse ... T*i_R*i_fd, acting toward -x' | REAL | Driveline.VehicleSpec | wheelTorque g = T*i_g*i_fd; reverse torque x-component = -(T*i_R*i_fd) <= 0 given T, i_R, i_fd >= 0 | TODO |
| P03-13 | 03:36 | 'num_gears is the number of gear_ratios values, and the unused entries are zero' | INT | Driveline.VehicleSpec | num_gears <= 10 and forall i >= num_gears, gear_ratios[i] = 0 | TODO |
| P03-14 | 03:42 | 'L = 0, o_f = o_r = length/2, L_bbox = length ... delta_max = delta_dot_max = i_s = 0' | REAL | Driveline.VehicleSpec | objectTier0 satisfies P03-06 exactly: 0 + len/2 + len/2 = len | TODO |
| P03-15 | 03:42 | 'Where a rule divides by delta_max, the quotient is 0 for an object' | MODEL | Driveline.VehicleSpec | safeDiv x 0 = 0 for objects (matches Lean's x/0 = 0) | TODO |
| P03-16 | 03:42 | 'v_lat,ra = delta_ss = beta_cg = 0 ... reports front_wheel_angle 0' | MODEL | Driveline.VehicleSpec | object steady state has zero lateral terms | TODO |
| P03-17 | 03:40 | 'each value above zero' | MODEL | Driveline.VehicleSpec | ObjectSpec WF: length, width, height, v_max, a_max > 0 | TODO |
| P03-19 | 03:40 | 'STATIC ... which only place may use' | MODEL | Driveline.VehicleSpec | class = STATIC <-> created by place | TODO |
| P03-20 | 03:26 | 'required_tier not populated ... is a compile-time error' | DECIDE | Driveline.VehicleSpec | accept bind <-> testBit mask required_tier | TODO |
| P03-21 | 03:28 | 'KinematicBicycle accepts only ... KinematicControlFrame' | DECIDE | Driveline.VehicleSpec | input type of the KS physics = KCF; ACF wiring rejected | TODO |
| P03-22 | 03:29 | 'delta = steering_wheel_norm * delta_max' | REAL | Driveline.VehicleSpec | abs norm <= 1 -> abs delta <= delta_max | TODO |
| P03-23 | 03:43 | 'No chain that serves an object actor ... carries a KinematicControlFrame or ActuatorControlFrame' | DECIDE | Driveline.VehicleSpec | object chain types avoid {KCF, ACF} under Lon/Lat/Override wrappers | TODO |
| P03-24 | 03:34-35 | 'OVERRIDE_TIER1_2 ... Never Overridden: Tier 0 geometry ... Tier 1 values that the steady-state solve uses' | MODEL | Driveline.VehicleSpec | effectiveParams with deck: tier0 unchanged; steady-state input = spec.tier1 | TODO |
| P03-25 | 03:36 | 'A value longer than 255 bytes ... is a compile-time error' | INT | Driveline.VehicleSpec | uri byte length <= 255 <-> fits uri[256] with NUL | TODO |
| P03-26 | 03:23 / H | 'deck_type (NONE, PACEJKA_TIR, SOLVER_URI)'; H '0:SUPPLEMENT_ONLY, 1:OVERRIDE_TIER1_2' | DECIDE | Driveline.VehicleSpec | enum encode/decode round trip on Fin 3 / Fin 2 | TODO |
| P03-27 | 03:14 / H | class CAR/TRUCK/CYCLIST/MOTORCYCLE; H '0:UNKNOWN ... 7:STATIC' | DECIDE | Driveline.VehicleSpec | vehicle classes map into {1,2,4,5}, object classes into {0,3,6,7}; disjoint and injective | TODO |
| PH-05 | H init ctx | 'num_wheels 0 (no Tier 2) or 4'; '4..7 zero' | DECIDE | Driveline.VehicleSpec | num_wheels = if Tier2 populated then 4 else 0; wheels[i] = 0 for i >= 4 | TODO |

### WP03 SliceBuffer queries and track lists (§4)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P02-11 | 02:21 | 'road_id (char[64]): Null-terminated' | MODEL | Driveline.Tracks | road id byte length <= 63 | TODO |
| P02-12 | 02:22 | 'lane 0 in a callback argument is DL_STATUS_ERR_INVALID_ARG' | DECIDE | Driveline.Tracks | validLane l <-> l != 0; callback l=0 returns -1 | TODO |
| P02-13 | 02:25 | 'The text after the last colon is the signed lane index' | MODEL | Driveline.Tracks | parse (render r l) = some (r,l) even if r contains ':' (split on last colon) | TODO |
| P02-14 | 02:26 | 'RHT, negative lanes drive toward increasing s ... LHT, positive lanes' | DECIDE | Driveline.Tracks | sigma rule lane = if (rule=RHT) = (lane<0) then 1 else -1, for lane != 0; sigma in {1,-1} | TODO |
| P04-01 | 04:16 | 'up to 64 lanes ... nodes beyond count zero-filled' | INT | Driveline.Tracks | route WF: count <= 64, and nodes[i] = 0 for i >= count | TODO |
| P04-02 | 04:19 | 'capacity N in [1, 64]' | INT | Driveline.SliceBuffer | 1 <= N <= 64 | TODO |
| P04-03 | 04:19 | 'N_s >= N_c ... holding the newest min(count_s, N_c) samples' | INT | Driveline.SliceBuffer | view b Nc = b.take Nc; view.count = min count_s Nc <= Nc | TODO |
| P04-04 | 04:21 | 'Timestamps ... strictly decrease from s[0] to s[count-1]' | MODEL | Driveline.SliceBuffer | Sorted (>) ts; push keeps it when t_new > s[0].t; view preserves it | TODO |
| P04-05 | 04:24,27 | 'Guaranteed valid from t = 0'; 'count ... from 1 to N_c' | INT | Driveline.SliceBuffer | after cold init: 1 <= count <= Nc | TODO |
| P04-06 | 04:26 | 'k is a compile-time constant and k >= N_c, compilation fails' | DECIDE | Driveline.SliceBuffer | accept const index k <-> k < Nc | TODO |
| P04-07 | 04:27 | 'buffer[k] returns ... buffer[count - 1]' | INT | Driveline.SliceBuffer | get k = s[min k (count-1)]; index in bounds since count >= 1 | TODO |
| P04-08 | 04:27 | 'Queries do not change the buffer' | MODEL | Driveline.SliceBuffer | queries are pure functions of the buffer | TODO |
| P04-09 | 04:28-29 | 'm = min(k, count-1)'; '{0.0,false} if count < 2' | INT | Driveline.SliceBuffer | count >= 2 and k >= 1 -> 1 <= m, so s[0].t - s[m].t > 0 (from P04-04) | TODO |
| P04-10 | 04:30 | 'integer difference taken first' | INT | Driveline.SliceBuffer | UInt64 subtraction s[0].t - s[m].t does not underflow, from P04-04 | TODO |
| P04-13 | 04:32 | 't_query >= s[0].t returns s[0]; t_query <= s[count-1].t returns s[count-1]' | INT | Driveline.SliceBuffer | when count = 1 the two clamps agree (no conflict); Int vs UInt64 comparison is well-defined | TODO |
| P04-14 | 04:33 | 'returned entry's t is t_query clamped to [s[count-1].t, s[0].t]' | INT | Driveline.SliceBuffer | (at q Interp).t = max s_last (min q s0) | TODO |
| P04-15 | 04:34 | 'Floor: newest s[k] where s[k].t <= t_query' | INT | Driveline.SliceBuffer | after clamping, such a k exists and is unique (first index under strict decrease) | TODO |
| P04-16 | 04:35 | 'bracket s[k+1].t <= t_query < s[k].t ... alpha in [0, 1)' | REAL | Driveline.SliceBuffer | the bracket exists and is unique; 0 <= alpha < 1 | TODO |
| P04-17 | 04:36 | '(1 - alpha) v_{k+1} + alpha v_k' | REAL | Driveline.SliceBuffer | LINEAR result lies in [min, max] of the two samples; this keeps confidence in [0,1] and mu in [0,2] | TODO |
| P04-20 | 04:38,56 | 'Every integer, enum, flag, and char[] field is HOLD' | MODEL | Driveline.SliceBuffer | classOf field = HOLD for all non-float64 fields | TODO |
| P04-21 | 04:39,58 | 'interpolated only when its dependency condition holds' | MODEL | Driveline.SliceBuffer | dep fails -> field = s[k+1].field | TODO |
| P04-22 | 04:58 | 'has_primary_target is 1 exactly when primary_target_id is nonzero' | DECIDE | Driveline.Tracks | WF radar slice: has = 1 <-> id != 0; Interp keeps this (both fields HOLD from s[k+1]) | TODO |
| P04-23 | 04:41 | 'Matched ... by target_actor_id ... dropped if absent from s[k+1]' | MODEL | Driveline.Tracks | ids of result = ids of s[k+1]; result length <= 32 without needing truncation | TODO |
| P04-24 | 04:54 | 'each target_actor_id appears at most once' | MODEL | Driveline.Tracks | Nodup ids; kept by merge and by sort+take | TODO |
| P04-25 | 04:54 | 'sorted by ascending range, ties ... ascending target_actor_id' | MODEL | Driveline.Tracks | Sorted lexLt (range,id); a strict total order given unique ids and non-NaN ranges | TODO |
| P04-26 | 04:54 | 'keeps the first 32 ... entries beyond num_tracks are zero-filled' | INT | Driveline.Tracks | num_tracks <= 32; tracks[i] = 0 for i >= num_tracks; result = (sort l).take 32 | TODO |
| P04-27 | 04:48-52 | 'confidence in [0,1]'; 'mu in [0, 2]'; 'ttc_lon +INFINITY when not closing' | MODEL | Driveline.Tracks | range predicates on slice fields; ttc is ENNReal-like (EXTERNAL for the inf encoding) | TODO |
| PH-03 | H ring view | 'entries + ((head + capacity - k) % capacity) * entry_size' | INT | Driveline.SliceBuffer | head < cap, k < cap -> index < cap, injective in k, k=0 gives head; no UInt32 overflow since cap <= 64 | TODO |

### WP04 Tick schedule and FMU time (§11, §7)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P07-08 | 07:36 | 'each later one is the previous one plus the previous communicationStepSize in binary64, so the points are contiguous' | MODEL | Driveline.FmuTime | p_{k+1} = fl(p_k+h) ⇒ FMI contiguity (rfl); drift vs nearest(t_k/1e9) bounded but nonzero | TODO |
| P07-09 | 07:43 | 'currentCommunicationPoint of tick t by the Times rule ... communicationStepSize = h' | MODEL | Driveline.FmuTime | scheduled ticks t_first + k·h map 1:1 to p_k | TODO |
| P07-10 | 07:44 | 'fmi3Warning counts as fmi3OK' | DECIDE | Driveline.FmuTime | status map | TODO |
| P07-11 | 07:46 | 'react ... one period later' | MODEL | Driveline.FmuTime | output(t) depends on inputs ≤ t only | TODO |
| P07-12 | 07:59 | 't_first, the earliest tick time t' ≥ t at which the component is scheduled' | INT | Driveline.FmuTime | t_first = least scheduled tick ≥ t; first DoStep point = startTime | TODO |
| P07-14 | 07:62-63 | terminate/free conditions | DECIDE | Driveline.FmuTime | call predicate | TODO |
| P11-01 | 11:12 | "t_ns = k_tick · Δt_base_ns", Δt ∈ ℤ⁺ | INT | Driveline.Schedule | `tickTime k = k * dt` over ℕ; strictly increasing when dt>0 | TODO |
| P11-02 | 11:13 | "k_div · Δt_base_ns · f_comp = 10^9 exactly" | DECIDE | Driveline.Schedule | `validRate dt f ↔ ∃ k:ℕ+, k*dt*f = 1e9` over ℚ; decidable as `(1e9/(dt*f)).den = 1 ∧ >0`; at most one k_div exists | TODO |
| P11-03 | 11:13 | "30Hz on a 500Hz base clock … compile-time error" | DECIDE | Driveline.Schedule | `¬ validRate 2_000_000 30` by `decide` | TODO |
| P11-04 | 11:14 | "omits a (rate: …) clause inherits … k_div = 1" | MODEL | Driveline.Schedule | `defaultDiv = 1`; `validRate dt (1e9/dt)` | TODO |
| P11-05 | 11:15 | "executes on tick k iff (k mod k_div) == 0" | DECIDE | Driveline.Schedule | `runs k d ↔ d ∣ k`; `runs 0 d` holds for every d | TODO |
| P11-06 | 11:15 | "holds its output constant via ZOH" | MODEL | Driveline.Schedule | `out k = out (d * (k / d))`; constant on `[d*m, d*m+d)` | TODO |
| P11-08 | 11:17 | "most recent step at or before the current tick … topological order" | MODEL | Driveline.Schedule | the value read at tick k is the upstream output at `max {j ≤ k ∣ runs j}`, with the same-tick write before the read because of topological order | TODO |
| P11-09 | 11:18 | "dt = k_div · Δt_base" | INT | Driveline.Schedule | `stepDt d dt = d*dt`; Int64 no overflow under a bound | TODO |
| P11-10 | 11:19-23 | "four phases in this order" | MODEL | Driveline.Schedule | `tick = P1 ≫ P2 ≫ P3 ≫ P4`; tick 0 = `P2 ≫ P3 ≫ P4` (11:20) | TODO |
| P11-11 | 11:23 | "sim_time is t + Δt … committed KinematicState" | MODEL | Driveline.Schedule | predicate env at tick k has `simTime = (k+1)*dt` | TODO |
| P11-12 | 11:23 | "If the predicate is true … no on statement fires" | MODEL | Driveline.Schedule | `term k → onFired k = ∅` | TODO |
| P11-13 | 11:23 | "static actor's committed state keeps every field except timestamp_ns" | MODEL | Driveline.Schedule | frame lemma on the commit | TODO |
| P11-14 | 11:23 | "adds the horizontal distance … to odometer_m" | REAL | Driveline.Schedule | the odometer never decreases (dist ≥ 0) | TODO |
| P11-24 | 11:27 | "ascending order of actor_id … group sorts by its smallest member" | DECIDE | Driveline.Schedule | evaluation order = `sortBy (minId)`; well defined because ids are unique (16:71) and groups are disjoint | TODO |
| P11-25 | 11:27 | "left-to-right order of their calls … after fn substitution" | MODEL | Driveline.Schedule | order = lexicographic topological sort, tie-break by call position; `IsTopo` | TODO |
| P11-26 | 11:27 | "per-actor instances … in bind order before the next component" | MODEL | Driveline.Schedule | group order = component-major, bind-minor | TODO |
| P11-27 | 11:27 | "No component reads another entity's output within a tick, so this order never delays data" | MODEL | Driveline.Schedule | the read set of an entity's components ⊆ that entity's buffers ∪ the P1 snapshot | TODO |
| P11-28 | 11:27 | "Phase 2 is data-race-free and parallelizable across actors" | MODEL | Driveline.Schedule | any interleaving of entity blocks gives the same state (commutation) | TODO |
| P05-40 | 05:40 | 'On a tick where a producer does not step ..., its consumers receive its last output again' | MODEL | Driveline.Schedule | delivered frame on a non-stepping tick = last output | TODO |

### WP05 Diagnostics and run record (§14, §18)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P11-21 | 11:24 | "first tick that a pair is in contact, and on no later tick" | MODEL | Driveline.RunRecord | `∀ pair, count collisionLines pair ≤ 1`; a line exists ↔ ∃ tick in contact | TODO |
| P14-01 | 14:12 | "negative code is an error. positive … warning" | DECIDE | Driveline.Diagnostics | `severity c = if c<0 then err else if c>0 then warn else ok` | TODO |
| P14-03 | 14:26 | "DL_STATUS_ERR_FMU … Components never return it" | MODEL | Driveline.Diagnostics | a component-returned -6 is invalid | TODO |
| P14-04 | 14:30 | warnings: "The run continues" | MODEL | Driveline.Diagnostics | a warning does not change the control state | TODO |
| P14-05 | 14:31 | "reported error is the first failing call in the order of §11" | MODEL | Driveline.Diagnostics | `reported = (seqOrder.filter failed).head?`, independent of parallel interleaving | TODO |
| P14-06 | 14:31 | "reports are exactly those that sequential execution … up to and including that error" | MODEL | Driveline.Diagnostics | `reports par = takeWhileIncl (¬isErr) (reports seq)` | TODO |
| P14-07 | 14:32 | "teardown … descending actor_id … group sorted by smallest member … reverse of Phase 2 order, physics first … reverse bind order" | DECIDE | Driveline.Diagnostics | `teardownOrder = reverse startupOrder` (if the phrase is meant literally, a theorem) | TODO |
| P14-08 | 14:32 | "dl_terminate if the state allows it … dl_free_instance if not Uninstantiated" | MODEL | Driveline.Diagnostics | per-instance teardown state machine is total and ends in Freed/Uninstantiated | TODO |
| P14-09 | 14:33 | "group instance's frames are checked in actor_ids order, each through every step … first failure" | MODEL | Driveline.Diagnostics | validation = frame-major, check-minor; first failure in that order is the result (rest cut off by the tool) | TODO |
| P14-10 | 14:33 | "every mode field must hold one of its listed values … counts … at m…" | DECIDE | Driveline.Diagnostics | `validFrame` is decidable; count ≤ capacity | TODO |
| P14-11 | 14:34 | "cold init carries tick 0 … splice window carries the tick after … tick k, Phase 4 included" | MODEL | Driveline.Diagnostics | `reportTick` by context; `simTime = reportTick*dt` | TODO |
| P14-12 | 14:34 | "teardown report carries the same tick … as the error … or … the tick whose Phase 4 ended it" | MODEL | Driveline.Diagnostics | teardown tick = tick of the terminating event | TODO |
| P14-13 | 14:34 | report field order "tick, sim_time_ns, severity, co…" | MODEL | Driveline.RunRecord | field list fixed (shared with 18:21) | TODO |
| P18-01 | 18:16 | "JSON Lines … no other whitespace … member order … escapes" | MODEL | Driveline.RunRecord | `encode` injective; `decode ∘ encode = id` | TODO |
| P18-02 | 18:16 | "integer … decimal with no leading zeros" | INT | Driveline.RunRecord | canonical `Nat.repr` (sign rule not stated) | TODO |
| P18-03 | 18:20,23 | "Header: first line … End: last line" | MODEL | Driveline.RunRecord | `head = header ∧ last = end`; exactly one of each | TODO |
| P18-04 | 18:22 | "actor_a and actor_b … ascending" | DECIDE | Driveline.RunRecord | `a < b` | TODO |
| P18-05 | 18:22 | "(v_lon cos ψ − v_lat sin ψ, v_lon sin ψ + v_lat cos ψ)" | REAL | Driveline.RunRecord | equals `rot ψ (v_lon, v_lat)`; norm preserved | TODO |
| P18-06 | 18:22 | "Lines of one tick follow the pair …" | DECIDE | Driveline.RunRecord | within a tick, collision lines are sorted lex by (a,b) | TODO |
| P18-07 | 18:23 | "0 and 0 for a run that fails during cold init" | MODEL | Driveline.RunRecord | the end line on a cold-init failure has tick 0 | TODO |
| P18-08 | 18:25 | "committed state after Phase 4 of tick k has tick k+1" | INT | Driveline.RunRecord | `collisionTick = reportTick + 1` within one Phase 4 | TODO |
| P18-09 | 18:25 | "ticks need not increase from line to line" | MODEL | Driveline.RunRecord | counterexample witness; prove only `tick(l₂) ≥ tick(l₁) - 1` for consecutive body lines | TODO |
| P18-10 | 18:25 | "Lines … in the order that sequential execution … produces" | MODEL | Driveline.RunRecord | `body = trace seqExec` | TODO |

### WP06 Manifest, types, units (§15, §16)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P00-01 | 00:35 | 'Tick k starts at t = k * dt_base' | INT | Driveline.Units | tickStart k = k*dt; strictly monotone in k when dt>0; no UInt64 overflow for k < 2^64/dt | TODO |
| P02-01 | 02:15 | 'unsigned 64-bit count of nanoseconds' | MODEL | Driveline.Units | Timestamp := UInt64; FrameTime := Int64; DSL Time := Int64 | TODO |
| P02-02 | 02:15 | 't - 0.18s is -130,000,000 ns' at t=0.05s | INT | Driveline.Units | (50_000_000 : Int) - 180_000_000 = -130_000_000 (by decide/omega) | TODO |
| P02-03 | 02:15 | 'Overflow in Time arithmetic is DL_STATUS_ERR_NUMERIC' | INT | Driveline.Units | checkedAdd a b = ok (a+b) <-> -2^63 <= a+b < 2^63, else err NUMERIC | TODO |
| P03-09 | 03:31 | 'holds when abs(a-b) <= 1e-6 * max(abs a, abs b, 1)' | REAL | Driveline.Units | approxEq refl and symm; NOT transitive (counterexample); exact equality implies approxEq | TODO |
| P11-07 | 11:16 | "Stage 3 … k_div = 1. A rate clause on a Stage 3 component is a compile-time error" | MODEL | Driveline.Types | `stage3 c → div c = 1`; matches 16:91 ("output is KinematicState") only if stage 3 ⇔ KinematicState output (15:42) | TODO |
| P15-01 | 15:16-22 | signature source table | MODEL | Driveline.Manifest | `sigSource : Kind → Source` is total | TODO |
| P15-02 | 15:24 | "signature from its declaration is OneToOne, reads no Tier 3 deck" | MODEL | Driveline.Manifest | `declSig → card = OneToOne ∧ decks = []` | TODO |
| P15-03 | 15:24 | "Every input port of a Mode B declaration must be a SliceBuffer" | DECIDE | Driveline.Types | `modeB → ∀ p, isSliceBuffer p.ty` | TODO |
| P15-04 | 15:26 | "declared ports, output type, required_tier must equal the manifest's" | DECIDE | Driveline.Manifest | equality check is decidable | TODO |
| P15-05 | 15:40 | "abi_version must equal the runtime's" | DECIDE | Driveline.Manifest | string equality | TODO |
| P15-06 | 15:42 | "stage 1, 2, 3 … must agree with output" | DECIDE | Driveline.Manifest | `stageOf output = stage` | TODO |
| P15-07 | 15:44 | "required_tier 0, 1, or 2" | DECIDE | Driveline.Manifest | `tier ∈ {0,1,2}` | TODO |
| P15-08 | 15:45 | "entity … only in a Stage 3 manifest … object requires required_tier 0" | DECIDE | Driveline.Manifest | `entity? ≠ none → stage=3`; `entity=object → tier=0` | TODO |
| P15-09 | 15:48 | "unit '1' for i64, Bool, enum, 's' for Time" | DECIDE | Driveline.Manifest | `unitOk ty u` decidable | TODO |
| P15-10 | 15:48 | "null default makes the parameter mandatory" | MODEL | Driveline.Manifest | `mandatory p ↔ p.default = none` | TODO |
| P15-11 | 15:49 | "An entry must include the field's baseline modes" | DECIDE | Driveline.Manifest | `baseline f ⊆ modes f`; a missing entry means all modes | TODO |
| P15-12 | 15:54 | "unknown name, missing mandatory, unit whose dimension differs" | DECIDE | Driveline.Manifest | call-site check over a finite map | TODO |
| P15-13 | 15:54 | "passes every parameter … in SI units, including defaults … f64 → type = 0" | MODEL | Driveline.Manifest | `encode` total over all params; tag injective (rest cut off by the tool) | TODO |
| P16-01 | 16:16 | "dimension over meters, kilograms, and seconds … rad/s and Hz same dimension" | INT | Driveline.Units | `Dim := ℤ×ℤ×ℤ` additive group; `mul = +`, `div = -` | TODO |
| P16-02 | 16:17 | Force N, Torque N·m, Pressure Pa, AngularVelocity 1/s | DECIDE | Driveline.Units | `N = (1,1,-2)`, `Pa = (-1,1,-2)`, by `decide`; AngularVelocity = Frequency | TODO |
| P16-03 | 16:18 | "Time: signed 64-bit count of nanoseconds … dimension s" | INT | Driveline.Types | `Time := Int64`; `dim Time = (0,0,1)` | TODO |
| P16-04 | 16:20 | "SliceBuffer<S,N> … 1 ≤ N ≤ 64 … TargetTrack is not" | DECIDE | Driveline.Types | `wfType` decidable | TODO |
| P16-05 | 16:27 | "T, Lon<T>, Lat<T> converts to Override<T> … Chain<A,B> converts to Chain<A,B'>" | MODEL | Driveline.Types | `conv` is a preorder; chain conversion is covariant in B | TODO |
| P16-06 | 16:33 | "Time literal … outside [-2^63, 2^63-1] ns is a compile-time error" | INT | Driveline.Types | exact ℚ→ℤ conversion, range test | TODO |
| P16-07 | 16:36 | "IntLit … above 2^63-1 is a compile-time error" | INT | Driveline.Types | `lit ≤ 2^63-1` | TODO |
| P16-08 | 16:43 | "A Time and a quantity of dimension s is a compile-time error" | DECIDE | Driveline.Types | `¬ typeOf (Time + Qty s)` | TODO |
| P16-09 | 16:43 | "Time*Int, Int*Time, Time/Int are Time" | DECIDE | Driveline.Types | typing rules | TODO |
| P16-10 | 16:44 | "/ on Int or Time truncates toward zero … zero divisor or overflow → ERR_NUMERIC" | INT | Driveline.Types | `Int.tdiv`; overflow iff result ∉ Int64 range (incl. `minInt / -1`) | TODO |
| P16-11 | 16:45 | "When a Time meets a quantity of dimension s, the Time converts to seconds" | MODEL | Driveline.Types | comparisons allow Time vs s; arithmetic does not (P16-08) | TODO |
| P16-12 | 16:47 | "== and != also accept Int, Bool, String, and enum" | DECIDE | Driveline.Types | typing rules | TODO |
| P16-14 | 16:91 | "required_tier must be 0, 1, or 2 … library component has no rate clause" | DECIDE | Driveline.Types | as in P15-07 | TODO |
| P16-15 | 16:99 | "exactly one map … timestep a Time above zero … seed from 0 to 2^63-1" | DECIDE | Driveline.Types | world-statement multiplicities | TODO |
| P16-16 | 16:102-103 | vehicle_spec / object_spec key rules | DECIDE | Driveline.Types | `tier2 → tier1`, `tier3 → tier1`; object dims > 0 | TODO |
| PH-01 | H:12 | 'DL_ABI_VERSION_0_20 0x00001400U' | DECIDE | Driveline.Units | 0x1400 = 20 * 256 | TODO |
| PH-02 | H:14-23 | status enum | DECIDE | Driveline.Units | OK = 0; warnings > 0; errors < 0; codes pairwise distinct | TODO |

### WP07 C-ABI rules (§9)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P07-01 | 07:15 | 'exactly its struct's size, or 16 + count · entry_size bytes' | INT | Driveline.Abi | payload length formula | TODO |
| P07-04 | 07:19 | 'newest first. Each entry is a uint64_t t_ns followed by the slice struct' | INT | Driveline.Abi | entry_size = 8 + sizeof(slice) (header is EXTERNAL) | TODO |
| P07-05 | 07:21 | 'a port named output, own_state, or dl_init_context is a compile-time error' | DECIDE | Driveline.Abi | name check | TODO |
| P07-06 | 07:25 | 'IntentFrame is intent-frame' | DECIDE | Driveline.Abi | kebab examples by `decide`; injective on CamelCase identifiers | TODO |
| P07-07 | 07:35 | 'conversion ... factor 1 and offset 0' | DECIDE | Driveline.Abi | unit check | TODO |
| P09-02 | 09:20 | '(major << 16) pipe (minor << 8)' | INT | Driveline.Abi | major<2^16, minor<2^8 ⇒ fits UInt32, injective, low byte 0 | TODO |
| P09-03 | 09:20 | 'Before version 1.0 ... only if their versions are equal' | DECIDE | Driveline.Abi | compat = eq | TODO |
| P09-05 | 09:21 | 'bytes after the null ... are zero ... byte comparisons ... deterministic' | DECIDE | Driveline.Abi | zeroed tail ⇒ (bytes equal ↔ strings equal) | TODO |
| P09-06 | 09:23 | 'actor_count entries, output_stride bytes apart' | INT | Driveline.Abi | entries don't overlap ⇔ stride ≥ sizeof(T) (unstated) | TODO |
| P09-07 | 09:24 | 'timestamp_ns is the tick time t ... KinematicState ... t + Δt_base ... also t + dt_step_ns' | INT | Driveline.Abi | k_div=1 (§11, EXTERNAL) ⇒ dt_step = Δt_base | TODO |
| P09-08 | 09:25 | 'dt_step_ns is k_div · Δt_base_ns' | INT | Driveline.Abi | definition | TODO |
| P09-09 | 09:26 | 'own_states[i] ... at tick time t' | INT | Driveline.Abi | previous physics stamp (t−Δt)+Δt = t, agrees with P09-07 | TODO |
| P09-10 | 09:31 | 'each s of a road lies in exactly one lane section' | REAL | Driveline.Abi | sorted starts from 0 ⇒ half-open intervals plus closed last one partition [0, len] | TODO |
| P09-11 | 09:33 | 'world_to_frenet succeeds for every finite (X, Y)' | DECIDE | Driveline.Abi | lexicographic tie-break is a linear order; totality needs a nonempty map | TODO |
| P09-12 | 09:35 | 'curvature is κ/(1 − κ d) ... negated when sampling toward decreasing s' | REAL | Driveline.Abi | same lemma as P06-01; d_offset sign flip keeps the side | TODO |
| P09-13 | 09:36 | 'writes at most max_successors ... out_num_successors to the total' | INT | Driveline.Abi | written = min(max, total) | TODO |

### WP08 Splice, init contexts, tier change, discrete parts (§6.2, §10.4)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P06-01 | 06:72 | 'kappa_0 = sigma · kappa_lane / (1 − kappa_lane · d_0)' | REAL | Driveline.InitContext | curvature of the offset curve at d equals κ/(1−κd) when κd<1; reversing direction negates it | TODO |
| P06-02 | 06:72 | 'kappa_lane · d_0 ≥ 1 ... ERR_NUMERIC' | DECIDE | Driveline.InitContext | guard passes ⇒ denominator > 0 (total and well-defined) | TODO |
| P06-04 | 06:73 | 'psi_0 = psi_travel − atan2(v_lat,ra, v_0) ... rear-axle velocity is tangent to the lane' | REAL | Driveline.InitContext | v0>0 ⇒ world direction of the rear-axle velocity ψ0+atan2(v_lat,v0) ≡ ψ_travel (mod 2π) | TODO |
| P06-05 | 06:73 | 'For KS, or at v_0 = 0, psi_0 = psi_travel' | REAL | Driveline.InitContext | for v0>0 with v_lat=0, atan2 term = 0; fails for v0<0 (Suspected issue 2) | TODO |
| P06-10 | 06:77 | 'slip_angle_alpha ... 0 for KS or when v_0 < 1 m/s, every reverse speed included' | DECIDE | Driveline.InitContext | case split on tier and v<1 | TODO |
| P06-11 | 06:77 | 'active_gear_index is −1 in REVERSE, 0 in PARK and NEUTRAL' | DECIDE | Driveline.InitContext | gear function is total; motor speed ≥ 0 (uses abs v0) | TODO |
| P06-14 | 06:78 | 'Every latched frame states every group in its baseline mode ... has no NONE group' | DECIDE | Driveline.InitContext | ∀ group in the Pass 1 frames, mode = baseline | TODO |
| P06-15 | 06:78 | 'steering_wheel_norm = clamp(δ_ss/δ_max, ±1)' | REAL | Driveline.InitContext | feasibility (abs δ_ss ≤ δ_max) ⇒ norm·δ_max = δ_ss, so the Tick 0 trim check passes | TODO |
| P06-16 | 06:79 | 'no buffer holds two samples at t = 0' | MODEL | Driveline.InitContext | Phase 1 is skipped on Tick 0 ⇒ timestamps in a buffer are strictly ordered | TODO |
| P06-17 | 06:83 | 'a promotion if ... required_tier is 0 and the incoming one's is 1 or 2, and a demotion in the reverse case' | DECIDE | Driveline.TierChange | classify : Fin 4 → Fin 4 → {promo, demo, none, ?}; tier 3 not covered | TODO |
| P06-18 | 06:83 | 'a splice between them changes no field' | DECIDE | Driveline.TierChange | tiers 1 ↔ 2 ⇒ update = id | TODO |
| P06-19 | 06:84 | 'A tier change keeps the sign of v_lon, so keeping chi keeps the path in reverse too' | REAL | Driveline.TierChange | rear-axle velocity direction = χ + (v<0 ? π : 0) is invariant when v_lon and χ are fixed | TODO |
| P06-20 | 06:84 | 'a_lon becomes a_lon − v_lat,ra psi_dot so that v_dot_lon is kept' | REAL | Driveline.TierChange | old v_lat = 0 ⇒ a'+v'ψ̇ = a (`ring`) | TODO |
| P06-21 | 06:84 | 'Five fields change' | DECIDE | Driveline.TierChange | changed fields ⊆ {v_lat, a_lon, fwa, β, ψ}; equality false when v<1 | TODO |
| P06-22 | 06:84 | 'psi = chi − gamma ... so the actor keeps its path, as at spawn' | REAL | Driveline.TierChange | ψ'+arctan(v'/v) ≡ χ (mod 2π) | TODO |
| P06-24 | 06:85 | 'a_lon becomes a_lon + v_lat,ra psi_dot with the old v_lat,ra' | REAL | Driveline.TierChange | new v_lat = 0 ⇒ v̇ kept (`ring`) | TODO |
| P06-25 | 06:85 | 'These five fields and β_cg change' | DECIDE | Driveline.TierChange | the diff set; β value unspecified | TODO |
| P06-26 | 06:86 | 'writes the changed fields into the committed state X(t) before any warm start. The map cache is left unchanged' | MODEL | Driveline.TierChange | update ∘ mapCache = mapCache | TODO |
| P06-27 | 06:87 | re-trim set: 'Stage 2 instance with a data path ... output type is not Lon<T>' | MODEL | Driveline.TierChange | set is a decidable graph filter; Phase 2 order is a sublist | TODO |
| P06-29 | 06:88 | 'a_lon_cmd equal to the committed v_dot_lon = a_lon + v_lat psi_dot' | REAL | Driveline.InitContext | on the Pass 1 state this equals 0 = the Pass 1 a_lon_cmd | TODO |
| P06-30 | 06:88 | 'v_0 = max(v_lon, 0)' | DECIDE | Driveline.InitContext | v_ref ≥ 0 | TODO |
| P06-31 | 06:88 | 'replaces each group ... not in its baseline mode, and is not NONE' | DECIDE | Driveline.InitContext | after conversion every group is baseline or NONE (not 'no NONE') | TODO |
| P06-32 | 06:88 | 'A component whose input and output types are equal ... gets its own last output' | MODEL | Driveline.InitContext | follows from the 'left the component' rule | TODO |
| P06-33 | 06:90-92 | 'Override<T> output delivers a frame with every group NONE' | DECIDE | Driveline.InitContext | conversion function cases | TODO |
| P06-34 | 06:93 | 'steering group becomes ANGLE ... A NONE steering group stays NONE ... Longitudinal fields keep their last values' | DECIDE | Driveline.TierChange | idempotent; leaves longitudinal fields unchanged | TODO |
| P06-35 | 06:94 | slip_angle 0 'when v_lon < 1 m/s ... or when the required_tier ... is 0' | DECIDE | Driveline.InitContext | case split | TODO |
| P06-36 | 06:95 | 'matches each context to its actor slot by chassis_state.actor_id ... in its actor_ids order' | DECIDE | Driveline.InitContext | Nodup actor_ids ⇒ contexts = filter, a Sublist, with injective matching; re-trim filters on tierChanged | TODO |
| P10-01 | 10:13,17-19 | cardinality table | MODEL | Driveline.Splice | dependency relation for each cardinality | TODO |
| P10-03 | 10:21 | 'bind a -> chain means exactly bind [a] -> chain'; distinct; order | DECIDE | Driveline.Splice | List.Nodup | TODO |
| P10-16 | 10:30 | 'so a partial target needs a partial replacement' | DECIDE | Driveline.Splice | spliceOK tgt rep -> isPartial tgt.out -> isPartial rep.out (suspected false) | TODO |
| P10-17 | 10:30 | 'one target contains the other' vs 'Two splices of the same target are allowed' | DECIDE | Driveline.Splice | strict containment relation | TODO |
| P10-18 | 10:31 | 'fires at most once ... in source order' | MODEL | Driveline.Splice | - | TODO |
| P10-19 | 10:32 | ascending actor_id, all-or-nothing write; net change 'between 0 and 1 or 2' | MODEL | Driveline.Splice | netChange b a := (b = 0) != (a = 0) | TODO |
| P10-20 | 10:32 | instantiate/teardown ordering | MODEL | Driveline.Splice | - | TODO |
| P10-21 | 10:33 | 'A single splice statement does not' | MODEL | Driveline.Splice | - | TODO |
| P05-41 | 05:32 | 'A frame that the runtime builds by the rules of Pass 1 step 5 uses only baseline modes' | MODEL | Driveline.InitContext | every Pass 1 step 5 frame has isBaseline modes | TODO |
| P05-42 | 05:32 | 'the steering that the runtime writes after a tier change uses ANGLE' | MODEL | Driveline.TierChange | steering replacement sets steer_mode/wheel_mode ANGLE | TODO |
| P10-40 | 10:25 | 'the runtime re-forms its merged frame in the splice window ... stamped with the next tick's time' | MODEL | Driveline.Splice | splice-window merged frame stamp = next tick time | TODO |

### WP09 Angles and rigid-body kinematics (§2, §5.3)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P02-05 | 02:16 | '+X East, +Y North, +Z Up' right-handed | REAL | Driveline.Angles | e_x x e_y = e_z | TODO |
| P02-06 | 02:17 | 'intrinsic Z-Y'-X'' (yaw -> pitch -> roll)' | REAL | Driveline.Angles | R = Rz psi * Ry theta * Rx phi; R in SO(3) (R^T R = 1, det R = 1) | TODO |
| P02-07 | 02:17 | 'counter-clockwise positive by the right-hand rule' | REAL | Driveline.Angles | d/dpsi of Rz psi * e_x at 0 = e_y | TODO |
| P02-08 | 02:18 | 'It equals the body frame when roll and pitch are 0' | REAL | Driveline.Angles | eulerZYX psi 0 0 = Rz psi | TODO |
| P02-15 | 02:27 | 'theta_road = sigma arctan(dz/ds)' / 'positive when the road rises in the driving direction' | REAL | Driveline.Angles | sign theta_road = sign (sigma * dz/ds); abs theta_road < pi/2 | TODO |
| P02-16 | 02:27 | 'An actor that drives against its lane ... still gets these lane-relative signs' | REAL | Driveline.Angles | theta_road depends only on (lane, s), not on the actor's heading/velocity | TODO |
| P04-11 | 04:30 | 'ANGLE field, the difference ... is wrapped to (-pi, pi]' | REAL | Driveline.Angles | wrap x in Ioc (-pi) pi; wrap x - x in 2*pi*Z; wrap idempotent | TODO |
| P04-18 | 04:37 | 'A difference of exactly pi therefore turns positive' | REAL | Driveline.Angles | wrap (-pi) = pi; wrap pi = pi | TODO |
| P04-19 | 04:37 | 'v_{k+1} + alpha Delta, wrapped' | REAL | Driveline.Angles | result in (-pi, pi]; alpha = 0 gives wrap v_{k+1} (follows a shortest-arc path) | TODO |
| P05-23 | 05:76 | 'before t_0 it is the first point ... after the last point it is the last point, held' | MODEL | Driveline.Kinematics | target interp traj t: t <= t0 gives p0; t >= tn gives pn; n = 1 gives a constant | TODO |
| P05-25 | 05:78 | 'remaining stopping distance is stop_at_odometer - own.odometer_m' | REAL | Driveline.Kinematics | if odometer is monotone, remaining is antitone | TODO |
| P05-28 | 05:92-93 | 'differs from the reported a_lon ... by v_lat psi_dot'; committed vdot = a_lon + v_lat psi_dot | REAL | Driveline.Kinematics | follows from P05-37 | TODO |
| P05-32 | 05:122 | 'v_y,cg = v_lat + l_r psi_dot' | REAL | Driveline.Kinematics | planar rigid body: v_P = v_O + omega x r with r = (l_r, 0) | TODO |
| P05-33 | 05:122-123 | beta = atan2(sgn(v_lon) v_y, abs v_lon), sgn(0) = +1, 0 at rest | REAL | Driveline.Kinematics | define with Complex.arg; beta 0 0 = 0 | TODO |
| P05-34 | 05:123 | 'equals arctan(v_y,cg / v_lon) whenever v_lon != 0, including reverse' | REAL | Driveline.Kinematics | v != 0 -> beta = Real.arctan (vy / v); true for both signs | TODO |
| P05-35 | 05:124 | KS: 'beta_cg = arctan(l_r/L tan delta) != 0 for v_lon != 0' | REAL | Driveline.Kinematics | the equality holds; the != 0 part needs delta != 0 and l_r != 0 | TODO |
| P05-36 | 05:133 | 'v_lat = -l_r psi_dot + v_y,cg' | REAL | Driveline.Kinematics | rearrangement of P05-32 | TODO |
| P05-37 | 05:135 | 'a_lon = vdot_lon - v_lat psi_dot and a_lat = vdot_lat + v_lon psi_dot' | REAL | Driveline.Kinematics | HasDerivAt of R(psi) v in rotating axes | TODO |
| P05-38 | 05:141 | odometer 'never decreases' | DECIDE | Driveline.Kinematics | round-to-nearest add is monotone; sqrt >= 0 | TODO |

### WP10 Steady state and axle loads (§6.2, §8)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P06-03 | 06:73 | 'sets psi_dot_0 = v_0 kappa_0' | REAL | Driveline.SteadyState | path curvature of the rear axle = ψ̇/‖(v,v_lat)‖ = κ0 ⇔ v_lat = 0 (see Suspected issue 1) | TODO |
| P06-06 | 06:75 | 'F_z,f = m g cosθ cosφ l_r/L − m g sinθ h_cg/L ...' | REAL | Driveline.AxleLoad | L = l_f + l_r ⇒ F_zf + F_zr = m g cosθ cosφ | TODO |
| P06-07 | 06:76 | 'an uphill road (θ_road > 0) moves load to the rear axle' | REAL | Driveline.AxleLoad | m,g,h_cg>0, θ∈(0,π/2) ⇒ F_zr > m g cosθ cosφ l_f/L and F_zf decreases | TODO |
| P06-08 | 06:74 | 'both are negated when the actor's yaw differs ... by more than π/2' | REAL | Driveline.AxleLoad | negating θ swaps the transfer term; the heading test uses the angle difference wrapped to [0,π] | TODO |
| P06-09 | 06:77 | 'normal_load_fz is half of the axle load' | REAL | Driveline.AxleLoad | sum over the 4 wheels = m g cosθ cosφ | TODO |
| P06-12 | 06:78 | 'a_lon = −v_lat,ra psi_dot_0' | REAL | Driveline.SteadyState | v̇_lon = a_lon + v_lat ψ̇ = 0 (`ring`) | TODO |
| P06-13 | 06:78 | 'a_lat = v_0 psi_dot_0 (the rear-axle acceleration on the steady circle)' | REAL | Driveline.SteadyState | body-y acceleration v̇_lat + vψ̇ with v̇_lat = 0 | TODO |
| P06-23 | 06:84 | 'lateral force and yaw moment ... balanced at the first step if the upstream steering command reproduces δ_ss' | REAL | Driveline.SteadyState | follows from P08-03 + P08-04 | TODO |
| P06-37 | 06:96 | 'δ_ss − δ_KS ≈ K_us v_lon psi_dot' | REAL | Driveline.SteadyState | δ_ss−δ_KS = (α_f−α_r) + O(ε²) and α_f−α_r = K_us·a_y exactly | TODO |
| P08-01 | 08:12 | 'a_y = v psi_dot' | REAL | Driveline.SteadyState | definition | TODO |
| P08-02 | 08:14 | 'δ_KS = arctan(L psi_dot / v)' | REAL | Driveline.SteadyState | inverts ψ̇ = v tanδ/L on (−π/2, π/2) | TODO |
| P08-03 | 08:18 | 'axle forces sum to m a_y and the yaw moment l_f F_yf − l_r F_yr is zero' | REAL | Driveline.SteadyState | L=l_f+l_r ⇒ both (`field_simp; ring`) | TODO |
| P08-04 | 08:17 | 'v_lat,ra = −v tan α_r, δ_ss = α_f + arctan(...)' | REAL | Driveline.SteadyState | v>0 ⇒ slip formulas reproduce α_f and α_r | TODO |
| P08-05 | 08:17 | 'β_cg = arctan((v_lat,ra + l_r psi_dot)/v)' | REAL | Driveline.SteadyState | CG lateral velocity = v_lat,ra + l_r ψ̇ | TODO |
| P08-07 | 08:19 | 'infeasible if abs δ_ss > δ_max, or if abs a_y > μ g' | MODEL | Driveline.SteadyState | decidable predicate; g constant | TODO |

### WP11 Contact test (§11)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P11-15 | 11:24 | "every pair a < b … except a pair of two static actors, ascending (a,b)" | DECIDE | Driveline.Contact | pair list = sorted lex filter; `Nodup`, `Sorted` | TODO |
| P11-16 | 11:24 | "overlap or touch … height intervals overlap or touch" | REAL | Driveline.Contact | closed-interval overlap `max lo ≤ min hi` | TODO |
| P11-17 | 11:24 | "largest projection of one rectangle is below the smallest projection of the other" | REAL | Driveline.Contact | strict `<` ⇒ touching counts; `contact a b ↔ (rect a ∩ rect b).Nonempty` (closed sets, SAT for convex polygons with edge normals) | TODO |
| P11-18 | 11:24 | (symmetry, implied) | DECIDE | Driveline.Contact | `contact a b = contact b a`, exact even in binary64, because the axis set and the corner projections do not depend on argument order | TODO |
| P11-19 | 11:24 | (rotation invariance, implied) | REAL | Driveline.Contact | holds over ℝ for a global rotation/translation; **false for binary64** (`cos`/`sin` rounding), so do not claim it for the Float model | TODO |
| P11-20 | 11:24 | "p + x u + y n … evaluated left to right per component"; "q_X w_X + q_Y w_Y" | MODEL | Driveline.Contact | Float model fixes the association `(p+x*u)+y*n`; no FMA (11:31) | TODO |
| P11-22 | 11:24 | "also on the spawn state at the end of cold init … tick 0" | MODEL | Driveline.Contact | contact test also runs at committed tick 0 | TODO |
| P11-23 | 11:25 | "60 m/s and a 500 Hz … 0.12 m" | INT | Driveline.Contact | `60/500 = 0.12` by `norm_num` | TODO |

### WP12 Sensors (§17.2)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P17-02 | 17:24 | "Where zones overlap, the later statement wins" | DECIDE | Driveline.Sensors | mu(road,s) is the mu of the last zone in the list with s0≤s<s1, else the default (foldl lemma) | TODO |
| P17-03 | 17:34 | "the zone or default value at the lane that world_to_frenet returns" | MODEL | Driveline.Sensors | μ(X,Y) := field ∘ w2f, with w2f an axiom; total only if w2f is total | TODO |
| P17-08 | 17:38 | "history must be a constant from 1 to 64" | DECIDE | Driveline.Sensors | range check | TODO |
| P17-09 | 17:48 | "bearing ... lies within ±fov/2" | REAL | Driveline.Sensors | atan2 ∈ (−π,π], so fov=2π detects every target in range | TODO |
| P17-10 | 17:48 | "rel_vx gains ψ̇ y and rel_vy loses ψ̇ x" | REAL | Driveline.Sensors | HasDerivAt: d/dt Rᵀ(p_T−p_S) = Rᵀ(v_T−v_S) − ψ̇ẑ×rel | TODO |
| P17-11 | 17:48 | "keep a constant gap on a curve therefore have zero relative velocity" | REAL | Driveline.Sensors | rel constant in the sensor frame → rel_v=0 → ttc=+∞ (from P17-10) | TODO |
| P17-12 | 17:48 | "v_P = v_ra + ψ̇ ẑ × r_P" | REAL | Driveline.Sensors | rigid-body velocity lemma | TODO |
| P17-13 | 17:48 | "ttc_lon is max(0, ...)/(−v_x)" | REAL | Driveline.Sensors | 0 ≤ ttc_lon in EReal | TODO |
| P17-14 | 17:48 | "x_front = L + o_f − x_mount" | REAL | Driveline.Sensors | FrontBumper gives x_front=0 | TODO |
| P17-15 | 17:54 | "nearest ... by range and then smaller target_actor_id" | DECIDE | Driveline.Sensors | lexicographic argmin is unique when ids are distinct and satisfies the filter | TODO |
| P17-16 | 17:54 | "primary_rcs is 10 dBsm ... and 0 otherwise" | DECIDE | Driveline.Sensors | definitional | TODO |
| P17-17 | 17:58 | "smallest positive rel_x, then the smaller target_actor_id" | DECIDE | Driveline.Sensors | lead is unique; lead_ttc=+∞ ↔ no lead | TODO |
| P17-18 | 17:58 | "out_left_lane_id ... if σ = +1" | DECIDE | Driveline.Sensors | the left/right swap under σ is an involution | TODO |
| P17-19 | 17:56 | "mu_mean is their mean" | REAL | Driveline.Sensors | min ≤ mean ≤ max | TODO |
| P05-43 | 05:80 | 'g is that track's rel_x' | MODEL | Driveline.Sensors | measured gap = rel_x of the track with target_actor_id = gap_target_actor_id from latest() of the first such port | TODO |

### WP13 Standard components (§17.3–17.5)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P17-01 | 17:28 | "min(max(x, lo), hi)" | REAL | Driveline.Std.Controllers | lo≤hi → lo ≤ clamp x lo hi ≤ hi; clamp is idempotent | TODO |
| P17-04 | 17:30 | "the first route node whose road_id equals from.road_id" | DECIDE | Driveline.Std.Controllers | List.find? spec, falling back to the own lane | TODO |
| P17-20 | 17:65 | "v_ref = max(0, v_target + 0.5 s⁻¹(o_j − Δx_j))" | REAL | Driveline.Std.Controllers | v_ref ≥ 0; the closed loop ẋ = −0.5(x+o_j) converges to x = −o_j | TODO |
| P17-21 | 17:77 | "continues from the previous output without a step when k_i ≠ 0" | REAL | Driveline.Std.Controllers | ki≠0 → first output after rebase = a_prev (field_simp) | TODO |
| P17-22 | 17:77 | "or I = 0 if k_i = 0" | REAL | Driveline.Std.Controllers | ki=0 → output = kp·e, so a step is possible | TODO |
| P17-23 | 17:80 | "a_k = a_{k−1} + clamp(..., ± max_jerk·dt)" | REAL | Driveline.Std.Controllers | abs(a_k−a_{k−1}) ≤ max_jerk·dt | TODO |
| P17-24 | 17:83 | "δ = clamp(..., ±δ_max)" | REAL | Driveline.Std.Controllers | δmax≥0 → abs δ ≤ δmax | TODO |
| P17-25 | 17:84 | "the output is arctan(Lκ_p), which is δ_KS" | REAL | Driveline.Std.Controllers | e=0 ∧ ψe=0 ∧ abs(arctan Lκ) ≤ δmax → δ = arctan Lκ | TODO |
| P17-26 | 17:82 | "smallest index winning ties" | DECIDE | Driveline.Std.Controllers | argmin with index tiebreak is unique | TODO |
| P17-27 | 17:87 | "the largest gear index g with ... ≥ 157.08 rad/s, or gear 1" | INT | Driveline.Std.Drivetrain | num_gears≥1 → g ∈ [1, num_gears]; if i_g decreases, the qualifying gears form a prefix | TODO |
| P17-29 | 17:89 | "comes to rest instead of creeping" | REAL | Driveline.Std.Drivetrain | abs v < 0.01 ∧ abs F_drive ≤ F_hold → v+a·Δt ∈ [0,v] when Δt ≤ dt | TODO |
| P17-30 | 17:89 | "(own.v_lat + l_r·yaw_rate)·yaw_rate" | REAL | Driveline.Std.Drivetrain | v̇x = F/m + v_y·r, consistent with the DST init v_y = v_lat + l_r·r | TODO |
| P17-31 | 17:89 | "steering_wheel_norm · δ_max" | REAL | Driveline.Std.Drivetrain | abs norm ≤ 1 → abs cmd ≤ δmax | TODO |
| P17-32 | 17:91 | "comes whole from secondary if its mode there is not NONE" | DECIDE | Driveline.Std.Controllers | per-group selection, so groups are never mixed | TODO |
| P17-33 | 17:100 | "Clamp v_lon ← max(0, v_lon) ... a ← max(0, a)" | REAL | Driveline.Std.KinematicBicycle | invariant v≥0; v=0 → a≥0 | TODO |
| P17-34 | 17:101 | "roll and pitch to 0. The standard physics is planar" | MODEL | Driveline.Std.KinematicBicycle | post-state roll=pitch=0 ∧ Z = elev(X,Y), by construction | TODO |
| P17-35 | 17:107 | "clamp(δ_cmd − δ, ±ρΔt)" | REAL | Driveline.Std.KinematicBicycle | abs(δ'−δ) ≤ ρΔt (ANGLE) or ≤ δ̇maxΔt (RATE); a later projection is nonexpansive | TODO |
| P17-36 | 17:107 | "Then abs δ ≤ δ_max" | REAL | Driveline.Std.KinematicBicycle | ANGLE: convex step keeps the bound if δ and δcmd are within it; RATE: false without an explicit clamp | TODO |
| P17-37 | 17:108 | "reaches a_cmd at once when the bound is +INFINITY" | REAL | Driveline.Std.KinematicBicycle | jerk=+∞ → a' = a_cmd | TODO |
| P17-38 | 17:111 | "ψ̇ = (v/L) tan δ" | MODEL | Driveline.Std.KinematicBicycle | Euler step by definition; well-defined iff abs δ < π/2 | TODO |
| P17-39 | 17:112 | "a_lat = vψ̇" | REAL | Driveline.Std.KinematicBicycle | definitional | TODO |
| P17-40 | 17:115 | "F_yi = clamp(C_αi α_i, ±μ_i max(0, F_zi))" | REAL | Driveline.Std.DynamicSingleTrack | μ_i≥0 → abs F_yi ≤ μ_i·max(0, F_zi) | TODO |
| P17-41 | 17:116 | "This small-angle model matches §8" | REAL | Driveline.Std.DynamicSingleTrack | a=0 ∧ the §8 steady state → v̇y = ṙ = v̇x = 0 (see issue 3) | TODO |
| P17-42 | 17:117 | "Δt < 2abs(Re λ)/abs(λ)²" | REAL | Driveline.Std.DynamicSingleTrack | abs(1+λh) < 1 ↔ Re λ < 0 ∧ h < −2Re λ/abs(λ)² | TODO |
| P17-44 | 17:117 | "the friction limit is the same in both regimes" | REAL | Driveline.Std.DynamicSingleTrack | both regimes use v̇ = clamp(a, ±μ̄g) | TODO |
| P17-45 | 17:117 | "the reset leaves both slip angles at 0" | REAL | Driveline.Std.DynamicSingleTrack | v_y = l_r·r ∧ r = v·tanδ/L ∧ abs δ < π/2 → α_f = α_r = 0 | TODO |
| P17-46 | 17:117 | "a_lon = v̇_x − v_lat r" | REAL | Driveline.Std.DynamicSingleTrack | round trip with the init formula a = a_lon + v_lat·ψ̇ | TODO |
| P17-47 | 17:120-121 | "v_t = min(v_ref, v_max, ...)", "v' = max(0, ...)" | REAL | Driveline.Std.ObjectPhysics | invariant 0 ≤ v ≤ v_max; abs(v'−v) ≤ a_max·Δt | TODO |
| P17-48 | 17:122,124 | "clamp(w(ψ_d − ψ), ±max_turn_rate Δt)" | REAL | Driveline.Std.ObjectPhysics | w(c)=c on (−π,π] → abs yaw_rate ≤ max_turn_rate | TODO |
| P17-49 | 17:120 | "square root of +INFINITY is +INFINITY" | REAL | Driveline.Std.ObjectPhysics | ENNReal sqrt lemma | TODO |
| P17-50 | 17:126 | "v capped at v_max" | DECIDE | Driveline.Std.ObjectPhysics | init establishes the P17-47 invariant | TODO |
| P17-51 | 17:70 | "each no-bound field +INFINITY" | MODEL | Driveline.Std.Controllers | outputs satisfy the §5.2 validity rules; fails for PID (no clamp) | TODO |

### WP14 Modules and lockfile (§19, §12)

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P12-01 | 12:14-15 | ScenarioFile / ModuleFile | DECIDE | Driveline.Modules | the reserved word scenario separates the two | TODO |
| P12-02 | 12:13-76 | EBNF | DECIDE | Driveline.Modules | LL(2) table has no conflicts (ImportDecl, PrimaryPipe, Arg, EnvBlock, Rate/TierClause) | TODO |
| P12-03 | 12:80 | "Every other quoted word ... is a contextual keyword" | DECIDE | Driveline.Modules | Ident excludes exactly the 16 reserved words | TODO |
| P12-04 | 12:82 | "inside a TypeSpec's type-argument list >> is two >" | DECIDE | Driveline.Modules | context-sensitive lexer | TODO |
| P12-05 | 12:82 | "N/m*s is also N·s/m" | INT | Driveline.Modules | left fold over ℤ⁷ dimension vectors | TODO |
| P12-06 | 12:82 | "3.0m/speed is a lexical error" | DECIDE | Driveline.Modules | the lexer rejects it | TODO |
| P12-07 | 12:83 | FreqLit / TimeLit | DECIDE | Driveline.Modules | the unit is exactly one atom | TODO |
| P12-08 | 12:81 | StringLit escapes | DECIDE | Driveline.Modules | only \" and \\ escapes; U+0000–U+001F rejected | TODO |
| P12-09 | 12:62 | CmpExpr "?" | DECIDE | Driveline.Modules | a<b<c does not parse | TODO |
| P17-05 | 17:23 | "At most 64 lane reference strings" | DECIDE | Driveline.Modules | static length check | TODO |
| P19-01 | 19:16 | "together with a manifest ... is a compile-time error" | DECIDE | Driveline.Modules | resolve is total with three outcomes: decl, native, error | TODO |
| P19-03 | 19:18 | "more than once adds one name" | DECIDE | Driveline.Modules | conflict ↔ same name with distinct identities | TODO |
| P19-04 | 19:18 | "nothing it imports" | DECIDE | Driveline.Modules | exports m = topDecls m | TODO |
| P19-05 | 19:19 | "A cycle of imports is a compile-time error" | DECIDE | Driveline.Modules | acyclic → a topological order exists | TODO |
| P19-06 | 19:23 | "whether or not the scenario uses the declaration" | DECIDE | Driveline.Modules | resolved inputs = transitive closure | TODO |
| P19-07 | 19:23 | "scheme of two or more characters" | DECIDE | Driveline.Modules | "C:/x" is not a scheme; "ab:x" is | TODO |
| P19-08 | 19:25 | "..` only as leading segments" | DECIDE | Driveline.Modules | normalize is idempotent; output has no empty or . segments | TODO |
| P19-09 | 19:25 | "sorted by path ... one entry" | DECIDE | Driveline.Modules | Sorted (<) → Nodup | TODO |
| P19-11 | 19:26 | "exactly the bytes of item 1's form" | DECIDE | Driveline.Modules | accept ↔ canonical(parse b) = b ∧ entry set = resolved set | TODO |

### — Not provable in Lean

| ID | Spec | Quote | Class | Lean module | Statement | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| P09-14 | — | ring index formula | — | — | not in §6–§9; probably §5 or §11 | DUP: PH-03 |
| P00-06 | 00:22 | 'If no such heading exists, it names numbered item M' | PROSE | — | reference-resolution rule; no numeric consequence | OUT: prose |
| P02-04 | 02:14 | 'Strict SI Units' | PROSE | Driveline.Units | dimension tags only (optional phantom-typed Quantity) | OUT: prose |
| P02-17 | 02:23-24 | 's ... along the OpenDRIVE road reference line'; 'd ... from the centerline of lane_id' | EXTERNAL | — | OpenDRIVE geometry; abstract Map axiomatization only | OUT: external |
| P03-10 | 03:31 | '0.1 + 0.2 + 0.3 != 0.6 while 0.3 + 0.2 + 0.1 = 0.6' | EXTERNAL | Driveline.Units | binary64 rounding; Lean Float can confirm with native_decide but the kernel cannot prove it | OUT: external |
| P03-18 | 03:40 | 'keeps abs v_lon <= v_max and abs a_lon <= a_max, and the runtime does not check them' | PROSE | — | component obligation the runtime does not check | OUT: prose |
| P03-28 | 03:30 | 'cannot be overridden inline' | CHECKED | — | grammar/static-semantics rule (§12/§16) | CHECKED |
| P03-29 | 03:36 | uri path normalization | EXTERNAL | — | filesystem / §19.2 path semantics | OUT: external |
| P04-12 | 04:30 | 'not finite ... {0.0, false}' | EXTERNAL | — | binary64 non-finite values; modelled as Option real | OUT: external |
| P04-28 | 04:44 | OSI mapping | EXTERNAL | — | ASAM OSI field semantics; open-items | OUT: external |
| P05-13 | 05:38 | 'checks them ... in the order that §14.2 gives' | EXTERNAL | Driveline.Validity | firstFailure returns the earliest failing rule | OUT: external |
| P05-16 | 05:40 | 'trajectory times and the stop target are absolute' | PROSE | — | - | OUT: prose |
| P05-19 | 05:69 | 'target_road_id names a road of the map ... num_waypoints is from 2 to 64' | EXTERNAL | Driveline.Validity | map oracle; range check | OUT: external |
| P05-21 | 05:72 | 'An IntentFrame requests forward travel' | PROSE | — | headings not checked | OUT: prose |
| P05-22 | 05:74 | Lane Target start-point rule | EXTERNAL | — | - | OUT: external |
| P05-24 | 05:76 | 'Frame validity checks only the parts of these rules that the list above names' | PROSE | — | - | OUT: prose |
| P06-28 | 06:87 | 'A Mode B FMU cannot be re-trimmed' | CHECKED | Driveline.TierChange | agrees with 07:30 | CHECKED |
| P07-02 | 07:17 | 'little-endian ... IEEE 754 binary64' | EXTERNAL | Driveline.Abi | host encoding, outside Lean | OUT: external |
| P07-03 | 07:18 | 'Times inside a frame ... are absolute simulation times' | PROSE | — | — | OUT: prose |
| P07-13 | 07:59 | 'sim_time_ns stays t' | CHECKED | Driveline.FmuTime | agrees with 06:94 | CHECKED |
| P08-06 | 08:18 | 'They must keep v_lon and psi_dot' | PROSE | — | — | OUT: prose |
| P08-08 | 08:20 | test vector, 'about 25% short' | CHECKED | Driveline.SteadyState | rational interval check; I derived L≈2.8, l_r≈1.547; 0.01331/0.01786 ⇒ 25.5% short; δ_ss−δ_KS = α_f−α_r = 0.00455 matches | CHECKED |
| P09-01 | 09:12 | 'Their layout is identical on 32-bit and 64-bit targets' | EXTERNAL | — | C compiler and header; needs a static_assert harness | OUT: external |
| P09-04 | 09:21 | 'road ID longer than 63 bytes ... longer than 55 bytes' | EXTERNAL | Driveline.Abi | header char[64]/char[56] | OUT: external |
| P10-02 | 10:19 | 'results must equal those of M OneToOne instances' | EXTERNAL | — | - | OUT: external |
| P10-04 | 10:22 | 'array literal with exactly M elements' | CHECKED | Driveline.Splice | - | CHECKED |
| P10-05 | 10:23 | 'output validation rejects one that is not' | CHECKED | Driveline.Validity | - | CHECKED |
| P10-10 | 10:26 | partial types chain within a branch | CHECKED | — | - | CHECKED |
| P10-14 | 10:27 | 'The runtime checks only the §5 validity of the output' | CHECKED | Driveline.Arbiter | the STT iff rule forces mode coupling but not the source group | CHECKED |
| P10-15 | 10:29 | physics_model splice of shared instance is an error | CHECKED | Driveline.Splice | - | CHECKED |
| P10-22 | 10:34 | 'exactly one Stage 3 physics component' | CHECKED | Driveline.Splice | - | CHECKED |
| P11-29 | 11:28 | "SipHash-2-4(key, msg) … 24-byte msg" | CHECKED | Driveline.Schedule | byte layout `msg.length = 24`; vector test | CHECKED |
| P11-30 | 11:30-31 | bit-identical / cross-platform conditions | EXTERNAL | — | depends on libm, compiler flags and IEEE hardware | OUT: external |
| P11-31 | 11:32 | "ORT_SEQUENTIAL and one intra-op thread" | EXTERNAL | — | runtime configuration of ONNX Runtime | OUT: external |
| P14-02 | 14:18-26 | codes 0, 2, 3, -1 … -6 | CHECKED | Driveline.Diagnostics | enum ↔ header table; injective; code 1 unused | CHECKED |
| P16-13 | 16:71 | "id … IntLit or HexLit token … at least 1, compared by value … unique" | CHECKED | Driveline.Types | `ids.Nodup ∧ ∀ i, 1 ≤ i ≤ 2^63-1` | CHECKED |
| P16-17 | 16:104 | tier record fields = header members | CHECKED | — | header-derived | CHECKED |
| P17-06 | 17:21 | "A negative v, or a v above ... v_max, is a compile-time error" | EXTERNAL | — | needs constant evaluation and the map | OUT: external |
| P17-07 | 17:26 | "so always false for two static actors" | EXTERNAL | — | depends on the contact rule in §11 | OUT: external |
| P17-28 | 17:87 | "157.08 rad/s" | CHECKED | — | 1500·2π/60 = 157.0796 | CHECKED |
| P17-43 | 17:117 | "smallest at v_x = 1 m/s: about 15 ms for Sedan_2026" | CHECKED | — | numeric eigenvalue check against §3 parameters | CHECKED |
| P17-52 | 17:12 | "two conforming runtimes produce the same outputs" | EXTERNAL | — | IEEE-754 determinism (§11) | OUT: external |
| P18-11 | 18:12 | "records … differ only in the detail text … native library entries" | EXTERNAL | — | depends on platform determinism (P11-30) | OUT: external |
| P19-02 | 19:17 | "equal its directory entry byte for byte" | EXTERNAL | Driveline.Modules | file system as an abstract list of directory entries | OUT: external |
| P19-10 | 19:25 | "lowercase hexadecimal SHA-256" | EXTERNAL | — | SHA-256; only the 64-hex format is DECIDE | OUT: external |
| P19-12 | 19:27 | "same entries in the same order" | PROSE | — | cross-reference to §18 | OUT: prose |
| PH-04 | H slice header | 'entry_size = 8 + sizeof(slice struct)'; 'count <= N' | CHECKED | — | sizeof/offsets via C compile (_Static_assert); count <= N is in P04-03 | CHECKED |
| PH-06 | H | '#pragma pack(push, 8)' layouts | CHECKED | — | C compile / ABI layout checks | CHECKED |
