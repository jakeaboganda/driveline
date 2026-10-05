import Mathlib.Tactic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic

/-!
# Tick schedule (spec §11)

A model of the base clock, rate divisors, and scheduling rule
(`docs/spec/11-execution.md:12-18`), the four tick phases (`11:19-23`), and the
evaluation order within a phase (`11:27`), with the delivery rule of `05:40`.

Phase 2 is modelled by `P2`: one output slot per component, components visited in
`order`, and each scheduled component writes its slot from the buffer as it
stands at its turn.

Chain order is modelled on `ChainExpr`, the chain expression of `12:47-49` after
`fn` substitution and inlining of named chains, with its calls numbered left to
right. By `16:75` a frame port is bound only as the pipe input or an `Arbitrate`
operand, so the data edges are exactly those of `>>`, `+`, and `Arbitrate`.
-/

namespace Driveline.Schedule

/-! ## Base clock and rates -/

abbrev Tick := ℕ

/-- Tick time in nanoseconds. -/
def tickTime (dt : ℕ+) (k : Tick) : ℕ := k * dt

/-- P11-01 (`11-execution.md:12`): "The simulation clock advances by integer tick
index k_tick ∈ {0, 1, 2, …} with base period Δt_base_ns ∈ ℤ⁺ nanoseconds
(t_ns = k_tick · Δt_base_ns)." Tick times strictly increase. -/
theorem tickTime_strictMono (dt : ℕ+) : StrictMono (tickTime dt) := by
  intro a b h
  exact Nat.mul_lt_mul_of_pos_right h dt.pos

def validRate (dt : ℕ+) (f : ℚ) : Prop := ∃ k : ℕ+, (k : ℚ) * dt * f = 10 ^ 9

def defaultDiv : ℕ+ := 1

/-- P11-02 (`11-execution.md:13`): "A sensor or component rate f_comp is valid only
if some positive integer k_div satisfies k_div · Δt_base_ns · f_comp = 10^9
exactly. The compiler checks this rule with exact rational arithmetic." The rule
is a finite rational check. -/
theorem validRate_iff (dt : ℕ+) (f : ℚ) :
    validRate dt f ↔ 0 < f ∧ ((10 ^ 9 : ℚ) / (dt * f)).den = 1 := by
  have hdt : (0 : ℚ) < (dt : ℚ) := by exact_mod_cast dt.pos
  constructor
  · rintro ⟨k, hk⟩
    have hk0 : (0 : ℚ) < (k : ℚ) := by exact_mod_cast k.pos
    have hf : 0 < f := by
      by_contra h
      push Not at h
      have : (k : ℚ) * dt * f ≤ 0 := mul_nonpos_of_nonneg_of_nonpos (by positivity) h
      linarith
    refine ⟨hf, ?_⟩
    have : (10 ^ 9 : ℚ) / (dt * f) = ((k : ℕ) : ℚ) := by
      rw [div_eq_iff (by positivity)]
      linarith [hk]
    rw [this]
    exact Rat.den_natCast _
  · rintro ⟨hf, hd⟩
    set q := (10 ^ 9 : ℚ) / (dt * f) with hq
    have hqpos : 0 < q := by positivity
    have hqint : (q.num : ℚ) = q := Rat.den_eq_one_iff q |>.mp hd
    have hnum : 0 < q.num := Rat.num_pos.mpr hqpos
    let k : ℕ+ := ⟨q.num.toNat, by omega⟩
    have hk : ((k : ℕ) : ℚ) = q := by
      show ((q.num.toNat : ℕ) : ℚ) = q
      rw [← hqint]
      exact_mod_cast Int.toNat_of_nonneg hnum.le
    refine ⟨k, ?_⟩
    rw [hk, hq]
    field_simp

instance (dt : ℕ+) (f : ℚ) : Decidable (validRate dt f) :=
  decidable_of_iff _ (validRate_iff dt f).symm

/-- P11-02 (`11-execution.md:13`): "some positive integer k_div satisfies
k_div · Δt_base_ns · f_comp = 10^9 exactly." The divisor of a valid rate is
unique. -/
theorem div_unique {dt : ℕ+} {f : ℚ} {k k' : ℕ+} (h : (k : ℚ) * dt * f = 10 ^ 9)
    (h' : (k' : ℚ) * dt * f = 10 ^ 9) : k = k' := by
  have hne : (dt : ℚ) * f ≠ 0 := by
    intro h0
    have : (k : ℚ) * dt * f = 0 := by rw [mul_assoc, h0, mul_zero]
    norm_num [this] at h
  have : (k : ℚ) = (k' : ℚ) := by
    apply mul_right_cancel₀ hne
    rw [← mul_assoc, ← mul_assoc, h, h']
  exact PNat.coe_inj.mp (by exact_mod_cast this)

/-- P11-03 (`11-execution.md:13`): "Any other rate (such as `30Hz` on a `500Hz` base
clock) is a compile-time error." -/
theorem rate30_on_500_invalid : ¬ validRate 2000000 30 := by
  rintro ⟨k, hk⟩
  have : (k : ℕ) * 2000000 * 30 = 10 ^ 9 := by exact_mod_cast hk
  omega

/-- P11-03 (`11-execution.md:13`): "valid only if some positive integer k_div
satisfies k_div · Δt_base_ns · f_comp = 10^9". `50Hz` on a `500Hz` base clock is
valid with k_div = 10, so the rule is not vacuous. -/
theorem rate50_on_500_valid : validRate 2000000 50 :=
  ⟨10, by norm_num⟩

/-- P11-04 (`11-execution.md:14`): "Any component that omits a `(rate: ...)` clause
inherits the base clock rate (k_div = 1)." The base rate is valid. -/
theorem default_rate_valid (dt : ℕ+) : validRate dt (10 ^ 9 / dt) :=
  ⟨1, by
    have : (dt : ℚ) ≠ 0 := by exact_mod_cast dt.ne_zero
    field_simp; simp⟩

/-- P11-04 (`11-execution.md:14`): "inherits the base clock rate (k_div = 1)." The
base rate has divisor 1 and no other. -/
theorem default_div (dt k : ℕ+) (h : (k : ℚ) * dt * (10 ^ 9 / dt) = 10 ^ 9) :
    k = defaultDiv := by
  have hdt : (dt : ℚ) ≠ 0 := by exact_mod_cast dt.ne_zero
  exact div_unique h (by simp [defaultDiv]; field_simp)

/-! ## Scheduling rule -/

/-- A component with divisor `d` runs on tick `k` (`11:15`). -/
def runs (d : ℕ+) (k : Tick) : Prop := k % d = 0

instance (d : ℕ+) (k : Tick) : Decidable (runs d k) :=
  inferInstanceAs (Decidable (k % (d : ℕ) = 0))

/-- The most recent tick at or before `k` on which the component runs. -/
def lastRun (d : ℕ+) (k : Tick) : Tick := (d : ℕ) * (k / d)

/-- The output on tick `k` under Zero-Order Hold. -/
def held {α : Type*} (d : ℕ+) (out : Tick → α) (k : Tick) : α := out (lastRun d k)

/-- A component's own period in nanoseconds. -/
def stepDt (d dt : ℕ+) : ℕ := (d : ℕ) * dt

/-- The least tick at or after `k` on which the component runs. -/
def tFirst (d : ℕ+) (k : Tick) : Tick := (d : ℕ) * ((k + d - 1) / d)

/-- P11-05 (`11-execution.md:15`): "A component with divisor k_div executes on tick
k_tick if and only if (k_tick mod k_div) == 0". -/
theorem runs_iff_dvd (d : ℕ+) (k : Tick) : runs d k ↔ (d : ℕ) ∣ k :=
  (Nat.dvd_iff_mod_eq_zero).symm

/-- P11-05 (`11-execution.md:15`): "executes on tick k_tick if and only if
(k_tick mod k_div) == 0". Every component runs on tick 0. -/
theorem runs_zero (d : ℕ+) : runs d 0 := Nat.zero_mod _

/-- P11-05 (`11-execution.md:15`): "executes on tick k_tick if and only if
(k_tick mod k_div) == 0". A base-rate component runs on every tick. -/
theorem runs_one (k : Tick) : runs 1 k := Nat.mod_one _

theorem lastRun_of_runs {d : ℕ+} {k : Tick} (h : runs d k) : lastRun d k = k :=
  Nat.mul_div_cancel' ((runs_iff_dvd d k).mp h)

theorem lastRun_succ_of_not_runs {d : ℕ+} {k : Tick} (h : ¬ runs d (k + 1)) :
    lastRun d (k + 1) = lastRun d k := by
  unfold lastRun
  rw [Nat.succ_div_of_not_dvd (fun h' => h ((runs_iff_dvd d _).mpr h'))]

/-- P11-06 (`11-execution.md:15`): "holds its output constant via Zero-Order Hold
(ZOH) on intermediate ticks." The held output comes from the latest tick at or
before `k` on which the component ran. -/
theorem lastRun_isGreatest (d : ℕ+) (k : Tick) :
    IsGreatest {j | j ≤ k ∧ runs d j} (lastRun d k) := by
  refine ⟨⟨Nat.mul_div_le k d, Nat.mul_mod_right _ _⟩, ?_⟩
  rintro j ⟨hjk, hj⟩
  obtain ⟨m, rfl⟩ := (runs_iff_dvd d j).mp hj
  unfold lastRun
  exact Nat.mul_le_mul_left _ ((Nat.le_div_iff_mul_le d.pos).mpr (by rw [mul_comm]; exact hjk))

/-- P11-06 (`11-execution.md:15`): "executes on tick k_tick … and holds its output
constant via Zero-Order Hold (ZOH) on intermediate ticks." On a tick where it runs,
the held output is the new one. -/
theorem held_run {α : Type*} (d : ℕ+) (out : Tick → α) (k : Tick) (h : runs d k) :
    held d out k = out k := by
  simp [held, lastRun_of_runs h]

/-- P11-06 (`11-execution.md:15`): "holds its output constant via Zero-Order Hold
(ZOH) on intermediate ticks." -/
theorem held_zoh {α : Type*} (d : ℕ+) (out : Tick → α) (k : Tick)
    (h : ¬ runs d (k + 1)) : held d out (k + 1) = held d out k := by
  simp [held, lastRun_succ_of_not_runs h]

/-- P11-09 (`11-execution.md:18`): "A scenario-declared component's `step(t, dt)`
receives t, the tick time, and dt = k_div · Δt_base, its own period." `dt` is the
time from this step to the component's next one. -/
theorem stepDt_period (d dt : ℕ+) (k : Tick) (h : runs d k) :
    IsLeast {j : Tick | k < j ∧ runs d j} (k + (d : ℕ)) ∧
      tickTime dt (k + (d : ℕ)) = tickTime dt k + stepDt d dt := by
  have hk := (runs_iff_dvd d k).mp h
  have hd0 : 0 < (d : ℕ) := d.pos
  refine ⟨⟨⟨Nat.lt_add_of_pos_right hd0, ?_⟩, ?_⟩, ?_⟩
  · exact (runs_iff_dvd d _).mpr (Nat.dvd_add hk dvd_rfl)
  · rintro j ⟨hkj, hj⟩
    have hd : (d : ℕ) ∣ j - k := Nat.dvd_sub ((runs_iff_dvd d j).mp hj) hk
    have hpos : 0 < j - k := Nat.sub_pos_of_lt hkj
    have := Nat.le_of_dvd hpos hd
    show k + (d : ℕ) ≤ j
    omega
  · simp [tickTime, stepDt, add_mul]

/-! ## Phase 2 dataflow -/

/-- Phase 2 executor: one buffer slot per component, components in `order`. -/
structure P2 (ι α : Type*) where
  order : List ι
  div : ι → ℕ+
  /-- Reads the buffer as it stands at its turn. -/
  step : ι → Tick → (ι → α) → α

variable {ι α : Type*} [DecidableEq ι]

def turn (p : P2 ι α) (k : Tick) (b : ι → α) (i : ι) : ι → α :=
  if runs (p.div i) k then Function.update b i (p.step i k b) else b

def phase2 (p : P2 ι α) (k : Tick) (b : ι → α) : ι → α := p.order.foldl (turn p k) b

/-- The buffer before Phase 2 of tick `k`. -/
def pre (p : P2 ι α) (b0 : ι → α) : Tick → (ι → α)
  | 0 => b0
  | k + 1 => phase2 p k (pre p b0 k)

/-- The buffer after Phase 2 of tick `k`. -/
def after (p : P2 ι α) (b0 : ι → α) (k : Tick) : ι → α := phase2 p k (pre p b0 k)

/-- The buffer that component `c` reads at its turn on tick `k`. -/
def seenBy (p : P2 ι α) (b0 : ι → α) (k : Tick) (c : ι) : ι → α :=
  (p.order.takeWhile (fun x => x ≠ c)).foldl (turn p k) (pre p b0 k)

theorem foldl_turn_of_not_mem (p : P2 ι α) (k : Tick) {u : ι} :
    ∀ (l : List ι) (b : ι → α), u ∉ l → (l.foldl (turn p k) b) u = b u
  | [], _, _ => rfl
  | i :: l, b, h => by
    have hi : u ≠ i := fun h' => h (h' ▸ List.mem_cons_self)
    rw [List.foldl_cons, foldl_turn_of_not_mem p k l _ (fun h' => h (List.mem_cons_of_mem _ h'))]
    unfold turn
    split_ifs <;> simp [Function.update_of_ne hi]

theorem foldl_turn_of_not_runs (p : P2 ι α) (k : Tick) {u : ι} (hu : ¬ runs (p.div u) k) :
    ∀ (l : List ι) (b : ι → α), (l.foldl (turn p k) b) u = b u
  | [], _ => rfl
  | i :: l, b => by
    rw [List.foldl_cons, foldl_turn_of_not_runs p k hu l]
    unfold turn
    by_cases hi : u = i
    · subst hi; simp [hu]
    · split_ifs <;> simp [Function.update_of_ne hi]

theorem split_takeWhile {l : List ι} {x : ι} (h : x ∈ l) :
    ∃ rest, l = l.takeWhile (fun y => y ≠ x) ++ x :: rest := by
  induction l with
  | nil => simp at h
  | cons y t ih =>
    by_cases hy : y = x
    · subst hy; exact ⟨t, by simp⟩
    · obtain ⟨r, hr⟩ := ih (by simpa [Ne.symm hy] using h)
      refine ⟨r, ?_⟩
      simp only [List.takeWhile_cons, ne_eq, hy, not_false_eq_true, decide_true,
        List.cons_append]
      exact congrArg _ hr

theorem not_mem_takeWhile_ne (x : ι) : ∀ l : List ι, x ∉ l.takeWhile (fun y => y ≠ x)
  | [] => by simp
  | y :: t => by
    by_cases hy : y = x
    · simp [List.takeWhile_cons, hy]
    · simp only [List.takeWhile_cons, ne_eq, hy, not_false_eq_true, decide_true, ite_true,
        List.mem_cons, not_or]
      exact ⟨Ne.symm hy, not_mem_takeWhile_ne x t⟩

/-- A component's slot after Phase 2 of tick `k` holds its output from the latest
tick on which it ran. -/
theorem after_lastRun (p : P2 ι α) (b0 : ι → α) (u : ι) :
    ∀ k, after p b0 k u = after p b0 (lastRun (p.div u) k) u
  | 0 => by simp [lastRun]
  | k + 1 => by
    by_cases h : runs (p.div u) (k + 1)
    · rw [lastRun_of_runs h]
    · rw [lastRun_succ_of_not_runs h, ← after_lastRun p b0 u k]
      exact foldl_turn_of_not_runs p (k + 1) h _ _

/-- The buffer an upstream's consumer reads holds the upstream's slot after
Phase 2. -/
theorem seenBy_eq_after (p : P2 ι α) (b0 : ι → α) (hnd : p.order.Nodup) {u c : ι}
    (hu : u ∈ p.order) (hc : c ∈ p.order)
    (hlt : p.order.idxOf u < p.order.idxOf c) (k : Tick) :
    seenBy p b0 k c u = after p b0 k u := by
  obtain ⟨rest, hr⟩ := split_takeWhile hc
  have hnot : u ∉ c :: rest := by
    intro hm
    have hnd' := hr ▸ hnd
    have hup : u ∉ p.order.takeWhile (fun y => y ≠ c) := fun h' =>
      List.disjoint_of_nodup_append hnd' h' hm
    rw [hr, List.idxOf_append_of_notMem hup,
      List.idxOf_append_of_notMem (not_mem_takeWhile_ne c _)] at hlt
    simp at hlt
  unfold after phase2 seenBy
  conv_rhs => rw [hr]
  rw [List.foldl_append]
  exact (foldl_turn_of_not_mem p k _ _ hnot).symm

/-- P11-08 (`11-execution.md:17`): "In Phase 2, a component reads each upstream
output as it stands after the upstream's most recent step at or before the current
tick. That includes a step earlier in the same Phase 2, because components run in
topological order." Upstream `u` precedes `c` in `order`. -/
theorem read_latest (p : P2 ι α) (b0 : ι → α) (hnd : p.order.Nodup) {u c : ι}
    (hu : u ∈ p.order) (hc : c ∈ p.order)
    (hlt : p.order.idxOf u < p.order.idxOf c) (k : Tick) :
    seenBy p b0 k c u = after p b0 (lastRun (p.div u) k) u := by
  rw [seenBy_eq_after p b0 hnd hu hc hlt, after_lastRun]

/-- P11-08 (`11-execution.md:17`): "a component reads each upstream output as it
stands after the upstream's most recent step". A scheduled component's step writes
its slot, from the buffer as it stands at its turn. -/
theorem written_at_turn (p : P2 ι α) (b0 : ι → α) (hnd : p.order.Nodup) {u : ι}
    (hu : u ∈ p.order) (k : Tick) (h : runs (p.div u) k) :
    after p b0 k u = p.step u k (seenBy p b0 k u) := by
  obtain ⟨rest, hr⟩ := split_takeWhile hu
  have hnd' := hr ▸ hnd
  have hrest : u ∉ rest := (List.nodup_cons.mp (List.nodup_append.mp hnd').2.1).1
  unfold after phase2 seenBy
  conv_lhs => rw [hr]
  rw [List.foldl_append, List.foldl_cons, foldl_turn_of_not_mem p k _ _ hrest]
  simp [turn, h]

/-- P05-40 (`05-checkpoints.md:40`): "On a tick where a producer does not step
([§11](11-execution.md)), its consumers receive its last output again." A consumer
`c` downstream of producer `u` reads the same value as on the previous tick. -/
theorem redelivered_when_idle (p : P2 ι α) (b0 : ι → α) (hnd : p.order.Nodup) {u c : ι}
    (hu : u ∈ p.order) (hc : c ∈ p.order)
    (hlt : p.order.idxOf u < p.order.idxOf c) (k : Tick) (h : ¬ runs (p.div u) (k + 1)) :
    seenBy p b0 (k + 1) c u = seenBy p b0 k c u := by
  rw [read_latest p b0 hnd hu hc hlt, read_latest p b0 hnd hu hc hlt,
    lastRun_succ_of_not_runs h]

/-! ## Phases -/

inductive Phase
  | sensors
  | control
  | physics
  | commit
  deriving DecidableEq, Repr

def Phase.idx : Phase → ℕ
  | .sensors => 1
  | .control => 2
  | .physics => 3
  | .commit => 4

def phases (k : Tick) : List Phase :=
  if k = 0 then [.control, .physics, .commit] else [.sensors, .control, .physics, .commit]

/-- P11-10 (`11-execution.md:19-23`): "Each tick runs four phases in this order".
The phases of a tick are in order. -/
theorem phases_sorted (k : Tick) : (phases k).Pairwise (fun a b => a.idx < b.idx) := by
  unfold phases; split_ifs <;> simp [Phase.idx]

/-- P11-10 (`11-execution.md:20`): "Tick 0 skips Phase 1 because cold initialization
Pass 1 has done it". -/
theorem sensors_iff (k : Tick) : Phase.sensors ∈ phases k ↔ k ≠ 0 := by
  unfold phases; split_ifs <;> simp_all

/-- P11-10 (`11-execution.md:19-23`): "Each tick runs four phases in this order".
Phases 2, 3, and 4 run on every tick. -/
theorem phases_suffix (k : Tick) : [Phase.control, .physics, .commit] <:+ phases k := by
  unfold phases
  split_ifs
  · exact List.suffix_refl _
  · exact List.suffix_cons _ _

inductive P4Step
  | commit
  | contact
  | terminate
  | onStatements
  deriving DecidableEq, Repr

/-- Phase 4 steps and the `on` ids that fire. -/
def phase4 (term : Bool) (onConds : List (ℕ × Bool)) : List P4Step × List ℕ :=
  if term then ([.commit, .contact, .terminate], [])
  else ([.commit, .contact, .terminate, .onStatements], (onConds.filter (·.2)).map (·.1))

def executed (term : Tick → Bool) (k : Tick) : Prop := ∀ j < k, term j = false

/-- `sim_time` inside the termination predicate of tick `k`. -/
def predTime (dt : ℕ+) (k : Tick) : ℕ := tickTime dt k + dt

/-- P11-11 (`11-execution.md:23`): "Inside the predicate, and inside `on`
conditions, `sim_time` is t + Δt". That is the next tick's time. -/
theorem predTime_next (dt : ℕ+) (k : Tick) : predTime dt k = tickTime dt (k + 1) := by
  simp [predTime, tickTime, add_mul]

/-- P11-12 (`11-execution.md:23`): "If the predicate is true, the run ends
successfully after this phase, no `on` statement fires on this tick". -/
theorem term_no_on (onConds : List (ℕ × Bool)) : (phase4 true onConds).2 = [] := rfl

/-- P11-12 (`11-execution.md:23`): "the runtime commits X(t + Δt) … Then the runtime
tests contact … and evaluates `terminate when`." -/
theorem contact_before_term (t : Bool) (onConds : List (ℕ × Bool)) :
    (phase4 t onConds).1.take 3 = [.commit, .contact, .terminate] := by
  cases t <;> rfl

/-- P11-12 (`11-execution.md:23`): "If the predicate is true, the run ends
successfully after this phase". No later tick runs. -/
theorem term_ends (term : Tick → Bool) (k : Tick) (h : term k = true) :
    ∀ j > k, ¬ executed term j := by
  intro j hj he
  simp [he k hj] at h

structure KState (σ : Type*) where
  timestamp_ns : ℕ
  /-- Every other field. -/
  rest : σ

def commitStatic {σ : Type*} (s : KState σ) (t' : ℕ) : KState σ := { s with timestamp_ns := t' }

/-- P11-13 (`11-execution.md:23`): "A static actor's committed state keeps every
field except `timestamp_ns`". -/
theorem commitStatic_rest {σ : Type*} (s : KState σ) (t' : ℕ) :
    (commitStatic s t').rest = s.rest := rfl

structure Pose where
  x : ℝ
  y : ℝ

noncomputable def odoStep (o : ℝ) (p p' : Pose) : ℝ :=
  o + Real.sqrt ((p'.x - p.x) ^ 2 + (p'.y - p.y) ^ 2)

/-- P11-14 (`11-execution.md:23`): "adds the horizontal distance between the
actor's old and new rear-axle positions to `odometer_m`". The odometer never
decreases. -/
theorem odo_mono (o : ℝ) (p p' : Pose) : o ≤ odoStep o p p' :=
  le_add_of_nonneg_right (Real.sqrt_nonneg _)

/-- P11-14 (`11-execution.md:23`): "adds the horizontal distance between the
actor's old and new rear-axle positions to `odometer_m`". It stays the same only
if the position does. -/
theorem odo_eq_iff (o : ℝ) (p p' : Pose) : odoStep o p p' = o ↔ p.x = p'.x ∧ p.y = p'.y := by
  unfold odoStep
  constructor
  · intro h
    have h0 : Real.sqrt ((p'.x - p.x) ^ 2 + (p'.y - p.y) ^ 2) = 0 := by linarith
    rw [Real.sqrt_eq_zero'] at h0
    have hx : (p'.x - p.x) ^ 2 = 0 := by nlinarith [sq_nonneg (p'.x - p.x), sq_nonneg (p'.y - p.y)]
    have hy : (p'.y - p.y) ^ 2 = 0 := by nlinarith [sq_nonneg (p'.x - p.x), sq_nonneg (p'.y - p.y)]
    have hx' := pow_eq_zero_iff (n := 2) (by norm_num) |>.mp hx
    have hy' := pow_eq_zero_iff (n := 2) (by norm_num) |>.mp hy
    constructor <;> linarith
  · rintro ⟨hx, hy⟩
    simp [hx, hy]

/-! ## Evaluation order -/

/-- An actor (one id) or a group (its member ids). -/
structure Entity where
  ids : Finset ℕ
  ne : ids.Nonempty

def Entity.key (e : Entity) : ℕ := e.ids.min' e.ne

/-- P11-24 (`11-execution.md:27`): "actors and groups are evaluated in ascending
order of `actor_id` … A group sorts by its smallest member `actor_id`." For
disjoint entities this order exists. -/
theorem entity_order_exists (es : List Entity)
    (hd : es.Pairwise (fun a b => Disjoint a.ids b.ids)) :
    ∃ l, l.Perm es ∧ l.Pairwise (fun a b => a.key < b.key) := by
  have hne : es.Pairwise (fun a b => a.key ≠ b.key) :=
    hd.imp fun {a b} (h : Disjoint a.ids b.ids) (hk : a.key = b.key) =>
      Finset.disjoint_left.mp h (Finset.min'_mem a.ids a.ne)
        (by rw [show a.ids.min' a.ne = b.ids.min' b.ne from hk]; exact Finset.min'_mem _ _)
  let l : List Entity := es.mergeSort (fun a b => decide (a.key ≤ b.key))
  have hp : l.Perm es := List.mergeSort_perm _ _
  have hs : l.Pairwise (fun a b => decide (a.key ≤ b.key)) :=
    List.pairwise_mergeSort (fun a b c h h' => by simp at *; omega)
      (fun a b => by simp; omega) _
  have hne' : l.Pairwise (fun a b => a.key ≠ b.key) :=
    (hne.perm hp.symm fun {_ _} h => Ne.symm h)
  refine ⟨l, hp, (hs.and hne').imp fun ⟨h, h'⟩ => ?_⟩
  simp at h
  omega

/-- P11-24 (`11-execution.md:27`): "actors and groups are evaluated in ascending
order of `actor_id` … A group sorts by its smallest member `actor_id`." The order
is unique. -/
theorem entity_order_unique (es : List Entity) {l₁ l₂ : List Entity}
    (h₁ : l₁.Perm es) (h₂ : l₂.Perm es)
    (s₁ : l₁.Pairwise (fun a b => a.key < b.key))
    (s₂ : l₂.Pairwise (fun a b => a.key < b.key)) : l₁ = l₂ :=
  List.Perm.eq_of_pairwise (fun _ _ _ _ h h' => absurd (h.trans h') (lt_irrefl _))
    s₁ s₂ (h₁.trans h₂.symm)

/-- Transitive closure of the data edges between `n` calls. -/
structure Chain (n : ℕ) where
  path : Fin n → Fin n → Prop

def Chain.IsDAG {n : ℕ} (c : Chain n) : Prop :=
  (∀ a, ¬ c.path a a) ∧ ∀ a b z, c.path a b → c.path b z → c.path a z

/-- The pairwise rule of `11:27`: `a` runs before `b`. -/
def tieOrder {n : ℕ} (c : Chain n) (a b : Fin n) : Prop :=
  c.path a b ∨ (¬ c.path a b ∧ ¬ c.path b a ∧ a < b)

/-- A chain expression (`12-grammar.md:47-49`) after `fn` substitution and inlining
of named chains. -/
inductive ChainExpr
  /-- One component call. -/
  | call
  /-- `a >> b`. -/
  | seq (a b : ChainExpr)
  /-- `(a + b)`. -/
  | par (a b : ChainExpr)
  /-- `Arbitrate(p, s, via: A())`, the arbiter call written last. -/
  | arb (p s : ChainExpr)

namespace ChainExpr

/-- Number of calls. -/
def size : ChainExpr → ℕ
  | call => 1
  | seq a b => size a + size b
  | par a b => size a + size b
  | arb p s => size p + size s + 1

/-- Calls that receive the pipe input, numbered left to right from `n`. -/
def ins : ChainExpr → ℕ → List ℕ
  | call, n => [n]
  | seq a _, n => ins a n
  | par a b, n => ins a n ++ ins b (n + size a)
  | arb p s, n => ins p n ++ ins s (n + size p)

/-- Calls whose output is the expression's output. -/
def outs : ChainExpr → ℕ → List ℕ
  | call, n => [n]
  | seq a b, n => outs b (n + size a)
  | par a b, n => outs a n ++ outs b (n + size a)
  | arb p s, n => [n + size p + size s]

/-- Data edges: `>>` feeds the outputs of `a` to the inputs of `b`, and the
arbiter reads both operands (`16:75`, `16:77-80`). -/
def edges : ChainExpr → ℕ → List (ℕ × ℕ)
  | call, _ => []
  | seq a b, n => edges a n ++ edges b (n + size a) ++
      (outs a n).flatMap fun x => (ins b (n + size a)).map fun y => (x, y)
  | par a b, n => edges a n ++ edges b (n + size a)
  | arb p s, n => edges p n ++ edges s (n + size p) ++
      (outs p n ++ outs s (n + size p)).map fun x => (x, n + size p + size s)

theorem ins_range : ∀ (e : ChainExpr) (n x : ℕ), x ∈ ins e n → n ≤ x ∧ x < n + size e
  | call, n, x, h => by simp [ins] at h; simp [size, h]
  | seq a b, n, x, h => by
    have := ins_range a n x h; simp only [size]; omega
  | par a b, n, x, h => by
    simp only [ins, List.mem_append] at h
    rcases h with h | h
    · have := ins_range a n x h; simp only [size]; omega
    · have := ins_range b _ x h; simp only [size]; omega
  | arb p s, n, x, h => by
    simp only [ins, List.mem_append] at h
    rcases h with h | h
    · have := ins_range p n x h; simp only [size]; omega
    · have := ins_range s _ x h; simp only [size]; omega

theorem outs_range : ∀ (e : ChainExpr) (n x : ℕ), x ∈ outs e n → n ≤ x ∧ x < n + size e
  | call, n, x, h => by simp [outs] at h; simp [size, h]
  | seq a b, n, x, h => by
    have := outs_range b _ x h; simp only [size]; omega
  | par a b, n, x, h => by
    simp only [outs, List.mem_append] at h
    rcases h with h | h
    · have := outs_range a n x h; simp only [size]; omega
    · have := outs_range b _ x h; simp only [size]; omega
  | arb p s, n, x, h => by
    simp [outs] at h; simp only [size]; omega

/-- Every data edge runs from a call to a later one, within the expression. -/
theorem edges_forward : ∀ (e : ChainExpr) (n x y : ℕ), (x, y) ∈ edges e n →
    n ≤ x ∧ x < y ∧ y < n + size e
  | call, _, _, _, h => by simp [edges] at h
  | seq a b, n, x, y, h => by
    simp only [edges, List.mem_append, List.mem_flatMap, List.mem_map, Prod.mk.injEq] at h
    rcases h with (h | h) | ⟨x', hx, y', hy, rfl, rfl⟩
    · have := edges_forward a n x y h; simp only [size]; omega
    · have := edges_forward b _ x y h; simp only [size]; omega
    · have := outs_range a n _ hx; have := ins_range b _ _ hy; simp only [size]; omega
  | par a b, n, x, y, h => by
    simp only [edges, List.mem_append] at h
    rcases h with h | h
    · have := edges_forward a n x y h; simp only [size]; omega
    · have := edges_forward b _ x y h; simp only [size]; omega
  | arb p s, n, x, y, h => by
    simp only [edges, List.mem_append, List.mem_map, Prod.mk.injEq] at h
    rcases h with (h | h) | ⟨x', hx | hx, rfl, rfl⟩
    · have := edges_forward p n x y h; simp only [size]; omega
    · have := edges_forward s _ x y h; simp only [size]; omega
    · have := outs_range p n _ hx; simp only [size]; omega
    · have := outs_range s _ _ hx; simp only [size]; omega

/-- The data paths between the calls of `e`. -/
def toChain (e : ChainExpr) : Chain (size e) :=
  ⟨fun a b => Relation.TransGen (fun x y => (x, y) ∈ edges e 0) a.val b.val⟩

theorem path_lt' (e : ChainExpr) {x y : ℕ}
    (h : Relation.TransGen (fun x y => (x, y) ∈ edges e 0) x y) : x < y := by
  induction h with
  | single h => exact (edges_forward e 0 _ _ h).2.1
  | tail _ h ih => exact ih.trans (edges_forward e 0 _ _ h).2.1

theorem path_lt (e : ChainExpr) {a b : Fin (size e)} (h : (toChain e).path a b) : a < b :=
  path_lt' e h

/-- The data paths of a chain form a DAG (`01-scope.md:23`). -/
theorem isDAG (e : ChainExpr) : (toChain e).IsDAG :=
  ⟨fun a h => lt_irrefl _ (path_lt e h), fun _ _ _ h h' => Relation.TransGen.trans h h'⟩

/-- The pairwise rule of `11:27` is call order. -/
theorem tieOrder_iff (e : ChainExpr) (a b : Fin (size e)) :
    tieOrder (toChain e) a b ↔ a < b := by
  constructor
  · rintro (h | ⟨_, _, h⟩)
    · exact path_lt e h
    · exact h
  · intro h
    by_cases hab : (toChain e).path a b
    · exact Or.inl hab
    · exact Or.inr ⟨hab, fun hba => absurd (path_lt e hba) (lt_asymm h), h⟩

/-- P11-25 (`11-execution.md:27`): "topological chain order within each actor, with
components that have no data path between them in the left-to-right order of their
calls in the chain expression after `fn` substitution". Read pair by pair, the rule
has exactly one solution, the left-to-right call order, which is topological.
The pairwise rule cannot form a cycle, because `16-static-semantics.md:75` binds
frame ports only as the pipe input or an `Arbitrate` operand, so every data path
runs left to right. -/
theorem chain_order_is_call_order (e : ChainExpr) (l : List (Fin (size e))) :
    (l.Perm (List.finRange (size e)) ∧ l.Pairwise (tieOrder (toChain e))) ↔
      l = List.finRange (size e) := by
  have hiff : ∀ l : List (Fin (size e)),
      l.Pairwise (tieOrder (toChain e)) ↔ l.Pairwise (· < ·) := fun l =>
    ⟨fun h => h.imp fun h => (tieOrder_iff e _ _).mp h,
      fun h => h.imp fun h => (tieOrder_iff e _ _).mpr h⟩
  constructor
  · rintro ⟨hp, hs⟩
    exact List.Perm.eq_of_pairwise (fun _ _ _ _ h h' => absurd (h.trans h') (lt_irrefl _))
      ((hiff l).mp hs) (List.pairwise_lt_finRange _) hp
  · rintro rfl
    exact ⟨List.Perm.refl _, (hiff _).mpr (List.pairwise_lt_finRange _)⟩

end ChainExpr

/-- Group order: component-major, `bind`-minor. -/
def groupOrder {κ : Type*} (cs : List κ) (bs : List ℕ) : List (κ × ℕ) :=
  cs.flatMap fun c => bs.map (c, ·)

def Precedes {β : Type*} (l : List β) (x y : β) : Prop :=
  ∃ i j : ℕ, i < j ∧ l[i]? = some x ∧ l[j]? = some y

theorem groupOrder_getElem? {κ : Type*} (bs : List ℕ) :
    ∀ (cs : List κ) (m : ℕ) (c : κ) (a : ℕ),
      (groupOrder cs bs)[m]? = some (c, a) ↔
        ∃ i j, m = i * bs.length + j ∧ cs[i]? = some c ∧ bs[j]? = some a
  | [], m, c, a => by simp [groupOrder]
  | c0 :: cs, m, c, a => by
    have ih := groupOrder_getElem? bs cs
    have hg : groupOrder (c0 :: cs) bs = bs.map (c0, ·) ++ groupOrder cs bs := rfl
    rw [hg]
    by_cases hm : m < bs.length
    · rw [List.getElem?_append_left (by simpa using hm)]
      simp only [List.getElem?_map, Option.map_eq_some_iff, Prod.mk.injEq]
      constructor
      · rintro ⟨a', ha, rfl, rfl⟩
        exact ⟨0, m, by simp, rfl, ha⟩
      · rintro ⟨i, j, rfl, hi, hj⟩
        have hj' : j < bs.length := (List.getElem?_eq_some_iff.mp hj).1
        rcases i with _ | i
        · simp at hi; exact ⟨a, by simpa using hj, hi, rfl⟩
        · nlinarith
    · push Not at hm
      rw [List.getElem?_append_right (by simpa using hm), List.length_map, ih]
      constructor
      · rintro ⟨i, j, hij, hi, hj⟩
        exact ⟨i + 1, j, by rw [Nat.succ_mul]; omega, hi, hj⟩
      · rintro ⟨i, j, rfl, hi, hj⟩
        have hj' : j < bs.length := (List.getElem?_eq_some_iff.mp hj).1
        rcases i with _ | i
        · omega
        · exact ⟨i, j, by rw [Nat.succ_mul]; omega, hi, hj⟩

theorem lex_lt {B i₁ i₂ j₁ j₂ : ℕ} (h₁ : j₁ < B) (h₂ : j₂ < B) :
    i₁ * B + j₁ < i₂ * B + j₂ ↔ i₁ < i₂ ∨ (i₁ = i₂ ∧ j₁ < j₂) := by
  constructor
  · intro h
    rcases lt_trichotomy i₁ i₂ with hi | rfl | hi
    · exact Or.inl hi
    · exact Or.inr ⟨rfl, by omega⟩
    · have : i₂ * B + B ≤ i₁ * B := by
        rw [← Nat.succ_mul]; exact Nat.mul_le_mul_right _ hi
      omega
  · rintro (hi | ⟨rfl, hj⟩)
    · have : i₁ * B + B ≤ i₂ * B := by
        rw [← Nat.succ_mul]; exact Nat.mul_le_mul_right _ hi
      omega
    · omega

theorem precedes_iff_of_nodup {β : Type*} {l : List β} (hl : l.Nodup) {x y : β}
    {i j : ℕ} (hx : l[i]? = some x) (hy : l[j]? = some y) : Precedes l x y ↔ i < j := by
  constructor
  · rintro ⟨i', j', hlt, hx', hy'⟩
    have hi : i' = i := (List.Nodup.getElem?_inj (List.getElem?_eq_some_iff.mp hx').1 hl).mp (hx'.trans hx.symm)
    have hj : j' = j := (List.Nodup.getElem?_inj (List.getElem?_eq_some_iff.mp hy').1 hl).mp (hy'.trans hy.symm)
    omega
  · intro h; exact ⟨i, j, h, hx, hy⟩

/-- P11-26 (`11-execution.md:27`): "each component's per-actor instances run one
after another in `bind` order". Each instance runs once. -/
theorem groupOrder_nodup {κ : Type*} (cs : List κ) (bs : List ℕ) (hc : cs.Nodup)
    (hb : bs.Nodup) : (groupOrder cs bs).Nodup := by
  unfold groupOrder
  rw [List.nodup_flatMap]
  refine ⟨fun c _ => hb.map fun _ _ h => (Prod.mk.inj h).2, ?_⟩
  refine hc.imp fun {x y} hxy => ?_
  show List.Disjoint _ _
  intro p h1 h2
  simp only [List.mem_map] at h1 h2
  obtain ⟨_, _, rfl⟩ := h1
  obtain ⟨_, _, h⟩ := h2
  exact hxy (congrArg Prod.fst h).symm

/-- P11-26 (`11-execution.md:27`): "within a group, components run in topological
order, and each component's per-actor instances run one after another in `bind`
order before the next component starts." -/
theorem groupOrder_precedes {κ : Type*} (cs : List κ) (bs : List ℕ) (hc : cs.Nodup)
    (hb : bs.Nodup) (c₁ c₂ : κ) (a₁ a₂ : ℕ) (h₁ : c₁ ∈ cs) (h₂ : c₂ ∈ cs) (g₁ : a₁ ∈ bs)
    (g₂ : a₂ ∈ bs) :
    Precedes (groupOrder cs bs) (c₁, a₁) (c₂, a₂) ↔
      Precedes cs c₁ c₂ ∨ (c₁ = c₂ ∧ Precedes bs a₁ a₂) := by
  obtain ⟨i₁, hi₁, rfl⟩ := List.getElem_of_mem h₁
  obtain ⟨i₂, hi₂, rfl⟩ := List.getElem_of_mem h₂
  obtain ⟨j₁, hj₁, rfl⟩ := List.getElem_of_mem g₁
  obtain ⟨j₂, hj₂, rfl⟩ := List.getElem_of_mem g₂
  have e₁ := (groupOrder_getElem? bs cs (i₁ * bs.length + j₁) _ _).mpr
    ⟨i₁, j₁, rfl, List.getElem?_eq_getElem hi₁, List.getElem?_eq_getElem hj₁⟩
  have e₂ := (groupOrder_getElem? bs cs (i₂ * bs.length + j₂) _ _).mpr
    ⟨i₂, j₂, rfl, List.getElem?_eq_getElem hi₂, List.getElem?_eq_getElem hj₂⟩
  have hgo := groupOrder_nodup cs bs hc hb
  have hceq : cs[i₁] = cs[i₂] ↔ i₁ = i₂ := ⟨fun h =>
    (List.Nodup.getElem?_inj hi₁ hc).mp
      (by simp [List.getElem?_eq_getElem hi₁, List.getElem?_eq_getElem hi₂, h]),
    fun h => by subst h; rfl⟩
  rw [precedes_iff_of_nodup hgo e₁ e₂, lex_lt hj₁ hj₂,
    precedes_iff_of_nodup hc (List.getElem?_eq_getElem hi₁) (List.getElem?_eq_getElem hi₂),
    precedes_iff_of_nodup hb (List.getElem?_eq_getElem hj₁) (List.getElem?_eq_getElem hj₂),
    hceq]

/-- An entity's Phase 2 block. By its type it reads only the snapshot `s` and its
own slot, and writes only its own slot (`11:27`). -/
def block {E S β : Type*} [DecidableEq E] (f : E → S → β → β) (s : S) (st : E → β) (e : E) :
    E → β :=
  Function.update st e (f e s (st e))

/-- P11-27 (`11-execution.md:27`): "No component reads another entity's output
within a tick, so this order never delays data." An entity's result depends only
on its own slot. -/
theorem block_reads_own {E S β : Type*} [DecidableEq E] (f : E → S → β → β) (s : S) (e : E)
    (st st' : E → β) (h : st e = st' e) : block f s st e e = block f s st' e e := by
  simp [block, h]

/-- P11-27 (`11-execution.md:27`): "Phase 2 components only read Phase 1
`SliceBuffer` snapshots from X(t) and write to actor-local checkpoint buffers".
A block leaves every other entity's slot alone. -/
theorem block_writes_own {E S β : Type*} [DecidableEq E] (f : E → S → β → β) (s : S)
    (st : E → β) (e e' : E) (h : e' ≠ e) : block f s st e e' = st e' :=
  Function.update_of_ne h _ _

/-- P11-28 (`11-execution.md:27`): "Phase 2 is data-race-free and parallelizable
across actors." Blocks of distinct entities commute. -/
theorem block_comm {E S β : Type*} [DecidableEq E] (f : E → S → β → β) (s : S) (st : E → β)
    {e e' : E} (h : e ≠ e') :
    block f s (block f s st e) e' = block f s (block f s st e') e := by
  unfold block
  rw [Function.update_of_ne h.symm, Function.update_of_ne h]
  exact Function.update_comm h.symm _ _ _ |>.symm

/-- P11-28 (`11-execution.md:27`): "Phase 2 is data-race-free and parallelizable
across actors." Every order of the blocks gives the same state. -/
theorem phase_perm {E S β : Type*} [DecidableEq E] (f : E → S → β → β) (s : S) (st : E → β)
    {l l' : List E} (h : l.Perm l') : l.foldl (block f s) st = l'.foldl (block f s) st :=
  h.foldl_eq' (fun x _ y _ z => by
    by_cases hxy : x = y
    · subst hxy; rfl
    · exact block_comm f s z hxy) st

end Driveline.Schedule
