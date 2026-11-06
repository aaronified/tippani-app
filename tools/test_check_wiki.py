"""Tests for tools/check_wiki.py. Run with: python3 -m unittest discover -s tools -p 'test_*.py'"""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_wiki as cw  # noqa: E402

TOOLS = Path(__file__).resolve().parent

GOOD = {
    "Home.md": "# Home\n\n- [Decisions](ADR-Index.md)\n",
    "_Sidebar.md": "- [Home](Home.md)\n",
    "ADR-Index.md": "# Decisions\n\n- [ADR-0001](ADR-0001-First.md)\n- [ADR-0002](ADR-0002-Second.md)\n",
    "ADR-0001-First.md": "# ADR-0001: First\n\n- **Status:** Accepted.\n\nBody.\n",
    "ADR-0002-Second.md": "# ADR-0002: Second\n\n- **Status:** Accepted.\n\nSee [one](ADR-0001-First.md).\n",
}


def wiki(**changes) -> Path:
    files = dict(GOOD)
    for name, text in changes.items():
        key = name.replace("__", "-").replace("_md", ".md")
        if text is None:
            files.pop(key, None)
        else:
            files[key] = text
    root = Path(tempfile.mkdtemp())
    (root / "docs" / "wiki").mkdir(parents=True)
    for name, text in files.items():
        (root / "docs" / "wiki" / name).write_text(text, encoding="utf-8")
    return root


def run(root: Path):
    return cw.problems(root / "docs" / "wiki")


class CheckWiki(unittest.TestCase):
    def test_a_sound_wiki_has_no_problems(self):
        self.assertEqual(run(wiki()), [])

    def test_a_link_to_a_missing_page_is_found(self):
        out = run(wiki(Home_md="# Home\n\n[x](Nowhere.md)\n[d](ADR-Index.md)\n"))
        self.assertTrue(any("Nowhere" in p for p in out), out)

    def test_a_link_to_a_repository_path_is_dead_in_a_flat_wiki(self):
        out = run(wiki(Home_md="# Home\n\n[ci](../.github/workflows/ci.yml)\n[d](ADR-Index.md)\n"))
        self.assertTrue(any("ci.yml" in p for p in out), out)

    def test_anchors_and_external_links_are_fine(self):
        text = "# Home\n\n[a](ADR-Index.md#how)\n[b](https://example.org/x)\n[c](mailto:a@b.c)\n"
        self.assertEqual(run(wiki(Home_md=text)), [])

    def test_a_page_nothing_links_to_is_found(self):
        out = run(wiki(**{"Orphan_md": "# Orphan\n"}))
        self.assertTrue(any("Orphan" in p and "reaches" in p for p in out), out)

    def test_a_page_reached_only_through_another_is_reached(self):
        out = run(wiki(**{"Deep_md": "# Deep\n", "ADR-Index_md": GOOD["ADR-Index.md"] + "\n[deep](Deep.md)\n"}))
        self.assertEqual(out, [])

    def test_an_adr_missing_from_the_index_is_found(self):
        out = run(wiki(**{"ADR-0003-Third_md": "# ADR-0003: Third\n\n- **Status:** Accepted.\n"}))
        self.assertTrue(any("ADR-0003-Third" in p and "not listed" in p for p in out), out)

    def test_an_index_entry_with_no_page_is_found(self):
        idx = GOOD["ADR-Index.md"] + "- [ADR-0003](ADR-0003-Ghost.md)\n"
        out = run(wiki(**{"ADR-Index_md": idx}))
        self.assertTrue(any("Ghost" in p for p in out), out)

    def test_a_gap_in_the_numbers_is_found(self):
        idx = "# D\n\n- [a](ADR-0001-First.md)\n- [c](ADR-0003-Third.md)\n"
        out = run(wiki(**{"ADR-0002-Second_md": None, "ADR-0003-Third_md": "# ADR-0003: Third\n\n- **Status:** Accepted.\n", "ADR-Index_md": idx}))
        self.assertTrue(any("ADR-0002 is missing" in p for p in out), out)

    def test_a_repeated_number_is_found(self):
        idx = GOOD["ADR-Index.md"] + "- [x](ADR-0002-Twin.md)\n"
        out = run(wiki(**{"ADR-0002-Twin_md": "# ADR-0002: Twin\n\n- **Status:** Accepted.\n", "ADR-Index_md": idx}))
        self.assertTrue(any("also used" in p for p in out), out)

    def test_a_title_that_disagrees_with_the_file_name_is_found(self):
        out = run(wiki(**{"ADR-0002-Second_md": "# ADR-0009: Second\n\n- **Status:** Accepted.\n"}))
        self.assertTrue(any("title says ADR-0009" in p for p in out), out)

    def test_an_adr_with_no_title_or_no_status_is_found(self):
        out = run(wiki(**{"ADR-0002-Second_md": "Second, with no heading.\n"}))
        self.assertTrue(any("first line must be" in p for p in out), out)
        self.assertTrue(any("Status" in p for p in out), out)

    def test_no_home_is_the_one_problem_reported(self):
        out = run(wiki(Home_md=None))
        self.assertEqual(len(out), 1)
        self.assertIn("Home.md is missing", out[0])

    def test_the_real_wiki_is_sound_right_now(self):
        result = subprocess.run([sys.executable, str(TOOLS / "check_wiki.py"), "--root", str(TOOLS.parent)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_command_exit_codes(self):
        bad = wiki(Home_md="# Home\n\n[x](Nowhere.md)\n")
        self.assertEqual(subprocess.run([sys.executable, str(TOOLS / "check_wiki.py"), "--root", str(bad)], capture_output=True).returncode, 1)
        self.assertEqual(subprocess.run([sys.executable, str(TOOLS / "check_wiki.py"), "bogus"], capture_output=True).returncode, 2)


if __name__ == "__main__":
    unittest.main()
