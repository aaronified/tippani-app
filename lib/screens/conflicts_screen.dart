import 'package:flutter/material.dart';

import '../sync/auto_sync.dart';
import 'library_widgets.dart' show EmptyState;
import '../sync/pull_sync.dart';

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
          phone ? 'Keep the phone’s for all?' : 'Keep the server’s for all?',
        ),
        content: Text(
          phone
              ? 'The server’s version of all $n will be replaced by what is on this phone.'
              : 'This phone’s version of all $n will be replaced by what is on the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(phone ? 'Keep the phone’s' : 'Keep the server’s'),
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
      appBar: AppBar(title: const Text('Sync conflicts')),
      body: ListenableBuilder(
        listenable: widget.auto,
        builder: (context, _) {
          final conflicts = widget.auto.conflicts;
          if (conflicts.isEmpty) {
            return const EmptyState(
              icon: Icons.task_alt_rounded,
              title: 'Nothing to settle.',
              hint: 'If the same quote or work is changed here and on the server, it will wait here for you.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Changed on both sides', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'No hurry: nothing has been changed on either side, and what you leave here stays until you choose. For each, keep the version on the phone or the one on the server.',
              ),
              const SizedBox(height: 8),
              if (conflicts.length > 1)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _chooseAll(ConflictSide.phone),
                      child: const Text('Keep the phone’s for all'),
                    ),
                    OutlinedButton(
                      onPressed: () => _chooseAll(ConflictSide.server),
                      child: const Text('Keep the server’s for all'),
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
              conflict.isWork ? 'Work' : 'Quote',
              style: theme.textTheme.labelMedium,
            ),
            Text(conflict.title, style: theme.textTheme.titleSmall),
            for (final d in conflict.diffs) ...[
              const SizedBox(height: 10),
              Text(d.label, style: theme.textTheme.labelLarge),
              Text('Phone: ${d.phone}'),
              Text('Server: ${d.server}'),
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
                    child: const Text('Keep the phone’s'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => onChoose(ConflictSide.server),
                    child: const Text('Keep the server’s'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
