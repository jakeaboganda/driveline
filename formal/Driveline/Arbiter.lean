import Driveline.Merge

/-!
# Arbiter coupled-motion rule (spec §10)

The `IntentFrame` rule of `docs/spec/10-composition.md:27`: when either source
is in `SPATIOTEMPORAL_TRAJECTORY`, the two motion groups come together from one
source, and in the split case the unstated group comes from the committed
baseline frame (06:94, built by the Pass 1 step 5 rules of 06:72).

The spec says 'The runtime checks only the §5 validity of the output', but the
baseline's `LANE_OFFSET` names the actor's committed lane, which need not be a
lane of the map. `Driveline.Arbiter.arbiter_baseline_can_fail` is the
counterexample; `IntentFrame.arbiterRule_valid` proves validity when the
baseline is valid.

The spec fixes neither the source of `turn_signal` nor the non-STT case.
`arbiterRule` takes both group-wise, and `arbiterOK` constrains only the motion
groups in the STT case. Projecting `OwnView` from `KinematicState` and the
baseline's 'next tick' stamp are deferred to the §6.2 work package.
-/

namespace Driveline

/-- The `own_state` fields read by 10:27 and 06:94. -/
structure OwnView where
  actorId : UInt64
  vLon : F64
  roadId : String
  laneId : Int32
  frenetD : F64

/-- `max(v_lon, 0)` (06:94, 10:27). The spec leaves NaN open; this uses IEEE
`fmax`, which gives 0 for NaN. -/
def F64.max0 : F64 → F64
  | .fin x => .fin (max x 0)
  | .posInf => .posInf
  | .negInf => 0
  | .nan => 0

theorem F64.max0_nonneg (x : F64) : ¬ (x.max0 < 0) ∧ (0 : F64) ≤ x.max0 := by
  cases x with
  | fin y =>
    simp only [max0, F64.zero_def, F64.fin_lt_fin, F64.fin_le_fin]
    exact ⟨not_lt.2 (le_max_right _ _), le_max_right _ _⟩
  | posInf => exact ⟨id, Or.inl trivial⟩
  | negInf => exact ⟨F64.not_zero_lt_zero, F64.zero_le_zero⟩
  | nan => exact ⟨F64.not_zero_lt_zero, F64.zero_le_zero⟩

namespace IntentFrame

/-- The `IntentFrame` part of the committed baseline frame: 06:94 applied to the
Pass 1 step 5 rules (06:72). -/
def committedBaseline (o : OwnView) (t : UInt64) : IntentFrame :=
  { IntentFrame.blank ⟨o.actorId, t⟩ with
    lon := .velocityTarget, vRef := o.vLon.max0, stopAtOdometer := .posInf,
    lat := .laneOffset, targetRoadId := o.roadId, targetLaneId := o.laneId, dRef := o.frenetD,
    signal := .off }

/-- Copy the `LON` group, mode and fields, from `src` into `dst`. -/
def withLonFrom (dst src : IntentFrame) : IntentFrame :=
  { dst with
    lon := src.lon, aRef := src.aRef, vRef := src.vRef, stopAtOdometer := src.stopAtOdometer,
    gapTargetActorId := src.gapTargetActorId, timeGapRef := src.timeGapRef,
    distanceGapMin := src.distanceGapMin }

/-- Copy the `LAT` group, mode and fields, from `src` into `dst`. -/
def withLatFrom (dst src : IntentFrame) : IntentFrame :=
  { dst with
    lat := src.lat, targetRoadId := src.targetRoadId, targetLaneId := src.targetLaneId,
    dRef := src.dRef, numWaypoints := src.numWaypoints, pathPoints := src.pathPoints }

/-- Copy both motion groups and the shared trajectory fields. -/
def withMotionFrom (dst src : IntentFrame) : IntentFrame :=
  { (dst.withLonFrom src).withLatFrom src with
    numTrajPoints := src.numTrajPoints, trajectory := src.trajectory }

/-- 10:27, the three cases of the coupled-motion rule. -/
def coupledMotion (base p s : IntentFrame) : IntentFrame :=
  if s.lon ≠ .none ∧ s.lat ≠ .none then p.withMotionFrom s
  else if s.lon = .none ∧ s.lat = .none then p
  else if s.lon ≠ .none then (p.withMotionFrom base).withLonFrom s
  else (p.withMotionFrom base).withLatFrom s

/-- Group-wise override (10:27: 'the secondary overrides only the groups it
requests'). -/
def groupwise (p s : IntentFrame) : IntentFrame :=
  let q := if s.lon ≠ .none then p.withLonFrom s else p
  let q := if s.lat ≠ .none then q.withLatFrom s else q
  { q with signal := if s.signal ≠ .none then s.signal else p.signal }

/-- A canonical arbiter: the coupled-motion rule in the STT case, group-wise
otherwise, the signal group-wise, zeroed. -/
def arbiterRule (h : Header) (base p s : IntentFrame) : IntentFrame :=
  let m := if p.usesSTT ∨ s.usesSTT then coupledMotion base p s else p.groupwise s
  ({ m with header := h, signal := (p.groupwise s).signal } : IntentFrame).zero

/-- The constraint 10:27 puts on any arbiter output. Outside the STT case it
constrains nothing. -/
def arbiterOK (base p s out : IntentFrame) : Prop :=
  (p.usesSTT ∨ s.usesSTT) →
    let r := coupledMotion base p s
    out.lon = r.lon ∧ out.lat = r.lat ∧ ∀ fld, r.uses fld = true → out.agreeOn fld r

theorem arbiterRule_eq (h : Header) (base p s : IntentFrame) :
    arbiterRule h base p s =
      ({ (if p.usesSTT ∨ s.usesSTT then coupledMotion base p s else p.groupwise s) with
          header := h, signal := (p.groupwise s).signal } : IntentFrame).zero := rfl

theorem coupledMotion_cases (base p s : IntentFrame) :
    (s.lon ≠ .none ∧ s.lat ≠ .none ∧ coupledMotion base p s = p.withMotionFrom s) ∨
    (s.lon = .none ∧ s.lat = .none ∧ coupledMotion base p s = p) ∨
    (s.lon ≠ .none ∧ s.lat = .none ∧
      coupledMotion base p s = (p.withMotionFrom base).withLonFrom s) ∨
    (s.lon = .none ∧ s.lat ≠ .none ∧
      coupledMotion base p s = (p.withMotionFrom base).withLatFrom s) := by
  unfold coupledMotion
  by_cases h1 : s.lon = .none <;> by_cases h2 : s.lat = .none <;> simp [h1, h2]

/-- A frame whose motion groups and fields all agree with `W` is valid as a full
frame when `W` satisfies the rules of 05:68-70 and it states every group. -/
theorem valid_full_of_rules {map : RoadMap} {V W : IntentFrame} (hl : V.lon = W.lon)
    (ht : V.lat = W.lat) (hu : ∀ fld, V.uses fld = true → V.agreeOn fld W)
    (hw : W.valid map .override) (hp : V.partialOverrideRule .full) : V.valid map .full := by
  have hu' : ∀ fld, V.uses fld = true → V.agreeOn fld { W with signal := V.signal } :=
    fun fld h => by cases fld <;> exact hu _ h
  exact ⟨hp, ((valid_congr (g := { W with signal := V.signal }) map .override ⟨hl, ht, rfl⟩ hu').2 ⟨Or.inl rfl, hw.2⟩).2⟩

/-- In a valid override, a single stated motion group is never STT (05:68). -/
theorem override_single_not_stt (map : RoadMap) (s : IntentFrame) (h : s.valid map .override)
    (h1 : (s.lon = .none) ≠ (s.lat = .none)) : s.lon ≠ .stt ∧ s.lat ≠ .stt := by
  have key : s.lon ≠ .stt := fun hl =>
    h1 (by rw [hl, h.2.1.1.1 hl]; exact propext ⟨nofun, nofun⟩)
  exact ⟨key, fun ht => key (h.2.1.1.2 ht)⟩

/-- 10:27 coupling: if either source is in STT, the coupled output is in STT in
both motion groups or in neither. -/
theorem coupledMotion_coupled (map : RoadMap) (base p s : IntentFrame) (hp : p.valid map .full)
    (hs : s.valid map .override) (hb : base.lon = .velocityTarget ∧ base.lat = .laneOffset) :
    (coupledMotion base p s).lon = .stt ↔ (coupledMotion base p s).lat = .stt := by
  rcases coupledMotion_cases base p s with ⟨-, -, e⟩ | ⟨-, -, e⟩ | ⟨h1, h2, e⟩ | ⟨h1, h2, e⟩ <;>
    rw [e]
  · exact hs.2.1.1
  · exact hp.2.1.1
  · have := override_single_not_stt map s hs (by rw [h2]; exact fun e => h1 (cast e.symm rfl))
    exact iff_of_false this.1 (by show base.lat ≠ .stt; rw [hb.2]; exact nofun)
  · have := override_single_not_stt map s hs (by rw [h1]; exact fun e => h2 (cast e rfl))
    exact iff_of_false (by show base.lon ≠ .stt; rw [hb.1]; exact nofun) this.2

/-- The coupled output, stamped and given a stated signal, is valid when the
sources and the baseline are. -/
theorem coupled_valid (map : RoadMap) (h : Header) (sig : TurnSignal) (base p s : IntentFrame)
    (hp : p.valid map .full) (hs : s.valid map .override) (hb : base.valid map .full)
    (hbs : ¬ base.usesSTT) (hsig : sig ≠ .none) :
    ({ coupledMotion base p s with header := h, signal := sig } : IntentFrame).valid map .full := by
  have hpf := (pOR_full p).1 hp.1
  have hbf := (pOR_full base).1 hb.1
  rcases coupledMotion_cases base p s with ⟨h1, h2, e⟩ | ⟨-, -, e⟩ | ⟨h1, h2, e⟩ | ⟨h1, h2, e⟩ <;>
    rw [e]
  · exact valid_full_of_rules (W := s) rfl rfl
      (fun fld _ => by cases fld <;> first | rfl | exact fun _ _ => rfl) hs
      ((pOR_full _).2 ⟨h1, h2, hsig⟩)
  · exact valid_full_of_rules (W := p) rfl rfl
      (fun fld _ => by cases fld <;> first | rfl | exact fun _ _ => rfl) ⟨Or.inl rfl, hp.2⟩
      ((pOR_full _).2 ⟨hpf.1, hpf.2.1, hsig⟩)
  · have hst := override_single_not_stt map s hs (by rw [h2]; exact fun e => h1 (cast e.symm rfl))
    exact valid_split (L := s) (T := base) rfl rfl hst.1 (fun e => hbs (Or.inr e)) rfl rfl rfl
      rfl rfl rfl rfl rfl hs.2.2.2.2 hb.2.2.1 hb.2.2.2.1 ((pOR_full _).2 ⟨h1, hbf.2.1, hsig⟩)
  · have hst := override_single_not_stt map s hs (by rw [h1]; exact fun e => h2 (cast e rfl))
    exact valid_split (L := base) (T := s) rfl rfl (fun e => hbs (Or.inl e)) hst.2 rfl rfl rfl
      rfl rfl rfl rfl rfl hb.2.2.2.2 hs.2.2.1 hs.2.2.2.1 ((pOR_full _).2 ⟨hbf.1, h2, hsig⟩)

theorem groupwise_lon (p s : IntentFrame) :
    (p.groupwise s).lon = (if s.lon ≠ .none then s else p).lon ∧
    (p.groupwise s).gapTargetActorId = (if s.lon ≠ .none then s else p).gapTargetActorId ∧
    (p.groupwise s).vRef = (if s.lon ≠ .none then s else p).vRef ∧
    (p.groupwise s).timeGapRef = (if s.lon ≠ .none then s else p).timeGapRef ∧
    (p.groupwise s).distanceGapMin = (if s.lon ≠ .none then s else p).distanceGapMin := by
  simp only [groupwise, withLatFrom, withLonFrom]
  split_ifs <;> exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem groupwise_lat (p s : IntentFrame) :
    (p.groupwise s).lat = (if s.lat ≠ .none then s else p).lat ∧
    (p.groupwise s).targetRoadId = (if s.lat ≠ .none then s else p).targetRoadId ∧
    (p.groupwise s).targetLaneId = (if s.lat ≠ .none then s else p).targetLaneId ∧
    (p.groupwise s).numWaypoints = (if s.lat ≠ .none then s else p).numWaypoints ∧
    (p.groupwise s).pathPoints = (if s.lat ≠ .none then s else p).pathPoints := by
  simp only [groupwise, withLatFrom, withLonFrom]
  split_ifs <;> exact ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- The group-wise output outside the STT case, stamped and given a stated
signal, is valid when the sources are. -/
theorem groupwise_valid (map : RoadMap) (h : Header) (sig : TurnSignal) (p s : IntentFrame)
    (hp : p.valid map .full) (hs : s.valid map .override) (hc : ¬ (p.usesSTT ∨ s.usesSTT))
    (hsig : sig ≠ .none) :
    ({ p.groupwise s with header := h, signal := sig } : IntentFrame).valid map .full := by
  have hpf := (pOR_full p).1 hp.1
  obtain ⟨e1, e2, e3, e4, e5⟩ := groupwise_lon p s
  obtain ⟨e6, e7, e8, e9, e10⟩ := groupwise_lat p s
  refine valid_split (L := if s.lon ≠ .none then s else p) (T := if s.lat ≠ .none then s else p)
    e1 e6 ?_ ?_ e2 e3 e4 e5 e7 e8 e9 e10 ?_ ?_ ?_ ((pOR_full _).2 ⟨?_, ?_, hsig⟩)
  · split
    · exact fun e => hc (Or.inr (Or.inl e))
    · exact fun e => hc (Or.inl (Or.inl e))
  · split
    · exact fun e => hc (Or.inr (Or.inr e))
    · exact fun e => hc (Or.inl (Or.inr e))
  · split
    · exact hs.2.2.2.2
    · exact hp.2.2.2.2
  · split
    · exact hs.2.2.1
    · exact hp.2.2.1
  · split
    · exact hs.2.2.2.1
    · exact hp.2.2.2.1
  · show (p.groupwise s).lon ≠ .none
    rw [e1]
    split
    · assumption
    · exact hpf.1
  · show (p.groupwise s).lat ≠ .none
    rw [e6]
    split
    · assumption
    · exact hpf.2.1

theorem groupwise_signal (map : RoadMap) (p s : IntentFrame) (hp : p.valid map .full) :
    (p.groupwise s).signal ≠ .none := by
  show (if s.signal ≠ .none then s.signal else p.signal) ≠ .none
  split
  · assumption
  · exact ((pOR_full p).1 hp.1).2.2

/-- The ledger statement of P10-12: 'valid p, valid s and valid base give valid
out', with `¬ base.usesSTT`, which the committed baseline satisfies by
construction (`committedBaseline_not_stt`). -/
theorem arbiterRule_valid (map : RoadMap) (h : Header) (base p s : IntentFrame)
    (hp : p.valid map .full) (hs : s.valid map .override) (hb : base.valid map .full)
    (hbs : ¬ base.usesSTT) : (arbiterRule h base p s).valid map .full := by
  rw [arbiterRule_eq, zero_valid_iff]
  have hsig := groupwise_signal map p s hp
  by_cases hc : p.usesSTT ∨ s.usesSTT
  · simp only [hc, ↓reduceIte]
    exact coupled_valid map h _ base p s hp hs hb hbs hsig
  · simp only [hc, ↓reduceIte]
    exact groupwise_valid map h _ p s hp hs hc hsig

theorem arbiterRule_ok (h : Header) (base p s : IntentFrame) :
    arbiterOK base p s (arbiterRule h base p s) := by
  intro hc
  rw [arbiterRule_eq]
  simp only [hc, ↓reduceIte]
  exact ⟨rfl, rfl, fun fld hu => by cases fld <;> exact zero_keeps _ _ hu⟩

/-- Any output that satisfies the rule and states a signal is valid in the STT
case. -/
theorem arbiterOK_valid (map : RoadMap) (base p s out : IntentFrame) (hp : p.valid map .full)
    (hs : s.valid map .override) (hb : base.valid map .full) (hbs : ¬ base.usesSTT)
    (hstt : p.usesSTT ∨ s.usesSTT) (hok : arbiterOK base p s out) (hsig : out.signal ≠ .none) :
    out.valid map .full := by
  obtain ⟨hl, ht, hu⟩ := hok hstt
  have hv := coupled_valid map out.header out.signal base p s hp hs hb hbs hsig
  refine (valid_congr (g := { coupledMotion base p s with header := out.header, signal := out.signal })
    map .full ⟨hl, ht, rfl⟩ fun fld hf => ?_).2 hv
  have hf' : (coupledMotion base p s).uses fld = true := by simpa only [uses, hl, ht] using hf
  have := hu fld hf'
  cases fld <;> exact this

theorem committedBaseline_spec (o : OwnView) (t : UInt64) :
    let b := committedBaseline o t
    b.lon = .velocityTarget ∧ b.vRef = o.vLon.max0 ∧ b.stopAtOdometer = .posInf ∧
      b.lat = .laneOffset ∧ b.targetRoadId = o.roadId ∧ b.targetLaneId = o.laneId ∧
      b.dRef = o.frenetD ∧ b.signal = .off ∧ b.header = ⟨o.actorId, t⟩ :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- The baseline is valid exactly when the actor's committed lane is a lane of
the map. -/
theorem committedBaseline_valid_iff (map : RoadMap) (o : OwnView) (t : UInt64) :
    (committedBaseline o t).valid map .full ↔
      map.road o.roadId ∧ map.lane o.roadId o.laneId.toInt :=
  ⟨fun hv => hv.2.2.1 rfl, fun hm =>
    ⟨(pOR_full _).2 ⟨nofun, nofun, nofun⟩, ⟨iff_of_false nofun nofun, nofun⟩, fun _ => hm,
      nofun, ⟨nofun, fun _ => (F64.max0_nonneg _).1, nofun, nofun⟩⟩⟩

theorem committedBaseline_not_stt (o : OwnView) (t : UInt64) :
    ¬ (committedBaseline o t).usesSTT := by
  rintro (h | h) <;> cases h

/-- Off-map counterexample: lane 0 is never valid (`RoadMap.lane_ne_zero`). -/
theorem committedBaseline_lane0 (map : RoadMap) (o : OwnView) (t : UInt64) (h : o.laneId = 0) :
    ¬ (committedBaseline o t).valid map .full := fun hv =>
  map.lane_ne_zero _ _ ((committedBaseline_valid_iff map o t).1 hv).2 (by rw [h]; rfl)

/-- On a mapped lane, the arbiter's canonical output is valid. -/
theorem arbiterRule_valid_onMap (map : RoadMap) (h : Header) (o : OwnView) (t : UInt64)
    (p s : IntentFrame) (hp : p.valid map .full) (hs : s.valid map .override)
    (hm : map.road o.roadId ∧ map.lane o.roadId o.laneId.toInt) :
    (arbiterRule h (committedBaseline o t) p s).valid map .full :=
  arbiterRule_valid map h _ p s hp hs ((committedBaseline_valid_iff map o t).2 hm)
    (committedBaseline_not_stt o t)

end IntentFrame

end Driveline

namespace Driveline.Arbiter

open IntentFrame

/-- P10-12, REFUTED. 'For `IntentFrame`, an Arbiter must take the two motion
groups together from one source whenever either source is in
`SPATIOTEMPORAL_TRAJECTORY`: ... and otherwise the secondary's stated group
together with the other group taken from the committed baseline frame ... The
runtime checks only the §5 validity of the output'
(docs/spec/10-composition.md:27). With a valid primary and a valid override,
the rule's output can fail 05:69: the primary is in STT, the secondary states
only `VELOCITY_TARGET`, and the actor's committed lane (here lane 0) is not a
lane of the map, so the baseline's `LANE_OFFSET` is invalid. Under a valid
baseline the output is valid: `Driveline.IntentFrame.arbiterRule_valid`, with
`Driveline.IntentFrame.arbiterRule_ok` showing the canonical arbiter follows
the rule and `Driveline.IntentFrame.arbiterOK_valid` covering every output that
follows it. -/
theorem arbiter_baseline_can_fail :
    ∃ (map : RoadMap) (o : OwnView) (t : UInt64) (h : Header) (p s : IntentFrame),
      p.valid map .full ∧ s.valid map .override ∧
        ¬ (arbiterRule h (committedBaseline o t) p s).valid map .full := by
  refine ⟨⟨fun _ => False, fun _ _ => False, fun _ _ h => h.elim⟩, ⟨0, 0, "", 0, 0⟩, 0, ⟨0, 0⟩,
    { blank ⟨0, 0⟩ with lon := .stt, lat := .stt, signal := .off, numTrajPoints := 1 },
    { blank ⟨0, 0⟩ with lon := .velocityTarget, vRef := 0, stopAtOdometer := .posInf },
    ⟨(pOR_full _).2 ⟨nofun, nofun, nofun⟩, ⟨iff_of_true rfl rfl, fun _ => ?_⟩, nofun, nofun,
      ⟨nofun, nofun, nofun, nofun⟩⟩,
    ⟨Or.inl rfl, ⟨iff_of_false nofun nofun, nofun⟩, nofun, nofun,
      ⟨nofun, fun _ => F64.not_zero_lt_zero, nofun, nofun⟩⟩,
    fun hv => (hv.2.2.1 rfl).1⟩
  refine ⟨le_refl 1, by decide, fun i hi => ?_, fun i j hij hj => ?_⟩
  · exact ⟨le_refl 0, F64.zero_le_zero, F64.inIoc_zero_pi⟩
  · have hj' : j.val < 1 := hj
    exact absurd hij (by rw [Fin.lt_def]; omega)

/-- P10-13. '`VELOCITY_TARGET` with `v_ref` $= \max($`own.v_lon`$, 0)$, or
`LANE_OFFSET` on the actor's lane with `d_ref` $=$ `own.frenet_d`'
(docs/spec/10-composition.md:27), with 'stop_at_odometer = +INFINITY ... and
turn_signal = OFF' (docs/spec/06-lifecycle.md:72) and 'the committed road_id
and lane_id in place of the spawn lane' (docs/spec/06-lifecycle.md:94). The
baseline is valid exactly when the committed lane is a lane of the map. -/
theorem committed_baseline :
    (∀ (o : OwnView) (t : UInt64),
      let b := committedBaseline o t
      b.lon = .velocityTarget ∧ b.vRef = o.vLon.max0 ∧ b.stopAtOdometer = .posInf ∧
        b.lat = .laneOffset ∧ b.targetRoadId = o.roadId ∧ b.targetLaneId = o.laneId ∧
        b.dRef = o.frenetD ∧ b.signal = .off ∧ b.header = ⟨o.actorId, t⟩) ∧
    (∀ (map : RoadMap) (o : OwnView) (t : UInt64),
      (committedBaseline o t).valid map .full ↔
        map.road o.roadId ∧ map.lane o.roadId o.laneId.toInt) :=
  ⟨committedBaseline_spec, committedBaseline_valid_iff⟩

end Driveline.Arbiter
