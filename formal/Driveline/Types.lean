import Driveline.Units
import Driveline.VehicleSpec
import Driveline.Schedule

/-!
# DSL types, operators, literals, and declaration rules (spec §16)

The types of `16-static-semantics.md:14-31`, port conversion (16:26-27), the operator
typing of 16:41-47, the literal rules of 16:33-36, the declaration clauses of 16:91,
and the scenario and spec rules of 16:99-103.

Operand types of `binTy` are taken after literal resolution (`resolveLit`, 16:35).
`Int` and `Time` values are modelled on `ℤ` with the range checks of `Driveline.Units`.
-/

namespace Driveline.Types

open Driveline.Units

/-! ## Types (§16.1) -/

/-- The checkpoint frames `IntentFrame`, `KinematicControlFrame`, `ActuatorControlFrame`. -/
inductive FrameTy | intent | kinematic | actuator deriving DecidableEq, Repr

/-- 16:23 'the slice types `VisualSlice`, `RadarSlice`, `CameraSlice`, and `SurfaceSlice`'. -/
inductive SliceTy | visual | radar | camera | surface deriving DecidableEq, Repr

/-- The enum types of 16:24. -/
inductive EnumTy | lon | lat | turnSignal | accel | steer | pedal | wheel | gear
  | objectClass | interpMode | mount deriving DecidableEq, Repr

/-- The types of §16.1. `unit` is `()`, well-formed only as the `A` of a chain (16:20). -/
inductive Ty
  | qty (d : Dim) | time | int | bool | string | enum (e : EnumTy)
  | frame (f : FrameTy) | kinState | lon (f : FrameTy) | lat (f : FrameTy) | ovr (f : FrameTy)
  | slice (s : SliceTy) | targetTrack | sliceBuf (s : Ty) (n : ℕ) | stamped (s : Ty)
  | chain (a b : Ty) | unit
  | array (t : Ty) | routeNodes | rate | entitySpec | openDriveMap
  deriving DecidableEq, Repr

def Ty.isSlice : Ty → Bool | .slice _ => true | _ => false

/-- 16:20 well-formed types: `SliceBuffer<S, N>` with a slice type `S` and 1 ≤ N ≤ 64,
and `Lon<T>`/`Lat<T>` with `T` `IntentFrame` or `KinematicControlFrame` (16:26). -/
def Ty.wf : Ty → Bool
  | .sliceBuf s n => s.isSlice && 1 ≤ n && n ≤ 64
  | .lon f | .lat f => f != .actuator
  | .stamped s => s.wf
  | .array t => t.wf
  | .chain a b => (a == .unit || a.wf) && b.wf
  | .unit => false
  | _ => true

def Ty.isPartial : Ty → Bool | .lon _ | .lat _ => true | _ => false

/-- Conversion of a value where a type is expected (16:26-27). -/
inductive Conv : Ty → Ty → Prop
  | toLon {f} : f ≠ .actuator → Conv (.frame f) (.lon f)
  | toLat {f} : f ≠ .actuator → Conv (.frame f) (.lat f)
  | toOvr (f) : Conv (.frame f) (.ovr f)
  | lonOvr (f) : Conv (.lon f) (.ovr f)
  | latOvr (f) : Conv (.lat f) (.ovr f)
  | chain {a b b'} : Conv b b' → b'.isPartial = false → Conv (.chain a b) (.chain a b')

/-- The stage table of 00:37-42, read off a component's output type. -/
def Ty.stage : Ty → Option VehicleSpec.Stage
  | .sliceBuf _ _ => some .sensor
  | .frame .intent | .lon .intent | .lat .intent | .ovr .intent => some .intent
  | .frame .kinematic | .frame .actuator | .lon .kinematic | .lat .kinematic
  | .ovr .kinematic | .ovr .actuator => some .control
  | .kinState => some .physics
  | _ => none

/-! ## Operators (§16.3) -/

/-- The dimension of a quantity or a `Time` (16:18). -/
def Ty.dim? : Ty → Option Dim | .qty d => some d | .time => some Dim.s | _ => none

/-- Dimension of a `*` or `/` operand: an `Int` is dimensionless and a `Time` is in
seconds (16:43). -/
def Ty.mulDim? : Ty → Option Dim | .int => some 0 | t => t.dim?

inductive BinOp | add | sub | mul | div | lt | le | gt | ge | eq | ne deriving DecidableEq

/-- 16:43 '`+` and `-` accept two `Time` values ..., two quantities of the same
dimension, or the `Int` cases'. -/
def addTy : Ty → Ty → Option Ty
  | .time, .time => some .time
  | .int, .int => some .int
  | .qty d, .qty e => if d = e then some (.qty d) else none
  | .int, .qty d | .qty d, .int => if d = 0 then some (.qty 0) else none
  | _, _ => none

/-- 16:43-44 `*` (`isDiv = false`) and `/` (`isDiv = true`). -/
def mulTy : Bool → Ty → Ty → Option Ty
  | _, .int, .int => some .int
  | _, .time, .int => some .time
  | false, .int, .time => some .time
  | isDiv, x, y =>
    match x.mulDim?, y.mulDim? with
    | some d, some e => some (.qty (if isDiv then d - e else d + e))
    | _, _ => none

/-- 16:45 'Comparisons require two `Int` operands or operands of the same dimension'. -/
def cmpTy : Ty → Ty → Option Ty
  | .int, .int => some .bool
  | .int, .qty d | .qty d, .int => if d = 0 then some .bool else none
  | x, y =>
    match x.dim?, y.dim? with
    | some d, some e => if d = e then some .bool else none
    | _, _ => none

def Ty.eqOnly : Ty → Bool | .bool | .string | .enum _ => true | _ => false

/-- 16:47 '`==` and `!=` also accept `Int`, `Bool`, `String`, and enum operands of the
same type'. -/
def eqTy (x y : Ty) : Option Ty :=
  match cmpTy x y with
  | some t => some t
  | none => if x = y ∧ x.eqOnly = true then some .bool else none

def binTy : BinOp → Ty → Ty → Option Ty
  | .add, x, y | .sub, x, y => addTy x y
  | .mul, x, y => mulTy false x y
  | .div, x, y => mulTy true x y
  | .lt, x, y | .le, x, y | .gt, x, y | .ge, x, y => cmpTy x y
  | .eq, x, y | .ne, x, y => eqTy x y

/-- 16:35 'A `QuantityLit` with dimension s has type `Time` where the expected type is
`Time`'. Applied only to literal expressions. -/
def resolveLit : Option Ty → Ty → Ty
  | some .time, .qty d => if d = Dim.s then .time else .qty d
  | _, t => t

/-- `/` on `Int` or `Time` (16:44): truncation toward zero, `ERR_NUMERIC` on a zero
divisor or a result outside `Int64`. -/
def tDiv (a b : ℤ) : Except Diagnostics.Code ℤ :=
  if b = 0 then .error .errNumeric else checked (a.tdiv b)

/-! ## Literals (§16.2) -/

/-- A `Time` literal's nanoseconds, from `q`, its exact value in seconds. -/
def timeLitNs (q : ℚ) : Option ℤ :=
  let n := q * 10 ^ 9
  if n.den = 1 ∧ inI64 n.num then some n.num else none

def intLitOk (n : ℕ) : Prop := n ≤ 2 ^ 63 - 1

instance (n : ℕ) : Decidable (intLitOk n) := inferInstanceAs (Decidable (_ ≤ _))

/-! ## Component declarations (§16.5) -/

inductive Form | native | modeA | modeB deriving DecidableEq

structure Port where
  name : String
  ty : Ty

structure CompDecl where
  form : Form
  inputs : List Port
  output : Ty
  /-- `none`: the clause is omitted. -/
  requiredTier : Option ℤ
  /-- The divisor `k_div` of a `rate` clause (11:12); `none`: the clause is omitted. -/
  rate : Option ℕ+

def CompDecl.tier (d : CompDecl) : ℤ := d.requiredTier.getD 0

/-- 11:14 'Any component that omits a `(rate: ...)` clause inherits the base clock rate
(k_div = 1)'. -/
def CompDecl.div (d : CompDecl) : ℕ+ := d.rate.getD Schedule.defaultDiv

/-- 16:91 declaration clauses, and 15:24 Mode B ports. -/
def CompDecl.clausesOk (d : CompDecl) : Prop :=
  d.tier ∈ ({0, 1, 2} : Finset ℤ) ∧ (d.output = .kinState → d.rate = none) ∧
    (d.form = .modeB → ∀ p ∈ d.inputs, ∃ s n, p.ty = .sliceBuf s n)

/-- A library component: it has no `rate` clause (16:91). -/
structure LibComp where
  inputs : List Port
  output : Ty

def LibComp.div (_ : LibComp) : ℕ+ := Schedule.defaultDiv

/-! ## Scenario and spec rules (§16.6) -/

inductive WorldStmt | map | timestep (ns : ℤ) | seed (n : ℤ) | environment

def WorldStmt.isMap : WorldStmt → Bool | .map => true | _ => false
def WorldStmt.isTimestep : WorldStmt → Bool | .timestep _ => true | _ => false
def WorldStmt.isSeed : WorldStmt → Bool | .seed _ => true | _ => false
def WorldStmt.isEnv : WorldStmt → Bool | .environment => true | _ => false

/-- The value rule of each world statement. -/
def WorldStmt.valueOk : WorldStmt → Prop
  | .timestep t => 0 < t
  | .seed n => 0 ≤ n ∧ n ≤ maxI64
  | _ => True

instance (w : WorldStmt) : Decidable w.valueOk := by
  cases w <;> unfold WorldStmt.valueOk <;> infer_instance

def worldOk (ws : List WorldStmt) : Prop :=
  ws.countP WorldStmt.isMap = 1 ∧ ws.countP WorldStmt.isTimestep = 1 ∧
    ws.countP WorldStmt.isSeed ≤ 1 ∧ ws.countP WorldStmt.isEnv ≤ 1 ∧ ∀ w ∈ ws, w.valueOk

instance (ws : List WorldStmt) : Decidable (worldOk ws) := by
  unfold worldOk; infer_instance

inductive VKey | cls | tier0 | tier1 | tier2 | tier3 deriving DecidableEq

structure VSpec where
  keys : List VKey
  /-- The effective class, `CAR` when the key is absent. -/
  cls : VehicleSpec.ObjectClass

def vspecOk (v : VSpec) : Prop :=
  v.keys.Nodup ∧ .tier0 ∈ v.keys ∧ (.tier2 ∈ v.keys → .tier1 ∈ v.keys) ∧
    (.tier3 ∈ v.keys → .tier1 ∈ v.keys) ∧ v.cls ∈ [.car, .truck, .cyclist, .motorcycle]

instance (v : VSpec) : Decidable (vspecOk v) := by unfold vspecOk; infer_instance

inductive OKey | cls | length | width | height | vMax | aMax deriving DecidableEq

def OKey.all : List OKey := [.cls, .length, .width, .height, .vMax, .aMax]

structure OSpec where
  keys : List OKey
  cls : VehicleSpec.ObjectClass
  length : ℝ
  width : ℝ
  height : ℝ
  vMax : ℝ
  aMax : ℝ

def ospecOk (o : OSpec) : Prop :=
  o.keys.Nodup ∧ (∀ k ∈ OKey.all, k ∈ o.keys) ∧ o.cls ∈ [.pedestrian, .animal, .unknown, .static] ∧
    0 < o.length ∧ 0 < o.width ∧ 0 < o.height ∧ 0 < o.vMax ∧ 0 < o.aMax

/-! ## Theorems -/

/-- 00:41 'Stage 3 (Physics): Output `KinematicState`': the only Stage 3 output. -/
theorem stage_physics_iff (t : Ty) : t.stage = some .physics ↔ t = .kinState := by
  constructor
  · intro h
    rcases t with _ | _ | _ | _ | _ | _ | f | _ | f | f | f <;>
      first | rfl | (cases f <;> simp [Ty.stage] at h) | simp [Ty.stage] at h
  · rintro rfl; rfl

/-- P11-07. 11:16 'Stage 3 components run on every tick (k_div = 1). A `rate` clause on a
Stage 3 component is a compile-time error.' With 16:91 'except one whose output is
`KinematicState`, which runs every tick' and the stage table 00:37-42. -/
theorem stage3_runs_every_tick (d : CompDecl) (h : d.output.stage = some .physics) :
    (d.clausesOk → d.div = 1 ∧ ∀ k, Schedule.runs d.div k) ∧
      (d.rate.isSome → ¬ d.clausesOk) := by
  have hk := (stage_physics_iff _).1 h
  refine ⟨fun ok => ?_, fun hr ok => ?_⟩
  · have : d.div = 1 := by simp [CompDecl.div, ok.2.1 hk, Schedule.defaultDiv]
    exact ⟨this, fun k => by simp [Schedule.runs, this, Nat.mod_one]⟩
  · simp [ok.2.1 hk] at hr

/-- P16-03. 16:18 '`Time`: A signed 64-bit count of nanoseconds. It has dimension s but
is an integer type.' -/
theorem time_type :
    (∀ t : Units.Time, inI64 t.toInt) ∧ Ty.time.dim? = some Dim.s ∧ (∀ d, Ty.time ≠ .qty d) ∧
      addTy .time .time = some .time :=
  ⟨time_carriers.2.2, rfl, fun _ h => Ty.noConfusion h, rfl⟩

/-- P16-04. 16:20 '`SliceBuffer<S, N>` with a slice type `S`, which `TargetTrack` is not,
and 1 ≤ N ≤ 64 ... `Lon<T>`, `Lat<T>`, or `Override<T>` with the `T` each allows'. -/
theorem sliceBuf_wf (s : Ty) (n : ℕ) :
    (Ty.sliceBuf s n).wf = true ↔ (∃ k, s = .slice k) ∧ 1 ≤ n ∧ n ≤ 64 := by
  cases s <;> simp [Ty.wf, Ty.isSlice]

example : (Ty.sliceBuf .targetTrack 8).wf = false ∧ (Ty.sliceBuf (.slice .radar) 0).wf = false ∧
    (Ty.sliceBuf (.slice .radar) 65).wf = false ∧ (Ty.sliceBuf (.slice .radar) 64).wf = true ∧
    (Ty.lon .actuator).wf = false := by decide

/-- P16-05. 16:26 'A value of type `T` converts to `Lon<T>` or `Lat<T>` where one is
expected ... A partial frame converts to `T` only through `+`.' 16:27 'A value of type
`T`, `Lon<T>`, or `Lat<T>` converts to `Override<T>` where one is expected ... A
`Chain<A, B>` converts to `Chain<A, B'>` exactly when a value of type `B` converts to `B'`
at a port and `B'` is not a partial type, and this is the only chain conversion. An
`Override<T>` never converts to `T`'. -/
theorem conv_rules (f : FrameTy) (a b c : Ty) :
    (Conv (.frame f) (.lon f) ↔ f ≠ .actuator) ∧ (Conv (.frame f) (.lat f) ↔ f ≠ .actuator) ∧
      Conv (.frame f) (.ovr f) ∧ Conv (.lon f) (.ovr f) ∧ Conv (.lat f) (.ovr f) ∧
      (Conv (.chain a b) c ↔ ∃ b', c = .chain a b' ∧ Conv b b' ∧ b'.isPartial = false) ∧
      ¬ Conv (.ovr f) (.frame f) ∧ ¬ Conv (.lon f) (.frame f) ∧ ¬ Conv (.lat f) (.frame f) := by
  refine ⟨⟨fun h => ?_, .toLon⟩, ⟨fun h => ?_, .toLat⟩, .toOvr f, .lonOvr f, .latOvr f,
    ⟨fun h => ?_, ?_⟩, fun h => ?_, fun h => ?_, fun h => ?_⟩
  · cases h; assumption
  · cases h; assumption
  · cases h with | chain h1 h2 => exact ⟨_, rfl, h1, h2⟩
  · rintro ⟨b', rfl, h1, h2⟩; exact .chain h1 h2
  all_goals cases h

/-- P16-06. 16:33 'A `Time` literal is converted from its decimal text to nanoseconds
exactly ..., and one outside [-2^63, 2^63 - 1] nanoseconds is a compile-time error.'
16:35 'A `Time` literal must be a whole number of nanoseconds.' -/
theorem timeLitNs_spec (q : ℚ) (z : ℤ) : timeLitNs q = some z ↔ q * 10 ^ 9 = z ∧ inI64 z := by
  simp only [timeLitNs]
  constructor
  · intro h
    split_ifs at h with hc
    cases h
    exact ⟨(Rat.coe_int_num_of_den_eq_one hc.1).symm, hc.2⟩
  · rintro ⟨h1, h2⟩
    simp [h1, h2]

/-- P16-07. 16:36 'An `IntLit` or `HexLit` has type `Int`, and one above 2^63 - 1 is a
compile-time error.' `Int` is signed 64-bit (16:19): a literal is accepted exactly when
an `Int64` holds it. -/
theorem intLit_ok_iff (n : ℕ) : intLitOk n ↔ ∃ x : Int64, x.toInt = n := by
  constructor
  · intro h
    refine ⟨Int64.ofInt n, ?_⟩
    rw [Int64.toInt_ofInt_of_le] <;> (simp [intLitOk] at *; try omega)
  · rintro ⟨x, hx⟩
    have := Int64.toInt_lt x
    unfold intLitOk; omega

/-- P16-08. 16:43 'A `Time` and a quantity of dimension s is a compile-time error ... A
literal of dimension s takes `Time` from the other operand'. -/
theorem time_plus_s :
    binTy .add .time (.qty Dim.s) = none ∧ binTy .add (.qty Dim.s) .time = none ∧
      binTy .sub .time (.qty Dim.s) = none ∧ binTy .sub (.qty Dim.s) .time = none ∧
      binTy .sub .time (resolveLit (some .time) (.qty Dim.s)) = some .time := by
  decide

/-- P16-09. 16:43 '`Time * Int`, `Int * Time`, and `Time / Int` are `Time` ... When `Time`
meets any other operand of `*` or `/`, it converts to a quantity in seconds, so `v * dt`
is a `Length`, and `Time / Time` is a dimensionless quantity.' -/
theorem time_mul_div (d : Dim) :
    binTy .mul .time .int = some .time ∧ binTy .mul .int .time = some .time ∧
      binTy .div .time .int = some .time ∧ binTy .div .time .time = some (.qty 0) ∧
      binTy .div .int .time = some (.qty (-Dim.s)) ∧
      binTy .mul (.qty d) .time = some (.qty (d + Dim.s)) := by
  refine ⟨rfl, rfl, rfl, ?_, ?_, rfl⟩ <;> simp [binTy, mulTy, Ty.mulDim?, Ty.dim?]

/-- P16-10. 16:44 '`/` on `Int` or `Time` truncates toward zero, and a zero divisor or an
overflow makes the step return `DL_STATUS_ERR_NUMERIC`.' The dividend is an `Int64`
value; the only overflow is -2^63 / -1. -/
theorem tDiv_spec (a b : ℤ) (ha : inI64 a) :
    (∀ q, tDiv a b = .ok q → q = a.tdiv b) ∧ (∀ e, tDiv a b = .error e → e = .errNumeric) ∧
      ((∃ e, tDiv a b = .error e) ↔ b = 0 ∨ (a = minI64 ∧ b = -1)) := by
  have key : b ≠ 0 → (¬ inI64 (a.tdiv b) ↔ a = minI64 ∧ b = -1) := by
    intro hb
    have hn : (a.tdiv b).natAbs = a.natAbs / b.natAbs := Int.natAbs_tdiv a b
    simp only [inI64, minI64, maxI64] at ha ⊢
    rcases (show b = 1 ∨ b = -1 ∨ 2 ≤ b.natAbs by omega) with rfl | rfl | hb2
    · rw [Int.tdiv_one]; omega
    · rw [show (-1 : ℤ) = -1 from rfl, Int.tdiv_neg, Int.tdiv_one]; omega
    · have : (a.tdiv b).natAbs ≤ a.natAbs / 2 := hn ▸ Nat.div_le_div_left hb2 (by norm_num)
      omega
  unfold tDiv checked
  by_cases hb : b = 0
  · simp [hb]
  · have k := key hb
    by_cases hr : inI64 (a.tdiv b) <;> simp_all

/-- P16-11. 16:45 'When a `Time` meets a quantity of dimension s, the `Time` converts to
seconds.' Comparisons accept the pair; `+` and `-` do not (P16-08). -/
theorem cmp_time_s (o : BinOp) (ho : o ∈ [.lt, .le, .gt, .ge, .eq, .ne]) :
    binTy o .time (.qty Dim.s) = some .bool ∧ binTy o (.qty Dim.s) .time = some .bool := by
  simp only [List.mem_cons, List.not_mem_nil, or_false] at ho
  rcases ho with rfl | rfl | rfl | rfl | rfl | rfl <;> decide

/-- P16-12. 16:47 'Comparisons have type `Bool` ... `==` and `!=` also accept `Int`,
`Bool`, `String`, and enum operands of the same type.' -/
theorem eq_same_type (o : BinOp) (ho : o = .eq ∨ o = .ne) (e e' : EnumTy) (h : e ≠ e') :
    binTy o .int .int = some .bool ∧ binTy o .bool .bool = some .bool ∧
      binTy o .string .string = some .bool ∧ binTy o (.enum e) (.enum e) = some .bool ∧
      binTy o .bool .int = none ∧ binTy o (.enum e) (.enum e') = none ∧
      binTy .lt .bool .bool = none := by
  rcases ho with rfl | rfl <;> simp [binTy, eqTy, cmpTy, Ty.dim?, Ty.eqOnly, h]

/-- P16-14. 16:91 'An omitted `required_tier` clause means `required_tier: 0`. Its value
must be 0, 1, or 2 ... A library component ... has no rate clause and always runs at the
base rate.' -/
theorem decl_tier_lib_rate (d : CompDecl) (c : LibComp) :
    (d.clausesOk → d.tier ∈ ({0, 1, 2} : Finset ℤ)) ∧ (d.requiredTier = none → d.tier = 0) ∧
      c.div = 1 ∧ ∀ k, Schedule.runs c.div k :=
  ⟨fun ok => ok.1, fun h => by simp [CompDecl.tier, h], rfl,
    fun k => by simp [Schedule.runs, LibComp.div, Schedule.defaultDiv, Nat.mod_one]⟩

/-- P16-15. 16:99 'A scenario has exactly one `map` of type `OpenDriveMap`, exactly one
`timestep`, a `Time` above zero, at most one `seed` (an `Int` from 0 to 2^63 - 1), and at
most one `environment`.' -/
theorem world_rules :
    ¬ worldOk [.timestep 1] ∧ ¬ worldOk [.map, .map, .timestep 1] ∧ ¬ worldOk [.map] ∧
      ¬ worldOk [.map, .timestep 1, .timestep 1] ∧ ¬ worldOk [.map, .timestep 0] ∧
      ¬ worldOk [.map, .timestep 1, .seed 0, .seed 0] ∧ ¬ worldOk [.map, .timestep 1, .seed (-1)] ∧
      ¬ worldOk [.map, .timestep 1, .seed (2 ^ 63)] ∧
      ¬ worldOk [.map, .timestep 1, .environment, .environment] ∧
      worldOk [.map, .timestep 10000000, .seed (2 ^ 63 - 1), .environment] := by
  decide

/-- P16-16. 16:102 '`tier0` is required, `tier2` requires `tier1`, and `tier3` requires
`tier1`.' 16:103 '`length`, `width`, and `height` are constant `Length`s, `v_max` a
constant `Velocity`, and `a_max` a constant `Acceleration`, each above zero.' -/
theorem spec_rules (v : VSpec) (o : OSpec) :
    (vspecOk v → .tier0 ∈ v.keys ∧ (.tier2 ∈ v.keys → .tier1 ∈ v.keys) ∧
      (.tier3 ∈ v.keys → .tier1 ∈ v.keys)) ∧
    (ospecOk o → 0 < o.length ∧ 0 < o.width ∧ 0 < o.height ∧ 0 < o.vMax ∧ 0 < o.aMax) ∧
    ¬ vspecOk ⟨[.tier0, .tier2], .car⟩ ∧ ¬ vspecOk ⟨[.tier1], .car⟩ ∧
    ¬ vspecOk ⟨[.tier0], .pedestrian⟩ ∧ vspecOk ⟨[.tier0, .tier1, .tier3], .car⟩ :=
  ⟨fun h => ⟨h.2.1, h.2.2.1, h.2.2.2.1⟩, fun h => h.2.2.2, by decide, by decide, by decide,
    by decide⟩

end Driveline.Types
