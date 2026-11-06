import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../harness/backup_screen.dart';
import '../harness/changelog_screen.dart';
import '../harness/harness.dart';
import '../harness/log_screen.dart';
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
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Log'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LogScreen(log: harness.log),
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
