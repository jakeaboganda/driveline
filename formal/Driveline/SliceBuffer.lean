import Mathlib.Tactic
import Mathlib.Data.Nat.ModEq
import Driveline.Angles

/-!
# SliceBuffer queries (spec §4.2)

The timestamped ring buffer of `docs/spec/04-perception.md:18-41`: the port view
(04:19), the timestamp invariant (04:21), the queries `latest`, `buffer[k]`,
`rate_of`, and `at` (04:23-41), the per-field interpolation classes, and the
in-process ring formula of `abi/driveline_abi.h:162-163`.

A buffer is a list, newest first, so `b[0]` is s[0] and `b.length` is `count`.
Float64 fields are real numbers. `t_ns` is a natural number (uint64) and
`t_query` an integer (a signed `Time`).
-/

noncomputable section

namespace Driveline.SliceBuffer

/-! ## Buffers and views (04:19-21) -/

structure Entry (α : Type) where
  t : ℕ          -- t_ns
  data : α

/-- Newest first: `b[0]` is s[0]; `b.length` is `count`. -/
abbrev Buffer (α : Type) := List (Entry α)

variable {α : Type}

/-- 04:21, plus count ≥ 1 (04:27). -/
def Valid (b : Buffer α) : Prop := b ≠ [] ∧ (b.map Entry.t).Pairwise (· > ·)

/-- The port view of 04:19: the newest `Nc` samples. -/
def view (b : Buffer α) (Nc : ℕ) : Buffer α := b.take Nc

/-- A push into a ring of capacity `N`. -/
def push (N : ℕ) (e : Entry α) (b : Buffer α) : Buffer α := (e :: b).take N

/-- The ring slot of entry k (driveline_abi.h:162-163). -/
def slot (head cap k : ℕ) : ℕ := (head + cap - k) % cap

/-- The compile-time bounds check of 04:26 for a constant index. -/
def acceptConstIndex (Nc k : ℕ) : Bool := decide (k < Nc)

/-- `buffer[k]` with the early-tick clamp (04:27). -/
def get (b : Buffer α) (k : ℕ) : Option (Entry α) := b[min k (b.length - 1)]?

/-- `buffer.latest()` (04:24). -/
def latest (b : Buffer α) : Option (Entry α) := get b 0

/-! ## `rate_of` (04:28-30) -/

structure Rate where
  value : ℝ
  valid : Bool

def rateM (b : Buffer α) (k : ℕ) : ℕ := min k (b.length - 1)
def tAt (b : Buffer α) (i : ℕ) : ℕ := (b[i]?.map Entry.t).getD 0
def rateDenom (b : Buffer α) (k : ℕ) : ℕ := tAt b 0 - tAt b (rateM b k)

/-- 04:28-30. `f` reads the field, `isAngle` is its class, and `dep` is its dependency
condition (`fun _ _ => true` if it has none). -/
def rateOf (f : α → ℝ) (isAngle : Bool) (dep : α → α → Bool)
    (b : Buffer α) (k : ℕ) : Rate :=
  match b[0]?, b[rateM b k]? with
  | some s0, some sm =>
    if b.length < 2 ∨ dep s0.data sm.data = false then ⟨0, false⟩ else
      let d := f s0.data - f sm.data
      ⟨(if isAngle then Angles.wrap d else d) / ((rateDenom b k : ℝ) / 10 ^ 9), true⟩
  | _, _ => ⟨0, false⟩

/-! ## `at` (04:31-35) -/

inductive Mode | floor | interpolate

def floorIdx (b : Buffer α) (q : ℤ) : Option ℕ := b.findIdx? fun e => decide ((e.t : ℤ) ≤ q)

/-- α of 04:35; `o` = s[k+1], `n` = s[k]. -/
def alpha (q : ℤ) (o n : Entry α) : ℝ :=
  ((q - o.t : ℤ) : ℝ) / (((n.t : ℤ) - o.t : ℤ) : ℝ)

/-- 04:31-35. `mix older newer w` interpolates the payload. -/
def atQ (mix : α → α → ℝ → α) (m : Mode) (b : Buffer α) (q : ℤ) : Option (Entry α) :=
  match b.head?, b.getLast? with
  | some s0, some sl =>
    if (s0.t : ℤ) ≤ q then some s0
    else if q ≤ (sl.t : ℤ) then some sl
    else match m, floorIdx b q with
      | .floor, some j => b[j]?
      | .interpolate, some (k + 1) =>
        match b[k]?, b[k + 1]? with
        | some n, some o => some ⟨q.toNat, mix o.data n.data (alpha q o n)⟩
        | _, _ => none
      | _, _ => none
  | _, _ => none

/-! ## Interpolation classes (04:36-39) -/

inductive Cls | linear | angle | hold deriving DecidableEq

def lerp (w vo vn : ℝ) : ℝ := (1 - w) * vo + w * vn
def angleInterp (w vo vn : ℝ) : ℝ := Angles.wrap (vo + w * Angles.wrap (vn - vo))
/-- One float64 field; `ok` is its dependency condition (04:39). -/
def interpReal (c : Cls) (ok : Bool) (w vo vn : ℝ) : ℝ :=
  if ok then (match c with | .linear => lerp w vo vn | .angle => angleInterp w vo vn | .hold => vo)
  else vo

/-! ## Helper lemmas -/

section Helpers

variable {b : Buffer α}

theorem Valid.ne_nil (hb : Valid b) : b ≠ [] := hb.1

theorem Valid.length_pos (hb : Valid b) : 0 < b.length := List.length_pos_iff.mpr hb.1

/-- Strict decrease by index. -/
theorem Valid.t_lt (hb : Valid b) {i j : ℕ} (hij : i < j) (hj : j < b.length) :
    b[j].t < b[i].t := by
  have h := List.pairwise_iff_getElem.mp hb.2 i j (by simp; omega) (by simpa using hj) hij
  simpa using h

theorem Valid.t_le (hb : Valid b) {i j : ℕ} (hij : i ≤ j) (hj : j < b.length) :
    b[j].t ≤ b[i].t := by
  rcases hij.lt_or_eq with h | rfl
  · exact (hb.t_lt h hj).le
  · exact le_rfl

theorem tAt_of_lt {i : ℕ} (h : i < b.length) : tAt b i = b[i].t := by
  simp [tAt, List.getElem?_eq_getElem h]

theorem head_eq {s0 : Entry α} (h0 : b.head? = some s0) : ∃ h : 0 < b.length, b[0] = s0 := by
  rw [List.head?_eq_getElem?] at h0
  rcases List.getElem?_eq_some_iff.mp h0 with ⟨h, he⟩
  exact ⟨h, he⟩

theorem last_eq {sl : Entry α} (hl : b.getLast? = some sl) :
    ∃ h : b.length - 1 < b.length, b[b.length - 1] = sl := by
  rw [List.getLast?_eq_getElem?] at hl
  rcases List.getElem?_eq_some_iff.mp hl with ⟨h, he⟩
  exact ⟨h, he⟩

/-- In the interior of the buffer, `floorIdx` finds the bracket. -/
theorem floor_interior (hb : Valid b) {s0 sl : Entry α} (h0 : b.head? = some s0)
    (hl : b.getLast? = some sl) {q : ℤ} (hlo : (sl.t : ℤ) < q) (hhi : q < s0.t) :
    ∃ k, ∃ hk : k + 1 < b.length, floorIdx b q = some (k + 1) ∧
      (b[k + 1].t : ℤ) ≤ q ∧ q < b[k].t := by
  obtain ⟨h0l, rfl⟩ := head_eq h0
  obtain ⟨hll, rfl⟩ := last_eq hl
  have hsome : (floorIdx b q).isSome := by
    rw [floorIdx, List.findIdx?_isSome, List.any_eq_true]
    exact ⟨_, List.getElem_mem hll, by simpa using hlo.le⟩
  obtain ⟨i, hi⟩ := Option.isSome_iff_exists.mp hsome
  obtain ⟨hil, hpi, hpj⟩ := List.findIdx?_eq_some_iff_getElem.mp hi
  cases i with
  | zero => simp at hpi; omega
  | succ k =>
    refine ⟨k, hil, hi, by simpa using hpi, ?_⟩
    have := hpj k (by omega)
    simp at this
    exact this

/-- `floorIdx` characterized when some sample is at or before the query. -/
theorem floor_spec (hb : Valid b) {q : ℤ} (j : ℕ) (hj : floorIdx b q = some j) :
    ∃ h : j < b.length, (b[j].t : ℤ) ≤ q ∧ ∀ i (hi : i < j), q < (b[i]'(by omega)).t := by
  obtain ⟨hjl, hpj, hpi⟩ := List.findIdx?_eq_some_iff_getElem.mp hj
  refine ⟨hjl, by simpa using hpj, fun i hi => ?_⟩
  have := hpi i hi
  simp at this
  exact this

end Helpers

section Theorems

variable {b : Buffer α} {N Nc k : ℕ} {q : ℤ} (mix : α → α → ℝ → α) (m : Mode)

/-! ## Views and pushes (04:19-27) -/

/-- P04-03: “A sensor with capacity N_s can bind to any component input port expecting
`SliceBuffer<T, N_c>` provided N_s ≥ N_c. … `count` ≤ N_c, holding the newest
min(count_s, N_c) samples” (04-perception.md:19). -/
theorem view_spec (b : Buffer α) (Nc : ℕ) :
    (view b Nc).length = min b.length Nc ∧ (view b Nc).length ≤ Nc ∧
      ∀ i < Nc, (view b Nc)[i]? = b[i]? := by
  refine ⟨by simp [view, min_comm], by simp [view], fun i hi => ?_⟩
  simp [view, List.getElem?_take, hi]

/-- P04-03: a port view of a sensor of capacity N_s ≥ N_c is the view of the full
history (04-perception.md:19). -/
theorem view_of_sensor {Ns Nc : ℕ} (h : Nc ≤ Ns) (b : Buffer α) :
    view (view b Ns) Nc = view b Nc := by
  simp [view, List.take_take, min_eq_left h]

theorem valid_take (hb : Valid b) (hN : 1 ≤ N) : Valid (b.take N) := by
  refine ⟨?_, ?_⟩
  · obtain ⟨x, r, rfl⟩ := List.exists_cons_of_ne_nil hb.1
    obtain ⟨n, rfl⟩ : ∃ n, N = n + 1 := ⟨N - 1, by omega⟩
    simp
  · rw [List.map_take]
    exact hb.2.sublist (List.take_sublist _ _)

/-- P04-04: “Timestamps in a buffer strictly decrease from s[0] to s[count-1]. The
runtime never pushes two samples with the same `t_ns`.” (04-perception.md:21) -/
theorem push_valid (hN : 1 ≤ N) (e : Entry α) (hb : Valid b ∨ b = [])
    (hnew : ∀ s ∈ b.head?, s.t < e.t) : Valid (push N e b) := by
  apply valid_take _ hN
  refine ⟨List.cons_ne_nil _ _, ?_⟩
  rcases hb with hb | rfl
  · obtain ⟨x, r, rfl⟩ := List.exists_cons_of_ne_nil hb.1
    have hx : x.t < e.t := hnew x (by simp)
    have h2 := hb.2
    simp only [List.map_cons, List.pairwise_cons] at h2 ⊢
    refine ⟨?_, h2⟩
    intro a ha
    simp only [List.mem_cons] at ha
    rcases ha with rfl | ha
    · exact hx
    · exact lt_trans (h2.1 a ha) hx
  · simp

/-- P04-04: a port view keeps the timestamp invariant (04-perception.md:21). -/
theorem view_valid (hb : Valid b) (hN : 1 ≤ Nc) : Valid (view b Nc) := valid_take hb hN

/-- P04-04: the same-`t_ns` rule is necessary (04-perception.md:21). -/
theorem push_same_t_invalid (hN : 2 ≤ N) (s : Entry α) (r : Buffer α) (x : α) :
    ¬ Valid (push N ⟨s.t, x⟩ (s :: r)) := by
  obtain ⟨n, rfl⟩ : ∃ n, N = n + 2 := ⟨N - 2, by omega⟩
  simp [push, Valid]

/-- P04-05: “Guaranteed valid from t = 0 because cold initialization Pass 1 performs the
Tick 0 sensor projection” (04:24); “`buffer.count` is the number of valid samples, from
1 to N_c” (04-perception.md:27). -/
theorem push_count (hN : 1 ≤ N) (e : Entry α) (b : Buffer α) :
    1 ≤ (push N e b).length ∧ (push N e b).length ≤ N := by
  simp [push]
  omega

/-- P04-05: a port view of a nonempty buffer has 1 to N_c samples (04-perception.md:27). -/
theorem view_count (hb : b ≠ []) (hN : 1 ≤ Nc) :
    1 ≤ (view b Nc).length ∧ (view b Nc).length ≤ Nc := by
  have := List.length_pos_iff.mpr hb
  simp [view]
  omega

/-! ## `buffer[k]` (04:24-27) -/

/-- P04-06: “If k is a compile-time constant and k ≥ N_c, compilation fails”
(04-perception.md:26). -/
theorem accept_iff (Nc k : ℕ) : acceptConstIndex Nc k = true ↔ k < Nc := by
  simp [acceptConstIndex]

/-- P04-06: an accepted constant index on a full buffer is not clamped
(04-perception.md:26-27). -/
theorem accepted_unclamped (h : acceptConstIndex Nc k = true) (hfull : b.length = Nc) :
    get b k = b[k]? := by
  rw [accept_iff] at h
  simp [get, show min k (b.length - 1) = k by omega]

/-- P04-07: “Before k+1 samples have been recorded …, `buffer[k]` returns the oldest
available sample `buffer[count - 1]`” (04-perception.md:27); with count ≥ 1 the access is
in bounds. -/
theorem get_isSome (hb : b ≠ []) (k : ℕ) : (get b k).isSome := by
  have := List.length_pos_iff.mpr hb
  simp [get]
  omega

/-- P04-07: an index below `count` is not clamped (04-perception.md:27). -/
theorem get_lt (h : k < b.length) : get b k = b[k]? := by
  simp [get, show min k (b.length - 1) = k by omega]

/-- P04-07: “`buffer[k]` returns the oldest available sample `buffer[count - 1]`”
(04-perception.md:27). -/
theorem get_clamp (h : b.length ≤ k) : get b k = b.getLast? := by
  simp [get, List.getLast?_eq_getElem?, show min k (b.length - 1) = b.length - 1 by omega]

/-- P04-07: “`buffer.latest()`: Equivalent to `buffer[0]`” (04-perception.md:24). -/
theorem latest_eq_head (b : Buffer α) : latest b = b.head? := by
  simp [latest, get, List.head?_eq_getElem?]

/-! ## `rate_of` (04:28-30) -/

/-- P04-09: “The timestamp invariant makes the denominator positive whenever count ≥ 2”
(04-perception.md:30), with “m = min(k, count-1)” (04:28) and “`window` must be a constant
`Int` of at least 1” (16-static-semantics.md:69). -/
theorem rate_of_denom_pos (hb : Valid b) (h2 : 2 ≤ b.length) (hk : 1 ≤ k) :
    1 ≤ rateM b k ∧ 0 < rateDenom b k := by
  have hm1 : 1 ≤ rateM b k := by simp [rateM]; omega
  have hml : rateM b k < b.length := by simp [rateM]; omega
  refine ⟨hm1, ?_⟩
  rw [rateDenom, tAt_of_lt (by omega), tAt_of_lt hml]
  have := hb.t_lt (i := 0) (by omega) hml
  omega

/-- P04-09: a valid rate has a positive denominator (04-perception.md:29-30, 16:69). -/
theorem rate_of_valid_denom_pos (f : α → ℝ) (isAngle : Bool) (dep : α → α → Bool)
    (hb : Valid b) (hk : 1 ≤ k) (hv : (rateOf f isAngle dep b k).valid = true) :
    0 < rateDenom b k := by
  have h2 : 2 ≤ b.length := by
    by_contra h
    revert hv
    unfold rateOf
    split
    · simp [show b.length < 2 by omega]
    · simp
  exact (rate_of_denom_pos hb h2 hk).2

/-- P04-42: “{0.0, false} if count < 2” (04-perception.md:29). -/
theorem rate_of_count_lt (f : α → ℝ) (isAngle : Bool) (dep : α → α → Bool) (k : ℕ)
    (h : b.length < 2) : rateOf f isAngle dep b k = ⟨0, false⟩ := by
  unfold rateOf
  split <;> simp [h]

/-- P04-43: “`valid` is also false if the dependency condition of f (§4.3) fails between
s[0] and s[m] (only these two samples are compared)”; “Whenever `valid` is false, `value`
is 0.0” (04-perception.md:30). -/
theorem rate_of_dep_fail (f : α → ℝ) (isAngle : Bool) (dep : α → α → Bool) (k : ℕ)
    {s0 sm : Entry α} (h0 : b[0]? = some s0) (hm : b[rateM b k]? = some sm)
    (hd : dep s0.data sm.data = false) : rateOf f isAngle dep b k = ⟨0, false⟩ := by
  simp [rateOf, h0, hm, hd]

/-- P04-44: “Whenever `valid` is false, `value` is 0.0” (04-perception.md:30). -/
theorem rate_of_invalid_value (f : α → ℝ) (isAngle : Bool) (dep : α → α → Bool) (k : ℕ)
    (h : (rateOf f isAngle dep b k).valid = false) : (rateOf f isAngle dep b k).value = 0 := by
  revert h
  unfold rateOf
  split
  · split <;> simp
  · simp

/-- P04-45: “{(s[0].f − s[m].f)/(s[0].t − s[m].t), true} otherwise”; “The denominator is
(s[0].t_ns − s[m].t_ns)/10^9”; “For an `ANGLE` field, the difference s[0].f − s[m].f is
wrapped to (−π, π]” (04-perception.md:29-30). -/
theorem rate_of_value (f : α → ℝ) (isAngle : Bool) (dep : α → α → Bool) (k : ℕ)
    (h : (rateOf f isAngle dep b k).valid = true) :
    ∃ s0 sm : Entry α, b[0]? = some s0 ∧ b[rateM b k]? = some sm ∧
      (rateOf f isAngle dep b k).value =
        (if isAngle then Angles.wrap (f s0.data - f sm.data) else f s0.data - f sm.data) /
          (((s0.t - sm.t : ℕ) : ℝ) / 10 ^ 9) := by
  revert h
  unfold rateOf
  split
  · next s0 sm h0 hm =>
    split
    · simp
    · intro _
      refine ⟨s0, sm, h0, hm, ?_⟩
      simp [rateDenom, tAt, h0, hm]
  · simp

/-- P04-10: “The denominator is (s[0].t_ns − s[m].t_ns)/10^9, with the integer difference
taken first” (04-perception.md:30). The uint64 subtraction does not wrap. -/
theorem rate_denom_exact (hb : Valid b) (k : ℕ) :
    tAt b (rateM b k) ≤ tAt b 0 ∧
      ((rateDenom b k : ℕ) : ℤ) = (tAt b 0 : ℤ) - tAt b (rateM b k) := by
  have hp := hb.length_pos
  have hml : rateM b k < b.length := by simp [rateM]; omega
  have hle : tAt b (rateM b k) ≤ tAt b 0 := by
    rw [tAt_of_lt hp, tAt_of_lt hml]
    exact hb.t_le (Nat.zero_le _) hml
  exact ⟨hle, by rw [rateDenom]; omega⟩

/-- P04-10: the same difference computed in uint64 (04-perception.md:30). -/
theorem rate_denom_uint64 (hb : Valid b) (hT : ∀ e ∈ b, e.t < 2 ^ 64) (k : ℕ) :
    (UInt64.ofNat (tAt b 0) - UInt64.ofNat (tAt b (rateM b k))).toNat = rateDenom b k := by
  have hp := hb.length_pos
  have hml : rateM b k < b.length := by simp [rateM]; omega
  have h0 : tAt b 0 < 2 ^ 64 := by rw [tAt_of_lt hp]; exact hT _ (List.getElem_mem _)
  have hm : tAt b (rateM b k) < 2 ^ 64 := by rw [tAt_of_lt hml]; exact hT _ (List.getElem_mem _)
  have hle := (rate_denom_exact hb k).1
  rw [UInt64.toNat_sub_of_le]
  · simp [UInt64.toNat_ofNat_of_lt' h0, UInt64.toNat_ofNat_of_lt' hm, rateDenom]
  · rw [UInt64.le_iff_toNat_le, UInt64.toNat_ofNat_of_lt' h0, UInt64.toNat_ofNat_of_lt' hm]
    exact hle

/-! ## `at` (04:31-35) -/

/-- P04-13: “If t_query ≥ s[0].t, returns s[0]. If t_query ≤ s[count-1].t, returns
s[count-1].” (04-perception.md:32) When both hold, the buffer has one sample, so the two
clamps agree. -/
theorem clamps_overlap (hb : Valid b) {s0 sl : Entry α} (h0 : b.head? = some s0)
    (hl : b.getLast? = some sl) (h1 : (s0.t : ℤ) ≤ q) (h2 : q ≤ (sl.t : ℤ)) :
    b.length = 1 ∧ s0 = sl := by
  obtain ⟨h0l, rfl⟩ := head_eq h0
  obtain ⟨hll, rfl⟩ := last_eq hl
  have hlen : b.length = 1 := by
    by_contra h
    have := hb.t_lt (i := 0) (j := b.length - 1) (by omega) hll
    omega
  refine ⟨hlen, ?_⟩
  simp only [hlen, Nat.sub_self]

/-- P04-13: “If t_query ≥ s[0].t, returns s[0].” (04-perception.md:32) -/
theorem at_clamp_hi {s0 : Entry α} (h0 : b.head? = some s0) (h : (s0.t : ℤ) ≤ q) :
    atQ mix m b q = some s0 := by
  cases b with
  | nil => simp at h0
  | cons x r =>
    simp at h0
    subst h0
    obtain ⟨sl, hl⟩ : ∃ sl, (x :: r).getLast? = some sl :=
      ⟨_, List.getLast?_eq_some_getLast (List.cons_ne_nil _ _)⟩
    simp only [atQ, List.head?_cons, hl, h, ↓reduceIte]

/-- P04-13: “If t_query ≤ s[count-1].t, returns s[count-1].” (04-perception.md:32) -/
theorem at_clamp_lo (hb : Valid b) {sl : Entry α} (hl : b.getLast? = some sl)
    (h : q ≤ (sl.t : ℤ)) : atQ mix m b q = some sl := by
  cases b with
  | nil => simp at hl
  | cons x r =>
    by_cases hx : (x.t : ℤ) ≤ q
    · rw [at_clamp_hi mix m (by simp) hx]
      rw [(clamps_overlap hb (by simp) hl hx h).2]
    · simp only [atQ, List.head?_cons, hl, hx, h, ↓reduceIte]

/-- P04-13: “`t_query` is a signed `Time` and may be negative. A negative query returns the
oldest sample.” (04-perception.md:32) -/
theorem at_negative (hb : Valid b) {sl : Entry α} (hl : b.getLast? = some sl) (h : q < 0) :
    atQ mix m b q = some sl :=
  at_clamp_lo mix m hb hl (by omega)

/-- The interior case of `at`. -/
theorem at_interior {s0 sl : Entry α} (h0 : b.head? = some s0)
    (hl : b.getLast? = some sl) (hlo : (sl.t : ℤ) < q) (hhi : q < s0.t) :
    atQ mix m b q = match m, floorIdx b q with
      | .floor, some j => b[j]?
      | .interpolate, some (k + 1) =>
        match b[k]?, b[k + 1]? with
        | some n, some o => some ⟨q.toNat, mix o.data n.data (alpha q o n)⟩
        | _, _ => none
      | _, _ => none := by
  simp only [atQ, h0, hl, not_le.mpr hhi, not_le.mpr hlo, ↓reduceIte]

/-- P04-16 (interior form of `at` in `Interpolate` mode): the bracket that `at` uses. -/
theorem at_interp_bracket (hb : Valid b) {s0 sl : Entry α} (h0 : b.head? = some s0)
    (hl : b.getLast? = some sl) (hlo : (sl.t : ℤ) < q) (hhi : q < s0.t) :
    ∃ k n o, b[k]? = some n ∧ b[k + 1]? = some o ∧ (o.t : ℤ) ≤ q ∧ q < n.t ∧
      atQ mix .interpolate b q = some ⟨q.toNat, mix o.data n.data (alpha q o n)⟩ := by
  obtain ⟨k, hk, hf, hko, hkn⟩ := floor_interior hb h0 hl hlo hhi
  refine ⟨k, b[k], b[k + 1], List.getElem?_eq_getElem (by omega),
    List.getElem?_eq_getElem hk, hko, hkn, ?_⟩
  rw [at_interior mix _ h0 hl hlo hhi, hf]
  simp only [List.getElem?_eq_getElem hk, List.getElem?_eq_getElem (show k < b.length by omega)]

/-- P04-14: “The returned entry's `t` is t_query clamped to [s[count-1].t, s[0].t] in
`Interpolate` mode, and the chosen sample's time otherwise” (04-perception.md:33).
`at_interp_eq` and `Tracks.at_radar` (and siblings) connect `at` to the slice interpolation
functions. -/
theorem at_interp_t (hb : Valid b) {s0 sl : Entry α} (h0 : b.head? = some s0)
    (hl : b.getLast? = some sl) (q : ℤ) :
    ∃ e, atQ mix .interpolate b q = some e ∧ (e.t : ℤ) = max (sl.t : ℤ) (min q s0.t) := by
  have hsl : sl.t ≤ s0.t := by
    obtain ⟨h0l, rfl⟩ := head_eq h0
    obtain ⟨hll, rfl⟩ := last_eq hl
    exact hb.t_le (Nat.zero_le _) hll
  by_cases hhi : (s0.t : ℤ) ≤ q
  · exact ⟨s0, at_clamp_hi mix _ h0 hhi, by omega⟩
  by_cases hlo : q ≤ (sl.t : ℤ)
  · exact ⟨sl, at_clamp_lo mix _ hb hl hlo, by omega⟩
  obtain ⟨k, n, o, -, -, -, -, he⟩ :=
    at_interp_bracket (q := q) mix hb h0 hl (by omega) (by omega)
  refine ⟨_, he, ?_⟩
  show ((q.toNat : ℕ) : ℤ) = _
  omega

/-- P04-14: in `Floor` mode the result is one of the samples, so its time is the chosen
sample's time (04-perception.md:33). -/
theorem at_floor_mem (hb : Valid b) (q : ℤ) : ∃ e ∈ b, atQ mix .floor b q = some e := by
  obtain ⟨x, r, hxr⟩ := List.exists_cons_of_ne_nil hb.1
  have h0 : b.head? = some x := by simp [hxr]
  obtain ⟨sl, hl⟩ := Option.isSome_iff_exists.mp
    (show b.getLast?.isSome by simp [hxr])
  have hsl : sl ∈ b := List.mem_of_getLast? hl
  by_cases hhi : (x.t : ℤ) ≤ q
  · exact ⟨x, by simp [hxr], at_clamp_hi mix _ h0 hhi⟩
  by_cases hlo : q ≤ (sl.t : ℤ)
  · exact ⟨sl, hsl, at_clamp_lo mix _ hb hl hlo⟩
  obtain ⟨k, hk, hf, -, -⟩ := floor_interior (q := q) hb h0 hl (by omega) (by omega)
  refine ⟨b[k + 1], List.getElem_mem hk, ?_⟩
  rw [at_interior mix _ h0 hl (by omega) (by omega), hf]
  simp [List.getElem?_eq_getElem hk]

/-- P04-15: “`Floor` Mode: Returns the newest sample s[k] where s[k].t ≤ t_query”
(04-perception.md:34). Once a sample is at or before the query, the clamps return that
sample too.
`at_interp_eq` and `Tracks.at_radar` (and siblings) connect `at` to the slice interpolation
functions. -/
theorem at_floor_spec (hb : Valid b) {sl : Entry α} (hl : b.getLast? = some sl)
    (hq : (sl.t : ℤ) ≤ q) :
    ∃ (k : ℕ) (e : Entry α), b[k]? = some e ∧ (e.t : ℤ) ≤ q ∧ (∀ j < k, ∀ e' : Entry α, b[j]? = some e' → q < e'.t) ∧
      atQ mix .floor b q = some e := by
  obtain ⟨x, r, hxr⟩ := List.exists_cons_of_ne_nil hb.1
  have h0 : b.head? = some x := by simp [hxr]
  obtain ⟨hll, hsl⟩ := last_eq hl
  by_cases hhi : (x.t : ℤ) ≤ q
  · exact ⟨0, x, by simp [hxr], hhi, fun j hj => absurd hj (Nat.not_lt_zero _),
      at_clamp_hi mix _ h0 hhi⟩
  by_cases hlo : q ≤ (sl.t : ℤ)
  · refine ⟨b.length - 1, sl, by rw [List.getElem?_eq_getElem hll, hsl], by omega,
      fun j hj e' he' => ?_, at_clamp_lo mix _ hb hl hlo⟩
    obtain ⟨hjl, rfl⟩ := List.getElem?_eq_some_iff.mp he'
    have := hb.t_lt hj hll
    rw [hsl] at this
    omega
  obtain ⟨k, hk, hf, -, -⟩ := floor_interior (q := q) hb h0 hl (by omega) (by omega)
  obtain ⟨_, hkq, hbefore⟩ := floor_spec hb _ hf
  refine ⟨k + 1, b[k + 1], List.getElem?_eq_getElem hk, hkq, fun j hj e' he' => ?_, ?_⟩
  · obtain ⟨hjl, rfl⟩ := List.getElem?_eq_some_iff.mp he'
    exact hbefore j hj
  · rw [at_interior mix _ h0 hl (by omega) (by omega), hf]
    simp [List.getElem?_eq_getElem hk]

/-- P04-16: “For bracket s[k+1].t ≤ t_query < s[k].t” (04-perception.md:35): in the
interior the bracket exists and is unique.
`at_interp_eq` and `Tracks.at_radar` (and siblings) connect `at` to the slice interpolation
functions. -/
theorem bracket_unique (hb : Valid b) {s0 sl : Entry α} (h0 : b.head? = some s0)
    (hl : b.getLast? = some sl) (hlo : (sl.t : ℤ) < q) (hhi : q < s0.t) :
    ∃! k, ∃ n o, b[k]? = some n ∧ b[k + 1]? = some o ∧ (o.t : ℤ) ≤ q ∧ q < n.t := by
  obtain ⟨k, hk, -, hko, hkn⟩ := floor_interior hb h0 hl hlo hhi
  refine ⟨k, ⟨b[k], b[k + 1], List.getElem?_eq_getElem (by omega),
    List.getElem?_eq_getElem hk, hko, hkn⟩, ?_⟩
  rintro j ⟨n, o, hn, ho, hjo, hjn⟩
  obtain ⟨hjl, rfl⟩ := List.getElem?_eq_some_iff.mp hn
  obtain ⟨hjl', rfl⟩ := List.getElem?_eq_some_iff.mp ho
  rcases lt_trichotomy j k with h | h | h
  · have := hb.t_le (i := j + 1) (j := k) (by omega) (by omega)
    omega
  · exact h
  · have := hb.t_le (i := k + 1) (j := j) (by omega) hjl
    omega

/-- P04-14..P04-17 glue: in the interior, `at` in `Interpolate` mode on the bracket
s[k+1].t ≤ t_query < s[k].t returns `mix s[k+1] s[k] α` at time t_query
(04-perception.md:33-35). -/
theorem at_interp_eq (hb : Valid b) {s0 sl : Entry α} (h0 : b.head? = some s0)
    (hl : b.getLast? = some sl) (hlo : (sl.t : ℤ) < q) (hhi : q < s0.t)
    {k : ℕ} {n o : Entry α} (hn : b[k]? = some n) (ho : b[k + 1]? = some o)
    (hko : (o.t : ℤ) ≤ q) (hkn : q < n.t) :
    atQ mix .interpolate b q = some ⟨q.toNat, mix o.data n.data (alpha q o n)⟩ := by
  obtain ⟨k', n', o', hn', ho', h1, h2, he⟩ := at_interp_bracket (q := q) mix hb h0 hl hlo hhi
  have hk : k = k' := (bracket_unique hb h0 hl hlo hhi).unique ⟨n, o, hn, ho, hko, hkn⟩
    ⟨n', o', hn', ho', h1, h2⟩
  subst hk
  rw [hn] at hn'
  rw [ho] at ho'
  cases hn'
  cases ho'
  exact he

/-- P04-16: “α = (t_query − s[k+1].t)/(s[k].t − s[k+1].t) ∈ [0, 1)” (04-perception.md:35). -/
theorem alpha_mem (o n : Entry α) (h1 : (o.t : ℤ) ≤ q) (h2 : q < n.t) :
    alpha q o n ∈ Set.Ico 0 1 := by
  have hd : (0 : ℝ) < (((n.t : ℤ) - o.t : ℤ) : ℝ) := by exact_mod_cast (show (0 : ℤ) < (n.t : ℤ) - o.t by omega)
  have hq : (0 : ℝ) ≤ ((q - o.t : ℤ) : ℝ) := by exact_mod_cast (show (0 : ℤ) ≤ q - o.t by omega)
  have hlt : ((q - o.t : ℤ) : ℝ) < (((n.t : ℤ) - o.t : ℤ) : ℝ) := by exact_mod_cast (show q - o.t < (n.t : ℤ) - o.t by omega)
  exact ⟨div_nonneg hq hd.le, (div_lt_one hd).mpr hlt⟩

/-! ## LINEAR interpolation (04:36) -/

/-- P04-17: “`LINEAR`: (1 − α) v_{k+1} + α v_k” (04-perception.md:36). The result stays
between the samples.
`at_interp_eq` and `Tracks.at_radar` (and siblings) connect `at` to the slice interpolation
functions. -/
theorem lerp_mem {w : ℝ} (hw : w ∈ Set.Ico (0 : ℝ) 1) (vo vn : ℝ) :
    lerp w vo vn ∈ Set.Icc (min vo vn) (max vo vn) := by
  obtain ⟨hw0, hw1⟩ := hw
  have a1 := mul_le_mul_of_nonneg_left (min_le_left vo vn) (show 0 ≤ 1 - w by linarith)
  have a2 := mul_le_mul_of_nonneg_left (min_le_right vo vn) hw0
  have a3 := mul_le_mul_of_nonneg_left (le_max_left vo vn) (show 0 ≤ 1 - w by linarith)
  have a4 := mul_le_mul_of_nonneg_left (le_max_right vo vn) hw0
  constructor <;> simp only [lerp] <;> nlinarith

/-- P04-17: a LINEAR field whose samples lie in an interval stays in it
(04-perception.md:36). -/
theorem lerp_mem_Icc {w vo vn lo hi : ℝ} (hw : w ∈ Set.Ico (0 : ℝ) 1)
    (ho : vo ∈ Set.Icc lo hi) (hn : vn ∈ Set.Icc lo hi) : lerp w vo vn ∈ Set.Icc lo hi := by
  have h := lerp_mem hw vo vn
  exact ⟨le_trans (le_min ho.1 hn.1) h.1, le_trans h.2 (max_le ho.2 hn.2)⟩

/-! ## Ring formula (driveline_abi.h:162-163) -/

/-- PH-03: “In-process ring view. Entry k (k = 0 newest) starts at
entries + ((head + capacity - k) % capacity) * entry_size” (driveline_abi.h:162-163). -/
theorem slot_lt {head cap k : ℕ} (hh : head < cap) : slot head cap k < cap :=
  Nat.mod_lt _ (by omega)

/-- PH-03: entry 0 is at `head` (driveline_abi.h:162-163). -/
theorem slot_zero {head cap : ℕ} (hh : head < cap) : slot head cap 0 = head := by
  simp [slot, Nat.mod_eq_of_lt hh]

/-- PH-03: distinct entries occupy distinct slots (driveline_abi.h:162-163). -/
theorem slot_injOn {head cap : ℕ} (hh : head < cap) : Set.InjOn (slot head cap) (Set.Iio cap) := by
  intro k1 hk1 k2 hk2 he
  simp only [Set.mem_Iio] at hk1 hk2
  have hd := (Nat.modEq_iff_dvd.mp he.symm)
  have hz := Int.eq_zero_of_abs_lt_dvd hd (by rw [abs_lt]; constructor <;> omega)
  omega

/-- PH-03: entry k+1 is the slot before entry k (driveline_abi.h:162-163). -/
theorem slot_succ {head cap k : ℕ} (hh : head < cap) (hk : k + 1 < cap) :
    slot head cap (k + 1) = (slot head cap k + cap - 1) % cap := by
  unfold slot
  set x := head + cap - k with hx
  have h1 : (x % cap + cap - 1 + 1) % cap = (x - 1 + 1) % cap := by
    rw [show x % cap + cap - 1 + 1 = x % cap + cap by omega, show x - 1 + 1 = x by omega,
      Nat.add_mod_right, Nat.mod_mod]
  have h2 := Nat.ModEq.add_right_cancel' 1 h1
  rw [show head + cap - (k + 1) = x - 1 by omega]
  exact h2.symm

/-- PH-03: the formula in uint32 does not overflow for capacity at most 64
(driveline_abi.h:162-163, 04-perception.md:19). -/
theorem slot_uint32 (head cap k : UInt32) (hc : cap.toNat ≤ 64) (hh : head < cap) (hk : k < cap) :
    ((head + cap - k) % cap).toNat = slot head.toNat cap.toNat k.toNat := by
  rw [UInt32.lt_iff_toNat_lt] at hh hk
  have hadd : (head + cap).toNat = head.toNat + cap.toNat := by
    rw [UInt32.toNat_add, Nat.mod_eq_of_lt (by omega)]
  rw [UInt32.toNat_mod, UInt32.toNat_sub_of_le, hadd]
  · rfl
  · rw [UInt32.le_iff_toNat_le, hadd]
    omega

end Theorems

/-- P04-19: “`ANGLE`: v_{k+1} + α Δ, wrapped to (−π, π], where Δ = v_k − v_{k+1} wrapped to
(−π, π]” (04-perception.md:37). `angleInterp α vo vn` has `vo = v_{k+1}` (older) and
`vn = v_k` (newer). -/
theorem angleInterp_spec (α vo vn : ℝ) :
    angleInterp α vo vn ∈ Set.Ioc (-Real.pi) Real.pi ∧ angleInterp 0 vo vn = Angles.wrap vo ∧
      angleInterp 1 vo vn = Angles.wrap vn ∧ |Angles.wrap (vn - vo)| ≤ Real.pi := by
  refine ⟨Angles.wrap_mem _, by simp [angleInterp], ?_, ?_⟩
  · obtain ⟨n, hn⟩ := Angles.wrap_eq_add (vn - vo)
    simp only [angleInterp, one_mul]
    rw [hn, show vo + (vn - vo + n * (2 * Real.pi)) = vn + n • (2 * Real.pi) by
      rw [zsmul_eq_mul]; ring]
    exact toIocMod_add_zsmul _ _ _ _
  · have h := Angles.wrap_mem (vn - vo)
    exact abs_le.mpr ⟨h.1.le, h.2⟩

end Driveline.SliceBuffer
