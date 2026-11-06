# ADR-0014: Export is Tippani's own Markdown, written to the server's format

- **Status:** Accepted. Taken in the library work, 6 November 2026; the owner asked for "export as Tippani Markdown" in the plan.

**Decided.** The app exports the library as the Markdown that Tippani's server imports and exports (`export_handlers.go`, `export_quotes.go`):
`type: book` with quotes under `## chapter` headings, `type: movie|show|game` for films, shows and games, one `type: quotes` block for quotes that
belong to no work, and a binding only where there is a value. Yellow, the default colour, is never written. A work with no quotes is left out.
`lib/library/markdown_export.dart` writes it, and its tests pin the exact bytes.

**Why.** A library made on the phone with no server must be movable to one later, and the importer is the only reader that exists. Inventing a
second format would need a second importer, and a file that one side cannot read is the worst kind of backup.

**Consequences.** If the server's export changes shape, this file changes with it; the tests here are the reminder. The app does not import
Markdown yet. Share uses the share sheet and Save uses the system file picker, so there is no storage permission.
