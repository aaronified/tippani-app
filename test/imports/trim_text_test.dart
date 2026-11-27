import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/imports/trim_text.dart';

/// Where the function IS the observable unit: what a long quote is cut into, and what keeping a run gives back.
void main() {
  test('a quote is cut after each sentence end, and nothing but white space is lost', () {
    expect(
      sentencesOf(
        'The spice must flow. Fear is the mind-killer! Who said that?',
      ),
      ['The spice must flow.', 'Fear is the mind-killer!', 'Who said that?'],
    );
  });

  test(
    'a closing quote stays with its sentence, and an opening one with the next',
    () {
      expect(sentencesOf('“Stop.” He did. “Why?” “Because.”'), [
        '“Stop.”',
        'He did.',
        '“Why?”',
        '“Because.”',
      ]);
    },
  );

  test('text with no end is one sentence, and an ellipsis is an end', () {
    expect(sentencesOf('no end here'), ['no end here']);
    expect(sentencesOf('and then… nothing'), ['and then…', 'nothing']);
  });

  test('a number or a name with a full stop inside it is not an end', () {
    expect(sentencesOf('It cost 3.5 rupees. Fine.'), [
      'It cost 3.5 rupees.',
      'Fine.',
    ]);
  });

  test('empty and blank text have no sentences', () {
    expect(sentencesOf(''), isEmpty);
    expect(sentencesOf('   \n '), isEmpty);
  });

  test('a run of sentences is kept, joined by one space', () {
    final s = sentencesOf('One. Two. Three. Four.');
    expect(keepSentences(s, 1, 2), 'Two. Three.');
    expect(keepSentences(s, 0, 3), 'One. Two. Three. Four.');
    expect(keepSentences(s, 3, 3), 'Four.');
  });
}
