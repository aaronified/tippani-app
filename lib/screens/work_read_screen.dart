import 'package:flutter/material.dart';

import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import '../library/models.dart';
import '../library/quote_text.dart';
import '../library/work_order.dart';

/// A work's quotes as one document to read straight through, by chapter, in reading order. The reader sets
/// the text size and whether translations and their own notes show, and can send the whole thing as text.
class WorkReadScreen extends StatefulWidget {
  const WorkReadScreen({
    super.key,
    required this.work,
    required this.quotes,
    this.share = shareThroughSheet,
  });

  final Work work;

  /// In reading order.
  final List<Quote> quotes;
  final ShareText share;

  @override
  State<WorkReadScreen> createState() => _WorkReadScreenState();
}

class _WorkReadScreenState extends State<WorkReadScreen> {
  double _size = 18;
  bool _translations = true;
  bool _notes = false;

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
            tooltip: 'Share all',
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
                          label: '${_size.round()}',
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
                        label: const Text('Translations'),
                        selected: _translations,
                        onSelected: (v) => setState(() => _translations = v),
                      ),
                      FilterChip(
                        label: const Text('My notes'),
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
                ? const Center(child: Text('No quotes from this work yet.'))
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
                                  style: TextStyle(
                                    fontSize: _size,
                                    height: 1.45,
                                  ),
                                ),
                                if (q.location.trim().isNotEmpty)
                                  Text(
                                    q.location.trim(),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                if (_translations &&
                                    q.translation.trim().isNotEmpty)
                                  SelectableText(
                                    q.translation.trim(),
                                    style: TextStyle(
                                      fontSize: _size * 0.9,
                                      fontStyle: FontStyle.italic,
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
