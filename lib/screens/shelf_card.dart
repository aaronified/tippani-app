import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../l10n/l10n.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../tools/work_details_source.dart';
import '../theme/tabler.dart';

/// The word the server uses for "in progress" on a work: reading a book, watching a film or show, playing a game.
String activeStatusOf(WorkKind kind) => switch (kind) {
  WorkKind.book || WorkKind.other => 'reading',
  WorkKind.game => 'playing',
  _ => 'watching',
};

/// What a shelf status is called, in the reader's language.
String shelfStatusLabel(BuildContext context, String status) =>
    switch (status) {
      'reading' => context.tr('common.shelf.reading.book.label'),
      'watching' => context.tr('common.shelf.reading.film.label'),
      'playing' => context.tr('common.shelf.playing.book.label'),
      'paused' => context.tr('common.shelf.paused.book.label'),
      'abandoned' => context.tr('common.shelf.abandoned.book.label'),
      'completed' => context.tr('common.field.finished.label'),
      _ => context.tr('app.shelf.not_started'),
    };

/// Where the reader is with a work: not started, in progress, paused, abandoned or finished, how far along, and
/// every time it was finished. The server owns the shelf (the same one the web shows), so a change goes there
/// first and the phone keeps the answer; offline, or for a work the server does not have, it is read-only.
class ShelfCard extends StatefulWidget {
  const ShelfCard({
    super.key,
    required this.work,
    required this.store,
    required this.onChanged,
  });

  final Work work;
  final LibraryStore store;

  /// Called after the phone has kept a new status, so the page can read it again.
  final VoidCallback onChanged;

  @override
  State<ShelfCard> createState() => _ShelfCardState();
}

class _ShelfCardState extends State<ShelfCard> {
  bool _busy = false;
  double? _dragging;

  WorkDetails get _d => widget.work.details;

  Future<void> _set(String status, {int progress = 0}) async {
    final source = DetailsScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (source == null || _busy) return;
    setState(() => _busy = true);
    try {
      final d = await source.setStatus(widget.work, status, progress: progress);
      if (d != null) {
        await widget.store.setWorkDetails(widget.work.id, d);
        widget.onChanged();
      }
    } on ServerException catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _dragging = null;
        });
      }
    }
  }

  String _label(String status) => shelfStatusLabel(context, status);

  String _when(ReadEntry r) {
    final from = r.startedAt;
    final to = r.finishedAt;
    final end = switch (r.outcome) {
      'abandoned' => context.tr('common.read-log.outcome.abandoned.label'),
      'open' => context.tr('app.shelf.in_progress'),
      _ => context.tr('common.read-log.outcome.finished.label'),
    };
    if (from.isEmpty && to.isEmpty) return end;
    return [
      if (from.isNotEmpty) from,
      if (to.isNotEmpty) '$end $to' else end,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final w = widget.work;
    final source = DetailsScope.of(context);
    final canSet = source != null && w.serverId != null;
    final active = activeStatusOf(w.kind);
    final status = _d.status;
    final inProgress = status == active || status == 'paused';
    final options = [active, 'paused', 'abandoned', 'completed'];
    final reads = [for (final r in _d.reads) r];
    final times = _d.timesFinished;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Ti.bookmark, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.isEmpty
                          ? context.tr('common.action.shelf.label')
                          : '${context.tr('common.action.shelf.label')} · ${_label(status)}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (status.isNotEmpty && canSet)
                    TextButton(
                      onPressed: _busy ? null : () => _set(''),
                      child: Text(
                        context.tr('common.selection.shelf.clear.label'),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final o in options)
                    ChoiceChip(
                      key: ValueKey('shelf-$o'),
                      label: Text(_label(o)),
                      selected: status == o,
                      onSelected: canSet && !_busy
                          ? (_) => _set(
                              o,
                              progress: o == 'completed' ? 100 : _d.progress,
                            )
                          : null,
                    ),
                ],
              ),
              if (inProgress) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: (_dragging ?? _d.progress).toDouble(),
                        max: 100,
                        divisions: 20,
                        label: context.tr('app.shelf.round', {
                          'round': (_dragging ?? _d.progress).round(),
                        }),
                        onChanged: canSet && !_busy
                            ? (v) => setState(() => _dragging = v)
                            : null,
                        onChangeEnd: canSet && !_busy
                            ? (v) => _set(status, progress: v.round())
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        context.tr('app.shelf.round', {
                          'round': (_dragging ?? _d.progress).round(),
                        }),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ],
              if (!canSet)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr('app.shelf.the_shelf_is_kept_on_your'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (times > 0) ...[
                const SizedBox(height: 8),
                Text(
                  times == 1
                      ? context.tr('app.shelf.finished_once')
                      : context.tr('app.shelf.finished_n_times', {'n': times}),
                  style: theme.textTheme.labelLarge,
                ),
              ],
              for (final r in reads.reversed.take(4))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _when(r),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
