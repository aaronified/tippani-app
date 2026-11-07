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

See also: [Home](Home.md) · [Plan](Plan.md) · [Developing](Developing.md) · [Releasing](Releasing.md)
