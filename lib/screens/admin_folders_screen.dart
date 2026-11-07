import 'package:flutter/material.dart';

import '../admin/admin_service.dart';
import 'admin_widgets.dart';

String _slug(String s) {
  final out = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return out.isEmpty
      ? 'folder'
      : (out.length > 32 ? out.substring(0, 32) : out);
}

String _size(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
  return '$bytes bytes';
}

/// The folders on the server's disk its library is read from (books and films whose files give a quote its
/// context), whether the backup carries those saved files, and a tidy-up of saved files nothing uses.
class AdminFoldersScreen extends StatelessWidget {
  const AdminFoldersScreen({super.key, required this.service});

  final AdminService service;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Library folders')),
    body: Loader<LibraryFolders>(
      load: service.folders,
      builder: (context, folders, reload) =>
          _Folders(service: service, folders: folders, reload: reload),
    ),
  );
}

class _Folders extends StatelessWidget {
  const _Folders({
    required this.service,
    required this.folders,
    required this.reload,
  });

  final AdminService service;
  final LibraryFolders folders;
  final Future<void> Function() reload;

  Future<void> _add(BuildContext context) async {
    final path = await askText(
      context,
      title: 'A folder on the server',
      label: 'Path on the server, like /books',
      yes: 'Next',
    );
    if (path == null || path.trim().isEmpty || !context.mounted) return;
    final guess = path.trim().split('/').where((p) => p.isNotEmpty).lastOrNull;
    final label = await askText(
      context,
      title: 'What to call it',
      label: 'Name',
      initial: guess ?? path.trim(),
      yes: 'Add',
    );
    if (label == null || !context.mounted) return;
    final name = label.trim().isEmpty ? (guess ?? path.trim()) : label.trim();
    final taken = {for (final m in folders.mounts) m.id};
    var id = _slug(name);
    for (var n = 2; taken.contains(id); n++) {
      id = '${_slug(name)}-$n';
    }
    final ok = await attempt(
      context,
      () async => service.saveMounts([
        ...folders.mounts,
        MountInfo(id: id, label: name, path: path.trim()),
      ]),
    );
    if (ok) await reload();
  }

  Future<void> _remove(BuildContext context, MountInfo m) async {
    final ok = await confirmDialog(
      context,
      title: 'Stop reading ${m.label}?',
      body: 'The folder itself is not touched. Files already attached from it stay saved.',
      yes: 'Remove',
    );
    if (!ok || !context.mounted) return;
    final done = await attempt(
      context,
      () async => service.saveMounts([
        for (final x in folders.mounts)
          if (x.id != m.id) x,
      ]),
    );
    if (done) await reload();
  }

  Future<void> _tidy(BuildContext context) async {
    int removed = 0;
    final ok = await attempt(context, () async {
      removed = await service.tidySources();
    });
    if (ok && context.mounted) {
      say(
        context,
        removed == 0
            ? 'Nothing to tidy.'
            : 'Removed $removed saved ${removed == 1 ? 'file' : 'files'}.',
      );
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (folders.mounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No folder is shared with Tippani yet. Add one that holds your books or films, and quotes can show the text around them.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final m in folders.mounts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Card(
                    child: ListTile(
                      leading: Icon(
                        m.ok
                            ? Icons.folder_outlined
                            : Icons.folder_off_outlined,
                        color: m.ok ? scheme.primary : scheme.error,
                      ),
                      title: Text(m.label),
                      subtitle: Text(
                        m.ok || m.error.isEmpty
                            ? m.path
                            : '${m.path}\n${m.error}',
                      ),
                      isThreeLine: !m.ok && m.error.isNotEmpty,
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _remove(context, m),
                      ),
                    ),
                  ),
                ),
              const AdminHeading('Backups'),
              Card(
                child: SwitchListTile(
                  title: const Text('Put the saved files in backups'),
                  subtitle: const Text(
                    'The files attached to works are copied into each backup. Backups get bigger.',
                  ),
                  value: folders.backupWithSources,
                  onChanged: (v) async {
                    final ok = await attempt(
                      context,
                      () async => service.setBackupSources(v),
                    );
                    if (ok) await reload();
                  },
                ),
              ),
              const AdminHeading('Tidy up'),
              Card(
                child: ListTile(
                  title: Text(
                    folders.orphanFiles == 0
                        ? 'No saved file is unused'
                        : '${folders.orphanFiles} saved ${folders.orphanFiles == 1 ? 'file is' : 'files are'} unused (${_size(folders.orphanBytes)})',
                  ),
                  subtitle: Text(
                    folders.missingFiles == 0
                        ? 'Every attached file is where it should be.'
                        : '${folders.missingFiles} attached ${folders.missingFiles == 1 ? 'file is' : 'files are'} missing from the disk.',
                    style: text.bodySmall,
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: folders.orphanFiles == 0
                        ? null
                        : () => _tidy(context),
                    child: const Text('Tidy'),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'add-folder',
            onPressed: () => _add(context),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add a folder'),
          ),
        ),
      ],
    );
  }
}
