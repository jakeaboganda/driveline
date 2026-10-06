import Mathlib.Analysis.SpecialFunctions.Complex.Arg
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Deriv
import Mathlib.Analysis.Calculus.Deriv.Prod
import Mathlib.Data.EReal.Basic
import Driveline.Angles
import Driveline.SliceBuffer
import Driveline.Tracks
import Driveline.VehicleSpec

/-!
# Standard sensors (§17.2)

Friction field lookup (17:24, 17:34), sensor history (17:38), mounts and detection (17:40-48),
track kinematics (17:48), primary and lead targets (17:54, 17:58), lane-free flags (17:58),
`mu_mean` (17:56), and the measured gap of `GAP_PROFILE` (05:80).
-/

namespace Driveline.Sensors

open Real Driveline.Tracks Driveline.VehicleSpec Driveline.SliceBuffer
open Driveline.Angles (atan2 atan2_mem atan2_zero_left)

open Classical

/-! ## Friction field (17:24, 17:34) -/

/-- 17:24 later zone wins. `inZone` is the zone match of 17:24. -/
def lastWins {Z : Type} (inZone : Z → Bool) (mu : Z → ℝ) (dflt : ℝ) (zs : List Z) : ℝ :=
  zs.foldl (fun acc z => if inZone z then mu z else acc) dflt

/-- `friction_zone(road, s_start, s_end, mu)` (17:24). -/
structure Zone where
  road : RoadId
  s0 : ℝ
  s1 : ℝ
  mu : ℝ

/-- "Sets μ on every lane of `road` for s_start ≤ s < s_end" (17:24). -/
noncomputable def Zone.covers (road : RoadId) (s : ℝ) (z : Zone) : Bool :=
  decide (z.road = road ∧ z.s0 ≤ s ∧ s < z.s1)

/-- μ at `(road, s)` from the zones in statement order and `default_friction` (17:24-25). -/
noncomputable def zoneMu (dflt : ℝ) (zs : List Zone) (road : RoadId) (s : ℝ) : ℝ :=
  lastWins (Zone.covers road s) Zone.mu dflt zs

structure FrenetHit where
  road : RoadId
  lane : ℤ
  s : ℝ
  d : ℝ

/-- 17:34 μ(X,Y). `w2f` = world_to_frenet (a parameter); `field` = zone-or-default at a lane. -/
def worldMu (w2f : ℝ → ℝ → ℝ → RoadId → Option FrenetHit) (field : RoadId → ℤ → ℝ → ℝ)
    (X Y psi : ℝ) (hint : RoadId) : Option ℝ :=
  (w2f X Y psi hint).map fun h => field h.road h.lane h.s

/-- The zone-or-default field (17:24-25) at a lane: a zone covers every lane of its road. -/
noncomputable def zoneField (dflt : ℝ) (zs : List Zone) : RoadId → ℤ → ℝ → ℝ :=
  fun r _ s => zoneMu dflt zs r s

def historyOk (N : ℤ) : Bool := decide (1 ≤ N ∧ N ≤ 64)

/-! ## Mounts and detection (17:40-48) -/

inductive Mount | frontBumper | windshield | center deriving DecidableEq

/-- Mount table (17:42-46). -/
noncomputable def mountPos (t : Tier0) : Mount → ℝ × ℝ × ℝ
  | .frontBumper => (t.wheelbase + t.overhang_front, 0, 1/2)
  | .windshield => (t.wheelbase / 2, 0, 9/10 * t.bbox_height)
  | .center => (t.wheelbase / 2, 0, t.bbox_height / 2)

noncomputable def xFront (t : Tier0) (m : Mount) : ℝ :=
  t.wheelbase + t.overhang_front - (mountPos t m).1

/-- heading → World, and World → heading (Rᵀ). -/
noncomputable def rot (ψ : ℝ) (v : ℝ × ℝ) : ℝ × ℝ :=
  (cos ψ * v.1 - sin ψ * v.2, sin ψ * v.1 + cos ψ * v.2)
noncomputable def rotT (ψ : ℝ) (v : ℝ × ℝ) : ℝ × ℝ :=
  (cos ψ * v.1 + sin ψ * v.2, -sin ψ * v.1 + cos ψ * v.2)
/-- ω ẑ × r -/
def crossZ (ω : ℝ) (r : ℝ × ℝ) : ℝ × ℝ := (-(ω * r.2), ω * r.1)

noncomputable def range3 (p : ℝ × ℝ × ℝ) : ℝ := √(p.1 ^ 2 + p.2.1 ^ 2 + p.2.2 ^ 2)
/-- Range and bearing test (17:48) on a sensor-frame point, with `Angles.atan2`, where
atan2(0, 0) = 0. -/
def inView (rng fov : ℝ) (p : ℝ × ℝ × ℝ) : Prop := range3 p ≤ rng ∧ |atan2 p.2.1 p.1| ≤ fov / 2

noncomputable def refPoint (t : Tier0) (pos : ℝ × ℝ) (ψ : ℝ) : ℝ × ℝ :=
  pos + ((t.wheelbase + t.overhang_front - t.overhang_rear) / 2) • (cos ψ, sin ψ)
noncomputable def sensorOrigin (t : Tier0) (m : Mount) (pos : ℝ × ℝ) (ψ : ℝ) : ℝ × ℝ :=
  pos + rot ψ ((mountPos t m).1, (mountPos t m).2.1)

/-- (rel_x, rel_y, rel_z) (17:48): the target's reference point in the ego's sensor frame, with
origin at the mount and the heading frame's axes, untilted by roll and pitch (17:40). `posT`,
`ψT`, `zT` are the target's rear-axle `pos`, yaw and `pos_z`; `posE`, `ψE`, `zE` the ego's. -/
noncomputable def relPos (tT tE : Tier0) (m : Mount) (posT : ℝ × ℝ) (ψT zT : ℝ) (posE : ℝ × ℝ)
    (ψE zE : ℝ) : ℝ × ℝ × ℝ :=
  let r := rotT ψE (refPoint tT posT ψT - sensorOrigin tE m posE ψE)
  (r.1, r.2, zT - (zE + (mountPos tE m).2.2))

/-- Detection (17:48): the target's `relPos` is within `range` and ±fov/2. -/
def detected (rng fov : ℝ) (tT tE : Tier0) (m : Mount) (posT : ℝ × ℝ) (ψT zT : ℝ)
    (posE : ℝ × ℝ) (ψE zE : ℝ) : Prop :=
  inView rng fov (relPos tT tE m posT ψT zT posE ψE zE)

/-- (rel_vx, rel_vy): Rᵀ(v_T − v_S) − ψ̇ ẑ × (rel_x, rel_y). -/
noncomputable def relVel (ψ ω : ℝ) (vT vS rel : ℝ × ℝ) : ℝ × ℝ := rotT ψ (vT - vS) - crossZ ω rel

noncomputable def ttcLon (x vx Lt xF : ℝ) : EReal :=
  if 0 < x ∧ vx < 0 then ((max 0 (x - Lt / 2 - xF) / (-vx) : ℝ) : EReal) else ⊤

/-- Point at angle θ on the circle of radius R about c, and its velocity at angular rate ω. -/
noncomputable def arcPt (c : ℝ × ℝ) (R θ : ℝ) : ℝ × ℝ := (c.1 + R * cos θ, c.2 + R * sin θ)
noncomputable def arcVel (R ω θ : ℝ) : ℝ × ℝ := (-(R * ω * sin θ), R * ω * cos θ)

/-! ## Primary and lead targets (17:54, 17:58) -/

def primaryEligible (W : ℝ) (x : Track) : Prop := 0 < x.rel_x ∧ |x.rel_y| ≤ W / 2 + 1/2
def IsPrimary (W : ℝ) (l : List Track) (p : Track) : Prop :=
  p ∈ l ∧ primaryEligible W p ∧ ∀ q ∈ l, primaryEligible W q → q ≠ p → trackLt p q
noncomputable def primary (W : ℝ) (l : List Track) : Option Track :=
  ((l.filter fun x => decide (primaryEligible W x)).mergeSort trackLe).head?
noncomputable def primaryRcs (W : ℝ) (l : List Track) : ℝ := if (primary W l).isSome then 10 else 0

def leadEligible (road : RoadId) (lane : ℤ) (x : Track) : Prop :=
  0 < x.rel_x ∧ x.road_id = road ∧ x.lane_id = lane
def leadLt (a b : Track) : Prop := a.rel_x < b.rel_x ∨ (a.rel_x = b.rel_x ∧ a.id < b.id)
noncomputable def leadLe (a b : Track) : Bool :=
  decide (a.rel_x < b.rel_x ∨ (a.rel_x = b.rel_x ∧ a.id ≤ b.id))
def IsLead (road : RoadId) (lane : ℤ) (l : List Track) (p : Track) : Prop :=
  p ∈ l ∧ leadEligible road lane p ∧ ∀ q ∈ l, leadEligible road lane q → q ≠ p → leadLt p q
noncomputable def lead (road : RoadId) (lane : ℤ) (l : List Track) : Option Track :=
  ((l.filter fun x => decide (leadEligible road lane x)).mergeSort leadLe).head?
/-- `ttc_lon` of a track (17:48) as an EReal (`Track.ttc_lon` is ℝ): `len` is L_bbox of the
target actor by id, `xF` the ego's x_front. -/
noncomputable def trackTtc (len : ℕ → ℝ) (xF : ℝ) (p : Track) : EReal :=
  ttcLon p.rel_x p.rel_vx (len p.id) xF

/-- `ttc` is the EReal ttc_lon of a track; 17:58 uses `trackTtc`. -/
noncomputable def leadTtc (ttc : Track → EReal) : Option Track → EReal
  | some p => ttc p
  | none => ⊤

/-! ## Lane-free flags (17:58) -/

inductive Dir | pos | neg deriving DecidableEq
def Dir.flip : Dir → Dir | .pos => .neg | .neg => .pos
structure Neighbor where
  lane : ℤ
  dir : Dir
/-- query_lane_topology at the actor's (road_id, lane_id, s). -/
structure Topo where
  outLeft : Option Neighbor
  outRight : Option Neighbor
def leftOut : Dir → Topo → Option Neighbor | .pos, t => t.outLeft | .neg, t => t.outRight
def rightOut : Dir → Topo → Option Neighbor | .pos, t => t.outRight | .neg, t => t.outLeft
def sideLane (σ : Dir) (o : Option Neighbor) : Option Neighbor := o.filter fun n => n.dir == σ
noncomputable def laneFree (road : RoadId) (σ : Dir) (o : Option Neighbor) (l : List Track) : ℕ :=
  match sideLane σ o with
  | none => 0
  | some n => if ∃ x ∈ l, x.road_id = road ∧ x.lane_id = n.lane ∧ |x.rel_x| ≤ 20 then 0 else 1

noncomputable def muMean (fl fr rl rr : ℝ) : ℝ := (fl + fr + rl + rr) / 4

/-! ## Surface contact points (17:56) -/

/-- t of one axle: its Tier 2 `track_width_f` or `track_width_r` if present, else 0.85 W_bbox. -/
noncomputable def trackW (t : Tier0) (tw : Option ℝ) : ℝ := tw.getD (17 / 20 * t.bbox_width)

/-- fl (L, +t/2), fr (L, −t/2), rl (0, +t/2), rr (0, −t/2) in the heading frame. -/
noncomputable def contactPoints (t : Tier0) (twF twR : Option ℝ) :
    (ℝ × ℝ) × (ℝ × ℝ) × (ℝ × ℝ) × (ℝ × ℝ) :=
  ((t.wheelbase, trackW t twF / 2), (t.wheelbase, -(trackW t twF / 2)),
   (0, trackW t twR / 2), (0, -(trackW t twR / 2)))

/-- (mu_fl, mu_fr, mu_rl, mu_rr): the World field `mu` at each contact point, placed by the
rear-axle origin `pos` and yaw ψ. -/
noncomputable def cornerMu {α : Type} (mu : ℝ × ℝ → α) (t : Tier0) (twF twR : Option ℝ)
    (pos : ℝ × ℝ) (ψ : ℝ) : α × α × α × α :=
  let c := contactPoints t twF twR
  (mu (pos + rot ψ c.1), mu (pos + rot ψ c.2.1), mu (pos + rot ψ c.2.2.1), mu (pos + rot ψ c.2.2.2))

/-! ## Measured gap (05:80) -/

/-- 05:80 ports whose slice type contains tracks[]. -/
inductive TrackPort
  | visual (b : Buffer VisualSlice) | radar (b : Buffer RadarSlice) | camera (b : Buffer CameraSlice)
inductive InPort | tracks (p : TrackPort) | other
def TrackPort.latestTracks : TrackPort → Option (List Track)
  | .visual b => (latest b).map (·.data.tracks)
  | .radar b => (latest b).map (·.data.tracks)
  | .camera b => (latest b).map (·.data.tracks)
def InPort.trackPort? : InPort → Option TrackPort | .tracks p => some p | .other => none
def measuredGap (ports : List InPort) (gapId : ℕ) : Option ℝ := do
  let p ← ports.findSome? InPort.trackPort?
  let ts ← p.latestTracks
  let tr ← ts.find? (·.id == gapId)
  pure tr.rel_x

/-! ## Helper lemmas -/

theorem lastWins_append {Z : Type} (inZone : Z → Bool) (mu : Z → ℝ) (dflt : ℝ) (l : List Z) (z : Z) :
    lastWins inZone mu dflt (l ++ [z]) = if inZone z then mu z else lastWins inZone mu dflt l := by
  simp [lastWins, List.foldl_append]

theorem lastWins_eq {Z : Type} (inZone : Z → Bool) (mu : Z → ℝ) (dflt : ℝ) (zs : List Z) :
    lastWins inZone mu dflt zs = ((zs.filter inZone).getLast?.map mu).getD dflt := by
  induction zs using List.reverseRecOn with
  | nil => rfl
  | append_singleton l z ih =>
    rw [lastWins_append, List.filter_append]
    by_cases h : inZone z <;> simp [h, ih]

theorem hasDerivAt_fst' {f : ℝ → ℝ × ℝ} {v : ℝ × ℝ} {t : ℝ} (h : HasDerivAt f v t) :
    HasDerivAt (fun τ => (f τ).1) v.1 t := by
  have := h.hasFDerivAt.fst.hasDerivAt
  simpa using this

theorem hasDerivAt_snd' {f : ℝ → ℝ × ℝ} {v : ℝ × ℝ} {t : ℝ} (h : HasDerivAt f v t) :
    HasDerivAt (fun τ => (f τ).2) v.2 t := by
  have := h.hasFDerivAt.snd.hasDerivAt
  simpa using this

theorem hasDerivAt_rotT {d : ℝ → ℝ × ℝ} {ψ : ℝ → ℝ} {D : ℝ × ℝ} {ω t : ℝ}
    (hd : HasDerivAt d D t) (hψ : HasDerivAt ψ ω t) :
    HasDerivAt (fun τ => rotT (ψ τ) (d τ)) (relVel (ψ t) ω D 0 (rotT (ψ t) (d t))) t := by
  have h1 := hasDerivAt_fst' hd
  have h2 := hasDerivAt_snd' hd
  have hx := (hψ.cos.mul h1).add (hψ.sin.mul h2)
  have hy := ((hψ.sin.neg).mul h1).add (hψ.cos.mul h2)
  convert hx.prodMk hy using 1
  all_goals (ext <;> simp [relVel, rotT, crossZ] <;> ring)

theorem hasDerivAt_rot {ψ : ℝ → ℝ} {ω t : ℝ} (r : ℝ × ℝ) (hψ : HasDerivAt ψ ω t) :
    HasDerivAt (fun τ => rot (ψ τ) r) (crossZ ω (rot (ψ t) r)) t := by
  have hx := (hψ.cos.mul_const r.1).sub (hψ.sin.mul_const r.2)
  have hy := (hψ.sin.mul_const r.1).add (hψ.cos.mul_const r.2)
  convert hx.prodMk hy using 1
  all_goals (ext <;> simp [rot, crossZ] <;> ring)

section Argmin

variable {lt : Track → Track → Prop} {le : Track → Track → Bool}

/-- `p` is the `lt`-least element of `l` with property `P`. -/
def IsMin (P : Track → Prop) (lt : Track → Track → Prop) (l : List Track) (p : Track) : Prop :=
  p ∈ l ∧ P p ∧ ∀ q ∈ l, P q → q ≠ p → lt p q

theorem isMin_unique {P : Track → Prop} {l : List Track} {p q : Track}
    (hasymm : ∀ a b, lt a b → lt b a → False)
    (hp : IsMin P lt l p) (hq : IsMin P lt l q) : p = q := by
  by_contra h
  exact hasymm p q (hp.2.2 q hq.1 hq.2.1 (Ne.symm h)) (hq.2.2 p hp.1 hp.2.1 h)

theorem argmin_spec (P : Track → Prop) (l : List Track)
    (htrans : ∀ a b c, le a b = true → le b c = true → le a c = true)
    (htotal : ∀ a b, (le a b || le b a) = true)
    (hlt : ∀ a b, le a b = true → a.id ≠ b.id → lt a b)
    (hasymm : ∀ a b, lt a b → lt b a → False)
    (hid : (l.map Track.id).Nodup) :
    (∀ p, ((l.filter fun x => decide (P x)).mergeSort le).head? = some p ↔ IsMin P lt l p) ∧
    (((l.filter fun x => decide (P x)).mergeSort le).head? = none ↔ ∀ q ∈ l, ¬ P q) := by
  set f := l.filter fun x => decide (P x)
  have hperm := List.mergeSort_perm f le
  have hfn : (f.map Track.id).Nodup := hid.sublist ((List.filter_sublist).map _)
  have hn : (f.mergeSort le).Pairwise (fun a b => a.id ≠ b.id) :=
    List.pairwise_map.mp ((hperm.map Track.id).nodup_iff.mpr hfn)
  have hs : (f.mergeSort le).Pairwise lt :=
    ((List.pairwise_mergeSort htrans htotal f).and hn).imp fun ⟨h1, h2⟩ => hlt _ _ h1 h2
  have hmem : ∀ x, x ∈ f.mergeSort le ↔ x ∈ l ∧ P x := by
    intro x; rw [hperm.mem_iff]; simp [f]
  have fwd : ∀ p, (f.mergeSort le).head? = some p → IsMin P lt l p := by
    intro p hp
    obtain ⟨rest, hrest⟩ : ∃ rest, f.mergeSort le = p :: rest := by
      cases h : f.mergeSort le with
      | nil => simp [h] at hp
      | cons a rest => simp [h] at hp; exact ⟨rest, by rw [hp]⟩
    have hp' := (hmem p).mp (by rw [hrest]; exact List.mem_cons_self)
    refine ⟨hp'.1, hp'.2, fun q hq hPq hne => ?_⟩
    have hq' := (hmem q).mpr ⟨hq, hPq⟩
    rw [hrest] at hq' hs
    rcases List.mem_cons.mp hq' with h | h
    · exact absurd h hne
    · exact List.rel_of_pairwise_cons hs h
  refine ⟨fun p => ⟨fwd p, fun hp => ?_⟩, ⟨fun h q hq hPq => ?_, fun h => ?_⟩⟩
  · cases hh : (f.mergeSort le).head? with
    | none =>
      rw [List.head?_eq_none_iff] at hh
      have := (hmem p).mpr ⟨hp.1, hp.2.1⟩
      simp [hh] at this
    | some a => rw [isMin_unique hasymm (fwd a hh) hp]
  · rw [List.head?_eq_none_iff] at h
    have := (hmem q).mpr ⟨hq, hPq⟩
    simp [h] at this
  · rw [List.head?_eq_none_iff, List.eq_nil_iff_forall_not_mem]
    intro x hx
    exact h x ((hmem x).mp hx).1 ((hmem x).mp hx).2

theorem trackLt_asymm (a b : Track) (h1 : trackLt a b) (h2 : trackLt b a) : False :=
  trackLt_strictOrder.1 a (trackLt_strictOrder.2 a b a h1 h2)

theorem trackLe_lt (a b : Track) (h : trackLe a b = true) (hne : a.id ≠ b.id) : trackLt a b := by
  rcases (trackLe_iff a b).mp h with h | ⟨h, h'⟩
  · exact Or.inl h
  · exact Or.inr ⟨h, lt_of_le_of_ne h' hne⟩

theorem leadLe_iff (a b : Track) :
    leadLe a b = true ↔ a.rel_x < b.rel_x ∨ (a.rel_x = b.rel_x ∧ a.id ≤ b.id) := by
  simp [leadLe]

theorem leadLe_trans (a b c : Track) (h1 : leadLe a b = true) (h2 : leadLe b c = true) :
    leadLe a c = true := by
  rw [leadLe_iff] at *
  rcases h1 with h1 | ⟨h1, h1'⟩ <;> rcases h2 with h2 | ⟨h2, h2'⟩
  · exact Or.inl (h1.trans h2)
  · exact Or.inl (h2 ▸ h1)
  · exact Or.inl (h1 ▸ h2)
  · exact Or.inr ⟨h1.trans h2, h1'.trans h2'⟩

theorem leadLe_total (a b : Track) : (leadLe a b || leadLe b a) = true := by
  rw [Bool.or_eq_true, leadLe_iff, leadLe_iff]
  rcases lt_trichotomy a.rel_x b.rel_x with h | h | h
  · exact Or.inl (Or.inl h)
  · rcases le_total a.id b.id with h' | h'
    · exact Or.inl (Or.inr ⟨h, h'⟩)
    · exact Or.inr (Or.inr ⟨h.symm, h'⟩)
  · exact Or.inr (Or.inl h)

theorem leadLe_lt (a b : Track) (h : leadLe a b = true) (hne : a.id ≠ b.id) : leadLt a b := by
  rcases (leadLe_iff a b).mp h with h | ⟨h, h'⟩
  · exact Or.inl h
  · exact Or.inr ⟨h, lt_of_le_of_ne h' hne⟩

theorem leadLt_asymm (a b : Track) (h1 : leadLt a b) (h2 : leadLt b a) : False := by
  rcases h1 with h1 | ⟨h1, h1'⟩ <;> rcases h2 with h2 | ⟨h2, h2'⟩
  · exact lt_asymm h1 h2
  · exact lt_irrefl _ (h2 ▸ h1)
  · exact lt_irrefl _ (h1 ▸ h2)
  · exact lt_asymm h1' h2'

end Argmin

/-! ## Theorems -/

/-- P17-02 (17-standard-library.md:24): `friction_zone` "Sets μ on every lane of `road` for
s_start ≤ s < s_end. Where zones overlap, the later statement wins", and `default_friction` is
"μ everywhere that no zone covers" (17:25). -/
theorem mu_later_zone_wins (dflt : ℝ) (zs : List Zone) (road : RoadId) (s : ℝ) :
    zoneMu dflt zs road s = ((zs.filter (Zone.covers road s)).getLast?.map Zone.mu).getD dflt :=
  lastWins_eq _ _ _ _

/-- `worldMu` for any lane field; 17:34 uses `zoneField` (P17-03). μ(X,Y) is "the zone or default value at the lane that
`world_to_frenet` returns for (X, Y), called with the actor's yaw as `psi` and its current
`road_id` as `hint_road_id`". -/
theorem world_mu_spec (w2f : ℝ → ℝ → ℝ → RoadId → Option FrenetHit) (field : RoadId → ℤ → ℝ → ℝ)
    (X Y psi : ℝ) (hint : RoadId) :
    ((worldMu w2f field X Y psi hint).isSome ↔ (w2f X Y psi hint).isSome) ∧
    ∀ h, w2f X Y psi hint = some h → worldMu w2f field X Y psi hint = some (field h.road h.lane h.s) := by
  refine ⟨by simp [worldMu], fun h hh => by simp [worldMu, hh]⟩

/-- P17-03 (17-standard-library.md:34): μ(X,Y) is "the zone or default value at the lane that
`world_to_frenet` returns for (X, Y), called with the actor's yaw as `psi` and its current
`road_id` as `hint_road_id`", with the zone or default value of 17:24-25. -/
theorem world_mu_zone_spec (w2f : ℝ → ℝ → ℝ → RoadId → Option FrenetHit) (dflt : ℝ)
    (zs : List Zone) (X Y psi : ℝ) (hint : RoadId) :
    ((worldMu w2f (zoneField dflt zs) X Y psi hint).isSome ↔ (w2f X Y psi hint).isSome) ∧
    ∀ h, w2f X Y psi hint = some h → worldMu w2f (zoneField dflt zs) X Y psi hint =
      some (((zs.filter (Zone.covers h.road h.s)).getLast?.map Zone.mu).getD dflt) := by
  refine ⟨(world_mu_spec w2f _ X Y psi hint).1, fun h hh => ?_⟩
  rw [(world_mu_spec w2f _ X Y psi hint).2 h hh]
  simp only [zoneField, mu_later_zone_wins]

/-- P17-08 (17-standard-library.md:38): "`history` must be a constant from 1 to 64". -/
theorem history_ok_iff (N : ℤ) : historyOk N = true ↔ 1 ≤ N ∧ N ≤ 64 := by
  simp [historyOk]

/-- P17-09 (17-standard-library.md:48): a target is detected if within `range` and "its bearing
atan2(y, x), with atan2(0, 0) = 0, in the sensor frame lies within ±fov/2";
`SurroundVisualSensor`: "`fov` is 2π" (17:53). -/
theorem full_fov_detects (rng : ℝ) (tT tE : Tier0) (m : Mount) (posT : ℝ × ℝ) (ψT zT : ℝ)
    (posE : ℝ × ℝ) (ψE zE : ℝ) :
    let p := relPos tT tE m posT ψT zT posE ψE zE
    atan2 p.2.1 p.1 ∈ Set.Ioc (-π) π ∧ atan2 0 0 = 0 ∧
      (detected rng (2 * π) tT tE m posT ψT zT posE ψE zE ↔ range3 p ≤ rng) := by
  intro p
  have hm := atan2_mem p.2.1 p.1
  refine ⟨hm, atan2_zero_left le_rfl, ⟨fun h => h.1, fun h => ⟨h, ?_⟩⟩⟩
  rw [abs_le]
  constructor <;> linarith [hm.1, hm.2]

/-- P17-10 (17-standard-library.md:48): "`rel_vx` and `rel_vy` are the time derivatives of
`rel_x` and `rel_y` in the sensor frame, which turns with the actor: the World velocity of the
target's reference point minus the World velocity of the sensor origin, rotated into the sensor
frame, minus ψ̇ ẑ × (x, y), so `rel_vx` gains ψ̇ y and `rel_vy` loses ψ̇ x". -/
theorem rel_vel_hasDerivAt {pT pS : ℝ → ℝ × ℝ} {ψ : ℝ → ℝ} {vT vS : ℝ × ℝ} {ω t : ℝ}
    (hT : HasDerivAt pT vT t) (hS : HasDerivAt pS vS t) (hψ : HasDerivAt ψ ω t) :
    HasDerivAt (fun τ => rotT (ψ τ) (pT τ - pS τ))
      (relVel (ψ t) ω vT vS (rotT (ψ t) (pT t - pS t))) t ∧
    relVel (ψ t) ω vT vS (rotT (ψ t) (pT t - pS t)) =
      ((rotT (ψ t) (vT - vS)).1 + ω * (rotT (ψ t) (pT t - pS t)).2,
       (rotT (ψ t) (vT - vS)).2 - ω * (rotT (ψ t) (pT t - pS t)).1) := by
  refine ⟨?_, ?_⟩
  · convert hasDerivAt_rotT (hT.sub hS) hψ using 1
    simp [relVel]
  · ext <;> simp [relVel, crossZ]

/-- P17-11 (17-standard-library.md:48): "Two actors that keep a constant gap on a curve
therefore have zero relative velocity, and their `ttc_lon` is `+INFINITY`". The gap is
(rel_x, rel_y), constant near t. -/
theorem constant_gap_zero_rel_vel {pT pS : ℝ → ℝ × ℝ} {ψ : ℝ → ℝ} {vT vS : ℝ × ℝ} {ω t : ℝ}
    {c : ℝ × ℝ} (hT : HasDerivAt pT vT t) (hS : HasDerivAt pS vS t) (hψ : HasDerivAt ψ ω t)
    (hc : (fun τ => rotT (ψ τ) (pT τ - pS τ)) =ᶠ[nhds t] fun _ => c) (Lt xF : ℝ) :
    relVel (ψ t) ω vT vS c = 0 ∧ ttcLon c.1 (relVel (ψ t) ω vT vS c).1 Lt xF = ⊤ := by
  have hd := (rel_vel_hasDerivAt hT hS hψ).1
  have hct : rotT (ψ t) (pT t - pS t) = c := hc.self_of_nhds
  have h0 : HasDerivAt (fun τ => rotT (ψ τ) (pT τ - pS τ)) 0 t :=
    (hasDerivAt_const t c).congr_of_eventuallyEq hc
  have hz : relVel (ψ t) ω vT vS c = 0 := by rw [← hct]; exact hd.unique h0
  refine ⟨hz, ?_⟩
  rw [hz]
  simp [ttcLon]

theorem hasDerivAt_arcPt (c : ℝ × ℝ) (R θ0 ω t : ℝ) :
    HasDerivAt (fun τ => arcPt c R (θ0 + ω * τ)) (arcVel R ω (θ0 + ω * t)) t := by
  have hθ : HasDerivAt (fun τ => θ0 + ω * τ) ω t := by
    simpa using ((hasDerivAt_id t).const_mul ω).const_add θ0
  have hx := (hθ.cos.const_mul R).const_add c.1
  have hy := (hθ.sin.const_mul R).const_add c.2
  convert hx.prodMk hy using 1
  all_goals (ext <;> simp [arcPt, arcVel] <;> ring)

/-- Instance for the P17-62 spec note: two points on one circle of radius R at the same angular
rate ω (equal speed |R ω|), angle gap Δ, sensor yaw tangent to the circle (θ + π/2). Their
sensor-frame offset is the constant (R sin Δ, R(1 − cos Δ)), so the relative velocity is 0. -/
theorem arc_equal_speed_zero_rel_vel (c : ℝ × ℝ) (R θ0 ω Δ t Lt xF : ℝ) :
    (∀ τ, rotT (θ0 + ω * τ + π / 2) (arcPt c R (θ0 + Δ + ω * τ) - arcPt c R (θ0 + ω * τ)) =
      (R * sin Δ, R * (1 - cos Δ))) ∧
    relVel (θ0 + ω * t + π / 2) ω (arcVel R ω (θ0 + Δ + ω * t)) (arcVel R ω (θ0 + ω * t))
      (R * sin Δ, R * (1 - cos Δ)) = 0 ∧
    ttcLon (R * sin Δ) 0 Lt xF = ⊤ := by
  have hc : ∀ τ, rotT (θ0 + ω * τ + π / 2) (arcPt c R (θ0 + Δ + ω * τ) - arcPt c R (θ0 + ω * τ)) =
      (R * sin Δ, R * (1 - cos Δ)) := by
    intro τ
    have e : θ0 + Δ + ω * τ = (θ0 + ω * τ) + Δ := by ring
    rw [e]
    set a := θ0 + ω * τ
    ext
    · simp only [rotT, arcPt, Prod.fst_sub, Prod.snd_sub, cos_pi_div_two, sin_pi_div_two,
        cos_add, sin_add]
      linear_combination (R * sin Δ) * sin_sq_add_cos_sq a
    · simp only [rotT, arcPt, Prod.fst_sub, Prod.snd_sub, cos_pi_div_two, sin_pi_div_two,
        cos_add, sin_add]
      linear_combination (R * (1 - cos Δ)) * sin_sq_add_cos_sq a
  have hψ : HasDerivAt (fun τ => θ0 + ω * τ + π / 2) ω t := by
    simpa using (((hasDerivAt_id t).const_mul ω).const_add θ0).add_const (π / 2)
  have hT : HasDerivAt (fun τ => arcPt c R (θ0 + Δ + ω * τ)) (arcVel R ω (θ0 + Δ + ω * t)) t :=
    hasDerivAt_arcPt c R (θ0 + Δ) ω t
  have h := constant_gap_zero_rel_vel hT (hasDerivAt_arcPt c R θ0 ω t) hψ
    (Filter.Eventually.of_forall hc) Lt xF
  refine ⟨hc, h.1, ?_⟩
  simp [ttcLon]

/-- P17-12 (17-standard-library.md:48): "v_P = v_ra + ψ̇ ẑ × r_P, with r_P the point's offset
from the rear-axle origin". `r` is the heading-frame offset, so r_P = rot ψ r. -/
theorem rigid_point_velocity {pRa : ℝ → ℝ × ℝ} {ψ : ℝ → ℝ} {vRa : ℝ × ℝ} {ω t : ℝ} (r : ℝ × ℝ)
    (hp : HasDerivAt pRa vRa t) (hψ : HasDerivAt ψ ω t) :
    HasDerivAt (fun τ => pRa τ + rot (ψ τ) r) (vRa + crossZ ω (rot (ψ t) r)) t :=
  hp.add (hasDerivAt_rot r hψ)

/-- P17-13 (17-standard-library.md:48): "`ttc_lon` is max(0, x − L_bbox,target/2 − x_front)/(−v_x)
if x > 0 and v_x < 0, else `+INFINITY`". -/
theorem ttcLon_nonneg (x vx Lt xF : ℝ) : 0 ≤ ttcLon x vx Lt xF := by
  unfold ttcLon
  split_ifs with h
  · exact EReal.coe_nonneg.mpr (div_nonneg (le_max_left _ _) (by linarith [h.2]))
  · exact le_top

/-- P17-14 (17-standard-library.md:48): "x_front = L + o_f − x_mount is the ego's extent ahead
of the mount, so the time runs to bumper contact"; `FrontBumper` is at (L + o_f, 0, 0.5 m)
(17:44). -/
theorem xFront_spec (t : Tier0) (m : Mount) (x vx Lt : ℝ) :
    (mountPos t m).1 + xFront t m = (boxX t).2 ∧ xFront t .frontBumper = 0 ∧
    (0 < x → vx < 0 → xFront t m ≤ x - Lt / 2 →
      ttcLon x vx Lt (xFront t m) = ((x - Lt / 2 - xFront t m) / (-vx) : ℝ) ∧
      x + vx * ((x - Lt / 2 - xFront t m) / (-vx)) - Lt / 2 = xFront t m) := by
  refine ⟨by simp [xFront, boxX], by simp [xFront, mountPos], fun hx hv hf => ⟨?_, ?_⟩⟩
  · simp [ttcLon, hx, hv, max_eq_right (by linarith : (0 : ℝ) ≤ x - Lt / 2 - xFront t m)]
  · have : vx ≠ 0 := hv.ne
    field_simp
    ring

/-- P17-15 (17-standard-library.md:54): "The primary target is the nearest of the slice's
tracks, by `range` and then smaller `target_actor_id`, with `rel_x` > 0 and |`rel_y`| ≤
W_bbox/2 + 0.5 m with the ego's W_bbox". Ids are distinct: `actor_id` is a "Unique actor
entity identifier" (05:47). -/
theorem primary_spec (W : ℝ) (l : List Track) (hid : (l.map Track.id).Nodup) :
    (∀ p, primary W l = some p ↔ IsPrimary W l p) ∧
    (primary W l = none ↔ ∀ q ∈ l, ¬ primaryEligible W q) :=
  argmin_spec (lt := trackLt) (primaryEligible W) l trackLe_trans trackLe_total trackLe_lt
    trackLt_asymm hid

/-- P17-16 (17-standard-library.md:54): "`primary_rcs` is 10 dBsm when a primary target exists,
and 0 otherwise". -/
theorem primary_rcs_spec (W : ℝ) (l : List Track) :
    primaryRcs W l = if ∃ q ∈ l, primaryEligible W q then 10 else 0 := by
  have h : (primary W l).isSome ↔ ∃ q ∈ l, primaryEligible W q := by
    simp [primary, List.head?_eq_none_iff, List.eq_nil_iff_forall_not_mem,
      Option.isSome_iff_ne_none, (List.mergeSort_perm _ trackLe).mem_iff]
  unfold primaryRcs
  by_cases hs : (primary W l).isSome
  · simp [hs, h.mp hs]
  · have hn : ¬ ∃ q ∈ l, primaryEligible W q := fun h' => hs (h.mpr h')
    simp only [hn, ↓reduceIte]
    simp [hs]

/-- Lead selection with any per-track `ttc`; 17:58 uses `trackTtc` (P17-17). -/
theorem lead_spec (road : RoadId) (lane : ℤ) (l : List Track) (ttc : Track → EReal)
    (hid : (l.map Track.id).Nodup) :
    (∀ p, lead road lane l = some p ↔ IsLead road lane l p) ∧
    (lead road lane l = none ↔ ∀ q ∈ l, ¬ leadEligible road lane q) ∧
    (lead road lane l = none → leadTtc ttc (lead road lane l) = ⊤) ∧
    (∀ p, lead road lane l = some p → leadTtc ttc (lead road lane l) = ttc p) := by
  have h := argmin_spec (lt := leadLt) (leadEligible road lane) l leadLe_trans leadLe_total
    leadLe_lt leadLt_asymm hid
  exact ⟨h.1, h.2, fun hn => by rw [hn]; rfl, fun p hp => by rw [hp]; rfl⟩

/-- P17-17 (17-standard-library.md:58): "`lead_ttc` is the `ttc_lon` of the lead track, which is
the track with the smallest positive `rel_x`, then the smaller `target_actor_id`, whose
`road_id` and `lane_id` equal the actor's. It is `+INFINITY` if there is none". `ttc_lon` is
that of 17:48 with the target's L_bbox `len p.id` and the ego's x_front `xF`. Ids are distinct
by 05:47. -/
theorem lead_ttc_spec (road : RoadId) (lane : ℤ) (l : List Track) (len : ℕ → ℝ) (xF : ℝ)
    (hid : (l.map Track.id).Nodup) :
    (∀ p, lead road lane l = some p ↔ IsLead road lane l p) ∧
    (lead road lane l = none ↔ ∀ q ∈ l, ¬ leadEligible road lane q) ∧
    (lead road lane l = none → leadTtc (trackTtc len xF) (lead road lane l) = ⊤) ∧
    (∀ p, lead road lane l = some p →
      leadTtc (trackTtc len xF) (lead road lane l) = ttcLon p.rel_x p.rel_vx (len p.id) xF) :=
  lead_spec road lane l (trackTtc len xF) hid

/-- The σ swap of 17:58 (P17-18). "That lane is `out_left_lane_id` of
`query_lane_topology` at the actor's `(road_id, lane_id, s)` if σ = +1, and `out_right_lane_id`
if σ = −1 ... A neighbor whose direction sign differs from σ counts as absent.
`right_lane_free` works the same way on the other side". -/
theorem lane_side_swap (σ : Dir) (t : Topo) (road : RoadId) (l : List Track) :
    σ.flip.flip = σ ∧ rightOut σ t = leftOut σ.flip t ∧ leftOut σ t = rightOut σ.flip t ∧
    (∀ n : Neighbor, n.dir ≠ σ → laneFree road σ (some n) l = 0) := by
  refine ⟨by cases σ <;> rfl, by cases σ <;> rfl, by cases σ <;> rfl, fun n hn => ?_⟩
  have : sideLane σ (some n) = none := by simp [sideLane, Option.filter, hn]
  simp [laneFree, this]

/-- P17-18 (17-standard-library.md:58): "`left_lane_free` is 1 if the lane to the actor's left
in its driving direction exists and has no track whose `road_id` and `lane_id` are that lane's
and whose |`rel_x`| ≤ 20 m. That lane is `out_left_lane_id` of `query_lane_topology` at the
actor's `(road_id, lane_id, s)` if σ = +1, and `out_right_lane_id` if σ = −1 ... A neighbor
whose direction sign differs from σ counts as absent. `right_lane_free` works the same way on
the other side". `left_lane_free` is `laneFree road σ (leftOut σ t) l`, `right_lane_free` is
`laneFree road σ (rightOut σ t) l`, with `road` the actor's `road_id`. -/
theorem lane_free_spec (σ : Dir) (t : Topo) (road : RoadId) (o : Option Neighbor)
    (l : List Track) :
    (laneFree road σ o l = 1 ↔ ∃ n, o = some n ∧ n.dir = σ ∧
      ∀ x ∈ l, ¬(x.road_id = road ∧ x.lane_id = n.lane ∧ |x.rel_x| ≤ 20)) ∧
    σ.flip.flip = σ ∧ rightOut σ t = leftOut σ.flip t ∧ leftOut σ t = rightOut σ.flip t := by
  refine ⟨?_, (lane_side_swap σ t road l).1, (lane_side_swap σ t road l).2.1,
    (lane_side_swap σ t road l).2.2.1⟩
  unfold laneFree
  cases o with
  | none => simp [sideLane]
  | some n =>
    by_cases hd : n.dir = σ
    · have : sideLane σ (some n) = some n := by simp [sideLane, Option.filter, hd]
      simp only [this]
      split_ifs with h
      · simp only [false_iff, not_exists, not_and]
        rintro n' hn' - hall
        cases hn'
        obtain ⟨x, hx, hx'⟩ := h
        exact hall x hx hx'.1 hx'.2.1 hx'.2.2
      · simp only [true_iff]
        exact ⟨n, rfl, hd, fun x hx hx' => h ⟨x, hx, hx'⟩⟩
    · have : sideLane σ (some n) = none := by simp [sideLane, Option.filter, hd]
      simp [this, hd]

/-- P17-61 (17-standard-library.md:48): "`rel_x`, `rel_y`, and `rel_z` are the reference point in
the sensor frame"; the reference point is "`pos` + ½(L + o_f − o_r)(cos ψ, sin ψ, 0) with its
Tier 0 geometry, at height `pos_z`"; the sensor frame "has the heading frame's axes and its
origin at the mount point ... Roll and pitch never tilt it" (17:40); "within `range` of the
sensor origin" is `range3` of it. -/
theorem rel_pos_spec (tT tE : Tier0) (m : Mount) (posT : ℝ × ℝ) (ψT zT : ℝ) (posE : ℝ × ℝ)
    (ψE zE : ℝ) :
    let p := relPos tT tE m posT ψT zT posE ψE zE
    let d := refPoint tT posT ψT - sensorOrigin tE m posE ψE
    rot ψE (p.1, p.2.1) = d ∧ p.2.2 = zT - (zE + (mountPos tE m).2.2) ∧
      range3 p = √(d.1 ^ 2 + d.2 ^ 2 + (zT - (zE + (mountPos tE m).2.2)) ^ 2) := by
  intro p d
  refine ⟨?_, rfl, ?_⟩
  · ext
    · simp only [p, relPos, rot, rotT]
      linear_combination d.1 * sin_sq_add_cos_sq ψE
    · simp only [p, relPos, rot, rotT]
      linear_combination d.2 * sin_sq_add_cos_sq ψE
  · simp only [range3, p, relPos, rotT]
    congr 1
    linear_combination (d.1 ^ 2 + d.2 ^ 2) * sin_sq_add_cos_sq ψE

/-- P17-19 (17-standard-library.md:56): "`mu_fl` through `mu_rr` are μ at the four contact
points ... `mu_mean` is their mean". -/
theorem mu_mean_bounds (a b c d : ℝ) :
    min (min a b) (min c d) ≤ muMean a b c d ∧ muMean a b c d ≤ max (max a b) (max c d) := by
  unfold muMean
  constructor
  · have := min_le_left (min a b) (min c d); have := min_le_right (min a b) (min c d)
    have := min_le_left a b; have := min_le_right a b
    have := min_le_left c d; have := min_le_right c d
    linarith
  · have := le_max_left (max a b) (max c d); have := le_max_right (max a b) (max c d)
    have := le_max_left a b; have := le_max_right a b
    have := le_max_left c d; have := le_max_right c d
    linarith

/-- P17-60 (17-standard-library.md:56): "`mu_fl` through `mu_rr` are μ at the four contact
points: `fl` at (L, +t/2), `fr` at (L, −t/2), `rl` at (0, +t/2), and `rr` at (0, −t/2) in the
heading frame, with t the Tier 2 track width of that axle (`track_width_f` or `track_width_r`)
if present, else 0.85 W_bbox". `mu` is μ at a World point (17:34), `pos` the rear-axle origin. -/
theorem surface_contact_points {α : Type} (mu : ℝ × ℝ → α) (t : Tier0) (twF twR : Option ℝ)
    (pos : ℝ × ℝ) (ψ : ℝ) :
    cornerMu mu t twF twR pos ψ =
      (mu (pos + rot ψ (t.wheelbase, trackW t twF / 2)),
       mu (pos + rot ψ (t.wheelbase, -(trackW t twF / 2))),
       mu (pos + rot ψ (0, trackW t twR / 2)), mu (pos + rot ψ (0, -(trackW t twR / 2)))) ∧
    (∀ w, trackW t (some w) = w) ∧ trackW t none = 17 / 20 * t.bbox_width :=
  ⟨rfl, fun _ => rfl, rfl⟩

/-- P05-43 (05-checkpoints.md:80): "It reads the measured gap g from the `latest()` sample of
its first declared such port, from the track whose `target_actor_id` equals
`gap_target_actor_id`: g is that track's `rel_x`". -/
theorem measured_gap_spec (ports : List InPort) (gid : ℕ) (g : ℝ) :
    measuredGap ports gid = some g ↔
      ∃ pre p post ts tr, ports = pre ++ InPort.tracks p :: post ∧
        (∀ q ∈ pre, q.trackPort? = none) ∧
        p.latestTracks = some ts ∧ ts.find? (·.id == gid) = some tr ∧ g = tr.rel_x := by
  have hport : ∀ p, ports.findSome? InPort.trackPort? = some p ↔
      ∃ pre post, ports = pre ++ InPort.tracks p :: post ∧ ∀ q ∈ pre, q.trackPort? = none := by
    intro p
    rw [List.findSome?_eq_some_iff]
    constructor
    · rintro ⟨pre, a, post, rfl, ha, hpre⟩
      cases a with
      | tracks p' => cases ha; exact ⟨pre, post, rfl, hpre⟩
      | other => cases ha
    · rintro ⟨pre, post, rfl, hpre⟩
      exact ⟨pre, _, post, rfl, rfl, hpre⟩
  unfold measuredGap
  simp only [Option.bind_eq_bind, Option.pure_def, Option.bind_eq_some_iff, Option.some.injEq]
  constructor
  · rintro ⟨p, hp, ts, hts, tr, htr, rfl⟩
    obtain ⟨pre, post, rfl, hpre⟩ := (hport p).mp hp
    exact ⟨pre, p, post, ts, tr, rfl, hpre, hts, htr, rfl⟩
  · rintro ⟨pre, p, post, ts, tr, rfl, hpre, hts, htr, rfl⟩
    exact ⟨p, (hport p).mpr ⟨pre, post, rfl, hpre⟩, ts, hts, tr, htr, rfl⟩

end Driveline.Sensors
