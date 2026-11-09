import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../app_controller.dart';
import '../harness/harness.dart' show BackupPicker;
import '../l10n/l10n.dart';
import '../library/library_store.dart';
import '../quiz/quiz.dart';
import '../sync/auto_sync.dart';
import '../theme/tabler.dart';
import '../tools/work_lookup.dart';
import '../widgets/swipe_pager.dart';
import 'anthologies_screen.dart';
import 'conflicts_screen.dart';
import 'library_screen.dart';

/// The four boards of the Boards tab: the pages of the reader's collection.
enum BoardKind {
  library('nav.tab.library.label'),
  catalogue('nav.tab.movies.label'),
  quotes('nav.tab.quotes.label'),
  anthologies('nav.tab.anthologies.label');

  const BoardKind(this.label);

  /// The token for the board's name.
  final String label;

  LibrarySection? get section => switch (this) {
    library => LibrarySection.books,
    catalogue => LibrarySection.catalogue,
    quotes => LibrarySection.quotes,
    anthologies => null,
  };
}

/// The Boards tab: Library, Catalogue, Quotes and Anthologies as pages side by side. The header names the board you are
/// on, with an arrow each way and a dot for each board; a sideways swipe or drag (or an arrow, or a dot) moves to the next.
/// The swipe is for these pages only: the other tabs of the bar do not swipe.
class BoardsTab extends StatefulWidget {
  const BoardsTab({
    super.key,
    required this.store,
    required this.picker,
    required this.boards,
    required this.goTo,
    this.anthologies,
    this.lookup,
    this.auto,
    this.quiz,
    this.controller,
  });

  final LibraryStore store;
  final BackupPicker picker;

  /// Which boards are shown, in order (the reader may hide some in Settings).
  final List<BoardKind> boards;

  /// Set to a board to bring it into view, from outside (a button on Home).
  final ValueNotifier<BoardKind?> goTo;
  final AnthologyService? anthologies;
  final WorkLookup? lookup;
  final AutoSync? auto;
  final QuizService? quiz;
  final AppController? controller;

  @override
  State<BoardsTab> createState() => _BoardsTabState();
}

class _BoardsTabState extends State<BoardsTab> {
  late final ValueNotifier<int> _page = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    widget.goTo.addListener(_goTo);
  }

  @override
  void dispose() {
    widget.goTo.removeListener(_goTo);
    _page.dispose();
    super.dispose();
  }

  void _goTo() {
    final k = widget.goTo.value;
    if (k == null) return;
    final i = widget.boards.indexOf(k);
    if (i >= 0) _page.value = i;
    widget.goTo.value = null;
  }

  Widget _board(BoardKind k) => switch (k) {
    BoardKind.anthologies => AnthologiesScreen(
      key: ValueKey(k),
      service: widget.anthologies!,
      picker: widget.picker,
      quiz: widget.quiz,
      controller: widget.controller,
      embedded: true,
    ),
    _ => LibraryScreen(
      key: ValueKey(k),
      store: widget.store,
      picker: widget.picker,
      anthologies: widget.anthologies,
      lookup: widget.lookup,
      auto: widget.auto,
      section: k.section!,
      embedded: true,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final boards = widget.boards;
    if (boards.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Stack(
            children: [
              _header(context),
              if (widget.auto != null)
                Positioned(
                  right: 52,
                  top: 4,
                  child: _syncState(context, widget.auto!),
                ),
            ],
          ),
          Expanded(
            child: SwipePager(
              tab: _page,
              children: [for (final k in boards) _board(k)],
            ),
          ),
        ],
      ),
    );
  }

  /// A sync running, or the conflicts waiting for the reader (a press settles them).
  Widget _syncState(BuildContext context, AutoSync auto) => ListenableBuilder(
    listenable: auto,
    builder: (context, _) {
      final n = auto.conflicts.length;
      if (n > 0) {
        return IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: n == 1 ? '1 sync conflict' : '$n sync conflicts',
          icon: Badge(label: Text('$n'), child: const Icon(Ti.refreshAlert)),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ConflictsScreen(auto: auto),
            ),
          ),
        );
      }
      if (auto.syncing) {
        return const Padding(
          padding: EdgeInsets.all(10),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      return const SizedBox.shrink();
    },
  );

  /// The name of the board you are on, an arrow each way and a dot for each board.
  Widget _header(BuildContext context) {
    final boards = widget.boards;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: _page,
      builder: (context, i, _) {
        final at = i.clamp(0, boards.length - 1);
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('board-previous'),
                tooltip: context.tr('app.boards_tab.previous'),
                onPressed: at == 0 ? null : () => _page.value = at - 1,
                icon: const Icon(Ti.chevronLeft),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      context.tr(boards[at].label),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var d = 0; d < boards.length; d++)
                          GestureDetector(
                            onTap: () => _page.value = d,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 4,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: d == at ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: d == at
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('board-next'),
                tooltip: context.tr('app.boards_tab.next'),
                onPressed: at == boards.length - 1
                    ? null
                    : () => _page.value = at + 1,
                icon: const Icon(Ti.chevronRight),
              ),
            ],
          ),
        );
      },
    );
  }
}
