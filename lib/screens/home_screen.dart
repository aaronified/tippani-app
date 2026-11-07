import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'connect_screen.dart';
import 'pair_screen.dart';
import '../l10n/l10n.dart';

/// The first screen. For now it says whether a server is set and whether it answers; the screens that
/// do things (capture, quotes) arrive in later phases and take their own destinations in the bar.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final url = controller.serverUrl;
        final text = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Tippani', style: text.headlineMedium),
            const SizedBox(height: 8),
            if (url == null) ...[
              Text(context.tr('app.home.not_connected_to_a_server_yet')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConnectScreen(controller: controller),
                  ),
                ),
                child: Text(context.tr('app.home.connect_to_your_server')),
              ),
            ] else ...[
              Text(url, style: text.titleMedium),
              const SizedBox(height: 4),
              Text(serverStatusLine(controller)),
              const SizedBox(height: 16),
              if (controller.revoked) ...[
                const SizedBox(height: 8),
                Text(
                  context.tr('app.home.this_phone_was_unpaired_from_the'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              if (controller.paired)
                Text(
                  context.tr('app.home.paired_as_name', {
                    'name': controller.username ?? '',
                  }),
                )
              else
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PairScreen(controller: controller),
                    ),
                  ),
                  child: Text(context.tr('app.home.pair_this_phone')),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: controller.checking ? null : controller.refresh,
                child: Text(context.tr('app.admin_update.check_again')),
              ),
            ],
          ],
        );
      },
    );
  }
}
