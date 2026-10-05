#!/usr/bin/env python3
"""Checks for the formal model and its obligations ledger. Exit status 1 on any failure.

Only the full run is a gate: --no-build skips lake build and the Lean axiom audit,
so it checks just the ledger, the textual ban, and the imports.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ROOT / "docs" / "formal" / "obligations.md"
FORMAL = ROOT / "formal"
LIB_ROOT = FORMAL / "Driveline.lean"
LIB_DIR = FORMAL / "Driveline"

ROW = re.compile(r"^\|\s*([A-Z]+\d*-\d{2})\s*\|")
STATUS = re.compile(
    r"^(TODO|CHECKED|OUT: external|OUT: prose"
    r"|(PROVED|REFUTED): (Driveline(?:\.[A-Za-z_][A-Za-z0-9_']*)+)"
    r"|DUP: ([A-Z]+\d*-\d{2}))$"
)
BANNED = re.compile(r"\b(sorry\w*|admit|native_decide|debug\.skipKernelTC|unsafe)\b")
AXIOM = re.compile(r"^\s*(@\[[^\]]*\]\s*)*((private|protected|noncomputable)\s+)*axiom\b")
IMPORT = re.compile(r"^import\s+(Driveline(?:\.[A-Za-z0-9_]+)+)\s*$")
AXIOMS_USED = re.compile(r"^'(.+)' depends on axioms: \[(.*)\]$")
NO_AXIOMS = re.compile(r"^'(.+)' does not depend on any axioms$")
ALLOWED_AXIOMS = {"propext", "Classical.choice", "Quot.sound"}
COUNT_KEYS = ["TODO", "PROVED", "REFUTED", "CHECKED", "OUT: external", "OUT: prose", "DUP"]

failures = []
notes = []


def fail(msg):
    failures.append(msg)


def rel(path):
    return path.relative_to(ROOT)


def parse_ledger():
    rows = []
    for lineno, line in enumerate(LEDGER.read_text().splitlines(), 1):
        m = ROW.match(line)
        if m:
            status = line.strip().strip("|").split("|")[-1].strip().strip("`").strip()
            rows.append((lineno, m.group(1), status))
    return rows


def check_ledger(rows):
    counts = dict.fromkeys(COUNT_KEYS, 0)
    seen = {}
    for lineno, row_id, _ in rows:
        if row_id in seen:
            fail(f"{rel(LEDGER)}: duplicate ID {row_id} at lines {seen[row_id]} and {lineno}")
        else:
            seen[row_id] = lineno
    for lineno, row_id, status in rows:
        m = STATUS.fullmatch(status)
        if not m:
            fail(f"{rel(LEDGER)}:{lineno}: {row_id} has bad status {status!r}")
            continue
        if m.group(2):
            counts[m.group(2)] += 1
        elif m.group(4):
            counts["DUP"] += 1
            target = m.group(4)
            if target == row_id:
                fail(f"{rel(LEDGER)}:{lineno}: {row_id} is a DUP of itself")
            elif target not in seen:
                fail(f"{rel(LEDGER)}:{lineno}: {row_id} is a DUP of unknown row {target}")
        else:
            counts[status] += 1
    return counts


def check_banned():
    """Defense in depth only; the axiom audit is the real check. Scans raw lines, comments included."""
    before = len(failures)
    for path in [LIB_ROOT, *sorted(LIB_DIR.rglob("*.lean"))]:
        for lineno, line in enumerate(path.read_text().splitlines(), 1):
            m = BANNED.search(line)
            if m:
                fail(f"{rel(path)}:{lineno}: banned token {m.group(1)}")
            if AXIOM.match(line):
                fail(f"{rel(path)}:{lineno}: banned token axiom")
    if len(failures) == before:
        notes.append("banned tokens")


def check_imports():
    expected = {"Driveline." + ".".join(p.relative_to(LIB_DIR).with_suffix("").parts)
                for p in LIB_DIR.rglob("*.lean")}
    actual = set()
    for line in LIB_ROOT.read_text().splitlines():
        m = IMPORT.match(line)
        if m:
            actual.add(m.group(1))
    missing = sorted(expected - actual)
    for name in missing:
        fail(f"{rel(LIB_ROOT)}: does not import {name}")
    if not missing:
        notes.append("imports")


def lean_env():
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/.elan/bin") + os.pathsep + env.get("PATH", "")
    return env


def run_build():
    try:
        r = subprocess.run(["lake", "build"], cwd=FORMAL, env=lean_env(), capture_output=True, text=True)
    except FileNotFoundError as e:
        fail(f"lake build: {e}")
        return False
    out = r.stdout + r.stderr
    if r.returncode != 0:
        tail = "\n".join(out.splitlines()[-20:])
        fail(f"lake build (exit {r.returncode}):\n{tail}")
        return False
    sorries = [line for line in out.splitlines() if "declaration uses" in line]
    for line in sorries:
        fail(f"lake build: {line.strip()}")
    if not sorries:
        notes.append("lake build")
    return True


def audit_axioms(names):
    """Ask Lean which axioms each ledger theorem depends on."""
    with tempfile.NamedTemporaryFile("w", suffix=".lean", delete=False) as f:
        f.write("import Driveline\n" + "".join(f"#print axioms {n}\n" for n in names))
    try:
        r = subprocess.run(["lake", "env", "lean", "--json", f.name],
                           cwd=FORMAL, env=lean_env(), capture_output=True, text=True)
    except FileNotFoundError as e:
        fail(f"axiom audit: {e}")
        return
    finally:
        os.unlink(f.name)
    # Line 1 is the import; name i is on line i + 2.
    by_line = {}
    for raw in r.stdout.splitlines():
        try:
            msg = json.loads(raw)
            by_line.setdefault(msg["pos"]["line"], []).append(msg)
        except (ValueError, KeyError, TypeError):
            fail(f"axiom audit: unexpected output {raw!r}")
    if r.returncode != 0 and not by_line:
        tail = "\n".join((r.stdout + r.stderr).splitlines()[-20:])
        fail(f"axiom audit (exit {r.returncode}):\n{tail}")
        return
    before = len(failures)
    for i, name in enumerate(names):
        msgs = by_line.pop(i + 2, [])
        if len(msgs) != 1 or msgs[0].get("severity") != "information":
            text = "; ".join(m.get("data", "") for m in msgs) or "no output"
            fail(f"{name}: {text}")
            continue
        data = msgs[0].get("data", "").strip()
        m = AXIOMS_USED.match(data) or NO_AXIOMS.match(data)
        if not m or m.group(1) != name:
            fail(f"{name}: unexpected output {data!r}")
            continue
        used = {a.strip() for a in m.group(2).split(",")} if m.re is AXIOMS_USED else set()
        bad = sorted(used - ALLOWED_AXIOMS)
        if bad:
            fail(f"{name}: depends on disallowed axioms {', '.join(bad)}")
    for line, msgs in sorted(by_line.items()):
        for m in msgs:
            fail(f"axiom audit: line {line}: {m.get('data', '')}")
    if len(failures) == before:
        notes.append(f"axiom audit: {len(names)} names")


def main(argv):
    if any(a != "--no-build" for a in argv):
        print("usage: check_formal.py [--no-build]", file=sys.stderr)
        return 2
    rows = parse_ledger()
    before = len(failures)
    counts = check_ledger(rows)
    if len(failures) == before:
        notes.append(f"ledger: {len(rows)} rows")
    names = [m.group(3) for m in (STATUS.fullmatch(status) for _, _, status in rows)
             if m and m.group(3)]
    check_banned()
    check_imports()
    skipped = []
    if "--no-build" in argv:
        skipped.append("skip lake build (--no-build)")
        skipped.append("skip axiom audit (--no-build)")
    elif run_build():
        audit_axioms(names)
    else:
        skipped.append("skip axiom audit (lake build failed)")
    for n in notes:
        print("ok   ", n)
    for s in skipped:
        print(s)
    for key in COUNT_KEYS:
        print(f"  {key} {counts[key]}")
    for f in failures:
        print("FAIL ", f)
    print(f"{len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
