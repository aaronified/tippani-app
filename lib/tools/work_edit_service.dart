import 'package:flutter/widgets.dart';

import '../api/server_call.dart';
import '../app_controller.dart';
import '../library/models.dart';
import '../sync/fingerprint.dart';

/// What a reader changes about a work on the server from the phone: its cast rows now, and (as the work page
/// gains them) its details and its cover. Every write goes THROUGH to the server, which owns these, so the web and
/// the phone agree; a refusal throws a [ServerException] carrying the server's own words. An interface so a test
/// can stand in for the server.
abstract class WorkEditService {
  /// Pulls the cast from TheTVDB for a film or show. [tvdbId] names the record when the work has none yet.
  Future<void> fetchCastFromTvdb(Work work, {int? tvdbId});

  /// Pulls the cast from IMDb; [imdb] is a title link or a `tt…` id.
  Future<void> fetchCastFromImdb(Work work, String imdb);

  /// Adds one row to the work's cast. A book has characters and no [actor].
  Future<void> addCast(
    Work work, {
    required String character,
    String actor = '',
  });

  /// Corrects one row: both names are sent, as the server reads an edit without them as no edit.
  Future<void> editCast(int castId, {required String character, String actor});

  /// Takes the row off the list.
  Future<void> removeCast(int castId);

  /// Keeps the character and takes the performer off it.
  Future<void> removeCastActor(int castId);
}

class PairedWorkEdit implements WorkEditService {
  PairedWorkEdit(this._controller);

  final AppController _controller;

  String _route(Work w) => workRoute(realmOfKind(w.kind));

  int _id(Work w) => w.serverId ?? (throw const ServerException('not synced'));

  @override
  Future<void> fetchCastFromTvdb(Work work, {int? tvdbId}) => serverCall<void>(
    _controller,
    (c) async {
      await c.postJson('/movies/${_id(work)}/cast/tvdb', {'tvdb_id': ?tvdbId});
    },
  );

  @override
  Future<void> fetchCastFromImdb(Work work, String imdb) =>
      serverCall<void>(_controller, (c) async {
        await c.postJson('/movies/${_id(work)}/cast/imdb', {'imdb': imdb});
      });

  @override
  Future<void> addCast(
    Work work, {
    required String character,
    String actor = '',
  }) => serverCall<void>(_controller, (c) async {
    await c.postJson('${_route(work)}/${_id(work)}/cast', {
      'character': character,
      if (actor.isNotEmpty) 'actor': actor,
    });
  });

  @override
  Future<void> editCast(
    int castId, {
    required String character,
    String actor = '',
  }) => serverCall<void>(_controller, (c) async {
    await c.putJson('/cast/$castId', {'character': character, 'actor': actor});
  });

  @override
  Future<void> removeCast(int castId) =>
      serverCall<void>(_controller, (c) async {
        await c.delete('/cast/$castId');
      });

  @override
  Future<void> removeCastActor(int castId) =>
      serverCall<void>(_controller, (c) async {
        await c.delete('/cast/$castId/actor');
      });
}

/// Gives the work page the [WorkEditService] without every screen taking one.
class WorkEditScope extends InheritedWidget {
  const WorkEditScope({super.key, required this.service, required super.child});

  final WorkEditService? service;

  static WorkEditService? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkEditScope>()?.service;

  @override
  bool updateShouldNotify(WorkEditScope old) => old.service != service;
}
