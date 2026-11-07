import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tippani/api/server_call.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/tags_screen.dart';
import 'package:tippani/tags/tag_service.dart';

import '../support/memory_library.dart';

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;

  @override
  Future<PickedFile?> pick() async => null;
}

/// The server's tags in memory, with a switch to make every call fail as an unreachable server does.
class _Tags implements TagService {
  _Tags(this.rows);

  final List<ServerTag> rows;
  final calls = <String>[];
  ServerException? fail;

  @override
  bool get available => true;

  void _check() {
    if (fail != null) throw fail!;
  }

  @override
  Future<List<ServerTag>> list() async {
    _check();
    return [...rows];
  }

  @override
  Future<ServerTag> create(String name, {String color = 'yellow'}) async {
    _check();
    calls.add('create $name');
    final t = ServerTag(
      id: rows.length + 10,
      name: name,
      color: color,
      style: 'sticker',
      quotes: 0,
    );
    rows.add(t);
    return t;
  }

  @override
  Future<ServerTag> save(
    ServerTag tag, {
    String? name,
    String? color,
    String? style,
  }) async {
    _check();
    calls.add('save ${tag.id} ${name ?? ''} ${color ?? ''} ${style ?? ''}');
    final i = rows.indexWhere((r) => r.id == tag.id);
    rows[i] = ServerTag(
      id: tag.id,
      name: name ?? tag.name,
      color: color ?? tag.color,
      style: style ?? tag.style,
      quotes: tag.quotes,
    );
    return rows[i];
  }

  @override
  Future<void> delete(ServerTag tag) async {
    _check();
    calls.add('delete ${tag.id}');
    rows.removeWhere((r) => r.id == tag.id);
  }

  @override
  Future<void> merge(ServerTag keep, List<ServerTag> drop) async {
    _check();
    calls.add('merge ${keep.id}<-${drop.map((d) => d.id).join(',')}');
    rows.removeWhere((r) => drop.any((d) => d.id == r.id));
  }
}

ServerTag _tag(int id, String name, [String color = 'yellow']) =>
    ServerTag(id: id, name: name, color: color, style: 'sticker', quotes: 1);

void main() {
  late MemoryLibrary lib;
  late _Tags svc;

  setUp(() async {
    lib = MemoryLibrary();
    await lib.addQuote(const QuoteDraft(text: 'One', tags: ['life', 'craft']));
    await lib.addQuote(const QuoteDraft(text: 'Two', tags: ['life']));
    svc = _Tags([_tag(1, 'life', 'blue'), _tag(2, 'craft', 'pink')]);
  });

  Future<void> open(WidgetTester tester, {TagService? service}) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: TagsScreen(
          store: lib,
          picker: _Picker(),
          service: service ?? svc,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String tag, String item) async {
    final row = find.ancestor(
      of: find.text('#$tag'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('Tag actions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every tag with how many quotes wear it', (tester) async {
    await open(tester);
    expect(find.text('#life'), findsOneWidget);
    expect(find.text('2 quotes · sticker'), findsOneWidget);
    expect(find.text('1 quote · sticker'), findsOneWidget);
  });

  testWidgets('a tag only the server holds is listed too', (tester) async {
    svc.rows.add(_tag(3, 'lonely'));
    await open(tester);
    expect(find.text('#lonely'), findsOneWidget);
  });

  testWidgets('with no server the tags are the phone\'s own', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TagsScreen(store: lib, picker: _Picker()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('#life'), findsOneWidget);
    expect(find.text('New tag'), findsNothing);
  });

  testWidgets('renaming changes the server first, then every quote', (
    tester,
  ) async {
    await open(tester);
    await menu(tester, 'life', 'Rename');
    await tester.enterText(find.byType(TextField).last, 'living');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(svc.calls, ['save 1 living  ']);
    final quotes = await lib.quotes();
    expect(quotes.every((q) => q.tags.contains('living')), isTrue);
    expect(quotes.any((q) => q.tags.contains('life')), isFalse);
    expect(find.text('#living'), findsOneWidget);
    expect(find.text('Renamed to #living.'), findsOneWidget);
  });

  testWidgets('renaming into an existing tag merges them on the server', (
    tester,
  ) async {
    await open(tester);
    await menu(tester, 'life', 'Rename');
    await tester.enterText(find.byType(TextField).last, 'Craft');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(svc.calls, ['merge 2<-1']);
    expect(find.text('#craft'), findsOneWidget);
    expect(find.text('#life'), findsNothing);
    expect((await lib.quotes()).every((q) => q.tags.length == 1), isTrue);
  });

  testWidgets(
    'a server that cannot be reached still changes the phone, and says so',
    (tester) async {
      await open(tester);
      svc.fail = const ServerException('The server could not be reached.');
      await menu(tester, 'life', 'Rename');
      await tester.enterText(find.byType(TextField).last, 'living');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The server could not be reached. Changed on this phone only.',
        ),
        findsOneWidget,
      );
      expect(
        (await lib.quotes()).every((q) => q.tags.contains('living')),
        isTrue,
      );
    },
  );

  testWidgets(
    'deleting asks, then takes the tag off the quotes and the server',
    (tester) async {
      await open(tester);
      await menu(tester, 'life', 'Delete');
      expect(
        find.text('It comes off 2 quotes. The quotes stay.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(svc.calls, ['delete 1']);
      expect(find.text('#life'), findsNothing);
      final quotes = await lib.quotes();
      expect(quotes, hasLength(2));
      expect(quotes.any((q) => q.tags.contains('life')), isFalse);
    },
  );

  testWidgets('cancelling a delete changes nothing', (tester) async {
    await open(tester);
    await menu(tester, 'life', 'Delete');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(svc.calls, isEmpty);
    expect(find.text('#life'), findsOneWidget);
  });

  testWidgets(
    'long press selects, and several are merged into the one chosen',
    (tester) async {
      await open(tester);
      await tester.longPress(find.text('#life'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('#craft'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Merge'));
      await tester.pumpAndSettle();
      // keep the second one in the list
      await tester.tap(find.text('#craft').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge').last);
      await tester.pumpAndSettle();
      expect(svc.calls, ['merge 2<-1']);
      final quotes = await lib.quotes();
      expect(
        quotes.every((q) => q.tags.length == 1 && q.tags.single == 'craft'),
        isTrue,
      );
      expect(find.text('#life'), findsNothing);
    },
  );

  testWidgets('colour and style are saved to the server', (tester) async {
    await open(tester);
    await menu(tester, 'life', 'Colour and style');
    await tester.tap(find.bySemanticsLabel('green'));
    await tester.tap(find.text('tape'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(svc.calls, ['save 1  green tape']);
    expect(svc.rows.first.color, 'green');
    expect(find.text('2 quotes · tape'), findsOneWidget);
  });

  testWidgets('a new tag is made on the server', (tester) async {
    await open(tester);
    await tester.tap(find.text('New tag'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '#fresh');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(svc.calls, ['create fresh']);
    expect(find.text('#fresh'), findsOneWidget);
  });

  testWidgets('the search box narrows the list', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'cra');
    await tester.pumpAndSettle();
    expect(find.text('#craft'), findsOneWidget);
    expect(find.text('#life'), findsNothing);
  });
}
