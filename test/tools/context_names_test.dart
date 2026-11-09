import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/tools/context_names.dart';

void main() {
  test('a text is split into its paragraphs or lines, empties dropped', () {
    expect(splitUnits('One.\n\n  Two.  \r\nThree.\n'), [
      'One.',
      'Two.',
      'Three.',
    ]);
    expect(splitUnits(''), isEmpty);
  });

  test('a name has to stand alone, and case does not matter', () {
    final s = findNames('Ann met annabel, and ANN smiled.', [
      ['Ann'],
    ]);
    expect([for (final x in s) (x.start, x.end)], [(0, 3), (21, 24)]);
  });

  test('other spellings count, and the longer name wins an overlap', () {
    const t = 'Mr. Bennet said his lady, Mrs. Bennet, knew Bennet.';
    final s = findNames(t, [
      ['Mr. Bennet', 'Bennet'],
      ['Mrs. Bennet', 'his lady'],
    ]);
    expect(
      [for (final x in s) t.substring(x.start, x.end)],
      ['Mr. Bennet', 'his lady', 'Mrs. Bennet', 'Bennet'],
    );
    expect([for (final x in s) x.who], [0, 1, 1, 0]);
  });

  test(
    'a one-letter name is not searched for, and an empty text finds nothing',
    () {
      expect(
        findNames('A B C', [
          ['A', 'B'],
        ]),
        isEmpty,
      );
      expect(
        findNames('', [
          ['Ann'],
        ]),
        isEmpty,
      );
    },
  );

  test('names with accents and other scripts stand alone too', () {
    final s = findNames('Zoë left; রহিম came back. Zoëtrope stayed.', [
      ['Zoë'],
      ['রহিম'],
    ]);
    expect([for (final x in s) x.who], [0, 1]);
  });
}
