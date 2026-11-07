import 'package:flutter/material.dart';

import '../admin/admin_service.dart';
import 'admin_widgets.dart';
import '../l10n/l10n.dart';

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
    appBar: AppBar(title: Text(context.tr('settings.library.folders.label'))),
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
      title: context.tr('app.admin_folders.a_folder_on_the_server'),
      label: context.tr('app.admin_folders.path_on_the_server_like_books'),
      yes: context.tr('common.date.picker.next.aria'),
    );
    if (path == null || path.trim().isEmpty || !context.mounted) return;
    final guess = path.trim().split('/').where((p) => p.isNotEmpty).lastOrNull;
    final label = await askText(
      context,
      title: context.tr('app.admin_folders.what_to_call_it'),
      label: context.tr('common.field.name.label'),
      initial: guess ?? path.trim(),
      yes: context.tr('common.action.add.label'),
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
      title: context.tr('app.admin_folders.stop_reading_label', {
        'label': m.label,
      }),
      body: context.tr('app.admin_folders.the_folder_itself_is_not_touched'),
      yes: context.tr('common.action.remove.label'),
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
            ? context.tr('app.admin_folders.nothing_to_tidy')
            : trn('app.admin_folders.removed_files', removed),
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
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    context.tr(
                      'app.admin_folders.no_folder_is_shared_with_tippani',
                    ),
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
                        tooltip: context.tr('common.action.remove.label'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _remove(context, m),
                      ),
                    ),
                  ),
                ),
              AdminHeading(context.tr('account.notify.event.backup.title')),
              Card(
                child: SwitchListTile(
                  title: Text(
                    context.tr(
                      'app.admin_folders.put_the_saved_files_in_backups',
                    ),
                  ),
                  subtitle: Text(
                    context.tr(
                      'app.admin_folders.the_files_attached_to_works_are',
                    ),
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
              AdminHeading(context.tr('app.admin_folders.tidy_up')),
              Card(
                child: ListTile(
                  title: Text(
                    folders.orphanFiles == 0
                        ? context.tr(
                            'app.admin_folders.no_saved_file_is_unused',
                          )
                        : '${folders.orphanFiles} saved ${folders.orphanFiles == 1 ? 'file is' : 'files are'} unused (${_size(folders.orphanBytes)})',
                  ),
                  subtitle: Text(
                    folders.missingFiles == 0
                        ? context.tr(
                            'app.admin_folders.every_attached_file_is_where_it',
                          )
                        : '${folders.missingFiles} attached ${folders.missingFiles == 1 ? 'file is' : 'files are'} missing from the disk.',
                    style: text.bodySmall,
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: folders.orphanFiles == 0
                        ? null
                        : () => _tidy(context),
                    child: Text(context.tr('app.admin_folders.tidy')),
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
            label: Text(context.tr('settings.library.add.label')),
          ),
        ),
      ],
    );
  }
}
