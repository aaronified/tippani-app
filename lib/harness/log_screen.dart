import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'app_log.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr('app.log.log_copied'))));
  }

  Future<void> _share() async {
    await widget.log.flush();
    await widget.share(_text, 'Tippani log');
  }

  Future<void> _clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('app.log.clear_the_log')),
        content: Text(context.tr('app.log.this_empties_the_log_on_this')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('common.selection.shelf.clear.label')),
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
        title: Text(context.tr('app.log.log')),
        actions: [
          IconButton(
            tooltip: context.tr('common.action.copy.label'),
            icon: const Icon(Ti.copy),
            onPressed: text.isEmpty ? null : _copy,
          ),
          IconButton(
            tooltip: context.tr('common.action.share.label'),
            icon: const Icon(Ti.share),
            onPressed: text.isEmpty ? null : _share,
          ),
          IconButton(
            tooltip: context.tr('common.selection.shelf.clear.label'),
            icon: const Icon(Ti.trash),
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: Text(context.tr('app.log.include_earlier_runs')),
            value: _history,
            onChanged: (v) => setState(() => _history = v),
          ),
          const Divider(height: 1),
          Expanded(
            child: text.isEmpty
                ? Center(child: Text(context.tr('app.log.the_log_is_empty')))
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
