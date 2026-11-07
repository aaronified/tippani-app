import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../library/cover_cache.dart';
import '../library/models.dart';
import 'library_widgets.dart';
import 'shelf_card.dart';

/// How the works are ordered.
enum WorkSort {
  title('Title'),
  creator('Author or maker'),
  yearNewest('Year, newest first'),
  yearOldest('Year, oldest first'),
  added('Recently added');

  const WorkSort(this.label);
  final String label;
}

/// What the works are gathered under.
enum WorkGroup {
  none('No grouping'),
  creator('Author or maker'),
  decade('Decade'),
  status('Where I am with it'),
  genre('Genre'),
  language('Language');

  const WorkGroup(this.label);
  final String label;
}

/// Which works to keep, by where the reader is with them.
enum WorkShelfFilter {
  all('All'),
  inProgress('In progress'),
  notStarted('Not started'),
  paused('Paused'),
  finished('Finished'),
  abandoned('Abandoned');

  const WorkShelfFilter(this.label);
  final String label;

  bool keeps(Work w) {
    final s = w.details.status;
    return switch (this) {
      WorkShelfFilter.all => true,
      WorkShelfFilter.inProgress => s == activeStatusOf(w.kind),
      WorkShelfFilter.notStarted => s.isEmpty,
      WorkShelfFilter.paused => s == 'paused',
      WorkShelfFilter.finished => s == 'completed',
      WorkShelfFilter.abandoned => s == 'abandoned',
    };
  }
}

/// One heading and the works under it.
class WorkGroupRows {
  const WorkGroupRows(this.title, this.works);
  final String title;
  final List<Work> works;
}

int _compareText(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

/// [works] in the order asked for. Never changes the list it is given.
List<Work> sortWorks(List<Work> works, WorkSort sort) {
  final out = [...works];
  int title(Work a, Work b) => _compareText(a.title, b.title);
  switch (sort) {
    case WorkSort.title:
      out.sort(title);
    case WorkSort.creator:
      out.sort((a, b) {
        final c = _compareText(a.creator, b.creator);
        return c != 0 ? c : title(a, b);
      });
    case WorkSort.yearNewest:
      out.sort((a, b) {
        final c = (b.year ?? -1 << 30).compareTo(a.year ?? -1 << 30);
        return c != 0 ? c : title(a, b);
      });
    case WorkSort.yearOldest:
      out.sort((a, b) {
        final c = (a.year ?? 1 << 30).compareTo(b.year ?? 1 << 30);
        return c != 0 ? c : title(a, b);
      });
    case WorkSort.added:
      out.sort((a, b) {
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : title(a, b);
      });
  }
  return out;
}

/// [works] gathered under headings, each group keeping the order [works] came in. Keys are tokens-free words the
/// screen translates: [labelOf] turns an internal key into the heading's words.
List<WorkGroupRows> groupWorks(
  List<Work> works,
  WorkGroup group, {
  required String Function(String key) labelOf,
}) {
  if (group == WorkGroup.none) return [WorkGroupRows('', works)];
  final keyOf = switch (group) {
    WorkGroup.creator => (Work w) => w.creator.trim(),
    WorkGroup.decade => (
      Work w,
    ) => w.year == null ? '' : '${w.year! ~/ 10 * 10}',
    WorkGroup.status => (Work w) => w.details.status,
    WorkGroup.genre => (
      Work w,
    ) => w.details.genres.isEmpty ? '' : w.details.genres.first,
    WorkGroup.language => (Work w) => w.language.trim(),
    WorkGroup.none => (Work w) => '',
  };
  final by = <String, List<Work>>{};
  for (final w in works) {
    by.putIfAbsent(keyOf(w), () => []).add(w);
  }
  final keys = by.keys.toList();
  int rank(String k) {
    // where a work is: in progress first, then paused, not started, finished, abandoned
    const order = [
      'reading',
      'watching',
      'playing',
      'paused',
      '',
      'completed',
      'abandoned',
    ];
    final i = order.indexOf(k);
    return i < 0 ? order.length : i;
  }

  switch (group) {
    case WorkGroup.status:
      keys.sort((a, b) => rank(a).compareTo(rank(b)));
    case WorkGroup.decade:
      keys.sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return int.parse(b).compareTo(int.parse(a));
      });
    default:
      keys.sort((a, b) {
        if (a.isEmpty) return 1; // "unknown" last
        if (b.isEmpty) return -1;
        return _compareText(a, b);
      });
  }
  // the in-progress words are one heading
  final merged = <String, List<Work>>{};
  for (final k in keys) {
    final heading =
        group == WorkGroup.status &&
            (k == 'reading' || k == 'watching' || k == 'playing')
        ? 'inprogress'
        : k;
    merged.putIfAbsent(heading, () => []).addAll(by[k]!);
  }
  return [
    for (final e in merged.entries) WorkGroupRows(labelOf(e.key), e.value),
  ];
}

/// The works of a section as the reader wants them: ordered, gathered under headings, filtered by where they are
/// with them, and shown as a list or as a wall of covers. The choices are kept per section.
class WorksView extends StatefulWidget {
  const WorksView({
    super.key,
    required this.works,
    required this.onOpen,
    required this.sectionKey,
    this.prefs,
    this.selected = const {},
    this.onLongPress,
  });

  final List<Work> works;
  final ValueChanged<Work> onOpen;

  /// The ids picked while selecting many, shown marked; [onLongPress] starts or extends that.
  final Set<int> selected;
  final ValueChanged<Work>? onLongPress;

  /// Names this section's saved choices ('books', 'catalogue').
  final String sectionKey;

  /// Where the choices are kept; null opens the phone's own.
  final SharedPreferences? prefs;

  @override
  State<WorksView> createState() => _WorksViewState();
}

class _WorksViewState extends State<WorksView> {
  WorkSort _sort = WorkSort.title;
  WorkGroup _group = WorkGroup.none;
  WorkShelfFilter _filter = WorkShelfFilter.all;
  bool _grid = false;
  int _columns = 3;
  SharedPreferences? _p;

  String _k(String name) => 'library_${widget.sectionKey}_$name';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final p = widget.prefs ?? await SharedPreferences.getInstance();
      _p = p;
      T pick<T extends Enum>(List<T> all, String name, T fallback) {
        final v = p.getString(_k(name));
        return all.where((e) => e.name == v).firstOrNull ?? fallback;
      }

      if (!mounted) return;
      setState(() {
        _sort = pick(WorkSort.values, 'sort', WorkSort.title);
        _group = pick(WorkGroup.values, 'group', WorkGroup.none);
        _filter = pick(WorkShelfFilter.values, 'filter', WorkShelfFilter.all);
        _grid = p.getBool(_k('grid')) ?? false;
        _columns = (p.getInt(_k('columns')) ?? 3).clamp(2, 4);
      });
    } on Object {
      // the choices just are not kept
    }
  }

  void _keep(String name, Object value) {
    final p = _p;
    if (p == null) return;
    if (value is Enum) {
      p.setString(_k(name), value.name);
    } else if (value is bool) {
      p.setBool(_k(name), value);
    } else if (value is int) {
      p.setInt(_k(name), value);
    }
  }

  String _heading(String key) {
    switch (_group) {
      case WorkGroup.status:
        return key == 'inprogress'
            ? context.tr('In progress')
            : key.isEmpty
            ? context.tr('Not started')
            : shelfStatusLabel(context, key);
      case WorkGroup.decade:
        return key.isEmpty ? context.tr('Year unknown') : '${key}s';
      case WorkGroup.creator:
        return key.isEmpty ? context.tr('Creator unknown') : key;
      case WorkGroup.genre:
        return key.isEmpty ? context.tr('No genre') : key;
      case WorkGroup.language:
        return key.isEmpty ? context.tr('Language unknown') : key;
      case WorkGroup.none:
        return '';
    }
  }

  Widget _menu<T extends Enum>({
    required String title,
    required IconData icon,
    required List<T> values,
    required T value,
    required String Function(T) label,
    required ValueChanged<T> onPicked,
    Key? key,
  }) {
    return PopupMenuButton<T>(
      key: key,
      tooltip: title,
      onSelected: onPicked,
      itemBuilder: (_) => [
        for (final v in values)
          CheckedPopupMenuItem<T>(
            value: v,
            checked: v == value,
            child: Text(label(v)),
          ),
      ],
      child: Chip(
        avatar: Icon(icon, size: 18),
        label: Text('$title: ${label(value)}'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kept = widget.works.where(_filter.keeps).toList();
    final sorted = sortWorks(kept, _sort);
    final groups = groupWorks(sorted, _group, labelOf: _heading);

    final toolbar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                _menu<WorkSort>(
                  key: const ValueKey('works-sort'),
                  title: context.tr('Sort'),
                  icon: Icons.sort_rounded,
                  values: WorkSort.values,
                  value: _sort,
                  label: (v) => context.tr(v.label),
                  onPicked: (v) {
                    setState(() => _sort = v);
                    _keep('sort', v);
                  },
                ),
                _menu<WorkGroup>(
                  key: const ValueKey('works-group'),
                  title: context.tr('Group'),
                  icon: Icons.view_agenda_outlined,
                  values: WorkGroup.values,
                  value: _group,
                  label: (v) => context.tr(v.label),
                  onPicked: (v) {
                    setState(() => _group = v);
                    _keep('group', v);
                  },
                ),
                IconButton.filledTonal(
                  key: const ValueKey('works-view'),
                  tooltip: _grid
                      ? context.tr('Show as a list')
                      : context.tr('Show as covers'),
                  icon: Icon(
                    _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  ),
                  onPressed: () {
                    setState(() => _grid = !_grid);
                    _keep('grid', _grid);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                for (final f in WorkShelfFilter.values)
                  ChoiceChip(
                    key: ValueKey('works-filter-${f.name}'),
                    label: Text(context.tr(f.label)),
                    selected: _filter == f,
                    onSelected: (_) {
                      setState(() => _filter = f);
                      _keep('filter', f);
                    },
                  ),
              ],
            ),
          ),
          if (_grid)
            Row(
              children: [
                Icon(
                  Icons.photo_size_select_large_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey('works-size'),
                    // fewer columns, bigger covers
                    value: (6 - _columns).toDouble(),
                    min: 2,
                    max: 4,
                    divisions: 2,
                    onChanged: (v) => setState(() => _columns = 6 - v.round()),
                    onChangeEnd: (v) => _keep('columns', 6 - v.round()),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              kept.length == widget.works.length
                  ? context.tr('{n} works', {'n': kept.length})
                  : context.tr('{n} of {total} works', {
                      'n': kept.length,
                      'total': widget.works.length,
                    }),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        toolbar,
        if (kept.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.tr('No works match. Choose All to see everything.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        for (final g in groups) ...[
          if (g.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(g.title, style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    '${g.works.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (_grid)
            _CoverGrid(
              works: g.works,
              columns: _columns,
              onOpen: widget.onOpen,
              selected: widget.selected,
              onLongPress: widget.onLongPress,
            )
          else
            for (final w in g.works)
              WorkTile(
                work: w,
                selected: widget.selected.contains(w.id),
                onLongPress: widget.onLongPress == null
                    ? null
                    : () => widget.onLongPress!(w),
                onTap: () => widget.onOpen(w),
              ),
        ],
      ],
    );
  }
}

/// A wall of covers, [columns] across, each with its title and maker under it and its shelf status on it.
class _CoverGrid extends StatelessWidget {
  const _CoverGrid({
    required this.works,
    required this.columns,
    required this.onOpen,
    required this.selected,
    required this.onLongPress,
  });

  final List<Work> works;
  final int columns;
  final ValueChanged<Work> onOpen;
  final Set<int> selected;
  final ValueChanged<Work>? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = 12.0;
          final w = (box.maxWidth - gap * (columns - 1)) / columns;
          final h = w * 1.5;
          return Wrap(
            spacing: gap,
            runSpacing: 14,
            children: [
              for (final work in works)
                SizedBox(
                  width: w,
                  child: InkWell(
                    key: ValueKey('cover-${work.id}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onOpen(work),
                    onLongPress: onLongPress == null
                        ? null
                        : () => onLongPress!(work),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: WorkCover(
                                work: work,
                                width: w,
                                height: h,
                                fallback: MonogramCover(
                                  work: work,
                                  width: w,
                                  height: h,
                                ),
                              ),
                            ),
                            if (selected.contains(work.id))
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: scheme.primary.withValues(
                                      alpha: 0.28,
                                    ),
                                    border: Border.all(
                                      color: scheme.primary,
                                      width: 3,
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (work.details.status.isNotEmpty)
                              Positioned(
                                left: 6,
                                bottom: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surface.withValues(
                                      alpha: 0.88,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    work.details.progress > 0 &&
                                            work.details.status != 'completed'
                                        ? '${shelfStatusLabel(context, work.details.status)} · ${work.details.progress}%'
                                        : shelfStatusLabel(
                                            context,
                                            work.details.status,
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          work.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge,
                        ),
                        if (work.creator.isNotEmpty)
                          Text(
                            work.creator,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
