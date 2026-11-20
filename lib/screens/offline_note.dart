import 'package:flutter/material.dart';

import '../api/offline_cache.dart';
import '../l10n/l10n.dart';
import '../theme/material_surface.dart';

/// Hands the phone's kept answers to every screen below it, so a screen that shows what the server holds can say
/// when it is showing the phone's copy without being given the controller (ADR-0032).
class OfflineScope extends InheritedWidget {
  const OfflineScope({super.key, required this.offline, required super.child});

  final OfflineCache offline;

  static OfflineCache? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OfflineScope>()?.offline;

  @override
  bool updateShouldNotify(OfflineScope old) => offline != old.offline;
}

/// Says when what a screen shows is the phone's copy of what the server last said, because the server could not
/// be reached (ADR-0022). Draws nothing while the server is answering.
class OfflineNote extends StatelessWidget {
  const OfflineNote({super.key, this.offline});

  /// Where the answers are kept; null reads it from the [OfflineScope] above (every screen but the two that were
  /// given the controller before the scope existed).
  final OfflineCache? offline;

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cache = offline ?? OfflineScope.of(context);
    if (cache == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([cache.servedFrom, cache.refusal]),
      builder: (context, _) {
        final from = cache.servedFrom.value;
        final refused = cache.refusal.value;
        if (from == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SurfaceCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                refused == null
                    ? context.tr('app.offline.from_the_phone', {
                        'date': _date(from),
                      })
                    : refused.isEmpty
                    ? context.tr('app.offline.refused', {'date': _date(from)})
                    : context.tr('app.offline.refused_with', {
                        'date': _date(from),
                        'reason': refused,
                      }),
              ),
            ),
          ),
        );
      },
    );
  }
}
