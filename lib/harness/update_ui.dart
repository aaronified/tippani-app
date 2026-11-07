import 'package:flutter/material.dart';

import 'apk_install.dart';
import 'changelog.dart';
import 'harness.dart';
import 'update_check.dart';
import 'update_controller.dart';
import 'version.dart';
import '../l10n/l10n.dart';

/// One plain sentence for each way an install can fail. Pure, so the words are tested.
String installFailureText(InstallFailure f) => switch (f) {
  InstallFailure.download =>
    'The download did not finish. Check your connection and try again.',
  InstallFailure.checksum => 'The downloaded file is not the one that was published, so it was not installed. Try again.',
  InstallFailure.notAllowed => 'Android will not let Tippani install updates yet. Allow "Install unknown apps" for Tippani in the phone\'s settings, then try again.',
  InstallFailure.install => 'Android\'s installer would not open. Try again, or download the update from the project\'s releases page.',
  InstallFailure.cancelled => 'The update was cancelled.',
  InstallFailure.internal => 'Something went wrong while updating. Try again.',
};

/// What a reader asked for by pressing "Check for updates", in a sentence.
String checkResultText(UpdateController u) {
  switch (u.stage) {
    case UpdateStage.available:
      return 'Version ${u.release?.version} is available.';
    case UpdateStage.upToDate:
      return 'You have the latest version ($appVersion).';
    case UpdateStage.checking:
      return 'Checking…';
    default:
      return switch (u.checkFailure) {
        CheckFailure.offline =>
          'Could not reach GitHub. Check your connection.',
        CheckFailure.rateLimited => 'GitHub is limiting requests from this network. Try again in a while.',
        CheckFailure.badReply =>
          'GitHub answered, but not in a way this app understands.',
        null => 'Version $appVersion.',
      };
  }
}

/// Wraps the app's frame: it asks for an update when the app opens, shows a toast when there is one, and
/// shows what is new on the first start after an update. It draws nothing of its own.
class UpdateHost extends StatefulWidget {
  const UpdateHost({super.key, required this.harness, required this.child});

  final Harness harness;
  final Widget child;

  @override
  State<UpdateHost> createState() => _UpdateHostState();
}

class _UpdateHostState extends State<UpdateHost> {
  UpdateController get _updates => widget.harness.updates;

  @override
  void initState() {
    super.initState();
    _updates.addListener(_onUpdate);
    _updates.checkOnOpen();
    WidgetsBinding.instance.addPostFrameCallback((_) => _whatsNew());
  }

  @override
  void dispose() {
    _updates.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted || !_updates.takeAnnouncement()) return;
    final release = _updates.release;
    if (release == null) return;
    // THE TOAST: an update is available, and one press downloads it. It stays long enough to read and
    // never blocks what the reader came to do.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            context.tr('Version {version} is available', {
              'version': release.version,
            }),
          ),
          duration: const Duration(seconds: 12),
          action: SnackBarAction(
            label: context.tr('Download'),
            onPressed: () =>
                showUpdateDialog(context, _updates, startNow: true),
          ),
        ),
      );
  }

  Future<void> _whatsNew() async {
    final h = widget.harness;
    final lastSeen = h.settings.lastSeenVersion;
    // Recorded whether or not anything is shown, so the dialog appears once per update.
    await h.settings.setLastSeenVersion(appVersion);
    if (!h.showWhatsNew) return;
    final entry = whatsNew(
      lastSeen: lastSeen,
      current: appVersion,
      entries: await h.changelog(),
    );
    if (entry == null || !mounted) return;
    h.log.info('showing what is new in ${entry.version}');
    await showWhatsNewDialog(context, entry);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showWhatsNewDialog(BuildContext context, ChangelogEntry entry) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('New in {version}', {'version': entry.version})),
      content: SingleChildScrollView(child: ChangelogBody(entry: entry)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('OK')),
        ),
      ],
    ),
  );
}

/// An entry's sections, each change by its header only (see [changeHeader]); the full words are on GitHub.
class ChangelogBody extends StatelessWidget {
  const ChangelogBody({super.key, required this.entry});

  final ChangelogEntry entry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in entry.sections.entries) ...[
          if (s.key.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(s.key, style: text.titleSmall),
            ),
          for (final b in s.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• ${changeHeader(b)}'),
            ),
        ],
      ],
    );
  }
}

/// The update's own dialog: what is on offer, the download with its progress, and what to do when it fails.
/// [startNow] begins the download at once, for the toast's Download button.
Future<void> showUpdateDialog(
  BuildContext context,
  UpdateController updates, {
  bool startNow = false,
}) {
  if (startNow) updates.download();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _UpdateDialog(updates: updates),
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.updates});

  final UpdateController updates;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final r = updates.release;
        final version = r?.version ?? '';
        switch (updates.stage) {
          case UpdateStage.downloading:
            return AlertDialog(
              title: Text(
                context.tr('Downloading {version}', {'version': version}),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: updates.percent == 0 ? null : updates.percent / 100,
                  ),
                  const SizedBox(height: 8),
                  Text('${updates.percent}%'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: updates.cancel,
                  child: Text(context.tr('Cancel')),
                ),
              ],
            );
          case UpdateStage.installing:
            return AlertDialog(
              title: Text(context.tr('Ready to install')),
              content: Text(
                context.tr(
                  'Android is asking you to install the update. Tippani will close while it does.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('OK')),
                ),
              ],
            );
          case UpdateStage.failed:
            return AlertDialog(
              title: Text(context.tr('The update did not install')),
              content: Text(
                installFailureText(
                  updates.installFailure ?? InstallFailure.internal,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    updates.dismiss();
                    Navigator.pop(context);
                  },
                  child: Text(context.tr('Close')),
                ),
                FilledButton(
                  onPressed: updates.download,
                  child: Text(context.tr('Try again')),
                ),
              ],
            );
          case UpdateStage.available:
            return AlertDialog(
              title: Text(
                context.tr('Version {version} is available', {
                  'version': version,
                }),
              ),
              content: SingleChildScrollView(
                child: Text(
                  r == null || r.notes.trim().isEmpty
                      ? 'A newer version of Tippani is ready.'
                      : r.notes.trim(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('Later')),
                ),
                FilledButton(
                  onPressed: updates.download,
                  child: Text(context.tr('Download')),
                ),
              ],
            );
          default:
            // Nothing on offer any more (a check since found none): the dialog has nothing to say.
            return AlertDialog(
              content: Text(context.tr('There is no update to install.')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('OK')),
                ),
              ],
            );
        }
      },
    );
  }
}
