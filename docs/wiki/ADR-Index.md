# Decisions

Source of truth: this wiki page (`docs/wiki/ADR-Index.md`).

Each decision is a page, `ADR-NNNN-Title.md`, in the order it was made. A page is never renumbered and is never rewritten to say something else:
a decision that changes gets a new page that says which it refines, and the old page's status says so.

## How a decision is made

1. **Decide it in words**, with the reason and the alternative that was not taken. The owner decides what is theirs to decide (licence, order of
   work, what must work alone, what is released); say which, and when.
2. **Write the page** from the template below, numbered after the last, and add it to this index in the same pull request that acts on it.
3. **A decision that corrects the plan** says what the plan said and what was found; the plan is then edited to agree.
4. **Mutation-check the rule it makes**, where it makes one a test can hold: break the code the way the decision forbids and see a named test fail.

## Template

```
# ADR-NNNN: <the decision, as a sentence>

- **Status:** Accepted. <who decided it and when, or what it refines>

**Decided.** <what, in a few sentences>

**Why.** <the reason, and the alternative not taken>

**Consequences.** <what it forces, what it costs, what to check before changing it>
```

## The decisions

- [ADR-0001](ADR-0001-Android-Only.md): Android only; no unbuildable ios/ directory ships
- [ADR-0002](ADR-0002-Licence-Is-GPL-3.0-And-Nothing-Proprietary.md): The licence is GPL-3.0, and nothing proprietary is linked
- [ADR-0003](ADR-0003-The-App-Works-On-Its-Own.md): The app works on its own, with no server
- [ADR-0004](ADR-0004-OCR-Is-Tesseract-Not-ML-Kit.md): Text recognition is Tesseract, not ML Kit
- [ADR-0005](ADR-0005-Material-You-Only.md): The look is Material You only
- [ADR-0006](ADR-0006-Pairing-Is-A-Typed-Code.md): Pairing is a typed code, not a QR
- [ADR-0007](ADR-0007-The-Harness-Is-The-Base-Every-Screen-Stands-On.md): The harness is the base every screen stands on
- [ADR-0008](ADR-0008-Releases-Are-app-v-Tags.md): A release is an app-vX.Y.Z tag with a tippani-app-vX.Y.Z.apk
- [ADR-0009](ADR-0009-A-Backup-Is-Checked-Whole-Before-Any-Of-It-Is-Written.md): A backup is checked whole before any of it is written, and never holds the token
- [ADR-0010](ADR-0010-401-And-403-Are-Different.md): 401 means unpair; 403 means not allowed
- [ADR-0011](ADR-0011-The-Server-Log-Is-Kept-Apart-From-The-App-Log.md): The server log is kept apart from the app log
- [ADR-0012](ADR-0012-Functions-Before-New-Features.md): All the functions come before the new features
- [ADR-0013](ADR-0013-The-Release-Is-Cut-By-A-Workflow.md): A release is cut by a workflow, signed with a key that is never in the repository
- [ADR-0014](ADR-0014-Export-Is-Tippani-s-Own-Markdown.md): Export is Tippani's own Markdown, written to the server's format
- [ADR-0015](ADR-0015-Sync-Starts-As-A-Push-That-Only-Adds.md): Sync starts as a push that only adds
- [ADR-0016](ADR-0016-Conflicts-Are-Chosen-Per-Item-Never-By-A-Rule.md): Conflicts are chosen per quote and per work, never by a rule
- [ADR-0017](ADR-0017-Deletes-Travel-Both-Ways-With-A-Wipe-Guard.md): Deletes travel both ways, with a guard against a wiped server
- [ADR-0018](ADR-0018-Sync-Runs-By-Itself-And-Never-Stops-For-A-Conflict.md): Sync runs by itself and never stops for a conflict
- [ADR-0019](ADR-0019-Sync-On-Every-Change-And-Once-A-Day-Nothing-In-Between.md): Sync on every change and once a day, with nothing in between
- [ADR-0020](ADR-0020-The-Colours-Are-Chosen-In-Settings.md): The colours are chosen in Settings
- [ADR-0021](ADR-0021-Four-Tabs-And-The-Boards-Tab.md): Four tabs, and the Boards tab
- [ADR-0022](ADR-0022-Everything-Reads-Offline-And-Changes-Wait-For-The-Server.md): Everything reads offline, and a change made offline waits for the server
- [ADR-0023](ADR-0023-Which-Server-Settings-The-Phone-Offers.md): Which server settings the phone offers
- [ADR-0024](ADR-0024-The-App-Wears-The-Accounts-Materials-Over-Material-You.md): The app wears the account's materials over Material You
- [ADR-0025](ADR-0025-A-Passage-Shows-And-Says-Its-Own-Parts-In-Its-Anthology.md): A passage shows and says its own parts in its anthology
- [ADR-0026](ADR-0026-The-App-Fetches-And-Edits-Metadata-Where-The-Web-Does.md): The app fetches and edits metadata where the web does
- [ADR-0027](ADR-0027-The-App-Offers-Its-Own-Tour-And-Keeps-Whether-It-Was-Seen-On-The-Phone.md): The app offers its own tour, and keeps whether it was seen on the phone
- [ADR-0028](ADR-0028-A-Material-Is-Composed-Once-And-Drawn-As-One-Image.md): A material is composed once and drawn as one image
- [ADR-0030](ADR-0030-Anthologies-Draw-From-The-Phone-First-And-Ask-The-Server-Behind-It.md): Anthologies draw from the phone first and ask the server behind it
- [ADR-0029](ADR-0029-A-Quotes-Menu-Holds-Every-Action-Its-Card-Does-Not-Show.md): A quote's menu holds every action its card does not show, and one function builds it
- [ADR-0031](ADR-0031-Every-Share-Is-One-Screen-With-A-Subject.md): Every share is one screen, with a subject
- [ADR-0032](ADR-0032-Every-Server-Screen-Draws-The-Phones-Copy-First.md): Every screen that shows what the server holds draws the phone's copy first
- [ADR-0033](ADR-0033-The-Broken-Link-Is-One-Mark-And-One-Toast.md): The broken link is one mark and one toast, not a note on every screen

See also: [Home](Home.md) · [Plan](Plan.md) · [Developing](Developing.md) · [Releasing](Releasing.md)
