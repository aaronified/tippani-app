import 'dart:async';

import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../sources/source_picker.dart';
import '../sources/sources_service.dart';
import '../l10n/l10n.dart';

/// The source a work's file belongs to: 'book' for a book, 'screen' for a film or a show (a game has none).
String? sourceSubjectOf(Work w) => switch (w.kind) {
  WorkKind.book || WorkKind.other => 'book',
  WorkKind.film || WorkKind.show => 'screen',
  WorkKind.game => null,
};

String _size(int bytes) {
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
  return '$bytes bytes';
}

void _say(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Runs [job]; says the server's words when it refuses. True when it worked.
Future<bool> _try(BuildContext context, Future<void> Function() job) async {
  try {
    await job();
    return true;
  } on ServerException catch (e) {
    if (context.mounted) _say(context, e.message);
    return false;
  }
}

/// Source files: the ebooks and subtitle tracks your quotes came from, which give a quote its surroundings. See
/// what is attached (read it again, free the space of an uploaded one, remove one), scan a folder on the server for
/// files that fit your works and attach or turn down what it finds, and attach one by hand from a folder on the
/// server or from this phone.
class SourceFilesScreen extends StatefulWidget {
  const SourceFilesScreen({
    super.key,
    required this.service,
    required this.library,
    required this.picker,
    this.pollEvery = const Duration(seconds: 2),
  });

  final SourcesService service;
  final LibraryStore library;
  final SourcePicker picker;
  final Duration pollEvery;

  @override
  State<SourceFilesScreen> createState() => _SourceFilesScreenState();
}

class _SourceFilesScreenState extends State<SourceFilesScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  List<Work> _works = const [];
  List<AttachedSource>? _attached;
  List<SourceMount>? _mounts;
  String _mount = '';
  ScanState _scan = const ScanState();
  List<FoundFile> _found = const [];
  String? _problem;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  String _title(String subject, int id, [String episode = '']) {
    for (final w in _works) {
      if (w.serverId == id && sourceSubjectOf(w) == subject) {
        return episode.isEmpty ? w.title : '${w.title} · $episode';
      }
    }
    return episode.isEmpty ? 'A work not on this phone' : 'A show · $episode';
  }

  Future<void> _read() async {
    try {
      final works = await widget.library.works();
      final attached = await widget.service.attached();
      final mounts = await widget.service.mounts();
      if (!mounted) return;
      setState(() {
        _works = works;
        _attached = attached;
        _mounts = mounts;
        _problem = null;
        if (_mount.isEmpty || !mounts.any((m) => m.id == _mount)) {
          _mount = mounts.isEmpty ? '' : mounts.first.id;
        }
      });
      await _readFound();
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<void> _readFound() async {
    if (_mount.isEmpty) return;
    try {
      final r = await widget.service.found(_mount);
      if (!mounted) return;
      setState(() {
        _scan = r.scan;
        _found = r.found;
      });
      _timer?.cancel();
      if (r.scan.live) {
        _timer = Timer.periodic(widget.pollEvery, (_) => _poll());
      }
    } on ServerException {
      // the Found tab says nothing until a scan has been asked for
    }
  }

  Future<void> _poll() async {
    if (_busy || _mount.isEmpty) return;
    _busy = true;
    try {
      final s = await widget.service.scanState(_mount);
      if (!mounted) return;
      setState(() => _scan = s);
      if (!s.live) {
        _timer?.cancel();
        await _readFound();
      }
    } on ServerException {
      // keep looking
    } finally {
      _busy = false;
    }
  }

  Future<void> _startScan() async {
    final ok = await _try(context, () async {
      await widget.service.scan(_mount);
    });
    if (ok) await _readFound();
  }

  Future<void> _attachFound(List<FoundFile> files, String bucket) async {
    AttachResult r = const AttachResult();
    final ok = await _try(context, () async {
      r = await widget.service.attachFound(bucket, [
        for (final f in files) f.token,
      ]);
    });
    if (!ok || !mounted) return;
    _say(
      context,
      '${r.attached} attached${r.skipped > 0 ? ', ${r.skipped} skipped' : ''}${r.failed > 0 ? ', ${r.failed} could not be read' : ''}.',
    );
    await _read();
  }

  Future<void> _ignoreFound(List<FoundFile> files) async {
    final ok = await _try(
      context,
      () => widget.service.ignoreFound([for (final f in files) f.token]),
    );
    if (ok) await _read();
  }

  Future<void> _remove(AttachedSource s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('app.source_files.remove_this_file')),
        content: Text(
          context.tr('app.source_files.the_file_is_taken_off_x', {
            'x': _title(s.subject, s.workId, s.episode),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('common.action.remove.label')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await _try(context, () => widget.service.remove(s.id))) await _read();
  }

  Future<void> _prune(AttachedSource s) async {
    PrunePreview p = const PrunePreview();
    if (!await _try(context, () async {
      p = await widget.service.prunePreview(s.id);
    })) {
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('app.source_files.free_the_space_of_this_file')),
        content: Text(
          context.tr('app.source_files.the_file_x_is_deleted_from', {
            'x': _size(p.bytes),
            'x2': _size(p.keptBytes),
            'with_context': p.withContext,
            'x3': p.withContext == 1 ? 'quote keeps' : 'quotes keep',
            'x4': p.withoutContext > 0
                ? ' ${p.withoutContext} ${p.withoutContext == 1 ? 'quote has' : 'quotes have'} none to keep.'
                : '',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('app.source_files.free_the_space')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await _try(context, () => widget.service.prune(s.id))) await _read();
  }

  Future<void> _rescan(AttachedSource s) async {
    if (await _try(context, () => widget.service.rescan(s.id)) && mounted) {
      _say(
        context,
        context.tr('app.source_files.read_again_quotes_now_have_the'),
      );
      await _read();
    }
  }

  /// Asks which work a file is for, and (for a show) which episode. Null when cancelled.
  Future<({Work work, String episode})?> _chooseWork() async {
    final candidates = [
      for (final w in _works)
        if (w.serverId != null && sourceSubjectOf(w) != null) w,
    ];
    if (candidates.isEmpty) {
      _say(context, context.tr('app.source_files.none_of_your_works_is_on'));
      return null;
    }
    final work = await showModalBottomSheet<Work>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var q = '';
        return StatefulBuilder(
          builder: (context, set) {
            final shown = [
              for (final w in candidates)
                if (q.isEmpty ||
                    w.title.toLowerCase().contains(q) ||
                    w.creator.toLowerCase().contains(q))
                  w,
            ];
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.75,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      context.tr('app.source_files.which_work_is_it_for'),
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: context.tr(
                          'app.source_files.search_your_works',
                        ),
                      ),
                      onChanged: (v) => set(() => q = v.trim().toLowerCase()),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final w in shown)
                          ListTile(
                            title: Text(w.title),
                            subtitle: w.creator.isEmpty
                                ? null
                                : Text(w.creator),
                            onTap: () => Navigator.pop(context, w),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (work == null || !mounted) return null;
    var episode = '';
    if (work.kind == WorkKind.show) {
      final c = TextEditingController();
      final e = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('common.source.episode.title')),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.tr('common.field.episode.label'),
              helperText: context.tr(
                'app.source_files.like_s01e04_a_show_s_subtitles',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('common.action.cancel.label')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: Text(context.tr('common.date.picker.next.aria')),
            ),
          ],
        ),
      );
      if (e == null || e.isEmpty) return null;
      episode = e;
    }
    return (work: work, episode: episode);
  }

  Future<void> _fromPhone() async {
    final SourceFile? file;
    try {
      file = await widget.picker.pick();
    } on SourceTooBig catch (e) {
      if (mounted) _say(context, e.toString());
      return;
    }
    if (file == null || !mounted) return;
    final chosen = await _chooseWork();
    if (chosen == null || !mounted) return;
    final f = file;
    final ok = await _try(
      context,
      () => widget.service.upload(
        bytes: f.bytes,
        fileName: f.name,
        subject: sourceSubjectOf(chosen.work)!,
        workId: chosen.work.serverId!,
        episode: chosen.episode,
      ),
    );
    if (ok && mounted) {
      _say(context, '${f.name} is attached to ${chosen.work.title}.');
      await _read();
      _tabs.animateTo(0);
    }
  }

  Future<void> _fromFolder() async {
    final mounts = _mounts ?? const [];
    if (mounts.isEmpty) return;
    final picked = await Navigator.of(context)
        .push<({String mount, String rel})>(
          MaterialPageRoute(
            builder: (_) =>
                _BrowseScreen(service: widget.service, mounts: mounts),
          ),
        );
    if (picked == null || !mounted) return;
    final chosen = await _chooseWork();
    if (chosen == null || !mounted) return;
    final ok = await _try(
      context,
      () => widget.service.attachMounted(
        mountId: picked.mount,
        rel: picked.rel,
        subject: sourceSubjectOf(chosen.work)!,
        workId: chosen.work.serverId!,
        episode: chosen.episode,
      ),
    );
    if (ok && mounted) {
      _say(
        context,
        tok('app.source_files.attached_to_title', {'title': chosen.work.title}),
      );
      await _read();
      _tabs.animateTo(0);
    }
  }

  Widget _attachedTab() {
    final list = _attached!;
    final scheme = Theme.of(context).colorScheme;
    if (list.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: EdgeInsets.all(40),
            child: Text(
              context.tr('app.source_files.no_file_is_attached_yet_scan'),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _read,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24, top: 8),
        children: [
          for (final s in list)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Card(
                child: ListTile(
                  leading: Icon(
                    s.state == 'missing'
                        ? Icons.link_off_rounded
                        : Icons.description_outlined,
                    color: s.state == 'missing' ? scheme.error : null,
                  ),
                  title: Text(_title(s.subject, s.workId, s.episode)),
                  isThreeLine: true,
                  subtitle: Text(
                    [
                      s.name,
                      [
                        s.format.toUpperCase(),
                        if (s.bytes > 0) _size(s.bytes),
                        if (s.mounted) 'from a server folder' else 'uploaded',
                        if (s.state == 'pruned') 'space freed',
                        if (s.state == 'missing') 'missing on the server',
                      ].where((x) => x.isNotEmpty).join(' · '),
                      '${s.withContext} ${s.withContext == 1 ? 'quote' : 'quotes'} with surroundings',
                    ].join('\n'),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: context.tr(
                      'settings.appearance.contrast.more.label',
                    ),
                    onSelected: (v) => switch (v) {
                      'rescan' => _rescan(s),
                      'prune' => _prune(s),
                      _ => _remove(s),
                    },
                    itemBuilder: (_) => [
                      if (s.state != 'pruned')
                        PopupMenuItem(
                          value: 'rescan',
                          child: Text(
                            context.tr(
                              'common.shelf.move.reading.again.book.label',
                            ),
                          ),
                        ),
                      if (s.prunable)
                        PopupMenuItem(
                          value: 'prune',
                          child: Text(
                            context.tr('app.source_files.free_the_space'),
                          ),
                        ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(
                          context.tr('app.source_files.remove_the_file'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _foundTab() {
    final mounts = _mounts!;
    if (mounts.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: EdgeInsets.all(40),
            child: Text(
              context.tr('app.source_files.the_server_has_no_folder_to'),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }
    final exact = [
      for (final f in _found)
        if (f.exact) f,
    ];
    final review = [
      for (final f in _found)
        if (!f.exact) f,
    ];
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _readFound,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                if (mounts.length > 1)
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _mount,
                      items: [
                        for (final m in mounts)
                          DropdownMenuItem(value: m.id, child: Text(m.label)),
                      ],
                      onChanged: (v) {
                        setState(() => _mount = v ?? _mount);
                        _readFound();
                      },
                    ),
                  )
                else
                  Expanded(
                    child: Text(mounts.first.label, style: text.titleMedium),
                  ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _scan.live ? null : _startScan,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(_scan.state == 'none' ? 'Scan' : 'Scan again'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(switch (_scan.state) {
              'none' => context.tr(
                'app.source_files.not_scanned_yet_a_scan_looks',
              ),
              'queued' => context.tr(
                'app.source_files.waiting_for_the_server_to_start',
              ),
              'running' =>
                'Looking… ${_scan.scanned} files read, ${_scan.found} found.',
              'partial' =>
                'Stopped part-way: ${_scan.scanned} files read. Scan again to carry on.',
              'failed' || 'interrupted' => tok(
                'app.source_files.the_scan_did_not_finishx',
                {'x': _scan.error.isEmpty ? '' : ': ${_scan.error}'},
              ),
              _ =>
                '${_scan.scanned} files read, ${_scan.found} fit a work${_scan.unclaimed > 0 ? ', ${_scan.unclaimed} fit none' : ''}.',
            }, style: text.bodySmall),
          ),
          if (_scan.live) const LinearProgressIndicator(),
          if (exact.isNotEmpty) ...[
            _FoundHeading(
              'Exact matches (${exact.length})',
              action: context.tr('app.source_files.attach_all'),
              onAction: () => _attachFound(exact, 'exact'),
            ),
            for (final f in exact) _foundTile(f),
          ],
          if (review.isNotEmpty) ...[
            _FoundHeading(
              'To look over (${review.length})',
              action: context.tr('app.source_files.turn_all_down'),
              onAction: () => _ignoreFound(review),
            ),
            for (final f in review) _foundTile(f),
          ],
          if (_found.isEmpty && !_scan.live && _scan.state == 'done')
            Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                context.tr('app.source_files.nothing_new_fits_works_that_have'),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _foundTile(FoundFile f) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              f.episode.isEmpty
                  ? f.title
                  : context.tr('app.source_files.title_episode', {
                      'title': f.title,
                      'episode': f.episode,
                    }),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              context.tr('app.source_files.rel_to_upper_case_x', {
                'rel': f.rel,
                'to_upper_case': f.format.toUpperCase(),
                'x': f.exact ? 'matched by its ids' : 'matched by its name',
              }),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => _ignoreFound([f]),
                    child: Text(context.tr('common.source.found.refuse')),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _attachFound([f], f.bucket),
                    child: Text(context.tr('common.source.found.attach')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _addTab() {
    final hasMounts = (_mounts ?? const []).isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(
              context.tr('app.source_files.from_a_folder_on_the_server'),
            ),
            subtitle: Text(
              hasMounts
                  ? context.tr(
                      'app.source_files.browse_the_server_s_folders_and',
                    )
                  : context.tr(
                      'app.source_files.the_server_has_no_folder_to_2',
                    ),
            ),
            enabled: hasMounts,
            onTap: hasMounts ? _fromFolder : null,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(context.tr('app.source_files.from_this_phone')),
            subtitle: Text(
              context.tr('app.source_files.send_an_ebook_or_a_subtitle'),
            ),
            onTap: _fromPhone,
          ),
        ),
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(context.tr('app.source_files.a_work_has_one_file_a')),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final attached = _attached;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('metadata.section.files.label')),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(
              text: attached == null
                  ? 'Attached'
                  : 'Attached (${attached.length})',
            ),
            Tab(text: _found.isEmpty ? 'Found' : 'Found (${_found.length})'),
            const Tab(text: 'Add'),
          ],
        ),
      ),
      body: _problem != null && attached == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_problem!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _read,
                      child: Text(context.tr('common.source.retry')),
                    ),
                  ],
                ),
              ),
            )
          : attached == null || _mounts == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [_attachedTab(), _foundTab(), _addTab()],
            ),
    );
  }
}

class _FoundHeading extends StatelessWidget {
  const _FoundHeading(
    this.text, {
    required this.action,
    required this.onAction,
  });

  final String text, action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    ),
  );
}

/// Walks a folder of the server's library to choose a file. Pops `(mount, rel)`.
class _BrowseScreen extends StatefulWidget {
  const _BrowseScreen({required this.service, required this.mounts});

  final SourcesService service;
  final List<SourceMount> mounts;

  @override
  State<_BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<_BrowseScreen> {
  late String _mount = widget.mounts.first.id;
  FolderListing? _list;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _open('');
  }

  Future<void> _open(String path) async {
    setState(() => _problem = null);
    try {
      final l = await widget.service.browse(_mount, path);
      if (mounted) setState(() => _list = l);
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _list;
    return Scaffold(
      appBar: AppBar(
        title: Text(l == null || l.root ? 'Choose a file' : l.path),
        leading: BackButton(
          onPressed: () {
            if (l != null && !l.root) {
              _open(l.parent);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (widget.mounts.length > 1)
            PopupMenuButton<String>(
              tooltip: context.tr('app.source_files.folder'),
              icon: const Icon(Icons.folder_special_outlined),
              onSelected: (v) {
                setState(() => _mount = v);
                _open('');
              },
              itemBuilder: (_) => [
                for (final m in widget.mounts)
                  PopupMenuItem(value: m.id, child: Text(m.label)),
              ],
            ),
        ],
      ),
      body: _problem != null
          ? Center(child: Text(_problem!))
          : l == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (l.entries.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(40),
                    child: Text(
                      context.tr(
                        'app.source_files.nothing_here_an_ebook_or_subtitle',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final e in l.entries)
                  ListTile(
                    leading: Icon(
                      e.dir
                          ? Icons.folder_outlined
                          : Icons.description_outlined,
                    ),
                    title: Text(e.name),
                    subtitle: e.dir || e.size == 0 ? null : Text(_size(e.size)),
                    onTap: () => e.dir
                        ? _open(e.rel)
                        : Navigator.pop(context, (mount: _mount, rel: e.rel)),
                  ),
                if (l.truncated)
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      context.tr(
                        'app.source_files.only_the_first_part_of_this',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
    );
  }
}
