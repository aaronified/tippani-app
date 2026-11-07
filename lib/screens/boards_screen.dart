import 'package:flutter/material.dart';

import '../library/library_store.dart';
import '../library/models.dart';
import 'quote_form_screen.dart' show quoteColour;

/// Your boards: shelves for standalone quotes, to file them on and to group and filter the library by. A board is
/// made, renamed, given a colour or deleted here; deleting one keeps its quotes, which are then on no board.
class BoardsScreen extends StatefulWidget {
  const BoardsScreen({super.key, required this.store});

  final LibraryStore store;

  @override
  State<BoardsScreen> createState() => _BoardsScreenState();
}

class _BoardsScreenState extends State<BoardsScreen> {
  List<Board>? _boards;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await widget.store.boards();
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
    }
  }

  String _sentence(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}.';

  Future<void> _edit({Board? board}) async {
    final name = TextEditingController(text: board?.name ?? '');
    var colour = board?.color ?? '';
    final done = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(board == null ? 'New board' : 'Edit board'),
          content: Column(
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
            ],
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
      } else {
        if (name.text.trim() != board.name) {
          await widget.store.renameBoard(board.id, name.text);
        }
        if (colour != board.color) {
          await widget.store.recolourBoard(board.id, colour);
        }
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

  @override
  Widget build(BuildContext context) {
    final boards = _boards;
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
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              children: [
                for (final b in boards)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    child: Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: b.color.isEmpty
                              ? Theme.of(context).colorScheme.outlineVariant
                              : quoteColour(b.color),
                        ),
                        title: Text(b.name),
                        subtitle: Text(
                          '${b.quotes} ${b.quotes == 1 ? 'quote' : 'quotes'}',
                        ),
                        onTap: () => _edit(board: b),
                        trailing: IconButton(
                          tooltip: 'Delete board',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(b),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
