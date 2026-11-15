import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';
import 'tour.dart';

/// The controls the tour points at. The shell hangs each on the real widget, so a step follows the control and not a
/// guess about where it is.
class TourKeys {
  final add = GlobalKey(debugLabel: 'tour-add');
  final home = GlobalKey(debugLabel: 'tour-home');
  final boards = GlobalKey(debugLabel: 'tour-boards');
  final server = GlobalKey(debugLabel: 'tour-server');
  final settings = GlobalKey(debugLabel: 'tour-settings');
}

/// The tour: one short sentence per control a new reader needs first, in the order the bottom bar reads.
///
/// [openTabOf] brings the tab that holds a control into view. A step is left out when the control is not there for
/// this reader: [hasAnthologies] and [canSync] answer for the two that depend on the server, and a tab the reader
/// hid or the account does not have is not built, so its key finds nothing and the tour skips the step.
List<TourStep> tourSteps(
  BuildContext context, {
  required TourKeys keys,
  required void Function(GlobalKey tab) openTabOf,
  required bool hasAnthologies,
  required bool canSync,
}) => [
  TourStep(
    id: 'welcome',
    title: context.tr('app.tour.welcome_title'),
    body: context.tr('app.tour.welcome_body'),
  ),
  TourStep(
    id: 'add',
    title: context.tr('app.tour.add_title'),
    body: context.tr('app.tour.add_body'),
    target: keys.add,
    before: () => openTabOf(keys.home),
  ),
  TourStep(
    id: 'home',
    title: context.tr('app.tour.home_title'),
    body: context.tr('app.tour.home_body'),
    target: keys.home,
    before: () => openTabOf(keys.home),
  ),
  TourStep(
    id: 'boards',
    title: context.tr('app.tour.boards_title'),
    body: context.tr('app.tour.boards_body'),
    target: keys.boards,
    before: () => openTabOf(keys.boards),
  ),
  if (hasAnthologies)
    TourStep(
      id: 'anthologies',
      title: context.tr('app.tour.anthologies_title'),
      body: context.tr('app.tour.anthologies_body'),
      target: keys.boards,
      before: () => openTabOf(keys.boards),
    ),
  TourStep(
    id: 'server',
    title: context.tr('app.tour.server_title'),
    body: context.tr('app.tour.server_body'),
    target: keys.server,
    before: () => openTabOf(keys.server),
  ),
  if (canSync)
    TourStep(
      id: 'sync',
      title: context.tr('app.tour.sync_title'),
      body: context.tr('app.tour.sync_body'),
      target: keys.server,
      before: () => openTabOf(keys.server),
    ),
  TourStep(
    id: 'settings',
    title: context.tr('app.tour.settings_title'),
    body: context.tr('app.tour.settings_body'),
    target: keys.settings,
    before: () => openTabOf(keys.settings),
  ),
];
