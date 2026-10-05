import Mathlib.Basic.Real.Basic
import Mathlib.Data.Finset.Basic
import Mathlib.Data.Nat.Bitwise
import Mathlib.Tactic

/-!
# Vehicle and object spec encoding (spec §3)

The `vehicle_spec` and `object_spec` of `docs/spec/03-vehicle-parameters.md`,
their keys (`16-static-semantics.md:102-105`), and their runtime encoding as
`dl_vehicle_spec_t` (`abi/driveline_abi.h:28-91`, 03:36, 03:44). Also the stage
and port rules of `00-conformance.md:33-43` that the tier rules rely on.

Values are real numbers. The binary64 evaluation of the invariant tolerance
(03:31) and the `uri` path resolution (03:36, §19.2) are out of scope.
-/

noncomputable section

namespace Driveline.VehicleSpec

section Types

/-! ## Frame and port types (00:33-43, 16:26-27) -/

/-- The unwrapped port and output types that stages and arbiters name. -/
inductive Base | sliceBuffer | intent | kcf | acf | kinematicState | other (n : ℕ)
  deriving DecidableEq, Repr

/-- A type `T`, `Lon<T>`, `Lat<T>`, or `Override<T>`. -/
inductive FrameType | whole (b : Base) | lon (b : Base) | lat (b : Base) | override (b : Base)
  deriving DecidableEq, Repr

def FrameType.root : FrameType → Base | .whole b | .lon b | .lat b | .override b => b

/-- 16:26-27: `Lon`/`Lat` over {IntentFrame, KCF}; `Override` over the three frames. -/
def FrameType.WF : FrameType → Prop
  | .whole _ => True
  | .lon b | .lat b => b = .intent ∨ b = .kcf
  | .override b => b = .intent ∨ b = .kcf ∨ b = .acf

inductive PortType | frame (t : FrameType) | openDriveMap | frictionField | other (n : ℕ)
inductive PortName | primary | secondary | named (n : ℕ) deriving DecidableEq
structure Sig where
  inputs : List (PortName × FrameType)
  output : FrameType

/-- 00:38-41: Sensor (Stage 0), Intent (Stage 1), Control (Stage 2), Physics (Stage 3). -/
inductive Stage | sensor | intent | control | physics deriving DecidableEq, Repr

/-- The stage table of 00:38-42. 00:38 'Projects World state into a `SliceBuffer`';
00:39 'Output `IntentFrame`, `Lon<IntentFrame>`, or `Lat<IntentFrame>`'; 00:40 'Output
`KinematicControlFrame`, `ActuatorControlFrame`, `Lon<KinematicControlFrame>`, or
`Lat<KinematicControlFrame>`'; 00:41 'Output `KinematicState`'; 00:42 'An output
`Override<T>` has the stage of `T`'. -/
def stage : FrameType → Option Stage
  | .whole .sliceBuffer => some .sensor
  | .whole .intent | .lon .intent | .lat .intent => some .intent
  | .whole .kcf | .whole .acf | .lon .kcf | .lat .kcf => some .control
  | .whole .kinematicState => some .physics
  | .override .sliceBuffer => some .sensor
  | .override .intent => some .intent
  | .override .kcf | .override .acf => some .control
  | .override .kinematicState => some .physics
  | _ => none

/-- 00:42 'An output `Override<T>` has the stage of `T`'. -/
theorem stage_override (b : Base) : stage (.override b) = stage (.whole b) := by
  cases b <;> rfl

/-- 00:39-40: `Lon<T>` is listed in the stage of `T`, for the `T` it may wrap. -/
theorem stage_lon (b : Base) (h : (FrameType.lon b).WF) : stage (.lon b) = stage (.whole b) := by
  rcases h with rfl | rfl <;> rfl

/-- 00:39-40: `Lat<T>` is listed in the stage of `T`, for the `T` it may wrap. -/
theorem stage_lat (b : Base) (h : (FrameType.lat b).WF) : stage (.lat b) = stage (.whole b) := by
  rcases h with rfl | rfl <;> rfl

/-- 00:37 'Its stage follows from its output type': every well-formed output type
built on a named frame type has a stage. -/
theorem stage_total (t : FrameType) (h : t.WF) (hb : ∀ n, t.root ≠ .other n) :
    (stage t).isSome := by
  rcases t with b | b | b | b <;> simp only [FrameType.root] at hb
  · cases b <;> first | rfl | exact absurd rfl (hb _)
  · rcases h with rfl | rfl <;> rfl
  · rcases h with rfl | rfl <;> rfl
  · rcases h with rfl | rfl | rfl <;> rfl

/-- P00-02. 00:37 'Its stage follows from its output type'; 00:42 'An output
`Override<T>` has the stage of `T`'; 00:39-40 list `Lon<T>` and `Lat<T>` in the stage
of `T`. -/
theorem stage_rules :
    (∀ t : FrameType, t.WF → (∀ n, t.root ≠ .other n) → (stage t).isSome) ∧
    (∀ b, stage (.override b) = stage (.whole b)) ∧
    (∀ b, (FrameType.lon b).WF → stage (.lon b) = stage (.whole b)) ∧
    (∀ b, (FrameType.lat b).WF → stage (.lat b) = stage (.whole b)) :=
  ⟨stage_total, stage_override, stage_lon, stage_lat⟩

/-- 00:43: the arbiter signature over `T`. -/
def arbiterSig (b : Base) : Sig :=
  ⟨[(.primary, .whole b), (.secondary, .override b)], .whole b⟩

/-- 00:43 'exactly the input ports `primary` of type `T` and `secondary` of type
`Override<T>`, and output type `T`, where `T` is `IntentFrame`,
`KinematicControlFrame`, or `ActuatorControlFrame`'. -/
def isArbiter (s : Sig) : Prop := ∃ b, (b = .intent ∨ b = .kcf ∨ b = .acf) ∧ s = arbiterSig b

/-- 00:43 'Its stage is the stage of `T`', which agrees with 00:37. -/
theorem arbiter_stage_eq (s : Sig) (h : isArbiter s) :
    ∃ b, stage s.output = stage (.whole b) ∧ (PortName.secondary, FrameType.override b) ∈ s.inputs ∧
      (stage s.output).isSome := by
  obtain ⟨b, hb, rfl⟩ := h
  refine ⟨b, rfl, by simp [arbiterSig], ?_⟩
  rcases hb with rfl | rfl | rfl <;> rfl

theorem arbiter_not_other (n : ℕ) : ¬ isArbiter (arbiterSig (.other n)) := by
  rintro ⟨b, hb, h⟩
  have : Base.other n = b := by simpa [arbiterSig] using congrArg Sig.output h
  subst this
  simp at hb

/-- P00-03. 00:43 'A component with exactly the input ports `primary` of type `T` and
`secondary` of type `Override<T>`, and output type `T`, where `T` is `IntentFrame`,
`KinematicControlFrame`, or `ActuatorControlFrame` ... Its stage is the stage of `T`'. -/
theorem arbiter_stage :
    (∀ s, isArbiter s → ∃ b, stage s.output = stage (.whole b) ∧
      (PortName.secondary, FrameType.override b) ∈ s.inputs ∧ (stage s.output).isSome) ∧
    (∀ n, ¬ isArbiter (arbiterSig (.other n))) :=
  ⟨arbiter_stage_eq, arbiter_not_other⟩

/-! ## Actors and ports (00:33-34) -/

/-- An actor: `comps` lists its components, `true` for a physics component. -/
structure Actor where
  isStatic : Bool
  sensors : List ℕ
  priors : List ℕ
  comps : List Bool

/-- 00:34 'exactly one physics component, except a static actor, which `place` creates
and which has no sensors, priors, or components'. -/
def Actor.WF (a : Actor) : Prop :=
  (a.isStatic = true → a.sensors = [] ∧ a.priors = [] ∧ a.comps = []) ∧
    (a.isStatic = false → a.comps.count true = 1)

/-- P00-04. 00:34 'exactly one physics component, except a static actor ... which has no
sensors, priors, or components'. -/
theorem static_no_physics (a : Actor) (h : a.WF) (hs : a.isStatic = true) :
    a.comps.count true = 0 := by
  simp [(h.1 hs).2.2]

/-- 00:33 'World-truth types: `OpenDriveMap` ... and `FrictionField`'. -/
def worldTruth : PortType → Prop
  | .openDriveMap | .frictionField => True
  | _ => False

/-- 00:33: the component port types of a program, none of world-truth type. -/
def Program.WF (ports : List PortType) : Prop := ∀ p ∈ ports, ¬ worldTruth p

/-- P00-05. 00:33 'Passing a value of a world-truth type to a component port is a
compile-time error'. -/
theorem reject_world_truth :
    (∀ t : FrameType, ¬ worldTruth (.frame t)) ∧
    ∀ ps, Program.WF ps → PortType.openDriveMap ∉ ps ∧ PortType.frictionField ∉ ps := by
  refine ⟨fun _ h => h, fun ps h => ⟨fun hm => h _ hm trivial, fun hm => h _ hm trivial⟩⟩

end Types

section Spec

/-! ## Tolerance (03:31) -/

/-- 03:31 'holds when |a - b| <= 10^-6 * max(|a|, |b|, 1)', over ℝ. -/
def approxEq (a b : ℝ) : Prop := |a - b| ≤ (1 / 10 ^ 6 : ℝ) * max (max |a| |b|) 1

theorem approxEq_symm (a b : ℝ) : approxEq a b ↔ approxEq b a := by
  simp only [approxEq, abs_sub_comm a b, max_comm |a| |b|]

theorem approxEq_of_small (a b : ℝ) (h : |a - b| ≤ 1 / 10 ^ 6) : approxEq a b := by
  unfold approxEq
  calc |a - b| ≤ (1 / 10 ^ 6 : ℝ) * 1 := by simpa using h
    _ ≤ _ := by gcongr; exact le_max_right _ _

theorem approxEq_of_eq (a b : ℝ) (h : a = b) : approxEq a b :=
  approxEq_of_small a b (by simp [h])

/-! ## Spec records (abi:32-81, 16:102-105) -/

/-- abi:32-39, `dl_kinematic_params_t`. -/
structure Tier0 where
  bbox_length : ℝ := 0
  bbox_width : ℝ := 0
  bbox_height : ℝ := 0
  wheelbase : ℝ := 0
  overhang_front : ℝ := 0
  overhang_rear : ℝ := 0
  max_steer_angle : ℝ := 0
  max_steer_rate : ℝ := 0
  steering_ratio : ℝ := 0

/-- abi:41-50, `dl_single_track_params_t`. -/
structure Tier1 where
  mass : ℝ := 0
  cg_dist_front : ℝ := 0
  cg_dist_rear : ℝ := 0
  cg_height : ℝ := 0
  inertia_zz : ℝ := 0
  cornering_stiffness_f : ℝ := 0
  cornering_stiffness_r : ℝ := 0
  aero_cd : ℝ := 0
  aero_area : ℝ := 0
  rolling_resistance_coeff : ℝ := 0

/-- abi:52-68, the scalar members of `dl_multibody_params_t`. -/
structure Tier2Core where
  sprung_mass : ℝ := 0
  unsprung_mass_f : ℝ := 0
  unsprung_mass_r : ℝ := 0
  inertia_xx : ℝ := 0
  inertia_yy : ℝ := 0
  inertia_xz : ℝ := 0
  track_width_f : ℝ := 0
  track_width_r : ℝ := 0
  susp_stiffness_f : ℝ := 0
  susp_stiffness_r : ℝ := 0
  susp_damping_f : ℝ := 0
  susp_damping_r : ℝ := 0
  arb_stiffness_f : ℝ := 0
  arb_stiffness_r : ℝ := 0
  tire_effective_radius : ℝ := 0
  wheel_polar_inertia : ℝ := 0
  max_drive_torque : ℝ := 0
  max_brake_torque : ℝ := 0
  final_drive_ratio : ℝ := 0
  reverse_gear_ratio : ℝ := 0

/-- 16:104: the DSL record. `num_gears` is excluded and `gear_ratios` is an array. -/
structure Tier2Dsl extends Tier2Core where
  gear_ratios : List ℝ

/-- abi:52-68, `dl_multibody_params_t`. -/
structure Tier2Abi extends Tier2Core where
  gear_ratios : Fin 10 → ℝ := fun _ => 0
  num_gears : ℕ := 0

/-- abi:71 '0:NONE, 1:PACEJKA_TIR, 2:SOLVER_URI'. -/
inductive DeckType | none | pacejkaTir | solverUri deriving DecidableEq, Repr
/-- abi:72 '0:SUPPLEMENT_ONLY, 1:OVERRIDE_TIER1_2'. -/
inductive Precedence | supplementOnly | overrideTier12 deriving DecidableEq, Repr

def DeckType.toNat : DeckType → ℕ | .none => 0 | .pacejkaTir => 1 | .solverUri => 2
def DeckType.ofNat? : ℕ → Option DeckType
  | 0 => some .none | 1 => some .pacejkaTir | 2 => some .solverUri | _ => Option.none
def Precedence.toNat : Precedence → ℕ | .supplementOnly => 0 | .overrideTier12 => 1
def Precedence.ofNat? : ℕ → Option Precedence
  | 0 => some .supplementOnly | 1 => some .overrideTier12 | _ => none

/-- 16:105. `uri` is the byte string after the resolution of 03:36. -/
structure Tier3Dsl where
  kind : DeckType
  prec : Precedence
  uri : List UInt8

/-- abi:70-76, `dl_custom_deck_t`. -/
structure Tier3Abi where
  deck_type : ℕ := 0
  precedence_mode : ℕ := 0
  uri : Fin 256 → UInt8 := fun _ => 0

/-- abi:78-81, `dl_object_params_t`. -/
structure ObjectParams where
  v_max : ℝ := 0
  a_max : ℝ := 0

/-- 16:22 `ObjectClass`. -/
inductive ObjectClass | unknown | car | truck | pedestrian | cyclist | motorcycle | animal | static
  deriving DecidableEq, Repr

/-- 16:22 'UNKNOWN = 0, CAR = 1, TRUCK = 2, PEDESTRIAN = 3, CYCLIST = 4, MOTORCYCLE = 5,
ANIMAL = 6, STATIC = 7'. -/
def ObjectClass.toNat : ObjectClass → ℕ
  | .unknown => 0 | .car => 1 | .truck => 2 | .pedestrian => 3
  | .cyclist => 4 | .motorcycle => 5 | .animal => 6 | .static => 7

/-- 03:14 '`CAR` (the default), `TRUCK`, `CYCLIST`, or `MOTORCYCLE`'. -/
inductive VehicleClass | car | truck | cyclist | motorcycle deriving DecidableEq
/-- 03:40 '`PEDESTRIAN`, `ANIMAL`, `UNKNOWN`, or `STATIC`'. -/
inductive ObjClass | pedestrian | animal | unknown | static deriving DecidableEq

instance : Fintype VehicleClass :=
  ⟨{.car, .truck, .cyclist, .motorcycle}, fun x => by cases x <;> decide⟩
instance : Fintype ObjClass :=
  ⟨{.pedestrian, .animal, .unknown, .static}, fun x => by cases x <;> decide⟩

def VehicleClass.toClass : VehicleClass → ObjectClass
  | .car => .car | .truck => .truck | .cyclist => .cyclist | .motorcycle => .motorcycle
def ObjClass.toClass : ObjClass → ObjectClass
  | .pedestrian => .pedestrian | .animal => .animal | .unknown => .unknown | .static => .static

/-- 16:102: `tier0` is required, the other tiers are optional, and `class` is `CAR`
when absent. -/
structure VSpec where
  cls : VehicleClass := .car
  tier0 : Tier0
  tier1 : Option Tier1 := none
  tier2 : Option Tier2Dsl := none
  tier3 : Option Tier3Dsl := none

/-- 16:103. -/
structure OSpec where
  cls : ObjClass
  length : ℝ
  width : ℝ
  height : ℝ
  v_max : ℝ
  a_max : ℝ

inductive Spec | vehicle (s : VSpec) | object (o : OSpec)

/-- abi:83-91, `dl_vehicle_spec_t`. -/
structure AbiSpec where
  mask : ℕ
  object_class : ℕ
  tier0 : Tier0 := {}
  tier1 : Tier1 := {}
  tier2 : Tier2Abi := {}
  tier3 : Tier3Abi := {}
  object : ObjectParams := {}

/-- Whether Tier `k` is populated. An object has Tier 0 only (03:42 'An object has no
Tier 1, 2, or 3'). -/
def populated : Spec → ℕ → Bool
  | .vehicle _, 0 => true
  | .vehicle s, 1 => s.tier1.isSome
  | .vehicle s, 2 => s.tier2.isSome
  | .vehicle s, 3 => s.tier3.isSome
  | .object _, 0 => true
  | _, _ => false

def bitIf (b : Bool) (k : ℕ) : ℕ := if b then 2 ^ k else 0

/-- The vehicle mask from the populated flags of Tiers 1-3. -/
def maskOf (b1 b2 b3 : Bool) : ℕ := 1 + bitIf b1 1 + bitIf b2 2 + bitIf b3 3

def encodeTier2 (t : Tier2Dsl) : Tier2Abi :=
  { t.toTier2Core with
    gear_ratios := fun i => t.gear_ratios.getD i 0
    num_gears := t.gear_ratios.length }

def encodeDeck (d : Tier3Dsl) : Tier3Abi :=
  { deck_type := d.kind.toNat, precedence_mode := d.prec.toNat, uri := fun i => d.uri.getD i 0 }

/-- 03:36, the runtime encoding of a `vehicle_spec`. -/
def encodeV (s : VSpec) : AbiSpec :=
  { mask := maskOf s.tier1.isSome s.tier2.isSome s.tier3.isSome
    object_class := s.cls.toClass.toNat
    tier0 := s.tier0
    tier1 := s.tier1.getD {}
    tier2 := (s.tier2.map encodeTier2).getD {}
    tier3 := (s.tier3.map encodeDeck).getD {} }

/-- 03:42 item 1: 'L = 0, o_f = o_r = length / 2, L_bbox = length, W_bbox = width,
H_bbox = height, and delta_max = delta_dot_max = i_s = 0'. -/
def objectTier0 (o : OSpec) : Tier0 :=
  { bbox_length := o.length, bbox_width := o.width, bbox_height := o.height,
    overhang_front := o.length / 2, overhang_rear := o.length / 2 }

/-- 03:44, the runtime encoding of an `object_spec`. -/
def encodeO (o : OSpec) : AbiSpec :=
  { mask := 0x11, object_class := o.cls.toClass.toNat, tier0 := objectTier0 o,
    object := ⟨o.v_max, o.a_max⟩ }

def encode : Spec → AbiSpec | .vehicle s => encodeV s | .object o => encodeO o

/-- 03:20 'Invariant: L_bbox == L + o_f + o_r'. -/
def Tier0.inv (t : Tier0) : Prop :=
  approxEq t.bbox_length (t.wheelbase + t.overhang_front + t.overhang_rear)

/-- Compile-time acceptance of a `vehicle_spec`: 03:20-22 invariants under 03:31,
03:22 'i_R > 0', 16:102 'tier2 requires tier1, and tier3 requires tier1', 16:104
'`gear_ratios` is an array literal of 1 to 10 dimensionless values', 16:105
'`deck_type` (`"PACEJKA_TIR"` or `"SOLVER_URI"`)', and 03:36 'A value longer than
255 bytes ... is a compile-time error'. -/
def VSpec.WF (s : VSpec) : Prop :=
  s.tier0.inv ∧
  (∀ t1 ∈ s.tier1, approxEq (t1.cg_dist_front + t1.cg_dist_rear) s.tier0.wheelbase) ∧
  (∀ t2 ∈ s.tier2, (∃ t1 ∈ s.tier1,
      approxEq (t2.sprung_mass + t2.unsprung_mass_f + t2.unsprung_mass_r) t1.mass) ∧
    0 < t2.reverse_gear_ratio ∧ 1 ≤ t2.gear_ratios.length ∧ t2.gear_ratios.length ≤ 10) ∧
  (∀ d ∈ s.tier3, s.tier1.isSome ∧ d.kind ≠ .none ∧ d.uri.length ≤ 255)

/-- 03:40 and 16:103 'each value above zero'. -/
def OSpec.WF (o : OSpec) : Prop :=
  0 < o.length ∧ 0 < o.width ∧ 0 < o.height ∧ 0 < o.v_max ∧ 0 < o.a_max

/-- The body-frame x range of the box, 03:20 'x in [-o_r, L + o_f]'. -/
def boxX (t : Tier0) : ℝ × ℝ := (-t.overhang_rear, t.wheelbase + t.overhang_front)
/-- The body-frame y range of the box, 03:20 'y in [-W_bbox/2, W_bbox/2]'. -/
def boxY (t : Tier0) : ℝ × ℝ := (-t.bbox_width / 2, t.bbox_width / 2)

/-! ## Reference origin and CG (02:19) -/

/-- 02:19: under the tolerance of 03:31 the two placements of the CG differ by at most
the tolerance. -/
theorem cg_readings_close (L lf lr : ℝ) (h : approxEq (lf + lr) L) :
    |lr - (L - lf)| ≤ (1 / 10 ^ 6 : ℝ) * max (max |lf + lr| |L|) 1 := by
  have : lr - (L - lf) = lf + lr - L := by ring
  rw [this]; exact h

/-- The tier 0 and 1 values of the CG witness: L = 3, o_f = o_r = 1, L_bbox = 5,
l_f = 3/2, l_r = 3/2 + 10^-7. -/
def cgWitness : VSpec :=
  { tier0 := { bbox_length := 5, wheelbase := 3, overhang_front := 1, overhang_rear := 1 }
    tier1 := some { mass := 1500, cg_dist_front := 3 / 2, cg_dist_rear := 3 / 2 + 1 / 10 ^ 7 } }

/-- P02-09, refuted. 02:19 'The Center of Gravity (CG) is located at longitudinal
distance l_r forward of the rear axle, l_f behind the front axle'. A spec accepted under
03:31 has l_f + l_r only within tolerance of L, so no CG position satisfies both
readings. -/
theorem cg_readings_disagree : ∃ s : VSpec, s.WF ∧ ∃ t1 ∈ s.tier1,
    ¬ ∃ cgX : ℝ, cgX = t1.cg_dist_rear ∧ s.tier0.wheelbase - cgX = t1.cg_dist_front := by
  refine ⟨cgWitness, ⟨?_, ?_, ?_, ?_⟩, _, rfl, ?_⟩
  · exact approxEq_of_eq _ _ (by simp [cgWitness]; norm_num)
  · rintro t1 ⟨⟩
    apply approxEq_of_small
    simp only [cgWitness]
    rw [show (3 / 2 + (3 / 2 + 1 / 10 ^ 7) - 3 : ℝ) = 1 / 10 ^ 7 by norm_num,
      abs_of_pos (by norm_num)]
    norm_num
  · rintro t2 h; simp [cgWitness] at h
  · rintro d h; simp [cgWitness] at h
  · rintro ⟨cgX, rfl, h⟩
    simp only [cgWitness] at h
    norm_num at h

/-- P02-10. 02:19 'For an object actor ..., the reference origin is the center of its
box's footprint on the ground plane'. With the values of 03:42 the footprint is centred
on the origin. -/
theorem object_origin_centred (o : OSpec) :
    boxX (objectTier0 o) = (-o.length / 2, o.length / 2) ∧
    (boxX (objectTier0 o)).1 + (boxX (objectTier0 o)).2 = 0 ∧
    (boxY (objectTier0 o)).1 + (boxY (objectTier0 o)).2 = 0 := by
  simp only [boxX, boxY, objectTier0]
  refine ⟨Prod.ext (by ring) (by ring), by ring, by ring⟩

/-! ## Populated tiers mask (03:12, 03:36, 03:44) -/

/-- 03:12: the masks that respect the tier requirements. -/
def validVehicleMask (m : ℕ) : Prop :=
  m < 16 ∧ m.testBit 0 = true ∧ (m.testBit 2 = true → m.testBit 1 = true) ∧
    (m.testBit 3 = true → m.testBit 1 = true)

instance (m : ℕ) : Decidable (validVehicleMask m) := by
  unfold validVehicleMask; infer_instance

theorem validVehicleMask_iff_mem (m : ℕ) :
    validVehicleMask m ↔ m ∈ ({1, 3, 7, 11, 15} : Finset ℕ) := by
  by_cases hm : m < 16
  · have key : ∀ k : Fin 16, validVehicleMask k ↔ (k : ℕ) ∈ ({1, 3, 7, 11, 15} : Finset ℕ) := by
      decide
    exact key ⟨m, hm⟩
  · constructor
    · intro h; exact absurd h.1 hm
    · intro h; simp at h; omega

theorem maskOf_bits (b1 b2 b3 : Bool) :
    (maskOf b1 b2 b3).testBit 0 = true ∧ (maskOf b1 b2 b3).testBit 1 = b1 ∧
    (maskOf b1 b2 b3).testBit 2 = b2 ∧ (maskOf b1 b2 b3).testBit 3 = b3 ∧
    (maskOf b1 b2 b3).testBit 4 = false ∧ maskOf b1 b2 b3 < 16 ∧
    maskOf b1 b2 b3 &&& 16 = 0 := by
  cases b1 <;> cases b2 <;> cases b3 <;> decide

theorem encodeV_mask_valid (s : VSpec) (h : s.WF) : validVehicleMask (encodeV s).mask := by
  have h2 : s.tier2.isSome = true → s.tier1.isSome = true := by
    intro hs
    obtain ⟨t2, ht2⟩ := Option.isSome_iff_exists.mp hs
    obtain ⟨t1, ht1, -⟩ := (h.2.2.1 t2 ht2).1
    rw [Option.mem_def.mp ht1]; rfl
  have h3 : s.tier3.isSome = true → s.tier1.isSome = true := by
    intro hs
    obtain ⟨d, hd⟩ := Option.isSome_iff_exists.mp hs
    exact (h.2.2.2 d hd).1
  obtain ⟨b0, b1, b2, b3, -, hlt, -⟩ := maskOf_bits s.tier1.isSome s.tier2.isSome s.tier3.isSome
  show validVehicleMask (maskOf _ _ _)
  exact ⟨hlt, b0, by rw [b2, b1]; exact h2, by rw [b3, b1]; exact h3⟩

/-- P03-01. 03:12 'Tier 2 requires Tiers 0 and 1; Tier 1 requires Tier 0). Tier 3 requires
Tier 1, and so Tier 0'. -/
theorem vehicle_mask_tier_closure :
    (∀ m, validVehicleMask m ↔ m ∈ ({1, 3, 7, 11, 15} : Finset ℕ)) ∧
    ∀ s : VSpec, s.WF → validVehicleMask (encodeV s).mask :=
  ⟨validVehicleMask_iff_mem, encodeV_mask_valid⟩

/-- P03-02. 03:36 'Bit k of `populated_tiers_mask`, for k from 0 to 3, is set if and only
if Tier k is populated, and bit 4 is clear'. -/
theorem mask_bit_iff (s : VSpec) :
    (∀ k < 4, (encodeV s).mask.testBit k = populated (.vehicle s) k) ∧
    (encodeV s).mask &&& 16 = 0 ∧ (encodeV s).mask < 2 ^ 32 := by
  obtain ⟨b0, b1, b2, b3, -, hlt, hand⟩ :=
    maskOf_bits s.tier1.isSome s.tier2.isSome s.tier3.isSome
  refine ⟨fun k hk => ?_, hand, by simp only [encodeV]; omega⟩
  interval_cases k <;> simp [encodeV, populated, b0, b1, b2, b3]

theorem encodeO_mask_ne (o : OSpec) :
    (encodeO o).mask = 0x11 ∧ ¬ validVehicleMask 0x11 ∧ ∀ s, (encodeV s).mask ≠ (encodeO o).mask := by
  refine ⟨rfl, by decide, fun s h => ?_⟩
  have := (maskOf_bits s.tier1.isSome s.tier2.isSome s.tier3.isSome).2.2.2.2.2.1
  simp only [encodeV, encodeO] at h
  omega

theorem object_iff_bit4 (x : Spec) : (encode x).mask.testBit 4 = true ↔ ∃ o, x = .object o := by
  cases x with
  | vehicle s =>
    simp [encode, encodeV, (maskOf_bits s.tier1.isSome s.tier2.isSome s.tier3.isSome).2.2.2.2.1]
  | object o => simp [encode, encodeO]; decide

theorem object_mask_bits (o : OSpec) (k : ℕ) (hk : k < 4) :
    (encodeO o).mask.testBit k = populated (.object o) k := by
  interval_cases k <;> simp [encodeO, populated] <;> decide

/-- P03-03. 03:44 'The runtime passes an `object_spec` as `dl_vehicle_spec_t` with bits 0
and 4 of `populated_tiers_mask` set'. -/
theorem object_mask (o : OSpec) :
    ((encodeO o).mask = 0x11 ∧ ¬ validVehicleMask 0x11 ∧
      ∀ s, (encodeV s).mask ≠ (encodeO o).mask) ∧
    (∀ x, (encode x).mask.testBit 4 = true ↔ ∃ o, x = .object o) ∧
    ∀ k < 4, (encodeO o).mask.testBit k = populated (.object o) k :=
  ⟨encodeO_mask_ne o, object_iff_bit4, object_mask_bits o⟩

/-- P03-04. 03:36 'Every field of an unpopulated tier is zero, and so is `object`'; 03:44
'and every other field zero'. -/
theorem unpopulated_zero :
    (∀ s : VSpec, (s.tier1 = none → (encodeV s).tier1 = {}) ∧
      (s.tier2 = none → (encodeV s).tier2 = {}) ∧
      (s.tier3 = none → (encodeV s).tier3 = {}) ∧ (encodeV s).object = {}) ∧
    ∀ o : OSpec, (encodeO o).tier1 = {} ∧ (encodeO o).tier2 = {} ∧ (encodeO o).tier3 = {} := by
  refine ⟨fun s => ⟨fun h => ?_, fun h => ?_, fun h => ?_, rfl⟩, fun _ => ⟨rfl, rfl, rfl⟩⟩ <;>
    simp [encodeV, h]

/-! ## Tier invariants (03:20-22) -/

/-- P03-05. 03:20 'In the body frame, the bounding box spans x in [-o_r, L + o_f],
y in [-W_bbox/2, W_bbox/2], and z in [0, H_bbox]'. -/
theorem box_extents (s : VSpec) (h : s.WF) :
    approxEq s.tier0.bbox_length ((boxX s.tier0).2 - (boxX s.tier0).1) ∧
    (boxY s.tier0).2 - (boxY s.tier0).1 = s.tier0.bbox_width := by
  refine ⟨?_, by simp only [boxY]; ring⟩
  have e : (boxX s.tier0).2 - (boxX s.tier0).1 =
      s.tier0.wheelbase + s.tier0.overhang_front + s.tier0.overhang_rear := by
    simp only [boxX]; ring
  rw [e]; exact h.1

/-- P03-06. 03:20 'Invariant: L_bbox == L + o_f + o_r', with the tolerance of 03:31
'|a - b| <= 10^-6 * max(|a|, |b|, 1)'. -/
theorem tier0_inv (s : VSpec) (h : s.WF) :
    approxEq (encodeV s).tier0.bbox_length
      ((encodeV s).tier0.wheelbase + (encodeV s).tier0.overhang_front +
        (encodeV s).tier0.overhang_rear) :=
  h.1

/-- P03-07. 03:21 'Invariant: l_f + l_r == L'. -/
theorem tier1_inv (s : VSpec) (h : s.WF) (h1 : populated (.vehicle s) 1 = true) :
    approxEq ((encodeV s).tier1.cg_dist_front + (encodeV s).tier1.cg_dist_rear)
      (encodeV s).tier0.wheelbase := by
  simp only [populated] at h1
  obtain ⟨t1, ht1⟩ := Option.isSome_iff_exists.mp h1
  simpa [encodeV, ht1] using h.2.1 t1 ht1

/-- P03-08. 03:22 'Invariant: m_s + m_uf + m_ur == m', with m from Tier 1 (03:12). -/
theorem tier2_inv (s : VSpec) (h : s.WF) (h2 : populated (.vehicle s) 2 = true) :
    populated (.vehicle s) 1 = true ∧
    approxEq ((encodeV s).tier2.sprung_mass + (encodeV s).tier2.unsprung_mass_f +
      (encodeV s).tier2.unsprung_mass_r) (encodeV s).tier1.mass := by
  simp only [populated] at h2 ⊢
  obtain ⟨t2, ht2⟩ := Option.isSome_iff_exists.mp h2
  obtain ⟨t1, ht1, happ⟩ := (h.2.2.1 t2 ht2).1
  refine ⟨by simp [Option.mem_def.mp ht1], ?_⟩
  simpa [encodeV, ht2, Option.mem_def.mp ht1, encodeTier2] using happ

/-- P03-11. 03:22 '`reverse_gear_ratio` i_R > 0'. -/
theorem reverse_pos (s : VSpec) (h : s.WF) (h2 : populated (.vehicle s) 2 = true) :
    0 < (encodeV s).tier2.reverse_gear_ratio := by
  simp only [populated] at h2
  obtain ⟨t2, ht2⟩ := Option.isSome_iff_exists.mp h2
  simpa [encodeV, ht2, encodeTier2] using (h.2.2.1 t2 ht2).2.1

/-- 03:22 'Peak drive torque at the wheels in forward gear g is T_drive,max i_g i_fd'. -/
def fwdWheelTorque (t : Tier2Abi) (g : Fin 10) : ℝ :=
  t.max_drive_torque * t.gear_ratios g * t.final_drive_ratio
/-- 03:22 'In reverse it is T_drive,max i_R i_fd, acting toward -x': its x component. -/
def revWheelTorqueX (t : Tier2Abi) : ℝ :=
  -(t.max_drive_torque * t.reverse_gear_ratio * t.final_drive_ratio)

/-- 03:22: with non-negative torque and final drive ratio, which the spec does not
require, the reverse torque acts toward -x. -/
theorem rev_toward_neg_x (t : Tier2Abi) (hT : 0 ≤ t.max_drive_torque)
    (hR : 0 < t.reverse_gear_ratio) (hfd : 0 ≤ t.final_drive_ratio) : revWheelTorqueX t ≤ 0 :=
  neg_nonpos.mpr (mul_nonneg (mul_nonneg hT hR.le) hfd)

/-- The P03-12 witness: the tiers 0 and 1 of `cgWitness` with l_r = 3/2, and
m_s = 1300, m_uf = m_ur = 100, T_drive,max = -1, i_R = 3, i_fd = 1, gears [3]. -/
def revWitness : VSpec :=
  { tier0 := { bbox_length := 5, wheelbase := 3, overhang_front := 1, overhang_rear := 1 }
    tier1 := some { mass := 1500, cg_dist_front := 3 / 2, cg_dist_rear := 3 / 2 }
    tier2 := some { sprung_mass := 1300, unsprung_mass_f := 100, unsprung_mass_r := 100,
                    max_drive_torque := -1, reverse_gear_ratio := 3, final_drive_ratio := 1,
                    gear_ratios := [3] } }

/-- P03-12, refuted. 03:22 'In reverse it is T_drive,max i_R i_fd, acting toward -x'.
Nothing makes `max_drive_torque` or `final_drive_ratio` non-negative, so an accepted spec
can have a reverse wheel torque toward +x. -/
theorem rev_torque_toward_pos_x : ∃ s : VSpec, s.WF ∧ ∃ t2 ∈ s.tier2,
    0 < revWheelTorqueX (encodeTier2 t2) := by
  refine ⟨revWitness, ⟨?_, ?_, ?_, ?_⟩, _, rfl, ?_⟩
  · exact approxEq_of_eq _ _ (by simp [revWitness]; norm_num)
  · rintro t1 ⟨⟩; exact approxEq_of_eq _ _ (by simp [revWitness])
  · rintro t2 ⟨⟩
    exact ⟨⟨_, rfl, approxEq_of_eq _ _ (by norm_num)⟩, by norm_num, by simp, by simp⟩
  · rintro d h; simp [revWitness] at h
  · simp [revWheelTorqueX, encodeTier2]

/-- P03-13. 03:36 '`num_gears` is the number of `gear_ratios` values, and the unused
entries are zero'; 03:22 '`gear_ratios[10]`'. -/
theorem gears_encoding (t : Tier2Dsl) (h : t.gear_ratios.length ≤ 10) :
    (encodeTier2 t).num_gears = t.gear_ratios.length ∧ (encodeTier2 t).num_gears ≤ 10 ∧
    (∀ i : Fin 10, t.gear_ratios.length ≤ i.val → (encodeTier2 t).gear_ratios i = 0) ∧
    (∀ i : Fin 10, (hi : i.val < t.gear_ratios.length) →
      (encodeTier2 t).gear_ratios i = t.gear_ratios[i.val]) := by
  refine ⟨rfl, h, fun i hi => ?_, fun i hi => ?_⟩
  · simp only [encodeTier2]; rw [List.getD_eq_getElem?_getD, List.getElem?_eq_none hi]; rfl
  · simp only [encodeTier2]; rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi]; rfl

/-! ## Objects (03:40-44) -/

/-- P03-14. 03:42 'An object is a Tier 0 vehicle with L = 0, o_f = o_r = `length` / 2,
L_bbox = `length`, ... and delta_max = delta_dot_max = i_s = 0'. -/
theorem object_tier0 (o : OSpec) :
    let t := objectTier0 o
    t.bbox_length = t.wheelbase + t.overhang_front + t.overhang_rear ∧ t.inv ∧
      t.max_steer_angle = 0 ∧ t.max_steer_rate = 0 ∧ t.steering_ratio = 0 := by
  have e : (objectTier0 o).bbox_length = (objectTier0 o).wheelbase +
      (objectTier0 o).overhang_front + (objectTier0 o).overhang_rear := by
    simp only [objectTier0]; ring
  exact ⟨e, approxEq_of_eq _ _ e, rfl, rfl, rfl⟩

/-- P03-15. 03:42 'Where a rule divides by delta_max, the quotient is 0 for an object'. -/
theorem object_div_delta (o : OSpec) (x : ℝ) : x / (encodeO o).tier0.max_steer_angle = 0 := by
  simp [encodeO, objectTier0]

/-- P03-17. 03:40 'a box of `length`, `width`, and `height`, a speed limit `v_max`, and
an acceleration limit `a_max`, each value above zero'. -/
theorem object_pos (o : OSpec) (h : o.WF) :
    let a := encodeO o
    0 < a.tier0.bbox_length ∧ 0 < a.tier0.bbox_width ∧ 0 < a.tier0.bbox_height ∧
      0 < a.object.v_max ∧ 0 < a.object.a_max ∧ (boxX a.tier0).1 < (boxX a.tier0).2 := by
  obtain ⟨hl, hw, hh, hv, ha⟩ := h
  refine ⟨hl, hw, hh, hv, ha, ?_⟩
  simp only [encodeO, objectTier0, boxX]
  linarith

inductive Creator | spawn | place deriving DecidableEq

/-- 03:40 and 16:103 'a spec of class `STATIC` may be used only by `place`'. -/
def useOK (o : OSpec) (c : Creator) : Prop := o.cls = .static → c = .place

/-- P03-19. 03:40 '`STATIC` for a fixed object such as a cone or barrier, which only
`place` may use'. -/
theorem static_only_place (o : OSpec) (c : Creator) (h : useOK o c) (hs : o.cls = .static) :
    c = .place :=
  h hs

/-! ## Tier check and wiring (03:26-29, 03:43) -/

/-- 03:26: the tier half of bind acceptance. -/
def tierCheck (x : Spec) (r : Fin 3) : Bool := populated x r

/-- P03-20. 03:26 'Binding or splicing a component whose `required_tier` is not populated
in the actor's `vehicle_spec` or `object_spec` is a compile-time error'. -/
theorem tierCheck_abi :
    (∀ (x : Spec) (r : Fin 3), tierCheck x r = (encode x).mask.testBit r) ∧
    ∀ (o : OSpec) (r : Fin 3), tierCheck (.object o) r = true ↔ r = 0 := by
  refine ⟨fun x r => ?_, fun o r => ?_⟩
  · cases x with
    | vehicle s => exact ((mask_bit_iff s).1 r (by omega)).symm
    | object o => exact (object_mask_bits o r (by omega)).symm
  · fin_cases r <;> simp [tierCheck, populated]

inductive Physics | kinematicBicycle | dynamicSingleTrack | object

/-- 03:28-29: the input frame types each physics model accepts without an adapter. -/
def accepts : Physics → FrameType → Prop
  | .kinematicBicycle, t => t = .whole .kcf
  | .dynamicSingleTrack, t => t = .whole .kcf
  | .object, t => t = .whole .intent

/-- P03-21. 03:28 'A Tier 0 vehicle physics model (`KinematicBicycle`) accepts **only**
Tier A `KinematicControlFrame` ... Wiring an `ActuatorControlFrame` into
`KinematicBicycle` is rejected at compile time'. -/
theorem kb_rejects_acf :
    (∀ t, accepts .kinematicBicycle t ↔ t = .whole .kcf) ∧
    ¬ accepts .kinematicBicycle (.whole .acf) := by
  simp [accepts]

/-- 03:29: with |`steering_wheel_norm`| <= 1, |delta| <= |delta_max|. -/
theorem steer_bound (n dmax : ℝ) (hn : |n| ≤ 1) : |n * dmax| ≤ |dmax| := by
  rw [abs_mul]; exact mul_le_of_le_one_left (abs_nonneg _) hn

/-- P03-22, refuted. 03:29 'it converts steering with delta = `steering_wheel_norm` *
delta_max'. Nothing makes delta_max non-negative (03:20), so |delta| <= delta_max fails
for norm = 1, delta_max = -1/2. -/
theorem steer_bound_counterexample : ∃ n dmax : ℝ, |n| ≤ 1 ∧ ¬ |n * dmax| ≤ dmax := by
  refine ⟨1, -1 / 2, by simp, ?_⟩
  rw [one_mul, abs_of_neg (by norm_num)]
  norm_num

/-- 03:43: a type carries a control frame, whole, partial, or `Override<T>`. -/
def carriesControl (t : FrameType) : Prop := t.root = .kcf ∨ t.root = .acf
def objectChainOK (ts : List FrameType) : Prop := ∀ t ∈ ts, ¬ carriesControl t

/-- P03-23. 03:43 'No chain that serves an object actor, whether named, `physics`, or
`bind`, carries a `KinematicControlFrame` or `ActuatorControlFrame`, whole, partial
(`Lon<T>`, `Lat<T>`), or `Override<T>`. A violation is a compile-time error'. -/
theorem object_chain_rejects :
    (∀ t : FrameType, (t.root = .kcf ∨ t.root = .acf) → ¬ objectChainOK [t]) ∧
    objectChainOK [.whole .intent, .lon .intent, .lat .intent, .override .intent] ∧
    accepts .object (.whole .intent) := by
  refine ⟨fun t hc h => h t (by simp) hc, ?_, rfl⟩
  simp [objectChainOK, carriesControl, FrameType.root]

/-! ## Tier 3 decks (03:23, 03:34-36) -/

structure Effective where
  tier0 : Tier0
  tier1 : Tier1
  tier2 : Tier2Abi

/-- 03:34: inside a supporting physics component an `OVERRIDE_TIER1_2` deck replaces
Tier 1-2 values; `deck` stands for the quantities the deck defines. -/
def effective (a : AbiSpec) (supports : Bool) (deck : Tier1 × Tier2Abi → Tier1 × Tier2Abi) :
    Effective :=
  if supports = true ∧ a.tier3.precedence_mode = 1 then
    let p := deck (a.tier1, a.tier2); ⟨a.tier0, p.1, p.2⟩
  else ⟨a.tier0, a.tier1, a.tier2⟩

/-- P03-24. 03:35 '**Never Overridden:** Tier 0 geometry, which World collision checks
use'. -/
theorem tier0_never_overridden (a : AbiSpec) (sup : Bool)
    (deck : Tier1 × Tier2Abi → Tier1 × Tier2Abi) : (effective a sup deck).tier0 = a.tier0 := by
  unfold effective; split <;> rfl

/-- P03-25. 03:36 'A value longer than 255 bytes after this resolution is a compile-time
error'; abi:75 'char uri[256]; Null-terminated path or URI'. -/
theorem uri_nul :
    (∀ u : List UInt8, u.length ≤ 255 ↔ u.length + 1 ≤ 256) ∧
    ∀ d : Tier3Dsl, (h : d.uri.length ≤ 255) →
      (encodeDeck d).uri ⟨d.uri.length, by omega⟩ = 0 ∧
      ∀ i : Fin 256, (hi : i.val < d.uri.length) → (encodeDeck d).uri i = d.uri[i.val] := by
  refine ⟨fun u => by omega, fun d h => ⟨?_, fun i hi => ?_⟩⟩
  · simp only [encodeDeck]; rw [List.getD_eq_getElem?_getD, List.getElem?_eq_none (le_refl _)]; rfl
  · simp only [encodeDeck]; rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi]; rfl

theorem bit3_iff_deck (s : VSpec) (h : s.WF) :
    (encodeV s).mask.testBit 3 = true ↔ (encodeV s).tier3.deck_type ≠ 0 := by
  have b3 := (maskOf_bits s.tier1.isSome s.tier2.isSome s.tier3.isSome).2.2.2.1
  simp only [encodeV, b3]
  cases ht : s.tier3 with
  | none => simp
  | some d =>
    have hk := (h.2.2.2 d ht).2.1
    simp only [Option.isSome_some, Option.map_some, Option.getD_some, encodeDeck, true_iff]
    cases hd : d.kind <;> simp_all [DeckType.toNat]

/-- P03-26. 03:36 '`deck_type` and `precedence_mode` hold the header's numeric values for
the enum names'; abi:71 '0:NONE, 1:PACEJKA_TIR, 2:SOLVER_URI'; abi:72 '0:SUPPLEMENT_ONLY,
1:OVERRIDE_TIER1_2'. -/
theorem deck_roundtrip :
    (∀ d : DeckType, DeckType.ofNat? d.toNat = some d) ∧
    (∀ n, (DeckType.ofNat? n).isSome ↔ n < 3) ∧
    (∀ p : Precedence, Precedence.ofNat? p.toNat = some p) ∧
    (∀ n, (Precedence.ofNat? n).isSome ↔ n < 2) ∧
    ∀ s : VSpec, s.WF → ((encodeV s).mask.testBit 3 = true ↔ (encodeV s).tier3.deck_type ≠ 0) := by
  refine ⟨fun d => by cases d <;> rfl, fun n => ?_, fun p => by cases p <;> rfl, fun n => ?_,
    bit3_iff_deck⟩
  · rcases n with _ | _ | _ | n
    · simp [DeckType.ofNat?]
    · simp [DeckType.ofNat?]
    · simp [DeckType.ofNat?]
    · exact iff_of_false (fun h => by cases h) (by omega)
  · rcases n with _ | _ | n
    · simp [Precedence.ofNat?]
    · simp [Precedence.ofNat?]
    · exact iff_of_false (fun h => by cases h) (by omega)

/-! ## Object classes (03:14, 03:40, 16:22) -/

/-- P03-27. 16:22 '`ObjectClass` (`UNKNOWN` = 0, `CAR` = 1, `TRUCK` = 2, `PEDESTRIAN` = 3,
`CYCLIST` = 4, `MOTORCYCLE` = 5, `ANIMAL` = 6, `STATIC` = 7)'; 03:14 vehicle classes
'`CAR` ..., `TRUCK`, `CYCLIST`, or `MOTORCYCLE`'; 03:40 object classes '`PEDESTRIAN`,
`ANIMAL`, `UNKNOWN`, or `STATIC`'. -/
theorem class_numbering :
    Function.Injective ObjectClass.toNat ∧
    Finset.univ.image (fun c : VehicleClass => c.toClass.toNat) = {1, 2, 4, 5} ∧
    Finset.univ.image (fun c : ObjClass => c.toClass.toNat) = {0, 3, 6, 7} ∧
    ∀ (v : VehicleClass) (o : ObjClass), v.toClass.toNat ≠ o.toClass.toNat := by
  refine ⟨fun a b h => ?_, by decide, by decide, fun v o => ?_⟩
  · cases a <;> cases b <;> simp_all [ObjectClass.toNat]
  · cases v <;> cases o <;> simp [VehicleClass.toClass, ObjClass.toClass, ObjectClass.toNat]

end Spec

end Driveline.VehicleSpec
