# ADR-0030: Anthologies draw from the phone first and ask the server behind it

- **Status:** Accepted and built. The owner: "Only anthology, when opened, each time tries to search the server and only after a while shows the cached results with a message up top. This behavior is different from rest of the app. Standardize."

**Decided.** The anthologies list, an opened anthology (its passages, headings and front matter), and the "add to anthology" choosers (a passage's menu and the bulk bar) draw what the phone holds at once, then ask the server behind it and swap its answer in, in place, so the reader keeps their scroll and place.

| State | What shows |
|---|---|
| A copy is kept | The copy, immediately. No spinner. |
| Nothing is kept, first ever load | A spinner, then the screen's nothing-yet line. |
| The server answers | Its answer replaces the copy. |
| The server cannot be reached | The copy stays. After the client gives up, the shared **Showing what this phone last saw** note (`OfflineNote`) appears at the top of the list, of an opened anthology and of the chooser, in the place every screen puts it. |
| The server refuses or fails (a 500, or a 404 for an anthology deleted on the web) | What is shown stays, and the same note says it is the phone's copy, because that is what it now is. Only a first load with nothing shown says why, with Retry. |
| A change was just made with the server silent | The copy, at once: the change is already written into it. The deleted anthology is off the list, the renamed one has its name, the added passage is there, without waiting for the server to answer or give up. |

**Why it differed.** The Library, shelves and Quotes read the phone's own database, so they draw at once. The anthologies are the server's, and `OfflineAnthologies.list()` and `get()` sent the request first and fell back to the kept copy only when it failed as unreachable, so a silent server held the screen on a spinner for the whole request timeout (15 seconds) before the copy and the note appeared. A queue flush ran first as well. The screens also replaced a showing list with the error text when a refresh was refused.

**How.** `OfflineAnthologies.keptList()` and `keptDetail(id)` read the kept copy with no request; the queued changes are already written into it, so they show exactly as before. A screen draws them on its first load, and again after a change the reader made **while changes wait for the server** (`pending > 0`): then the kept copy is the newest thing there is, because every queued change is written into it as it is queued. With nothing waiting the change went to the server, the kept copy is the older one, and it is not drawn. (This said "first load only" and drew the server's answer after a change; with a silent server that was a flush and a read, about 30 seconds, during which a deleted anthology stayed on the list and could be opened.) A counter keeps a slow read from putting an older answer back over a newer one.

The chooser makes its own dialog route, so the read's failure closes exactly that route: it may land before the dialog has been drawn (there was no context yet to close, and the dialog stayed on its spinner) or while the reader is dismissing it (a pop then closed the screen beneath).

[ADR-0032](ADR-0032-Every-Server-Screen-Draws-The-Phones-Copy-First.md) makes this the rule for every screen that shows what the server holds. The offline queue, the flush order, the keys and the error words are unchanged (ADR-0022, ADR-0025). The two duplicated choosers became one, `chooseAnthology`, which shows the copy at once and the server's list when it lands.

**Rejected.** A shorter timeout only for anthologies (still a wait, and a different rule from the rest); a new banner for "refreshing" (the shared note already says the one thing a reader needs, and only when it is true); putting `kept` on `AnthologyService` (every fake would have to implement it; the screens already ask `service is OfflineAnthologies` for the waiting note).
