# ADR-0034: The app's own preferences belong to the account the phone is paired as

- **Status:** Accepted and built. The owner, planning audiobooks and Grimmory: *"All settings will be user specific. If there is something that doesn't adhere to this, fix it right away."* The audit found the server-side settings already per account, and the phone's own preferences in one device-wide store.

**Why.** Pairing as someone else left the new account reading the last one's read-aloud voice, share-picture look, library sort and layout, auto-sync switch and tour outcome. The server's copy of an account's answers was already cleared on unpair ([ADR-0022](ADR-0022-Everything-Reads-Offline-And-Changes-Wait-For-The-Server.md)); these were the one thing that was not.

**Decided.**

| What | Where it lives |
|---|---|
| Read-aloud voice, speed and pitch; the share picture's choices; the library's sort, grouping, filter and layout per section; auto-sync on or off; the tour's outcome | `acct.<server>\|<name>.<key>` while the phone is paired as that account |
| The same choices while the phone is unpaired | The bare key, exactly as every phone already holds them, so nothing is migrated |
| A new account's first set | A copy of the phone's own, so choices made before pairing carry over once; a set that exists is never overwritten |
| The server address, the token, the name paired as, the version whose "what's new" was shown, the sync's own bookkeeping, the offline copy | Unchanged. These are facts about the phone or the pairing, not choices |

`PrefKeys` (`lib/settings/preference_scope.dart`) is the one list of preference names; `PreferenceScope.key` gives the name a set uses, and `AppController` points it at the account on load, pairing, unpairing and a refused token. Holders of a loaded value (`SpeechSettings`, `AutoSync`) re-read when it switches. **A preference added later is named in `PrefKeys` and read through `PreferenceScope.key`; one that is not is device-wide by accident.**

**Not changed, and noted.** The phone's library database is one per phone, not per account. Pairing as a different account would push the first account's local-only works and quotes to the second one's server. That is a larger decision than preferences and is not made here.

**Rejected.** Wiping the device-wide preferences on every account switch (a reader who returns finds defaults, and the reader who set the app up before pairing loses it all); a one-time migration of the old keys into a named set (the unpaired set already is the old keys); scoping "what's new" and the sync bookkeeping too (a changelog shown again because someone else paired is noise, and the bookkeeping describes this phone's library).
