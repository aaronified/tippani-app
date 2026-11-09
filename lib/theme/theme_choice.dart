import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';

import 'package:flutter/material.dart';

import '../settings/settings_store.dart';

/// Tippani's own red, the seed where the phone gives no wallpaper colours (before Android 12, or a launcher that does not
/// share them) and the first palette.
const Color tippaniSeed = Color(0xFFB4482D);

/// Where the app's colours come from: the phone (Material You, which follows the wallpaper), a photo the reader picks, or
/// one of the app's own palettes. Kept on this phone only, since a colour is a taste of one screen.
class ThemeChoice extends ChangeNotifier {
  ThemeChoice([this._settings]) {
    final s = _settings;
    if (s == null) return;
    final saved = s.read(_sourceKey);
    if (saved != null &&
        (saved == 'system' ||
            saved == 'photo' ||
            palettes.containsKey(saved))) {
      _source = saved;
    }
    final seed = int.tryParse(s.read(_seedKey) ?? '');
    if (seed != null) _photoSeed = Color(seed);
    if (_source == 'photo' && _photoSeed == null) _source = 'system';
  }

  static const _sourceKey = 'theme_source';
  static const _seedKey = 'theme_photo_seed';

  /// The app's own palettes, by name: a seed colour each, from which Material 3 makes the whole scheme.
  static const palettes = <String, Color>{
    'tippani': tippaniSeed,
    'indigo': Color(0xFF4C5BD4),
    'teal': Color(0xFF00897B),
    'forest': Color(0xFF3F7D45),
    'rose': Color(0xFFC2456E),
    'amber': Color(0xFFC77700),
    'slate': Color(0xFF5B6B7B),
  };

  final SettingsStore? _settings;
  String _source = 'system';
  Color? _photoSeed;

  /// 'system', 'photo', or the name of a palette.
  String get source => _source;

  /// The colour picked out of the reader's photo, once there is one.
  Color? get photoSeed => _photoSeed;

  /// The seed of the chosen palette or photo; null for the phone's own colours.
  Color? get seed => switch (_source) {
    'system' => null,
    'photo' => _photoSeed,
    final name => palettes[name],
  };

  Future<void> choose(String source) async {
    if (source != 'system' &&
        source != 'photo' &&
        !palettes.containsKey(source)) {
      return;
    }
    if (source == 'photo' && _photoSeed == null) return;
    _source = source;
    await _settings?.write(_sourceKey, source);
    notifyListeners();
  }

  /// Takes the colours of the picture at [path] and uses them: the dominant colour becomes the seed.
  Future<void> usePhoto(String path) async {
    final scheme = await ColorScheme.fromImageProvider(
      provider: FileImage(File(path)),
    );
    await useSeed(scheme.primary);
  }

  /// Uses [colour] as the seed of the photo choice.
  Future<void> useSeed(Color colour) async {
    _photoSeed = colour;
    _source = 'photo';
    await _settings?.write(_seedKey, '${colour.toARGB32()}');
    await _settings?.write(_sourceKey, 'photo');
    notifyListeners();
  }

  /// The light and dark schemes: the phone's where [lightDynamic] and [darkDynamic] are chosen and given, else made from
  /// the seed (Tippani's red when nothing else applies).
  (ColorScheme, ColorScheme) schemes(
    ColorScheme? lightDynamic,
    ColorScheme? darkDynamic,
  ) {
    final s = seed;
    if (s == null && lightDynamic != null && darkDynamic != null) {
      return (lightDynamic.harmonized(), darkDynamic.harmonized());
    }
    final base = s ?? tippaniSeed;
    return (
      ColorScheme.fromSeed(seedColor: base),
      ColorScheme.fromSeed(seedColor: base, brightness: Brightness.dark),
    );
  }
}
