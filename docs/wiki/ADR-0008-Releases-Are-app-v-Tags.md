# ADR-0008: A release is an app-vX.Y.Z tag with a tippani-app-vX.Y.Z.apk

- **Status:** Accepted. Decided with the plan; built 6 November 2026.

**Decided.** A release of the app is a tag `app-vX.Y.Z` whose APK is named `tippani-app-vX.Y.Z.apk`. The update check reads exactly those names
and only accepts that tag form, so the Tippani server's `v3.6.2` tags are never taken for an app release.

**Why.** The two projects share a GitHub account but not a release line. `versionCode` is the workflow's run number, which only goes up, so each
release installs over the one before; renaming `release.yml` would reset it, and Android refuses to install a lower code over a higher one.

**Consequences.** The tag, `pubspec.yaml` and `appVersion` (`lib/harness/version.dart`) must agree, and `tools/check_release_version.py` fails the
release before it builds if they do not. See [ADR-0013](ADR-0013-The-Release-Is-Cut-By-A-Workflow.md).
