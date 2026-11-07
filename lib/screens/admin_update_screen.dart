import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin/admin_service.dart';
import '../api/server_call.dart';
import 'admin_widgets.dart';

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
      title: 'Update the server?',
      body:
          'The server pulls ${i.latest}, restarts, and is out of reach for a minute or two. Every reader is disconnected meanwhile.',
      yes: 'Update',
    );
    if (!ok || !mounted) return;
    setState(() => _applying = 'Starting the update…');
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
        if (mounted) setState(() => _applying = 'The server is restarting…');
      }
    }
    if (mounted) {
      setState(() => _applying = null);
      say(
        context,
        'The server did not come back on a new version. Check it on its own computer.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final i = _info;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server updates'),
        actions: [
          IconButton(
            tooltip: 'Check again',
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
                      i.available ? 'An update is ready' : 'Up to date',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Running: ${i.current.isEmpty ? 'unknown' : i.current}',
                    ),
                    Text(
                      'Newest on the ${i.channel == 'prerelease' ? 'pre-release' : 'stable'} line: ${i.latest.isEmpty ? 'unknown' : i.latest}',
                    ),
                    if (i.publishedAt.isNotEmpty)
                      Text('Published ${i.publishedAt.split('T').first}'),
                    const SizedBox(height: 12),
                    if (i.available && i.canSelfUpdate)
                      FilledButton.icon(
                        onPressed: _applying == null ? _apply : null,
                        icon: const Icon(Icons.system_update_alt_rounded),
                        label: Text('Update to ${i.latest}'),
                      ),
                    if (i.available &&
                        !i.canSelfUpdate &&
                        i.guidedCommand.isNotEmpty) ...[
                      const Text(
                        'This server cannot update itself. Run this on its computer:',
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
                        label: const Text('Copy the command'),
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
                    Text('Release line', style: text.titleSmall),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'stable', label: Text('Stable')),
                        ButtonSegment(
                          value: 'prerelease',
                          label: Text('Pre-release'),
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
