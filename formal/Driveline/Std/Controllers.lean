import Mathlib
import Driveline.Std.Basic
import Driveline.Angles
import Driveline.Frames
import Driveline.Validity

/-!
# Standard controllers and arbiter (spec §17.1, §17.3, §17.4)

`follow_route` (17:30), `PincerHiveMind` (17:61-67), `PIDSpeedController`
(17:74-78), `JerkLimiter` (17:80), `StanleyLat` (17:82-84),
`BrakeOverrideArbiter` (17:91), and the output frames that state their groups
in full (17:70).
-/

namespace Driveline.Std

open Real

/-! ## `follow_route` -/

/-- A lane reference: a road id and a lane id. -/
structure LaneRef (R : Type) where
  road : R
  lane : ℤ

/-- 17:30: the first route node whose `road_id` equals `from.road_id`, or
`from`'s own lane. -/
def followTarget {R : Type} [DecidableEq R] (route : List (LaneRef R)) (r : R)
    (own : LaneRef R) : LaneRef R :=
  (route.find? (fun n => decide (n.road = r))).getD own

/-! ## `PincerHiveMind` -/

/-- 17:65 'o_j = pinch_gap · (j − (M−1)/2)'. -/
noncomputable def pincerOffset (gap : ℝ) (M j : ℕ) : ℝ := gap * (j - ((M : ℝ) - 1) / 2)

/-- 17:65 'Δx_j = −x, v_target = own.v_lon + v_x, v_ref = max(0, v_target +
0.5 s⁻¹ · (o_j − Δx_j))'. -/
noncomputable def pincerVref (vOwn relX relVx o : ℝ) : ℝ :=
  max 0 (vOwn + relVx + (1 / 2) * (o - (-relX)))

/-! ## `PIDSpeedController` -/

/-- 17:75: the integral, the previous error and output, and `rebase`. -/
structure Pid where
  I : ℝ
  ePrev : ℝ
  aPrev : ℝ
  rebase : Bool

/-- 17:75 'Cold init and warm start set a_prev to the latched `a_lon_cmd` and
set `rebase`'. I and e_prev are whatever they were. -/
def Pid.init (aLatched I e : ℝ) : Pid := ⟨I, e, aLatched, true⟩

/-- 17:76 `ACCEL_TARGET`. -/
def Pid.accelStep (s : Pid) (aRef : ℝ) : ℝ × Pid := (aRef, { s with aPrev := aRef, rebase := true })

/-- 17:77 `VELOCITY_TARGET`, with e = v_ref − own.v_lon. -/
noncomputable def Pid.velStep (kp ki kd dt : ℝ) (s : Pid) (e : ℝ) : ℝ × Pid :=
  let I0 := if s.rebase then (if ki = 0 then 0 else (s.aPrev - kp * e) / ki - e * dt) else s.I
  let ep := if s.rebase then e else s.ePrev
  let I1 := I0 + e * dt
  let a := kp * e + ki * I1 + kd * (e - ep) / dt
  (a, ⟨I1, e, a, false⟩)

/-! ## `JerkLimiter` -/

/-- 17:80 'a_k = a_{k−1} + clamp(a_in − a_{k−1}, ± max_jerk · dt)'. -/
noncomputable def jerkStep (maxJerk dt aPrev aIn : ℝ) : ℝ :=
  aPrev + clampS (aIn - aPrev) (maxJerk * dt)

/-! ## `StanleyLat` -/

/-- 17:82: the lateral offset e of the rear axle from path point p. -/
noncomputable def lateralOffset (X Y xp yp ψp : ℝ) : ℝ :=
  -Real.sin ψp * (X - xp) + Real.cos ψp * (Y - yp)

/-- 17:82: ψ_e = ψ_p − χ wrapped, with χ = ψ + atan2(own.v_lat, own.v_lon). -/
noncomputable def headingError (ψp ψ vlat vlon : ℝ) : ℝ :=
  Angles.wrap (ψp - (ψ + Angles.atan2 vlat vlon))

/-- 17:83: δ = clamp(arctan(Lκ_p) + ψ_e + arctan(−k e / (k_soft + |own.v_lon|)), ±δ_max). -/
noncomputable def stanley (L κ ψe k e kSoft vlon δmax : ℝ) : ℝ :=
  clampS (Real.arctan (L * κ) + ψe + Real.arctan (-k * e / (kSoft + |vlon|))) δmax

/-- 17:82: index `i` is the nearest point, with the smallest index winning ties. -/
def IsNearest {n : ℕ} (d : Fin n → ℝ) (i : Fin n) : Prop :=
  (∀ j, d i ≤ d j) ∧ ∀ j, j < i → d i < d j

/-! ## `BrakeOverrideArbiter` -/

/-- Whether group `gr` of `f` has mode `NONE`. -/
def groupNone (f : ActuatorControlFrame) : ActuatorGroup → Bool
  | .pedals => match f.pedal with | .none => true | _ => false
  | .wheel => match f.wheel with | .none => true | _ => false
  | .gear => match f.gear with | .none => true | _ => false

/-- 17:91: the frame group `gr` comes from: `secondary` if its mode there is
not `NONE`, else `primary`. -/
def arbiterSource (p s : ActuatorControlFrame) (gr : ActuatorGroup) : ActuatorControlFrame :=
  if groupNone s gr then p else s

/-- 17:91 'Each group, `PEDALS`, `WHEEL`, and `GEAR`, comes whole from
`secondary` if its mode there is not `NONE`, and from `primary` otherwise.' -/
def arbitrate (p s : ActuatorControlFrame) : ActuatorControlFrame where
  header := p.header
  pedal := (arbiterSource p s .pedals).pedal
  throttle := (arbiterSource p s .pedals).throttle
  brake := (arbiterSource p s .pedals).brake
  wheel := (arbiterSource p s .wheel).wheel
  steeringWheelNorm := (arbiterSource p s .wheel).steeringWheelNorm
  steeringTorqueNm := (arbiterSource p s .wheel).steeringTorqueNm
  gear := (arbiterSource p s .gear).gear
  manualGearIndex := (arbiterSource p s .gear).manualGearIndex

/-! ## Output frames (17:70) -/

/-- `Lon<KinematicControlFrame>`: `ACCEL` with `a_lon_cmd = a` and
`jerk_lon_cmd = +INFINITY` (17:70, 17:78, 17:80). -/
def accelFrame (h : Header) (a : ℝ) : KinematicControlFrame where
  header := h
  accel := .accel
  steer := .none
  aLonCmd := .fin a
  jerkLonCmd := .posInf
  steerAngleCmd := 0
  steerRateCmd := 0

/-- `Lat<KinematicControlFrame>`: `ANGLE` with `steer_angle_cmd = δ` and
`steer_rate_cmd = +INFINITY` (17:70, 17:84). -/
def angleFrame (h : Header) (δ : ℝ) : KinematicControlFrame where
  header := h
  accel := .none
  steer := .angle
  aLonCmd := 0
  jerkLonCmd := 0
  steerAngleCmd := .fin δ
  steerRateCmd := .posInf

/-- `KinematicControlFrame` with both groups, as `SimpleDrivetrain` outputs (17:89). -/
def driveFrame (h : Header) (a δ : ℝ) : KinematicControlFrame where
  header := h
  accel := .accel
  steer := .angle
  aLonCmd := .fin a
  jerkLonCmd := .posInf
  steerAngleCmd := .fin δ
  steerRateCmd := .posInf

/-! ## Theorems -/

/-- P17-01. 17:28 '`clamp` ... min(max(x, lo), hi) for a quantity type `T`'.
The result is at most `hi`, at least `lo` when `lo ≤ hi`, and clamping twice
changes nothing. -/
theorem clamp_bounds (x lo hi : ℝ) :
    clamp x lo hi ≤ hi ∧ (lo ≤ hi → lo ≤ clamp x lo hi) ∧
      clamp (clamp x lo hi) lo hi = clamp x lo hi := by
  refine ⟨min_le_right _ _, fun h => le_min (le_max_right _ _) h, ?_⟩
  unfold clamp
  simp only [min_def, max_def]
  split_ifs <;> linarith

/-- P17-04. 17:30 'The target lane is the first route node whose `road_id`
equals `from.road_id`, or `from`'s own lane if no node matches.' -/
theorem follow_route_target {R : Type} [DecidableEq R] (route : List (LaneRef R)) (r : R)
    (own : LaneRef R) :
    ((∀ n ∈ route, n.road ≠ r) ∧ followTarget route r own = own) ∨
      ∃ pre post, route = pre ++ followTarget route r own :: post ∧
        (followTarget route r own).road = r ∧ ∀ n ∈ pre, n.road ≠ r := by
  unfold followTarget
  cases hf : route.find? (fun n => decide (n.road = r)) with
  | none =>
    left
    refine ⟨fun n hn => ?_, rfl⟩
    have := List.find?_eq_none.1 hf n hn
    simpa using this
  | some b =>
    right
    obtain ⟨hb, pre, post, hroute, hpre⟩ := List.find?_eq_some_iff_append.1 hf
    refine ⟨pre, post, hroute, by simpa using hb, fun n hn => ?_⟩
    simpa using hpre n hn

/-- P17-20. 17:65 'v_ref = max(0, v_target + 0.5 s⁻¹ · (o_j − Δx_j))'. The
reference speed is never negative. With perfect speed tracking and no clamp,
the relative position x obeys ẋ = −0.5 (x + o_j), whose solution converges to
x = −o_j, so member j settles o_j behind the target. -/
theorem pincer_vref (vOwn relX relVx o x0 : ℝ) :
    0 ≤ pincerVref vOwn relX relVx o ∧
      (∀ t, HasDerivAt (fun t => -o + (x0 + o) * Real.exp (-t / 2))
        (-(1 / 2) * ((-o + (x0 + o) * Real.exp (-t / 2)) + o)) t) ∧
      Filter.Tendsto (fun t => -o + (x0 + o) * Real.exp (-t / 2)) Filter.atTop (nhds (-o)) := by
  refine ⟨le_max_left _ _, fun t => ?_, ?_⟩
  · have h1 : HasDerivAt (fun t : ℝ => -t / 2) (-1 / 2) t := by
      simpa using ((hasDerivAt_id t).neg.div_const 2)
    have h2 := ((h1.exp).const_mul (x0 + o)).const_add (-o)
    convert h2 using 1
    ring
  · have h1 : Filter.Tendsto (fun t : ℝ => -t / 2) Filter.atTop Filter.atBot := by
      have : Filter.Tendsto (fun t : ℝ => t / 2) Filter.atTop Filter.atTop :=
        Filter.tendsto_id.atTop_div_const (by norm_num)
      refine (Filter.tendsto_neg_atTop_atBot.comp this).congr' (Filter.Eventually.of_forall fun t => ?_)
      simp [neg_div]
    have h2 := (Real.tendsto_exp_atBot.comp h1).const_mul (x0 + o)
    have h3 := h2.const_add (-o)
    simpa using h3

/-- P17-21. 17:77 'So the first velocity step after initialization or after
`ACCEL_TARGET` continues from the previous output without a step when
k_i ≠ 0.' -/
theorem pid_rebase_continuous (kp ki kd dt e : ℝ) (s : Pid) (hr : s.rebase = true)
    (hki : ki ≠ 0) : (s.velStep kp ki kd dt e).1 = s.aPrev := by
  simp only [Pid.velStep, hr, hki, ↓reduceIte, sub_self, mul_zero, zero_div, add_zero]
  field_simp
  ring

/-- P17-22. 17:77 '$I = (a_{prev} − k_p e)/k_i − e\,dt$, or I = 0 if k_i = 0'.
With k_i = 0 the first step after a rebase outputs k_p e, so the output can
step. -/
theorem pid_rebase_ki_zero (kp kd dt e : ℝ) (s : Pid) (hr : s.rebase = true) :
    (s.velStep kp 0 kd dt e).1 = kp * e ∧
      ∃ s' : Pid, s'.rebase = true ∧ (s'.velStep 1 0 0 1 1).1 ≠ s'.aPrev := by
  refine ⟨?_, ⟨0, 0, 0, true⟩, rfl, ?_⟩
  · simp [Pid.velStep, hr]
  · norm_num [Pid.velStep]

/-- P17-23. 17:80 'Parameter `max_jerk` ... (above zero). Output
a_k = a_{k−1} + clamp(a_in − a_{k−1}, ± max_jerk · dt)', where dt is the
component's period k_div · Δt_base (17:14, 11:13). -/
theorem jerk_bound (maxJerk : ℝ) (k base : ℕ+) (aPrev aIn : ℝ) (hj : 0 < maxJerk) :
    |jerkStep maxJerk (compDt k base) aPrev aIn - aPrev| ≤ maxJerk * compDt k base := by
  unfold jerkStep
  rw [add_sub_cancel_left]
  exact abs_clampS_le _ _ (mul_nonneg hj.le (compDt_pos k base).le)

/-- P17-24. 17:83 'δ = clamp(..., ±δ_max)'. Spec gap: §3 states no sign for
`max_steer_angle`, so δ_max ≥ 0 is the ledger's hypothesis. -/
theorem stanley_bound (L κ ψe k e kSoft vlon δmax : ℝ) (h : 0 ≤ δmax) :
    |stanley L κ ψe k e kSoft vlon δmax| ≤ δmax :=
  abs_clampS_le _ _ h

/-- P17-25. 17:84 'On a path that the rear axle already follows, e = 0 and
ψ_e = 0, so the output is arctan(Lκ_p), which is δ_KS'. Spec gap: the clamp
keeps this only when |arctan(Lκ_p)| ≤ δ_max, which the spec does not state. -/
theorem stanley_on_path (L κ k kSoft vlon δmax : ℝ) (h : |Real.arctan (L * κ)| ≤ δmax) :
    stanley L κ 0 k 0 kSoft vlon δmax = Real.arctan (L * κ) := by
  unfold stanley
  simp only [add_zero, mul_zero, zero_div, Real.arctan_zero]
  exact clampS_of_abs_le h

/-- P17-26. 17:82 'Let p be the path point nearest to it, with the smallest
index winning ties', and 17:84 'A reference path with no points ... is
`DL_STATUS_ERR_INVALID_ARG`', so the path has a point. Exactly one point is
the nearest. -/
theorem nearest_unique {n : ℕ} (d : Fin n → ℝ) (hn : 0 < n) : ∃! i, IsNearest d i := by
  have hne : (Finset.univ : Finset (Fin n)).Nonempty := ⟨⟨0, hn⟩, Finset.mem_univ _⟩
  obtain ⟨i0, -, hi0⟩ := Finset.exists_min_image Finset.univ d hne
  let S := Finset.univ.filter (fun j => d j = d i0)
  have hS : S.Nonempty := ⟨i0, by simp [S]⟩
  refine ⟨S.min' hS, ⟨fun j => ?_, fun j hj => ?_⟩, fun i hi => ?_⟩
  · have := (Finset.mem_filter.1 (S.min'_mem hS)).2
    rw [this]; exact hi0 j (Finset.mem_univ _)
  · have hm := (Finset.mem_filter.1 (S.min'_mem hS)).2
    rcases (hi0 j (Finset.mem_univ _)).lt_or_eq with h | h
    · rw [hm]; exact h
    · exfalso
      have : S.min' hS ≤ j := S.min'_le j (by simp [S, h])
      exact absurd hj (not_lt.2 this)
  · have hm := (Finset.mem_filter.1 (S.min'_mem hS)).2
    have hle : d i ≤ d (S.min' hS) := hi.1 _
    have hge : d (S.min' hS) ≤ d i := by rw [hm]; exact hi0 i (Finset.mem_univ _)
    have hmem : i ∈ S := by simp [S]; rw [← hm]; linarith
    rcases (S.min'_le i hmem).lt_or_eq with h | h
    · exact absurd (hi.2 _ h) (not_lt.2 hge)
    · exact h.symm

/-- P17-32. 17:91 'Each group, `PEDALS`, `WHEEL`, and `GEAR`, comes whole from
`secondary` if its mode there is not `NONE`, and from `primary` otherwise.'
Each group's mode and every field of the group come from the same frame. -/
theorem arbiter_whole_groups (p s : ActuatorControlFrame) :
    ((arbitrate p s).pedal = (arbiterSource p s .pedals).pedal ∧
      ∀ fld : ActuatorField, ActuatorGroup.pedals ∈ fld.groups →
        (arbitrate p s).agreeOn fld (arbiterSource p s .pedals)) ∧
    ((arbitrate p s).wheel = (arbiterSource p s .wheel).wheel ∧
      ∀ fld : ActuatorField, ActuatorGroup.wheel ∈ fld.groups →
        (arbitrate p s).agreeOn fld (arbiterSource p s .wheel)) ∧
    ((arbitrate p s).gear = (arbiterSource p s .gear).gear ∧
      ∀ fld : ActuatorField, ActuatorGroup.gear ∈ fld.groups →
        (arbitrate p s).agreeOn fld (arbiterSource p s .gear)) := by
  refine ⟨⟨rfl, fun fld h => ?_⟩, ⟨rfl, fun fld h => ?_⟩, ⟨rfl, fun fld h => ?_⟩⟩ <;>
    cases fld <;> simp_all [ActuatorField.groups, ActuatorControlFrame.agreeOn, arbitrate]

/-- P17-51. 17:70 'Every output below states its groups in full, with each
no-bound field `+INFINITY`.' The `Lon` output of `PIDSpeedController` and
`JerkLimiter`, the `Lat` output of `StanleyLat`, and the full output of
`SimpleDrivetrain` pass the output check (05:98, 14-diagnostics item 4) for
every real command: §5.2 needs only finite commands and bounds above zero. -/
theorem std_outputs_valid (h : Header) :
    (∀ a : ℝ, (accelFrame h a).outputCheck .lon = .ok) ∧
      (∀ δ : ℝ, (angleFrame h δ).outputCheck .lat = .ok) ∧
      ∀ a δ : ℝ, (driveFrame h a δ).outputCheck .full = .ok := by
  refine ⟨fun a => ?_, fun δ => ?_, fun a δ => ?_⟩ <;>
    rw [KinematicControlFrame.outputCheck_ok] <;>
    refine ⟨?_, ?_, ?_⟩
  all_goals first
    | (right; intro g; cases g <;>
        simp [KinematicControlFrame.stated, KinematicControlFrame.modeNat, accelFrame,
          angleFrame, driveFrame, ModeEnum.toNat])
    | (refine ⟨?_, ?_, ?_, ?_⟩ <;>
        simp [KinematicControlFrame.uses, AccelMode.uses, SteerMode.uses, accelFrame,
          angleFrame, driveFrame, F64.Finite])
    | (refine ⟨?_, ?_, ?_⟩
       · right; intro g; cases g <;>
          simp [KinematicControlFrame.stated, KinematicControlFrame.modeNat, accelFrame,
            angleFrame, driveFrame, ModeEnum.toNat]
       all_goals intro hm; simp_all [accelFrame, angleFrame, driveFrame, F64.zero_lt_posInf])

end Driveline.Std
