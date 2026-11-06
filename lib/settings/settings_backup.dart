import '../harness/backup.dart';
import 'server_url.dart';
import 'settings_store.dart';

/// What a backup keeps of the settings: which server the app is pointed at. NOT the device token, which is
/// a credential and is left for the phone to pair again (see [BackupContributor]).
class SettingsBackup implements BackupContributor {
  SettingsBackup(this._settings, {this.onRestored});

  final SettingsStore _settings;

  /// Called after a restore, so the screens that show the server read it again.
  final Future<void> Function()? onRestored;

  @override
  String get key => 'settings';

  @override
  Future<Object?> export() async => {'server_url': _settings.serverUrl};

  // Nothing in the settings section can be damaged badly enough to refuse: a bad address is skipped.
  @override
  Future<void> check(Object? data) async {}

  @override
  Future<void> restore(Object? data) async {
    if (data is! Map) return;
    final raw = data['server_url'];
    // A restored address is checked as a typed one is, so a hand-edited or damaged file cannot plant
    // something that is not an address.
    final url = raw is String ? normaliseServerUrl(raw) : null;
    if (url != null) {
      // A token is good only for the server that issued it, so pointing the app at a different one drops it.
      if (url != _settings.serverUrl) await _settings.forgetServer();
      await _settings.setServerUrl(url);
    }
    await onRestored?.call();
  }
}
