import Driveline.Diagnostics
import Mathlib.Data.Nat.Digits.Lemmas
import Mathlib.Data.Finset.Sort

/-!
# Run record (spec §18) and collision lines (§11 Contact)

`docs/spec/18-run-record.md`. The JSON Lines encoding of §18.1 over `List Char`,
the lines of §18.2, the collision lines of the Contact rule
(11-execution.md:24), and the order of the lines of a run (18:25).
-/

namespace Driveline.RunRecord

open Diagnostics

/-! ## Encoding (§18.1) -/

def hex (n : Nat) : Char := Char.ofNat (if n < 10 then 48 + n else 87 + n)

/-- "A string escapes `"` as `\"`, `\` as `\\`, and each character from U+0000
to U+001F as `\u00` followed by two lowercase hexadecimal digits. Every other
character is written as itself." (18-run-record.md:16) -/
def escChar (c : Char) : List Char :=
  if c = '"' then ['\\', '"']
  else if c = '\\' then ['\\', '\\']
  else if c.toNat < 32 then ['\\', 'u', '0', '0', hex (c.toNat / 16), hex (c.toNat % 16)]
  else [c]

def escape (s : List Char) : List Char := s.flatMap escChar

def jstr (s : List Char) : List Char := '"' :: escape s ++ ['"']

def digitChar (d : Nat) : Char := Char.ofNat (48 + d)

/-- "An integer is written in decimal with no leading zeros." (18:16) -/
def jnat (n : Nat) : List Char :=
  if n = 0 then ['0'] else (Nat.digits 10 n).reverse.map digitChar

def parseNat (s : List Char) : Nat := Nat.ofDigits 10 (s.reverse.map fun c => c.toNat - 48)

/-- The characters of an ECMAScript `Number::toString` of a finite value. -/
def numChar (c : Char) : Prop := c ∈ "0123456789+-.e".toList

instance : DecidablePred numChar := fun c => inferInstanceAs (Decidable (c ∈ _))

/-- The binary64 writer of 18:16, "in the form that ECMAScript `Number::toString`
produces". That form uses only digits, `+`, `-`, `.` and `e`. The digits it
chooses are binary64 formatting (P18-40, `OUT: external`). -/
structure Renderer (F : Type) where
  render : F → List Char
  alphabet : ∀ x, ∀ c ∈ render x, numChar c

/-- A lockfile entry `{ "path": string, "sha256": string }`, members in that
order, in the encoding of §18.1 (19-modules.md:25). -/
def fileEntry (e : List Char × List Char) : List Char :=
  '{' :: (jstr "path".toList ++ ':' :: (jstr e.1 ++ ',' ::
    (jstr "sha256".toList ++ ':' :: (jstr e.2 ++ ['}']))))

/-- The entries separated by `,`. -/
def fileEntries : List (List Char × List Char) → List Char
  | [] => []
  | [e] => fileEntry e
  | e :: e' :: es => fileEntry e ++ ',' :: fileEntries (e' :: es)

/-- The array `files` of (`path`, `sha256`) entries (19-modules.md:25). -/
def jfiles (fs : List (List Char × List Char)) : List Char := '[' :: fileEntries fs ++ [']']

/-- A member value. `files` is the header's `files` (§19.2). -/
inductive Val (F : Type)
  | nat (n : Nat)
  | str (s : List Char)
  | num (x : F)
  | files (fs : List (List Char × List Char))

def Val.render {F : Type} (R : Renderer F) : Val F → List Char
  | .nat n => jnat n
  | .str s => jstr s
  | .num x => R.render x
  | .files fs => jfiles fs

def Val.shape {F : Type} : Val F → Nat
  | .nat _ => 0
  | .str _ => 1
  | .num _ => 2
  | .files _ => 3

def member {F : Type} (R : Renderer F) (m : String × Val F) : List Char :=
  jstr m.1.toList ++ ':' :: m.2.render R

/-- The members separated by `,`. -/
def members {F : Type} (R : Renderer F) : List (String × Val F) → List Char
  | [] => []
  | [m] => member R m
  | m :: m' :: ms => member R m ++ ',' :: members R (m' :: ms)

/-- "Each line is one JSON object followed by `\n`, with no other whitespace." -/
def encodeObj {F : Type} (R : Renderer F) (ms : List (String × Val F)) : List Char :=
  '{' :: members R ms ++ ['}', '\n']

/-! ### Lemmas on the encoding -/

theorem hex_inj : ∀ a < 16, ∀ b < 16, hex a = hex b → a = b := by decide

def unhex (c : Char) : Nat := if c.toNat < 58 then c.toNat - 48 else c.toNat - 87

theorem unhex_hex : ∀ n < 16, unhex (hex n) = n := by decide

/-- Reads one escaped character. -/
def unesc : List Char → Option (Char × List Char)
  | '\\' :: 'u' :: '0' :: '0' :: h1 :: h2 :: r => some (Char.ofNat (unhex h1 * 16 + unhex h2), r)
  | '\\' :: c :: r => some (c, r)
  | c :: r => some (c, r)
  | [] => none

theorem unesc_escChar (c : Char) (x : List Char) : unesc (escChar c ++ x) = some (c, x) := by
  unfold escChar
  split_ifs with h1 h2 h3
  · subst h1; rfl
  · subst h2; rfl
  · simp only [List.cons_append, List.nil_append, unesc]
    rw [unhex_hex _ (by omega), unhex_hex _ (by omega), Nat.div_add_mod', Char.ofNat_toNat]
  · simp only [List.cons_append, List.nil_append]
    unfold unesc
    split
    · rename_i heq; simp only [List.cons.injEq] at heq; exact absurd heq.1 h2
    · rename_i heq; simp only [List.cons.injEq] at heq; exact absurd heq.1 h2
    · rename_i heq; simp only [List.cons.injEq] at heq; rw [heq.1, heq.2]
    · simp at *

theorem escChar_cancel {a b : Char} {x y : List Char} (h : escChar a ++ x = escChar b ++ y) :
    a = b ∧ x = y := by
  have := congrArg unesc h
  rw [unesc_escChar, unesc_escChar] at this
  simpa using this

theorem escChar_head (c : Char) : ∃ h t, escChar c = h :: t ∧ h ≠ '"' := by
  unfold escChar
  split_ifs with h1 <;> simp [h1]

theorem escape_cancel : ∀ {a b : List Char} {x y : List Char},
    escape a ++ '"' :: x = escape b ++ '"' :: y → a = b ∧ x = y
  | [], [], _, _, h => by simpa [escape] using h
  | [], c :: b, _, _, h => by
    obtain ⟨h0, t, he, hn⟩ := escChar_head c
    simp [escape, he] at h
    exact absurd h.1.symm hn
  | c :: a, [], _, _, h => by
    obtain ⟨h0, t, he, hn⟩ := escChar_head c
    simp [escape, he] at h
    exact absurd h.1 hn
  | c :: a, d :: b, x, y, h => by
    simp only [escape, List.flatMap_cons, List.append_assoc] at h
    obtain ⟨rfl, h'⟩ := escChar_cancel h
    obtain ⟨rfl, rfl⟩ := escape_cancel (a := a) (b := b) h'
    exact ⟨rfl, rfl⟩

theorem jstr_cancel {a b x y : List Char} (h : jstr a ++ x = jstr b ++ y) : a = b ∧ x = y := by
  simp only [jstr, List.cons_append, List.append_assoc, List.singleton_append,
    List.cons.injEq, true_and] at h
  exact escape_cancel h

theorem jstr_inj {a b : List Char} : jstr a = jstr b ↔ a = b :=
  ⟨fun h => (jstr_cancel (x := []) (y := []) (by simpa using h)).1, fun h => h ▸ rfl⟩

theorem tok_cancel (A : Char → Prop) :
    ∀ {x y r s : List Char} {c : Char}, (∀ ch ∈ x, A ch) → (∀ ch ∈ y, A ch) → ¬ A c →
      x ++ c :: r = y ++ c :: s → x = y ∧ r = s
  | [], [], _, _, _, _, _, _, h => by simpa using h
  | [], e :: y, _, _, _, _, hy, hc, h => by
    simp only [List.nil_append, List.cons_append, List.cons.injEq] at h
    exact absurd (h.1 ▸ hy e (by simp)) hc
  | e :: x, [], _, _, _, hx, _, hc, h => by
    simp only [List.nil_append, List.cons_append, List.cons.injEq] at h
    exact absurd (h.1 ▸ hx e (by simp)) hc
  | e :: x, f :: y, _, _, _, hx, hy, hc, h => by
    simp only [List.cons_append, List.cons.injEq] at h
    obtain ⟨rfl, h'⟩ := h
    obtain ⟨rfl, rfl⟩ := tok_cancel A (fun ch hm => hx ch (by simp [hm]))
      (fun ch hm => hy ch (by simp [hm])) hc h'
    exact ⟨rfl, rfl⟩

theorem digitChar_toNat {d : Nat} (h : d < 10) : (digitChar d).toNat - 48 = d := by
  interval_cases d <;> rfl

theorem digitChar_numChar {d : Nat} (h : d < 10) : numChar (digitChar d) ∧ (digitChar d).isDigit ∧
    (digitChar d = '0' → d = 0) := by
  interval_cases d <;> decide

theorem parse_jnat (n : Nat) : parseNat (jnat n) = n := by
  unfold jnat
  split_ifs with h
  · subst h; rfl
  · simp only [parseNat, List.map_reverse, List.reverse_reverse, List.map_map]
    rw [List.map_congr_left (g := id) fun d hd => by
      simpa using digitChar_toNat (Nat.digits_lt_base (by norm_num) hd)]
    simp [Nat.ofDigits_digits]

theorem jnat_inj {a b : Nat} : jnat a = jnat b ↔ a = b :=
  ⟨fun h => by rw [← parse_jnat a, h, parse_jnat], fun h => h ▸ rfl⟩

theorem jnat_numChar (n : Nat) : ∀ c ∈ jnat n, numChar c := by
  unfold jnat
  split_ifs
  · simp only [List.mem_singleton, forall_eq]; decide
  · simp only [List.mem_map, List.mem_reverse]
    rintro c ⟨d, hd, rfl⟩
    exact (digitChar_numChar (Nat.digits_lt_base (by norm_num) hd)).1

theorem jnat_isDigit (n : Nat) : ∀ c ∈ jnat n, c.isDigit = true := by
  unfold jnat
  split_ifs
  · simp only [List.mem_singleton, forall_eq]; decide
  · simp only [List.mem_map, List.mem_reverse]
    rintro c ⟨d, hd, rfl⟩
    exact (digitChar_numChar (Nat.digits_lt_base (by norm_num) hd)).2.1

theorem fileEntry_cancel {a b : List Char × List Char} {x y : List Char}
    (h : fileEntry a ++ x = fileEntry b ++ y) : a = b ∧ x = y := by
  simp only [fileEntry, List.cons_append, List.append_assoc, List.cons.injEq, true_and] at h
  obtain ⟨-, h⟩ := jstr_cancel h
  simp only [List.cons.injEq, true_and] at h
  obtain ⟨h1, h⟩ := jstr_cancel h
  simp only [List.cons.injEq, true_and] at h
  obtain ⟨-, h⟩ := jstr_cancel h
  simp only [List.cons.injEq, true_and] at h
  obtain ⟨h2, h⟩ := jstr_cancel h
  simp only [List.cons_append, List.nil_append, List.cons.injEq, true_and] at h
  exact ⟨Prod.ext h1 h2, h⟩

theorem fileEntries_head (e : List Char × List Char) (es : List (List Char × List Char)) :
    ∃ t, fileEntries (e :: es) = '{' :: t := by
  cases es <;> simp only [fileEntries, fileEntry, List.cons_append] <;> exact ⟨_, rfl⟩

theorem fileEntries_cancel : ∀ {a b : List (List Char × List Char)} {x y : List Char},
    fileEntries a ++ ']' :: x = fileEntries b ++ ']' :: y → a = b ∧ x = y
  | [], [], _, _, h => by simpa [fileEntries] using h
  | [], e :: es, _, _, h => by
    obtain ⟨t, ht⟩ := fileEntries_head e es
    simp [fileEntries, ht] at h
  | e :: es, [], _, _, h => by
    obtain ⟨t, ht⟩ := fileEntries_head e es
    simp [fileEntries, ht] at h
  | [e], [f], _, _, h => by
    obtain ⟨rfl, h⟩ := fileEntry_cancel h
    simpa using h
  | [e], f :: f' :: fs, _, _, h => by
    simp only [fileEntries, List.append_assoc, List.cons_append] at h
    simpa using (fileEntry_cancel h).2
  | e :: e' :: es, [f], _, _, h => by
    simp only [fileEntries, List.append_assoc, List.cons_append] at h
    simpa using (fileEntry_cancel h).2
  | e :: e' :: es, f :: f' :: fs, _, _, h => by
    simp only [fileEntries, List.append_assoc, List.cons_append] at h
    obtain ⟨rfl, h'⟩ := fileEntry_cancel h
    obtain ⟨h1, h2⟩ := fileEntries_cancel (List.cons.inj h').2
    exact ⟨by rw [h1], h2⟩

theorem jfiles_inj {a b : List (List Char × List Char)} : jfiles a = jfiles b ↔ a = b := by
  refine ⟨fun h => ?_, fun h => h ▸ rfl⟩
  simp only [jfiles, List.cons_append, List.cons.injEq, true_and] at h
  exact (fileEntries_cancel (x := []) (y := []) h).1

theorem comma_not_numChar : ¬ numChar ',' := by decide

/-- A value followed by `,` determines its text and the rest. -/
theorem val_cancel {F : Type} (R : Renderer F) {v w : Val F} {r s : List Char}
    (hs : v.shape = w.shape) (hr : v.shape ≠ 3)
    (h : v.render R ++ ',' :: r = w.render R ++ ',' :: s) :
    v.render R = w.render R ∧ r = s := by
  cases v <;> cases w <;> simp only [Val.shape] at hs hr <;> (try omega) <;>
    simp only [Val.render] at h ⊢
  · exact tok_cancel numChar (jnat_numChar _) (jnat_numChar _) comma_not_numChar h
  · obtain ⟨rfl, h'⟩ := jstr_cancel h
    simpa using h'
  · exact tok_cancel numChar (R.alphabet _) (R.alphabet _) comma_not_numChar h

/-- Two member lists with the same keys and value shapes, `files` only last,
that encode alike have the same value texts. -/
theorem members_cancel {F : Type} (R : Renderer F) :
    ∀ (ms₁ ms₂ : List (String × Val F)), ms₁.map (·.1) = ms₂.map (·.1) →
      ms₁.map (·.2.shape) = ms₂.map (·.2.shape) → (∀ m ∈ ms₁.dropLast, m.2.shape ≠ 3) →
      members R ms₁ ++ ['}', '\n'] = members R ms₂ ++ ['}', '\n'] →
      ms₁.map (·.2.render R) = ms₂.map (·.2.render R)
  | [], [], _, _, _, _ => rfl
  | [], _ :: _, hk, _, _, _ => by simp at hk
  | _ :: _, [], hk, _, _, _ => by simp at hk
  | [(k₁, v₁)], [(k₂, v₂)], hk, _, _, h => by
    simp only [List.map_cons, List.map_nil, List.cons.injEq, and_true] at hk
    subst hk
    simp only [members, member, List.append_assoc, List.cons_append,
      List.append_cancel_left_eq, List.cons.injEq, true_and] at h
    simpa using List.append_cancel_right h
  | [_], _ :: _ :: _, hk, _, _, _ => by simp at hk
  | _ :: _ :: _, [_], hk, _, _, _ => by simp at hk
  | (k₁, v₁) :: m₁ :: t₁, (k₂, v₂) :: m₂ :: t₂, hk, hs, hl, h => by
    simp only [List.map_cons, List.cons.injEq] at hk hs
    obtain ⟨rfl, hk⟩ := hk
    simp only [members, member, List.append_assoc, List.cons_append,
      List.append_cancel_left_eq, List.cons.injEq, true_and] at h
    have hr : v₁.shape ≠ 3 := hl (k₁, v₁) (by simp)
    obtain ⟨hv, h'⟩ := val_cancel R hs.1 hr h
    have ih := members_cancel R (m₁ :: t₁) (m₂ :: t₂)
      (by simpa using hk) (by simpa using hs.2)
      (fun m hm => hl m (by rw [List.dropLast_cons₂]; exact List.mem_cons_of_mem _ hm))
      (by simpa only [List.append_assoc] using h')
    simp only [List.map_cons] at ih ⊢
    rw [hv, ih]

/-! ## Lines (§18.2) -/

structure Header where
  specVersion : List Char
  abiVersion : List Char
  sha256 : List Char
  seed : Nat
  timestepNs : Nat
  files : List (List Char × List Char)

inductive RSev | warning | error
  deriving DecidableEq

def RSev.name : RSev → List Char
  | .warning => "warning".toList
  | .error => "error".toList

/-- The report fields of 14-diagnostics.md:34. -/
structure Report where
  tick : Nat
  simTimeNs : Nat
  severity : RSev
  code : Code
  inst : List Char
  detail : List Char

structure Collision (F : Type) where
  tick : Nat
  simTimeNs : Nat
  a : Nat
  b : Nat
  vxA : F
  vyA : F
  vxB : F
  vyB : F

inductive Line (F : Type)
  | header (h : Header)
  | report (r : Report)
  | collision (c : Collision F)
  | stop (success : Bool) (tick simTimeNs : Nat)

/-- The members of each line, in the order of 18:20-23. -/
def Line.members {F : Type} : Line F → List (String × Val F)
  | .header h =>
    [("record", .str "header".toList), ("spec_version", .str h.specVersion),
      ("abi_version", .str h.abiVersion), ("scenario_sha256", .str h.sha256),
      ("seed", .nat h.seed), ("timestep_ns", .nat h.timestepNs), ("files", .files h.files)]
  | .report r =>
    [("record", .str "report".toList), ("tick", .nat r.tick), ("sim_time_ns", .nat r.simTimeNs),
      ("severity", .str r.severity.name), ("code", .str r.code.name.toList),
      ("instance", .str r.inst), ("detail", .str r.detail)]
  | .collision c =>
    [("record", .str "collision".toList), ("tick", .nat c.tick), ("sim_time_ns", .nat c.simTimeNs),
      ("actor_a", .nat c.a), ("actor_b", .nat c.b), ("vx_a", .num c.vxA), ("vy_a", .num c.vyA),
      ("vx_b", .num c.vxB), ("vy_b", .num c.vyB)]
  | .stop s t n =>
    [("record", .str "end".toList), ("outcome", .str (if s then "success" else "failure").toList),
      ("tick", .nat t), ("sim_time_ns", .nat n)]

def encode {F : Type} (R : Renderer F) (l : Line F) : List Char := encodeObj R l.members

/-- A line with its binary64 values replaced by `g` of them. -/
def Line.map {F G : Type} (g : F → G) : Line F → Line G
  | .header h => .header h
  | .report r => .report r
  | .collision c => .collision ⟨c.tick, c.simTimeNs, c.a, c.b, g c.vxA, g c.vyA, g c.vxB, g c.vyB⟩
  | .stop s t n => .stop s t n

def Line.kind {F : Type} : Line F → List Char
  | .header _ => "header".toList
  | .report _ => "report".toList
  | .collision _ => "collision".toList
  | .stop _ _ _ => "end".toList

theorem encode_kind {F : Type} (R : Renderer F) (l : Line F) :
    ∃ rest, encode R l = '{' :: (jstr "record".toList ++ ':' :: (jstr l.kind ++ ',' :: rest)) := by
  cases l <;> simp only [encode, encodeObj, Line.members, members, member, Val.render, Line.kind,
    List.append_assoc, List.cons_append] <;> exact ⟨_, rfl⟩

theorem code_name_inj {c d : Code} (h : c.name.toList = d.name.toList) : c = d := by
  cases c <;> cases d <;> first | rfl | (exact absurd h (by decide))

theorem rsev_name_inj {a b : RSev} (h : a.name = b.name) : a = b := by
  cases a <;> cases b <;> first | rfl | (exact absurd h (by decide))

theorem outcome_inj {a b : Bool}
    (h : (if a then "success" else "failure").toList = (if b then "success" else "failure").toList) :
    a = b := by
  cases a <;> cases b <;> first | rfl | (exact absurd h (by decide))

theorem encode_same_kind {F : Type} (R : Renderer F) {l₁ l₂ : Line F}
    (h : encode R l₁ = encode R l₂) : l₁.kind = l₂.kind := by
  obtain ⟨r₁, h₁⟩ := encode_kind R l₁
  obtain ⟨r₂, h₂⟩ := encode_kind R l₂
  rw [h₁, h₂] at h
  simp only [List.cons.injEq, List.append_cancel_left_eq, true_and] at h
  exact (jstr_cancel h).1

theorem encode_texts {F : Type} (R : Renderer F) {a b : Line F} (hk : a.kind = b.kind)
    (h : encode R a = encode R b) :
    a.members.map (·.2.render R) = b.members.map (·.2.render R) := by
  cases a <;> cases b <;> simp only [Line.kind] at hk <;> (try exact absurd hk (by decide)) <;>
    exact members_cancel R _ _ rfl rfl
      (by simp [Line.members, List.dropLast, Val.shape])
      (by simpa [encode, encodeObj] using h)

/-- Two lines have the same encoding exactly when they agree with their binary64
values replaced by their written text. -/
theorem encode_eq_iff {F : Type} (R : Renderer F) (l₁ l₂ : Line F) :
    encode R l₁ = encode R l₂ ↔ l₁.map R.render = l₂.map R.render := by
  constructor
  · intro h
    have hk := encode_same_kind R h
    have := encode_texts R hk h
    cases l₁ <;> cases l₂ <;> simp only [Line.kind] at hk <;> (try exact absurd hk (by decide)) <;>
      simp only [Line.members, List.map_cons, List.map_nil, Val.render, List.cons.injEq,
        jstr_inj, jnat_inj, jfiles_inj, and_true, true_and] at this <;> simp only [Line.map]
    · rename_i a b
      cases a; cases b; simp_all
    · rename_i a b
      obtain ⟨h1, h2, h3, h4, h5, h6⟩ := this
      cases a; cases b
      simp only at h1 h2 h3 h4 h5 h6
      subst h1 h2 h5 h6
      rw [rsev_name_inj h3, code_name_inj h4]
    · rename_i a b
      cases a; cases b; simp_all
    · obtain ⟨h1, h2, h3⟩ := this
      simp [outcome_inj h1, h2, h3]
  · intro h
    cases l₁ <;> cases l₂ <;> simp only [Line.map, reduceCtorEq, Line.collision.injEq,
      Line.header.injEq, Line.report.injEq, Line.stop.injEq, Collision.mk.injEq] at h
    all_goals first
      | (subst h; rfl)
      | (obtain ⟨rfl, rfl, rfl⟩ := h; rfl)
      | (rename_i a b; cases a; cases b
         simp only at h
         obtain ⟨rfl, rfl, rfl, rfl, h5, h6, h7, h8⟩ := h
         simp [encode, encodeObj, Line.members, members, member, Val.render, h5, h6, h7, h8])

/-- P18-02. "An integer is written in decimal with no leading zeros."
(18-run-record.md:16). Every character of the text is a decimal digit, it
starts with `0` only for 0, and it determines the integer. -/
theorem jnat_canonical (n m : Nat) :
    (∀ c ∈ jnat n, c.isDigit = true) ∧ ((jnat n).head? = some '0' → n = 0) ∧
      (jnat n = jnat m → n = m) := by
  refine ⟨jnat_isDigit n, fun h => ?_, jnat_inj.1⟩
  unfold jnat at h
  split_ifs at h with hn
  · exact hn
  · have hne : Nat.digits 10 n ≠ [] := Nat.digits_ne_nil_iff_ne_zero.2 hn
    rw [List.head?_map, List.head?_reverse, List.getLast?_eq_getLast hne] at h
    simp only [Option.map_some, Option.some.injEq] at h
    have hl := Nat.getLast_digit_ne_zero 10 hn
    exact absurd ((digitChar_numChar (Nat.digits_lt_base (by norm_num)
      (List.getLast_mem hne))).2.2 h) hl

/-- P14-13. "Each report has the fields `tick`, `sim_time_ns`, `severity`
(`warning` or `error`), `code` (a `dl_status_t` name), `instance` ..., and
`detail` (text)." (14-diagnostics.md:34) and "Members: `record` (`"report"`),
then the report fields in the order that §14.2 lists them." (18:21). The code
is written as its name, so code -1 is never written as an integer. -/
theorem report_members {F : Type} (r : Report) :
    ((Line.report r : Line F).members.map (·.1)) =
      ["record", "tick", "sim_time_ns", "severity", "code", "instance", "detail"] ∧
      (Line.report r : Line F).members.lookup "code" = some (.str r.code.name.toList) := by
  refine ⟨rfl, ?_⟩
  simp [Line.members, List.lookup]

/-! ## Record shape (§18.2 items 1 and 4) -/

/-- A line between the header and the end line: a report or a collision (18:21-22). -/
inductive BodyLine (F : Type)
  | report (r : Report)
  | collision (c : Collision F)

def BodyLine.line {F : Type} : BodyLine F → Line F
  | .report r => .report r
  | .collision c => .collision c

def Line.isHeader {F : Type} : Line F → Bool
  | .header _ => true
  | _ => false

def Line.isEnd {F : Type} : Line F → Bool
  | .stop _ _ _ => true
  | _ => false

def record {F : Type} (h : Header) (body : List (BodyLine F)) (s : Bool) (t n : Nat) :
    List (Line F) :=
  .header h :: body.map BodyLine.line ++ [.stop s t n]

/-- P18-03. "Header: The first line." (18:20) and "End: The last line." (18:23).
The record has exactly one header line and one end line. -/
theorem record_ends {F : Type} (h : Header) (body : List (BodyLine F)) (s : Bool) (t n : Nat) :
    (record h body s t n).head? = some (.header h) ∧
      (record h body s t n).getLast? = some (.stop s t n) ∧
      ((record h body s t n).filter (·.isHeader)).length = 1 ∧
      ((record h body s t n).filter (·.isEnd)).length = 1 := by
  have hh : (body.map BodyLine.line).filter (fun l : Line F => l.isHeader) = [] :=
    List.filter_eq_nil_iff.2 fun l hl => by
      obtain ⟨b, -, rfl⟩ := List.mem_map.1 hl; cases b <;> simp [BodyLine.line, Line.isHeader]
  have he : (body.map BodyLine.line).filter (fun l : Line F => l.isEnd) = [] :=
    List.filter_eq_nil_iff.2 fun l hl => by
      obtain ⟨b, -, rfl⟩ := List.mem_map.1 hl; cases b <;> simp [BodyLine.line, Line.isEnd]
  refine ⟨rfl, by rw [record, List.getLast?_append]; rfl, ?_, ?_⟩
  · rw [record, List.cons_append, List.filter_cons, List.filter_append, hh]; rfl
  · rw [record, List.cons_append, List.filter_cons, List.filter_append, he]; rfl

/-! ## Collisions (11-execution.md:24, §18.2 item 3) -/

/-- "every pair of actors a < b by `actor_id`, except a pair of two static
actors, in ascending order of (a, b)" (11-execution.md:24). `ids` is the set of
`actor_id`s. -/
def pairList (ids : Finset ℕ) (static : ℕ → Bool) : List (ℕ × ℕ) :=
  (ids.sort).flatMap fun a =>
    ((ids.sort).filter fun b => decide (a < b) && !(static a && static b)).map (a, ·)

theorem mem_pairList {ids : Finset ℕ} {static : ℕ → Bool} {p : ℕ × ℕ} :
    p ∈ pairList ids static ↔
      p.1 ∈ ids ∧ p.2 ∈ ids ∧ p.1 < p.2 ∧ ¬ (static p.1 = true ∧ static p.2 = true) := by
  obtain ⟨a, b⟩ := p
  simp [pairList]
  cases static a <;> cases static b <;> simp

def lexLt (p q : ℕ × ℕ) : Prop := p.1 < q.1 ∨ (p.1 = q.1 ∧ p.2 < q.2)

theorem pairList_sorted (ids : Finset ℕ) (static : ℕ → Bool) :
    (pairList ids static).Pairwise lexLt := by
  have hs : (ids.sort).Pairwise (· < ·) := (Finset.sortedLT_sort ids).pairwise
  unfold pairList
  rw [List.pairwise_flatMap]
  refine ⟨fun a _ => ?_, ?_⟩
  · rw [List.pairwise_map]
    exact (hs.filter _).imp fun h => Or.inr ⟨rfl, h⟩
  · refine hs.imp fun h => ?_
    simp only [List.mem_map]
    rintro _ ⟨b, _, rfl⟩ _ ⟨b', _, rfl⟩
    exact Or.inl h

theorem pairList_nodup (ids : Finset ℕ) (static : ℕ → Bool) : (pairList ids static).Nodup :=
  (pairList_sorted ids static).imp fun {p q} h hpq => by
    subst hpq; rcases h with h | ⟨_, h⟩ <;> omega

/-- The pairs in contact at committed state `t` and not reported before. -/
def newPairs (contact : ℕ → ℕ × ℕ → Bool) (ps : List (ℕ × ℕ)) (t : ℕ) (seen : List (ℕ × ℕ)) :
    List (ℕ × ℕ) :=
  ps.filter fun p => contact t p && !seen.contains p

/-- The runtime's test over the committed states 0, ..., n-1 (the spawn state
has tick 0, the state after Phase 4 of tick k has tick k+1): the collision
lines `(tick, pair)` written so far, and the pairs already reported. -/
def scan (contact : ℕ → ℕ × ℕ → Bool) (ps : List (ℕ × ℕ)) : ℕ → List (ℕ × (ℕ × ℕ)) × List (ℕ × ℕ)
  | 0 => ([], [])
  | n + 1 =>
    let r := scan contact ps n
    let new := newPairs contact ps n r.2
    (r.1 ++ new.map (n, ·), r.2 ++ new)

def collisions (contact : ℕ → ℕ × ℕ → Bool) (ps : List (ℕ × ℕ)) (n : ℕ) : List (ℕ × (ℕ × ℕ)) :=
  (scan contact ps n).1

theorem mem_seen (contact : ℕ → ℕ × ℕ → Bool) (ps : List (ℕ × ℕ)) (p : ℕ × ℕ) :
    ∀ n, p ∈ (scan contact ps n).2 ↔ p ∈ ps ∧ ∃ t < n, contact t p = true
  | 0 => by simp [scan]
  | n + 1 => by
    have ih := mem_seen contact ps p n
    simp only [scan, newPairs, List.mem_append, List.mem_filter, Bool.and_eq_true,
      Bool.not_eq_true', List.contains_eq_mem, decide_eq_false_iff_not, ih]
    constructor
    · rintro (⟨hp, t, ht, hc⟩ | ⟨hp, hc, _⟩)
      · exact ⟨hp, t, by omega, hc⟩
      · exact ⟨hp, n, by omega, hc⟩
    · rintro ⟨hp, t, ht, hc⟩
      by_cases h : ∃ t < n, contact t p = true
      · exact Or.inl ⟨hp, h⟩
      · have : t = n := by
          by_contra hne; exact h ⟨t, by omega, hc⟩
        subst this
        exact Or.inr ⟨hp, hc, fun h' => h h'.2⟩

theorem mem_collisions (contact : ℕ → ℕ × ℕ → Bool) (ps : List (ℕ × ℕ)) (t : ℕ) (p : ℕ × ℕ) :
    ∀ n, (t, p) ∈ collisions contact ps n ↔
      t < n ∧ p ∈ ps ∧ contact t p = true ∧ ∀ t' < t, contact t' p = false
  | 0 => by simp [collisions, scan]
  | n + 1 => by
    have ih := mem_collisions contact ps t p n
    simp only [collisions] at ih ⊢
    simp only [scan, newPairs, List.mem_append, List.mem_map, List.mem_filter, Bool.and_eq_true,
      Bool.not_eq_true', List.contains_eq_mem, decide_eq_false_iff_not, mem_seen, ih,
      Prod.mk.injEq]
    constructor
    · rintro (⟨ht, hp, hc, hf⟩ | ⟨q, ⟨hq, hc, hn⟩, rfl, rfl⟩)
      · exact ⟨by omega, hp, hc, hf⟩
      · refine ⟨by omega, hq, hc, fun t' ht' => ?_⟩
        by_contra h
        exact hn ⟨hq, t', ht', by simpa using h⟩
    · rintro ⟨ht, hp, hc, hf⟩
      rcases Nat.lt_succ_iff_lt_or_eq.1 ht with ht | rfl
      · exact Or.inl ⟨ht, hp, hc, hf⟩
      · refine Or.inr ⟨p, ⟨hp, hc, ?_⟩, rfl, rfl⟩
        rintro ⟨_, t', ht', hc'⟩
        simp [hf t' ht'] at hc'

theorem collisions_nodup (contact : ℕ → ℕ × ℕ → Bool) {ps : List (ℕ × ℕ)} (hps : ps.Nodup) :
    ∀ n, (collisions contact ps n).Nodup
  | 0 => by simp [collisions, scan]
  | n + 1 => by
    have ih := collisions_nodup contact hps n
    simp only [collisions] at ih ⊢
    simp only [scan]
    rw [List.nodup_append]
    refine ⟨ih, (hps.filter _).map (fun a b h => by simpa using h), ?_⟩
    rintro ⟨t, p⟩ h₁ y h₂
    simp only [List.mem_map] at h₂
    obtain ⟨_, _, rfl⟩ := h₂
    have := ((mem_collisions contact ps t p n).1 h₁).1
    intro he
    simp only [Prod.mk.injEq] at he
    omega

theorem filter_tick_sublist (contact : ℕ → ℕ × ℕ → Bool) (ps : List (ℕ × ℕ)) (t : ℕ) :
    ∀ n, (((collisions contact ps n).filter (·.1 == t)).map (·.2)).Sublist ps
  | 0 => by simp [collisions, scan]
  | n + 1 => by
    simp only [collisions, scan, List.filter_append, List.map_append]
    by_cases htn : t = n
    · subst htn
      have h0 : ((scan contact ps t).1.filter (·.1 == t)) = [] := by
        rw [List.filter_eq_nil_iff]
        rintro ⟨t', p⟩ hm
        have := ((mem_collisions contact ps t' p t).1 hm).1
        simp only [beq_iff_eq]; omega
      rw [h0, List.filter_map]
      simp only [Function.comp_def, beq_self_eq_true, List.filter_true, List.map_map,
        List.nil_append, List.map_id_fun', id]
      exact List.filter_sublist
    · have h1 : (((newPairs contact ps n (scan contact ps n).2).map (n, ·)).filter
          (·.1 == t)) = [] := by
        rw [List.filter_eq_nil_iff]
        intro x hx
        simp only [List.mem_map] at hx
        obtain ⟨_, _, rfl⟩ := hx
        simp only [beq_iff_eq]; omega
      rw [h1, List.map_nil, List.append_nil]
      exact filter_tick_sublist contact ps t n

/-- P11-21. "On the first tick that a pair is in contact, and on no later tick,
the runtime writes a `collision` line to the run record" (11-execution.md:24).
The pairs are those that the same sentence's test covers: "every pair of actors
a < b by `actor_id`, except a pair of two static actors" (`mem_pairList`), so a
pair of two static actors gets no line, as stated. For each pair: at most one
line, a line exactly when the pair is in contact on some tested committed state,
and its tick is the first such state. -/
theorem collision_first_contact (ids : Finset ℕ) (static : ℕ → Bool)
    (contact : ℕ → ℕ × ℕ → Bool) (n : ℕ) (p : ℕ × ℕ) :
    ((collisions contact (pairList ids static) n).filter (·.2 == p)).length ≤ 1 ∧
      ((∃ t, (t, p) ∈ collisions contact (pairList ids static) n) ↔
        p ∈ pairList ids static ∧ ∃ t < n, contact t p = true) ∧
      ∀ t, (t, p) ∈ collisions contact (pairList ids static) n →
        contact t p = true ∧ ∀ t' < t, contact t' p = false := by
  set ps := pairList ids static
  refine ⟨?_, ⟨?_, ?_⟩, fun t h => ?_⟩
  · have hnd := ((collisions_nodup contact (pairList_nodup ids static) n).filter
      (fun x : ℕ × (ℕ × ℕ) => x.2 == p))
    have hall : ∀ x ∈ (collisions contact ps n).filter (·.2 == p),
        ∀ y ∈ (collisions contact ps n).filter (·.2 == p), x = y := by
      rintro ⟨t₁, q₁⟩ h₁ ⟨t₂, q₂⟩ h₂
      simp only [List.mem_filter, beq_iff_eq] at h₁ h₂
      obtain ⟨h₁, e₁⟩ := h₁
      obtain ⟨h₂, e₂⟩ := h₂
      change q₁ = p at e₁
      change q₂ = p at e₂
      rw [e₁] at h₁ ⊢
      rw [e₂] at h₂ ⊢
      have a₁ := (mem_collisions contact ps t₁ p n).1 h₁
      have a₂ := (mem_collisions contact ps t₂ p n).1 h₂
      have : t₁ = t₂ := by
        rcases Nat.lt_trichotomy t₁ t₂ with h | h | h
        · simp [a₂.2.2.2 t₁ h] at a₁
        · exact h
        · simp [a₁.2.2.2 t₂ h] at a₂
      rw [this]
    generalize (collisions contact ps n).filter (·.2 == p) = L at hnd hall
    match L, hnd, hall with
    | [], _, _ => simp
    | [_], _, _ => simp
    | a :: b :: _, hnd, hall =>
      exact absurd (hall a (by simp) b (by simp)) (by simp at hnd; exact hnd.1.1)
  · rintro ⟨t, h⟩
    obtain ⟨ht, hp, hc, _⟩ := (mem_collisions contact ps t p n).1 h
    exact ⟨hp, t, ht, hc⟩
  · rintro ⟨hp, t, ht, hc⟩
    classical
    let t₀ := Nat.find (⟨t, hc⟩ : ∃ t, contact t p = true)
    have h₀ : contact t₀ p = true := Nat.find_spec (⟨t, hc⟩ : ∃ t, contact t p = true)
    have hle : t₀ ≤ t := Nat.find_min' _ hc
    refine ⟨t₀, (mem_collisions contact ps t₀ p n).2 ⟨by omega, hp, h₀, fun t' ht' => ?_⟩⟩
    have := Nat.find_min (⟨t, hc⟩ : ∃ t, contact t p = true) ht'
    simpa using this
  · obtain ⟨_, _, hc, hf⟩ := (mem_collisions contact ps t p n).1 h
    exact ⟨hc, hf⟩

/-- P18-04. "`actor_a` and `actor_b` (the two `actor_id`s, ascending)"
(18-run-record.md:22). -/
theorem pair_ascending (ids : Finset ℕ) (static : ℕ → Bool) :
    ∀ p ∈ pairList ids static, p.1 < p.2 :=
  fun _ h => (mem_pairList.1 h).2.2.1

/-- P18-06. "Lines of one tick follow the pair order of §11" (18-run-record.md:22),
the "ascending order of (a, b)" of 11-execution.md:24. -/
theorem tick_lines_sorted (ids : Finset ℕ) (static : ℕ → Bool) (contact : ℕ → ℕ × ℕ → Bool)
    (n t : ℕ) :
    (((collisions contact (pairList ids static) n).filter (·.1 == t)).map (·.2)).Pairwise
      lexLt :=
  (pairList_sorted ids static).sublist (filter_tick_sublist contact _ t n)

/-- "the World-frame horizontal velocity of each actor's reference origin" (18:22). -/
noncomputable def worldVel (vlon vlat ψ : ℝ) : ℝ × ℝ :=
  (vlon * Real.cos ψ - vlat * Real.sin ψ, vlon * Real.sin ψ + vlat * Real.cos ψ)

/-- P18-05. "(v_lon cos ψ − v_lat sin ψ, v_lon sin ψ + v_lat cos ψ)"
(18-run-record.md:22). Over ℝ, this is (v_lon, v_lat) rotated by ψ, so it
keeps the speed. The binary64 values in the record are not covered. -/
theorem worldVel_rotation (vlon vlat ψ : ℝ) :
    ((worldVel vlon vlat ψ).1 : ℂ) + (worldVel vlon vlat ψ).2 * Complex.I =
        (vlon + vlat * Complex.I) * Complex.exp (ψ * Complex.I) ∧
      (worldVel vlon vlat ψ).1 ^ 2 + (worldVel vlon vlat ψ).2 ^ 2 = vlon ^ 2 + vlat ^ 2 := by
  refine ⟨?_, ?_⟩
  · rw [Complex.exp_mul_I, ← Complex.ofReal_cos, ← Complex.ofReal_sin]
    simp only [worldVel]
    push_cast
    ring_nf
    rw [Complex.I_sq]
    ring
  · have := Real.sin_sq_add_cos_sq ψ
    simp only [worldVel]
    linear_combination (vlon ^ 2 + vlat ^ 2) * this

/-! ## The lines of a run (18:23-25) -/

inductive Kind (P : Type)
  | report (p : P)
  | collision (a b : ℕ)

def Kind.isCollision {P : Type} : Kind P → Bool
  | .collision _ _ => true
  | .report _ => false

structure Event (P : Type) where
  tick : ℕ
  kind : Kind P

/-- Tick k in the order of 11-execution.md:19-24 and 10:32: `early`, the
reports of Phases 1 to 3 and of the Phase 4 commit; `pairs`, the collision
lines of the committed state; `late`, the reports of `terminate when` and the
`on` conditions; `window`, the reports of a splice window, its teardown calls
included in sequence (18:25). -/
structure TickRun (P : Type) where
  early : List P
  pairs : List (ℕ × ℕ)
  late : List P
  window : List P

/-- The lines of tick k with their ticks (14:34, 18:25). -/
def TickRun.events {P : Type} (k : ℕ) (t : TickRun P) : List (Event P) :=
  t.early.map (fun p => ⟨reportTick (.exec k), .report p⟩) ++
    t.pairs.map (fun q => ⟨k + 1, .collision q.1 q.2⟩) ++
    t.late.map (fun p => ⟨reportTick (.exec k), .report p⟩) ++
    t.window.map (fun p => ⟨reportTick (.splice k), .report p⟩)

def ticksEv {P : Type} : ℕ → List (TickRun P) → List (Event P)
  | _, [] => []
  | k, t :: ts => t.events k ++ ticksEv (k + 1) ts

structure Run (P : Type) where
  cold : List P
  spawnPairs : List (ℕ × ℕ)
  ticks : List (TickRun P)
  ending : Ending
  teardown : List P

/-- The lines before the end-of-run teardown: cold init, the contact test on
the spawn state (tick 0, 11:24), then each tick. -/
def Run.pre {P : Type} (r : Run P) : List (Event P) :=
  r.cold.map (fun p => ⟨reportTick .coldInit, .report p⟩) ++
    r.spawnPairs.map (fun q => ⟨0, .collision q.1 q.2⟩) ++ ticksEv 0 r.ticks

/-- "Reports of the end-of-run teardown ... come after every other report and
before the end line." (18:25) -/
def Run.body {P : Type} (r : Run P) : List (Event P) :=
  r.pre ++ r.teardown.map fun p => ⟨teardownTick r.ending, .report p⟩

/-- The ticks executed match the ending: none after a cold-init failure, and
ticks 0, ..., k when the run ended in or after tick k. -/
def Run.WF {P : Type} (r : Run P) : Prop :=
  match r.ending with
  | .failed .coldInit _ => r.ticks = [] ∧ r.spawnPairs = []
  | .failed (.exec k) _ | .failed (.splice k) _ | .succeeded k => r.ticks.length = k + 1

/-- P14-12. "A teardown report carries the same tick and time as the error that
ended the run, or, after a successful run, the tick whose Phase 4 ended it."
(14-diagnostics.md:34) -/
theorem teardown_report_tick {P : Type} (r : Run P) :
    ∀ e ∈ r.body.drop r.pre.length,
      e.tick = (match r.ending with
        | .failed c _ => reportTick c
        | .succeeded k => k) ∧ e.kind.isCollision = false := by
  intro e he
  simp only [Run.body, List.drop_left, List.mem_map] at he
  obtain ⟨p, _, rfl⟩ := he
  exact ⟨by cases r.ending <;> rfl, rfl⟩

/-- P18-08. "The committed state after Phase 4 of tick k has tick k + 1 ... So
a collision line carries the committed state's tick, while a report from the
same Phase 4 carries the executing tick k" (18-run-record.md:25). -/
theorem phase4_collision_tick {P : Type} (k : ℕ) (t : TickRun P) :
    (∀ e ∈ t.events k, e.kind.isCollision = true → e.tick = reportTick (.exec k) + 1) ∧
      ∀ p ∈ t.late, (⟨reportTick (.exec k), .report p⟩ : Event P) ∈ t.events k := by
  constructor
  · intro e he hc
    simp only [TickRun.events, List.mem_append, List.mem_map] at he
    rcases he with ((⟨_, _, rfl⟩ | ⟨_, _, rfl⟩) | ⟨_, _, rfl⟩) | ⟨_, _, rfl⟩ <;>
      simp_all [Kind.isCollision, reportTick]
  · intro p hp
    simp only [TickRun.events, List.mem_append, List.mem_map]
    exact Or.inl (Or.inr ⟨p, hp, rfl⟩)

/-- The events of the ticks, each tagged with its tick index. -/
def tagged {P : Type} : ℕ → List (TickRun P) → List (ℕ × Event P)
  | _, [] => []
  | k, t :: ts => (t.events k).map (k, ·) ++ tagged (k + 1) ts

theorem ticksEv_eq {P : Type} : ∀ (k : ℕ) (ts : List (TickRun P)),
    ticksEv k ts = (tagged k ts).map Prod.snd
  | _, [] => rfl
  | k, t :: ts => by
    simp [ticksEv, tagged, ticksEv_eq (k + 1) ts, Function.comp_def]

theorem tagged_bounds {P : Type} : ∀ (k : ℕ) (ts : List (TickRun P)), ∀ x ∈ tagged k ts,
    x.1 ≤ x.2.tick ∧ x.2.tick ≤ x.1 + 1 ∧ k ≤ x.1 ∧ x.1 < k + ts.length
  | _, [] => by simp [tagged]
  | k, t :: ts => by
    intro x hx
    simp only [tagged, List.mem_append, List.mem_map] at hx
    rcases hx with ⟨e, he, rfl⟩ | hx
    · simp only [TickRun.events, List.mem_append, List.mem_map] at he
      rcases he with ((⟨_, _, rfl⟩ | ⟨_, _, rfl⟩) | ⟨_, _, rfl⟩) | ⟨_, _, rfl⟩ <;>
        simp [reportTick]
    · have := tagged_bounds (k + 1) ts x hx
      simp only [List.length_cons]
      omega

theorem tagged_sorted {P : Type} : ∀ (k : ℕ) (ts : List (TickRun P)),
    (tagged k ts).Pairwise (fun x y => x.1 ≤ y.1)
  | _, [] => by simp [tagged]
  | k, t :: ts => by
    simp only [tagged]
    rw [List.pairwise_append, List.pairwise_map]
    refine ⟨List.pairwise_of_forall fun _ _ => le_refl k, tagged_sorted (k + 1) ts, ?_⟩
    intro x hx y hy
    simp only [List.mem_map] at hx
    obtain ⟨_, _, rfl⟩ := hx
    have := tagged_bounds (k + 1) ts y hy
    simp only; omega

/-- P18-09. "So a collision line carries the committed state's tick, while a
report from the same Phase 4 carries the executing tick k ..., and ticks need
not increase from line to line." (18-run-record.md:25). A run whose tick 0 ends
on a contact and on `terminate when`: its collision line has tick 1 and the
teardown report after it tick 0. A tick never drops by more than one. -/
theorem ticks_need_not_increase :
    (∃ r : Run ℕ, r.WF ∧ ¬ r.body.IsChain (fun a b => a.tick ≤ b.tick)) ∧
      ∀ {P : Type} (r : Run P), r.WF → r.body.IsChain (fun a b => a.tick ≤ b.tick + 1) := by
  refine ⟨⟨⟨[], [], [⟨[], [(1, 2)], [], []⟩], .succeeded 0, [7]⟩, rfl, ?_⟩, ?_⟩
  · simp [Run.body, Run.pre, ticksEv, TickRun.events, teardownTick]
  · intro P r hwf
    let T := teardownTick r.ending
    let tb : List (ℕ × Event P) :=
      (r.cold.map (fun p => (⟨reportTick .coldInit, .report p⟩ : Event P)) ++
        r.spawnPairs.map (fun q => (⟨0, .collision q.1 q.2⟩ : Event P))).map (0, ·) ++
        tagged 0 r.ticks ++ (r.teardown.map fun p => (⟨T, .report p⟩ : Event P)).map (T, ·)
    have hb : r.body = tb.map Prod.snd := by
      simp [tb, T, Run.body, Run.pre, ticksEv_eq, Function.comp_def]
    have hlen : ∀ x ∈ tagged 0 r.ticks, x.1 ≤ T := by
      intro x hx
      have := tagged_bounds 0 r.ticks x hx
      simp only [T, Run.WF] at hwf ⊢
      split at hwf
      · rw [hwf.1] at hx; simp [tagged] at hx
      all_goals rename_i heq; rw [heq]; simp only [teardownTick, reportTick]; omega
    have hbd : ∀ x ∈ tb, x.1 ≤ x.2.tick ∧ x.2.tick ≤ x.1 + 1 := by
      intro x hx
      simp only [tb, List.mem_append, List.mem_map] at hx
      rcases hx with ((⟨e, he, rfl⟩ | hx) | ⟨e, he, rfl⟩)
      · rcases he with ⟨_, _, rfl⟩ | ⟨_, _, rfl⟩ <;> simp [reportTick]
      · exact ⟨(tagged_bounds 0 r.ticks x hx).1, (tagged_bounds 0 r.ticks x hx).2.1⟩
      · obtain ⟨_, _, rfl⟩ := he; simp
    have hs : tb.Pairwise (fun x y => x.1 ≤ y.1) := by
      refine List.pairwise_append.2 ⟨List.pairwise_append.2 ⟨List.pairwise_map.2
        (List.pairwise_of_forall fun _ _ => le_refl 0), tagged_sorted 0 r.ticks, ?_⟩,
        List.pairwise_map.2 (List.pairwise_of_forall fun _ _ => le_refl T), ?_⟩
      · intro x hx y _
        obtain ⟨_, _, rfl⟩ := List.mem_map.1 hx
        exact Nat.zero_le _
      · intro x hx y hy
        obtain ⟨_, _, rfl⟩ := List.mem_map.1 hy
        rcases List.mem_append.1 hx with hx | hx
        · obtain ⟨_, _, rfl⟩ := List.mem_map.1 hx
          exact Nat.zero_le _
        · exact hlen x hx
    rw [hb, List.isChain_map]
    refine (hs.imp_of_mem fun {x y} hx hy h => ?_).isChain
    have := hbd x hx
    have := hbd y hy
    omega

/-- P18-10. "Lines between the header and the end line appear in the order that
sequential execution in the order of §11 produces them. Reports of the
end-of-run teardown (§14.2 item 3) come after every other report and before
the end line. Reports of a splice window's teardown calls stay in sequence."
(18-run-record.md:25). A tick whose Phase 2 ran in parallel writes the same
lines as sequential execution (`par_reports`, `hcover` as there), and every
line after the others is an end-of-run teardown report. The order of 18:25 is
encoded by the definition of `Run.body`: cold init, the spawn-state contact
test, then each tick in the order of `TickRun.events`, then the end-of-run
teardown. -/
theorem lines_sequential {C P : Type} (out : C → CallOut P) (ran : C → Bool) (order : List C)
    (hcover : ∀ c ∈ takeUntilIncl (fun c => (out c).err.isSome) order, ran c = true)
    (k : ℕ) (t : TickRun P) (before : List P) (r : Run P) :
    ({ t with early := before ++ (takeUntilIncl (·.2) (collected out ran order)).map Prod.fst }
        : TickRun P).events k =
      ({ t with early := before ++ seqReports out order } : TickRun P).events k ∧
      r.body.take r.pre.length = r.pre ∧
      ∀ e ∈ r.body.drop r.pre.length, ∃ p ∈ r.teardown, e = ⟨teardownTick r.ending, .report p⟩ := by
  refine ⟨by rw [par_reports out ran order hcover], by simp [Run.body], ?_⟩
  intro e he
  simp only [Run.body, List.drop_left, List.mem_map] at he
  obtain ⟨p, hp, rfl⟩ := he
  exact ⟨p, hp, rfl⟩

/-- The last committed tick: none after a cold-init failure (14:31); after a
failure in tick k, tick k + 1 if its Phase 4 commit happened, else tick k (the
spawn state for k = 0); after a splice window or a successful Phase 4 of tick k,
tick k + 1. -/
def lastCommitted : Ending → Option ℕ
  | .failed .coldInit _ => none
  | .failed (.exec k) c => some (if c then k + 1 else k)
  | .failed (.splice k) _ => some (k + 1)
  | .succeeded k => some (k + 1)

def isSuccess : Ending → Bool
  | .succeeded _ => true
  | .failed _ _ => false

/-- "`tick`, and `sim_time_ns` of the last committed state, or 0 and 0 for a
run that fails during cold init" (18:23). -/
def endLine {F : Type} (dt : ℕ+) (e : Ending) : Line F :=
  match lastCommitted e with
  | some k => .stop (isSuccess e) k (Schedule.tickTime dt k)
  | none => .stop (isSuccess e) 0 0

/-- P18-07. "End: ... `outcome` (`"success"` or `"failure"`), `tick`, and
`sim_time_ns` of the last committed state, or 0 and 0 for a run that fails
during cold init." (18-run-record.md:23) -/
theorem end_cold_init {F : Type} (dt : ℕ+) (b : Bool) :
    (endLine dt (.failed .coldInit b) : Line F) = .stop false 0 0 ∧
      (endLine dt (.failed (.exec 0) false) : Line F) = .stop false 0 0 := by
  refine ⟨rfl, ?_⟩
  simp [endLine, lastCommitted, isSuccess, Schedule.tickTime]

end Driveline.RunRecord

namespace Driveline.RunRecord

/-! ### Framing of a line -/

/-- A piece of an encoded line: literal text, or a string written by `jstr`. -/
inductive Tok
  | lit (s : List Char)
  | str (s : List Char)

def Tok.text : Tok → List Char
  | .lit s => s
  | .str s => jstr s

/-- A literal piece holds no whitespace. -/
def Tok.Bare : Tok → Prop
  | .lit s => ∀ c ∈ s, c.isWhitespace = false
  | .str _ => True

def fileToks (e : List Char × List Char) : List Tok :=
  [.lit ['{'], .str "path".toList, .lit [':'], .str e.1, .lit [','], .str "sha256".toList,
    .lit [':'], .str e.2, .lit ['}']]

def filesToks : List (List Char × List Char) → List Tok
  | [] => []
  | [e] => fileToks e
  | e :: e' :: es => fileToks e ++ .lit [','] :: filesToks (e' :: es)

def Val.toks {F : Type} (R : Renderer F) : Val F → List Tok
  | .nat n => [.lit (jnat n)]
  | .str s => [.str s]
  | .num x => [.lit (R.render x)]
  | .files fs => .lit ['['] :: filesToks fs ++ [.lit [']']]

def memberToks {F : Type} (R : Renderer F) (m : String × Val F) : List Tok :=
  .str m.1.toList :: .lit [':'] :: m.2.toks R

def membersToks {F : Type} (R : Renderer F) : List (String × Val F) → List Tok
  | [] => []
  | [m] => memberToks R m
  | m :: m' :: ms => memberToks R m ++ .lit [','] :: membersToks R (m' :: ms)

/-- The pieces of a line before its final `\n`. -/
def Line.toks {F : Type} (R : Renderer F) (l : Line F) : List Tok :=
  .lit ['{'] :: membersToks R l.members ++ [.lit ['}']]

theorem fileToks_text (e : List Char × List Char) :
    (fileToks e).flatMap Tok.text = fileEntry e := by
  simp [fileToks, fileEntry, Tok.text]

theorem filesToks_text : ∀ fs, (filesToks fs).flatMap Tok.text = fileEntries fs
  | [] => rfl
  | [e] => fileToks_text e
  | e :: e' :: es => by
    simp [filesToks, fileEntries, fileToks_text, filesToks_text (e' :: es), Tok.text]

theorem Val.toks_text {F : Type} (R : Renderer F) (v : Val F) :
    (v.toks R).flatMap Tok.text = v.render R := by
  cases v <;> simp [Val.toks, Val.render, Tok.text, jfiles, filesToks_text]

theorem membersToks_text {F : Type} (R : Renderer F) :
    ∀ ms, (membersToks R ms).flatMap Tok.text = members R ms
  | [] => rfl
  | [m] => by simp [membersToks, members, memberToks, member, Tok.text, Val.toks_text]
  | m :: m' :: ms => by
    simp [membersToks, members, memberToks, member, Tok.text, Val.toks_text,
      membersToks_text R (m' :: ms)]

theorem numChar_not_ws : ∀ c, numChar c → c.isWhitespace = false := by
  intro c h
  simp only [numChar] at h
  revert c
  decide

theorem fileToks_bare (e : List Char × List Char) : ∀ t ∈ fileToks e, t.Bare := by
  simp [fileToks, Tok.Bare]

theorem filesToks_bare : ∀ fs, ∀ t ∈ filesToks fs, t.Bare
  | [] => by simp [filesToks]
  | [e] => fileToks_bare e
  | e :: e' :: es => by
    intro t ht
    simp only [filesToks, List.mem_append, List.mem_cons] at ht
    rcases ht with ht | rfl | ht
    · exact fileToks_bare e t ht
    · simp [Tok.Bare]
    · exact filesToks_bare (e' :: es) t ht

theorem Val.toks_bare {F : Type} (R : Renderer F) (v : Val F) : ∀ t ∈ v.toks R, t.Bare := by
  cases v <;> simp only [Val.toks, List.mem_cons, List.mem_append, List.not_mem_nil, or_false]
  · rintro t rfl; exact fun c hc => numChar_not_ws c (jnat_numChar _ c hc)
  · rintro t rfl; trivial
  · rintro t rfl; exact fun c hc => numChar_not_ws c (R.alphabet _ c hc)
  · rintro t ((rfl | ht) | rfl)
    · simp [Tok.Bare]
    · exact filesToks_bare _ t ht
    · simp [Tok.Bare]

theorem membersToks_bare {F : Type} (R : Renderer F) :
    ∀ ms, ∀ t ∈ membersToks R ms, t.Bare
  | [] => by simp [membersToks]
  | [m] => by
    intro t ht
    simp only [membersToks, memberToks, List.mem_cons] at ht
    rcases ht with rfl | rfl | ht
    · trivial
    · simp [Tok.Bare]
    · exact Val.toks_bare R _ t ht
  | m :: m' :: ms => by
    intro t ht
    simp only [membersToks, memberToks, List.mem_append, List.mem_cons] at ht
    rcases ht with (rfl | rfl | ht) | rfl | ht
    · trivial
    · simp [Tok.Bare]
    · exact Val.toks_bare R _ t ht
    · simp [Tok.Bare]
    · exact membersToks_bare R (m' :: ms) t ht

theorem hex_ne_nl : ∀ n < 16, hex n ≠ '\n' := by decide

theorem nl_not_mem_escChar (c : Char) : '\n' ∉ escChar c := by
  unfold escChar
  split_ifs with h1 h2 h3
  · decide
  · decide
  · simp only [List.mem_cons, List.not_mem_nil, or_false, not_or]
    exact ⟨by decide, by decide, by decide, by decide, (hex_ne_nl _ (by omega)).symm,
      (hex_ne_nl _ (by omega)).symm⟩
  · simp only [List.mem_singleton]
    rintro rfl
    exact h3 (by decide)

theorem nl_not_mem_jstr (s : List Char) : '\n' ∉ jstr s := by
  intro h
  simp only [jstr, escape, List.cons_append, List.mem_cons, List.mem_append, List.mem_flatMap,
    List.mem_singleton, List.not_mem_nil, or_false] at h
  rcases h with h | ⟨c, _, h⟩ | h
  · exact absurd h (by decide)
  · exact nl_not_mem_escChar c h
  · exact absurd h (by decide)

theorem nl_not_mem_text (t : Tok) (h : t.Bare) : '\n' ∉ t.text := by
  cases t with
  | lit s => intro hm; have := h _ hm; revert this; decide
  | str s => exact nl_not_mem_jstr s

/-- P18-01. "The record is UTF-8 text in JSON Lines form. Each line is one JSON
object followed by `\n`, with no other whitespace. Members appear in the order
that §18.2 lists them, and every listed member is present. A string escapes `"`
as `\"`, `\` as `\\`, and each character from U+0000 to U+001F as `\u00`
followed by two lowercase hexadecimal digits. Every other character is written
as itself." (18-run-record.md:16). Two lines have the same encoding exactly
when they agree with their binary64 values replaced by their written text. A
line is a sequence of pieces followed by `\n`, where a whitespace character
lies only inside a `jstr` string, and `\n` occurs only as the last character.
The member order is the order of `Line.members`. -/
theorem encode_spec {F : Type} (R : Renderer F) :
    (∀ l₁ l₂ : Line F, encode R l₁ = encode R l₂ ↔ l₁.map R.render = l₂.map R.render) ∧
      ∀ l : Line F, encode R l = (l.toks R).flatMap Tok.text ++ ['\n'] ∧
        (∀ t ∈ l.toks R, t.Bare) ∧ '\n' ∉ (l.toks R).flatMap Tok.text := by
  have hb : ∀ l : Line F, ∀ t ∈ l.toks R, t.Bare := by
    intro l t ht
    simp only [Line.toks, List.mem_cons, List.mem_append, List.not_mem_nil, or_false] at ht
    rcases ht with (rfl | ht) | rfl
    · simp [Tok.Bare]
    · exact membersToks_bare R _ t ht
    · simp [Tok.Bare]
  refine ⟨encode_eq_iff R, fun l => ⟨?_, hb l, ?_⟩⟩
  · simp [encode, encodeObj, Line.toks, Tok.text, membersToks_text]
  · simp only [List.mem_flatMap, not_exists, not_and]
    exact fun t ht => nl_not_mem_text t (hb l t ht)

end Driveline.RunRecord
