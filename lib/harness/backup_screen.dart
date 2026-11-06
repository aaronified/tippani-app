import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'backup.dart';
import 'harness.dart';

/// One plain sentence for each reason a file could not be restored. Pure, so the words are tested.
String backupProblemText(BackupProblem p) => switch (p) {
  BackupProblem.tooBig => 'That file is too big to be a Tippani backup.',
  BackupProblem.notJson =>
    'That file is not a Tippani backup (it is not readable as one).',
  BackupProblem.notOurs => 'That file is not a Tippani backup.',
  BackupProblem.tooNew => 'That backup was made by a newer version of the app. Update the app, then restore it.',
  BackupProblem.noSections => 'That backup holds nothing to restore.',
  BackupProblem.damaged => 'Part of that backup is damaged, so none of it was restored. Nothing on this phone has changed.',
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
          ? 'The backup could not be written.'
          : r.inDownloads
          ? 'Backed up as ${r.name}, here and in your Downloads folder.'
          : 'Backed up as ${r.name}. This phone could not also copy it to Downloads.';
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
    setState(() => _message = 'Backup saved.');
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
        title: const Text('Restore this backup?'),
        content: Text(
          'Made ${doc.createdAt.toLocal().toString().split('.').first}'
          '${doc.appVersion.isEmpty ? '' : ' by version ${doc.appVersion}'}.\n\n'
          'It replaces the settings and the library on this phone with the ones in the file, whatever is there now. You will need to pair this phone again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
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
          ? 'Restored. Pair this phone again to use it.'
          : 'Restored. The file also held ${r.ignored.length} part${r.ignored.length == 1 ? '' : 's'} this version of the app does not know, which were left out.';
    });
  }

  Future<void> _restoreCopy(String name) async {
    final bytes = await _service.readCopy(name);
    if (bytes == null) {
      if (mounted) setState(() => _message = 'That copy could not be read.');
      return;
    }
    await _restore(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final copies = _copies;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'A backup keeps the app\'s settings. It does not hold the key that pairs this phone with your server, '
            'so after a restore you pair again.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _backUp,
            child: const Text('Back up now'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _saveAs,
            child: const Text('Save a copy somewhere…'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _restoreFromFile,
            child: const Text('Restore from a file…'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!),
          ],
          const SizedBox(height: 24),
          Text(
            'Copies on this phone',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (copies == null)
            const LinearProgressIndicator()
          else if (copies.isEmpty)
            const Text('None yet.')
          else
            for (final name in copies)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(name),
                trailing: TextButton(
                  onPressed: () => _restoreCopy(name),
                  child: const Text('Restore'),
                ),
              ),
        ],
      ),
    );
  }
}
