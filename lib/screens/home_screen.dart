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
            Text(context.tr('Tippani'), style: text.headlineMedium),
            const SizedBox(height: 8),
            if (url == null) ...[
              Text(context.tr('Not connected to a server yet.')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConnectScreen(controller: controller),
                  ),
                ),
                child: Text(context.tr('Connect to your server')),
              ),
            ] else ...[
              Text(url, style: text.titleMedium),
              const SizedBox(height: 4),
              Text(serverStatusLine(controller)),
              const SizedBox(height: 16),
              if (controller.revoked) ...[
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'This phone was unpaired from the server. Pair it again to use your library.',
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              if (controller.paired)
                Text(
                  context.tr('Paired as {name}.', {
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
                  child: Text(context.tr('Pair this phone')),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: controller.checking ? null : controller.refresh,
                child: Text(context.tr('Check again')),
              ),
            ],
          ],
        );
      },
    );
  }
}
