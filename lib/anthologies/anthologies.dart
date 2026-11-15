import 'dart:typed_data';

import '../api/api_client.dart';
import '../app_controller.dart';
import '../sync/fingerprint.dart';
import '../l10n/l10n.dart';

/// A collection of quotes the reader has gathered and ordered, kept on the server.
class Anthology {
  const Anthology({
    required this.id,
    required this.title,
    required this.intro,
    required this.entries,
    required this.raw,
  });

  final int id;
  final String title;
  final String intro;

  /// How many passages it holds.
  final int entries;

  /// The server's whole row. An edit sends it back with only the fields it changes altered, so the display
  /// switches this app does not show are not wiped.
  final Map<String, Object?> raw;

  factory Anthology.fromJson(Map<String, Object?> j) => Anthology(
    id: (j['id'] as num).toInt(),
    title: (j['title'] as String?) ?? '',
    intro: (j['intro'] as String?) ?? '',
    entries: (j['entries'] as num?)?.toInt() ?? 0,
    raw: j,
  );

  String _s(String key) => (raw[key] as String?) ?? '';

  /// How passages are grouped under a heading: '', 'work', 'person' or 'character'.
  String get groupBy => _s('group_by');

  /// The name of the cover picture file on the server, or ''.
  String get coverPath => _s('cover_path');

  /// The name of the landscape poster file on the server, or '' (the page draws one from the title).
  String get posterPath => _s('poster_path');

  /// What the reader wrote about the book, apart from the introduction.
  String get description => _s('description');

  /// The reader's epigraph and dedication, shown before the passages.
  String get epigraph => _s('epigraph');
  String get dedication => _s('dedication');

  /// The search that fills it ('' for none) and whether it keeps filling as quotes arrive.
  String get rule => _s('rule');
  bool get ruleAuto => raw['rule_auto'] == true;

  /// A display switch the server keeps (`hide_credit`, `hide_source`, `hide_commentary`, `hide_colour`,
  /// `show_locator`, `show_date`).
  bool flag(String key) => raw[key] == true;

  /// The stored switches beyond those six, key to on/off, as the server sends them (`fields`).
  Map<String, bool> get extra {
    final f = raw['fields'];
    return f is Map
        ? {
            for (final e in f.entries)
              if (e.value is bool) '${e.key}': e.value as bool,
          }
        : const {};
  }

  /// Whether this anthology shows [key] (the registry's own key: `credit`, `translation`, `isbn`, ...), before any
  /// passage's own choice. The six that have a column of their own are spelled `hide_` or `show_` there; the rest are
  /// off until switched on, except the quote's own note, which has always shown.
  bool shows(String key) {
    switch (key) {
      case 'credit':
        return !flag('hide_credit');
      case 'source':
        return !flag('hide_source');
      case 'commentary':
        return !flag('hide_commentary');
      case 'colour':
        return !flag('hide_colour');
      case 'locator':
        return flag('show_locator');
      case 'date':
        return flag('show_date');
    }
    final on = extra[key];
    return key == 'note' ? on != false : on == true;
  }
}

/// One display switch: the key the server stores it under, the words for the reader, and how it is stored. The six
/// from the first version keep their `hide_`/`show_` column (a "hide" switch is on unless set); every later one is a key of
/// the stored `fields` object. [part] says which group of the dialog it sits in, and [byDefault] marks the one that
/// shows until it is switched off (the quote's own note).
class AnthologySwitch {
  const AnthologySwitch(
    this.key,
    this.label, {
    this.hide = false,
    this.stored = false,
    this.byDefault = false,
    this.part = 'passage',
  });

  final String key;
  final String label;
  final bool hide;
  final bool stored;
  final bool byDefault;
  final String part;

  /// The registry's own name for it, which is also what an entry's override is keyed by.
  String get name =>
      stored ? key : key.replaceFirst(RegExp(r'^(hide|show)_'), '');
}

/// The display switches of an anthology, in the order the page offers them: what the document prints about a
/// passage, what the quote itself carries, what its book or film knows, and who is answerable for it.
final anthologySwitches = <AnthologySwitch>[
  AnthologySwitch(
    'hide_credit',
    tx('app.anthologies.who_it_is_by'),
    hide: true,
  ),
  AnthologySwitch(
    'hide_source',
    tx('app.anthologies.the_book_or_film'),
    hide: true,
  ),
  AnthologySwitch(
    'hide_commentary',
    tx('app.anthologies.my_commentary'),
    hide: true,
  ),
  AnthologySwitch(
    'hide_colour',
    tx('app.anthologies.the_colour_edge'),
    hide: true,
  ),
  AnthologySwitch('show_locator', tx('app.anthologies.where_in_the_work')),
  AnthologySwitch('show_date', tx('app.anthologies.the_date')),
  for (final (key, label, byDefault) in const [
    ('note', 'anthologies.form.fields.note.label', true),
    ('translation', 'anthologies.form.fields.translation.label', false),
    ('language', 'anthologies.form.fields.language.label', false),
    ('tags', 'anthologies.form.fields.tags.label', false),
    ('context', 'anthologies.form.fields.context.label', false),
  ])
    AnthologySwitch(
      key,
      tx(label),
      stored: true,
      byDefault: byDefault,
      part: 'quote',
    ),
  for (final key in const [
    'author',
    'director',
    'translator',
    'editor',
    'publisher',
    'year',
    'series',
    'subtitle',
    'isbn',
    'pages',
    'media-type',
  ])
    AnthologySwitch(
      key.replaceAll('-', '_'),
      tx('common.field.$key.label'),
      stored: true,
      part: 'work',
    ),
  for (final key in const ['bio', 'born', 'died', 'links'])
    AnthologySwitch(
      key,
      tx('common.field.$key.label'),
      stored: true,
      part: 'person',
    ),
];

/// The parts of a quote a passage may restate for itself, by the key the server takes, with the name of the field
/// that carries it in a passage as the server sends it.
const anthologyEditable = <String, String>{
  'quote': 'quote',
  'note': 'quote_note',
  'translation': 'translation',
  'context_before': 'context_before',
  'context_after': 'context_after',
};

/// One passage in an anthology, as the server draws it.
class AnthologyEntry {
  const AnthologyEntry({
    required this.kind,
    required this.itemId,
    required this.quote,
    required this.note,
    required this.source,
    required this.credit,
    required this.color,
    required this.language,
    required this.locator,
    this.position = 0,
    this.favorite = false,
    this.workId = 0,
    this.personName = '',
    this.characterName = '',
    this.date = '',
    this.quoteNote = '',
    this.translation = '',
    this.tags = const [],
    this.contextBefore = '',
    this.contextAfter = '',
    this.work = const {},
    this.person = const {},
    this.fields = const {},
    this.edits = const {},
    this.originals = const {},
  });

  /// "book", "screen" or "utterance": which of the server's tables [itemId] is in.
  final String kind;
  final int itemId;
  final String quote;

  /// The reader's commentary for this passage in this anthology.
  final String note;
  final String source;
  final String credit;
  final String color;
  final String language;
  final String locator;

  /// Where it sits among the passages and headings (they are ordered by this number).
  final double position;
  final bool favorite;

  /// The id of the work it is from, 0 for a standalone quote.
  final int workId;
  final String personName;
  final String characterName;
  final String date;

  /// What the quote itself carries: its own note (not the commentary above, which belongs to this anthology), what it
  /// says in another language, its tags, and the source text before and after it. Already the anthology's version
  /// where this passage restates one of them ([edits]); [originals] holds the library's own words for those.
  final String quoteNote;
  final String translation;
  final List<String> tags;
  final String contextBefore;
  final String contextAfter;

  /// What its book or film, and its person, know, by the registry's keys (only the ones that have a value).
  final Map<String, String> work;
  final Map<String, String> person;

  /// THIS passage's own choice of what it shows, key to shown or hidden, over the anthology's switches.
  final Map<String, bool> fields;

  /// The parts of the quote this anthology restates for this passage, and what the library says in their place.
  final Map<String, String> edits;
  final Map<String, String> originals;

  /// A copy with some things changed, for the code that has to keep a passage and change one part of it.
  AnthologyEntry copyWith({
    double? position,
    String? note,
    Map<String, bool>? fields,
    Map<String, String>? edits,
    Map<String, String>? originals,
    String? quote,
    String? quoteNote,
    String? translation,
    String? contextBefore,
    String? contextAfter,
  }) => AnthologyEntry(
    kind: kind,
    itemId: itemId,
    quote: quote ?? this.quote,
    note: note ?? this.note,
    source: source,
    credit: credit,
    color: color,
    language: language,
    locator: locator,
    position: position ?? this.position,
    favorite: favorite,
    workId: workId,
    personName: personName,
    characterName: characterName,
    date: date,
    quoteNote: quoteNote ?? this.quoteNote,
    translation: translation ?? this.translation,
    tags: tags,
    contextBefore: contextBefore ?? this.contextBefore,
    contextAfter: contextAfter ?? this.contextAfter,
    work: work,
    person: person,
    fields: fields ?? this.fields,
    edits: edits ?? this.edits,
    originals: originals ?? this.originals,
  );

  /// Whether this passage shows [key]: its own choice if it has one, else what [a] says.
  bool shownIn(Anthology a, String key) => fields[key] ?? a.shows(key);

  factory AnthologyEntry.fromJson(Map<String, Object?> j) => AnthologyEntry(
    kind: (j['kind'] as String?) ?? '',
    itemId: (j['item_id'] as num?)?.toInt() ?? 0,
    quote: (j['quote'] as String?) ?? '',
    note: (j['note'] as String?) ?? '',
    source: (j['source'] as String?) ?? '',
    credit: (j['credit'] as String?) ?? '',
    color: (j['color'] as String?) ?? 'yellow',
    language: (j['language'] as String?) ?? '',
    locator: (j['locator'] as String?) ?? '',
    position: (j['position'] as num?)?.toDouble() ?? 0,
    favorite: j['favorite'] == true,
    workId: (j['work_id'] as num?)?.toInt() ?? 0,
    personName: (j['person_name'] as String?) ?? '',
    characterName: (j['character_name'] as String?) ?? '',
    date: (j['date'] as String?) ?? '',
    quoteNote: (j['quote_note'] as String?) ?? '',
    translation: (j['translation'] as String?) ?? '',
    tags: [
      for (final t in (j['tags'] as List?) ?? const [])
        if (t is String) t,
    ],
    contextBefore: (j['context_before'] as String?) ?? '',
    contextAfter: (j['context_after'] as String?) ?? '',
    work: _strings(j['work']),
    person: _strings(j['person']),
    fields: {
      for (final e in ((j['fields'] as Map?) ?? const {}).entries)
        if (e.value is bool) '${e.key}': e.value as bool,
    },
    edits: _strings(j['edits']),
    originals: _strings(j['originals']),
  );

  static Map<String, String> _strings(Object? v) => v is Map
      ? {
          for (final e in v.entries)
            if (e.value is String) '${e.key}': e.value as String,
        }
      : const {};

  /// Who and where it is from, on one line.
  String get from => [
    credit,
    source,
    locator,
  ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');

  /// The key passages are grouped by under [by] ('work', 'person' or 'character'), '' when it has none.
  String groupKey(String by) => switch (by) {
    'work' =>
      workId != 0 ? 'w:$workId' : (source.isNotEmpty ? 's:$source' : ''),
    'person' => personName.isNotEmpty ? personName : credit,
    'character' => characterName,
    _ => '',
  };

  /// The heading for the group this passage opens.
  String groupLabel(String by) {
    final label = switch (by) {
      'work' => source,
      'person' => personName.isNotEmpty ? personName : credit,
      _ => characterName,
    };
    return label.isEmpty ? tx('app.anthologies.not_named') : label;
  }

  /// Names a passage by what the server calls it.
  String get ref => '$kind/$itemId';
}

/// A heading the reader put between passages, with the words under it.
class AnthologySection {
  const AnthologySection({
    required this.id,
    required this.position,
    required this.title,
    required this.prose,
  });

  final int id;
  final double position;
  final String title;
  final String prose;

  factory AnthologySection.fromJson(Map<String, Object?> j) => AnthologySection(
    id: (j['id'] as num?)?.toInt() ?? 0,
    position: (j['position'] as num?)?.toDouble() ?? 0,
    title: (j['title'] as String?) ?? '',
    prose: (j['prose'] as String?) ?? '',
  );
}

/// One place in the running order: a passage or a heading.
class AnthologySlot {
  const AnthologySlot.entry(AnthologyEntry this.entry) : section = null;
  const AnthologySlot.section(AnthologySection this.section) : entry = null;

  final AnthologyEntry? entry;
  final AnthologySection? section;

  double get position => entry?.position ?? section!.position;

  /// What the server's order route calls this slot.
  ({String kind, int itemId}) get ref => entry != null
      ? (kind: entry!.kind, itemId: entry!.itemId)
      : (kind: 'section', itemId: section!.id);
}

class AnthologyDetail {
  const AnthologyDetail(
    this.anthology,
    this.entries, [
    this.sections = const [],
  ]);
  final Anthology anthology;
  final List<AnthologyEntry> entries;
  final List<AnthologySection> sections;

  /// The passages and headings in the order they are read.
  List<AnthologySlot> get slots {
    final all = [
      for (final e in entries) AnthologySlot.entry(e),
      for (final s in sections) AnthologySlot.section(s),
    ];
    all.sort((a, b) => a.position.compareTo(b.position));
    return all;
  }
}

/// A passage the server took out of an anthology and keeps, so it can be put back where it was.
class RemovedPassage {
  const RemovedPassage({
    required this.kind,
    required this.itemId,
    required this.quote,
    required this.source,
    required this.credit,
    required this.note,
  });

  final String kind;
  final int itemId;
  final String quote;
  final String source;
  final String credit;
  final String note;

  factory RemovedPassage.fromJson(Map<String, Object?> j) => RemovedPassage(
    kind: (j['kind'] as String?) ?? '',
    itemId: (j['item_id'] as num?)?.toInt() ?? 0,
    quote: (j['quote'] as String?) ?? '',
    source: (j['source'] as String?) ?? '',
    credit: (j['credit'] as String?) ?? '',
    note: (j['note'] as String?) ?? '',
  );
}

/// What a fill did, or (a preview) would do.
class FillResult {
  const FillResult({
    required this.added,
    required this.matched,
    required this.skipped,
    required this.capped,
    this.items = const [],
  });

  /// Passages put in the anthology now (always 0 for a preview).
  final int added;

  /// How many quotes the rule found.
  final int matched;

  /// Found but already in it (or taken out of it by the reader).
  final int skipped;

  /// The anthology reached the most passages the server allows.
  final bool capped;

  /// Some of what was found, for a preview.
  final List<AnthologyEntry> items;
}

/// The words the fill chooser offers, from the server's search vocabulary. Books and films are (id, title).
class FillVocabulary {
  const FillVocabulary({
    this.tags = const [],
    this.authors = const [],
    this.shelves = const [],
    this.books = const [],
    this.movies = const [],
    this.colours = const [],
  });

  final List<String> tags, authors, shelves;
  final List<({String key, String name})> books, movies, colours;

  static List<({String key, String name})> _pairs(Object? v) => [
    if (v is List)
      for (final x in v)
        if (x is Map)
          (
            key: '${x['key'] ?? x['id'] ?? ''}',
            name: '${x['name'] ?? x['title'] ?? ''}',
          ),
  ];

  static List<String> _names(Object? v) => [
    if (v is List)
      for (final x in v)
        if (x is String) x,
  ];

  factory FillVocabulary.fromJson(Map<String, Object?> j) => FillVocabulary(
    tags: _names(j['tags']),
    authors: _names(j['authors']),
    shelves: _names(j['shelves']),
    books: _pairs(j['books']),
    movies: _pairs(j['movies']),
    colours: _pairs(j['colours']),
  );
}

/// The places a fill can take passages from, in the order the chooser lists them.
enum FillSource {
  all('anthologies.fill.all.label'),
  book('anthologies.fill.book.label'),
  movie('anthologies.fill.movie.label'),
  tag('anthologies.fill.tag.label'),
  author('anthologies.fill.author.label'),
  colour('anthologies.fill.colour.label'),
  shelf('anthologies.fill.shelf.label'),
  favourite('anthologies.fill.favourite.label'),
  dates('anthologies.fill.dates.label');

  const FillSource(this.label);
  final String label;

  /// The search field the value goes in, or null for a source that has no value.
  String? get field => switch (this) {
    book => 'book',
    movie => 'movie',
    tag => 'tag',
    author => 'author',
    colour => 'colour',
    shelf => 'shelf',
    _ => null,
  };
}

/// The search the server runs for a fill: [source], and its [value] (a title's id, a tag's name, ...) or, for
/// "Saved between", a [from] and [to] date (YYYY-MM-DD). '' when what is needed has not been chosen.
String fillRule(
  FillSource source, {
  String value = '',
  String from = '',
  String to = '',
}) {
  final p = <String, String>{'scope': 'all'};
  switch (source) {
    case FillSource.all:
      break;
    case FillSource.favourite:
      p['favourite'] = 'yes';
    case FillSource.dates:
      if (from.isEmpty && to.isEmpty) return '';
      if (from.isNotEmpty) p['added_from'] = from;
      if (to.isNotEmpty) p['added_to'] = to;
    default:
      if (value.isEmpty) return '';
      p[source.field!] = value;
  }
  return p.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');
}

/// A file the server made of an anthology, to be saved or sent.
class ExportedFile {
  const ExportedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// The server's word for where a quote lives, from the phone's: books and films are different tables.
String entryKindOf(Realm realm) => switch (realm) {
  Realm.book => 'book',
  Realm.screen => 'screen',
  Realm.loose => 'utterance',
};

/// Anything that went wrong with an anthology, in words for the reader.
class AnthologyException implements Exception {
  const AnthologyException(this.message, {this.unreachable = false});
  final String message;

  /// The server could not be reached at all (no network, too slow, or nothing paired), as opposed to the
  /// server answering "no". Only this is worth keeping a change for: it goes up when the server is back.
  final bool unreachable;
  @override
  String toString() => message;
}

/// What the screens need of the server's anthologies. An interface so a test can stand in for the server.
abstract class AnthologyService {
  /// Whether there is a paired server to ask.
  bool get available;

  /// Whether the server can keep a poster and a description (API revision 10). True while the server has not
  /// been asked: a change made then waits, and the server's refusal is shown.
  bool get hasPoster;

  /// Runs [run], which makes a request that may be sent twice, under [key]: the server answers a repeated key
  /// with the first answer, so a request whose reply was lost makes nothing twice. A null key is no key.
  Future<T> keyed<T>(String? key, Future<T> Function() run);

  Future<List<Anthology>> list();
  Future<AnthologyDetail> get(int id);
  Future<Anthology> create(String title, String intro);

  /// Changes the title and introduction of [a], keeping everything else the server holds for it.
  Future<void> edit(
    Anthology a, {
    required String title,
    required String intro,
  });

  /// Changes which parts of each passage the anthology shows (see [anthologySwitches]), keeping the rest.
  Future<void> setSwitches(Anthology a, Map<String, bool> switches);
  Future<void> delete(int id);

  /// Adds the quote [itemId] (in the server's [kind] table) to the end of anthology [id]. False when it was
  /// already in it.
  Future<bool> add(int id, String kind, int itemId);
  Future<void> removeEntry(int id, String kind, int itemId);

  /// The reader's commentary on one passage.
  Future<void> setNote(int id, String kind, int itemId, String note);

  /// What one passage shows and says in this anthology only: [fields] is its own show/hide choice per key (null puts
  /// a key back to the anthology's), [edits] the words it restates (null puts the quote's own back). The quote in the
  /// library is never written.
  Future<void> setEntryDisplay(
    int id,
    String kind,
    int itemId, {
    Map<String, bool?> fields = const {},
    Map<String, String?> edits = const {},
  });

  /// Moves the passage or heading [kind]/[itemId] to follow [after] (null: to the top). A heading ('section')
  /// takes the passages under it along.
  Future<void> move(
    int id,
    String kind,
    int itemId, {
    ({String kind, int itemId})? after,
  });

  Future<AnthologySection> addSection(
    int id,
    String title,
    String prose, {
    ({String kind, int itemId})? after,
  });
  Future<void> editSection(int id, int sectionId, String title, String prose);
  Future<void> deleteSection(int id, int sectionId);

  /// How passages are grouped under headings: '', 'work', 'person' or 'character'.
  Future<void> setGrouping(int id, String groupBy);

  /// The epigraph and dedication, and the description when one is given (left alone when null).
  Future<void> setFront(
    int id,
    String epigraph,
    String dedication, {
    String? description,
  });

  /// Sets the landscape poster; returns its file name.
  Future<String> setPoster(int id, Uint8List bytes, String fileName);

  /// Takes the poster away.
  Future<void> removePoster(int id);

  /// Puts a picture on as the cover, and returns the new cover's file name.
  Future<String> setCover(int id, Uint8List bytes, String fileName);
  Future<void> removeCover(int id);

  /// Runs (or with [preview], only counts) a fill from the search [rule].
  Future<FillResult> fill(
    int id,
    String rule, {
    bool preview = false,
    bool auto = false,
  });
  Future<FillVocabulary> vocabulary();

  /// What the reader took out, which can be put back.
  Future<List<RemovedPassage>> removed(int id);
  Future<void> restore(int id, String kind, int itemId);

  /// The anthology as a Markdown file, or an EPUB book.
  Future<ExportedFile> export(int id, {bool epub = false});
}

/// The paired server's anthologies, through the app's own API client.
class ServerAnthologies implements AnthologyService {
  ServerAnthologies(this._controller);

  final AppController _controller;

  @override
  bool get available => _controller.paired;

  String? _key;

  @override
  Future<T> keyed<T>(String? key, Future<T> Function() run) async {
    _key = key;
    try {
      return await run();
    } finally {
      _key = null;
    }
  }

  @override
  bool get hasPoster {
    final caps = _controller.check?.capabilities;
    return caps == null || caps.has('anthology-poster');
  }

  Future<T> _call<T>(Future<T> Function(ApiClient c) run) async {
    if (!available) {
      throw const AnthologyException(
        'This phone is not paired with a server.',
        unreachable: true,
      );
    }
    try {
      // withClient answers null only when nothing is paired (checked above); a call that returns nothing
      // (a delete) is a null that is not a failure.
      return await _controller.withClient(run) as T;
    } on ApiException catch (e) {
      throw AnthologyException(
        // A server that is restarting behind a proxy answers 502, 503 or 504, and one that is busy answers 429:
        // none of those is a refusal of the change, so it waits and is sent again.
        unreachable:
            e.failure == ApiFailure.network ||
            e.failure == ApiFailure.timeout ||
            e.failure == ApiFailure.unauthorised ||
            e.failure == ApiFailure.rateLimited ||
            (e.failure == ApiFailure.server && (e.status ?? 0) >= 502),
        switch (e.failure) {
          ApiFailure.network => tx(
            'app.admin_service.the_server_could_not_be_reached',
          ),
          ApiFailure.timeout => tx(
            'app.admin_service.the_server_took_too_long_to',
          ),
          ApiFailure.unauthorised => tx(
            'app.board_service.the_server_no_longer_accepts_this',
          ),
          ApiFailure.forbidden => tx(
            'app.account_service.the_server_does_not_allow_that',
          ),
          ApiFailure.rateLimited => tx(
            'app.board_service.the_server_asks_you_to_wait',
          ),
          ApiFailure.server || ApiFailure.badResponse =>
            e.detail.isNotEmpty
                ? e.detail
                : tx('app.admin_service.the_server_could_not_do_that'),
        },
      );
    }
  }

  Map<String, Object?> _map(Object? v) => v is Map
      ? Map<String, Object?>.from(v)
      : throw const AnthologyException('The server sent something unexpected.');

  @override
  Future<List<Anthology>> list() => _call((c) async {
    final body = _map(await c.getJson('/anthologies'));
    final all = body['anthologies'];
    if (all is! List) return <Anthology>[];
    return [for (final a in all) Anthology.fromJson(_map(a))];
  });

  @override
  Future<AnthologyDetail> get(int id) => _call((c) async {
    final body = _map(await c.getJson('/anthologies/$id'));
    final entries = body['entries'];
    final sections = body['sections'];
    return AnthologyDetail(
      Anthology.fromJson(_map(body['anthology'])),
      [
        if (entries is List)
          for (final e in entries) AnthologyEntry.fromJson(_map(e)),
      ],
      [
        if (sections is List)
          for (final s in sections) AnthologySection.fromJson(_map(s)),
      ],
    );
  });

  @override
  Future<Anthology> create(String title, String intro) => _call((c) async {
    final made = await c.postJson('/anthologies', {
      'title': title,
      'intro': intro,
    }, idempotencyKey: _key);
    return Anthology.fromJson(_map(made));
  });

  @override
  Future<void> edit(
    Anthology a, {
    required String title,
    required String intro,
  }) => _call((c) async {
    // The server's PUT is the whole record; send back what it holds with the two fields changed.
    final body = Map<String, Object?>.from(a.raw)
      ..['title'] = title
      ..['intro'] = intro;
    await c.putJson('/anthologies/${a.id}', body);
  });

  @override
  Future<void> setSwitches(Anthology a, Map<String, bool> switches) =>
      _call((c) async {
        final body = Map<String, Object?>.from(a.raw);
        final stored = {
          for (final s in anthologySwitches)
            if (s.stored) s.key,
        };
        final fields = {...a.extra};
        for (final e in switches.entries) {
          if (stored.contains(e.key)) {
            fields[e.key] = e.value;
          } else {
            body[e.key] = e.value;
          }
        }
        body['fields'] = fields;
        await c.putJson('/anthologies/${a.id}', body);
      });

  @override
  Future<void> delete(int id) => _call((c) async {
    await c.delete('/anthologies/$id');
  });

  @override
  Future<bool> add(int id, String kind, int itemId) => _call((c) async {
    final r = await c.postJson('/anthologies/$id/entries', {
      'items': [
        {'kind': kind, 'item_id': itemId},
      ],
    }, idempotencyKey: _key);
    return r is Map && (r['added'] as num? ?? 0) > 0;
  });

  @override
  Future<void> removeEntry(int id, String kind, int itemId) => _call((c) async {
    await c.delete('/anthologies/$id/entries/$kind/$itemId');
  });

  @override
  Future<void> setNote(int id, String kind, int itemId, String note) =>
      _call((c) async {
        await c.putJson('/anthologies/$id/entries', {
          'kind': kind,
          'item_id': itemId,
          'note': note,
        });
      });

  @override
  Future<void> setEntryDisplay(
    int id,
    String kind,
    int itemId, {
    Map<String, bool?> fields = const {},
    Map<String, String?> edits = const {},
  }) => _call((c) async {
    await c.putJson('/anthologies/$id/entries/$kind/$itemId/display', {
      'fields': fields,
      'edits': edits,
    });
  });

  Map<String, Object?> _ref(({String kind, int itemId}) r) => {
    'kind': r.kind,
    'item_id': r.itemId,
  };

  @override
  Future<void> move(
    int id,
    String kind,
    int itemId, {
    ({String kind, int itemId})? after,
  }) => _call((c) async {
    await c.postJson('/anthologies/$id/order', {
      'kind': kind,
      'item_id': itemId,
      if (after != null) 'after': _ref(after),
    });
  });

  @override
  Future<AnthologySection> addSection(
    int id,
    String title,
    String prose, {
    ({String kind, int itemId})? after,
  }) => _call((c) async {
    final r = await c.postJson('/anthologies/$id/sections', {
      'title': title,
      'prose': prose,
      if (after != null) 'after': _ref(after),
    }, idempotencyKey: _key);
    return AnthologySection.fromJson(_map(r));
  });

  @override
  Future<void> editSection(int id, int sectionId, String title, String prose) =>
      _call((c) async {
        await c.putJson('/anthologies/$id/sections/$sectionId', {
          'title': title,
          'prose': prose,
        });
      });

  @override
  Future<void> deleteSection(int id, int sectionId) => _call((c) async {
    await c.delete('/anthologies/$id/sections/$sectionId');
  });

  @override
  Future<void> setGrouping(int id, String groupBy) => _call((c) async {
    await c.putJson('/anthologies/$id/grouping', {'group_by': groupBy});
  });

  @override
  Future<void> setFront(
    int id,
    String epigraph,
    String dedication, {
    String? description,
  }) => _call((c) async {
    await c.putJson('/anthologies/$id/front', {
      'epigraph': epigraph,
      'dedication': dedication,
      // an older server does not know it, and one that does keeps what it holds when it is not named
      'description': ?description,
    });
  });

  @override
  Future<String> setPoster(int id, Uint8List bytes, String fileName) =>
      _call((c) async {
        final r = await c.postFile(
          '/anthologies/$id/poster',
          'file',
          bytes,
          fileName,
        );
        final path = r is Map ? (r['poster_path'] ?? r['path']) : null;
        return path is String ? path : '';
      });

  @override
  Future<void> removePoster(int id) => _call((c) async {
    await c.delete('/anthologies/$id/poster');
  });

  @override
  Future<String> setCover(int id, Uint8List bytes, String fileName) =>
      _call((c) async {
        final r = await c.postFile(
          '/anthologies/$id/cover',
          'file',
          bytes,
          fileName,
        );
        final path = r is Map ? (r['cover_path'] ?? r['path']) : null;
        return path is String ? path : '';
      });

  @override
  Future<void> removeCover(int id) => _call((c) async {
    await c.delete('/anthologies/$id/cover');
  });

  @override
  Future<FillResult> fill(
    int id,
    String rule, {
    bool preview = false,
    bool auto = false,
  }) => _call((c) async {
    final r = _map(
      await c.postJson('/anthologies/$id/fill', {
        'rule': rule,
        'preview': preview,
        'auto': auto,
      }),
    );
    final items = r['items'];
    return FillResult(
      added: (r['added'] as num?)?.toInt() ?? 0,
      matched: (r['matched'] as num?)?.toInt() ?? 0,
      skipped: (r['skipped'] as num?)?.toInt() ?? 0,
      capped: r['capped'] == true,
      items: [
        if (items is List)
          for (final x in items) AnthologyEntry.fromJson(_map(x)),
      ],
    );
  });

  @override
  Future<FillVocabulary> vocabulary() => _call((c) async {
    return FillVocabulary.fromJson(_map(await c.getJson('/search/vocabulary')));
  });

  @override
  Future<List<RemovedPassage>> removed(int id) => _call((c) async {
    final r = _map(await c.getJson('/anthologies/$id/removed'));
    final l = r['removed'];
    return [
      if (l is List)
        for (final x in l) RemovedPassage.fromJson(_map(x)),
    ];
  });

  @override
  Future<void> restore(int id, String kind, int itemId) => _call((c) async {
    await c.postJson('/anthologies/$id/removed/$kind/$itemId', {});
  });

  @override
  Future<ExportedFile> export(int id, {bool epub = false}) => _call((c) async {
    final bytes = await c.getBytes(
      '/anthologies/$id/export${epub ? '.epub' : ''}',
    );
    final list = await c.getJson('/anthologies/$id');
    final title = list is Map && list['anthology'] is Map
        ? '${(list['anthology'] as Map)['title'] ?? 'anthology'}'
        : 'anthology';
    final safe = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return ExportedFile(
      '${safe.isEmpty ? 'anthology' : safe}.${epub ? 'epub' : 'md'}',
      bytes,
    );
  });
}
