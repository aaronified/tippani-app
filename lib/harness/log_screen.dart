import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'app_log.dart';

/// Shares text through Android's share sheet. A function so a test can stand in for it.
typedef ShareText = Future<void> Function(String text, String subject);

Future<void> shareThroughSheet(String text, String subject) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}

/// The app's log, readable on the phone. A reader who has a problem can look at what the app did, copy it,
/// or send it; nothing leaves the phone unless they press Share, and the log never holds a credential or
/// anything they wrote ([AppLog]).
class LogScreen extends StatefulWidget {
  const LogScreen({
    super.key,
    required this.log,
    this.share = shareThroughSheet,
  });

  final AppLog log;
  final ShareText share;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  bool _history = false;

  String get _text => widget.log.text(includeHistory: _history);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Log copied')));
  }

  Future<void> _share() async {
    await widget.log.flush();
    await widget.share(_text, 'Tippani log');
  }

  Future<void> _clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear the log?'),
        content: const Text(
          'This empties the log on this phone, including earlier runs. Nothing else changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.log.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log'),
        actions: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: text.isEmpty ? null : _copy,
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share),
            onPressed: text.isEmpty ? null : _share,
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('Include earlier runs'),
            value: _history,
            onChanged: (v) => setState(() => _history = v),
          ),
          const Divider(height: 1),
          Expanded(
            child: text.isEmpty
                ? const Center(child: Text('The log is empty.'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      text,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
