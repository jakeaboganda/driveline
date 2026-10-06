import Driveline.TierChange
import Driveline.Schedule
import Driveline.Lifecycle
import Driveline.Merge
import Driveline.VehicleSpec

/-!
# Composition and splicing (spec §10.1, §10.2, §10.4)

Cardinality, group binds, the typing, trigger and timing rules of a splice, and
the stamp of a merged frame that the splice window re-forms.
-/

namespace Driveline.Splice

open VehicleSpec TierChange

/-! ## Cardinality and group binds (10:13-21) -/

inductive Card | oneToOne | oneToMany | manyToMany
  deriving DecidableEq, Repr

/-- Whether the output for actor `i` may depend on actor `j`'s inputs (10:17-19). -/
def mayDepend {ι : Type*} : Card → ι → ι → Prop
  | .oneToMany, _, _ => True
  | _, i, j => i = j

/-- A group step `F` (inputs of the `M` actors to outputs) obeys cardinality `k`. -/
def respects {M : ℕ} {α β : Type*} (k : Card) (F : (Fin M → α) → Fin M → β) : Prop :=
  ∀ i x y, (∀ j : Fin M, mayDepend k i j → x j = y j) → F x i = F y i

/-- P10-01 10:17-19 'OneToOne | One per actor ... | Actor i's inputs only.' /
'OneToMany | One per group ... | The inputs of every actor in the group.' /
'ManyToMany | One per group ... | Actor i's inputs only. The results must equal those of M
OneToOne instances.' -/
theorem card_dependency {M : ℕ} {α β : Type*} (F : (Fin M → α) → Fin M → β) :
    (respects .oneToOne F ↔ ∃ g : Fin M → α → β, ∀ x i, F x i = g i (x i)) ∧
      (respects .manyToMany F ↔ respects .oneToOne F) ∧ respects .oneToMany F := by
  refine ⟨⟨fun h => ⟨fun i a => F (fun _ => a) i, fun x i => h i _ _ ?_⟩, ?_⟩, Iff.rfl, ?_⟩
  · intro j hj
    simp only [mayDepend] at hj
    subst hj; rfl
  · rintro ⟨g, hg⟩ i x y hxy
    rw [hg, hg, hxy i rfl]
  · intro i x y hxy
    have : x = y := funext fun j => hxy j trivial
    rw [this]

/-- The argument of a `bind`: one actor or a list. -/
inductive BindArg | single (a : ℕ) | list (l : List ℕ)

/-- The actor list of a `bind`; `actor_ids` follows this order (10:21). -/
def bindList : BindArg → List ℕ | .single a => [a] | .list l => l

/-- 'The names in a bind list must be distinct actors' (10:21). -/
def bindOK (b : BindArg) : Prop := (bindList b).Nodup

/-- P10-03 10:21 'bind a -> chain means exactly bind [a] -> chain. The names in a bind list
must be distinct actors. ... The runtime orders actors by the order of the bind list, and
actor_ids in dl_batch_step_io_t follows that order.' -/
theorem bind_norm (a : ℕ) (l : List ℕ) :
    bindList (.single a) = bindList (.list [a]) ∧ bindOK (.single a) ∧
      (bindOK (.list l) ↔ l.Nodup) ∧ bindList (.list l) = l := by
  simp [bindList, bindOK]

/-! ## Splice typing (10:30) -/

/-- Conversion of a value at a port or as a `step` result (16:26-27): equal types; `T`,
`Lon<T>` or `Lat<T>` to `Override<T>`; `T` to `Lon<T>` or `Lat<T>`. -/
def converts (a b : FrameType) : Prop :=
  a = b ∨ (b = .override a.root ∧ ∀ r, a ≠ .override r) ∨
    (∃ r, a = .whole r ∧ (b = .lon r ∨ b = .lat r))

def isPartial : FrameType → Prop
  | .lon _ | .lat _ => True
  | _ => False

/-- 16:27 'A Chain<A, B> converts to Chain<A, B'> exactly when a value of type B converts to
B' at a port and B' is not a partial type, and this is the only chain conversion.' -/
def chainConverts (b b' : FrameType) : Prop := b = b' ∨ (converts b b' ∧ ¬ isPartial b')

/-- 10:30 'an output type equal to the target's or converting to it by the chain conversion
of §16.1'. -/
def spliceTypeOK (tgtOut repOut : FrameType) : Prop := chainConverts repOut tgtOut

/-- At a port a full `T` converts to `Lon<T>` (16:26), so the restriction of the chain
conversion to non-partial `B'` is what the next theorem needs. -/
theorem port_converts_whole_lon (r : Base) : converts (.whole r) (.lon r) :=
  Or.inr (Or.inr ⟨r, rfl, Or.inl rfl⟩)

/-- P10-16 10:30 'The replacement must have ... an output type equal to the target's or
converting to it by the chain conversion of §16.1, so a partial target needs a partial
replacement'. True, and stronger: the chain conversion of 16:27 never yields a partial type,
so a partial target needs a replacement of the same output type. -/
theorem partial_target_partial_replacement (tgt rep : FrameType)
    (h : spliceTypeOK tgt rep) (ht : isPartial tgt) : rep = tgt ∧ isPartial rep := by
  rcases h with h | ⟨-, hn⟩
  · exact ⟨h, h ▸ ht⟩
  · exact absurd ht hn

structure SpliceStmt (T : Type) where
  actor : ℕ
  target : T

/-- 10:30 'two splice statements on the same actor where one target contains the other'. -/
def conflicts {T : Type} (contains : T → T → Prop) (s u : SpliceStmt T) : Prop :=
  s.actor = u.actor ∧ (contains s.target u.target ∨ contains u.target s.target)

/-- 10:30 the compile-time error: a conflicting pair, except that 'Two splices of the same
target are allowed'. -/
def rejected {T : Type} (contains : T → T → Prop) (s u : SpliceStmt T) : Prop :=
  conflicts contains s u ∧ s.target ≠ u.target

/-- P10-17 10:30 'So are two splice statements on the same actor where one target contains
the other ... Two splices of the same target are allowed'. A same-target pair is never
rejected, and the exemption is needed: when containment is reflexive (a target's components
include its own), such a pair on one actor conflicts by containment. Every other conflicting
pair is rejected. -/
theorem same_target_allowed {T : Type} (contains : T → T → Prop) (s u : SpliceStmt T) :
    (s.target = u.target → ¬ rejected contains s u) ∧
      ((∀ x, contains x x) → s.actor = u.actor → s.target = u.target →
        conflicts contains s u) ∧
      (conflicts contains s u → s.target ≠ u.target → rejected contains s u) :=
  ⟨fun h ⟨_, hne⟩ => hne h, fun hr ha ht => ⟨ha, Or.inl (ht ▸ hr _)⟩, fun hc hne => ⟨hc, hne⟩⟩

/-! ## Trigger (10:31) -/

/-- An `on` statement fires on tick `k`: its condition holds there and on no earlier tick. -/
def firedAt (cond : ℕ → Bool) (k : ℕ) : Prop := cond k = true ∧ ∀ j < k, cond j = false

/-- P10-18 10:31 'Each on statement fires at most once, on the first tick where its condition
is true.' -/
theorem fires_once (cond : ℕ → Bool) (k k' : ℕ) (h : firedAt cond k) (h' : firedAt cond k') :
    k = k' := by
  rcases lt_trichotomy k k' with hk | hk | hk
  · have := h'.2 k hk
    rw [h.1] at this; cases this
  · exact hk
  · have := h.2 k' hk
    rw [h'.1] at this; cases this

/-- P10-18 10:31 'Statements that fire on the same tick run in source order.' -/
theorem fire_order (conds : List (ℕ × Bool)) :
    (Schedule.phase4 false conds).2 = (conds.filter (·.2)).map (·.1) ∧
      (Schedule.phase4 false conds).2.Sublist (conds.map (·.1)) := by
  refine ⟨rfl, ?_⟩
  exact List.Sublist.map _ List.filter_sublist

/-! ## Timing (10:32) -/

theorem mapM_none {σ : Type*} (solve : ℕ → Option σ) :
    ∀ (l : List ℕ) (i : ℕ), i ∈ l → solve i = none →
      l.mapM (fun i => (solve i).map (i, ·)) = none
  | [], _, h, _ => by simp at h
  | a :: l, i, h, hs => by
    rcases List.mem_cons.1 h with rfl | h
    · simp [List.mapM_cons, hs]
    · cases ha : solve a <;> simp [List.mapM_cons, ha, mapM_none solve l i h hs]

theorem mapM_some {σ : Type*} (solve : ℕ → Option σ) :
    ∀ (l : List ℕ), (∀ i ∈ l, (solve i).isSome) →
      ∃ us, l.mapM (fun i => (solve i).map (i, ·)) = some us ∧ us.map (·.1) = l
  | [], _ => ⟨[], rfl, rfl⟩
  | a :: l, h => by
    obtain ⟨u, hu⟩ := Option.isSome_iff_exists.1 (h a List.mem_cons_self)
    obtain ⟨us, hus, hm⟩ := mapM_some solve l (fun i hi => h i (List.mem_cons_of_mem _ hi))
    exact ⟨(a, u) :: us, by simp [List.mapM_cons, hu, hus], by simp [hm]⟩

/-- The window's committed state update: solve every update in ascending `actor_id` order,
and write them only if all succeed (10:32). -/
def windowUpdate {σ ς : Type*} (ids : List ℕ) (solve : ℕ → Option σ)
    (write : List (ℕ × σ) → ς → ς) (st : ς) : ς :=
  match (ids.mergeSort (fun a b => decide (a ≤ b))).mapM (fun i => (solve i).map (i, ·)) with
  | some us => write us st
  | none => st

/-- P10-19 10:32 'It solves every update in ascending actor_id order first and writes them
only if all succeed, so a failed solve leaves the committed state unchanged.' -/
theorem window_all_or_nothing {σ ς : Type*} (ids : List ℕ) (solve : ℕ → Option σ)
    (write : List (ℕ × σ) → ς → ς) (st : ς) :
    ((∃ i ∈ ids, solve i = none) → windowUpdate ids solve write st = st) ∧
      ((∀ i ∈ ids, (solve i).isSome) → ∃ us, windowUpdate ids solve write st = write us st ∧
        (us.map (·.1)).Perm ids ∧ (us.map (·.1)).Pairwise (· ≤ ·)) := by
  have hp := List.mergeSort_perm ids (fun a b => decide (a ≤ b))
  refine ⟨fun ⟨i, hi, hs⟩ => ?_, fun h => ?_⟩
  · unfold windowUpdate
    rw [mapM_none solve _ i (hp.mem_iff.2 hi) hs]
  · obtain ⟨us, hus, hm⟩ := mapM_some solve _ (fun i hi => h i (hp.mem_iff.1 hi))
    refine ⟨us, by unfold windowUpdate; rw [hus], hm ▸ hp, ?_⟩
    rw [hm]
    have := List.pairwise_mergeSort (le := fun a b : ℕ => decide (a ≤ b))
      (fun a b c hab hbc => by simp at *; omega) (fun a b => by simp; omega) ids
    exact this.imp (fun hab => by simpa using hab)

/-- 10:32 'only a change between 0 and 1 or 2 counts'. -/
def netChange (b a : Fin 3) : Bool := (b = 0) != (a = 0)

/-- P10-19 10:32 'A tier change is net for the window: it compares the actor's physics
required_tier before the first statement with its required_tier after the last, and only a
change between 0 and 1 or 2 counts, as §6.2.4 defines.' -/
theorem netChange_iff (b a : Fin 3) : netChange b a = true ↔ classify b a ≠ .none := by
  revert b a; decide

/-- The tier after the window: the tier after the last statement, or `b` with no statement. -/
def windowNet (b : Fin 3) (ts : List (Fin 3)) : Bool := netChange b (ts.getLastD b)

/-- P10-21 10:33 'A net tier change across the window, as defined in the Timing bullet, is a
promotion or demotion and triggers the re-trim of §6.2.4. A single splice statement does
not.' Only the tiers before the first and after the last statement count; 0 → 1 → 0 across
two statements is no change although each statement alone is one. -/
theorem net_only (b a : Fin 3) (mid : List (Fin 3)) :
    windowNet b (mid ++ [a]) = netChange b a ∧
      (windowNet b (mid ++ [a]) = true ↔ classify b a ≠ .none) ∧
      (classify 0 1 = .promo ∧ classify 1 0 = .demo ∧ windowNet 0 [1, 0] = false) := by
  have h1 : windowNet b (mid ++ [a]) = netChange b a := by simp [windowNet]
  exact ⟨h1, h1 ▸ netChange_iff b a, by decide, by decide, by decide⟩

/-- Window operations. `create s i` stands for `dl_instantiate`, `dl_set_parameters` and
`dl_configure_structure` on replacement instance `i` of statement `s` (in that order, by
`Lifecycle.splice_sequence`), `warm s i` for `dl_enter_warm_start` then `dl_exit_init_mode`,
`teardown s i` for `dl_terminate` then `dl_free_instance`. -/
inductive WinOp
  | update
  | capture (s : ℕ)
  | teardown (s i : ℕ)
  | create (s i : ℕ)
  | warm (s i : ℕ)
  | retrim
  deriving DecidableEq, Repr

/-- One splice statement `s` with outgoing instances `st.1` in teardown order and replacement
instances `st.2` in Phase 2 order. -/
def block (s : ℕ) (st : List ℕ × List ℕ) : List WinOp :=
  (.capture s :: st.1.map (.teardown s)) ++ (st.2.map (.create s) ++ st.2.map (.warm s))

def blocks : ℕ → List (List ℕ × List ℕ) → List WinOp
  | _, [] => []
  | s, st :: rest => block s st ++ blocks (s + 1) rest

/-- The splice window (10:32): the state update, each statement in source order, the
re-trim. -/
def windowOps (stmts : List (List ℕ × List ℕ)) : List WinOp :=
  .update :: blocks 0 stmts ++ [.retrim]

def Precedes (L : List WinOp) (x y : WinOp) : Prop := ∃ A B, L = A ++ B ∧ x ∈ A ∧ y ∈ B

theorem blocks_append : ∀ (n : ℕ) (l₁ l₂ : List (List ℕ × List ℕ)),
    blocks n (l₁ ++ l₂) = blocks n l₁ ++ blocks (n + l₁.length) l₂
  | n, [], l₂ => by simp [blocks]
  | n, a :: l₁, l₂ => by
    simp only [List.cons_append, blocks, blocks_append (n + 1) l₁ l₂, List.append_assoc,
      List.length_cons]
    congr 3; omega

theorem mem_blocks : ∀ (l : List (List ℕ × List ℕ)) (n s : ℕ) (st : List ℕ × List ℕ) (x : WinOp),
    l[s]? = some st → x ∈ block (n + s) st → x ∈ blocks n l
  | [], _, _, _, _, h, _ => by simp at h
  | a :: l, n, 0, st, x, h, hx => by
    simp at h; subst h; simp only [blocks, List.mem_append]; left; simpa using hx
  | a :: l, n, s + 1, st, x, h, hx => by
    simp only [List.getElem?_cons_succ] at h
    have := mem_blocks l (n + 1) s st x h (by rwa [show n + 1 + s = n + (s + 1) by omega])
    simp [blocks, this]

theorem precedes_mid {A M B : List WinOp} {x y : WinOp} (h : Precedes M x y) :
    Precedes (A ++ M ++ B) x y := by
  obtain ⟨P, Q, rfl, hx, hy⟩ := h
  exact ⟨A ++ P, Q ++ B, by simp, by simp [hx], by simp [hy]⟩

/-- Statement `s` of the window sits between a prefix and a suffix. -/
theorem windowOps_split (stmts : List (List ℕ × List ℕ)) (s : ℕ) (st : List ℕ × List ℕ)
    (h : stmts[s]? = some st) : ∃ A B, windowOps stmts = A ++ block s st ++ B := by
  have hs : s < stmts.length := (List.getElem?_eq_some_iff.1 h).1
  have hl : stmts = stmts.take s ++ st :: stmts.drop (s + 1) := by
    conv_lhs => rw [← List.take_append_drop s stmts]
    congr 1
    rw [List.drop_eq_getElem_cons hs, (List.getElem?_eq_some_iff.1 h).2]
  refine ⟨.update :: blocks 0 (stmts.take s), blocks (s + 1) (stmts.drop (s + 1)) ++ [.retrim], ?_⟩
  conv_lhs => rw [windowOps, hl, blocks_append]
  simp [blocks, List.length_take, Nat.min_eq_left hs.le]

/-- P10-20 10:32 'Before the first statement, the runtime finds every promotion and demotion
that the window causes and applies their committed state update ... It then completes each
splice statement, in source order, before it starts the next. For each one it captures the
latched frames of the outgoing target, calls dl_terminate and dl_free_instance on every
outgoing instance in teardown order ..., calls dl_instantiate, dl_set_parameters, and
dl_configure_structure on each replacement instance in Phase 2 order, finishing all three
before the next instance and all instances before any warm start, and calls
dl_enter_warm_start and then dl_exit_init_mode. After all statements, the runtime performs
one re-trim'. -/
theorem window_order (stmts : List (List ℕ × List ℕ)) :
    (windowOps stmts).head? = some .update ∧ (windowOps stmts).getLast? = some .retrim ∧
      (∀ s st, stmts[s]? = some st →
        (∀ i ∈ st.1, Precedes (windowOps stmts) (.capture s) (.teardown s i)) ∧
        (∀ i ∈ st.1, ∀ j ∈ st.2, Precedes (windowOps stmts) (.teardown s i) (.create s j)) ∧
        (∀ i ∈ st.2, ∀ j ∈ st.2, Precedes (windowOps stmts) (.create s i) (.warm s j))) ∧
      (∀ s s' st st' x y, s < s' → stmts[s]? = some st → stmts[s']? = some st' →
        x ∈ block s st → y ∈ block s' st' → Precedes (windowOps stmts) x y) := by
  refine ⟨rfl, ?_, fun s st h => ?_, ?_⟩
  · rw [windowOps, List.getLast?_append]
    simp
  · obtain ⟨A, B, hAB⟩ := windowOps_split stmts s st h
    rw [hAB]
    refine ⟨fun i hi => precedes_mid ?_, fun i hi j hj => precedes_mid ?_,
      fun i hi j hj => precedes_mid ?_⟩
    · exact ⟨[.capture s], st.1.map (.teardown s) ++ (st.2.map (.create s) ++ st.2.map (.warm s)),
        by simp [block], by simp, by simp [hi]⟩
    · exact ⟨.capture s :: st.1.map (.teardown s), st.2.map (.create s) ++ st.2.map (.warm s),
        rfl, by simp [hi], by simp [hj]⟩
    · exact ⟨.capture s :: st.1.map (.teardown s) ++ st.2.map (.create s),
        st.2.map (.warm s), by simp [block], by simp [hi], by simp [hj]⟩
  · intro s s' st st' x y hss h h' hx hy
    have hs : s < stmts.length := (List.getElem?_eq_some_iff.1 h).1
    have hl : stmts = stmts.take (s + 1) ++ stmts.drop (s + 1) := (List.take_append_drop _ _).symm
    have hlen : (stmts.take (s + 1)).length = s + 1 := by simp; omega
    refine ⟨.update :: blocks 0 (stmts.take (s + 1)),
      blocks (s + 1) (stmts.drop (s + 1)) ++ [.retrim], ?_, ?_, ?_⟩
    · conv_lhs => rw [windowOps, hl, blocks_append]
      simp [hlen]
    · refine List.mem_cons_of_mem _ (mem_blocks _ 0 s st x ?_ (by simpa using hx))
      rw [List.getElem?_take]; simp [h]
    · refine List.mem_append_left _ (mem_blocks _ (s + 1) (s' - (s + 1)) st' y ?_ ?_)
      · rw [List.getElem?_drop, show s + 1 + (s' - (s + 1)) = s' by omega, h']
      · rwa [show s + 1 + (s' - (s + 1)) = s' by omega]

/-- The window's re-trim set: the §6.2.4 set, less the instances created in the window. -/
def windowRetrim {ι : Type} (order : List ι) (st sv rc lo created : ι → Bool) : List ι :=
  (retrimSet order st sv rc lo).filter (fun x => !created x)

/-- P10-20 10:32 'Instances created in this window are not part of the re-trim set, because
their warm start already used the updated state.' -/
theorem window_retrim_excludes_created {ι : Type} (order : List ι) (st sv rc lo created : ι → Bool)
    (x : ι) (hx : x ∈ windowRetrim order st sv rc lo created) :
    created x = false ∧ x ∈ retrimSet order st sv rc lo := by
  simp only [windowRetrim, List.mem_filter, Bool.not_eq_true'] at hx
  exact ⟨hx.2, hx.1⟩

/-! ## Re-formed merged frame (10:25) -/

/-- P10-40 10:25 'When a splice creates a + or replaces a producer that feeds one, the runtime
re-forms its merged frame in the splice window from each branch's current output ... stamped
with the next tick's time.' The window after tick `k` stamps the frame with the predicted
time of `k`, which is tick `k + 1`. -/
theorem reformed_stamp (dt : ℕ+) (k : Schedule.Tick) (a : UInt64) (x y : KinematicControlFrame)
    (p q : IntentFrame) :
    (KinematicControlFrame.merge ⟨a, UInt64.ofNat (Schedule.predTime dt k)⟩ x y).header.timestampNs =
        UInt64.ofNat (Schedule.tickTime dt (k + 1)) ∧
      (IntentFrame.merge ⟨a, UInt64.ofNat (Schedule.predTime dt k)⟩ p q).header.timestampNs =
        UInt64.ofNat (Schedule.tickTime dt (k + 1)) := by
  simp [KinematicControlFrame.merge, IntentFrame.merge, Schedule.predTime_next]

end Driveline.Splice
