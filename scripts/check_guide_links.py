#!/usr/bin/env python3
"""Check documentation links and pinned source lines against the current tree.

Run with --refresh only after reviewing moved code and updating the guide's
line anchors. The fingerprint file is maintenance data, not reader material.
"""

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
FINGERPRINTS = ROOT / ".github" / "guide-source-anchors.json"
LINK = re.compile(r"!?\[[^]]*\]\(([^)]+)\)")
LINE = re.compile(r"L([1-9][0-9]*)(?:-L([1-9][0-9]*))?")


def headings(path: Path) -> set[str]:
    result = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("#"):
            continue
        label = line.lstrip("#").strip().lower()
        label = re.sub(r"[^\w -]", "", label)
        result.add(re.sub(r" +", "-", label))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="record reviewed current anchor lines")
    args = parser.parse_args()
    expected = json.loads(FINGERPRINTS.read_text(encoding="utf-8")) if FINGERPRINTS.exists() else {}
    actual = {}
    errors = []
    pages = [ROOT / "README.md", *sorted((ROOT / "docs").glob("*.md")),
             *sorted((ROOT / "docs" / "guide").glob("*.md"))]
    for page in pages:
        for number, text in enumerate(page.read_text(encoding="utf-8").splitlines(), 1):
            for match in LINK.finditer(text):
                target = match.group(1)
                if target.startswith(("http://", "https://", "mailto:")):
                    continue
                file_part, _, fragment = target.partition("#")
                destination = (page.parent / file_part).resolve() if file_part else page
                location = f"{page.relative_to(ROOT)}:{number}"
                if not destination.exists():
                    errors.append(f"{location}: missing {target}")
                    continue
                if not fragment:
                    continue
                line_match = LINE.fullmatch(fragment)
                if line_match:
                    if not destination.is_file():
                        errors.append(f"{location}: line anchor on directory {target}")
                        continue
                    lines = destination.read_text(encoding="utf-8").splitlines()
                    start = int(line_match.group(1))
                    end = int(line_match.group(2) or start)
                    if start > end or end > len(lines):
                        errors.append(f"{location}: line outside {target}")
                        continue
                    key = f"{destination.relative_to(ROOT)}#{fragment}"
                    actual[key] = "\n".join(lines[start - 1:end])
                elif destination.suffix == ".md" and fragment not in headings(destination):
                    errors.append(f"{location}: missing heading {target}")
    if args.refresh:
        if errors:
            print("\n".join(errors))
            return 1
        FINGERPRINTS.write_text(json.dumps(dict(sorted(actual.items())), indent=2) + "\n", encoding="utf-8")
        print(f"Recorded {len(actual)} source anchors")
        return 0
    for key, value in actual.items():
        if key not in expected:
            errors.append(f"untracked source anchor {key}")
        elif expected[key] != value:
            errors.append(f"stale source anchor {key}")
    for key in expected.keys() - actual.keys():
        errors.append(f"unused source anchor {key}")
    if errors:
        print("\n".join(errors))
        return 1
    print(f"Guide links valid; {len(actual)} source anchors match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
