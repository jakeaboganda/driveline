import Driveline.Schedule
import Driveline.Validity

/-!
# Status codes and runtime handling (spec §14)

`docs/spec/14-diagnostics.md`. The status codes of §14.1, the sequential and
parallel selection of the reported error (item 2), the teardown order (item 3),
the output-validation order (item 4, on `Validity`'s `outputCheck`), and the
report tick (item 5).
-/

namespace Driveline.Diagnostics

/-! ## Status codes (§14.1) -/

/-- The §14.1 table (14-diagnostics.md:18-26). -/
inductive Code
  | ok | warnFmuColdSplice | warnTrimMismatch | errInvalidArg | errTierMissing
  | errNumeric | errUnsupportedMode | errState | errFmu
  deriving DecidableEq, Repr

def Code.toInt : Code → Int
  | .ok => 0
  | .warnFmuColdSplice => 2
  | .warnTrimMismatch => 3
  | .errInvalidArg => -1
  | .errTierMissing => -2
  | .errNumeric => -3
  | .errUnsupportedMode => -4
  | .errState => -5
  | .errFmu => -6

def Code.name : Code → String
  | .ok => "DL_STATUS_OK"
  | .warnFmuColdSplice => "DL_STATUS_WARN_FMU_COLD_SPLICE"
  | .warnTrimMismatch => "DL_STATUS_WARN_TRIM_MISMATCH"
  | .errInvalidArg => "DL_STATUS_ERR_INVALID_ARG"
  | .errTierMissing => "DL_STATUS_ERR_TIER_MISSING"
  | .errNumeric => "DL_STATUS_ERR_NUMERIC"
  | .errUnsupportedMode => "DL_STATUS_ERR_UNSUPPORTED_MODE"
  | .errState => "DL_STATUS_ERR_STATE"
  | .errFmu => "DL_STATUS_ERR_FMU"

inductive Severity | ok | warning | error
  deriving DecidableEq, Repr

/-- "A negative code is an error. A positive code is a warning." -/
def severityOf (c : Int) : Severity :=
  if c < 0 then .error else if c > 0 then .warning else .ok

def Code.severity (c : Code) : Severity := severityOf c.toInt

/-- P14-01. "A negative code is an error. A positive code is a warning."
(14-diagnostics.md:12). The sign rule agrees with the `ERR_` and `WARN_` name
prefixes of the §14.1 table. -/
theorem severity_by_sign (c : Code) :
    (c.severity = .error ↔ "DL_STATUS_ERR_".toList.isPrefixOf c.name.toList = true) ∧
      (c.severity = .warning ↔ "DL_STATUS_WARN_".toList.isPrefixOf c.name.toList = true) := by
  cases c <;> decide

/-- Whether a component may return the code from a `dl_*` call. -/
def Code.componentReturns : Code → Bool
  | .errFmu => false
  | _ => true

/-- P14-03. `DL_STATUS_ERR_FMU`: "The runtime reports it. Components never
return it." (14-diagnostics.md:26). Every other code of the table is one that a
component may return. -/
theorem errFmu_runtime_only (c : Code) : c.componentReturns = true ↔ c ≠ .errFmu := by
  cases c <;> decide

/-! ## Warnings and errors (§14.2 items 1 and 2) -/

inductive Control | running | stopped
  deriving DecidableEq

/-- "The run continues" after a warning (14:30); an error "stops the run" (14:31). -/
def handle (s : Control) (c : Code) : Control :=
  if c.severity = .error then .stopped else s

/-- P14-04. Warnings: "The runtime records the warning ... The run continues."
(14-diagnostics.md:30). -/
theorem warning_continues (s : Control) (c : Code) (h : c.severity = .warning) :
    handle s c = s := by
  simp [handle, h]

/-- The reports of one call: its warnings, then at most one error, output
validation included. It depends only on the call, because "No component reads
another entity's output within a tick" (11-execution.md:27). -/
structure CallOut (R : Type) where
  warns : List R
  err : Option R

/-- Sequential execution in the order of §11: it stops at the first error. -/
def seqReports {C R : Type} (out : C → CallOut R) : List C → List R
  | [] => []
  | c :: cs => (out c).warns ++
      match (out c).err with
      | some e => [e]
      | none => seqReports out cs

/-- The reports of the calls that ran, in §11 order, each flagged if it is an error. -/
def collected {C R : Type} (out : C → CallOut R) (ran : C → Bool) (order : List C) :
    List (R × Bool) :=
  (order.filter ran).flatMap fun c =>
    (out c).warns.map (·, false) ++ (out c).err.toList.map (·, true)

/-- The prefix up to and including the first element that satisfies `p`. -/
def takeUntilIncl {α : Type} (p : α → Bool) : List α → List α
  | [] => []
  | a :: as => if p a then [a] else a :: takeUntilIncl p as

/-- The first failing call of `order`. -/
def failedFirst {C R : Type} (out : C → CallOut R) (order : List C) : Option C :=
  order.find? fun c => (out c).err.isSome

theorem takeUntilIncl_append_of_false {α : Type} (p : α → Bool) (l₁ l₂ : List α)
    (h : ∀ x ∈ l₁, p x = false) : takeUntilIncl p (l₁ ++ l₂) = l₁ ++ takeUntilIncl p l₂ := by
  induction l₁ with
  | nil => rfl
  | cons a l ih =>
    simp only [List.mem_cons, forall_eq_or_imp] at h
    simp [takeUntilIncl, h.1, ih h.2]

/-- P14-05. "If several calls fail, as can happen when Phase 2 runs in parallel,
the reported error is the first failing call in the order of §11"
(14-diagnostics.md:31). `hcover`: every call up to and including that error has
run, which the next sentence of 14:31 requires. -/
theorem reported_first {C R : Type} (out : C → CallOut R) (ran : C → Bool) (order : List C)
    (hcover : ∀ c ∈ takeUntilIncl (fun c => (out c).err.isSome) order, ran c = true) :
    failedFirst out (order.filter ran) = failedFirst out order := by
  induction order with
  | nil => rfl
  | cons c cs ih =>
    have hc : ran c = true := hcover c (by unfold takeUntilIncl; split <;> simp)
    by_cases he : (out c).err.isSome = true
    · simp [failedFirst, List.filter, hc, List.find?, he]
    · have he' : (out c).err.isSome = false := by simpa using he
      have ih' := ih (fun x hx => hcover x (by simp [takeUntilIncl, he', hx]))
      simp only [failedFirst] at ih' ⊢
      simp [List.filter, hc, List.find?, he', ih']

/-- P14-06. "The run's reports are exactly those that sequential execution in
that order produces up to and including that error, and reports from calls
after it are discarded." (14-diagnostics.md:31). The runtime keeps the reports
of the calls that ran, in §11 order, up to the first error. Teardown runs after
this error and its reports follow it (18-run-record.md:25). `hcover` as in
`reported_first`. -/
theorem par_reports {C R : Type} (out : C → CallOut R) (ran : C → Bool) (order : List C)
    (hcover : ∀ c ∈ takeUntilIncl (fun c => (out c).err.isSome) order, ran c = true) :
    (takeUntilIncl (·.2) (collected out ran order)).map Prod.fst = seqReports out order := by
  induction order with
  | nil => rfl
  | cons c cs ih =>
    have hc : ran c = true := hcover c (by unfold takeUntilIncl; split <;> simp)
    have hw : ∀ x ∈ (out c).warns.map (·, false), (fun y : R × Bool => y.2) x = false := by
      simp
    simp only [collected, List.filter, hc, List.flatMap_cons, List.append_assoc]
    rw [takeUntilIncl_append_of_false _ _ _ hw]
    cases he : (out c).err with
    | some e => simp [takeUntilIncl, seqReports, he, Function.comp_def]
    | none =>
      have ih' := ih (fun x hx => hcover x (by simp [takeUntilIncl, he, hx]))
      simp [seqReports, he, ← ih', collected, Function.comp_def]

/-! ## Teardown order (§14.2 item 3) -/

/-- An actor or a group. `ent`: its `actor_id`s, keyed by the smallest;
`phase2`: its components in Phase 2 order, each with its per-actor instances in
`bind` order; `physics`: its physics instances in `bind` order
(11-execution.md:27). -/
structure Entity (I : Type) where
  ent : Schedule.Entity
  phase2 : List (List I)
  physics : List I

/-- The entity's instances in Phase 2 order, "with each actor's or group's
physics instances after its Stage 2 instances and per-actor physics instances in
`bind` order" (06-lifecycle.md:70). -/
def Entity.startup {I : Type} (e : Entity I) : List I := e.phase2.flatten ++ e.physics

/-- "in the reverse of Phase 2 order, physics first, with per-actor instances in
reverse `bind` order" (14-diagnostics.md:32). -/
def Entity.teardown {I : Type} (e : Entity I) : List I :=
  e.physics.reverse ++ (e.phase2.map List.reverse).reverse.flatten

/-- The Phase 2 instance order of the current graph, for `es` in Phase 2 order. -/
def startupOrder {I : Type} (es : List (Entity I)) : List I := es.flatMap Entity.startup

/-- "in descending `actor_id` order, with a group sorted by its smallest member" (14:32). -/
def teardownOrder {I : Type} (es : List (Entity I)) : List I := es.reverse.flatMap Entity.teardown

/-- P14-07. Teardown visits "instances in descending `actor_id` order, with a
group sorted by its smallest member, and within one actor or group in the
reverse of Phase 2 order, physics first, with per-actor instances in reverse
`bind` order" (14-diagnostics.md:32). `es` is in Phase 2 order: "ascending
order of `actor_id` ... A group sorts by its smallest member `actor_id`"
(11-execution.md:27), an order that `Schedule.entity_order_unique` makes unique.
Then `es.reverse` is strictly descending by that key, and teardown is the
reverse of the current graph's Phase 2 instance order. -/
theorem teardown_reverse_startup {I : Type} (es : List (Entity I))
    (hs : es.Pairwise fun a b => a.ent.key < b.ent.key) :
    es.reverse.Pairwise (fun a b => b.ent.key < a.ent.key) ∧
      teardownOrder es = (startupOrder es).reverse := by
  refine ⟨List.pairwise_reverse.2 hs, ?_⟩
  simp only [teardownOrder, startupOrder, List.reverse_flatMap, Entity.startup,
    Function.comp_def, List.reverse_append, List.reverse_flatten]
  rfl

/-! ## Output validation order (§14.2 item 4) -/

/-- The result of one list of checks: the first failure, else `ok`. -/
def firstFail (rs : List CheckResult) : CheckResult := (rs.find? (· != .ok)).getD .ok

/-- "A group instance's frames are checked in `actor_ids` order" (14:33). -/
def groupCheck {F : Type} (check : F → CheckResult) (frames : List F) : CheckResult :=
  firstFail (frames.map check)

open Classical in
/-- One step of the output check: `ok` if `p` holds, else `fail`. -/
noncomputable def stepResult (p : Prop) (fail : CheckResult) : CheckResult :=
  if p then .ok else fail

theorem firstFail_cons (r : CheckResult) (l : List CheckResult) :
    firstFail (r :: l) = if r = .ok then firstFail l else r := by
  cases r <;> simp [firstFail, List.find?] <;> rfl

theorem firstFail_append (l₁ l₂ : List CheckResult) :
    firstFail (l₁ ++ l₂) = if firstFail l₁ = .ok then firstFail l₂ else firstFail l₁ := by
  induction l₁ with
  | nil => simp [firstFail]
  | cons r l ih =>
    rw [List.cons_append, firstFail_cons, firstFail_cons, ih]
    split_ifs <;> simp_all

theorem groupCheck_flatMap {F : Type} (steps : F → List CheckResult) (frames : List F) :
    groupCheck (fun f => firstFail (steps f)) frames = firstFail (frames.flatMap steps) := by
  induction frames with
  | nil => rfl
  | cons f fs ih =>
    simp only [groupCheck, List.map_cons, List.flatMap_cons] at ih ⊢
    rw [firstFail_cons, firstFail_append, ih]

/-- The three steps of 14:33 for an `IntentFrame`. -/
noncomputable def intentSteps (map : RoadMap) (d : Decl) (f : IntentFrame) : List CheckResult :=
  [stepResult (f.wellFormed d) .invalidArg, stepResult f.finiteOK .numeric,
    stepResult (f.valid map d) .invalidArg]

noncomputable def kinematicSteps (d : Decl) (f : KinematicControlFrame) : List CheckResult :=
  [stepResult (f.wellFormed d) .invalidArg, stepResult f.finiteOK .numeric,
    stepResult (f.valid d) .invalidArg]

noncomputable def actuatorSteps (n : Nat) (d : Decl) (f : ActuatorControlFrame) :
    List CheckResult :=
  [stepResult (f.wellFormed d) .invalidArg, stepResult f.finiteOK .numeric,
    stepResult (f.valid n d) .invalidArg]

theorem intent_outputCheck_steps (map : RoadMap) (d : Decl) (f : IntentFrame) :
    f.outputCheck map d = firstFail (intentSteps map d f) := by
  unfold IntentFrame.outputCheck intentSteps stepResult
  split_ifs <;> rfl

theorem kinematic_outputCheck_steps (d : Decl) (f : KinematicControlFrame) :
    f.outputCheck d = firstFail (kinematicSteps d f) := by
  unfold KinematicControlFrame.outputCheck kinematicSteps stepResult
  split_ifs <;> rfl

theorem actuator_outputCheck_steps (n : Nat) (d : Decl) (f : ActuatorControlFrame) :
    f.outputCheck n d = firstFail (actuatorSteps n d f) := by
  unfold ActuatorControlFrame.outputCheck actuatorSteps stepResult
  split_ifs <;> rfl

/-- P14-09. "A group instance's frames are checked in `actor_ids` order, each
through every step below before the next, and the first failure is the
reported error." (14-diagnostics.md:33). For each frame type, `Validity`'s
`outputCheck` over the frames of a group is the first failure of the
frame-major, step-minor list of steps. -/
theorem group_check_frame_major (map : RoadMap) (n : Nat) (d : Decl)
    (fi : List IntentFrame) (fk : List KinematicControlFrame) (fa : List ActuatorControlFrame) :
    groupCheck (fun f => f.outputCheck map d) fi = firstFail (fi.flatMap (intentSteps map d)) ∧
      groupCheck (fun f => f.outputCheck d) fk = firstFail (fk.flatMap (kinematicSteps d)) ∧
      groupCheck (fun f => f.outputCheck n d) fa = firstFail (fa.flatMap (actuatorSteps n d)) := by
  refine ⟨?_, ?_, ?_⟩
  · simp only [intent_outputCheck_steps]; exact groupCheck_flatMap _ _
  · simp only [kinematic_outputCheck_steps]; exact groupCheck_flatMap _ _
  · simp only [actuator_outputCheck_steps]; exact groupCheck_flatMap _ _

/-- P14-10. "every count that the frame's modes use (`num_waypoints`,
`num_traj_points`) must be at most 64, and every `char[N]` field that the modes
use must hold a null within its N bytes with valid UTF-8 before it ..., and a
failure is `DL_STATUS_ERR_INVALID_ARG`" (14-diagnostics.md:33). `IntentFrame` is
the frame with counts and `char` fields. A mode field always holds a listed
value or `NONE`, because it has an enum type (`Validity`). -/
theorem output_step1 (map : RoadMap) (d : Decl) (f : IntentFrame) :
    (¬ f.wellFormed d → f.outputCheck map d = .invalidArg) ∧
      (f.outputCheck map d = .ok →
        (f.uses .numWaypoints = true → f.numWaypoints ≤ 64) ∧
          (f.uses .numTrajPoints = true → f.numTrajPoints ≤ 64) ∧
          (f.uses .targetRoadId = true → charOK f.targetRoadId)) := by
  refine ⟨fun h => ?_, fun h => ?_⟩
  · unfold IntentFrame.outputCheck; simp [h]
  · exact (IntentFrame.outputCheck_ok.1 h).1.2

/-! ## Report tick (§14.2 item 5) -/

/-- Where a report is made. `splice k`: the window after Phase 4 of tick `k`. -/
inductive Ctx | coldInit | exec (k : Nat) | splice (k : Nat)

def reportTick : Ctx → Nat
  | .coldInit => 0
  | .exec k => k
  | .splice k => k + 1

/-- "each with `sim_time_ns` equal to that tick's time" (14:34, 11-execution.md:12). -/
def simTimeNs (dt : ℕ+) (c : Ctx) : Nat := Schedule.tickTime dt (reportTick c)

/-- P14-11. "A report made during cold init carries tick 0, one made in a
splice window carries the tick after the window, and one made while the
runtime executes tick k, Phase 4 included, carries tick k, each with
`sim_time_ns` equal to that tick's time." (14-diagnostics.md:34). A splice
window report has a positive time, as `Lifecycle.splice_sequence` needs. -/
theorem report_tick (dt : ℕ+) (k : Nat) :
    reportTick .coldInit = 0 ∧ reportTick (.exec k) = k ∧ reportTick (.splice k) = k + 1 ∧
      (∀ c, simTimeNs dt c = reportTick c * dt) ∧ 0 < simTimeNs dt (.splice k) := by
  refine ⟨rfl, rfl, rfl, fun _ => rfl, ?_⟩
  simp [simTimeNs, reportTick, Schedule.tickTime]

/-- How a run ended. `failed c committed`: an error in context `c`;
`committed`: the failing tick's Phase 4 commit happened (14:31).
`succeeded k`: `terminate when` held in Phase 4 of tick `k`. -/
inductive Ending | failed (at_ : Ctx) (committed : Bool) | succeeded (k : Nat)

/-- "A teardown report carries the same tick and time as the error that ended
the run, or, after a successful run, the tick whose Phase 4 ended it." (14:34) -/
def teardownTick : Ending → Nat
  | .failed c _ => reportTick c
  | .succeeded k => k

end Driveline.Diagnostics
