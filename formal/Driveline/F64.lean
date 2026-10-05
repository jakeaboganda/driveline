import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic

/-!
# binary64 values

The `float64` fields of the checkpoint frames (`docs/spec/05-checkpoints.md`).
`F64` has the four kinds of binary64 value and orders them as IEEE 754 does, so
NaN compares false with everything. Finite values are exact reals: the model
has no rounding, which stays `OUT: external`.
-/

namespace Driveline

inductive F64 where
  | fin (x : ℝ)
  | posInf
  | negInf
  | nan

namespace F64

instance : Zero F64 := ⟨fin 0⟩

/-- IEEE `<`: `-∞ < finite < +∞`, and NaN is unordered. -/
def lt : F64 → F64 → Prop
  | fin x, fin y => x < y
  | negInf, fin _ | negInf, posInf | fin _, posInf => True
  | _, _ => False

/-- IEEE `≤`: less, or equal and not NaN. -/
def le (a b : F64) : Prop := lt a b ∨ (a = b ∧ a ≠ nan)

instance : LT F64 := ⟨lt⟩
instance : LE F64 := ⟨le⟩

/-- `x ∈ (lo, hi]`. Only finite values qualify. -/
def inIoc (lo hi : ℝ) : F64 → Prop
  | fin x => lo < x ∧ x ≤ hi
  | _ => False

/-- `x ∈ [lo, hi]`. Only finite values qualify. -/
def inIcc (lo hi : ℝ) : F64 → Prop
  | fin x => lo ≤ x ∧ x ≤ hi
  | _ => False

/-- `x ∈ (lo, hi)`. Only finite values qualify. -/
def inIoo (lo hi : ℝ) : F64 → Prop
  | fin x => lo < x ∧ x < hi
  | _ => False

theorem zero_def : (0 : F64) = fin 0 := rfl

theorem fin_lt_fin {x y : ℝ} : fin x < fin y ↔ x < y := Iff.rfl

theorem fin_le_fin {x y : ℝ} : fin x ≤ fin y ↔ x ≤ y := by
  show x < y ∨ (fin x = fin y ∧ fin x ≠ nan) ↔ x ≤ y
  rw [le_iff_lt_or_eq]
  constructor
  · rintro (h | ⟨h, -⟩)
    · exact Or.inl h
    · exact Or.inr (fin.inj h)
  · rintro (h | rfl)
    · exact Or.inl h
    · exact Or.inr ⟨rfl, fun h => by cases h⟩

theorem not_lt_nan (a : F64) : ¬ a < nan := by
  cases a <;> exact id

theorem not_nan_lt (a : F64) : ¬ nan < a := by
  cases a <;> exact id

theorem not_le_nan (a : F64) : ¬ a ≤ nan := by
  rintro (h | ⟨rfl, h⟩)
  · exact not_lt_nan _ h
  · exact h rfl

theorem zero_lt_posInf : (0 : F64) < posInf := trivial

theorem zero_le_zero : (0 : F64) ≤ 0 := Or.inr ⟨rfl, fun h => by cases h⟩

theorem not_zero_lt_zero : ¬ (0 : F64) < 0 := lt_irrefl (0 : ℝ)

theorem not_inIcc_nan (lo hi : ℝ) : ¬ nan.inIcc lo hi := id

theorem inIoc_zero_pi : (0 : F64).inIoc (-Real.pi) Real.pi :=
  ⟨by linarith [Real.pi_pos], Real.pi_pos.le⟩

theorem inIoo_zero_half_pi : (0 : F64).inIoo (-(Real.pi / 2)) (Real.pi / 2) :=
  ⟨by linarith [Real.pi_pos], by linarith [Real.pi_pos]⟩

end F64

end Driveline
