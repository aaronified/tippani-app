import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A PKCE pair for a browser sign-in: the secret kept on the phone and the hash sent to the server.
class Pkce {
  const Pkce(this.verifier, this.challenge, this.state);

  final String verifier, challenge, state;

  /// A fresh pair and a `state` to tie the answer to the request that asked for it.
  factory Pkce.generate([Random? random]) {
    final r = random ?? Random.secure();
    final verifier = _token(r, 64);
    return Pkce(verifier, challengeFor(verifier), _token(r, 32));
  }

  /// The S256 challenge of [verifier]: base64url of its SHA-256 with no padding (RFC 7636).
  static String challengeFor(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  static String _token(Random r, int length) => String.fromCharCodes([
    for (var i = 0; i < length; i++)
      _alphabet.codeUnitAt(r.nextInt(_alphabet.length)),
  ]);
}
