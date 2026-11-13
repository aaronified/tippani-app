import 'package:flutter/material.dart';

import '../api/offline_cache.dart';
import '../l10n/l10n.dart';

/// Says when what a screen shows is the phone's copy of what the server last said, because the server could not
/// be reached (ADR-0022). Draws nothing while the server is answering.
class OfflineNote extends StatelessWidget {
  const OfflineNote({super.key, required this.offline});

  final OfflineCache offline;

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: offline.servedFrom,
      builder: (context, from, _) {
        if (from == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                context.tr('app.offline.from_the_phone', {'date': _date(from)}),
              ),
            ),
          ),
        );
      },
    );
  }
}
