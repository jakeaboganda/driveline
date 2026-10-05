import Driveline.Frames

/-!
# Frame validity (spec §5)

The validity rules of `docs/spec/05-checkpoints.md`: the Partial and Override
rule (05:34), the `IntentFrame` rules (05:66-70), the `KinematicControlFrame`
rule (05:98), the `ActuatorControlFrame` rule (05:114), and the
`KinematicState` rule (05:119).

'Each mode field holds one of its listed values' (05:67, 05:98, 05:114) holds
by construction: a mode field has an enum type, and `ModeEnum.ofNat?` decodes
only the listed numbers (P05-03).

The output check of §14.2 runs the finiteness step before these rules, so
'not negative' (05:70), written `¬ x < 0`, is `0 ≤ x` on every frame that
passes the check (`gap_rule`).
-/

namespace Driveline

/-- The road map that 05:69 checks against. The OpenDRIVE facts are
`OUT: external`. `lane_ne_zero` is the OpenDRIVE fact behind 05:69 'so the lane
ID is not 0'. -/
structure RoadMap where
  road : String → Prop
  lane : String → Int → Prop
  lane_ne_zero : ∀ r l, lane r l → l ≠ 0

/-- 'strictly increase' (05:68), over the first `n` entries. -/
def timesIncrease (n : Nat) (t : Fin 64 → Int) : Prop :=
  ∀ i j : Fin 64, i < j → j.val < n → t i < t j

/-- 05:68: `num_traj_points` is from 1 to 64, the trajectory times are not
negative and strictly increase, each `v_k ≥ 0`, and each `psi` lies in `(-π, π]`. -/
def trajOK (n : Nat) (t : Fin 64 → TrajPoint) : Prop :=
  1 ≤ n ∧ n ≤ 64 ∧
    (∀ i : Fin 64, i.val < n →
      0 ≤ (t i).tNs.toInt ∧ (0 : F64) ≤ (t i).v ∧ (t i).psi.inIoc (-Real.pi) Real.pi) ∧
    timesIncrease n fun i => (t i).tNs.toInt

/-- 05:69: `num_waypoints` is from 2 to 64 and each `psi_ref` lies in `(-π, π]`. -/
def pathOK (n : Nat) (p : Fin 64 → Waypoint) : Prop :=
  2 ≤ n ∧ n ≤ 64 ∧ ∀ i : Fin 64, i.val < n → (p i).psiRef.inIoc (-Real.pi) Real.pi

theorem trajOK_congr {n : Nat} {t t' : Fin 64 → TrajPoint}
    (h : ∀ i : Fin 64, i.val < n → t i = t' i) : trajOK n t ↔ trajOK n t' := by
  unfold trajOK timesIncrease
  constructor <;> rintro ⟨h1, h2, h3, h4⟩ <;>
    refine ⟨h1, h2, fun i hi => ?_, fun i j hij hj => ?_⟩
  · rw [← h i hi]; exact h3 i hi
  · dsimp only; rw [← h i (Nat.lt_trans hij hj), ← h j hj]; exact h4 i j hij hj
  · rw [h i hi]; exact h3 i hi
  · dsimp only; rw [h i (Nat.lt_trans hij hj), h j hj]; exact h4 i j hij hj

theorem pathOK_congr {n : Nat} {p p' : Fin 64 → Waypoint}
    (h : ∀ i : Fin 64, i.val < n → p i = p' i) : pathOK n p ↔ pathOK n p' := by
  unfold pathOK
  constructor <;> rintro ⟨h1, h2, h3⟩ <;> refine ⟨h1, h2, fun i hi => ?_⟩
  · rw [← h i hi]; exact h3 i hi
  · rw [h i hi]; exact h3 i hi

/-! ## IntentFrame -/

namespace IntentFrame

/-- 05:68 -/
def sttRule (f : IntentFrame) : Prop :=
  (f.lon = .stt ↔ f.lat = .stt) ∧ (f.lon = .stt → trajOK f.numTrajPoints f.trajectory)

/-- 05:69, `LANE_OFFSET` -/
def laneRule (map : RoadMap) (f : IntentFrame) : Prop :=
  f.lat = .laneOffset → map.road f.targetRoadId ∧ map.lane f.targetRoadId f.targetLaneId.toInt

/-- 05:69, `POLYLINE_PATH` -/
def polylineRule (f : IntentFrame) : Prop :=
  f.lat = .polylinePath → pathOK f.numWaypoints f.pathPoints

/-- 05:70. 'Where they apply' is where the modes use the field. -/
def gapRule (f : IntentFrame) : Prop :=
  (f.lon = .gapProfile → f.gapTargetActorId ≠ 0) ∧
    (f.uses .vRef = true → ¬ f.vRef < 0) ∧
    (f.uses .timeGapRef = true → ¬ f.timeGapRef < 0) ∧
    (f.uses .distanceGapMin = true → ¬ f.distanceGapMin < 0)

/-- A valid `IntentFrame` of declared type `d` (05:66). -/
def valid (f : IntentFrame) (map : RoadMap) (d : Decl) : Prop :=
  f.partialOverrideRule d ∧ f.sttRule ∧ f.laneRule map ∧ f.polylineRule ∧ f.gapRule

/-- Validity of a frame of declared type `d` at the port it reaches (05:34).
`partialPort` marks a `Lon<T>` or `Lat<T>` port, where a full frame must also
not use `SPATIOTEMPORAL_TRAJECTORY`. -/
def validAt (f : IntentFrame) (map : RoadMap) (d : Decl) (partialPort : Bool) : Prop :=
  f.valid map d ∧ (partialPort = true → d = .full → ¬ f.usesSTT)

theorem pOR_congr {f g : IntentFrame} {d : Decl} (hl : f.lon = g.lon) (ht : f.lat = g.lat)
    (hs : f.signal = g.signal) : f.partialOverrideRule d ↔ g.partialOverrideRule d := by
  have hm : f.modeNat = g.modeNat := by
    funext x; cases x <;> simp only [modeNat, hl, ht, hs]
  have hS : f.usesSTT ↔ g.usesSTT := by simp only [usesSTT, hl, ht]
  unfold partialOverrideRule
  rw [hm, hS]

/-- Validity depends only on the modes and the used fields. -/
theorem valid_congr {f g : IntentFrame} (map : RoadMap) (d : Decl)
    (hm : f.lon = g.lon ∧ f.lat = g.lat ∧ f.signal = g.signal)
    (hu : ∀ fld, f.uses fld = true → f.agreeOn fld g) : f.valid map d ↔ g.valid map d := by
  obtain ⟨hl, ht, hs⟩ := hm
  have hU : ∀ fld, g.uses fld = f.uses fld := fun fld => by simp only [uses, hl, ht]
  have hstt : f.sttRule ↔ g.sttRule := by
    unfold sttRule
    rw [← hl, ← ht]
    refine and_congr Iff.rfl (imp_congr_right fun h => ?_)
    have hn : f.uses .numTrajPoints = true := uses_of_lon (by rw [h]; rfl)
    have htr : f.uses .trajectory = true := uses_of_lon (by rw [h]; rfl)
    have e : f.numTrajPoints = g.numTrajPoints := hu _ hn
    have ht' : ∀ i : Fin 64, i.val < f.numTrajPoints → f.trajectory i = g.trajectory i :=
      hu _ htr
    rw [← e]
    exact trajOK_congr ht'
  have hlane : f.laneRule map ↔ g.laneRule map := by
    unfold laneRule
    rw [← ht]
    refine imp_congr_right fun h => ?_
    rw [show f.targetRoadId = g.targetRoadId from hu .targetRoadId (uses_of_lat (by rw [h]; rfl)),
      show f.targetLaneId = g.targetLaneId from hu .targetLaneId (uses_of_lat (by rw [h]; rfl))]
  have hpoly : f.polylineRule ↔ g.polylineRule := by
    unfold polylineRule
    rw [← ht]
    refine imp_congr_right fun h => ?_
    have hp : f.uses .pathPoints = true := uses_of_lat (by rw [h]; rfl)
    have e : f.numWaypoints = g.numWaypoints := hu .numWaypoints (uses_of_lat (by rw [h]; rfl))
    have hp' : ∀ i : Fin 64, i.val < f.numWaypoints → f.pathPoints i = g.pathPoints i := hu _ hp
    rw [← e]
    exact pathOK_congr hp'
  have hgap : f.gapRule ↔ g.gapRule := by
    unfold gapRule
    rw [← hl, hU, hU, hU]
    refine and_congr (imp_congr_right fun h => ?_) (and_congr (imp_congr_right fun h => ?_)
      (and_congr (imp_congr_right fun h => ?_) (imp_congr_right fun h => ?_)))
    · rw [show f.gapTargetActorId = g.gapTargetActorId from
        hu .gapTargetActorId (uses_of_lon (by rw [h]; rfl))]
    · rw [show f.vRef = g.vRef from hu _ h]
    · rw [show f.timeGapRef = g.timeGapRef from hu _ h]
    · rw [show f.distanceGapMin = g.distanceGapMin from hu _ h]
  exact and_congr (pOR_congr hl ht hs) (and_congr hstt (and_congr hlane (and_congr hpoly hgap)))

theorem zero_valid_iff (map : RoadMap) (d : Decl) (f : IntentFrame) :
    f.zero.valid map d ↔ f.valid map d :=
  valid_congr map d ⟨rfl, rfl, rfl⟩ fun fld h => zero_keeps f fld h

theorem zero_idem (f : IntentFrame) : f.zero.zero = f.zero :=
  zero_determined f.zero f rfl ⟨rfl, rfl, rfl⟩ fun fld h => zero_keeps f fld h

theorem gapRule_mono {f g : IntentFrame} (hl : g.lon = .gapProfile → f.lon = .gapProfile)
    (hu : ∀ fld, g.uses fld = true → f.uses fld = true)
    (h1 : g.gapTargetActorId = f.gapTargetActorId) (h2 : g.vRef = f.vRef)
    (h3 : g.timeGapRef = f.timeGapRef) (h4 : g.distanceGapMin = f.distanceGapMin)
    (h : f.gapRule) : g.gapRule := by
  obtain ⟨a, b, c, e⟩ := h
  refine ⟨fun hg => ?_, fun hv => ?_, fun hv => ?_, fun hv => ?_⟩
  · rw [h1]; exact a (hl hg)
  · rw [h2]; exact b (hu _ hv)
  · rw [h3]; exact c (hu _ hv)
  · rw [h4]; exact e (hu _ hv)

end IntentFrame

/-! ## KinematicControlFrame -/

namespace KinematicControlFrame

/-- 05:98: the Partial and Override rule holds and the bounds under `ACCEL`
and `ANGLE` are above zero. -/
def valid (f : KinematicControlFrame) (d : Decl) : Prop :=
  f.partialOverrideRule d ∧ (f.accel = .accel → (0 : F64) < f.jerkLonCmd) ∧
    (f.steer = .angle → (0 : F64) < f.steerRateCmd)

theorem pOR_congr {f g : KinematicControlFrame} {d : Decl} (ha : f.accel = g.accel)
    (hs : f.steer = g.steer) : f.partialOverrideRule d ↔ g.partialOverrideRule d := by
  have hm : f.modeNat = g.modeNat := by
    funext x; cases x <;> simp only [modeNat, ha, hs]
  unfold partialOverrideRule
  rw [hm]

theorem valid_congr {f g : KinematicControlFrame} (d : Decl)
    (hm : f.accel = g.accel ∧ f.steer = g.steer)
    (hu : ∀ fld, f.uses fld = true → f.agreeOn fld g) : f.valid d ↔ g.valid d := by
  obtain ⟨ha, hs⟩ := hm
  unfold valid
  rw [← ha, ← hs]
  refine and_congr (pOR_congr ha hs)
    (and_congr (imp_congr_right fun h => ?_) (imp_congr_right fun h => ?_))
  · rw [show f.jerkLonCmd = g.jerkLonCmd from hu .jerkLonCmd (by simp [uses, h, AccelMode.uses])]
  · rw [show f.steerRateCmd = g.steerRateCmd from
      hu .steerRateCmd (by simp [uses, h, SteerMode.uses])]

theorem zero_valid_iff (d : Decl) (f : KinematicControlFrame) : f.zero.valid d ↔ f.valid d :=
  valid_congr d ⟨rfl, rfl⟩ fun fld h => zero_keeps f fld h

theorem zero_idem (f : KinematicControlFrame) : f.zero.zero = f.zero :=
  zero_determined f.zero f rfl ⟨rfl, rfl⟩ fun fld h => zero_keeps f fld h

end KinematicControlFrame

/-! ## ActuatorControlFrame -/

namespace ActuatorControlFrame

/-- 05:114. `numGears` is `num_gears` from §3. The rule applies the whole
05:34 paragraph, not only its Override sentence (spec WP01 finding). -/
def valid (f : ActuatorControlFrame) (numGears : Nat) (d : Decl) : Prop :=
  f.partialOverrideRule d ∧
    (f.pedal = .pedals → f.throttle.inIcc 0 1 ∧ f.brake.inIcc 0 1) ∧
    (f.wheel = .angle → f.steeringWheelNorm.inIcc (-1) 1) ∧
    (f.gear = .drive → 0 ≤ f.manualGearIndex.toInt ∧ f.manualGearIndex.toInt ≤ numGears)

theorem pOR_congr {f g : ActuatorControlFrame} {d : Decl} (hp : f.pedal = g.pedal)
    (hw : f.wheel = g.wheel) (hg : f.gear = g.gear) :
    f.partialOverrideRule d ↔ g.partialOverrideRule d := by
  have hm : f.modeNat = g.modeNat := by
    funext x; cases x <;> simp only [modeNat, hp, hw, hg]
  unfold partialOverrideRule
  rw [hm]

theorem valid_congr {f g : ActuatorControlFrame} (n : Nat) (d : Decl)
    (hm : f.pedal = g.pedal ∧ f.wheel = g.wheel ∧ f.gear = g.gear)
    (hu : ∀ fld, f.uses fld = true → f.agreeOn fld g) : f.valid n d ↔ g.valid n d := by
  obtain ⟨hp, hw, hg⟩ := hm
  unfold valid
  rw [← hp, ← hw, ← hg]
  refine and_congr (pOR_congr hp hw hg) (and_congr (imp_congr_right fun h => ?_)
    (and_congr (imp_congr_right fun h => ?_) (imp_congr_right fun h => ?_)))
  · rw [show f.throttle = g.throttle from hu .throttle (by simp [uses, h, PedalMode.uses]),
      show f.brake = g.brake from hu .brake (by simp [uses, h, PedalMode.uses])]
  · rw [show f.steeringWheelNorm = g.steeringWheelNorm from
      hu .steeringWheelNorm (by simp [uses, h, WheelMode.uses])]
  · rw [show f.manualGearIndex = g.manualGearIndex from
      hu .manualGearIndex (by simp [uses, h, GearMode.uses])]

theorem zero_valid_iff (n : Nat) (d : Decl) (f : ActuatorControlFrame) :
    f.zero.valid n d ↔ f.valid n d :=
  valid_congr n d ⟨rfl, rfl, rfl⟩ fun fld h => zero_keeps f fld h

theorem zero_idem (f : ActuatorControlFrame) : f.zero.zero = f.zero :=
  zero_determined f.zero f rfl ⟨rfl, rfl, rfl⟩ fun fld h => zero_keeps f fld h

end ActuatorControlFrame

/-! ## KinematicState -/

/-- 05:119 -/
def KinematicState.valid (s : KinematicState) : Prop :=
  s.yaw.inIoc (-Real.pi) Real.pi ∧ s.roll.inIoc (-Real.pi) Real.pi ∧
    s.pitch.inIoo (-(Real.pi / 2)) (Real.pi / 2)

/-- 'a value at or below zero means stop now' (05:78): `stop_at_odometer −
odometer_m ≤ 0`. -/
def stopNow (s : F64) (odo : ℝ) : Prop := s ≤ .fin odo

theorem not_stopNow_posInf (odo : ℝ) : ¬ stopNow .posInf odo := by
  rintro (h | ⟨h, _⟩)
  · exact h
  · cases h

/-! ## Output validation (spec §14.2)

The output check of `docs/spec/14-diagnostics.md` item 4, in its order: (1)
mode values, `NONE`, used counts and used `char[64]` fields, failing with
`DL_STATUS_ERR_INVALID_ARG`; (2) finiteness of every used field, where a field
that its mode makes a bound (05:36) may be `+INFINITY`, failing with
`DL_STATUS_ERR_NUMERIC`; (3) the §5 validity rules, failing with
`DL_STATUS_ERR_INVALID_ARG`. A mode field always holds a listed value or `NONE`
here, because it has an enum type (P05-03). -/

/-- The outcome of the output check of one frame. -/
inductive CheckResult | ok | invalidArg | numeric
  deriving DecidableEq

namespace F64

def Finite : F64 → Prop
  | fin _ => True
  | _ => False

theorem not_finite_posInf : ¬ posInf.Finite := id

theorem Finite.exists {x : F64} (h : x.Finite) : ∃ r : ℝ, x = fin r := by
  cases x with
  | fin r => exact ⟨r, rfl⟩
  | _ => exact (h : False).elim

/-- On a finite value, 'not negative' is `0 ≤ r`. -/
theorem Finite.nonneg {x : F64} (h : x.Finite) (hn : ¬ x < 0) : ∃ r : ℝ, x = fin r ∧ 0 ≤ r := by
  obtain ⟨r, rfl⟩ := h.exists
  rw [zero_def, fin_lt_fin] at hn
  exact ⟨r, rfl, not_lt.1 hn⟩

end F64

def Waypoint.Finite (w : Waypoint) : Prop :=
  w.x.Finite ∧ w.y.Finite ∧ w.psiRef.Finite ∧ w.kappaRef.Finite

def TrajPoint.Finite (p : TrajPoint) : Prop :=
  p.x.Finite ∧ p.y.Finite ∧ p.psi.Finite ∧ p.v.Finite ∧ p.a.Finite ∧ p.kappa.Finite

/-- A `char[64]` field holds a NUL within its 64 bytes with valid UTF-8 before
it. A `String` is valid UTF-8, so the text must have no NUL and fit in 63
bytes. -/
def charOK (s : String) : Prop := s.utf8ByteSize < 64 ∧ '\x00' ∉ s.toList

namespace IntentFrame

/-- Step 1, `NONE` only where 05:34 allows it: no stated group is `NONE`. -/
def noneOK (d : Decl) (f : IntentFrame) : Prop :=
  d = .override ∨ ∀ g, stated d g = true → f.modeNat g ≠ 0

/-- Step 1. -/
def wellFormed (d : Decl) (f : IntentFrame) : Prop :=
  f.noneOK d ∧ (f.uses .numWaypoints = true → f.numWaypoints ≤ 64) ∧
    (f.uses .numTrajPoints = true → f.numTrajPoints ≤ 64) ∧
    (f.uses .targetRoadId = true → charOK f.targetRoadId)

/-- Step 2. `stop_at_odometer` is a bound under every mode that uses it. -/
def finiteOK (f : IntentFrame) : Prop :=
  (f.uses .aRef = true → f.aRef.Finite) ∧ (f.uses .vRef = true → f.vRef.Finite) ∧
    (f.uses .stopAtOdometer = true → f.stopAtOdometer.Finite ∨ f.stopAtOdometer = .posInf) ∧
    (f.uses .timeGapRef = true → f.timeGapRef.Finite) ∧
    (f.uses .distanceGapMin = true → f.distanceGapMin.Finite) ∧
    (f.uses .dRef = true → f.dRef.Finite) ∧
    (f.uses .pathPoints = true →
      ∀ i : Fin 64, i.val < f.numWaypoints → (f.pathPoints i).Finite) ∧
    (f.uses .trajectory = true →
      ∀ i : Fin 64, i.val < f.numTrajPoints → (f.trajectory i).Finite)

open Classical in
/-- The output check of one `IntentFrame` of declared type `d`. -/
noncomputable def outputCheck (map : RoadMap) (d : Decl) (f : IntentFrame) : CheckResult :=
  if ¬ f.wellFormed d then .invalidArg
  else if ¬ f.finiteOK then .numeric
  else if f.valid map d then .ok else .invalidArg

theorem outputCheck_ok {map : RoadMap} {d : Decl} {f : IntentFrame} :
    f.outputCheck map d = .ok ↔ f.wellFormed d ∧ f.finiteOK ∧ f.valid map d := by
  unfold outputCheck
  split_ifs <;> simp_all

theorem outputCheck_numeric {map : RoadMap} {d : Decl} {f : IntentFrame} (hw : f.wellFormed d)
    (hf : ¬ f.finiteOK) : f.outputCheck map d = .numeric := by
  unfold outputCheck
  simp_all

end IntentFrame

namespace KinematicControlFrame

/-- Step 1, `NONE` only where 05:34 allows it. -/
def noneOK (d : Decl) (f : KinematicControlFrame) : Prop :=
  d = .override ∨ ∀ g, stated d g = true → f.modeNat g ≠ 0

/-- Step 1. The frame has no counts and no `char` fields. -/
def wellFormed (d : Decl) (f : KinematicControlFrame) : Prop := f.noneOK d

/-- Step 2. `jerk_lon_cmd` under `ACCEL` and `steer_rate_cmd` under `ANGLE`
are bounds (05:36). -/
def finiteOK (f : KinematicControlFrame) : Prop :=
  (f.uses .aLonCmd = true → f.aLonCmd.Finite) ∧
    (f.uses .jerkLonCmd = true →
      f.jerkLonCmd.Finite ∨ (f.accel = .accel ∧ f.jerkLonCmd = .posInf)) ∧
    (f.uses .steerAngleCmd = true → f.steerAngleCmd.Finite) ∧
    (f.uses .steerRateCmd = true →
      f.steerRateCmd.Finite ∨ (f.steer = .angle ∧ f.steerRateCmd = .posInf))

open Classical in
/-- The output check of one `KinematicControlFrame` of declared type `d`. -/
noncomputable def outputCheck (d : Decl) (f : KinematicControlFrame) : CheckResult :=
  if ¬ f.wellFormed d then .invalidArg
  else if ¬ f.finiteOK then .numeric
  else if f.valid d then .ok else .invalidArg

theorem outputCheck_ok {d : Decl} {f : KinematicControlFrame} :
    f.outputCheck d = .ok ↔ f.wellFormed d ∧ f.finiteOK ∧ f.valid d := by
  unfold outputCheck
  split_ifs <;> simp_all

theorem outputCheck_numeric {d : Decl} {f : KinematicControlFrame} (hw : f.wellFormed d)
    (hf : ¬ f.finiteOK) : f.outputCheck d = .numeric := by
  unfold outputCheck
  simp_all

theorem outputCheck_invalid {d : Decl} {f : KinematicControlFrame} (hw : f.wellFormed d)
    (hf : f.finiteOK) (hv : ¬ f.valid d) : f.outputCheck d = .invalidArg := by
  unfold outputCheck
  simp_all

end KinematicControlFrame

namespace ActuatorControlFrame

/-- Step 1, `NONE` only where 05:34 allows it. -/
def noneOK (d : Decl) (f : ActuatorControlFrame) : Prop :=
  d = .override ∨ ∀ g, f.modeNat g ≠ 0

/-- Step 1. The frame has no counts and no `char` fields. -/
def wellFormed (d : Decl) (f : ActuatorControlFrame) : Prop := f.noneOK d

/-- Step 2. No field of this frame is a bound. -/
def finiteOK (f : ActuatorControlFrame) : Prop :=
  (f.uses .throttle = true → f.throttle.Finite) ∧ (f.uses .brake = true → f.brake.Finite) ∧
    (f.uses .steeringWheelNorm = true → f.steeringWheelNorm.Finite) ∧
    (f.uses .steeringTorqueNm = true → f.steeringTorqueNm.Finite)

open Classical in
/-- The output check of one `ActuatorControlFrame` of declared type `d`. -/
noncomputable def outputCheck (numGears : Nat) (d : Decl) (f : ActuatorControlFrame) :
    CheckResult :=
  if ¬ f.wellFormed d then .invalidArg
  else if ¬ f.finiteOK then .numeric
  else if f.valid numGears d then .ok else .invalidArg

theorem outputCheck_ok {n : Nat} {d : Decl} {f : ActuatorControlFrame} :
    f.outputCheck n d = .ok ↔ f.wellFormed d ∧ f.finiteOK ∧ f.valid n d := by
  unfold outputCheck
  split_ifs <;> simp_all

theorem outputCheck_numeric {n : Nat} {d : Decl} {f : ActuatorControlFrame}
    (hw : f.wellFormed d) (hf : ¬ f.finiteOK) : f.outputCheck n d = .numeric := by
  unfold outputCheck
  simp_all

end ActuatorControlFrame

/-! ## Decidability of `IntentFrame` validity (05:66)

The order on `ℝ` is decidable only classically in Mathlib, so these instances
are noncomputable. They are built rule by rule from the decisions of the parts,
and need decidable map predicates. -/

namespace F64

noncomputable instance decLt (a b : F64) : Decidable (a < b) := by
  cases a <;> cases b <;>
    first | exact Real.decidableLT _ _ | exact isTrue trivial | exact isFalse id

noncomputable instance decEq : DecidableEq F64 := fun a b => by
  cases a <;> cases b <;>
    first | exact isTrue rfl | exact isFalse nofun | exact decidable_of_iff _ ⟨congrArg fin, fin.inj⟩

noncomputable instance decLe (a b : F64) : Decidable (a ≤ b) :=
  inferInstanceAs (Decidable (a < b ∨ (a = b ∧ a ≠ nan)))

noncomputable instance decInIoc (lo hi : ℝ) (a : F64) : Decidable (a.inIoc lo hi) := by
  cases a <;> unfold inIoc <;> infer_instance

end F64

namespace IntentFrame

instance decPOR (d : Decl) (f : IntentFrame) : Decidable (f.partialOverrideRule d) := by
  unfold partialOverrideRule
  rw [IntentGroup.forall_iff]
  infer_instance

noncomputable instance decStt (f : IntentFrame) : Decidable f.sttRule := by
  unfold sttRule trajOK timesIncrease
  infer_instance

instance decLane (map : RoadMap) [∀ r, Decidable (map.road r)] [∀ r l, Decidable (map.lane r l)]
    (f : IntentFrame) : Decidable (f.laneRule map) := by
  unfold laneRule
  infer_instance

noncomputable instance decPolyline (f : IntentFrame) : Decidable f.polylineRule := by
  unfold polylineRule pathOK
  infer_instance

noncomputable instance decGap (f : IntentFrame) : Decidable f.gapRule := by
  unfold gapRule
  infer_instance

noncomputable instance decValid (map : RoadMap) [∀ r, Decidable (map.road r)]
    [∀ r l, Decidable (map.lane r l)] (d : Decl) (f : IntentFrame) :
    Decidable (f.valid map d) := by
  unfold valid
  infer_instance

end IntentFrame

end Driveline

namespace Driveline.Validity

/-- P05-02. 'Every full frame states every group' (docs/spec/05-checkpoints.md:14):
a valid full frame has no `NONE` group. -/
theorem full_states_every_group :
    (∀ (map : RoadMap) (f : IntentFrame), f.valid map .full → ∀ g, f.modeNat g ≠ 0) ∧
    (∀ f : KinematicControlFrame, f.valid .full → ∀ g, f.modeNat g ≠ 0) ∧
    (∀ (n : Nat) (f : ActuatorControlFrame), f.valid n .full → ∀ g, f.modeNat g ≠ 0) := by
  refine ⟨fun _ f hv g => ?_, fun f hv g => ?_, fun _ f hv g => ?_⟩
  · rcases hv.1 with h | ⟨h, -⟩
    · cases h
    · exact (h g).1 (by cases g <;> rfl)
  · rcases hv.1 with h | h
    · cases h
    · exact (h g).1 (by cases g <;> rfl)
  · rcases hv.1 with h | ⟨-, h⟩
    · cases h
    · exact h g

/-- P05-08. 'A `Lon<T>` frame ... states the `LON` group and has every other
group `NONE`. ... A stated group is never `NONE`, and neither uses
`SPATIOTEMPORAL_TRAJECTORY`' (docs/spec/05-checkpoints.md:34). -/
theorem lon_frame_groups :
    (∀ f : IntentFrame, f.partialOverrideRule .lon ↔
      f.lon ≠ .none ∧ f.lon ≠ .stt ∧ f.lat = .none ∧ f.signal = .none) ∧
    (∀ f : KinematicControlFrame, f.partialOverrideRule .lon ↔
      f.accel ≠ .none ∧ f.steer = .none) ∧
    (∀ (n : Nat) (f : ActuatorControlFrame), ¬ f.valid n .lon) :=
  ⟨IntentFrame.pOR_lon, KinematicControlFrame.pOR_lon, fun _ _ ⟨h, _⟩ => by
    rcases h with h | ⟨h, _⟩ <;> cases h⟩

/-- P05-09. 'A `Lat<T>` frame states `LAT`, and for `IntentFrame` also
`SIGNAL`, and has `LON` `NONE`' (docs/spec/05-checkpoints.md:34). -/
theorem lat_frame_groups :
    (∀ f : IntentFrame, f.partialOverrideRule .lat ↔
      f.lat ≠ .none ∧ f.lat ≠ .stt ∧ f.signal ≠ .none ∧ f.lon = .none) ∧
    (∀ f : KinematicControlFrame, f.partialOverrideRule .lat ↔
      f.steer ≠ .none ∧ f.accel = .none) ∧
    (∀ (n : Nat) (f : ActuatorControlFrame), ¬ f.valid n .lat) :=
  ⟨IntentFrame.pOR_lat, KinematicControlFrame.pOR_lat, fun _ _ ⟨h, _⟩ => by
    rcases h with h | ⟨h, _⟩ <;> cases h⟩

/-- P05-10. 'An `Override<T>` frame ... may have any group `NONE`. Every other
frame has no `NONE` group' (docs/spec/05-checkpoints.md:34). A valid full frame
is a valid override, and an override with every group `NONE` is valid. -/
theorem full_is_override :
    (∀ (map : RoadMap) (f : IntentFrame), f.valid map .full → f.valid map .override) ∧
    (∀ (map : RoadMap) (f : IntentFrame),
      ({ f with lon := .none, lat := .none, signal := .none } : IntentFrame).valid map .override) ∧
    (∀ f : KinematicControlFrame, f.valid .full → f.valid .override) ∧
    (∀ f : KinematicControlFrame,
      ({ f with accel := .none, steer := .none } : KinematicControlFrame).valid .override) ∧
    (∀ (n : Nat) (f : ActuatorControlFrame), f.valid n .full → f.valid n .override) ∧
    (∀ (n : Nat) (f : ActuatorControlFrame),
      ({ f with pedal := .none, wheel := .none, gear := .none } : ActuatorControlFrame).valid
        n .override) := by
  refine ⟨fun _ _ ⟨_, h⟩ => ⟨Or.inl rfl, h⟩, fun _ _ => ?_, fun _ ⟨_, h⟩ => ⟨Or.inl rfl, h⟩,
    fun _ => ⟨Or.inl rfl, nofun, nofun⟩, fun _ _ ⟨_, h⟩ => ⟨Or.inl rfl, h⟩,
    fun _ _ => ⟨Or.inl rfl, nofun, nofun, nofun⟩⟩
  exact ⟨Or.inl rfl, ⟨⟨nofun, nofun⟩, nofun⟩, nofun, nofun, nofun, nofun, nofun,
    nofun⟩

/-- P05-11. 'A full frame that a step produces and that reaches a `Lon<T>` or
`Lat<T>` port ... is valid only if, in addition, it does not use
`SPATIOTEMPORAL_TRAJECTORY`' (docs/spec/05-checkpoints.md:34), with the
conversion at the port of 05:40. At a partial port, a full frame is valid if and
only if it is valid and does not use STT; a partial frame, and any frame at a
full port, needs only `valid`. Such a frame converts to valid partial frames.
`KinematicControlFrame` has no STT mode, so every valid full frame converts. The
last conjunct shows that the exclusion is needed. -/
theorem port_conversion :
    (∀ (map : RoadMap) (f : IntentFrame),
      f.validAt map .full true ↔ f.valid map .full ∧ ¬ f.usesSTT) ∧
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame), d ≠ .full →
      (f.validAt map d true ↔ f.valid map d)) ∧
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame), f.validAt map d false ↔ f.valid map d) ∧
    (∀ (map : RoadMap) (f : IntentFrame), f.validAt map .full true →
      f.toLon.valid map .lon ∧ f.toLat.valid map .lat) ∧
    (∀ f : KinematicControlFrame, f.valid .full → f.toLon.valid .lon ∧ f.toLat.valid .lat) ∧
    (∀ map : RoadMap, ∃ f : IntentFrame, f.valid map .full ∧ ¬ f.validAt map .full true ∧
      ¬ f.toLon.valid map .lon) := by
  refine ⟨fun _ _ => ⟨fun ⟨h, s⟩ => ⟨h, s rfl rfl⟩, fun ⟨h, s⟩ => ⟨h, fun _ _ => s⟩⟩,
    fun _ _ _ hd => ⟨fun h => h.1, fun h => ⟨h, fun _ h' => absurd h' hd⟩⟩,
    fun _ _ _ => ⟨fun h => h.1, fun h => ⟨h, nofun⟩⟩, fun map f ⟨hv, hs⟩ => ?_,
    fun f hv => ?_, fun map => ?_⟩
  · replace hs := hs rfl rfl
    obtain ⟨hp, ⟨_, _⟩, hlane, hpoly, hgap⟩ := hv
    obtain ⟨h1, h2, h3⟩ := (IntentFrame.pOR_full f).mp hp
    have hl : f.lon ≠ .stt := fun h => hs (Or.inl h)
    have ht : f.lat ≠ .stt := fun h => hs (Or.inr h)
    constructor
    · refine (IntentFrame.zero_valid_iff _ _ _).mpr ⟨(IntentFrame.pOR_lon _).mpr
        ⟨h1, hl, rfl, rfl⟩, ⟨⟨fun h => absurd h hl, nofun⟩, fun h => absurd h hl⟩,
        nofun, nofun, IntentFrame.gapRule_mono (f := f) id (fun fld h => ?_) rfl rfl rfl rfl hgap⟩
      simp only [IntentFrame.uses, LatMode.none_uses, Bool.or_false] at h
      exact IntentFrame.uses_of_lon h
    · refine (IntentFrame.zero_valid_iff _ _ _).mpr ⟨(IntentFrame.pOR_lat _).mpr
        ⟨h2, ht, h3, rfl⟩, ⟨⟨nofun, fun h => absurd h ht⟩, nofun⟩, hlane, hpoly,
        IntentFrame.gapRule_mono (f := f) (by intro h; cases h) (fun fld h => ?_) rfl rfl rfl rfl
        hgap⟩
      simp only [IntentFrame.uses, LonMode.none_uses, Bool.false_or] at h
      exact IntentFrame.uses_of_lat h
  · obtain ⟨hp, ha, hs⟩ := hv
    obtain ⟨h1, h2⟩ := (KinematicControlFrame.pOR_full f).mp hp
    exact ⟨(KinematicControlFrame.zero_valid_iff _ _).mpr
        ⟨(KinematicControlFrame.pOR_lon _).mpr ⟨h1, rfl⟩, ha, nofun⟩,
      (KinematicControlFrame.zero_valid_iff _ _).mpr
        ⟨(KinematicControlFrame.pOR_lat _).mpr ⟨h2, rfl⟩, nofun, hs⟩⟩
  · refine ⟨{ IntentFrame.blank ⟨0, 0⟩ with
      lon := .stt, lat := .stt, signal := .off, numTrajPoints := 1 }, ?_, fun h => ?_⟩
    · refine ⟨(IntentFrame.pOR_full _).mpr ⟨nofun, nofun, nofun⟩,
        ⟨⟨fun _ => rfl, fun _ => rfl⟩, fun _ => ⟨le_refl 1, by decide,
          fun _ _ => ⟨le_refl 0, F64.zero_le_zero, F64.inIoc_zero_pi⟩,
          fun i j hij hj => by
            change j.val < 1 at hj
            have : i.val < j.val := hij
            omega⟩⟩,
        nofun, nofun, nofun, nofun, nofun, nofun⟩
    · exact fun h => h.2 rfl rfl (Or.inl rfl)
    · exact ((IntentFrame.pOR_lon _).mp
        ((IntentFrame.zero_valid_iff _ _ _).mp h).1).2.1 rfl

/-- P05-12. '`jerk_lon_cmd` under `ACCEL`, `steer_rate_cmd` under `ANGLE`, and
`stop_at_odometer` bound other fields. The value `+INFINITY` means no bound'
(docs/spec/05-checkpoints.md:36), with the output check of
docs/spec/14-diagnostics.md item 4. `+∞` in one of the three bound fields under
its bound mode keeps a frame that passes the check passing. Any other used
`IntentFrame` field that is not finite, and a NaN or `-∞` stop target, fail with
`DL_STATUS_ERR_NUMERIC`. With 'a value at or below zero means stop now' (05:78),
a `+∞` stop target never stops. -/
theorem infinity_no_bound :
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame), f.outputCheck map d = .ok →
      ({ f with stopAtOdometer := .posInf } : IntentFrame).outputCheck map d = .ok) ∧
    (∀ (d : Decl) (f : KinematicControlFrame), f.outputCheck d = .ok → f.accel = .accel →
      ({ f with jerkLonCmd := .posInf } : KinematicControlFrame).outputCheck d = .ok) ∧
    (∀ (d : Decl) (f : KinematicControlFrame), f.outputCheck d = .ok → f.steer = .angle →
      ({ f with steerRateCmd := .posInf } : KinematicControlFrame).outputCheck d = .ok) ∧
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame) (x : F64), ¬ x.Finite → f.wellFormed d →
      (f.uses .aRef = true ∧ f.aRef = x ∨ f.uses .vRef = true ∧ f.vRef = x ∨
        f.uses .timeGapRef = true ∧ f.timeGapRef = x ∨
        f.uses .distanceGapMin = true ∧ f.distanceGapMin = x ∨ f.uses .dRef = true ∧ f.dRef = x ∨
        f.uses .stopAtOdometer = true ∧ f.stopAtOdometer = x ∧ x ≠ .posInf) →
      f.outputCheck map d = .numeric) ∧
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame), f.wellFormed d →
      (f.uses .pathPoints = true ∧
          ∃ i : Fin 64, i.val < f.numWaypoints ∧ ¬ (f.pathPoints i).Finite ∨
        f.uses .trajectory = true ∧
          ∃ i : Fin 64, i.val < f.numTrajPoints ∧ ¬ (f.trajectory i).Finite) →
      f.outputCheck map d = .numeric) ∧
    (∀ odo : ℝ, ¬ stopNow .posInf odo) := by
  refine ⟨fun map d f h => ?_, fun d f h ha => ?_, fun d f h hs => ?_,
    fun map d f x hx hw h => IntentFrame.outputCheck_numeric hw fun hf => ?_,
    fun map d f hw h => IntentFrame.outputCheck_numeric hw fun hf => ?_, not_stopNow_posInf⟩
  · obtain ⟨hw, ⟨h1, h2, -, h4, h5, h6, h7, h8⟩, hv⟩ := IntentFrame.outputCheck_ok.1 h
    exact IntentFrame.outputCheck_ok.2 ⟨hw, ⟨h1, h2, fun _ => Or.inr rfl, h4, h5, h6, h7, h8⟩, hv⟩
  · obtain ⟨hw, ⟨h1, -, h3, h4⟩, hp, -, hv⟩ := KinematicControlFrame.outputCheck_ok.1 h
    exact KinematicControlFrame.outputCheck_ok.2
      ⟨hw, ⟨h1, fun _ => Or.inr ⟨ha, rfl⟩, h3, h4⟩, hp, fun _ => F64.zero_lt_posInf, hv⟩
  · obtain ⟨hw, ⟨h1, h2, h3, -⟩, hp, hv, -⟩ := KinematicControlFrame.outputCheck_ok.1 h
    exact KinematicControlFrame.outputCheck_ok.2
      ⟨hw, ⟨h1, h2, h3, fun _ => Or.inr ⟨hs, rfl⟩⟩, hp, hv, fun _ => F64.zero_lt_posInf⟩
  · obtain ⟨h1, h2, h3, h4, h5, h6, -, -⟩ := hf
    rcases h with ⟨hu, he⟩ | ⟨hu, he⟩ | ⟨hu, he⟩ | ⟨hu, he⟩ | ⟨hu, he⟩ | ⟨hu, he, hne⟩
    · exact hx (he ▸ h1 hu)
    · exact hx (he ▸ h2 hu)
    · exact hx (he ▸ h4 hu)
    · exact hx (he ▸ h5 hu)
    · exact hx (he ▸ h6 hu)
    · rcases h3 hu with h | h
      · exact hx (he ▸ h)
      · exact hne (he ▸ h)
  · obtain ⟨-, -, -, -, -, -, h7, h8⟩ := hf
    rcases h with ⟨hu, i, hi, hn⟩ | ⟨hu, i, hi, hn⟩
    · exact hn (h7 hu i hi)
    · exact hn (h8 hu i hi)

/-- P05-14. 'After the check, the runtime sets every field that the frame's
modes do not use, and every array entry past its count, to zero, so the bytes
that consumers receive are deterministic' (docs/spec/05-checkpoints.md:38).
For each frame: zeroing is idempotent, keeps validity, keeps the used fields,
and depends only on the header, the modes and the used fields. -/
theorem zeroing :
    (∀ f : IntentFrame, f.zero.zero = f.zero) ∧
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame), f.valid map d → f.zero.valid map d) ∧
    (∀ (f : IntentFrame) fld, f.uses fld = true → f.zero.agreeOn fld f) ∧
    (∀ f g : IntentFrame, f.header = g.header →
      (f.lon = g.lon ∧ f.lat = g.lat ∧ f.signal = g.signal) →
      (∀ fld, f.uses fld = true → f.agreeOn fld g) → f.zero = g.zero) ∧
    (∀ f : KinematicControlFrame, f.zero.zero = f.zero) ∧
    (∀ (d : Decl) (f : KinematicControlFrame), f.valid d → f.zero.valid d) ∧
    (∀ (f : KinematicControlFrame) fld, f.uses fld = true → f.zero.agreeOn fld f) ∧
    (∀ f g : KinematicControlFrame, f.header = g.header →
      (f.accel = g.accel ∧ f.steer = g.steer) →
      (∀ fld, f.uses fld = true → f.agreeOn fld g) → f.zero = g.zero) ∧
    (∀ f : ActuatorControlFrame, f.zero.zero = f.zero) ∧
    (∀ (n : Nat) (d : Decl) (f : ActuatorControlFrame), f.valid n d → f.zero.valid n d) ∧
    (∀ (f : ActuatorControlFrame) fld, f.uses fld = true → f.zero.agreeOn fld f) ∧
    (∀ f g : ActuatorControlFrame, f.header = g.header →
      (f.pedal = g.pedal ∧ f.wheel = g.wheel ∧ f.gear = g.gear) →
      (∀ fld, f.uses fld = true → f.agreeOn fld g) → f.zero = g.zero) :=
  ⟨IntentFrame.zero_idem, fun map d f => (IntentFrame.zero_valid_iff map d f).mpr,
    IntentFrame.zero_keeps, IntentFrame.zero_determined,
    KinematicControlFrame.zero_idem, fun d f => (KinematicControlFrame.zero_valid_iff d f).mpr,
    KinematicControlFrame.zero_keeps, KinematicControlFrame.zero_determined,
    ActuatorControlFrame.zero_idem, fun n d f => (ActuatorControlFrame.zero_valid_iff n d f).mpr,
    ActuatorControlFrame.zero_keeps, ActuatorControlFrame.zero_determined⟩

/-- P05-17. 'An `IntentFrame` is valid if and only if every rule below holds,
together with the Partial and Override rule above'
(docs/spec/05-checkpoints.md:66). Given decidable map predicates, validity is
decidable (`IntentFrame.decValid`), and the decision is the conjunction of the
decisions of the five rules. The mode-value rule holds by the enum types. -/
theorem intent_valid_decidable (map : RoadMap) [∀ r, Decidable (map.road r)]
    [∀ r l, Decidable (map.lane r l)] (d : Decl) (f : IntentFrame) :
    Nonempty (Decidable (f.valid map d)) ∧
      decide (f.valid map d) = (decide (f.partialOverrideRule d) && decide f.sttRule &&
        decide (f.laneRule map) && decide f.polylineRule && decide f.gapRule) := by
  refine ⟨⟨inferInstance⟩, ?_⟩
  simp [IntentFrame.valid, Bool.and_assoc]

theorem timesIncrease_of_adjacent {n : Nat} (hn : n ≤ 64) {t : Fin 64 → Int}
    (h : ∀ k (hk : k + 1 < n), t ⟨k, by omega⟩ < t ⟨k + 1, by omega⟩) :
    timesIncrease n t := by
  have key : ∀ d i (hi : i + d + 1 < n), t ⟨i, by omega⟩ < t ⟨i + d + 1, by omega⟩ := by
    intro d
    induction d with
    | zero => exact fun i hi => h i hi
    | succ d ih => exact fun i hi => lt_trans (ih i (by omega)) (h (i + d + 1) hi)
  rintro ⟨i, hi⟩ ⟨j, hj⟩ hij hjn
  change i < j at hij
  change j < n at hjn
  obtain ⟨d, rfl⟩ : ∃ d, j = i + d + 1 := ⟨j - i - 1, by omega⟩
  exact key d i hjn

/-- P05-18. '`lon_mode` is `SPATIOTEMPORAL_TRAJECTORY` if and only if `lat_mode`
is. Then ... the trajectory times are not negative and strictly increase'
(docs/spec/05-checkpoints.md:68). The adjacent-pair check that a runtime runs is
equivalent to the pairwise rule of the model and to `StrictMono`. -/
theorem stt_trajectory_rule :
    (∀ (n : Nat) (hn : n ≤ 64) (t : Fin 64 → Int64),
      ((∀ k (hk : k + 1 < n), (t ⟨k, by omega⟩).toInt < (t ⟨k + 1, by omega⟩).toInt) ↔
        timesIncrease n fun i => (t i).toInt) ∧
      (timesIncrease n (fun i => (t i).toInt) ↔
        StrictMono fun i : Fin n => (t (Fin.castLE hn i)).toInt)) ∧
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame), f.valid map d →
      (f.lon = .stt ↔ f.lat = .stt)) := by
  refine ⟨fun n hn t => ⟨⟨timesIncrease_of_adjacent (t := fun i => (t i).toInt) hn, fun h k hk => ?_⟩, ⟨fun h a b hab => ?_,
    fun h i j hij hj => ?_⟩⟩, fun _ _ _ hv => hv.2.1.1⟩
  · exact h ⟨k, by omega⟩ ⟨k + 1, by omega⟩ (Nat.lt_succ_self k) hk
  · exact h _ _ hab (by simp)
  · exact h (a := ⟨i.val, Nat.lt_trans hij hj⟩) (b := ⟨j.val, hj⟩) hij

/-- P05-20. 'With `GAP_PROFILE`, `gap_target_actor_id` is not 0. Where they
apply, `v_ref`, `time_gap_ref`, and `distance_gap_min` are not negative'
(docs/spec/05-checkpoints.md:70), on every frame that passes the output check of
docs/spec/14-diagnostics.md item 4. The finiteness step runs first, so each of
these fields is a real at least 0. -/
theorem gap_rule :
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame), f.outputCheck map d = .ok →
      f.lon = .gapProfile → f.gapTargetActorId ≠ 0 ∧
        (∃ v : ℝ, f.vRef = .fin v ∧ 0 ≤ v) ∧ (∃ t : ℝ, f.timeGapRef = .fin t ∧ 0 ≤ t) ∧
        (∃ g : ℝ, f.distanceGapMin = .fin g ∧ 0 ≤ g)) ∧
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame), f.outputCheck map d = .ok →
      f.uses .vRef = true → ∃ v : ℝ, f.vRef = .fin v ∧ 0 ≤ v) := by
  refine ⟨fun map d f h hg => ?_, fun map d f h hu => ?_⟩
  · obtain ⟨-, ⟨-, h2, -, h4, h5, -⟩, ⟨-, -, -, -, ⟨g1, g2, g3, g4⟩⟩⟩ :=
      IntentFrame.outputCheck_ok.1 h
    have hv : f.uses .vRef = true := IntentFrame.uses_of_lon (by rw [hg]; rfl)
    have ht : f.uses .timeGapRef = true := IntentFrame.uses_of_lon (by rw [hg]; rfl)
    have hd : f.uses .distanceGapMin = true := IntentFrame.uses_of_lon (by rw [hg]; rfl)
    exact ⟨g1 hg, (h2 hv).nonneg (g2 hv), (h4 ht).nonneg (g3 ht), (h5 hd).nonneg (g4 hd)⟩
  · obtain ⟨-, ⟨-, h2, -⟩, ⟨-, -, -, -, ⟨-, g2, -⟩⟩⟩ := IntentFrame.outputCheck_ok.1 h
    exact (h2 hu).nonneg (g2 hu)

/-- P05-27. 'A component that receives a mode it does not implement returns
`DL_STATUS_ERR_UNSUPPORTED_MODE` ... `NONE` is never checked', and 'a field that
it does not list accepts every mode' (docs/spec/05-checkpoints.md:82). -/
theorem unsupported_mode_check {α : Type} [ModeEnum α] [DecidableEq α] :
    (∀ L : Option (List α), supports L ModeEnum.none = true) ∧
    (∀ m : α, supports none m = true) ∧
    (∀ (l : List α) (m : α), m ≠ ModeEnum.none → (supports (some l) m = true ↔ m ∈ l)) :=
  ⟨fun _ => by simp [supports], fun _ => by simp [supports],
    fun _ _ h => by simp [supports, h]⟩

/-- P05-29. 'A `KinematicControlFrame` is valid if and only if the Partial and
Override rule holds, each mode field holds one of its listed values, and the
bounds under `ACCEL` and `ANGLE` are above zero' (docs/spec/05-checkpoints.md:98),
with the output check of docs/spec/14-diagnostics.md item 4. A passing frame has
its bounds above zero, and a finite bound at or below zero fails with
`DL_STATUS_ERR_INVALID_ARG`. A used field that is not finite fails with
`DL_STATUS_ERR_NUMERIC`, except `+∞` in a bound field under its bound mode
(`infinity_no_bound`): NaN anywhere, and `+∞` in `jerk_lon_cmd` under `JERK` or
`steer_rate_cmd` under `RATE`, are numeric errors. -/
theorem kinematic_bounds_above_zero :
    (∀ (d : Decl) (f : KinematicControlFrame), f.outputCheck d = .ok →
      (f.accel = .accel → (0 : F64) < f.jerkLonCmd) ∧
        (f.steer = .angle → (0 : F64) < f.steerRateCmd)) ∧
    (∀ (d : Decl) (f : KinematicControlFrame) (x : ℝ), f.wellFormed d → f.finiteOK →
      (f.accel = .accel ∧ f.jerkLonCmd = .fin x ∨ f.steer = .angle ∧ f.steerRateCmd = .fin x) →
      x ≤ 0 → f.outputCheck d = .invalidArg) ∧
    (∀ (d : Decl) (f : KinematicControlFrame) (x : F64), ¬ x.Finite → f.wellFormed d →
      (f.uses .aLonCmd = true ∧ f.aLonCmd = x ∨ f.accel = .jerk ∧ f.jerkLonCmd = x ∨
        f.uses .steerAngleCmd = true ∧ f.steerAngleCmd = x ∨
        f.steer = .rate ∧ f.steerRateCmd = x ∨
        f.uses .jerkLonCmd = true ∧ f.jerkLonCmd = x ∧ x ≠ .posInf ∨
        f.uses .steerRateCmd = true ∧ f.steerRateCmd = x ∧ x ≠ .posInf) →
      f.outputCheck d = .numeric) := by
  refine ⟨fun d f h => (KinematicControlFrame.outputCheck_ok.1 h).2.2.2, fun d f x hw hf h hx =>
    KinematicControlFrame.outputCheck_invalid hw hf fun hv => ?_,
    fun d f x hx hw h => KinematicControlFrame.outputCheck_numeric hw fun hf => ?_⟩
  · have key : ¬ (0 : F64) < .fin x := by
      rw [F64.zero_def, F64.fin_lt_fin]; exact not_lt.2 hx
    rcases h with ⟨ha, he⟩ | ⟨hs, he⟩
    · exact key (he ▸ hv.2.1 ha)
    · exact key (he ▸ hv.2.2 hs)
  · obtain ⟨h1, h2, h3, h4⟩ := hf
    rcases h with ⟨hu, he⟩ | ⟨ha, he⟩ | ⟨hu, he⟩ | ⟨hs, he⟩ | ⟨hu, he, hne⟩ | ⟨hu, he, hne⟩
    · exact hx (he ▸ h1 hu)
    · rcases h2 (by simp [KinematicControlFrame.uses, ha, AccelMode.uses]) with h | ⟨h, -⟩
      · exact hx (he ▸ h)
      · rw [ha] at h; cases h
    · exact hx (he ▸ h3 hu)
    · rcases h4 (by simp [KinematicControlFrame.uses, hs, SteerMode.uses]) with h | ⟨h, -⟩
      · exact hx (he ▸ h)
      · rw [hs] at h; cases h
    · rcases h2 hu with h | ⟨-, h⟩
      · exact hx (he ▸ h)
      · exact hne (he ▸ h)
    · rcases h4 hu with h | ⟨-, h⟩
      · exact hx (he ▸ h)
      · exact hne (he ▸ h)

/-- P05-30. 'An `ActuatorControlFrame` is valid if and only if the Override
rule holds, each mode field holds one of its listed values, `throttle` and
`brake` lie in `[0, 1]` under `PEDALS`, `steering_wheel_norm` lies in `[-1, 1]`
under `ANGLE`, and under `DRIVE` `manual_gear_index` is from 0 to `num_gears`
(so 0 without Tier 2)' (docs/spec/05-checkpoints.md:114), with the output check
of docs/spec/14-diagnostics.md item 4. A passing frame satisfies the ranges, and
a used field that is not finite (NaN or an infinity) fails with
`DL_STATUS_ERR_NUMERIC`, since no field of this frame is a bound. That
`num_gears` is 0 without Tier 2 is a §3 fact. -/
theorem actuator_ranges :
    (∀ (n : Nat) (d : Decl) (f : ActuatorControlFrame), f.outputCheck n d = .ok →
      (f.pedal = .pedals → f.throttle.inIcc 0 1 ∧ f.brake.inIcc 0 1) ∧
        (f.wheel = .angle → f.steeringWheelNorm.inIcc (-1) 1) ∧
        (f.gear = .drive → 0 ≤ f.manualGearIndex.toInt ∧ f.manualGearIndex.toInt ≤ n)) ∧
    (∀ (d : Decl) (f : ActuatorControlFrame), f.outputCheck 0 d = .ok → f.gear = .drive →
      f.manualGearIndex = 0) ∧
    (∀ (n : Nat) (d : Decl) (f : ActuatorControlFrame) (x : F64), ¬ x.Finite →
      f.wellFormed d →
      (f.uses .throttle = true ∧ f.throttle = x ∨ f.uses .brake = true ∧ f.brake = x ∨
        f.uses .steeringWheelNorm = true ∧ f.steeringWheelNorm = x ∨
        f.uses .steeringTorqueNm = true ∧ f.steeringTorqueNm = x) →
      f.outputCheck n d = .numeric) := by
  refine ⟨fun _ _ _ h => (ActuatorControlFrame.outputCheck_ok.1 h).2.2.2, fun _ f h hg => ?_,
    fun n d f x hx hw h => ActuatorControlFrame.outputCheck_numeric hw fun hf => ?_⟩
  · obtain ⟨h0, h1⟩ := (ActuatorControlFrame.outputCheck_ok.1 h).2.2.2.2.2 hg
    exact Int8.toInt_inj.mp (by simp only [Int8.toInt_zero]; push_cast at h1; omega)
  · obtain ⟨h1, h2, h3, h4⟩ := hf
    rcases h with ⟨hu, he⟩ | ⟨hu, he⟩ | ⟨hu, he⟩ | ⟨hu, he⟩
    · exact hx (he ▸ h1 hu)
    · exact hx (he ▸ h2 hu)
    · exact hx (he ▸ h3 hu)
    · exact hx (he ▸ h4 hu)

/-- P05-31. 'A `KinematicState` is valid if and only if `yaw` and `roll` lie in
`(-π, π]` and `pitch` lies in `(-π/2, π/2)`' (docs/spec/05-checkpoints.md:119).
`pitch = π/2` is excluded, and the rule is satisfiable. -/
theorem kinematic_state_angles :
    (∀ s : KinematicState, s.valid ↔ s.yaw.inIoc (-Real.pi) Real.pi ∧
      s.roll.inIoc (-Real.pi) Real.pi ∧ s.pitch.inIoo (-(Real.pi / 2)) (Real.pi / 2)) ∧
    (∀ s : KinematicState, ¬ ({ s with pitch := .fin (Real.pi / 2) } : KinematicState).valid) ∧
    (∃ s : KinematicState, s.valid) :=
  ⟨fun _ => Iff.rfl, fun _ ⟨_, _, _, h⟩ => lt_irrefl _ h,
    ⟨⟨⟨0, 0⟩, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, "", 0, 0, 0, 0⟩,
      F64.inIoc_zero_pi, F64.inIoc_zero_pi, F64.inIoo_zero_half_pi⟩⟩

end Driveline.Validity
