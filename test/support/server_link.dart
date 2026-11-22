import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mark a screen wears while it shows the phone's copy because the server could not be reached or refused
/// (ADR-0033), found by what a screen reader announces rather than by what draws it.
final brokenLink = find.byWidgetPredicate(
  (w) =>
      w is Tooltip &&
      (w.message == unreachableLabel || w.message == refusedLabel),
);

/// What the mark is called while the server cannot be reached, and while it answered and turned the refresh down.
const unreachableLabel = 'Server not reachable';
const refusedLabel = 'Server refused the refresh';

/// Presses the broken-link mark and checks the words that come up (the old note's), then lets them go.
Future<void> linkSays(
  WidgetTester tester,
  String words, {
  String? not,
  String? also,
}) async {
  expect(brokenLink, findsOneWidget);
  await tester.tap(brokenLink);
  await tester.pump();
  final snack = find.descendant(
    of: find.byType(SnackBar),
    matching: find.textContaining(words),
  );
  expect(snack, findsOneWidget);
  if (also != null) expect(find.textContaining(also), findsOneWidget);
  if (not != null) {
    expect(find.textContaining(not), findsNothing);
  }
  ScaffoldMessenger.of(tester.element(find.byType(SnackBar))).clearSnackBars();
  await tester.pump();
}
