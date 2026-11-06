# ADR-0006: Pairing is a typed code, not a QR

- **Status:** Accepted. Built 6 November 2026; corrects the plan.

**Decided.** The reader makes a code in Tippani's Settings > Server > Devices and types it in the app. The claim
(`POST /auth/devices/claim`) carries no credential; the token it returns goes to secure storage and never to the log or a screen.

**Why not a QR.** The plan said "scan the QR", but Tippani's web Settings shows an 8-character code and no QR. A QR needs a web change and a QR
library against Tippani's dependency budget (its ADR-0005). It is a later nicety, not a blocker.

**Consequences.** `normalisePairingCode` ignores case, spaces and dashes and reads `O`, `I` and `L` as the server's alphabet does. The code lasts
five minutes and works once; the server answers a wrong, expired and spent code alike, so the app cannot tell them apart either. Marking "this
phone" in the device list needed Tippani API revision 9 (`current` on `GET /auth/devices`); against an older server the list says it cannot tell
which row is this phone.
