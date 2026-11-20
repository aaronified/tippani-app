# ADR-0030: Anthologies draw from the phone first and ask the server behind it

- **Status:** Accepted and built. The owner: "Only anthology, when opened, each time tries to search the server and only after a while shows the cached results with a message up top. This behavior is different from rest of the app. Standardize."

**Decided.** The anthologies list, an opened anthology (its passages, headings and front matter), and the "add to anthology" choosers (a passage's menu and the bulk bar) draw what the phone holds at once, then ask the server behind it and swap its answer in, in place, so the reader keeps their scroll and place.

| State | What shows |
|---|---|
| A copy is kept | The copy, immediately. No spinner. |
| Nothing is kept, first ever load | A spinner, then the screen's nothing-yet line. |
| The server answers | Its answer replaces the copy. |
| The server cannot be reached | The copy stays. After the client gives up, the shared **Showing what this phone last saw** note (`OfflineNote`) appears in the place every screen puts it. |
| The server refuses or fails | What is shown stays. Only a first load with nothing shown says why, with Retry. |

**Why it differed.** The Library, shelves and Quotes read the phone's own database, so they draw at once. The anthologies are the server's, and `OfflineAnthologies.list()` and `get()` sent the request first and fell back to the kept copy only when it failed as unreachable, so a silent server held the screen on a spinner for the whole request timeout (15 seconds) before the copy and the note appeared. A queue flush ran first as well. The screens also replaced a showing list with the error text when a refresh was refused.

**How.** `OfflineAnthologies.keptList()` and `keptDetail(id)` read the kept copy with no request; the queued changes are already written into it, so they show exactly as before. A screen draws them on its first load only (a reload after a change refreshes in place, so an older copy is never flashed over a newer screen), and a counter keeps a slow read from putting an older answer back over a newer one. The offline queue, the flush order, the keys and the error words are unchanged (ADR-0022, ADR-0025). The two duplicated choosers became one, `chooseAnthology`, which shows the copy at once and the server's list when it lands.

**Rejected.** A shorter timeout only for anthologies (still a wait, and a different rule from the rest); a new banner for "refreshing" (the shared note already says the one thing a reader needs, and only when it is true); putting `kept` on `AnthologyService` (every fake would have to implement it; the screens already ask `service is OfflineAnthologies` for the waiting note).
