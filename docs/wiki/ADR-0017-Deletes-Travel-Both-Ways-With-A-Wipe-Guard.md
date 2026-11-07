# ADR-0017: Deletes travel both ways, with a guard against a wiped server

- **Status:** Accepted and built. The owner, 7 November 2026, on the list of what was missing: "Deletes don't sync: fix".

**Decided.** A quote or work deleted on the phone is deleted on the server, and one deleted on the server is removed from the phone. Neither
side's delete is silent, and neither can quietly cost the reader something they changed.

**Phone to server.** Deleting a work or quote that is on the server writes a row in `deletions` (the server's route and id; a work also notes
each of its linked quotes). The next sync sends `DELETE` for each before it reads anything, so the lists it reads cannot bring the item back.
The server does not destroy it: its bin keeps it for 30 days and the app's Bin screen can restore it. A 404 means the server had already
dropped it, and the note is cleared. A refusal (400, 409) is reported and the note cleared, which means the item may come back down on the
pull that follows, because the server decided to keep it. Any other failure stops the sync and keeps the notes for next time. Nothing is
noted for something that was never on the server.

**Server to phone.** An item the phone links to that the server's lists no longer hold was deleted there. It is removed here only if it has
not been changed here since the two last agreed (its stored fingerprint still matches). If the reader changed it, it is kept and unlinked,
so it goes up again as new: their edit wins over a delete they did not know about. A work is removed only when no quote is left in it; a
work that still holds a quote that exists only on the phone is kept and unlinked for the same reason.

**The guard.** If ten or more linked items are missing and they are more than half of everything linked, nothing is removed and the sync
says so. That shape is a server restored from an old copy, a different server, or a wiped data folder, not a reader deleting over half
their library between two syncs. Fewer missing items are treated as real deletes.

**Why not just "the server wins" or "never delete".** Never deleting leaves the two libraries drifting apart and a deleted quote
resurrected by the next sync, which the owner called out. Letting any absence delete would let one bad response empty the phone.

**Not covered.** A phone that deleted something while another phone edited it: the second phone's edit is kept (it relinks as new), so the
item reappears on the server as a new row. The server's bin is not read by the pull.
