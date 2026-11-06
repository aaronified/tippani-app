# ADR-0012: All the functions come before the new features

- **Status:** Accepted. The owner, 6 November 2026.

**Decided.** The plan's phases 1 to 4 of "all of Tippani's functions" come first: (1) core, (2) the reading side, (3) management, (4) settings
and admin. Only then the new features: capture with Tesseract, donation, bug report, and the first signed release.

**Consequences.** The local library comes first because the core must work alone ([ADR-0003](ADR-0003-The-App-Works-On-Its-Own.md)). Pairing and
the harness, already built, are unaffected. The release workflow is scaffolded now so it is ready, but it cannot run until the owner sets its
secrets ([Releasing](Releasing.md)).
