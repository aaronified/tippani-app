import 'dart:convert';

import 'package:flutter/services.dart';

import 'abs_models.dart';

/// One Audiobookshelf server a Tippani account is signed in to, and the tokens for it.
class AbsConnection {
  const AbsConnection({required this.serverUrl, required this.tokens});

  final String serverUrl;
  final AbsTokens tokens;

  AbsConnection withTokens(AbsTokens t) =>
      AbsConnection(serverUrl: serverUrl, tokens: t);

  String toJson() =>
      jsonEncode({'serverUrl': serverUrl, 'tokens': tokens.toJson()});

  static AbsConnection? fromJson(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final m = jsonDecode(text);
      if (m is! Map) return null;
      final url = m['serverUrl'];
      final tokens = AbsTokens.fromStored(m['tokens']);
      if (url is! String || url.isEmpty || tokens == null) return null;
      return AbsConnection(serverUrl: url, tokens: tokens);
    } on FormatException {
      return null;
    }
  }
}

/// Where an account's Audiobookshelf sign-in is kept. [account] is a short id for the Tippani account
/// (never the Tippani token), so every account on a phone has its own and none sees another's.
abstract class AbsTokenStore {
  Future<AbsConnection?> read(String account);
  Future<void> write(String account, AbsConnection connection);
  Future<void> clear(String account);
}

/// The real store: the Kotlin `AbsVault`, encrypted with a key that never leaves the Android Keystore.
/// The player service reads the same vault with no Dart engine running, which is why it is not a
/// Flutter plugin's storage.
class VaultAbsTokenStore implements AbsTokenStore {
  VaultAbsTokenStore([MethodChannel? channel])
    : _channel =
          channel ??
          const MethodChannel('io.github.aaronified.tippani/abs_vault');

  final MethodChannel _channel;

  @override
  Future<AbsConnection?> read(String account) async => AbsConnection.fromJson(
    await _channel.invokeMethod<String>('get', {'account': account}),
  );

  @override
  Future<void> write(String account, AbsConnection connection) async {
    await _channel.invokeMethod<bool>('put', {
      'account': account,
      'value': connection.toJson(),
    });
  }

  @override
  Future<void> clear(String account) async {
    await _channel.invokeMethod<bool>('clear', {'account': account});
  }
}

/// A store in memory, for tests.
class MemoryAbsTokenStore implements AbsTokenStore {
  final _held = <String, AbsConnection>{};

  @override
  Future<AbsConnection?> read(String account) async => _held[account];

  @override
  Future<void> write(String account, AbsConnection connection) async =>
      _held[account] = connection;

  @override
  Future<void> clear(String account) async => _held.remove(account);
}
