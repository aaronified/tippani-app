# flutter_tesseract_ocr, vendored

This is `flutter_tesseract_ocr` 0.4.31 (BSD-3-Clause, see LICENSE) with one change: `android/build.gradle` no longer has a
`buildscript` block that names `jcenter()` and an old Android Gradle plugin, which stopped the app building. Everything else is as
published, including the bundled Tesseract4Android library (`android/libs`, Apache-2.0).
