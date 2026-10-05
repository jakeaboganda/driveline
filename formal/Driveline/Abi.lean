import Mathlib.Tactic
import Driveline.SliceBuffer
import Driveline.Schedule
import Driveline.Manifest
import Driveline.Diagnostics
import Batteries.Data.Char.AsciiCasing

/-!
# C-ABI rules (spec §9, §7 byte encoding)

`docs/spec/09-abi.md`, `abi/driveline_abi.h`, and the Mode A byte encoding of
`docs/spec/07-fmu-packaging.md:15-35`. The version encoding, the `SliceBuffer`
header and payload, `char[N]` fields, output memory, the header fields and step
times the runtime writes, the host map callbacks' lane sections, tie-breaks and
successor lists, and the MIME, port-name and unit rules of Mode A.

The ring slot formula is `SliceBuffer.slot`, and step times are `Schedule.stepDt`.
-/

namespace Driveline.Abi

open Driveline.SliceBuffer Driveline.Schedule

/-! ## Version (09-abi.md:20, driveline_abi.h:12) -/

/-- `DL_ABI_VERSION_<major>_<minor>` is `(major << 16) | (minor << 8)` (09-abi.md:20). -/
def encode (major minor : ℕ) : ℕ := (major <<< 16) ||| (minor <<< 8)

/-- Before 1.0: compatible only when the version words are equal (09-abi.md:20). -/
def compatible (component runtime : ℕ) : Bool := component == runtime

/-! ## Slice buffer (driveline_abi.h:153-169) -/

structure SliceHeader where
  /-- `N` -/
  capacity : ℕ
  /-- Valid entries, `≤ N` -/
  count : ℕ
  /-- `8 + sizeof(slice struct)` -/
  entrySize : ℕ

/-- Byte offset of entry `k` in the ring (driveline_abi.h:162-163). -/
def entryOffset (h : SliceHeader) (head k : ℕ) : ℕ := slot head h.capacity k * h.entrySize

/-! ## Payload bytes (07-fmu-packaging.md:15, 17, 19) -/

abbrev Byte := Fin 256
abbrev Bytes := List Byte

/-- A little-endian unsigned integer of `w` bytes. -/
def leN (w n : ℕ) : Bytes :=
  (List.range w).map fun i => ⟨n / 256 ^ i % 256, Nat.mod_lt _ (by decide)⟩

def le32 (n : ℕ) : Bytes := leN 4 n
def le64 (n : ℕ) : Bytes := leN 8 n
def de32 (b : Bytes) : ℕ := b.foldr (fun x acc => x.val + 256 * acc) 0

/-- `dl_slice_buffer_header_t` (four `uint32_t`: capacity, count, entry_size, `_pad`)
followed by the entries (07-fmu-packaging.md:19, driveline_abi.h:155-160). -/
def serializeBuffer (h : SliceHeader) (entries : List Bytes) : Bytes :=
  le32 h.capacity ++ le32 h.count ++ le32 h.entrySize ++ le32 0 ++ entries.flatten

/-- One entry: `uint64_t t_ns` then the slice struct (07-fmu-packaging.md:19). -/
def serializeEntry (tNs : ℕ) (slice : Bytes) : Bytes := le64 tNs ++ slice

/-- The `count` entries of a ring, newest first, read with the header's slot formula. -/
def payloadEntries (h : SliceHeader) (head : ℕ) (ring : ℕ → Bytes) : List Bytes :=
  (List.range h.count).map fun k => ring (slot head h.capacity k)

/-! ## char[N] (09-abi.md:21) -/

/-- Content that fits a `char[n]`: no null byte, and room for the terminating null. -/
def fits (n : ℕ) (c : Bytes) : Prop := (∀ x ∈ c, x ≠ 0) ∧ c.length + 1 ≤ n

/-- Content, then the null, then a zero tail. -/
def pad (n : ℕ) (c : Bytes) : Bytes := c ++ List.replicate (n - c.length) 0

/-- A well-formed `char[n]` value (09-abi.md:21). -/
def wf (n : ℕ) (b : Bytes) : Prop := ∃ c, fits n c ∧ b = pad n c

/-- The bytes up to the null. -/
def content (b : Bytes) : Bytes := b.takeWhile (· ≠ 0)

/-- `char road_id[64]` (`dl_lane_ref_t` and others). -/
def roadIdN : ℕ := 64
/-- `char name[56]` (`dl_param_t`). -/
def paramNameN : ℕ := 56

section Theorems

/-! ## Version theorems -/

theorem encode_eq {major minor : ℕ} (hm : minor < 2 ^ 8) :
    encode major minor = major * 2 ^ 16 + minor * 2 ^ 8 := by
  have h : major <<< 16 = (major <<< 8) <<< 8 := by
    simp [Nat.shiftLeft_eq, mul_assoc]
  rw [encode, h, ← Nat.shiftLeft_or_distrib, ← Nat.shiftLeft_add_eq_or_of_lt hm]
  simp only [Nat.shiftLeft_eq]
  ring

/-- "`DL_ABI_VERSION_<major>_<minor>` has the value `(major << 16) | (minor << 8)`"
(09-abi.md:20): the low byte is always zero. -/
theorem encode_low_byte (major minor : ℕ) : encode major minor % 256 = 0 := by
  have h : major <<< 16 = (major <<< 8) <<< 8 := by
    simp [Nat.shiftLeft_eq, mul_assoc, ← pow_add]
  rw [encode, h, ← Nat.shiftLeft_or_distrib, Nat.shiftLeft_eq]
  exact Nat.mul_mod_left _ _

/-- With `major < 2^16` and `minor < 2^8` the word fits a `uint32_t` (09-abi.md:20). -/
theorem encode_lt {major minor : ℕ} (hM : major < 2 ^ 16) (hm : minor < 2 ^ 8) :
    encode major minor < 2 ^ 32 := by
  rw [encode_eq hm]
  omega

/-- With `minor < 2^8`, different versions get different words (09-abi.md:20).
The spec states no bound on `minor`; see `refute_encode_injective`. -/
theorem encode_injective {a b m n : ℕ} (hm : m < 2 ^ 8) (hn : n < 2 ^ 8)
    (h : encode a m = encode b n) : a = b ∧ m = n := by
  rw [encode_eq hm, encode_eq hn] at h
  omega

/-- P09-02 REFUTE: "`DL_ABI_VERSION_<major>_<minor>` has the value
`(major << 16) | (minor << 8)`" (09-abi.md:20). No rule bounds `minor` (README.md:47
only says `abi_version` increases, and 15-manifest.md:40, 18-run-record.md:20 write it
as `"<major>.<minor>"`), and versions 0.256 and 1.0 get the same word. -/
theorem refute_encode_injective : encode 0 256 = encode 1 0 ∧ (0, 256) ≠ (1, 0) := by
  decide

/-- With bounded fields, the compatibility check is version equality (09-abi.md:20). -/
theorem compatible_encode {a b m n : ℕ} (hm : m < 2 ^ 8) (hn : n < 2 ^ 8) :
    compatible (encode a m) (encode b n) = true ↔ a = b ∧ m = n := by
  simp only [compatible, beq_iff_eq]
  exact ⟨encode_injective hm hn, fun ⟨h1, h2⟩ => h1 ▸ h2 ▸ rfl⟩

/-- The `abi_version` check of the enter call: "`abi_version` must equal the component's
ABI version. Otherwise the enter call returns `DL_STATUS_ERR_INVALID_ARG`" (09-abi.md:20).
`field` is the runtime's `abi_version` in `dl_init_context_t`. -/
def enterAbiCheck (component field : ℕ) : Option Diagnostics.Code :=
  if compatible component field then none else some .errInvalidArg

/-- P09-03 REFUTE: "`abi_version` must equal the component's ABI version. Otherwise the
enter call returns `DL_STATUS_ERR_INVALID_ARG`" (09-abi.md:20), with versions encoded as
`(major << 16) | (minor << 8)`. Nothing bounds `minor`, so a runtime at 0.256 and a
component at 1.0 pass the check, in both orders, although their versions differ. -/
theorem refute_compatible :
    enterAbiCheck (encode 1 0) (encode 0 256) = none ∧
      enterAbiCheck (encode 0 256) (encode 1 0) = none ∧ (0, 256) ≠ (1, 0) := by
  decide

/-! ## Slice buffer theorems -/

/-- P09-18: "Entry k (k = 0 newest) starts at
entries + ((head + capacity - k) % capacity) * entry_size" (driveline_abi.h:162-163),
with `head` "Slot of the newest entry" (:166) and "count; Valid entries, <= N" (:157):
every valid entry lies inside the `capacity · entry_size` bytes of the ring. Slot
range, injectivity, `k = 0` and the step back are `SliceBuffer.slot_lt`, `slot_injOn`,
`slot_zero` and `slot_succ` (PH-03). -/
theorem entry_in_bounds (h : SliceHeader) {head k : ℕ} (hd : head < h.capacity)
    (hk : k < h.count) (hc : h.count ≤ h.capacity) :
    entryOffset h head k + h.entrySize ≤ h.capacity * h.entrySize := by
  have hs := slot_lt (k := k) hd
  unfold entryOffset
  calc slot head h.capacity k * h.entrySize + h.entrySize
      = (slot head h.capacity k + 1) * h.entrySize := by ring
    _ ≤ h.capacity * h.entrySize := Nat.mul_le_mul_right _ hs

/-! ## Payload theorems -/

theorem leN_length (w n : ℕ) : (leN w n).length = w := by simp [leN]

/-- P09-20: "Every `fmi3Binary` value uses little-endian byte order"
(07-fmu-packaging.md:17): a `uint32_t` field reads back as written. -/
theorem de32_le32 {n : ℕ} (h : n < 2 ^ 32) : de32 (le32 n) = n := by
  simp [de32, le32, leN, List.range_succ]
  omega

/-- P07-01: "every input value the runtime sets has exactly its struct's size, or
16 + count · `entry_size` bytes for a `SliceBuffer`" (07-fmu-packaging.md:15), with the
value "a `dl_slice_buffer_header_t` followed by `count` entries" (07-fmu-packaging.md:19)
and the header four `uint32_t` (driveline_abi.h:155-160). -/
theorem buffer_length (h : SliceHeader) (es : List Bytes) (hc : es.length = h.count)
    (he : ∀ e ∈ es, e.length = h.entrySize) :
    (serializeBuffer h es).length = 16 + h.count * h.entrySize := by
  have hm : es.map List.length = List.replicate es.length h.entrySize :=
    List.eq_replicate_iff.mpr ⟨by simp, by simpa using he⟩
  simp [serializeBuffer, le32, leN_length, List.length_flatten, hm, hc]
  omega

/-- P07-04: "Each entry is a `uint64_t t_ns` followed by the slice struct"
(07-fmu-packaging.md:19), so `entry_size` is 8 + sizeof(slice struct). -/
theorem entry_length (tNs : ℕ) (slice : Bytes) :
    (serializeEntry tNs slice).length = 8 + slice.length := by
  simp [serializeEntry, le64, leN_length]

/-- P07-04: "count entries, newest first" (07-fmu-packaging.md:19): entry `k` of the
payload is ring slot `(head + capacity - k) % capacity` (driveline_abi.h:162-163). -/
theorem payload_newest_first (h : SliceHeader) (head : ℕ) (ring : ℕ → Bytes) {k : ℕ}
    (hk : k < h.count) :
    (payloadEntries h head ring)[k]? = some (ring (slot head h.capacity k)) := by
  simp [payloadEntries, hk]

/-! ## char[N] theorems -/

theorem pad_length {n : ℕ} {c : Bytes} (h : fits n c) : (pad n c).length = n := by
  have := h.2
  simp [pad]
  omega

/-- "A `char[N]` field holds at most N − 1 bytes plus a terminating null … The bytes
after the null … are zero" (09-abi.md:21). -/
theorem pad_wf {n : ℕ} {c : Bytes} (h : fits n c) : wf n (pad n c) := ⟨c, h, rfl⟩

theorem content_append_zero : ∀ {c : Bytes} (zs : Bytes), (∀ x ∈ c, x ≠ 0) →
    content (c ++ 0 :: zs) = c
  | [], zs, _ => by simp [content]
  | x :: c, zs, h => by
    have hx := h x (by simp)
    have ih := content_append_zero (c := c) zs (fun y hy => h y (List.mem_cons_of_mem _ hy))
    simp only [content, decide_not] at ih ⊢
    simp [hx, ih]

theorem content_pad {n : ℕ} {c : Bytes} (h : fits n c) : content (pad n c) = c := by
  obtain ⟨k, hk⟩ : ∃ k, n - c.length = k + 1 := ⟨n - c.length - 1, by have := h.2; omega⟩
  rw [pad, hk, List.replicate_succ]
  exact content_append_zero _ h.1

theorem wf_length {n : ℕ} {b : Bytes} (h : wf n b) : b.length = n := by
  obtain ⟨c, hc, rfl⟩ := h
  exact pad_length hc

theorem wf_content_length {n : ℕ} {b : Bytes} (h : wf n b) : (content b).length + 1 ≤ n := by
  obtain ⟨c, hc, rfl⟩ := h
  rw [content_pad hc]
  exact hc.2

/-- P09-05: "Two `char[N]` values are equal when their bytes up to the null are equal.
The bytes after the null and every padding member are zero … so byte comparisons and
Mode A payloads are deterministic" (09-abi.md:21). -/
theorem wf_eq_iff {n : ℕ} {a b : Bytes} (ha : wf n a) (hb : wf n b) :
    content a = content b ↔ a = b := by
  refine ⟨fun h => ?_, congrArg content⟩
  obtain ⟨ca, hca, rfl⟩ := ha
  obtain ⟨cb, hcb, rfl⟩ := hb
  rw [content_pad hca, content_pad hcb] at h
  rw [h]

theorem fits_iff {n : ℕ} {c : Bytes} (h0 : ∀ x ∈ c, x ≠ 0) : fits n c ↔ c.length + 1 ≤ n :=
  ⟨And.right, fun h => ⟨h0, h⟩⟩

/-- P09-15: "A `char[N]` field holds at most N − 1 bytes plus a terminating null … A road
ID longer than 63 bytes … is a compile-time error, and so is a component parameter name
longer than 55 bytes (`dl_param_t.name`)" (09-abi.md:21): the limits are exactly what
`char road_id[64]` and `char name[56]` hold. `h0` is "`const char*` arguments are
null-terminated" (09-abi.md:21). -/
theorem name_limits (c : Bytes) (h0 : ∀ x ∈ c, x ≠ 0) :
    (fits roadIdN c ↔ c.length ≤ 63) ∧ (fits paramNameN c ↔ c.length ≤ 55) := by
  rw [fits_iff h0, fits_iff h0, roadIdN, paramNameN]
  omega

/-- Zero-padded byte lists of equal length compare like their contents. -/
theorem append_zeros_lt_iff : ∀ {a b : Bytes} {i j : ℕ}, (∀ x ∈ a, x ≠ 0) → (∀ x ∈ b, x ≠ 0) →
    0 < i → 0 < j → a.length + i = b.length + j →
    (a ++ List.replicate i 0 < b ++ List.replicate j 0 ↔ a < b)
  | [], [], i, j, _, _, _, _, hl => by
    simp at hl
    subst hl
    simp only [List.nil_append, List.lt_irrefl]
  | [], y :: b, i, j, _, hb, hi, _, _ => by
    obtain ⟨i, rfl⟩ : ∃ i', i = i' + 1 := ⟨i - 1, by omega⟩
    have hy : (0 : Byte) < y := Fin.pos_iff_ne_zero.mpr (hb y (by simp))
    simp [List.replicate_succ, List.cons_lt_cons_iff, hy, List.nil_lt_cons]
  | x :: a, [], i, j, ha, _, _, hj, _ => by
    obtain ⟨j, rfl⟩ : ∃ j', j = j' + 1 := ⟨j - 1, by omega⟩
    have hx : (0 : Byte) < x := Fin.pos_iff_ne_zero.mpr (ha x (by simp))
    simp [List.replicate_succ, List.cons_lt_cons_iff, List.not_lt_nil, not_lt.mpr hx.le,
      hx.ne']
  | x :: a, y :: b, i, j, ha, hb, hi, hj, hl => by
    have ih := append_zeros_lt_iff (a := a) (b := b) (i := i) (j := j)
      (fun z hz => ha z (by simp [hz])) (fun z hz => hb z (by simp [hz])) hi hj
      (by simp at hl; omega)
    simp only [List.cons_append, List.cons_lt_cons_iff, ih]

/-- P09-16: "`road_id` compared by bytes" (09-abi.md:33), on fields whose "bytes after
the null … are zero" (09-abi.md:21): comparing the zero-padded `char[64]` fields gives
the order of their contents, with a proper prefix first. -/
theorem pad_lt_iff {a b : Bytes} (ha : fits roadIdN a) (hb : fits roadIdN b) :
    pad roadIdN a < pad roadIdN b ↔ a < b :=
  append_zeros_lt_iff ha.1 hb.1 (by have := ha.2; omega) (by have := hb.2; omega)
    (by have := ha.2; have := hb.2; omega)

end Theorems

/-! ## Ring index in `uint32_t` (driveline_abi.h:163) -/

/-- The ring slot expression evaluated in `uint32_t`, as C does (driveline_abi.h:163). -/
def slot32 (head cap k : UInt32) : UInt32 := (head + cap - k) % cap

/-- `head + capacity` wraps modulo 2^32 when the capacity exceeds 2^31: with
capacity 0xC0000000 and head 0xBFFFFFFF, entry 0 is not at `head`. -/
theorem refute_slot32 : slot32 0xBFFFFFFF 0xC0000000 0 ≠ 0xBFFFFFFF := by
  decide

/-- P09-19: "Entry k (k = 0 newest) starts at
entries + ((head + capacity - k) % capacity) * entry_size" (driveline_abi.h:162-163),
computed in `uint32_t`. The header does not bound `capacity` (see `refute_slot32`), but
"Every mounted sensor has a compile-time capacity N ∈ [1, 64]" and the component's
buffer "has `capacity` = N_c" with N_c ≤ N_s (04-perception.md:19), so the `uint32_t`
value is the exact slot. `head` is "Slot of the newest entry" (driveline_abi.h:166) and
`k < count ≤ capacity` (driveline_abi.h:157). -/
theorem slot32_eq {head cap k : UInt32} (hc : cap.toNat ≤ 64) (h : head < cap) (hk : k ≤ cap) :
    (slot32 head cap k).toNat = slot head.toNat cap.toNat k.toNat := by
  have h' : head.toNat < cap.toNat := h
  have hk' : k.toNat ≤ cap.toNat := hk
  have hsum : (head + cap).toNat = head.toNat + cap.toNat := by
    rw [UInt32.toNat_add]
    exact Nat.mod_eq_of_lt (by omega)
  have hle : k ≤ head + cap := by
    rw [UInt32.le_iff_toNat_le, hsum]
    omega
  rw [slot32, UInt32.toNat_mod, UInt32.toNat_sub_of_le _ _ hle, hsum, slot]

/-! ## Output memory (09-abi.md:23) -/

/-- Byte offset of output entry `i`. -/
def outOffset (stride i : ℕ) : ℕ := i * stride

/-- The byte ranges `[a, a + la)` and `[b, b + lb)` do not overlap. -/
def RangesDisjoint (a la b lb : ℕ) : Prop := a + la ≤ b ∨ b + lb ≤ a

/-- P09-06: "The runtime allocates `outputs` … with `actor_count` entries,
`output_stride` bytes apart … `dl_do_step` must write every entry … its entry size is
`sizeof(T)`" (09-abi.md:23): with at least two actors and a nonempty struct, the entries
are disjoint, so the writes do not overwrite each other in any order, exactly when
`output_stride ≥ sizeof(T)`. A smaller stride cannot satisfy the runtime: `dl_do_step`
writes every entry (09-abi.md:23) and the runtime then writes `actor_id` into every
output frame (09-abi.md:24), so overlapping entries would lose one actor's frame. -/
theorem outputs_disjoint_iff {n stride size : ℕ} (hn : 2 ≤ n) (hsz : 0 < size) :
    (∀ i < n, ∀ j < n, i ≠ j →
      RangesDisjoint (outOffset stride i) size (outOffset stride j) size) ↔ size ≤ stride := by
  constructor
  · intro h
    rcases h 0 (by omega) 1 (by omega) (by omega) with h | h <;>
      simp [outOffset] at h <;> omega
  · intro hs i _ j _ hij
    unfold RangesDisjoint outOffset
    rcases Nat.lt_or_gt_of_ne hij with hl | hl
    · left
      calc i * stride + size ≤ i * stride + stride := by omega
        _ = (i + 1) * stride := by ring
        _ ≤ j * stride := Nat.mul_le_mul_right _ hl
    · right
      calc j * stride + size ≤ j * stride + stride := by omega
        _ = (j + 1) * stride := by ring
        _ ≤ i * stride := Nat.mul_le_mul_right _ hl

/-! ## Header fields and step times (09-abi.md:24-26) -/

inductive OutKind | kinematicState | other

/-- The `timestamp_ns` the runtime writes (09-abi.md:24). -/
def stampTime : OutKind → ℕ → ℕ → ℕ
  | .kinematicState, t, dtBase => t + dtBase
  | .other, t, _ => t

structure Frame (β : Type) where
  actorId : ℕ
  timestampNs : ℕ
  body : β

/-- The runtime overwrites `actor_id` and `timestamp_ns` (09-abi.md:24). -/
def finalize {β : Type} (k : OutKind) (id t dtBase : ℕ) (f : Frame β) : Frame β :=
  { f with actorId := id, timestampNs := stampTime k t dtBase }

/-- P09-17: "the runtime writes `actor_id` and `timestamp_ns` into every output frame.
The component's values for these two fields are ignored" (09-abi.md:24). -/
theorem finalize_ignores {β : Type} (k : OutKind) (id t dtBase : ℕ) (f g : Frame β)
    (h : f.body = g.body) : finalize k id t dtBase f = finalize k id t dtBase g := by
  cases f; cases g; cases h; rfl

theorem finalize_actor {β : Type} (k : OutKind) (id t dtBase : ℕ) (f : Frame β) :
    (finalize k id t dtBase f).actorId = id := rfl

/-- "`timestamp_ns` is the tick time t of the step" (09-abi.md:24). -/
theorem stamp_other {β : Type} (id t dtBase : ℕ) (f : Frame β) :
    (finalize .other id t dtBase f).timestampNs = t := rfl

/-- "except for `KinematicState`, where it is t + Δt_base" (09-abi.md:24). -/
theorem stamp_kinematic {β : Type} (id t dtBase : ℕ) (f : Frame β) :
    (finalize .kinematicState id t dtBase f).timestampNs = t + dtBase := rfl

/-- P09-07: "`timestamp_ns` is the tick time t of the step, except for `KinematicState`,
where it is t + Δt_base … Physics always runs at the base rate, so this is also
t + `dt_step_ns`" (09-abi.md:24). `h` is "Physics always runs at the base rate". -/
theorem physics_stamp {d dt : ℕ+} (t : ℕ) (h : d = 1) :
    stampTime .kinematicState t dt = t + stepDt d dt := by
  subst h
  simp [stampTime, stepDt]

/-- P09-08: "`dt_step_ns` is k_div · Δt_base_ns" (09-abi.md:25), which is
`Schedule.stepDt`; at the base rate it is Δt_base. -/
theorem stepDt_eq (d dt : ℕ+) : stepDt d dt = (d : ℕ) * dt := rfl

theorem stepDt_one (dt : ℕ+) : stepDt 1 dt = dt := by simp [stepDt]

/-- P09-09: "`own_states[i]` is the committed `KinematicState` of actor `actor_ids[i]` at
tick time t, as Phase 4 of the previous tick left it" (09-abi.md:26): the previous tick,
at t − Δt_base, stamped it t (09-abi.md:24). Tick 0 is excluded by `h`; there it is
`chassis_state` from cold init. -/
theorem own_state_stamp {t dtBase : ℕ} (h : dtBase ≤ t) :
    stampTime .kinematicState (t - dtBase) dtBase = t := by
  simp [stampTime]
  omega

/-! ## Lane sections (09-abi.md:31) -/

section Sections

variable {α : Type} [LinearOrder α]

/-- Section `j` covers `[s_j, s_{j+1})`; the last one covers `[s_{m-1}, len]`. -/
def covers (starts : List α) (len : α) (j : ℕ) (s : α) : Prop :=
  ∃ h : j < starts.length, starts[j] ≤ s ∧
    if h' : j + 1 < starts.length then s < starts[j + 1] else s ≤ len

theorem covers_exists : ∀ (starts : List α) (len lo s : α), starts.head? = some lo →
    starts.Pairwise (· ≤ ·) → lo ≤ s → s ≤ len → ∃ j, covers starts len j s
  | [], _, _, _, h0, _, _, _ => by simp at h0
  | [a], len, lo, s, h0, _, hs0, hs1 => by
    simp at h0
    subst h0
    exact ⟨0, by simp, by simpa using hs0, by simpa using hs1⟩
  | a :: b :: r, len, lo, s, h0, hs, hs0, hs1 => by
    simp at h0
    subst h0
    by_cases hb : s < b
    · exact ⟨0, by simp, by simpa using hs0, by simpa using hb⟩
    · obtain ⟨j, hj, h1, h2⟩ :=
        covers_exists (b :: r) len b s rfl hs.of_cons (not_lt.mp hb) hs1
      refine ⟨j + 1, by simpa using hj, by simpa using h1, ?_⟩
      simpa using h2

/-- P09-10: "A lane section covers [s_start, s_next), and the last one also covers the
road's end, so each s of a road lies in exactly one lane section" (09-abi.md:31): every
`s ∈ [0, len]`. The sections are in order (`hs`), and the first starts at `s = 0` (`h0`),
an OpenDRIVE rule (ledger P09-22). -/
theorem lane_section_partition [Zero α] (starts : List α) (len s : α)
    (h0 : starts.head? = some 0) (hs : starts.Pairwise (· ≤ ·))
    (hs0 : 0 ≤ s) (hs1 : s ≤ len) : ∃! j, covers starts len j s := by
  obtain ⟨j, hj⟩ := covers_exists starts len 0 s h0 hs hs0 hs1
  have key : ∀ i i', covers starts len i s → covers starts len i' s → ¬ i < i' := by
    rintro i i' ⟨hi, -, hi2⟩ ⟨hi', hi'1, -⟩ hlt
    have hn : i + 1 < starts.length := by omega
    rw [dif_pos hn] at hi2
    have hmono : starts[i + 1] ≤ starts[i'] := by
      rcases Nat.lt_or_ge (i + 1) i' with h | h
      · exact List.pairwise_iff_getElem.mp hs _ _ hn hi' h
      · have : i + 1 = i' := by omega
        subst this
        exact le_rfl
    exact absurd (lt_of_lt_of_le hi2 (hmono.trans hi'1)) (lt_irrefl _)
  refine ⟨j, hj, fun i hi => ?_⟩
  rcases lt_trichotomy i j with h | h | h
  · exact absurd h (key i j hi hj)
  · exact h
  · exact absurd h (key j i hj hi)

end Sections

/-! ## world_to_frenet choice (09-abi.md:33) -/

section Choice

variable {α : Type} [LinearOrder α]

/-- One lane of the map, seen from the query point (X, Y). -/
structure Cand (α : Type) where
  roadId : Bytes
  laneId : ℤ
  s : α
  d : α
  /-- `|psi − driving heading|` wrapped to `[0, π]` -/
  headingDiff : α
  /-- The lane's area contains (X, Y). -/
  contains : Bool
  /-- Distance from (X, Y) to the lane's centerline -/
  dist : α

/-- Hint match first (`false < true`), then heading difference, then `road_id` by
unsigned bytes, then `lane_id` as a signed integer (09-abi.md:33). -/
def key (hint : Bytes) (c : Cand α) : Bool ×ₗ α ×ₗ Bytes ×ₗ ℤ :=
  toLex (c.roadId != hint, toLex (c.headingDiff, toLex (c.roadId, c.laneId)))

/-- Off every lane: nearest centerline first, then the same tie-breaks (09-abi.md:33). -/
def offKey (hint : Bytes) (c : Cand α) : α ×ₗ (Bool ×ₗ α ×ₗ Bytes ×ₗ ℤ) :=
  toLex (c.dist, key hint c)

/-- `c` is a least element of `cs` under `f`. -/
def IsMinBy {β : Type} [LinearOrder β] (f : Cand α → β) (cs : List (Cand α)) (c : Cand α) :
    Prop :=
  c ∈ cs ∧ ∀ c' ∈ cs, f c ≤ f c'

def IsChoice (hint : Bytes) (cs : List (Cand α)) (c : Cand α) : Prop := IsMinBy (key hint) cs c

theorem exists_minBy {β : Type} [LinearOrder β] (f : Cand α → β) : ∀ (cs : List (Cand α)),
    cs ≠ [] → ∃ c, IsMinBy f cs c
  | [], h => absurd rfl h
  | [a], _ => ⟨a, by simp, by simp⟩
  | a :: b :: r, _ => by
    obtain ⟨c, hc, hmin⟩ := exists_minBy f (b :: r) (by simp)
    rcases le_total (f a) (f c) with h | h
    · refine ⟨a, by simp, ?_⟩
      intro c' hc'
      rcases List.mem_cons.mp hc' with rfl | hc'
      · exact le_rfl
      · exact h.trans (hmin c' hc')
    · refine ⟨c, List.mem_cons_of_mem _ hc, ?_⟩
      intro c' hc'
      rcases List.mem_cons.mp hc' with rfl | hc'
      · exact h
      · exact hmin c' hc'

/-- P09-11: "If several lanes contain the point … the callback prefers `hint_road_id`,
then the lane whose driving heading … is closest to `psi` …, then the smallest
`(road_id, lane_id)` … If no lane contains the point, it returns the lane with the nearest
centerline, using the same tie-breaks. So `world_to_frenet` succeeds for every finite
(X, Y)" (09-abi.md:33): when some lane contains the point, a least containing lane exists
under the tie-breaks, and otherwise a least lane exists under nearest centerline, then the
same tie-breaks. `hne` is a map with a lane: Pass 1 calls `frenet_to_world` at every
actor's spawn `(road_id, lane_id, s_0, d_0)` (06-lifecycle.md:72). -/
theorem choice_exists (hint : Bytes) (lanes : List (Cand α)) (hne : lanes ≠ []) :
    (lanes.filter (·.contains) ≠ [] → ∃ c, IsChoice hint (lanes.filter (·.contains)) c) ∧
      (lanes.filter (·.contains) = [] → ∃ c, IsMinBy (offKey hint) lanes c) :=
  ⟨exists_minBy _ _, fun _ => exists_minBy _ _ hne⟩

/-- "So `world_to_frenet` succeeds for every finite (X, Y)" (09-abi.md:33) needs a lane
to choose from: on an empty map there is none. -/
theorem no_choice_empty (hint : Bytes) : ¬ ∃ c : Cand α, IsChoice hint [] c := by
  simp [IsChoice, IsMinBy]

end Choice

/-- P09-21 REFUTE: "Returns the lane whose area contains (X, Y), with `s` on that road's
reference line, `d` from that lane's centerline" (09-abi.md:33). One lane can contain the
point at two values of `s` (a helical ramp) with tied heading differences: both are
choices, so the returned `(s, d)` is not determined by 09-abi.md:33. -/
theorem refute_unique_s : ∃ (cs : List (Cand ℤ)) (a b : Cand ℤ),
    IsChoice [] cs a ∧ IsChoice [] cs b ∧ (a.s, a.d) ≠ (b.s, b.d) := by
  refine ⟨[⟨[1], -1, 10, 0, 0, true, 0⟩, ⟨[1], -1, 50, 0, 0, true, 0⟩],
    ⟨[1], -1, 10, 0, 0, true, 0⟩, ⟨[1], -1, 50, 0, 0, true, 0⟩,
    ⟨by simp, ?_⟩, ⟨by simp, ?_⟩, by decide⟩ <;>
    · intro c hc
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl <;> exact le_rfl

/-! ## sample_lane_path (09-abi.md:35) -/

/-- Curvature of the offset curve at offset `d` from a centerline of curvature `κ`. -/
noncomputable def offsetCurv (κ d : ℝ) : ℝ := κ / (1 - κ * d)

/-- P09-12: "the curvature is κ / (1 − κ d) for centerline curvature κ and offset d, both
relative to increasing s, negated when sampling toward decreasing s" (09-abi.md:35):
reversing the direction negates κ and d, and the formula negates. The spec defines no
result when `κ d ≥ 1`, where Lean's `x / 0 = 0` hides the pole (ledger P09-23). -/
theorem offsetCurv_reverse (κ d : ℝ) : offsetCurv (-κ) (-d) = -offsetCurv κ d := by
  simp [offsetCurv, neg_div]

/-- "`d_offset` changes sign, so the points stay on the same side of the path"
(09-abi.md:35): reversing the direction negates the normal. -/
theorem offset_side (p n : ℝ × ℝ) (d : ℝ) : p + d • n = p + (-d) • (-n) := by
  simp

/-! ## Successors (09-abi.md:36) -/

abbrev LaneRef := Bytes × ℤ

/-- Successors sorted by `(road_id, lane_id)`, the first `maxN` written, and the total. -/
def topo (succ : List LaneRef) (maxN : ℕ) : List LaneRef × ℕ :=
  let sorted := succ.mergeSort (fun a b => decide (toLex a ≤ toLex b))
  (sorted.take maxN, sorted.length)

theorem topo_total (succ : List LaneRef) (m : ℕ) : (topo succ m).2 = succ.length := by
  simp [topo]

/-- P09-13: "The callback writes at most `max_successors` of them and sets
`out_num_successors` to the total" (09-abi.md:36). -/
theorem topo_written_length (succ : List LaneRef) (m : ℕ) :
    (topo succ m).1.length = min m succ.length := by
  simp [topo]

theorem topo_truncated_iff (succ : List LaneRef) (m : ℕ) :
    (topo succ m).1.length < (topo succ m).2 ↔ m < succ.length := by
  rw [topo_written_length, topo_total]
  omega

/-- "Successors are … sorted by `(road_id, lane_id)`" (09-abi.md:36). -/
theorem topo_sorted (succ : List LaneRef) (m : ℕ) :
    (topo succ m).1.Pairwise (fun a b => toLex a ≤ toLex b) := by
  have hs := List.pairwise_mergeSort (le := fun a b : LaneRef => decide (toLex a ≤ toLex b))
    (fun a b c hab hbc => by simp only [decide_eq_true_eq] at *; exact hab.trans hbc)
    (fun a b => by simpa using le_total (toLex a) (toLex b)) succ
  exact (hs.sublist (List.take_sublist _ _)).imp (by simp)

/-! ## Lane 0 (02-conventions.md:22) -/

/-- The lane-argument check of a map callback over the map's lanes: lane 0 fails with
`DL_STATUS_ERR_INVALID_ARG` (02-conventions.md:22), and so does a lane outside the map
(09-abi.md:31). -/
def laneArgCheck (lanes : List LaneRef) (r : LaneRef) : Option Diagnostics.Code :=
  if r.2 = 0 ∨ r ∉ lanes then some .errInvalidArg else none

/-- P02-12: "0 is the road reference line, which has no centerline, so lane 0 in a
callback argument is `DL_STATUS_ERR_INVALID_ARG`" (02-conventions.md:22). An OpenDRIVE map
lists lane 0 as the center lane of every lane section: on such a map lane 0 still fails,
with code −1, while a listed lane other than 0 passes. -/
theorem lane_zero_invalid :
    laneArgCheck [([1], 0), ([1], -1)] ([1], 0) = some .errInvalidArg ∧
      laneArgCheck [([1], 0), ([1], -1)] ([1], -1) = none ∧
      Diagnostics.Code.errInvalidArg.toInt = -1 ∧
      ∀ (lanes : List LaneRef) (r : Bytes), laneArgCheck lanes (r, 0) = some .errInvalidArg := by
  refine ⟨by decide, by decide, rfl, fun lanes r => by simp [laneArgCheck]⟩

/-! ## Mode A variable names (07-fmu-packaging.md:21) -/

def reserved : List String := ["output", "own_state", "dl_init_context"]

def portNameOk (n : String) : Bool := !reserved.contains n

/-- The FMI variables of a Mode A FMU: the input ports, then `output`, `own_state` and
`dl_init_context`. -/
def fmiVars (ports : List String) : List String := ports ++ reserved

/-- P07-05: "a port named `output`, `own_state`, or `dl_init_context` is a compile-time
error" (07-fmu-packaging.md:21). -/
theorem reserved_rejected : ∀ n ∈ reserved, portNameOk n = false := by decide

/-- What the rule buys: every FMI variable name is distinct (07-fmu-packaging.md:21). -/
theorem fmiVars_nodup {ports : List String} (hn : ports.Nodup)
    (hok : ∀ p ∈ ports, portNameOk p = true) : (fmiVars ports).Nodup := by
  refine List.nodup_append.mpr ⟨hn, by decide, fun a ha b hb hab => ?_⟩
  subst hab
  have := hok a ha
  simp [portNameOk] at this
  exact this hb

/-! ## MIME subtype names (07-fmu-packaging.md:25) -/

/-- An inner character: a hyphen before a capital, which is lowered. -/
def kebabChar (x : Char) : List Char := if x.isUpper then ['-', x.toLower] else [x]

/-- "the type names written in lowercase with a hyphen before each inner capital"
(07-fmu-packaging.md:25). -/
def kebab : List Char → List Char
  | [] => []
  | c :: cs => c.toLower :: cs.flatMap kebabChar

def builtinTypes : List String :=
  ["IntentFrame", "KinematicControlFrame", "ActuatorControlFrame", "KinematicState",
   "VisualSlice", "RadarSlice", "CameraSlice", "SurfaceSlice", "RouteNodes"]

/-- An ASCII CamelCase identifier: a capital, then letters and digits. -/
def CamelCase (s : List Char) : Prop :=
  ∃ c cs, s = c :: cs ∧ c.isUpper = true ∧ ∀ x ∈ s, x.isAlphanum = true

/-- P07-06: "`IntentFrame` is `intent-frame`, `KinematicControlFrame` is
`kinematic-control-frame`, and `RadarSlice` is `radar-slice`" (07-fmu-packaging.md:25). -/
theorem kebab_examples : kebab "IntentFrame".toList = "intent-frame".toList ∧
    kebab "KinematicControlFrame".toList = "kinematic-control-frame".toList ∧
    kebab "RadarSlice".toList = "radar-slice".toList := by
  decide

/-- `own_state` has MIME type `application/x-driveline.kinematic-state` (07-fmu-packaging.md:23). -/
theorem kebab_kinematicState : kebab "KinematicState".toList = "kinematic-state".toList := by
  decide

theorem builtin_mime_distinct : (builtinTypes.map fun n => kebab n.toList).Nodup := by
  decide

/-- The rule alone is not injective: `aB` and `AB` both give `a-b`. -/
theorem kebab_case_collision : kebab "aB".toList = kebab "AB".toList := by
  decide

theorem toUpper_of_isUpper {x : Char} (h : x.isUpper = true) : x.toUpper = x :=
  Char.toUpper_eq_of_not_isLower (Char.not_isLower_of_isUpper h)

theorem flatMap_kebabChar_inj : ∀ {a b : List Char}, (∀ x ∈ a, x.isAlphanum = true) →
    (∀ x ∈ b, x.isAlphanum = true) → a.flatMap kebabChar = b.flatMap kebabChar → a = b
  | [], [], _, _, _ => rfl
  | [], y :: b, _, _, h => by
    simp [kebabChar] at h
    split at h <;> simp at h
  | x :: a, [], _, _, h => by
    simp [kebabChar] at h
    split at h <;> simp at h
  | x :: a, y :: b, ha, hb, h => by
    have hxa := ha x (by simp)
    have hya := hb y (by simp)
    have hdash : ('-').isAlphanum = false := by decide
    have ih := @flatMap_kebabChar_inj a b (fun z hz => ha z (by simp [hz]))
      (fun z hz => hb z (by simp [hz]))
    simp only [List.flatMap_cons, kebabChar] at h
    by_cases hx : x.isUpper = true <;> by_cases hy : y.isUpper = true <;>
      simp only [hx, hy, ite_true, Bool.false_eq_true, ite_false, List.cons_append,
        List.nil_append, List.cons.injEq] at h
    · obtain ⟨-, hl, ht⟩ := h
      have : x = y := by
        rw [← toUpper_of_isUpper hx, ← toUpper_of_isUpper hy, ← Char.toUpper_toLower_eq_toUpper,
          hl, Char.toUpper_toLower_eq_toUpper]
      rw [this, ih ht]
    · exact absurd (h.1 ▸ hya) (by simp [hdash])
    · exact absurd (h.1 ▸ hxa) (by simp [hdash])
    · rw [h.1, ih h.2]

/-- "lowercase with a hyphen before each inner capital" (07-fmu-packaging.md:25) gives
distinct MIME subtypes to distinct ASCII CamelCase type names. -/
theorem kebab_injective {a b : List Char} (ha : CamelCase a) (hb : CamelCase b)
    (h : kebab a = kebab b) : a = b := by
  obtain ⟨c, cs, rfl, hc, hca⟩ := ha
  obtain ⟨d, ds, rfl, hd, hda⟩ := hb
  simp only [kebab, List.cons.injEq] at h
  have hcd : c = d := by
    rw [← toUpper_of_isUpper hc, ← toUpper_of_isUpper hd, ← Char.toUpper_toLower_eq_toUpper,
      h.1, Char.toUpper_toLower_eq_toUpper]
  rw [hcd, flatMap_kebabChar_inj (fun x hx => hca x (by simp [hx]))
    (fun x hx => hda x (by simp [hx])) h.2]

/-! ## Units (07-fmu-packaging.md:35) -/

inductive BaseUnit | kg | m | s | A | K | mol | cd | rad
  deriving DecidableEq

/-- A declared FMI unit: conversion `factor · x + offset` to base units, and base-unit
exponents. -/
structure FmiUnit where
  factor : ℚ
  offset : ℚ
  exps : BaseUnit → ℤ

def toBase (u : FmiUnit) (x : ℚ) : ℚ := u.factor * x + u.offset

/-- "factor 1 and offset 0 and whose base-unit exponents match the dimension of the value
bound to it, ignoring any `rad` exponent" (07-fmu-packaging.md:35). -/
def unitOk (u : FmiUnit) (dim : BaseUnit → ℤ) : Prop :=
  u.factor = 1 ∧ u.offset = 0 ∧ ∀ b, b ≠ .rad → u.exps b = dim b

/-- P07-07: "conversion to base units has factor 1 and offset 0 … Any other unit is a
compile-time error, so the runtime never converts units" (07-fmu-packaging.md:35). -/
theorem unitOk_toBase {u : FmiUnit} {dim : BaseUnit → ℤ} (h : unitOk u dim) (x : ℚ) :
    toBase u x = x := by
  simp [toBase, h.1, h.2.1]

/-- "ignoring any `rad` exponent because angles are dimensionless" (07-fmu-packaging.md:35). -/
theorem unitOk_rad {u : FmiUnit} {dim : BaseUnit → ℤ} (h : unitOk u dim) (k : ℤ) :
    unitOk { u with exps := Function.update u.exps .rad k } dim :=
  ⟨h.1, h.2.1, fun b hb => by simp [Function.update_of_ne hb, h.2.2 b hb]⟩

/-! ## Ledger bundles -/

/-- P07-04: "count entries, newest first. Each entry is a `uint64_t t_ns` followed by the
slice struct" (07-fmu-packaging.md:19): `entry_length` and `payload_newest_first`. -/
theorem slice_payload_layout :
    (∀ (tNs : ℕ) (slice : Bytes), (serializeEntry tNs slice).length = 8 + slice.length) ∧
    ∀ (h : SliceHeader) (head : ℕ) (ring : ℕ → Bytes) (k : ℕ), k < h.count →
      (payloadEntries h head ring)[k]? = some (ring (slot head h.capacity k)) :=
  ⟨entry_length, fun h head ring _ hk => payload_newest_first h head ring hk⟩

/-- P07-06: "`IntentFrame` is `intent-frame`" (07-fmu-packaging.md:25): the spec's
examples hold and the rule is injective on ASCII CamelCase type names
(`kebab_examples`, `kebab_injective`). -/
theorem mime_subtype_rule :
    (kebab "IntentFrame".toList = "intent-frame".toList ∧
      kebab "KinematicControlFrame".toList = "kinematic-control-frame".toList ∧
      kebab "RadarSlice".toList = "radar-slice".toList) ∧
    ∀ {a b : List Char}, CamelCase a → CamelCase b → kebab a = kebab b → a = b :=
  ⟨kebab_examples, kebab_injective⟩

end Driveline.Abi
