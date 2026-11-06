import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/harness/app_log.dart';
import 'package:tippani/harness/files.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  final fixed = DateTime.utc(2026, 11, 6, 8, 30, 15);

  AppLog logOn(MemoryAppFiles files) =>
      AppLog(files: files, clock: () => fixed);

  test('a line has a time, a level and the message', () async {
    final log = logOn(MemoryAppFiles());
    await log.start(version: '0.1.0');
    log.warn('server check failed: timeout');
    expect(
      log.lines.last,
      '2026-11-06T08:30:15 [warn] server check failed: timeout',
    );
    expect(log.lines.first, contains('start tippani-app 0.1.0'));
  });

  group('redact', () {
    test('takes a bearer token out of a line', () {
      expect(
        redact('Authorization: Bearer abc.def-123'),
        'Authorization: Bearer [redacted]',
      );
      expect(
        redact('header bearer SECRETVALUE sent'),
        'header bearer [redacted] sent',
      );
    });

    test('takes out token=, password= and key: values', () {
      expect(redact('claim token=abc123 done'), 'claim token=[redacted] done');
      expect(redact('password: hunter2'), 'password: [redacted]');
      expect(redact('api_key=AKIA1234'), contains('[redacted]'));
    });

    test('takes out a long run of hex or base64-looking characters, which is what a device token looks like', () {
      expect(redact('got ${'a1' * 20} back'), 'got [redacted] back');
      expect(redact('got ${'Ab_-' * 12} back'), 'got [redacted] back');
    });

    test('leaves an ordinary line alone', () {
      const line = 'server answered: revision 8, version 3.6.2';
      expect(redact(line), line);
    });

    test('the log applies it to everything added', () async {
      final log = logOn(MemoryAppFiles());
      log.info('sent Bearer ${'f' * 40}');
      expect(log.text(), isNot(contains('ffffffff')));
      expect(log.text(), contains('Bearer [redacted]'));
    });
  });

  test('a run keeps at most maxLines, dropping the oldest', () {
    final log = AppLog(clock: () => fixed);
    for (var i = 0; i < AppLog.maxLines + 50; i++) {
      log.info('line $i');
    }
    expect(log.length, AppLog.maxLines);
    expect(log.lines.first, contains('line 50'));
    expect(log.lines.last, contains('line ${AppLog.maxLines + 49}'));
  });

  test(
    'flush writes this run, and the next start moves it into the history',
    () async {
      final files = MemoryAppFiles();
      final first = logOn(files);
      await first.start(version: '0.1.0');
      first.info('first run line');
      await first.flush();
      expect(
        utf8.decode(files.logs[AppLog.currentFile]!),
        contains('first run line'),
      );

      final second = logOn(files);
      await second.start(version: '0.1.1');
      second.info('second run line');
      expect(
        second.text(),
        isNot(contains('first run line')),
        reason: 'this run alone by default',
      );
      final both = second.text(includeHistory: true);
      expect(
        both.indexOf('first run line'),
        lessThan(both.indexOf('second run line')),
      );
      expect(both, contains('earlier runs above'));
    },
  );

  test('the history keeps only its newest historyCap characters, from a whole line', () async {
    final files = MemoryAppFiles();
    final big = List.generate(
      8000,
      (i) => '2026-01-01T00:00:00 [info] filler line number $i',
    ).join('\n');
    files.logs[AppLog.historyFile] = bytes(big);
    final log = logOn(files);
    await log.start(version: '0.1.0');
    final text = log.text(includeHistory: true);
    expect(text.length, lessThan(AppLog.historyCap + 500));
    expect(text, contains('filler line number 7999'));
    expect(text, isNot(contains('filler line number 0\n')));
    expect(
      text.startsWith('2026-'),
      isTrue,
      reason: 'it starts at a line, not in the middle of one',
    );
  });

  test('starting twice does nothing the second time', () async {
    final log = logOn(MemoryAppFiles());
    await log.start(version: '0.1.0');
    await log.start(version: '0.1.0');
    expect(
      log.lines.where((l) => l.contains('start tippani-app')),
      hasLength(1),
    );
  });

  test(
    'clear empties this run and the history, in memory and on disk',
    () async {
      final files = MemoryAppFiles();
      final log = logOn(files);
      await log.start(version: '0.1.0');
      log.info('something');
      await log.flush();
      await log.clear();
      expect(log.length, 0);
      expect(log.text(includeHistory: true), isEmpty);
      expect(files.logs[AppLog.currentFile], isEmpty);
      expect(files.logs[AppLog.historyFile], isEmpty);
    },
  );

  test('a phone that cannot write does not break logging', () async {
    final files = MemoryAppFiles()..writable = false;
    final log = logOn(files);
    await log.start(version: '0.1.0');
    log.info('still here');
    await log.flush();
    expect(log.text(), contains('still here'));
  });
}
