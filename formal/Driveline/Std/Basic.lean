import Mathlib
import Driveline.Frames
import Driveline.Validity

/-!
# Standard library helpers (spec §17)

`clamp` (17:28), the symmetric `clamp(x, ±b)` of §17.4 and §17.5, the bound of a
no-bound field (05:36), and the time steps of the common notation (17:14): the
base step Δt and a component's period dt = k_div · Δt_base (11:12-13, 11:18).
-/

namespace Driveline.Std

/-- 17:28 '`clamp` ... min(max(x, lo), hi)'. -/
def clamp (x lo hi : ℝ) : ℝ := min (max x lo) hi

/-- clamp(x, ±b). -/
def clampS (x b : ℝ) : ℝ := clamp x (-b) b

/-- 05:36: a bound field; `none` is `+INFINITY`, no bound. -/
def bound : F64 → Option ℝ
  | .fin b => some b
  | _ => none

/-- Moves `x` toward `t` by at most `b · Δt`, or jumps to `t` without a bound. -/
def toward (x t : ℝ) : Option ℝ → ℝ → ℝ
  | some b, Δt => x + clampS (t - x) (b * Δt)
  | none, _ => t

/-- 11:12 'base period Δt_base_ns ∈ ℤ⁺ nanoseconds', in seconds. 17:14 'Δt = Δt_base'. -/
noncomputable def tickDt (base : ℕ+) : ℝ := (base : ℝ) / 10 ^ 9

/-- 17:14 '$dt$ is the component's own period k_div · Δt_base', with 11:13 'some
positive integer k_div'. -/
noncomputable def compDt (k base : ℕ+) : ℝ := (k : ℝ) * tickDt base

theorem tickDt_pos (base : ℕ+) : 0 < tickDt base := by
  unfold tickDt; have := base.pos; positivity

theorem compDt_pos (k base : ℕ+) : 0 < compDt k base := by
  unfold compDt; have := k.pos; have := tickDt_pos base; positivity

theorem tickDt_le_compDt (k base : ℕ+) : tickDt base ≤ compDt k base := by
  unfold compDt
  have h1 : (1 : ℝ) ≤ k := by exact_mod_cast k.pos
  nlinarith [tickDt_pos base]

theorem abs_clampS_le (x b : ℝ) (hb : 0 ≤ b) : |clampS x b| ≤ b := by
  unfold clampS clamp
  rw [abs_le]
  constructor
  · exact le_min (le_max_right _ _) (by linarith)
  · exact min_le_right _ _

theorem clampS_of_abs_le {x b : ℝ} (h : |x| ≤ b) : clampS x b = x := by
  unfold clampS clamp
  rw [abs_le] at h
  rw [max_eq_left h.1, min_eq_left h.2]

end Driveline.Std
