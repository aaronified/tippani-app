import '../tools/work_details_source.dart';
import 'cover_cache.dart';
import 'library_store.dart';
import 'models.dart';

/// Keeps what a shelf and a work page draw on the phone, so they read with no server (ADR-0022): every cover
/// picture, and each work's details and cast. Run after a sync. Only what is not kept yet is fetched, and the
/// works go oldest first (never fetched, then the longest since), so each run moves on from where the last stopped.
/// A run makes at most [limit] requests (a work's details and its cast are two), and the rest follows at the next
/// sync, the way the quote contexts do. Details are read again once they are older than [refreshAfter], so a shelf
/// or a cast changed on the web reaches the phone.
///
/// A cover the server cannot serve (a 404) is no sign that it is not answering: it is skipped and, when the caller
/// passes [missed], not tried again until the app is next opened. Three works in a row whose details could not be
/// fetched do mean it: the run stops and the rest waits for the next sync. Returns how many requests it made.
Future<int> keepWorkExtras(
  LibraryStore library,
  CoverCache covers,
  WorkDetailsSource details, {
  int limit = 60,
  Duration refreshAfter = const Duration(days: 14),
  DateTime Function()? clock,
  Set<String>? missed,
}) async {
  final now = (clock ?? DateTime.now)();
  final works = [...await library.works()]
    ..sort((a, b) {
      final x = a.details.fetchedAt, y = b.details.fetchedAt;
      if (x == null || y == null) {
        return x == y ? 0 : (x == null ? -1 : 1);
      }
      return x.compareTo(y);
    });
  var made = 0;
  var failed = 0;
  for (final Work w in works) {
    if (made >= limit) break;
    if (w.cover.isNotEmpty &&
        !(missed?.contains(w.cover) ?? false) &&
        !await covers.kept(w.cover)) {
      final file = await covers.fileFor(w.cover);
      made++;
      if (file == null) missed?.add(w.cover);
      if (made >= limit) break;
    }
    final fetched = w.details.fetchedAt;
    final stale = fetched == null || now.difference(fetched) >= refreshAfter;
    if (w.serverId != null && stale) {
      final d = await details.fetch(w);
      made += 2;
      // not answered (no server, or it failed): the next sync tries again
      if (d == null) {
        if (++failed >= 3) break;
        continue;
      }
      failed = 0;
      await library.setWorkDetails(w.id, d);
    }
  }
  return made;
}
