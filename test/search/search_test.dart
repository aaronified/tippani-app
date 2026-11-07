import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/search_screen.dart';
import 'package:tippani/search/search_models.dart';
import 'package:tippani/search/search_service.dart';

import '../support/memory_library.dart';

/// What the real server answers for a search (trimmed to the parts the page reads).
const _serverAnswer = <String, Object?>{
  'books': [
    {
      'id': 3,
      'title': 'The Dispossessed',
      'author': 'Ursula Le Guin',
      'cover_path': '0123456789abcdef.jpg',
      'published_year': 1974,
      'genres': ['Science fiction'],
    },
  ],
  'movies': [
    {
      'id': 7,
      'title': 'Casablanca',
      'director': 'Michael Curtiz',
      'release_year': 1942,
      'poster_path': '',
      'media_type': 'movie',
    },
  ],
  'annotations': [
    {
      'id': 11,
      'book_id': 3,
      'book_title': 'The Dispossessed',
      'quote': 'There is nothing so wholly anarchic as the unknown.',
      'color': 'blue',
      'character': 'Shevek',
      'book_author': 'Ursula Le Guin',
    },
  ],
  'dialogues': [
    {
      'id': 21,
      'movie_id': 7,
      'movie_title': 'Casablanca',
      'quote': 'Here is looking at you, kid.',
      'character': 'Rick',
      'actor': 'Humphrey Bogart',
      'timestamp': '01:32:00',
    },
  ],
  'quotes': [
    {
      'id': 5,
      'quote': 'We must cultivate our garden.',
      'speaker': 'Voltaire',
      'occasion': 'Candide',
    },
  ],
  'authors': [
    {
      'name': 'Ursula Le Guin',
      'books': [
        {'id': 3, 'title': 'The Dispossessed', 'author': 'Ursula Le Guin'},
      ],
    },
  ],
  'actors': [
    {
      'name': 'Humphrey Bogart',
      'dialogues': [
        {'id': 21, 'quote': 'Here is looking at you, kid.'},
      ],
    },
  ],
  'tags': [
    {
      'name': 'garden',
      'count': 2,
      'annotations': [
        {'id': 11, 'quote': 'x'},
      ],
    },
  ],
  'genres': [
    {
      'name': 'Science fiction',
      'books': [
        {'id': 3, 'title': 'The Dispossessed'},
      ],
    },
  ],
  'notes': {
    'annotations': [
      {'id': 12, 'quote': 'q', 'note': 'my thoughts on anarchy'},
    ],
  },
  'corrected': 'anarchic',
};

void main() {
  group('reading the server answer', () {
    test('every section of the web page is filled', () {
      final r = parseServerSearch(_serverAnswer);
      expect(r.fromServer, isTrue);
      expect(r.corrected, 'anarchic');
      expect(r.works.map((w) => w.title), ['The Dispossessed', 'Casablanca']);
      expect(r.works[0].serverId, 3);
      expect(r.works[0].cover, '0123456789abcdef.jpg');
      expect(r.works[1].screen, isTrue);
      expect(r.people.map((p) => '${p.role}:${p.name}'), [
        'author:Ursula Le Guin',
        'actor:Humphrey Bogart',
      ]);
      expect(r.tags.single.count, 2);
      expect(r.genres.single.works.single.title, 'The Dispossessed');
      expect(r.notes.single.note, 'my thoughts on anarchy');
      expect(r.quotes.map((q) => q.kind), [
        QuoteHitKind.highlight,
        QuoteHitKind.line,
        QuoteHitKind.standalone,
      ]);
      // a film line is credited to the actor, a highlight to the author
      expect(r.quotes[1].credit, 'Humphrey Bogart');
      expect(r.quotes[0].credit, 'Ursula Le Guin');
      expect(r.quotes[0].speaker, 'Shevek');
    });

    test('a bare answer is empty rather than an error', () {
      expect(parseServerSearch(const {}).isEmpty, isTrue);
    });
  });

  group('typing filters', () {
    test('field:value parts are taken out of the words', () {
      final q = parseQuery('anarchy tag:garden author:"Le Guin" colour:blue');
      expect(q.words, 'anarchy');
      expect(q.facets.map((f) => f.label), [
        'Tag: garden',
        'Author: Le Guin',
        'Colour: blue',
      ]);
    });

    test('color is colour, and an unknown field stays in the words', () {
      final q = parseQuery('color:pink time:12');
      expect(q.facets.single.field, 'colour');
      expect(q.words, 'time:12');
    });

    test('suggestions start with what begins with the text', () {
      const v = SearchVocabulary({
        'author': ['Ursula Le Guin', 'Gu Ling'],
        'tag': ['guinea', 'language'],
      });
      final s = v.suggest('gu');
      expect(s.map((f) => f.value).first, anyOf('Gu Ling', 'guinea'));
      expect(s.map((f) => f.value), containsAll(['Gu Ling', 'guinea']));
      expect(v.suggest('g'), isEmpty, reason: 'one letter suggests nothing');
    });
  });

  test('matched words are marked, whatever the case', () {
    final span = marked(
      'The Unknown is wholly anarchic',
      const ['unknown', 'anarch'],
      const TextStyle(),
      Colors.yellow,
    );
    final marks = [
      for (final c in span.children!.cast<TextSpan>())
        if (c.style?.backgroundColor == Colors.yellow) c.text,
    ];
    expect(marks, ['Unknown', 'anarch']);
  });

  group('searching the phone', () {
    late MemoryLibrary lib;
    late LocalSearch search;

    setUp(() async {
      lib = MemoryLibrary();
      search = LocalSearch(lib);
      final book = await lib.addWork(
        const WorkDraft(title: 'Walden', creator: 'Henry David Thoreau'),
      );
      final film = await lib.addWork(
        const WorkDraft(
          title: 'Casablanca',
          kind: WorkKind.film,
          creator: 'Michael Curtiz',
        ),
      );
      await lib.addQuote(
        QuoteDraft(
          text: 'Simplify, simplify.',
          workId: book.id,
          tags: const ['life'],
          color: 'blue',
        ),
      );
      await lib.addQuote(
        QuoteDraft(
          text: 'Of all the gin joints',
          workId: film.id,
          speaker: 'Rick',
          note: 'my favourite simplify moment',
        ),
      );
      await lib.addQuote(const QuoteDraft(text: 'A proverb, simplify it.'));
    });

    test(
      'words find titles, quotes, notes and the people and tags named',
      () async {
        final r = await search.search('simplify');
        expect(r.fromServer, isFalse);
        expect(r.quotes.map((q) => q.text), contains('Simplify, simplify.'));
        expect(r.notes.single.workTitle, 'Casablanca');
        final byName = await search.search('thoreau');
        expect(byName.people.single.name, 'Henry David Thoreau');
        expect(byName.people.single.works.single.title, 'Walden');
        final byTag = await search.search('lif');
        expect(byTag.tags.single.name, 'life');
        expect(byTag.tags.single.count, 1);
      },
    );

    test('scopes and filters narrow what is found', () async {
      final films = await search.search('', scope: SearchScope.movies);
      expect(films.works.single.title, 'Casablanca');
      expect(films.quotes, isEmpty);
      final blue = await search.search(
        '',
        facets: const [SearchFacet('colour', 'blue')],
      );
      expect(blue.quotes.single.text, 'Simplify, simplify.');
      final tagged = await search.search(
        'simplify',
        facets: const [SearchFacet('tag', 'LIFE')],
      );
      expect(tagged.quotes.single.text, 'Simplify, simplify.');
      final byAuthor = await search.search(
        '',
        facets: const [SearchFacet('author', 'Henry David Thoreau')],
      );
      expect(byAuthor.works.single.title, 'Walden');
      expect(byAuthor.quotes.single.workTitle, 'Walden');
      final boardOnly = await search.search('', scope: SearchScope.quotes);
      expect(boardOnly.quotes.single.kind, QuoteHitKind.standalone);
    });

    test('the vocabulary comes from what is on the phone', () async {
      final v = await search.vocabulary();
      expect(v.of('author'), ['Henry David Thoreau']);
      expect(v.of('director'), ['Michael Curtiz']);
      expect(v.of('tag'), ['life']);
      expect(v.of('speaker'), ['Rick']);
      expect(v.of('colour'), hasLength(6));
    });
  });
}
