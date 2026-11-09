import 'package:flutter/material.dart';

import '../library/library_store.dart';
import '../api/server_call.dart';
import '../library/models.dart';
import '../library/suggestions.dart';
import '../people/people_directory.dart';
import '../widgets/combo_field.dart';
import '../tools/work_lookup.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

String workKindLabel(WorkKind k) => switch (k) {
  WorkKind.book => 'Book',
  WorkKind.film => 'Film',
  WorkKind.show => 'Show',
  WorkKind.game => 'Game',
  WorkKind.other => 'Other',
};

/// What the creator of a kind of work is called: whoever the reader would name.
String creatorLabel(WorkKind k) => switch (k) {
  WorkKind.book => 'Author',
  WorkKind.film => 'Director',
  WorkKind.show => 'Creator',
  WorkKind.game => 'Studio',
  WorkKind.other => 'Creator',
};

/// Adds a work, or changes one. Pops the saved [Work].
class WorkFormScreen extends StatefulWidget {
  const WorkFormScreen({
    super.key,
    required this.store,
    this.work,
    this.lookup,
    this.initialKind = WorkKind.book,
  });

  /// The kind a new work starts as (a film when it is added from the Catalogue).
  final WorkKind initialKind;

  final LibraryStore store;
  final Work? work;

  /// Finds details through the paired server; null (or not available) hides Look up details.
  final WorkLookup? lookup;

  @override
  State<WorkFormScreen> createState() => _WorkFormScreenState();
}

class _WorkFormScreenState extends State<WorkFormScreen> {
  late final _title = TextEditingController(text: widget.work?.title);
  late final _creator = TextEditingController(text: widget.work?.creator);
  late final _year = TextEditingController(
    text: widget.work?.year?.toString() ?? '',
  );
  late final _language = TextEditingController(text: widget.work?.language);
  late WorkKind _kind = widget.work?.kind ?? widget.initialKind;
  String? _error;
  bool _saving = false;
  bool _looking = false;
  List<Work> _all = const [];

  @override
  void initState() {
    super.initState();
    widget.store.works().then((ws) {
      if (mounted) setState(() => _all = ws);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _creator.dispose();
    _year.dispose();
    _language.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(
        () => _error = context.tr('app.work_form.type_a_title_to_look_up'),
      );
      return;
    }
    setState(() {
      _looking = true;
      _error = null;
    });
    List<WorkMatch> found = const [];
    try {
      found = await widget.lookup!.find(_kind, title, creator: _creator.text);
    } on ServerException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (!mounted) return;
    setState(() => _looking = false);
    if (found.isEmpty) {
      if (_error == null) {
        setState(
          () => _error = context.tr('app.work_form.nothing_matched_that_title'),
        );
      }
      return;
    }
    final chosen = await showDialog<WorkMatch>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.tr('app.work_form.which_one')),
        children: [
          for (final m in found.take(8))
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(m),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m.title),
                subtitle: m.summary.isEmpty ? null : Text(m.summary),
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _title.text = chosen.title;
      if (chosen.creator.isNotEmpty) _creator.text = chosen.creator;
      if (chosen.year != null) _year.text = '${chosen.year}';
    });
  }

  Future<void> _save() async {
    final yearText = _year.text.trim();
    final year = yearText.isEmpty ? null : int.tryParse(yearText);
    if (yearText.isNotEmpty && year == null) {
      setState(
        () => _error = context.tr('app.work_form.the_year_must_be_a_number'),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = WorkDraft(
      title: _title.text,
      kind: _kind,
      creator: _creator.text,
      year: year,
      language: _language.text,
    );
    try {
      final saved = widget.work == null
          ? await widget.store.addWork(draft)
          : await widget.store.updateWork(widget.work!.id, draft);
      if (mounted) Navigator.of(context).pop(saved);
    } on LibraryException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _sentence(e.message);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(
            widget.work == null
                ? 'app.work_form.add_a_work'
                : 'app.work_form.edit_work',
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(context.tr('common.action.save.label')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          SegmentedButton<WorkKind>(
            segments: [
              for (final k in WorkKind.values)
                ButtonSegment(value: k, label: Text(workKindLabel(k))),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _kind = s.single),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: context.tr('common.field.title.label'),
            ),
          ),
          if (widget.lookup?.available == true) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _looking ? null : _lookUp,
                icon: _looking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Ti.worldSearch),
                label: Text(context.tr('app.work_form.look_up_details')),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // the people the server holds for this kind of work, and the credits already in the library
          ComboField(
            controller: _creator,
            multi: true,
            labelText: creatorLabel(_kind),
            options: () => creditOptions(
              _kind,
              _all,
              PeopleDirectoryScope.of(context)?.names ?? (_) => const [],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            textCapitalization: TextCapitalization.none,
            controller: _year,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.tr('common.field.year.label'),
            ),
          ),
          const SizedBox(height: 12),
          ComboField(
            controller: _language,
            textCapitalization: TextCapitalization.none,
            labelText: context.tr('common.field.language.label'),
            helperText: context.tr(
              'app.work_form.what_it_is_written_or_spoken',
            ),
            options: () => languageOptions(_all),
          ),
        ],
      ),
    );
  }
}

/// The store's messages are lower-case fragments; a screen shows a sentence.
String _sentence(String m) =>
    m.isEmpty ? m : '${m[0].toUpperCase()}${m.substring(1)}.';
