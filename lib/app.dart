import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'harness/harness.dart';
import 'harness/update_ui.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';

/// Tippani's own red, used as the seed where the phone gives no wallpaper colours (before Android 12,
/// and on devices that opt out). The web app's accent is the same colour.
const Color tippaniSeed = Color(0xFFB4482D);

ThemeData _theme(ColorScheme scheme) =>
    ThemeData(colorScheme: scheme, useMaterial3: true);

class TippaniApp extends StatelessWidget {
  const TippaniApp({
    super.key,
    required this.controller,
    required this.harness,
  });

  final AppController controller;
  final Harness harness;

  @override
  Widget build(BuildContext context) {
    // THE PHONE'S OWN COLOURS WHERE IT HAS THEM (Material You), and Tippani's red where it does not.
    // The light and dark schemes come as a pair so the app follows the system setting.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final light =
            lightDynamic ?? ColorScheme.fromSeed(seedColor: tippaniSeed);
        final dark =
            darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: tippaniSeed,
              brightness: Brightness.dark,
            );
        return MaterialApp(
          title: 'Tippani',
          theme: _theme(light.harmonized()),
          darkTheme: _theme(dark.harmonized()),
          home: Shell(controller: controller, harness: harness),
        );
      },
    );
  }
}

/// The frame every screen lives in: a bottom bar with one destination per screen the app has. A later
/// phase adds its screen here (Capture, Quotes) rather than the app starting with empty tabs.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.controller, required this.harness});

  final AppController controller;
  final Harness harness;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller, harness: widget.harness),
    ];
    return UpdateHost(
      harness: widget.harness,
      child: Scaffold(
        body: SafeArea(child: screens[_index]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
