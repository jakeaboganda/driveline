import Driveline.Std.Basic
import Driveline.Angles

/-!
# Object physics: `PointMassWalker` (spec §17.5, 17:119-126)

The speed, heading, and yaw-rate updates of one walker step (17:120-124) and its init
(17:126). The reference path and its errors are those of `StanleyLat` and enter here as
the desired heading ψ_d.
-/

namespace Driveline.Std

open Real

/-- 17:120 'v_t = min(v_ref, v_max, √(2 a_max max(0, stop_at_odometer − own.odometer_m))),
where the square root of `+INFINITY` is `+INFINITY`'. A non-finite `stop_at_odometer`
drops the third term. -/
noncomputable def targetSpeed (vref vmax amax odo : ℝ) : F64 → ℝ
  | .fin st => min (min vref vmax) (Real.sqrt (2 * amax * max 0 (st - odo)))
  | _ => min vref vmax

/-- 17:121 'v' = max(0, v + clamp(v_t − v, ±a_max Δt))'. -/
noncomputable def walkSpeed (amax Δt v vt : ℝ) : ℝ := max 0 (v + clampS (vt - v) (amax * Δt))

/-- 17:122 'ψ' = w(ψ + clamp(w(ψ_d − ψ), ±max_turn_rate Δt))', with T = `max_turn_rate`. -/
noncomputable def walkHeading (T Δt ψ ψd : ℝ) : ℝ :=
  Angles.wrap (ψ + clampS (Angles.wrap (ψd - ψ)) (T * Δt))

/-- 17:124 '`yaw_rate` = w(ψ' − ψ)/Δt'. -/
noncomputable def walkYawRate (ψ ψ' Δt : ℝ) : ℝ := Angles.wrap (ψ' - ψ) / Δt

/-- 17:126 'it sets ... v from `chassis_state`, with v capped at v_max. An init context
with v_lon < 0 makes the enter call return `DL_STATUS_ERR_INVALID_ARG`' (`none`). -/
noncomputable def walkerInit (vmax vlon : ℝ) : Option ℝ :=
  if vlon < 0 then none else some (min vlon vmax)

/-- P17-47. 17:120 'v_t = min(v_ref, v_max, ...)' and 17:121
'v' = max(0, v + clamp(v_t − v, ±a_max Δt))': the step keeps 0 ≤ v ≤ v_max and changes v
by at most a_max Δt. a_max > 0 is 03:40 (`OSpec.WF`). -/
theorem walker_speed_inv (vref vmax amax odo Δt v : ℝ) (st : F64) (hv0 : 0 ≤ v)
    (hvm : v ≤ vmax) (ha : 0 ≤ amax) (hΔ : 0 ≤ Δt) :
    let v' := walkSpeed amax Δt v (targetSpeed vref vmax amax odo st)
    0 ≤ v' ∧ v' ≤ vmax ∧ |v' - v| ≤ amax * Δt := by
  intro v'
  have hb : 0 ≤ amax * Δt := mul_nonneg ha hΔ
  have ht : targetSpeed vref vmax amax odo st ≤ vmax := by
    cases st <;> simp only [targetSpeed] <;>
      first
      | exact min_le_right vref vmax
      | exact min_le_of_left_le (min_le_right vref vmax)
  set vt := targetSpeed vref vmax amax odo st
  set c := clampS (vt - v) (amax * Δt) with hc
  have hcb : |c| ≤ amax * Δt := abs_clampS_le _ _ hb
  have hcu : c ≤ max (vt - v) (-(amax * Δt)) := by
    simp only [hc, clampS, clamp]; exact min_le_left _ _
  have hv' : v' = max 0 (v + c) := rfl
  rw [abs_le] at hcb
  refine ⟨le_max_left _ _, ?_, ?_⟩
  · rw [hv']
    refine max_le (hv0.trans hvm) ?_
    rcases le_total (vt - v) (-(amax * Δt)) with h | h
    · rw [max_eq_right h] at hcu; linarith
    · rw [max_eq_left h] at hcu; linarith
  · rw [hv', abs_le]
    rcases le_total 0 (v + c) with h | h
    · rw [max_eq_right h]; constructor <;> linarith
    · rw [max_eq_left h]; constructor <;> linarith

/-- P17-48. 17:122 'ψ' = w(ψ + clamp(w(ψ_d − ψ), ±max_turn_rate Δt))' and 17:124
'`yaw_rate` = w(ψ' − ψ)/Δt': the reported yaw rate never exceeds `max_turn_rate`, which
17:119 requires 'above zero'. The clamped value lies in (−π, π], so w leaves it unchanged. -/
theorem walker_yaw_rate (T Δt ψ ψd : ℝ) (hT : 0 < T) (hΔ : 0 < Δt) :
    |walkYawRate ψ (walkHeading T Δt ψ ψd) Δt| ≤ T := by
  set c := clampS (Angles.wrap (ψd - ψ)) (T * Δt) with hc
  have hb : 0 ≤ T * Δt := (mul_pos hT hΔ).le
  have hcb : |c| ≤ T * Δt := abs_clampS_le _ _ hb
  have hw := Angles.wrap_mem (ψd - ψ)
  have hmem : c ∈ Set.Ioc (-π) π := by
    rcases le_or_gt π (T * Δt) with h | h
    · rwa [hc, clampS_of_abs_le ((abs_le.mpr ⟨by linarith [hw.1], hw.2⟩).trans h)]
    · rw [abs_le] at hcb; exact ⟨by linarith, by linarith⟩
  obtain ⟨n, hn⟩ := Angles.wrap_eq_add (ψ + c)
  have hyaw : Angles.wrap (walkHeading T Δt ψ ψd - ψ) = c := by
    have : walkHeading T Δt ψ ψd - ψ = c + n • (2 * π) := by
      simp only [walkHeading, ← hc, hn, zsmul_eq_mul]; ring
    rw [this, Angles.wrap, toIocMod_add_zsmul, ← Angles.wrap, Angles.wrap_of_mem hmem]
  rw [walkYawRate, hyaw, abs_div, abs_of_pos hΔ, div_le_iff₀ hΔ]
  exact hcb

/-- P17-49. 17:120 'where the square root of `+INFINITY` is `+INFINITY`': with
`stop_at_odometer` = `+INFINITY` the third term drops out of the min, and for a_max > 0
this matches the limit of the square root as `stop_at_odometer` grows. -/
theorem stop_infinity (vref vmax amax odo : ℝ) :
    targetSpeed vref vmax amax odo .posInf = min vref vmax ∧
      (0 < amax → Filter.Tendsto (fun st => Real.sqrt (2 * amax * max 0 (st - odo)))
        Filter.atTop Filter.atTop) := by
  refine ⟨rfl, fun ha => ?_⟩
  refine Real.tendsto_sqrt_atTop.comp ?_
  have h2 : (0 : ℝ) < 2 * amax := by linarith
  refine Filter.Tendsto.const_mul_atTop h2 ?_
  refine Filter.tendsto_atTop_mono (fun st => le_max_right 0 (st - odo)) ?_
  exact Filter.tendsto_atTop_add_const_right _ _ Filter.tendsto_id

/-- P17-50. 17:126 'it sets X, Y, ψ, and v from `chassis_state`, with v capped at v_max.
An init context with v_lon < 0 makes the enter call return `DL_STATUS_ERR_INVALID_ARG`':
an accepted init establishes the invariant 0 ≤ v ≤ v_max of P17-47. v_max > 0 is 03:40
(`OSpec.WF`). -/
theorem walker_init_inv (vmax vlon v : ℝ) (hvm : 0 ≤ vmax) (h : walkerInit vmax vlon = some v) :
    0 ≤ v ∧ v ≤ vmax := by
  unfold walkerInit at h
  split_ifs at h with hl
  cases h
  exact ⟨le_min (not_lt.mp hl) hvm, min_le_right _ _⟩

end Driveline.Std
