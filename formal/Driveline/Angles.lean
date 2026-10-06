import Mathlib.Algebra.Order.ToIntervalMod
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.SpecialFunctions.Complex.Arg
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Deriv
import Mathlib.LinearAlgebra.CrossProduct
import Mathlib.LinearAlgebra.UnitaryGroup
import Mathlib.Analysis.Calculus.Deriv.Prod

/-!
# Angle wrapping

`wrap` maps an angle to (-π, π], as `04-perception.md:30` and `04-perception.md:37`
require for `ANGLE` fields. Shared by the slice buffer queries and the vehicle model.
-/

noncomputable section

namespace Driveline.Angles

open Real

/-- An angle wrapped to (-π, π] (04-perception.md:37). -/
def wrap (x : ℝ) : ℝ := toIocMod Real.two_pi_pos (-π) x

/-- P04-11: “For an `ANGLE` field, the difference s[0].f − s[m].f is wrapped to (−π, π]”
(04-perception.md:30). -/
theorem wrap_mem (x : ℝ) : wrap x ∈ Set.Ioc (-π) π := by
  have h := toIocMod_mem_Ioc Real.two_pi_pos (-π) x
  rwa [show -π + 2 * π = π by ring] at h

/-- P04-11: `wrap` is the identity on (−π, π] (04-perception.md:30). -/
theorem wrap_of_mem {x : ℝ} (h : x ∈ Set.Ioc (-π) π) : wrap x = x := by
  unfold wrap
  rw [toIocMod_eq_self, show -π + 2 * π = π by ring]
  exact h

/-- P04-18: “A difference of exactly π therefore turns positive” (04-perception.md:37). -/
theorem wrap_neg_pi : wrap (-π) = π := by
  unfold wrap
  rw [toIocMod_apply_left]
  ring

theorem wrap_eq_add (x : ℝ) : ∃ n : ℤ, wrap x = x + n * (2 * π) := by
  refine ⟨-toIocDiv Real.two_pi_pos (-π) x, ?_⟩
  unfold wrap
  rw [← self_sub_toIocDiv_zsmul, zsmul_eq_mul]
  push_cast
  ring

/-- P04-18: “A difference of exactly π therefore turns positive” (04-perception.md:37):
π itself stays π. -/
theorem wrap_pi : wrap π = π :=
  wrap_of_mem ⟨by linarith [Real.pi_pos], le_rfl⟩

/-- P04-11: “For an `ANGLE` field, the difference s[0].f − s[m].f is wrapped to (−π, π]”
(04-perception.md:30): the result lies in (−π, π], differs from the input by a multiple
of 2π, and wrapping is idempotent. -/
theorem wrap_spec (x : ℝ) :
    wrap x ∈ Set.Ioc (-π) π ∧ (∃ n : ℤ, wrap x = x + n * (2 * π)) ∧ wrap (wrap x) = wrap x :=
  ⟨wrap_mem x, wrap_eq_add x, wrap_of_mem (wrap_mem x)⟩

/-- P04-18: “A difference of exactly π therefore turns positive” (04-perception.md:37):
both −π and π wrap to π. -/
theorem wrap_exact_pi : wrap (-π) = π ∧ wrap π = π := ⟨wrap_neg_pi, wrap_pi⟩

/-- `atan2(y, x)`, the angle of the point (x, y), in (-π, π] (06-lifecycle.md:73). -/
def atan2 (y x : ℝ) : ℝ := Complex.arg ⟨x, y⟩

theorem atan2_mem (y x : ℝ) : atan2 y x ∈ Set.Ioc (-π) π := Complex.arg_mem_Ioc _

theorem atan2_zero_left {x : ℝ} (hx : 0 ≤ x) : atan2 0 x = 0 := by
  have : (⟨x, 0⟩ : ℂ) = (x : ℂ) := Complex.ext (by simp) (by simp)
  rw [atan2, this, Complex.arg_ofReal_of_nonneg hx]

/-- (x, y) is its length times (cos, sin) of `atan2 y x`. -/
theorem atan2_polar (y x : ℝ) :
    Real.sqrt (x ^ 2 + y ^ 2) * Real.cos (atan2 y x) = x ∧
      Real.sqrt (x ^ 2 + y ^ 2) * Real.sin (atan2 y x) = y := by
  have hn : ‖(⟨x, y⟩ : ℂ)‖ = Real.sqrt (x ^ 2 + y ^ 2) := by
    rw [Complex.norm_def, Complex.normSq_mk]; congr 1; ring
  refine ⟨?_, ?_⟩
  · rw [← hn]; exact Complex.norm_mul_cos_arg _
  · rw [← hn]; exact Complex.norm_mul_sin_arg _

/-! ## Rotations (02-conventions.md:16-18) -/

open Matrix

/-- +X East in the World frame, +x forward in the body frame. -/
def e₁ : Fin 3 → ℝ := ![1, 0, 0]
/-- +Y North in the World frame, +y left in the body frame. -/
def e₂ : Fin 3 → ℝ := ![0, 1, 0]
/-- +Z Up. -/
def e₃ : Fin 3 → ℝ := ![0, 0, 1]

/-- Roll: rotation by φ about +X. -/
def Rx (φ : ℝ) : Matrix (Fin 3) (Fin 3) ℝ := !![1, 0, 0; 0, cos φ, -sin φ; 0, sin φ, cos φ]
/-- Pitch: rotation by θ about +Y. -/
def Ry (θ : ℝ) : Matrix (Fin 3) (Fin 3) ℝ := !![cos θ, 0, sin θ; 0, 1, 0; -sin θ, 0, cos θ]
/-- Yaw: rotation by ψ about +Z. -/
def Rz (ψ : ℝ) : Matrix (Fin 3) (Fin 3) ℝ := !![cos ψ, -sin ψ, 0; sin ψ, cos ψ, 0; 0, 0, 1]

/-- Body-to-World rotation. -/
def eulerZYX (ψ θ φ : ℝ) : Matrix (Fin 3) (Fin 3) ℝ := Rz ψ * Ry θ * Rx φ

/-- `skew u *ᵥ v = u ×₃ v`. -/
def skew (u : Fin 3 → ℝ) : Matrix (Fin 3) (Fin 3) ℝ :=
  !![0, -u 2, u 1; u 2, 0, -u 0; -u 1, u 0, 0]

/-- Rodrigues: rotation by `a` about the unit axis `u`. -/
def axisRot (u : Fin 3 → ℝ) (a : ℝ) : Matrix (Fin 3) (Fin 3) ℝ :=
  1 + sin a • skew u + (1 - cos a) • (skew u * skew u)

/-- 02-conventions.md:18: the World frame rotated by ψ about +Z. -/
def headingFrame (ψ : ℝ) : Matrix (Fin 3) (Fin 3) ℝ := Rz ψ

/-- P02-05: “Right-handed Cartesian coordinate system (X, Y, Z) … (+X East, +Y North,
+Z Up)” (02-conventions.md:16). -/
theorem world_right_handed : e₁ ⨯₃ e₂ = e₃ := by
  ext i; fin_cases i <;> simp [cross_apply, e₁, e₂, e₃]

private theorem so3_of {A : Matrix (Fin 3) (Fin 3) ℝ} (h1 : Aᵀ * A = 1) (h2 : A.det = 1) :
    A ∈ Matrix.specialOrthogonalGroup (Fin 3) ℝ :=
  ⟨Matrix.mem_unitaryGroup_iff'.mpr (by
    rw [Matrix.star_eq_conjTranspose, Matrix.conjTranspose_eq_transpose_of_trivial]; exact h1), h2⟩

theorem Rx_mem (φ : ℝ) : Rx φ ∈ Matrix.specialOrthogonalGroup (Fin 3) ℝ := by
  have hφ := sin_sq_add_cos_sq φ
  refine so3_of ?_ ?_
  · ext i j; fin_cases i <;> fin_cases j
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination (1) * hφ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination (1) * hφ
  · simp only [Rx, det_fin_three, Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; linear_combination hφ

theorem Ry_mem (θ : ℝ) : Ry θ ∈ Matrix.specialOrthogonalGroup (Fin 3) ℝ := by
  have hθ := sin_sq_add_cos_sq θ
  refine so3_of ?_ ?_
  · ext i j; fin_cases i <;> fin_cases j
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination (1) * hθ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination (1) * hθ
  · simp only [Ry, det_fin_three, Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; linear_combination hθ

theorem Rz_mem (ψ : ℝ) : Rz ψ ∈ Matrix.specialOrthogonalGroup (Fin 3) ℝ := by
  have hψ := sin_sq_add_cos_sq ψ
  refine so3_of ?_ ?_
  · ext i j; fin_cases i <;> fin_cases j
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination (1) * hψ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination (1) * hψ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
  · simp only [Rz, det_fin_three, Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; linear_combination hψ

/-- P02-06: “ISO 8855 intrinsic Z-Y'-X'' (yaw ψ → pitch θ → roll φ) rotation sequence”
(02-conventions.md:17). Each rotation is about the axis already moved by the earlier ones. -/
theorem eulerZYX_intrinsic (ψ θ φ : ℝ) :
    eulerZYX ψ θ φ ∈ Matrix.specialOrthogonalGroup (Fin 3) ℝ ∧ axisRot e₃ ψ = Rz ψ ∧
      axisRot (Rz ψ *ᵥ e₂) θ * Rz ψ = Rz ψ * Ry θ ∧
      axisRot ((Rz ψ * Ry θ) *ᵥ e₁) φ * (Rz ψ * Ry θ) = eulerZYX ψ θ φ := by
  have hψ := sin_sq_add_cos_sq ψ
  have hθ := sin_sq_add_cos_sq θ
  have hφ := sin_sq_add_cos_sq φ
  refine ⟨Submonoid.mul_mem _ (Submonoid.mul_mem _ (Rz_mem ψ) (Ry_mem θ)) (Rx_mem φ), ?_, ?_, ?_⟩
  · ext i j; fin_cases i <;> fin_cases j
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
  · ext i j; fin_cases i <;> fin_cases j
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination ((cos ψ)*(cos θ) - (cos ψ)) * hψ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination ((cos θ)*(sin ψ) - (sin ψ)) * hψ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination (-(sin θ)) * hψ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination ((cos θ) - 1) * hψ
  · ext i j; fin_cases i <;> fin_cases j
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination (-(cos φ)*(cos θ)^2*(sin ψ) + (cos θ)^2*(sin ψ)) * hψ + (-(cos φ)*(sin ψ) + (sin ψ)) * hθ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination ((cos φ)*(cos ψ)*(sin θ) - (cos ψ)*(sin θ) + (sin φ)*(sin ψ)) * hθ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination ((cos φ)*(cos ψ)*(cos θ)^2 - (cos ψ)*(cos θ)^2) * hψ + ((cos φ)*(cos ψ) - (cos ψ)) * hθ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination ((cos φ)*(sin ψ)*(sin θ) - (cos ψ)*(sin φ) - (sin ψ)*(sin θ)) * hθ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination ((cos θ)*(sin φ)) * hψ
    · simp only [Rx, Ry, Rz, eulerZYX, axisRot, skew, e₁, e₂, e₃, Matrix.mul_apply, Matrix.add_apply, Matrix.smul_apply, Matrix.transpose_apply, Matrix.one_apply, mulVec, dotProduct, Fin.sum_univ_three, Matrix.of_apply, Matrix.cons_val', Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.cons_val_two, Matrix.head_cons, Matrix.tail_cons, Matrix.empty_val', Matrix.cons_val_fin_one, Matrix.head_fin_const, smul_eq_mul, Fin.isValue, Fin.reduceFinMk, Fin.zero_eta, Fin.mk_one, reduceIte, Fin.reduceEq]; 
      all_goals linear_combination ((cos φ)*(cos θ)^3 + (cos φ)*(cos θ)*(sin θ)^2 - (cos θ)^3 - (cos θ)*(sin θ)^2) * hψ + ((cos φ)*(cos θ) - (cos θ)) * hθ

private theorem hasDerivAt_vec3 {f g h : ℝ → ℝ} {a b c t : ℝ} (hf : HasDerivAt f a t)
    (hg : HasDerivAt g b t) (hh : HasDerivAt h c t) :
    HasDerivAt (fun s => ![f s, g s, h s]) ![a, b, c] t := by
  rw [hasDerivAt_pi]; intro i; fin_cases i
  · simpa using hf
  · simpa using hg
  · simpa using hh

/-- P02-07: “All angles are counter-clockwise positive by the right-hand rule”
(02-conventions.md:17). A small positive angle turns +x toward +y about +z, +z toward +x about
+y, and +y toward +z about +x. -/
theorem rotations_ccw_positive :
    HasDerivAt (fun ψ => Rz ψ *ᵥ e₁) e₂ 0 ∧ HasDerivAt (fun θ => Ry θ *ᵥ e₃) e₁ 0 ∧
      HasDerivAt (fun φ => Rx φ *ᵥ e₂) e₃ 0 := by
  refine ⟨?_, ?_, ?_⟩
  · convert hasDerivAt_vec3 (hasDerivAt_cos 0) (hasDerivAt_sin 0) (hasDerivAt_const 0 (0 : ℝ))
      using 1
    · funext s; ext i; fin_cases i <;> simp [Rz, e₁, mulVec, dotProduct, Fin.sum_univ_three]
    · ext i; fin_cases i <;> simp [e₂]
  · convert hasDerivAt_vec3 (hasDerivAt_sin 0) (hasDerivAt_const 0 (0 : ℝ)) (hasDerivAt_cos 0)
      using 1
    · funext s; ext i; fin_cases i <;> simp [Ry, e₃, mulVec, dotProduct, Fin.sum_univ_three]
    · ext i; fin_cases i <;> simp [e₁]
  · convert hasDerivAt_vec3 (hasDerivAt_const 0 (0 : ℝ)) (hasDerivAt_cos 0) (hasDerivAt_sin 0)
      using 1
    · funext s; ext i; fin_cases i <;> simp [Rx, e₂, mulVec, dotProduct, Fin.sum_univ_three]
    · ext i; fin_cases i <;> simp [e₃]

/-- P02-08: “It equals the body frame when roll and pitch are 0” (02-conventions.md:18). -/
theorem heading_eq_body_level (ψ : ℝ) : eulerZYX ψ 0 0 = headingFrame ψ := by
  ext i j; fin_cases i <;> fin_cases j <;>
    simp [eulerZYX, headingFrame, Rz, Ry, Rx, Matrix.mul_apply, Fin.sum_univ_three]

/-- The body x axis of `eulerZYX ψ θ 0`: (cos ψ cos θ, sin ψ cos θ, −sin θ). -/
theorem body_x_axis (ψ θ : ℝ) :
    eulerZYX ψ θ 0 *ᵥ e₁ = ![cos ψ * cos θ, sin ψ * cos θ, -sin θ] := by
  ext i; fin_cases i <;>
    simp [eulerZYX, Rz, Ry, Rx, e₁, Matrix.mul_apply, Matrix.mulVec, dotProduct,
      Fin.sum_univ_three]

/-- P02-40: “On an uphill road, a vehicle facing its lane's driving direction has ISO 8855
pitch θ = −θ_road because positive ISO pitch is nose-down, and one facing the other way has
θ = +θ_road” (02-conventions.md:27). The lane tangent in the driving direction has heading χ
and climbs at θ_road: (cos χ cos θ_road, sin χ cos θ_road, sin θ_road). -/
theorem pitch_of_road_grade {ψ θ χ θroad : ℝ} (hθ : θ ∈ Set.Ioo (-(π / 2)) (π / 2))
    (hr : θroad ∈ Set.Ioo (-(π / 2)) (π / 2)) :
    let t : Fin 3 → ℝ := ![cos χ * cos θroad, sin χ * cos θroad, sin θroad]
    (eulerZYX ψ θ 0 *ᵥ e₁ = t → θ = -θroad) ∧ (eulerZYX ψ θ 0 *ᵥ e₁ = -t → θ = θroad) := by
  intro t
  have inj := Real.injOn_sin
  have mθ : θ ∈ Set.Icc (-(π / 2)) (π / 2) := Set.Ioo_subset_Icc_self hθ
  have mr : θroad ∈ Set.Icc (-(π / 2)) (π / 2) := Set.Ioo_subset_Icc_self hr
  have mnr : -θroad ∈ Set.Icc (-(π / 2)) (π / 2) := ⟨by linarith [mr.2], by linarith [mr.1]⟩
  rw [body_x_axis]
  refine ⟨fun h => inj mθ mnr ?_, fun h => inj mθ mr ?_⟩
  · have := congrFun h 2; simp [t] at this; rw [Real.sin_neg]; linarith
  · have := congrFun h 2; simp [t] at this; linarith

end Driveline.Angles
