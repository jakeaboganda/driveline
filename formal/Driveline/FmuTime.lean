import Driveline.Schedule
import Driveline.Lifecycle

/-!
# FMU time and calls (spec §7)

A model of the Times rule (`docs/spec/07-fmu-packaging.md:36`), the step procedure
(`07:43-46`), and the FMI calls of the lifecycle mapping (`07:57-63`).

Rounding is abstract: `rnd` turns a nanosecond count over 10^9 into binary64, and
`fl` rounds a sum. IEEE 754 addition returns the correctly rounded exact sum, so
`fl (a + b)` is binary64 `a + b` when `fl` is round-to-nearest-even. The
contiguity theorems hold for every `rnd` and `fl`; `rnd = fl = id` gives exact
arithmetic.
-/

namespace Driveline.FmuTime

open Driveline.Schedule

structure Times where
  rnd : ℚ → ℚ
  fl : ℚ → ℚ

def startTime (T : Times) (tNs : ℕ) : ℚ := T.rnd ((tNs : ℚ) / 10 ^ 9)

def stepSize (T : Times) (hNs : ℕ) : ℚ := T.rnd ((hNs : ℚ) / 10 ^ 9)

/-- The `j`-th `currentCommunicationPoint` after an initialization at `tNs`. -/
def point (T : Times) (tNs hNs : ℕ) : ℕ → ℚ
  | 0 => startTime T tNs
  | j + 1 => T.fl (point T tNs hNs j + stepSize T hNs)

/-- P07-08 (`07-fmu-packaging.md:36`): "The first `currentCommunicationPoint` after
each initialization, including a re-trim after `fmi3Reset`, is that
initialization's `startTime`". -/
theorem point_zero (T : Times) (t h : ℕ) : point T t h 0 = startTime T t := rfl

theorem point_succ (T : Times) (t h j : ℕ) :
    point T t h (j + 1) = T.fl (point T t h j + stepSize T h) := rfl

/-- P07-08 (`07-fmu-packaging.md:36`): "`startTime` and `communicationStepSize` are
the binary64 values nearest to their nanosecond counts divided by 10^9". Without
rounding the points are the step times. -/
theorem point_exact (t h : ℕ) :
    ∀ j : ℕ, point ⟨id, id⟩ t h j = ((t + j * h : ℕ) : ℚ) / 10 ^ 9
  | 0 => by simp [point, startTime]
  | j + 1 => by
    rw [point_succ, point_exact t h j]
    simp only [stepSize, id]
    push_cast
    ring

/-- P07-09 (`07-fmu-packaging.md:43`): "It calls `fmi3DoStep` with the
`currentCommunicationPoint` of tick t by the Times rule of §7 and
`communicationStepSize` = h." From a scheduled tick `k0`, the scheduled ticks are
exactly `k0 + j · k_div`, so the `j`-th one gets point `j`. -/
theorem doStep_ticks (d : ℕ+) (k0 : Tick) (h0 : runs d k0) (k : Tick) :
    (runs d k ∧ k0 ≤ k) ↔ ∃ j : ℕ, k = k0 + j * d := by
  have hk0 := (runs_iff_dvd d k0).mp h0
  constructor
  · rintro ⟨hk, hle⟩
    obtain ⟨m, hm⟩ := Nat.dvd_sub ((runs_iff_dvd d k).mp hk) hk0
    refine ⟨m, ?_⟩
    have h := Nat.sub_add_cancel hle
    rw [hm] at h
    rw [← h]
    ring
  · rintro ⟨j, rfl⟩
    exact ⟨(runs_iff_dvd d _).mpr (Nat.dvd_add hk0 (Nat.dvd_mul_left _ _)),
      Nat.le_add_right _ _⟩

/-- P07-09 (`07-fmu-packaging.md:43`): "`currentCommunicationPoint` of tick t by the
Times rule". Step indices map one to one, in order, onto scheduled ticks. -/
theorem doStep_index_strictMono (d : ℕ+) (k0 : Tick) :
    StrictMono (fun j : ℕ => k0 + j * (d : ℕ)) := fun _ _ h =>
  Nat.add_lt_add_left (Nat.mul_lt_mul_of_pos_right h d.pos) _

/-- P07-09 (`07-fmu-packaging.md:43`): "`communicationStepSize` = h." The `j`-th
scheduled tick lies `j` periods after the first. -/
theorem doStep_time (dt d : ℕ+) (k0 j : ℕ) :
    tickTime dt (k0 + j * d) = tickTime dt k0 + j * stepDt d dt := by
  simp only [tickTime, stepDt]
  ring

/-- FMI 3.0 contiguity of a call sequence `(cp j, h j)`: each
`currentCommunicationPoint` is the previous one plus the previous
`communicationStepSize` in binary64, `cp (j + 1) = fl (cp j + h j)`. -/
def Contiguous (T : Times) (cp h : ℕ → ℚ) : Prop := ∀ j, cp (j + 1) = T.fl (cp j + h j)

/-- The runtime's `fmi3DoStep` arguments `(currentCommunicationPoint,
communicationStepSize)` on tick `kt`, for a component with divisor `d` initialized
for tick `k`. Tick `kt` is the `(kt - tFirst d k) / d`-th scheduled tick from
`tFirst d k`, and the `j`-th one gets `point j` and the step size of `h`. -/
def doStepCall (T : Times) (dt d : ℕ+) (k kt : Tick) : ℚ × ℚ :=
  (point T (tickTime dt (tFirst d k)) (stepDt d dt) ((kt - tFirst d k) / d),
    stepSize T (stepDt d dt))

theorem tFirst_runs (d : ℕ+) (k : Tick) : runs d (tFirst d k) :=
  (runs_iff_dvd d _).mpr (Nat.dvd_mul_right _ _)

/-- P07-09 (`07-fmu-packaging.md:43`): "It calls `fmi3DoStep` with the
`currentCommunicationPoint` of tick t by the Times rule of §7 and
`communicationStepSize` = h." The `j`-th scheduled tick from `tFirst` is
scheduled, lies `j` periods of `h = stepDt d dt` after `tFirst`, and gets point
`j` and step size `h`. -/
theorem doStep_call (T : Times) (dt d : ℕ+) (k j : ℕ) :
    runs d (tFirst d k + j * d) ∧
      tickTime dt (tFirst d k + j * d) = tickTime dt (tFirst d k) + j * stepDt d dt ∧
      doStepCall T dt d k (tFirst d k + j * d) =
        (point T (tickTime dt (tFirst d k)) (stepDt d dt) j, stepSize T (stepDt d dt)) := by
  refine ⟨(runs_iff_dvd d _).mpr
    (Nat.dvd_add ((runs_iff_dvd d _).mp (tFirst_runs d k)) (Nat.dvd_mul_left _ _)),
    doStep_time dt d _ j, ?_⟩
  simp [doStepCall, Nat.mul_div_cancel j d.pos]

/-- P07-08 (`07-fmu-packaging.md:36`): "The first `currentCommunicationPoint` after
each initialization … is that initialization's `startTime`, and each later one is
the previous one plus the previous `communicationStepSize` in binary64, so the
points are contiguous as FMI 3.0 requires." The runtime's calls on the scheduled
ticks from `tFirst` start at `startTime` and are contiguous. -/
theorem calls_contiguous (T : Times) (dt d : ℕ+) (k : Tick) :
    (doStepCall T dt d k (tFirst d k)).1 = startTime T (tickTime dt (tFirst d k)) ∧
      Contiguous T (fun j => (doStepCall T dt d k (tFirst d k + j * d)).1)
        (fun j => (doStepCall T dt d k (tFirst d k + j * d)).2) := by
  refine ⟨by simp [doStepCall, point], fun j => ?_⟩
  simp only [(doStep_call T dt d k _).2.2]
  rfl

inductive FmiStatus
  | ok
  | warning
  | discard
  | error
  | fatal
  deriving DecidableEq, Repr

def doStepOk (s : FmiStatus) (terminateSimulation earlyReturn : Bool) : Bool :=
  (s == .ok || s == .warning) && !terminateSimulation && !earlyReturn

/-- P07-10 (`07-fmu-packaging.md:44`): "An FMI return of `fmi3Warning` counts as
`fmi3OK`. Any worse return, or a step that sets `terminateSimulation` or
`earlyReturn`, is `DL_STATUS_ERR_FMU`". -/
theorem doStepOk_iff (s : FmiStatus) (ts er : Bool) :
    doStepOk s ts er = true ↔ (s = .ok ∨ s = .warning) ∧ ts = false ∧ er = false := by
  cases s <;> cases ts <;> cases er <;> decide

/-- A discrete-time FMU: state update over one step and output map. -/
structure Fmu (X U Y : Type*) where
  F : X → U → ℚ → ℚ → X
  H : X → Y

variable {X U Y : Type*}

/-- State after `j` steps, with inputs `u j` held over step `j`. -/
def Fmu.state (m : Fmu X U Y) (x0 : X) (u : ℕ → U) (p : ℕ → ℚ) (h : ℚ) : ℕ → X
  | 0 => x0
  | j + 1 => m.F (Fmu.state m x0 u p h j) (u j) (p j) h

/-- Output read after the `j`-th `fmi3DoStep`: the FMU at `p j + h`. -/
def Fmu.out (m : Fmu X U Y) (x0 : X) (u : ℕ → U) (p : ℕ → ℚ) (h : ℚ) (j : ℕ) : Y :=
  m.H (m.state x0 u p h (j + 1))

theorem Fmu.state_causal (m : Fmu X U Y) (x0 : X) (p : ℕ → ℚ) (h : ℚ) (u u' : ℕ → U) :
    ∀ j, (∀ i < j, u i = u' i) → m.state x0 u p h j = m.state x0 u' p h j
  | 0, _ => rfl
  | j + 1, hu => by
    simp only [Fmu.state]
    rw [Fmu.state_causal m x0 p h u u' j (fun i hi => hu i (by omega)), hu j (by omega)]

/-- P07-11 (`07-fmu-packaging.md:46`): "The outputs read in step 3 describe the FMU
at t + h computed from inputs held over [t, t + h)." The output after step `j` is
computed from the inputs held over steps `0 … j` only: inputs held over later
steps do not change it. -/
theorem out_causal (m : Fmu X U Y) (x0 : X) (p : ℕ → ℚ) (h : ℚ) (u u' : ℕ → U) (j : ℕ)
    (hu : ∀ i ≤ j, u i = u' i) : m.out x0 u p h j = m.out x0 u' p h j := by
  unfold Fmu.out
  rw [m.state_causal x0 p h u u' (j + 1) (fun i hi => hu i (by omega))]

theorem ceil_mul_bounds (n k : ℕ) (hn : 0 < n) :
    k ≤ n * ((k + n - 1) / n) ∧ n * ((k + n - 1) / n) < k + n := by
  have h1 := Nat.div_add_mod (k + n - 1) n
  have h2 := Nat.mod_lt (k + n - 1) hn
  generalize (k + n - 1) / n = q at *
  generalize (k + n - 1) % n = r at *
  generalize n * q = a at *
  omega

theorem ceil_mul_least (n k m : ℕ) (hn : 0 < n) (hk : k ≤ n * m) :
    n * ((k + n - 1) / n) ≤ n * m := by
  apply Nat.mul_le_mul_left
  have : (k + n - 1) / n < m + 1 := by
    rw [Nat.div_lt_iff_lt_mul hn, Nat.succ_mul, mul_comm m n]
    generalize n * m = b at *
    omega
  omega

/-- P07-12 (`07-fmu-packaging.md:59`): "Initialize at t_first, the earliest tick time
t' ≥ t at which the component is scheduled (§11)". -/
theorem tFirst_isLeast (d : ℕ+) (k : Tick) : IsLeast {j | k ≤ j ∧ runs d j} (tFirst d k) := by
  refine ⟨⟨(ceil_mul_bounds d k d.pos).1, (runs_iff_dvd d _).mpr (Nat.dvd_mul_right _ _)⟩, ?_⟩
  rintro j ⟨hkj, hj⟩
  obtain ⟨m, rfl⟩ := (runs_iff_dvd d j).mp hj
  exact ceil_mul_least d k m d.pos hkj

/-- P07-12 (`07-fmu-packaging.md:59`): "the earliest tick time t' ≥ t at which the
component is scheduled". It comes less than one period after `t`. -/
theorem tFirst_lt (d : ℕ+) (k : Tick) : tFirst d k < k + d :=
  (ceil_mul_bounds d k d.pos).2

/-- P07-12 (`07-fmu-packaging.md:57`, `:59`): "`dl_enter_cold_init` | Initialize at
t = 0." The splice rule agrees at t = 0. -/
theorem tFirst_zero (d : ℕ+) : tFirst d 0 = 0 := by
  simp [tFirst, Nat.div_eq_of_lt (Nat.sub_lt d.pos Nat.one_pos)]

/-- Whether some FMI call on the instance returned `fmi3Error` or `fmi3Fatal`. -/
structure FmiHistory where
  sawError : Bool
  sawFatal : Bool

/-- FMI Step Mode by the `07:57-61` mapping: only after `dl_exit_init_mode`. -/
def fmiStepMode : Lifecycle.State → Bool
  | .stepMode => true
  | _ => false

inductive FmiCall
  | terminate
  | freeInstance
  deriving DecidableEq, Repr

def termCalls (s : Lifecycle.State) (h : FmiHistory) : List FmiCall :=
  if fmiStepMode s && !h.sawError && !h.sawFatal then [.terminate] else []

def freeCalls (h : FmiHistory) : List FmiCall := if h.sawFatal then [] else [.freeInstance]

/-- P07-14 (`07-fmu-packaging.md:62-63`): "`fmi3Terminate` if the FMU is in FMI Step
Mode and no FMI call on it has returned `fmi3Error` or `fmi3Fatal`. Otherwise no
FMI call." / "`fmi3FreeInstance`, unless an FMI call on the instance has returned
`fmi3Fatal`, in which case no FMI call." -/
theorem fatal_no_calls (s : Lifecycle.State) (h : FmiHistory) (hf : h.sawFatal = true) :
    termCalls s h ++ freeCalls h = [] := by
  simp [termCalls, freeCalls, hf]

/-- P07-14 (`07-fmu-packaging.md:62-63`): "`fmi3Terminate` if … no FMI call on it has
returned `fmi3Error` or `fmi3Fatal`" / "`fmi3FreeInstance`, unless … `fmi3Fatal`". -/
theorem error_only_free (s : Lifecycle.State) (h : FmiHistory) (he : h.sawError = true)
    (hf : h.sawFatal = false) : termCalls s h ++ freeCalls h = [.freeInstance] := by
  simp [termCalls, freeCalls, he, hf]

/-- P07-14 (`07-fmu-packaging.md:62`): "`fmi3Terminate` if the FMU is in FMI Step
Mode". -/
theorem terminate_only_stepMode (s : Lifecycle.State) (h : FmiHistory)
    (ht : FmiCall.terminate ∈ termCalls s h) : s = .stepMode := by
  cases s <;> simp_all [termCalls, fmiStepMode]

/-- P07-14 (`07-fmu-packaging.md:63`): "`fmi3FreeInstance`, unless an FMI call on the
instance has returned `fmi3Fatal`". -/
theorem freed_unless_fatal (h : FmiHistory) (hf : h.sawFatal = false) :
    FmiCall.freeInstance ∈ freeCalls h := by
  simp [freeCalls, hf]

end Driveline.FmuTime
