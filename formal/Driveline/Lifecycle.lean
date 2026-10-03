/-!
# Component lifecycle (spec §6.1)

A model of the **Allowed Calls** table, `docs/spec/06-lifecycle.md:53-63`, and
proofs of the claims that §6, §10.4, and §14.2 make about it.
-/

namespace Driveline.Lifecycle

inductive State where
  | uninstantiated
  | instantiated
  | structuralConfig
  | coldInitMode
  | warmStartMode
  | stepMode
  | terminated
  deriving DecidableEq, Repr

inductive Call where
  | instantiate
  | setParameters
  | configureStructure
  | enterColdInit
  | enterWarmStart
  | exitInitMode
  | doStep
  | terminate
  | freeInstance
  deriving DecidableEq, Repr

/-- Simulation time of a call in nanoseconds. Only the two enter calls read it:
it is the `sim_time_ns` of their init contexts. -/
abbrev Time := Nat

/-- The Allowed Calls table. `none` means the call is not allowed: it returns
`DL_STATUS_ERR_STATE` and leaves the state unchanged (`06-lifecycle.md:51`). -/
def next : State → Call → Time → Option State
  | .uninstantiated,   .instantiate,        _     => some .instantiated
  | .instantiated,     .setParameters,      _     => some .instantiated
  | .structuralConfig, .setParameters,      _     => some .structuralConfig
  | .instantiated,     .configureStructure, _     => some .structuralConfig
  | .structuralConfig, .enterColdInit,      0     => some .coldInitMode
  | .structuralConfig, .enterWarmStart,     _ + 1 => some .warmStartMode
  | .stepMode,         .enterWarmStart,     _     => some .warmStartMode
  | .coldInitMode,     .exitInitMode,       _     => some .stepMode
  | .warmStartMode,    .exitInitMode,       _     => some .stepMode
  | .stepMode,         .doStep,             _     => some .stepMode
  | .instantiated,     .terminate,          _
  | .structuralConfig, .terminate,          _
  | .coldInitMode,     .terminate,          _
  | .warmStartMode,    .terminate,          _
  | .stepMode,         .terminate,          _     => some .terminated
  | .uninstantiated,   .freeInstance,       _     => none
  | _,                 .freeInstance,       _     => some .uninstantiated
  | _,                 _,                   _     => none

/-- Status of a call as the instance reports it. `componentError` stands for
any error code a component returns from an allowed call. -/
inductive Status where
  | ok
  | errState
  | componentError
  deriving DecidableEq, Repr

/-- One call. `fails` says whether the component returns an error from an
allowed call. "A call that returns an error also leaves the state unchanged"
(`06-lifecycle.md:51`). -/
def apply (s : State) (c : Call) (t : Time) (fails : Bool) : State × Status :=
  match next s c t with
  | none => (s, .errState)
  | some s' => if fails then (s, .componentError) else (s', .ok)

/-- Runs calls that all succeed. `none` if any call is not allowed. -/
def run : State → List (Call × Time) → Option State
  | s, [] => some s
  | s, (c, t) :: cs =>
    match next s c t with
    | some s' => run s' cs
    | none => none

/-! ## The diagram agrees with the table -/

/-- Time labels on diagram edges. -/
inductive Guard where
  | any
  | zero
  | positive
  deriving DecidableEq, Repr

def Guard.holds : Guard → Time → Bool
  | .any, _ => true
  | .zero, t => t == 0
  | .positive, t => t > 0

/-- Every edge drawn in the diagram, `06-lifecycle.md:16-49`. -/
def diagram : List (State × Call × State × Guard) :=
  [ (.uninstantiated,   .instantiate,        .instantiated,     .any)
  , (.instantiated,     .setParameters,      .instantiated,     .any)
  , (.instantiated,     .configureStructure, .structuralConfig, .any)
  , (.structuralConfig, .setParameters,      .structuralConfig, .any)
  , (.structuralConfig, .enterColdInit,      .coldInitMode,     .zero)
  , (.structuralConfig, .enterWarmStart,     .warmStartMode,    .positive)
  , (.coldInitMode,     .exitInitMode,       .stepMode,         .any)
  , (.warmStartMode,    .exitInitMode,       .stepMode,         .any)
  , (.stepMode,         .enterWarmStart,     .warmStartMode,    .any)
  , (.stepMode,         .doStep,             .stepMode,         .any)
  , (.stepMode,         .terminate,          .terminated,       .any)
  , (.terminated,       .freeInstance,       .uninstantiated,   .any) ]

def drawn (s : State) (c : Call) (t : Time) (s' : State) : Bool :=
  diagram.any fun (a, b, d, g) => a == s && b == c && d == s' && g.holds t

/-- Every drawn edge is allowed by the table. -/
theorem diagram_sound :
    ∀ e ∈ diagram, ∀ t, e.2.2.2.holds t = true → next e.1 e.2.1 t = some e.2.2.1 := by
  simp only [diagram, List.forall_mem_cons, List.not_mem_nil, false_imp_iff,
    implies_true, and_true]
  and_intros <;> intro t ht <;> cases t <;> simp_all [next, Guard.holds]

/-- The table has edges that the diagram omits, and every one of them is a
`dl_terminate` or `dl_free_instance` edge. -/
theorem undrawn_edges (s : State) (c : Call) (t : Time) (s' : State)
    (h : next s c t = some s') (hd : drawn s c t s' = false) :
    c = .terminate ∨ c = .freeInstance := by
  cases s <;> cases c <;> cases t <;> simp_all [drawn, diagram, Guard.holds, next]

/-- The diagram omits `dl_terminate` edges as well as `dl_free_instance` edges
(`06-lifecycle.md:51`): this one is in the table and not in the diagram. -/
theorem undrawn_terminate_edge :
    next .instantiated .terminate 0 = some .terminated ∧
    drawn .instantiated .terminate 0 .terminated = false := by
  decide

/-! ## The runtime's call sequences are allowed -/

/-- Cold init: Phase 2 setup, then Pass 2 or Pass 3 (`06-lifecycle.md:70-81`). -/
theorem cold_init_sequence :
    run .uninstantiated
      [ (.instantiate, 0), (.setParameters, 0), (.configureStructure, 0)
      , (.enterColdInit, 0), (.exitInitMode, 0) ] = some .stepMode := by
  decide

/-- A splice creates and warm-starts each replacement in an inter-tick window
whose time `t` is the next tick, so `t > 0` (`10-composition.md:185`). -/
theorem splice_sequence (t : Time) (ht : t > 0) :
    run .uninstantiated
      [ (.instantiate, t), (.setParameters, t), (.configureStructure, t)
      , (.enterWarmStart, t), (.exitInitMode, t) ] = some .stepMode := by
  cases t with
  | zero => contradiction
  | succ n => rfl

/-- A splice cannot happen at `t = 0`. -/
theorem no_warm_start_at_zero :
    next .structuralConfig .enterWarmStart 0 = none := by
  decide

/-- A re-trim takes a running instance through warm start and back
(`06-lifecycle.md:87`). -/
theorem retrim_sequence (t : Time) :
    run .stepMode [(.enterWarmStart, t), (.exitInitMode, t)] = some .stepMode := by
  rfl

/-! ## Initialization comes before stepping -/

theorem into_stepMode (s : State) (c : Call) (t : Time)
    (h : next s c t = some .stepMode) : c = .exitInitMode ∨ s = .stepMode := by
  cases s <;> cases c <;> cases t <;> simp_all [next]

/-- Every successful run that reaches `StepMode` from another state includes a
`dl_exit_init_mode` call, so no instance steps before it is initialized. -/
theorem stepMode_needs_init (calls : List (Call × Time)) :
    ∀ s, s ≠ .stepMode → run s calls = some .stepMode →
      .exitInitMode ∈ calls.map Prod.fst := by
  induction calls with
  | nil => intro s hs h; simp [run] at h; exact absurd h hs
  | cons ct cs ih =>
    intro s hs h
    obtain ⟨c, t⟩ := ct
    simp only [run] at h
    split at h
    · rename_i s' hn
      by_cases hc : c = .exitInitMode
      · simp [hc]
      · by_cases hs' : s' = .stepMode
        · subst hs'
          rcases into_stepMode s c t hn with h1 | h1
          · exact absurd h1 hc
          · exact absurd h1 hs
        · simp [ih s' hs' h]
    · contradiction

/-! ## Teardown (§14.2 item 3) -/

/-- Teardown of one instance: "it calls `dl_terminate` if the state allows
it, and then `dl_free_instance` if the instance is not `Uninstantiated`"
(`14-diagnostics.md:395`). `skipTerminate` is the case of an instance whose
`dl_terminate` already failed (`10-composition.md:185`). The calls may fail,
and a failed call leaves the state unchanged. -/
def teardown (s : State) (t : Time) (skipTerminate termFails : Bool) : State × List Status :=
  let (s1, st1) :=
    if !skipTerminate && (next s .terminate t).isSome then
      let r := apply s .terminate t termFails
      (r.1, [r.2])
    else (s, [])
  if s1 != .uninstantiated then
    let r := apply s1 .freeInstance t false
    (r.1, st1 ++ [r.2])
  else (s1, st1)

/-- Teardown ends every instance `Uninstantiated` from any state, whether or not
`dl_terminate` fails or is skipped, and never makes a call that the table forbids. -/
theorem teardown_frees (s : State) (t : Time) (skip fails : Bool) :
    (teardown s t skip fails).1 = .uninstantiated ∧
    .errState ∉ (teardown s t skip fails).2 := by
  cases s <;> cases skip <;> cases fails <;> simp [teardown, apply, next]

end Driveline.Lifecycle
