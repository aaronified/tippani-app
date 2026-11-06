# ADR-0010: 401 means unpair; 403 means not allowed

- **Status:** Accepted. Found by a test, 6 November 2026.

**Decided.** A 401 means the server no longer accepts the token (the phone was unpaired on the web): the app forgets it and Home says so. A 403
means the token is good but not allowed, an admin-only route asked by someone who is not an admin: it never unpairs the phone.

**Why.** The client first read both as "unauthorised", so a non-admin opening the server log would have been unpaired.

**Consequences.** `ApiFailure.forbidden` is separate from `unauthorised`. `isAdmin` is asked from `GET /auth/me` on open and after pairing and never
stored, so a demoted admin loses the admin screens the next time the app opens.
