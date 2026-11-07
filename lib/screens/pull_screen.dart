import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../sync/auto_sync.dart';
import '../sync/pull_sync.dart';
import 'conflicts_screen.dart';
import '../l10n/l10n.dart';

String _count(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';

/// What a sync did, in plain words. Counts only: it never repeats what anything said.
List<String> describePull(PullResult r) {
  final lines = <String>[];
  if (r.brought == 0 &&
      r.sent == 0 &&
      r.conflicts.isEmpty &&
      r.refused.isEmpty &&
      r.stoppedBy == null) {
    lines.add(tx('app.pull.your_phone_and_your_server_already'));
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
  if (up.isNotEmpty) {
    lines.add(
      tx('app.pull.sent_up_your_changes_to_x', {'x': up.join(' and ')}),
    );
  }
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
      lines.add(tx('app.pull.the_server_does_not_accept_this'));
    case ApiFailure.rateLimited:
      lines.add(tx('app.pull.the_server_asked_the_app_to'));
    case ApiFailure.forbidden:
      lines.add(tx('app.pull.this_account_is_not_allowed_to'));
    case ApiFailure.server || ApiFailure.badResponse:
      lines.add(tx('app.pull.the_server_answered_with_an_error'));
  }
  return lines;
}

/// The state of the sync with the paired server: whether it runs by itself, when it last finished, what it did, and
/// the way to settle conflicts (their own screen, because they can wait). The reader can also sync right now.
class PullScreen extends StatelessWidget {
  const PullScreen({super.key, required this.auto});

  final AutoSync auto;

  String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final l = t.toLocal();
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.pull.sync_with_server'))),
      body: ListenableBuilder(
        listenable: auto,
        builder: (context, _) {
          final r = auto.lastResult;
          final n = auto.conflicts.length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(context.tr('app.pull.brings_down_what_is_new_or')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('app.pull.sync_automatically')),
                subtitle: Text(
                  context.tr('app.pull.a_few_seconds_after_you_change'),
                ),
                value: auto.enabled,
                onChanged: auto.setEnabled,
              ),
              const SizedBox(height: 8),
              if (auto.syncing)
                const LinearProgressIndicator()
              else
                FilledButton(
                  onPressed: auto.syncNow,
                  child: Text(context.tr('app.pull.sync_now')),
                ),
              const SizedBox(height: 16),
              if (auto.lastSynced != null)
                Text(
                  context.tr('app.pull.last_synced_when', {
                    'when': _when(auto.lastSynced!),
                  }),
                ),
              if (n > 0) ...[
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ConflictsScreen(auto: auto),
                    ),
                  ),
                  child: Text(
                    n == 1
                        ? '1 conflict waiting: settle it'
                        : '$n conflicts waiting: settle them',
                  ),
                ),
              ],
              if (r != null) ...[
                const SizedBox(height: 16),
                for (final line in describePull(r))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(line),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
