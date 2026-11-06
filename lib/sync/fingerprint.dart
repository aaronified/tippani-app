import 'dart:convert';

import '../library/models.dart';

/// Which of the server's tables an item lives in. Their ids overlap (book 5 and film 5 both exist), so an id
/// means nothing without it.
enum Realm { book, screen, loose }

Realm realmOfKind(WorkKind k) =>
    k == WorkKind.film || k == WorkKind.show || k == WorkKind.game
    ? Realm.screen
    : Realm.book;

/// The realm a quote belongs to on the server, given its work (null for a standalone quote).
Realm realmOfQuote(Work? w) => w == null ? Realm.loose : realmOfKind(w.kind);

/// The server's route for a work in [r] and for a quote in it.
String workRoute(Realm r) => r == Realm.screen ? '/movies' : '/books';
String quoteRoute(Realm r) => switch (r) {
  Realm.book => '/annotations',
  Realm.screen => '/dialogues',
  Realm.loose => '/quotes',
};

typedef Fields = Map<String, Object?>;

String _s(Object? v) => v is String ? v.trim() : '';

List<String> _tags(Object? v) {
  final seen = <String>{};
  final out = <String>[];
  if (v is List) {
    for (final t in v) {
      final name = _s(t);
      if (name.isNotEmpty && seen.add(name.toLowerCase())) {
        out.add(name.toLowerCase());
      }
    }
  }
  return out..sort();
}

/// What a work says, in a shape both sides can be compared in: only what the server also holds, so a field the
/// server cannot keep never makes the two look different. (A work's language is not held by the server's list,
/// so it is not compared; a book and an "other" are one thing to the server.)
Fields workFields(Work w) => {
  'kind': realmOfKind(w.kind) == Realm.screen ? w.kind.name : 'book',
  'title': w.title.trim(),
  'creator': w.creator.trim(),
  'year': w.year == null || w.year == 0 ? null : w.year,
};

/// The same shape, read from a row of the server's `/books` or `/movies` list.
Fields serverWorkFields(Map row, Realm realm) {
  final year = realm == Realm.screen
      ? row['release_year']
      : row['published_year'];
  final media = _s(row['media_type']);
  return {
    'kind': realm == Realm.screen
        ? (media == 'movie' || media.isEmpty ? 'film' : media)
        : 'book',
    'title': _s(row['title']),
    'creator': _s(realm == Realm.screen ? row['director'] : row['author']),
    'year': year is int && year != 0 ? year : null,
  };
}

/// What a quote says, in the same comparable shape. A film's chapter has nowhere to live on the server, so it
/// is left out for a quote in [realm] screen.
Fields quoteFields(Quote q, Realm realm) => {
  'text': q.text.trim(),
  'translation': q.translation.trim(),
  'language': q.language.trim(),
  'speaker': q.speaker.trim(),
  'chapter': realm == Realm.screen ? '' : q.chapter.trim(),
  'location': q.location.trim(),
  'note': q.note.trim(),
  'color': quoteColors.contains(q.color) ? q.color : 'yellow',
  'favorite': q.favorite,
  'tags': _tags(q.tags),
};

/// The same shape, read from a row of the server's `/annotations`, `/dialogues` or `/quotes` list.
Fields serverQuoteFields(Map row, Realm realm) {
  final color = _s(row['color']);
  return {
    'text': _s(row['quote']),
    'translation': _s(row['translation']),
    'language': _s(row['language']),
    'speaker': _s(realm == Realm.loose ? row['speaker'] : row['character']),
    'chapter': switch (realm) {
      Realm.book => _s(row['chapter']),
      Realm.screen => '',
      Realm.loose => _s(row['occasion']),
    },
    'location': _s(switch (realm) {
      Realm.book => row['location'],
      Realm.screen => row['timestamp'],
      Realm.loose => row['place'],
    }),
    'note': _s(row['note']),
    'color': quoteColors.contains(color) ? color : 'yellow',
    'favorite': row['favorite'] == true,
    'tags': _tags(row['tags']),
  };
}

/// A short, stable fingerprint of [fields] (FNV-1a over their canonical JSON). It is only ever compared with
/// another fingerprint made the same way, so a collision would need two different quotes to agree on 64 bits.
String fingerprint(Fields fields) {
  final keys = fields.keys.toList()..sort();
  final text = jsonEncode({for (final k in keys) k: fields[k]});
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(text)) {
    h ^= b;
    h *= 0x100000001b3;
  }
  return h.toRadixString(16).padLeft(16, '0');
}
