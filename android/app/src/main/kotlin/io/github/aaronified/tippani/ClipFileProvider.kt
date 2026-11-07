package io.github.aaronified.tippani

import androidx.core.content.FileProvider

/// The FileProvider that hands out a copied quote picture (see MainActivity.copyImage). A class of its own, not
/// the library's, so it can sit beside the update installer's provider without the two sharing a name.
class ClipFileProvider : FileProvider()
