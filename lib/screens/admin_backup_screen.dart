import 'package:flutter/material.dart';

import '../admin/admin_service.dart';
import '../admin/server_files.dart';
import '../api/server_call.dart';
import 'admin_widgets.dart';

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
  String yes = 'Go on',
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
                  segments: const [
                    ButtonSegment(value: false, label: Text('Password')),
                    ButtonSegment(value: true, label: Text('Passphrase')),
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
                      ? 'Passphrase'
                      : account.isEmpty
                      ? 'Your password'
                      : 'Password of $account',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, (
                password: passphrase ? '' : c.text,
                passphrase: passphrase ? c.text : '',
              )),
              child: Text(yes),
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
      title: 'Back up the server',
      body: 'The backup holds every reader\'s library. It is sealed with your password or a passphrase; you will need the same to open it.',
      yes: 'Back up',
    );
    if (secret == null || !mounted) return;
    setState(() => _working = 'Starting the backup…');
    try {
      final job = await widget.service.createBackup(
        password: secret.password,
        passphrase: secret.passphrase,
      );
      if (job != null) {
        final done = await _wait(job, 'Backing up');
        if (done != null && done.state != 'succeeded' && mounted) {
          say(
            context,
            done.error.isEmpty ? 'The backup did not finish.' : done.error,
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
    setState(() => _working = 'Bringing the backup to this phone…');
    try {
      final f = await widget.service.downloadBackup();
      if (!mounted) return;
      setState(() => _working = null);
      final saved = await widget.files.save(f.name, f.bytes);
      if (mounted && saved) say(context, 'Saved ${f.name}.');
    } on ServerException catch (e) {
      if (mounted) say(context, e.message);
    }
    if (mounted) setState(() => _working = null);
  }

  /// Makes the safety copy of the library as it is now and keeps it on this phone. True when it is there.
  Future<bool> _safetyCopy() async {
    final secret = await askBackupSecret(
      context,
      title: 'A copy of what the server holds now',
      body: 'Before the library is replaced, the server makes a copy of it, and you keep that copy on this phone. Seal it with your password or a passphrase.',
      yes: 'Make the copy',
    );
    if (secret == null || !mounted) return false;
    try {
      setState(() => _working = 'Making the safety copy…');
      final job = await widget.service.createSafetyCopy(
        password: secret.password,
        passphrase: secret.passphrase,
      );
      if (job == null) return false;
      final done = await _wait(job, 'Making the safety copy');
      if (done == null || done.state != 'succeeded') {
        if (mounted) {
          say(
            context,
            done?.error.isNotEmpty == true
                ? done!.error
                : 'The safety copy was not made.',
          );
        }
        return false;
      }
      setState(() => _working = 'Bringing the safety copy to this phone…');
      final f = await widget.service.downloadSafetyCopy(done.id);
      if (!mounted) return false;
      setState(() => _working = null);
      final saved = await widget.files.save(
        f.name,
        f.bytes,
        title: 'Keep the safety copy',
      );
      if (!saved && mounted) {
        say(context, 'The safety copy was not kept, so nothing was restored.');
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
      title: 'Replace the whole library?',
      body: fromPhone
          ? 'Every reader\'s library on the server is replaced with ${file!.name}. First you will keep a copy of what the server holds now.'
          : 'Every reader\'s library on the server is replaced with the backup made ${info!.created}. First you will keep a copy of what the server holds now.',
      yes: 'Continue',
      danger: true,
    );
    if (!ok || !mounted) return;
    if (!await _safetyCopy() || !mounted) return;
    final secret = await askBackupSecret(
      context,
      title: 'Open the backup',
      body: fromPhone
          ? 'Give the password of the account it was made under, or its passphrase.'
          : info!.needsPassphrase
          ? 'This backup is sealed with a passphrase.'
          : info.needsPassword
          ? 'This backup is sealed with the password of ${info.account.isEmpty ? 'the account that made it' : info.account}.'
          : 'This backup is not sealed. Press Restore to go on.',
      mode: fromPhone ? null : (info!.key == 'none' ? 'password' : info.key),
      account: fromPhone ? '' : info!.account,
      yes: 'Restore',
    );
    if (secret == null || !mounted) return;
    setState(
      () => _working = 'Restoring. The server will be busy for a while…',
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
          'The library is restored. Sync this phone from Settings to match it.',
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
      appBar: AppBar(title: const Text('Server backup')),
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
                      child: const Text('Try again'),
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
                        Text('The kept backup', style: text.titleSmall),
                        const SizedBox(height: 6),
                        Text(
                          info == null
                              ? 'The server has no backup yet.'
                              : '${info.created.isEmpty ? info.name : info.created} · ${_size(info.size)} · ${switch (info.key) {
                                  'password' => 'sealed with the password of ${info.account.isEmpty ? 'its account' : info.account}',
                                  'passphrase' => 'sealed with a passphrase',
                                  'none' => 'not sealed',
                                  _ => 'sealing unknown',
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
                                label: const Text('Save on this phone'),
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
                          'Put a backup back',
                          style: text.titleSmall?.copyWith(color: scheme.error),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'This replaces every reader\'s library on the server. A copy of what is there now is made first and kept on this phone.',
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
                                child: const Text('Restore the kept backup'),
                              ),
                            OutlinedButton(
                              onPressed: _working == null
                                  ? () => _restore(fromPhone: true)
                                  : null,
                              child: const Text('Restore from a file'),
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
