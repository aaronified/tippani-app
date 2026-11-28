import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/listen/abs/pkce.dart';

void main() {
  test('the S256 challenge matches the RFC 7636 example', () {
    expect(
      Pkce.challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('a generated pair is long enough, URL-safe, and its challenge fits', () {
    final p = Pkce.generate(Random(1));
    expect(p.verifier.length, inInclusiveRange(43, 128));
    expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(p.verifier), isTrue);
    expect(p.challenge, Pkce.challengeFor(p.verifier));
    expect(p.challenge.contains('='), isFalse);
    expect(p.state, isNotEmpty);
  });

  test('two pairs differ', () {
    expect(Pkce.generate().verifier, isNot(Pkce.generate().verifier));
  });
}
