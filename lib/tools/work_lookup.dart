import '../api/server_call.dart';
import '../app_controller.dart';
import '../library/models.dart';

/// One possible match for a work the reader is describing.
class WorkMatch {
  const WorkMatch({required this.title, required this.creator, this.year});

  final String title;

  /// The author, where the source gives one (books do; films and shows do not).
  final String creator;
  final int? year;

  String get summary =>
      [if (creator.isNotEmpty) creator, if (year != null) '$year'].join(' · ');
}

/// Finds what a title most likely is, through the paired server (which holds the keys for TMDB, TheTVDB and the
/// rest, so this app holds none). An interface so a test can stand in for the server.
abstract class WorkLookup {
  bool get available;
  Future<List<WorkMatch>> find(
    WorkKind kind,
    String title, {
    String creator = '',
  });
}

class PairedWorkLookup implements WorkLookup {
  PairedWorkLookup(this._controller);
  final AppController _controller;

  @override
  bool get available => _controller.paired;

  @override
  Future<List<WorkMatch>> find(
    WorkKind kind,
    String title, {
    String creator = '',
  }) => serverCall(_controller, (c) async {
    final isBook = kind == WorkKind.book || kind == WorkKind.other;
    final body = asMap(
      isBook
          ? await c.postJson('/books/lookup', {
              'title': title,
              if (creator.trim().isNotEmpty) 'author': creator.trim(),
            })
          : await c.postJson('/movies/lookup', {
              'title': title,
              'media_type': switch (kind) {
                WorkKind.show => 'show',
                WorkKind.game => 'game',
                _ => 'movie',
              },
            }),
    );
    final all = body['candidates'];
    if (all is! List) return <WorkMatch>[];
    return [
      for (final m in all)
        if (m is Map && (m['title'] as String? ?? '').isNotEmpty)
          WorkMatch(
            title: m['title'] as String,
            creator: (m['author'] as String?) ?? '',
            year: ((m['published_year'] ?? m['release_year']) as num?)
                ?.toInt()
                .let((y) => y > 0 ? y : null),
          ),
    ];
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
