import 'package:flutter/material.dart';

import '../account/preferences.dart';
import '../l10n/l10n.dart';

/// Saves [patch] to the account's preferences and tells the reader when the server refused it, in its words.
Future<void> savePrefs(BuildContext context, Map<String, Object?> patch) async {
  final source = PrefsScope.sourceOf(context);
  if (source == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final refusal = await source.save(patch);
  if (refusal != null) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(refusal)));
  }
}

/// A titled group of settings in a rounded card, the way Settings draws its own.
class PrefGroup extends StatelessWidget {
  const PrefGroup({super.key, this.title, this.footer, required this.children});

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 16, 8),
              child: Text(
                title!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 24, 0),
              child: Text(
                footer!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One option in [ChoiceTile].
class Choice<T> {
  const Choice(this.value, this.label, [this.hint]);

  final T value;
  final String label;
  final String? hint;
}

/// A setting with a few named values: shows the one in force, and a sheet to pick another.
class ChoiceTile<T> extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final T value;
  final List<Choice<T>> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = choices.where((c) => c.value == value).firstOrNull;
    return ListTile(
      leading: icon == null ? null : Icon(icon),
      title: Text(title),
      subtitle: Text([?current?.label, ?subtitle].join(' · ')),
      trailing: const Icon(Icons.expand_more_rounded),
      onTap: () async {
        final picked = await showModalBottomSheet<T>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (ctx) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  RadioGroup<T>(
                    groupValue: value,
                    onChanged: (v) {
                      if (v != null) Navigator.of(ctx).pop(v);
                    },
                    child: Column(
                      children: [
                        for (final c in choices)
                          RadioListTile<T>(
                            value: c.value,
                            title: Text(c.label),
                            subtitle: c.hint == null ? null : Text(c.hint!),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (picked != null && picked != value) onChanged(picked);
      },
    );
  }
}

/// A percentage dial that moves through fixed steps (75, 100, 125...).
class StepTile extends StatelessWidget {
  const StepTile({
    super.key,
    required this.title,
    this.icon,
    required this.steps,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final IconData? icon;
  final List<int> steps;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final i = steps.contains(value) ? steps.indexOf(value) : steps.indexOf(100);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon), const SizedBox(width: 16)],
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Text(
                '${steps[i]}%',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          Slider(
            value: i.toDouble(),
            min: 0,
            max: (steps.length - 1).toDouble(),
            divisions: steps.length - 1,
            label: '${steps[i]}%',
            semanticFormatterCallback: (_) => '${steps[i]}%',
            onChanged: (v) {
              final next = steps[v.round()];
              if (next != steps[i]) onChanged(next);
            },
          ),
        ],
      ),
    );
  }
}

/// A heading and body shown when something cannot be done (no server, say).
class PrefNote extends StatelessWidget {
  const PrefNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// A page of settings: the title, and the children in a list that keeps clear of the system bars.
class PrefPage extends StatelessWidget {
  const PrefPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      children: children,
    ),
  );
}

/// How a language switch reads in the pickers ("English", "বাংলা").
String languageLabel(BuildContext context, String code) {
  final l = L10nScope.of(context);
  if (code.isEmpty) return context.tr('app.prefs.the_phone_s_own_language');
  final hit = l?.choices.where((c) => c.code == code).firstOrNull;
  return hit?.name ?? code;
}

/// Asks for one line of text. The dialog owns its field, so it can close without the field being used after.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String? helper,
  int? maxLength,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(
    title: title,
    initial: initial,
    hint: hint,
    helper: helper,
    maxLength: maxLength,
  ),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    this.hint,
    this.helper,
    this.maxLength,
  });

  final String title, initial;
  final String? hint, helper;
  final int? maxLength;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      maxLength: widget.maxLength,
      decoration: InputDecoration(
        hintText: widget.hint,
        helperText: widget.helper,
      ),
      onSubmitted: (v) => Navigator.pop(context, v.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('common.action.cancel.label')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _c.text.trim()),
        child: Text(context.tr('common.action.save.label')),
      ),
    ],
  );
}
