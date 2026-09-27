"""Rewrite each spec document's depends_on from the normative documents it links to."""
import re
from pathlib import Path

SPEC = Path(__file__).resolve().parent.parent / "spec"


def normative(path):
    return re.search(r"^normative: true$", path.read_text(), re.M) is not None


def linked(path):
    body = re.sub(r"```.*?```", "", path.read_text().split("\n---\n", 1)[1], flags=re.S)
    return sorted({t for t in re.findall(r"\]\((\d\d-[\w-]+\.md)\)", body)
                   if t != path.name and normative(SPEC / t)})


def main():
    for path in sorted(SPEC.glob("*.md")):
        text = path.read_text()
        deps = linked(path) if normative(path) else []
        new = re.sub(r"^depends_on: .*$", "depends_on: [" + ", ".join(deps) + "]", text, count=1, flags=re.M)
        if new != text:
            path.write_text(new)
            print(path.relative_to(SPEC.parent))


if __name__ == "__main__":
    main()
