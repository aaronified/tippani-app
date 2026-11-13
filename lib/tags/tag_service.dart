import 'package:flutter/widgets.dart';

import '../api/server_call.dart';
import '../api/offline_writes.dart';
import '../app_controller.dart';

/// The looks a tag can wear on the web: a sticker, a banner, a flyout, a piece of tape or a film reel.
const tagStyles = ['sticker', 'banner', 'flyout', 'tape', 'reel'];

/// A tag as the server keeps it: a name, a colour (one of the quote colours) and a style, with how many of the
/// server's quotes wear it.
class ServerTag {
  const ServerTag({
    required this.id,
    required this.name,
    required this.color,
    required this.style,
    required this.quotes,
  });

  final int id;
  final String name;
  final String color;
  final String style;
  final int quotes;

  factory ServerTag.fromJson(Map<String, Object?> j) => ServerTag(
    id: (j['id'] as num).toInt(),
    name: (j['name'] as String?) ?? '',
    color: (j['color'] as String?) ?? 'yellow',
    style: (j['style'] as String?) ?? 'sticker',
    quotes:
        ((j['annotations'] as num?)?.toInt() ?? 0) +
        ((j['dialogues'] as num?)?.toInt() ?? 0) +
        // Standalone quotes; a server older than 3.7.1 does not send the count.
        ((j['utterances'] as num?)?.toInt() ?? 0),
  );
}

/// The server's tags: their colours and styles live only there. An interface so a test can stand in for it.
abstract class TagService {
  bool get available;
  Future<List<ServerTag>> list();

  /// Makes a tag (a new name; the server refuses one that exists, in any capitals).
  Future<ServerTag> create(String name, {String color = 'yellow'});

  /// Changes a tag's name, colour and style (all three are sent: the server takes the whole tag).
  Future<ServerTag> save(
    ServerTag tag, {
    String? name,
    String? color,
    String? style,
  });

  Future<void> delete(ServerTag tag);

  /// Folds [drop] into [keep]: every quote wearing a dropped tag wears [keep] instead.
  Future<void> merge(ServerTag keep, List<ServerTag> drop);
}

class PairedTagService implements TagService {
  PairedTagService(this._controller, {this.writes});
  final AppController _controller;

  /// Where a rename, a colour or style change and a delete wait when the server cannot be reached.
  final OfflineWrites? writes;

  @override
  bool get available => _controller.paired;

  @override
  Future<List<ServerTag>> list() => serverCall(_controller, (c) async {
    final body = asMap(await c.getJson('/tags'));
    final all = body['tags'];
    return [
      if (all is List)
        for (final t in all)
          if (t is Map) ServerTag.fromJson(Map<String, Object?>.from(t)),
    ];
  });

  @override
  Future<ServerTag> create(String name, {String color = 'yellow'}) =>
      serverCall(_controller, (c) async {
        return ServerTag.fromJson(
          asMap(await c.postJson('/tags', {'name': name, 'color': color})),
        );
      });

  @override
  Future<ServerTag> save(
    ServerTag tag, {
    String? name,
    String? color,
    String? style,
  }) => serverCall(_controller, (c) async {
    final body = <String, Object?>{
      'name': name ?? tag.name,
      'color': color ?? tag.color,
      'style': style ?? tag.style,
    };
    final w = writes;
    if (w == null) {
      return ServerTag.fromJson(
        asMap(await c.putJson('/tags/${tag.id}', body)),
      );
    }
    final r = await w.write(
      'PUT',
      '/tags/${tag.id}',
      body,
      local: () => w.patchKept('/tags', (j) {
        final m = Map<String, Object?>.from(asMap(j));
        m['tags'] = [
          for (final t in (m['tags'] as List? ?? const []))
            t is Map && t['id'] == tag.id ? {...t, ...body} : t,
        ];
        return m;
      }),
    );
    return r.sent
        ? ServerTag.fromJson(asMap(r.answer))
        : ServerTag(
            id: tag.id,
            name: body['name']! as String,
            color: body['color']! as String,
            style: body['style']! as String,
            quotes: tag.quotes,
          );
  });

  @override
  Future<void> delete(ServerTag tag) => serverCall(_controller, (c) async {
    final w = writes;
    if (w == null) {
      await c.delete('/tags/${tag.id}');
      return;
    }
    await w.write(
      'DELETE',
      '/tags/${tag.id}',
      null,
      local: () => w.patchKept('/tags', (j) {
        final m = Map<String, Object?>.from(asMap(j));
        m['tags'] = [
          for (final t in (m['tags'] as List? ?? const []))
            if (!(t is Map && t['id'] == tag.id)) t,
        ];
        return m;
      }),
    );
  });

  @override
  Future<void> merge(ServerTag keep, List<ServerTag> drop) =>
      serverCall(_controller, (c) async {
        await c.postJson('/tags/merge', {
          'keep_id': keep.id,
          'drop_ids': [for (final d in drop) d.id],
        });
      });
}

/// Gives the screens below it the [TagService], so the library can offer the Tags page without taking one.
class TagServiceScope extends InheritedWidget {
  const TagServiceScope({
    super.key,
    required this.service,
    required super.child,
  });

  final TagService? service;

  static TagService? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TagServiceScope>()?.service;

  @override
  bool updateShouldNotify(TagServiceScope old) => old.service != service;
}
