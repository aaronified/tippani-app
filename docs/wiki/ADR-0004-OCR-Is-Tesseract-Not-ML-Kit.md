# ADR-0004: Text recognition is Tesseract, not ML Kit

- **Status:** Accepted. The owner, 6 November 2026.

**Decided.** Recognising a photographed page uses Tesseract (Apache-2.0) on the device, with `tessdata_fast` language data (also Apache-2.0).
Not Google's ML Kit, which is proprietary.

**Why.** [ADR-0002](ADR-0002-Licence-Is-GPL-3.0-And-Nothing-Proprietary.md). Tesseract also returns each word's and line's bounding box, which
the line selection and the page-number and chapter proposals depend on.

**Consequences.** Accuracy on a photographed page is lower than ML Kit's, so the correction screen is not optional and the photo is straightened
and sharpened first. English ships with the app; other languages (Bengali `ben`, Hindi `hin`) are downloaded when the reader asks. The package is
chosen when capture starts and must be free software with Tesseract inside it; failing that, the app wraps Tesseract through a native channel as
the harness does for files. No GPL additional permission is needed.
