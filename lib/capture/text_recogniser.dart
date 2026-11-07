import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

/// Turns a photographed page into text. An interface so a test can stand in for Tesseract.
abstract class TextRecogniser {
  /// The text on the picture at [imagePath], read as [language] (Tesseract codes joined with "+", such as "eng"
  /// or "eng+hin"). Throws if the picture cannot be read.
  Future<String> read(String imagePath, String language);

  /// The same page as hOCR: HTML with each line's and word's text and box, which the reader picks words from on the
  /// picture. Throws if the picture cannot be read.
  Future<String> hocr(String imagePath, String language);
}

/// Tesseract, running on the phone: the picture never leaves it. The language data it needs is bundled in
/// `assets/tessdata`.
class TesseractRecogniser implements TextRecogniser {
  const TesseractRecogniser();

  @override
  Future<String> read(String imagePath, String language) =>
      FlutterTesseractOcr.extractText(imagePath, language: language);

  @override
  Future<String> hocr(String imagePath, String language) =>
      FlutterTesseractOcr.extractHocr(imagePath, language: language);
}

/// What a page photographed straight comes out as is one line per printed line, with words cut by a hyphen at
/// a line's end. This joins the lines of a paragraph into one, mends those words, and keeps a blank line as the
/// break between paragraphs.
String tidyRecognisedText(String raw) {
  final paragraphs = raw
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n[ \t]*\n+'))
      .map(
        (p) => p
            .replaceAllMapped(
              RegExp(r'([A-Za-zऀ-ॿ])-\n\s*([a-zऀ-ॿ])'),
              (m) => '${m[1]}${m[2]}',
            )
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .join(' ')
            .replaceAll(RegExp(r'[ \t]{2,}'), ' '),
      )
      .where((p) => p.isNotEmpty);
  return paragraphs.join('\n\n');
}
