import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../sync/pull_sync.dart';

String _count(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

/// What a sync did, in plain words. Counts only: it never repeats what anything said.
List<String> describePull(PullResult r) {
  final lines = <String>[];
  if (r.brought == 0 &&
      r.sent == 0 &&
      r.conflicts.isEmpty &&
      r.refused.isEmpty &&
      r.stoppedBy == null) {
    lines.add('Your phone and your server already agree.');
  }
  final down = [
    if (r.worksAdded > 0) _count(r.worksAdded, 'new work'),
    if (r.quotesAdded > 0) _count(r.quotesAdded, 'new quote'),
    if (r.worksUpdated > 0) _count(r.worksUpdated, 'changed work'),
    if (r.quotesUpdated > 0) _count(r.quotesUpdated, 'changed quote'),
  ];
  if (down.isNotEmpty) lines.add('Brought down: ${down.join(', ')}.');
  final up = [
    if (r.worksSent > 0) _count(r.worksSent, 'work'),
    if (r.quotesSent > 0) _count(r.quotesSent, 'quote'),
  ];
  if (up.isNotEmpty) lines.add('Sent up your changes to ${up.join(' and ')}.');
  if (r.conflicts.isNotEmpty) {
    lines.add(
      '${_count(r.conflicts.length, 'item')} changed on both sides. Nothing was changed for ${r.conflicts.length == 1 ? 'it' : 'them'}: choose below.',
    );
  }
  if (r.skipped > 0) {
    lines.add(
      '${_count(r.skipped, 'item')} on the server could not be brought down (no words, or its work is not here).',
    );
  }
  if (r.goneOnServer > 0) {
    lines.add(
      '${_count(r.goneOnServer, 'item')} ${r.goneOnServer == 1 ? 'was' : 'were'} removed on the server while syncing, and left alone here.',
    );
  }
  if (r.deletedThere > 0) {
    lines.add(
      '${_count(r.deletedThere, 'item')} you deleted here ${r.deletedThere == 1 ? 'was' : 'were'} deleted on the server too (they are in its bin for a while).',
    );
  }
  if (r.deletedHere > 0) {
    lines.add(
      '${_count(r.deletedHere, 'item')} deleted on the server ${r.deletedHere == 1 ? 'was' : 'were'} removed here too.',
    );
  }
  if (r.relinked > 0) {
    lines.add(
      '${_count(r.relinked, 'item')} deleted on the server but changed here ${r.relinked == 1 ? 'was' : 'were'} kept, and will be sent up again.',
    );
  }
  if (r.linked > 0) {
    lines.add(
      '${_count(r.linked, 'item')} here matched ${r.linked == 1 ? 'one' : 'ones'} already on the server, so ${r.linked == 1 ? 'it was' : 'they were'} joined, not copied.',
    );
  }
  if (r.heldBack > 0) {
    lines.add(
      '${_count(r.heldBack, 'item')} are missing from the server. That is so many that nothing was removed here: check that the server is the right one and has not been restored from an old copy.',
    );
  }
  for (final x in r.refused) {
    lines.add('The server refused ${x.what}: ${x.reason}.');
  }
  switch (r.stoppedBy) {
    case null:
      break;
    case ApiFailure.network || ApiFailure.timeout:
      lines.add(
        'The server could not be reached. Nothing more was changed; try again when it answers.',
      );
    case ApiFailure.unauthorised:
      lines.add(
        'The server does not accept this phone. Pair it again in Settings.',
      );
    case ApiFailure.rateLimited:
      lines.add(
        'The server asked the app to slow down. Try again in a minute.',
      );
    case ApiFailure.forbidden:
      lines.add('This account is not allowed to do that.');
    case ApiFailure.server || ApiFailure.badResponse:
      lines.add('The server answered with an error. Try again later.');
  }
  return lines;
}

/// Syncs with the paired server and lets the reader settle each conflict: for each quote and each work that
/// changed on both sides, keep the phone's or keep the server's. Nothing is overwritten until they choose.
class PullScreen extends StatefulWidget {
  const PullScreen({super.key, required this.sync});

  final PullSync sync;

  @override
  State<PullScreen> createState() => _PullScreenState();
}

class _PullScreenState extends State<PullScreen> {
  PullResult? _result;
  bool _running = false;
  final _conflicts = <SyncConflict>[];
  final _problems = <SyncConflict, String>{};
  final _busy = <SyncConflict>{};

  Future<void> _run() async {
    setState(() {
      _running = true;
      _result = null;
      _conflicts.clear();
      _problems.clear();
    });
    final r = await widget.sync.sync();
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = r;
      _conflicts.addAll(r.conflicts);
    });
  }

  Future<void> _choose(SyncConflict c, ConflictSide side) async {
    setState(() {
      _busy.add(c);
      _problems.remove(c);
    });
    final problem = await widget.sync.resolve(c, side);
    if (!mounted) return;
    setState(() {
      _busy.remove(c);
      if (problem == null) {
        _conflicts.remove(c);
      } else {
        _problems[c] = problem;
      }
    });
  }

  Future<void> _chooseAll(ConflictSide side) async {
    final phone = side == ConflictSide.phone;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          phone ? 'Keep the phone’s for all?' : 'Keep the server’s for all?',
        ),
        content: Text(
          phone
              ? 'The server’s version of all ${_conflicts.length} will be replaced by what is on this phone.'
              : 'This phone’s version of all ${_conflicts.length} will be replaced by what is on the server.',
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
    for (final c in List.of(_conflicts)) {
      if (!mounted) return;
      await _choose(c, side);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync with server')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Brings down what is new or changed on your server, and sends up what you changed here. '
            'Deleting follows both ways: what you delete here is deleted on the server (its bin keeps it for a while), and what you delete on the server is removed here. If the same quote or work changed in both places, you choose which version to keep.',
          ),
          const SizedBox(height: 16),
          if (_running)
            const LinearProgressIndicator()
          else
            FilledButton(onPressed: _run, child: const Text('Sync now')),
          if (r != null) ...[
            const SizedBox(height: 24),
            for (final line in describePull(r))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line),
              ),
          ],
          if (_conflicts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Changed on both sides', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_conflicts.length > 1)
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
            for (final c in _conflicts)
              _ConflictCard(
                conflict: c,
                busy: _busy.contains(c),
                problem: _problems[c],
                onChoose: (side) => _choose(c, side),
              ),
          ],
        ],
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
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
