import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The names of the phone's own preferences (ADR-0034). One list, so a preference added here is scoped to the
/// account and adopted by a new one without a second place to remember it.
class PrefKeys {
  const PrefKeys._();

  static const speechVoiceName = 'speech_voice_name';
  static const speechVoiceLocale = 'speech_voice_locale';
  static const speechRate = 'speech_rate';
  static const speechPitch = 'speech_pitch';
  static const autoSync = 'auto_sync';
  static const tourOutcome = 'tour_outcome';
  static const tourVersion = 'tour_version';
  static const shareTheme = 'share_image_theme';
  static const shareMaterial = 'share_image_material';
  static const shareTint = 'share_image_tint';
  static const shareBackdrop = 'share_portrait';
  static const shareSwap = 'share_swap_sides';
  static const shareSignature = 'share_signature';
  static const shareFace = 'share_face_kind';

  /// The library screens keep a sort, a grouping, a filter and a layout each, under a name that carries the
  /// section: `library_<section>_<choice>`.
  static String library(String section, String choice) =>
      'library_${section}_$choice';

  static const _exact = {
    speechVoiceName,
    speechVoiceLocale,
    speechRate,
    speechPitch,
    autoSync,
    tourOutcome,
    tourVersion,
    shareTheme,
    shareMaterial,
    shareTint,
    shareBackdrop,
    shareSwap,
    shareSignature,
    shareFace,
  };

  /// Whether [bare] is one of the phone's own preferences, as opposed to a fact about the phone or its server
  /// (the address, the token, the version last shown, the sync's own bookkeeping).
  static bool isPreference(String bare) =>
      _exact.contains(bare) || bare.startsWith('library_');
}

/// Whose preferences are in use: the account this phone is paired as, or the phone's own set while it is not
/// (ADR-0034).
///
/// The phone's own set keeps its bare keys, which is what every phone has held until now, so nothing is
/// migrated and an unpaired phone reads what it always did. An account's set is kept beside it under
/// `acct.<owner>.<key>`, and a set that does not exist yet starts as a copy of the phone's own, so the person
/// who set the app up before pairing keeps their choices.
class PreferenceScope extends ChangeNotifier {
  PreferenceScope();

  static final instance = PreferenceScope();

  String? _owner;

  /// The account in use as `server|name`, or null while the phone is unpaired.
  String? get owner => _owner;

  /// The key [bare] is kept under for the set in use.
  String key(String bare) => _owner == null ? bare : '${_prefix(_owner!)}$bare';

  static String _prefix(String owner) => 'acct.$owner.';

  /// Switches to [owner]'s set, or to the phone's own for null. Listeners re-read what they hold.
  Future<void> use(String? owner) async {
    if (owner == _owner) return;
    if (owner != null) await _adopt(owner);
    _owner = owner;
    notifyListeners();
  }

  Future<void> _adopt(String owner) async {
    try {
      final p = await SharedPreferences.getInstance();
      final prefix = _prefix(owner);
      final keys = p.getKeys();
      if (keys.any((k) => k.startsWith(prefix))) return;
      for (final k in keys.where(PrefKeys.isPreference)) {
        final v = p.get(k);
        final to = '$prefix$k';
        switch (v) {
          case final String s:
            await p.setString(to, s);
          case final bool b:
            await p.setBool(to, b);
          case final int i:
            await p.setInt(to, i);
          case final double d:
            await p.setDouble(to, d);
        }
      }
    } on Object {
      // the account starts from the defaults
    }
  }
}
