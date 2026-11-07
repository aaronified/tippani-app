import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../app_controller.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../sync/board_sync.dart' show boardFields;
import '../sync/fingerprint.dart';

/// Something went wrong with a board on the server, in words for the reader.
class BoardException implements Exception {
  const BoardException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A language the server has starter proverbs in, and how many.
class StarterOffer {
  const StarterOffer(this.language, this.count);
  final String language;
  final int count;
}

/// The kinds of board the server knows, with the words for each.
const boardKinds = <(String, String)>[
  ('plain', 'Plain'),
  ('proverb', 'Proverbs'),
  ('speech', 'Speeches'),
  ('letter', 'Letters'),
  ('essay', 'Essays'),
];

String boardKindLabel(String kind) =>
    boardKinds.where((k) => k.$1 == kind).map((k) => k.$2).firstOrNull ??
    'Plain';

/// What the server holds for a board beyond its name and colour: a description, a picture, its kind and languages,
/// whether it is hidden, and where it sits in the order. An interface so a test can stand in for the server.
abstract class BoardService {
  /// Whether there is a paired server to ask.
  bool get available;

  /// Changes some of the server's fields for [board] (any of `description`, `kind`, `languages`, `hidden`, `pos`)
  /// and keeps the answer on the phone. Throws if the board is not on the server yet.
  Future<void> update(Board board, Map<String, Object?> changes);

  /// Puts a picture on [board] and keeps its name on the phone.
  Future<void> setImage(Board board, Uint8List bytes, String fileName);

  /// Takes the picture off [board].
  Future<void> removeImage(Board board);

  /// The languages the server has starter proverbs in.
  Future<List<StarterOffer>> starters();

  /// Files the starter proverbs of [language] on [board] (on the server; they reach the phone with the next sync).
  /// How many were new.
  Future<int> addStarters(Board board, String language);
}

/// The paired server's boards, through the app's own API client. What it learns about a board is written back to
/// the phone's copy of the server's row, so the screens show it at once and the sync agrees with it.
class ServerBoards implements BoardService {
  ServerBoards(this._controller, this._store);

  final AppController _controller;
  final LibraryStore _store;

  @override
  bool get available => _controller.paired;

  Future<T> _call<T>(Future<T> Function(ApiClient c) run) async {
    if (!available) {
      throw const BoardException('This phone is not paired with a server.');
    }
    try {
      return await _controller.withClient(run) as T;
    } on ApiException catch (e) {
      throw BoardException(switch (e.failure) {
        ApiFailure.network => 'The server could not be reached.',
        ApiFailure.timeout => 'The server took too long to answer.',
        ApiFailure.unauthorised =>
          'The server no longer accepts this phone. Pair it again.',
        ApiFailure.forbidden => 'The server does not allow that.',
        ApiFailure.rateLimited => 'The server asks you to wait a moment.',
        ApiFailure.server || ApiFailure.badResponse =>
          e.detail.isNotEmpty ? e.detail : 'The server could not do that.',
      });
    }
  }

  /// The fields the server's board edit takes. It replaces the whole board, so all of them go every time.
  static const _putKeys = [
    'name',
    'description',
    'color',
    'image_path',
    'hidden',
    'pos',
    'kind',
    'languages',
    'text_order',
  ];

  /// Reads the board's row as the server has it now, writes [changes] over it, and keeps the result.
  Future<void> _write(
    Board board,
    Map<String, Object?> Function(Map<String, Object?> row) change,
  ) async {
    final id = board.serverId;
    if (id == null) {
      throw const BoardException(
        'This board is not on the server yet. Sync, then try again.',
      );
    }
    final row = await _call((c) async {
      final got = await c.getJson('/boards');
      final l = got is Map ? got['boards'] : null;
      final mine = [
        if (l is List)
          for (final x in l)
            if (x is Map && x['id'] == id) Map<String, Object?>.from(x),
      ];
      if (mine.isEmpty) {
        throw const BoardException('The server does not have this board.');
      }
      final next = {...mine.first, ...change(mine.first)};
      await c.putJson('/boards/$id', {
        for (final k in _putKeys)
          if (next.containsKey(k)) k: next[k],
      });
      return next;
    });
    // the phone's name and colour may be ahead of the server's; they travel with the next sync, not here
    final hash =
        board.syncedHash ?? fingerprint(boardFields(board.name, board.color));
    await _store.linkBoard(board.id, id, hash, row);
  }

  @override
  Future<void> update(Board board, Map<String, Object?> changes) =>
      _write(board, (_) => changes);

  @override
  Future<void> setImage(Board board, Uint8List bytes, String fileName) async {
    final id = board.serverId;
    if (id == null) {
      throw const BoardException(
        'This board is not on the server yet. Sync, then try again.',
      );
    }
    final r = await _call(
      (c) => c.postFile('/boards/$id/cover', 'file', bytes, fileName),
    );
    final name = r is Map ? (r['image_path'] ?? r['path']) : null;
    if (name is! String || name.isEmpty) {
      throw const BoardException('The server did not keep the picture.');
    }
    final hash =
        board.syncedHash ?? fingerprint(boardFields(board.name, board.color));
    await _store.linkBoard(board.id, id, hash, {
      ...board.serverRow,
      'image_path': name,
    });
  }

  @override
  Future<void> removeImage(Board board) =>
      _write(board, (_) => {'image_path': ''});

  @override
  Future<List<StarterOffer>> starters() => _call((c) async {
    final r = await c.getJson('/quotes/starters');
    final l = r is Map ? r['languages'] : null;
    return [
      if (l is List)
        for (final x in l)
          if (x is Map)
            StarterOffer(
              '${x['language'] ?? ''}',
              (x['count'] as num?)?.toInt() ?? 0,
            ),
    ];
  });

  @override
  Future<int> addStarters(Board board, String language) async {
    final id = board.serverId;
    if (id == null) {
      throw const BoardException(
        'This board is not on the server yet. Sync, then try again.',
      );
    }
    final r = await _call(
      (c) => c.postJson('/quotes/starters', {
        'language': language,
        'board_id': id,
      }),
    );
    return r is Map ? (r['added'] as num?)?.toInt() ?? 0 : 0;
  }
}

/// Gives the screens below it the [BoardService].
class BoardScope extends InheritedWidget {
  const BoardScope({super.key, required this.service, required super.child});

  final BoardService? service;

  static BoardService? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BoardScope>()?.service;

  @override
  bool updateShouldNotify(BoardScope old) => old.service != service;
}
