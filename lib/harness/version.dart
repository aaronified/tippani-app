/// The version of this build. Kept in step with `version:` in pubspec.yaml: `test/version_test.dart`
/// fails when they differ, and the release workflow refuses a tag that does not match the pubspec.
const appVersion = '0.4.0';

/// The repository the releases come from.
const releaseRepo = 'aaronified/tippani-app';

/// A release of the app is tagged `app-vX.Y.Z` (the plan's convention, kept although the app has its
/// own repository, so a tag is never mistaken for one of the server's).
const releaseTagPrefix = 'app-v';

/// The APK attached to a release is named `tippani-app-vX.Y.Z.apk`.
const apkNamePrefix = 'tippani-app-v';
