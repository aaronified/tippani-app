import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/server_call.dart';
import '../checks/checks_service.dart';
import '../imports/import_picker.dart';
import '../imports/import_service.dart';
import '../imports/markdown_import.dart';
import '../library/library_store.dart';
import '../sync/auto_sync.dart';
import 'checks_tabs.dart';
import 'staging_screen.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

/// Where the things that wait on the reader are: files imported into the server's queue, stray marks in the
/// words, corrections from a work's own file, and times and places from it. Each tab carries a count of what is
/// waiting. Importing a Markdown file into this phone works with no server.
class ChecksScreen extends StatefulWidget {
  const ChecksScreen({
    super.key,
    this.imports,
    this.checks,
    this.library,
    this.picker = const SystemImportPicker(),
    this.auto,
  });

  final ImportService? imports;
  final ChecksService? checks;
  final LibraryStore? library;
  final ImportPicker picker;
  final AutoSync? auto;

  @override
  State<ChecksScreen> createState() => _ChecksScreenState();
}

class _ChecksScreenState extends State<ChecksScreen> {
  int _pending = 0;
  CheckCounts _counts = const CheckCounts();

  bool get _server => widget.imports?.available == true;

  @override
  void initState() {
    super.initState();
    _refreshCounts();
  }

  Future<void> _refreshCounts() async {
    try {
      if (_server) {
        final p = await widget.imports!.pending();
        if (mounted) setState(() => _pending = p);
      }
      if (widget.checks?.available == true) {
        final c = await widget.checks!.counts();
        if (mounted) setState(() => _counts = c);
      }
    } on ServerException {
      // the tabs say what went wrong when they open
    }
  }

  /// After the server changed quotes, bring the phone's copy up to date.
  Future<void> _pull() async {
    await widget.auto?.syncNow();
    await _refreshCounts();
  }

  Widget _tab(String label, int n) => Tab(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (n > 0) ...[const SizedBox(width: 6), Badge(label: Text('$n'))],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final checks = widget.checks;
    final tabs = <(Widget, Widget)>[
      (
        _tab(context.tr('checks.tab.imports.label'), _pending),
        ImportsTab(
          imports: widget.imports,
          library: widget.library,
          picker: widget.picker,
          pending: _pending,
          onPending: (n) => setState(() => _pending = n),
          onApproved: _pull,
        ),
      ),
      if (checks != null) ...[
        (
          _tab(context.tr('checks.tab.marks.label'), _counts.strayMarks),
          StrayMarksTab(service: checks, onChanged: _pull),
        ),
        (
          _tab('Corrections', _counts.corrections),
          CorrectionsTab(service: checks, onChanged: _pull),
        ),
        (
          _tab(context.tr('app.checks.times_and_places'), _counts.locators),
          LocatorsTab(service: checks, onChanged: _pull),
        ),
      ],
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('app.checks_entry.import_and_checks')),
          bottom: tabs.length > 1
              ? TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final t in tabs) t.$1],
                )
              : null,
        ),
        body: TabBarView(children: [for (final t in tabs) t.$2]),
      ),
    );
  }
}

class _Result {
  _Result(this.name, {this.outcome, this.local, this.error, this.file});
  final String name;
  final ImportOutcome? outcome;
  final MarkdownImportResult? local;
  final String? error;
  final ImportFile? file;
  String? readAs;
}

/// Import files: into the server's queue (it reads Kindle, Goodreads, IMDb, Readest and the rest), or a Markdown
/// file into this phone. What is waiting in the server's queue is reviewed on its own screen.
class ImportsTab extends StatefulWidget {
  const ImportsTab({
    super.key,
    required this.imports,
    required this.library,
    required this.picker,
    required this.pending,
    required this.onPending,
    required this.onApproved,
  });

  final ImportService? imports;
  final LibraryStore? library;
  final ImportPicker picker;
  final int pending;
  final ValueChanged<int> onPending;
  final Future<void> Function() onApproved;

  @override
  State<ImportsTab> createState() => _ImportsTabState();
}

class _ImportsTabState extends State<ImportsTab> {
  final _results = <_Result>[];
  String? _busy;
  double? _progress;

  bool get _server => widget.imports?.available == true;

  void _say(String m) {
    final s = ScaffoldMessenger.of(context);
    s.clearSnackBars();
    s.showSnackBar(SnackBar(content: Text(m)));
  }

  Future<ImportFile?> _pick({List<String>? extensions}) async {
    try {
      return await widget.picker.pick(extensions: extensions);
    } on ImportTooBig catch (e) {
      if (mounted) _say(e.toString());
      return null;
    }
  }

  Future<void> _send(ImportFile f, {String? as, _Result? again}) async {
    setState(() {
      _busy = f.name;
      _progress = null;
    });
    _Result r;
    try {
      final o = await widget.imports!.importFile(
        f.name,
        f.bytes,
        as: as,
        onProgress: (d, t) {
          if (mounted && t > 0) setState(() => _progress = d / t);
        },
      );
      r = _Result(
        f.name,
        outcome: o,
        error: o.ok ? null : o.message,
        file: o.unknownFormat ? f : null,
      );
      if (o.ok) widget.onPending(o.pending);
    } on ServerException catch (e) {
      r = _Result(f.name, error: e.message);
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (again != null) _results.remove(again);
      _results.insert(0, r);
    });
  }

  Future<void> _chooseServerFile() async {
    final f = await _pick();
    if (f != null && mounted) await _send(f);
  }

  Future<void> _chooseLocalFile() async {
    final f = await _pick(extensions: const ['md', 'markdown', 'txt']);
    if (f == null || !mounted) return;
    setState(() {
      _busy = f.name;
      _progress = null;
    });
    _Result r;
    try {
      final text = utf8.decode(f.bytes, allowMalformed: true);
      final res = await importMarkdown(text, widget.library!);
      r = _Result(f.name, local: res);
    } on MarkdownImportException catch (e) {
      r = _Result(f.name, error: e.message);
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      _results.insert(0, r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pending = widget.pending;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (_server && pending > 0)
          Card(
            color: scheme.primaryContainer,
            child: ListTile(
              leading: Icon(Ti.inbox, color: scheme.onPrimaryContainer),
              title: Text(
                pending == 1
                    ? '1 imported quote is waiting for you to okay it'
                    : '$pending imported quotes are waiting for you to okay them',
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
              trailing: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StagingScreen(
                      service: widget.imports!,
                      onApproved: widget.onApproved,
                      onChanged: widget.onPending,
                    ),
                  ),
                ),
                child: Text(context.tr('settings.section.review.label')),
              ),
            ),
          ),
        if (_server)
          _Panel(
            icon: Ti.cloudDownload,
            title: context.tr('app.checks.import_a_file'),
            body: context.tr(
              'app.checks.the_server_reads_kindle_goodreads_hardcover',
            ),
            action: FilledButton.icon(
              onPressed: _busy == null ? _chooseServerFile : null,
              icon: const Icon(Ti.fileUpload),
              label: Text(context.tr('app.checks.choose_a_file')),
            ),
          )
        else
          Card(
            child: ListTile(
              leading: const Icon(Ti.cloudOff),
              title: Text(
                context.tr('app.checks.importing_to_a_server_needs_a'),
              ),
              subtitle: Text(
                context.tr('app.checks.pair_this_phone_in_settings_a'),
              ),
            ),
          ),
        if (widget.library != null)
          _Panel(
            icon: Ti.fileText,
            title: context.tr('app.checks.import_markdown_into_this_phone'),
            body: 'A file in the form the app exports (a "---" block naming each book or film, then its quotes). It goes straight into the library on this phone, and a book or quote you already have is left as it is.',
            action: OutlinedButton.icon(
              onPressed: _busy == null ? _chooseLocalFile : null,
              icon: const Icon(Ti.fileImport),
              label: Text(context.tr('app.checks.choose_a_markdown_file')),
            ),
          ),
        if (_busy != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('app.checks.reading_busy', {'busy': _busy}),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: _progress),
              ],
            ),
          ),
        for (final r in _results)
          _ResultCard(
            result: r,
            onReadAs: r.file == null || !_server
                ? null
                : (kind) => _send(r.file!, as: kind, again: r),
            onReview: _server && (r.outcome?.ok ?? false)
                ? () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StagingScreen(
                        service: widget.imports!,
                        onApproved: widget.onApproved,
                        onChanged: widget.onPending,
                      ),
                    ),
                  )
                : null,
          ),
        const SizedBox(height: 8),
        Card(
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Ti.helpCircle),
            title: Text(context.tr('app.checks.how_to_get_a_file_from')),
            children: [
              for (final s in importSources)
                ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(s.title),
                  subtitle: Text(s.about),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    for (var i = 0; i < s.steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('${i + 1}. ${s.steps[i]}'),
                      ),
                    if (s.caveat.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          s.caveat,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final IconData icon;
  final String title, body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            action,
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatefulWidget {
  const _ResultCard({
    required this.result,
    required this.onReadAs,
    required this.onReview,
  });

  final _Result result;
  final ValueChanged<String>? onReadAs;
  final VoidCallback? onReview;

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  String? _as;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = widget.result;
    final o = r.outcome;
    final l = r.local;
    String line;
    var bad = false;
    if (r.error != null) {
      line = r.error!;
      bad = true;
    } else if (o != null) {
      final what = sourceName(o.source);
      line = o.staged == 0
          ? tx('app.checks.read_as_nothing_new', {'what': what})
          : tx('app.checks.read_as_staged', {
              'what': what,
              'quotes': countWords('quote', o.staged),
              'works': countWords('work', o.works),
            });
      if (o.nearDuplicates > 0) {
        line += ' ${tx('app.checks.near_duplicates', {'n': o.nearDuplicates})}';
      }
    } else if (l != null) {
      line = l.quotes == 0 && l.works == 0
          ? trn('app.checks.nothing_new_local', l.duplicates)
          : [
              l.works > 0
                  ? tx('app.checks.added_quotes_and_works', {
                      'quotes': countWords('quote', l.quotes),
                      'works': countWords('new work', l.works),
                    })
                  : tx('app.checks.added_quotes', {
                      'quotes': countWords('quote', l.quotes),
                    }),
              if (l.duplicates > 0)
                tx('app.checks.already_here', {'n': l.duplicates}),
              if (l.skippedBlocks > 0)
                tx('app.checks.not_read_here', {'n': l.skippedBlocks}),
            ].join(' ');
    } else {
      line = '';
    }
    return Card(
      color: bad ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  bad ? Ti.alertCircle : Ti.circleCheck,
                  color: bad ? scheme.onErrorContainer : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.name,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              line,
              style: TextStyle(color: bad ? scheme.onErrorContainer : null),
            ),
            if (widget.onReadAs != null) ...[
              const SizedBox(height: 8),
              Text(
                context.tr('import.unknown.body'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _as,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.tr('import.read-as.label'),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in importSources)
                          DropdownMenuItem(value: s.kind, child: Text(s.title)),
                      ],
                      onChanged: (v) => setState(() => _as = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _as == null
                        ? null
                        : () => widget.onReadAs!(_as!),
                    child: Text(context.tr('app.checks.read_it')),
                  ),
                ],
              ),
            ],
            if (widget.onReview != null && (o?.staged ?? 0) > 0)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onReview,
                  child: Text(context.tr('app.checks.review_the_queue')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
