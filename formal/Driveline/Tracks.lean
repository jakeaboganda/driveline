import Mathlib.Tactic
import Driveline.Angles
import Driveline.SliceBuffer

/-!
# Sensor slices and track lists (spec §4.1, §4.3)

Routes (`docs/spec/04-perception.md:16`), the four slice payloads and `TargetTrack`
(04:45-52, `abi/driveline_abi.h:97-151`), their interpolation classes and dependency
conditions (04:36-41, 04:56-58), and the track list rules (04:54).

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

/-! ## Field class tables (abi:109-151, 04:56-57) -/

inductive TrackField | target_actor_id | rel_x | rel_y | rel_z | rel_vx | rel_vy | rel_yaw | range
  | bearing | ttc_lon | road_id | lane_id | object_class | confidence
  deriving DecidableEq

def TrackField.ty : TrackField → Ty
  | .target_actor_id | .lane_id | .object_class => .int
  | .road_id => .str
  | _ => .f64

def TrackField.cls : TrackField → Cls
  | .target_actor_id | .lane_id | .object_class | .road_id => .hold
  | .rel_yaw | .bearing => .angle
  | _ => .linear

inductive VisualField | ego_road_id | ego_lane_id | left_lane_free | right_lane_free | ego_s
  | ego_d | lead_ttc | num_tracks
  deriving DecidableEq

def VisualField.ty : VisualField → Ty
  | .ego_road_id => .str
  | .ego_lane_id | .left_lane_free | .right_lane_free | .num_tracks => .int
  | _ => .f64

def VisualField.cls : VisualField → Cls
  | .ego_road_id | .ego_lane_id | .left_lane_free | .right_lane_free | .num_tracks => .hold
  | _ => .linear

inductive RadarField | has_primary_target | num_tracks | primary_target_id | primary_range
  | primary_azimuth | primary_rcs
  deriving DecidableEq

def RadarField.ty : RadarField → Ty
  | .has_primary_target | .num_tracks | .primary_target_id => .int
  | _ => .f64

def RadarField.cls : RadarField → Cls
  | .has_primary_target | .num_tracks | .primary_target_id => .hold
  | .primary_azimuth => .angle
  | _ => .linear

inductive CameraField | obstacle_confidence | lane_line_confidence | d_lane_center_est
  | heading_error_est | num_tracks
  deriving DecidableEq

def CameraField.ty : CameraField → Ty
  | .num_tracks => .int
  | _ => .f64

def CameraField.cls : CameraField → Cls
  | .num_tracks => .hold
  | .heading_error_est => .angle
  | _ => .linear

inductive SurfaceField | mu_fl | mu_fr | mu_rl | mu_rr | mu_mean | road_grade | road_bank
  | elevation_z
  deriving DecidableEq

def SurfaceField.ty : SurfaceField → Ty := fun _ => .f64

def SurfaceField.cls : SurfaceField → Cls := fun _ => .linear

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

/-- P04-20: “Every integer, enum, flag, and `char[]` field is `HOLD`” (04:38, 04:56). -/
theorem track_hold : ∀ f : TrackField, f.ty ≠ .f64 → f.cls = .hold := by
  intro f; cases f <;> decide

/-- P04-20: “Every integer, enum, flag, and `char[]` field is `HOLD`” (04:38, 04:56). -/
theorem visual_hold : ∀ f : VisualField, f.ty ≠ .f64 → f.cls = .hold := by
  intro f; cases f <;> decide

/-- P04-20: “Every integer, enum, flag, and `char[]` field is `HOLD`” (04:38, 04:56). -/
theorem radar_hold : ∀ f : RadarField, f.ty ≠ .f64 → f.cls = .hold := by
  intro f; cases f <;> decide

/-- P04-20: “Every integer, enum, flag, and `char[]` field is `HOLD`” (04:38, 04:56). -/
theorem camera_hold : ∀ f : CameraField, f.ty ≠ .f64 → f.cls = .hold := by
  intro f; cases f <;> decide

/-- P04-20: “Every integer, enum, flag, and `char[]` field is `HOLD`” (04:38, 04:56). -/
theorem surface_hold : ∀ f : SurfaceField, f.ty ≠ .f64 → f.cls = .hold := by
  intro f; cases f <;> decide

/-- P04-20: “Every `float64` field is `LINEAR` unless listed here. … `ANGLE`: `rel_yaw`,
`bearing`, `primary_azimuth`, `heading_error_est`” (04-perception.md:56-57). -/
theorem track_angle : ∀ f : TrackField, f.cls = .angle ↔ f = .rel_yaw ∨ f = .bearing := by
  intro f; cases f <;> decide

/-- P04-20: “`ANGLE`: … `primary_azimuth`” (04-perception.md:57). -/
theorem radar_angle : ∀ f : RadarField, f.cls = .angle ↔ f = .primary_azimuth := by
  intro f; cases f <;> decide

/-- P04-20: “`ANGLE`: … `heading_error_est`” (04-perception.md:57). -/
theorem camera_angle : ∀ f : CameraField, f.cls = .angle ↔ f = .heading_error_est := by
  intro f; cases f <;> decide

/-- P04-20: no `VisualSlice` field is `ANGLE` (04-perception.md:57). -/
theorem visual_angle : ∀ f : VisualField, f.cls ≠ .angle := by
  intro f; cases f <;> decide

/-- P04-20: no `SurfaceSlice` field is `ANGLE` (04-perception.md:57). -/
theorem surface_angle : ∀ f : SurfaceField, f.cls ≠ .angle := by
  intro f; cases f <;> decide

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

end Theorems

end Driveline.Tracks
