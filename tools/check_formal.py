#!/usr/bin/env python3
"""Checks for the formal model and its obligations ledger. Exit status 1 on any failure."""
import os
import re
import subprocess
import sys
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
NAMESPACE = re.compile(r"^\s*namespace\s+([A-Za-z0-9_.]+)")
END = re.compile(r"^\s*end\s+([A-Za-z0-9_.]+)")
BANNED = re.compile(r"\b(sorry|admit|native_decide)\b")
AXIOM = re.compile(r"^axiom\s")
IMPORT = re.compile(r"^import\s+(Driveline(?:\.[A-Za-z0-9_]+)+)\s*$")
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


def code_lines(path):
    text = re.sub(r"/-.*?-/", lambda m: "\n" * m.group(0).count("\n"), path.read_text(), flags=re.S)
    return [(i, line) for i, line in enumerate(text.splitlines(), 1)
            if not line.lstrip().startswith("--")]


def check_name(row_id, name):
    module, short = name.rsplit(".", 1)
    path = FORMAL / (module.replace(".", "/") + ".lean")
    if not path.exists():
        fail(f"{row_id}: {name}: missing file {rel(path)}")
        return False
    decl = re.compile(
        r"^\s*(?:@\[[^\]]*\]\s*)?(?:private\s+|protected\s+)?(?:theorem|lemma)\s+"
        + re.escape(short) + r"\b"
    )
    scopes = []
    for _, line in code_lines(path):
        m = NAMESPACE.match(line)
        if m:
            scopes.append(m.group(1))
            continue
        m = END.match(line)
        if m:
            if scopes and scopes[-1] == m.group(1):
                scopes.pop()
            continue
        if decl.match(line) and ".".join(scopes) == module:
            return True
    fail(f"{row_id}: {name} is not declared in {rel(path)}")
    return False


def check_banned():
    before = len(failures)
    for path in [LIB_ROOT, *sorted(LIB_DIR.rglob("*.lean"))]:
        for lineno, line in code_lines(path):
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


def run_build():
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/.elan/bin") + os.pathsep + env.get("PATH", "")
    try:
        r = subprocess.run(["lake", "build"], cwd=FORMAL, env=env, capture_output=True, text=True)
    except FileNotFoundError as e:
        fail(f"lake build: {e}")
        return
    if r.returncode != 0:
        tail = "\n".join((r.stdout + r.stderr).splitlines()[-20:])
        fail(f"lake build (exit {r.returncode}):\n{tail}")
    else:
        notes.append("lake build")


def main(argv):
    if any(a != "--no-build" for a in argv):
        print("usage: check_formal.py [--no-build]", file=sys.stderr)
        return 2
    rows = parse_ledger()
    before = len(failures)
    counts = check_ledger(rows)
    if len(failures) == before:
        notes.append(f"ledger: {len(rows)} rows")
    before = len(failures)
    resolved = 0
    for _, row_id, status in rows:
        m = STATUS.fullmatch(status)
        if m and m.group(3):
            resolved += check_name(row_id, m.group(3))
    if len(failures) == before:
        notes.append(f"lean names: {resolved} resolved")
    check_banned()
    check_imports()
    if "--no-build" in argv:
        skipped = "skip lake build (--no-build)"
    else:
        skipped = None
        run_build()
    for n in notes:
        print("ok   ", n)
    if skipped:
        print(skipped)
    for key in COUNT_KEYS:
        print(f"  {key} {counts[key]}")
    for f in failures:
        print("FAIL ", f)
    print(f"{len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
