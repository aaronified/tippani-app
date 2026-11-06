import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/sync/fingerprint.dart';

Quote quote({
  String text = 'Words',
  String chapter = '',
  String note = '',
  String color = 'yellow',
  bool favorite = false,
  List<String> tags = const [],
}) => Quote(
  id: 1,
  workId: null,
  text: text,
  translation: '',
  language: '',
  speaker: '',
  chapter: chapter,
  location: '',
  note: note,
  color: color,
  favorite: favorite,
  notedAt: DateTime.utc(2026),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: tags,
);

void main() {
  String fp(Quote q, [Realm r = Realm.book]) => fingerprint(quoteFields(q, r));

  test('the same fields give the same fingerprint, a different field a different one', () {
    expect(fp(quote()), fp(quote()));
    expect(fp(quote()), isNot(fp(quote(text: 'Other'))));
    expect(fp(quote()), isNot(fp(quote(note: 'n'))));
    expect(fp(quote()), isNot(fp(quote(color: 'pink'))));
    expect(fp(quote()), isNot(fp(quote(favorite: true))));
  });

  test('spacing at the edges, the order and case of tags, and an unknown colour do not count as changes', () {
    expect(fp(quote(text: ' Words ')), fp(quote()));
    expect(fp(quote(tags: ['B', 'a'])), fp(quote(tags: ['a', 'b'])));
    expect(fp(quote(tags: ['a', 'A'])), fp(quote(tags: ['a'])));
    expect(fp(quote(color: 'chartreuse')), fp(quote()));
  });

  test('a film quote\'s chapter is not compared, a book quote\'s is', () {
    expect(
      fp(quote(chapter: 'Act 2'), Realm.screen),
      fp(quote(), Realm.screen),
    );
    expect(fp(quote(chapter: 'Act 2')), isNot(fp(quote())));
  });

  test(
    'a row from the server reads the same as the phone\'s quote it describes',
    () {
      final row = {
        'quote': 'Words',
        'translation': '',
        'language': '',
        'character': '',
        'chapter': '',
        'location': '',
        'note': 'n',
        'color': 'yellow',
        'favorite': false,
        'tags': ['T'],
      };
      expect(
        fingerprint(serverQuoteFields(row, Realm.book)),
        fp(quote(note: 'n', tags: ['t'])),
      );
    },
  );

  test('each realm reads its own column names', () {
    final book = serverQuoteFields({
      'quote': 'q',
      'character': 'C',
      'chapter': 'Ch',
      'location': 'L',
    }, Realm.book);
    expect(
      [book['speaker'], book['chapter'], book['location']],
      ['C', 'Ch', 'L'],
    );
    final film = serverQuoteFields({
      'quote': 'q',
      'character': 'C',
      'chapter': 'ignored',
      'timestamp': 'T',
    }, Realm.screen);
    expect(
      [film['speaker'], film['chapter'], film['location']],
      ['C', '', 'T'],
    );
    final loose = serverQuoteFields({
      'quote': 'q',
      'speaker': 'S',
      'occasion': 'O',
      'place': 'P',
    }, Realm.loose);
    expect(
      [loose['speaker'], loose['chapter'], loose['location']],
      ['S', 'O', 'P'],
    );
  });

  test('a work: no year and year 0 are the same; a book and an "other" are the same; a film is not a show', () {
    Work w(WorkKind k, {int? year}) => Work(
      id: 1,
      kind: k,
      title: 'T',
      creator: 'C',
      year: year,
      language: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    String f(Work x) => fingerprint(workFields(x));
    expect(f(w(WorkKind.book)), f(w(WorkKind.book, year: 0)));
    expect(f(w(WorkKind.book)), f(w(WorkKind.other)));
    expect(f(w(WorkKind.film)), isNot(f(w(WorkKind.show))));
    expect(f(w(WorkKind.book)), isNot(f(w(WorkKind.film))));
    expect(
      fingerprint(
        serverWorkFields({
          'title': 'T',
          'author': 'C',
          'published_year': 0,
        }, Realm.book),
      ),
      f(w(WorkKind.book)),
    );
    expect(
      fingerprint(
        serverWorkFields({
          'title': 'T',
          'director': 'C',
          'media_type': 'movie',
        }, Realm.screen),
      ),
      f(w(WorkKind.film)),
    );
  });

  test(
    'the realm of a quote follows its work, and each realm has its own route',
    () {
      expect(realmOfKind(WorkKind.game), Realm.screen);
      expect(realmOfKind(WorkKind.other), Realm.book);
      expect(realmOfQuote(null), Realm.loose);
      expect(quoteRoute(Realm.loose), '/quotes');
      expect(workRoute(Realm.screen), '/movies');
    },
  );
}
