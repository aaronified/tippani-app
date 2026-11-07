import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../account/preferences.dart';

/// The face for the words of a quote, and for the large display lines: Source Serif 4 (SIL OFL, bundled).
const String quoteFont = 'SourceSerif4';

/// The face for everything else: Inter (SIL OFL, bundled).
const String uiFont = 'Inter';

/// Tippani's look over whichever Material You colours the phone gave: shape, type, spacing and the way bars,
/// cards, inputs and dialogs sit. Colours are never chosen here, only taken from [scheme] (the owner's rule: the
/// phone's own colours, nothing else).
ThemeData buildTheme(ColorScheme scheme) {
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: uiFont,
  );
  final text = _text(base.textTheme, scheme);
  const radius = 20.0;
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
  );
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      titleTextStyle: TextStyle(
        fontFamily: uiFont,
        fontSize: 26,
        height: 1.2,
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: text.titleMedium?.copyWith(color: scheme.onSurface),
      subtitleTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium?.copyWith(
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: s.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      highlightElevation: 3,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.secondaryContainer,
      labelStyle: text.labelLarge,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: text.labelLarge,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      circularTrackColor: Colors.transparent,
      color: scheme.primary,
    ),
  );
}

TextTheme _text(TextTheme t, ColorScheme scheme) {
  TextStyle? w(TextStyle? s, FontWeight weight, [double spacing = 0]) =>
      s?.copyWith(fontWeight: weight, letterSpacing: spacing);
  return t.copyWith(
    headlineLarge: w(t.headlineLarge, FontWeight.w700, -0.8),
    headlineMedium: w(t.headlineMedium, FontWeight.w700, -0.6),
    headlineSmall: w(t.headlineSmall, FontWeight.w700, -0.4),
    titleLarge: w(t.titleLarge, FontWeight.w600, -0.2),
    titleMedium: w(t.titleMedium, FontWeight.w600, 0),
    titleSmall: w(t.titleSmall, FontWeight.w600, 0.1),
    bodyLarge: t.bodyLarge?.copyWith(height: 1.45),
    bodyMedium: t.bodyMedium?.copyWith(height: 1.4),
    labelLarge: w(t.labelLarge, FontWeight.w600, 0.1),
    labelMedium: w(t.labelMedium, FontWeight.w500, 0.2),
    labelSmall: w(t.labelSmall, FontWeight.w500, 0.3),
  );
}

/// The faces the app carries, by the token the server keeps for them.
const quoteFaces = {
  'source-serif-4': 'SourceSerif4',
  'newsreader': 'Newsreader',
  'noto-serif-bengali': 'NotoSerifBengali',
  'noto-serif-devanagari': 'NotoSerifDevanagari',
};

/// The style for a quote's words: the serif, at [size], with room between the lines. What the reader set in
/// Settings applies: the size of quotes, their line height, and the face chosen for [language].
TextStyle quoteStyle(
  BuildContext context, {
  double size = 17,
  double height = 1.5,
  Color? color,
  FontStyle? style,
  FontWeight weight = FontWeight.w400,
  String language = '',
}) {
  final prefs = PrefsScope.of(context);
  final leading = prefs.quoteLeading;
  final token = prefs.fontsByLanguage[language.trim().toLowerCase()];
  return TextStyle(
    fontFamily: quoteFaces[token] ?? quoteFont,
    fontSize: size * prefs.sizeDisplay / 100,
    height: leading > 0 ? leading / 100 : height,
    fontWeight: weight,
    fontStyle: style,
    color: color ?? Theme.of(context).colorScheme.onSurface,
    letterSpacing: -0.1,
  );
}

/// Keeps a quote's lines to the length the reader chose (45 to 80 characters), or the full width.
Widget quoteMeasure(BuildContext context, double size, Widget child) {
  final m = PrefsScope.of(context).quoteMeasure;
  if (m <= 0) return child;
  return Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: m * size * 0.52),
      child: child,
    ),
  );
}
