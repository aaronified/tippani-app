import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/tools/context_store.dart';

// The contexts kept on the phone, one file each (ADR-0022).

void main() {
  late Directory dir;
  late FileContextStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tippani_ctx');
    store = FileContextStore(() async => Directory('${dir.path}/contexts'));
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on Object {
      // the temporary folder is the system's to clear
    }
  });

  test('an answer is kept and read back, and a missing one is null', () async {
    expect(await store.read('annotation-7'), isNull);
    await store.write(
      'annotation-7',
      StoredContext(at: DateTime.utc(2026), body: '{"body":"x"}'),
    );
    final read = await store.read('annotation-7');
    expect(read!.body, '{"body":"x"}');
    expect(read.none, isFalse);
  });

  test('a note that the server has none is kept as such', () async {
    await store.write('dialogue-3', StoredContext.none(DateTime.utc(2026)));
    expect((await store.read('dialogue-3'))!.none, isTrue);
  });

  test('a damaged file is a missing one, never an error', () async {
    await store.write(
      'annotation-1',
      StoredContext(at: DateTime.utc(2026), body: '{}'),
    );
    File('${dir.path}/contexts/annotation-1.json')
        .writeAsStringSync('{not json');
    expect(await store.read('annotation-1'), isNull);
  });

  test('clear forgets everything', () async {
    await store.write(
      'annotation-1',
      StoredContext(at: DateTime.utc(2026), body: '{}'),
    );
    await store.write(
      'utterance-2',
      StoredContext(at: DateTime.utc(2026), body: '{}'),
    );
    await store.clear();
    expect(await store.read('annotation-1'), isNull);
    expect(await store.read('utterance-2'), isNull);
  });
}
