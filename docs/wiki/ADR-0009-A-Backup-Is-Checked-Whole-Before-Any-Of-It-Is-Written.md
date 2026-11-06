# ADR-0009: A backup is checked whole before any of it is written, and never holds the token

- **Status:** Accepted. Built 6 November 2026.

**Decided.** A backup is JSON sections, one per `BackupContributor`. A restore first runs `check` on every section and writes none unless all
pass, so a backup with a damaged library changes nothing, settings included. **The device token is never in a backup**: the file is copied to
Downloads and may be shared, and a token in it would be a credential lying about. Restoring a different server drops the old server's token.

**Why.** Before this a half-restore was possible: settings written, then the library refused, and the reader told it failed and left with half.

**Consequences.** A restore REPLACES the library and the settings, and the confirmation says so. After a restore the phone pairs again, which is
one code. A file too big, not ours, from a newer app, or damaged is refused with a sentence.
