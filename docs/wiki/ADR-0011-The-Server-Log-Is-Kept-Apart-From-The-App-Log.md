# ADR-0011: The server log is kept apart from the app log

- **Status:** Accepted. The owner, 6 November 2026.

**Decided.** The **App log** is this phone's own record of what the app did. The **Server log** is the Tippani server's, read by an admin from
`GET /admin/logs`. They are separate Settings entries and never share a screen, a copy, a share or a file.

**Consequences.** The server log appears only for an admin. Its window is set by the server's clock (`since`), later pages send back the first
answer's `from` and `upto` so lines logged meanwhile are in neither page, and its lines are redacted on the way out as the app's are. Asking for it
writes nothing of its lines into the app log.
