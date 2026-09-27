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
    for path in sorted(EXAMPLES.glob("*.dline")):
        try:
            parser.parse(path.read_text())
            notes.append(f"grammar: {path.name} parses ({len(rules)} rules)")
        except Exception as e:
            fail(f"grammar: {path.name} does not parse\n{e}")


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


def main():
    readme_meta, docs = check_docs()
    check_abi(readme_meta)
    check_grammar(docs)
    check_test_vector(docs)
    for n in notes:
        print("ok   ", n)
    for f in failures:
        print("FAIL ", f)
    print(f"{len(failures)} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
