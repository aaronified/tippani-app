import 'dart:async';

import 'package:flutter/material.dart';

import '../admin/admin_service.dart';
import 'admin_widgets.dart';
import '../l10n/l10n.dart';

/// What a kind of job is called, in words. A kind the app has no words for is shown as "Job".
String jobKindName(String kind) =>
    const {
      'fill': 'Fill in missing details',
      'covers': 'Fetch covers',
      'people': 'Fetch portraits and details',
      'reverify': 'Re-check details',
      'reverify-apply': 'Apply a re-check',
      'backup': 'Back up the server',
      'backup.safety': 'Safety copy before a restore',
      'import': 'Import a file',
      'import.approve': 'Approve imported quotes',
      'library.scan': 'Scan the library folders',
      'lookup.book': 'Look up a book',
      'lookup.movie': 'Look up a film',
      'lookup.images': 'Look up pictures',
      'lookup.portrait': 'Fetch a portrait',
      'lookup.links': 'Look up links',
      'lookup.person': 'Look up a person',
      'lookup.reverify': 'Re-check one work',
      'lookup.cast-image': 'Fetch a cast picture',
      'lookup.cast-imdb': 'Fetch a cast list',
      'lookup.cast-tvdb': 'Fetch a cast list',
      'lookup.cast-art': 'Fetch cast art',
      'lookup.signature': 'Fetch a signature',
      'update.check': 'Check for an update',
      'update.apply': 'Update the server',
      'metadata.test': 'Test the metadata sources',
      'notify.test': 'Send a test note',
      'work.save': 'Save a work',
      'person.save': 'Save a person',
      'character.save': 'Save a character',
      'restore': 'Restore a backup',
      'reset': 'Reset the library',
      'notify.daily': 'Daily note',
    }[kind] ??
    'Job';

/// What the common-job rows are called.
String commonJobName(String id) =>
    const {
      'fill-all': 'Fill in every work',
      'people-missing': 'Fetch missing portraits and details',
      'covers': 'Fetch every cover',
      'backup': 'Back up the server',
    }[id] ??
    jobKindName(id);

String _stateName(String s) => switch (s) {
  'queued' => 'Waiting',
  'running' => 'Running',
  'succeeded' => 'Done',
  'failed' => 'Failed',
  'stopped' => 'Stopped',
  'interrupted' => 'Interrupted',
  _ => s,
};

/// The server's jobs: what is running and waiting now (read again every few seconds while you look), what ran in
/// the last thirty days, and the common jobs you can start. Each can be stopped while it is alive and run again
/// after it ends, and its log can be read.
class AdminJobsScreen extends StatefulWidget {
  const AdminJobsScreen({
    super.key,
    required this.service,
    this.pollEvery = const Duration(seconds: 3),
  });

  final AdminService service;
  final Duration pollEvery;

  @override
  State<AdminJobsScreen> createState() => _AdminJobsScreenState();
}

class _AdminJobsScreenState extends State<AdminJobsScreen> {
  JobsPage? _current, _past;
  List<CommonJob>? _common;
  String? _problem;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(widget.pollEvery, (_) => _read(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read({bool quiet = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      final cur = await widget.service.jobs(view: 'current');
      final past = await widget.service.jobs(view: 'past');
      final common = await widget.service.commonJobs();
      if (mounted) {
        setState(() {
          _current = cur;
          _past = past;
          _common = common;
          _problem = null;
        });
      }
    } on Object catch (e) {
      if (mounted && !quiet) setState(() => _problem = '$e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _stop(JobInfo j) async {
    if (await attempt(context, () => widget.service.stopJob(j.id))) _read();
  }

  Future<void> _rerun(JobInfo j) async {
    if (await attempt(context, () async => widget.service.rerun(j.id))) {
      _read();
    }
  }

  Future<void> _start(CommonJob j) async {
    if (await attempt(
      context,
      () async => widget.service.startJob(j.kind, j.params),
    )) {
      _read();
    }
  }

  Future<void> _stopAll() async {
    final ok = await confirmDialog(
      context,
      title: context.tr('app.admin_jobs.stop_every_job'),
      body: context.tr('app.admin_jobs.the_running_job_and_every_waiting'),
      yes: context.tr('settings.jobs.current.stop-all.label'),
      danger: true,
    );
    if (!ok || !mounted) return;
    if (await attempt(context, widget.service.stopAll)) _read();
  }

  Future<void> _log(JobInfo j) async {
    List<String> lines;
    try {
      lines = await widget.service.jobLog(j.id);
    } on Object catch (e) {
      if (mounted) say(context, '$e');
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              '${jobKindName(j.kind)}${j.subject.isEmpty ? '' : ' · ${j.subject}'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (lines.isEmpty)
              Text(context.tr('app.admin_jobs.this_job_logged_nothing')),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText(
                  l,
                  style: const TextStyle(
                    fontFamily: 'IBMPlexMono',
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _card(JobInfo j) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tone = switch (j.state) {
      'failed' || 'interrupted' => scheme.errorContainer,
      'running' => scheme.primaryContainer,
      'queued' => scheme.tertiaryContainer,
      _ => scheme.secondaryContainer,
    };
    final counts = j.counts.entries.where((e) => e.value > 0).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _log(j),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(jobKindName(j.kind), style: text.titleSmall),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: tone,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(_stateName(j.state), style: text.labelSmall),
                    ),
                  ],
                ),
                if (j.subject.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      j.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (j.live && j.total > 0) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: (j.done / j.total).clamp(0, 1).toDouble(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('quiz.progress.label', {
                      'done': j.done,
                      'total': j.total,
                    }),
                    style: text.labelSmall,
                  ),
                ],
                if (j.state == 'queued' && j.ahead > 0)
                  Text(
                    context.tr('app.admin_jobs.ahead_ahead_of_it', {
                      'ahead': j.ahead,
                    }),
                    style: text.labelSmall,
                  ),
                if (j.error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      j.error,
                      style: text.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                if (counts.isNotEmpty && !j.live)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 12,
                      children: [
                        for (final e in counts)
                          Text(
                            context.tr('app.admin_jobs.value_key', {
                              'value': e.value,
                              'key': e.key,
                            }),
                            style: text.labelSmall,
                          ),
                      ],
                    ),
                  ),
                if (j.username.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      context.tr('app.admin_jobs.by_username', {
                        'username': j.username,
                      }),
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (j.live || j.rerunnable)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (j.live)
                          TextButton.icon(
                            onPressed: () => _stop(j),
                            icon: const Icon(Icons.stop_rounded),
                            label: Text(
                              context.tr('settings.jobs.current.stop.label'),
                            ),
                          ),
                        if (j.rerunnable)
                          TextButton.icon(
                            onPressed: () => _rerun(j),
                            icon: const Icon(Icons.replay_rounded),
                            label: Text(
                              context.tr('settings.jobs.past.rerun.label'),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _commonCard(CommonJob j) {
    final scheme = Theme.of(context).colorScheme;
    final last = j.last;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        child: ListTile(
          title: Text(commonJobName(j.id)),
          subtitle: Text(
            j.current != null
                ? '${_stateName(j.current!.state)} now'
                : last == null
                ? context.tr('app.admin_jobs.not_run_in_the_last_thirty')
                : 'Last: ${_stateName(last.state)}${last.finishedAt == null ? '' : ' on ${_day(last.finishedAt!)}'}',
          ),
          trailing: j.current != null
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : FilledButton.tonal(
                  onPressed: () => _start(j),
                  child: Text(context.tr('settings.jobs.common.run.label')),
                ),
          iconColor: scheme.primary,
        ),
      ),
    );
  }

  String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cur = _current, past = _past, common = _common;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('settings.section.jobs.label')),
          actions: [
            if (cur != null && cur.jobs.isNotEmpty)
              IconButton(
                tooltip: context.tr('app.admin_jobs.stop_every_job_2'),
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: _stopAll,
              ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                text: cur == null || cur.jobs.isEmpty
                    ? 'Now'
                    : 'Now (${cur.jobs.length})',
              ),
              const Tab(text: 'Past'),
              const Tab(text: 'Common'),
            ],
          ),
        ),
        body: _problem != null && cur == null
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
            : cur == null || past == null || common == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _list(
                    cur.jobs,
                    context.tr('settings.jobs.current.empty'),
                    () => _read(),
                  ),
                  _list(
                    past.jobs,
                    context.tr('app.admin_jobs.no_job_has_ended_in_the'),
                    () => _read(),
                  ),
                  RefreshIndicator(
                    onRefresh: () => _read(),
                    child: ListView(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      children: [
                        for (final j in common) _commonCard(j),
                        if (common.isEmpty)
                          Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              context.tr(
                                'app.admin_jobs.this_server_has_no_queue_so',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _list(
    List<JobInfo> jobs,
    String empty,
    Future<void> Function() refresh,
  ) {
    return RefreshIndicator(
      onRefresh: refresh,
      child: jobs.isEmpty
          ? ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(48),
                  child: Text(empty, textAlign: TextAlign.center),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [for (final j in jobs) _card(j)],
            ),
    );
  }
}
