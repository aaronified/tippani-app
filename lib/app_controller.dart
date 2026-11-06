import 'package:flutter/foundation.dart';

import 'api/api_client.dart';
import 'api/capabilities.dart';
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
  AppController(this._settings, {ClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? _defaultClient;

  final SettingsStore _settings;
  final ClientFactory _clientFactory;

  ServerCheck? _check;
  bool _checking = false;

  String? get serverUrl => _settings.serverUrl;

  /// The last answer for the stored server, or null before the first ask.
  ServerCheck? get check => _check;

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
      return ServerCheck.answered(await client.capabilities());
    } on ApiException catch (e) {
      return ServerCheck.failed(e.failure, e.detail);
    } finally {
      client.close();
    }
  }

  /// Keeps [serverUrl] as the server, after a check that said it is usable.
  Future<void> connect(String serverUrl, ServerCheck check) async {
    assert(check.usable, 'only a usable server is kept');
    await _settings.setServerUrl(serverUrl);
    _check = check;
    notifyListeners();
  }

  /// Forgets the server and its credential together.
  Future<void> forget() async {
    await _settings.forgetServer();
    _check = null;
    notifyListeners();
  }
}
