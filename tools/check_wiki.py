#!/usr/bin/env python3
"""Check docs/wiki/: the pages link to each other correctly and the decisions are kept in order.

Usage:
    python3 tools/check_wiki.py                 # in the repository root
    python3 tools/check_wiki.py --root path/to/copy

Exit status: 0 when the wiki is sound, 1 with one line per problem, 2 if the arguments are wrong.

What it checks:
  - every relative link `](Page)` or `](Page.md#anchor)` names a page that exists (the wiki is published flat, so
    a link to a repository path would be dead there);
  - every page is reachable from Home.md or _Sidebar.md, so the wiki does not publish a page nobody can find;
  - every ADR-NNNN-*.md page is listed in ADR-Index.md, and the index lists no page that is not there;
  - ADR numbers are unique and have no gaps (a gap is a decision that was deleted or never written);
  - every ADR has a title `# ADR-NNNN: ...` whose number matches its file name, and a `**Status:**` line.

Requires only the Python standard library.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

LINK = re.compile(r"\]\(([^)\s]+)\)")
ADR_FILE = re.compile(r"^ADR-(\d{4})-.+\.md$")
ADR_TITLE = re.compile(r"^# ADR-(\d{4}): \S")


def problems(wiki: Path) -> list[str]:
    out: list[str] = []
    pages = {p.stem: p for p in wiki.glob("*.md")}
    if "Home" not in pages:
        return ["Home.md is missing; the wiki would have no front page."]

    links: dict[str, set[str]] = {}
    for name, path in pages.items():
        text = path.read_text(encoding="utf-8")
        targets: set[str] = set()
        for match in LINK.finditer(text):
            target = match.group(1).split("#", 1)[0]
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            stem = target[:-3] if target.endswith(".md") else target
            if stem not in pages:
                out.append(f"{path.name}: the link to '{target}' names no page in docs/wiki/.")
            else:
                targets.add(stem)
        links[name] = targets

    reached = {"Home"}
    queue = ["Home"] + (["_Sidebar"] if "_Sidebar" in pages else [])
    reached.update(queue)
    while queue:
        for nxt in links.get(queue.pop(), ()):
            if nxt not in reached:
                reached.add(nxt)
                queue.append(nxt)
    for name in sorted(pages):
        if name not in reached and name != "_Sidebar":
            out.append(f"{name}.md: no chain of links from Home.md or _Sidebar.md reaches it.")

    adrs: dict[int, Path] = {}
    for name, path in pages.items():
        match = ADR_FILE.match(path.name)
        if not match:
            continue
        number = int(match.group(1))
        if number in adrs:
            out.append(f"{path.name}: ADR number {number:04d} is also used by {adrs[number].name}.")
        adrs[number] = path
        text = path.read_text(encoding="utf-8")
        first = next((line for line in text.splitlines() if line.strip()), "")
        title = ADR_TITLE.match(first)
        if not title:
            out.append(f"{path.name}: the first line must be '# ADR-{number:04d}: <the decision>'.")
        elif int(title.group(1)) != number:
            out.append(f"{path.name}: the title says ADR-{title.group(1)} but the file name says {number:04d}.")
        if "**Status:**" not in text:
            out.append(f"{path.name}: it has no '**Status:**' line.")

    if adrs:
        top = max(adrs)
        for n in range(1, top + 1):
            if n not in adrs:
                out.append(f"ADR-{n:04d} is missing: numbers run to {top:04d} with a gap.")

    index = pages.get("ADR-Index")
    if index is None:
        out.append("ADR-Index.md is missing.")
    else:
        listed = set(links.get("ADR-Index", ()))
        for path in adrs.values():
            if path.stem not in listed:
                out.append(f"{path.name}: it is not listed in ADR-Index.md.")
        for stem in sorted(listed):
            if ADR_FILE.match(stem + ".md") and stem not in {p.stem for p in adrs.values()}:
                out.append(f"ADR-Index.md lists {stem}, which does not exist.")
    return out


def main(argv: list[str]) -> int:
    args = argv[1:]
    root = Path(".")
    if len(args) == 2 and args[0] == "--root":
        root = Path(args[1])
        args = []
    if args:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    wiki = root / "docs" / "wiki"
    if not wiki.is_dir():
        print(f"::error::{wiki} is not a directory.")
        return 1
    found = problems(wiki)
    for line in found:
        print(f"::error::{line}")
    if found:
        return 1
    pages = len(list(wiki.glob("*.md")))
    adrs = len([p for p in wiki.glob("ADR-*.md") if ADR_FILE.match(p.name)])
    print(f"docs/wiki is sound: {pages} pages, {adrs} decisions, every link resolves and every page is reachable.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
