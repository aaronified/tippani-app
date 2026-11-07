import 'package:flutter/material.dart';

import '../sync/auto_sync.dart';
import 'library_widgets.dart' show EmptyState;
import '../sync/pull_sync.dart';
import '../l10n/l10n.dart';

/// What changed on both the phone and the server, waiting for the reader. Nothing here is urgent and nothing has
/// been overwritten: they settle one, several or none, whenever they like, and the next sync keeps the rest here.
class ConflictsScreen extends StatefulWidget {
  const ConflictsScreen({super.key, required this.auto});

  final AutoSync auto;

  @override
  State<ConflictsScreen> createState() => _ConflictsScreenState();
}

class _ConflictsScreenState extends State<ConflictsScreen> {
  final _problems = <SyncConflict, String>{};
  final _busy = <SyncConflict>{};

  Future<void> _choose(SyncConflict c, ConflictSide side) async {
    setState(() {
      _busy.add(c);
      _problems.remove(c);
    });
    final problem = await widget.auto.resolve(c, side);
    if (!mounted) return;
    setState(() {
      _busy.remove(c);
      if (problem != null) _problems[c] = problem;
    });
  }

  Future<void> _chooseAll(ConflictSide side) async {
    final phone = side == ConflictSide.phone;
    final n = widget.auto.conflicts.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          phone
              ? context.tr('app.conflicts.keep_the_phone_s_for_all_2')
              : context.tr('app.conflicts.keep_the_server_s_for_all_2'),
        ),
        content: Text(
          phone
              ? context.tr('app.conflicts.the_server_s_version_of_all', {
                  'n': n,
                })
              : context.tr('app.conflicts.this_phone_s_version_of_all', {
                  'n': n,
                }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              phone
                  ? context.tr('app.conflicts.keep_the_phone_s')
                  : context.tr('app.conflicts.keep_the_server_s'),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final c in widget.auto.conflicts) {
      if (!mounted) return;
      await _choose(c, side);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.conflicts.sync_conflicts'))),
      body: ListenableBuilder(
        listenable: widget.auto,
        builder: (context, _) {
          final conflicts = widget.auto.conflicts;
          if (conflicts.isEmpty) {
            return EmptyState(
              icon: Icons.task_alt_rounded,
              title: context.tr('app.conflicts.nothing_to_settle'),
              hint: context.tr('app.conflicts.if_the_same_quote_or_work'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                context.tr('app.conflicts.changed_on_both_sides'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('app.conflicts.no_hurry_nothing_has_been_changed'),
              ),
              const SizedBox(height: 8),
              if (conflicts.length > 1)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _chooseAll(ConflictSide.phone),
                      child: Text(
                        context.tr('app.conflicts.keep_the_phone_s_for_all'),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _chooseAll(ConflictSide.server),
                      child: Text(
                        context.tr('app.conflicts.keep_the_server_s_for_all'),
                      ),
                    ),
                  ],
                ),
              for (final c in conflicts)
                ConflictCard(
                  conflict: c,
                  busy: _busy.contains(c),
                  problem: _problems[c],
                  onChoose: (side) => _choose(c, side),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ConflictCard extends StatelessWidget {
  const ConflictCard({
    super.key,
    required this.conflict,
    required this.busy,
    required this.problem,
    required this.onChoose,
  });

  final SyncConflict conflict;
  final bool busy;
  final String? problem;
  final void Function(ConflictSide) onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conflict.isWork
                  ? context.tr('anthologies.group.work')
                  : context.tr('common.field.quote.label'),
              style: theme.textTheme.labelMedium,
            ),
            Text(conflict.title, style: theme.textTheme.titleSmall),
            for (final d in conflict.diffs) ...[
              const SizedBox(height: 10),
              Text(d.label, style: theme.textTheme.labelLarge),
              Text(context.tr('app.conflicts.phone_value', {'value': d.phone})),
              Text(
                context.tr('app.conflicts.server_value', {'value': d.server}),
              ),
            ],
            if (problem != null) ...[
              const SizedBox(height: 8),
              Text(problem!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 12),
            if (busy)
              const LinearProgressIndicator()
            else
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => onChoose(ConflictSide.phone),
                    child: Text(context.tr('app.conflicts.keep_the_phone_s')),
                  ),
                  FilledButton.tonal(
                    onPressed: () => onChoose(ConflictSide.server),
                    child: Text(context.tr('app.conflicts.keep_the_server_s')),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
