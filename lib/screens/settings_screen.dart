import 'conflicts_screen.dart';
import 'read_aloud_settings_screen.dart';
import 'tools_screens.dart';

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
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 12,
            bottom: 24,
          ),
          children: [
            const _Section('Server'),
            _Group(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(
                    url == null ? 'Connect to your server' : 'Server',
                  ),
                  subtitle: Text(
                    url == null
                        ? 'Not connected to a server yet.'
                        : '$url\n${serverStatusLine(controller)}',
                  ),
                  isThreeLine: url != null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ConnectScreen(controller: controller),
                    ),
                  ),
                ),
                if (controller.revoked)
                  ListTile(
                    leading: Icon(
                      Icons.warning_amber_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text(
                      'This phone was unpaired from the server',
                    ),
                    subtitle: const Text('Pair it again to use your library.'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PairScreen(controller: controller),
                      ),
                    ),
                  ),
                if (url != null)
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('Check again'),
                    enabled: !controller.checking,
                    onTap: controller.refresh,
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
                  if (harness.tools != null) ...[
                    ListTile(
                      leading: const Icon(Icons.bar_chart_outlined),
                      title: const Text('Statistics'),
                      subtitle: const Text(
                        'The numbers the server keeps about your library',
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StatsScreen(tools: harness.tools!),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Bin'),
                      subtitle: const Text(
                        'What you deleted lately, to bring back',
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BinScreen(tools: harness.tools!),
                        ),
                      ),
                    ),
                  ],
                  if (harness.auto != null)
                    ListenableBuilder(
                      listenable: harness.auto!,
                      builder: (context, _) {
                        final auto = harness.auto!;
                        final n = auto.conflicts.length;
                        return Column(
                          children: [
                            ListTile(
                              leading: auto.syncing
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.sync),
                              title: const Text('Sync with server'),
                              subtitle: Text(
                                auto.failure != null
                                    ? 'The last try did not finish'
                                    : auto.lastSynced != null
                                    ? (auto.enabled
                                          ? 'Automatic · up to date'
                                          : 'Automatic sync is off')
                                    : (auto.enabled
                                          ? 'Automatic'
                                          : 'Automatic sync is off'),
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => PullScreen(auto: auto),
                                ),
                              ),
                            ),
                            ListTile(
                              leading: const Icon(Icons.sync_problem_outlined),
                              title: const Text('Sync conflicts'),
                              subtitle: Text(
                                n == 0
                                    ? 'Nothing to settle'
                                    : n == 1
                                    ? '1 waiting for you'
                                    : '$n waiting for you',
                              ),
                              trailing: n == 0
                                  ? null
                                  : Badge(label: Text('$n')),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ConflictsScreen(auto: auto),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
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
              ],
            ),
            const _Section('App'),
            _Group(
              children: [
                ListTile(
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('Read aloud'),
                  subtitle: const Text('Voice, speed and pitch'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReadAloudSettingsScreen(),
                    ),
                  ),
                ),
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
              ],
            ),
            const SizedBox(height: 16),
            const _Group(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Tippani for Android $appVersion'),
                  subtitle: Text(
                    'Free software, GPL-3.0. Source: github.com/aaronified/tippani-app',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A group of settings on one rounded surface, so the screen reads as a few blocks and not one long list.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Column(mainAxisSize: MainAxisSize.min, children: [...children]),
      ),
    );
  }
}

/// A heading over a group of settings.
class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
