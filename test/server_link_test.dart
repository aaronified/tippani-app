import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/account/preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/l10n/l10n.dart';
import 'package:tippani/library/models.dart';
import 'package:tippani/screens/library_screen.dart';
import 'package:tippani/screens/server_link.dart';
import 'package:tippani/settings/settings_store.dart';

import 'support/fake_server.dart';
import 'support/memory_library.dart';
import 'support/server_link.dart';

/// The app's real Bengali files, read from disk so no platform channel is needed.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());

  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      File(key).readAsString();
}

class _Picker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async => true;
  @override
  Future<PickedFile?> pick() async => null;
}

Future<AppController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final c = AppController(store, clientFactory: FakeServer().factory);
  await c.load();
  return c;
}

void main() {
  testWidgets(
    'a Bengali reader gets the toast in Bengali, through the real app wiring',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await _controller();
      final store = SettingsStore(
        await SharedPreferences.getInstance(),
        MemoryTokenVault(),
      );
      final l10n = L10n(bundle: _DiskBundle(), deviceLanguage: 'en');
      // the files are read in real time, not the test's fake clock
      await tester.runAsync(() async {
        l10n.use('bn');
        await l10n.loaded;
      });
      await tester.pumpWidget(
        TippaniApp(
          controller: c,
          harness: Harness.fake(
            store,
            controller: c,
            library: MemoryLibrary(),
            prefs: PairedPreferences(c, store),
            l10n: l10n,
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.offline.servedFrom.value = DateTime.utc(2026, 11, 13);
      await tester.pump();
      await tester.pump();
      final toast = find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('সার্ভারে পৌঁছানো যাচ্ছে না'),
      );
      expect(toast, findsOneWidget);
      expect(find.textContaining('Showing what this phone'), findsNothing);
    },
  );

  testWidgets(
    'the mark is named for what happened: unreachable, or answered and refused',
    (tester) async {
      final c = await _controller();
      await tester.pumpWidget(
        OfflineScope(
          offline: c.offline,
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: const [ServerLinkIcon()],
                leading: const ServerLinkBadge(child: Icon(Icons.dns)),
              ),
            ),
          ),
        ),
      );
      expect(brokenLink, findsNothing);

      c.offline.markServed(DateTime.utc(2026, 11, 13));
      await tester.pump();
      expect(find.byTooltip(unreachableLabel), findsOneWidget);
      expect(find.byTooltip(refusedLabel), findsNothing);
      expect(find.bySemanticsLabel(unreachableLabel), findsWidgets);

      c.offline.markRefused(DateTime.utc(2026, 11, 13), 'no');
      await tester.pump();
      expect(find.byTooltip(refusedLabel), findsOneWidget);
      expect(find.byTooltip(unreachableLabel), findsNothing);
      expect(find.bySemanticsLabel(refusedLabel), findsWidgets);
      expect(find.bySemanticsLabel(unreachableLabel), findsNothing);
    },
  );

  group('a message already showing is not thrown away', () {
    Future<(AppController, GlobalKey<ScaffoldMessengerState>)> framed(
      WidgetTester tester,
    ) async {
      final c = await _controller();
      final key = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        OfflineScope(
          offline: c.offline,
          child: MaterialApp(
            scaffoldMessengerKey: key,
            builder: (context, child) => ServerLinkToast(
              offline: c.offline,
              messenger: key,
              child: child!,
            ),
            home: const Scaffold(appBar: null, body: SizedBox()),
          ),
        ),
      );
      return (c, key);
    }

    testWidgets('the toast waits behind an Undo', (tester) async {
      final (c, key) = await framed(tester);
      key.currentState!.showSnackBar(
        SnackBar(
          content: const Text('Quote deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ),
      );
      await tester.pump();
      c.offline.markServed(DateTime.utc(2026, 11, 13));
      await tester.pump();
      await tester.pump();
      expect(find.text('Undo'), findsOneWidget);
      expect(find.textContaining('cannot be reached'), findsNothing);
      // the Undo goes; the toast comes after it
      key.currentState!.hideCurrentSnackBar();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Undo'), findsNothing);
      expect(find.textContaining('cannot be reached'), findsOneWidget);
    });

    testWidgets('pressing the mark waits behind an Undo', (tester) async {
      final c = await _controller();
      c.offline.markServed(DateTime.utc(2026, 11, 13));
      final key = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        OfflineScope(
          offline: c.offline,
          child: MaterialApp(
            scaffoldMessengerKey: key,
            home: Scaffold(appBar: AppBar(actions: const [ServerLinkIcon()])),
          ),
        ),
      );
      key.currentState!.showSnackBar(
        SnackBar(
          content: const Text('Quote deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ),
      );
      await tester.pump();
      await tester.tap(brokenLink);
      await tester.pump();
      expect(find.text('Undo'), findsOneWidget);
      expect(find.textContaining('cannot be reached'), findsNothing);
      key.currentState!.hideCurrentSnackBar();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.textContaining('cannot be reached'), findsOneWidget);
    });
  });

  testWidgets(
    'on a 360 dp phone the library\'s selection bar, with the mark, does not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await _controller();
      c.offline.markServed(DateTime.utc(2026, 11, 13));
      final lib = MemoryLibrary();
      for (final t in ['One', 'Two']) {
        await lib.addQuote(QuoteDraft(text: t));
      }
      await tester.pumpWidget(
        OfflineScope(
          offline: c.offline,
          child: MaterialApp(
            home: LibraryScreen(
              store: lib,
              picker: _Picker(),
              section: LibrarySection.quotes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('One'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(brokenLink, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
