# ADR-0016: Conflicts are chosen per quote and per work, never by a rule

- **Status:** Accepted and built. The owner, 6 November 2026: "user decides, on quote/work basis (both options should be available)".

**Decided.** When the same quote or work has changed on the phone and on the server since they last agreed, the app does not pick a winner. It
shows both versions and the reader chooses, for that quote or that work: keep the phone's, or keep the server's. Both are always on offer.
There is no "newest wins" and no "the server always wins". Nothing is overwritten on either side until the reader has chosen.

**Why.** Either automatic rule loses a reader's edit without telling them, and the library is made of things people typed on purpose.

**How it is built.** The pull has to know, for each item, what both sides looked like when they last agreed, so it can tell "changed here",
"changed there" and "changed in both". The first plan was to store the server's `updated_at` at the last sync. That does not work: the server
does not give a work's `updated_at` in any route the app can read. So each work and quote stores a **fingerprint of the fields that sync**
(`synced_hash`, a schema upgrade to version 2), written when the phone and the server agree: when the push creates an item, when an item comes
down, and when a conflict is settled. At the next sync the phone's fields, the server's fields and the stored fingerprint are compared:

- phone equals server: nothing to do (the fingerprint is refreshed);
- only the server differs from the fingerprint: its version is applied here;
- only the phone differs: it is sent up, written over the server's own row so what the phone does not hold (a sticker, a chapter number) is not wiped;
- both differ, or they differ and no agreement was ever recorded: a **conflict**. Nothing changes on either side until the reader chooses.

Conflicts are not stored. An unresolved one is found again by the next sync, so there is no half-resolved state to repair. The conflict list
shows, for each item, only the fields that read differently, the phone's and the server's, and two buttons: keep the phone's or keep the
server's. "Keep the phone's for all" and "Keep the server's for all" are there when there is more than one, behind a confirmation, because that
is the one place a single tap replaces many items. Nothing is ever deleted on either side by a sync.

**What is compared.** For a quote: its words, translation, language, who said it, chapter, place, note, colour, favourite and tags. A film
quote's chapter is left out (the server has nowhere to keep it). For a work: its kind (book or film, show, game), title, creator and year. A
work's language is not compared, because the server's list does not give it. Spacing at the edges and the case and order of tags do not count
as a change. [ADR-0015](ADR-0015-Sync-Starts-As-A-Push-That-Only-Adds.md) is the push that this builds on.

**Limits.** An item the server no longer has is handled by [ADR-0017](ADR-0017-Deletes-Travel-Both-Ways-With-A-Wipe-Guard.md). A server quote with no words (a note only), or
whose work is not on the phone, is counted and not brought down. An item the phone has never pushed and the server holds under the same
title is brought down as a second copy: the pull matches by the server's id, not by title.
