import 'dart:async';

import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../library/library_store.dart';
import '../library/models.dart';
import '../sources/source_picker.dart';
import '../sources/sources_service.dart';

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
        title: const Text('Remove this file?'),
        content: Text(
          'The file is taken off ${_title(s.subject, s.workId, s.episode)}. Quotes keep the surroundings already cut from it; new quotes will have none.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
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
        title: const Text('Free the space of this file?'),
        content: Text(
          'The file (${_size(p.bytes)}) is deleted from the server; ${_size(p.keptBytes)} of surroundings stay. ${p.withContext} ${p.withContext == 1 ? 'quote keeps' : 'quotes keep'} its surroundings.${p.withoutContext > 0 ? ' ${p.withoutContext} ${p.withoutContext == 1 ? 'quote has' : 'quotes have'} none to keep.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Free the space'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await _try(context, () => widget.service.prune(s.id))) await _read();
  }

  Future<void> _rescan(AttachedSource s) async {
    if (await _try(context, () => widget.service.rescan(s.id)) && mounted) {
      _say(context, 'Read again. Quotes now have the surroundings it gives.');
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
      _say(
        context,
        'None of your works is on the server yet. Sync first, then attach a file.',
      );
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
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'Which work is it for?',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search your works',
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
          title: const Text('Which episode?'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Episode',
              helperText: 'Like s01e04. A show\'s subtitles cover one episode.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Next'),
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
      _say(context, 'Attached to ${chosen.work.title}.');
      await _read();
      _tabs.animateTo(0);
    }
  }

  Widget _attachedTab() {
    final list = _attached!;
    final scheme = Theme.of(context).colorScheme;
    if (list.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(40),
            child: Text(
              'No file is attached yet. Scan a folder on the Found tab, or attach one by hand on the Add tab, and quotes can show the lines around them.',
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
                    tooltip: 'More',
                    onSelected: (v) => switch (v) {
                      'rescan' => _rescan(s),
                      'prune' => _prune(s),
                      _ => _remove(s),
                    },
                    itemBuilder: (_) => [
                      if (s.state != 'pruned')
                        const PopupMenuItem(
                          value: 'rescan',
                          child: Text('Read it again'),
                        ),
                      if (s.prunable)
                        const PopupMenuItem(
                          value: 'prune',
                          child: Text('Free the space'),
                        ),
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove the file'),
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
        children: const [
          Padding(
            padding: EdgeInsets.all(40),
            child: Text(
              'The server has no folder to look in. An admin adds them under Server administration, Library folders.',
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
              'none' => 'Not scanned yet. A scan looks for ebooks and subtitle files that fit your works.',
              'queued' => 'Waiting for the server to start…',
              'running' =>
                'Looking… ${_scan.scanned} files read, ${_scan.found} found.',
              'partial' =>
                'Stopped part-way: ${_scan.scanned} files read. Scan again to carry on.',
              'failed' || 'interrupted' =>
                'The scan did not finish${_scan.error.isEmpty ? '' : ': ${_scan.error}'}',
              _ =>
                '${_scan.scanned} files read, ${_scan.found} fit a work${_scan.unclaimed > 0 ? ', ${_scan.unclaimed} fit none' : ''}.',
            }, style: text.bodySmall),
          ),
          if (_scan.live) const LinearProgressIndicator(),
          if (exact.isNotEmpty) ...[
            _FoundHeading(
              'Exact matches (${exact.length})',
              action: 'Attach all',
              onAction: () => _attachFound(exact, 'exact'),
            ),
            for (final f in exact) _foundTile(f),
          ],
          if (review.isNotEmpty) ...[
            _FoundHeading(
              'To look over (${review.length})',
              action: 'Turn all down',
              onAction: () => _ignoreFound(review),
            ),
            for (final f in review) _foundTile(f),
          ],
          if (_found.isEmpty && !_scan.live && _scan.state == 'done')
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Nothing new fits. Works that have no quotes, or already have a file, are left out.',
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
              f.episode.isEmpty ? f.title : '${f.title} · ${f.episode}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              '${f.rel}\n${f.format.toUpperCase()} · ${f.exact ? 'matched by its ids' : 'matched by its name'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => _ignoreFound([f]),
                    child: const Text('Not this one'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _attachFound([f], f.bucket),
                    child: const Text('Attach'),
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
            title: const Text('From a folder on the server'),
            subtitle: Text(
              hasMounts
                  ? 'Browse the server\'s folders and choose the file. It is read in place, not copied.'
                  : 'The server has no folder to browse. An admin adds them in Library folders.',
            ),
            enabled: hasMounts,
            onTap: hasMounts ? _fromFolder : null,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('From this phone'),
            subtitle: const Text(
              'Send an ebook or a subtitle file (up to 25 MB). The server keeps a copy.',
            ),
            onTap: _fromPhone,
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'A work has one file. A book takes an ebook or a text file; a film or a show\'s episode takes subtitles.',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final attached = _attached;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Source files'),
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
                      child: const Text('Try again'),
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
              tooltip: 'Folder',
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
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Text(
                      'Nothing here an ebook or subtitle file could be.',
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
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Only the first part of this folder is shown.',
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
    );
  }
}
