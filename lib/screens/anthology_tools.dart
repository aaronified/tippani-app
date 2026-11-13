import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../anthologies/anthologies.dart';
import '../capture/photo_source.dart';
import '../library/cover_cache.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

/// Sends a file through Android's share sheet. A function so a test can stand in for it.
typedef ShareFile = Future<void> Function(Uint8List bytes, String fileName);

Future<void> shareFileThroughSheet(Uint8List bytes, String fileName) async {
  final epub = fileName.toLowerCase().endsWith('.epub');
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          bytes,
          mimeType: epub ? 'application/epub+zip' : 'text/markdown',
          name: fileName,
        ),
      ],
      fileNameOverrides: [fileName],
    ),
  );
}

/// A cover picture of an anthology, or [fallback] while there is none (and while it loads).
class AnthologyCover extends StatelessWidget {
  const AnthologyCover({
    super.key,
    required this.name,
    required this.width,
    required this.height,
    required this.fallback,
  });

  final String name;
  final double width, height;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final source = CoverScope.of(context);
    if (name.isEmpty || source == null) return fallback;
    return FutureBuilder<File?>(
      future: source.fileFor(name),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) return fallback;
        return Image.file(
          f,
          width: width,
          height: height,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback,
        );
      },
    );
  }
}

/// An anthology's landscape poster: the picture the reader gave it, or one drawn from its title while there is
/// none, so every anthology looks like a book on a shelf. [aspect] is width over height.
class AnthologyPoster extends StatelessWidget {
  const AnthologyPoster({
    super.key,
    required this.name,
    required this.title,
    this.aspect = 16 / 9,
    this.compact = false,
  });

  final String name, title;
  final double aspect;

  /// A thumbnail in a row: the title is left to the row beside it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final drawn = Container(
      alignment: Alignment.center,
      padding: EdgeInsets.all(compact ? 4 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.secondaryContainer],
        ),
      ),
      child: compact
          ? Icon(Ti.books, color: scheme.onPrimaryContainer)
          : Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
    return AspectRatio(
      aspectRatio: aspect,
      child: AnthologyCover(
        name: name,
        width: double.infinity,
        height: double.infinity,
        fallback: SizedBox.expand(child: drawn),
      ),
    );
  }
}

/// Asks for a heading and the words under it. Null if the reader backs out.
Future<({String title, String prose})?> askSection(
  BuildContext context, {
  String title = '',
  String prose = '',
  required String heading,
}) {
  final t = TextEditingController(text: title);
  final p = TextEditingController(text: prose);
  return showDialog<({String title, String prose})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(heading),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                textCapitalization: TextCapitalization.words,
                controller: t,
                autofocus: true,
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.tr('anthologies.section.heading.label'),
                ),
              ),
              TextField(
                textCapitalization: TextCapitalization.sentences,
                controller: p,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: context.tr(
                    'app.anthology_tools.words_under_it_optional',
                  ),
                ),
              ),
            ],
          ),
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
                          .pop((title: t.text.trim(), prose: p.text.trim())),
            child: Text(context.tr('common.action.save.label')),
          ),
        ],
      ),
    ),
  );
}

/// Asks for the reader's commentary on one passage. Null if the reader backs out; '' clears it.
Future<String?> askCommentary(BuildContext context, String note) {
  final c = TextEditingController(text: note);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('app.anthologies.commentary')),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: context.tr(
            'app.anthology_tools.your_words_for_this_passage_shown',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.action.cancel.label')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(c.text.trim()),
          child: Text(context.tr('common.action.save.label')),
        ),
      ],
    ),
  );
}

/// How passages are grouped under headings.
Future<String?> askGrouping(BuildContext context, String current) =>
    showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.tr('app.anthology_tools.group_passages_by')),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (v) => Navigator.of(context).pop(v ?? ''),
            child: Column(
              children: [
                for (final (value, label) in [
                  ('', context.tr('anthologies.group.none')),
                  ('work', context.tr('app.anthology_tools.book_or_film')),
                  ('person', context.tr('bin.kind.person.label')),
                  ('character', context.tr('common.field.character.label')),
                ])
                  RadioListTile<String>(value: value, title: Text(label)),
              ],
            ),
          ),
        ],
      ),
    );

/// Which parts of each passage the anthology shows. Null if the reader backs out.
Future<Map<String, bool>?> askSwitches(BuildContext context, Anthology a) {
  // on = shown; the server stores a "hide" switch the other way up
  final shown = {
    for (final s in anthologySwitches)
      s.key: s.hide ? !a.flag(s.key) : a.flag(s.key),
  };
  return showDialog<Map<String, bool>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(context.tr('app.anthology_tools.what_it_shows')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in anthologySwitches)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr(s.label)),
                value: shown[s.key]!,
                onChanged: (v) => setState(() => shown[s.key] = v),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop({
              for (final s in anthologySwitches)
                s.key: s.hide ? !shown[s.key]! : shown[s.key]!,
            }),
            child: Text(context.tr('common.action.save.label')),
          ),
        ],
      ),
    ),
  );
}

/// The epigraph, the dedication and the cover. The cover is changed at once; the words when the reader saves.
/// True when anything changed.
Future<bool> editFrontMatter(
  BuildContext context,
  AnthologyService service,
  Anthology a, {
  PhotoSource? photos,
}) async {
  final epigraph = TextEditingController(text: a.epigraph);
  final dedication = TextEditingController(text: a.dedication);
  final description = TextEditingController(text: a.description);
  var cover = a.coverPath;
  var poster = a.posterPath;
  var changed = false;
  String? problem;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(context.tr('app.anthology_tools.front_of_the_book')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AnthologyCover(
                      name: cover,
                      width: 64,
                      height: 88,
                      fallback: Container(
                        width: 64,
                        height: 88,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHigh,
                        child: const Icon(Ti.photo),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () async {
                            try {
                              final path = await (photos ?? DevicePhotos())
                                  .choose();
                              if (path == null) return;
                              final bytes = await File(path).readAsBytes();
                              final name = path.split(RegExp(r'[\\/]')).last;
                              final made = await service.setCover(
                                a.id,
                                bytes,
                                name,
                              );
                              setState(() {
                                cover = made;
                                changed = true;
                                problem = null;
                              });
                            } on AnthologyException catch (e) {
                              setState(() => problem = e.message);
                            }
                          },
                          child: Text(
                            cover.isEmpty
                                ? context.tr('app.anthology_tools.add_a_cover')
                                : context.tr(
                                    'app.anthology_tools.change_cover',
                                  ),
                          ),
                        ),
                        if (cover.isNotEmpty)
                          TextButton(
                            onPressed: () async {
                              try {
                                await service.removeCover(a.id);
                                setState(() {
                                  cover = '';
                                  changed = true;
                                  problem = null;
                                });
                              } on AnthologyException catch (e) {
                                setState(() => problem = e.message);
                              }
                            },
                            child: Text(
                              context.tr('app.anthology_tools.remove_cover'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AnthologyPoster(name: poster, title: a.title),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        final path = await (photos ?? DevicePhotos()).choose();
                        if (path == null) return;
                        final bytes = await File(path).readAsBytes();
                        final name = path.split(RegExp(r'[\\/]')).last;
                        final made = await service.setPoster(a.id, bytes, name);
                        setState(() {
                          poster = made;
                          changed = true;
                          problem = null;
                        });
                      } on AnthologyException catch (e) {
                        setState(() => problem = e.message);
                      }
                    },
                    child: Text(
                      poster.isEmpty
                          ? context.tr('app.anthology_tools.add_a_poster')
                          : context.tr('app.anthology_tools.change_poster'),
                    ),
                  ),
                  if (poster.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        try {
                          await service.removePoster(a.id);
                          setState(() {
                            poster = '';
                            changed = true;
                            problem = null;
                          });
                        } on AnthologyException catch (e) {
                          setState(() => problem = e.message);
                        }
                      },
                      child: Text(
                        context.tr('app.anthology_tools.remove_poster'),
                      ),
                    ),
                ],
              ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    problem!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                textCapitalization: TextCapitalization.sentences,
                controller: description,
                minLines: 3,
                maxLines: 8,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: context.tr('app.anthology_tools.description'),
                ),
              ),
              TextField(
                textCapitalization: TextCapitalization.sentences,
                controller: epigraph,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: context.tr('anthologies.front.epigraph.label'),
                ),
              ),
              TextField(
                textCapitalization: TextCapitalization.sentences,
                controller: dedication,
                minLines: 1,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: context.tr('anthologies.front.dedication.label'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('common.action.close.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('common.action.save.label')),
          ),
        ],
      ),
    ),
  );
  if (saved == true &&
      (epigraph.text.trim() != a.epigraph ||
          dedication.text.trim() != a.dedication ||
          description.text.trim() != a.description)) {
    try {
      await service.setFront(
        a.id,
        epigraph.text.trim(),
        dedication.text.trim(),
        // named only when the reader changed it, so a copy older than a description written on the web
        // does not send that description back empty
        description: description.text.trim() != a.description
            ? description.text.trim()
            : null,
      );
      changed = true;
    } on AnthologyException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
  return changed;
}

/// What the reader chooses to do with an exported file.
enum ExportAction { save, send }

/// Asks what to export and what to do with it. Null if the reader backs out.
Future<({bool epub, ExportAction action})?> askExport(
  BuildContext context,
) => showModalBottomSheet<({bool epub, ExportAction action})>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (epub, label) in [
          (false, context.tr('share.format.markdown.name')),
          (true, context.tr('app.anthology_tools.epub_book')),
        ]) ...[
          ListTile(
            leading: const Icon(Ti.deviceFloppy),
            title: Text(
              context.tr('app.anthology_tools.save_as_label', {'label': label}),
            ),
            onTap: () =>
                Navigator.of(context)
                    .pop((epub: epub, action: ExportAction.save)),
          ),
          ListTile(
            leading: const Icon(Ti.share2),
            title: Text(
              context.tr('app.anthology_tools.send_as_label', {'label': label}),
            ),
            onTap: () =>
                Navigator.of(context)
                    .pop((epub: epub, action: ExportAction.send)),
          ),
        ],
      ],
    ),
  ),
);

/// The passages the reader took out, each with a button to put it back where it was.
class RemovedScreen extends StatefulWidget {
  const RemovedScreen({super.key, required this.service, required this.id});

  final AnthologyService service;
  final int id;

  @override
  State<RemovedScreen> createState() => _RemovedScreenState();
}

class _RemovedScreenState extends State<RemovedScreen> {
  List<RemovedPassage>? _all;
  String? _problem;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.service.removed(widget.id);
      if (mounted) {
        setState(() {
          _all = r;
          _problem = null;
        });
      }
    } on AnthologyException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<void> _put(RemovedPassage p) async {
    try {
      await widget.service.restore(widget.id, p.kind, p.itemId);
      _restored = true;
      await _load();
    } on AnthologyException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_restored);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('app.anthology_tools.taken_out')),
        ),
        body: _problem != null
            ? Center(child: Text(_problem!))
            : all == null
            ? const Center(child: CircularProgressIndicator())
            : all.isEmpty
            ? Center(
                child: Text(
                  context.tr(
                    'app.anthology_tools.nothing_was_taken_out_of_this',
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      context.tr(
                        'app.anthology_tools.a_passage_you_take_out_stays',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  for (final p in all)
                    Card(
                      child: ListTile(
                        title: Text(
                          context.tr('app.anthologies.trim', {
                            'trim': p.quote.trim(),
                          }),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            p.credit,
                            p.source,
                          ].where((s) => s.trim().isNotEmpty).join(', '),
                        ),
                        trailing: TextButton(
                          onPressed: () => _put(p),
                          child: Text(
                            context.tr('app.anthology_tools.put_back'),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Chooses a search that fills the anthology, shows what it would take, and fills it. Pops true after a fill.
class FillScreen extends StatefulWidget {
  const FillScreen({super.key, required this.service, required this.anthology});

  final AnthologyService service;
  final Anthology anthology;

  @override
  State<FillScreen> createState() => _FillScreenState();
}

class _FillScreenState extends State<FillScreen> {
  FillVocabulary _vocab = const FillVocabulary();
  FillSource _source = FillSource.all;
  String _value = '';
  String _from = '', _to = '';
  bool _auto = false;
  bool _busy = false;
  String? _problem;
  FillResult? _preview;
  bool _filled = false;

  @override
  void initState() {
    super.initState();
    _auto = widget.anthology.ruleAuto;
    widget.service.vocabulary().then(
      (v) {
        if (mounted) setState(() => _vocab = v);
      },
      onError: (_) {
        // the lists are a convenience; "everything", favourites and dates still work without them
      },
    );
  }

  String get _rule => fillRule(_source, value: _value, from: _from, to: _to);

  List<({String key, String name})> get _options => switch (_source) {
    FillSource.book => _vocab.books,
    FillSource.movie => _vocab.movies,
    FillSource.colour => _vocab.colours,
    FillSource.tag => [for (final t in _vocab.tags) (key: t, name: t)],
    FillSource.author => [for (final t in _vocab.authors) (key: t, name: t)],
    FillSource.shelf => [for (final t in _vocab.shelves) (key: t, name: t)],
    _ => const [],
  };

  Future<void> _run({required bool preview}) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final r = await widget.service.fill(
        widget.anthology.id,
        _rule,
        preview: preview,
        auto: _auto,
      );
      if (!mounted) return;
      if (preview) {
        setState(() => _preview = r);
      } else {
        _filled = true;
        Navigator.of(context).pop(r);
      }
    } on AnthologyException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDate: now,
    );
    if (d == null) return;
    final s =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    setState(() {
      if (from) {
        _from = s;
      } else {
        _to = s;
      }
      _preview = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _options;
    final ready = _rule.isNotEmpty;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('app.anthology_tools.fill_from')),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              context.tr(
                'app.anthology_tools.choose_where_the_passages_come_from',
              ),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in FillSource.values)
                  ChoiceChip(
                    label: Text(context.tr(s.label)),
                    selected: _source == s,
                    onSelected: (_) => setState(() {
                      _source = s;
                      _value = '';
                      _preview = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_source.field != null)
              DropdownMenu<String>(
                key: ValueKey(_source),
                expandedInsets: EdgeInsets.zero,
                enableFilter: true,
                requestFocusOnTap: true,
                label: Text(context.tr(_source.label)),
                dropdownMenuEntries: [
                  for (final o in options)
                    DropdownMenuEntry(value: o.key, label: o.name),
                ],
                onSelected: (v) => setState(() {
                  _value = v ?? '';
                  _preview = null;
                }),
              ),
            if (_source == FillSource.dates)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(true),
                      child: Text(
                        _from.isEmpty
                            ? context.tr('anthologies.fill.from.label')
                            : context.tr('app.anthology_tools.from_from', {
                                'from': _from,
                              }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(false),
                      child: Text(
                        _to.isEmpty
                            ? 'To'
                            : context.tr('app.anthology_tools.to_to', {
                                'to': _to,
                              }),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.tr(
                  'app.anthology_tools.keep_adding_as_new_quotes_arrive',
                ),
              ),
              value: _auto,
              onChanged: (v) => setState(() {
                _auto = v;
                _preview = null;
              }),
            ),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _problem!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (_preview != null) ...[
              const SizedBox(height: 8),
              Text(
                _preview!.matched == 0
                    ? context.tr('app.search.nothing_matches')
                    : context.tr(
                        _preview!.matched == 1
                            ? tx('app.anthology_tools.preview_one')
                            : tx('app.anthology_tools.preview_many'),
                        {
                          'n': _preview!.matched,
                          'add': _preview!.matched - _preview!.skipped,
                        },
                      ),
                style: theme.textTheme.titleSmall,
              ),
              for (final e in _preview!.items.take(5))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    context.tr('app.anthologies.trim', {
                      'trim': e.quote.trim(),
                    }),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: ready && !_busy
                        ? () => _run(preview: true)
                        : null,
                    child: Text(context.tr('app.anthology_tools.preview')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: ready && !_busy
                        ? () => _run(preview: false)
                        : null,
                    child: _busy && !_filled
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(context.tr('app.anthology_tools.fill_now')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
