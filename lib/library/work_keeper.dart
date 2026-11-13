import '../tools/work_details_source.dart';
import 'cover_cache.dart';
import 'library_store.dart';
import 'models.dart';

/// Keeps what a shelf and a work page draw on the phone, so they read with no server (ADR-0022): every cover
/// picture, and each work's details and cast. Run after a sync. Only what is not kept yet is fetched, up to
/// [limit] requests a run, and the rest follows at the next sync, the way the quote contexts do. Details are read
/// again once they are older than [refreshAfter], so a shelf or a cast changed on the web reaches the phone.
/// Returns how many requests it made.
Future<int> keepWorkExtras(
  LibraryStore library,
  CoverCache covers,
  WorkDetailsSource details, {
  int limit = 60,
  Duration refreshAfter = const Duration(days: 14),
  DateTime Function()? clock,
}) async {
  final now = (clock ?? DateTime.now)();
  var made = 0;
  var failed = 0;
  for (final Work w in await library.works()) {
    if (made >= limit) break;
    if (w.cover.isNotEmpty && !await covers.kept(w.cover)) {
      final file = await covers.fileFor(w.cover);
      made++;
      failed = file == null ? failed + 1 : 0;
      // three misses in a row: the server is not answering, so the rest waits for the next sync
      if (failed >= 3) break;
      if (made >= limit) break;
    }
    final fetched = w.details.fetchedAt;
    final stale = fetched == null || now.difference(fetched) >= refreshAfter;
    if (w.serverId != null && stale) {
      final d = await details.fetch(w);
      made++;
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
