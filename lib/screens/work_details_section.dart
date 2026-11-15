import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../library/models.dart';
import '../library/quote_chips.dart';
import '../people/people_directory.dart';
import '../people/people_service.dart';
import '../tools/work_edit_service.dart';
import 'person_screen.dart';
import '../l10n/l10n.dart';

/// What the server knows about a work, laid out under its title: description, genres, the small facts (publisher,
/// pages, ISBN, series) and the cast or characters. Draws nothing for a work with nothing to show.
class WorkDetailsSection extends StatefulWidget {
  const WorkDetailsSection({
    super.key,
    required this.work,
    this.onFilter,
    this.onChanged,
  });

  final Work work;

  /// Called after a cast change was written to the server, so the page can fetch the work again and redraw; null
  /// (or no server to write to) leaves the cast read-only.
  final Future<void> Function()? onChanged;

  /// Called when a person's page asks for the library filtered by a name; null makes a cast row do nothing.
  final ValueChanged<ChipFilter>? onFilter;

  @override
  State<WorkDetailsSection> createState() => _WorkDetailsSectionState();
}

/// How many cast members show before "Show all".
const castShown = 8;

class _WorkDetailsSectionState extends State<WorkDetailsSection> {
  bool _moreText = false;
  bool _allCast = false;

  bool get _editable =>
      widget.onChanged != null &&
      widget.work.serverId != null &&
      WorkEditScope.of(context) != null;

  bool get _isBook =>
      widget.work.kind == WorkKind.book || widget.work.kind == WorkKind.other;

  /// Runs one write on the server and, when it took, has the page fetch the work again. A refusal is said in the
  /// server's own words and nothing is redrawn.
  Future<void> _write(Future<void> Function(WorkEditService s) op) async {
    final service = WorkEditScope.of(context);
    if (service == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await op(service);
    } on ServerException catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (mounted) await widget.onChanged!();
  }

  Future<void> _editRow([CastMember? row]) async {
    final got = await showDialog<({String character, String actor})>(
      context: context,
      builder: (_) => _CastRowDialog(row: row, withActor: !_isBook),
    );
    if (got == null || !mounted) return;
    if (row == null) {
      await _write(
        (s) =>
            s.addCast(widget.work, character: got.character, actor: got.actor),
      );
    } else {
      await _write(
        (s) => s.editCast(row.id, character: got.character, actor: got.actor),
      );
    }
  }

  Future<void> _fromImdb() async {
    final link = await showDialog<String>(
      context: context,
      builder: (_) => const _ImdbDialog(),
    );
    if (link == null || !mounted) return;
    await _write((s) => s.fetchCastFromImdb(widget.work, link));
  }

  Widget _castMenu(BuildContext context) => PopupMenuButton<String>(
    tooltip: context.tr('app.cast.menu'),
    onSelected: (v) {
      switch (v) {
        case 'add':
          _editRow();
        case 'tvdb':
          _write((s) => s.fetchCastFromTvdb(widget.work));
        case 'imdb':
          _fromImdb();
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'add',
        child: Text(
          context.tr(_isBook ? 'app.cast.add_character' : 'app.cast.add_cast'),
        ),
      ),
      if (!_isBook) ...[
        PopupMenuItem(
          value: 'tvdb',
          child: Text(context.tr('app.cast.fetch_tvdb')),
        ),
        PopupMenuItem(
          value: 'imdb',
          child: Text(context.tr('app.cast.fetch_imdb')),
        ),
      ],
    ],
  );

  Widget _rowMenu(BuildContext context, CastMember c) =>
      PopupMenuButton<String>(
        tooltip: context.tr('app.cast.row_menu'),
        onSelected: (v) {
          switch (v) {
            case 'edit':
              _editRow(c);
            case 'remove':
              _write((s) => s.removeCast(c.id));
            case 'performer':
              _write((s) => s.removeCastActor(c.id));
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'edit',
            child: Text(context.tr('common.action.edit.label')),
          ),
          if (!_isBook && c.actor.isNotEmpty)
            PopupMenuItem(
              value: 'performer',
              child: Text(context.tr('app.cast.remove_performer')),
            ),
          PopupMenuItem(
            value: 'remove',
            child: Text(context.tr('common.action.remove.label')),
          ),
        ],
      );

  /// One cast row: the character's picture (or the actor's), then "Actor as Character". A press opens the page of
  /// the character, or of the actor where the part has no character.
  Widget _castRow(BuildContext context, CastMember c) {
    final scheme = Theme.of(context).colorScheme;
    final label = c.actor.isEmpty
        ? c.character
        : c.character.isEmpty
        ? c.actor
        : '${c.actor} as ${c.character}';
    final chip = c.character.isEmpty
        ? QuoteChip(ChipKind.speaker, c.actor)
        : QuoteChip(ChipKind.character, c.character, c.actor);
    final initial = (c.character.isEmpty ? c.actor : c.character).trim();
    final opens =
        widget.onFilter != null && PeopleServiceScope.of(context) != null;
    return InkWell(
      onTap: opens
          ? () =>
                openPersonPage(context, chip: chip, onFilter: widget.onFilter!)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            PersonFace(
              chip: chip,
              radius: 16,
              fallback: CircleAvatar(
                radius: 16,
                backgroundColor: scheme.tertiaryContainer,
                child: Text(
                  initial.isEmpty
                      ? '?'
                      : initial.characters.first.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: scheme.onTertiaryContainer),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            if (_editable && c.id > 0) _rowMenu(context, c),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.work.details;
    if (d.isEmpty && !_editable) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isBook =
        widget.work.kind == WorkKind.book || widget.work.kind == WorkKind.other;
    final facts = <(String, String)>[
      if (d.subtitle.isNotEmpty)
        (context.tr('common.field.subtitle.label'), d.subtitle),
      if (d.series.isNotEmpty)
        (context.tr('common.field.series.label'), d.series),
      if (d.publisher.isNotEmpty)
        (context.tr('common.field.publisher.label'), d.publisher),
      if (d.pages > 0) (context.tr('common.field.pages.label'), '${d.pages}'),
      if (d.isbn.isNotEmpty) ('ISBN', d.isbn),
    ];
    final cast = _allCast ? d.cast : d.cast.take(castShown).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.description.isNotEmpty) ...[
            Text(
              d.description,
              maxLines: _moreText ? null : 6,
              overflow: _moreText ? null : TextOverflow.ellipsis,
            ),
            if (d.description.length > 280)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _moreText = !_moreText),
                  child: Text(
                    _moreText
                        ? context.tr('common.action.show-less.label')
                        : context.tr('context.more'),
                  ),
                ),
              ),
          ],
          if (d.genres.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final g in d.genres) Chip(label: Text(g))],
            ),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final f in facts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(f.$1, style: theme.textTheme.labelLarge),
                    ),
                    Expanded(child: Text(f.$2)),
                  ],
                ),
              ),
          ],
          if (d.cast.isNotEmpty || _editable) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isBook
                        ? context.tr('stats.breakdown.characters.label')
                        : context.tr('common.field.cast.label'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (_editable) _castMenu(context),
              ],
            ),
            const SizedBox(height: 4),
            for (final c in cast) _castRow(context, c),
            if (d.cast.length > castShown)
              TextButton(
                onPressed: () => setState(() => _allCast = !_allCast),
                child: Text(
                  _allCast
                      ? context.tr('app.dashboard.show_fewer')
                      : context.tr('app.work_details.show_all_n', {
                          'n': d.cast.length,
                        }),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Asks for one cast row: the character and, for a film or show, who played them.
class _CastRowDialog extends StatefulWidget {
  const _CastRowDialog({required this.row, required this.withActor});

  final CastMember? row;
  final bool withActor;

  @override
  State<_CastRowDialog> createState() => _CastRowDialogState();
}

class _CastRowDialogState extends State<_CastRowDialog> {
  late final _character = TextEditingController(text: widget.row?.character);
  late final _actor = TextEditingController(text: widget.row?.actor);

  @override
  void dispose() {
    _character.dispose();
    _actor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        context.tr(
          widget.row == null ? 'app.cast.add_title' : 'app.cast.edit_title',
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _character,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.tr('common.field.character.label'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.withActor)
            TextField(
              controller: _actor,
              decoration: InputDecoration(
                labelText: context.tr('common.field.actor.label'),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.action.cancel.label')),
        ),
        FilledButton(
          // the server refuses a row with no character
          onPressed: _character.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop((
                  character: _character.text.trim(),
                  actor: _actor.text.trim(),
                )),
          child: Text(context.tr('common.action.save.label')),
        ),
      ],
    );
  }
}

/// Asks for the IMDb title the cast is to come from.
class _ImdbDialog extends StatefulWidget {
  const _ImdbDialog();

  @override
  State<_ImdbDialog> createState() => _ImdbDialogState();
}

class _ImdbDialogState extends State<_ImdbDialog> {
  final _link = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('app.cast.fetch_imdb')),
      content: TextField(
        controller: _link,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: context.tr('app.cast.imdb_link'),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.action.cancel.label')),
        ),
        FilledButton(
          onPressed: _link.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_link.text.trim()),
          child: Text(context.tr('app.cast.fetch')),
        ),
      ],
    );
  }
}
