import 'package:shared_preferences/shared_preferences.dart';

/// How the first-run tour ended on this phone.
enum TourOutcome { finished, dismissed }

/// Whether the tour has been seen, kept on the phone in its own two keys. THERE IS NO SERVER FIELD FOR THIS: the web
/// keeps its own tour state on the account, but it describes the web's screens, and a reader who finished that tour
/// has not seen the bottom bar (ADR-0027).
class TourStore {
  const TourStore();

  static const outcomeKey = 'tour_outcome';

  /// Which tour was shown. A later, longer tour bumps this and is offered once more to those who finished the old one.
  static const versionKey = 'tour_version';
  static const version = 1;

  /// null while the tour has not been offered (or was last seen as an older one).
  Future<TourOutcome?> outcome() async {
    try {
      final p = await SharedPreferences.getInstance();
      if ((p.getInt(versionKey) ?? 0) < version) return null;
      return switch (p.getString(outcomeKey)) {
        'finished' => TourOutcome.finished,
        'dismissed' => TourOutcome.dismissed,
        _ => null,
      };
    } on Object {
      // a phone that cannot be read is not pestered with the tour on every start
      return TourOutcome.dismissed;
    }
  }

  Future<void> remember(TourOutcome outcome) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(outcomeKey, outcome.name);
      await p.setInt(versionKey, version);
    } on Object {
      // nothing to do: the tour just may be offered again
    }
  }
}
