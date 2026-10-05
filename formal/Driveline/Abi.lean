import Mathlib.Tactic
import Driveline.SliceBuffer
import Driveline.Schedule
import Driveline.Manifest

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

/-- P09-03 REFUTE: "Before version 1.0, a component and a runtime work together only
if their versions are equal. `dl_instantiate` returns `DL_STATUS_ERR_INVALID_ARG` for
any other version" (09-abi.md:20). Comparing the words accepts a 0.256 component in a
1.0 runtime, because nothing bounds `minor`. -/
theorem refute_compatible : compatible (encode 0 256) (encode 1 0) = true ∧ (0, 256) ≠ (1, 0) := by
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

end Driveline.Abi
