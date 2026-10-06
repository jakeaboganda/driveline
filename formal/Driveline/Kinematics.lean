import Driveline.Angles
import Driveline.Frames
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Arctan
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Deriv
import Mathlib.Analysis.Calculus.Deriv.Prod

/-!
# Rigid-body kinematics

Planar kinematics of the rear-axle origin and the CG (`05-checkpoints.md:121-135`), the
sideslip angle β_cg, trajectory targets (`05-checkpoints.md:76`) and the odometer
(`05-checkpoints.md:141`). Vectors in the plane are `Fin 2 → ℝ`, World axes; `rot2 ψ` maps
heading-frame axes to World axes.
-/

noncomputable section

namespace Driveline.Kinematics

open Real Matrix
open Driveline.Angles (atan2 atan2_zero_left atan2_polar)

/-- Rotation by `a` in the plane. -/
def rot2 (a : ℝ) : Matrix (Fin 2) (Fin 2) ℝ := !![cos a, -sin a; sin a, cos a]

/-- 05-checkpoints.md:122: v_{y,cg} = v_lat + l_r ψ̇. -/
def vyCg (lr vLat r : ℝ) : ℝ := vLat + lr * r

/-- sgn with sgn(0) = +1 (05-checkpoints.md:123). -/
def sgn0 (x : ℝ) : ℝ := if 0 ≤ x then 1 else -1

/-- 05-checkpoints.md:122-123: β_cg = atan2(sgn(v_lon) v_{y,cg}, |v_lon|). -/
def betaCg (lr vLon vLat r : ℝ) : ℝ := atan2 (sgn0 vLon * vyCg lr vLat r) |vLon|

/-- 05-checkpoints.md:122: with no Tier 1, β = 0. -/
def betaReported : Option ℝ → ℝ → ℝ → ℝ → ℝ
  | none, _, _, _ => 0
  | some lr, v, vl, r => betaCg lr v vl r

/-- Kinematic single-track yaw rate ψ̇ = v_lon / L tan δ (05-checkpoints.md:124). -/
def ksYawRate (L vLon δ : ℝ) : ℝ := vLon / L * tan δ

/-- 05-checkpoints.md:76; `between` is the component's interpolation. -/
def trajTarget {α : Type} (time : α → ℤ) (between : α → α → ℤ → α) : List α → ℤ → Option α
  | [], _ => none
  | [p], _ => some p
  | p :: q :: rest, t =>
    if t ≤ time p then some p
    else if t < time q then some (between p q t)
    else trajTarget time between (q :: rest) t

/-- 05-checkpoints.md:141: the sum of √(ΔX·ΔX + ΔY·ΔY) over consecutive committed
positions, 0 at spawn. -/
def odometer (X Y : ℕ → ℝ) : ℕ → ℝ
  | 0 => 0
  | k + 1 => odometer X Y k +
      √((X (k + 1) - X k) * (X (k + 1) - X k) + (Y (k + 1) - Y k) * (Y (k + 1) - Y k))

/-! ## Helper lemmas -/

theorem rot2_mulVec (a : ℝ) (v : Fin 2 → ℝ) :
    rot2 a *ᵥ v = ![cos a * v 0 - sin a * v 1, sin a * v 0 + cos a * v 1] := by
  ext i; fin_cases i <;> simp [rot2, mulVec, dotProduct, Fin.sum_univ_two] <;> ring

theorem rot2_neg_mulVec (a : ℝ) (v : Fin 2 → ℝ) : rot2 (-a) *ᵥ (rot2 a *ᵥ v) = v := by
  have h := sin_sq_add_cos_sq a
  ext i; fin_cases i <;> simp [rot2_mulVec]
  · linear_combination v 0 * h
  · linear_combination v 1 * h

theorem hasDerivAt_vec2 {f g : ℝ → ℝ} {a b t : ℝ} (hf : HasDerivAt f a t)
    (hg : HasDerivAt g b t) : HasDerivAt (fun s => ![f s, g s]) ![a, b] t := by
  rw [hasDerivAt_pi]; intro i; fin_cases i
  · simpa using hf
  · simpa using hg

theorem sgn0_mul_abs (x : ℝ) : sgn0 x * |x| = x := by
  unfold sgn0; split_ifs with h
  · simp [abs_of_nonneg h]
  · simp [abs_of_neg (not_le.mp h)]

/-- `atan2 y x = arctan (y / x)` for `x > 0`. -/
theorem atan2_of_pos {y x : ℝ} (hx : 0 < x) : atan2 y x = arctan (y / x) := by
  obtain ⟨hc, hs⟩ := atan2_polar y x
  have hr : 0 < √(x ^ 2 + y ^ 2) := Real.sqrt_pos.mpr (by positivity)
  have habs : |atan2 y x| < π / 2 :=
    Complex.abs_arg_lt_pi_div_two_iff.mpr (Or.inl hx)
  obtain ⟨h1, h2⟩ := abs_lt.mp habs
  rw [← Real.arctan_tan h1 h2, Real.tan_eq_sin_div_cos]
  congr 1
  rw [← hc, ← hs]
  field_simp

/-! ## Theorems -/

/-- P05-23: “before t_0 it is the first point, between points it follows the component's
interpolation, and after the last point it is the last point, held. A trajectory of one
point is that point, held” and “The times are not negative and strictly increase”
(05-checkpoints.md:76). -/
theorem trajTarget_spec {α : Type} (time : α → ℤ) (between : α → α → ℤ → α) :
    (∀ p rest t, t ≤ time p → trajTarget time between (p :: rest) t = some p) ∧
      (∀ ps pn t, ((ps ++ [pn]).map time).Chain' (· < ·) → time pn ≤ t →
        trajTarget time between (ps ++ [pn]) t = some pn) ∧
      (∀ p t, trajTarget time between [p] t = some p) := by
  refine ⟨fun p rest t h => ?_, fun ps pn t hc ht => ?_, fun _ _ => rfl⟩
  · cases rest with
    | nil => rfl
    | cons q rest => simp [trajTarget, h]
  · have hp : (ps ++ [pn]).Pairwise (fun a b => time a < time b) :=
      List.pairwise_map.mp (List.chain'_iff_pairwise.mp hc)
    clear hc
    induction ps with
    | nil => rfl
    | cons a ps ih =>
      have hpw := List.pairwise_cons.mp hp
      have ha : ¬ t ≤ time a := not_le.mpr ((hpw.1 pn (by simp)).trans_le ht)
      cases ps with
      | nil => simp [trajTarget, ha, not_lt.mpr ht]
      | cons b ps =>
        have hb : ¬ t < time b := by
          have h2 := List.pairwise_cons.mp hpw.2
          rcases List.mem_append.mp (show pn ∈ ps ++ [pn] by simp) with h | h
          · exact not_lt.mpr ((h2.1 pn (by simp)).le.trans ht)
          · exact not_lt.mpr ((h2.1 pn (by simp)).le.trans ht)
        simp only [List.cons_append, trajTarget, ha, hb, ↓reduceIte]
        exact ih hpw.2

/-- P05-25: “A consumer's remaining stopping distance is `stop_at_odometer` −
`own.odometer_m`” (05-checkpoints.md:78), with “It never decreases” (05-checkpoints.md:141). -/
theorem remaining_antitone (stop : ℝ) (odo : ℕ → ℝ) (h : Monotone odo) :
    Antitone (fun k => stop - odo k) :=
  fun _ _ hab => sub_le_sub_left (h hab) stop

/-- P05-37: “Inertial acceleration of the rear-axle origin in heading-frame axes:
a_lon = v̇_lon − v_lat ψ̇ and a_lat = v̇_lat + v_lon ψ̇” (05-checkpoints.md:135). -/
theorem accel_heading_axes {vLon vLat ψ : ℝ → ℝ} {t dvLon dvLat r : ℝ}
    (h1 : HasDerivAt vLon dvLon t) (h2 : HasDerivAt vLat dvLat t) (h3 : HasDerivAt ψ r t) :
    HasDerivAt (fun s => rot2 (ψ s) *ᵥ ![vLon s, vLat s])
      (rot2 (ψ t) *ᵥ ![dvLon - vLat t * r, dvLat + vLon t * r]) t := by
  convert hasDerivAt_vec2 ((h3.cos.mul h1).sub (h3.sin.mul h2))
    ((h3.sin.mul h1).add (h3.cos.mul h2)) using 1
  · funext s; simp [rot2_mulVec]
  · ext i; fin_cases i <;> simp [rot2_mulVec] <;> ring

/-- P05-28: “In a turn it differs from the reported `a_lon` … by v_lat ψ̇”
(05-checkpoints.md:92) and “committed v̇_lon = a_lon + v_lat ψ̇” (05-checkpoints.md:93). -/
theorem vdot_sub_aLon {vLon vLat ψ : ℝ → ℝ} {t dvLon dvLat r : ℝ} {A : Fin 2 → ℝ}
    (h1 : HasDerivAt vLon dvLon t) (h2 : HasDerivAt vLat dvLat t) (h3 : HasDerivAt ψ r t)
    (hA : HasDerivAt (fun s => rot2 (ψ s) *ᵥ ![vLon s, vLat s]) A t) :
    dvLon - (rot2 (-ψ t) *ᵥ A) 0 = vLat t * r ∧ dvLon = (rot2 (-ψ t) *ᵥ A) 0 + vLat t * r := by
  rw [hA.unique (accel_heading_axes h1 h2 h3), rot2_neg_mulVec]
  simp

/-- P05-32: “v_{x,cg} = v_lon, v_{y,cg} = v_lat + l_r ψ̇” (05-checkpoints.md:122), with
“CG is located at longitudinal distance l_r forward of the rear axle” (02-conventions.md:20).
Planar: `O` is the rear-axle origin, `V` its velocity, and the CG velocity in heading-frame
axes is (v_lon, v_lat + l_r ψ̇). -/
theorem cg_velocity {O : ℝ → Fin 2 → ℝ} {ψ : ℝ → ℝ} {t r : ℝ} {V : Fin 2 → ℝ} (lr : ℝ)
    (hO : HasDerivAt O V t) (hψ : HasDerivAt ψ r t) :
    HasDerivAt (fun s => O s + rot2 (ψ s) *ᵥ ![lr, 0])
      (rot2 (ψ t) *ᵥ ![(rot2 (-ψ t) *ᵥ V) 0, vyCg lr ((rot2 (-ψ t) *ᵥ V) 1) r]) t := by
  have h := sin_sq_add_cos_sq (ψ t)
  convert hO.add (hasDerivAt_vec2 (hψ.cos.mul_const lr) (hψ.sin.mul_const lr)) using 1
  · funext s; ext i; fin_cases i <;> simp [rot2_mulVec]
  · ext i; fin_cases i <;> simp [rot2_mulVec, vyCg]
    · linear_combination (-V 0) * h
    · linear_combination (-V 1) * h

/-- P05-36: “`v_lat` … −l_r ψ̇ + v_{y,cg} for `ST`/`MB`” (05-checkpoints.md:133). `W` is the
CG velocity. -/
theorem vLat_from_cg {O : ℝ → Fin 2 → ℝ} {ψ : ℝ → ℝ} {t r : ℝ} {V W : Fin 2 → ℝ} (lr : ℝ)
    (hO : HasDerivAt O V t) (hψ : HasDerivAt ψ r t)
    (hP : HasDerivAt (fun s => O s + rot2 (ψ s) *ᵥ ![lr, 0]) W t) :
    (rot2 (-ψ t) *ᵥ V) 1 = -lr * r + (rot2 (-ψ t) *ᵥ W) 1 := by
  rw [hP.unique (cg_velocity lr hO hψ), rot2_neg_mulVec]
  simp [vyCg]

/-- P05-33: “β_cg = atan2(sgn(v_lon) v_{y,cg}, |v_lon|) with sgn(0) = +1 and β_cg = 0 when
v_lon = v_{y,cg} = 0” (05-checkpoints.md:122-123). -/
theorem betaCg_rest (lr vLat r : ℝ) (h : vyCg lr vLat r = 0) :
    betaCg lr 0 vLat r = 0 ∧ sgn0 0 = 1 := by
  refine ⟨?_, by simp [sgn0]⟩
  simp only [betaCg, h, mul_zero, abs_zero]
  exact atan2_zero_left le_rfl

/-- P05-34: “This equals arctan(v_{y,cg} / v_lon) whenever v_lon ≠ 0, including reverse
driving” (05-checkpoints.md:123). -/
theorem betaCg_eq_arctan (lr vLon vLat r : ℝ) (hv : vLon ≠ 0) :
    betaCg lr vLon vLat r = arctan (vyCg lr vLat r / vLon) := by
  rw [betaCg, atan2_of_pos (abs_pos.mpr hv)]
  congr 1
  conv_rhs => rw [← sgn0_mul_abs vLon]
  have ha : |vLon| ≠ 0 := abs_ne_zero.mpr hv
  have hs : sgn0 vLon ≠ 0 := by unfold sgn0; split_ifs <;> norm_num
  have hs2 : sgn0 vLon * sgn0 vLon = 1 := by unfold sgn0; split_ifs <;> norm_num
  field_simp
  linear_combination (-vyCg lr vLat r) * hs2

/-- P05-35: “rear-axle lateral velocity is genuinely v_lat = 0, while yaw rate is
ψ̇ = v_lon/L tan δ and … β_cg = arctan(l_r/L tan δ)” (05-checkpoints.md:124). -/
theorem ks_betaCg (lr L δ vLon : ℝ) (hv : vLon ≠ 0) :
    betaCg lr vLon 0 (ksYawRate L vLon δ) = arctan (lr / L * tan δ) := by
  rw [betaCg_eq_arctan _ _ _ _ hv]
  congr 1
  rw [vyCg, ksYawRate, zero_add,
    show lr * (vLon / L * tan δ) / vLon = lr / L * tan δ * (vLon * vLon⁻¹) by ring,
    mul_inv_cancel₀ hv, mul_one]

/-- P05-35 (REFUTED): “β_cg = arctan(l_r/L tan δ) ≠ 0 for v_lon ≠ 0”
(05-checkpoints.md:124) fails for straight-ahead steering δ = 0, with v_lon = 1. -/
theorem ks_betaCg_ne_zero_false : betaCg 1.5 1 0 (ksYawRate 2.7 1 0) = 0 := by
  simp only [betaCg, ksYawRate, vyCg, tan_zero, mul_zero, add_zero, abs_one]
  exact atan2_zero_left zero_le_one

/-- P05-38: “the sum of the horizontal distances √(ΔX·ΔX + ΔY·ΔY) between consecutive
committed positions … and 0 at spawn. It never decreases” (05-checkpoints.md:141). -/
theorem odometer_monotone (X Y : ℕ → ℝ) : Monotone (odometer X Y) ∧ odometer X Y 0 = 0 :=
  ⟨monotone_nat_of_le_succ fun k => le_add_of_nonneg_right (Real.sqrt_nonneg _), rfl⟩

end Driveline.Kinematics
