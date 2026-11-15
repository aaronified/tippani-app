# ADR-0026: The app fetches and edits metadata where the web does

- **Status:** Accepted and built. The owner, 15 November 2026: "App must be able to fetch metadata (or even upload/edit) from all applicable screens like the server … These metadata will also be synced with the server."

**Decided.** Every metadata action the web offers on a screen the app also has is offered on that screen, and each one is written to the server and read back, so the web and the phone agree:

| Screen | What it can now do |
|---|---|
| A name or character with no record | Add it to the library (`POST /people/ensure`, `POST /characters`), after which the page has the menu every record has |
| A work | Fetch metadata (the same field-by-field review Metadata tools open, started from this one work), Find it online and link its source, Edit details, Cover from a link, Remove cover |
| A work's cast | Add, edit, remove a row, remove only the performer, fetch from TheTVDB or IMDb |
| A person | Portrait from a link, signature lookup (kept only when accepted), the name it sorts under |
| A character | Picture from a link or from one of its appearances, put on a work, take off a work (asking what to do with quotes that still name it) |

**Written through, not queued.** These calls need the server's sources or the server's records (a lookup, a fetch, a cast row's id), so none of them waits in the offline queue; offline, the control says so in the server's words. The text edits that could be queued (details, cast rows) are not, because the server replaces a whole record on a save and a queued overlay could overwrite a change made on the web in between; each save reads the record first. The offline queue stays for what the app already queues (anthologies, tags, settings).

**Read back.** After a write the page refetches the work's details or the person's record and the people directory refreshes; fetching metadata, saving details and linking a source also run a sync pass, because they can change the title, creator, year or cover that the library list shows. A cast row or a cover change touches nothing the list draws, so those only re-read the page.

**Rejected.** A second review screen for one work (the Metadata tools' review already shows each field, the supplier to take it from, and leaves alone what changed meanwhile); an edit form that sends only the changed fields (the book and film routes replace the record).
