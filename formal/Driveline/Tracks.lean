import Mathlib.Tactic
import Driveline.Angles
import Driveline.SliceBuffer
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Arctan
import Mathlib.Analysis.Calculus.Deriv.Basic

/-!
# Sensor slices and track lists (spec §4.1, §4.3)

Routes (`docs/spec/04-perception.md:16`), the four slice payloads and `TargetTrack`
(04:45-52, `abi/driveline_abi.h:97-151`), their interpolation classes and dependency
conditions (04:36-41, 04:56-58), the track list rules (04:54), and `at` on each slice
buffer (`at_radar` and its siblings).

Float64 fields are real numbers, so the `+INFINITY` values of `ttc_lon` and `lead_ttc`
(04:48-49) and the non-finite rules (04:30, 04:40) are not modeled. `num_tracks` is the
length of `tracks`; `toArray32` gives the zero-filled C array.
-/

noncomputable section

namespace Driveline.Tracks

open Driveline.SliceBuffer

/-! ## Routes (04:16) -/

/-- The bytes of a `char[64]` before the NUL. -/
abbrev RoadId := List UInt8

structure LaneRef where
  road : RoadId
  lane : ℤ

def LaneRef.zero : LaneRef := ⟨[], 0⟩

structure Route where
  count : ℕ
  nodes : Fin 64 → LaneRef

def encodeRoute (l : List LaneRef) : Option Route :=
  if l.length ≤ 64 then some ⟨l.length, fun i => l.getD i LaneRef.zero⟩ else none

/-! ## Slices (abi:109-151, 04:45-52) -/

structure Track where
  id : ℕ                                           -- target_actor_id
  rel_x : ℝ
  rel_y : ℝ
  rel_z : ℝ
  rel_vx : ℝ
  rel_vy : ℝ
  rel_yaw : ℝ
  range : ℝ
  bearing : ℝ
  ttc_lon : ℝ
  road_id : RoadId
  lane_id : ℤ
  object_class : ℕ
  confidence : ℝ

def Track.zero : Track := ⟨0, 0, 0, 0, 0, 0, 0, 0, 0, 0, [], 0, 0, 0⟩

/-- In every slice `num_tracks` is `tracks.length`. -/
structure VisualSlice where
  ego_road_id : RoadId
  ego_lane_id : ℤ
  left_lane_free : ℕ
  right_lane_free : ℕ
  ego_s : ℝ
  ego_d : ℝ
  lead_ttc : ℝ
  tracks : List Track

structure RadarSlice where
  has_primary_target : ℕ
  primary_target_id : ℕ
  primary_range : ℝ
  primary_azimuth : ℝ
  primary_rcs : ℝ
  tracks : List Track

structure CameraSlice where
  obstacle_confidence : ℝ
  lane_line_confidence : ℝ
  d_lane_center_est : ℝ
  heading_error_est : ℝ
  tracks : List Track

structure SurfaceSlice where
  mu_fl : ℝ
  mu_fr : ℝ
  mu_rl : ℝ
  mu_rr : ℝ
  mu_mean : ℝ
  road_grade : ℝ
  road_bank : ℝ
  elevation_z : ℝ

/-! ## Track lists (04:54) -/

/-- The zero-filled `tracks[32]` array. -/
def toArray32 (l : List Track) : Fin 32 → Track := fun i => l.getD i Track.zero

/-- Ascending `range`, ties by ascending `target_actor_id` (04:54). -/
def trackLt (a b : Track) : Prop := a.range < b.range ∨ (a.range = b.range ∧ a.id < b.id)

def trackLe (a b : Track) : Bool :=
  decide (a.range < b.range ∨ (a.range = b.range ∧ a.id ≤ b.id))

/-- Sort and keep the first 32 (04:54). -/
def finalize (l : List Track) : List Track := (l.mergeSort trackLe).take 32

/-! ## Interpolation (04:36-41, 04:56-58) -/

def interpTrack (w : ℝ) (o n : Track) : Track :=
  { o with
    rel_x := interpReal .linear true w o.rel_x n.rel_x
    rel_y := interpReal .linear true w o.rel_y n.rel_y
    rel_z := interpReal .linear true w o.rel_z n.rel_z
    rel_vx := interpReal .linear true w o.rel_vx n.rel_vx
    rel_vy := interpReal .linear true w o.rel_vy n.rel_vy
    rel_yaw := interpReal .angle true w o.rel_yaw n.rel_yaw
    range := interpReal .linear true w o.range n.range
    bearing := interpReal .angle true w o.bearing n.bearing
    ttc_lon := interpReal .linear true w o.ttc_lon n.ttc_lon
    confidence := interpReal .linear true w o.confidence n.confidence }

/-- A track of s[k+1], interpolated with the track of the same id in s[k] if there is one
(04:41). -/
def matchTrack (w : ℝ) (n : List Track) (a : Track) : Track :=
  match n.find? (·.id == a.id) with
  | some c => interpTrack w a c
  | none => a

def mergeTracks (w : ℝ) (o n : List Track) : List Track :=
  finalize (o.map (matchTrack w n))

def visualDepS (o n : VisualSlice) : Bool := o.ego_road_id == n.ego_road_id
def visualDepD (o n : VisualSlice) : Bool := visualDepS o n && o.ego_lane_id == n.ego_lane_id
def radarDep (o n : RadarSlice) : Bool :=
  o.primary_target_id == n.primary_target_id && o.primary_target_id != 0

def interpVisual (w : ℝ) (o n : VisualSlice) : VisualSlice :=
  { o with
    ego_s := interpReal .linear (visualDepS o n) w o.ego_s n.ego_s
    ego_d := interpReal .linear (visualDepD o n) w o.ego_d n.ego_d
    lead_ttc := interpReal .linear true w o.lead_ttc n.lead_ttc
    tracks := mergeTracks w o.tracks n.tracks }

def interpRadar (w : ℝ) (o n : RadarSlice) : RadarSlice :=
  { o with
    primary_range := interpReal .linear (radarDep o n) w o.primary_range n.primary_range
    primary_azimuth := interpReal .angle (radarDep o n) w o.primary_azimuth n.primary_azimuth
    primary_rcs := interpReal .linear (radarDep o n) w o.primary_rcs n.primary_rcs
    tracks := mergeTracks w o.tracks n.tracks }

def interpCamera (w : ℝ) (o n : CameraSlice) : CameraSlice :=
  { o with
    obstacle_confidence := interpReal .linear true w o.obstacle_confidence n.obstacle_confidence
    lane_line_confidence := interpReal .linear true w o.lane_line_confidence n.lane_line_confidence
    d_lane_center_est := interpReal .linear true w o.d_lane_center_est n.d_lane_center_est
    heading_error_est := interpReal .angle true w o.heading_error_est n.heading_error_est
    tracks := mergeTracks w o.tracks n.tracks }

def interpSurface (w : ℝ) (o n : SurfaceSlice) : SurfaceSlice :=
  { mu_fl := interpReal .linear true w o.mu_fl n.mu_fl
    mu_fr := interpReal .linear true w o.mu_fr n.mu_fr
    mu_rl := interpReal .linear true w o.mu_rl n.mu_rl
    mu_rr := interpReal .linear true w o.mu_rr n.mu_rr
    mu_mean := interpReal .linear true w o.mu_mean n.mu_mean
    road_grade := interpReal .linear true w o.road_grade n.road_grade
    road_bank := interpReal .linear true w o.road_bank n.road_bank
    elevation_z := interpReal .linear true w o.elevation_z n.elevation_z }

/-! ## Well-formedness (04:48-52, 04:58) -/

def WFRadar (r : RadarSlice) : Prop :=
  (r.has_primary_target = 1 ↔ r.primary_target_id ≠ 0) ∧
  (r.primary_target_id = 0 → r.primary_range = 0 ∧ r.primary_azimuth = 0 ∧ r.primary_rcs = 0)
def WFTrack (x : Track) : Prop := x.confidence ∈ Set.Icc 0 1
def WFCamera (c : CameraSlice) : Prop :=
  c.obstacle_confidence ∈ Set.Icc 0 1 ∧ c.lane_line_confidence ∈ Set.Icc 0 1
def WFSurface (s : SurfaceSlice) : Prop := ∀ μ ∈ [s.mu_fl, s.mu_fr, s.mu_rl, s.mu_rr], μ ∈ Set.Icc 0 2

/-! ## Helper lemmas -/

theorem trackLe_iff (a b : Track) :
    trackLe a b = true ↔ a.range < b.range ∨ (a.range = b.range ∧ a.id ≤ b.id) := by
  simp [trackLe]

theorem trackLe_trans (a b c : Track) (h1 : trackLe a b = true) (h2 : trackLe b c = true) :
    trackLe a c = true := by
  rw [trackLe_iff] at *
  rcases h1 with h1 | ⟨h1, h1'⟩ <;> rcases h2 with h2 | ⟨h2, h2'⟩
  · exact Or.inl (h1.trans h2)
  · exact Or.inl (h2 ▸ h1)
  · exact Or.inl (h1 ▸ h2)
  · exact Or.inr ⟨h1.trans h2, h1'.trans h2'⟩

theorem trackLe_total (a b : Track) : (trackLe a b || trackLe b a) = true := by
  rw [Bool.or_eq_true, trackLe_iff, trackLe_iff]
  rcases lt_trichotomy a.range b.range with h | h | h
  · exact Or.inl (Or.inl h)
  · rcases le_total a.id b.id with h' | h'
    · exact Or.inl (Or.inr ⟨h, h'⟩)
    · exact Or.inr (Or.inr ⟨h.symm, h'⟩)
  · exact Or.inr (Or.inl h)

theorem matchTrack_id (w : ℝ) (n : List Track) (a : Track) : (matchTrack w n a).id = a.id := by
  unfold matchTrack
  split <;> rfl

theorem ids_map (w : ℝ) (o n : List Track) :
    (o.map (matchTrack w n)).map Track.id = o.map Track.id := by
  simp [List.map_map, Function.comp_def, matchTrack_id]

theorem finalize_perm {l : List Track} (h : l.length ≤ 32) : (finalize l).Perm l := by
  unfold finalize
  rw [List.take_of_length_le (by simpa using h)]
  exact List.mergeSort_perm l trackLe

theorem mem_of_mem_finalize {l : List Track} {x : Track} (h : x ∈ finalize l) : x ∈ l :=
  (List.mergeSort_perm l trackLe).mem_iff.mp (List.mem_of_mem_take h)

theorem sorted_lt {l : List Track} (h : (l.map Track.id).Nodup) :
    (l.mergeSort trackLe).Pairwise trackLt := by
  have hs := List.pairwise_mergeSort trackLe_trans trackLe_total l
  have hn : (l.mergeSort trackLe).Pairwise (fun a b => a.id ≠ b.id) :=
    List.pairwise_map.mp (((List.mergeSort_perm l trackLe).map Track.id).nodup_iff.mpr h)
  refine (hs.and hn).imp fun {a b} ⟨h1, h2⟩ => ?_
  rcases (trackLe_iff a b).mp h1 with h1 | ⟨h1, h1'⟩
  · exact Or.inl h1
  · exact Or.inr ⟨h1, lt_of_le_of_ne h1' h2⟩

section Theorems

variable {w : ℝ} {o n : Track} {l : List Track}

/-! ## Routes (04:16) -/

/-- P04-01: “Ordered array of up to 64 lanes (`dl_route_t`, §9, with nodes beyond `count`
zero-filled)” (04-perception.md:16). -/
theorem encodeRoute_isSome (l : List LaneRef) : (encodeRoute l).isSome ↔ l.length ≤ 64 := by
  unfold encodeRoute
  split <;> simp_all

/-- P04-01: “Ordered array of up to 64 lanes (`dl_route_t`, §9, with nodes beyond `count`
zero-filled)” (04-perception.md:16). -/
theorem encodeRoute_wf {l : List LaneRef} {r : Route} (h : encodeRoute l = some r) :
    r.count = l.length ∧ r.count ≤ 64 ∧ (∀ i : Fin 64, r.count ≤ i → r.nodes i = LaneRef.zero) ∧
      (List.ofFn r.nodes).take r.count = l := by
  unfold encodeRoute at h
  split_ifs at h with hl
  obtain rfl := Option.some.inj h
  refine ⟨rfl, hl, fun i hi => ?_, ?_⟩
  · simp [List.getD_eq_getElem?_getD, List.getElem?_eq_none hi]
  · apply List.ext_getElem
    · simp; omega
    · intro i h1 h2
      simp only [List.getElem_take, List.getElem_ofFn]
      simp [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem h2]

/-! ## Interpolation classes (04:38-39, 04:56-58) -/

/-- P04-20: “`HOLD`: Value from s[k+1]” (04-perception.md:38), for the HOLD fields of a
track. -/
theorem interpTrack_hold (w : ℝ) (o n : Track) :
    (interpTrack w o n).id = o.id ∧ (interpTrack w o n).road_id = o.road_id ∧
      (interpTrack w o n).lane_id = o.lane_id ∧
      (interpTrack w o n).object_class = o.object_class :=
  ⟨rfl, rfl, rfl, rfl⟩

/-- P04-20: “`HOLD`: Value from s[k+1]” (04-perception.md:38), for the HOLD fields of a
`VisualSlice`. -/
theorem interpVisual_hold (w : ℝ) (o n : VisualSlice) :
    (interpVisual w o n).ego_road_id = o.ego_road_id ∧
      (interpVisual w o n).ego_lane_id = o.ego_lane_id ∧
      (interpVisual w o n).left_lane_free = o.left_lane_free ∧
      (interpVisual w o n).right_lane_free = o.right_lane_free :=
  ⟨rfl, rfl, rfl, rfl⟩

/-- P04-20: “`HOLD`: Value from s[k+1]” (04-perception.md:38), for the HOLD fields of a
`RadarSlice`. -/
theorem interpRadar_hold (w : ℝ) (o n : RadarSlice) :
    (interpRadar w o n).has_primary_target = o.has_primary_target ∧
      (interpRadar w o n).primary_target_id = o.primary_target_id :=
  ⟨rfl, rfl⟩

/-- P04-20: “`HOLD`: Value from s[k+1]. Every integer, enum, flag, and `char[]` field is
`HOLD`” (04-perception.md:38, 04:56), for every non-float64 field of `TargetTrack`,
`VisualSlice`, and `RadarSlice` other than `num_tracks` (`CameraSlice` and `SurfaceSlice`
have no other such field; `num_tracks` is in `radar_num_tracks_hold`,
`camera_num_tracks_hold`, and `num_tracks_hold`). -/
theorem interp_hold (w : ℝ) :
    (∀ o n : Track, (interpTrack w o n).id = o.id ∧ (interpTrack w o n).road_id = o.road_id ∧
      (interpTrack w o n).lane_id = o.lane_id ∧
      (interpTrack w o n).object_class = o.object_class) ∧
    (∀ o n : VisualSlice, (interpVisual w o n).ego_road_id = o.ego_road_id ∧
      (interpVisual w o n).ego_lane_id = o.ego_lane_id ∧
      (interpVisual w o n).left_lane_free = o.left_lane_free ∧
      (interpVisual w o n).right_lane_free = o.right_lane_free) ∧
    (∀ o n : RadarSlice, (interpRadar w o n).has_primary_target = o.has_primary_target ∧
      (interpRadar w o n).primary_target_id = o.primary_target_id) :=
  ⟨interpTrack_hold w, interpVisual_hold w, interpRadar_hold w⟩

/-- P04-21: “A field with a dependency … is interpolated only when its dependency condition
holds between s[k+1] and s[k]. Otherwise that field takes its value from s[k+1]” (04:39);
“`ego_s` depends on `ego_road_id`. `ego_d` depends on `ego_road_id` and `ego_lane_id`.”
(04-perception.md:58) -/
theorem visual_dep_fail (w : ℝ) (o n : VisualSlice) :
    (o.ego_road_id ≠ n.ego_road_id → (interpVisual w o n).ego_s = o.ego_s) ∧
    (o.ego_road_id ≠ n.ego_road_id ∨ o.ego_lane_id ≠ n.ego_lane_id →
      (interpVisual w o n).ego_d = o.ego_d) := by
  refine ⟨fun h => ?_, fun h => ?_⟩
  · have hd : visualDepS o n = false := by simp [visualDepS, h]
    simp [interpVisual, interpReal, hd]
  · have hd : visualDepD o n = false := by
      rcases h with h | h <;> simp [visualDepD, visualDepS, h]
    simp [interpVisual, interpReal, hd]

/-- P04-21: “`primary_range`, `primary_azimuth`, and `primary_rcs` depend on
`primary_target_id`. … For the `primary_*` fields, `primary_target_id` must also be
nonzero.” (04-perception.md:58); otherwise the value comes from s[k+1] (04:39). -/
theorem radar_dep_fail (w : ℝ) (o n : RadarSlice)
    (h : o.primary_target_id ≠ n.primary_target_id ∨ o.primary_target_id = 0) :
    (interpRadar w o n).primary_range = o.primary_range ∧
      (interpRadar w o n).primary_azimuth = o.primary_azimuth ∧
      (interpRadar w o n).primary_rcs = o.primary_rcs := by
  have hd : radarDep o n = false := by rcases h with h | h <;> simp [radarDep, h]
  simp [interpRadar, interpReal, hd]

/-- P04-21: “The **dependency condition** of a field holds between two samples if each of
its dependency fields is equal in both” (04-perception.md:58); then the field is
interpolated (04:39). -/
theorem visual_dep_holds {o n : VisualSlice} (h : o.ego_road_id = n.ego_road_id) :
    (interpVisual w o n).ego_s = lerp w o.ego_s n.ego_s := by
  simp [interpVisual, visualDepS, interpReal, h]

/-- P04-21: “`ego_d` depends on `ego_road_id` and `ego_lane_id`. … The dependency
condition of a field holds between two samples if each of its dependency fields is equal in
both” (04-perception.md:58); then the field is interpolated (04:39). -/
theorem visual_dep_holds_d {o n : VisualSlice} (hr : o.ego_road_id = n.ego_road_id)
    (hl : o.ego_lane_id = n.ego_lane_id) :
    (interpVisual w o n).ego_d = lerp w o.ego_d n.ego_d := by
  simp [interpVisual, visualDepD, visualDepS, interpReal, hr, hl]

/-- P04-21: “`primary_range`, `primary_azimuth`, and `primary_rcs` depend on
`primary_target_id`. … For the `primary_*` fields, `primary_target_id` must also be
nonzero.” (04-perception.md:58); then each field follows its class (04:36-37, 04:39). -/
theorem radar_dep_holds {o n : RadarSlice} (h : o.primary_target_id = n.primary_target_id)
    (h0 : o.primary_target_id ≠ 0) :
    (interpRadar w o n).primary_range = lerp w o.primary_range n.primary_range ∧
      (interpRadar w o n).primary_azimuth =
        angleInterp w o.primary_azimuth n.primary_azimuth ∧
      (interpRadar w o n).primary_rcs = lerp w o.primary_rcs n.primary_rcs := by
  have hd : radarDep o n = true := by simp [radarDep, h, h ▸ h0]
  simp [interpRadar, interpReal, hd]

/-- P04-22: “`has_primary_target` is 1 exactly when `primary_target_id` is nonzero. When
`primary_target_id` is 0, `primary_range`, `primary_azimuth`, and `primary_rcs` are 0.”
(04-perception.md:58) -/
theorem interpRadar_wf (w : ℝ) (o n : RadarSlice) (ho : WFRadar o) :
    WFRadar (interpRadar w o n) := by
  refine ⟨ho.1, fun h0 => ?_⟩
  have h0' : o.primary_target_id = 0 := h0
  have hd : radarDep o n = false := by simp [radarDep, h0']
  simp only [interpRadar, interpReal, hd]
  exact ho.2 h0'

/-! ## Track arrays (04:41, 04:54) -/

/-- P04-23: “Matched across s[k+1] and s[k] by `target_actor_id`. … Tracks present in only
one sample are taken from s[k+1], or dropped if absent from s[k+1]. The result is sorted
and truncated …, and `num_tracks` is its length.” (04-perception.md:41) -/
theorem mergeTracks_ids (w : ℝ) (o n : List Track) (ho : o.length ≤ 32) :
    ((mergeTracks w o n).map Track.id).Perm (o.map Track.id) := by
  have := (finalize_perm (l := o.map (matchTrack w n)) (by simpa using ho)).map Track.id
  rwa [ids_map] at this

/-- P04-23: “Tracks present in both samples interpolate field by field under the rules
above” (04-perception.md:41). -/
theorem mergeTracks_matched {o n : List Track} {a c : Track} (ho : o.length ≤ 32)
    (hn : (n.map Track.id).Nodup) (ha : a ∈ o) (hc : c ∈ n) (h : a.id = c.id) :
    interpTrack w a c ∈ mergeTracks w o n := by
  have hf : n.find? (·.id == a.id) = some c := by
    cases hfc : n.find? (fun x => x.id == a.id) with
    | none =>
      rw [List.find?_eq_none] at hfc
      exact absurd (by simp [h]) (hfc c hc)
    | some c' =>
      have h1 := List.find?_some hfc
      have h2 := List.mem_of_find?_eq_some hfc
      simp at h1
      rw [List.inj_on_of_nodup_map hn h2 hc (h1.trans h)]
  have hm : matchTrack w n a = interpTrack w a c := by simp [matchTrack, hf]
  rw [mergeTracks, (finalize_perm (by simpa using ho)).mem_iff, ← hm]
  exact List.mem_map_of_mem ha

/-- P04-23: “Tracks present in only one sample are taken from s[k+1]” (04-perception.md:41):
a track of s[k+1] whose id is absent from s[k] is in the result unchanged. -/
theorem mergeTracks_unmatched {o n : List Track} {a : Track} (ho : o.length ≤ 32)
    (ha : a ∈ o) (hn : ∀ c ∈ n, c.id ≠ a.id) : a ∈ mergeTracks w o n := by
  have hf : n.find? (·.id == a.id) = none := by
    rw [List.find?_eq_none]
    intro c hc
    simpa using hn c hc
  have hm : matchTrack w n a = a := by simp [matchTrack, hf]
  rw [mergeTracks, (finalize_perm (by simpa using ho)).mem_iff, ← hm]
  exact List.mem_map_of_mem ha

/-- P04-23: “`num_tracks` is its length” (04-perception.md:41) agrees with `num_tracks` as
HOLD (04:38), for a `RadarSlice`. -/
theorem radar_num_tracks_hold {o n : RadarSlice} (ho : o.tracks.length ≤ 32) :
    (interpRadar w o n).tracks.length = o.tracks.length := by
  have := (finalize_perm (l := o.tracks.map (matchTrack w n.tracks)) (by simpa using ho)).length_eq
  simpa [interpRadar, mergeTracks] using this

/-- P04-23: “`num_tracks` is its length” (04-perception.md:41) agrees with `num_tracks` as
HOLD (04:38), for a `CameraSlice`. -/
theorem camera_num_tracks_hold {o n : CameraSlice} (ho : o.tracks.length ≤ 32) :
    (interpCamera w o n).tracks.length = o.tracks.length := by
  have := (finalize_perm (l := o.tracks.map (matchTrack w n.tracks)) (by simpa using ho)).length_eq
  simpa [interpCamera, mergeTracks] using this

/-- P04-23: “`num_tracks` is its length” (04-perception.md:41) agrees with `num_tracks` as
HOLD (04:38). -/
theorem num_tracks_hold {o n : VisualSlice} (ho : o.tracks.length ≤ 32) :
    (interpVisual w o n).tracks.length = o.tracks.length := by
  have := (finalize_perm (l := o.tracks.map (matchTrack w n.tracks)) (by simpa using ho)).length_eq
  simpa [interpVisual, mergeTracks] using this

/-- P04-24: “Within one slice, each `target_actor_id` appears at most once”
(04-perception.md:54). -/
theorem finalize_nodup (h : (l.map Track.id).Nodup) : ((finalize l).map Track.id).Nodup := by
  have hs : ((l.mergeSort trackLe).map Track.id).Nodup :=
    ((List.mergeSort_perm l trackLe).map Track.id).nodup_iff.mpr h
  exact hs.sublist ((List.take_sublist _ _).map _)

/-- P04-24: “Within one slice, each `target_actor_id` appears at most once”
(04-perception.md:54); interpolation keeps this. -/
theorem mergeTracks_nodup {o n : List Track} (ho : (o.map Track.id).Nodup) :
    ((mergeTracks w o n).map Track.id).Nodup :=
  finalize_nodup (by rw [ids_map]; exact ho)

/-- P04-25: “Tracks are sorted by ascending `range`, with ties broken by ascending
`target_actor_id`” (04-perception.md:54). This order is strict. -/
theorem trackLt_strictOrder :
    (∀ a, ¬ trackLt a a) ∧ ∀ a b c, trackLt a b → trackLt b c → trackLt a c := by
  refine ⟨fun a h => ?_, fun a b c h1 h2 => ?_⟩
  · rcases h with h | ⟨-, h⟩ <;> exact lt_irrefl _ h
  · rcases h1 with h1 | ⟨h1, h1'⟩ <;> rcases h2 with h2 | ⟨h2, h2'⟩
    · exact Or.inl (h1.trans h2)
    · exact Or.inl (h2 ▸ h1)
    · exact Or.inl (h1 ▸ h2)
    · exact Or.inr ⟨h1.trans h2, h1'.trans h2'⟩

/-- P04-25: with distinct ids (04:54) the order of 04-perception.md:54 is total. -/
theorem trackLt_total (a b : Track) (h : a.id ≠ b.id) : trackLt a b ∨ trackLt b a := by
  rcases lt_trichotomy a.range b.range with hr | hr | hr
  · exact Or.inl (Or.inl hr)
  · rcases Nat.lt_or_gt_of_ne h with hi | hi
    · exact Or.inl (Or.inr ⟨hr, hi⟩)
    · exact Or.inr (Or.inr ⟨hr.symm, hi⟩)
  · exact Or.inr (Or.inl hr)

/-- P04-25: “Tracks are sorted by ascending `range`, with ties broken by ascending
`target_actor_id`” (04-perception.md:54). -/
theorem finalize_sorted (h : (l.map Track.id).Nodup) : (finalize l).Pairwise trackLt :=
  (sorted_lt h).sublist (List.take_sublist _ _)

/-- P04-26: “`num_tracks` is at most 32” (04-perception.md:54). -/
theorem finalize_length (l : List Track) : (finalize l).length = min l.length 32 := by
  simp [finalize, Nat.min_comm]

/-- P04-26: “If a sensor detects more than 32 targets, the slice keeps the first 32 in this
order.” (04-perception.md:54) -/
theorem finalize_first32 {x : Track} (h : (l.map Track.id).Nodup) (hx : x ∈ l)
    (hd : x ∉ finalize l) : ∀ y ∈ finalize l, trackLt y x := by
  intro y hy
  have hs := sorted_lt h
  rw [← List.take_append_drop 32 (l.mergeSort trackLe), List.pairwise_append] at hs
  have hxs : x ∈ l.mergeSort trackLe := (List.mergeSort_perm l trackLe).mem_iff.mpr hx
  rw [← List.take_append_drop 32 (l.mergeSort trackLe), List.mem_append] at hxs
  rcases hxs with hxs | hxs
  · exact absurd hxs hd
  · exact hs.2.2 y hy x hxs

/-- P04-26: “entries beyond `num_tracks` are zero-filled” (04-perception.md:54). -/
theorem toArray32_zero (l : List Track) (i : Fin 32) (h : l.length ≤ i) :
    toArray32 l i = Track.zero := by
  simp [toArray32, List.getD_eq_getElem?_getD, List.getElem?_eq_none h]

/-! ## Value ranges (04:48-52) -/

/-- P04-27: “`confidence` ([0,1])” (04-perception.md:48). Interpolation keeps it. -/
theorem interpTrack_wf (hw : w ∈ Set.Ico (0 : ℝ) 1) (ho : WFTrack o) (hn : WFTrack n) :
    WFTrack (interpTrack w o n) := by
  simpa [WFTrack, interpTrack, interpReal] using lerp_mem_Icc hw ho hn

/-- P04-27: “`confidence` ([0,1])” (04-perception.md:48), for every merged track. -/
theorem mergeTracks_wf {o n : List Track} (hw : w ∈ Set.Ico (0 : ℝ) 1)
    (ho : ∀ x ∈ o, WFTrack x) (hn : ∀ x ∈ n, WFTrack x) :
    ∀ x ∈ mergeTracks w o n, WFTrack x := by
  intro x hx
  obtain ⟨a, ha, rfl⟩ := List.mem_map.mp (mem_of_mem_finalize hx)
  unfold matchTrack
  split
  · next c hc => exact interpTrack_wf hw (ho a ha) (hn c (List.mem_of_find?_eq_some hc))
  · exact ho a ha

/-- P04-27: “`obstacle_confidence`, `lane_line_confidence` ([0,1])” (04-perception.md:51).
Interpolation keeps them. -/
theorem interpCamera_wf {o n : CameraSlice} (hw : w ∈ Set.Ico (0 : ℝ) 1) (ho : WFCamera o)
    (hn : WFCamera n) : WFCamera (interpCamera w o n) := by
  simpa [WFCamera, interpCamera, interpReal] using
    And.intro (lerp_mem_Icc hw ho.1 hn.1) (lerp_mem_Icc hw ho.2 hn.2)

/-- P04-27: “per-corner friction μ ∈ [0, 2]” (04-perception.md:52). Interpolation keeps it. -/
theorem interpSurface_wf {o n : SurfaceSlice} (hw : w ∈ Set.Ico (0 : ℝ) 1) (ho : WFSurface o)
    (hn : WFSurface n) : WFSurface (interpSurface w o n) := by
  simp only [WFSurface, List.forall_mem_cons, List.not_mem_nil, false_imp_iff, implies_true,
    and_true] at *
  simp only [interpSurface, interpReal, if_true]
  exact ⟨lerp_mem_Icc hw ho.1 hn.1, lerp_mem_Icc hw ho.2.1 hn.2.1,
    lerp_mem_Icc hw ho.2.2.1 hn.2.2.1, lerp_mem_Icc hw ho.2.2.2 hn.2.2.2⟩

/-! ## `at` on slice buffers (04:33-41) -/

/-- P04-14..P04-17: `buffer.at(t_query, Interpolate)` on a `RadarSlice` buffer, in the
interior bracket s[k+1].t ≤ t_query < s[k].t, returns `interpRadar α s[k+1] s[k]`
(04-perception.md:35-41). -/
theorem at_radar {b : Buffer RadarSlice} {q : ℤ} (hb : SliceBuffer.Valid b)
    {s0 sl : Entry RadarSlice} (h0 : b.head? = some s0) (hl : b.getLast? = some sl)
    (hlo : (sl.t : ℤ) < q) (hhi : q < s0.t) {k : ℕ} {n o : Entry RadarSlice}
    (hn : b[k]? = some n) (ho : b[k + 1]? = some o) (hko : (o.t : ℤ) ≤ q) (hkn : q < n.t) :
    atQ (fun o n w => interpRadar w o n) .interpolate b q =
      some ⟨q.toNat, interpRadar (alpha q o n) o.data n.data⟩ :=
  at_interp_eq _ hb h0 hl hlo hhi hn ho hko hkn

/-- P04-14..P04-17: `at` in `Interpolate` mode on a `VisualSlice` buffer
(04-perception.md:35-41). -/
theorem at_visual {b : Buffer VisualSlice} {q : ℤ} (hb : SliceBuffer.Valid b)
    {s0 sl : Entry VisualSlice} (h0 : b.head? = some s0) (hl : b.getLast? = some sl)
    (hlo : (sl.t : ℤ) < q) (hhi : q < s0.t) {k : ℕ} {n o : Entry VisualSlice}
    (hn : b[k]? = some n) (ho : b[k + 1]? = some o) (hko : (o.t : ℤ) ≤ q) (hkn : q < n.t) :
    atQ (fun o n w => interpVisual w o n) .interpolate b q =
      some ⟨q.toNat, interpVisual (alpha q o n) o.data n.data⟩ :=
  at_interp_eq _ hb h0 hl hlo hhi hn ho hko hkn

/-- P04-14..P04-17: `at` in `Interpolate` mode on a `CameraSlice` buffer
(04-perception.md:35-41). -/
theorem at_camera {b : Buffer CameraSlice} {q : ℤ} (hb : SliceBuffer.Valid b)
    {s0 sl : Entry CameraSlice} (h0 : b.head? = some s0) (hl : b.getLast? = some sl)
    (hlo : (sl.t : ℤ) < q) (hhi : q < s0.t) {k : ℕ} {n o : Entry CameraSlice}
    (hn : b[k]? = some n) (ho : b[k + 1]? = some o) (hko : (o.t : ℤ) ≤ q) (hkn : q < n.t) :
    atQ (fun o n w => interpCamera w o n) .interpolate b q =
      some ⟨q.toNat, interpCamera (alpha q o n) o.data n.data⟩ :=
  at_interp_eq _ hb h0 hl hlo hhi hn ho hko hkn

/-- P04-14..P04-17: `at` in `Interpolate` mode on a `SurfaceSlice` buffer
(04-perception.md:35-36). -/
theorem at_surface {b : Buffer SurfaceSlice} {q : ℤ} (hb : SliceBuffer.Valid b)
    {s0 sl : Entry SurfaceSlice} (h0 : b.head? = some s0) (hl : b.getLast? = some sl)
    (hlo : (sl.t : ℤ) < q) (hhi : q < s0.t) {k : ℕ} {n o : Entry SurfaceSlice}
    (hn : b[k]? = some n) (ho : b[k + 1]? = some o) (hko : (o.t : ℤ) ≤ q) (hkn : q < n.t) :
    atQ (fun o n w => interpSurface w o n) .interpolate b q =
      some ⟨q.toNat, interpSurface (alpha q o n) o.data n.data⟩ :=
  at_interp_eq _ hb h0 hl hlo hhi hn ho hko hkn

end Theorems

/-! ## Lane references and driving direction (02-conventions.md:25-27) -/

section Lanes

/-- Traffic rule of a road: right-hand or left-hand traffic. -/
inductive Rule | rht | lht deriving DecidableEq

/-- 02-conventions.md:26: does lane `l` drive toward increasing s? -/
def drivesIncreasingS : Rule → ℤ → Bool
  | .rht, l => decide (l < 0)
  | .lht, l => decide (0 < l)

/-- 02-conventions.md:26: σ is +1 if the lane drives toward increasing s and −1 otherwise. -/
def sigma (r : Rule) (l : ℤ) : ℤ := if drivesIncreasingS r l then 1 else -1

/-- The decimal digit character of `d < 10`. -/
def digitChar (d : ℕ) : Char := Char.ofNat (48 + d)

/-- The value of a decimal digit character. -/
def digitVal (c : Char) : Option ℕ := if c.isDigit then some (c.toNat - 48) else none

/-- Decimal digits, least significant first; `[0]` for 0. -/
def digitsLE (n : ℕ) : List ℕ := if n = 0 then [0] else Nat.digits 10 n

def encodeNat (n : ℕ) : List Char := (digitsLE n).reverse.map digitChar

def decodeNat (cs : List Char) : Option ℕ :=
  if cs = [] then none else (cs.mapM digitVal).map (fun ds => Nat.ofDigits 10 ds.reverse)

/-- Decimal with an optional leading '-'. -/
def encodeInt : ℤ → List Char
  | .ofNat k => encodeNat k
  | .negSucc k => '-' :: encodeNat (k + 1)

def decodeInt : List Char → Option ℤ
  | [] => none
  | c :: cs => if c = '-' then (decodeNat cs).map (fun k => -(k : ℤ))
      else (decodeNat (c :: cs)).map (fun k => (k : ℤ))

/-- 02-conventions.md:25: "<road_id>:<lane_id>". -/
def render (road : List Char) (lane : ℤ) : List Char := road ++ ':' :: encodeInt lane

/-- Splits at the last colon (02-conventions.md:25). -/
def parse (s : List Char) : Option (List Char × ℤ) :=
  match s.reverse.span (· ≠ ':') with
  | (revLane, _ :: revRoad) => (decodeInt revLane.reverse).map (revRoad.reverse, ·)
  | _ => none

/-- Elevation profile z(s), superelevation and traffic rule of each road. The superelevation is
a roll angle, positive when the left of the reference line direction (increasing s) is
higher. -/
structure ElevMap where
  elev : String → ℝ → ℝ
  superelev : String → ℝ → ℝ
  rule : String → Rule

/-- A `road_grade` query: the actor's lane and s, and its heading and velocity. -/
structure GradeQuery where
  roadId : String
  laneId : ℤ
  s : ℝ
  yaw : ℝ
  vLon : ℝ

/-- 02-conventions.md:27: θ_road = σ arctan(dz/ds). -/
def roadGrade (m : ElevMap) (q : GradeQuery) : ℝ :=
  (sigma (m.rule q.roadId) q.laneId : ℝ) * Real.arctan (deriv (m.elev q.roadId) q.s)

/-- 02-conventions.md:27: φ_road = σ · the OpenDRIVE superelevation. -/
def roadBank (m : ElevMap) (q : GradeQuery) : ℝ :=
  (sigma (m.rule q.roadId) q.laneId : ℝ) * m.superelev q.roadId q.s

/-- Height of the road surface at s and lateral offset d, with d positive to the left in the
reference line direction (02-conventions.md:23): the cross section is tilted by the
superelevation about the reference line. -/
def crossHeight (m : ElevMap) (road : String) (s d : ℝ) : ℝ :=
  m.elev road s + d * Real.sin (m.superelev road s)

theorem digitVal_digitChar {d : ℕ} (h : d < 10) : digitVal (digitChar d) = some d := by
  interval_cases d <;> decide

theorem digitChar_ne {d : ℕ} (h : d < 10) : digitChar d ≠ ':' ∧ digitChar d ≠ '-' := by
  interval_cases d <;> decide

theorem digitsLE_lt (n : ℕ) : ∀ d ∈ digitsLE n, d < 10 := by
  intro d hd
  unfold digitsLE at hd
  split_ifs at hd
  · simp at hd; omega
  · exact Nat.digits_lt_base (by norm_num) hd

theorem mapM_digitVal (L : List ℕ) (h : ∀ d ∈ L, d < 10) :
    (L.map digitChar).mapM digitVal = some L := by
  induction L with
  | nil => rfl
  | cons d L ih =>
    simp only [List.map_cons, List.mapM_cons, digitVal_digitChar (h d (by simp)),
      ih (fun x hx => h x (by simp [hx]))]
    rfl

theorem decodeNat_encodeNat (n : ℕ) : decodeNat (encodeNat n) = some n := by
  have hl := digitsLE_lt n
  have hne : encodeNat n ≠ [] := by
    unfold encodeNat digitsLE; split_ifs with h0
    · simp
    · simpa using (Nat.digits_ne_nil_iff_ne_zero (b := 10)).mpr h0
  simp only [decodeNat, hne, ↓reduceIte]
  rw [encodeNat, mapM_digitVal _ (fun d hd => hl d (List.mem_reverse.mp hd))]
  simp only [Option.map_some, List.reverse_reverse, digitsLE]
  split_ifs with h0
  · simp [h0]
  · rw [Nat.ofDigits_digits]

theorem encodeNat_ne (n : ℕ) : ∀ c ∈ encodeNat n, c ≠ ':' ∧ c ≠ '-' := by
  intro c hc
  obtain ⟨d, hd, rfl⟩ := List.mem_map.mp hc
  exact digitChar_ne (digitsLE_lt n d (List.mem_reverse.mp hd))

theorem encodeInt_ne (n : ℤ) : ∀ c ∈ encodeInt n, c ≠ ':' := by
  intro c hc
  cases n with
  | ofNat k => exact (encodeNat_ne k c hc).1
  | negSucc k =>
    rcases List.mem_cons.mp hc with rfl | h
    · decide
    · exact (encodeNat_ne _ c h).1

theorem decodeInt_encodeInt (n : ℤ) : decodeInt (encodeInt n) = some n := by
  cases n with
  | ofNat k =>
    simp only [encodeInt]
    obtain ⟨c, cs, hcs⟩ : ∃ c cs, encodeNat k = c :: cs := by
      cases h : encodeNat k with
      | nil => have := decodeNat_encodeNat k; rw [h] at this; simp [decodeNat] at this
      | cons c cs => exact ⟨c, cs, rfl⟩
    have hc : c ≠ '-' := (encodeNat_ne k c (by simp [hcs])).2
    rw [hcs, decodeInt]; simp only [hc, ↓reduceIte]; rw [← hcs, decodeNat_encodeNat]
    rfl
  | negSucc k =>
    simp only [encodeInt, decodeInt, ↓reduceIte, decodeNat_encodeNat]
    rfl

theorem span_append_cons (p : Char → Bool) (l₁ l₂ : List Char) (c : Char)
    (h : ∀ x ∈ l₁, p x = true) (hc : p c = false) : (l₁ ++ c :: l₂).span p = (l₁, c :: l₂) := by
  rw [List.span_eq_takeWhile_dropWhile]
  induction l₁ with
  | nil => simp [hc]
  | cons x l ih =>
    have hx := h x (by simp)
    have ih := ih (fun y hy => h y (by simp [hy]))
    simp only [Prod.mk.injEq] at ih
    simp [hx, ih.1, ih.2]

/-- P02-13: “The text after the last colon is the signed lane index” (02-conventions.md:25).
`road` may contain ':'. -/
theorem parse_render (road : List Char) (lane : ℤ) : parse (render road lane) = some (road, lane) := by
  have hs : (render road lane).reverse.span (· ≠ ':') =
      ((encodeInt lane).reverse, ':' :: road.reverse) := by
    rw [render, List.reverse_append, List.reverse_cons, List.append_assoc, List.singleton_append]
    exact span_append_cons _ _ _ _
      (fun x hx => by simpa using encodeInt_ne lane x (List.mem_reverse.mp hx)) (by decide)
  rw [parse, hs]
  simp [decodeInt_encodeInt]

/-- P02-14: “For RHT, negative lanes drive toward increasing s. For LHT, positive lanes drive
toward increasing s” and “σ is +1 if it drives toward increasing s and −1 otherwise”
(02-conventions.md:26). Lane 0 is excluded by 02-conventions.md:22. -/
theorem sigma_spec (r : Rule) (l : ℤ) (hl : l ≠ 0) :
    (sigma r l = 1 ↔ (r = .rht ∧ l < 0) ∨ (r = .lht ∧ 0 < l)) ∧
      (sigma r l = -1 ↔ (r = .rht ∧ 0 < l) ∨ (r = .lht ∧ l < 0)) ∧
      (sigma r l = 1 ∨ sigma r l = -1) := by
  cases r <;> by_cases h : l < 0 <;> simp [sigma, drivesIncreasingS, h] <;> omega

theorem sigma_cases (r : Rule) (l : ℤ) : (sigma r l : ℝ) = 1 ∨ (sigma r l : ℝ) = -1 := by
  unfold sigma; split_ifs <;> simp

/-- P02-15: “`road_grade` θ_road is positive when the road rises in the driving direction …
θ_road = σ arctan(dz/ds)” (02-conventions.md:27). The rise along the driving direction is
modeled on its own: D is the rate of change of the elevation at s + σ τ, at τ = 0. -/
theorem roadGrade_sign (m : ElevMap) (q : GradeQuery) {D : ℝ}
    (hd : DifferentiableAt ℝ (m.elev q.roadId) q.s)
    (hD : HasDerivAt (fun τ => m.elev q.roadId (q.s + (sigma (m.rule q.roadId) q.laneId : ℝ) * τ))
      D 0) :
    (0 < roadGrade m q ↔ 0 < D) ∧ (roadGrade m q < 0 ↔ D < 0) ∧
      |roadGrade m q| < Real.pi / 2 := by
  set σ := (sigma (m.rule q.roadId) q.laneId : ℝ) with hσ
  have hin : HasDerivAt (fun τ : ℝ => q.s + σ * τ) σ 0 := by
    simpa using ((hasDerivAt_id (0 : ℝ)).const_mul σ).const_add q.s
  have hcomp := hd.hasDerivAt.comp_of_eq (0 : ℝ) hin (by simp)
  have hDe : D = σ * deriv (m.elev q.roadId) q.s := by
    rw [hD.unique hcomp, mul_comm]
  have hpos : ∀ x, 0 < Real.arctan x ↔ 0 < x := fun x => by
    have h := Real.arctan_strictMono.lt_iff_lt (a := 0) (b := x)
    rwa [Real.arctan_zero] at h
  have hneg : ∀ x, Real.arctan x < 0 ↔ x < 0 := fun x => by
    have h := Real.arctan_strictMono.lt_iff_lt (a := x) (b := 0)
    rwa [Real.arctan_zero] at h
  have habs : ∀ x, |Real.arctan x| < Real.pi / 2 := fun x =>
    abs_lt.mpr ⟨Real.neg_pi_div_two_lt_arctan x, Real.arctan_lt_pi_div_two x⟩
  simp only [roadGrade, ← hσ, hDe]
  rcases sigma_cases (m.rule q.roadId) q.laneId with h | h <;> rw [← hσ] at h <;> rw [h]
  · simp [hpos, hneg, habs]
  · simp [hpos, hneg, habs, abs_neg]

/-- P02-16: “An actor that drives against its lane, such as in reverse, still gets these
lane-relative signs” (02-conventions.md:27). The clause holds by design: `roadGrade` does
not read the query's `yaw` or `vLon`, so two queries that differ only in them agree. -/
theorem roadGrade_lane_relative (m : ElevMap) (q₁ q₂ : GradeQuery)
    (hr : q₁.roadId = q₂.roadId) (hl : q₁.laneId = q₂.laneId) (hs : q₁.s = q₂.s) :
    roadGrade m q₁ = roadGrade m q₂ := by
  simp only [roadGrade, hr, hl, hs]

/-- P02-41: “`road_bank` φ_road is positive when the road is higher on the left than on the
right, relative to that direction … φ_road = σ · the OpenDRIVE superelevation”
(02-conventions.md:27). The point at lateral offset σ w (w > 0) is left of the driving
direction, the point at −σ w right of it. -/
theorem roadBank_sign (m : ElevMap) (q : GradeQuery)
    (hse : m.superelev q.roadId q.s ∈ Set.Ioo (-(Real.pi / 2)) (Real.pi / 2)) {w : ℝ} (hw : 0 < w) :
    let σ := (sigma (m.rule q.roadId) q.laneId : ℝ)
    (crossHeight m q.roadId q.s (-(σ * w)) < crossHeight m q.roadId q.s (σ * w) ↔
        0 < roadBank m q) ∧
      (crossHeight m q.roadId q.s (σ * w) < crossHeight m q.roadId q.s (-(σ * w)) ↔
        roadBank m q < 0) := by
  intro σ
  set a := m.superelev q.roadId q.s with ha
  have mono := Real.strictMonoOn_sin
  have m0 : (0 : ℝ) ∈ Set.Icc (-(Real.pi / 2)) (Real.pi / 2) :=
    ⟨by linarith [Real.pi_pos], by linarith [Real.pi_pos]⟩
  have ma : a ∈ Set.Icc (-(Real.pi / 2)) (Real.pi / 2) := Set.Ioo_subset_Icc_self hse
  have hpos : 0 < Real.sin a ↔ 0 < a := by
    have := mono.lt_iff_lt m0 ma; rwa [Real.sin_zero] at this
  have hneg : Real.sin a < 0 ↔ a < 0 := by
    have := mono.lt_iff_lt ma m0; rwa [Real.sin_zero] at this
  simp only [crossHeight, roadBank, ← ha]
  rcases sigma_cases (m.rule q.roadId) q.laneId with h | h <;> simp only [σ, h]
  · rw [one_mul, one_mul]
    constructor
    · rw [← hpos]; constructor <;> intro <;> nlinarith
    · rw [← hneg]; constructor <;> intro <;> nlinarith
  · constructor
    · rw [show 0 < -1 * a ↔ a < 0 by constructor <;> intro <;> linarith, ← hneg]
      constructor <;> intro <;> nlinarith
    · rw [show -1 * a < 0 ↔ 0 < a by constructor <;> intro <;> linarith, ← hpos]
      constructor <;> intro <;> nlinarith

end Lanes

end Driveline.Tracks
