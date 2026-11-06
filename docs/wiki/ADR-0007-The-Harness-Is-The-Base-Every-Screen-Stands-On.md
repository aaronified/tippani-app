# ADR-0007: The harness is the base every screen stands on

- **Status:** Accepted. The owner, 6 November 2026.

**Decided.** `lib/harness/` is built once in `main` and handed down: the update check and installer, the changelog after an update, the app
log, backup and restore, and one narrow interface over one native channel for files (`MainActivity.kt`). A feature screen gets a log line, a
backup section and an update toast without writing any of them.

**Consequences.** A feature with data worth keeping implements `BackupContributor` and registers itself in `Harness.open`. Tests use
`Harness.fake` and `MemoryAppFiles`. The update check runs on open (the plan had it off by default; the owner asked for it on) and is silent when
it finds nothing or cannot ask; nothing downloads until the reader presses Download.
