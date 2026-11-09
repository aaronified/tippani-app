import 'admin_screen.dart';
import 'checks_entry.dart';
import 'metadata_tools_screen.dart';
import 'source_files_screen.dart';
import 'filtered_quotes_screen.dart';
import 'people_console_screen.dart';
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
import 'prefs_entries.dart';
import 'tags_screen.dart';
import 'pair_screen.dart';
import 'pull_screen.dart';
import 'sync_screen.dart';
import '../harness/update_controller.dart';
import '../harness/update_ui.dart';
import '../harness/version.dart';
import 'connect_screen.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

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
        title: Text(context.tr('app.settings.forget_this_server')),
        content: Text(
          context.tr('app.settings.the_app_forgets_the_server_address'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('app.settings.forget')),
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
        title: Text(context.tr('app.settings.unpair_this_phone')),
        content: Text(context.tr('app.settings.the_server_is_told_to_forget')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common.action.cancel.label')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('app.devices.unpair')),
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
            _Section(context.tr('settings.section.server.label')),
            _Group(
              children: [
                ListTile(
                  leading: const Icon(Ti.server),
                  title: Text(
                    url == null ? 'Connect to your server' : 'Server',
                  ),
                  subtitle: Text(
                    url == null
                        ? context.tr('app.home.not_connected_to_a_server_yet')
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
                      Ti.alertTriangle,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      context.tr(
                        'app.settings.this_phone_was_unpaired_from_the',
                      ),
                    ),
                    subtitle: Text(
                      context.tr('app.settings.pair_it_again_to_use_your'),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PairScreen(controller: controller),
                      ),
                    ),
                  ),
                if (url != null)
                  ListTile(
                    leading: const Icon(Ti.refresh),
                    title: Text(context.tr('app.admin_update.check_again')),
                    enabled: !controller.checking,
                    onTap: controller.refresh,
                  ),
                if (url != null && !controller.paired)
                  ListTile(
                    leading: const Icon(Ti.deviceMobileCode),
                    title: Text(context.tr('app.home.pair_this_phone')),
                    subtitle: Text(
                      context.tr('app.settings.needed_to_use_your_library'),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PairScreen(controller: controller),
                      ),
                    ),
                  ),
                if (controller.paired) ...[
                  ListTile(
                    leading: const Icon(Ti.devices),
                    title: Text(context.tr('app.devices.paired_devices')),
                    subtitle: Text(
                      context.tr('app.settings.paired_as_name', {
                        'name': controller.username ?? '',
                      }),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DevicesScreen(controller: controller),
                      ),
                    ),
                  ),
                  if (harness.tools != null) ...[
                    ListTile(
                      leading: const Icon(Ti.chartBar),
                      title: Text(context.tr('app.settings.statistics')),
                      subtitle: Text(
                        context.tr(
                          'app.settings.the_numbers_the_server_keeps_about',
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StatsScreen(
                            tools: harness.tools!,
                            store: harness.library,
                            picker: harness.picker,
                            anthologies: harness.anthologies,
                          ),
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Ti.trash),
                      title: Text(context.tr('bin.title')),
                      subtitle: Text(
                        context.tr(
                          'app.settings.what_you_deleted_lately_to_bring',
                        ),
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
                                  : const Icon(Ti.refresh),
                              title: Text(
                                context.tr('app.pull.sync_with_server'),
                              ),
                              subtitle: Text(
                                auto.failure != null
                                    ? context.tr(
                                        'app.settings.the_last_try_did_not_finish',
                                      )
                                    : auto.lastSynced != null
                                    ? (auto.enabled
                                          ? context.tr(
                                              'app.settings.automatic_up_to_date',
                                            )
                                          : context.tr(
                                              'app.settings.automatic_sync_is_off',
                                            ))
                                    : (auto.enabled
                                          ? 'Automatic'
                                          : context.tr(
                                              'app.settings.automatic_sync_is_off',
                                            )),
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => PullScreen(auto: auto),
                                ),
                              ),
                            ),
                            ListTile(
                              leading: const Icon(Ti.refreshAlert),
                              title: Text(
                                context.tr('app.conflicts.sync_conflicts'),
                              ),
                              subtitle: Text(
                                n == 0
                                    ? context.tr(
                                        'app.settings.nothing_to_settle',
                                      )
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
                      leading: const Icon(Ti.cloudUpload),
                      title: Text(
                        context.tr('app.settings.send_library_to_server'),
                      ),
                      subtitle: Text(
                        context.tr('app.settings.adds_what_is_only_on_this'),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SyncScreen(sync: harness.sync!),
                        ),
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Ti.deviceMobileOff),
                    title: Text(context.tr('app.settings.unpair_this_phone_2')),
                    onTap: () => _unpair(context),
                  ),
                ],
                if (url != null)
                  ListTile(
                    leading: const Icon(Ti.unlink),
                    title: Text(
                      context.tr('app.settings.forget_this_server_2'),
                    ),
                    onTap: () => _forget(context),
                  ),
              ],
            ),
            if (harness.library != null || harness.imports != null) ...[
              _Section(context.tr('app.settings.your_library')),
              _Group(
                children: [
                  ChecksEntry(controller: controller, harness: harness),
                  if (harness.sources != null && harness.library != null)
                    ListTile(
                      leading: const Icon(Ti.fileText),
                      title: Text(context.tr('metadata.section.files.label')),
                      subtitle: Text(
                        context.tr(
                          'app.settings.the_ebooks_and_subtitles_your_quotes',
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SourceFilesScreen(
                            service: harness.sources!,
                            library: harness.library!,
                            picker: harness.sourcePicker,
                          ),
                        ),
                      ),
                    ),
                  if (harness.peopleConsole != null && harness.library != null)
                    ListTile(
                      leading: const Icon(Ti.usersGroup),
                      title: Text(
                        context.tr('app.settings.people_and_characters'),
                      ),
                      subtitle: Text(
                        context.tr(
                          'app.settings.authors_actors_speakers_and_characters_spellings',
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => PeopleConsoleScreen(
                            console: harness.peopleConsole!,
                            onFilter: (f) => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => FilteredQuotesScreen(
                                  store: harness.library!,
                                  picker: harness.picker,
                                  title: f.name,
                                  query: f.name,
                                  anthologies: harness.anthologies,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (harness.metadata != null && harness.library != null)
                    ListTile(
                      leading: const Icon(Ti.worldSearch),
                      title: Text(
                        context.tr('app.settings.details_and_duplicates'),
                      ),
                      subtitle: Text(
                        context.tr('app.settings.works_that_lack_a_cover_or'),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MetadataToolsScreen(
                            service: harness.metadata!,
                            admin: controller.isAdmin,
                            onChanged: () => harness.auto?.scheduleSoon(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (controller.isAdmin && harness.admin != null) ...[
              _Section(context.tr('app.admin.server_administration')),
              _Group(
                children: [
                  ListTile(
                    leading: const Icon(Ti.shieldLock),
                    title: Text(context.tr('app.settings.run_the_server')),
                    subtitle: Text(
                      context.tr(
                        'app.settings.users_jobs_backups_updates_library_folders',
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdminScreen(
                          service: harness.admin!,
                          files: harness.serverFiles,
                          myName: controller.username ?? '',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            PrefsEntries(controller: controller, harness: harness),
            const _Section('App'),
            _Group(
              children: [
                if (harness.library != null)
                  ListTile(
                    leading: const Icon(Ti.tag),
                    title: Text(context.tr('common.field.tags.label')),
                    subtitle: Text(
                      context.tr(
                        'app.settings.rename_colour_merge_and_delete_your',
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TagsScreen(
                          store: harness.library!,
                          picker: harness.picker,
                          service: harness.tags,
                          anthologies: harness.anthologies,
                        ),
                      ),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Ti.speakerphone),
                  title: Text(context.tr('speech.play.aria')),
                  subtitle: Text(
                    context.tr('app.settings.voice_speed_and_pitch'),
                  ),
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
                      leading: const Icon(Ti.circleArrowDown),
                      title: Text(
                        u.stage == UpdateStage.available
                            ? context.tr('app.settings.update_available')
                            : context.tr('settings.updates.check.label'),
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
                  leading: const Icon(Ti.sparkles),
                  title: Text(context.tr('app.changelog.what_s_new')),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChangelogScreen(harness: harness),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Ti.databaseExport),
                  title: Text(context.tr('app.backup.backup_and_restore')),
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
                  leading: const Icon(Ti.receipt),
                  title: Text(context.tr('app.settings.app_log')),
                  subtitle: Text(
                    context.tr('app.settings.what_this_app_did_on_this'),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LogScreen(log: harness.log),
                    ),
                  ),
                ),
                if (controller.isAdmin)
                  ListTile(
                    leading: const Icon(Ti.server),
                    title: Text(context.tr('app.server_log.server_log')),
                    subtitle: Text(
                      context.tr('app.settings.the_tippani_server_s_own_log'),
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
            _Group(
              children: [
                ListTile(
                  leading: Icon(Ti.infoCircle),
                  title: Text(
                    context.tr('app.settings.tippani_for_android_app_version', {
                      'app_version': appVersion,
                    }),
                  ),
                  subtitle: Text(
                    '${context.tr('app.settings.free_software_gpl_3_0_source')}\n${context.tr('app.settings.icons_by_tabler')}',
                  ),
                  isThreeLine: true,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Tippani',
                    applicationVersion: appVersion,
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
