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

05:70 says `v_ref`, `time_gap_ref` and `distance_gap_min` are 'not negative'.
This model reads that literally as `¬ x < 0`, which accepts NaN. `gap_rule`
records the gap.
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
  · rw [← h i (Nat.lt_trans hij hj), ← h j hj]; exact h4 i j hij hj
  · rw [h i hi]; exact h3 i hi
  · rw [h i (Nat.lt_trans hij hj), h j hj]; exact h4 i j hij hj

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

/-- 05:70. 'Where they apply' is where the modes use the field; 'not
negative' is read literally. -/
def gapRule (f : IntentFrame) : Prop :=
  (f.lon = .gapProfile → f.gapTargetActorId ≠ 0) ∧
    (f.uses .vRef = true → ¬ f.vRef < 0) ∧
    (f.uses .timeGapRef = true → ¬ f.timeGapRef < 0) ∧
    (f.uses .distanceGapMin = true → ¬ f.distanceGapMin < 0)

/-- A valid `IntentFrame` of declared type `d` (05:66). -/
def valid (f : IntentFrame) (map : RoadMap) (d : Decl) : Prop :=
  f.partialOverrideRule d ∧ f.sttRule ∧ f.laneRule map ∧ f.polylineRule ∧ f.gapRule

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
    rw [show f.numTrajPoints = g.numTrajPoints from hu _ hn]
    rw [show f.numTrajPoints = g.numTrajPoints from hu _ hn] at htr
    exact trajOK_congr (hu _ htr)
  have hlane : f.laneRule map ↔ g.laneRule map := by
    unfold laneRule
    rw [← ht]
    refine imp_congr_right fun h => ?_
    rw [show f.targetRoadId = g.targetRoadId from hu _ (uses_of_lat (by rw [h]; rfl)),
      show f.targetLaneId = g.targetLaneId from hu _ (uses_of_lat (by rw [h]; rfl))]
  have hpoly : f.polylineRule ↔ g.polylineRule := by
    unfold polylineRule
    rw [← ht]
    refine imp_congr_right fun h => ?_
    have hp : f.uses .pathPoints = true := uses_of_lat (by rw [h]; rfl)
    have e : f.numWaypoints = g.numWaypoints := hu _ (uses_of_lat (by rw [h]; rfl))
    have hp' := hu _ hp
    rw [e] at hp' ⊢
    exact pathOK_congr hp'
  have hgap : f.gapRule ↔ g.gapRule := by
    unfold gapRule
    rw [← hl, hU, hU, hU]
    refine and_congr (imp_congr_right fun h => ?_) (and_congr (imp_congr_right fun h => ?_)
      (and_congr (imp_congr_right fun h => ?_) (imp_congr_right fun h => ?_)))
    · rw [show f.gapTargetActorId = g.gapTargetActorId from
        hu _ (uses_of_lon (by rw [h]; rfl))]
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

end Driveline

namespace Driveline.Validity

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
  exact ⟨Or.inl rfl, ⟨Iff.rfl.trans ⟨nofun, nofun⟩, nofun⟩, nofun, nofun, nofun, nofun, nofun,
    nofun⟩

/-- P05-11. 'A full frame that a step produces and that reaches a `Lon<T>` or
`Lat<T>` port ... is valid only if, in addition, it does not use
`SPATIOTEMPORAL_TRAJECTORY`' (docs/spec/05-checkpoints.md:34), with the
conversion at the port of 05:40. The last conjunct shows that the exclusion is
needed. -/
theorem port_conversion :
    (∀ (map : RoadMap) (f : IntentFrame), f.valid map .full → ¬ f.usesSTT →
      f.toLon.valid map .lon ∧ f.toLat.valid map .lat) ∧
    (∀ f : KinematicControlFrame, f.valid .full → f.toLon.valid .lon ∧ f.toLat.valid .lat) ∧
    (∀ map : RoadMap, ∃ f : IntentFrame, f.valid map .full ∧ ¬ f.toLon.valid map .lon) := by
  refine ⟨fun map f hv hs => ?_, fun f hv => ?_, fun map => ?_⟩
  · obtain ⟨hp, ⟨_, _⟩, hlane, hpoly, hgap⟩ := hv
    obtain ⟨h1, h2, h3⟩ := (IntentFrame.pOR_full f).mp hp
    have hl : f.lon ≠ .stt := fun h => hs (Or.inl h)
    have ht : f.lat ≠ .stt := fun h => hs (Or.inr h)
    constructor
    · refine (IntentFrame.zero_valid_iff _ _ _).mpr ⟨(IntentFrame.pOR_lon _).mpr
        ⟨h1, hl, rfl, rfl⟩, ⟨⟨fun h => absurd h hl, nofun⟩, fun h => absurd h hl⟩,
        nofun, nofun, IntentFrame.gapRule_mono id (fun fld h => ?_) rfl rfl rfl rfl hgap⟩
      simp only [IntentFrame.uses, LatMode.none_uses, Bool.or_false] at h
      exact IntentFrame.uses_of_lon h
    · refine (IntentFrame.zero_valid_iff _ _ _).mpr ⟨(IntentFrame.pOR_lat _).mpr
        ⟨h2, ht, h3, rfl⟩, ⟨⟨nofun, fun h => absurd h ht⟩, nofun⟩, hlane, hpoly,
        IntentFrame.gapRule_mono nofun (fun fld h => ?_) rfl rfl rfl rfl hgap⟩
      simp only [IntentFrame.uses, LonMode.none_uses, Bool.false_or] at h
      exact IntentFrame.uses_of_lat h
  · obtain ⟨hp, ha, _⟩ := hv
    obtain ⟨h1, h2⟩ := (KinematicControlFrame.pOR_full f).mp hp
    exact ⟨(KinematicControlFrame.zero_valid_iff _ _).mpr
        ⟨(KinematicControlFrame.pOR_lon _).mpr ⟨h1, rfl⟩, ha, nofun⟩,
      (KinematicControlFrame.zero_valid_iff _ _).mpr
        ⟨(KinematicControlFrame.pOR_lat _).mpr ⟨h2, rfl⟩, nofun, hv.2.2⟩⟩
  · refine ⟨{ IntentFrame.blank ⟨0, 0⟩ with
      lon := .stt, lat := .stt, signal := .off, numTrajPoints := 1 }, ?_, fun h => ?_⟩
    · refine ⟨(IntentFrame.pOR_full _).mpr ⟨nofun, nofun, nofun⟩,
        ⟨Iff.rfl.trans ⟨fun _ => rfl, fun _ => rfl⟩, fun _ => ⟨le_refl 1, by decide,
          fun _ _ => ⟨le_refl 0, F64.zero_le_zero, F64.inIoc_zero_pi⟩,
          fun i j hij hj => absurd (Nat.lt_of_le_of_lt (Nat.zero_le i.val) hij) (by omega)⟩⟩,
        nofun, nofun, nofun, nofun, nofun, nofun⟩
    · exact ((IntentFrame.pOR_lon _).mp
        ((IntentFrame.zero_valid_iff _ _ _).mp h).1).2.1 rfl

/-- P05-12. 'The value `+INFINITY` means no bound'
(docs/spec/05-checkpoints.md:36). `+∞` passes every bound rule, and with 'a value
at or below zero means stop now' (05:78) a `+∞` stop target never stops. -/
theorem infinity_no_bound :
    (∀ (d : Decl) (f : KinematicControlFrame), f.valid d →
      ({ f with jerkLonCmd := .posInf, steerRateCmd := .posInf } : KinematicControlFrame).valid d) ∧
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame), f.valid map d →
      ({ f with stopAtOdometer := .posInf } : IntentFrame).valid map d) ∧
    (∀ odo : ℝ, ¬ stopNow .posInf odo) := by
  refine ⟨fun _ _ ⟨hp, _, _⟩ => ⟨hp, fun _ => F64.zero_lt_posInf, fun _ => F64.zero_lt_posInf⟩,
    fun _ _ _ h => h, fun _ => ?_⟩
  rintro (h | ⟨h, _⟩)
  · exact h
  · cases h

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
(docs/spec/05-checkpoints.md:66). The mode-value rule holds by the enum types. -/
theorem intent_valid_iff (map : RoadMap) (d : Decl) (f : IntentFrame) :
    f.valid map d ↔ f.partialOverrideRule d ∧ f.sttRule ∧ f.laneRule map ∧ f.polylineRule ∧
      f.gapRule :=
  Iff.rfl

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
  refine ⟨fun n hn t => ⟨⟨timesIncrease_of_adjacent hn, fun h k hk => ?_⟩, ⟨fun h a b hab => ?_,
    fun h i j hij hj => ?_⟩⟩, fun _ _ _ hv => hv.2.1.1⟩
  · exact h ⟨k, by omega⟩ ⟨k + 1, by omega⟩ (Nat.lt_succ_self k) hk
  · exact h _ _ hab (by simp)
  · exact h (a := ⟨i.val, Nat.lt_trans hij hj⟩) (b := ⟨j.val, hj⟩) hij

/-- P05-20. 'With `GAP_PROFILE`, `gap_target_actor_id` is not 0. Where they
apply, `v_ref`, `time_gap_ref`, and `distance_gap_min` are not negative'
(docs/spec/05-checkpoints.md:70). 'Not negative' (`¬ x < 0`) and 'at least 0'
(`0 ≤ x`) differ on NaN. The model follows the text, so a NaN `v_ref` passes:
the last conjunct is the witness for the spec gap. -/
theorem gap_rule :
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame), f.valid map d →
      f.lon = .gapProfile → f.gapTargetActorId ≠ 0) ∧
    (∀ (map : RoadMap) (d : Decl) (f : IntentFrame), f.valid map d →
      f.uses .vRef = true → ¬ f.vRef < 0) ∧
    (¬ F64.nan < 0 ∧ ¬ (0 : F64) ≤ F64.nan) ∧
    (∀ map : RoadMap, ∃ f : IntentFrame,
      f.valid map .lon ∧ f.lon = .gapProfile ∧ f.vRef = .nan) := by
  refine ⟨fun _ _ _ hv => hv.2.2.2.2.1, fun _ _ _ hv => hv.2.2.2.2.2.1,
    ⟨F64.not_nan_lt _, F64.not_le_nan _⟩, fun map => ⟨{ IntentFrame.blank ⟨0, 0⟩ with
      lon := .gapProfile, gapTargetActorId := 1, vRef := .nan }, ?_, rfl, rfl⟩⟩
  refine ⟨(IntentFrame.pOR_lon _).mpr ⟨nofun, nofun, rfl, rfl⟩, ⟨⟨nofun, nofun⟩, nofun⟩,
    nofun, nofun, fun _ => by decide, fun _ => F64.not_nan_lt _,
    fun _ => F64.not_zero_lt_zero, fun _ => F64.not_zero_lt_zero⟩

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
bounds under `ACCEL` and `ANGLE` are above zero' (docs/spec/05-checkpoints.md:98).
NaN bounds are rejected and `+∞` is accepted. -/
theorem kinematic_bounds_above_zero :
    (∀ (d : Decl) (f : KinematicControlFrame), f.accel = .accel → f.jerkLonCmd = .nan →
      ¬ f.valid d) ∧
    (∀ (d : Decl) (f : KinematicControlFrame), f.steer = .angle → f.steerRateCmd = .nan →
      ¬ f.valid d) ∧
    (0 : F64) < .posInf ∧
    (∀ (d : Decl) (f : KinematicControlFrame), f.accel = .accel →
      f.partialOverrideRule d → (f.steer = .angle → (0 : F64) < f.steerRateCmd) →
      (f.valid d ↔ (0 : F64) < f.jerkLonCmd)) :=
  ⟨fun _ _ ha hn ⟨_, h, _⟩ => F64.not_lt_nan 0 (hn ▸ h ha),
    fun _ _ hs hn ⟨_, _, h⟩ => F64.not_lt_nan 0 (hn ▸ h hs), F64.zero_lt_posInf,
    fun _ _ ha hp hs => ⟨fun h => h.2.1 ha, fun h => ⟨hp, fun _ => h, hs⟩⟩⟩

/-- P05-30. 'An `ActuatorControlFrame` is valid if and only if the Override
rule holds, each mode field holds one of its listed values, `throttle` and
`brake` lie in `[0, 1]` under `PEDALS`, `steering_wheel_norm` lies in `[-1, 1]`
under `ANGLE`, and under `DRIVE` `manual_gear_index` is from 0 to `num_gears`
(so 0 without Tier 2)' (docs/spec/05-checkpoints.md:114). That `num_gears` is 0
without Tier 2 is a §3 fact. -/
theorem actuator_ranges :
    (∀ (n : Nat) (d : Decl) (f : ActuatorControlFrame), f.valid n d → f.gear = .drive →
      0 ≤ f.manualGearIndex.toInt ∧ f.manualGearIndex.toInt ≤ n) ∧
    (∀ (d : Decl) (f : ActuatorControlFrame), f.valid 0 d → f.gear = .drive →
      f.manualGearIndex = 0) ∧
    (∀ (n : Nat) (d : Decl) (f : ActuatorControlFrame), f.pedal = .pedals →
      (f.throttle = .nan ∨ f.brake = .nan) → ¬ f.valid n d) ∧
    (∀ (n : Nat) (d : Decl) (f : ActuatorControlFrame), f.wheel = .angle →
      f.steeringWheelNorm = .nan → ¬ f.valid n d) := by
  refine ⟨fun _ _ _ hv hg => hv.2.2.2 hg, fun _ f hv hg => ?_,
    fun _ _ _ hp hn hv => ?_, fun _ _ _ hw hn hv => ?_⟩
  · obtain ⟨h0, h1⟩ := hv.2.2.2 hg
    exact Int8.toInt_inj.mp (by simp only [Int8.toInt_zero]; push_cast at h1; omega)
  · obtain ⟨ht, hb⟩ := hv.2.1 hp
    rcases hn with hn | hn
    · rw [hn] at ht; exact F64.not_inIcc_nan _ _ ht
    · rw [hn] at hb; exact F64.not_inIcc_nan _ _ hb
  · have h := hv.2.2.1 hw
    rw [hn] at h; exact F64.not_inIcc_nan _ _ h

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
