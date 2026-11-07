import 'package:flutter/material.dart';

import '../admin/admin_service.dart';
import '../admin/server_files.dart';
import '../api/server_call.dart';
import 'admin_widgets.dart';
import '../l10n/l10n.dart';

/// What the reader typed to open or seal a backup: the account's password, or a passphrase.
typedef BackupSecret = ({String password, String passphrase});

/// Asks for the password of an account or a passphrase. [mode] fixes which one when the archive says (`password`
/// or `passphrase`); null lets the reader choose.
Future<BackupSecret?> askBackupSecret(
  BuildContext context, {
  required String title,
  required String body,
  String? mode,
  String account = '',
  String yes = 'app.admin_backup.go_on',
}) {
  return showDialog<BackupSecret>(
    context: context,
    builder: (context) {
      var passphrase = mode == 'passphrase';
      final c = TextEditingController();
      return StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body),
              const SizedBox(height: 12),
              if (mode == null)
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(context.tr('common.field.password.label')),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(context.tr('common.field.passphrase.label')),
                    ),
                  ],
                  selected: {passphrase},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => set(() => passphrase = s.single),
                ),
              TextField(
                controller: c,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: passphrase
                      ? context.tr('common.field.passphrase.label')
                      : account.isEmpty
                      ? context.tr('settings.restore.password.label')
                      : tx('app.admin_backup.password_of_account', {
                          'account': account,
                        }),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('common.action.cancel.label')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                password: passphrase ? '' : c.text,
                passphrase: passphrase ? c.text : '',
              )),
              child: Text(context.tr(yes)),
            ),
          ],
        ),
      );
    },
  );
}

/// Backing up the server and putting a backup back: make one (sealed with your password or a passphrase), bring it
/// to this phone, and replace the library with the kept backup or with a file from this phone. A restore first
/// makes a copy of what the server holds now and keeps it on this phone, as the server demands.
class AdminBackupScreen extends StatefulWidget {
  const AdminBackupScreen({
    super.key,
    required this.service,
    required this.files,
    this.pollEvery = const Duration(seconds: 2),
  });

  final AdminService service;
  final ServerFiles files;
  final Duration pollEvery;

  @override
  State<AdminBackupScreen> createState() => _AdminBackupScreenState();
}

class _AdminBackupScreenState extends State<AdminBackupScreen> {
  BackupInfo? _info;
  bool _loaded = false;
  String? _problem;
  String? _working;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final b = await widget.service.backup();
      if (mounted) {
        setState(() {
          _info = b;
          _loaded = true;
          _problem = null;
        });
      }
    } on ServerException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    }
  }

  Future<JobInfo?> _wait(JobInfo job, String what) async {
    var j = job;
    for (var i = 0; i < 1200 && j.live; i++) {
      if (mounted) {
        setState(
          () => _working = j.total > 0
              ? '$what (${j.done} of ${j.total})'
              : '$what…',
        );
      }
      await Future<void>.delayed(widget.pollEvery);
      if (!mounted) return null;
      j = await widget.service.job(j.id) ?? j;
    }
    return j;
  }

  Future<void> _make() async {
    final secret = await askBackupSecret(
      context,
      title: context.tr('app.admin_backup.back_up_the_server'),
      body: context.tr('app.admin_backup.the_backup_holds_every_reader_s'),
      yes: context.tr('settings.jobs.kind.backup'),
    );
    if (secret == null || !mounted) return;
    final backingUp = context.tr('app.admin_backup.backing_up');
    setState(
      () => _working = context.tr('app.admin_backup.starting_the_backup'),
    );
    try {
      final job = await widget.service.createBackup(
        password: secret.password,
        passphrase: secret.passphrase,
      );
      if (job != null) {
        final done = await _wait(job, backingUp);
        if (done != null && done.state != 'succeeded' && mounted) {
          say(
            context,
            done.error.isEmpty
                ? context.tr('app.admin_backup.the_backup_did_not_finish')
                : done.error,
          );
        }
      }
    } on ServerException catch (e) {
      if (mounted) say(context, e.message);
    }
    if (mounted) setState(() => _working = null);
    await _read();
  }

  Future<void> _download() async {
    final info = _info;
    if (info == null) return;
    if (info.size > maxServerFileBytes) {
      say(context, const ServerFileTooBig().toString());
      return;
    }
    setState(
      () => _working = context.tr(
        'app.admin_backup.bringing_the_backup_to_this_phone',
      ),
    );
    try {
      final f = await widget.service.downloadBackup();
      if (!mounted) return;
      setState(() => _working = null);
      final saved = await widget.files.save(f.name, f.bytes);
      if (mounted && saved) {
        say(context, tx('app.admin_backup.saved_name', {'name': f.name}));
      }
    } on ServerException catch (e) {
      if (mounted) say(context, e.message);
    }
    if (mounted) setState(() => _working = null);
  }

  /// Makes the safety copy of the library as it is now and keeps it on this phone. True when it is there.
  Future<bool> _safetyCopy() async {
    final secret = await askBackupSecret(
      context,
      title: context.tr('app.admin_backup.a_copy_of_what_the_server'),
      body: context.tr('app.admin_backup.before_the_library_is_replaced_the'),
      yes: context.tr('app.admin_backup.make_the_copy'),
    );
    if (secret == null || !mounted) return false;
    final making = context.tr('app.admin_backup.making_the_safety_copy_2');
    try {
      setState(
        () => _working = context.tr('app.admin_backup.making_the_safety_copy'),
      );
      final job = await widget.service.createSafetyCopy(
        password: secret.password,
        passphrase: secret.passphrase,
      );
      if (job == null) return false;
      final done = await _wait(job, making);
      if (done == null || done.state != 'succeeded') {
        if (mounted) {
          say(
            context,
            done?.error.isNotEmpty == true
                ? done!.error
                : context.tr('app.admin_backup.the_safety_copy_was_not_made'),
          );
        }
        return false;
      }
      setState(
        () => _working = context.tr(
          'app.admin_backup.bringing_the_safety_copy_to_this',
        ),
      );
      final f = await widget.service.downloadSafetyCopy(done.id);
      if (!mounted) return false;
      setState(() => _working = null);
      final saved = await widget.files.save(
        f.name,
        f.bytes,
        title: context.tr('app.admin_backup.keep_the_safety_copy'),
      );
      if (!saved && mounted) {
        say(
          context,
          context.tr('app.admin_backup.the_safety_copy_was_not_kept'),
        );
      }
      return saved;
    } on ServerException catch (e) {
      if (mounted) say(context, e.message);
      return false;
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _restore({required bool fromPhone}) async {
    final info = _info;
    ChosenFile? file;
    if (fromPhone) {
      try {
        file = await widget.files.pick();
      } on ServerFileTooBig catch (e) {
        if (mounted) say(context, e.toString());
        return;
      }
      if (file == null || !mounted) return;
    } else if (info == null) {
      return;
    }
    final ok = await confirmDialog(
      context,
      title: context.tr('app.admin_backup.replace_the_whole_library'),
      body: fromPhone
          ? tx('app.admin_backup.every_reader_s_library_on_the', {
              'name': file!.name,
            })
          : tx('app.admin_backup.every_reader_s_library_on_the_2', {
              'created': info!.created,
            }),
      yes: context.tr('home.daily.resume.label'),
      danger: true,
    );
    if (!ok || !mounted) return;
    if (!await _safetyCopy() || !mounted) return;
    final secret = await askBackupSecret(
      context,
      title: context.tr('app.admin_backup.open_the_backup'),
      body: fromPhone
          ? context.tr('app.admin_backup.give_the_password_of_the_account')
          : info!.needsPassphrase
          ? context.tr('app.admin_backup.this_backup_is_sealed_with_a')
          : info.needsPassword
          ? info.account.isEmpty
                ? tx('app.admin_backup.sealed_with_unknown')
                : tx('app.admin_backup.this_backup_is_sealed_with_the', {
                    'account': info.account,
                  })
          : context.tr('app.admin_backup.this_backup_is_not_sealed_press'),
      mode: fromPhone ? null : (info!.key == 'none' ? 'password' : info.key),
      account: fromPhone ? '' : info!.account,
      yes: context.tr('common.action.restore.label'),
    );
    if (secret == null || !mounted) return;
    setState(
      () => _working = context.tr(
        'app.admin_backup.restoring_the_server_will_be_busy',
      ),
    );
    try {
      if (fromPhone) {
        await widget.service.restoreUpload(
          file!.bytes,
          file.name,
          password: secret.password,
          passphrase: secret.passphrase,
        );
      } else {
        await widget.service.restoreKept(
          password: secret.password,
          passphrase: secret.passphrase,
        );
      }
      if (mounted) {
        say(
          context,
          context.tr('app.admin_backup.the_library_is_restored_sync_this'),
        );
      }
    } on ServerException catch (e) {
      if (mounted) say(context, e.message);
    }
    if (mounted) setState(() => _working = null);
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.admin_backup.server_backup'))),
      body: _problem != null
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
          : !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_working != null)
                  Card(
                    color: scheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_working!, style: text.titleSmall),
                          const SizedBox(height: 10),
                          const LinearProgressIndicator(),
                        ],
                      ),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('app.admin_backup.the_kept_backup'),
                          style: text.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          info == null
                              ? context.tr(
                                  'app.admin_backup.the_server_has_no_backup_yet',
                                )
                              : '${info.created.isEmpty ? info.name : info.created} · ${_size(info.size)} · ${switch (info.key) {
                                  'password' => info.account.isEmpty ? context.tr('app.admin_backup.kind_password_unknown') : context.tr('app.admin_backup.kind_password', {'account': info.account}),
                                  'passphrase' => context.tr('app.admin_backup.kind_passphrase'),
                                  'none' => context.tr('app.admin_backup.kind_none'),
                                  _ => context.tr('app.admin_backup.kind_unknown'),
                                }}',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _working == null ? _make : null,
                              icon: const Icon(Icons.backup_outlined),
                              label: Text(
                                info == null ? 'Back up now' : 'Back up again',
                              ),
                            ),
                            if (info != null)
                              OutlinedButton.icon(
                                onPressed: _working == null ? _download : null,
                                icon: const Icon(Icons.download_rounded),
                                label: Text(
                                  context.tr(
                                    'app.admin_backup.save_on_this_phone',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('app.admin_backup.put_a_backup_back'),
                          style: text.titleSmall?.copyWith(color: scheme.error),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr(
                            'app.admin_backup.this_replaces_every_reader_s_library',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (info != null)
                              OutlinedButton(
                                onPressed: _working == null
                                    ? () => _restore(fromPhone: false)
                                    : null,
                                child: Text(
                                  context.tr(
                                    'app.admin_backup.restore_the_kept_backup',
                                  ),
                                ),
                              ),
                            OutlinedButton(
                              onPressed: _working == null
                                  ? () => _restore(fromPhone: true)
                                  : null,
                              child: Text(
                                context.tr(
                                  'app.admin_backup.restore_from_a_file',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _size(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
    return '$bytes bytes';
  }
}
