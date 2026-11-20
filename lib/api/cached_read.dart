import 'dart:async';

import 'api_client.dart';
import 'server_call.dart';

/// The one way a screen that shows what the server holds loads it (ADR-0032): draw the phone's copy at once, ask
/// the server behind it, replace the copy in place when the answer lands.
///
/// One [CachedRead] per thing a screen reads. Each [run] takes a turn number, and an answer that lands after a later
/// turn started is dropped, so a slow earlier read never puts older data back over a later one.
///
/// - First load, nothing on screen: the loader runs once from the phone only ([readFromPhone], no request, no
///   waiting). If every read in it had a copy, that is drawn. Then the loader runs for real.
/// - A copy on screen: only the real run, and a failure leaves the screen alone ([fail] is for a screen with
///   nothing to show).
/// - [live]: the read that follows a change the reader made. It never answers from the phone, so the old value
///   cannot come back over the new one.
class CachedRead {
  int _turn = 0;

  /// The turn a [run] started now would take, for a caller that wants to know whether it is still the latest.
  int get turn => _turn;

  Future<void> run<T>({
    required Future<T> Function() load,
    required bool Function() alive,
    required bool haveCopy,
    required void Function(T value) draw,
    required FutureOr<void> Function(Object error) fail,
    bool live = false,
  }) async {
    final mine = ++_turn;
    var shown = haveCopy;
    if (!live && !haveCopy) {
      try {
        final kept = await readFromPhone(load);
        if (mine == _turn && alive()) {
          draw(kept);
          shown = true;
        }
      } on Exception {
        // no copy of all of it: the real read below is what the screen waits for
      }
    }
    try {
      final fresh = await (live
          ? readLive(load, copyShown: shown)
          : shown
          ? readWithCopyShown(load)
          : load());
      if (mine == _turn && alive()) draw(fresh);
    } on Exception catch (e) {
      // a read that fails leaves a screen that has something showing alone; the shared note says it is the phone's
      if (mine == _turn && alive() && !shown) await fail(e);
    }
  }
}

/// What to tell the reader about a read that failed with nothing to show.
String problemText(Object e) => e is ServerException ? e.message : '$e';
