import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../app_controller.dart';
import '../settings/settings_store.dart';
import '../l10n/l10n.dart';

/// The character the server leaves where the words of a fill-in-the-blank were.
const String clozeBlank = '￼';

/// One face the server draws on a quiz card: a character (or a person) with the picture file stored for them, and
/// the actor who plays them with the actor's picture.
class QuizFace {
  const QuizFace({
    required this.name,
    this.path = '',
    this.actor = '',
    this.actorImage = '',
  });

  final String name;
  final String path;
  final String actor;
  final String actorImage;

  factory QuizFace.fromJson(Map<Object?, Object?> j) => QuizFace(
    name: '${j['name'] ?? ''}',
    path: '${j['path'] ?? ''}',
    actor: '${j['actor'] ?? ''}',
    actorImage: '${j['actor_image'] ?? ''}',
  );

  /// The picture to draw: the character's own, else the actor's.
  String get image => path.isNotEmpty ? path : actorImage;
}

List<QuizFace> _faces(Object? v) => v is List
    ? [
        for (final f in v)
          if (f is Map) QuizFace.fromJson(f),
      ]
    : const [];

/// What one multiple-choice option is, beyond the words on it. Only drawn after the card is graded.
class QuizOption {
  const QuizOption({
    this.person = '',
    this.kind = '',
    this.art = '',
    this.source = '',
    this.itemKind = '',
    this.itemId = 0,
    this.creator = '',
    this.year = 0,
    this.who = const [],
    this.speaker = '',
    this.date = '',
  });

  final String person;
  final String kind;
  final String art;
  final String source;
  final String itemKind;
  final int itemId;
  final String creator;
  final int year;
  final List<QuizFace> who;
  final String speaker;
  final String date;

  factory QuizOption.fromJson(Map<Object?, Object?> j) => QuizOption(
    person: '${j['person'] ?? ''}',
    kind: '${j['kind'] ?? ''}',
    art: '${j['art'] ?? ''}',
    source: '${j['source'] ?? ''}',
    itemKind: '${j['item_kind'] ?? ''}',
    itemId: (j['item_id'] as num?)?.toInt() ?? 0,
    creator: '${j['creator'] ?? ''}',
    year: (j['year'] as num?)?.toInt() ?? 0,
    who: _faces(j['who']),
    speaker: '${j['speaker'] ?? ''}',
    date: '${j['date'] ?? ''}',
  );
}

/// One question, as the server sets it. [direction] says what is asked: `source` (which work), `quote` (which
/// quote), `speaker` / `author` (who), `cloze` (type the missing words), `cloze-mcq` (pick the missing words) and
/// `flip` (look, then mark yourself).
class QuizCard {
  const QuizCard({
    required this.kind,
    required this.id,
    required this.direction,
    required this.quote,
    this.note = '',
    this.color = '',
    this.language = '',
    this.title = '',
    this.author = '',
    this.director = '',
    this.year = 0,
    this.art = '',
    this.character = '',
    this.actor = '',
    this.speaker = '',
    this.occasionDate = '',
    this.chapter = '',
    this.location = '',
    this.timestamp = '',
    this.mediaType = '',
    this.status = '',
    this.lapseCount = 0,
    this.leech = false,
    this.options = const [],
    this.answer = -1,
    this.meta = const [],
    this.easyChips = const [],
    this.easyPeople = const [],
    this.who = const [],
  });

  final String kind;
  final int id;
  final String direction;
  final String quote;
  final String note;
  final String color;
  final String language;
  final String title;
  final String author;
  final String director;
  final int year;
  final String art;
  final String character;
  final String actor;
  final String speaker;
  final String occasionDate;
  final String chapter;
  final String location;
  final String timestamp;
  final String mediaType;
  final String status;
  final int lapseCount;
  final bool leech;
  final List<String> options;
  final int answer;
  final List<QuizOption> meta;
  final List<QuizFace> easyChips;
  final List<String> easyPeople;
  final List<QuizFace> who;

  factory QuizCard.fromJson(Map<Object?, Object?> j) => QuizCard(
    kind: '${j['kind'] ?? ''}',
    id: (j['id'] as num?)?.toInt() ?? 0,
    direction: '${j['direction'] ?? ''}',
    quote: '${j['quote'] ?? ''}',
    note: '${j['note'] ?? ''}',
    color: '${j['color'] ?? ''}',
    language: '${j['language'] ?? ''}',
    title: '${j['title'] ?? ''}',
    author: '${j['author'] ?? ''}',
    director: '${j['director'] ?? ''}',
    year: (j['year'] as num?)?.toInt() ?? 0,
    art: '${j['art'] ?? ''}',
    character: '${j['character'] ?? ''}',
    actor: '${j['actor'] ?? ''}',
    speaker: '${j['speaker'] ?? ''}',
    occasionDate: '${j['occasion_date'] ?? ''}',
    chapter: '${j['chapter'] ?? ''}',
    location: '${j['location'] ?? ''}',
    timestamp: '${j['timestamp'] ?? ''}',
    mediaType: '${j['media_type'] ?? ''}',
    status: '${j['status'] ?? ''}',
    lapseCount: (j['lapse_count'] as num?)?.toInt() ?? 0,
    leech: j['leech'] == true,
    options: j['options'] is List
        ? [for (final o in j['options'] as List) '$o']
        : const [],
    answer: (j['answer'] as num?)?.toInt() ?? -1,
    meta: j['option_meta'] is List
        ? [
            for (final o in j['option_meta'] as List)
              o is Map ? QuizOption.fromJson(o) : const QuizOption(),
          ]
        : const [],
    easyChips: _faces(j['easy_chips']),
    easyPeople: j['easy_people'] is List
        ? [for (final p in j['easy_people'] as List) '$p']
        : const [],
    who: _faces(j['who']),
  );

  /// The words the card shows as its quote (a note-only quote shows its note).
  String get shown => quote.trim().isEmpty ? note : quote;

  bool get hasBlank => shown.contains(clozeBlank);

  bool get isCloze => direction == 'cloze';
  bool get isFlip => direction == 'flip';
  bool get isChoice => options.isNotEmpty && !isCloze && !isFlip;

  /// What the source of this card is called: a book, a film, a show, an occasion.
  String get noun => switch (mediaType) {
    'movie' => 'film',
    'show' => 'show',
    'game' => 'game',
    _ => kind == 'utterance' ? 'occasion' : 'book',
  };

  /// The line under the question: who made the work, and when.
  String get creditLine => [
    if (author.isNotEmpty) author else if (director.isNotEmpty) director,
    if (year != 0) '$year',
  ].join(' · ');
}

/// How many quotes are in each state of being remembered.
class QuizStates {
  const QuizStates({
    this.unseen = 0,
    this.remembered = 0,
    this.forgetting = 0,
    this.probablyForgotten = 0,
    this.total = 0,
  });

  final int unseen, remembered, forgetting, probablyForgotten, total;

  factory QuizStates.fromJson(Object? v) {
    if (v is! Map) return const QuizStates();
    int n(String k) => (v[k] as num?)?.toInt() ?? 0;
    return QuizStates(
      unseen: n('unseen'),
      remembered: n('remembered'),
      forgetting: n('forgetting'),
      probablyForgotten: n('probably_forgotten'),
      total: n('total'),
    );
  }
}

/// Today's deck.
class QuizDeck {
  const QuizDeck({
    required this.items,
    this.answeredToday = 0,
    this.gotToday = 0,
    this.forgotToday = 0,
    this.quota = 0,
    this.streak = 0,
    this.states = const QuizStates(),
    this.capacity = 0,
  });

  final List<QuizCard> items;
  final int answeredToday, gotToday, forgotToday, quota, streak, capacity;
  final QuizStates states;

  factory QuizDeck.fromJson(Map<Object?, Object?> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return QuizDeck(
      items: [
        if (j['items'] is List)
          for (final c in j['items'] as List)
            if (c is Map) QuizCard.fromJson(c),
      ],
      answeredToday: n('answered_today'),
      gotToday: n('got_today'),
      forgotToday: n('forgot_today'),
      quota: n('quota'),
      streak: n('streak'),
      states: QuizStates.fromJson(j['states']),
      capacity: n('capacity'),
    );
  }

  /// Cards still to answer today.
  int get remaining => math.max(0, items.length);
}

/// The two scores.
class QuizScores {
  const QuizScores({
    this.dailyAnswered = 0,
    this.dailyGot = 0,
    this.streak = 0,
    this.days = 0,
    this.remaining = 0,
    this.quota = 0,
    this.practiceAnswered = 0,
    this.practiceGot = 0,
    this.practiceSessions = 0,
    this.states = const QuizStates(),
    this.capacity = 0,
  });

  final int dailyAnswered, dailyGot, streak, days, remaining, quota;
  final int practiceAnswered, practiceGot, practiceSessions, capacity;
  final QuizStates states;

  factory QuizScores.fromJson(Map<Object?, Object?> j) {
    final d = j['daily'] is Map ? j['daily'] as Map : const {};
    final p = j['practice'] is Map ? j['practice'] as Map : const {};
    int n(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
    return QuizScores(
      dailyAnswered: n(d, 'answered'),
      dailyGot: n(d, 'got'),
      streak: n(d, 'streak'),
      days: n(d, 'days'),
      remaining: n(d, 'remaining'),
      quota: n(d, 'quota'),
      practiceAnswered: n(p, 'answered'),
      practiceGot: n(p, 'got'),
      practiceSessions: n(p, 'sessions'),
      states: QuizStates.fromJson(j['states']),
      capacity: n(j, 'capacity'),
    );
  }
}

/// One answer to send: which card, how it went, and in which deck. For a typed blank, [attempt] is the words typed
/// (the server grades it and ignores [result]).
class QuizAnswer {
  const QuizAnswer({
    required this.kind,
    required this.id,
    required this.result,
    required this.mode,
    this.attempt,
  });

  final String kind;
  final int id;

  /// `got`, `forgot` or (practice only) `skip`.
  final String result;

  /// `daily` or `practice`.
  final String mode;
  final String? attempt;
}

/// What the server said about an answer it took.
class AnswerOutcome {
  const AnswerOutcome({
    required this.result,
    this.answer = '',
    this.synonym = false,
    this.leech = false,
    this.lapses = 0,
    this.remaining,
    this.answered = 0,
    this.got = 0,
    this.forgot = 0,
  });

  /// The grade recorded (for a typed blank, the server's own).
  final String result;

  /// For a typed blank, the words that were missing.
  final String answer;
  final bool synonym;
  final bool leech;
  final int lapses;

  /// Cards left in today's deck (daily only).
  final int? remaining;
  final int answered, got, forgot;

  bool get correct => result == 'got';

  factory AnswerOutcome.fromJson(Map<Object?, Object?> j) => AnswerOutcome(
    result: '${j['result'] ?? ''}',
    answer: '${j['answer'] ?? ''}',
    synonym: j['synonym'] == true,
    leech: j['leech'] == true,
    lapses: (j['lapse_count'] as num?)?.toInt() ?? 0,
    remaining: (j['remaining'] as num?)?.toInt(),
    answered: (j['answered'] as num?)?.toInt() ?? 0,
    got: (j['got'] as num?)?.toInt() ?? 0,
    forgot: (j['forgot'] as num?)?.toInt() ?? 0,
  );
}

/// Anything that went wrong with the quiz, in words for the reader.
class QuizException implements Exception {
  const QuizException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the screens need of the quiz. An interface so a test can stand in for the server.
abstract class QuizService implements Listenable {
  /// Whether there is a paired server to ask.
  bool get available;

  /// Answers made and not yet taken by the server.
  int get waiting;

  Future<QuizDeck> daily();

  /// The Practice round, over the whole library or (with [anthology], an anthology's server id) only the
  /// passages of that anthology.
  Future<List<QuizCard>> practice({int? anthology});
  Future<QuizScores> scores();

  /// Keeps [a] (so it survives the phone being offline or closed) and sends it. Returns what the server said, or
  /// null when it could not be sent yet and waits on the phone.
  Future<AnswerOutcome?> answer(QuizAnswer a);

  /// Tells the server the quote was seen (the three other quotes a graded card showed). Best effort.
  Future<void> seen(String kind, int id);

  /// Clears the Practice score.
  Future<void> resetPractice();

  /// Sends whatever is waiting.
  Future<void> drain();
}

/// How one send went.
enum SendResult { sent, refused, later }

/// The answers made and not yet taken by the server, kept in the phone's preferences until they are. They go in the
/// order given, each with an id of its own (so a repeat is recognised as an echo) and how long ago it was made (so
/// it counts for the day it was given).
class AnswerQueue extends ChangeNotifier {
  AnswerQueue({
    required this.read,
    required this.write,
    required this.send,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String? Function() read;
  final Future<void> Function(String) write;

  /// Sends one entry's body. Returns what became of it and, if taken, the server's answer.
  final Future<(SendResult, Map<Object?, Object?>?)> Function(
    Map<String, Object?> body,
  )
  send;
  final DateTime Function() _clock;

  bool _draining = false;
  final _firsts = <String, Completer<Map<Object?, Object?>?>>{};

  /// The longest an answer is kept (the server refuses older).
  static const keptFor = Duration(days: 30);

  List<Map<String, Object?>> _entries() {
    final raw = read();
    if (raw == null || raw.isEmpty) return [];
    try {
      final j = jsonDecode(raw);
      if (j is! List) return [];
      return [
        for (final e in j)
          if (e is Map) Map<String, Object?>.from(e),
      ];
    } on Object {
      return [];
    }
  }

  Future<void> _save(List<Map<String, Object?>> list) async {
    await write(list.isEmpty ? '' : jsonEncode(list));
    notifyListeners();
  }

  int get length => _entries().length;

  static int _counter = 0;

  /// Keeps [a], tries to send the queue once, and gives what the server said about [a] (null: it waits).
  Future<Map<Object?, Object?>?> keep(
    QuizAnswer a, {
    required int offset,
  }) async {
    final key =
        'a${_clock().microsecondsSinceEpoch.toRadixString(36)}${(_counter++).toRadixString(36)}';
    final list = _entries()
      ..add({
        'key': key,
        't': _clock().millisecondsSinceEpoch,
        'kind': a.kind,
        'id': a.id,
        'result': a.result,
        'mode': a.mode,
        'offset': offset,
        if (a.attempt != null) 'attempt': a.attempt,
      });
    await _save(list);
    final first = Completer<Map<Object?, Object?>?>();
    _firsts[key] = first;
    unawaited(drain());
    return first.future;
  }

  /// Sends the entries in order until one cannot go.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      for (;;) {
        final list = _entries();
        if (list.isEmpty) break;
        final head = list.first;
        final age =
            _clock().millisecondsSinceEpoch -
            ((head['t'] as num?)?.toInt() ?? 0);
        final body = {
          'kind': head['kind'],
          'id': head['id'],
          'result': head['result'],
          'mode': head['mode'],
          'offset': head['offset'],
          'client_id': head['key'],
          'answered_ago_ms': age < 0 ? 0 : age,
          if (head['attempt'] != null) 'attempt': head['attempt'],
        };
        final (result, data) = await send(body);
        final key = '${head['key']}';
        switch (result) {
          case SendResult.sent:
            await _save(list.sublist(1));
            _firsts.remove(key)?.complete(data ?? const {});
          case SendResult.refused:
            await _save(list.sublist(1));
            _firsts.remove(key)?.complete(null);
          case SendResult.later:
            for (final c in _firsts.values) {
              if (!c.isCompleted) c.complete(null);
            }
            _firsts.clear();
            return;
        }
      }
    } finally {
      _draining = false;
    }
  }
}

/// The paired server's quiz.
class ServerQuiz extends ChangeNotifier implements QuizService {
  ServerQuiz(this._controller, this._settings, {DateTime Function()? clock}) {
    queue = AnswerQueue(
      read: () => _settings.quizAnswers,
      write: _settings.setQuizAnswers,
      send: _send,
      clock: clock,
    )..addListener(notifyListeners);
  }

  final AppController _controller;
  final SettingsStore _settings;
  late final AnswerQueue queue;

  @override
  bool get available => _controller.paired;

  @override
  int get waiting => queue.length;

  int get _offset => DateTime.now().timeZoneOffset.inMinutes;

  Future<(SendResult, Map<Object?, Object?>?)> _send(
    Map<String, Object?> body,
  ) async {
    if (!available) return (SendResult.later, null);
    try {
      final r = await _controller.withClient(
        (c) => c.postJson('/review/answer', body),
      );
      return (SendResult.sent, r is Map ? Map<Object?, Object?>.from(r) : null);
    } on ApiException catch (e) {
      final s = e.status;
      final forGood =
          s != null &&
          s >= 400 &&
          s < 500 &&
          s != 401 &&
          s != 403 &&
          s != 408 &&
          s != 429;
      return (forGood ? SendResult.refused : SendResult.later, null);
    }
  }

  Future<T> _call<T>(Future<T> Function(ApiClient c) run) async {
    if (!available) {
      throw const QuizException('This phone is not paired with a server.');
    }
    try {
      return await _controller.withClient(run) as T;
    } on ApiException catch (e) {
      throw QuizException(switch (e.failure) {
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
          e.detail.isNotEmpty ? e.detail : 'The server could not do that.',
      });
    }
  }

  Map<Object?, Object?> _map(Object? v) => v is Map
      ? Map<Object?, Object?>.from(v)
      : throw const QuizException('The server sent something unexpected.');

  @override
  Future<QuizDeck> daily() => _call(
    (c) async => QuizDeck.fromJson(
      _map(await c.getJson('/review/daily?offset=$_offset')),
    ),
  );

  @override
  Future<List<QuizCard>> practice({int? anthology}) => _call((c) async {
    final j = _map(
      await c.getJson(
        '/review/practice?offset=$_offset'
        '${anthology == null ? '' : '&anthology=$anthology'}',
      ),
    );
    return [
      if (j['items'] is List)
        for (final x in j['items'] as List)
          if (x is Map) QuizCard.fromJson(x),
    ];
  });

  @override
  Future<QuizScores> scores() => _call(
    (c) async => QuizScores.fromJson(
      _map(await c.getJson('/review/scores?offset=$_offset')),
    ),
  );

  @override
  Future<AnswerOutcome?> answer(QuizAnswer a) async {
    final got = await queue.keep(a, offset: _offset);
    return got == null ? null : AnswerOutcome.fromJson(got);
  }

  @override
  Future<void> seen(String kind, int id) async {
    try {
      await _controller.withClient(
        (c) => c.postJson('/review/seen', {'kind': kind, 'id': id}),
      );
    } on Object {
      // reading an option is only a nudge to the schedule; losing one costs nothing
    }
  }

  @override
  Future<void> resetPractice() => _call((c) => c.delete('/review/practice'));

  @override
  Future<void> drain() => queue.drain();
}
