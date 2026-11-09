import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'account/account_service.dart';
import 'account/preferences.dart';
import 'app_controller.dart';
import 'l10n/l10n.dart';
import 'harness/harness.dart';
import 'library/cover_cache.dart';
import 'tools/quote_context.dart';
import 'tools/work_details_source.dart';
import 'harness/update_ui.dart';
import 'screens/add_quote_sheet.dart';
import 'screens/boards_tab.dart';
import 'screens/dashboard_screen.dart';
import 'screens/home_screen.dart';
import 'screens/checks_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'boards/board_service.dart';
import 'people/people_console.dart';
import 'people/people_directory.dart';
import 'tools/cover_search.dart';
import 'people/people_service.dart';
import 'search/search_service.dart';
import 'tags/tag_service.dart';
import 'share/share_people.dart';
import 'theme/app_theme.dart';
import 'theme/tabler.dart';

/// Tippani's own red, used as the seed where the phone gives no wallpaper colours (before Android 12,
/// and on devices that opt out). The web app's accent is the same colour.
export 'theme/theme_choice.dart' show tippaniSeed;

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
      builder: (lightDynamic, darkDynamic) => ListenableBuilder(
        listenable: harness.themeChoice,
        builder: (context, _) {
          final (light, dark) = harness.themeChoice.schemes(
            lightDynamic,
            darkDynamic,
          );
          return MaterialApp(
            title: 'Tippani',
            theme: _theme(light),
            darkTheme: _theme(dark),
            builder: (context, child) => PrefsScope(
              source: harness.prefs,
              child: L10nScope(
                l10n: harness.l10n,
                child: Builder(
                  builder: (context) {
                    // the reader's text size scales every word the app draws
                    final media = MediaQuery.of(context);
                    final factor = PrefsScope.of(context).sizeUi / 100;
                    return MediaQuery(
                      data: media.copyWith(
                        textScaler: TextScaler.linear(
                          media.textScaler.scale(1) * factor,
                        ),
                      ),
                      child: ContextRulesScope(
                        rules: harness.contextRules,
                        child: CoverScope(
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
                                    child: PeopleServiceScope(
                                      service: harness.peopleService,
                                      child: TagServiceScope(
                                        service: harness.tags,
                                        child: PeopleConsoleScope(
                                          console: harness.peopleConsole,
                                          child: ServerSearchScope(
                                            service: harness.search,
                                            child: CoverSearchScope(
                                              search: harness.coverSearch,
                                              child: child!,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            home: Shell(controller: controller, harness: harness),
          );
        },
      ),
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

  /// The tabs as last drawn: which are there depends on the sections the reader hid, so "open the Library" asks here
  /// for where it is rather than counting.
  List<({Widget screen, NavigationDestination destination})> _tabsNow =
      const [];

  /// Brings a board of the Boards tab into view, from outside it (a button on Home).
  final _boardsGoTo = ValueNotifier<BoardKind?>(null);

  void _goTo(LibrarySection part) {
    final i = _tabsNow.indexWhere((t) => t.screen is BoardsTab);
    if (i < 0) return;
    setState(() => _index = i);
    _boardsGoTo.value = switch (part) {
      LibrarySection.catalogue => BoardKind.catalogue,
      LibrarySection.quotes => BoardKind.quotes,
      _ => BoardKind.library,
    };
  }

  Future<void> _openImports(BuildContext context) async {
    final h = widget.harness;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChecksScreen(
          imports: h.imports,
          checks: h.checks,
          library: h.library,
          picker: h.importPicker,
          auto: h.auto,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // The token is read first (a screen builds its client from it), then the server is asked.
    widget.controller.load().then((_) {
      widget.controller.refresh();
      widget.harness.refreshAccountSettings();
    });
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
    // Which sections show is the reader's choice (Settings, Sections), as on the web. The server refuses to hide all
    // three of Library, Catalogue and Quotes; a phone that has never heard from it shows everything.
    final prefs = PrefsScope.of(context);
    final hideAll =
        prefs.hideLibrary && prefs.hideCatalogue && prefs.hideQuotes;
    bool shown(LibrarySection part) =>
        hideAll ||
        !switch (part) {
          LibrarySection.books => prefs.hideLibrary,
          LibrarySection.catalogue => prefs.hideCatalogue,
          LibrarySection.quotes => prefs.hideQuotes,
          LibrarySection.all => false,
        };
    final quiz = widget.harness.quiz;
    final boardKinds = [
      if (library != null && shown(LibrarySection.books)) BoardKind.library,
      if (library != null && shown(LibrarySection.catalogue))
        BoardKind.catalogue,
      if (library != null && shown(LibrarySection.quotes)) BoardKind.quotes,
      if (library != null &&
          widget.harness.anthologies != null &&
          (prefs.showAnthologies || !prefs.known))
        BoardKind.anthologies,
    ];
    final tabs = <({Widget screen, NavigationDestination destination})>[
      // Home comes first where the app has the quiz to put on it: the day's cards, the favourites, a line at random.
      if (library != null && quiz != null)
        (
          screen: Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: FloatingActionButton.extended(
              heroTag: 'add-anything',
              onPressed: () => showAddQuoteSheet(
                context,
                store: library,
                onImport: () => _openImports(context),
              ),
              icon: const Icon(Ti.plus),
              label: Text(context.tr('app.add.title')),
            ),
            body: DashboardScreen(
              store: library,
              quiz: quiz,
              controller: widget.controller,
              picker: widget.harness.picker,
              anthologies: widget.harness.anthologies,
              auto: widget.harness.auto,
              onOpenLibrary: () => _goTo(LibrarySection.books),
              onOpenCatalogue: () => _goTo(LibrarySection.catalogue),
              imports: widget.harness.imports,
              onOpenImports: () => _openImports(context),
            ),
          ),
          destination: NavigationDestination(
            icon: const Icon(Ti.home),
            selectedIcon: const Icon(Ti.homeFilled),
            label: context.tr('nav.tab.home.label'),
          ),
        ),
      if (library != null && boardKinds.isNotEmpty)
        (
          screen: BoardsTab(
            store: library,
            picker: widget.harness.picker,
            boards: boardKinds,
            goTo: _boardsGoTo,
            anthologies: widget.harness.anthologies,
            lookup: widget.harness.lookup,
            auto: widget.harness.auto,
            quiz: widget.harness.quiz,
            controller: widget.controller,
          ),
          destination: NavigationDestination(
            icon: const Icon(Ti.layoutBoard),
            label: context.tr('tour.step.boards.name'),
          ),
        ),
      // Without a library (a test of the server screens alone) there is nothing else to open on, so the server
      // screen stands in; with one, the server is a section of Settings.
      if (library == null)
        (
          screen: HomeScreen(controller: widget.controller),
          destination: NavigationDestination(
            icon: const Icon(Ti.home),
            selectedIcon: const Icon(Ti.homeFilled),
            label: context.tr('nav.tab.home.label'),
          ),
        ),
      // the server: the connection, sync, the library on the server, administration
      (
        screen: SettingsScreen(
          controller: widget.controller,
          harness: widget.harness,
          part: SettingsPart.server,
        ),
        destination: NavigationDestination(
          icon: const Icon(Ti.server),
          label: context.tr('settings.section.server.label'),
        ),
      ),
      // the app's own settings
      (
        screen: SettingsScreen(
          controller: widget.controller,
          harness: widget.harness,
        ),
        destination: NavigationDestination(
          icon: const Icon(Ti.settings),
          selectedIcon: const Icon(Ti.settingsFilled),
          label: context.tr('nav.tab.settings.label'),
        ),
      ),
    ];
    _tabsNow = tabs;
    return UpdateHost(
      harness: widget.harness,
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _index.clamp(0, tabs.length - 1),
            children: [for (final t in tabs) t.screen],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          // A word like "Anthologies" is cut off when the bar is crowded (many tabs, a narrow phone, large text):
          // then only the open tab keeps its label, and the others are the icon alone.
          labelBehavior:
              _labelsFit(context, [for (final t in tabs) t.destination.label])
              ? NavigationDestinationLabelBehavior.alwaysShow
              : NavigationDestinationLabelBehavior.onlyShowSelected,
          selectedIndex: _index.clamp(0, tabs.length - 1),
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [for (final t in tabs) t.destination],
        ),
      ),
    );
  }
}

/// Whether every tab's label fits on one line in the bar: the widest word, in the bar's own label style and the
/// phone's text size, has to fit the width of one tab. When one does not, the bar keeps only the open tab's label
/// (a label that wraps into two lines, or breaks in the middle of a word, looks broken).
bool _labelsFit(BuildContext context, List<String> labels) {
  final theme = Theme.of(context);
  final style =
      theme.navigationBarTheme.labelTextStyle?.resolve({
        WidgetState.selected,
      }) ??
      theme.textTheme.labelMedium ??
      const TextStyle(fontSize: 11);
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  final tab = MediaQuery.sizeOf(context).width / labels.length;
  var widest = 0.0;
  for (final l in labels) {
    final p = TextPainter(
      text: TextSpan(text: l, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    if (p.width > widest) widest = p.width;
    p.dispose();
  }
  // a little room each side, as the bar keeps
  return widest + 12 <= tab;
}
