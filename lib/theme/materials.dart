import 'dart:convert';

import '../account/preferences.dart';

/// One texture: the file under `assets/textures/`, the two sizes it is laid at (logical pixels), and how strongly its
/// grain shows. The numbers are the web's own (`TEXTILES` in the server's `theme.js`), measured there, so a surface
/// looks the same on both.
class Textile {
  const Textile(this.file, this.coarse, this.fine, this.strength);

  /// The asset file, without the folder.
  final String file;
  final double coarse;
  final double fine;

  /// 0 to 1. `flat` is 0 and has no file: no material at all.
  final double strength;

  bool get isFlat => strength == 0 && file.isEmpty;
}

/// Every material a surface can be made of, by the name the server stores (`tileCard: "marble"`).
const textiles = <String, Textile>{
  'flat': Textile('', 0, 0, 0),
  'paper': Textile('paper.webp', 220, 71, 0.10),
  'linen': Textile('linen.png', 340, 109, 0.11),
  'cotton': Textile('cotton.png', 300, 97, 0.12),
  'canvas': Textile('canvas.png', 400, 129, 0.10),
  'denim': Textile('denim.png', 320, 103, 0.12),
  'wool': Textile('wool.png', 360, 113, 0.12),
  'wood': Textile('wood.webp', 300, 97, 0.12),
  'metal': Textile('metal.webp', 260, 84, 0.09),
  'brushed': Textile('brushed.png', 240, 78, 0.08),
  'matte': Textile('matte.png', 200, 65, 0.07),
  'satin': Textile('satin.png', 210, 68, 0.07),
  'glass': Textile('glass.webp', 280, 90, 0.06),
  'glass-soft': Textile('glass-soft.png', 280, 90, 0.12),
  'rubber': Textile('rubber-flat.png', 230, 74, 0.10),
  'fabric': Textile('fabric.webp', 260, 84, 0.11),
  'walnut': Textile('walnut.png', 300, 97, 0.09),
  'pine': Textile('pine.png', 340, 109, 0.09),
  'marble': Textile('marble.png', 360, 116, 0.08),
  'granite': Textile('granite.png', 280, 90, 0.08),
  'sandstone': Textile('sandstone.png', 300, 97, 0.09),
  'concrete': Textile('concrete.png', 320, 103, 0.08),
  'cardboard': Textile('cardboard.png', 280, 90, 0.10),
  'paper-photo': Textile('paper-photo.png', 300, 97, 0.07),
  'leather': Textile('leather-004.png', 260, 84, 0.10),
  'leather-suede': Textile('leather-021.png', 240, 78, 0.11),
  'leather-pebbled': Textile('leather-034d.png', 280, 90, 0.09),
  'leather-tooled': Textile('leather-037.png', 320, 103, 0.06),
};

/// The materials a reader can pick for a slot, in the order the mixer lists them: every one but `flat`, which is the
/// absence of a material and is what Atrium means rather than a tile.
final pickableTextiles = [
  for (final name in textiles.keys)
    if (name != 'flat') name,
];

/// The four surfaces a set dresses: the desk, the furniture, what you write on, what the book is bound in.
const slots = ['ground', 'shell', 'card', 'cover'];

/// The eight sets, each as its material for the four [slots], in that order.
const materialSets = <String, List<String>>{
  'manuscript': ['linen', 'paper', 'paper', 'wood'],
  'film-assembly': ['metal', 'brushed', 'matte', 'glass'],
  'office': ['glass', 'rubber', 'satin', 'metal'],
  'school': ['wood', 'rubber', 'paper', 'cotton'],
  'atelier': ['canvas', 'denim', 'cotton', 'wool'],
  'bindery': ['concrete', 'leather-suede', 'paper-photo', 'leather-pebbled'],
  'quarry': ['sandstone', 'granite', 'satin', 'marble'],
  'atrium': ['flat', 'flat', 'flat', 'flat'],
};

const materialSetDefault = 'manuscript';

/// What a material does with the one light in the room, each 0 to 100.
class Phys {
  const Phys(this.hard, this.sss, this.diff, this.refl);

  /// How tight the highlight is.
  final int hard;

  /// Light entering and coming back out (why paper glows).
  final int sss;

  /// A cool edge to a warm core in the highlight.
  final int diff;

  /// How much of the room it gives back.
  final int refl;

  Phys copyWith({int? hard, int? sss, int? diff, int? refl}) => Phys(
    hard ?? this.hard,
    sss ?? this.sss,
    diff ?? this.diff,
    refl ?? this.refl,
  );

  @override
  bool operator ==(Object other) =>
      other is Phys &&
      other.hard == hard &&
      other.sss == sss &&
      other.diff == diff &&
      other.refl == refl;

  @override
  int get hashCode => Object.hash(hard, sss, diff, refl);
}

/// The factory dials per material (the server's `PHYS`).
const factoryPhys = <String, Phys>{
  'paper': Phys(34, 62, 0, 4),
  'paper-photo': Phys(58, 34, 14, 20),
  'cardboard': Phys(30, 48, 0, 10),
  'linen': Phys(20, 74, 5, 0),
  'cotton': Phys(14, 80, 0, 0),
  'canvas': Phys(26, 58, 0, 9),
  'denim': Phys(24, 42, 0, 8),
  'wool': Phys(6, 66, 0, 2),
  'fabric': Phys(18, 70, 4, 6),
  'leather': Phys(44, 52, 6, 15),
  'leather-suede': Phys(12, 72, 0, 4),
  'leather-pebbled': Phys(50, 46, 8, 18),
  'leather-tooled': Phys(56, 40, 10, 20),
  'wood': Phys(62, 22, 10, 22),
  'walnut': Phys(66, 20, 12, 23),
  'pine': Phys(54, 30, 8, 19),
  'marble': Phys(88, 44, 18, 30),
  'granite': Phys(92, 10, 14, 16),
  'sandstone': Phys(70, 26, 0, 25),
  'concrete': Phys(80, 8, 0, 28),
  'metal': Phys(96, 0, 60, 74),
  'brushed': Phys(90, 0, 72, 52),
  'satin': Phys(74, 12, 46, 34),
  'matte': Phys(46, 8, 4, 5),
  'rubber': Phys(36, 6, 10, 13),
  'glass': Phys(100, 0, 54, 66),
  'glass-soft': Phys(82, 10, 30, 38),
  'flat': Phys(0, 0, 0, 0),
};

/// The four dial names, in the order the mixer draws them, with the server's vocabulary key for each label.
const physDials = <(String, String)>[
  ('hard', 'settings.appearance.phys.hard.label'),
  ('sss', 'settings.appearance.phys.sss.label'),
  ('diff', 'settings.appearance.phys.diff.label'),
  ('refl', 'settings.appearance.phys.refl.label'),
];

/// The reader's own edits to the dials, as the server stores them: one JSON object keyed by material, each holding only
/// the dials that were moved. A value that is not that shape is the factory's, as it is on the web.
Map<String, Map<String, int>> parseTweaks(Object? raw) {
  try {
    final v = raw is String ? (raw.isEmpty ? null : jsonDecode(raw)) : raw;
    if (v is! Map) return const {};
    final out = <String, Map<String, int>>{};
    for (final e in v.entries) {
      final dials = e.value;
      if (e.key is! String || dials is! Map) continue;
      final own = <String, int>{};
      for (final d in dials.entries) {
        final n = d.value;
        if (d.key is String && n is num && n >= 0 && n <= 100) {
          own[d.key as String] = n.round();
        }
      }
      if (own.isNotEmpty) out[e.key as String] = own;
    }
    return out;
  } catch (_) {
    return const {};
  }
}

/// What the account says its surfaces are made of, and how each material catches the light.
class MaterialLook {
  const MaterialLook({
    required this.set,
    required this.overrides,
    required this.tweaks,
  });

  /// The look of a phone that has not heard from the server: no material in any slot, which is how the app looked before
  /// textures and costs nothing to draw.
  static const none = MaterialLook(set: 'atrium', overrides: {}, tweaks: {});

  factory MaterialLook.fromPrefs(ServerPrefs prefs) {
    // The server's answer always carries the set (empty when never chosen); a phone that has only its own settings
    // (a language, a type size) has not heard from the server and stays plain.
    if (!prefs.raw.containsKey('materialSet')) return none;
    final set = materialSets.containsKey(prefs.str('materialSet'))
        ? prefs.str('materialSet')
        : materialSetDefault;
    final overrides = <String, String>{};
    for (final slot in slots) {
      final v = prefs.str('tile${slot[0].toUpperCase()}${slot.substring(1)}');
      if (textiles.containsKey(v)) overrides[slot] = v;
    }
    return MaterialLook(
      set: set,
      overrides: overrides,
      tweaks: parseTweaks(prefs.raw['texTweak']),
    );
  }

  final String set;

  /// slot to material name, only for the slots the reader changed from the set's own.
  final Map<String, String> overrides;
  final Map<String, Map<String, int>> tweaks;

  /// The material of [slot]: the reader's own if they set one, else the set's.
  String tileFor(String slot) =>
      overrides[slot] ?? materialSets[set]![slots.indexOf(slot)];

  /// The dials of material [name] with the reader's edits over the factory's.
  Phys physFor(String name) {
    final base = factoryPhys[name] ?? factoryPhys['matte']!;
    final own = tweaks[name];
    if (own == null) return base;
    return Phys(
      own['hard'] ?? base.hard,
      own['sss'] ?? base.sss,
      own['diff'] ?? base.diff,
      own['refl'] ?? base.refl,
    );
  }

  /// Whether any slot wears a texture, so a surface can skip all drawing for a look that has none.
  bool get hasMaterial => slots.any((s) => !textiles[tileFor(s)]!.isFlat);

  /// The materials in play, each once, for the dials the mixer offers (`flat` has nothing to change).
  List<String> get materialsInUse => [
    for (final n in {for (final s in slots) tileFor(s)})
      if (n != 'flat') n,
  ];
}

/// Has material [name] been moved off the factory? The reset control is offered only where there is something to undo.
bool physDirty(String name, Map<String, Map<String, int>> tweaks) {
  final own = tweaks[name];
  final base = factoryPhys[name] ?? factoryPhys['matte']!;
  if (own == null) return false;
  return (own['hard'] ?? base.hard) != base.hard ||
      (own['sss'] ?? base.sss) != base.sss ||
      (own['diff'] ?? base.diff) != base.diff ||
      (own['refl'] ?? base.refl) != base.refl;
}

/// The `texTweak` value to save after [dials] became the edits of [material] (null puts the material back to the
/// factory). The stored object is kept whole: it also holds the web's glass dials and anything a newer server adds,
/// and none of that is this screen's to drop. Only what differs from the factory is written; '' when nothing does.
String editedTweaks(Object? raw, String material, Map<String, int>? dials) {
  Map<String, Object?> all = {};
  try {
    final v = raw is String ? (raw.isEmpty ? null : jsonDecode(raw)) : raw;
    if (v is Map) {
      all = {for (final e in v.entries) '${e.key}': e.value};
    }
  } catch (_) {
    all = {};
  }
  final base = factoryPhys[material] ?? factoryPhys['matte']!;
  final factory = {
    'hard': base.hard,
    'sss': base.sss,
    'diff': base.diff,
    'refl': base.refl,
  };
  // The material's own entry is merged into, never replaced: the glass material's key is also where the web keeps the
  // lens's dials (clarity, refract, bevel, fringe, gain, blur), and those are not this screen's to drop.
  final existing = all[material];
  final entry = <String, Object?>{
    if (existing is Map)
      for (final e in existing.entries) '${e.key}': e.value,
  };
  for (final dial in factory.keys) {
    final v = dials?[dial];
    if (v == null || v == factory[dial]) {
      entry.remove(dial);
    } else {
      entry[dial] = v;
    }
  }
  if (entry.isEmpty) {
    all.remove(material);
  } else {
    all[material] = entry;
  }
  return all.isEmpty ? '' : jsonEncode(all);
}
