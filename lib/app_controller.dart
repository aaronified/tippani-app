import 'package:flutter/foundation.dart';

import 'api/api_client.dart';
import 'api/capabilities.dart';
import 'api/offline_cache.dart';
import 'harness/app_log.dart';
import 'pairing/devices.dart';
import 'pairing/pairing_service.dart';
import 'settings/server_url.dart';
import 'settings/settings_store.dart';

/// Builds the client for a server. A function so a test can hand the app a client with no network.
typedef ClientFactory = ApiClient Function(Uri base, String? token);

ApiClient _defaultClient(Uri base, String? token) =>
    ApiClient(base: base, token: token);

/// What asking a server "what are you" came to: its answer, or why there was none.
class ServerCheck {
  const ServerCheck.answered(Capabilities this.capabilities)
    : failure = null,
      detail = '';
  const ServerCheck.failed(ApiFailure this.failure, [this.detail = ''])
    : capabilities = null;

  final Capabilities? capabilities;
  final ApiFailure? failure;
  final String detail;

  /// Whether the answering server is one this app can speak to; null when nothing answered.
  Compatibility? get verdict =>
      capabilities == null ? null : compatibilityOf(capabilities!);

  /// A Tippani server answered and its revision is one this app can speak.
  bool get usable => verdict == Compatibility.ok;
}

/// The app's state that more than one screen needs: which server it is pointed at and whether that
/// server is reachable and compatible. Screens listen to it; nothing else holds this state.
class AppController extends ChangeNotifier {
  AppController(this._settings, {ClientFactory? clientFactory, this._log})
    : _clientFactory = clientFactory ?? _defaultClient;

  final SettingsStore _settings;
  final AppLog? _log;
  late final PairingService _pairing = PairingService(
    _settings,
    clientFactory: _clientFactory,
    log: _log,
  );

  // The device token, held in memory once read so a screen can build a client without waiting on storage.
  String? _token;
  bool _revoked = false;
  final ClientFactory _clientFactory;

  /// What the server last said, for the screens that only read (ADR-0022). Cleared whenever the phone stops
  /// being paired, so one account's answers never show under another.
  late final OfflineCache offline = OfflineCache(_settings);

  ServerCheck? _check;
  bool _checking = false;

  String? get serverUrl => _settings.serverUrl;

  /// The last answer for the stored server, or null before the first ask.
  ServerCheck? get check => _check;

  /// Whether this phone holds a device token for the stored server.
  bool get paired => _token != null && _token!.isNotEmpty;

  /// Who this phone is paired as, for display.
  String? get username => paired ? _settings.username : null;

  /// True after the server refused the token (the device was unpaired from the web Settings). The home
  /// screen says so and offers to pair again.
  bool get revoked => _revoked;

  bool _isAdmin = false;

  /// Whether the paired account is an admin, as the server last said. Asked again each time the app opens
  /// and after pairing, and never kept on the phone: an admin who is demoted should lose the admin screens
  /// the next time the app opens, not whenever a stored flag is cleared.
  bool get isAdmin => paired && _isAdmin;

  static const _adminKey = 'paired_admin';

  bool _loaded = false;

  /// Whether the stored token has been read yet. Until it has, [paired] is false whatever the phone holds, so a
  /// screen that opens at start must not read that as "not paired".
  bool get loaded => _loaded;

  /// Reads the stored token once at start.
  Future<void> load() async {
    _token = await _settings.token();
    // the last answer, so a phone that starts with no server still shows the administration it is allowed
    _isAdmin = _settings.read(_adminKey) == 'yes';
    _loaded = true;
    notifyListeners();
    await loadAccount();
  }

  /// Asks the server who this phone is paired as and whether that account is an admin (`GET /auth/me`). A
  /// failure leaves the last answer alone: not being able to ask is not a demotion.
  Future<void> loadAccount() async {
    if (!paired) {
      _isAdmin = false;
      return;
    }
    try {
      final me = await withClient((c) => c.getJson('/auth/me'));
      if (me is Map) {
        _isAdmin = me['is_admin'] == true;
        await _settings.write(_adminKey, _isAdmin ? 'yes' : 'no');
        notifyListeners();
      }
    } on ApiException {
      // unreachable, or the token was refused (withClient has already unpaired the phone)
    }
  }

  /// A client for the stored server carrying the device token, or null when not connected and paired. The
  /// caller closes it.
  ApiClient? authedClient() {
    final url = serverUrl;
    if (url == null || !paired) return null;
    return _clientFactory(apiBaseOf(url), _token)..offline = offline;
  }

  /// Calls [run] with an authenticated client, and treats a refused token as the end of this pairing: the
  /// phone forgets it and the home screen says it was unpaired. Returns null when not paired.
  Future<T?> withClient<T>(Future<T> Function(ApiClient client) run) async {
    final client = authedClient();
    if (client == null) return null;
    try {
      return await run(client);
    } on ApiException catch (e) {
      if (e.failure == ApiFailure.unauthorised) {
        _log?.warn(
          'the server refused the token this phone holds; unpairing it here',
        );
        await _settings.forgetToken();
        await _settings.remove(_adminKey);
        await offline.clear();
        _token = null;
        _revoked = true;
        notifyListeners();
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Pairs this phone with the stored server using [code] from the web Settings.
  Future<PairResult> pair(String code, String deviceName) async {
    final url = serverUrl;
    if (url == null) return const PairResult.failed(PairFailure.unexpected);
    final result = await _pairing.claim(url, code, deviceName);
    if (result.ok) {
      _token = await _settings.token();
      _revoked = false;
      notifyListeners();
      await loadAccount();
    }
    return result;
  }

  /// The devices on this account.
  Future<List<DeviceInfo>?> devices() => withClient(listDevices);

  /// Unpairs [id] from the account.
  Future<void> revoke(int id) async {
    await withClient((c) => revokeDevice(c, id));
  }

  /// Unpairs every device of the account, this phone too: the server ends all their tokens, so this phone
  /// forgets its own as well.
  Future<void> revokeAll() async {
    await withClient<Object?>(
      (c) => c.postJson('/auth/devices/revoke-all', {}),
    );
    // The token is gone with the rest. Asking the server to forget this phone would be answered 401 and read as
    // "unpaired from the server", an alert about something the reader just did on purpose.
    await _forgetPairing();
    _log?.info('unpaired every device');
  }

  Future<void> _forgetPairing() async {
    await _settings.forgetToken();
    await _settings.remove(_adminKey);
    await offline.clear();
    _token = null;
    _isAdmin = false;
    notifyListeners();
  }

  /// Unpairs this phone: asks the server to forget it (best effort; a server that cannot be reached is not
  /// a reason to keep the token), then forgets the token here. The server address stays.
  Future<void> unpair() async {
    try {
      final all = await devices();
      final me = all?.where((d) => d.current).firstOrNull;
      if (me != null) await revoke(me.id);
    } on ApiException {
      // unreachable or already unpaired: the local half still happens
    }
    await _forgetPairing();
    _log?.info('unpaired');
  }

  bool get checking => _checking;

  /// Asks the stored server what it is. Does nothing when none is stored.
  Future<void> refresh() async {
    final url = serverUrl;
    if (url == null) {
      _check = null;
      notifyListeners();
      return;
    }
    _checking = true;
    notifyListeners();
    _check = await probe(url);
    _checking = false;
    notifyListeners();
  }

  /// Asks [serverUrl] what it is without remembering it, for the connect screen to show before it keeps
  /// anything.
  Future<ServerCheck> probe(String serverUrl) async {
    final client = _clientFactory(apiBaseOf(serverUrl), null);
    try {
      final caps = await client.capabilities();
      // The address is not logged (it is the reader's own), only what came of asking.
      _log?.info(
        'server answered: revision ${caps.apiRevision}, version ${caps.version}',
      );
      return ServerCheck.answered(caps);
    } on ApiException catch (e) {
      _log?.warn(
        'server check failed: ${e.failure.name}${e.status == null ? '' : ' ${e.status}'}',
      );
      return ServerCheck.failed(e.failure, e.detail);
    } finally {
      client.close();
    }
  }

  /// Keeps [serverUrl] as the server, after a check that said it is usable.
  Future<void> connect(String serverUrl, ServerCheck check) async {
    assert(check.usable, 'only a usable server is kept');
    await _settings.setServerUrl(serverUrl);
    _log?.info('server kept');
    _check = check;
    notifyListeners();
  }

  /// Forgets the server and its credential together.
  Future<void> forget() async {
    await _settings.forgetServer();
    await _settings.remove(_adminKey);
    await offline.clear();
    _isAdmin = false;
    _log?.info('server forgotten');
    _token = null;
    _revoked = false;
    _check = null;
    notifyListeners();
  }
}
