import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../harness/backup_screen.dart';
import '../harness/changelog_screen.dart';
import '../harness/harness.dart';
import '../harness/log_screen.dart';
import '../harness/server_log_screen.dart';
import 'devices_screen.dart';
import 'pair_screen.dart';
import 'pull_screen.dart';
import 'sync_screen.dart';
import '../harness/update_controller.dart';
import '../harness/update_ui.dart';
import '../harness/version.dart';
import 'connect_screen.dart';

/// Which server the app is pointed at, and the way to point it somewhere else or forget it.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.harness,
  });

  final AppController controller;
  final Harness harness;

  Future<void> _forget(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this server?'),
        content: const Text(
          'The app forgets the server address and the credential it holds for it. Nothing on the server changes; '
          'you can pair this phone again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (yes == true) await controller.forget();
  }

  Future<void> _unpair(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unpair this phone?'),
        content: const Text(
          'The server is told to forget this phone, and the app forgets its key. The server address stays, so you can pair again with a new code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (yes == true) await controller.unpair();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final url = controller.serverUrl;
        return ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Server'),
              subtitle: Text(url ?? 'Not set'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConnectScreen(controller: controller),
                ),
              ),
            ),
            if (url != null && !controller.paired)
              ListTile(
                leading: const Icon(Icons.phonelink_lock_outlined),
                title: const Text('Pair this phone'),
                subtitle: const Text('Needed to use your library'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PairScreen(controller: controller),
                  ),
                ),
              ),
            if (controller.paired) ...[
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: const Text('Paired devices'),
                subtitle: Text('Paired as ${controller.username ?? ''}'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DevicesScreen(controller: controller),
                  ),
                ),
              ),
              if (harness.pull != null)
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Sync with server'),
                  subtitle: const Text(
                    'Brings down changes, sends yours up, and lets you settle clashes',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PullScreen(sync: harness.pull!),
                    ),
                  ),
                ),
              if (harness.sync != null)
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('Send library to server'),
                  subtitle: const Text('Adds what is only on this phone'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SyncScreen(sync: harness.sync!),
                    ),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.phonelink_erase_outlined),
                title: const Text('Unpair this phone'),
                onTap: () => _unpair(context),
              ),
            ],
            if (url != null)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Forget this server'),
                onTap: () => _forget(context),
              ),
            const Divider(),
            ListenableBuilder(
              listenable: harness.updates,
              builder: (context, _) {
                final u = harness.updates;
                return ListTile(
                  leading: const Icon(Icons.system_update_outlined),
                  title: Text(
                    u.stage == UpdateStage.available
                        ? 'Update available'
                        : 'Check for updates',
                  ),
                  subtitle: Text(checkResultText(u)),
                  onTap: u.stage == UpdateStage.checking
                      ? null
                      : () async {
                          if (u.stage != UpdateStage.available) {
                            await u.checkNow();
                          }
                          if (context.mounted &&
                              u.stage == UpdateStage.available) {
                            await showUpdateDialog(context, u);
                          }
                        },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.new_releases_outlined),
              title: const Text("What's new"),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChangelogScreen(harness: harness),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Backup and restore'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BackupScreen(harness: harness),
                ),
              ),
            ),
            // TWO LOGS, KEPT APART. The app's log is this phone's own record of what the app did; the
            // server's log is the server's, kept there, and only an admin can read it. They never share a
            // screen, a copy or a file.
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('App log'),
              subtitle: const Text("What this app did on this phone"),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LogScreen(log: harness.log),
                ),
              ),
            ),
            if (controller.isAdmin)
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Server log'),
                subtitle: const Text(
                  "The Tippani server's own log. Admins only",
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ServerLogScreen(controller: controller),
                  ),
                ),
              ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Tippani for Android $appVersion'),
              subtitle: Text(
                'Free software, GPL-3.0. Source: github.com/aaronified/tippani-app',
              ),
            ),
          ],
        );
      },
    );
  }
}
