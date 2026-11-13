# ADR-0003: The app works on its own, with no server

- **Status:** Accepted. The owner, 6 November 2026.

**Decided.** The core works with no server and no network: capture, browse, search, add, edit, tag, the daily quiz, boards and anthologies,
and export/import run on a SQLite library on the phone (`lib/library/`). A server is optional. **Management and admin screens** (metadata sources,
Checks, jobs, library folders, source files, the server log, the device list) need a paired server and say so.

*Status note, 13 November 2026:* anthologies are kept on the server with a copy and a queue on the phone ([ADR-0022](ADR-0022-Everything-Reads-Offline-And-Changes-Wait-For-The-Server.md)), not in the phone's SQLite library; management screens show the phone's last copy with no server; and sync is two-way ([ADR-0015](ADR-0015-Sync-Starts-As-A-Push-That-Only-Adds.md) to [ADR-0019](ADR-0019-Sync-On-Every-Change-And-Once-A-Day-Nothing-In-Between.md)).

**Why.** A reader with no server, or whose server is off, still has their quotes. Pairing adds sync; it is not a way in.

**Consequences.** Every row has a `server_id`, empty until a server has it. Backups carry the library
([ADR-0009](ADR-0009-A-Backup-Is-Checked-Whole-Before-Any-Of-It-Is-Written.md)). Home opens on the library, not on "connect to a server". Each
function is built twice over: once against the local store, and where it needs one, against the server. Until sync exists it is push-only, and
who wins a conflict is the owner's call.
