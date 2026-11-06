/// A pairing code as the server shows it: 8 characters of a 32-symbol alphabet with no I, L, O or U, so a
/// code read off a screen cannot be mistyped as a different valid one (the server's `pairingAlphabet`).
const pairingAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const pairingCodeLength = 8;

/// Turns what a reader typed into the code, or null when it cannot be one. Case, spaces and dashes are
/// ignored, since a code is read aloud or copied in groups; the letters a reader is likely to confuse are
/// read the way the server's alphabet does (a typed `O` is `0`, `I` and `L` are `1`).
String? normalisePairingCode(String raw) {
  final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
  final mapped = cleaned
      .replaceAll('O', '0')
      .replaceAll('I', '1')
      .replaceAll('L', '1');
  if (mapped.length != pairingCodeLength) return null;
  for (final rune in mapped.split('')) {
    if (!pairingAlphabet.contains(rune)) return null;
  }
  return mapped;
}
