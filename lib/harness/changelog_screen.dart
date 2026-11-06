import 'package:flutter/material.dart';

import 'changelog.dart';
import 'harness.dart';
import 'update_ui.dart';
import 'version.dart';

/// Every version's changes, newest first, from the changelog bundled into the app. It works with no
/// network, and it is the same text the "new in this version" dialog shows after an update.
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key, required this.harness});

  final Harness harness;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What\'s new')),
      body: FutureBuilder<List<ChangelogEntry>>(
        future: harness.changelog(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snap.data!;
          if (entries.isEmpty) {
            return const Center(
              child: Text('No changelog is bundled with this build.'),
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
            ],
          );
        },
      ),
    );
  }
}
