import 'package:flutter/material.dart';

import '../api/offline_cache.dart';
import '../l10n/l10n.dart';
import '../theme/tabler.dart';

/// Hands the phone's kept answers to every screen below it, so the broken-link mark can say whether the phone is
/// showing a copy without any screen being given the controller (ADR-0032).
class OfflineScope extends InheritedWidget {
  const OfflineScope({super.key, required this.offline, required super.child});

  final OfflineCache offline;

  static OfflineCache? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OfflineScope>()?.offline;

  @override
  bool updateShouldNotify(OfflineScope old) => offline != old.offline;
}

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The words for the state of the link, or null while the server is answering: the phone's copy and its date, and
/// whether the server could not be reached or turned the refresh down (ADR-0033).
String? serverLinkWords(BuildContext context, OfflineCache cache) {
  final from = cache.servedFrom.value;
  final refused = cache.refusal.value;
  if (from == null) return null;
  return refused == null
      ? context.tr('app.offline.from_the_phone', {'date': _date(from)})
      : refused.isEmpty
      ? context.tr('app.offline.refused', {'date': _date(from)})
      : context.tr('app.offline.refused_with', {
          'date': _date(from),
          'reason': refused,
        });
}

/// What the mark is called, by the state of the link: the server could not be reached, or it answered and turned the
/// refresh down (ADR-0033). Read aloud, and the icon's tooltip.
String serverLinkLabel(BuildContext context, OfflineCache cache) => context.tr(
  cache.refusal.value == null
      ? 'app.offline.not_reachable'
      : 'app.offline.refused_label',
);

/// The mark that the link to the server is broken while what the phone shows is its own copy. It is one thing for
/// the whole connection, so it is drawn on the Server tab and in every [ShellAppBar] (a screen opened over the tabs,
/// and the library's own bars, selection included) (ADR-0033). Draws nothing while the server is answering.
class ServerLinkIcon extends StatelessWidget {
  const ServerLinkIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final cache = OfflineScope.of(context);
    if (cache == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([cache.servedFrom, cache.refusal]),
      builder: (context, _) {
        if (cache.servedFrom.value == null) return const SizedBox.shrink();
        final label = serverLinkLabel(context, cache);
        return IconButton(
          tooltip: label,
          icon: Icon(Ti.unlink, color: Theme.of(context).colorScheme.error),
          onPressed: () => showServerLinkNote(context, cache),
        );
      },
    );
  }
}

/// [child] (the Server tab's glyph) with the broken-link mark on its corner while the link is broken.
class ServerLinkBadge extends StatelessWidget {
  const ServerLinkBadge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cache = OfflineScope.of(context);
    if (cache == null) return child;
    return ListenableBuilder(
      listenable: Listenable.merge([cache.servedFrom, cache.refusal]),
      builder: (context, _) {
        if (cache.servedFrom.value == null) return child;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            PositionedDirectional(
              end: -6,
              top: -4,
              child: Semantics(
                container: true,
                label: serverLinkLabel(context, cache),
                child: ExcludeSemantics(
                  child: Icon(
                    Ti.unlink,
                    size: 14,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Says what the mark means, in the old note's words, as a snack bar.
void showServerLinkNote(BuildContext context, OfflineCache cache) {
  final words = serverLinkWords(context, cache);
  if (words == null) return;
  final messenger = ScaffoldMessenger.of(context);
  // a second press while the note is up (or waiting its turn) says nothing more, so five presses are not twenty
  // seconds of the same sentence; a message that is not ours (an Undo, say) is never touched: the note queues behind it
  if (_noteUp[messenger] == true) return;
  _noteUp[messenger] = true;
  messenger
      .showSnackBar(SnackBar(content: Text(words)))
      .closed
      .whenComplete(() => _noteUp[messenger] = false);
}

/// Whether a press of the mark has a note up (or queued) on this messenger.
final _noteUp = Expando<bool>('server link note');

/// Shows the toast once for each time the app is brought to the front: the first time the link is found broken
/// while the app is awake, and not again until the phone has gone to the background and come back. It sits above
/// the navigator but BELOW the language scope, so its words are in the reader's language, and one toast serves every
/// screen however many of them fall back to their copy. No timer: it listens to the same notifiers the mark does
/// and to the app's lifecycle.
class ServerLinkToast extends StatefulWidget {
  const ServerLinkToast({
    super.key,
    required this.offline,
    required this.messenger,
    required this.child,
  });

  final OfflineCache offline;
  final GlobalKey<ScaffoldMessengerState> messenger;
  final Widget child;

  @override
  State<ServerLinkToast> createState() => _ServerLinkToastState();
}

class _ServerLinkToastState extends State<ServerLinkToast>
    with WidgetsBindingObserver {
  var _toasted = false;
  var _wentAway = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.offline.servedFrom.addListener(_changed);
    // a copy already on screen when this mounts counts as the first sight of it
    if (widget.offline.servedFrom.value != null) _changed();
  }

  @override
  void dispose() {
    widget.offline.servedFrom.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _wentAway = true;
    if (state == AppLifecycleState.resumed && _wentAway) {
      _wentAway = false;
      _toasted = false;
      // still broken on coming back: say so again
      if (widget.offline.servedFrom.value != null) _changed();
    }
  }

  void _changed() {
    if (_toasted || widget.offline.servedFrom.value == null) return;
    _toasted = true;
    // a notifier may change in the middle of a build; the snack bar waits for the frame
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = widget.messenger.currentState;
      if (state == null || !mounted) return;
      // queued behind a message already showing (an Undo), never over it. Its words are worked out when it is drawn,
      // from the bar's own context (below the language scope, so in the reader's language), so they are true of
      // the link as it is then.
      state.showSnackBar(
        SnackBar(
          content: Builder(
            builder: (context) {
              final words = serverLinkWords(context, widget.offline);
              if (words == null) {
                // The link was whole again by the time this came up (it waited behind an Undo, say, which stays until
                // it is dismissed). The framework cannot withdraw a snack bar that is still queued, so it is taken
                // off the moment it is drawn and says nothing.
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => widget.messenger.currentState?.removeCurrentSnackBar(),
                );
                return const SizedBox.shrink();
              }
              return Text(words);
            },
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
