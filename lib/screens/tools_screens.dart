import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../tools/server_tools.dart';
import '../l10n/l10n.dart';

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
    final scheme = theme.colorScheme;
    Widget row(String label, Object value) => ListTile(
      dense: true,
      title: Text(label),
      trailing: Text('$value', style: theme.textTheme.titleMedium),
    );
    Widget big(String label, Object value) => Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Statistics'))),
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
          : s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.1,
                  children: [
                    big('Quotes', s.quotes),
                    big('Favourites', s.favourites),
                    big('Books', s.books),
                    big('Films', s.films),
                    big('Shows', s.shows),
                    if (s.games > 0) big('Games', s.games),
                    big('Tags', s.tags),
                    big('Anthologies', s.anthologies),
                  ],
                ),
                if (s.firstSaved.isNotEmpty ||
                    s.busiestMonth.isNotEmpty ||
                    s.mostQuoted.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: [
                        if (s.firstSaved.isNotEmpty)
                          row('First saved', s.firstSaved),
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
                      ],
                    ),
                  ),
                ],
                if (s.topTags.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                    child: Text(
                      context.tr('Top tags'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Card(
                    child: Column(
                      children: [
                        for (final t in s.topTags) row('#${t.name}', t.count),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
