import Driveline.Types
import Driveline.Frames

/-!
# Component manifests and parameter passing (spec §15)

Signature sources (15:16-26), the manifest members of 15:38-50 with their validity
rules, the call-site check of 15:54, and the `dl_param_t` encoding of 15:54 and
`abi/driveline_abi.h:339-345`.

Parameter values are exact: an `f64` value is a real number, and binary64 rounding is
out of scope. A manifest is modelled after JSON parsing: `unitExpr` is the §12 parse of
`unit`, and `default` is the exact value of the JSON number's decimal text (15:48).
-/

namespace Driveline.Manifest

open Driveline.Units Driveline.Types

deriving instance DecidableEq for Port

/-! ## Signature sources (§15.1) -/

/-- The component kinds of 15:18-22. -/
inductive Kind | declared | modeB | modeA | native | std deriving DecidableEq

inductive SigSource | decl | fmuManifest | dcmJson | stdlib deriving DecidableEq

def sigSource : Kind → SigSource
  | .declared | .modeB => .decl
  | .modeA => .fmuManifest
  | .native => .dcmJson
  | .std => .stdlib

inductive Cardinality | oneToOne | oneToMany | manyToMany deriving DecidableEq

inductive Entity | vehicle | object deriving DecidableEq

/-- The parts of a signature that 15:24 fixes for a declared component. -/
structure Sig where
  card : Cardinality
  decks : List String
  entity : Option Entity

/-- 15:24 the signature of a component declared with its own signature. -/
def declSig (d : CompDecl) : Sig :=
  ⟨.oneToOne, [], if d.output.stage = some .physics then some .vehicle else none⟩

/-- 15:26 'The declared ports, output type, and `required_tier` must equal the manifest's'. -/
def modeAMatches (inputs : List Port) (output : Ty) (tier : ℤ) (d : CompDecl) : Prop :=
  d.inputs = inputs ∧ d.output = output ∧ d.tier = tier

instance (inputs : List Port) (output : Ty) (tier : ℤ) (d : CompDecl) :
    Decidable (modeAMatches inputs output tier d) := by
  unfold modeAMatches; infer_instance

/-! ## Mode fields (15:49) -/

/-- The mode fields of the checkpoint types (05:18-25). -/
inductive ModeField | lon | lat | turnSignal | accel | steer | pedal | wheel | gear
  deriving DecidableEq

def ModeField.all : List ModeField := [.lon, .lat, .turnSignal, .accel, .steer, .pedal, .wheel, .gear]

theorem ModeField.mem_all (f : ModeField) : f ∈ ModeField.all := by
  cases f <;> simp [ModeField.all]

/-- The enum of each mode field. -/
def ModeField.Val : ModeField → Type
  | .lon => LonMode | .lat => LatMode | .turnSignal => TurnSignal | .accel => AccelMode
  | .steer => SteerMode | .pedal => PedalMode | .wheel => WheelMode | .gear => GearMode

instance ModeField.decEq : (f : ModeField) → DecidableEq f.Val
  | .lon => inferInstanceAs (DecidableEq LonMode)
  | .lat => inferInstanceAs (DecidableEq LatMode)
  | .turnSignal => inferInstanceAs (DecidableEq TurnSignal)
  | .accel => inferInstanceAs (DecidableEq AccelMode)
  | .steer => inferInstanceAs (DecidableEq SteerMode)
  | .pedal => inferInstanceAs (DecidableEq PedalMode)
  | .wheel => inferInstanceAs (DecidableEq WheelMode)
  | .gear => inferInstanceAs (DecidableEq GearMode)

/-- The modes other than `NONE`, the only spellings a `modes` entry may use (15:49). -/
def ModeField.listed : (f : ModeField) → List f.Val
  | .lon => (ModeEnum.listed : List LonMode)
  | .lat => (ModeEnum.listed : List LatMode)
  | .turnSignal => (ModeEnum.listed : List TurnSignal)
  | .accel => (ModeEnum.listed : List AccelMode)
  | .steer => (ModeEnum.listed : List SteerMode)
  | .pedal => (ModeEnum.listed : List PedalMode)
  | .wheel => (ModeEnum.listed : List WheelMode)
  | .gear => (ModeEnum.listed : List GearMode)

/-- The baseline modes of 05:32. -/
def ModeField.isBaseline : (f : ModeField) → f.Val → Bool
  | .lon => LonMode.isBaseline
  | .lat => LatMode.isBaseline
  | .turnSignal => TurnSignal.isBaseline
  | .accel => AccelMode.isBaseline
  | .steer => SteerMode.isBaseline
  | .pedal => PedalMode.isBaseline
  | .wheel => WheelMode.isBaseline
  | .gear => GearMode.isBaseline

/-- A `modes` member: `none` for a field without an entry. -/
abbrev Modes := (f : ModeField) → Option (List f.Val)

/-- One entry: spelled with modes other than `NONE`, and including every baseline mode. -/
def entryOk (f : ModeField) : Option (List f.Val) → Prop
  | none => True
  | some xs => (∀ e ∈ xs, e ∈ f.listed) ∧ ∀ e ∈ f.listed, f.isBaseline e = true → e ∈ xs

instance (f : ModeField) (o : Option (List f.Val)) : Decidable (entryOk f o) := by
  cases o <;> unfold entryOk <;> infer_instance

def modesOk (ms : Modes) : Prop := ∀ f ∈ ModeField.all, entryOk f (ms f)

instance (ms : Modes) : Decidable (modesOk ms) := by unfold modesOk; infer_instance

/-- 15:49 'A field without an entry accepts every mode.' -/
def accepts (ms : Modes) (f : ModeField) (e : f.Val) : Prop :=
  e ∈ f.listed ∧ ∀ xs, ms f = some xs → e ∈ xs

/-! ## Parameters (15:48) -/

inductive PType | f64 | i64 | time | bool | enum (e : EnumTy) deriving DecidableEq

structure MParam where
  name : String
  ty : PType
  unit : String
  /-- The §12 `UnitExpr` parse of `unit`; `none` when it does not parse. -/
  unitExpr : Option UnitExpr
  /-- The exact value of the JSON number; `none` for `null`. -/
  default : Option ℚ

def MParam.mandatory (p : MParam) : Prop := p.default = none

/-- 15:48 '`unit` is a `UnitExpr` of §12, or `"1"` for dimensionless', and '`"1"` for
`i64`, `Bool`, and enum types, `"s"` for `Time`'. -/
def unitOk : PType → String → Option UnitExpr → Prop
  | .f64, s, u => u.isSome ∨ s = "1"
  | .time, s, _ => s = "s"
  | _, s, _ => s = "1"

instance (t : PType) (s : String) (u : Option UnitExpr) : Decidable (unitOk t s u) := by
  cases t <;> unfold unitOk <;> infer_instance

/-- A parameter value as the runtime passes it. -/
inductive PVal | f64 (x : ℝ) | i64 (z : ℤ) | time (ns : ℤ) | bool (b : Bool) | enum (n : ℕ)

def PVal.HasType : PVal → PType → Prop
  | .f64 _, .f64 | .i64 _, .i64 | .time _, .time | .bool _, .bool => True
  | .enum _, .enum _ => True
  | _, _ => False

/-- The SI factor of a parameter's unit; `"1"` has factor 1. -/
noncomputable def unitFactor : Option UnitExpr → ℝ
  | some u => u.factor
  | none => 1

/-- 15:48 'A `default` is written in `unit`, with `Time` in seconds, `Bool` as 0 or 1, and an
enum as its numeric value, and the compiler converts it like a call-site argument'.
`none` is a conversion error. Like a literal argument, an `i64` default must fit `Int`
(16:36) and a `Time` default must be whole nanoseconds in the `Int64` range (16:33, 15:48).
An enum default is accepted when it is a non-negative integer: this is the model's choice,
because the spec states no rule that the value name a member of the enum (spec gap). -/
noncomputable def convDefault : PType → Option UnitExpr → ℚ → Option PVal
  | .f64, u, q => some (.f64 ((q : ℝ) * unitFactor u))
  | .i64, _, q => if q.den = 1 ∧ inI64 q.num then some (.i64 q.num) else none
  | .time, _, q => (timeLitNs q).map .time
  | .bool, _, q => if q = 0 then some (.bool false) else if q = 1 then some (.bool true) else none
  | .enum _, _, q => if q.den = 1 ∧ 0 ≤ q.num then some (.enum q.num.toNat) else none

theorem convDefault_hasType {t : PType} {u : Option UnitExpr} {q : ℚ} {v : PVal}
    (h : convDefault t u q = some v) : v.HasType t := by
  cases t with
  | f64 => simp only [convDefault, Option.some.injEq] at h; subst h; trivial
  | i64 =>
    simp only [convDefault] at h
    split_ifs at h <;> cases h; trivial
  | time =>
    simp only [convDefault, Option.map_eq_some_iff] at h
    obtain ⟨_, _, rfl⟩ := h; trivial
  | bool =>
    simp only [convDefault] at h
    split_ifs at h <;> cases h <;> trivial
  | enum e =>
    simp only [convDefault] at h
    split_ifs at h <;> cases h; trivial

/-! ## Manifests (§15.3) -/

structure Manifest where
  abiVersion : String
  name : String
  stage : ℤ
  cardinality : Cardinality
  requiredTier : ℤ
  entity : Option Entity
  inputs : List Port
  output : Ty
  parameters : List MParam
  modes : Modes
  deckTypes : List String

/-- `DL_ABI_VERSION_0_20` (H:12). -/
def runtimeAbi : String := "0.20"

/-- The stage numbers of 00:38-41. -/
def stageNum : VehicleSpec.Stage → ℤ
  | .sensor => 0 | .intent => 1 | .control => 2 | .physics => 3

/-- 15:42 '`1`, `2`, or `3`. It must agree with `output`.' -/
def stageOk (stage : ℤ) (output : Ty) : Prop :=
  stage ∈ ({1, 2, 3} : Finset ℤ) ∧ output.stage.map stageNum = some stage

instance (stage : ℤ) (output : Ty) : Decidable (stageOk stage output) := by
  unfold stageOk; infer_instance

/-- 09:21 'a component parameter name longer than 55 bytes (`dl_param_t.name`)' is a
compile-time error. -/
def nameFits (s : String) : Prop := s.utf8ByteSize ≤ 55

/-- The rules of 15:40-50 for a manifest of component `file`, with 09:21. -/
def Manifest.valid (file : String) (m : Manifest) : Prop :=
  m.abiVersion = runtimeAbi ∧ m.name = file ∧ stageOk m.stage m.output ∧
  m.requiredTier ∈ ({0, 1, 2} : Finset ℤ) ∧ (m.entity ≠ none → m.stage = 3) ∧
  (m.entity = some .object → m.requiredTier = 0) ∧
  (∀ p ∈ m.parameters, unitOk p.ty p.unit p.unitExpr ∧ nameFits p.name ∧
    ∀ q ∈ p.default, (convDefault p.ty p.unitExpr q).isSome) ∧
  modesOk m.modes

/-- 15:45 'The default is `"vehicle"`': the kind of actor of a Stage 3 component. -/
def Manifest.effEntity (m : Manifest) : Option Entity :=
  if m.stage = 3 then some (m.entity.getD .vehicle) else none

/-! ## Call sites (§15.4) -/

/-- The DSL type a parameter expects (15:48, 16:18). -/
def PType.toTy : PType → Option UnitExpr → Ty
  | .f64, u => .qty ((u.map UnitExpr.dim).getD 0)
  | .i64, _ => .int
  | .time, _ => .time
  | .bool, _ => .bool
  | .enum e, _ => .enum e

/-- An argument fits its parameter; an `Int` fits a dimensionless quantity (16:35). -/
def argTyOk (p : MParam) (t : Ty) : Prop :=
  t = p.ty.toTy p.unitExpr ∨ (t = .int ∧ p.ty.toTy p.unitExpr = .qty 0)

instance (p : MParam) (t : Ty) : Decidable (argTyOk p t) := by
  unfold argTyOk; infer_instance

structure Arg where
  name : String
  ty : Ty

/-- 15:54 call-site check, with 16:75 (no duplicate named argument). -/
def callOk (ports : List String) (ps : List MParam) (args : List Arg) : Prop :=
  (args.map (·.name)).Nodup ∧ (∀ a ∈ args, a.name ∈ ports ∨ ∃ p ∈ ps, p.name = a.name) ∧
  (∀ p ∈ ps, p.default = none → ∃ a ∈ args, a.name = p.name) ∧
  (∀ a ∈ args, ∀ p ∈ ps, a.name = p.name → argTyOk p a.ty)

instance (ports : List String) (ps : List MParam) (args : List Arg) :
    Decidable (callOk ports ps args) := by
  unfold callOk; infer_instance

/-! ## `dl_param_t` (H:339-345) -/

/-- `dl_param_t` without `_pad`; `name` is checked by `nameFits`. -/
structure DlParam where
  name : String
  type : ℕ
  f64 : ℝ
  i64 : ℤ

/-- 15:54. The unused member is 0 (09:21 'every padding member' is zero; H:341 does not
name the unused value member). -/
def encode (n : String) : PVal → DlParam
  | .f64 x => ⟨n, 0, x, 0⟩
  | .i64 z => ⟨n, 1, 0, z⟩
  | .time z => ⟨n, 1, 0, z⟩
  | .bool b => ⟨n, 1, 0, if b then 1 else 0⟩
  | .enum k => ⟨n, 1, 0, k⟩

/-- The receiver's reading of an entry, given the type its own manifest declares. -/
def decode : PType → DlParam → PVal
  | .f64, d => .f64 d.f64
  | .i64, d => .i64 d.i64
  | .time, d => .time d.i64
  | .bool, d => .bool (d.i64 ≠ 0)
  | .enum _, d => .enum d.i64.toNat

/-- The value passed for parameter `p`: the argument if given, else the converted default. -/
noncomputable def paramVal (args : List (String × PVal)) (p : MParam) : Option PVal :=
  match args.lookup p.name with
  | some v => some v
  | none => p.default.bind (convDefault p.ty p.unitExpr)

/-- 15:54 'passes every parameter through `dl_set_parameters` … including those that take
their default'. -/
noncomputable def passAll (ps : List MParam) (args : List (String × PVal)) :
    Option (List DlParam) :=
  ps.mapM fun p => (paramVal args p).map (encode p.name)

/-! ## Theorems -/

/-- P15-01. 15:16-22 the signature source table: the `component` declaration for a
declared component and a Mode B FMU, `extra/org.driveline.dcm/manifest.json` for a Mode A
FMU, `<Name>.dcm.json` for a native library component, §17 for `std::...`. -/
theorem sigSource_table :
    sigSource .declared = .decl ∧ sigSource .modeB = .decl ∧
      sigSource .modeA = .fmuManifest ∧ sigSource .native = .dcmJson ∧
      sigSource .std = .stdlib := by
  decide

/-- P15-02. 15:24 'A component whose signature comes from its declaration is `OneToOne`,
reads no Tier 3 deck, and, if it is a Stage 3 component, is a vehicle physics
component'. -/
theorem declSig_oneToOne_no_deck (d : CompDecl) :
    (declSig d).card = .oneToOne ∧ (declSig d).decks = [] ∧
      (d.output.stage = some .physics → (declSig d).entity = some .vehicle) := by
  refine ⟨rfl, rfl, fun h => ?_⟩
  simp [declSig, h]

/-- P15-03. 15:24 'Every input port of a Mode B declaration must be a `SliceBuffer` … A
checkpoint input on a Mode B declaration is a compile-time error.' -/
theorem modeB_inputs_slice (d : CompDecl) (ok : d.clausesOk) (h : d.form = .modeB) :
    ∀ p ∈ d.inputs, (∃ s n, p.ty = .sliceBuf s n) ∧
      ∀ f, p.ty ≠ .frame f ∧ p.ty ≠ .kinState ∧ p.ty ≠ .lon f ∧ p.ty ≠ .lat f ∧
        p.ty ≠ .ovr f := by
  intro p hp
  obtain ⟨s, n, hs⟩ := ok.2.2 h p hp
  exact ⟨⟨s, n, hs⟩, fun f => by simp [hs]⟩

/-- P15-04. 15:26 'The declared ports, output type, and `required_tier` must equal the
manifest's. A mismatch is a compile-time error.' The check is decidable, and an omitted
declaration tier is 0 (16:91). -/
theorem modeA_match_decidable (m : Manifest) (d : CompDecl) :
    (decide (modeAMatches m.inputs m.output m.requiredTier d) = true ↔
      d.inputs = m.inputs ∧ d.output = m.output ∧ d.requiredTier.getD 0 = m.requiredTier) := by
  simp only [modeAMatches, CompDecl.tier]
  exact decide_eq_true_iff

/-- P15-05. 15:40 '`abi_version` … It must equal the runtime's ABI version, or the
reference is a compile-time error.' -/
theorem abi_version_eq (f : String) (m : Manifest) (h : m.valid f) :
    m.abiVersion = "0.20" :=
  h.1

/-- P15-06. 15:42 '`stage` … `1`, `2`, or `3`. It must agree with `output`.' The check is
decidable, and with the stage table 00:38-42 stage 3 means output `KinematicState`. -/
theorem stage_agrees_output (f : String) (m : Manifest) (h : m.valid f) :
    decide (stageOk m.stage m.output) = true ∧ m.stage ∈ ({1, 2, 3} : Finset ℤ) ∧
      (m.stage = 3 ↔ m.output = .kinState) := by
  obtain ⟨hs, hmap⟩ := h.2.2.1
  refine ⟨decide_eq_true h.2.2.1, hs, ?_⟩
  rw [← stage_physics_iff]
  cases ho : m.output.stage with
  | none => simp [ho] at hmap
  | some st =>
    simp only [ho, Option.map_some, Option.some.injEq] at hmap
    rw [← hmap]
    cases st <;> simp [stageNum]

/-- P15-07. 15:44 '`required_tier` … `0`, `1`, or `2`'. -/
theorem manifest_tier (f : String) (m : Manifest) (h : m.valid f) :
    m.requiredTier ∈ ({0, 1, 2} : Finset ℤ) :=
  h.2.2.2.1

/-- P15-08. 15:45 '`entity` … Optional, and allowed only in a Stage 3 manifest. The
default is `"vehicle"`. `"object"` requires `required_tier` 0.' -/
theorem entity_rules (f : String) (m : Manifest) (h : m.valid f) :
    (m.entity ≠ none → m.stage = 3) ∧ (m.entity = some .object → m.requiredTier = 0) ∧
      (m.stage = 3 → m.entity = none → m.effEntity = some .vehicle) :=
  ⟨h.2.2.2.2.1, h.2.2.2.2.2.1, fun h3 he => by simp [Manifest.effEntity, h3, he]⟩

/-- P15-09. 15:48 '"unit": string (`"1"` for `i64`, `Bool`, and enum types, `"s"` for
`Time`, and any other value a compile-time error for those types)'; for `f64`, '`unit` is
a `UnitExpr` of §12, or `"1"` for dimensionless'. -/
theorem unit_rules (s : String) (u : Option UnitExpr) (e : EnumTy) :
    (unitOk .time s u ↔ s = "s") ∧ (unitOk .i64 s u ↔ s = "1") ∧
      (unitOk .bool s u ↔ s = "1") ∧ (unitOk (.enum e) s u ↔ s = "1") ∧
      (unitOk .f64 s u ↔ u.isSome ∨ s = "1") ∧
      (∀ t, decide (unitOk t s u) = true ↔ unitOk t s u) := by
  refine ⟨Iff.rfl, Iff.rfl, Iff.rfl, Iff.rfl, Iff.rfl, fun t => decide_eq_true_iff⟩

/-- P15-10. 15:48 'A `null` default makes the parameter mandatory at the call site.' A
call that omits a parameter is accepted only if that parameter has a default. -/
theorem mandatory_iff_null (p : MParam) (ports : List String) (ps : List MParam)
    (args : List Arg) (hp : p ∈ ps) (ok : callOk ports ps args) :
    (p.mandatory ↔ p.default = none) ∧
      ((∀ a ∈ args, a.name ≠ p.name) → p.default ≠ none) := by
  refine ⟨Iff.rfl, fun hn hd => ?_⟩
  obtain ⟨a, ha, hname⟩ := ok.2.2.1 p hp hd
  exact hn a ha hname

/-- P15-11. 15:49 'A field without an entry accepts every mode. An entry must include the
field's baseline modes (§5), or the reference is a compile-time error', with the
baseline modes of 05:32. The check is decidable. -/
theorem baseline_modes_required (ms : Modes) (f : ModeField) (e : f.Val) (he : e ∈ f.listed) :
    (ms f = none → accepts ms f e) ∧
      (modesOk ms → f.isBaseline e = true → accepts ms f e) ∧
      (∀ xs, ms f = some xs → f.isBaseline e = true → e ∉ xs → ¬ modesOk ms) ∧
      (decide (modesOk ms) = true ↔ modesOk ms) := by
  refine ⟨fun h => ⟨he, by simp [h]⟩, fun ok hb => ⟨he, fun xs hx => ?_⟩,
    fun xs hx hb hn ok => ?_, decide_eq_true_iff⟩
  · have := ok f (ModeField.mem_all f)
    rw [hx] at this
    exact this.2 e he hb
  · have := ok f (ModeField.mem_all f)
    rw [hx] at this
    exact hn (this.2 e he hb)

/-- P15-12. 15:54 'At each call site, the compiler checks every named argument that is not
an input port against `parameters`. An unknown name, a missing mandatory parameter, or a
unit whose dimension differs from `unit` is a compile-time error.' The check is
decidable. -/
theorem call_site_errors (ports : List String) (ps : List MParam) (args : List Arg) :
    (decide (callOk ports ps args) = true ↔ callOk ports ps args) ∧
      (∀ a ∈ args, a.name ∉ ports → (∀ p ∈ ps, p.name ≠ a.name) → ¬ callOk ports ps args) ∧
      (∀ p ∈ ps, p.mandatory → (∀ a ∈ args, a.name ≠ p.name) → ¬ callOk ports ps args) ∧
      (∀ a ∈ args, ∀ p ∈ ps, a.name = p.name → p.ty = .f64 → ∀ d,
        a.ty = .qty d → d ≠ (p.unitExpr.map UnitExpr.dim).getD 0 → ¬ callOk ports ps args) := by
  refine ⟨decide_eq_true_iff, fun a ha hp hq ok => ?_, fun p hp hm hn ok => ?_,
    fun a ha p hp hn hf d hd hne ok => ?_⟩
  · rcases ok.2.1 a ha with h | ⟨p, hp', he⟩
    · exact hp h
    · exact hq p hp' he
  · obtain ⟨a, ha, he⟩ := ok.2.2.1 p hp hm
    exact hn a ha he
  · have := ok.2.2.2 a ha p hp hn
    simp only [argTyOk, hd, hf, PType.toTy] at this
    rcases this with h | ⟨h, _⟩
    · exact hne (Ty.qty.inj h)
    · cases h

theorem decode_encode {t : PType} {v : PVal} (hv : v.HasType t) (n : String) :
    decode t (encode n v) = v := by
  cases v <;> cases t <;> simp_all [PVal.HasType, encode, decode]

theorem encode_type {t : PType} {v : PVal} (hv : v.HasType t) (n : String) :
    (encode n v).type = 0 ↔ t = .f64 := by
  cases v <;> cases t <;> simp_all [PVal.HasType, encode]

theorem lookup_mem {args : List (String × PVal)} {n : String} {v : PVal}
    (h : args.lookup n = some v) : (n, v) ∈ args := by
  induction args with
  | nil => simp at h
  | cons a as ih =>
    obtain ⟨k, w⟩ := a
    by_cases hk : n = k
    · subst hk; simp [List.lookup] at h; simp [h]
    · have : (n == k) = false := by simpa using hk
      simp only [List.lookup, this] at h
      exact List.mem_cons_of_mem _ (ih h)

/-- P15-13. 15:54 'The runtime passes every parameter through `dl_set_parameters` in SI
units, including those that take their default … An `f64` parameter becomes `type = 0`
with the SI value. An `i64` parameter becomes `type = 1`. A `Time` parameter becomes
`type = 1` with the value in nanoseconds. A `Bool` parameter becomes `type = 1` with 0 or
1, and an enum parameter becomes `type = 1` with the enum's numeric value.'
The tag alone does not tell `i64`, `Time`, `Bool`, and enum apart; the receiver knows
each parameter's declared type from its own manifest (15:48), and given that type every
value round-trips. For a valid manifest (names of at most 55 bytes, 09:21) and arguments
of their parameters' types, every parameter is passed, in manifest order, once each
mandatory one has an argument: each entry has `type = 0` exactly for `f64` and decodes to
the value passed, the argument or the converted default. Defaults arrive in SI units, a
`Time` default in nanoseconds, and an `i64` or `Time` default in the `Int64` range
(16:33, 16:36). -/
theorem params_round_trip (t : PType) (v : PVal) (hv : v.HasType t) (n : String)
    (f : String) (m : Manifest) (h : m.valid f) (args : List (String × PVal))
    (hargs : ∀ p ∈ m.parameters, p.mandatory → (args.lookup p.name).isSome)
    (htys : ∀ p ∈ m.parameters, ∀ w, (p.name, w) ∈ args → w.HasType p.ty) :
    (decode t (encode n v) = v ∧ (encode n v).name = n ∧
      ((encode n v).type = 0 ↔ t = .f64)) ∧
    (∀ u q, convDefault .f64 u q = some (.f64 ((q : ℝ) * unitFactor u))) ∧
    (∀ u q z, convDefault .time u q = some (.time z) ↔ q * 10 ^ 9 = z ∧ inI64 z) ∧
    (∀ u q z, convDefault .i64 u q = some (.i64 z) ↔ q = z ∧ inI64 z) ∧
    ∃ ds, passAll m.parameters args = some ds ∧
      List.Forall₂ (fun p d => d.name = p.name ∧ nameFits d.name ∧
        (d.type = 0 ↔ p.ty = .f64) ∧ paramVal args p = some (decode p.ty d) ∧
        (args.lookup p.name = none → (p.ty = .i64 ∨ p.ty = .time) → inI64 d.i64))
        m.parameters ds := by
  refine ⟨⟨decode_encode hv n, ?_, ?_⟩, fun _ _ => rfl, fun u q z => ?_, fun u q z => ?_, ?_⟩
  · cases v <;> rfl
  · exact encode_type hv n
  · simp only [convDefault, Option.map_eq_some_iff, PVal.time.injEq, exists_eq_right]
    exact timeLitNs_spec q z
  · simp only [convDefault]
    split_ifs with hd
    · simp only [Option.some.injEq, PVal.i64.injEq]
      constructor
      · rintro rfl; exact ⟨(Rat.coe_int_num_of_den_eq_one hd.1).symm, hd.2⟩
      · rintro ⟨rfl, _⟩; simp
    · simp only [false_iff]
      rintro ⟨rfl, hz⟩
      exact hd ⟨by simp, by simpa using hz⟩
  · have hps := h.2.2.2.2.2.2.1
    clear h hv
    generalize m.parameters = ps at hps hargs htys ⊢
    induction ps with
    | nil => exact ⟨[], rfl, .nil⟩
    | cons p ps ih =>
      have hp := hps p (by simp)
      obtain ⟨ds, hds, hall⟩ :=
        ih (fun q hq => hps q (by simp [hq])) (fun q hq => hargs q (by simp [hq]))
          (fun q hq => htys q (by simp [hq]))
      have : ∃ v, paramVal args p = some v ∧ v.HasType p.ty ∧
          (args.lookup p.name = none → (p.ty = .i64 ∨ p.ty = .time) →
            inI64 (encode p.name v).i64) := by
        unfold paramVal
        cases hl : args.lookup p.name with
        | some v => exact ⟨v, rfl, htys p (by simp) v (lookup_mem hl), by simp⟩
        | none =>
          cases hd : p.default with
          | none =>
            have := hargs p (by simp) hd
            simp [hl] at this
          | some q =>
            have := hp.2.2 q (by simp [hd])
            obtain ⟨v, hv⟩ := Option.isSome_iff_exists.1 this
            refine ⟨v, by simp [hv], convDefault_hasType hv, fun _ ht => ?_⟩
            rcases ht with ht | ht <;> rw [ht] at hv
            · simp only [convDefault] at hv
              split_ifs at hv with hc
              cases hv; exact hc.2
            · simp only [convDefault, Option.map_eq_some_iff] at hv
              obtain ⟨z, hz, rfl⟩ := hv
              exact ((timeLitNs_spec q z).1 hz).2
      obtain ⟨v, hv, hty, hr⟩ := this
      refine ⟨encode p.name v :: ds, ?_, .cons ⟨?_, ?_, ?_, ?_, hr⟩ hall⟩
      · simp [passAll] at hds ⊢
        simp [hv, hds]
      · cases v <;> rfl
      · cases v <;> exact hp.2.1
      · exact encode_type hty _
      · rw [decode_encode hty, hv]

end Driveline.Manifest
