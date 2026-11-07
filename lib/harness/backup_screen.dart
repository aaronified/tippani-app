import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'backup.dart';
import 'harness.dart';
import '../l10n/l10n.dart';

/// One plain sentence for each reason a file could not be restored. Pure, so the words are tested.
String backupProblemText(BackupProblem p) => switch (p) {
  BackupProblem.tooBig => 'app.backup.that_file_is_too_big_to',
  BackupProblem.notJson =>
    'That file is not a Tippani backup (it is not readable as one).',
  BackupProblem.notOurs => 'app.backup.that_file_is_not_a_tippani',
  BackupProblem.tooNew => 'app.backup.that_backup_was_made_by_a',
  BackupProblem.noSections => 'app.backup.that_backup_holds_nothing_to_restore',
  BackupProblem.damaged => 'app.backup.part_of_that_backup_is_damaged',
};

/// Back up what the app keeps, and restore it. A backup is written to the app's own storage and to the
/// Downloads folder, so it survives an update and a clear of the app's data. It does not hold the device
/// token: after a restore the phone pairs again, which is one scan.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.harness});

  final Harness harness;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<String>? _copies;
  String? _message;
  bool _busy = false;

  BackupService get _service => widget.harness.backup;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final copies = await _service.copies();
    if (mounted) setState(() => _copies = copies);
  }

  Future<void> _backUp() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final r = await _service.backUp();
    widget.harness.log.info(
      r == null
          ? 'backup failed: could not write'
          : 'backup made${r.inDownloads ? ' (and copied to Downloads)' : ''}',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = r == null
          ? context.tr('app.backup.the_backup_could_not_be_written')
          : r.inDownloads
          ? tok('app.backup.backed_up_as_name_here_and', {'name': r.name})
          : tok('app.backup.backed_up_as_name_this_phone', {'name': r.name});
    });
    await _load();
  }

  Future<void> _saveAs() async {
    final doc = await _service.collect();
    final bytes = Uint8List.fromList(utf8.encode(doc.toText()));
    final saved = await widget.harness.picker.save(
      backupFileName(doc.createdAt),
      bytes,
    );
    widget.harness.log.info(
      saved ? 'backup saved to a chosen place' : 'save backup cancelled',
    );
    if (!mounted || !saved) return;
    setState(() => _message = context.tr('app.backup.backup_saved'));
  }

  Future<void> _restoreFromFile() async {
    final PickedFile? file;
    try {
      file = await widget.harness.picker.pick();
    } on BackupException catch (e) {
      if (mounted) setState(() => _message = backupProblemText(e.problem));
      return;
    }
    if (file == null) return;
    await _restore(file.bytes);
  }

  Future<void> _restore(Uint8List bytes) async {
    final BackupDocument doc;
    try {
      doc = parseBackup(bytes);
    } on BackupException catch (e) {
      widget.harness.log.warn('restore refused: ${e.problem.name}');
      if (mounted) setState(() => _message = backupProblemText(e.problem));
      return;
    }
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('app.backup.restore_this_backup')),
        content: Text(
          context.tr('app.backup.made_firstx_it_replaces_the_settings_2', {
            'first': doc.createdAt.toLocal().toString().split('.').first,
            'x': doc.appVersion.isEmpty ? '' : ' by version ${doc.appVersion}',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('common.action.restore.label')),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ({List<String> restored, List<String> ignored}) r;
    try {
      r = await _service.restore(doc);
    } on BackupException catch (e) {
      // Every section is checked before any is written, so nothing on the phone has changed.
      widget.harness.log.warn('restore refused: ${e.problem.name}');
      if (mounted) setState(() => _message = backupProblemText(e.problem));
      return;
    }
    widget.harness.log.info(
      'restored: ${r.restored.join(', ')}${r.ignored.isEmpty ? '' : ' (ignored: ${r.ignored.join(', ')})'}',
    );
    if (!mounted) return;
    setState(() {
      _message = r.ignored.isEmpty
          ? context.tr('app.backup.restored_pair_this_phone_again_to')
          : 'Restored. The file also held ${r.ignored.length} part${r.ignored.length == 1 ? '' : 's'} this version of the app does not know, which were left out.';
    });
  }

  Future<void> _restoreCopy(String name) async {
    final bytes = await _service.readCopy(name);
    if (bytes == null) {
      if (mounted) {
        setState(
          () => _message = context.tr('app.backup.that_copy_could_not_be_read'),
        );
      }
      return;
    }
    await _restore(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final copies = _copies;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.backup.backup_and_restore'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.tr('app.backup.a_backup_keeps_the_app_s')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _backUp,
            child: Text(context.tr('settings.backup.now.label')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _saveAs,
            child: Text(context.tr('app.backup.save_a_copy_somewhere')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _restoreFromFile,
            child: Text(context.tr('app.backup.restore_from_a_file')),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!),
          ],
          const SizedBox(height: 24),
          Text(
            context.tr('app.backup.copies_on_this_phone'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (copies == null)
            const LinearProgressIndicator()
          else if (copies.isEmpty)
            Text(context.tr('app.backup.none_yet'))
          else
            for (final name in copies)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(name),
                trailing: TextButton(
                  onPressed: () => _restoreCopy(name),
                  child: Text(context.tr('common.action.restore.label')),
                ),
              ),
        ],
      ),
    );
  }
}
