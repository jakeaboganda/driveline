"""Mechanical checks for the Driveline specification. Exit status 1 on any failure."""
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "spec"
HEADER = ROOT / "abi" / "driveline_abi.h"
EXAMPLES = ROOT / "examples"

failures = []
notes = []


def fail(msg):
    failures.append(msg)


def version_tuple(v):
    return tuple(int(x) for x in str(v).split("."))


def front_matter(path):
    text = path.read_text()
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        fail(f"{path.relative_to(ROOT)}: missing front-matter")
        return {}, text
    meta = {}
    for line in m.group(1).splitlines():
        key, _, value = line.partition(":")
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            value = [v.strip() for v in value[1:-1].split(",") if v.strip()]
        meta[key.strip()] = value
    return meta, text[m.end():]


def outside_fences(body):
    out, fence = [], False
    for line in body.splitlines():
        if line.startswith("```"):
            fence = not fence
            continue
        if not fence:
            out.append(line)
    return "\n".join(out)


def check_docs():
    readme_meta, readme_body = front_matter(ROOT / "README.md")
    for key in ("title", "spec_version", "abi_version", "status"):
        if key not in readme_meta:
            fail(f"README.md: front-matter lacks {key}")
    spec_version = version_tuple(readme_meta.get("spec_version", "0"))

    changelog_meta, changelog = front_matter(ROOT / "CHANGELOG.md")
    first = re.search(r"^## (\S+)", changelog, re.M)
    if not first or first.group(1) != readme_meta.get("spec_version"):
        fail("CHANGELOG.md: first entry must match spec_version")

    docs = {}
    for path in sorted(SPEC.glob("*.md")):
        meta, body = front_matter(path)
        docs[path.name] = (meta, body)
        for key in ("title", "version", "status", "normative", "depends_on"):
            if key not in meta:
                fail(f"spec/{path.name}: front-matter lacks {key}")
        if "version" in meta and version_tuple(meta["version"]) > spec_version:
            fail(f"spec/{path.name}: version {meta['version']} is newer than spec_version")
        for dep in meta.get("depends_on", []):
            if not (SPEC / dep).exists():
                fail(f"spec/{path.name}: depends_on {dep} does not exist")
        h1 = re.findall(r"^# (.*)$", outside_fences(body), re.M)
        if len(h1) != 1:
            fail(f"spec/{path.name}: expected one h1, found {len(h1)}")
        if "section" in meta and h1 and not h1[0].startswith(f"{meta['section']}. "):
            fail(f"spec/{path.name}: h1 does not start with section {meta['section']}")

    changed = [n for n, (m, _) in docs.items() if m.get("version") == readme_meta.get("spec_version")]
    notes.append(f"docs changed in {readme_meta.get('spec_version')}: {', '.join(changed) or 'none'}")

    headings = {}
    for name, (meta, body) in docs.items():
        for num in re.findall(r"^#{1,4} (\d+(?:\.\d+)*)[. ]", outside_fences(body), re.M):
            headings[num] = name

    section_file = {m["section"]: n for n, (m, _) in docs.items() if "section" in m}
    for num, name in section_file.items():
        if f"(spec/{name})" not in readme_body:
            fail(f"README.md: document table lacks spec/{name}")

    for name, (meta, body) in [*docs.items(), ("../README.md", (readme_meta, readme_body)),
                               ("../CHANGELOG.md", (changelog_meta, changelog))]:
        text = outside_fences(body)
        base = (SPEC / name).parent
        for target in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", text):
            if not target.startswith("http") and not (base / target).exists():
                fail(f"{name}: broken link {target}")
        if name.startswith(".."):
            continue
        for ref, target in re.findall(r"\[§(\d+(?:\.\d+)*)\]\(([^)]+)\)", text):
            parts = ref.split(".")
            if section_file.get(parts[0]) != target:
                fail(f"spec/{name}: §{ref} links to {target}, expected {section_file.get(parts[0])}")
            prefixes = [".".join(parts[:i]) for i in range(len(parts), 0, -1)]
            if not any(p in headings for p in prefixes[:2]):
                fail(f"spec/{name}: §{ref} has no matching heading")
        if re.search(r"\bv\d+\.\d+\b", text):
            fail(f"spec/{name}: names a spec version in prose; versions live in front-matter")
        if re.search(r"\bSections? \d", text):
            fail(f"spec/{name}: cites sections by bare number; use linked § references")
        if re.search(r"\bAppendix [A-Z]\b", text):
            fail(f"spec/{name}: refers to an appendix; the suite has none")
        deps = set(meta.get("depends_on", []))
        linked = {t for t in re.findall(r"\]\((\d\d-[\w-]+\.md)\)", text)
                  if t != name and docs[t][0].get("normative") == "true"}
        expected = linked if meta.get("normative") == "true" else set()
        if deps != expected:
            fail(f"spec/{name}: depends_on differs from its links; run tools/sync_deps.py")
        bare = re.findall(r"(?<!\[)§\d+(?:\.\d+)*", text)
        if bare:
            fail(f"spec/{name}: unlinked section references {sorted(set(bare))}")
    return readme_meta, docs


def struct_names(header_text):
    names = []
    for body, name in re.findall(r"typedef struct \{(.*?)\} (\w+);", header_text, re.S):
        if "*" not in re.sub(r"/\*.*?\*/", "", body, flags=re.S):
            names.append(name)
    return names


def compile_sizes(flags, names, tmp):
    src = tmp / "sizes.c"
    src.write_text(f'#include "{HEADER}"\n#include <stdio.h>\nint main(void){{\n' + "".join(
        f'printf("{n} %zu\\n", sizeof({n}));\n' for n in names) + "return 0;}\n")
    exe = tmp / "sizes"
    subprocess.run(["gcc", "-std=c11", *flags, str(src), "-o", str(exe)], check=True,
                   capture_output=True, text=True)
    out = subprocess.run([str(exe)], check=True, capture_output=True, text=True).stdout
    return dict(line.split() for line in out.splitlines())


def check_abi(readme_meta):
    text = HEADER.read_text()
    m = re.search(r"#define DL_ABI_VERSION_(\d+)_(\d+) (0x[0-9A-Fa-f]{8})U", text)
    if not m:
        fail("abi: DL_ABI_VERSION macro not found")
    else:
        major, minor, value = int(m.group(1)), int(m.group(2)), int(m.group(3), 16)
        if f"{major}.{minor}" != readme_meta.get("abi_version"):
            fail(f"abi: macro version {major}.{minor} != README abi_version")
        if value != (major << 16 | minor << 8):
            fail("abi: macro name and value disagree")
    fmu = (SPEC / "07-fmu-packaging.md").read_text()
    for v in set(re.findall(r";version=(\d+\.\d+)", fmu)):
        if v != readme_meta.get("abi_version"):
            fail(f"spec/07-fmu-packaging.md: MIME version {v} != abi_version")
    base = ["gcc", "-std=c11", "-Wall", "-Wextra", "-Wpadded", "-Werror", "-fsyntax-only", "-x", "c"]
    r = subprocess.run([*base, str(HEADER)], capture_output=True, text=True)
    if r.returncode:
        fail("abi: 64-bit compile failed\n" + r.stderr)
        return
    names = struct_names(text)
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        sizes64 = compile_sizes([], names, tmp)
        r32 = subprocess.run([*base, "-m32", "-ffreestanding", str(HEADER)], capture_output=True, text=True)
        if r32.returncode and ("stubs-32" in r32.stderr or "wordsize" in r32.stderr):
            notes.append("abi: 32-bit toolchain missing, 32-bit step skipped")
            return
        if r32.returncode:
            fail("abi: 32-bit compile failed\n" + r32.stderr)
            return
        probe = tmp / "probe.c"
        probe.write_text(f'#include "{HEADER}"\n' + "".join(
            f'_Static_assert(sizeof({n}) == {sizes64[n]}, "{n}");\n' for n in names))
        r = subprocess.run(["gcc", "-std=c11", "-m32", "-ffreestanding", "-fsyntax-only", str(probe)],
                           capture_output=True, text=True)
        if r.returncode:
            fail("abi: 32-bit and 64-bit sizes differ\n" + r.stderr)
    notes.append(f"abi: {len(names)} pointer-free structs, identical sizes on 64-bit and 32-bit")


def check_grammar(docs):
    from lark import Lark

    body = docs["12-grammar.md"][1]
    ebnf = re.search(r"```ebnf\n(.*?)```", body, re.S).group(1)
    reserved = re.search(r"The reserved words are (.*?)\. Every other", body).group(1)
    reserved = re.findall(r"`(\w+)`", reserved)
    units = re.search(r"`UnitName` is one of (.*?)\. ", body).group(1)
    units = sorted(re.findall(r"`(\w+)`", units), key=len, reverse=True)
    lexical = {"Ident", "IntLit", "HexLit", "FloatLit", "StringLit", "QuantityLit", "FreqLit", "TimeLit"}

    def snake(name):
        return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()

    def convert(rhs):
        out = []
        for tok in re.findall(r'"[^"]*"|[A-Za-z_]\w*|[()|*+?]', rhs):
            if tok.startswith('"'):
                out.append(tok)
            elif tok in lexical:
                out.append(tok.upper())
            elif re.match(r"[A-Za-z_]", tok):
                out.append(snake(tok))
            else:
                out.append(tok)
        return " ".join(out)

    rules = []
    for line in ebnf.splitlines():
        if not line.strip():
            continue
        m = re.match(r"(\w+)\s*::=(.*)", line)
        if m:
            rules.append([m.group(1), m.group(2)])
        else:
            rules[-1][1] += " " + line.strip()
    unit = "(?:" + "|".join(units) + r")(?:\^\d+)?"
    num = r"(?:\d+\.\d+|\d+)"
    src = "\n".join(f"{snake(n)}: {convert(b)}" for n, b in rules) + f"""
IDENT: /(?!(?:{'|'.join(reserved)})\\b)[A-Za-z_]\\w*/
QUANTITYLIT: /{num}{unit}(?:[*\\/]{unit})*(?![A-Za-z0-9_])/
FREQLIT: /{num}Hz(?![A-Za-z0-9_])/
TIMELIT: /{num}(?:ms|us|ns|s)(?![A-Za-z0-9_])/
FLOATLIT: /\\d+\\.\\d+/
HEXLIT: /0x[0-9A-Fa-f]+/
INTLIT: /\\d+/
STRINGLIT: /"(?:\\\\.|[^"\\\\])*"/
%ignore /\\s+/
%ignore /\\/\\/[^\\n]*/
"""
    parser = Lark(src, start="scenario_file", parser="earley", lexer="dynamic")
    if not list(EXAMPLES.glob("*.dline")):
        fail("grammar: no example scenarios to parse")
    for path in sorted(EXAMPLES.glob("*.dline")):
        try:
            parser.parse(path.read_text())
            notes.append(f"grammar: {path.name} parses ({len(rules)} rules)")
        except Exception as e:
            fail(f"grammar: {path.name} does not parse\n{e}")


def check_vehicle_spec_fields():
    header = HEADER.read_text()
    scenario = (EXAMPLES / "kanagawa_pinch_test.dline").read_text()
    for tier, struct in (("tier0", "dl_kinematic_params_t"), ("tier1", "dl_single_track_params_t"),
                         ("tier2", "dl_multibody_params_t")):
        body = re.search(r"typedef struct \{([^{}]*)\} " + struct + ";", header).group(1)
        body = re.sub(r"/\*.*?\*/", "", body)
        members = set()
        for decl in body.split(";"):
            names = decl.split()[1:] if decl.split() else []
            for n in " ".join(names).split(","):
                n = re.sub(r"\[.*\]", "", n).strip()
                if n and not n.startswith("_") and n != "num_gears":
                    members.add(n)
        block = re.search(tier + r"\s*=\s*\{(.*?)\};", scenario, re.S).group(1)
        fields = set(re.findall(r"(\w+)\s*:", block))
        if fields != members:
            fail(f"vehicle_spec {tier}: missing {sorted(members - fields)}, unknown {sorted(fields - members)}")
    notes.append("vehicle_spec: example tier records match the header structs")


def check_scenario_rules():
    from fractions import Fraction

    scenario = (EXAMPLES / "kanagawa_pinch_test.dline").read_text()
    scenario = re.sub(r"//[^\n]*", "", scenario)
    step = re.search(r"timestep\s*=\s*([0-9.]+)s\b", scenario).group(1)
    base_ns = Fraction(step) * 10**9
    for hz in re.findall(r"rate:\s*([0-9.]+)Hz", scenario):
        k = Fraction(10**9) / (base_ns * Fraction(hz))
        if k.denominator != 1 or k < 1:
            fail(f"scenario: {hz}Hz does not divide the base clock ({step}s)")
    ids = [int(i) for i in re.findall(r"spawn\(id:\s*(\d+)", scenario)]
    if len(ids) != len(set(ids)) or min(ids) < 1:
        fail(f"scenario: actor ids {ids} are not unique and >= 1")
    history = {}
    for actor, body in re.findall(r"actor (\w+) = spawn\(.*?\) with \{(.*?)\n    \};", scenario, re.S):
        for name, n in re.findall(r"(\w+)\s*=\s*\w+\([^;]*history:\s*(\d+)", body):
            history[(actor, name)] = int(n)
    ports = {}
    for comp, portlist in re.findall(r"component (\w+)[^;{]*?\):\s*\((.*?)\)\s*->", scenario, re.S):
        for port, n in re.findall(r"(\w+):\s*SliceBuffer<\w+,\s*(\d+)>", portlist):
            ports[(comp, port)] = int(n)
    checked = 0
    for actor, body in re.findall(r"actor (\w+) = spawn\(.*?\) with \{(.*?)\n    \};", scenario, re.S):
        for comp, args in re.findall(r"(\w+)\(([^()]*sensors\.[^()]*)\)", body):
            for port, sensor in re.findall(r"(\w+):\s*sensors\.(\w+)", args):
                need = ports.get((comp, port))
                have = history.get((actor, sensor))
                if need is None:
                    continue
                checked += 1
                if have is None or have < need:
                    fail(f"scenario: {actor}.{sensor} history {have} < {comp}.{port} capacity {need}")
    if checked == 0:
        fail("scenario: no sensor-to-port bindings found to check")
    notes.append(f"scenario: rates divide the base clock, ids {sorted(ids)} unique, "
                 f"{checked} buffer bindings fit their capacities")


def struct_members(header, struct):
    body = re.search(r"typedef struct \{([^{}]*)\} " + struct + ";", header).group(1)
    body = re.sub(r"/\*.*?\*/", "", body)
    out = set()
    for decl in body.split(";"):
        words = decl.split()
        for n in " ".join(words[1:]).split(","):
            n = re.sub(r"\[.*\]", "", n).strip()
            if n and not n.startswith("_"):
                out.add(n)
    return out


def check_frame_tables(docs):
    header = HEADER.read_text()
    body = docs["05-checkpoints.md"][1]
    sections = {"dl_intent_frame_t": ("## 5.1", "## 5.2"),
                "dl_kinematic_control_frame_t": ("### Tier A", "### Tier B"),
                "dl_actuator_control_frame_t": ("### Tier B", "## 5.3"),
                "dl_kinematic_state_t": ("## 5.3", None)}
    for struct, (start, end) in sections.items():
        part = body[body.index(start): body.index(end) if end else len(body)]
        rows = [l for l in part.splitlines() if l.startswith("|") and not l.startswith("| :")][1:]
        names = set()
        for row in rows:
            cells = [c.strip() for c in row.strip("|").split("|")]
            cell = cells[1] if cells[0].startswith("**") or cells[0] == "" else cells[0]
            names |= set(re.findall(r"`([a-z_]+)`", cell))
        members = struct_members(header, struct)
        if names != members:
            fail(f"05-checkpoints.md: {struct} table differs from header: "
                 f"table only {sorted(names - members)}, header only {sorted(members - names)}")
    notes.append("frame tables in section 5 match the header structs")


def check_test_vector(docs):
    scenario = (EXAMPLES / "kanagawa_pinch_test.dline").read_text()

    def param(name):
        return float(re.search(rf"\b{name}:\s*([0-9.]+)", scenario).group(1))

    m, lf, lr = param("mass"), param("cg_dist_front"), param("cg_dist_rear")
    caf, car, L = param("cornering_stiffness_f"), param("cornering_stiffness_r"), param("wheelbase")
    v, r = 28.0, 28.0 / 500.0
    ay = v * r
    af, ar = m * ay * lr / L / caf, m * ay * lf / L / car
    vlat = -v * math.tan(ar)
    dss = af + math.atan((vlat + L * r) / v)
    dks = math.atan(L * r / v)
    beta = math.atan((vlat + lr * r) / v)
    body = docs["08-steady-state.md"][1]
    for value in (f"{ay:.3f}", f"{vlat:.4f}", f"{dks:.5f}", f"{dss:.5f}", f"{beta:.5f}"):
        if value not in body:
            fail(f"test vector: {value} not found in spec/08-steady-state.md")
    moment = lf * caf * (dss - math.atan((vlat + L * r) / v)) - lr * car * (-math.atan(vlat / v))
    if abs(moment) > 1e-6:
        fail(f"test vector: yaw moment {moment} is not zero")
    notes.append("test vector: recomputed values match spec/08-steady-state.md")

    iz = param("inertia_zz")
    vy = vlat + lr * r
    alpha_f = dss - math.atan((vy + lf * r) / v)
    alpha_r = -math.atan((vy - lr * r) / v)
    fyf, fyr = caf * alpha_f, car * alpha_r
    vy_dot = (fyf + fyr) / m - v * r
    r_dot = (lf * fyf - lr * fyr) / iz
    if abs(vy_dot) > 1e-9 or abs(r_dot) > 1e-9:
        fail(f"std DynamicSingleTrack is not at rest in the section 8 steady state: "
             f"vy_dot={vy_dot:.3e}, r_dot={r_dot:.3e}")
    else:
        notes.append("std DynamicSingleTrack derivatives vanish at the section 8 steady state")


def check_siphash(docs):
    import struct
    sys.path.insert(0, str(ROOT / "tools"))
    from siphash import siphash24

    key = bytes(range(16))
    reference = {0: 0x726FDB47DD0E0E31, 8: 0x93F5F5799A932462, 15: 0xA129CA6149BE45E5}
    for length, expected in reference.items():
        if siphash24(key, bytes(range(length))) != expected:
            fail(f"siphash: reference vector for length {length} fails")
            return
    body = docs["11-execution.md"][1]
    vectors = re.findall(r"`scenario_seed = (\d+)`, `actor_id = (\d+)`, `sensor_port_index = (\d+)`, "
                         r"`k_tick = (\d+)` gives `(0x[0-9a-f]{16})`", body)
    if not vectors:
        fail("siphash: no seed test vectors in spec/11-execution.md")
    for scn, actor, port, tick, expected in vectors:
        got = siphash24(struct.pack("<QQ", int(scn), 0), struct.pack("<QIIQ", int(actor), int(port), 0, int(tick)))
        if got != int(expected, 16):
            fail(f"siphash: seed vector {scn},{actor},{port},{tick} gives 0x{got:016x}, spec says {expected}")
    notes.append(f"siphash: reference vectors pass, {len(vectors)} seed vectors match")


def main():
    readme_meta, docs = check_docs()
    check_abi(readme_meta)
    check_grammar(docs)
    check_vehicle_spec_fields()
    check_scenario_rules()
    check_frame_tables(docs)
    check_test_vector(docs)
    check_siphash(docs)
    for n in notes:
        print("ok   ", n)
    for f in failures:
        print("FAIL ", f)
    print(f"{len(failures)} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
