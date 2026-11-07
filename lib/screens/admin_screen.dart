import 'package:flutter/material.dart';

import '../admin/admin_service.dart';
import '../admin/server_files.dart';
import 'admin_backup_screen.dart';
import 'admin_folders_screen.dart';
import 'admin_jobs_screen.dart';
import 'admin_sources_screen.dart';
import 'admin_update_screen.dart';
import 'admin_users_screen.dart';
import '../l10n/l10n.dart';

/// Running the server: its users, jobs, backups, updates, library folders and metadata sources. Only an admin
/// account is offered this (Settings hides it for anyone else), and the server checks again on every call.
class AdminScreen extends StatelessWidget {
  const AdminScreen({
    super.key,
    required this.service,
    required this.files,
    this.myName = '',
  });

  final AdminService service;
  final ServerFiles files;
  final String myName;

  @override
  Widget build(BuildContext context) {
    Widget row(
      IconData icon,
      String title,
      String hint,
      Widget Function() to,
    ) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(hint),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => to())),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.admin.server_administration')),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          row(
            Icons.group_outlined,
            'Users',
            context.tr('app.admin.add_a_reader_make_an_admin'),
            () => AdminUsersScreen(service: service, myName: myName),
          ),
          row(
            Icons.work_history_outlined,
            'Jobs',
            context.tr('app.admin.what_is_running_and_waiting_what'),
            () => AdminJobsScreen(service: service),
          ),
          row(
            Icons.backup_outlined,
            context.tr('app.admin_backup.server_backup'),
            context.tr('app.admin.make_a_backup_keep_it_on'),
            () => AdminBackupScreen(service: service, files: files),
          ),
          row(
            Icons.system_update_alt_rounded,
            context.tr('app.admin_update.server_updates'),
            context.tr('app.admin.the_version_it_runs_and_updating'),
            () => AdminUpdateScreen(service: service),
          ),
          row(
            Icons.folder_open_outlined,
            context.tr('settings.library.folders.label'),
            context.tr('app.admin.folders_on_the_server_that_quotes'),
            () => AdminFoldersScreen(service: service),
          ),
          row(
            Icons.travel_explore_rounded,
            context.tr('metadata.help.metadata-sources.term'),
            context.tr('app.admin.who_the_server_asks_for_details'),
            () => AdminSourcesScreen(service: service),
          ),
        ],
      ),
    );
  }
}
