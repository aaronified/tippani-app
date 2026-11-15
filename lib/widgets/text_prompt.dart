import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Asks for one line of text in a small dialog. Returns what was typed (trimmed), or null when it was cancelled;
/// the action is not offered while the field is empty.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  TextInputType? keyboard,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPrompt(
    title: title,
    label: label,
    action: action,
    keyboard: keyboard,
  ),
);

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.label,
    required this.action,
    this.keyboard,
  });

  final String title, label, action;
  final TextInputType? keyboard;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: widget.keyboard,
        textCapitalization: TextCapitalization.none,
        decoration: InputDecoration(labelText: widget.label),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.action.cancel.label')),
        ),
        FilledButton(
          onPressed: _text.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_text.text.trim()),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
