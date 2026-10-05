import Mathlib.Algebra.Order.ToIntervalMod
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic

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

theorem wrap_mem (x : ℝ) : wrap x ∈ Set.Ioc (-π) π := by
  have h := toIocMod_mem_Ioc Real.two_pi_pos (-π) x
  rwa [show -π + 2 * π = π by ring] at h

theorem wrap_of_mem {x : ℝ} (h : x ∈ Set.Ioc (-π) π) : wrap x = x := by
  unfold wrap
  rw [toIocMod_eq_self, show -π + 2 * π = π by ring]
  exact h

/-- “A difference of exactly π therefore turns positive” (04-perception.md:37). -/
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

end Driveline.Angles
