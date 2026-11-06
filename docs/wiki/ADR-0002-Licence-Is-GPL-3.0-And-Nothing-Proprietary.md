# ADR-0002: The licence is GPL-3.0, and nothing proprietary is linked

- **Status:** Accepted. The owner, 6 November 2026.

**Decided.** The app is GPL-3.0 (`LICENSE`). It links nothing proprietary: no ML Kit, no Google Play Services library, no closed SDK of any
kind. A dependency must be free software.

**Why.** A GPL app that bundles a proprietary library needs an additional permission from every copyright holder, and the owner chose not to
need one. GPL-3.0 is compatible with Google Play; the licence that causes trouble is for Apple's App Store, which the app does not target
([ADR-0001](ADR-0001-Android-Only.md)). The Tippani server is MIT and is a separate program that this app only talks to over its API.

**Consequences.** Text recognition is Tesseract ([ADR-0004](ADR-0004-OCR-Is-Tesseract-Not-ML-Kit.md)). A new dependency is checked for its
licence before it is added; a package that pulls in a closed binary is refused. Contributions come under the same licence, and an exception
for any outside code would need that contributor's agreement.
