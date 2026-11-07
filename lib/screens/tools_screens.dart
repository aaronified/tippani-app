import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../tools/server_tools.dart';
import '../l10n/l10n.dart';

export 'stats_screen.dart';

String _kindWords(String kind) => switch (kind) {
  'annotation' => tx('app.checks_tabs.book_quote'),
  'dialogue' => tx('app.checks_tabs.film_or_show_quote'),
  'quote' || 'utterance' => 'Quote',
  'book' => 'Book',
  'movie' => tx('bin.kind.movie.label'),
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
            child: Text(context.tr('common.action.cancel.label')),
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
        title: Text(context.tr('bin.title')),
        actions: [
          if (bin != null && bin.entries.isNotEmpty)
            IconButton(
              tooltip: context.tr('app.tools.empty_the_bin'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                if (await _confirm(
                  context.tr('bin.confirm.title'),
                  context.tr('app.tools.everything_in_it_is_deleted_for'),
                  context.tr('bin.confirm.label'),
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
                      child: Text(context.tr('common.source.retry')),
                    ),
                  ],
                ),
              ),
            )
          : bin == null
          ? const Center(child: CircularProgressIndicator())
          : bin.entries.isEmpty
          ? Center(child: Text(context.tr('app.tools.the_bin_is_empty')))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    context.tr('app.tools.things_you_delete_are_kept_here', {
                      'kept_days': bin.keptDays,
                    }),
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
                              tooltip: context.tr(
                                'common.action.restore.label',
                              ),
                              icon: const Icon(Icons.restore),
                              onPressed: () =>
                                  _act(() => widget.tools.restore(e.id)),
                            ),
                            IconButton(
                              tooltip: context.tr('app.tools.delete_for_good'),
                              icon: const Icon(Icons.delete_forever_outlined),
                              onPressed: () async {
                                if (await _confirm(
                                  context.tr('app.tools.delete_for_good_2'),
                                  context.tr(
                                    'app.tools.it_cannot_be_brought_back_after',
                                  ),
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
