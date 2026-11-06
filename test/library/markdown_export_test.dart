import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/markdown_export.dart';
import 'package:tippani/library/models.dart';

import '../support/memory_library.dart';

void main() {
  late MemoryLibrary lib;

  setUp(() => lib = MemoryLibrary());

  Future<String> md() async =>
      libraryMarkdown(await lib.works(), await lib.quotes());

  test('a book is frontmatter that says it is a book, then quotes under their chapters', () async {
    final w = await lib.addWork(
      const WorkDraft(
        title: 'Walden',
        creator: 'Henry David Thoreau',
        year: 1854,
      ),
    );
    await lib.addQuote(
      QuoteDraft(
        text: 'Simplify, simplify.',
        workId: w.id,
        note: 'Read twice.',
        tags: const ['simple', 'life'],
        favorite: true,
      ),
    );
    await lib.addQuote(
      QuoteDraft(
        text: 'The mass of men\nlead lives of quiet desperation.',
        workId: w.id,
        chapter: 'Economy',
        speaker: 'Thoreau',
        color: 'blue',
        location: 'p. 8',
      ),
    );
    expect(
      await md(),
      '---\n'
      'title: Walden\n'
      'author: Henry David Thoreau\n'
      'year: 1854\n'
      'type: book\n'
      '---\n'
      '\n'
      '> Simplify, simplify.\n'
      '- note: Read twice.\n'
      '- tags: life, simple\n'
      '- date: 2026-11-06\n'
      '- favorite: true\n'
      '\n'
      '## Economy\n'
      '\n'
      '> The mass of men\n'
      '> lead lives of quiet desperation.\n'
      '- character: Thoreau\n'
      '- color: blue\n'
      '- loc: p. 8\n'
      '- date: 2026-11-06\n',
    );
  });

  test(
    'chapterless quotes come first, whatever order they were saved in',
    () async {
      final w = await lib.addWork(const WorkDraft(title: 'B'));
      await lib.addQuote(
        QuoteDraft(text: 'in a chapter', workId: w.id, chapter: 'One'),
      );
      await lib.addQuote(QuoteDraft(text: 'no chapter', workId: w.id));
      final out = await md();
      expect(out.indexOf('no chapter'), lessThan(out.indexOf('## One')));
      expect(out.indexOf('## One'), lessThan(out.indexOf('in a chapter')));
    },
  );

  test('two quotes in one chapter share one heading', () async {
    final w = await lib.addWork(const WorkDraft(title: 'B'));
    for (final t in ['a', 'b']) {
      await lib.addQuote(QuoteDraft(text: t, workId: w.id, chapter: 'One'));
    }
    await lib.addQuote(QuoteDraft(text: 'c', workId: w.id, chapter: 'Two'));
    await lib.addQuote(QuoteDraft(text: 'd', workId: w.id, chapter: ' One '));
    expect('## One'.allMatches(await md()), hasLength(1));
  });

  test('a film says movie, names its director and has no headings; a show and a game say so', () async {
    final f = await lib.addWork(
      const WorkDraft(
        title: 'Casablanca',
        kind: WorkKind.film,
        creator: 'Michael Curtiz',
      ),
    );
    final s = await lib.addWork(
      const WorkDraft(title: 'Dark', kind: WorkKind.show),
    );
    final g = await lib.addWork(
      const WorkDraft(title: 'Hades', kind: WorkKind.game),
    );
    await lib.addQuote(
      QuoteDraft(
        text: 'Here is looking at you.',
        workId: f.id,
        speaker: 'Rick',
        location: '01:32:10',
        chapter: 'ignored',
      ),
    );
    await lib.addQuote(QuoteDraft(text: 'x', workId: s.id));
    await lib.addQuote(QuoteDraft(text: 'y', workId: g.id));
    final out = await md();
    expect(
      out,
      contains(
        '---\ntitle: Casablanca\ndirector: Michael Curtiz\ntype: movie\n---\n'
        '\n> Here is looking at you.\n- character: Rick\n- timestamp: 01:32:10\n',
      ),
    );
    expect(out, contains('title: Dark\ntype: show\n'));
    expect(out, contains('title: Hades\ntype: game\n'));
    expect(out, isNot(contains('## ')));
  });

  test('quotes with no work are one type: quotes block, with the occasion as the heading', () async {
    await lib.addQuote(const QuoteDraft(text: 'A stitch in time saves nine.'));
    await lib.addQuote(
      const QuoteDraft(
        text: 'We shall fight on the beaches.',
        speaker: 'Churchill',
        chapter: 'House of Commons',
        location: 'London',
        language: 'English',
      ),
    );
    expect(
      await md(),
      '---\n'
      'type: quotes\n'
      '---\n'
      '\n'
      '> A stitch in time saves nine.\n'
      '- date: 2026-11-06\n'
      '\n'
      '## House of Commons\n'
      '\n'
      '> We shall fight on the beaches.\n'
      '- speaker: Churchill\n'
      '- place: London\n'
      '- language: English\n'
      '- date: 2026-11-06\n',
    );
  });

  test(
    'every work is its own block, and the loose quotes are the last one',
    () async {
      final a = await lib.addWork(const WorkDraft(title: 'A'));
      final b = await lib.addWork(const WorkDraft(title: 'B'));
      await lib.addQuote(const QuoteDraft(text: 'loose'));
      await lib.addQuote(QuoteDraft(text: 'in b', workId: b.id));
      await lib.addQuote(QuoteDraft(text: 'in a', workId: a.id));
      final out = await md();
      final titleA = out.indexOf('title: A');
      final titleB = out.indexOf('title: B');
      final loose = out.indexOf('type: quotes');
      expect(titleA, greaterThanOrEqualTo(0));
      expect(titleA, lessThan(titleB));
      expect(titleB, lessThan(loose));
      // Three closing fences, and the opening fence of the two blocks after the first.
      expect('\n---\n'.allMatches(out), hasLength(5));
    },
  );

  test(
    'a work with no quotes is left out, and an empty library is an empty file',
    () async {
      await lib.addWork(const WorkDraft(title: 'Unread'));
      expect(await md(), '');
    },
  );

  test('a value is one line, yellow is not written, and the default is not a binding', () async {
    final w = await lib.addWork(const WorkDraft(title: 'T'));
    await lib.addQuote(
      QuoteDraft(
        text: 'q',
        workId: w.id,
        note: 'first line\n   second   line',
        color: 'yellow',
      ),
    );
    final out = await md();
    expect(out, contains('- note: first line second line\n'));
    expect(out, isNot(contains('color')));
    expect(out, isNot(contains('favorite')));
  });
}
