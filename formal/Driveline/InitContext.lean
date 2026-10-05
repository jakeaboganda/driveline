import Driveline.Frames
import Driveline.Validity
import Driveline.Arbiter
import Driveline.Merge
import Driveline.Angles
import Driveline.VehicleSpec
import Driveline.Schedule

/-!
# Init contexts

Cold init Pass 1 (docs/spec/06-lifecycle.md:72-79) and the warm-start parts of
06:88-95: the spawn curvature and heading, the wheel and powertrain fields, the
latched frames that Pass 1 step 5 builds, their conversion at `t > 0`, the output
before the first step, and the matching of contexts to actor slots.

The spawn geometry uses an algebraic Frenet model: `offset_curvature` takes the
first and second derivatives of the offset curve as given vectors.
-/

noncomputable section

namespace Driveline.InitContext

open VehicleSpec

/-- The map cache of a committed state (06:78): `road_id`, `lane_id`, `s`, `d`. -/
structure MapCache where
  road : ℕ
  lane : ℤ
  s : ℝ
  d : ℝ

/-- The fields of `chassis_state` that Pass 1 and a tier change write (06:78, 06:84-85). -/
structure Chassis where
  actorId : ℕ
  t : ℕ
  x : ℝ
  y : ℝ
  z : ℝ
  psi : ℝ
  vLon : ℝ
  vLat : ℝ
  psiDot : ℝ
  aLon : ℝ
  aLat : ℝ
  fwa : ℝ
  beta : ℝ
  odo : ℝ
  cache : MapCache

/-- 06:88 'the committed v_dot_lon = a_lon + v_lat psi_dot'. -/
def vdot (c : Chassis) : ℝ := c.aLon + c.vLat * c.psiDot

/-- The physics kind that Pass 1 distinguishes: `KS` (`required_tier` 0) or a single-track
steady state (`required_tier` 1 or 2). -/
inductive PhysTier | ks | st
  deriving DecidableEq

/-- 06:72 'kappa_0 = sigma · kappa_lane / (1 − kappa_lane · d_0)'. -/
def kappa0 (σ : ℤ) (κ d : ℝ) : ℝ := σ * κ / (1 - κ * d)

/-- The signed curvature of a plane curve with velocity `v` and acceleration `w`. -/
def signedCurv (v w : ℝ × ℝ) : ℝ := (v.1 * w.2 - v.2 * w.1) / (Real.sqrt (v.1 ^ 2 + v.2 ^ 2)) ^ 3

/-- 06:73 the spawn heading. -/
def psi0 (k : PhysTier) (ψt vLat v0 : ℝ) : ℝ :=
  if k = .ks ∨ v0 = 0 then ψt else Angles.wrap (ψt - Angles.atan2 vLat v0)

/-- 06:77 `slip_angle_alpha` at cold init, with `α` the §8 axle slip angle. -/
def slipAlpha (k : PhysTier) (v α : ℝ) : ℝ := if k = .ks ∨ v < 1 then 0 else α

/-- 06:94 `slip_angle_alpha` at a warm start, with `α` from the §17.5 formulas. -/
def warmSlip (tierAfter : Fin 3) (v α : ℝ) : ℝ := if v < 1 ∨ tierAfter = 0 then 0 else α

/-- 06:77 `active_gear_index`; in `DRIVE` the argument is the gear that the rule picks. -/
def activeGearIndex : GearMode → ℤ → ℤ
  | .reverse, _ => -1
  | .park, _ => 0
  | .neutral, _ => 0
  | .drive, g => g
  | .none, _ => 0

/-- 06:77 'motor_or_engine_speed_rads is (|v_0| / R_eff) i i_fd'. -/
def motorSpeed (v R i ifd : ℝ) : ℝ := |v| / R * i * ifd

/-- 06:78 'clamp(δ_ss/δ_max, ±1)'. -/
def wheelNorm (δ δmax : ℝ) : ℝ := max (-1) (min 1 (δ / δmax))

/-- 06:78 `latched_kinematic_ctrl`: `ACCEL` with `a_lon_cmd` and `jerk_lon_cmd = +INFINITY`,
`ANGLE` with `steer_angle_cmd = δ` and `steer_rate_cmd = +INFINITY`. -/
def baseKcf (h : Header) (aCmd δ : ℝ) : KinematicControlFrame where
  header := h
  accel := .accel
  steer := .angle
  aLonCmd := .fin aCmd
  jerkLonCmd := .posInf
  steerAngleCmd := .fin δ
  steerRateCmd := .posInf

/-- 06:78 `latched_actuator_ctrl`: `PEDALS` with 0 and 0, `ANGLE` with the clamped
`steering_wheel_norm`, and gear mode `g` with `manual_gear_index = 0`. -/
def baseAcf (h : Header) (δ δmax : ℝ) (g : GearMode) : ActuatorControlFrame where
  header := h
  pedal := .pedals
  wheel := .angle
  gear := g
  manualGearIndex := 0
  throttle := 0
  brake := 0
  steeringWheelNorm := .fin (wheelNorm δ δmax)
  steeringTorqueNm := 0

/-- 06:88 the conversion at `t > 0`: each group that is neither baseline nor `NONE` is
replaced by that group, mode and fields, of the committed baseline frame `base`. -/
def IntentFrame.convert (base f : IntentFrame) : IntentFrame :=
  let f1 := if f.lon = .none ∨ f.lon.isBaseline then f else f.withLonFrom base
  let f2 := if f1.lat = .none ∨ f1.lat.isBaseline then f1 else f1.withLatFrom base
  if f2.signal = .none ∨ f2.signal.isBaseline then f2 else { f2 with signal := base.signal }

/-- 06:88 the conversion of a `KinematicControlFrame`. -/
def KinematicControlFrame.convert (base f : KinematicControlFrame) : KinematicControlFrame :=
  let f1 := if f.accel = .none ∨ f.accel.isBaseline then f else
    { f with accel := base.accel, aLonCmd := base.aLonCmd, jerkLonCmd := base.jerkLonCmd }
  if f1.steer = .none ∨ f1.steer.isBaseline then f1 else
    { f1 with steer := base.steer, steerAngleCmd := base.steerAngleCmd,
              steerRateCmd := base.steerRateCmd }

/-- 06:88 the conversion of an `ActuatorControlFrame`. -/
def ActuatorControlFrame.convert (base f : ActuatorControlFrame) : ActuatorControlFrame :=
  let f1 := if f.pedal = .none ∨ f.pedal.isBaseline then f else
    { f with pedal := base.pedal, throttle := base.throttle, brake := base.brake }
  let f2 := if f1.wheel = .none ∨ f1.wheel.isBaseline then f1 else
    { f1 with wheel := base.wheel, steeringWheelNorm := base.steeringWheelNorm,
              steeringTorqueNm := base.steeringTorqueNm }
  if f2.gear = .none ∨ f2.gear.isBaseline then f2 else
    { f2 with gear := base.gear, manualGearIndex := base.manualGearIndex }

/-- 06:88 the latched frame of a type: the last frame that left the component, else the
last frame that reached its input. -/
def latched {F : Type} (lastOut lastIn : Option F) : Option F := lastOut <|> lastIn

/-- 06:90-92 the output before the first step of a latched `IntentFrame` `L`, by the
output's declared type. `h` carries the served actor and the next tick's time. -/
def preStep (k : FrameType) (L : IntentFrame) (h : Header) : IntentFrame :=
  match k with
  | .whole _ => L
  | .lon _ => L.toLon
  | .lat _ => L.toLat
  | .override _ => IntentFrame.blank h

/-- A `dl_init_context_t`, by its `chassis_state.actor_id`. -/
structure Ctx where
  actorId : ℕ
  tierChanged : Bool

/-- 06:95 the contexts an instance gets: one per selected served actor, in `actor_ids`
order. Cold init and a splice select every actor; a re-trim selects `tierChanged`. -/
def ctxs (ids : List ℕ) (sel : ℕ → Bool) (mk : ℕ → Ctx) : List Ctx := (ids.filter sel).map mk

/-- 06:95 'matches each context to its actor slot by chassis_state.actor_id'. -/
def matchSlot (cs : List Ctx) (a : ℕ) : Option Ctx := cs.find? (·.actorId = a)

/-- 06:72 'Steps 2 to 5 apply only to actors that spawn creates'. -/
def hasInitContext (c : Creator) : Bool := c == .spawn

/-- P06-01. 06:72 'kappa_0 = sigma · kappa_lane / (1 − kappa_lane · d_0)' ... 'The factor
sigma holds because a curve that turns left toward increasing s turns right toward
decreasing s'. With unit tangent `T` and left normal `N`, the offset curve `c + d N` has
velocity `(1 − κd) T` and acceleration `a T + (1 − κd) κ N` by the Frenet equations; its
signed curvature is `κ / (1 − κd)`, and reversed it is the negative. `h` is the 06:72 guard. -/
theorem offset_curvature (κ d a : ℝ) (T : ℝ × ℝ) (hT : T.1 ^ 2 + T.2 ^ 2 = 1) (h : κ * d < 1) :
    let N : ℝ × ℝ := (-T.2, T.1)
    let o1 := (1 - κ * d) • T
    let o2 := a • T + ((1 - κ * d) * κ) • N
    signedCurv o1 o2 = κ / (1 - κ * d) ∧ signedCurv (-o1) o2 = -(κ / (1 - κ * d)) ∧
      kappa0 1 κ d = κ / (1 - κ * d) ∧ kappa0 (-1) κ d = -(κ / (1 - κ * d)) := by
  intro N o1 o2
  have hc : 0 < 1 - κ * d := by linarith
  have hs : Real.sqrt (((1 - κ * d) * T.1) ^ 2 + ((1 - κ * d) * T.2) ^ 2) = 1 - κ * d := by
    rw [show ((1 - κ * d) * T.1) ^ 2 + ((1 - κ * d) * T.2) ^ 2 = (1 - κ * d) ^ 2 by
      linear_combination (1 - κ * d) ^ 2 * hT]
    exact Real.sqrt_sq hc.le
  have hs' : Real.sqrt ((-((1 - κ * d) * T.1)) ^ 2 + (-((1 - κ * d) * T.2)) ^ 2) = 1 - κ * d := by
    rw [neg_sq, neg_sq]; exact hs
  simp only [signedCurv, kappa0, o1, o2, N, Prod.smul_fst, Prod.smul_snd, Prod.fst_add,
    Prod.snd_add, Prod.fst_neg, Prod.snd_neg, smul_eq_mul, hs, hs']
  have hc' : (1 - κ * d) ≠ 0 := hc.ne'
  refine ⟨?_, ?_, by push_cast; ring, by push_cast; ring⟩
  · field_simp
    linear_combination (1 - κ * d) ^ 2 * κ * (1 - κ * d) * hT
  · field_simp
    linear_combination -((1 - κ * d) ^ 2 * κ * (1 - κ * d)) * hT

/-- P06-02. 06:72 'A spawn or placement with kappa_lane · d_0 ≥ 1 lies at or beyond the
center of curvature and is DL_STATUS_ERR_NUMERIC'. Past the guard the denominator of
kappa_0 is positive. -/
theorem guard_denom_pos (κ d : ℝ) (h : ¬ (κ * d ≥ 1)) : 0 < 1 - κ * d := by
  linarith [not_le.mp h]

/-- P06-04. 06:73 'The spawn heading is psi_0 = psi_travel − atan2(v_lat,ra, v_0), wrapped
to (−π, π], so the rear-axle velocity is tangent to the lane and the actor follows it'. For
v_0 > 0 the rear-axle velocity in world coordinates is a positive multiple of the travel
direction. The spawn speed is ≥ 0 (17:21), and at v_0 = 0 the 06:73 clause 'at v_0 = 0,
psi_0 = psi_travel' applies. -/
theorem spawn_heading_tangent (ψt vLat v0 : ℝ) (hv : 0 < v0) :
    let ψ0 := psi0 .st ψt vLat v0
    ∃ k > 0, (v0 * Real.cos ψ0 - vLat * Real.sin ψ0, v0 * Real.sin ψ0 + vLat * Real.cos ψ0) =
      k • (Real.cos ψt, Real.sin ψt) := by
  intro ψ0
  set θ := Angles.atan2 vLat v0
  set r := Real.sqrt (v0 ^ 2 + vLat ^ 2)
  have hr : 0 < r := Real.sqrt_pos.2 (by positivity)
  obtain ⟨hc, hs⟩ := Angles.atan2_polar vLat v0
  obtain ⟨n, hn⟩ := Angles.wrap_eq_add (ψt - θ)
  have hψ : ψ0 = ψt - θ + n * (2 * Real.pi) := by
    simp only [ψ0, psi0, hv.ne', or_false, reduceCtorEq, if_false]; exact hn
  refine ⟨r, hr, ?_⟩
  rw [hψ, Real.cos_add_int_mul_two_pi, Real.sin_add_int_mul_two_pi, ← hc, ← hs,
    Real.cos_sub, Real.sin_sub]
  ext
  · simp only [Prod.smul_fst, smul_eq_mul]
    linear_combination r * Real.cos ψt * Real.sin_sq_add_cos_sq θ
  · simp only [Prod.smul_snd, smul_eq_mul]
    linear_combination r * Real.sin ψt * Real.sin_sq_add_cos_sq θ

/-- P06-05. 06:73 'For KS, or at v_0 = 0, psi_0 = psi_travel'. The clause agrees with the
general formula for a KS actor (v_lat,ra = 0), because a spawn speed is ≥ 0 (17:21 'with
speed v ≥ 0 ... A negative v ... is a compile-time error'). -/
theorem ks_heading_consistent (ψt v0 : ℝ) (hv : 0 ≤ v0) :
    Angles.wrap (ψt - Angles.atan2 0 v0) = Angles.wrap ψt ∧ psi0 .ks ψt 0 v0 = ψt := by
  refine ⟨by rw [Angles.atan2_zero_left hv, sub_zero], ?_⟩
  simp [psi0]

/-- P06-10. 06:77 'slip_angle_alpha is the §8 axle slip angle (alpha_f or alpha_r, 0 for KS
or when v_0 < 1 m/s, every reverse speed included)'. -/
theorem slip_zero (k : PhysTier) (v α : ℝ) :
    (k = .ks ∨ v < 1 → slipAlpha k v α = 0) ∧ (v < 0 → slipAlpha k v α = 0) ∧
      (k = .st → 1 ≤ v → slipAlpha k v α = α) := by
  refine ⟨fun h => if_pos h, fun h => if_pos (Or.inr (by linarith)), fun hk hv => ?_⟩
  subst hk
  exact if_neg (by simp [not_lt.mpr hv])

/-- P06-11. 06:77 'active_gear_index is −1 in REVERSE, 0 in PARK and NEUTRAL, and in DRIVE
the gear frame's manual_gear_index ... and otherwise the gear of the Gear ratio rule' and
'motor_or_engine_speed_rads is (|v_0| / R_eff) i i_fd'. The motor speed depends only on
|v_0|, so it is the same forward and in reverse, and it is ≥ 0 when R_eff, i and i_fd are
positive. An accepted vehicle_spec need not make them positive: see `motor_speed_neg`. -/
theorem gear_index (g : ℤ) (v R i ifd : ℝ) :
    activeGearIndex .reverse g = -1 ∧ activeGearIndex .park g = 0 ∧
      activeGearIndex .neutral g = 0 ∧ activeGearIndex .drive g = g ∧
      motorSpeed (-v) R i ifd = motorSpeed v R i ifd ∧
      (0 < R → 0 < i → 0 < ifd → 0 ≤ motorSpeed v R i ifd) := by
  refine ⟨rfl, rfl, rfl, rfl, by simp [motorSpeed], fun hR hi hf => ?_⟩
  unfold motorSpeed; positivity

/-- An accepted vehicle spec with `R_eff = 1`, `i_R = 3` and `i_fd = -1`. -/
def motorWitness : VSpec :=
  { tier0 := { bbox_length := 5, wheelbase := 3, overhang_front := 1, overhang_rear := 1 }
    tier1 := some { mass := 1500, cg_dist_front := 3 / 2, cg_dist_rear := 3 / 2 }
    tier2 := some { sprung_mass := 1300, unsprung_mass_f := 100, unsprung_mass_r := 100,
                    tire_effective_radius := 1, reverse_gear_ratio := 3,
                    final_drive_ratio := -1, gear_ratios := [3] } }

/-- Finding on P06-11: nothing in §3 or §16 makes `final_drive_ratio` positive, so an
accepted spec can give a negative `motor_or_engine_speed_rads` in `REVERSE`. -/
theorem motor_speed_neg : ∃ s : VSpec, s.WF ∧ ∃ t2 ∈ s.tier2,
    motorSpeed 1 (encodeTier2 t2).tire_effective_radius (encodeTier2 t2).reverse_gear_ratio
      (encodeTier2 t2).final_drive_ratio < 0 := by
  refine ⟨motorWitness, ⟨?_, ?_, ?_, ?_⟩, _, rfl, ?_⟩
  · exact approxEq_of_eq _ _ (by simp [motorWitness]; norm_num)
  · rintro t1 ⟨⟩; exact approxEq_of_eq _ _ (by simp [motorWitness])
  · rintro t2 ⟨⟩
    exact ⟨⟨_, rfl, approxEq_of_eq _ _ (by norm_num)⟩, by norm_num, by simp, by simp⟩
  · rintro d h; simp [motorWitness] at h
  · simp [motorSpeed, encodeTier2]

/-- P06-14. 06:78 'Every latched frame states every group in its baseline mode (§5),
carries the actor's actor_id and timestamp_ns = 0, and has no NONE group'. The latched
intent is the committed-baseline rule of 06:72 at time 0, the kinematic frame has
`a_lon_cmd = 0` and the actuator frame `DRIVE`. -/
theorem pass1_frames_baseline {map : RoadMap} (o : OwnView map) (a : UInt64) (δ δmax : ℝ) :
    let h : Header := ⟨a, 0⟩
    let I := IntentFrame.committedBaseline o 0
    let K := baseKcf h 0 δ
    let A := baseAcf h δ δmax .drive
    I.lon.isBaseline ∧ I.lat.isBaseline ∧ I.signal.isBaseline ∧ K.accel.isBaseline ∧
      K.steer.isBaseline ∧ A.pedal.isBaseline ∧ A.wheel.isBaseline ∧ A.gear.isBaseline ∧
      I.header = ⟨o.actorId, 0⟩ ∧ K.header = h ∧ A.header = h := by
  intro h I K A
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- P06-15. 06:78 'ANGLE with steering_wheel_norm = clamp(delta_ss / delta_max, ±1)'. Under
08:19 feasibility ('A steady state is infeasible if |delta_ss| > delta_max'; an infeasible
spawn state fails cold init) the clamp is inactive, so `steering_wheel_norm · delta_max`
gives back delta_ss and the Tick 0 trim check passes. -/
theorem wheel_norm_trim (δ δmax : ℝ) (hf : feasible δ δmax) : wheelNorm δ δmax * δmax = δ := by
  unfold feasible at hf
  rcases (abs_nonneg δ).trans hf |>.lt_or_eq with hpos | h0
  · have h1 : δ / δmax ≤ 1 := (div_le_one hpos).2 (le_of_abs_le hf)
    have h2 : -1 ≤ δ / δmax := by
      rw [le_div_iff₀ hpos]; linarith [neg_abs_le δ]
    rw [wheelNorm, min_eq_right h1, max_eq_right h2, div_mul_cancel₀ _ hpos.ne']
  · subst h0
    have : δ = 0 := abs_nonpos_iff.mp hf
    simp [wheelNorm, this]

/-- P06-16. 06:79 'it runs sensor projection at t = 0 once over the complete spawn World.
This projection is Tick 0's Phase 1. Tick 0 does not run Phase 1 again, so no buffer holds
two samples at t = 0'. A buffer's sample times are the Pass 1 sample at 0 followed by the
Phase 1 runs of ticks 0 to n; they increase strictly and hold 0 once. -/
theorem t0_single_sample (dt : ℕ+) (n : ℕ) (fires : Schedule.Tick → Bool) :
    let ts := 0 :: ((List.range (n + 1)).filter
      (fun k => decide (Schedule.Phase.sensors ∈ Schedule.phases k) && fires k)).map
        (Schedule.tickTime dt)
    ts.Pairwise (· < ·) ∧ ts.count 0 = 1 := by
  intro ts
  have hpos : ∀ t ∈ ((List.range (n + 1)).filter
      (fun k => decide (Schedule.Phase.sensors ∈ Schedule.phases k) && fires k)).map
        (Schedule.tickTime dt), 0 < t := by
    intro t ht
    simp only [List.mem_map, List.mem_filter, Bool.and_eq_true, decide_eq_true_eq,
      Schedule.sensors_iff] at ht
    obtain ⟨k, ⟨-, hk, -⟩, rfl⟩ := ht
    simp only [Schedule.tickTime]
    exact Nat.mul_pos (Nat.pos_of_ne_zero hk) dt.pos
  have hpw : ts.Pairwise (· < ·) :=
    List.pairwise_cons.2 ⟨hpos, ((List.pairwise_lt_range).filter _).map _
      (fun _ _ h => Schedule.tickTime_strictMono dt h)⟩
  exact ⟨hpw, List.count_eq_one_of_mem (hpw.imp (fun h => h.ne)) (List.mem_cons_self ..)⟩

/-- P06-29. 06:88 'with a_lon_cmd equal to the committed v_dot_lon = a_lon + v_lat psi_dot'.
On the Pass 1 state, where 06:78 sets 'a_lon = −v_lat,ra psi_dot_0', this is the Pass 1
'a_lon_cmd = 0'. -/
theorem pass1_alon_cmd (c : Chassis) (h : c.aLon = -(c.vLat * c.psiDot)) : vdot c = 0 := by
  rw [vdot, h]; ring

/-- P06-30. 06:88 'v_0 = max(v_lon, 0)': the committed baseline's `v_ref` is ≥ 0. -/
theorem baseline_vref_nonneg {map : RoadMap} (o : OwnView map) (t : UInt64) :
    (0 : F64) ≤ (IntentFrame.committedBaseline o t).vRef :=
  (F64.max0_nonneg o.vLon).2

/-- P06-31. 06:88 'the runtime first replaces each group of a latched frame of any type that
is not in its baseline mode, and is not NONE, with that group of the committed baseline
frame' ... 'A converted frame keeps its timestamp_ns'. After conversion every group of each
frame type is baseline or NONE, and the header is kept. -/
theorem convert_modes {map : RoadMap} (o : OwnView map) (t : UInt64) (f : Driveline.IntentFrame)
    (hk : Header) (a δ : ℝ) (k : KinematicControlFrame) (ha : Header) (δmax : ℝ) (g : GearMode)
    (b : ActuatorControlFrame) :
    let F := IntentFrame.convert (IntentFrame.committedBaseline o t) f
    let K := KinematicControlFrame.convert (baseKcf hk a δ) k
    let B := ActuatorControlFrame.convert (baseAcf ha δ δmax g) b
    (F.lon = .none ∨ F.lon.isBaseline) ∧ (F.lat = .none ∨ F.lat.isBaseline) ∧
      (F.signal = .none ∨ F.signal.isBaseline) ∧ F.header = f.header ∧
      (K.accel = .none ∨ K.accel.isBaseline) ∧ (K.steer = .none ∨ K.steer.isBaseline) ∧
      K.header = k.header ∧
      (B.pedal = .none ∨ B.pedal.isBaseline) ∧ (B.wheel = .none ∨ B.wheel.isBaseline) ∧
      (B.gear = .none ∨ B.gear.isBaseline) ∧ B.header = b.header := by
  intro F K B
  simp only [F, K, B, IntentFrame.convert, KinematicControlFrame.convert,
    ActuatorControlFrame.convert]
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;>
    split_ifs <;> simp_all [IntentFrame.withLonFrom, IntentFrame.withLatFrom,
      IntentFrame.committedBaseline, baseKcf, baseAcf, GearMode.isBaseline]

/-- P06-32. 06:88 'For a re-trim, the latched frame of each type is the last frame of that
type that left the component, or, if none left it, the last frame of that type that reached
its input' ... 'In these rules a Lon<T> or Lat<T> output counts as the merged frame at its
+' ... 'A component whose input and output types are equal, such as JerkLimiter, therefore
gets its own last output'. A component's own last output `f` is its latched frame; for a
`Lon<T>` output `a` merged with `b` at its `+`, the latched frame agrees with `a` on the
`LON` group and its fields. -/
theorem latched_own_output {F : Type} (o i : Option F) (f : F) (ho : o = some f)
    (h : Header) (a b : KinematicControlFrame) :
    latched o i = some f ∧ (KinematicControlFrame.merge h a b).accel = a.accel ∧
      ∀ fld, a.accel.uses fld = true →
        KinematicControlFrame.agreeOn fld (KinematicControlFrame.merge h a b) a := by
  subst ho
  refine ⟨rfl, rfl, fun fld hu => ?_⟩
  cases fld <;> cases ha : a.accel <;> simp_all [AccelMode.uses, KinematicControlFrame.agreeOn,
    KinematicControlFrame.merge]

/-- P06-33. 06:90-92 'A full T output delivers the latched frame unchanged' / 'A Lon<T> or
Lat<T> output ... delivers it with the unstated groups NONE and their fields zero' / 'An
Override<T> output delivers a frame with every group NONE and every other field zero,
carrying the served actor's actor_id and stamped with the next tick's time'. -/
theorem preStep_cases (L : Driveline.IntentFrame) (h : Header) (r : Base) :
    preStep (.whole r) L h = L ∧ preStep (.lon r) L h = L.toLon ∧
      preStep (.lat r) L h = L.toLat ∧
      preStep (.override r) L h = Driveline.IntentFrame.blank h ∧
      (preStep (.override r) L h).lon = .none ∧ (preStep (.override r) L h).lat = .none ∧
      (preStep (.override r) L h).signal = .none ∧ (preStep (.override r) L h).header = h :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- P06-35. 06:94 'Each axle's slip_angle_alpha ... is 0 when v_lon < 1 m/s, every reverse
speed included, as in §8, or when the required_tier of the actor's physics component after
the window's last splice statement (§10.4) is 0'. -/
theorem warm_slip (r : Fin 3) (v α : ℝ) :
    (v < 1 ∨ r = 0 → warmSlip r v α = 0) ∧ (v < 0 → warmSlip r v α = 0) ∧
      (1 ≤ v → r ≠ 0 → warmSlip r v α = α) := by
  refine ⟨fun h => if_pos h, fun h => if_pos (Or.inl (by linarith)), fun hv hr => ?_⟩
  exact if_neg (by simp [not_lt.mpr hv, hr])

/-- P06-36. 06:95 'the component matches each context to its actor slot by
chassis_state.actor_id. An instance gets contexts only for the actors that it serves, in its
actor_ids order. Cold init and a splice pass one for each of them. A re-trim passes contexts
only for the served actors whose physics tier changed'. The selected contexts are a sublist
of the full list in `actor_ids` order, and each selected actor's slot finds its own context
and no other actor's slot finds one. -/
theorem ctx_match (ids : List ℕ) (sel : ℕ → Bool) (mk : ℕ → Ctx)
    (hmk : ∀ a, (mk a).actorId = a) (a : ℕ) :
    (ctxs ids sel mk).Sublist (ctxs ids (fun _ => true) mk) ∧
      (a ∈ ids → sel a = true → matchSlot (ctxs ids sel mk) a = some (mk a)) ∧
      (sel a = false → matchSlot (ctxs ids sel mk) a = none) := by
  have hm : matchSlot (ctxs ids sel mk) a =
      ((ids.filter sel).find? (fun x => decide (x = a))).map mk := by
    simp [matchSlot, ctxs, List.find?_map, Function.comp_def, hmk]
  have key : ∀ l : List ℕ, a ∈ l → l.find? (fun x => decide (x = a)) = some a := by
    intro l
    induction l with
    | nil => simp
    | cons x l ih =>
      intro hl
      by_cases hx : x = a
      · simp [hx]
      · simp only [List.find?_cons, hx, decide_false]
        exact ih ((List.mem_cons.1 hl).resolve_left (Ne.symm hx))
  refine ⟨?_, fun hi hs => ?_, fun hs => ?_⟩
  · simp only [ctxs, List.filter_true]
    exact (List.filter_sublist).map _
  · rw [hm, key _ (List.mem_filter.2 ⟨hi, hs⟩)]; rfl
  · rw [hm, List.find?_eq_none.2]; · rfl
    intro x hx
    simp only [List.mem_filter] at hx
    simp only [decide_eq_true_eq]
    rintro rfl; simp_all

/-- P05-41. 05:32 'A frame that the runtime builds by the rules of Pass 1 step 5 uses only
baseline modes'. This covers the committed baseline frames of 06:88, whose gear mode may be
REVERSE, which is baseline (05:32 'every mode of gear_mode'). -/
theorem built_frames_baseline {map : RoadMap} (o : OwnView map) (t : UInt64) (h : Header)
    (a δ δmax : ℝ) (g : GearMode) (hg : g ≠ .none) :
    (IntentFrame.committedBaseline o t).lon.isBaseline ∧
      (IntentFrame.committedBaseline o t).lat.isBaseline ∧
      (IntentFrame.committedBaseline o t).signal.isBaseline ∧
      (baseKcf h a δ).accel.isBaseline ∧ (baseKcf h a δ).steer.isBaseline ∧
      (baseAcf h δ δmax g).pedal.isBaseline ∧ (baseAcf h δ δmax g).wheel.isBaseline ∧
      (baseAcf h δ δmax g).gear.isBaseline :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, (GearMode.isBaseline_iff g).2 hg⟩

/-- P00-40. 00:34 'except a static actor, which place creates and which has no sensors,
priors, or components'; 06:72 'Steps 2 to 5 apply only to actors that spawn creates. A
static actor (§17.1 place) gets no init context'. -/
theorem static_iff_place (c : Creator) : hasInitContext c = false ↔ c = .place := by
  cases c <;> decide

end Driveline.InitContext
