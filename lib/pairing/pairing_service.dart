import '../api/api_client.dart';
import '../harness/app_log.dart';
import '../settings/server_url.dart';
import '../settings/settings_store.dart';

/// Why a pairing did not happen.
enum PairFailure {
  /// The server did not recognise the code: wrong, expired (five minutes) or already used. The server
  /// answers all three alike on purpose, so this app cannot tell them apart either.
  invalidCode,

  /// Too many attempts; the claim is rate limited.
  rateLimited,

  /// The server could not be reached, or was too slow.
  unreachable,

  /// The server answered in a way this app does not understand.
  unexpected,
}

class PairResult {
  const PairResult.paired(String this.username) : failure = null;
  const PairResult.failed(PairFailure this.failure) : username = null;

  final String? username;
  final PairFailure? failure;

  bool get ok => failure == null;
}

/// Turns a code into a device token: `POST /auth/devices/claim` with no credential, then the token goes
/// to secure storage and nowhere else. The token never reaches the log or the screen.
class PairingService {
  PairingService(
    this._settings, {
    ApiClient Function(Uri base, String? token)? clientFactory,
    this._log,
  }) : _clientFactory =
           clientFactory ??
           ((base, token) => ApiClient(base: base, token: token));

  final SettingsStore _settings;
  final ApiClient Function(Uri base, String? token) _clientFactory;
  final AppLog? _log;

  /// Claims [code] on [serverUrl] for a device called [deviceName] (the server keeps 64 characters).
  Future<PairResult> claim(
    String serverUrl,
    String code,
    String deviceName,
  ) async {
    final client = _clientFactory(apiBaseOf(serverUrl), null);
    try {
      final body = await client.postJson('/auth/devices/claim', {
        'code': code,
        'name': deviceName.trim(),
      });
      final token = body is Map ? body['token'] : null;
      final username = body is Map ? body['username'] : null;
      if (token is! String || token.isEmpty || username is! String) {
        _log?.warn('pairing: the server answered, but not with a token');
        return const PairResult.failed(PairFailure.unexpected);
      }
      await _settings.setToken(token);
      await _settings.setUsername(username);
      _log?.info('paired as $username');
      return PairResult.paired(username);
    } on ApiException catch (e) {
      _log?.warn(
        'pairing failed: ${e.failure.name}${e.status == null ? '' : ' ${e.status}'}',
      );
      return PairResult.failed(switch (e.failure) {
        // 401 from the claim route is "invalid or expired pairing code", not a session problem.
        ApiFailure.unauthorised => PairFailure.invalidCode,
        ApiFailure.rateLimited => PairFailure.rateLimited,
        ApiFailure.network || ApiFailure.timeout => PairFailure.unreachable,
        ApiFailure.server ||
        ApiFailure.forbidden ||
        ApiFailure.badResponse => PairFailure.unexpected,
      });
    } finally {
      client.close();
    }
  }
}
