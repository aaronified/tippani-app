import 'package:flutter/material.dart';

import '../theme/tabler.dart';

/// The four sections' icons, from Tabler Icons like every other icon in the app. Each takes the colour and size of the
/// icon theme it is drawn in, so the navigation bar can tint the chosen one.
enum NavSection {
  library('Library', Ti.books),
  catalogue('Catalogue', Ti.movie),
  quotes('Quotes', Ti.quote),
  anthologies('Anthologies', Ti.stack2);

  const NavSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// A section's icon, in the colour and size of the surrounding icon theme.
class NavSectionIcon extends StatelessWidget {
  const NavSectionIcon(this.section, {super.key});

  final NavSection section;

  @override
  Widget build(BuildContext context) =>
      Icon(section.icon, semanticLabel: section.label);
}
