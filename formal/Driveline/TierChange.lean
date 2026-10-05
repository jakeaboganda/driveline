import Driveline.InitContext
import Driveline.Lifecycle
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Arctan

/-!
# Tier change

The tier change of a splice (docs/spec/06-lifecycle.md:83-87, 06:93): the promotion and
demotion classification, the committed state update of each, the re-trim set, and the
steering that the runtime writes into frames after a tier change.

The course angle keeps the path only for `v_lon ≠ 0`: at `v_lon = 0` the spec defines
`gamma = 0` and the rear-axle velocity is `(0, v_lat,ra)`, which the spec leaves to §8.
-/

noncomputable section

namespace Driveline.TierChange

open InitContext Real

/-- 06:84 'gamma = arctan(v_lat,ra / v_lon) for v_lon ≠ 0 and gamma = 0 otherwise'. -/
def gamma (vLat vLon : ℝ) : ℝ := if vLon = 0 then 0 else Real.arctan (vLat / vLon)

/-- 06:84 'the rear-axle course angle chi = psi + gamma'. -/
def chi (c : Chassis) : ℝ := c.psi + gamma c.vLat c.vLon

/-- The `ST` steady state of §8 at `(v_lon, psi_dot)`: `v_lat,ra`, `δ_ss` and `β_cg`. -/
structure STSol where
  vLat : ℝ
  δ : ℝ
  β : ℝ

/-- 06:84 the promotion update of the committed state. -/
def promote (s : STSol) (c : Chassis) : Chassis :=
  { c with vLat := s.vLat, aLon := c.aLon - s.vLat * c.psiDot, fwa := s.δ, beta := s.β,
           psi := Angles.wrap (chi c - gamma s.vLat c.vLon) }

/-- 06:85 the demotion update of the committed state. The spec gives no value for `β_cg`,
so it is the parameter `βKS`. -/
def demote (δKS βKS : ℝ) (c : Chassis) : Chassis :=
  { c with vLat := 0, fwa := δKS, psi := Angles.wrap (chi c), aLon := c.aLon + c.vLat * c.psiDot,
           aLat := c.vLon * c.psiDot, beta := βKS }

/-- The kind of a splice that replaces the physics component. -/
inductive Change | promo | demo | none
  deriving DecidableEq

/-- 06:83 the classification by the outgoing and incoming `required_tier`. -/
def classify (o n : Fin 3) : Change :=
  if o = 0 ∧ n ≠ 0 then .promo else if o ≠ 0 ∧ n = 0 then .demo else .none

/-- 06:86 the committed state update of a splice of the physics component. -/
def update (s : STSol) (δKS βKS : ℝ) (o n : Fin 3) (c : Chassis) : Chassis :=
  match classify o n with
  | .promo => promote s c
  | .demo => demote δKS βKS c
  | .none => c

/-- The world-frame velocity of the rear axle. -/
def worldVel (c : Chassis) : ℝ × ℝ :=
  (c.vLon * Real.cos c.psi - c.vLat * Real.sin c.psi,
   c.vLon * Real.sin c.psi + c.vLat * Real.cos c.psi)

/-- 06:87 the re-trim set, in Phase 2 order `order`: the Stage 2 instances (`st`) that serve
the actor (`sv`), have a data path to the new physics component (`rc`), and whose output type
is not `Lon<T>` (`lo`). -/
def retrimSet {ι : Type} (order : List ι) (st sv rc lo : ι → Bool) : List ι :=
  order.filter (fun x => st x && sv x && rc x && !lo x)

end Driveline.TierChange

/-- 06:93 the steering of a `KinematicControlFrame` after a tier change: `ANGLE` with
`steer_angle_cmd = fwa` and `steer_rate_cmd = +INFINITY`, a `NONE` group stays `NONE`, and
then every field that the modes do not use is zeroed. -/
def Driveline.KinematicControlFrame.steerAfter (fwa : ℝ) (f : KinematicControlFrame) :
    KinematicControlFrame :=
  (if f.steer = .none then f else
    { f with steer := .angle, steerAngleCmd := .fin fwa, steerRateCmd := .posInf }).zero

/-- 06:93 the steering of an `ActuatorControlFrame` after a tier change: `ANGLE` with
`steering_wheel_norm = clamp(fwa / δ_max, ±1)`, a `NONE` group stays `NONE`, and then every
field that the modes do not use is zeroed. -/
def Driveline.ActuatorControlFrame.steerAfter (fwa δmax : ℝ) (f : ActuatorControlFrame) :
    ActuatorControlFrame :=
  (if f.wheel = .none then f else
    { f with wheel := .angle, steeringWheelNorm := .fin (InitContext.wheelNorm fwa δmax) }).zero

namespace Driveline.TierChange

open InitContext Real

theorem cos_wrap (x : ℝ) : Real.cos (Angles.wrap x) = Real.cos x := by
  obtain ⟨n, h⟩ := Angles.wrap_eq_add x
  rw [h, Real.cos_add_int_mul_two_pi]

theorem sin_wrap (x : ℝ) : Real.sin (Angles.wrap x) = Real.sin x := by
  obtain ⟨n, h⟩ := Angles.wrap_eq_add x
  rw [h, Real.sin_add_int_mul_two_pi]

theorem wrap_add_int (x : ℝ) (n : ℤ) : Angles.wrap (x + n * (2 * π)) = Angles.wrap x := by
  simp only [Angles.wrap]
  rw [← zsmul_eq_mul, toIocMod_add_zsmul]

theorem wrap_wrap_add (x y : ℝ) : Angles.wrap (Angles.wrap x + y) = Angles.wrap (x + y) := by
  obtain ⟨n, h⟩ := Angles.wrap_eq_add x
  rw [h, show x + n * (2 * π) + y = (x + y) + n * (2 * π) by ring, wrap_add_int]

/-- For `v_lon ≠ 0` the rear-axle velocity is `v_lon / cos gamma` along `chi`. -/
theorem worldVel_chi (c : Chassis) (hv : c.vLon ≠ 0) :
    worldVel c = (c.vLon / Real.cos (gamma c.vLat c.vLon)) •
      (Real.cos (chi c), Real.sin (chi c)) := by
  have hc := Real.cos_arctan_pos (c.vLat / c.vLon)
  have hs : Real.sin (Real.arctan (c.vLat / c.vLon)) =
      c.vLat / c.vLon * Real.cos (Real.arctan (c.vLat / c.vLon)) := by
    rw [Real.sin_arctan, Real.cos_arctan]; ring
  simp only [worldVel, chi, gamma, hv, ↓reduceIte, Real.cos_add, Real.sin_add, hs, Prod.smul_mk,
    smul_eq_mul, Prod.mk.injEq]
  constructor <;> field_simp

/-- P06-19. 06:84 'A tier change keeps the sign of v_lon, so keeping chi keeps the path in
reverse too'. -/
theorem path_kept (c c' : Chassis) (hv : c.vLon ≠ 0) (hs : 0 < c'.vLon * c.vLon)
    (hχ : Angles.wrap (chi c') = Angles.wrap (chi c)) :
    ∃ k : ℝ, 0 < k ∧ worldVel c' = k • worldVel c := by
  have hv' : c'.vLon ≠ 0 := by rintro h; rw [h, zero_mul] at hs; exact lt_irrefl _ hs
  have hc := Real.cos_arctan_pos (c.vLat / c.vLon)
  have hc' := Real.cos_arctan_pos (c'.vLat / c'.vLon)
  have ecos : Real.cos (chi c') = Real.cos (chi c) := by rw [← cos_wrap, hχ, cos_wrap]
  have esin : Real.sin (chi c') = Real.sin (chi c) := by rw [← sin_wrap, hχ, sin_wrap]
  rw [worldVel_chi c hv, worldVel_chi c' hv', ecos, esin]
  simp only [gamma, hv, hv', ↓reduceIte]
  have h2 : 0 < c.vLon ^ 2 := lt_of_le_of_ne (sq_nonneg _) (Ne.symm (pow_ne_zero 2 hv))
  refine ⟨c'.vLon * c.vLon * Real.cos (Real.arctan (c.vLat / c.vLon)) /
    (c.vLon ^ 2 * Real.cos (Real.arctan (c'.vLat / c'.vLon))),
    div_pos (mul_pos hs hc) (mul_pos h2 hc'), ?_⟩
  rw [← mul_smul]
  congr 1
  field_simp

/-- P06-19. 06:84 'A tier change keeps the sign of v_lon': the update keeps `v_lon`. -/
theorem update_keeps_vlon (s : STSol) (δ β : ℝ) (o n : Fin 3) (c : Chassis) :
    (update s δ β o n c).vLon = c.vLon := by
  unfold update; split <;> rfl

/-- P06-17. 06:83 'a promotion if the outgoing component's required_tier is 0 and the incoming
one's is 1 or 2, and a demotion in the reverse case'. Tier 3 cannot occur: 16:91 'Its value
must be 0, 1, or 2'. -/
theorem classify_spec (o n : Fin 3) :
    (classify o n = .promo ↔ o = 0 ∧ n ≠ 0) ∧ (classify o n = .demo ↔ o ≠ 0 ∧ n = 0) ∧
      (classify o n = .none ↔ (o = 0 ↔ n = 0)) := by
  revert o n; decide

/-- P06-18. 06:83 'Tiers 1 and 2 share the ST steady state ..., so a splice between them
changes no field'. -/
theorem update_tiers12 (s : STSol) (δ β : ℝ) (o n : Fin 3) (ho : o ≠ 0) (hn : n ≠ 0)
    (c : Chassis) : update s δ β o n c = c := by
  have : classify o n = .none := by simp [classify, ho, hn]
  simp [update, this]

/-- P06-20. 06:84 'v_lat,ra goes from 0 to the solved value, a_lon becomes
a_lon − v_lat,ra psi_dot so that v_dot_lon is kept'. -/
theorem promote_vdot (s : STSol) (c : Chassis) (h0 : c.vLat = 0) :
    vdot (promote s c) = vdot c := by
  simp only [vdot, promote, h0]; ring

/-- P06-21. 06:84 'Five fields change: v_lat,ra ..., a_lon ..., front_wheel_angle ..., β_cg
..., and the yaw'. Every other field is kept. -/
theorem promote_fields (s : STSol) (c : Chassis) :
    { promote s c with
        vLat := c.vLat, aLon := c.aLon, fwa := c.fwa, beta := c.beta, psi := c.psi } = c := by
  cases c; rfl

/-- P06-22. 06:84 'the yaw becomes psi = chi − gamma with gamma from the solved v_lat,ra
..., wrapped to (−π, π], so the actor keeps its path, as at spawn'. -/
theorem promote_chi (s : STSol) (c : Chassis) :
    Angles.wrap (chi (promote s c)) = Angles.wrap (chi c) ∧
      (c.vLon ≠ 0 → ∃ k : ℝ, 0 < k ∧ worldVel (promote s c) = k • worldVel c) := by
  have h : Angles.wrap (chi (promote s c)) = Angles.wrap (chi c) := by
    simp only [chi, promote]
    rw [wrap_wrap_add, sub_add_cancel]
  refine ⟨h, fun hv => path_kept c _ hv ?_ h⟩
  simp only [promote]
  exact mul_self_pos.mpr hv

/-- P06-24. 06:85 'a_lon becomes a_lon + v_lat,ra psi_dot with the old v_lat,ra so that
v_dot_lon is kept' and 'The runtime keeps ... chi'. -/
theorem demote_vdot (δ β : ℝ) (c : Chassis) :
    vdot (demote δ β c) = vdot c ∧ Angles.wrap (chi (demote δ β c)) = Angles.wrap (chi c) := by
  refine ⟨by simp only [vdot, demote]; ring, ?_⟩
  simp only [chi, demote, gamma, zero_div, Real.arctan_zero, ite_self, add_zero]
  exact Angles.wrap_of_mem (Angles.wrap_mem _)

/-- P06-25. 06:85 'These five fields and β_cg change'. Every other field is kept. -/
theorem demote_fields (δ β : ℝ) (c : Chassis) :
    { demote δ β c with
        vLat := c.vLat, fwa := c.fwa, psi := c.psi, aLon := c.aLon, aLat := c.aLat,
        beta := c.beta } = c := by
  cases c; rfl

/-- P06-26. 06:86 'writes the changed fields into the committed state X(t) before any warm
start. The map cache is left unchanged'; 06:84-85 'The runtime keeps the position ...
and psi_dot'. -/
theorem update_keeps (s : STSol) (δ β : ℝ) (o n : Fin 3) (c : Chassis) :
    let c' := update s δ β o n c
    c'.cache = c.cache ∧ c'.x = c.x ∧ c'.y = c.y ∧ c'.z = c.z ∧ c'.psiDot = c.psiDot ∧
      c'.actorId = c.actorId := by
  unfold update; split <;> exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- P06-27. 06:87 'the runtime moves the re-trim set, in Phase 2 order, ...: every Stage 2
instance with a data path to the new physics component, that serves the actor and whose
output type is not Lon<T>'. -/
theorem retrimSet_spec {ι : Type} (order : List ι) (st sv rc lo : ι → Bool) (x : ι) :
    (retrimSet order st sv rc lo).Sublist order ∧
      (x ∈ retrimSet order st sv rc lo ↔
        x ∈ order ∧ st x ∧ sv x ∧ rc x ∧ lo x = false) := by
  refine ⟨List.filter_sublist, ?_⟩
  simp [retrimSet, and_assoc]

theorem kcf_zero_zero (f : KinematicControlFrame) : f.zero.zero = f.zero := by
  obtain ⟨h, a, s, x1, x2, x3, x4⟩ := f
  cases a <;> cases s <;> rfl

theorem acf_zero_zero (f : ActuatorControlFrame) : f.zero.zero = f.zero := by
  obtain ⟨h, p, w, g, x0, x1, x2, x3, x4⟩ := f
  cases p <;> cases w <;> cases g <;> rfl

/-- P06-34. 06:93 'In a KinematicControlFrame the steering group becomes ANGLE with
steer_angle_cmd = front_wheel_angle and steer_rate_cmd = +INFINITY ... A NONE steering group
stays NONE. The runtime then zeroes every field that the new modes do not use, and each frame
keeps its timestamp_ns. Longitudinal fields keep their last values'. -/
theorem kcf_steerAfter (w : ℝ) (f : KinematicControlFrame) :
    let g := f.steerAfter w
    g.steerAfter w = g ∧ (f.steer = .none → g.steer = .none) ∧ g.accel = f.accel ∧
      g.header = f.header ∧
      ∀ fld, f.accel.uses fld = true → KinematicControlFrame.agreeOn fld g f := by
  obtain ⟨h, a, s, x1, x2, x3, x4⟩ := f
  cases a <;> cases s <;> refine ⟨?_, ?_, rfl, rfl, ?_⟩ <;>
    first
    | rfl
    | (intro fld; cases fld <;> intro hu <;> first | rfl | cases hu)
    | (intro _; rfl)

/-- P06-34. 06:93 the `ActuatorControlFrame` case: 'it becomes ANGLE with steering_wheel_norm
= clamp(front_wheel_angle / δ_max, ±1). A NONE steering group stays NONE ... Longitudinal
fields keep their last values'. -/
theorem acf_steerAfter (w δmax : ℝ) (f : ActuatorControlFrame) :
    let g := f.steerAfter w δmax
    g.steerAfter w δmax = g ∧ (f.wheel = .none → g.wheel = .none) ∧ g.pedal = f.pedal ∧
      g.gear = f.gear ∧ g.header = f.header ∧
      ∀ fld, (f.pedal.uses fld || f.gear.uses fld) = true →
        ActuatorControlFrame.agreeOn fld g f := by
  obtain ⟨h, p, wm, gm, x0, x1, x2, x3, x4⟩ := f
  cases p <;> cases wm <;> cases gm <;> refine ⟨?_, ?_, rfl, rfl, rfl, ?_⟩ <;>
    first
    | rfl
    | (intro fld; cases fld <;> intro hu <;> first | rfl | cases hu)
    | (intro _; rfl)

/-- P05-42. 05:32 'the steering that the runtime writes after a tier change uses ANGLE'. -/
theorem steerAfter_angle (w δmax : ℝ) (f : KinematicControlFrame) (f' : ActuatorControlFrame) :
    (f.steer ≠ .none → (f.steerAfter w).steer = .angle) ∧
      (f'.wheel ≠ .none → (f'.steerAfter w δmax).wheel = .angle) := by
  constructor
  · intro h; simp [KinematicControlFrame.steerAfter, h, KinematicControlFrame.zero]
  · intro h; simp [ActuatorControlFrame.steerAfter, h, ActuatorControlFrame.zero]

end Driveline.TierChange
