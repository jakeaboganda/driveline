import Mathlib
import Driveline.Std.Basic
import Driveline.VehicleSpec

/-!
# `SimpleDrivetrain` (spec §17.4, 17:86-89)

The automatic gear choice, the resistance force, the low-speed hold, and the
output acceleration. The drive and brake forces are inputs, as the spec gives
them in closed form from the pedals (17:88).
-/

namespace Driveline.Std

open Real

/-- The parameters `SimpleDrivetrain` reads: m, g, ρ_air, C_d, A_f, C_rr,
R_eff, i_fd, i_R, T_drive,max, T_brake,max, δ_max, the gear ratios i_g, and
`num_gears`. -/
structure DT where
  m : ℝ
  g : ℝ
  ρair : ℝ
  Cd : ℝ
  Af : ℝ
  Crr : ℝ
  Reff : ℝ
  ifd : ℝ
  iR : ℝ
  Tdrive : ℝ
  Tbrake : ℝ
  δmax : ℝ
  ratio : ℕ → ℝ
  nGears : ℕ

/-- 17:87 '(|v| / R_eff) i_g i_fd ≥ 157.08 rad/s'. -/
def qualifies (p : DT) (v : ℝ) (g : ℕ) : Prop := 157.08 ≤ |v| / p.Reff * p.ratio g * p.ifd

open Classical in
/-- 17:87 'the largest gear index g with ... ≥ 157.08 rad/s, or gear 1 if none
qualifies'. -/
noncomputable def autoGear (p : DT) (v : ℝ) : ℕ :=
  let q := (Finset.Icc 1 p.nGears).filter (qualifies p v)
  if h : q.Nonempty then q.max' h else 1

/-- 17:88 'F_res = ½ ρ_air C_d A_f v|v| + C_rr m g sgn(v)', with sgn(0) = 0. -/
noncomputable def fRes (p : DT) (v : ℝ) : ℝ :=
  (1 / 2) * p.ρair * p.Cd * p.Af * v * |v| + p.Crr * p.m * p.g * Real.sign v

/-- 17:89, the branch |v| < 0.01 m/s. -/
noncomputable def lowSpeedAccel (m dt v Fd Fhold : ℝ) : ℝ :=
  if Fhold < |Fd| then Real.sign Fd * (|Fd| - Fhold) / m
  else -Real.sign v * min (|v| / dt) ((Fhold - |Fd|) / m)

/-- 17:104 'v_y = v_lat + l_r ψ̇', the CG lateral velocity of the DST init. -/
def dstVy (vlat lr r : ℝ) : ℝ := vlat + lr * r

/-- 17:89 'a = (F_drive − F_res − F_brake sgn(v)) / m + (own.v_lat + l_r
own.yaw_rate) · own.yaw_rate', or the low-speed rule with
F_hold = F_brake + C_rr m g. -/
noncomputable def dtAccel (p : DT) (dt v vlat r lr Fd Fb : ℝ) : ℝ :=
  if |v| < 0.01 then lowSpeedAccel p.m dt v Fd (Fb + p.Crr * p.m * p.g)
  else (Fd - fRes p v - Fb * Real.sign v) / p.m + (vlat + lr * r) * r

/-- P17-27. 17:87 '`DRIVE` with `manual_gear_index` = 0 uses the largest gear
index g with (|v| / R_eff) i_g i_fd ≥ 157.08 rad/s, or gear 1 if none
qualifies.' With `num_gears` ≥ 1 (16:104 '`gear_ratios` is an array literal of
1 to 10 dimensionless values, and `num_gears` is its length') the gear is in
range. -/
theorem auto_gear_in_range (p : DT) (v : ℝ) (hn : 1 ≤ p.nGears) :
    autoGear p v ∈ Finset.Icc 1 p.nGears := by
  classical
  unfold autoGear
  simp only
  split_ifs with h
  · exact (Finset.mem_filter.1 (Finset.max'_mem _ h)).1
  · exact Finset.mem_Icc.2 ⟨le_rfl, hn⟩

/-- Auxiliary to P17-27, not a spec clause: if the ratios decrease, every lower
gear than a qualifying one qualifies too, so the qualifying gears of 17:87 form a
prefix. -/
theorem qualifies_prefix (p : DT) (v : ℝ) (hR : 0 < p.Reff) (hi : 0 ≤ p.ifd)
    (ha : AntitoneOn p.ratio (Finset.Icc 1 p.nGears)) (g g' : ℕ) (h1 : 1 ≤ g')
    (hle : g' ≤ g) (hg : g ≤ p.nGears) (hq : qualifies p v g) : qualifies p v g' := by
  unfold qualifies at *
  have hr : p.ratio g ≤ p.ratio g' :=
    ha (by simp; omega) (by simp; omega) hle
  have hc : 0 ≤ |v| / p.Reff := div_nonneg (abs_nonneg v) hR.le
  calc (157.08 : ℝ) ≤ |v| / p.Reff * p.ratio g * p.ifd := hq
    _ ≤ |v| / p.Reff * p.ratio g' * p.ifd :=
      mul_le_mul_of_nonneg_right (mul_le_mul_of_nonneg_left hr hc) hi

/-- P17-29, conditional: with m > 0, of which §3 and 16:104 state no sign for
the Tier 1 `mass`, 17:89 'Otherwise a = −sgn(v) min(|v| / dt, (F_hold − |F_drive|) / m),
so the actor comes to rest instead of creeping' holds. Physics steps by
Δt = Δt_base and the drivetrain's period is dt = k_div · Δt_base (17:14,
11:12-13), so Δt ≤ dt and one physics step moves v toward 0 without passing
it. -/
theorem low_speed_rest (p : DT) (k base : ℕ+) (v vlat r lr Fd Fb : ℝ) (hm : 0 < p.m)
    (hv : |v| < 0.01) (hF : |Fd| ≤ Fb + p.Crr * p.m * p.g) :
    v + dtAccel p (compDt k base) v vlat r lr Fd Fb * tickDt base ∈ Set.Icc (min 0 v) (max 0 v) := by
  have hdt := compDt_pos k base
  have hΔ := tickDt_pos base
  have hΔdt := tickDt_le_compDt k base
  set dt := compDt k base
  set Δt := tickDt base
  have ha : dtAccel p dt v vlat r lr Fd Fb =
      -Real.sign v * min (|v| / dt) ((Fb + p.Crr * p.m * p.g - |Fd|) / p.m) := by
    simp only [dtAccel, hv, if_true, lowSpeedAccel, if_neg (not_lt.2 hF)]
  rw [ha]
  set c := min (|v| / dt) ((Fb + p.Crr * p.m * p.g - |Fd|) / p.m)
  have hc0 : 0 ≤ c := le_min (div_nonneg (abs_nonneg v) hdt.le) (div_nonneg (by linarith) hm.le)
  have hc1 : c * Δt ≤ |v| := by
    calc c * Δt ≤ |v| / dt * dt :=
          mul_le_mul (min_le_left _ _) hΔdt hΔ.le (div_nonneg (abs_nonneg v) hdt.le)
      _ = |v| := div_mul_cancel₀ _ hdt.ne'
  have hcΔ : 0 ≤ c * Δt := mul_nonneg hc0 hΔ.le
  rcases lt_trichotomy v 0 with h | h | h
  · rw [Real.sign_of_neg h, abs_of_neg h] at *
    rw [min_eq_right h.le, max_eq_left h.le]
    constructor <;> nlinarith
  · subst h; simp
  · rw [Real.sign_of_pos h, abs_of_pos h] at *
    rw [min_eq_left h.le, max_eq_right h.le]
    constructor <;> nlinarith

/-- `SimpleDrivetrain` parameters with m = −1, C_rr = 0 and T_brake,max = R_eff = 1. -/
def negMassDT : DT :=
  { m := -1, g := 1, ρair := 0, Cd := 0, Af := 0, Crr := 0, Reff := 1, ifd := 1, iR := 1,
    Tdrive := 1, Tbrake := 1, δmax := 0, ratio := fun _ => 1, nGears := 1 }

/-- P17-29, refuted. 17:89 'Otherwise a = −sgn(v) min(|v| / dt, (F_hold − |F_drive|) / m),
so the actor comes to rest instead of creeping.' §3 and 16:104 state no sign for the
Tier 1 `mass`. With m = −1, brake = 1 (F_brake = T_brake,max / R_eff = 1), F_drive = 0
and F_hold = 1 > 0, the min is (F_hold − |F_drive|) / m = −1, so a = sgn(v) and from
v = 1/200 one physics step moves v away from 0: the actor does not come to rest. The
conditional result is `low_speed_rest`. -/
theorem low_speed_neg_mass_creeps (k base : ℕ+) :
    let p := negMassDT
    let Fb := 1 * p.Tbrake / p.Reff
    p.m < 0 ∧ 0 < Fb + p.Crr * p.m * p.g ∧ |(0 : ℝ)| ≤ Fb + p.Crr * p.m * p.g ∧
      |(1 / 200 : ℝ)| < 0.01 ∧
      1 / 200 + dtAccel p (compDt k base) (1 / 200) 0 0 0 0 Fb * tickDt base ∉
        Set.Icc (min 0 (1 / 200)) (max 0 (1 / 200)) := by
  have hdt := compDt_pos k base
  have hΔ := tickDt_pos base
  have ha : dtAccel negMassDT (compDt k base) (1 / 200) 0 0 0 0 (1 * negMassDT.Tbrake / negMassDT.Reff) = 1 := by
    have hq : (-1 : ℝ) ≤ 1 / 200 / compDt k base := by
      have := div_pos (show (0 : ℝ) < 1 / 200 by norm_num) hdt; linarith
    simp only [dtAccel, lowSpeedAccel, negMassDT]
    rw [if_pos (by norm_num), Real.sign_of_pos (show (0 : ℝ) < 1 / 200 by norm_num)]
    norm_num
    rw [min_eq_right hq]
    norm_num
  refine ⟨by norm_num [negMassDT], by norm_num [negMassDT], by norm_num [negMassDT], by norm_num, ?_⟩
  rw [ha, Set.mem_Icc, not_and_or]
  right
  rw [max_eq_right (by norm_num)]
  linarith

/-- P17-30. 17:89 '(own.v_lat + l_r own.yaw_rate) · own.yaw_rate, where the
last term, the CG lateral velocity times the yaw rate, turns the net-force
acceleration of the CG into v̇_lon'. Above 0.01 m/s, if the net-force
acceleration (F_drive − F_res − F_brake sgn(v)) / m is the body-x acceleration of
the CG, v̇_x − v_y r, with v_y = v_lat + l_r ψ̇ the CG lateral velocity of the DST
init (17:104), then the output a is v̇_x. -/
theorem drivetrain_yaw_term (p : DT) (dt v vlat r lr Fd Fb vxDot : ℝ) (hv : ¬ |v| < 0.01)
    (hF : (Fd - fRes p v - Fb * Real.sign v) / p.m = vxDot - dstVy vlat lr r * r) :
    dtAccel p dt v vlat r lr Fd Fb = vxDot := by
  simp only [dtAccel, hv, if_false]
  rw [hF, dstVy]
  ring

/-- P17-31. 17:89 '`ANGLE` with `steer_angle_cmd` = `steering_wheel_norm` · δ_max'.
A valid input has |`steering_wheel_norm`| ≤ 1 under `ANGLE` (05:114, see
`Validity.actuator_ranges`). δ_max ≥ 0 holds for every running actor: 08:19 'A
steady state is infeasible if |δ_ss| > δ_max ... During cold init, an infeasible
spawn state is `DL_STATUS_ERR_NUMERIC`', so a feasible δ_ss gives
0 ≤ |δ_ss| ≤ δ_max (`Driveline.VehicleSpec.steer_bound_of_feasible`). -/
theorem drivetrain_steer (n δmax : ℝ) (hn : |n| ≤ 1) (hδ : 0 ≤ δmax) : |n * δmax| ≤ δmax := by
  rw [abs_mul, abs_of_nonneg hδ]
  nlinarith [abs_nonneg n]

end Driveline.Std
