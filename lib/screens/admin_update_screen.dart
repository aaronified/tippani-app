import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin/admin_service.dart';
import '../api/server_call.dart';
import 'admin_widgets.dart';
import '../l10n/l10n.dart';

/// The server's own version: what it runs, what is newest on the release line it follows (stable or pre-release),
/// and, where the server can update itself, a button that does it. Where it cannot, the command to run on the
/// server's computer is shown to copy.
class AdminUpdateScreen extends StatefulWidget {
  const AdminUpdateScreen({
    super.key,
    required this.service,
    this.pollEvery = const Duration(seconds: 3),
  });

  final AdminService service;
  final Duration pollEvery;

  @override
  State<AdminUpdateScreen> createState() => _AdminUpdateScreenState();
}

class _AdminUpdateScreenState extends State<AdminUpdateScreen> {
  UpdateInfo? _info;
  String? _problem;
  bool _busy = false;
  String? _applying;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final i = await widget.service.updateCheck();
      if (mounted) setState(() => _info = i);
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _channel(String channel) async {
    setState(() => _busy = true);
    try {
      final i = await widget.service.setChannel(channel);
      if (mounted) setState(() => _info = i);
    } on ServerException catch (e) {
      if (mounted) say(context, e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _apply() async {
    final i = _info;
    if (i == null) return;
    final ok = await confirmDialog(
      context,
      title: context.tr('app.admin_update.update_the_server'),
      body:
          'The server pulls ${i.latest}, restarts, and is out of reach for a minute or two. Every reader is disconnected meanwhile.',
      yes: 'Update',
    );
    if (!ok || !mounted) return;
    setState(
      () => _applying = context.tr('app.admin_update.starting_the_update'),
    );
    try {
      // the answer to the apply rarely arrives (the server restarts under it), so a lost one is not a refusal
      await widget.service.applyUpdate().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // carry on: the state below says what really happened
    } on ServerException catch (e) {
      if (e.message != 'The server could not be reached.' &&
          e.message != 'The server took too long to answer.') {
        if (mounted) {
          setState(() => _applying = null);
          say(context, e.message);
        }
        return;
      }
    }
    for (var n = 0; n < 100 && mounted; n++) {
      await Future<void>.delayed(widget.pollEvery);
      try {
        final now = await widget.service.updateCheck();
        if (now.current != i.current && now.current.isNotEmpty) {
          if (mounted) {
            setState(() {
              _info = now;
              _applying = null;
            });
            say(context, 'The server now runs ${now.current}.');
          }
          return;
        }
        final phase = await widget.service.updatePhase();
        if (mounted && phase.isNotEmpty) {
          setState(() => _applying = 'Updating… ($phase)');
        }
      } on ServerException {
        if (mounted) {
          setState(
            () => _applying = context.tr(
              'app.admin_update.the_server_is_restarting',
            ),
          );
        }
      }
    }
    if (mounted) {
      setState(() => _applying = null);
      say(context, context.tr('app.admin_update.the_server_did_not_come_back'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final i = _info;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.admin_update.server_updates')),
        actions: [
          IconButton(
            tooltip: context.tr('app.admin_update.check_again'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _busy || _applying != null ? null : _check,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy || _applying != null) const LinearProgressIndicator(),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_problem!, style: TextStyle(color: scheme.error)),
            ),
          if (_applying != null)
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_applying!, style: text.titleSmall),
              ),
            ),
          if (i != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.available
                          ? context.tr('app.admin_update.an_update_is_ready')
                          : context.tr('app.admin_update.up_to_date'),
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('app.admin_update.running_current', {
                        'current': i.current.isEmpty ? 'unknown' : i.current,
                      }),
                    ),
                    Text(
                      context.tr(
                        'app.admin_update.newest_on_the_x_line_latest',
                        {
                          'x': i.channel == 'prerelease'
                              ? 'pre-release'
                              : 'stable',
                          'latest': i.latest.isEmpty ? 'unknown' : i.latest,
                        },
                      ),
                    ),
                    if (i.publishedAt.isNotEmpty)
                      Text(
                        context.tr('app.admin_update.published_first', {
                          'first': i.publishedAt.split('T').first,
                        }),
                      ),
                    const SizedBox(height: 12),
                    if (i.available && i.canSelfUpdate)
                      FilledButton.icon(
                        onPressed: _applying == null ? _apply : null,
                        icon: const Icon(Icons.system_update_alt_rounded),
                        label: Text(
                          context.tr('app.admin_update.update_to_latest', {
                            'latest': i.latest,
                          }),
                        ),
                      ),
                    if (i.available &&
                        !i.canSelfUpdate &&
                        i.guidedCommand.isNotEmpty) ...[
                      Text(
                        context.tr(
                          'app.admin_update.this_server_cannot_update_itself_run',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          i.guidedCommand,
                          style: const TextStyle(
                            fontFamily: 'IBMPlexMono',
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: i.guidedCommand),
                          );
                          if (context.mounted) say(context, 'Copied');
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: Text(
                          context.tr('app.admin_update.copy_the_command'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('app.admin_update.release_line'),
                      style: text.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'stable',
                          label: Text(context.tr('app.admin_update.stable')),
                        ),
                        ButtonSegment(
                          value: 'prerelease',
                          label: Text(
                            context.tr('app.admin_update.pre_release'),
                          ),
                        ),
                      ],
                      selected: {i.channel},
                      showSelectedIcon: false,
                      onSelectionChanged: _busy || _applying != null
                          ? null
                          : (s) => _channel(s.single),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
