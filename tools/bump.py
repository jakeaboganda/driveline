"""Record one atomic spec change: bump spec_version, stamp changed docs, add a changelog entry.

Usage: tools/bump.py [--abi] "Changelog line" [more lines ...] -- docs/spec/a.md [docs/spec/b.md ...]
--abi also bumps abi_version, the DL_ABI_VERSION macro, and the MIME versions in docs/spec/07.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def next_minor(v):
    major, minor = (int(x) for x in v.split("."))
    return f"{major}.{minor + 1}"


def set_front_matter(path, key, value):
    text = path.read_text()
    new, n = re.subn(rf"^{key}: .*$", f"{key}: {value}", text, count=1, flags=re.M)
    if n != 1:
        sys.exit(f"{path}: no front-matter key {key}")
    path.write_text(new)


def main(argv):
    abi = "--abi" in argv
    argv = [a for a in argv if a != "--abi"]
    if "--" not in argv:
        sys.exit(__doc__)
    split = argv.index("--")
    lines, docs = argv[:split], argv[split + 1:]
    if not lines or not docs:
        sys.exit(__doc__)

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import sync_deps
    docs = sorted(set(docs) | set(sync_deps.sync()))

    readme = ROOT / "README.md"
    meta = readme.read_text()
    old = re.search(r"^spec_version: (.*)$", meta, re.M).group(1)
    new = next_minor(old)
    set_front_matter(readme, "spec_version", new)
    for doc in docs:
        set_front_matter(ROOT / doc, "version", new)

    if abi:
        old_abi = re.search(r"^abi_version: (.*)$", meta, re.M).group(1)
        new_abi = next_minor(old_abi)
        major, minor = (int(x) for x in new_abi.split("."))
        set_front_matter(readme, "abi_version", new_abi)
        header = ROOT / "abi" / "driveline_abi.h"
        h = header.read_text()
        h = re.sub(r"DL_ABI_VERSION_\d+_\d+ 0x[0-9A-Fa-f]{8}U",
                   f"DL_ABI_VERSION_{major}_{minor} 0x{(major << 16 | minor << 8):08X}U", h)
        h = re.sub(r"DL_ABI_VERSION_\d+_\d+ \*/", f"DL_ABI_VERSION_{major}_{minor} */", h)
        header.write_text(h)
        fmu = ROOT / "docs" / "spec" / "07-fmu-packaging.md"
        fmu.write_text(re.sub(r";version=\d+\.\d+", f";version={new_abi}", fmu.read_text()))
        set_front_matter(fmu, "version", new)
        lines = lines + [f"ABI version {new_abi}."]

    changelog = ROOT / "CHANGELOG.md"
    text = changelog.read_text()
    entry = f"## {new}\n\n" + "".join(f"* {l}\n" for l in lines) + "\n"
    i = text.index("\n## ") + 1
    changelog.write_text(text[:i] + entry + text[i:])
    print(new)


if __name__ == "__main__":
    main(sys.argv[1:])
