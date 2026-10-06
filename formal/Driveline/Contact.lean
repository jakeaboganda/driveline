import Mathlib.Tactic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
import Mathlib.Analysis.Convex.Radon
import Driveline.RunRecord
import Driveline.VehicleSpec

/-!
# Contact test (spec §11 Contact)

`docs/spec/11-execution.md:24-25`. One separating-axis test over any scalar
type, so ℝ and `Float` share it, the closed footprints over ℝ, and the
collision lines of a run derived from the test.
-/

namespace Driveline.Contact

/-- An actor's placed footprint and height data: position, `u = (c, s)`, the
body-frame box and `H_bbox` (11:24). -/
structure Body (α : Type) where
  x : α
  y : α
  z : α
  c : α
  s : α
  xlo : α
  xhi : α
  ylo : α
  yhi : α
  H : α

section Generic

variable {α : Type} [Add α] [Mul α] [Neg α] [LT α] [LE α] [Max α] [Min α]

/-- "u = (cos ψ, sin ψ)" (11:24). -/
def u (b : Body α) : α × α := (b.c, b.s)

/-- "n = (−sin ψ, cos ψ)" (11:24). -/
def n (b : Body α) : α × α := (-b.s, b.c)

/-- "A corner with body-frame coordinates (x, y) is at p + x u + y n ...
evaluated left to right per component" (11:24). -/
def corner (b : Body α) (ex ey : α) : α × α :=
  (b.x + ex * b.c + ey * -b.s, b.y + ex * b.s + ey * b.c)

/-- "q_X w_X + q_Y w_Y" (11:24). -/
def proj (w q : α × α) : α := q.1 * w.1 + q.2 * w.2

/-- The largest projection of the four corners on `w`. -/
def pmax (b : Body α) (w : α × α) : α :=
  max (max (proj w (corner b b.xlo b.ylo)) (proj w (corner b b.xhi b.ylo)))
      (max (proj w (corner b b.xhi b.yhi)) (proj w (corner b b.xlo b.yhi)))

/-- The smallest projection of the four corners on `w`. -/
def pmin (b : Body α) (w : α × α) : α :=
  min (min (proj w (corner b b.xlo b.ylo)) (proj w (corner b b.xhi b.ylo)))
      (min (proj w (corner b b.xhi b.yhi)) (proj w (corner b b.xlo b.yhi)))

/-- "the four vectors u and n of the two actors" (11:24). -/
def axes (a b : Body α) : List (α × α) := [u a, n a, u b, n b]

/-- "the largest projection of one rectangle is below the smallest projection
of the other" (11:24). -/
def Separated (a b : Body α) (w : α × α) : Prop := pmax a w < pmin b w ∨ pmax b w < pmin a w

/-- "The footprints overlap or touch unless, on some vector, ..." (11:24). -/
def FootprintContact (a b : Body α) : Prop := ∀ w ∈ axes a b, ¬ Separated a b w

/-- The closed intervals [z, z + H] intersect; the self conjuncts make an empty
interval (H < 0) never touch. -/
def HeightContact (a b : Body α) : Prop :=
  a.z ≤ a.z + a.H ∧ b.z ≤ b.z + b.H ∧ a.z ≤ b.z + b.H ∧ b.z ≤ a.z + a.H

/-- "The pair is in contact if their footprints overlap or touch and their
height intervals overlap or touch" (11:24). -/
def Contact (a b : Body α) : Prop := FootprintContact a b ∧ HeightContact a b

/-- P11-18. "Each corner of both rectangles is projected onto each of the four
vectors u and n of the two actors" (11-execution.md:24). The test does not
depend on argument order, for every scalar type, binary64 included: the proof
uses no arithmetic law. -/
theorem contact_comm (a b : Body α) : Contact a b ↔ Contact b a := by
  have hax : ∀ w, w ∈ axes a b ↔ w ∈ axes b a := by
    intro w; simp only [axes, List.mem_cons, List.not_mem_nil, or_false]; tauto
  have hsep : ∀ w, Separated a b w ↔ Separated b a w := fun w => Or.comm
  unfold Contact FootprintContact HeightContact
  simp only [hax, hsep]
  tauto

end Generic

/-- P11-18, the binary64 instance of `contact_comm` (11-execution.md:24). -/
theorem contact_comm_float (a b : Body Float) : Contact a b ↔ Contact b a := contact_comm a b

/-- P11-20. "A corner with body-frame coordinates (x, y) is at p + x u + y n
... evaluated left to right per component"; "projected ... as
q_X w_X + q_Y w_Y" (11-execution.md:24). In the binary64 model each `*` and `+`
is one operation. The association is fixed by the model, which evaluates the
terms as written. That no build contracts them into a fused multiply-add is a
property of the compiler and hardware, P11-30 (`OUT: external`); this theorem
does not cover it. -/
theorem corner_float_eval (b : Body Float) (ex ey : Float) :
    corner b ex ey = ((b.x + ex * b.c) + ey * (-b.s), (b.y + ex * b.s) + ey * b.c) ∧
    ∀ w q : Float × Float, proj w q = q.1 * w.1 + q.2 * w.2 :=
  ⟨rfl, fun _ _ => rfl⟩

/-! ## The real model -/

/-- A body-frame box. -/
structure Geom where
  xlo : ℝ
  xhi : ℝ
  ylo : ℝ
  yhi : ℝ
  H : ℝ

/-- "In the body frame, the bounding box spans x ∈ [−o_r, L + o_f],
y ∈ [−W_bbox/2, W_bbox/2], and z ∈ [0, H_bbox]" (03-vehicle-parameters.md:20). -/
noncomputable def Geom.ofTier0 (p : VehicleSpec.Tier0) : Geom :=
  ⟨(VehicleSpec.boxX p).1, (VehicleSpec.boxX p).2, (VehicleSpec.boxY p).1, (VehicleSpec.boxY p).2,
    (VehicleSpec.boxZ p).2⟩

/-- An object's box: "length = L + o_f + o_r" with "o_f = o_r = length/2" and
`L = 0` (03-vehicle-parameters.md:42), so it spans x ∈ [−length/2, length/2]. -/
theorem geom_ofTier0_object (o : VehicleSpec.OSpec) :
    (Geom.ofTier0 (VehicleSpec.objectTier0 o)).xlo = -o.length / 2 ∧
      (Geom.ofTier0 (VehicleSpec.objectTier0 o)).xhi = o.length / 2 := by
  have h := congrArg Prod.fst (VehicleSpec.object_origin_centred o).1
  have h' := congrArg Prod.snd (VehicleSpec.object_origin_centred o).1
  exact ⟨h, h'⟩

/-- An actor's state for the test: (`pos_x`, `pos_y`, `pos_z`), `yaw`, box. -/
structure Actor where
  x : ℝ
  y : ℝ
  z : ℝ
  ψ : ℝ
  g : Geom

/-- "placed at (pos_x, pos_y) and rotated by yaw" (11:24). -/
noncomputable def Actor.body (a : Actor) : Body ℝ :=
  ⟨a.x, a.y, a.z, Real.cos a.ψ, Real.sin a.ψ, a.g.xlo, a.g.xhi, a.g.ylo, a.g.yhi, a.g.H⟩

/-- The closed footprint. `uIcc` equals `Icc` under positive dimensions and
needs no added hypothesis. -/
def rect (b : Body ℝ) : Set (ℝ × ℝ) :=
  {q | ∃ ex ∈ Set.uIcc b.xlo b.xhi, ∃ ey ∈ Set.uIcc b.ylo b.yhi, q = corner b ex ey}

/-- One global rotation by `φ` and translation by `(tx, ty, tz)`. -/
noncomputable def Actor.move (φ tx ty tz : ℝ) (a : Actor) : Actor :=
  { a with x := tx + a.x * Real.cos φ - a.y * Real.sin φ,
           y := ty + a.x * Real.sin φ + a.y * Real.cos φ,
           z := a.z + tz, ψ := a.ψ + φ }

open Classical in
/-- The contact test on committed state `t` of the world `w t`, as the input of
`RunRecord.collisions`. -/
noncomputable def contactAt (w : ℕ → ℕ → Actor) (t : ℕ) (p : ℕ × ℕ) : Bool :=
  decide (Contact (w t p.1).body (w t p.2).body)

/-- An axis-aligned unit cube at (x, 0, z). -/
def sq (x z : ℝ) : Actor := ⟨x, 0, z, 0, ⟨0, 1, 0, 1, 1⟩⟩

/-! ### Height -/

/-- P11-16. "their height intervals overlap or touch"; "Its height interval is
[pos_z, pos_z + H_bbox]" (11-execution.md:24). -/
theorem heightContact_iff_Icc (a b : Actor) :
    HeightContact a.body b.body ↔
      (Set.Icc a.z (a.z + a.g.H) ∩ Set.Icc b.z (b.z + b.g.H)).Nonempty := by
  simp only [HeightContact, Actor.body]
  constructor
  · rintro ⟨h1, h2, h3, h4⟩
    exact ⟨max a.z b.z, ⟨le_max_left _ _, max_le h1 h4⟩, ⟨le_max_right _ _, max_le h3 h2⟩⟩
  · rintro ⟨q, ⟨h1, h2⟩, h3, h4⟩
    exact ⟨by linarith, by linarith, by linarith, by linarith⟩

/-- P11-16. "overlap or touch" (11-execution.md:24): the closed-interval form
`max lo ≤ min hi`. -/
theorem heightContact_iff_max_le_min (a b : Actor) :
    HeightContact a.body b.body ↔ max a.z b.z ≤ min (a.z + a.g.H) (b.z + b.g.H) := by
  simp only [HeightContact, Actor.body, max_le_iff, le_min_iff]
  tauto

/-! ### Footprint -/

private lemma affine_lo {f : ℝ → ℝ} {K B l h x lo : ℝ} (hf : ∀ x, f x = K + x * B)
    (hx : x ∈ Set.uIcc l h) (hl : lo ≤ f l) (hh : lo ≤ f h) : lo ≤ f x := by
  rw [hf] at hl hh ⊢
  rw [Set.mem_uIcc] at hx
  rcases hx with ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rcases le_total 0 B with hB | hB <;> nlinarith

private lemma affine_hi {f : ℝ → ℝ} {K B l h x hi : ℝ} (hf : ∀ x, f x = K + x * B)
    (hx : x ∈ Set.uIcc l h) (hl : f l ≤ hi) (hh : f h ≤ hi) : f x ≤ hi := by
  rw [hf] at hl hh ⊢
  rw [Set.mem_uIcc] at hx
  rcases hx with ⟨h1, h2⟩ | ⟨h1, h2⟩ <;> rcases le_total 0 B with hB | hB <;> nlinarith

/-- Every point of the closed footprint projects between the extreme corners. -/
lemma proj_corner_bounds (b : Body ℝ) (w : ℝ × ℝ) {ex ey : ℝ}
    (hx : ex ∈ Set.uIcc b.xlo b.xhi) (hy : ey ∈ Set.uIcc b.ylo b.yhi) :
    pmin b w ≤ proj w (corner b ex ey) ∧ proj w (corner b ex ey) ≤ pmax b w := by
  have fx : ∀ ey' x, proj w (corner b x ey') =
      (b.x * w.1 + b.y * w.2 + ey' * (-b.s * w.1 + b.c * w.2)) + x * (b.c * w.1 + b.s * w.2) := by
    intros; simp only [proj, corner]; ring
  have fy : ∀ ex' y, proj w (corner b ex' y) =
      (b.x * w.1 + b.y * w.2 + ex' * (b.c * w.1 + b.s * w.2)) + y * (-b.s * w.1 + b.c * w.2) := by
    intros; simp only [proj, corner]; ring
  constructor
  · have h1 : pmin b w ≤ proj w (corner b b.xlo b.ylo) :=
      min_le_of_left_le (min_le_left _ _)
    have h2 : pmin b w ≤ proj w (corner b b.xhi b.ylo) :=
      min_le_of_left_le (min_le_right _ _)
    have h3 : pmin b w ≤ proj w (corner b b.xhi b.yhi) :=
      min_le_of_right_le (min_le_left _ _)
    have h4 : pmin b w ≤ proj w (corner b b.xlo b.yhi) :=
      min_le_of_right_le (min_le_right _ _)
    have hl := affine_lo (f := fun y => proj w (corner b b.xlo y)) (fy b.xlo) hy h1 h4
    have hh := affine_lo (f := fun y => proj w (corner b b.xhi y)) (fy b.xhi) hy h2 h3
    exact affine_lo (f := fun x => proj w (corner b x ey)) (fx ey) hx hl hh
  · have h1 : proj w (corner b b.xlo b.ylo) ≤ pmax b w :=
      le_max_of_le_left (le_max_left _ _)
    have h2 : proj w (corner b b.xhi b.ylo) ≤ pmax b w :=
      le_max_of_le_left (le_max_right _ _)
    have h3 : proj w (corner b b.xhi b.yhi) ≤ pmax b w :=
      le_max_of_le_right (le_max_left _ _)
    have h4 : proj w (corner b b.xlo b.yhi) ≤ pmax b w :=
      le_max_of_le_right (le_max_right _ _)
    have hl := affine_hi (f := fun y => proj w (corner b b.xlo y)) (fy b.xlo) hy h1 h4
    have hh := affine_hi (f := fun y => proj w (corner b b.xhi y)) (fy b.xhi) hy h2 h3
    exact affine_hi (f := fun x => proj w (corner b x ey)) (fx ey) hx hl hh

lemma pmin_le_pmax (b : Body ℝ) (w : ℝ × ℝ) : pmin b w ≤ pmax b w := by
  have h := proj_corner_bounds b w Set.left_mem_uIcc Set.left_mem_uIcc
  exact h.1.trans h.2

/-- Every value between the extreme projections is the projection of a point of
the footprint (intermediate values on the connected box). -/
lemma exists_corner_proj (b : Body ℝ) (w : ℝ × ℝ) {v : ℝ} (h1 : pmin b w ≤ v)
    (h2 : v ≤ pmax b w) :
    ∃ ex ∈ Set.uIcc b.xlo b.xhi, ∃ ey ∈ Set.uIcc b.ylo b.yhi, proj w (corner b ex ey) = v := by
  set S := (fun p : ℝ × ℝ => proj w (corner b p.1 p.2)) ''
    (Set.uIcc b.xlo b.xhi ×ˢ Set.uIcc b.ylo b.yhi)
  have hS : IsPreconnected S := by
    refine (isPreconnected_uIcc.prod isPreconnected_uIcc).image _ ?_
    apply Continuous.continuousOn
    simp only [proj, corner]
    fun_prop
  have mem : ∀ {x y}, x ∈ Set.uIcc b.xlo b.xhi → y ∈ Set.uIcc b.ylo b.yhi →
      proj w (corner b x y) ∈ S := fun hx hy => ⟨(_, _), ⟨hx, hy⟩, rfl⟩
  have hmin : ∀ {x y}, x ∈ S → y ∈ S → min x y ∈ S := by
    intro x y hx hy; rcases min_choice x y with h | h <;> rw [h] <;> assumption
  have hmax : ∀ {x y}, x ∈ S → y ∈ S → max x y ∈ S := by
    intro x y hx hy; rcases max_choice x y with h | h <;> rw [h] <;> assumption
  have l := @Set.left_mem_uIcc _ _ b.xlo b.xhi
  have r := @Set.right_mem_uIcc _ _ b.xlo b.xhi
  have l' := @Set.left_mem_uIcc _ _ b.ylo b.yhi
  have r' := @Set.right_mem_uIcc _ _ b.ylo b.yhi
  have hlo : pmin b w ∈ S :=
    hmin (hmin (mem l l') (mem r l')) (hmin (mem r r') (mem l r'))
  have hhi : pmax b w ∈ S :=
    hmax (hmax (mem l l') (mem r l')) (hmax (mem r r') (mem l r'))
  obtain ⟨⟨ex, ey⟩, ⟨hx, hy⟩, he⟩ := hS.Icc_subset hlo hhi ⟨h1, h2⟩
  exact ⟨ex, hx, ey, hy, he⟩

/-- The closed slab of `b` across the vector `w`. -/
def strip (b : Body ℝ) (w : ℝ × ℝ) : Set (ℝ × ℝ) :=
  {q | pmin b w ≤ proj w q ∧ proj w q ≤ pmax b w}

lemma convex_strip (b : Body ℝ) (w : ℝ × ℝ) : Convex ℝ (strip b w) := by
  intro x hx y hy p r hp hr hpr
  simp only [strip, proj, Set.mem_ofPred_eq, Prod.fst_add, Prod.snd_add, Prod.smul_fst,
    Prod.smul_snd, smul_eq_mul] at hx hy ⊢
  have e : (p * x.1 + r * y.1) * w.1 + (p * x.2 + r * y.2) * w.2 =
      p * (x.1 * w.1 + x.2 * w.2) + r * (y.1 * w.1 + y.2 * w.2) := by ring
  rw [e]
  have hm : pmin b w = p * pmin b w + r * pmin b w := by rw [← add_mul, hpr, one_mul]
  have hM : pmax b w = p * pmax b w + r * pmax b w := by rw [← add_mul, hpr, one_mul]
  have a1 := mul_le_mul_of_nonneg_left hx.1 hp
  have a2 := mul_le_mul_of_nonneg_left hx.2 hp
  have a3 := mul_le_mul_of_nonneg_left hy.1 hr
  have a4 := mul_le_mul_of_nonneg_left hy.2 hr
  constructor <;> linarith

private lemma proj_u_corner (b : Body ℝ) (hb : b.c ^ 2 + b.s ^ 2 = 1) (ex ey : ℝ) :
    proj (u b) (corner b ex ey) = (b.x * b.c + b.y * b.s) + ex := by
  simp only [proj, corner, u]; linear_combination ex * hb

private lemma proj_n_corner (b : Body ℝ) (hb : b.c ^ 2 + b.s ^ 2 = 1) (ex ey : ℝ) :
    proj (n b) (corner b ex ey) = (b.x * -b.s + b.y * b.c) + ey := by
  simp only [proj, corner, n]; linear_combination ey * hb

private lemma mem_uIcc_of (P l h v : ℝ) (h1 : min (P + l) (P + h) ≤ v)
    (h2 : v ≤ max (P + l) (P + h)) : v - P ∈ Set.uIcc l h := by
  rw [min_add_add_left] at h1
  rw [max_add_add_left] at h2
  rw [Set.mem_uIcc]
  rcases le_total l h with hlh | hlh
  · rw [min_eq_left hlh] at h1
    rw [max_eq_right hlh] at h2
    exact Or.inl ⟨by linarith, by linarith⟩
  · rw [min_eq_right hlh] at h1
    rw [max_eq_left hlh] at h2
    exact Or.inr ⟨by linarith, by linarith⟩

/-- With `c² + s² = 1` the footprint is the intersection of its two slabs. -/
lemma mem_rect_iff (b : Body ℝ) (hb : b.c ^ 2 + b.s ^ 2 = 1) (q : ℝ × ℝ) :
    q ∈ rect b ↔ q ∈ strip b (u b) ∧ q ∈ strip b (n b) := by
  constructor
  · rintro ⟨ex, hx, ey, hy, rfl⟩
    exact ⟨proj_corner_bounds b _ hx hy, proj_corner_bounds b _ hx hy⟩
  · rintro ⟨hu, hn⟩
    simp only [strip, pmin, pmax, proj_u_corner b hb, proj_n_corner b hb, Set.mem_ofPred_eq,
      min_self, max_self] at hu hn
    rw [min_comm (_ + b.xhi), max_comm (_ + b.xhi), min_self, max_self] at hu
    refine ⟨_, mem_uIcc_of _ _ _ _ hu.1 hu.2, _, mem_uIcc_of _ _ _ _ hn.1 hn.2, ?_⟩
    obtain ⟨q1, q2⟩ := q
    simp only [corner, proj, u, n]
    ext
    · linear_combination (-(q1) + b.x) * hb
    · linear_combination (-(q2) + b.y) * hb

lemma rect_inter_strip (a b : Body ℝ) (w : ℝ × ℝ) (h : ¬ Separated a b w) :
    (rect a ∩ strip b w).Nonempty := by
  simp only [Separated, not_or, not_lt] at h
  obtain ⟨ex, hx, ey, hy, he⟩ := exists_corner_proj a w (v := max (pmin a w) (pmin b w))
    (le_max_left _ _) (max_le (pmin_le_pmax a w) h.1)
  refine ⟨corner a ex ey, ⟨ex, hx, ey, hy, rfl⟩, ?_, ?_⟩ <;> rw [he]
  · exact le_max_right _ _
  · exact max_le h.2 (pmin_le_pmax b w)

lemma corner_mem_rect (b : Body ℝ) {ex ey : ℝ} (hx : ex ∈ Set.uIcc b.xlo b.xhi)
    (hy : ey ∈ Set.uIcc b.ylo b.yhi) : corner b ex ey ∈ rect b := ⟨ex, hx, ey, hy, rfl⟩

/-- The separating-axis theorem for two closed rectangles with orthonormal
frames: no separating vector among the four edge normals iff the rectangles
meet. (→) is Helly's theorem in the plane over the four slabs. -/
theorem footprintContact_iff_inter_body (a b : Body ℝ) (ha : a.c ^ 2 + a.s ^ 2 = 1)
    (hb : b.c ^ 2 + b.s ^ 2 = 1) :
    FootprintContact a b ↔ (rect a ∩ rect b).Nonempty := by
  constructor
  · intro h
    have hs : ∀ w ∈ axes a b, ¬ Separated b a w := fun w hw hs => h w hw (Or.comm.1 hs)
    let F : Fin 4 → Set (ℝ × ℝ) := ![strip a (u a), strip a (n a), strip b (u b), strip b (n b)]
    -- Every three slabs meet: two of one rectangle make the rectangle.
    have three : ∀ j : Fin 4, ∃ q, ∀ i, i ≠ j → q ∈ F i := by
      intro j
      fin_cases j
      · obtain ⟨q, hq, hq'⟩ := rect_inter_strip b a (n a) (hs _ (by simp [axes]))
        rw [mem_rect_iff b hb] at hq
        refine ⟨q, fun i hi => ?_⟩
        fin_cases i <;> simp_all [F]
      · obtain ⟨q, hq, hq'⟩ := rect_inter_strip b a (u a) (hs _ (by simp [axes]))
        rw [mem_rect_iff b hb] at hq
        refine ⟨q, fun i hi => ?_⟩
        fin_cases i <;> simp_all [F]
      · obtain ⟨q, hq, hq'⟩ := rect_inter_strip a b (n b) (h _ (by simp [axes]))
        rw [mem_rect_iff a ha] at hq
        refine ⟨q, fun i hi => ?_⟩
        fin_cases i <;> simp_all [F]
      · obtain ⟨q, hq, hq'⟩ := rect_inter_strip a b (u b) (h _ (by simp [axes]))
        rw [mem_rect_iff a ha] at hq
        refine ⟨q, fun i hi => ?_⟩
        fin_cases i <;> simp_all [F]
    have hall : (⋂ i ∈ (Finset.univ : Finset (Fin 4)), F i).Nonempty := by
      apply Convex.helly_theorem (𝕜 := ℝ)
      · simp
      · intro i _
        fin_cases i <;> exact convex_strip _ _
      · intro I _ hI
        have hne : I ≠ Finset.univ := by
          rintro rfl; simp at hI
        obtain ⟨j, hj⟩ : ∃ j, j ∉ I := by
          by_contra hc
          exact hne (Finset.eq_univ_iff_forall.2 fun j => by_contra fun hj => hc ⟨j, hj⟩)
        obtain ⟨q, hq⟩ := three j
        exact ⟨q, Set.mem_iInter₂.2 fun i hi => hq i (fun e => hj (e ▸ hi))⟩
    obtain ⟨q, hq⟩ := hall
    simp only [Set.mem_iInter₂] at hq
    refine ⟨q, (mem_rect_iff a ha q).2 ⟨?_, ?_⟩, (mem_rect_iff b hb q).2 ⟨?_, ?_⟩⟩
    · exact hq 0 (Finset.mem_univ _)
    · exact hq 1 (Finset.mem_univ _)
    · exact hq 2 (Finset.mem_univ _)
    · exact hq 3 (Finset.mem_univ _)
  · rintro ⟨q, ⟨ex, hx, ey, hy, rfl⟩, ⟨ex', hx', ey', hy', he⟩⟩ w _ hsep
    have ba := proj_corner_bounds a w hx hy
    have bb := proj_corner_bounds b w hx' hy'
    rw [← he] at bb
    rcases hsep with h | h <;> linarith [ba.1, ba.2, bb.1, bb.2]

lemma body_norm (a : Actor) : a.body.c ^ 2 + a.body.s ^ 2 = 1 := Real.cos_sq_add_sin_sq a.ψ

/-- P11-17. "The pair is in contact if their footprints overlap or touch ...
Each corner of both rectangles is projected onto each of the four vectors u and
n of the two actors ... The footprints overlap or touch unless, on some vector,
the largest projection of one rectangle is below the smallest projection of the
other" (11-execution.md:24). The test on u_a, n_a, u_b, n_b decides
closed-rectangle intersection. -/
theorem footprintContact_iff_inter (a b : Actor) :
    FootprintContact a.body b.body ↔ (rect a.body ∩ rect b.body).Nonempty :=
  footprintContact_iff_inter_body _ _ (body_norm a) (body_norm b)

private lemma sq_body_c (x z : ℝ) : (sq x z).body.c = 1 := by simp [sq, Actor.body]
private lemma sq_body_s (x z : ℝ) : (sq x z).body.s = 0 := by simp [sq, Actor.body]

/-- P11-17. "overlap or touch" (11-execution.md:24): a shared edge and a shared
height endpoint count. -/
theorem touching_counts : Contact (sq 0 0).body (sq 1 1).body := by
  refine ⟨(footprintContact_iff_inter _ _).2 ⟨(1, 0), ⟨1, ?_, 0, ?_, ?_⟩, ⟨0, ?_, 0, ?_, ?_⟩⟩, ?_⟩
  all_goals norm_num [corner, sq, Actor.body, HeightContact]

/-- P11-17. "below" (11-execution.md:24): a positive gap separates. -/
theorem gap_separates : ¬ FootprintContact (sq 0 0).body (sq 2 0).body := by
  rw [footprintContact_iff_inter]
  rintro ⟨q, ⟨ex, hx, ey, _, rfl⟩, ⟨ex', hx', ey', _, he⟩⟩
  simp only [corner, sq_body_c, sq_body_s, Prod.mk.injEq] at he
  simp only [sq, Actor.body, Set.uIcc_of_le zero_le_one, Set.mem_Icc] at hx hx' he
  linarith [he.1]

/-! ### Rotation and translation -/

/-- The global motion on the plane. -/
noncomputable def T (φ tx ty : ℝ) (q : ℝ × ℝ) : ℝ × ℝ :=
  (tx + q.1 * Real.cos φ - q.2 * Real.sin φ, ty + q.1 * Real.sin φ + q.2 * Real.cos φ)

private lemma T_inj (φ tx ty : ℝ) {q q' : ℝ × ℝ} (h : T φ tx ty q = T φ tx ty q') : q = q' := by
  obtain ⟨q1, q2⟩ := q
  obtain ⟨r1, r2⟩ := q'
  simp only [T, Prod.mk.injEq] at h
  have hn := Real.cos_sq_add_sin_sq φ
  obtain ⟨h1, h2⟩ := h
  ext
  · linear_combination Real.cos φ * h1 + Real.sin φ * h2 - (q1 - r1) * hn
  · linear_combination -Real.sin φ * h1 + Real.cos φ * h2 - (q2 - r2) * hn

private lemma corner_move (φ tx ty tz : ℝ) (a : Actor) (ex ey : ℝ) :
    corner (a.move φ tx ty tz).body ex ey = T φ tx ty (corner a.body ex ey) := by
  simp only [corner, Actor.move, Actor.body, T, Real.cos_add, Real.sin_add]
  ext <;> ring

private lemma inter_move (φ tx ty tz : ℝ) (a b : Actor) :
    (rect (a.move φ tx ty tz).body ∩ rect (b.move φ tx ty tz).body).Nonempty ↔
      (rect a.body ∩ rect b.body).Nonempty := by
  constructor
  · rintro ⟨q, ⟨ex, hx, ey, hy, rfl⟩, ⟨ex', hx', ey', hy', he⟩⟩
    rw [corner_move, corner_move] at he
    exact ⟨_, ⟨ex, hx, ey, hy, rfl⟩, ⟨ex', hx', ey', hy', T_inj φ tx ty he⟩⟩
  · rintro ⟨q, ⟨ex, hx, ey, hy, rfl⟩, ⟨ex', hx', ey', hy', he⟩⟩
    refine ⟨T φ tx ty (corner a.body ex ey), ⟨ex, hx, ey, hy, (corner_move ..).symm⟩,
      ⟨ex', hx', ey', hy', ?_⟩⟩
    rw [corner_move, he]

/-- P11-19. "placed at (pos_x, pos_y) and rotated by yaw" (11-execution.md:24):
over ℝ, contact is invariant under one global rotation by φ and translation.
The binary64 clause is OUT. -/
theorem contact_move (φ tx ty tz : ℝ) (a b : Actor) :
    Contact (a.move φ tx ty tz).body (b.move φ tx ty tz).body ↔ Contact a.body b.body := by
  unfold Contact
  rw [footprintContact_iff_inter, footprintContact_iff_inter, inter_move]
  apply and_congr Iff.rfl
  simp only [HeightContact, Actor.move, Actor.body]
  constructor <;> rintro ⟨h1, h2, h3, h4⟩ <;>
    exact ⟨by linarith, by linarith, by linarith, by linarith⟩

/-! ## Collision lines from the test -/

/-- P11-15. "The runtime tests every pair of actors a < b by actor_id, except a
pair of two static actors, in ascending order of (a, b)" (11-execution.md:24).
The pairs of `RunRecord.pairList` are exactly these, in strictly ascending
lexicographic order, each once. -/
theorem pairList_spec (ids : Finset ℕ) (static : ℕ → Bool) :
    (∀ p, p ∈ RunRecord.pairList ids static ↔
      p.1 ∈ ids ∧ p.2 ∈ ids ∧ p.1 < p.2 ∧ ¬ (static p.1 = true ∧ static p.2 = true)) ∧
    (RunRecord.pairList ids static).Pairwise RunRecord.lexLt ∧
    (RunRecord.pairList ids static).Nodup :=
  ⟨fun _ => RunRecord.mem_pairList, RunRecord.pairList_sorted ids static,
    RunRecord.pairList_nodup ids static⟩

/-- P11-22. "and also on the spawn state at the end of cold init, where the
committed state has tick 0" (11-execution.md:24). A pair of the test in contact
on the spawn state gets a line with tick 0 in every scan that covers it, that
is of the committed states 0, ..., n. -/
theorem contact_tick0 (ids : Finset ℕ) (static : ℕ → Bool) (w : ℕ → ℕ → Actor) (n : ℕ)
    {p : ℕ × ℕ} (hp : p ∈ RunRecord.pairList ids static)
    (h : Contact (w 0 p.1).body (w 0 p.2).body) :
    (0, p) ∈ RunRecord.collisions (contactAt w) (RunRecord.pairList ids static) (n + 1) :=
  (RunRecord.mem_collisions _ _ _ _ _).2
    ⟨Nat.succ_pos n, hp, by simpa [contactAt] using h, fun _ h => absurd h (Nat.not_lt_zero _)⟩

/-- P11-40. "The runtime tests every pair of actors a < b by actor_id, except a
pair of two static actors ... On the first tick that a pair is in contact, and
on no later tick, the runtime writes a `collision` line" (11-execution.md:24).
The collision lines over the committed states 0, ..., n-1 come from the contact
test applied to `pairList`. -/
theorem mem_collisions_contact (ids : Finset ℕ) (static : ℕ → Bool) (w : ℕ → ℕ → Actor)
    (n t a b : ℕ) :
    (t, (a, b)) ∈ RunRecord.collisions (contactAt w) (RunRecord.pairList ids static) n ↔
      a ∈ ids ∧ b ∈ ids ∧ a < b ∧ ¬ (static a = true ∧ static b = true) ∧ t < n ∧
      Contact (w t a).body (w t b).body ∧ ∀ t' < t, ¬ Contact (w t' a).body (w t' b).body := by
  rw [RunRecord.mem_collisions, RunRecord.mem_pairList]
  simp only [contactAt, decide_eq_true_eq, decide_eq_false_iff_not]
  tauto

/-- P11-40. "except a pair of two static actors" (11-execution.md:24): two
static actors never get a line, even in contact. -/
theorem static_pair_no_line (ids : Finset ℕ) (static : ℕ → Bool) (w : ℕ → ℕ → Actor)
    (n t a b : ℕ) (ha : static a = true) (hb : static b = true) :
    (t, (a, b)) ∉ RunRecord.collisions (contactAt w) (RunRecord.pairList ids static) n := by
  rw [mem_collisions_contact]
  exact fun h => h.2.2.2.1 ⟨ha, hb⟩

/-- P11-40. The exception matters (11-execution.md:24): two static actors that
touch on the spawn state have no line. -/
theorem static_exception_witness :
    let w : ℕ → ℕ → Actor := fun _ i => if i = 0 then sq 0 0 else sq 1 1
    Contact (w 0 0).body (w 0 1).body ∧
    (0, (0, 1)) ∉ RunRecord.collisions (contactAt w) (RunRecord.pairList {0, 1} (fun _ => true)) 1 :=
  ⟨by simpa using touching_counts, static_pair_no_line _ _ _ _ _ _ _ rfl rfl⟩

/-- The pairs newly in contact on committed state `t`: the collision lines of
that state. -/
def pairsAt (contact : ℕ → ℕ × ℕ → Bool) (ps : List (ℕ × ℕ)) (t : ℕ) : List (ℕ × ℕ) :=
  RunRecord.newPairs contact ps t (RunRecord.scan contact ps t).2

/-- The number of committed states that the runtime tests for contact. The
spawn state is committed state 0, and tick k commits state k + 1 in Phase 4
(11:20, 11:24). A failed cold init tests none. A run that fails in tick k with
its error before Phase 4's contact test (`Run.StopsAtError` with no report after
the test, 14:31) "finishes no further phase", so it does not test state k + 1. -/
def committed {P : Type} (r : RunRecord.Run P) : ℕ :=
  match r.ending with
  | .failed .coldInit _ => 0
  | .failed (.exec _) _ =>
    if r.ticks.getLast?.any (·.late.isEmpty) then r.ticks.length else r.ticks.length + 1
  | _ => r.ticks.length + 1

theorem committed_le {P : Type} (r : RunRecord.Run P) : committed r ≤ r.ticks.length + 1 := by
  unfold committed
  split
  · omega
  · split <;> omega
  · omega

/-- A run whose collision lines are those of the contact test `contact` on the
pairs `ps`: the spawn state is committed state 0, tick k commits state k + 1,
and a state that the run does not test has no line (11:24, 18:22). -/
def RunPairsFromContact {P : Type} (contact : ℕ → ℕ × ℕ → Bool) (ps : List (ℕ × ℕ))
    (r : RunRecord.Run P) : Prop :=
  r.spawnPairs = (if 0 < committed r then pairsAt contact ps 0 else []) ∧
    ∀ k (t : RunRecord.TickRun P), r.ticks[k]? = some t →
      t.pairs = if k + 1 < committed r then pairsAt contact ps (k + 1) else []

/-- The `(tick, pair)` of a collision line. -/
def colLine {P : Type} (e : RunRecord.Event P) : Option (ℕ × (ℕ × ℕ)) :=
  match e.kind with
  | .collision a b => some (e.tick, (a, b))
  | .report _ => none

private lemma collisions_eq (contact : ℕ → ℕ × ℕ → Bool) (ps : List (ℕ × ℕ)) :
    ∀ n, RunRecord.collisions contact ps n =
      (List.range n).flatMap fun t => (pairsAt contact ps t).map (t, ·)
  | 0 => rfl
  | n + 1 => by
    rw [List.range_succ, List.flatMap_append, ← collisions_eq contact ps n]
    simp [RunRecord.collisions, RunRecord.scan, pairsAt]

private lemma ticksEv_lines {P : Type} (f : ℕ → List (ℕ × ℕ)) :
    ∀ (ts : List (RunRecord.TickRun P)) (k : ℕ),
      (∀ i t, ts[i]? = some t → t.pairs = f (k + i + 1)) →
      (RunRecord.ticksEv k ts).filterMap colLine =
        (List.range' (k + 1) ts.length).flatMap fun t => (f t).map (t, ·)
  | [], _, _ => rfl
  | t :: ts, k, h => by
    have h0 := h 0 t rfl
    have ih := ticksEv_lines f ts (k + 1) fun i t' ht' => by
      rw [h (i + 1) t' ht']; congr 1; omega
    simp only [RunRecord.ticksEv, List.filterMap_append, ih, List.length_cons,
      List.range'_succ, List.flatMap_cons, RunRecord.TickRun.events, List.filterMap_map]
    simp [Function.comp_def, colLine, h0]

private lemma flatMap_trunc (f : ℕ → List (ℕ × ℕ)) (n : ℕ) :
    ∀ m, n ≤ m → ((List.range m).flatMap fun t => (if t < n then f t else []).map (t, ·)) =
      (List.range n).flatMap fun t => (f t).map (t, ·)
  | 0, h => by simp [Nat.le_zero.1 h]
  | m + 1, h => by
    rcases Nat.lt_or_ge m n with hm | hm
    · obtain rfl : n = m + 1 := by omega
      apply List.flatMap_congr
      intro t ht
      simp [List.mem_range.1 ht]
    · rw [List.range_succ, List.flatMap_append, flatMap_trunc f n m hm]
      simp [Nat.not_lt.2 hm]

/-- P11-40. "On the first tick that a pair is in contact, and on no later tick,
the runtime writes a `collision` line to the run record" (11-execution.md:24):
the collision lines of a run whose `Run.spawnPairs` and `TickRun.pairs` come from
the contact test are, by tick, the lines of `RunRecord.collisions` over the
committed states that it tests, 0, ..., `committed r` − 1. This covers a run
that fails before Phase 4 of its last tick, whose last state is not tested. -/
theorem run_collision_lines {P : Type} (contact : ℕ → ℕ × ℕ → Bool) (ps : List (ℕ × ℕ))
    (r : RunRecord.Run P) (h : RunPairsFromContact contact ps r) :
    r.pre.filterMap colLine = RunRecord.collisions contact ps (committed r) := by
  set n := committed r
  set g : ℕ → List (ℕ × ℕ) := fun t => if t < n then pairsAt contact ps t else []
  rw [collisions_eq, ← flatMap_trunc (pairsAt contact ps) n _ (committed_le r),
    List.range_eq_range', List.range'_succ, List.flatMap_cons]
  have ht := ticksEv_lines g r.ticks 0 fun i t hi => by
    rw [h.2 i t hi, Nat.zero_add]
  simp only [RunRecord.Run.pre, List.filterMap_append, List.filterMap_map, ht, h.1]
  simp [Function.comp_def, colLine, g, n]

/-- P11-23. "At a closing speed of 60 m/s and a 500 Hz base clock, the
displacement per tick is 0.12 m." (11-execution.md:25) -/
theorem displacement_per_tick : (60 : ℚ) / 500 = 0.12 := by norm_num

end Driveline.Contact
