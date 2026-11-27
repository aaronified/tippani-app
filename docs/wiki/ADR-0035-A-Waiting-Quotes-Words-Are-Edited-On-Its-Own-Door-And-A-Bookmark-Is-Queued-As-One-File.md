# ADR-0035: A waiting quote's words are edited on their own door, a bookmark is queued as one file, and dictated quotes say so

- **Status:** Accepted and built (the first work of [Plan: listen, read and bookmark](Plan-Listen.md), "Foundations")
- **The owner, 27 November 2026:** "Quote text can't be edited in the imports queue. Only metadata can … Then add that feature as well." and "build all the support stuff (like the import screen enhancement) first."

**What was decided.**

| Piece | Decision |
|---|---|
| Editing words in Pending imports | A quote's edit sheet gains Quote, Note and Translation fields and a **Trim** control (tap a sentence, tap another to extend the run, Use these). It is offered only when the server lists `staged-text-edit` (Tippani server ADR-0937, API revision 13). An older server shows the words and says they cannot be changed there |
| The request | `PATCH /import/staged/quotes/{id}` through `StagedTextEdit`, a class apart from `StagedEdit`. The bulk door still never carries words, so a words edit cannot ride on a bulk request and be ignored. Words go first and alone: a refusal (a `409` for words equal to another waiting quote's, a `400` for no words) is said, and the sheet's other fields are not sent for a save that was refused |
| A bookmark in the queue | `bookQuoteMarkdown` writes one quote on one book as the Tippani Markdown the server's importer reads, from the server's parser, using the work's own `title`, `author` and `isbn` so the server joins the existing work. `ImportService.queueOnce` sends it under a fixed name (`bookmark-<uuid>.md`) after asking whether a batch with that name is already waiting, because the server names a batch after its file and offers no idempotency key on imports |
| Dictated quotes | A quote made by dictation is saved with source `voice` and is pushed as `voice` to a server that lists `voice-source`, and as `manual` to one that does not (an older server answers 400 to a value it does not know) |

**Found while building, and fixed with it.** The quote form stores `ocr` for a scanned page, and the push mapped only `capture` to `ocr`, so every scanned quote reached the server as `manual`. Both words now map to `ocr`. Quotes already sent keep their mark: the server's `source` is set on create only.

**Why a separate request class.** Putting `quote` on `StagedEdit` would make one `toJson` serve two doors, and a bulk call carrying words would succeed with the words dropped, which is how a feature ships dead (see the server's note on its bulk request). Two classes, two routes, and a fake server that answers each as the real one does.

**Rejected.**

| Option | Why not |
|---|---|
| A range slider for Trim | Fiddly to drive, to test and with a thumb. Sentence taps need no new control and give a contiguous run by construction |
| Trimming in a local inbox before upload | Keeps the draft out of the queue the owner asked for |
| Sending a bookmark straight to `POST /quotes` with `voice` | Keeps the provenance but skips the queue, and the owner wants to review first |
| Splitting sentences with a language model | A convenience for trimming does not need one; a wrong split costs a tap and loses no word |

**Not built here.** The "N bookmarks waiting for transcription" row on Pending imports, the bookmark pipeline, the clip and Whisper: they need the listening subsystem, which the plan builds after these foundations.
