import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../sync/auto_sync.dart';
import '../sync/pull_sync.dart';
import 'conflicts_screen.dart';
import '../l10n/l10n.dart';

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
    if (r.worksAdded > 0) countWords('new work', r.worksAdded),
    if (r.quotesAdded > 0) countWords('new quote', r.quotesAdded),
    if (r.worksUpdated > 0) countWords('changed work', r.worksUpdated),
    if (r.quotesUpdated > 0) countWords('changed quote', r.quotesUpdated),
  ];
  if (down.isNotEmpty) {
    lines.add(tx('app.pull.brought_down', {'x': down.join(', ')}));
  }
  final up = [
    if (r.worksSent > 0) countWords('work', r.worksSent),
    if (r.quotesSent > 0) countWords('quote', r.quotesSent),
  ];
  if (up.isNotEmpty) {
    lines.add(tx('app.pull.sent_up_your_changes_to_x', {'x': andList(up)}));
  }
  if (r.conflicts.isNotEmpty) {
    lines.add(trn('app.pull.conflicts', r.conflicts.length));
  }
  if (r.skipped > 0) {
    lines.add(trn('app.pull.skipped', r.skipped));
  }
  if (r.goneOnServer > 0) {
    lines.add(trn('app.pull.gone_on_server', r.goneOnServer));
  }
  if (r.deletedThere > 0) {
    lines.add(trn('app.pull.deleted_there', r.deletedThere));
  }
  if (r.deletedHere > 0) {
    lines.add(trn('app.pull.deleted_here', r.deletedHere));
  }
  if (r.relinked > 0) {
    lines.add(trn('app.pull.relinked', r.relinked));
  }
  if (r.linked > 0) {
    lines.add(trn('app.pull.linked', r.linked));
  }
  if (r.heldBack > 0) {
    lines.add(tx('app.pull.held_back', {'n': r.heldBack}));
  }
  for (final x in r.refused) {
    lines.add(tx('app.pull.refused', {'what': x.what, 'reason': x.reason}));
  }
  switch (r.stoppedBy) {
    case null:
      break;
    case ApiFailure.network || ApiFailure.timeout:
      lines.add(tx('app.pull.unreachable'));
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
