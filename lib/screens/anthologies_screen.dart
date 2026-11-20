import 'package:flutter/material.dart';

import '../anthologies/anthologies.dart';
import '../anthologies/offline_anthologies.dart';
import '../api/api_client.dart' show readWithCopyShown;
import '../app_controller.dart';
import '../capture/photo_source.dart';
import '../harness/harness.dart' show BackupPicker, SystemBackupPicker;
import '../share/share_subject.dart';
import 'share_screen.dart' show openShare;
import '../quiz/quiz.dart' show QuizService;
import 'anthology_tools.dart';
import 'quiz_screen.dart';
import 'quote_form_screen.dart' show quoteColour;
import '../l10n/l10n.dart';
import '../theme/tabler.dart';
import 'offline_note.dart';
import '../theme/material_surface.dart';

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
              textCapitalization: TextCapitalization.words,
              controller: t,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.tr('common.field.title.label'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.sentences,
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
    this.picker,
    this.photos,
    this.quiz,
    this.controller,
    this.embedded = false,
  });

  /// Drawn inside the Boards tab, whose header names the board: no bar of its own.
  final bool embedded;

  /// When given, the list waits for the phone to read its pairing (the tabs are built at start, before that is
  /// known) and reads again if the pairing changes.
  final AppController? controller;

  final AnthologyService service;
  final BackupPicker? picker;
  final PhotoSource? photos;

  /// Where Practise comes from. Null: the anthology has no Practise.
  final QuizService? quiz;

  @override
  State<AnthologiesScreen> createState() => _AnthologiesScreenState();
}

class _AnthologiesScreenState extends State<AnthologiesScreen> {
  List<Anthology>? _all;
  String? _problem;
  bool _wasPaired = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_pairingChanged);
    _load();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_pairingChanged);
    super.dispose();
  }

  void _pairingChanged() {
    final c = widget.controller;
    if (c == null || !mounted) return;
    if (c.loaded && (c.paired != _wasPaired || _all == null)) _load();
  }

  /// Which read is the latest, so a slow one that lands after a newer one cannot put the older list back.
  int _asked = 0;

  /// Draws what the phone holds at once, then asks the server in the background and swaps its answer in. A read
  /// that fails never takes the list off the screen (ADR-0030); only a first load with nothing kept says why.
  ///
  /// [changed] is a read after a change the reader made: the kept copy then already says the change when one waits
  /// for the server (a change is written into it as it is queued), so it is drawn at once instead of waiting for
  /// a server that may not answer, and what was deleted is off the list the moment it was deleted. With nothing
  /// waiting the change went to the server and the kept copy is the older one, so it is not drawn.
  Future<void> _load({bool changed = false}) async {
    final c = widget.controller;
    // the spinner stays until the pairing is known
    if (c != null && !c.loaded) return;
    _wasPaired = c?.paired ?? false;
    final service = widget.service;
    if (service is OfflineAnthologies &&
        (_all == null || (changed && service.pending.value > 0))) {
      final kept = service.keptList(forDraw: true);
      if (kept != null) setState(() => _all = kept);
    }
    final turn = ++_asked;
    try {
      final copyShown = _all != null;
      final all = await (copyShown
          ? readWithCopyShown(service.list)
          : service.list());
      if (mounted && turn == _asked) {
        setState(() {
          _all = all;
          _problem = null;
        });
      }
    } on AnthologyException catch (e) {
      if (mounted && turn == _asked && _all == null) {
        setState(() => _problem = e.message);
      }
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
      await _load(changed: true);
    } on AnthologyException catch (e) {
      if (!mounted) return;
      if (_all == null) {
        setState(() => _problem = e.message);
      } else {
        final m = ScaffoldMessenger.of(context);
        m.clearSnackBars();
        m.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _open(Anthology a) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AnthologyScreen(
          service: widget.service,
          id: a.id,
          picker: widget.picker,
          photos: widget.photos,
          quiz: widget.quiz,
        ),
      ),
    );
    // the opened anthology may have been changed or deleted there
    await _load(changed: true);
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Scaffold(
      appBar: widget.embedded
          ? null
          : ShellAppBar(title: Text(context.tr('nav.tab.anthologies.label'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-anthology',
        onPressed: _create,
        icon: const Icon(Ti.plus),
        label: Text(context.tr('anthologies.list.new.label')),
      ),
      body: Column(
        children: [
          const OfflineNote(),
          _WaitingNote(widget.service),
          Expanded(child: _list(context, all)),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, List<Anthology>? all) {
    return _problem != null
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
        ? Center(child: Text(context.tr('app.anthologies.no_anthologies_yet')))
        : ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 88),
            children: [
              for (final a in all)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  child: SurfaceCard(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 80,
                          child: AnthologyPoster(
                            name: a.posterPath,
                            title: a.title,
                            compact: true,
                          ),
                        ),
                      ),
                      title: Text(a.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (a.description.trim().isNotEmpty)
                            Text(
                              a.description.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(countWords('passage', a.entries)),
                        ],
                      ),
                      trailing: const Icon(Ti.chevronRight),
                      onTap: () => _open(a),
                    ),
                  ),
                ),
            ],
          );
  }
}

/// What waits for the server, and what it refused: shown above the list so a reader who worked with no signal
/// can see their changes are kept (ADR-0022).
class _WaitingNote extends StatelessWidget {
  const _WaitingNote(this.service);

  final AnthologyService service;

  @override
  Widget build(BuildContext context) {
    final s = service;
    if (s is! OfflineAnthologies) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([s.pending, s.problems]),
      builder: (context, _) {
        final n = s.pending.value;
        final refused = s.problems.value;
        if (n == 0 && refused.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SurfaceCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (n > 0)
                    Text(
                      n == 1
                          ? context.tr('app.anthologies.waiting_one')
                          : context.tr('app.anthologies.waiting_many', {
                              'n': n,
                            }),
                    ),
                  for (final r in refused)
                    Text(
                      context.tr('app.anthologies.not_taken', {'reason': r}),
                    ),
                  if (refused.isNotEmpty)
                    TextButton(
                      onPressed: () => s.problems.value = const [],
                      child: Text(context.tr('common.action.done.label')),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
    this.picker,
    this.photos,
    this.quiz,
  });

  final AnthologyService service;
  final int id;
  final QuizService? quiz;

  /// Where a shared file is saved. Null: the system's own.
  final BackupPicker? picker;
  final PhotoSource? photos;

  @override
  State<AnthologyScreen> createState() => _AnthologyScreenState();
}

enum _Menu {
  practise,
  heading,
  group,
  display,
  front,
  fill,
  removed,
  edit,
  delete,
}

class _AnthologyScreenState extends State<AnthologyScreen> {
  AnthologyDetail? _detail;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _asked = 0;

  /// The opened anthology draws from the phone's copy at once the first time; the server's answer replaces it when
  /// it lands, in place, so the reader keeps their scroll. A failed read leaves what is shown alone (ADR-0030).
  /// [changed] is as for the list: a change waiting for the server is already in the kept copy, which is drawn at
  /// once so the reader sees what they just did.
  Future<void> _load({bool changed = false}) async {
    final service = widget.service;
    if (service is OfflineAnthologies &&
        (_detail == null || (changed && service.pending.value > 0))) {
      final kept = service.keptDetail(widget.id, forDraw: true);
      if (kept != null) setState(() => _detail = kept);
    }
    final turn = ++_asked;
    try {
      final copyShown = _detail != null;
      final d = await (copyShown
          ? readWithCopyShown(() => service.get(widget.id))
          : service.get(widget.id));
      if (mounted && turn == _asked) {
        setState(() {
          _detail = d;
          _problem = null;
        });
      }
    } on AnthologyException catch (e) {
      if (mounted && turn == _asked && _detail == null) {
        setState(() => _problem = e.message);
      }
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
      await _load(changed: true);
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

  /// What this passage shows and says in this anthology only (its own choices over the anthology's, and its own
  /// words for the parts of the quote an anthology may restate). The quote in the library is never written.
  Future<void> _display(AnthologyEntry e) async {
    final r = await askEntryDisplay(context, _detail!.anthology, e);
    if (r == null || (r.fields.isEmpty && r.edits.isEmpty)) return;
    await _do(
      () => widget.service.setEntryDisplay(
        widget.id,
        e.kind,
        e.itemId,
        fields: r.fields,
        edits: r.edits,
      ),
    );
  }

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
        final s = await askSwitches(
          context,
          a,
          quoteParts: widget.service.hasEntryDisplay,
        );
        if (s != null) await _do(() => widget.service.setSwitches(a, s));
      case _Menu.front:
        final changed = await editFrontMatter(
          context,
          widget.service,
          a,
          photos: widget.photos,
        );
        if (changed) await _load(changed: true);
      case _Menu.fill:
        final nothingNew = context.tr('app.anthologies.nothing_new_to_add');
        final addedText = context.tr;
        final r = await Navigator.of(context).push<FillResult>(
          MaterialPageRoute(
            builder: (_) => FillScreen(service: widget.service, anthology: a),
          ),
        );
        if (r != null) {
          await _load(changed: true);
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
      case _Menu.edit:
        await _edit();
      case _Menu.delete:
        await _delete();
      case _Menu.removed:
        final back = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                RemovedScreen(service: widget.service, id: widget.id),
          ),
        );
        if (back == true) await _load(changed: true);
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
          case 'display':
            await _display(slot.entry!);
          case 'edit':
            await _editHeading(slot.section!);
          case 'delete':
            await _deleteHeading(slot.section!);
          case 'after':
            await _addHeading(after: slot);
          case 'remove':
            await _remove(slot.entry!);
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
        if (slot.entry != null && widget.service.hasEntryDisplay)
          PopupMenuItem(
            value: 'display',
            child: Text(context.tr('anthologies.entry.display.label')),
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
        // One menu per passage and no loose cross beside it: a second icon on a card a thumb has to hit
        // made the removal one slip away from the menu.
        if (slot.entry != null)
          PopupMenuItem(
            value: 'remove',
            child: Text(
              context.tr('app.anthologies.remove_from_anthology'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
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
    // What THIS passage shows: its own choice if it has one, else the anthology's.
    bool eff(String name) => e.shownIn(a, name);
    final from = [
      if (eff('credit')) e.credit,
      if (eff('source')) e.source,
      if (eff('locator')) e.locator,
    ].map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');
    String line(String part, Map<String, String> values) => [
      for (final sw in anthologySwitches.where((x) => x.part == part))
        if (eff(sw.name) && (values[sw.name] ?? '').trim().isNotEmpty)
          '${sw.label}: ${values[sw.name]!.trim()}',
    ].join(' · ');
    final workLine = line('work', e.work);
    final personLine = line('person', e.person);
    Widget quiet(String text, {bool italic = false}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontStyle: italic ? FontStyle.italic : null,
        ),
      ),
    );
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
        if (eff('commentary') && e.note.trim().isNotEmpty)
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
        SurfaceCard(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Container(
            decoration: !eff('colour')
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
                      if (eff('context') && e.contextBefore.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            e.contextBefore.trim(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      Text(
                        context.tr('app.anthologies.trim', {
                          'trim': e.quote.trim(),
                        }),
                        style: theme.textTheme.titleMedium,
                      ),
                      if (eff('context') && e.contextAfter.trim().isNotEmpty)
                        quiet(e.contextAfter.trim(), italic: true),
                      if (from.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            context.tr('app.anthologies.from', {'from': from}),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      if (eff('date') && e.date.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(e.date, style: theme.textTheme.bodySmall),
                        ),
                      if (eff('translation') && e.translation.trim().isNotEmpty)
                        quiet(e.translation.trim(), italic: true),
                      if (eff('note') && e.quoteNote.trim().isNotEmpty)
                        quiet(e.quoteNote.trim()),
                      if (eff('language') && e.language.trim().isNotEmpty)
                        quiet(e.language.trim()),
                      if (eff('tags') && e.tags.isNotEmpty)
                        quiet(e.tags.join(' · ')),
                      if (workLine.isNotEmpty) quiet(workLine),
                      if (personLine.isNotEmpty) quiet(personLine),
                    ],
                  ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AnthologyPoster(name: a.posterPath, title: a.title),
          ),
        ),
        if (a.description.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(a.description.trim(), style: theme.textTheme.bodyLarge),
          ),
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
      appBar: ShellAppBar(
        title: Text(
          d?.anthology.title ?? context.tr('common.field.anthology.label'),
        ),
        actions: [
          if (d != null) ...[
            IconButton(
              tooltip: context.tr('common.action.share.label'),
              icon: const Icon(Ti.share2),
              onPressed: () => openShare(
                context,
                AnthologyShare(d, widget.service),
                picker: widget.picker ?? const SystemBackupPicker(),
              ),
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
                // Edit and Delete live here and not as two more icons in the bar: four icons left the title
                // eight letters ("Stoic mo..."), where the reader is there to read it.
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _Menu.edit,
                  child: Text(context.tr('common.action.edit.label')),
                ),
                PopupMenuItem(
                  value: _Menu.delete,
                  child: Text(
                    context.tr('common.action.delete.label'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          const OfflineNote(),
          Expanded(
            child: _problem != null
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
          ),
        ],
      ),
    );
  }
}

/// Asks which anthology: the phone's own list at once, the server's swapped in behind it. Returns the [Anthology],
/// the string `'new'`, or null (dismissed, or nothing could be read and a message said so).
Future<Object?> chooseAnthology(
  BuildContext context,
  AnthologyService service,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final kept = service is OfflineAnthologies
      ? service.keptList(forDraw: true)
      : null;
  final shown = ValueNotifier<List<Anthology>?>(kept);
  // The route is made here, not by showDialog, so the read's own failure can close exactly this route: it may land
  // before the dialog has been drawn (nothing to find through a context yet) or while the reader is dismissing it
  // (a pop then would close the screen beneath).
  final route = DialogRoute<Object>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.tr('common.action.anthology.label')),
      children: [
        const OfflineNote(),
        ValueListenableBuilder<List<Anthology>?>(
          valueListenable: shown,
          builder: (context, all, _) => all == null
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in all)
                      SimpleDialogOption(
                        onPressed: () => Navigator.of(context).pop(a),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(a.title),
                        ),
                      ),
                  ],
                ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop('new'),
          child: Text(context.tr('app.anthologies.a_new_anthology')),
        ),
      ],
    ),
  );
  var closed = false;
  (kept != null ? readWithCopyShown(service.list) : service.list()).then<void>(
    (all) {
      if (!closed) shown.value = all;
    },
    onError: (Object e) {
      if (closed) return;
      // a failed read leaves a list that is showing alone; with nothing shown it says why and gives the door back
      if (shown.value != null) return;
      final reason = e is AnthologyException ? e.message : '$e';
      messenger.showSnackBar(SnackBar(content: Text(reason)));
      if (route.isCurrent) navigator.pop();
    },
  );
  try {
    return await navigator.push<Object>(route);
  } finally {
    closed = true;
    shown.dispose();
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
  final chosen = await chooseAnthology(context, service);
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
