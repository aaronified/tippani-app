import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../api/server_call.dart';
import '../app_controller.dart';
import '../library/models.dart';
import '../sync/fingerprint.dart';

/// Where a work's extra facts come from. An interface so a test can stand in for the server.
abstract class WorkDetailsSource {
  /// What the server knows about [work] (its description, genres, cast and the rest), or null when it cannot be
  /// asked: the work is not on the server yet, no server is paired, or the server did not answer.
  Future<WorkDetails?> fetch(Work work);
}

/// How long fetched details are trusted before a work's page asks again.
const detailsFreshFor = Duration(days: 1);

/// Fetches a work's record and its cast from the paired server.
class PairedWorkDetails implements WorkDetailsSource {
  PairedWorkDetails(this._controller, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppController _controller;
  final DateTime Function() _clock;

  @override
  Future<WorkDetails?> fetch(Work work) async {
    final id = work.serverId;
    if (id == null || !_controller.paired) return null;
    final route = workRoute(realmOfKind(work.kind));
    try {
      return await serverCall<WorkDetails?>(_controller, (c) async {
        final row = await c.getJson('$route/$id');
        if (row is! Map) return null;
        final base = WorkDetails.fromJson(row);
        // The cast is a separate answer; if it fails the rest still counts, and the cast already held is kept.
        var cast = work.details.cast;
        try {
          final body = await c.getJson('$route/$id/cast');
          final list = body is Map ? body['cast'] : null;
          if (list is List) {
            cast = [
              for (final x in list)
                if (CastMember.fromJson(x) != null) CastMember.fromJson(x)!,
            ];
          }
        } on ApiException {
          // keep what was there
        }
        return base.copyWith(cast: cast, fetchedAt: _clock());
      });
    } on ServerException {
      return null;
    }
  }
}

/// Gives the work screen the [WorkDetailsSource] without every screen taking one.
class DetailsScope extends InheritedWidget {
  const DetailsScope({super.key, required this.source, required super.child});

  final WorkDetailsSource? source;

  static WorkDetailsSource? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailsScope>()?.source;

  @override
  bool updateShouldNotify(DetailsScope old) => old.source != source;
}
