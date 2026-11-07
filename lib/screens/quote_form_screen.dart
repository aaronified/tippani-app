import 'package:flutter/material.dart';

import '../capture/page_adjuster.dart';
import '../capture/photo_source.dart';
import '../capture/text_recogniser.dart';
import '../capture/voice_listener.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import 'capture_screen.dart';
import 'voice_screen.dart';
import 'work_form_screen.dart';

/// The colour a quote's name stands for, drawn in the theme's own tone so it works in light and dark.
Color quoteColour(String name) => switch (name) {
  'green' => const Color(0xFF6BAA75),
  'blue' => const Color(0xFF5B8FD6),
  'pink' => const Color(0xFFD97BA6),
  'orange' => const Color(0xFFE59A4A),
  'purple' => const Color(0xFF9A7BD6),
  _ => const Color(0xFFE5C34A),
};

/// Adds a quote, or changes one. Pops `true` when something was saved or deleted.
class QuoteFormScreen extends StatefulWidget {
  const QuoteFormScreen({
    super.key,
    required this.store,
    this.quote,
    this.workId,
    this.initialText = '',
    this.source = 'manual',
    this.photos,
    this.recogniser = const TesseractRecogniser(),
    this.listener,
    this.adjuster,
    this.adjustPage = true,
  });

  /// Straightens and crops a scanned page; null uses the phone's own. A test passes a stand-in, or turns it off.
  final PageAdjuster? adjuster;
  final bool adjustPage;

  /// Where a scanned page's picture comes from, how its text is read, and what listens when the reader speaks.
  /// Null uses the phone's own; a test passes stand-ins.
  final PhotoSource? photos;
  final TextRecogniser recogniser;
  final VoiceListener? listener;

  final LibraryStore store;

  /// The quote being changed; null adds a new one.
  final Quote? quote;

  /// The work a new quote starts in (opened from a work's page).
  final int? workId;

  /// The words a new quote starts with (read from a photographed page).
  final String initialText;

  /// How a new quote was captured: "manual" or "ocr". A quote being changed keeps its own.
  final String source;

  @override
  State<QuoteFormScreen> createState() => _QuoteFormScreenState();
}

class _QuoteFormScreenState extends State<QuoteFormScreen> {
  late final _text = TextEditingController(
    text: widget.quote?.text ?? widget.initialText,
  );
  late final _translation = TextEditingController(
    text: widget.quote?.translation,
  );
  late final _speaker = TextEditingController(text: widget.quote?.speaker);
  late final _chapter = TextEditingController(text: widget.quote?.chapter);
  late final _location = TextEditingController(text: widget.quote?.location);
  late final _note = TextEditingController(text: widget.quote?.note);
  late final _language = TextEditingController(text: widget.quote?.language);
  late final _tags = TextEditingController(text: widget.quote?.tags.join(', '));
  late int? _workId = widget.quote?.workId ?? widget.workId;
  late String _color = widget.quote?.color ?? 'yellow';
  late bool _favourite = widget.quote?.favorite ?? false;
  late String _source = widget.quote?.source ?? widget.source;
  List<Work> _works = const [];
  List<Board> _boards = const [];
  late int? _boardId = widget.quote?.boardId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadWorks();
  }

  @override
  void dispose() {
    for (final c in [
      _text,
      _translation,
      _speaker,
      _chapter,
      _location,
      _note,
      _language,
      _tags,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadWorks() async {
    final ws = await widget.store.works();
    final bs = await widget.store.boards();
    if (mounted) {
      setState(() {
        _works = ws;
        _boards = bs;
      });
    }
  }

  Future<void> _newWork() async {
    final w = await Navigator.of(context).push<Work>(
      MaterialPageRoute(builder: (_) => WorkFormScreen(store: widget.store)),
    );
    if (w == null) return;
    await _loadWorks();
    if (mounted) setState(() => _workId = w.id);
  }

  /// Puts [t] in the words: replacing them if they are empty, otherwise added after what is there, so a second
  /// page or a second thing said does not wipe the first.
  void _put(CapturedText t) {
    if (t.text.isEmpty) return;
    setState(() {
      _text.text = _text.text.trim().isEmpty
          ? t.text
          : '${_text.text.trimRight()}\n\n${t.text}';
      // a quote being changed keeps the way it was first captured
      if (widget.quote == null && t.source == 'ocr') _source = 'ocr';
    });
  }

  Future<void> _scan() async {
    final t = await Navigator.of(context).push<CapturedText>(
      MaterialPageRoute(
        builder: (_) => CaptureScreen(
          photos: widget.photos,
          recogniser: widget.recogniser,
          adjuster: widget.adjuster,
          adjust: widget.adjustPage,
        ),
      ),
    );
    if (t != null) _put(t);
  }

  Future<void> _speak() async {
    final t = await Navigator.of(context).push<CapturedText>(
      MaterialPageRoute(builder: (_) => VoiceScreen(listener: widget.listener)),
    );
    if (t != null) _put(t);
  }

  QuoteDraft _draft() => QuoteDraft(
    text: _text.text,
    workId: _workId,
    translation: _translation.text,
    language: _language.text,
    speaker: _speaker.text,
    chapter: _chapter.text,
    location: _location.text,
    note: _note.text,
    color: _color,
    favorite: _favourite,
    notedAt: widget.quote?.notedAt,
    source: _source,
    tags: _tags.text.split(','),
    boardId: _workId == null ? _boardId : null,
  );

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.quote == null) {
        await widget.store.addQuote(_draft());
      } else {
        await widget.store.updateQuote(widget.quote!.id, _draft());
      }
      if (mounted) Navigator.of(context).pop(true);
    } on LibraryException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '${e.message[0].toUpperCase()}${e.message.substring(1)}.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this quote?'),
        content: const Text(
          'It is removed from this phone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await widget.store.deleteQuote(widget.quote!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.quote != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit quote' : 'Add a quote'),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
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
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'The words',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scan a page'),
              ),
              OutlinedButton.icon(
                onPressed: _speak,
                icon: const Icon(Icons.mic_none),
                label: const Text('Speak'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _works.any((w) => w.id == _workId) ? _workId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'From'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('No work (a standalone quote)'),
              ),
              for (final w in _works)
                DropdownMenuItem<int?>(
                  value: w.id,
                  child: Text(
                    w.creator.isEmpty ? w.title : '${w.title} · ${w.creator}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _workId = v),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _newWork,
              icon: const Icon(Icons.add),
              label: const Text('New work'),
            ),
          ),
          if (_workId == null && _boards.isNotEmpty) ...[
            DropdownButtonFormField<int?>(
              initialValue: _boards.any((b) => b.id == _boardId)
                  ? _boardId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Board'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('No board'),
                ),
                for (final b in _boards)
                  DropdownMenuItem<int?>(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _boardId = v),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _speaker,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Who said it'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chapter,
                  decoration: InputDecoration(
                    labelText: _workId == null ? 'Occasion' : 'Chapter',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _location,
                  decoration: InputDecoration(
                    labelText: _workId == null ? 'Place' : 'Page or position',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _translation,
            minLines: 1,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Translation'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _language,
            decoration: const InputDecoration(
              labelText: 'Language of the words',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Your note'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: 'Tags',
              helperText: 'Separated by commas.',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final c in quoteColors)
                ChoiceChip(
                  key: ValueKey('colour-$c'),
                  label: Text(c),
                  avatar: CircleAvatar(backgroundColor: quoteColour(c)),
                  selected: _color == c,
                  onSelected: (_) => setState(() => _color = c),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Favourite'),
            value: _favourite,
            onChanged: (v) => setState(() => _favourite = v),
          ),
        ],
      ),
    );
  }
}
