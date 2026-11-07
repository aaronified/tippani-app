import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'harness/harness.dart';
import 'library/cover_cache.dart';
import 'tools/quote_context.dart';
import 'tools/work_details_source.dart';
import 'harness/update_ui.dart';
import 'screens/anthologies_screen.dart';
import 'screens/nav_icons.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'boards/board_service.dart';
import 'people/people_directory.dart';
import 'tags/tag_service.dart';
import 'share/share_people.dart';
import 'theme/app_theme.dart';

/// Tippani's own red, used as the seed where the phone gives no wallpaper colours (before Android 12,
/// and on devices that opt out). The web app's accent is the same colour.
const Color tippaniSeed = Color(0xFFB4482D);

ThemeData _theme(ColorScheme scheme) => buildTheme(scheme);

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
          builder: (context, child) => CoverScope(
            source: harness.covers,
            child: DetailsScope(
              source: harness.details,
              child: ContextScope(
                source: harness.contexts,
                child: PeopleScope(
                  source: harness.people,
                  child: PeopleDirectoryScope(
                    directory: harness.directory,
                    child: BoardScope(
                      service: harness.boards,
                      child: TagServiceScope(
                        service: harness.tags,
                        child: child!,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
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
    // The token is read first (a screen builds its client from it), then the server is asked.
    widget.controller.load().then((_) => widget.controller.refresh());
    // Keeping the library in step with the server starts with the app (and stays off in tests).
    if (widget.harness.runAutoSync) {
      widget.harness.auto?.start(widget.harness.library?.changes);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The library comes first: the app works with no server, so what it opens on is the reader's own books.
    // The sections are the web app's own (Library, Catalogue, Quotes, Anthologies), each with its icon. Anthologies
    // live on the server, so that one is there only where the app has the means to reach them. A harness with no
    // library (a test of the server screens alone) has none of these.
    final library = widget.harness.library;
    final tabs = <({Widget screen, NavigationDestination destination})>[
      if (library != null)
        for (final (nav, part) in [
          (NavSection.library, LibrarySection.books),
          (NavSection.catalogue, LibrarySection.catalogue),
          (NavSection.quotes, LibrarySection.quotes),
        ])
          (
            screen: LibraryScreen(
              key: ValueKey(part),
              store: library,
              picker: widget.harness.picker,
              anthologies: widget.harness.anthologies,
              lookup: widget.harness.lookup,
              auto: widget.harness.auto,
              section: part,
            ),
            destination: NavigationDestination(
              icon: NavSectionIcon(nav),
              label: nav.label,
            ),
          ),
      if (library != null && widget.harness.anthologies != null)
        (
          screen: AnthologiesScreen(
            service: widget.harness.anthologies!,
            picker: widget.harness.picker,
          ),
          destination: NavigationDestination(
            icon: NavSectionIcon(NavSection.anthologies),
            label: NavSection.anthologies.label,
          ),
        ),
      // Without a library (a test of the server screens alone) there is nothing else to open on, so the server
      // screen stands in; with one, the server is a section of Settings.
      if (library == null)
        (
          screen: HomeScreen(controller: widget.controller),
          destination: const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
        ),
      (
        screen: SettingsScreen(
          controller: widget.controller,
          harness: widget.harness,
        ),
        destination: const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ),
    ];
    return UpdateHost(
      harness: widget.harness,
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _index,
            children: [for (final t in tabs) t.screen],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          // A word like "Anthologies" is cut off when the bar is crowded (many tabs, a narrow phone, large text):
          // then only the open tab keeps its label, and the others are the icon alone.
          labelBehavior:
              MediaQuery.sizeOf(context).width /
                      tabs.length /
                      MediaQuery.textScalerOf(context).scale(1) <
                  66
              ? NavigationDestinationLabelBehavior.onlyShowSelected
              : NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [for (final t in tabs) t.destination],
        ),
      ),
    );
  }
}
