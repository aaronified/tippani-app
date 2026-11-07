import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../sync/push_sync.dart';
import '../l10n/l10n.dart';

/// What a push did, in plain words, for the screen. Counts and the phone's own item numbers only: it never
/// repeats what anything said.
List<String> describePush(PushResult r) {
  final lines = <String>[];
  if (r.sent == 0 &&
      r.alreadyThere == 0 &&
      r.stoppedBy == null &&
      r.refused.isEmpty) {
    return [tx('app.sync.everything_is_already_there')];
  }
  if (r.sent > 0 || r.alreadyThere > 0) {
    final parts = <String>[
      if (r.worksSent > 0) countWords('work', r.worksSent),
      if (r.quotesSent > 0) countWords('quote', r.quotesSent),
    ];
    if (parts.isNotEmpty) {
      lines.add(tx('app.sync.sent_x_to_your_server', {'x': andList(parts)}));
    }
    if (r.alreadyThere > 0) {
      lines.add(trn('app.sync.already_there', r.alreadyThere));
    }
  }
  switch (r.stoppedBy) {
    case null:
      break;
    case ApiFailure.network || ApiFailure.timeout:
      lines.add(tx('app.sync.unreachable'));
    case ApiFailure.unauthorised:
      lines.add(tx('app.sync.the_server_does_not_accept_this'));
    case ApiFailure.rateLimited:
      lines.add(tx('app.pull.the_server_asked_the_app_to'));
    case ApiFailure.forbidden:
      lines.add(tx('app.sync.this_account_is_not_allowed_to'));
    case ApiFailure.server || ApiFailure.badResponse:
      lines.add(tx('app.sync.the_server_answered_with_an_error'));
  }
  if (r.waiting > 0) {
    lines.add(trn('app.sync.waiting', r.waiting));
  }
  for (final x in r.refused) {
    lines.add(tx('app.pull.refused', {'what': x.what, 'reason': x.reason}));
  }
  return lines;
}

/// Sends the library to the paired server, once. It only adds: nothing on the server is changed or removed.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.sync});

  final PushSync sync;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  ({int works, int quotes})? _pending;
  PushResult? _result;
  bool _running = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final p = await widget.sync.pending();
    if (mounted) setState(() => _pending = p);
  }

  Future<void> _send() async {
    setState(() {
      _running = true;
      _result = null;
      _done = 0;
      _total = 0;
    });
    final r = await widget.sync.push(
      onProgress: (d, t) {
        if (mounted) {
          setState(() {
            _done = d;
            _total = t;
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = r;
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pending;
    final nothing = p != null && p.works == 0 && p.quotes == 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.settings.send_library_to_server')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.tr('app.sync.sends_the_works_and_quotes_that')),
          const SizedBox(height: 16),
          if (p == null)
            const LinearProgressIndicator()
          else
            Text(
              nothing
                  ? context.tr('app.sync.nothing_is_waiting')
                  : tx('app.sync.waiting_to_be_sent', {
                      'works': countWords('work', p.works),
                      'quotes': countWords('quote', p.quotes),
                    }),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          const SizedBox(height: 16),
          if (_running) ...[
            LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
            const SizedBox(height: 8),
            Text(_total == 0 ? 'Starting…' : 'Sent $_done of $_total'),
          ] else
            FilledButton(
              onPressed: p == null || nothing ? null : _send,
              child: Text(context.tr('app.sync.send_to_server')),
            ),
          if (_result != null) ...[
            const SizedBox(height: 24),
            for (final line in describePush(_result!))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line),
              ),
          ],
        ],
      ),
    );
  }
}
