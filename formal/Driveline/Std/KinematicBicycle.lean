import Driveline.Std.Basic
import Driveline.VehicleSpec

/-!
# Actuator dynamics and `KinematicBicycle` (spec §17.5, 17:96-112)

The actuator update shared by `KinematicBicycle` and `DynamicSingleTrack` (17:106-108)
and the six steps of a `KinematicBicycle` tick (17:96-101, 17:110-112).
-/

namespace Driveline.Std

/-- 17:107 steering commands: `ANGLE` with δ_cmd and `steer_rate_cmd` (`none` is
`+INFINITY`), and `RATE` with δ̇_cmd. -/
inductive SteerCmd
  | angle (c : ℝ) (rate : Option ℝ)
  | rate (w : ℝ)

/-- 17:108 longitudinal commands: `ACCEL` with a_cmd and `jerk_lon_cmd` (`none` is
`+INFINITY`), and `JERK` with j_cmd. -/
inductive LonCmd
  | accel (c : ℝ) (jerk : Option ℝ)
  | jerk (j : ℝ)

/-- 17:107 'Under `ANGLE`, δ ← δ + clamp(δ_cmd − δ, ±ρΔt), where
ρ = min(δ̇_max, `steer_rate_cmd`). Under `RATE`, δ ← δ + clamp(δ̇_cmd, ±δ̇_max)Δt'. -/
def steerStep (δdotMax Δt δ : ℝ) : SteerCmd → ℝ
  | .angle c r =>
    δ + clampS (c - δ) ((match r with | some r => min δdotMax r | none => δdotMax) * Δt)
  | .rate w => δ + clampS w δdotMax * Δt

/-- 17:108 'Under `ACCEL`, a moves toward a_cmd by at most `jerk_lon_cmd` · Δt ...
Under `JERK`, a ← a + j_cmd Δt'. -/
def lonStep (Δt a : ℝ) : LonCmd → ℝ
  | .accel c b => toward a c b Δt
  | .jerk j => a + j * Δt

/-- The `KinematicBicycle` state: pose, rear-axle speed v, δ, and a (17:110). -/
structure KS where
  X : ℝ
  Y : ℝ
  ψ : ℝ
  v : ℝ
  δ : ℝ
  a : ℝ

/-- The reported fields of `KinematicState` that the step sets (17:101-102, 17:112). -/
structure Out where
  Z : ℝ
  roll : ℝ
  pitch : ℝ
  vlon : ℝ
  vlat : ℝ
  aLon : ℝ
  aLat : ℝ
  yawRate : ℝ
  fwa : ℝ

/-- Steps 2-3 (17:98-99): one explicit Euler step of 17:111
'Ẋ = v cos ψ, Ẏ = v sin ψ, ψ̇ = (v/L) tan δ, v̇ = a' at the state of tick t with the
updated δ and a. -/
noncomputable def ksEuler (L Δt : ℝ) (s : KS) (δ a : ℝ) : KS :=
  { X := s.X + s.v * Real.cos s.ψ * Δt, Y := s.Y + s.v * Real.sin s.ψ * Δt,
    ψ := s.ψ + s.v / L * Real.tan δ * Δt, v := s.v + a * Δt, δ := δ, a := a }

/-- Step 4 (17:100): 'Clamp v_lon ← max(0, v_lon) ... If the new v_lon is 0, also set
a ← max(0, a)'. -/
noncomputable def postClamp (s : KS) : KS :=
  let v := max 0 s.v
  { s with v := v, a := if v = 0 then max 0 s.a else s.a }

/-- One `KinematicBicycle` tick, steps 1-6 (17:97-102). Step 5 sets Z to the map
elevation and roll and pitch to 0; step 6 reports `front_wheel_angle` = δ and the
derivatives at the new state (17:112 'v_lat = 0, `a_lon` = a, and `a_lat` = vψ̇'). -/
noncomputable def ksStep (L δdotMax Δt : ℝ) (elev : ℝ → ℝ → ℝ) (s : KS) (sc : SteerCmd)
    (lc : LonCmd) : KS × Out :=
  let δ := steerStep δdotMax Δt s.δ sc
  let a := lonStep Δt s.a lc
  let s' := postClamp (ksEuler L Δt s δ a)
  let yr := s'.v / L * Real.tan s'.δ
  (s', ⟨elev s'.X s'.Y, 0, 0, s'.v, 0, s'.a, s'.v * yr, yr, s'.δ⟩)

/-- P17-33. 17:100 'Clamp v_lon ← max(0, v_lon) ... If the new v_lon is 0, also set
a ← max(0, a), so a stopped actor reports no deceleration'. -/
theorem ks_speed_nonneg (L δdotMax Δt : ℝ) (elev : ℝ → ℝ → ℝ) (s : KS) (sc : SteerCmd)
    (lc : LonCmd) :
    0 ≤ (ksStep L δdotMax Δt elev s sc lc).1.v ∧
      ((ksStep L δdotMax Δt elev s sc lc).1.v = 0 →
        0 ≤ (ksStep L δdotMax Δt elev s sc lc).1.a) := by
  simp only [ksStep, postClamp]
  refine ⟨le_max_left _ _, fun h => ?_⟩
  simp only [h, ↓reduceIte, le_max_left]

/-- P17-34. 17:101 'Set Z to the map elevation at the new (X, Y), and roll and pitch to
0. The standard physics is planar'. -/
theorem ks_planar (L δdotMax Δt : ℝ) (elev : ℝ → ℝ → ℝ) (s : KS) (sc : SteerCmd)
    (lc : LonCmd) :
    let q := ksStep L δdotMax Δt elev s sc lc
    q.2.roll = 0 ∧ q.2.pitch = 0 ∧ q.2.Z = elev q.1.X q.1.Y :=
  ⟨rfl, rfl, rfl⟩

/-- P17-35, conditional: with δ̇_max ≥ 0, of which §3 (03:20) states no range for
`max_steer_rate`, 17:107 'Under `ANGLE`, δ ← δ + clamp(δ_cmd − δ, ±ρΔt), where
ρ = min(δ̇_max, `steer_rate_cmd`). Under `RATE`, δ ← δ + clamp(δ̇_cmd, ±δ̇_max)Δt'
moves δ by at most ρΔt or δ̇_maxΔt. `steer_rate_cmd` is 'above zero, or +INFINITY'
(05:96). -/
theorem steer_rate_bound (δdotMax Δt δ : ℝ) (hm : 0 ≤ δdotMax) (hΔ : 0 ≤ Δt) :
    (∀ c r, 0 < r → |steerStep δdotMax Δt δ (.angle c (some r)) - δ| ≤ min δdotMax r * Δt) ∧
      (∀ c, |steerStep δdotMax Δt δ (.angle c none) - δ| ≤ δdotMax * Δt) ∧
      (∀ w, |steerStep δdotMax Δt δ (.rate w) - δ| ≤ δdotMax * Δt) := by
  refine ⟨fun c r hr => ?_, fun c => ?_, fun w => ?_⟩
  · simp only [steerStep, add_sub_cancel_left]
    exact abs_clampS_le _ _ (mul_nonneg (le_min hm hr.le) hΔ)
  · simp only [steerStep, add_sub_cancel_left]
    exact abs_clampS_le _ _ (mul_nonneg hm hΔ)
  · simp only [steerStep, add_sub_cancel_left, abs_mul, abs_of_nonneg hΔ]
    exact mul_le_mul_of_nonneg_right (abs_clampS_le _ _ hm) hΔ

/-- P17-35, refuted. 17:107 'Under `RATE`, δ ← δ + clamp(δ̇_cmd, ±δ̇_max)Δt'.
§3 (03:20) states no range for `max_steer_rate`, and the vehicle spec's well-formedness
rules (03:31) do not constrain it. With δ̇_max < 0 the clamp's bounds cross,
clamp(δ̇_cmd, ±δ̇_max) = δ̇_max, and δ moves by |δ̇_max|Δt > δ̇_maxΔt, so the step is
not bounded by δ̇_maxΔt. The conditional result is `steer_rate_bound`. -/
theorem steer_rate_neg_max (δdotMax Δt δ w : ℝ) (hm : δdotMax < 0) (hΔ : 0 < Δt) :
    steerStep δdotMax Δt δ (.rate w) = δ + δdotMax * Δt ∧
      δdotMax * Δt < |steerStep δdotMax Δt δ (.rate w) - δ| := by
  have hc : clampS w δdotMax = δdotMax := by
    unfold clampS clamp
    exact min_eq_right (le_trans (by linarith) (le_max_right _ _))
  have he : steerStep δdotMax Δt δ (.rate w) = δ + δdotMax * Δt := by
    simp only [steerStep, hc]
  refine ⟨he, ?_⟩
  rw [he, add_sub_cancel_left]
  have : δdotMax * Δt < 0 := mul_neg_of_neg_of_pos hm hΔ
  linarith [abs_nonneg (δdotMax * Δt)]

/-- P17-36, refuted. 17:107 '... Under `RATE`, δ ← δ + clamp(δ̇_cmd, ±δ̇_max)Δt. Then
|δ| ≤ δ_max.' No step clamps δ to δ_max (§9.1, §11 and the rest of docs/spec/ have no
runtime steering clamp), so from δ = 0 a held `RATE` command passes any δ_max. -/
theorem steer_exceeds_max (δmax δdotMax Δt : ℝ) (hm : 0 < δdotMax) (hΔ : 0 < Δt) :
    ∃ k : ℕ, δmax < (fun δ => steerStep δdotMax Δt δ (.rate δdotMax))^[k] 0 := by
  have hc : clampS δdotMax δdotMax = δdotMax := clampS_of_abs_le (abs_of_pos hm).le
  have hit : ∀ k : ℕ,
      (fun δ => steerStep δdotMax Δt δ (.rate δdotMax))^[k] 0 = k * (δdotMax * Δt) := by
    intro k
    induction k with
    | zero => simp
    | succ k ih =>
      rw [Function.iterate_succ_apply', ih]
      simp only [steerStep, hc]
      push_cast; ring
  have hp : 0 < δdotMax * Δt := mul_pos hm hΔ
  obtain ⟨k, hk⟩ := exists_nat_gt (δmax / (δdotMax * Δt))
  refine ⟨k, ?_⟩
  rw [hit]
  rwa [div_lt_iff₀ hp] at hk

/-- P17-37. 17:108 'Under `ACCEL`, a moves toward a_cmd by at most `jerk_lon_cmd` · Δt,
so it reaches a_cmd at once when the bound is `+INFINITY`'. -/
theorem accel_no_jerk_bound (Δt a c : ℝ) : lonStep Δt a (.accel c none) = c := rfl

/-- P17-38. 17:111 'ψ̇ = (v/L) tan δ', taken in one Euler step (17:99); tan δ is defined
where cos δ ≠ 0, which holds for |δ| < π/2. -/
theorem ks_euler (L Δt δ a : ℝ) (s : KS) :
    (ksEuler L Δt s δ a).ψ = s.ψ + s.v / L * Real.tan δ * Δt ∧
      (|δ| < Real.pi / 2 → 0 < Real.cos δ) := by
  refine ⟨rfl, fun h => ?_⟩
  rw [abs_lt] at h
  exact Real.cos_pos_of_mem_Ioo ⟨h.1, h.2⟩

/-- P17-39. 17:112 'It reports v_lat = 0, `a_lon` = a, and `a_lat` = vψ̇'. -/
theorem ks_alat (L δdotMax Δt : ℝ) (elev : ℝ → ℝ → ℝ) (s : KS) (sc : SteerCmd)
    (lc : LonCmd) :
    let o := (ksStep L δdotMax Δt elev s sc lc).2
    o.aLat = o.vlon * o.yawRate :=
  rfl

end Driveline.Std
