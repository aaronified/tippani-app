import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/imports/markdown_import.dart';
import 'package:tippani/library/markdown_export.dart';
import 'package:tippani/library/models.dart';

import '../support/memory_library.dart';

Future<MemoryLibrary> _library() async {
  final lib = MemoryLibrary();
  final book = await lib.addWork(
    const WorkDraft(
      title: 'Walden',
      creator: 'Henry David Thoreau',
      year: 1854,
      language: 'en',
    ),
  );
  final film = await lib.addWork(
    const WorkDraft(
      title: 'Casablanca',
      kind: WorkKind.film,
      creator: 'Michael Curtiz',
      year: 1942,
    ),
  );
  await lib.addQuote(
    QuoteDraft(
      text: 'Simplify, simplify.',
      workId: book.id,
      chapter: 'Economy',
      location: 'p. 8',
      note: 'my margin',
      color: 'blue',
      favorite: true,
      tags: const ['life', 'rules'],
      translation: 'saral karo',
      speaker: 'Thoreau',
    ),
  );
  await lib.addQuote(
    QuoteDraft(
      text: 'Here is looking at you, kid.',
      workId: film.id,
      speaker: 'Rick',
      location: '01:02:03',
    ),
  );
  await lib.addQuote(
    const QuoteDraft(text: 'A loose one.', speaker: 'Anon', location: 'Paris'),
  );
  return lib;
}

void main() {
  test('what the app exports comes back in as the same library', () async {
    final from = await _library();
    final md = libraryMarkdown(await from.works(), await from.quotes());

    final to = MemoryLibrary();
    final r = await importMarkdown(md, to);

    expect(r.works, 2);
    expect(r.quotes, 3);
    expect(r.duplicates, 0);
    final walden = (await to.works(kind: WorkKind.book)).single;
    expect(walden.title, 'Walden');
    expect(walden.creator, 'Henry David Thoreau');
    expect(walden.year, 1854);
    final q = (await to.quotes(workId: walden.id)).single;
    expect(q.text, 'Simplify, simplify.');
    expect(q.chapter, 'Economy');
    expect(q.location, 'p. 8');
    expect(q.note, 'my margin');
    expect(q.color, 'blue');
    expect(q.favorite, isTrue);
    expect(q.tags, containsAll(['life', 'rules']));
    expect(q.translation, 'saral karo');
    expect(q.speaker, 'Thoreau');
    final casa = (await to.works(kind: WorkKind.film)).single;
    final line = (await to.quotes(workId: casa.id)).single;
    expect(line.speaker, 'Rick');
    expect(line.location, '01:02:03');
    final loose = (await to.quotes()).where((x) => x.workId == null).single;
    expect(loose.text, 'A loose one.');
    expect(loose.speaker, 'Anon');
    expect(loose.location, 'Paris');
  });

  test('reading the same file twice adds nothing the second time', () async {
    final from = await _library();
    final md = libraryMarkdown(await from.works(), await from.quotes());
    final to = MemoryLibrary();
    await importMarkdown(md, to);

    final again = await importMarkdown(md, to);

    expect(again.works, 0);
    expect(again.quotes, 0);
    expect(again.duplicates, 3);
    expect((await to.works()).length, 2);
    expect((await to.quotes()).length, 3);
  });

  test('a quote joins the book already on the phone', () async {
    final to = MemoryLibrary();
    final walden = await to.addWork(
      const WorkDraft(title: 'walden', creator: 'Thoreau'),
    );
    final r = await importMarkdown(
      '---\ntitle: Walden\nauthor: Thoreau\ntype: book\n---\n\n> New words.\n',
      to,
    );
    expect(r.works, 0);
    expect(r.quotes, 1);
    expect((await to.quotes(workId: walden.id)).single.text, 'New words.');
  });

  test('a multi-line quote is one quote', () async {
    final to = MemoryLibrary();
    await importMarkdown(
      '---\ntitle: T\ntype: book\n---\n\n> first line\n> second line\n- note: n\n',
      to,
    );
    expect((await to.quotes()).single.text, 'first line second line');
  });

  test(
    'a file that is not Tippani Markdown is refused in plain words',
    () async {
      final to = MemoryLibrary();
      await expectLater(
        importMarkdown('just some words', to),
        throwsA(isA<MarkdownImportException>()),
      );
      await expectLater(
        importMarkdown('# A Readest title\n', to),
        throwsA(
          isA<MarkdownImportException>().having(
            (e) => e.message,
            'message',
            contains('Readest'),
          ),
        ),
      );
      await expectLater(
        importMarkdown('   \n', to),
        throwsA(isA<MarkdownImportException>()),
      );
      expect(await to.quotes(), isEmpty);
    },
  );

  test('an anthology block is left for the server and counted', () async {
    final to = MemoryLibrary();
    final r = await importMarkdown(
      '---\ntitle: A\ntype: anthology\n---\n> x\n',
      to,
    );
    expect(r.skippedBlocks, 1);
    expect(r.quotes, 0);
  });
}
