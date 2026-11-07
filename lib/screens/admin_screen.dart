import 'package:flutter/material.dart';

import '../admin/admin_service.dart';
import '../admin/server_files.dart';
import 'admin_backup_screen.dart';
import 'admin_folders_screen.dart';
import 'admin_jobs_screen.dart';
import 'admin_sources_screen.dart';
import 'admin_update_screen.dart';
import 'admin_users_screen.dart';

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
      appBar: AppBar(title: const Text('Server administration')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          row(
            Icons.group_outlined,
            'Users',
            'Add a reader, make an admin, remove an account',
            () => AdminUsersScreen(service: service, myName: myName),
          ),
          row(
            Icons.work_history_outlined,
            'Jobs',
            'What is running and waiting, what ran, and common jobs to start',
            () => AdminJobsScreen(service: service),
          ),
          row(
            Icons.backup_outlined,
            'Server backup',
            'Make a backup, keep it on this phone, put one back',
            () => AdminBackupScreen(service: service, files: files),
          ),
          row(
            Icons.system_update_alt_rounded,
            'Server updates',
            'The version it runs, and updating it',
            () => AdminUpdateScreen(service: service),
          ),
          row(
            Icons.folder_open_outlined,
            'Library folders',
            'Folders on the server that quotes read their context from',
            () => AdminFoldersScreen(service: service),
          ),
          row(
            Icons.travel_explore_rounded,
            'Metadata sources',
            'Who the server asks for details, and its keys',
            () => AdminSourcesScreen(service: service),
          ),
        ],
      ),
    );
  }
}
