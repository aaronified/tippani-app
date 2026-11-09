import 'package:flutter/material.dart';

import '../account/prefs_effects.dart';
import '../capture/page_adjuster.dart';
import '../capture/photo_source.dart';
import '../capture/text_recogniser.dart';
import '../capture/voice_listener.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import 'capture_screen.dart';
import 'voice_screen.dart';
import 'work_form_screen.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

/// The colour a quote's name stands for, drawn in the theme's own tone so it works in light and dark.
Color quoteColour(String name) {
  final own = PrefsEffects.current.colourHex(name);
  final parsed = own.length == 7 && own.startsWith('#')
      ? int.tryParse(own.substring(1), radix: 16)
      : null;
  if (parsed != null) return Color(0xFF000000 | parsed);
  return switch (name) {
    'green' => const Color(0xFF6BAA75),
    'blue' => const Color(0xFF5B8FD6),
    'pink' => const Color(0xFFD97BA6),
    'orange' => const Color(0xFFE59A4A),
    'purple' => const Color(0xFF9A7BD6),
    _ => const Color(0xFFE5C34A),
  };
}

/// What a colour is called: the name the reader gave it in Settings, or its own.
String quoteColourName(String token) {
  final own = PrefsEffects.current.colourName(token);
  return own.isNotEmpty ? own : token;
}

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

  /// What the form offers to fill the boxes with: the cast of the chosen work, the chapters already used in it, and
  /// the tags the library already has.
  List<Quote> _inWork = const [];
  List<String> _knownTags = const [];
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
    // in the reader's order; a hidden board is not offered (unless the quote is already on it)
    final bs = await widget.store.boards()
      ..sort((x, y) {
        final p = (x.pos ?? 1 << 30).compareTo(y.pos ?? 1 << 30);
        return p != 0
            ? p
            : x.name.toLowerCase().compareTo(y.name.toLowerCase());
      });
    final tags = await widget.store.tags();
    if (mounted) {
      setState(() {
        _works = ws;
        _boards = bs;
        _knownTags = tags;
      });
    }
    await _loadWorkHints();
  }

  Future<void> _loadWorkHints() async {
    final id = _workId;
    final qs = id == null
        ? const <Quote>[]
        : await widget.store.quotes(workId: id, limit: 1 << 30);
    if (mounted) setState(() => _inWork = qs);
  }

  /// The characters (or, for a book, the speakers already used) the chosen work offers for "who said it".
  List<String> get _speakerHints {
    final w = _works.where((w) => w.id == _workId).firstOrNull;
    final seen = <String>{};
    final out = <String>[];
    void add(String s) {
      final n = s.trim();
      if (n.isNotEmpty && seen.add(n.toLowerCase())) out.add(n);
    }

    if (w != null) {
      for (final c in w.details.cast) {
        add(c.character);
      }
    }
    for (final q in _inWork) {
      for (final n in q.speaker.split(RegExp(r'\s*[,;&]\s*'))) {
        add(n);
      }
    }
    return out.take(14).toList();
  }

  List<String> get _chapterHints {
    final seen = <String>{};
    return [
      for (final q in _inWork)
        if (q.chapter.trim().isNotEmpty && seen.add(q.chapter.trim()))
          q.chapter.trim(),
    ].take(14).toList();
  }

  /// Adds [name] to a comma-separated box, unless it is already there.
  void _append(TextEditingController c, String name) {
    final parts = [
      for (final p in c.text.split(','))
        if (p.trim().isNotEmpty) p.trim(),
    ];
    if (parts.any((p) => p.toLowerCase() == name.toLowerCase())) return;
    setState(() => c.text = [...parts, name].join(', '));
  }

  Widget _hints(
    String label,
    List<String> options,
    void Function(String) pick,
  ) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 0,
            children: [
              for (final o in options)
                ActionChip(
                  label: Text(o),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => pick(o),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _newWork() async {
    final w = await Navigator.of(context).push<Work>(
      MaterialPageRoute(builder: (_) => WorkFormScreen(store: widget.store)),
    );
    if (w == null) return;
    await _loadWorks();
    if (mounted) setState(() => _workId = w.id);
    await _loadWorkHints();
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
        title: Text(context.tr('quotes.delete.confirm')),
        content: Text(
          context.tr('app.quote_form.it_is_removed_from_this_phone'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('app.anthologies.keep_it')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('common.action.delete.label')),
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
        title: Text(
          editing
              ? context.tr('common.quote.edit.title')
              : context.tr('app.work.add_a_quote'),
        ),
        actions: [
          if (editing)
            IconButton(
              tooltip: context.tr('common.action.delete.label'),
              icon: const Icon(Ti.trash),
              onPressed: _delete,
            ),
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
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.tr('app.quote_form.the_words'),
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
                icon: const Icon(Ti.scan),
                label: Text(context.tr('app.capture.scan_a_page')),
              ),
              OutlinedButton.icon(
                onPressed: _speak,
                icon: const Icon(Ti.microphone),
                label: Text(context.tr('app.quote_form.speak')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _works.any((w) => w.id == _workId) ? _workId : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.tr('anthologies.fill.from.label'),
            ),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text(
                  context.tr('app.quote_form.no_work_a_standalone_quote'),
                ),
              ),
              for (final w in _works)
                DropdownMenuItem<int?>(
                  value: w.id,
                  child: Text(
                    w.creator.isEmpty
                        ? w.title
                        : context.tr('app.quote_form.title_creator', {
                            'title': w.title,
                            'creator': w.creator,
                          }),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) {
              setState(() => _workId = v);
              _loadWorkHints();
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _newWork,
              icon: const Icon(Ti.plus),
              label: Text(context.tr('app.quote_form.new_work')),
            ),
          ),
          if (_workId == null && _boards.isNotEmpty) ...[
            DropdownButtonFormField<int?>(
              initialValue: _boards.any((b) => b.id == _boardId)
                  ? _boardId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('common.field.board.label'),
              ),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(context.tr('app.bulk_bar.no_board')),
                ),
                for (final b in _boards.where(
                  (b) => !b.hidden || b.id == _boardId,
                ))
                  DropdownMenuItem<int?>(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _boardId = v),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _speaker,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: context.tr('anthologies.form.fields.credit.label'),
            ),
          ),
          _hints(
            context.tr('app.quote_form.in_this_work'),
            _speakerHints,
            (n) => _append(_speaker, n),
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
          _hints(
            context.tr('app.quote_form.chapters_you_used'),
            _chapterHints,
            (n) => setState(() => _chapter.text = n),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _translation,
            minLines: 1,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: context.tr('common.field.translation.label'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _language,
            decoration: InputDecoration(
              labelText: context.tr('app.quote_form.language_of_the_words'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: context.tr('identity.field.note'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tags,
            decoration: InputDecoration(
              labelText: context.tr('common.field.tags.label'),
              helperText: context.tr('app.quote_form.separated_by_commas'),
            ),
          ),
          _hints(
            context.tr('app.quote_form.your_tags'),
            [
              for (final t in _knownTags)
                if (!_tags.text
                    .split(',')
                    .any((p) => p.trim().toLowerCase() == t.toLowerCase()))
                  t,
            ].take(14).toList(),
            (n) => _append(_tags, n),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final c in quoteColors)
                if (c == _color || !PrefsEffects.current.colourHidden(c))
                  ChoiceChip(
                    key: ValueKey('colour-$c'),
                    label: Text(quoteColourName(c)),
                    avatar: CircleAvatar(backgroundColor: quoteColour(c)),
                    selected: _color == c,
                    onSelected: (_) => setState(() => _color = c),
                  ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('common.field.favourite.label')),
            value: _favourite,
            onChanged: (v) => setState(() => _favourite = v),
          ),
        ],
      ),
    );
  }
}
