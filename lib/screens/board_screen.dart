import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../boards/board_service.dart';
import '../harness/harness.dart' show BackupPicker, SystemBackupPicker;
import '../library/library_store.dart';
import '../library/models.dart';
import '../sync/fingerprint.dart' show realmOfQuote;
import 'anthologies_screen.dart' show addToAnthologyDialog;
import 'boards_screen.dart' show BoardPicture;
import 'library_widgets.dart';
import 'quote_form_screen.dart' show quoteColour;
import 'quote_screen.dart';

/// How the quotes of a board are put in order.
enum BoardSort {
  newest('Newest first'),
  oldest('Oldest first'),
  text('A to Z'),
  speaker('Who said it'),
  colour('Colour'),
  favourites('Favourites first');

  const BoardSort(this.label);
  final String label;
}

/// How the quotes of a board are gathered under headings.
enum BoardGroup {
  none('No groups'),
  speaker('Who said it'),
  language('Language'),
  colour('Colour');

  const BoardGroup(this.label);
  final String label;
}

/// The quotes in [quotes] in the order [sort] gives.
List<Quote> sortBoardQuotes(List<Quote> quotes, BoardSort sort) {
  int byText(Quote a, Quote b) =>
      a.text.toLowerCase().compareTo(b.text.toLowerCase());
  int bySpeaker(Quote a, Quote b) {
    // quotes with nobody named go last
    if (a.speaker.isEmpty != b.speaker.isEmpty) {
      return a.speaker.isEmpty ? 1 : -1;
    }
    final c = a.speaker.toLowerCase().compareTo(b.speaker.toLowerCase());
    return c != 0 ? c : byText(a, b);
  }

  final list = [...quotes];
  switch (sort) {
    case BoardSort.newest:
      list.sort((a, b) => b.notedAt.compareTo(a.notedAt));
    case BoardSort.oldest:
      list.sort((a, b) => a.notedAt.compareTo(b.notedAt));
    case BoardSort.text:
      list.sort(byText);
    case BoardSort.speaker:
      list.sort(bySpeaker);
    case BoardSort.colour:
      list.sort((a, b) {
        final c = quoteColors
            .indexOf(a.color)
            .compareTo(quoteColors.indexOf(b.color));
        return c != 0 ? c : byText(a, b);
      });
    case BoardSort.favourites:
      list.sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return b.notedAt.compareTo(a.notedAt);
      });
  }
  return list;
}

/// The heading a quote falls under when grouped by [group] ('' for the group of those with none).
String boardGroupOf(Quote q, BoardGroup group) => switch (group) {
  BoardGroup.none => '',
  BoardGroup.speaker => q.speaker.trim(),
  BoardGroup.language => q.language.trim(),
  BoardGroup.colour => q.color,
};

/// One board: its picture and what it is for, then its quotes, sorted and grouped as the reader likes.
class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.store,
    required this.boardId,
    this.picker,
    this.anthologies,
  });

  final LibraryStore store;
  final int boardId;
  final BackupPicker? picker;
  final AnthologyService? anthologies;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  Board? _board;
  List<Quote> _quotes = const [];
  Map<int, Work> _works = const {};
  bool _loaded = false;
  BoardSort _sort = BoardSort.newest;
  BoardGroup _group = BoardGroup.none;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final boards = await widget.store.boards();
    final board = boards.where((b) => b.id == widget.boardId).firstOrNull;
    final quotes = await widget.store.quotes(
      boardId: widget.boardId,
      limit: 100000,
    );
    final works = await widget.store.works();
    if (!mounted) return;
    setState(() {
      _board = board;
      _quotes = quotes;
      _works = {for (final w in works) w.id: w};
      _loaded = true;
    });
  }

  Future<void> _open(Quote q) async {
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => QuoteScreen(
          store: widget.store,
          quoteId: q.id,
          picker: widget.picker ?? const SystemBackupPicker(),
          anthologies: widget.anthologies,
        ),
      ),
    );
    await _load();
  }

  Widget _tile(Quote q) => QuoteTile(
    quote: q,
    work: _works[q.workId],
    onTap: () => _open(q),
    onFavourite: () async {
      await widget.store.setFavorite(q.id, !q.favorite);
      await _load();
    },
    onAddToAnthology:
        widget.anthologies?.available == true && q.serverId != null
        ? () => addToAnthologyDialog(
            context,
            widget.anthologies!,
            kind: entryKindOf(realmOfQuote(_works[q.workId])),
            itemId: q.serverId!,
          )
        : null,
  );

  String _headingOf(String key) {
    if (key.isEmpty) {
      return switch (_group) {
        BoardGroup.speaker => 'Nobody named',
        BoardGroup.language => 'No language',
        _ => 'Other',
      };
    }
    return _group == BoardGroup.colour
        ? '${key[0].toUpperCase()}${key.substring(1)}'
        : key;
  }

  List<Widget> _body(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = sortBoardQuotes(_quotes, _sort);
    if (_group == BoardGroup.none) return [for (final q in sorted) _tile(q)];
    // groups in the order their first quote comes in the sorted list, those with none last
    final groups = <String, List<Quote>>{};
    for (final q in sorted) {
      groups.putIfAbsent(boardGroupOf(q, _group), () => []).add(q);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
        return 0;
      });
    return [
      for (final k in keys) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
          child: Row(
            children: [
              if (_group == BoardGroup.colour && k.isNotEmpty) ...[
                CircleAvatar(radius: 6, backgroundColor: quoteColour(k)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  '${_headingOf(k)} · ${groups[k]!.length}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final q in groups[k]!) _tile(q),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final b = _board;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(b?.name ?? 'Board'),
        actions: [
          PopupMenuButton<BoardSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => [
              for (final s in BoardSort.values)
                CheckedPopupMenuItem(
                  value: s,
                  checked: s == _sort,
                  child: Text(s.label),
                ),
            ],
          ),
          PopupMenuButton<BoardGroup>(
            tooltip: 'Group',
            icon: const Icon(Icons.segment_rounded),
            initialValue: _group,
            onSelected: (g) => setState(() => _group = g),
            itemBuilder: (_) => [
              for (final g in BoardGroup.values)
                CheckedPopupMenuItem(
                  value: g,
                  checked: g == _group,
                  child: Text(g.label),
                ),
            ],
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : b == null
          ? const Center(child: Text('This board is gone.'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (b.imagePath.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BoardPicture(
                        name: b.imagePath,
                        width: double.infinity,
                        height: 180,
                        fallback: const SizedBox(height: 180),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${_quotes.length} ${_quotes.length == 1 ? 'quote' : 'quotes'}',
                        style: theme.textTheme.labelLarge,
                      ),
                      if (b.kind != 'plain')
                        Chip(
                          label: Text(boardKindLabel(b.kind)),
                          visualDensity: VisualDensity.compact,
                        ),
                      for (final l in b.languages)
                        Chip(
                          label: Text(l),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (b.hidden)
                        const Chip(
                          label: Text('Hidden'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                if (b.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      b.description,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                if (_quotes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No quotes on this board yet. File a standalone quote on it from the quote form.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ..._body(context),
              ],
            ),
    );
  }
}
