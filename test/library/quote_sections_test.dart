import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/library/work_order.dart';

int _n = 0;

Quote _q(
  String text, {
  String chapter = '',
  String location = '',
  String color = 'yellow',
  String speaker = '',
  List<String> tags = const [],
  DateTime? noted,
}) => Quote(
  id: ++_n,
  workId: 1,
  text: text,
  translation: '',
  language: '',
  speaker: speaker,
  chapter: chapter,
  location: location,
  note: '',
  color: color,
  favorite: false,
  notedAt: noted ?? DateTime.utc(2026, 1, 1),
  source: 'manual',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  tags: tags,
);

List<String> _texts(List<Quote> qs) => [for (final q in qs) q.text];
List<String> _keys(List<QuoteSection> s) => [for (final x in s) x.key];

void main() {
  final a = _q(
    'a',
    chapter: 'Ch 2',
    color: 'blue',
    speaker: 'Rick, Ilsa',
    tags: ['love', 'war'],
    noted: DateTime.utc(2026, 3, 5),
  );
  final b = _q(
    'b',
    chapter: 'Ch 10',
    color: 'pink',
    speaker: 'Rick',
    tags: ['war'],
    noted: DateTime.utc(2026, 1, 9),
  );
  final c = _q('c', color: 'blue', noted: DateTime.utc(2026, 3, 20));
  final d = _q(
    'd',
    chapter: 'Ch 2',
    color: 'yellow',
    speaker: 'Ilsa',
    noted: DateTime.utc(2025, 12, 31),
  );
  final all = [a, b, c, d];

  group('order', () {
    test('reading order counts "Ch 2" before "Ch 10", chapter-less last', () {
      // within a chapter, the one met first comes first
      expect(_texts(orderQuotes(all, QuoteOrder.reading)), [
        'd',
        'a',
        'b',
        'c',
      ]);
    });

    test('newest and oldest by the day noted', () {
      expect(_texts(orderQuotes(all, QuoteOrder.newest)), ['c', 'a', 'b', 'd']);
      expect(_texts(orderQuotes(all, QuoteOrder.oldest)), ['d', 'b', 'a', 'c']);
    });

    test('the list given is not changed', () {
      final before = _texts(all);
      orderQuotes(all, QuoteOrder.newest);
      expect(_texts(all), before);
    });
  });

  group('sections', () {
    final ordered = orderQuotes(all, QuoteOrder.reading);

    test('by chapter follows the order, chapter-less last', () {
      final s = sectionQuotes(ordered, QuoteGroup.chapter);
      expect(_keys(s), ['Ch 2', 'Ch 10', '']);
      expect(_texts(s.first.quotes), ['d', 'a']);
    });

    test('by colour, in the palette\'s order', () {
      final s = sectionQuotes(ordered, QuoteGroup.colour);
      expect(_keys(s), ['yellow', 'blue', 'pink']);
      expect(_texts(s[1].quotes), ['a', 'c']);
    });

    test('by tag, a quote under each of its tags, untagged last', () {
      final s = sectionQuotes(ordered, QuoteGroup.tag);
      expect(_keys(s), ['love', 'war', '']);
      expect(_texts(s[1].quotes), ['a', 'b']);
      expect(_texts(s.last.quotes), ['d', 'c']);
    });

    test('by who said it, each name once, nobody last', () {
      final s = sectionQuotes(ordered, QuoteGroup.speaker);
      expect(_keys(s), ['Ilsa', 'Rick', '']);
      expect(_texts(s.first.quotes), ['d', 'a']);
      expect(_texts(s[1].quotes), ['a', 'b']);
    });

    test('by month, the newest month first', () {
      final s = sectionQuotes(ordered, QuoteGroup.month);
      expect(_keys(s), ['2026-03', '2026-01', '2025-12']);
      expect(_texts(s.first.quotes), ['a', 'c']);
    });

    test('no grouping is one section, in the order given', () {
      final s = sectionQuotes(ordered, QuoteGroup.none);
      expect(s, hasLength(1));
      expect(_texts(s.single.quotes), _texts(ordered));
    });
  });
}
