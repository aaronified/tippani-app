import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the device token is kept. A token is a credential, so it goes in the platform's secure
/// storage and never in the plain preferences the server address lives in.
abstract class TokenVault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// The real vault: Android Keystore-backed storage.
class SecureTokenVault implements TokenVault {
  SecureTokenVault([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'device_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// A vault in memory, for tests.
class MemoryTokenVault implements TokenVault {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// What the app remembers between runs: which server, and the credential for it.
class SettingsStore {
  SettingsStore(this._prefs, this._vault);

  static const _serverKey = 'server_url';
  final SharedPreferences _prefs;
  final TokenVault _vault;

  String? get serverUrl => _prefs.getString(_serverKey);

  Future<void> setServerUrl(String url) => _prefs.setString(_serverKey, url);

  static const _seenKey = 'last_seen_version';

  /// The app version this phone last showed "what is new" for, or null on a first install.
  String? get lastSeenVersion => _prefs.getString(_seenKey);

  Future<void> setLastSeenVersion(String version) =>
      _prefs.setString(_seenKey, version);

  static const _quizKey = 'quiz_answers';

  /// The quiz answers made and not yet taken by the server (JSON), kept so they survive the app closing.
  String? get quizAnswers => _prefs.getString(_quizKey);

  Future<void> setQuizAnswers(String json) =>
      json.isEmpty ? _prefs.remove(_quizKey) : _prefs.setString(_quizKey, json);

  static const _userKey = 'paired_user';

  /// Who this phone is paired as, for display. The server's answer at pairing; never a credential.
  String? get username => _prefs.getString(_userKey);

  Future<void> setUsername(String name) => _prefs.setString(_userKey, name);

  Future<String?> token() => _vault.read();

  Future<void> setToken(String token) => _vault.write(token);

  /// Forgets who this phone is paired as and the credential, and keeps the server: the reader unpairs but
  /// can pair again with a new code without typing the address.
  Future<void> forgetToken() async {
    await _prefs.remove(_userKey);
    await _vault.clear();
  }

  /// Forgets the server and its credential together: a token is only good for the server that issued
  /// it, so keeping one without the other leaves a stranded secret.
  Future<void> forgetServer() async {
    await _prefs.remove(_serverKey);
    await _prefs.remove(_userKey);
    await _vault.clear();
  }
}
