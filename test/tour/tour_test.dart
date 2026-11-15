import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tippani/app.dart';
import 'package:tippani/app_controller.dart';
import 'package:tippani/harness/harness.dart';
import 'package:tippani/settings/settings_store.dart';
import 'package:tippani/tour/tour_store.dart';

import '../support/fake_anthologies.dart';
import '../support/fake_quiz.dart';
import '../support/fake_server.dart';
import '../support/memory_library.dart';

// A reader's view of the first-run tour: what the phone shows, what a person presses, what is shown on the next start.
// What these know of the code is the harness's `tour:` and `freshInstall:` arguments, the way the app is wired to be
// offered one without a first run on a real phone, and two keys on the tour's own parts — `tour-card` (the card) and
// `tour-spotlight` (an invisible box where the ring is drawn) — because where the ring sits is geometry and nothing on
// the screen says it in words; each is checked against a control found by its words or its type.

/// Opens the app on a phone that has never opened it. Call again, without [fresh], to start the app again on the same
/// phone.
Future<AppController> open(
  WidgetTester tester, {
  bool fresh = true,
  bool quiz = true,
  bool anthologies = true,
  bool pair = false,
  bool freshInstall = true,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (fresh) {
    SharedPreferences.setMockInitialValues({
      if (pair) 'server_url': 'https://q.example.org',
    });
  }
  final server = FakeServer();
  final store = SettingsStore(
    await SharedPreferences.getInstance(),
    MemoryTokenVault(),
  );
  final c = AppController(store, clientFactory: server.factory);
  await c.load();
  if (pair) await c.pair('ABCD2345', 'My phone');
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    TippaniApp(
      controller: c,
      harness: Harness.fake(
        store,
        controller: c,
        library: MemoryLibrary(),
        quiz: quiz ? FakeQuiz() : null,
        anthologies: anthologies ? FakeAnthologies() : null,
        tour: const TourStore(),
        freshInstall: freshInstall,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pumpAndSettle();
  return c;
}

/// Words on the tour's card, not the same words on the screen under it.
Finder inCard(String text) => find.descendant(
  of: find.byKey(const ValueKey('tour-card')),
  matching: find.text(text),
);

Finder get welcome => find.text('Welcome to Tippani');

Future<void> press(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('tour-card')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

int tab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  testWidgets('a first run is offered the tour, with a Skip and where it is', (
    tester,
  ) async {
    await open(tester);
    expect(welcome, findsOneWidget);
    expect(find.text('1 of 7'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Skip'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, 'Back'),
      findsNothing,
      reason: 'nowhere to go back to on the first stop',
    );
  });

  testWidgets(
    'Skip dismisses it for good: the app started again does not ask',
    (tester) async {
      await open(tester);
      await press(tester, 'Skip');
      expect(welcome, findsNothing);
      await open(tester, fresh: false);
      expect(welcome, findsNothing);
      await open(tester, fresh: false);
      expect(find.text('Skip'), findsNothing);
    },
  );

  testWidgets('Next and Back walk the stops, and Done is remembered', (
    tester,
  ) async {
    await open(tester);
    await press(tester, 'Next');
    expect(find.text('Add anything'), findsOneWidget);
    expect(find.text('2 of 7'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Back'), findsOneWidget);
    await press(tester, 'Back');
    expect(welcome, findsOneWidget);
    expect(find.text('1 of 7'), findsOneWidget);

    for (final title in [
      'Add anything',
      'Home',
      'Your shelves',
      'Anthologies',
      'Your server',
    ]) {
      await press(tester, 'Next');
      expect(inCard(title), findsOneWidget, reason: title);
    }
    await press(tester, 'Next');
    expect(find.text('7 of 7'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Next'),
      findsNothing,
      reason: 'the last stop ends the tour',
    );
    await press(tester, 'Done');
    expect(find.text('7 of 7'), findsNothing);
    await open(tester, fresh: false);
    expect(welcome, findsNothing);
  });

  testWidgets('each stop opens the tab its control is on', (tester) async {
    await open(tester);
    expect(tab(tester), 0);
    await press(tester, 'Next'); // add: on Home
    expect(tab(tester), 0);
    await press(tester, 'Next');
    await press(tester, 'Next'); // shelves
    expect(tab(tester), 1);
    await press(tester, 'Next');
    await press(tester, 'Next'); // server
    expect(tab(tester), 2);
    await press(tester, 'Next'); // settings
    expect(tab(tester), 3);
  });

  testWidgets('Take the tour in Settings plays it again', (tester) async {
    await open(tester);
    await press(tester, 'Skip');
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take the tour'));
    await tester.pumpAndSettle();
    expect(welcome, findsOneWidget);
    expect(find.text('1 of 7'), findsOneWidget);
    await press(tester, 'Skip');
    expect(welcome, findsNothing);
  });

  testWidgets('a stop whose control this reader has not got is skipped', (
    tester,
  ) async {
    // no quiz on this server: no Home tab and so no Add button, and no Anthologies: the stops that point at them go
    await open(tester, quiz: false, anthologies: false);
    expect(find.text('1 of 4'), findsOneWidget);
    await press(tester, 'Next');
    expect(find.text('Add anything'), findsNothing);
    expect(find.text('Your shelves'), findsOneWidget);
    expect(find.text('2 of 4'), findsOneWidget);
    await press(tester, 'Next');
    expect(find.text('Your server'), findsOneWidget);
    expect(find.text('Anthologies'), findsNothing);
    await press(tester, 'Next');
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('4 of 4'), findsOneWidget);
  });

  testWidgets('Keeping in step is a stop for a paired phone only', (
    tester,
  ) async {
    await open(tester, pair: true);
    expect(find.text('1 of 8'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await press(tester, 'Next');
    }
    expect(inCard('Keeping in step'), findsOneWidget);
    expect(find.text('7 of 8'), findsOneWidget);
  });

  testWidgets(
    'the card is by the thumb, and the screen under it takes no press',
    (tester) async {
      await open(tester);
      await press(tester, 'Next'); // the Add button
      final card = tester.getRect(find.byKey(const ValueKey('tour-card')));
      final bar = tester.getRect(find.byType(NavigationBar));
      expect(card.center.dy, greaterThan(1200), reason: 'in the lower half');
      expect(card.bottom, lessThanOrEqualTo(bar.top));
      // a press on the control itself is the tour's, not the app's
      await tester.tap(find.text('Add a quote'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Scan a page'), findsNothing);
      expect(find.text('Add anything'), findsOneWidget);
    },
  );

  testWidgets('the card is announced to a screen reader when a stop changes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    var node = tester.getSemantics(find.byKey(const ValueKey('tour-text')));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    expect(node.label, contains('Welcome to Tippani'));
    expect(node.label, contains('1 of 7'));
    await press(tester, 'Next');
    node = tester.getSemantics(find.byKey(const ValueKey('tour-text')));
    expect(node.label, contains('Add anything'));
    expect(node.label, contains('Start here'));
    semantics.dispose();
  });

  testWidgets(
    'it works at the largest text, in the dark, with animations off',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(() {
        tester.platformDispatcher.clearAllTestValues();
      });
      await open(tester);
      expect(welcome, findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.widgetWithText(FilledButton, 'Next'));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      // still there with nothing animated, and the Next button can be pressed
      expect(find.text('Your shelves'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Next').hitTestable(),
        findsOneWidget,
      );
    },
  );

  testWidgets('someone upgrading is not walked through it again', (
    tester,
  ) async {
    await open(tester, freshInstall: false);
    expect(welcome, findsNothing);
  });

  /// Where the ring is drawn, and where the control it should be on is.
  Rect ring(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('tour-spotlight')));

  Rect controlWithWords(WidgetTester tester, String words) => tester.getRect(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(words)),
  );

  Future<void> toTheLastStop(WidgetTester tester) async {
    for (var i = 0; i < 12 && find.text('Done').evaluate().isEmpty; i++) {
      await press(tester, 'Next');
    }
  }

  testWidgets('the ring sits on the control the stop names', (tester) async {
    await open(tester);
    await press(tester, 'Next');
    expect(
      ring(tester)
          .contains(tester.getCenter(find.byType(FloatingActionButton))),
      isTrue,
      reason: 'the Add stop rings the Add button',
    );
    await toTheLastStop(tester);
    expect(
      ring(tester).contains(controlWithWords(tester, 'Settings').center),
      isTrue,
      reason: 'the last stop rings the Settings tab',
    );
  });

  testWidgets('the ring follows the control when the screen changes shape', (
    tester,
  ) async {
    await open(tester);
    await toTheLastStop(tester);
    tester.view.physicalSize = const Size(1200, 700);
    await tester.pumpAndSettle();
    expect(
      ring(tester).contains(controlWithWords(tester, 'Settings').center),
      isTrue,
    );
  });

  testWidgets('the system Back is a Skip, and is remembered', (tester) async {
    await open(tester);
    expect(welcome, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(welcome, findsNothing);
    await open(tester, fresh: false);
    expect(welcome, findsNothing);
  });

  testWidgets('the reader is put back on the tab they started on', (
    tester,
  ) async {
    await open(tester);
    final started = tab(tester);
    await toTheLastStop(tester);
    expect(
      tab(tester),
      isNot(started),
      reason: 'the last stop is on another tab',
    );
    await press(tester, 'Done');
    expect(tab(tester), started);
  });
}
