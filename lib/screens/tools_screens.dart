import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../tools/server_tools.dart';
import '../l10n/l10n.dart';

export 'stats_screen.dart';

String _kindWords(String kind) => switch (kind) {
  'annotation' => 'Book quote',
  'dialogue' => 'Film or show quote',
  'quote' || 'utterance' => 'Quote',
  'book' => 'Book',
  'movie' => 'Film or show',
  _ => kind.isEmpty ? 'Item' : '${kind[0].toUpperCase()}${kind.substring(1)}',
};

/// The server's bin: what was deleted lately and can still be brought back. Needs a paired server.
class BinScreen extends StatefulWidget {
  const BinScreen({super.key, required this.tools});

  final ServerTools tools;

  @override
  State<BinScreen> createState() => _BinScreenState();
}

class _BinScreenState extends State<BinScreen> {
  Bin? _bin;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await widget.tools.bin();
      if (mounted) {
        setState(() {
          _bin = b;
          _problem = null;
        });
      }
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  void _say(String message) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _act(Future<void> Function() run) async {
    try {
      await run();
      await _load();
    } on ServerException catch (e) {
      if (mounted) _say(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bin = _bin;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Bin')),
        actions: [
          if (bin != null && bin.entries.isNotEmpty)
            IconButton(
              tooltip: context.tr('Empty the bin'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                if (await _confirm(
                  'Empty the bin?',
                  'Everything in it is deleted for good. This cannot be undone.',
                  'Empty it',
                )) {
                  await _act(widget.tools.emptyBin);
                }
              },
            ),
        ],
      ),
      body: _problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_problem!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: Text(context.tr('Try again')),
                    ),
                  ],
                ),
              ),
            )
          : bin == null
          ? const Center(child: CircularProgressIndicator())
          : bin.entries.isEmpty
          ? Center(child: Text(context.tr('The bin is empty.')))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    'Things you delete are kept here for ${bin.keptDays} days.',
                  ),
                ),
                for (final e in bin.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    child: Card(
                      child: ListTile(
                        title: Text(
                          e.label.isEmpty ? _kindWords(e.kind) : e.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            _kindWords(e.kind),
                            if (e.childCount > 0)
                              'with ${e.childCount} ${e.childCount == 1 ? 'quote' : 'quotes'}',
                            if (e.deletedAt.isNotEmpty)
                              'deleted ${e.deletedAt}',
                          ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: context.tr('Restore'),
                              icon: const Icon(Icons.restore),
                              onPressed: () =>
                                  _act(() => widget.tools.restore(e.id)),
                            ),
                            IconButton(
                              tooltip: context.tr('Delete for good'),
                              icon: const Icon(Icons.delete_forever_outlined),
                              onPressed: () async {
                                if (await _confirm(
                                  'Delete for good?',
                                  'It cannot be brought back after this.',
                                  'Delete',
                                )) {
                                  await _act(
                                    () => widget.tools.deleteForever(e.id),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
