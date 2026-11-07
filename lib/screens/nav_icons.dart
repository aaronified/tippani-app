import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The four sections' icons, the web app's own (its navigation draws these same shapes), so the phone and the web read
/// alike. Each takes the colour and size of the icon theme it is drawn in, so the navigation bar can tint the chosen one.
enum NavSection {
  library(
    'Library',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="14.1 2.1 243.9 243.9"><path d="M231.65,194.55,198.46,36.75a16,16,0,0,0-19-12.39L132.65,34.42a16.08,16.08,0,0,0-12.3,19l33.19,157.8A16,16,0,0,0,169.16,224a16.25,16.25,0,0,0,3.38-.36l46.81-10.06A16.09,16.09,0,0,0,231.65,194.55ZM136,50.15c0-.06,0-.09,0-.09l46.8-10,3.33,15.87L139.33,66Zm10,47.38-3.35-15.9,46.82-10.06,3.34,15.9Zm70,100.41-46.8,10-3.33-15.87L212.67,182,216,197.85C216,197.91,216,197.94,216,197.94ZM104,32H56A16,16,0,0,0,40,48V208a16,16,0,0,0,16,16h48a16,16,0,0,0,16-16V48A16,16,0,0,0,104,32ZM56,48h48V64H56Zm48,160H56V192h48v16Z"/></svg>',
  ),
  catalogue(
    'Catalogue',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0.3 -3.7 263.4 263.4"><path d="M232,216H183.36A103.95,103.95,0,1,0,128,232H232a8,8,0,0,0,0-16ZM80,148a20,20,0,1,1,20-20A20,20,0,0,1,80,148Zm48,48a20,20,0,1,1,20-20A20,20,0,0,1,128,196Zm0-96a20,20,0,1,1,20-20A20,20,0,0,1,128,100Zm28,28a20,20,0,1,1,20,20A20,20,0,0,1,156,128Z"/></svg>',
  ),
  quotes(
    'Quotes',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="1.2 5.2 253.7 253.7"><path d="M116,72v88a48.05,48.05,0,0,1-48,48,8,8,0,0,1,0-16,32,32,0,0,0,32-32v-8H40a16,16,0,0,1-16-16V72A16,16,0,0,1,40,56h60A16,16,0,0,1,116,72ZM216,56H156a16,16,0,0,0-16,16v64a16,16,0,0,0,16,16h60v8a32,32,0,0,1-32,32,8,8,0,0,0,0,16,48.05,48.05,0,0,0,48-48V72A16,16,0,0,0,216,56Z"/></svg>',
  ),
  anthologies(
    'Anthologies',
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-8.5 -8.6 273.2 273.2"><path d="M220,169.09l-92,53.65L36,169.09A8,8,0,0,0,28,182.91l96,56a8,8,0,0,0,8.06,0l96-56A8,8,0,1,0,220,169.09Z"/><path d="M220,121.09l-92,53.65L36,121.09A8,8,0,0,0,28,134.91l96,56a8,8,0,0,0,8.06,0l96-56A8,8,0,1,0,220,121.09Z"/><path d="M28,86.91l96,56a8,8,0,0,0,8.06,0l96-56a8,8,0,0,0,0-13.82l-96-56a8,8,0,0,0-8.06,0l-96,56a8,8,0,0,0,0,13.82Z"/></svg>',
  );

  const NavSection(this.label, this.svg);

  final String label;
  final String svg;
}

/// A section's icon, in the colour and size of the surrounding icon theme.
class NavSectionIcon extends StatelessWidget {
  const NavSectionIcon(this.section, {super.key});

  final NavSection section;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    return SvgPicture.string(
      section.svg,
      width: size,
      height: size,
      semanticsLabel: section.label,
      colorFilter: ColorFilter.mode(
        theme.color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        BlendMode.srcIn,
      ),
    );
  }
}
