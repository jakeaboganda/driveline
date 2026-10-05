import Mathlib.Algebra.Order.ToIntervalMod
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.SpecialFunctions.Complex.Arg

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

end Driveline.Angles
