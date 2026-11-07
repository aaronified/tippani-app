import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import '../library/models.dart';
import '../library/quote_text.dart';
import '../library/work_order.dart';
import '../speech/speaker.dart';
import '../l10n/l10n.dart';

/// A work's quotes as one document to read straight through, by chapter, in reading order. The reader sets
/// the text size and whether translations and their own notes show, and can send the whole thing as text.
class WorkReadScreen extends StatefulWidget {
  const WorkReadScreen({
    super.key,
    required this.work,
    required this.quotes,
    this.share = shareThroughSheet,
    this.speaker,
  });

  final Work work;

  /// In reading order.
  final List<Quote> quotes;
  final ShareText share;
  final Speaker? speaker;

  @override
  State<WorkReadScreen> createState() => _WorkReadScreenState();
}

class _WorkReadScreenState extends State<WorkReadScreen> {
  double _size = 18;
  bool _translations = true;
  bool _notes = false;
  bool _reading = false;
  late final Speaker _speaker = widget.speaker ?? PlatformSpeaker();

  @override
  void dispose() {
    _reading = false;
    _speaker.stop();
    super.dispose();
  }

  /// Reads every quote in turn, in reading order, until the end or until stopped.
  Future<void> _toggleReading() async {
    if (_reading) {
      setState(() => _reading = false);
      await _speaker.stop();
      return;
    }
    setState(() => _reading = true);
    final couldNotRead = context.tr('app.work_read.the_work_could_not_be_read');
    String? problem;
    try {
      for (final q in widget.quotes) {
        if (!_reading) break;
        final language = q.language.isNotEmpty
            ? q.language
            : widget.work.language;
        if (!await _speaker.speak(q.text, language)) {
          problem = 'This phone has no voice for "$language".';
          break;
        }
      }
    } on Object {
      problem = couldNotRead;
    }
    if (!mounted) return;
    setState(() => _reading = false);
    if (problem != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final groups = groupByChapter(widget.quotes);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.work.title),
        actions: [
          IconButton(
            tooltip: _reading
                ? context.tr('speech.stop.aria')
                : context.tr('speech.play.aria'),
            icon: Icon(
              _reading ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
            ),
            onPressed: widget.quotes.isEmpty ? null : _toggleReading,
          ),
          IconButton(
            tooltip: context.tr('app.work_read.share_all'),
            icon: const Icon(Icons.ios_share),
            onPressed: () => widget.share(
              workShareText(
                widget.work,
                widget.quotes,
                translations: _translations,
                notes: _notes,
              ),
              widget.work.title,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: scheme.surfaceContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.text_decrease, size: 20),
                      Expanded(
                        child: Slider(
                          value: _size,
                          min: 14,
                          max: 32,
                          divisions: 9,
                          label: context.tr('app.work_read.round', {
                            'round': _size.round(),
                          }),
                          semanticFormatterCallback: (v) =>
                              'Text size ${v.round()}',
                          onChanged: (v) => setState(() => _size = v),
                        ),
                      ),
                      const Icon(Icons.text_increase, size: 20),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: Text(context.tr('app.work_read.translations')),
                        selected: _translations,
                        onSelected: (v) => setState(() => _translations = v),
                      ),
                      FilterChip(
                        label: Text(context.tr('app.work_read.my_notes')),
                        selected: _notes,
                        onSelected: (v) => setState(() => _notes = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: widget.quotes.isEmpty
                ? Center(
                    child: Text(
                      context.tr('app.work_read.no_quotes_from_this_work_yet'),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    children: [
                      for (final g in groups) ...[
                        if (g.name.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 8),
                            child: Text(
                              g.name,
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                        for (final q in g.quotes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  '“${q.text.trim()}”',
                                  style: quoteStyle(
                                    context,
                                    size: _size,
                                    height: 1.55,
                                    language: q.language,
                                  ),
                                ),
                                if (q.location.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      q.location.trim(),
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                if (_translations &&
                                    q.translation.trim().isNotEmpty)
                                  SelectableText(
                                    q.translation.trim(),
                                    style: quoteStyle(
                                      context,
                                      size: _size * 0.9,
                                      height: 1.5,
                                      style: FontStyle.italic,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                if (_notes && q.note.trim().isNotEmpty)
                                  SelectableText(
                                    q.note.trim(),
                                    style: TextStyle(
                                      fontSize: _size * 0.85,
                                      color: scheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
