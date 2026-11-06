# ADR-0015: Sync starts as a push that only adds

- **Status:** Accepted. The owner, 6 November 2026 ("first a push-only sync when the phone is paired... then a pull").

**Decided.** When the phone is paired, a push sends every work and quote whose `server_id` is empty to the server and stores the id the server
returns. It creates (`POST /books`, `/movies`, `/annotations`, `/dialogues`, `/quotes`) and nothing else: it never edits or deletes on the
server and never reads the server's library. What already has a `server_id` is not sent again, so a second push sends nothing and a push that
stopped half way carries on. A work goes before its quotes, because they need its id.

**Mapping.** Books and works of kind "other" go to `/books`; films, shows and games to `/movies` with the matching `media_type`. A quote in a
book is an annotation (chapter, location, speaker as `character`); in a film, show or game a dialogue (location as `timestamp`; the chapter
has no home there and is not sent); with no work, a standalone quote (chapter as `occasion`, location as `place`, speaker as `speaker`).
The app's `capture` source goes up as `ocr`; everything else as `manual`, the only two values the server accepts.

**Stops and carries on.** A 400 is that item's problem: it is reported by the phone's own item number and the server's reason, its quotes wait,
and the rest goes on. A 409 carries the row it clashed with: the quote is linked to it, not copied. No network, a refused token, rate limiting,
`403` or a server error end the push, and the rest waits for the next one. A 201 with no id is a stop, never a guess.

**Why.** The one thing a first sync must not do is damage a library. Adding is safe to repeat and safe to abandon. Edits made after an item
was pushed are conflicts, and which side wins is for the owner to choose ([ADR-0016](ADR-0016-Conflicts-Are-Chosen-Per-Item-Never-By-A-Rule.md)),
so they wait for the sync that reads the server, which now exists; the push itself stays an add-only step.

**Consequences.** If the response to a create is lost after the server made the row, the retry creates a second copy of a work (quotes are
safe: the server deduplicates them). A work with the same title already on the server is created again, because the push does not ask the
server to check; the book and film routes would need the app to handle their "needs confirm" answer first.
