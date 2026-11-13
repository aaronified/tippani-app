---
name: tippani-app-rate
description: Rate finished Tippani app work with the kit's work-rater, under the scoring and rerun rules used across the Tippani repos. Use at stage 7 of tippani-app-gate, before pushing and before reporting done.
---

# Rate Tippani app work

Base: the kit's `work-rating` skill and `work-rater` agent (`isolation: "worktree"`). Hand it the session's prompts **verbatim, in order**,
the diffs and the real verification output (or "none was run" — e.g. no Flutter in the container). **Never a target.**

| Scored | Reported, unscored |
|---|---|
| behaviour defect; a test that cannot fail for the defect it names; text a user meets in the app or the changelog's What's new; a wrong claim in README/wiki; a false account of the work | commit bodies, code comments, plans, test headers |

| Pass says | Do |
|---|---|
| ≥ 8/10 | fix every finding, stop |
| < 8, ≥ 3 major (scored, high/medium) | fix all, rerun on the fixes |
| < 8, < 3 major | fix all, stop |

- ≤ 5 raters, commits grouped; raters' helpers on `haiku`; no edits to code or docs while a rater runs.
- The rater checks the feature against the screen where a preview exists (`tool/preview`), and that tests exercise what a reader does
  (press, see), not private names.
- Report the score as given; every finding fixed or answered with the line that disproves it.
