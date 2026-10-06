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
range. If the ratios decrease, every lower gear than a qualifying one
qualifies too, so the qualifying gears form a prefix. -/
theorem auto_gear (p : DT) (v : ℝ) (hn : 1 ≤ p.nGears) :
    autoGear p v ∈ Finset.Icc 1 p.nGears ∧
      (0 < p.Reff → 0 ≤ p.ifd → AntitoneOn p.ratio (Finset.Icc 1 p.nGears) →
        ∀ g g', 1 ≤ g' → g' ≤ g → g ≤ p.nGears → qualifies p v g → qualifies p v g') := by
  classical
  refine ⟨?_, fun hR hi ha g g' h1 hle hg hq => ?_⟩
  · unfold autoGear
    simp only
    split_ifs with h
    · exact (Finset.mem_filter.1 (Finset.max'_mem _ h)).1
    · exact Finset.mem_Icc.2 ⟨le_rfl, hn⟩
  · unfold qualifies at *
    have hr : p.ratio g ≤ p.ratio g' :=
      ha (by simp; omega) (by simp; omega) hle
    have hc : 0 ≤ |v| / p.Reff := div_nonneg (abs_nonneg v) hR.le
    calc (157.08 : ℝ) ≤ |v| / p.Reff * p.ratio g * p.ifd := hq
      _ ≤ |v| / p.Reff * p.ratio g' * p.ifd :=
        mul_le_mul_of_nonneg_right (mul_le_mul_of_nonneg_left hr hc) hi

/-- P17-29. 17:89 'Otherwise a = −sgn(v) min(|v| / dt, (F_hold − |F_drive|) / m),
so the actor comes to rest instead of creeping.' Physics steps by
Δt = Δt_base and the drivetrain's period is dt = k_div · Δt_base (17:14,
11:12-13), so Δt ≤ dt and one physics step moves v toward 0 without passing
it. Spec gap: §3 and 16:104 state no sign for the Tier 1 `mass`, so m > 0 is
a hypothesis. -/
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

/-- P17-30. 17:89 '(own.v_lat + l_r own.yaw_rate) · own.yaw_rate, where the
last term, the CG lateral velocity times the yaw rate, turns the net-force
acceleration of the CG into v̇_lon'. Above 0.01 m/s the yaw term is the DST
init's CG lateral velocity v_y = v_lat + l_r ψ̇ (17:104) times the yaw rate. -/
theorem drivetrain_yaw_term (p : DT) (dt v vlat r lr Fd Fb : ℝ) (hv : ¬ |v| < 0.01) :
    dtAccel p dt v vlat r lr Fd Fb = (Fd - fRes p v - Fb * Real.sign v) / p.m + dstVy vlat lr r * r := by
  simp only [dtAccel, hv, if_false, dstVy]

/-- P17-31. 17:89 '`ANGLE` with `steer_angle_cmd` = `steering_wheel_norm` · δ_max'.
A valid input has |`steering_wheel_norm`| ≤ 1 under `ANGLE` (05:114, see
`Validity.actuator_ranges`). Spec gap: §3 states no sign for
`max_steer_angle`, so δ_max ≥ 0 is the ledger's hypothesis. -/
theorem drivetrain_steer (n δmax : ℝ) (hn : |n| ≤ 1) (hδ : 0 ≤ δmax) : |n * δmax| ≤ δmax := by
  rw [abs_mul, abs_of_nonneg hδ]
  nlinarith [abs_nonneg n]

end Driveline.Std
