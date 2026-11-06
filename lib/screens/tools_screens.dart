import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../tools/server_tools.dart';

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
            child: const Text('Cancel'),
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
        title: const Text('Bin'),
        actions: [
          if (bin != null && bin.entries.isNotEmpty)
            IconButton(
              tooltip: 'Empty the bin',
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
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : bin == null
          ? const Center(child: CircularProgressIndicator())
          : bin.entries.isEmpty
          ? const Center(child: Text('The bin is empty.'))
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Things you delete are kept here for ${bin.keptDays} days.',
                  ),
                ),
                for (final e in bin.entries)
                  ListTile(
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
                        if (e.deletedAt.isNotEmpty) 'deleted ${e.deletedAt}',
                      ].join(' · '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Restore',
                          icon: const Icon(Icons.restore),
                          onPressed: () =>
                              _act(() => widget.tools.restore(e.id)),
                        ),
                        IconButton(
                          tooltip: 'Delete for good',
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
              ],
            ),
    );
  }
}

/// The server's numbers about the library. Needs a paired server.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.tools});

  final ServerTools tools;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  LibraryStats? _stats;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.tools.stats();
      if (mounted) {
        setState(() {
          _stats = s;
          _problem = null;
        });
      }
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    final theme = Theme.of(context);
    Widget row(String label, Object value) => ListTile(
      dense: true,
      title: Text(label),
      trailing: Text('$value', style: theme.textTheme.titleMedium),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
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
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                row('Quotes', s.quotes),
                row('Favourites', s.favourites),
                row('Books', s.books),
                row('Films', s.films),
                row('Shows', s.shows),
                if (s.games > 0) row('Games', s.games),
                row('Tags', s.tags),
                row('Anthologies', s.anthologies),
                if (s.firstSaved.isNotEmpty) row('First saved', s.firstSaved),
                if (s.busiestMonth.isNotEmpty)
                  row(
                    'Busiest month',
                    '${s.busiestMonth} (${s.busiestMonthCount})',
                  ),
                if (s.mostQuoted.isNotEmpty)
                  row(
                    'Most quoted work',
                    '${s.mostQuoted} (${s.mostQuotedCount})',
                  ),
                if (s.topTags.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('Top tags'),
                  ),
                  for (final t in s.topTags) row('#${t.name}', t.count),
                ],
              ],
            ),
    );
  }
}
