import 'package:flutter/material.dart';

import '../library/library_store.dart';
import '../library/models.dart';

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
  const WorkFormScreen({super.key, required this.store, this.work});

  final LibraryStore store;
  final Work? work;

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
  late WorkKind _kind = widget.work?.kind ?? WorkKind.book;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _creator.dispose();
    _year.dispose();
    _language.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final yearText = _year.text.trim();
    final year = yearText.isEmpty ? null : int.tryParse(yearText);
    if (yearText.isNotEmpty && year == null) {
      setState(() => _error = 'The year must be a number.');
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
        title: Text(widget.work == null ? 'Add a work' : 'Edit work'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
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
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _creator,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: creatorLabel(_kind)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _year,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Year'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _language,
            decoration: const InputDecoration(
              labelText: 'Language',
              helperText:
                  'What it is written or spoken in, if you want to say.',
            ),
          ),
        ],
      ),
    );
  }
}

/// The store's messages are lower-case fragments; a screen shows a sentence.
String _sentence(String m) =>
    m.isEmpty ? m : '${m[0].toUpperCase()}${m.substring(1)}.';
