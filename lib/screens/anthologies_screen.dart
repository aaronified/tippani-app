import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../capture/photo_source.dart';
import '../harness/harness.dart' show BackupPicker;
import '../harness/log_screen.dart' show ShareText, shareThroughSheet;
import '../quiz/quiz.dart' show QuizService;
import 'anthology_tools.dart';
import 'quiz_screen.dart';
import 'quote_form_screen.dart' show quoteColour;
import '../l10n/l10n.dart';

/// An anthology as plain text to send: its title and introduction, then each passage with where it is from and the
/// reader's commentary on it.
String anthologyShareText(AnthologyDetail d) {
  final out = StringBuffer(d.anthology.title);
  if (d.anthology.intro.trim().isNotEmpty) {
    out.write('\n\n${d.anthology.intro.trim()}');
  }
  for (final e in d.entries) {
    out.write('\n\n“${e.quote.trim()}”');
    if (e.from.isNotEmpty) out.write('\n— ${e.from}');
    if (e.note.trim().isNotEmpty) out.write('\n${e.note.trim()}');
  }
  return out.toString();
}

/// Asks for a title and an introduction. Null if the reader backs out.
Future<({String title, String intro})?> askAnthologyText(
  BuildContext context, {
  String title = '',
  String intro = '',
  required String heading,
}) {
  final t = TextEditingController(text: title);
  final i = TextEditingController(text: intro);
  return showDialog<({String title, String intro})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(heading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: t,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.tr('common.field.title.label'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: i,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: context.tr('anthologies.form.intro.label'),
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
            onPressed: t.text.trim().isEmpty
                ? null
                : () =>
                      Navigator.of(context)
                          .pop((title: t.text.trim(), intro: i.text.trim())),
            child: Text(context.tr('common.action.save.label')),
          ),
        ],
      ),
    ),
  );
}

/// Your anthologies on the server: collections of quotes you have gathered and ordered. Needs a paired server.
class AnthologiesScreen extends StatefulWidget {
  const AnthologiesScreen({
    super.key,
    required this.service,
    this.share = shareThroughSheet,
    this.picker,
    this.shareFile = shareFileThroughSheet,
    this.photos,
    this.quiz,
  });

  final AnthologyService service;
  final ShareText share;
  final BackupPicker? picker;
  final ShareFile shareFile;
  final PhotoSource? photos;

  /// Where Practise comes from. Null: the anthology has no Practise.
  final QuizService? quiz;

  @override
  State<AnthologiesScreen> createState() => _AnthologiesScreenState();
}

class _AnthologiesScreenState extends State<AnthologiesScreen> {
  List<Anthology>? _all;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.service.list();
      if (mounted) {
        setState(() {
          _all = all;
          _problem = null;
        });
      }
    } on AnthologyException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<void> _create() async {
    final text = await askAnthologyText(
      context,
      heading: context.tr('anthologies.list.new.label'),
    );
    if (text == null) return;
    try {
      await widget.service.create(text.title, text.intro);
      await _load();
    } on AnthologyException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<void> _open(Anthology a) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AnthologyScreen(
          service: widget.service,
          id: a.id,
          share: widget.share,
          picker: widget.picker,
          shareFile: widget.shareFile,
          photos: widget.photos,
          quiz: widget.quiz,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('nav.tab.anthologies.label'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-anthology',
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(context.tr('anthologies.list.new.label')),
      ),
      body: _problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_problem!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: Text(context.tr('common.source.retry')),
                    ),
                  ],
                ),
              ),
            )
          : all == null
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
          ? Center(
              child: Text(context.tr('app.anthologies.no_anthologies_yet')),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              children: [
                for (final a in all)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: AnthologyCover(
                            name: a.coverPath,
                            width: 40,
                            height: 56,
                            fallback: const SizedBox(
                              width: 40,
                              height: 56,
                              child: Icon(Icons.collections_bookmark_outlined),
                            ),
                          ),
                        ),
                        title: Text(a.title),
                        subtitle: Text(countWords('passage', a.entries)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _open(a),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// One anthology, read in its own order: the cover, epigraph and dedication, the introduction, then passages and
/// headings that can be dragged into place, given commentary, and grouped. From here it is also filled from a
/// search, given a cover, switched to show more or less of each passage, exported, shared, renamed or deleted.
class AnthologyScreen extends StatefulWidget {
  const AnthologyScreen({
    super.key,
    required this.service,
    required this.id,
    this.share = shareThroughSheet,
    this.picker,
    this.shareFile = shareFileThroughSheet,
    this.photos,
    this.quiz,
  });

  final AnthologyService service;
  final int id;
  final ShareText share;
  final QuizService? quiz;

  /// Where an exported file is saved. Null: only sending is offered.
  final BackupPicker? picker;
  final ShareFile shareFile;
  final PhotoSource? photos;

  @override
  State<AnthologyScreen> createState() => _AnthologyScreenState();
}

enum _Menu { practise, heading, group, display, front, fill, removed, export }

class _AnthologyScreenState extends State<AnthologyScreen> {
  AnthologyDetail? _detail;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.service.get(widget.id);
      if (mounted) {
        setState(() {
          _detail = d;
          _problem = null;
        });
      }
    } on AnthologyException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  void _say(String message) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs a change on the server, reads the anthology again, and says what went wrong in words.
  Future<void> _do(Future<void> Function() run) async {
    try {
      await run();
      await _load();
    } on AnthologyException catch (e) {
      if (mounted) _say(e.message);
    }
  }

  Future<void> _edit() async {
    final a = _detail!.anthology;
    final text = await askAnthologyText(
      context,
      heading: context.tr('anthologies.form.edit.title'),
      title: a.title,
      intro: a.intro,
    );
    if (text == null) return;
    await _do(
      () => widget.service.edit(a, title: text.title, intro: text.intro),
    );
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.tr('quotes.board.delete.confirm.title', {
            'name': _detail!.anthology.title,
          }),
        ),
        content: Text(
          context.tr('app.anthologies.the_anthology_is_removed_from_the'),
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
    try {
      await widget.service.delete(widget.id);
      if (mounted) Navigator.of(context).pop(true);
    } on AnthologyException catch (e) {
      if (mounted) _say(e.message);
    }
  }

  Future<void> _remove(AnthologyEntry e) =>
      _do(() => widget.service.removeEntry(widget.id, e.kind, e.itemId));

  Future<void> _commentary(AnthologyEntry e) async {
    final note = await askCommentary(context, e.note);
    if (note == null || note == e.note) return;
    await _do(() => widget.service.setNote(widget.id, e.kind, e.itemId, note));
  }

  Future<void> _addHeading({AnthologySlot? after}) async {
    final s = await askSection(
      context,
      heading: context.tr('app.anthologies.new_heading'),
    );
    if (s == null) return;
    await _do(
      () => widget.service.addSection(
        widget.id,
        s.title,
        s.prose,
        after: after?.ref,
      ),
    );
  }

  Future<void> _editHeading(AnthologySection s) async {
    final r = await askSection(
      context,
      heading: context.tr('app.anthologies.edit_heading'),
      title: s.title,
      prose: s.prose,
    );
    if (r == null) return;
    await _do(
      () => widget.service.editSection(widget.id, s.id, r.title, r.prose),
    );
  }

  Future<void> _deleteHeading(AnthologySection s) =>
      _do(() => widget.service.deleteSection(widget.id, s.id));

  /// Moves [slots] item [from] so that it follows the item that is at [to] among the others (null: first).
  Future<void> _moveTo(List<AnthologySlot> slots, int from, int to) async {
    final moving = slots[from];
    final rest = [...slots]..removeAt(from);
    final after = to <= 0 ? null : rest[to - 1].ref;
    if (to == from) return;
    await _do(
      () => widget.service.move(
        widget.id,
        moving.ref.kind,
        moving.ref.itemId,
        after: after,
      ),
    );
  }

  Future<void> _menu(_Menu m) async {
    final d = _detail!;
    final a = d.anthology;
    switch (m) {
      case _Menu.practise:
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => QuizScreen(
              service: widget.quiz!,
              mode: QuizMode.practice,
              anthology: widget.id,
            ),
          ),
        );
      case _Menu.heading:
        await _addHeading();
      case _Menu.group:
        final by = await askGrouping(context, a.groupBy);
        if (by != null && by != a.groupBy) {
          await _do(() => widget.service.setGrouping(widget.id, by));
        }
      case _Menu.display:
        final s = await askSwitches(context, a);
        if (s != null) await _do(() => widget.service.setSwitches(a, s));
      case _Menu.front:
        final changed = await editFrontMatter(
          context,
          widget.service,
          a,
          photos: widget.photos,
        );
        if (changed) await _load();
      case _Menu.fill:
        final nothingNew = context.tr('app.anthologies.nothing_new_to_add');
        final addedText = context.tr;
        final r = await Navigator.of(context).push<FillResult>(
          MaterialPageRoute(
            builder: (_) => FillScreen(service: widget.service, anthology: a),
          ),
        );
        if (r != null) {
          await _load();
          _say(
            r.added == 0
                ? nothingNew
                : r.added == 1
                ? addedText(tx('app.anthologies.added_one_passage'))
                : addedText(tx('app.anthologies.added_n_passages'), {
                    'n': r.added,
                  }),
          );
        }
      case _Menu.removed:
        final back = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                RemovedScreen(service: widget.service, id: widget.id),
          ),
        );
        if (back == true) await _load();
      case _Menu.export:
        final choice = await askExport(context);
        if (choice == null) return;
        try {
          final f = await widget.service.export(widget.id, epub: choice.epub);
          if (choice.action == ExportAction.send || widget.picker == null) {
            await widget.shareFile(f.bytes, f.name);
          } else {
            final saved = await widget.picker!.save(f.name, f.bytes);
            if (saved && mounted) {
              _say(context.tr('app.admin_backup.saved_name', {'name': f.name}));
            }
          }
        } on AnthologyException catch (e) {
          if (mounted) _say(e.message);
        }
    }
  }

  Widget _passage(
    BuildContext context,
    AnthologyDetail d,
    List<AnthologySlot> slots,
    int i,
  ) {
    final theme = Theme.of(context);
    final a = d.anthology;
    final slot = slots[i];
    final key = ValueKey(
      slot.entry != null ? 'e-${slot.entry!.ref}' : 's-${slot.section!.id}',
    );

    final menu = PopupMenuButton<String>(
      tooltip: context.tr('app.anthologies.more_for_this_one'),
      onSelected: (v) async {
        switch (v) {
          case 'up':
            await _moveTo(slots, i, i - 1);
          case 'down':
            await _moveTo(slots, i, i + 1);
          case 'note':
            await _commentary(slot.entry!);
          case 'edit':
            await _editHeading(slot.section!);
          case 'delete':
            await _deleteHeading(slot.section!);
          case 'after':
            await _addHeading(after: slot);
        }
      },
      itemBuilder: (_) => [
        if (i > 0)
          PopupMenuItem(
            value: 'up',
            child: Text(context.tr('common.action.move-up.label')),
          ),
        if (i < slots.length - 1)
          PopupMenuItem(
            value: 'down',
            child: Text(context.tr('common.action.move-down.label')),
          ),
        if (slot.entry != null)
          PopupMenuItem(
            value: 'note',
            child: Text(context.tr('app.anthologies.commentary')),
          ),
        if (slot.section != null) ...[
          PopupMenuItem(
            value: 'edit',
            child: Text(context.tr('app.anthologies.edit_heading')),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text(context.tr('app.anthologies.delete_heading')),
          ),
        ],
        PopupMenuItem(
          value: 'after',
          child: Text(context.tr('app.anthologies.add_a_heading_after')),
        ),
      ],
    );

    if (slot.section != null) {
      final s = slot.section!;
      return Padding(
        key: key,
        padding: const EdgeInsets.fromLTRB(16, 20, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title, style: theme.textTheme.titleLarge),
                  if (s.prose.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(s.prose, style: theme.textTheme.bodyMedium),
                    ),
                ],
              ),
            ),
            menu,
          ],
        ),
      );
    }

    final e = slot.entry!;
    final by = a.groupBy;
    final prev = i > 0 ? slots[i - 1].entry : null;
    final gk = e.groupKey(by);
    final header =
        by.isNotEmpty &&
        gk.isNotEmpty &&
        (prev == null || prev.groupKey(by) != gk);
    final from = [
      if (!a.flag('hide_credit')) e.credit,
      if (!a.flag('hide_source')) e.source,
      if (a.flag('show_locator')) e.locator,
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              e.groupLabel(by),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (!a.flag('hide_commentary') && e.note.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              e.note.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Container(
            decoration: a.flag('hide_colour')
                ? null
                : BoxDecoration(
                    border: Border(
                      left: BorderSide(color: quoteColour(e.color), width: 6),
                    ),
                  ),
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('app.anthologies.trim', {
                          'trim': e.quote.trim(),
                        }),
                        style: theme.textTheme.titleMedium,
                      ),
                      if (from.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            context.tr('app.anthologies.from', {'from': from}),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      if (a.flag('show_date') && e.date.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(e.date, style: theme.textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.tr('app.anthologies.remove_from_anthology'),
                  icon: const Icon(Icons.close),
                  onPressed: () => _remove(e),
                ),
                menu,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _front(BuildContext context, AnthologyDetail d) {
    final theme = Theme.of(context);
    final a = d.anthology;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (a.coverPath.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AnthologyCover(
                  name: a.coverPath,
                  width: 180,
                  height: 250,
                  fallback: const SizedBox(width: 180, height: 250),
                ),
              ),
            ),
          ),
        if (a.dedication.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Center(
              child: Text(
                a.dedication.trim(),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        if (a.epigraph.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
            child: Text(
              a.epigraph.trim(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (a.intro.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(a.intro, style: theme.textTheme.bodyLarge),
          ),
        if (d.entries.isEmpty && d.sections.isEmpty)
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              context.tr('app.anthologies.nothing_in_this_anthology_yet_open'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final slots = d?.slots ?? const <AnthologySlot>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          d?.anthology.title ?? context.tr('common.field.anthology.label'),
        ),
        actions: [
          if (d != null) ...[
            IconButton(
              tooltip: context.tr('common.action.share.label'),
              icon: const Icon(Icons.ios_share),
              onPressed: () =>
                  widget.share(anthologyShareText(d), d.anthology.title),
            ),
            IconButton(
              tooltip: context.tr('common.action.edit.label'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
            IconButton(
              tooltip: context.tr('common.action.delete.label'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
            PopupMenuButton<_Menu>(
              tooltip: context.tr('settings.appearance.contrast.more.label'),
              onSelected: _menu,
              itemBuilder: (_) => [
                if (widget.quiz?.available == true && d.entries.isNotEmpty)
                  PopupMenuItem(
                    value: _Menu.practise,
                    child: Text(context.tr('common.action.practise.label')),
                  ),
                PopupMenuItem(
                  value: _Menu.fill,
                  child: Text(context.tr('app.anthologies.fill_from')),
                ),
                PopupMenuItem(
                  value: _Menu.heading,
                  child: Text(context.tr('app.anthologies.add_a_heading')),
                ),
                PopupMenuItem(
                  value: _Menu.group,
                  child: Text(context.tr('app.anthologies.group_by')),
                ),
                PopupMenuItem(
                  value: _Menu.display,
                  child: Text(context.tr('app.anthologies.what_it_shows')),
                ),
                PopupMenuItem(
                  value: _Menu.front,
                  child: Text(context.tr('app.anthologies.cover_and_front')),
                ),
                PopupMenuItem(
                  value: _Menu.removed,
                  child: Text(context.tr('app.anthologies.taken_out')),
                ),
                PopupMenuItem(
                  value: _Menu.export,
                  child: Text(context.tr('app.anthologies.export')),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _problem != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_problem!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: Text(context.tr('common.source.retry')),
                    ),
                  ],
                ),
              ),
            )
          : d == null
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
              header: _front(context, d),
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: slots.length,
              onReorderItem: (from, to) => _moveTo(slots, from, to),
              itemBuilder: (context, i) => _passage(context, d, slots, i),
            ),
    );
  }
}

/// Lets the reader choose an anthology and adds [kind]/[itemId] to it. Says what happened in a message.
Future<void> addToAnthologyDialog(
  BuildContext context,
  AnthologyService service, {
  required String kind,
  required int itemId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final tr = context.tr;
  List<Anthology> all;
  try {
    all = await service.list();
  } on AnthologyException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;
  final chosen = await showDialog<Object>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.tr('common.action.anthology.label')),
      children: [
        for (final a in all)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(a),
            child: Text(a.title),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop('new'),
          child: Text(context.tr('app.anthologies.a_new_anthology')),
        ),
      ],
    ),
  );
  if (chosen == null) return;
  try {
    Anthology target;
    if (chosen == 'new') {
      if (!context.mounted) return;
      final text = await askAnthologyText(
        context,
        heading: context.tr('anthologies.list.new.label'),
      );
      if (text == null) return;
      target = await service.create(text.title, text.intro);
    } else {
      target = chosen as Anthology;
    }
    final added = await service.add(target.id, kind, itemId);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added
              ? tr('app.anthologies.added_to_title', {'title': target.title})
              : tr('app.anthologies.already_in_title', {'title': target.title}),
        ),
      ),
    );
  } on AnthologyException catch (e) {
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
