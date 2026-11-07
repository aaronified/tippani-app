import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'changelog.dart';
import 'harness.dart';
import 'update_ui.dart';
import 'version.dart';
import '../l10n/l10n.dart';

/// Opens a web address in the phone's browser; false if nothing could. A function so a test can stand in for it.
typedef OpenLink = Future<bool> Function(Uri url);

Future<bool> openInBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Every version's changes, newest first, each by a short header, from the changelog bundled into the app. It works
/// with no network, and it is the same list the "new in this version" dialog shows after an update. The full words
/// of every change are in the changelog on GitHub, one tap away at the foot.
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({
    super.key,
    required this.harness,
    this.openLink = openInBrowser,
  });

  final Harness harness;
  final OpenLink openLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('What\'s new'))),
      body: FutureBuilder<List<ChangelogEntry>>(
        future: harness.changelog(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snap.data!;
          if (entries.isEmpty) {
            return Center(
              child: Text(
                context.tr('No changelog is bundled with this build.'),
              ),
            );
          }
          return ListView(
            children: [
              for (final e in entries)
                ExpansionTile(
                  initiallyExpanded: e.version == appVersion,
                  title: Text(e.isUnreleased ? 'Unreleased' : e.version),
                  subtitle: e.date == null ? null : Text(e.date!),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [ChangelogBody(entry: e)],
                ),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text(context.tr('Full changelog on GitHub')),
                subtitle: Text(context.tr('Every change in full')),
                onTap: () async {
                  final ok = await openLink(Uri.parse(changelogUrl));
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.tr(
                            'The link could not be opened. It is at github.com/aaronified/tippani-app.',
                          ),
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
