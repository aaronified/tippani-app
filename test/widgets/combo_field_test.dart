import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/library/suggestions.dart';
import 'package:tippani/widgets/combo_field.dart';

Work _work(
  int id,
  String title, {
  String series = '',
  WorkKind kind = WorkKind.book,
  String creator = '',
  String language = '',
}) => Work(
  id: id,
  kind: kind,
  title: title,
  creator: creator,
  year: null,
  language: language,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  details: WorkDetails(series: series),
);

void main() {
  test('suggestions put what starts with the typing first, then words, then the rest', () {
    final out = rankOptions('car', [
      'Scarlett',
      'Carol',
      'The Carpet-Bag',
      'Oscar',
    ]);
    expect(out, ['Carol', 'The Carpet-Bag', 'Scarlett', 'Oscar']);
  });

  test(
    'case and accents do not matter, and what is already taken is left out',
    () {
      expect(rankOptions('zoe', ['Zoë', 'Zoey']), ['Zoë', 'Zoey']);
      expect(rankOptions('', ['A', 'B']), ['A', 'B']);
      expect(rankOptions('', ['A', 'B'], skip: {'a'}), ['B']);
    },
  );

  test('a work stands alone, or with the works of its series', () {
    final a = _work(1, 'A', series: 'Saga');
    final b = _work(2, 'B', series: ' saga ');
    final c = _work(3, 'C');
    final film = _work(4, 'D', series: 'Saga', kind: WorkKind.film);
    expect(seriesOf(a, [a, b, c, film]).map((w) => w.id), [1, 2]);
    expect(seriesOf(c, [a, b, c]).map((w) => w.id), [3]);
    expect(seriesOf(null, [a]), isEmpty);
  });

  test('chapters come in chapter order where they carry a number', () {
    expect(
      sortChapters(['Epilogue', '10. Ten', 'Chapter 2', '1. One', 'Prologue']),
      ['1. One', 'Chapter 2', '10. Ten', 'Epilogue', 'Prologue'],
    );
  });

  test('credits come from the library and the server, by the kind of work', () {
    final out = creditOptions(
      WorkKind.film,
      [
        _work(1, 'F', kind: WorkKind.film, creator: 'Ang Lee, Wong Kar-wai'),
        _work(2, 'B', creator: 'Someone Else'),
      ],
      (kind) =>
          kind == 'director' ? ['Wong Kar-wai', 'Satyajit Ray'] : ['An Author'],
    );
    expect(out.take(4), [
      'Ang Lee',
      'Wong Kar-wai',
      'Satyajit Ray',
      'An Author',
    ]);
    expect(out, isNot(contains('Someone Else')));
  });

  test('languages in the library come before the common ones', () {
    final out = languageOptions([_work(1, 'A', language: 'bn')]);
    expect(out.first, 'bn');
    expect(out.where((l) => l == 'bn'), hasLength(1));
    expect(out, contains('en'));
  });

  test('every text box says how it capitalises', () {
    final missing = <String>[];
    final start = RegExp(r'\b(TextField|TextFormField)\(');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      for (final m in start.allMatches(s)) {
        var i = m.end;
        var depth = 1;
        while (depth > 0 && i < s.length) {
          if (s[i] == '(') depth++;
          if (s[i] == ')') depth--;
          i++;
        }
        if (!s.substring(m.start, i).contains('textCapitalization')) {
          missing.add(
            '${f.path}:${s.substring(0, m.start).split('\n').length}',
          );
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'give each a textCapitalization: $missing',
    );
  });
}
