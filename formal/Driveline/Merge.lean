import Driveline.Validity

/-!
# Partial merge `(A + B)` (spec §10)

The merge of a `Lon<T>` branch and a `Lat<T>` branch
(`docs/spec/10-composition.md:24-25`). `merge h a b` takes the `LON` group from
`a`, and the `LAT` group, `SIGNAL` and the shared trajectory fields from `b`.
After zeroing, which branch the shared fields come from does not matter
(`IntentFrame.zero_merge`).

The splice-window stamp of 10:25 ('re-forms its merged frame in the splice
window ... stamped with the next tick's time') is deferred to the §6.2.4/§11
work package.
-/

namespace Driveline

namespace IntentFrame

/-- The merged frame of 10:25: header `h`, `LON` from `a`, the rest from `b`. -/
def merge (h : Header) (a b : IntentFrame) : IntentFrame :=
  { b with
    header := h, lon := a.lon, aRef := a.aRef, vRef := a.vRef, stopAtOdometer := a.stopAtOdometer,
    gapTargetActorId := a.gapTargetActorId, timeGapRef := a.timeGapRef,
    distanceGapMin := a.distanceGapMin }

/-- The frame consumers receive on a tick: a merged, zeroed frame stamped with
the tick when a branch steps, otherwise the last merged frame. -/
def mergeTick (actor t : UInt64) (stepped : Bool) (prev a b : IntentFrame) : IntentFrame :=
  if stepped then (merge ⟨actor, t⟩ a b).zero else prev

/-- The rules of 05:68-70 for a frame whose `LON` group and fields agree with
`L` and whose `LAT` group and fields agree with `T`, neither in STT. -/
theorem valid_split {map : RoadMap} {d : Decl} {V L T : IntentFrame}
    (hl : V.lon = L.lon) (ht : V.lat = T.lat) (hls : L.lon ≠ .stt) (hts : T.lat ≠ .stt)
    (h1 : V.gapTargetActorId = L.gapTargetActorId) (h2 : V.vRef = L.vRef)
    (h3 : V.timeGapRef = L.timeGapRef) (h4 : V.distanceGapMin = L.distanceGapMin)
    (h5 : V.targetRoadId = T.targetRoadId) (h6 : V.targetLaneId = T.targetLaneId)
    (h7 : V.numWaypoints = T.numWaypoints) (h8 : V.pathPoints = T.pathPoints)
    (hL : L.gapRule) (hT : T.laneRule map) (hT' : T.polylineRule)
    (hp : V.partialOverrideRule d) : V.valid map d := by
  have hU : ∀ fld, IntentGroup.lat ∉ fld.groups → V.uses fld = L.uses fld := fun fld hf => by
    simp only [uses, hl, LatMode.uses_eq_false _ fld hf]
  obtain ⟨a, b, c, e⟩ := hL
  refine ⟨hp, ?_, ?_, ?_, ?_⟩
  · unfold sttRule
    rw [hl, ht]
    exact ⟨iff_of_false hls hts, fun h => absurd h hls⟩
  · unfold laneRule
    rw [ht, h5, h6]
    exact hT
  · unfold polylineRule
    rw [ht, h7, h8]
    exact hT'
  · refine ⟨fun hg => ?_, fun hv => ?_, fun hv => ?_, fun hv => ?_⟩
    · rw [h1]; exact a (hl ▸ hg)
    · rw [h2]; exact b (by rwa [← hU .vRef (by decide)])
    · rw [h3]; exact c (by rwa [← hU .timeGapRef (by decide)])
    · rw [h4]; exact e (by rwa [← hU .distanceGapMin (by decide)])

theorem merge_full (h : Header) (a b : IntentFrame) (ha : a.partialOverrideRule .lon)
    (hb : b.partialOverrideRule .lat) :
    (merge h a b).partialOverrideRule .full ∧ ¬ (merge h a b).usesSTT := by
  obtain ⟨a1, a2, -, -⟩ := (pOR_lon a).1 ha
  obtain ⟨b1, b2, b3, -⟩ := (pOR_lat b).1 hb
  exact ⟨(pOR_full _).2 ⟨a1, b1, b3⟩, fun h => h.elim a2 b2⟩

theorem merge_valid (map : RoadMap) (h : Header) (a b : IntentFrame) (ha : a.valid map .lon)
    (hb : b.valid map .lat) : (merge h a b).valid map .full := by
  obtain ⟨-, a2, -, -⟩ := (pOR_lon a).1 ha.1
  obtain ⟨-, b2, -, -⟩ := (pOR_lat b).1 hb.1
  exact valid_split (L := a) (T := b) rfl rfl a2 b2 rfl rfl rfl rfl rfl rfl rfl rfl ha.2.2.2.2
    hb.2.2.1 hb.2.2.2.1 (merge_full h a b ha.1 hb.1).1

theorem zero_merge (map : RoadMap) (h : Header) (a b : IntentFrame) (ha : a.valid map .lon)
    (hb : b.valid map .lat) : (merge h a b).zero = merge h a.zero b.zero := by
  obtain ⟨-, hs, hal, -⟩ := (pOR_lon a).1 ha.1
  obtain ⟨-, -, -, hbl⟩ := (pOR_lat b).1 hb.1
  clear ha hb
  rcases a with ⟨_, la, ta⟩
  rcases b with ⟨_, lb, tb⟩
  dsimp only at hs hal hbl
  subst hal hbl
  cases la <;> cases tb <;> first | exact absurd rfl hs | rfl

end IntentFrame

namespace KinematicControlFrame

/-- The merged frame of 10:25: header `h`, `LON` from `a`, `LAT` from `b`. -/
def merge (h : Header) (a b : KinematicControlFrame) : KinematicControlFrame :=
  { b with header := h, accel := a.accel, aLonCmd := a.aLonCmd, jerkLonCmd := a.jerkLonCmd }

def mergeTick (actor t : UInt64) (stepped : Bool) (prev a b : KinematicControlFrame) :
    KinematicControlFrame :=
  if stepped then (merge ⟨actor, t⟩ a b).zero else prev

theorem merge_full (h : Header) (a b : KinematicControlFrame) (ha : a.partialOverrideRule .lon)
    (hb : b.partialOverrideRule .lat) : (merge h a b).partialOverrideRule .full :=
  (pOR_full _).2 ⟨((pOR_lon a).1 ha).1, ((pOR_lat b).1 hb).1⟩

theorem merge_valid (h : Header) (a b : KinematicControlFrame) (ha : a.valid .lon)
    (hb : b.valid .lat) : (merge h a b).valid .full :=
  ⟨merge_full h a b ha.1 hb.1, ha.2.1, hb.2.2⟩

theorem zero_merge (h : Header) (a b : KinematicControlFrame) (ha : a.valid .lon)
    (hb : b.valid .lat) : (merge h a b).zero = merge h a.zero b.zero := by
  obtain ⟨-, hal⟩ := (pOR_lon a).1 ha.1
  obtain ⟨-, hbl⟩ := (pOR_lat b).1 hb.1
  clear ha hb
  rcases a with ⟨_, la, ta⟩
  rcases b with ⟨_, lb, tb⟩
  dsimp only at hal hbl
  subst hal hbl
  cases la <;> cases tb <;> rfl

end KinematicControlFrame

end Driveline

namespace Driveline.Merge

/-- P10-06. 'Two `LON` branches, two `LAT` branches, or more than two branches
are compile-time errors, so the two branches can never write the same field'
(docs/spec/10-composition.md:24). A `LON` mode and a `LAT` mode use no common
field once STT is excluded; the last conjunct shows the exclusion is needed. -/
theorem branches_disjoint :
    (∀ (ml : LonMode) (mt : LatMode), ml ≠ .stt → mt ≠ .stt → ∀ fld : IntentField,
      ¬ (ml.uses fld = true ∧ mt.uses fld = true)) ∧
    (∀ (ma : AccelMode) (ms : SteerMode) (fld : KinematicField),
      ¬ (ma.uses fld = true ∧ ms.uses fld = true)) ∧
    (LonMode.stt.uses .trajectory = true ∧ LatMode.stt.uses .trajectory = true) := by
  refine ⟨fun ml mt hl ht fld => ?_, fun ma ms fld => ?_, rfl, rfl⟩
  · revert hl ht; cases ml <;> cases mt <;> cases fld <;> decide
  · cases ma <;> cases ms <;> cases fld <;> decide

/-- P10-07. 'It states every group, so it is a full frame of type $T$, and it
never uses `SPATIOTEMPORAL_TRAJECTORY`' (docs/spec/10-composition.md:25). -/
theorem merge_full_frame :
    (∀ (h : Header) (a b : IntentFrame), a.partialOverrideRule .lon →
      b.partialOverrideRule .lat →
      (IntentFrame.merge h a b).partialOverrideRule .full ∧ ¬ (IntentFrame.merge h a b).usesSTT) ∧
    (∀ (h : Header) (a b : KinematicControlFrame), a.partialOverrideRule .lon →
      b.partialOverrideRule .lat → (KinematicControlFrame.merge h a b).partialOverrideRule .full) :=
  ⟨IntentFrame.merge_full, KinematicControlFrame.merge_full⟩

/-- P10-08. 'Two valid partial frames always merge into a valid full frame, so a
merged frame never fails validation, and the runtime validates and zeroes it
like a produced frame' (docs/spec/10-composition.md:25). Zeroing the merged
frame gives the merge of the zeroed branches, so the source of the shared
trajectory fields does not matter. -/
theorem merge_valid :
    (∀ (map : RoadMap) (h : Header) (a b : IntentFrame), a.valid map .lon → b.valid map .lat →
      (IntentFrame.merge h a b).valid map .full ∧
        (IntentFrame.merge h a b).zero = IntentFrame.merge h a.zero b.zero) ∧
    (∀ (h : Header) (a b : KinematicControlFrame), a.valid .lon → b.valid .lat →
      (KinematicControlFrame.merge h a b).valid .full ∧
        (KinematicControlFrame.merge h a b).zero = KinematicControlFrame.merge h a.zero b.zero) :=
  ⟨fun map h a b ha hb => ⟨IntentFrame.merge_valid map h a b ha hb,
      IntentFrame.zero_merge map h a b ha hb⟩,
    fun h a b ha hb => ⟨KinematicControlFrame.merge_valid h a b ha hb,
      KinematicControlFrame.zero_merge h a b ha hb⟩⟩

/-- P10-09. 'On ticks where neither branch steps, consumers receive the last
merged frame. ... Every other merged frame's `timestamp_ns` is the tick on
which it is formed' (docs/spec/10-composition.md:25). The splice-window case
('stamped with the next tick's time') is deferred to the §6.2.4/§11 work
package. -/
theorem merge_timestamps :
    (∀ (actor t : UInt64) (prev a b : IntentFrame),
      (IntentFrame.mergeTick actor t true prev a b).header.timestampNs = t ∧
        IntentFrame.mergeTick actor t false prev a b = prev) ∧
    (∀ (actor t : UInt64) (prev a b : KinematicControlFrame),
      (KinematicControlFrame.mergeTick actor t true prev a b).header.timestampNs = t ∧
        KinematicControlFrame.mergeTick actor t false prev a b = prev) :=
  ⟨fun _ _ _ _ _ => ⟨rfl, rfl⟩, fun _ _ _ _ _ => ⟨rfl, rfl⟩⟩

end Driveline.Merge
