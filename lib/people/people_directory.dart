import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app_controller.dart';
import '../library/cover_cache.dart';
import '../library/quote_chips.dart';

/// One person the server knows: the name, and the files of the portrait and the signature ('' for none).
class PersonInfo {
  const PersonInfo(this.name, this.image, this.signature, [this.id = 0]);

  final String name;
  final String image;
  final String signature;

  /// The person's id on the server (0 if unknown), which opens their page.
  final int id;
}

/// One character the server knows: its id, name and the file of its picture ('' for none).
class CharacterInfo {
  const CharacterInfo(this.id, this.name, this.image);

  final int id;
  final String name;
  final String image;
}

String foldName(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Everyone with a face the server holds: authors, actors and speakers by name, and characters by name, kept on
/// the phone so a quote shows the same round portraits as on the web with no server in reach.
abstract class PeopleDirectory implements Listenable {
  /// The person of [kind] ('author', 'actor' or 'speaker') called [name], or null if the server has none.
  PersonInfo? person(String kind, String name);

  /// The person called [name] under any kind (author, actor, director ...), preferring one with a portrait.
  PersonInfo? anyPerson(String name);

  /// The names of everyone of [kind] ('author', 'actor', 'director' ...) the server holds, for suggestions.
  List<String> names(String kind);

  /// The character called [name], or null if the server has none.
  CharacterInfo? character(String name);

  /// The picture file of the character called [name], or '' if there is none.
  String characterImage(String name);

  /// The picture to draw on [chip]: the portrait of an author or a speaker; for a character, its own picture, or
  /// failing that the portrait of the actor who plays them. '' when there is none.
  String faceOf(QuoteChip chip);

  /// A portrait for [name] whatever they are credited as: an author, an actor, a director, a speaker or a
  /// character. '' when there is none.
  String anyFaceOf(String name);

  /// The file of a picture the server names, fetched once and kept; null while it is not there.
  Future<File?> file(String name);

  /// Completes once the lists have been read (from the phone's own copy, and from the server if it answers).
  Future<void> ready();

  /// Reads the lists again from the server (the sync's way of saying "people may have changed").
  Future<void> refresh();

  /// Keeps the pictures the server gave the characters named on quotes (name to file), for chips whose work's cast
  /// has not been read.
  void rememberFaces(Map<String, String> faces);
}

/// The directory read from the paired server (`GET /people?kind=` for each kind, and `GET /characters`) and
/// written beside the covers, so it is there offline and the next start.
class PairedPeopleDirectory extends ChangeNotifier implements PeopleDirectory {
  PairedPeopleDirectory(
    this._controller,
    this._covers, {
    this._folder,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppController _controller;
  final CoverSource _covers;
  Directory? _folder;
  final DateTime Function() _clock;

  final _people = <String, Map<String, PersonInfo>>{};
  final _characters = <String, CharacterInfo>{};
  final _seen = <String, String>{};
  DateTime? _loadedAt;
  Future<void>? _loading;
  bool _diskRead = false;

  /// How long a reading stays good before the next look-up reads again.
  static const staleAfter = Duration(minutes: 15);

  static const kinds = [
    'author',
    'actor',
    'director',
    'speaker',
    'translator',
    'editor',
    'studio',
    'publisher',
  ];

  Future<File> _store() async {
    var d = _folder;
    if (d == null) {
      final base = await getApplicationSupportDirectory();
      d = Directory('${base.path}/people');
      _folder = d;
    }
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/people.json');
  }

  /// Starts a reading if there is none yet or the last one is old. Never waits: the answer comes as a notification.
  void _ensure() {
    if (_loading != null) return;
    final at = _loadedAt;
    if (at != null && _clock().difference(at) < staleAfter) return;
    _loading = _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    if (!_diskRead) {
      _diskRead = true;
      await _readDisk();
      await _readSeen();
    }
    if (!_controller.paired) return;
    try {
      final got = await _controller.withClient((c) async {
        final out = <String, List<Object?>>{};
        for (final k in kinds) {
          final r = await c.getJson('/people?kind=$k');
          out[k] = r is Map && r['people'] is List
              ? (r['people'] as List).cast<Object?>()
              : const [];
        }
        final ch = await c.getJson('/characters');
        out['characters'] = ch is Map && ch['characters'] is List
            ? (ch['characters'] as List).cast<Object?>()
            : const [];
        return out;
      });
      if (got == null) return;
      _apply(got);
      _loadedAt = _clock();
      await _writeDisk(got);
      notifyListeners();
    } on Object {
      // keep what we have; the next look-up tries again
    }
  }

  void _apply(Map<String, List<Object?>> got) {
    _people.clear();
    _characters.clear();
    for (final k in kinds) {
      final byName = <String, PersonInfo>{};
      for (final r in got[k] ?? const <Object?>[]) {
        if (r is! Map) continue;
        final name = '${r['name'] ?? ''}';
        if (name.isEmpty) continue;
        byName[foldName(name)] = PersonInfo(
          name,
          '${r['image_path'] ?? ''}',
          '${r['signature_path'] ?? ''}',
          r['id'] is int ? r['id'] as int : 0,
        );
      }
      _people[k] = byName;
    }
    for (final r in got['characters'] ?? const <Object?>[]) {
      if (r is! Map) continue;
      final image = '${r['image_path'] ?? ''}';
      final name = '${r['name'] ?? ''}';
      if (name.isEmpty) continue;
      final key = foldName(name);
      final had = _characters[key];
      // two characters can share a name; the one with a picture speaks for it
      if (had == null || (had.image.isEmpty && image.isNotEmpty)) {
        _characters[key] = CharacterInfo(
          r['id'] is int ? r['id'] as int : 0,
          name,
          image,
        );
      }
    }
  }

  Future<void> _readDisk() async {
    try {
      final f = await _store();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      final got = <String, List<Object?>>{};
      for (final k in [...kinds, 'characters']) {
        final v = j[k];
        got[k] = v is List ? v.cast<Object?>() : const [];
      }
      _apply(got);
      notifyListeners();
    } on Object {
      // a damaged file is read again from the server
    }
  }

  Future<void> _writeDisk(Map<String, List<Object?>> got) async {
    try {
      final f = await _store();
      final slim = <String, Object?>{};
      for (final e in got.entries) {
        slim[e.key] = [
          for (final r in e.value)
            if (r is Map)
              {
                'id': r['id'],
                'name': r['name'],
                'image_path': r['image_path'],
                'signature_path': r['signature_path'],
              },
        ];
      }
      final tmp = File('${f.path}.part');
      await tmp.writeAsString(jsonEncode(slim), flush: true);
      await tmp.rename(f.path);
    } on Object {
      // not kept; read again next time
    }
  }

  @override
  PersonInfo? person(String kind, String name) {
    _ensure();
    return _people[kind]?[foldName(name)];
  }

  @override
  PersonInfo? anyPerson(String name) {
    _ensure();
    final key = foldName(name);
    PersonInfo? found;
    for (final k in kinds) {
      final p = _people[k]?[key];
      if (p == null) continue;
      if (p.image.isNotEmpty) return p;
      found ??= p;
    }
    return found;
  }

  @override
  List<String> names(String kind) {
    _ensure();
    return [
      for (final p in _people[kind]?.values ?? const <PersonInfo>[]) p.name,
    ];
  }

  @override
  CharacterInfo? character(String name) {
    _ensure();
    return _characters[foldName(name)];
  }

  @override
  String characterImage(String name) {
    _ensure();
    final own = _characters[foldName(name)]?.image ?? '';
    return own.isNotEmpty ? own : _seen[foldName(name)] ?? '';
  }

  @override
  void rememberFaces(Map<String, String> faces) {
    var changed = false;
    for (final e in faces.entries) {
      final k = foldName(e.key);
      if (_seen[k] != e.value) {
        _seen[k] = e.value;
        changed = true;
      }
    }
    if (!changed) return;
    notifyListeners();
    _saveSeen();
  }

  Future<void> _saveSeen() async {
    try {
      final f = await _store();
      final s = File('${f.path}.seen');
      await s.writeAsString(jsonEncode(_seen), flush: true);
    } on Object {
      // not kept; the next sync gives them again
    }
  }

  Future<void> _readSeen() async {
    try {
      final f = await _store();
      final s = File('${f.path}.seen');
      if (!await s.exists()) return;
      final j = jsonDecode(await s.readAsString());
      if (j is Map) {
        for (final e in j.entries) {
          _seen.putIfAbsent('${e.key}', () => '${e.value}');
        }
      }
    } on Object {
      // read again from the next sync
    }
  }

  @override
  String faceOf(QuoteChip chip) {
    // the work's own cast names the picture best: that character in this work
    if (chip.image.isNotEmpty && chip.kind != ChipKind.author) {
      return chip.image;
    }
    switch (chip.kind) {
      case ChipKind.author:
        final a = person('author', chip.name)?.image ?? '';
        return a.isNotEmpty ? a : anyPerson(chip.name)?.image ?? '';
      case ChipKind.speaker:
        final s = person('speaker', chip.name)?.image ?? '';
        if (s.isNotEmpty) return s;
        final p = anyPerson(chip.name)?.image ?? '';
        // a name spoken in a book can be a character
        return p.isNotEmpty ? p : characterImage(chip.name);
      case ChipKind.character:
        final own = characterImage(chip.name);
        if (own.isNotEmpty) return own;
        return chip.actor.isEmpty
            ? ''
            : person('actor', chip.actor)?.image ?? '';
    }
  }

  @override
  String anyFaceOf(String name) {
    _ensure();
    final key = foldName(name);
    for (final k in kinds) {
      final img = _people[k]?[key]?.image ?? '';
      if (img.isNotEmpty) return img;
    }
    return characterImage(name);
  }

  @override
  Future<File?> file(String name) => _covers.fileFor(name);

  @override
  Future<void> ready() async {
    _ensure();
    await _loading;
  }

  @override
  Future<void> refresh() async {
    _loadedAt = null;
    _ensure();
    await _loading;
  }
}

/// Gives the screens below it the [PeopleDirectory].
class PeopleDirectoryScope extends InheritedWidget {
  const PeopleDirectoryScope({
    super.key,
    required this.directory,
    required super.child,
  });

  final PeopleDirectory? directory;

  static PeopleDirectory? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PeopleDirectoryScope>()
      ?.directory;

  @override
  bool updateShouldNotify(PeopleDirectoryScope old) =>
      old.directory != directory;
}

/// A round portrait for one chip (or [fallback], the initial, while there is none). Reads the picture from the
/// [PeopleDirectory] and draws it cropped to the circle, as the web does.
class PersonFace extends StatefulWidget {
  const PersonFace({
    super.key,
    required QuoteChip this.chip,
    required this.radius,
    required this.fallback,
  }) : anyName = null;

  /// The portrait of [name] whoever they are credited as (see [PeopleDirectory.anyFaceOf]).
  const PersonFace.any({
    super.key,
    required String this.anyName,
    required this.radius,
    required this.fallback,
  }) : chip = null;

  final QuoteChip? chip;
  final String? anyName;
  final double radius;
  final Widget fallback;

  @override
  State<PersonFace> createState() => _PersonFaceState();
}

class _PersonFaceState extends State<PersonFace> {
  PeopleDirectory? _dir;
  String _name = '';
  Future<File?>? _file;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final d = PeopleDirectoryScope.of(context);
    if (!identical(d, _dir)) {
      _dir?.removeListener(_changed);
      _dir = d;
      d?.addListener(_changed);
    }
    _look();
  }

  @override
  void didUpdateWidget(PersonFace old) {
    super.didUpdateWidget(old);
    _look();
  }

  @override
  void dispose() {
    _dir?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(_look);
  }

  void _look() {
    final d = _dir;
    final name = d == null
        ? ''
        : widget.chip != null
        ? d.faceOf(widget.chip!)
        : d.anyFaceOf(widget.anyName ?? '');
    if (name == _name) return;
    _name = name;
    _file = name.isEmpty ? null : d!.file(name);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    final f = _file;
    if (f == null) return widget.fallback;
    return FutureBuilder<File?>(
      future: f,
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) return widget.fallback;
        return ClipOval(
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: (size * 3).round(),
            errorBuilder: (_, _, _) => widget.fallback,
          ),
        );
      },
    );
  }
}
