import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/imports/markdown_import.dart';
import 'package:tippani/imports/quote_markdown.dart';

import '../support/memory_library.dart';

/// Where the function IS the observable unit: the file a bookmark becomes. The format is the server's, so the test
/// reads the file back the way the importer does (the app's own reader of the same format) and checks the exact text.
void main() {
  test(
    'a bookmark becomes frontmatter, a chapter, the words and their bindings',
    () {
      final md = bookQuoteMarkdown(
        title: 'Dust of Dreams',
        author: 'Steven Erikson',
        language: 'en',
        isbn: '9780765316530',
        chapter: 'Chapter 14',
        text: 'The horses had stopped, and Tavore said nothing.',
        location: '3:42:10',
        note: 'From an audiobook bookmark',
        tags: ['bookmark', 'audiobook'],
        notedAt: DateTime.utc(2026, 11, 27, 23, 59),
      );
      expect(md, '''---
type: book
title: Dust of Dreams
author: Steven Erikson
language: en
isbn: 9780765316530
---

## Chapter 14

> The horses had stopped, and Tavore said nothing.
- location: 3:42:10
- date: 2026-11-27
- note: From an audiobook bookmark
- tags: bookmark, audiobook
''');
    },
  );

  test('what is left out is left out, and the words are one line', () {
    final md = bookQuoteMarkdown(
      title: 'Walden',
      text: '  Simplify,\n\n  simplify.\r\n  ',
    );
    expect(
      md,
      '---\ntype: book\ntitle: Walden\n---\n\n> Simplify, simplify.\n',
    );
  });

  test(
    'a value with a colon, a quote mark or a line break cannot break the file',
    () {
      final md = bookQuoteMarkdown(
        title: 'Dune: Messiah\n---\ntitle: Other',
        author: 'Frank\nHerbert',
        text: 'a: b',
        note: 'one\ntwo',
        tags: ['a,b', ' ', 'c'],
      );
      expect(md, contains('title: Dune: Messiah --- title: Other\n'));
      expect(md, contains('author: Frank Herbert\n'));
      expect(md, contains('- note: one two\n'));
      expect(md, contains('- tags: a b, c\n'));
      expect('---'.allMatches(md.split('\n').join('\n')).length >= 2, isTrue);
      // the frontmatter closes exactly once, where the builder closed it
      expect(md.split('\n').where((l) => l == '---').length, 2);
    },
  );

  test('a book without a title and a quote without words are refused', () {
    expect(() => bookQuoteMarkdown(title: ' ', text: 'x'), throwsArgumentError);
    expect(
      () => bookQuoteMarkdown(title: 'x', text: ' \n '),
      throwsArgumentError,
    );
  });

  test('the file reads back as the same work and the same quote', () async {
    final md = bookQuoteMarkdown(
      title: 'Dust of Dreams',
      author: 'Steven Erikson',
      language: 'en',
      chapter: 'Chapter 14',
      text: 'The horses had stopped, and Tavore said nothing.',
      location: '3:42:10',
      note: 'From an audiobook bookmark',
      tags: ['bookmark'],
      notedAt: DateTime.utc(2026, 11, 27),
    );
    final lib = MemoryLibrary();
    final r = await importMarkdown(md, lib);
    expect((r.works, r.quotes), (1, 1));

    final work = (await lib.works()).single;
    expect(work.title, 'Dust of Dreams');
    expect(work.creator, 'Steven Erikson');
    expect(work.language, 'en');
    final q = (await lib.quotes(workId: work.id)).single;
    expect(q.text, 'The horses had stopped, and Tavore said nothing.');
    expect(q.chapter, 'Chapter 14');
    expect(q.location, '3:42:10');
    expect(q.note, 'From an audiobook bookmark');
    expect(q.tags, ['bookmark']);
    expect(q.notedAt.toUtc().year, 2026);
    expect(q.notedAt.toUtc().month, 11);
    expect(q.notedAt.toUtc().day, 27);
  });

  test('a bookmark has one file name, the same each time', () {
    expect(bookmarkFileName('3f9a'), 'bookmark-3f9a.md');
    expect(bookmarkFileName('3f9a'), bookmarkFileName('3f9a'));
    expect(bookmarkFileName('3f9a'), isNot(bookmarkFileName('b210')));
  });
}
