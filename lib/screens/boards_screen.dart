import 'dart:io';

import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../boards/board_service.dart';
import '../capture/photo_source.dart';
import '../harness/harness.dart' show BackupPicker;
import '../library/cover_cache.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../sync/auto_sync.dart';
import 'board_screen.dart';
import 'quote_form_screen.dart' show quoteColour;

/// The picture of a board, or [fallback] while there is none (and while it loads).
class BoardPicture extends StatelessWidget {
  const BoardPicture({
    super.key,
    required this.name,
    required this.width,
    required this.height,
    required this.fallback,
  });

  final String name;
  final double width, height;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final source = CoverScope.of(context);
    if (name.isEmpty || source == null) return fallback;
    return FutureBuilder<File?>(
      future: source.fileFor(name),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) return fallback;
        return Image.file(
          f,
          width: width,
          height: height,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback,
        );
      },
    );
  }
}

/// Your boards: shelves for standalone quotes, to file them on and to group and filter the library by. A board is
/// made, renamed, given a colour, a description, a kind and a picture, hidden, put in order or deleted here; deleting
/// one keeps its quotes, which are then on no board. What only the server keeps (description, kind, picture, order,
/// hidden) needs the board to be on the server, which a sync does.
class BoardsScreen extends StatefulWidget {
  const BoardsScreen({
    super.key,
    required this.store,
    this.picker,
    this.anthologies,
    this.auto,
    this.photos,
  });

  final LibraryStore store;
  final BackupPicker? picker;
  final AnthologyService? anthologies;
  final AutoSync? auto;
  final PhotoSource? photos;

  @override
  State<BoardsScreen> createState() => _BoardsScreenState();
}

class _BoardsScreenState extends State<BoardsScreen> {
  List<Board>? _boards;

  BoardService? get _service {
    final s = BoardScope.of(context);
    return s != null && s.available ? s : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await widget.store.boards();
    // the reader's order, then the rest by name; a board with no place yet goes last
    b.sort((x, y) {
      final p = (x.pos ?? 1 << 30).compareTo(y.pos ?? 1 << 30);
      return p != 0 ? p : x.name.toLowerCase().compareTo(y.name.toLowerCase());
    });
    if (mounted) setState(() => _boards = b);
  }

  void _say(String message) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _guard(Future<void> Function() run) async {
    try {
      await run();
      await _load();
    } on LibraryException catch (e) {
      if (mounted) _say(_sentence(e.message));
    } on BoardException catch (e) {
      if (mounted) _say(e.message);
    }
  }

  String _sentence(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}.';

  Future<void> _edit({Board? board}) async {
    final service = _service;
    final onServer = board?.serverId != null && service != null;
    final name = TextEditingController(text: board?.name ?? '');
    final description = TextEditingController(text: board?.description ?? '');
    final languages = TextEditingController(
      text: board?.languages.join(', ') ?? '',
    );
    var colour = board?.color ?? '';
    var kind = board?.kind ?? 'plain';
    final done = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(board == null ? 'New board' : 'Edit board'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                if (onServer) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'What it is for',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Colour'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('None'),
                      selected: colour.isEmpty,
                      onSelected: (_) => setState(() => colour = ''),
                    ),
                    for (final c in quoteColors)
                      ChoiceChip(
                        label: const SizedBox(width: 4),
                        avatar: CircleAvatar(
                          radius: 9,
                          backgroundColor: quoteColour(c),
                        ),
                        tooltip: c,
                        selected: colour == c,
                        onSelected: (_) => setState(() => colour = c),
                      ),
                  ],
                ),
                if (onServer) ...[
                  const SizedBox(height: 16),
                  const Text('Kind'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (k, label) in boardKinds)
                        ChoiceChip(
                          label: Text(label),
                          selected: kind == k,
                          onSelected: (_) => setState(() => kind = k),
                        ),
                    ],
                  ),
                  if (kind == 'proverb') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: languages,
                      decoration: const InputDecoration(
                        labelText: 'Languages',
                        helperText: 'Separate with commas: Bengali, Hindi',
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (done != true) return;
    await _guard(() async {
      if (board == null) {
        await widget.store.addBoard(name.text, color: colour);
        return;
      }
      if (name.text.trim() != board.name) {
        await widget.store.renameBoard(board.id, name.text);
      }
      if (colour != board.color) {
        await widget.store.recolourBoard(board.id, colour);
      }
      if (onServer) {
        final langs = kind == 'proverb'
            ? [
                for (final l in languages.text.split(RegExp(r'[,;]')))
                  if (l.trim().isNotEmpty) l.trim(),
              ]
            : <String>[];
        final changes = <String, Object?>{
          if (description.text.trim() != board.description)
            'description': description.text.trim(),
          if (kind != board.kind) 'kind': kind,
          if (kind != board.kind ||
              langs.join('|') != board.languages.join('|'))
            'languages': langs,
        };
        if (changes.isNotEmpty) await service.update(board, changes);
      }
    });
  }

  Future<void> _delete(Board b) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${b.name}?'),
        content: Text(
          b.quotes == 0
              ? 'The board is removed.'
              : 'The board is removed. Its ${b.quotes} ${b.quotes == 1 ? 'quote stays' : 'quotes stay'} in your library, on no board.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure == true) await _guard(() => widget.store.deleteBoard(b.id));
  }

  Future<void> _setPicture(Board b) async {
    final service = _service!;
    final path = await (widget.photos ?? DevicePhotos()).choose();
    if (path == null) return;
    await _guard(() async {
      final bytes = await File(path).readAsBytes();
      await service.setImage(b, bytes, path.split(RegExp(r'[\\/]')).last);
    });
  }

  /// Puts the boards in the order [boards] has, sending each changed place to the server.
  Future<void> _place(List<Board> boards) async {
    final service = _service;
    if (service == null) return;
    await _guard(() async {
      for (var i = 0; i < boards.length; i++) {
        final b = boards[i];
        if (b.serverId != null && b.pos != i) {
          await service.update(b, {'pos': i});
        }
      }
    });
  }

  Future<void> _move(Board b, int by) async {
    final all = [..._boards!];
    final i = all.indexWhere((x) => x.id == b.id);
    final j = i + by;
    if (j < 0 || j >= all.length) return;
    all.insert(j, all.removeAt(i));
    await _place(all);
  }

  Future<void> _starters(Board b) async {
    final service = _service!;
    try {
      final offers = await service.starters();
      if (!mounted) return;
      if (offers.isEmpty) {
        _say('The server has no starter proverbs.');
        return;
      }
      final wanted = b.languages.map((l) => l.toLowerCase()).toSet();
      final lang = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Add starter proverbs'),
          children: [
            for (final o in offers)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(o.language),
                child: Text(
                  '${o.language} (${o.count})${wanted.contains(o.language.toLowerCase()) ? ' · this board' : ''}',
                ),
              ),
          ],
        ),
      );
      if (lang == null) return;
      final n = await service.addStarters(b, lang);
      if (!mounted) return;
      _say(
        n == 0
            ? 'Those proverbs are already there.'
            : 'Added $n ${n == 1 ? 'proverb' : 'proverbs'} on the server. Syncing now.',
      );
      await widget.auto?.syncNow();
      await _load();
    } on BoardException catch (e) {
      if (mounted) _say(e.message);
    }
  }

  Future<void> _open(Board b) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BoardScreen(
          store: widget.store,
          boardId: b.id,
          picker: widget.picker,
          anthologies: widget.anthologies,
        ),
      ),
    );
    await _load();
  }

  Widget _card(BuildContext context, List<Board> boards, int i) {
    final b = boards[i];
    final service = _service;
    final onServer = b.serverId != null && service != null;
    final scheme = Theme.of(context).colorScheme;
    final dot = CircleAvatar(
      radius: 12,
      backgroundColor: b.color.isEmpty
          ? scheme.outlineVariant
          : quoteColour(b.color),
    );
    final facts = [
      '${b.quotes} ${b.quotes == 1 ? 'quote' : 'quotes'}',
      if (b.kind != 'plain') boardKindLabel(b.kind),
      if (b.hidden) 'Hidden',
    ].join(' · ');
    return Padding(
      key: ValueKey('board-${b.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
          leading: b.imagePath.isEmpty
              ? dot
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: BoardPicture(
                    name: b.imagePath,
                    width: 44,
                    height: 44,
                    fallback: dot,
                  ),
                ),
          title: Text(
            b.name,
            style: b.hidden ? TextStyle(color: scheme.onSurfaceVariant) : null,
          ),
          subtitle: Text(
            b.description.isEmpty ? facts : '$facts\n${b.description}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _open(b),
          trailing: PopupMenuButton<String>(
            tooltip: 'More for ${b.name}',
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  await _edit(board: b);
                case 'picture':
                  await _setPicture(b);
                case 'nopicture':
                  await _guard(() => service!.removeImage(b));
                case 'hide':
                  await _guard(() => service!.update(b, {'hidden': !b.hidden}));
                case 'up':
                  await _move(b, -1);
                case 'down':
                  await _move(b, 1);
                case 'starters':
                  await _starters(b);
                case 'delete':
                  await _delete(b);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (onServer) ...[
                PopupMenuItem(
                  value: 'picture',
                  child: Text(
                    b.imagePath.isEmpty ? 'Add a picture' : 'Change picture',
                  ),
                ),
                if (b.imagePath.isNotEmpty)
                  const PopupMenuItem(
                    value: 'nopicture',
                    child: Text('Remove picture'),
                  ),
                PopupMenuItem(
                  value: 'hide',
                  child: Text(b.hidden ? 'Show' : 'Hide'),
                ),
                if (i > 0)
                  const PopupMenuItem(value: 'up', child: Text('Move up')),
                if (i < boards.length - 1)
                  const PopupMenuItem(value: 'down', child: Text('Move down')),
                if (b.kind == 'proverb')
                  const PopupMenuItem(
                    value: 'starters',
                    child: Text('Add starter proverbs'),
                  ),
              ],
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boards = _boards;
    final canOrder = _service != null && (boards?.length ?? 0) > 1;
    return Scaffold(
      appBar: AppBar(title: const Text('Boards')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('New board'),
      ),
      body: boards == null
          ? const Center(child: CircularProgressIndicator())
          : boards.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No boards yet. A board is a shelf for standalone quotes: make one, then file quotes on it from the quote form.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : canOrder
          ? ReorderableListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              itemCount: boards.length,
              onReorderItem: (from, to) {
                final all = [...boards];
                all.insert(to, all.removeAt(from));
                _place(all);
              },
              itemBuilder: (context, i) => _card(context, boards, i),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              children: [
                for (var i = 0; i < boards.length; i++)
                  _card(context, boards, i),
              ],
            ),
    );
  }
}
