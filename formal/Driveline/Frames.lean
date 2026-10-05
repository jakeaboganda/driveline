import Driveline.F64

/-!
# Checkpoint frames (spec §5)

The three command frames and `KinematicState` of `docs/spec/05-checkpoints.md`:
groups and modes (05:16-32), the Partial and Override rule (05:34), the zeroing
of unused fields (05:38), and delivery (05:40). Validity is in
`Driveline.Validity`.
-/

namespace Driveline

/-! ## Modes -/

/-- A mode enum: `NONE`, the listed modes in table order (05:18-25), and the
ABI number of each mode. `toNat` is written out by hand for each enum, so the
encoding theorems check real content. -/
class ModeEnum (α : Type) where
  none : α
  listed : List α
  toNat : α → Nat

/-- Decodes a mode byte: the mode with that number, if any. -/
def ModeEnum.ofNat? {α : Type} [ModeEnum α] (n : Nat) : Option α :=
  (ModeEnum.none :: ModeEnum.listed).find? fun m => ModeEnum.toNat m == n

theorem ModeEnum.ofNat_inv {α : Type} [ModeEnum α] (n : Nat) (m : α)
    (h : ModeEnum.ofNat? n = some m) : ModeEnum.toNat m = n := by
  simpa using List.find?_some h

/-- The numbering rule of 05:32 for one enum. -/
abbrev ModeEnum.Numbered (α : Type) [ModeEnum α] [DecidableEq α] : Prop :=
  (∀ m ∈ (ModeEnum.listed : List α), ModeEnum.toNat m = (ModeEnum.listed : List α).idxOf m + 1) ∧
    ModeEnum.toNat (ModeEnum.none : α) = 0

inductive LonMode | none | accelTarget | velocityTarget | gapProfile | stt
  deriving DecidableEq, Repr
inductive LatMode | none | laneOffset | polylinePath | stt
  deriving DecidableEq, Repr
inductive TurnSignal | none | off | left | right | hazard
  deriving DecidableEq, Repr
inductive AccelMode | none | accel | jerk
  deriving DecidableEq, Repr
inductive SteerMode | none | angle | rate
  deriving DecidableEq, Repr
inductive PedalMode | none | pedals
  deriving DecidableEq, Repr
inductive WheelMode | none | angle | torque
  deriving DecidableEq, Repr
inductive GearMode | none | park | reverse | neutral | drive
  deriving DecidableEq, Repr

instance : ModeEnum LonMode where
  none := .none
  listed := [.accelTarget, .velocityTarget, .gapProfile, .stt]
  toNat := fun
    | .none => 0 | .accelTarget => 1 | .velocityTarget => 2 | .gapProfile => 3 | .stt => 4

instance : ModeEnum LatMode where
  none := .none
  listed := [.laneOffset, .polylinePath, .stt]
  toNat := fun | .none => 0 | .laneOffset => 1 | .polylinePath => 2 | .stt => 3

instance : ModeEnum TurnSignal where
  none := .none
  listed := [.off, .left, .right, .hazard]
  toNat := fun | .none => 0 | .off => 1 | .left => 2 | .right => 3 | .hazard => 4

instance : ModeEnum AccelMode where
  none := .none
  listed := [.accel, .jerk]
  toNat := fun | .none => 0 | .accel => 1 | .jerk => 2

instance : ModeEnum SteerMode where
  none := .none
  listed := [.angle, .rate]
  toNat := fun | .none => 0 | .angle => 1 | .rate => 2

instance : ModeEnum PedalMode where
  none := .none
  listed := [.pedals]
  toNat := fun | .none => 0 | .pedals => 1

instance : ModeEnum WheelMode where
  none := .none
  listed := [.angle, .torque]
  toNat := fun | .none => 0 | .angle => 1 | .torque => 2

instance : ModeEnum GearMode where
  none := .none
  listed := [.park, .reverse, .neutral, .drive]
  toNat := fun | .none => 0 | .park => 1 | .reverse => 2 | .neutral => 3 | .drive => 4

/-! Baseline modes (05:32). Every mode of `gear_mode` means every listed mode,
so `NONE` is not a baseline mode. -/

def LonMode.isBaseline : LonMode → Bool | .velocityTarget => true | _ => false
def LatMode.isBaseline : LatMode → Bool | .laneOffset => true | _ => false
def TurnSignal.isBaseline : TurnSignal → Bool | .off => true | _ => false
def AccelMode.isBaseline : AccelMode → Bool | .accel => true | _ => false
def SteerMode.isBaseline : SteerMode → Bool | .angle => true | _ => false
def PedalMode.isBaseline : PedalMode → Bool | .pedals => true | _ => false
def WheelMode.isBaseline : WheelMode → Bool | .angle => true | _ => false
def GearMode.isBaseline : GearMode → Bool | .none => false | _ => true

theorem LonMode.isBaseline_iff (m : LonMode) : m.isBaseline = true ↔ m = .velocityTarget := by
  cases m <;> decide
theorem LatMode.isBaseline_iff (m : LatMode) : m.isBaseline = true ↔ m = .laneOffset := by
  cases m <;> decide
theorem TurnSignal.isBaseline_iff (m : TurnSignal) : m.isBaseline = true ↔ m = .off := by
  cases m <;> decide
theorem AccelMode.isBaseline_iff (m : AccelMode) : m.isBaseline = true ↔ m = .accel := by
  cases m <;> decide
theorem SteerMode.isBaseline_iff (m : SteerMode) : m.isBaseline = true ↔ m = .angle := by
  cases m <;> decide
theorem PedalMode.isBaseline_iff (m : PedalMode) : m.isBaseline = true ↔ m = .pedals := by
  cases m <;> decide
theorem WheelMode.isBaseline_iff (m : WheelMode) : m.isBaseline = true ↔ m = .angle := by
  cases m <;> decide
theorem GearMode.isBaseline_iff (m : GearMode) : m.isBaseline = true ↔ m ≠ .none := by
  cases m <;> decide

/-! ## Groups and fields -/

inductive IntentGroup | lon | lat | signal
  deriving DecidableEq, Repr
inductive KinematicGroup | lon | lat
  deriving DecidableEq, Repr
inductive ActuatorGroup | pedals | wheel | gear
  deriving DecidableEq, Repr

/-- The declared type of a frame: `T`, `Lon<T>`, `Lat<T>`, or `Override<T>`. -/
inductive Decl | full | lon | lat | override
  deriving DecidableEq, Repr

theorem IntentGroup.forall_iff {P : IntentGroup → Prop} :
    (∀ g, P g) ↔ P .lon ∧ P .lat ∧ P .signal :=
  ⟨fun h => ⟨h _, h _, h _⟩, fun ⟨a, b, c⟩ g => by cases g <;> assumption⟩

theorem KinematicGroup.forall_iff {P : KinematicGroup → Prop} :
    (∀ g, P g) ↔ P .lon ∧ P .lat :=
  ⟨fun h => ⟨h _, h _⟩, fun ⟨a, b⟩ g => by cases g <;> assumption⟩

theorem ActuatorGroup.forall_iff {P : ActuatorGroup → Prop} :
    (∀ g, P g) ↔ P .pedals ∧ P .wheel ∧ P .gear :=
  ⟨fun h => ⟨h _, h _, h _⟩, fun ⟨a, b, c⟩ g => by cases g <;> assumption⟩

inductive IntentField
  | aRef | vRef | stopAtOdometer | gapTargetActorId | timeGapRef | distanceGapMin
  | targetRoadId | targetLaneId | dRef | numWaypoints | pathPoints
  | numTrajPoints | trajectory
  deriving DecidableEq, Repr

inductive KinematicField | aLonCmd | jerkLonCmd | steerAngleCmd | steerRateCmd
  deriving DecidableEq, Repr

inductive ActuatorField | throttle | brake | steeringWheelNorm | steeringTorqueNm | manualGearIndex
  deriving DecidableEq, Repr

/-- The Fields column of 05:18-20. `num_traj_points` and `trajectory` are
shared by `LON` and `LAT`. -/
def IntentField.groups : IntentField → List IntentGroup
  | .aRef | .vRef | .stopAtOdometer | .gapTargetActorId | .timeGapRef | .distanceGapMin => [.lon]
  | .targetRoadId | .targetLaneId | .dRef | .numWaypoints | .pathPoints => [.lat]
  | .numTrajPoints | .trajectory => [.lon, .lat]

/-- The Fields column of 05:21-22. -/
def KinematicField.groups : KinematicField → List KinematicGroup
  | .aLonCmd | .jerkLonCmd => [.lon]
  | .steerAngleCmd | .steerRateCmd => [.lat]

/-- The Fields column of 05:23-25. -/
def ActuatorField.groups : ActuatorField → List ActuatorGroup
  | .throttle | .brake => [.pedals]
  | .steeringWheelNorm | .steeringTorqueNm => [.wheel]
  | .manualGearIndex => [.gear]

/-! Fields per Mode, 05:28-30, one function per mode enum. -/

def LonMode.uses : LonMode → IntentField → Bool
  | .accelTarget, .aRef | .accelTarget, .stopAtOdometer => true
  | .velocityTarget, .vRef | .velocityTarget, .stopAtOdometer => true
  | .gapProfile, .vRef | .gapProfile, .gapTargetActorId | .gapProfile, .timeGapRef
  | .gapProfile, .distanceGapMin | .gapProfile, .stopAtOdometer => true
  | .stt, .numTrajPoints | .stt, .trajectory => true
  | _, _ => false

def LatMode.uses : LatMode → IntentField → Bool
  | .laneOffset, .targetRoadId | .laneOffset, .targetLaneId | .laneOffset, .dRef => true
  | .polylinePath, .numWaypoints | .polylinePath, .pathPoints => true
  | .stt, .numTrajPoints | .stt, .trajectory => true
  | _, _ => false

/-- `SIGNAL` has no fields (05:20). -/
def TurnSignal.uses : TurnSignal → IntentField → Bool := fun _ _ => false

def AccelMode.uses : AccelMode → KinematicField → Bool
  | .accel, .aLonCmd | .accel, .jerkLonCmd | .jerk, .jerkLonCmd => true
  | _, _ => false

def SteerMode.uses : SteerMode → KinematicField → Bool
  | .angle, .steerAngleCmd | .angle, .steerRateCmd | .rate, .steerRateCmd => true
  | _, _ => false

def PedalMode.uses : PedalMode → ActuatorField → Bool
  | .pedals, .throttle | .pedals, .brake => true
  | _, _ => false

def WheelMode.uses : WheelMode → ActuatorField → Bool
  | .angle, .steeringWheelNorm | .torque, .steeringTorqueNm => true
  | _, _ => false

def GearMode.uses : GearMode → ActuatorField → Bool
  | .drive, .manualGearIndex => true
  | _, _ => false

theorem LonMode.uses_eq_false (m : LonMode) (fld : IntentField)
    (h : IntentGroup.lon ∉ fld.groups) : m.uses fld = false := by
  revert h; cases m <;> cases fld <;> decide

theorem LatMode.uses_eq_false (m : LatMode) (fld : IntentField)
    (h : IntentGroup.lat ∉ fld.groups) : m.uses fld = false := by
  revert h; cases m <;> cases fld <;> decide

theorem LonMode.none_uses (fld : IntentField) : LonMode.none.uses fld = false := by
  cases fld <;> rfl

theorem LatMode.none_uses (fld : IntentField) : LatMode.none.uses fld = false := by
  cases fld <;> rfl

/-! ## Frames -/

structure Header where
  actorId : UInt64
  timestampNs : UInt64

structure Waypoint where
  x : F64
  y : F64
  psiRef : F64
  kappaRef : F64

instance : Zero Waypoint := ⟨⟨0, 0, 0, 0⟩⟩

structure TrajPoint where
  tNs : Int64
  x : F64
  y : F64
  psi : F64
  v : F64
  a : F64
  kappa : F64

instance : Zero TrajPoint := ⟨⟨0, 0, 0, 0, 0, 0, 0⟩⟩

/-- `dl_intent_frame_t` (abi:185-205). `char[64]` is a `String` (all NUL is
`""`), and the counts are `Nat`. -/
@[ext] structure IntentFrame where
  header : Header
  lon : LonMode
  lat : LatMode
  signal : TurnSignal
  aRef : F64
  vRef : F64
  stopAtOdometer : F64
  gapTargetActorId : UInt64
  timeGapRef : F64
  distanceGapMin : F64
  targetRoadId : String
  targetLaneId : Int32
  numWaypoints : Nat
  dRef : F64
  numTrajPoints : Nat
  pathPoints : Fin 64 → Waypoint
  trajectory : Fin 64 → TrajPoint

/-- `dl_kinematic_control_frame_t` (abi:207-215). -/
@[ext] structure KinematicControlFrame where
  header : Header
  accel : AccelMode
  steer : SteerMode
  aLonCmd : F64
  jerkLonCmd : F64
  steerAngleCmd : F64
  steerRateCmd : F64

/-- `dl_actuator_control_frame_t` (abi:217-228). -/
@[ext] structure ActuatorControlFrame where
  header : Header
  pedal : PedalMode
  wheel : WheelMode
  gear : GearMode
  manualGearIndex : Int8
  throttle : F64
  brake : F64
  steeringWheelNorm : F64
  steeringTorqueNm : F64

/-- `dl_kinematic_state_t` (abi:227-241). -/
structure KinematicState where
  header : Header
  posX : F64
  posY : F64
  posZ : F64
  roll : F64
  pitch : F64
  yaw : F64
  vLon : F64
  vLat : F64
  yawRate : F64
  aLon : F64
  aLat : F64
  frontWheelAngle : F64
  slipAngleBetaCg : F64
  roadId : String
  laneId : Int32
  frenetS : F64
  frenetD : F64
  odometerM : F64

theorem cond_congr_of {α : Type} {b : Bool} {x y z : α} (h : b = true → x = y) :
    cond b x z = cond b y z := by
  cases b
  · rfl
  · exact h rfl

/-- Two zeroed arrays agree when their masks and their entries below the
count do. -/
theorem mask_congr {α : Type} {u : Bool} {n m : Nat} {p q : Fin 64 → α} {z : α}
    (hn : u = true → n = m) (hp : u = true → ∀ i : Fin 64, i.val < n → p i = q i) :
    (fun i : Fin 64 => cond (u && decide (i.val < n)) (p i) z) =
      (fun i : Fin 64 => cond (u && decide (i.val < m)) (q i) z) := by
  funext i
  cases u
  · rfl
  · rw [← hn rfl]
    by_cases hi : i.val < n
    · simp [hi, hp rfl i hi]
    · simp [hi]

/-! ### IntentFrame -/

namespace IntentFrame

def uses (f : IntentFrame) (fld : IntentField) : Bool := f.lon.uses fld || f.lat.uses fld

def usesSTT (f : IntentFrame) : Prop := f.lon = .stt ∨ f.lat = .stt

instance (f : IntentFrame) : Decidable f.usesSTT :=
  inferInstanceAs (Decidable (f.lon = .stt ∨ f.lat = .stt))

def modeNat (f : IntentFrame) : IntentGroup → Nat
  | .lon => ModeEnum.toNat f.lon
  | .lat => ModeEnum.toNat f.lat
  | .signal => ModeEnum.toNat f.signal

/-- The groups that a frame of each declared type states (05:34). -/
def stated : Decl → IntentGroup → Bool
  | .full, _ | .lon, .lon | .lat, .lat | .lat, .signal => true
  | _, _ => false

/-- The Partial and Override rule (05:34): an override may have any group
`NONE`; otherwise exactly the stated groups are not `NONE`, and a partial frame
does not use `SPATIOTEMPORAL_TRAJECTORY`. -/
def partialOverrideRule (d : Decl) (f : IntentFrame) : Prop :=
  d = .override ∨
    ((∀ g, stated d g = true ↔ f.modeNat g ≠ 0) ∧ ((d = .lon ∨ d = .lat) → ¬ f.usesSTT))

/-- Zeroing (05:38): every field that the modes do not use, and every array
entry past its count, becomes 0. -/
def zero (f : IntentFrame) : IntentFrame where
  header := f.header
  lon := f.lon
  lat := f.lat
  signal := f.signal
  aRef := bif f.uses .aRef then f.aRef else 0
  vRef := bif f.uses .vRef then f.vRef else 0
  stopAtOdometer := bif f.uses .stopAtOdometer then f.stopAtOdometer else 0
  gapTargetActorId := bif f.uses .gapTargetActorId then f.gapTargetActorId else 0
  timeGapRef := bif f.uses .timeGapRef then f.timeGapRef else 0
  distanceGapMin := bif f.uses .distanceGapMin then f.distanceGapMin else 0
  targetRoadId := bif f.uses .targetRoadId then f.targetRoadId else ""
  targetLaneId := bif f.uses .targetLaneId then f.targetLaneId else 0
  numWaypoints := bif f.uses .numWaypoints then f.numWaypoints else 0
  dRef := bif f.uses .dRef then f.dRef else 0
  numTrajPoints := bif f.uses .numTrajPoints then f.numTrajPoints else 0
  pathPoints i := bif f.uses .pathPoints && decide (i.val < f.numWaypoints) then f.pathPoints i else 0
  trajectory i :=
    bif f.uses .trajectory && decide (i.val < f.numTrajPoints) then f.trajectory i else 0

/-- Agreement on one field; for an array, on the entries below `f`'s count. -/
def agreeOn : IntentField → IntentFrame → IntentFrame → Prop
  | .aRef, f, g => f.aRef = g.aRef
  | .vRef, f, g => f.vRef = g.vRef
  | .stopAtOdometer, f, g => f.stopAtOdometer = g.stopAtOdometer
  | .gapTargetActorId, f, g => f.gapTargetActorId = g.gapTargetActorId
  | .timeGapRef, f, g => f.timeGapRef = g.timeGapRef
  | .distanceGapMin, f, g => f.distanceGapMin = g.distanceGapMin
  | .targetRoadId, f, g => f.targetRoadId = g.targetRoadId
  | .targetLaneId, f, g => f.targetLaneId = g.targetLaneId
  | .dRef, f, g => f.dRef = g.dRef
  | .numWaypoints, f, g => f.numWaypoints = g.numWaypoints
  | .pathPoints, f, g => ∀ i : Fin 64, i.val < f.numWaypoints → f.pathPoints i = g.pathPoints i
  | .numTrajPoints, f, g => f.numTrajPoints = g.numTrajPoints
  | .trajectory, f, g => ∀ i : Fin 64, i.val < f.numTrajPoints → f.trajectory i = g.trajectory i

/-- Every mode `NONE` and every field 0. -/
def blank (h : Header) : IntentFrame where
  header := h
  lon := .none
  lat := .none
  signal := .none
  aRef := 0
  vRef := 0
  stopAtOdometer := 0
  gapTargetActorId := 0
  timeGapRef := 0
  distanceGapMin := 0
  targetRoadId := ""
  targetLaneId := 0
  numWaypoints := 0
  dRef := 0
  numTrajPoints := 0
  pathPoints := fun _ => 0
  trajectory := fun _ => 0

/-- Conversion of a full frame at a `Lon<T>` port (05:40): the unstated groups
become `NONE` and their fields 0. -/
def toLon (f : IntentFrame) : IntentFrame := ({ f with lat := .none, signal := .none } : IntentFrame).zero

/-- Conversion of a full frame at a `Lat<T>` port (05:40). -/
def toLat (f : IntentFrame) : IntentFrame := ({ f with lon := .none } : IntentFrame).zero

theorem uses_of_lon {f : IntentFrame} {fld : IntentField} (h : f.lon.uses fld = true) :
    f.uses fld = true := by
  simp [uses, h]

theorem uses_of_lat {f : IntentFrame} {fld : IntentField} (h : f.lat.uses fld = true) :
    f.uses fld = true := by
  simp [uses, h]

theorem uses_numWaypoints (f : IntentFrame) : f.uses .numWaypoints = f.uses .pathPoints := by
  unfold uses
  cases f.lon <;> cases f.lat <;> rfl

theorem uses_numTrajPoints (f : IntentFrame) : f.uses .numTrajPoints = f.uses .trajectory := by
  unfold uses
  cases f.lon <;> cases f.lat <;> rfl

theorem pOR_full (f : IntentFrame) :
    f.partialOverrideRule .full ↔ f.lon ≠ .none ∧ f.lat ≠ .none ∧ f.signal ≠ .none := by
  unfold partialOverrideRule usesSTT
  simp only [IntentGroup.forall_iff, stated, modeNat]
  generalize f.lon = a
  generalize f.lat = b
  generalize f.signal = c
  cases a <;> cases b <;> cases c <;> decide

theorem pOR_lon (f : IntentFrame) :
    f.partialOverrideRule .lon ↔
      f.lon ≠ .none ∧ f.lon ≠ .stt ∧ f.lat = .none ∧ f.signal = .none := by
  unfold partialOverrideRule usesSTT
  simp only [IntentGroup.forall_iff, stated, modeNat]
  generalize f.lon = a
  generalize f.lat = b
  generalize f.signal = c
  cases a <;> cases b <;> cases c <;> decide

theorem pOR_lat (f : IntentFrame) :
    f.partialOverrideRule .lat ↔
      f.lat ≠ .none ∧ f.lat ≠ .stt ∧ f.signal ≠ .none ∧ f.lon = .none := by
  unfold partialOverrideRule usesSTT
  simp only [IntentGroup.forall_iff, stated, modeNat]
  generalize f.lon = a
  generalize f.lat = b
  generalize f.signal = c
  cases a <;> cases b <;> cases c <;> decide

theorem zero_keeps (f : IntentFrame) (fld : IntentField) (h : f.uses fld = true) :
    f.zero.agreeOn fld f := by
  cases fld
  case pathPoints =>
    have hn : f.uses .numWaypoints = true := by rw [uses_numWaypoints]; exact h
    simp only [agreeOn]
    intro i hi
    simp only [zero, hn, h, Bool.cond_true, Bool.true_and] at hi ⊢
    simp [hi]
  case trajectory =>
    have hn : f.uses .numTrajPoints = true := by rw [uses_numTrajPoints]; exact h
    simp only [agreeOn]
    intro i hi
    simp only [zero, hn, h, Bool.cond_true, Bool.true_and] at hi ⊢
    simp [hi]
  all_goals simp only [agreeOn, zero, h, Bool.cond_true]

theorem zero_unused (f : IntentFrame) (fld : IntentField) (h : f.uses fld = false) :
    f.zero.agreeOn fld (blank f.header) := by
  cases fld
  case pathPoints =>
    simp only [agreeOn]
    intro i _
    simp only [zero, h, Bool.false_and, Bool.cond_false]
    rfl
  case trajectory =>
    simp only [agreeOn]
    intro i _
    simp only [zero, h, Bool.false_and, Bool.cond_false]
    rfl
  all_goals (simp only [agreeOn, zero, h, Bool.cond_false] <;> rfl)

theorem zero_determined (f g : IntentFrame) (hh : f.header = g.header)
    (hm : f.lon = g.lon ∧ f.lat = g.lat ∧ f.signal = g.signal)
    (hu : ∀ fld, f.uses fld = true → f.agreeOn fld g) : f.zero = g.zero := by
  obtain ⟨hl, ht, hs⟩ := hm
  have hU : ∀ fld, g.uses fld = f.uses fld := fun fld => by simp only [uses, hl, ht]
  apply IntentFrame.ext <;> simp only [zero, hU, hh, hl, ht, hs]
  all_goals first
    | exact cond_congr_of (hu _)
    | exact mask_congr (fun h => hu .numWaypoints (by rw [uses_numWaypoints]; exact h))
        (hu .pathPoints)
    | exact mask_congr (fun h => hu .numTrajPoints (by rw [uses_numTrajPoints]; exact h))
        (hu .trajectory)

end IntentFrame

/-- The three exceptions to as-is delivery (05:40) that this model covers.
The steering replacement and the pre-step conversion are left to the §6.2.4
work package. -/
inductive Delivery | asIs | toLonPort | toLatPort

def IntentFrame.deliver (f : IntentFrame) : Delivery → IntentFrame
  | .asIs => f
  | .toLonPort => f.toLon
  | .toLatPort => f.toLat

/-! ### KinematicControlFrame -/

namespace KinematicControlFrame

def uses (f : KinematicControlFrame) (fld : KinematicField) : Bool :=
  f.accel.uses fld || f.steer.uses fld

def modeNat (f : KinematicControlFrame) : KinematicGroup → Nat
  | .lon => ModeEnum.toNat f.accel
  | .lat => ModeEnum.toNat f.steer

def stated : Decl → KinematicGroup → Bool
  | .full, _ | .lon, .lon | .lat, .lat => true
  | _, _ => false

/-- The Partial and Override rule (05:34). -/
def partialOverrideRule (d : Decl) (f : KinematicControlFrame) : Prop :=
  d = .override ∨ ∀ g, stated d g = true ↔ f.modeNat g ≠ 0

def zero (f : KinematicControlFrame) : KinematicControlFrame where
  header := f.header
  accel := f.accel
  steer := f.steer
  aLonCmd := bif f.uses .aLonCmd then f.aLonCmd else 0
  jerkLonCmd := bif f.uses .jerkLonCmd then f.jerkLonCmd else 0
  steerAngleCmd := bif f.uses .steerAngleCmd then f.steerAngleCmd else 0
  steerRateCmd := bif f.uses .steerRateCmd then f.steerRateCmd else 0

def agreeOn : KinematicField → KinematicControlFrame → KinematicControlFrame → Prop
  | .aLonCmd, f, g => f.aLonCmd = g.aLonCmd
  | .jerkLonCmd, f, g => f.jerkLonCmd = g.jerkLonCmd
  | .steerAngleCmd, f, g => f.steerAngleCmd = g.steerAngleCmd
  | .steerRateCmd, f, g => f.steerRateCmd = g.steerRateCmd

def toLon (f : KinematicControlFrame) : KinematicControlFrame :=
  ({ f with steer := .none } : KinematicControlFrame).zero

def toLat (f : KinematicControlFrame) : KinematicControlFrame :=
  ({ f with accel := .none } : KinematicControlFrame).zero

theorem pOR_full (f : KinematicControlFrame) :
    f.partialOverrideRule .full ↔ f.accel ≠ .none ∧ f.steer ≠ .none := by
  unfold partialOverrideRule
  simp only [KinematicGroup.forall_iff, stated, modeNat]
  generalize f.accel = a
  generalize f.steer = b
  cases a <;> cases b <;> decide

theorem pOR_lon (f : KinematicControlFrame) :
    f.partialOverrideRule .lon ↔ f.accel ≠ .none ∧ f.steer = .none := by
  unfold partialOverrideRule
  simp only [KinematicGroup.forall_iff, stated, modeNat]
  generalize f.accel = a
  generalize f.steer = b
  cases a <;> cases b <;> decide

theorem pOR_lat (f : KinematicControlFrame) :
    f.partialOverrideRule .lat ↔ f.steer ≠ .none ∧ f.accel = .none := by
  unfold partialOverrideRule
  simp only [KinematicGroup.forall_iff, stated, modeNat]
  generalize f.accel = a
  generalize f.steer = b
  cases a <;> cases b <;> decide

theorem zero_keeps (f : KinematicControlFrame) (fld : KinematicField) (h : f.uses fld = true) :
    f.zero.agreeOn fld f := by
  cases fld <;> simp only [agreeOn, zero, h, Bool.cond_true]

theorem zero_determined (f g : KinematicControlFrame) (hh : f.header = g.header)
    (hm : f.accel = g.accel ∧ f.steer = g.steer)
    (hu : ∀ fld, f.uses fld = true → f.agreeOn fld g) : f.zero = g.zero := by
  obtain ⟨ha, hs⟩ := hm
  have hU : ∀ fld, g.uses fld = f.uses fld := fun fld => by simp only [uses, ha, hs]
  apply KinematicControlFrame.ext <;> simp only [zero, hU, hh, ha, hs]
  all_goals exact cond_congr_of (hu _)

end KinematicControlFrame

/-! ### ActuatorControlFrame -/

namespace ActuatorControlFrame

def uses (f : ActuatorControlFrame) (fld : ActuatorField) : Bool :=
  f.pedal.uses fld || f.wheel.uses fld || f.gear.uses fld

def modeNat (f : ActuatorControlFrame) : ActuatorGroup → Nat
  | .pedals => ModeEnum.toNat f.pedal
  | .wheel => ModeEnum.toNat f.wheel
  | .gear => ModeEnum.toNat f.gear

/-- The Partial and Override rule (05:34). `ActuatorControlFrame` has no
partial types, so only `T` and `Override<T>` are allowed. -/
def partialOverrideRule (d : Decl) (f : ActuatorControlFrame) : Prop :=
  d = .override ∨ (d = .full ∧ ∀ g, f.modeNat g ≠ 0)

def zero (f : ActuatorControlFrame) : ActuatorControlFrame where
  header := f.header
  pedal := f.pedal
  wheel := f.wheel
  gear := f.gear
  manualGearIndex := bif f.uses .manualGearIndex then f.manualGearIndex else 0
  throttle := bif f.uses .throttle then f.throttle else 0
  brake := bif f.uses .brake then f.brake else 0
  steeringWheelNorm := bif f.uses .steeringWheelNorm then f.steeringWheelNorm else 0
  steeringTorqueNm := bif f.uses .steeringTorqueNm then f.steeringTorqueNm else 0

def agreeOn : ActuatorField → ActuatorControlFrame → ActuatorControlFrame → Prop
  | .throttle, f, g => f.throttle = g.throttle
  | .brake, f, g => f.brake = g.brake
  | .steeringWheelNorm, f, g => f.steeringWheelNorm = g.steeringWheelNorm
  | .steeringTorqueNm, f, g => f.steeringTorqueNm = g.steeringTorqueNm
  | .manualGearIndex, f, g => f.manualGearIndex = g.manualGearIndex

theorem pOR_full (f : ActuatorControlFrame) :
    f.partialOverrideRule .full ↔ f.pedal ≠ .none ∧ f.wheel ≠ .none ∧ f.gear ≠ .none := by
  unfold partialOverrideRule
  simp only [ActuatorGroup.forall_iff, modeNat]
  generalize f.pedal = a
  generalize f.wheel = b
  generalize f.gear = c
  cases a <;> cases b <;> cases c <;> decide

theorem zero_keeps (f : ActuatorControlFrame) (fld : ActuatorField) (h : f.uses fld = true) :
    f.zero.agreeOn fld f := by
  cases fld <;> simp only [agreeOn, zero, h, Bool.cond_true]

theorem zero_determined (f g : ActuatorControlFrame) (hh : f.header = g.header)
    (hm : f.pedal = g.pedal ∧ f.wheel = g.wheel ∧ f.gear = g.gear)
    (hu : ∀ fld, f.uses fld = true → f.agreeOn fld g) : f.zero = g.zero := by
  obtain ⟨hp, hw, hg⟩ := hm
  have hU : ∀ fld, g.uses fld = f.uses fld := fun fld => by simp only [uses, hp, hw, hg]
  apply ActuatorControlFrame.ext <;> simp only [zero, hU, hh, hp, hw, hg]
  all_goals exact cond_congr_of (hu _)

end ActuatorControlFrame

/-! ## Measured gap and unsupported modes -/

/-- The mode a Stage 2 component acts on (05:80): `GAP_PROFILE` without a
track port, or without the matching track, is `VELOCITY_TARGET`. -/
def effectiveLonMode (hasTrackPort trackFound : Bool) : LonMode → LonMode
  | .gapProfile => if hasTrackPort && trackFound then .gapProfile else .velocityTarget
  | m => m

/-- Whether a component accepts a mode (05:82). `none` is a manifest that does
not list the field. -/
def supports {α : Type} [ModeEnum α] [DecidableEq α] (manifest : Option (List α)) (m : α) : Bool :=
  decide (m = ModeEnum.none) || manifest.all fun l => decide (m ∈ l)

end Driveline

namespace Driveline.Frames

/-- P05-01. 'Every checkpoint frame carries `timestamp_ns` ... and `actor_id`
..., which the runtime writes' (docs/spec/05-checkpoints.md:12). Every frame
structure has one `header`, no `*Field` constructor names it, and zeroing and
port conversion keep it. -/
theorem header_kept :
    (∀ f : IntentFrame,
      f.zero.header = f.header ∧ f.toLon.header = f.header ∧ f.toLat.header = f.header) ∧
    (∀ f : KinematicControlFrame,
      f.zero.header = f.header ∧ f.toLon.header = f.header ∧ f.toLat.header = f.header) ∧
    (∀ f : ActuatorControlFrame, f.zero.header = f.header) :=
  ⟨fun _ => ⟨rfl, rfl, rfl⟩, fun _ => ⟨rfl, rfl, rfl⟩, fun _ => rfl⟩

/-- P05-03. The mode table (docs/spec/05-checkpoints.md:18-25) and the ABI
comments, for example abi:187 'LonMode: 0:NONE, 1:ACCEL_TARGET,
2:VELOCITY_TARGET, 3:GAP_PROFILE, 4:SPATIOTEMPORAL_TRAJECTORY'. Each byte
decodes to the mode the ABI names, every mode round-trips, and decoding only
returns a mode with that number, so a decoded mode field 'holds one of its
listed values' (05:67). -/
theorem mode_encodings :
    (List.range 6).map (ModeEnum.ofNat? (α := LonMode)) =
      [some .none, some .accelTarget, some .velocityTarget, some .gapProfile, some .stt, none] ∧
    (List.range 5).map (ModeEnum.ofNat? (α := LatMode)) =
      [some .none, some .laneOffset, some .polylinePath, some .stt, none] ∧
    (List.range 6).map (ModeEnum.ofNat? (α := TurnSignal)) =
      [some .none, some .off, some .left, some .right, some .hazard, none] ∧
    (List.range 4).map (ModeEnum.ofNat? (α := AccelMode)) =
      [some .none, some .accel, some .jerk, none] ∧
    (List.range 4).map (ModeEnum.ofNat? (α := SteerMode)) =
      [some .none, some .angle, some .rate, none] ∧
    (List.range 3).map (ModeEnum.ofNat? (α := PedalMode)) = [some .none, some .pedals, none] ∧
    (List.range 4).map (ModeEnum.ofNat? (α := WheelMode)) =
      [some .none, some .angle, some .torque, none] ∧
    (List.range 6).map (ModeEnum.ofNat? (α := GearMode)) =
      [some .none, some .park, some .reverse, some .neutral, some .drive, none] ∧
    (∀ m : LonMode, ModeEnum.ofNat? (ModeEnum.toNat m) = some m) ∧
    (∀ m : LatMode, ModeEnum.ofNat? (ModeEnum.toNat m) = some m) ∧
    (∀ m : TurnSignal, ModeEnum.ofNat? (ModeEnum.toNat m) = some m) ∧
    (∀ m : AccelMode, ModeEnum.ofNat? (ModeEnum.toNat m) = some m) ∧
    (∀ m : SteerMode, ModeEnum.ofNat? (ModeEnum.toNat m) = some m) ∧
    (∀ m : PedalMode, ModeEnum.ofNat? (ModeEnum.toNat m) = some m) ∧
    (∀ m : WheelMode, ModeEnum.ofNat? (ModeEnum.toNat m) = some m) ∧
    (∀ m : GearMode, ModeEnum.ofNat? (ModeEnum.toNat m) = some m) ∧
    (∀ {α : Type} [ModeEnum α] (n : Nat) (m : α),
      ModeEnum.ofNat? n = some m → ModeEnum.toNat m = n) := by
  refine ⟨by decide, by decide, by decide, by decide, by decide, by decide, by decide, by decide,
    fun m => by cases m <;> decide, fun m => by cases m <;> decide,
    fun m => by cases m <;> decide, fun m => by cases m <;> decide,
    fun m => by cases m <;> decide, fun m => by cases m <;> decide,
    fun m => by cases m <;> decide, fun m => by cases m <;> decide, ?_⟩
  intro α _ n m h
  exact ModeEnum.ofNat_inv n m h

/-- P05-04. 'A field applies only under the modes listed here'
(docs/spec/05-checkpoints.md:27-30): `jerk_lon_cmd` under `ACCEL` and `JERK`,
`steer_rate_cmd` under `ANGLE` and `RATE`, and the per-mode bullets agree with
the Fields column of the table (05:18-25) for every group of every frame. -/
theorem fields_per_mode :
    (∀ m : AccelMode, m.uses .jerkLonCmd = true ↔ m = .accel ∨ m = .jerk) ∧
    (∀ m : SteerMode, m.uses .steerRateCmd = true ↔ m = .angle ∨ m = .rate) ∧
    (∀ (m : LonMode) fld, m.uses fld = true → IntentGroup.lon ∈ fld.groups) ∧
    (∀ fld : IntentField, IntentGroup.lon ∈ fld.groups → ∃ m : LonMode, m.uses fld = true) ∧
    (∀ (m : LatMode) fld, m.uses fld = true → IntentGroup.lat ∈ fld.groups) ∧
    (∀ fld : IntentField, IntentGroup.lat ∈ fld.groups → ∃ m : LatMode, m.uses fld = true) ∧
    (∀ fld : IntentField, IntentGroup.signal ∉ fld.groups) ∧
    (∀ (m : TurnSignal) fld, m.uses fld = false) ∧
    (∀ (m : AccelMode) fld, m.uses fld = true → KinematicGroup.lon ∈ fld.groups) ∧
    (∀ fld : KinematicField, KinematicGroup.lon ∈ fld.groups → ∃ m : AccelMode, m.uses fld = true) ∧
    (∀ (m : SteerMode) fld, m.uses fld = true → KinematicGroup.lat ∈ fld.groups) ∧
    (∀ fld : KinematicField, KinematicGroup.lat ∈ fld.groups → ∃ m : SteerMode, m.uses fld = true) ∧
    (∀ (m : PedalMode) fld, m.uses fld = true → ActuatorGroup.pedals ∈ fld.groups) ∧
    (∀ fld : ActuatorField, ActuatorGroup.pedals ∈ fld.groups → ∃ m : PedalMode, m.uses fld = true) ∧
    (∀ (m : WheelMode) fld, m.uses fld = true → ActuatorGroup.wheel ∈ fld.groups) ∧
    (∀ fld : ActuatorField, ActuatorGroup.wheel ∈ fld.groups → ∃ m : WheelMode, m.uses fld = true) ∧
    (∀ (m : GearMode) fld, m.uses fld = true → ActuatorGroup.gear ∈ fld.groups) ∧
    (∀ fld : ActuatorField, ActuatorGroup.gear ∈ fld.groups → ∃ m : GearMode, m.uses fld = true) := by
  refine ⟨fun m => by cases m <;> decide, fun m => by cases m <;> decide,
    fun m fld => by cases m <;> cases fld <;> decide, fun fld h => ?_,
    fun m fld => by cases m <;> cases fld <;> decide, fun fld h => ?_,
    fun fld => by cases fld <;> decide, fun _ _ => rfl,
    fun m fld => by cases m <;> cases fld <;> decide, fun fld h => ?_,
    fun m fld => by cases m <;> cases fld <;> decide, fun fld h => ?_,
    fun m fld => by cases m <;> cases fld <;> decide, fun fld h => ?_,
    fun m fld => by cases m <;> cases fld <;> decide, fun fld h => ?_,
    fun m fld => by cases m <;> cases fld <;> decide, fun fld h => ?_⟩
  · cases fld <;> first
      | exact ⟨.accelTarget, rfl⟩ | exact ⟨.velocityTarget, rfl⟩ | exact ⟨.gapProfile, rfl⟩
      | exact ⟨.stt, rfl⟩ | exact absurd h (by decide)
  · cases fld <;> first
      | exact ⟨.laneOffset, rfl⟩ | exact ⟨.polylinePath, rfl⟩ | exact ⟨.stt, rfl⟩
      | exact absurd h (by decide)
  · cases fld <;> first | exact ⟨.accel, rfl⟩ | exact absurd h (by decide)
  · cases fld <;> first | exact ⟨.angle, rfl⟩ | exact absurd h (by decide)
  · cases fld <;> first | exact ⟨.pedals, rfl⟩ | exact absurd h (by decide)
  · cases fld <;> first | exact ⟨.angle, rfl⟩ | exact ⟨.torque, rfl⟩ | exact absurd h (by decide)
  · cases fld <;> first | exact ⟨.drive, rfl⟩ | exact absurd h (by decide)

/-- P05-05. 'The listed modes are numbered from 1 in the order shown ... Every
mode enum also has `NONE` ($0$)' (docs/spec/05-checkpoints.md:32). -/
theorem modes_numbered :
    ModeEnum.Numbered LonMode ∧ ModeEnum.Numbered LatMode ∧ ModeEnum.Numbered TurnSignal ∧
    ModeEnum.Numbered AccelMode ∧ ModeEnum.Numbered SteerMode ∧ ModeEnum.Numbered PedalMode ∧
    ModeEnum.Numbered WheelMode ∧ ModeEnum.Numbered GearMode := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> decide

/-- P05-06. 'The **baseline mode** of each mode field is the one that
runtime-authored frames use ...: `VELOCITY_TARGET` for `lon_mode`,
`LANE_OFFSET` for `lat_mode`, `OFF` for `turn_signal`, `ACCEL` for
`accel_mode`, `ANGLE` for `steer_mode` and `wheel_mode`, `PEDALS` for
`pedal_mode`, and every mode of `gear_mode`' (docs/spec/05-checkpoints.md:32).
A frame in baseline modes states every group and does not use
`SPATIOTEMPORAL_TRAJECTORY`. That Pass 1 step 5 frames use only baseline modes
needs the §6.2 model and is left to that work package. -/
theorem baseline_modes :
    (∀ f : IntentFrame, f.lon.isBaseline = true → f.lat.isBaseline = true →
      f.signal.isBaseline = true → f.partialOverrideRule .full ∧ ¬ f.usesSTT) ∧
    (∀ f : KinematicControlFrame, f.accel.isBaseline = true → f.steer.isBaseline = true →
      f.partialOverrideRule .full) ∧
    (∀ f : ActuatorControlFrame, f.pedal.isBaseline = true → f.wheel.isBaseline = true →
      f.gear.isBaseline = true → f.partialOverrideRule .full) ∧
    (∀ g : GearMode, g.isBaseline = true ↔ g ≠ .none) := by
  refine ⟨fun f h1 h2 h3 => ?_, fun f h1 h2 => ?_, fun f h1 h2 h3 => ?_, GearMode.isBaseline_iff⟩
  · rw [LonMode.isBaseline_iff] at h1
    rw [LatMode.isBaseline_iff] at h2
    rw [TurnSignal.isBaseline_iff] at h3
    rw [IntentFrame.pOR_full]
    unfold IntentFrame.usesSTT
    rw [h1, h2, h3]
    decide
  · rw [AccelMode.isBaseline_iff] at h1
    rw [SteerMode.isBaseline_iff] at h2
    rw [KinematicControlFrame.pOR_full, h1, h2]
    decide
  · rw [PedalMode.isBaseline_iff] at h1
    rw [WheelMode.isBaseline_iff] at h2
    rw [ActuatorControlFrame.pOR_full, h1, h2]
    exact ⟨by decide, by decide, (GearMode.isBaseline_iff _).mp h3⟩

/-- P05-15. 'The runtime delivers each producer's latest output, as validated,
zeroed, and stamped, without further change, except for ... the conversion of
a full frame at a `Lon<T>` or `Lat<T>` port, which sets the unstated groups to
`NONE` and their fields to zero' (docs/spec/05-checkpoints.md:40). The steering
replacement and the pre-step conversion are left to the §6.2.4 work package. -/
theorem delivery :
    (∀ f : IntentFrame, f.deliver .asIs = f) ∧
    (∀ f : IntentFrame, f.toLon.lat = .none ∧ f.toLon.signal = .none ∧
      (∀ fld, IntentGroup.lon ∉ fld.groups → f.toLon.agreeOn fld (IntentFrame.blank f.header)) ∧
      (∀ fld, f.lon.uses fld = true → f.toLon.agreeOn fld f)) ∧
    (∀ f : IntentFrame, f.toLat.lon = .none ∧ f.toLat.signal = f.signal ∧
      (∀ fld, IntentGroup.lat ∉ fld.groups → f.toLat.agreeOn fld (IntentFrame.blank f.header)) ∧
      (∀ fld, f.lat.uses fld = true → f.toLat.agreeOn fld f)) := by
  refine ⟨fun f => rfl, fun f => ⟨rfl, rfl, fun fld hg => ?_, fun fld hu => ?_⟩,
    fun f => ⟨rfl, rfl, fun fld hg => ?_, fun fld hu => ?_⟩⟩
  · exact IntentFrame.zero_unused _ fld
      (by simp [IntentFrame.uses, LonMode.uses_eq_false _ _ hg, LatMode.none_uses])
  · have := IntentFrame.zero_keeps ({ f with lat := .none, signal := .none } : IntentFrame) fld
      (IntentFrame.uses_of_lon hu)
    cases fld <;> exact this
  · exact IntentFrame.zero_unused _ fld
      (by simp [IntentFrame.uses, LatMode.uses_eq_false _ _ hg, LonMode.none_uses])
  · have := IntentFrame.zero_keeps ({ f with lon := .none } : IntentFrame) fld
      (IntentFrame.uses_of_lat hu)
    cases fld <;> exact this

/-- P05-26. 'A component that accepts `GAP_PROFILE` and has no such port treats
it as `VELOCITY_TARGET` with the same `v_ref`. ... If no such track exists, the
component treats the gap target as absent and tracks `v_ref`'
(docs/spec/05-checkpoints.md:80). The measured gap `g = rel_x` is left to the
§4/§17 work package. -/
theorem effective_lon_mode :
    (∀ p t : Bool, effectiveLonMode p t .gapProfile = .velocityTarget ↔ (p && t) = false) ∧
    (∀ (p t : Bool) (m : LonMode), m ≠ .gapProfile → effectiveLonMode p t m = m) :=
  ⟨fun p t => by cases p <;> cases t <;> decide,
    fun p t m h => by cases m <;> first | rfl | exact absurd rfl h⟩

end Driveline.Frames
