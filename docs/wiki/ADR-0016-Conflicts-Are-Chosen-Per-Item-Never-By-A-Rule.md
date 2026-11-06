# ADR-0016: Conflicts are chosen per quote and per work, never by a rule

- **Status:** Accepted as a decision, not built. The owner, 6 November 2026: "user decides, on quote/work basis (both options should be available)".

**Decided.** When the same quote or work has changed on the phone and on the server since they last agreed, the app does not pick a winner. It
shows both versions and the reader chooses, for that quote or that work: keep the phone's, or keep the server's. Both are always on offer.
There is no "newest wins" and no "the server always wins". Nothing is overwritten on either side until the reader has chosen.

**Why.** Either automatic rule loses a reader's edit without telling them, and the library is made of things people typed on purpose.

**Consequences.** The pull step must know, for each item, what both sides looked like when they last agreed, so it can tell "changed here",
"changed there" and "changed in both". That means storing the server's own `updated_at` at the last sync beside the phone's. It is added with
the pull, in a schema upgrade, not before. A conflict list screen shows each item with the two versions side by side and the two choices; how
to offer "choose for all the rest" is decided when it is built. [ADR-0015](ADR-0015-Sync-Starts-As-A-Push-That-Only-Adds.md) is the part that
exists.
