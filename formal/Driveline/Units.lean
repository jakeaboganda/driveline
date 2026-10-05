import Driveline.Diagnostics

/-!
# Units, time arithmetic, and the ABI constants (spec §2, §3.1, §16.1, header)

Dimensions over (m, kg, s) and the unit expressions of `12-grammar.md:82`
(`16-static-semantics.md:16-17`), the time representation of `02-conventions.md:15`
with checked `Time` arithmetic, the invariant tolerance of `03-vehicle-parameters.md:31`,
the tick start of `00-conformance.md:35`, and the header's ABI word and status codes
(`abi/driveline_abi.h:12-23`).

Integer values are modelled on `ℤ` with explicit `Int64` range checks. Quantities
and tolerance operands are exact reals: a tier value is a constant expression
(16:100), and a non-finite binary64 result there is a compile-time error (16:44),
so NaN and infinities never reach the tolerance check.
-/

namespace Driveline.Units

/-! ## Dimensions and units (§16.1, §12) -/

/-- Exponents of (m, kg, s). An additive commutative group by the Mathlib product
instances, so multiplying units adds dimensions. -/
abbrev Dim := ℤ × ℤ × ℤ

def Dim.s : Dim := (0, 0, 1)

/-- The `UnitName`s of 12:82. -/
inductive UnitName | m | s | ms | us | ns | kg | N | Pa | rad | deg | Hz
  deriving DecidableEq, Repr

def UnitName.dim : UnitName → Dim
  | .m => (1, 0, 0)
  | .s | .ms | .us | .ns => (0, 0, 1)
  | .kg => (0, 1, 0)
  | .N => (1, 1, -2)
  | .Pa => (-1, 1, -2)
  | .rad | .deg => 0
  | .Hz => (0, 0, -1)

/-- The SI factor of each unit name. -/
noncomputable def UnitName.factor : UnitName → ℝ
  | .ms => 1 / 10 ^ 3
  | .us => 1 / 10 ^ 6
  | .ns => 1 / 10 ^ 9
  | .deg => Real.pi / 180
  | _ => 1

/-- `UnitAtom ::= UnitName ("^" [0-9]+)?` (12:82). -/
structure UnitAtom where
  name : UnitName
  pow : ℕ := 1

def UnitAtom.dim (a : UnitAtom) : Dim := (a.pow : ℤ) • a.name.dim

noncomputable def UnitAtom.factor (a : UnitAtom) : ℝ := a.name.factor ^ a.pow

/-- `UnitExpr ::= UnitAtom (("*" | "/") UnitAtom)*`, applied left to right (12:82),
so `a / b * c` is `mul (div (atom a) b) c`. -/
inductive UnitExpr
  | atom (a : UnitAtom)
  | mul (l : UnitExpr) (r : UnitAtom)
  | div (l : UnitExpr) (r : UnitAtom)

def UnitExpr.dim : UnitExpr → Dim
  | .atom a => a.dim
  | .mul l r => l.dim + r.dim
  | .div l r => l.dim - r.dim

noncomputable def UnitExpr.factor : UnitExpr → ℝ
  | .atom a => a.factor
  | .mul l r => l.factor * r.factor
  | .div l r => l.factor / r.factor

/-- P16-01. "A quantity is a binary64 value with a dimension over meters, kilograms,
and seconds. Radians and degrees are dimensionless, so `rad/s` and `Hz` have the same
dimension." (16-static-semantics.md:16). `*` adds dimensions, `/` subtracts them, and
`rad/s` has the dimension of `Hz`. 12:82 'A `UnitExpr` applies `*` and `/` left to right,
so `N*s/m` is N·s/m and `N/m*s` is also N·s/m': the two have the same dimension and
factor. -/
theorem dim_mul_div_rad_s_Hz (l : UnitExpr) (r : UnitAtom) :
    (UnitExpr.mul l r).dim = l.dim + r.dim ∧ (UnitExpr.div l r).dim = l.dim - r.dim ∧
      (UnitExpr.div (.atom ⟨.rad, 1⟩) ⟨.s, 1⟩).dim = (UnitExpr.atom ⟨.Hz, 1⟩).dim ∧
      (UnitExpr.mul (.div (.atom ⟨.N, 1⟩) ⟨.m, 1⟩) ⟨.s, 1⟩).dim =
        (UnitExpr.div (.mul (.atom ⟨.N, 1⟩) ⟨.s, 1⟩) ⟨.m, 1⟩).dim ∧
      (UnitExpr.mul (.div (.atom ⟨.N, 1⟩) ⟨.m, 1⟩) ⟨.s, 1⟩).factor =
        (UnitExpr.div (.mul (.atom ⟨.N, 1⟩) ⟨.s, 1⟩) ⟨.m, 1⟩).factor := by
  refine ⟨rfl, rfl, ?_, ?_, ?_⟩
  · simp [UnitExpr.dim, UnitAtom.dim, UnitName.dim]
  · simp only [UnitExpr.dim]; abel
  · simp only [UnitExpr.factor]; ring

/-- The named quantity types of 16:17. -/
inductive NamedQty
  | scalar | angle | length | velocity | acceleration | jerk | angularVelocity | frequency
  | mass | force | torque | pressure
  deriving DecidableEq, Repr

def NamedQty.dim : NamedQty → Dim
  | .scalar | .angle => 0
  | .length => (1, 0, 0)
  | .velocity => (1, 0, -1)
  | .acceleration => (1, 0, -2)
  | .jerk => (1, 0, -3)
  | .angularVelocity | .frequency => (0, 0, -1)
  | .mass => (0, 1, 0)
  | .force => (1, 1, -2)
  | .torque => (2, 1, -2)
  | .pressure => (-1, 1, -2)

/-- P16-02. "`AngularVelocity` (1/s), `Frequency` (1/s), `Mass` (kg), `Force` (N),
`Torque` (N·m), and `Pressure` (Pa)" (16-static-semantics.md:17). Each named type has
the dimension of its unit text. -/
theorem named_dims :
    NamedQty.angularVelocity.dim = NamedQty.frequency.dim ∧
      NamedQty.frequency.dim = (UnitExpr.atom ⟨.Hz, 1⟩).dim ∧
      NamedQty.mass.dim = (UnitExpr.atom ⟨.kg, 1⟩).dim ∧
      NamedQty.force.dim = (UnitExpr.atom ⟨.N, 1⟩).dim ∧
      NamedQty.torque.dim = (UnitExpr.mul (.atom ⟨.N, 1⟩) ⟨.m, 1⟩).dim ∧
      NamedQty.pressure.dim = (UnitExpr.atom ⟨.Pa, 1⟩).dim ∧
      NamedQty.acceleration.dim = (UnitExpr.div (.atom ⟨.m, 1⟩) ⟨.s, 2⟩).dim := by
  simp [NamedQty.dim, UnitExpr.dim, UnitAtom.dim, UnitName.dim]

/-! ## Int64 and time (§2) -/

def minI64 : ℤ := -2 ^ 63
def maxI64 : ℤ := 2 ^ 63 - 1

def inI64 (z : ℤ) : Prop := minI64 ≤ z ∧ z ≤ maxI64

instance (z : ℤ) : Decidable (inI64 z) := inferInstanceAs (Decidable (_ ∧ _))

/-- A timestamp in a frame, buffer, or ABI struct (02:15). -/
abbrev Timestamp := UInt64
/-- A time inside a frame, such as a trajectory time (02:15). -/
abbrev FrameTime := Int64
/-- A value of the DSL type `Time` (02:15, 16:18). -/
abbrev Time := Int64

/-- P02-01. "Every timestamp in a frame, buffer, or ABI struct is an unsigned 64-bit
count of nanoseconds since t = 0. Times inside a frame ... are `int64` absolute
nanoseconds. Every value of the DSL type `Time` is a signed 64-bit count of
nanoseconds" (02-conventions.md:15). The three carriers have the stated ranges. -/
theorem time_carriers :
    (∀ t : Timestamp, t.toNat < 2 ^ 64) ∧ (∀ t : FrameTime, inI64 t.toInt) ∧
      (∀ t : Time, inI64 t.toInt) := by
  refine ⟨fun t => t.toNat_lt, fun t => ⟨?_, ?_⟩, fun t => ⟨?_, ?_⟩⟩ <;>
    simp only [minI64, maxI64] <;>
    first
    | exact Int64.le_toInt t
    | have := Int64.toInt_lt t; omega

/-- A `Time` operation's result: in range, or `DL_STATUS_ERR_NUMERIC`. -/
def checked (z : ℤ) : Except Diagnostics.Code ℤ :=
  if inI64 z then .ok z else .error .errNumeric

def tAdd (a b : ℤ) : Except Diagnostics.Code ℤ := checked (a + b)
def tSub (a b : ℤ) : Except Diagnostics.Code ℤ := checked (a - b)
def tMul (a b : ℤ) : Except Diagnostics.Code ℤ := checked (a * b)

/-- P02-02. "at t = 0.05 s, `t - 0.18s` is -130,000,000 ns" (02-conventions.md:15). -/
theorem t_minus_018 : tSub 50000000 180000000 = .ok (-130000000) := by
  simp [tSub, checked, inI64, minI64, maxI64]

/-- P02-03. "Overflow in `Time` arithmetic is `DL_STATUS_ERR_NUMERIC`"
(02-conventions.md:15). Each operation gives the exact result when it is in range,
and `ERR_NUMERIC` otherwise. -/
theorem time_overflow_numeric (a b : ℤ) :
    (tAdd a b = (if inI64 (a + b) then .ok (a + b) else .error .errNumeric)) ∧
      (tSub a b = (if inI64 (a - b) then .ok (a - b) else .error .errNumeric)) ∧
      (tMul a b = (if inI64 (a * b) then .ok (a * b) else .error .errNumeric)) :=
  ⟨rfl, rfl, rfl⟩

/-- P00-01. "Tick k starts at t = k · Δt_base" (00-conformance.md:35). Tick starts
strictly increase, and stay below 2^64 ns, so fit a timestamp, for k < 2^64 / Δt. -/
theorem tick_start (dt : ℕ+) :
    StrictMono (Schedule.tickTime dt) ∧
      ∀ k : ℕ, k < 2 ^ 64 / (dt : ℕ) → Schedule.tickTime dt k < 2 ^ 64 := by
  refine ⟨Schedule.tickTime_strictMono dt, fun k hk => ?_⟩
  unfold Schedule.tickTime
  have h1 : (k + 1) * (dt : ℕ) ≤ 2 ^ 64 / (dt : ℕ) * dt := Nat.mul_le_mul_right _ hk
  have h2 : 2 ^ 64 / (dt : ℕ) * dt ≤ 2 ^ 64 := Nat.div_mul_le_self _ _
  have h3 : k * (dt : ℕ) < (k + 1) * dt := Nat.mul_lt_mul_of_pos_right (Nat.lt_succ_self k) dt.pos
  omega

/-! ## Invariant tolerance (§3.1) -/

/-- `|a - b| ≤ 10⁻⁶ · max(|a|, |b|, 1)` (03:31). -/
def approxEq (a b : ℝ) : Prop := |a - b| ≤ 1 / 10 ^ 6 * max |a| (max |b| 1)

/-- P03-09. "An invariant written a == b in the tier table holds when
|a - b| ≤ 10⁻⁶ · max(|a|, |b|, 1)" (03-vehicle-parameters.md:31). Over ℝ the relation is reflexive and symmetric, implied by
exact equality, and not transitive. Its binary64 evaluation is out of scope (P03-41). -/
theorem approxEq_refl_symm_not_trans :
    (∀ a : ℝ, approxEq a a) ∧ (∀ a b : ℝ, approxEq a b → approxEq b a) ∧
      (∀ a b : ℝ, a = b → approxEq a b) ∧
      ¬ ∀ a b c : ℝ, approxEq a b → approxEq b c → approxEq a c := by
  have refl : ∀ a : ℝ, approxEq a a := fun a => by
    unfold approxEq
    rw [sub_self, abs_zero]
    positivity
  refine ⟨refl, fun a b h => ?_, fun a b h => h ▸ refl a, fun h => ?_⟩
  · unfold approxEq at *
    rw [abs_sub_comm, max_left_comm]
    exact h
  · have := h 0 (1 / 10 ^ 6) (2 / 10 ^ 6)
      (by unfold approxEq; norm_num [abs_of_pos])
      (by unfold approxEq; norm_num [abs_of_pos])
    unfold approxEq at this
    norm_num [abs_of_pos] at this

/-! ## Header constants -/

/-- `#define DL_ABI_VERSION_0_20 0x00001400U` (driveline_abi.h:12). -/
def abiVersion_0_20 : UInt32 := 0x00001400

/-- PH-01. "#define DL_ABI_VERSION_0_20 0x00001400U" (driveline_abi.h:12). The word
is minor version 20 in bits 8-15 and major version 0 above it. -/
theorem abi_word : abiVersion_0_20.toNat = 0 * 2 ^ 16 + 20 * 2 ^ 8 := by decide

/-- PH-02. The `dl_status_t` enum (driveline_abi.h:14-23): `DL_STATUS_OK = 0`, the
`WARN_` codes 2 and 3, and the `ERR_` codes -1 to -6. The codes are pairwise
distinct, `OK` is the only zero, warnings are positive and errors negative. -/
theorem status_codes :
    Function.Injective Diagnostics.Code.toInt ∧
      ∀ c : Diagnostics.Code,
        (c = .ok ↔ c.toInt = 0) ∧
          ((c = .warnFmuColdSplice ∨ c = .warnTrimMismatch) ↔ 0 < c.toInt) ∧
          ((c ≠ .ok ∧ c ≠ .warnFmuColdSplice ∧ c ≠ .warnTrimMismatch) ↔ c.toInt < 0) := by
  refine ⟨fun a b h => ?_, fun c => ?_⟩
  · cases a <;> cases b <;> simp_all [Diagnostics.Code.toInt]
  · cases c <;> simp [Diagnostics.Code.toInt]

end Driveline.Units
