import 'package:flutter/material.dart';

/// OryvexVPN design tokens.
///
/// One colour theme, two appearances. Ink: a near-black canvas with a faint blue cast, tiles
/// lifted one step with a hairline edge. Paper: a cool grey canvas with white tiles and soft
/// shadows. Both share one electric blue (#0A6CFF) for every action and every "on"; text that
/// is blue uses [link], which is lifted on ink so it stays readable. Inter for text, Inter
/// Display for headlines, JetBrains Mono for addresses and logs, all bundled.
///
/// The surface colours are switched as a group by [setDarkMode]. Widgets read them while they
/// build, so the app rebuilds every element when the appearance changes (see app.dart): no
/// widget, const or not, can keep a colour from the other appearance.
class Ox {
  Ox._();

  static const black = Color(0xFF000000);
  static bool darkMode = true;

  /// Bumped on every appearance change, for painters that cache what they drew.
  static int palette = 0;

  // Surfaces
  static Color canvas = const Color(0xFF06080C);
  static Color nav = const Color(0xE60A0D13);
  static Color tile = const Color(0xFF0F131A);
  static Color tileHi = const Color(0xFF1C232E);
  static Color tileTop = const Color(0xFF283141);
  static Color field = const Color(0xFF151A23);
  static Color hairline = const Color(0xFF2A3240);
  static Color hairlineSoft = const Color(0xFF1B212B);

  /// A wash for hover, pressed and "selected" fills that works on any surface.
  static Color overlay = const Color(0x0FFFFFFF);

  // Blue: the one accent. Unchanged across appearances.
  static const blue = Color(0xFF0A6CFF);
  static const blueCta = Color(0xFF0A6CFF);
  static const blueCtaHi = Color(0xFF2A80FF); // its hover
  static const blueSoft = Color(0xFF4C9BFF);
  static const blueDeep = Color(0xFF0046D5);
  static const blueIce = Color(0xFF8CC2FF);

  /// Blue for text and small glyphs: lifted on ink, the full blue on paper.
  static Color link = const Color(0xFF5AA5FF);

  /// A blue-tinted fill for selected tiles and "on" capsules.
  static Color blueWash = const Color(0x290A6CFF);

  // Type
  static Color text = const Color(0xFFF4F6FA);
  static Color secondary = const Color(0xFFAEB7C6);
  static Color tertiary = const Color(0xFF8590A2);

  // States
  static const danger = Color(0xFFE3342F);
  static const success = Color(0xFF34C759);
  static Color warn = const Color(0xFFFFB454);

  static List<BoxShadow> tileShadow = const <BoxShadow>[];

  // Fonts bundled by the oryvex_shared package (fonts/, SIL OFL 1.1). A font a package bundles
  // is only found under "packages/<package>/<family>".
  static const sans = 'packages/oryvex_shared/Inter';
  static const display = 'packages/oryvex_shared/InterDisplay';
  static const mono = 'packages/oryvex_shared/JetBrainsMono';
  static const fallback = <String>['Segoe UI Variable Text', 'Segoe UI', 'Roboto', 'Noto Sans', 'Arial'];
  static const monoFallback = <String>['Cascadia Mono', 'Consolas', 'Roboto Mono', 'Noto Sans Mono', 'monospace'];

  // Short names used across the widgets.
  static Color get card => tile;
  static Color get cardHi => tileHi;
  static Color get line => hairline;
  static Color get muted => secondary;
  static Color get faint => tertiary;
  static Color get surface => tile;

  static void setDarkMode(bool dark) {
    if (dark != darkMode) palette++;
    darkMode = dark;
    canvas = dark ? const Color(0xFF06080C) : const Color(0xFFF2F3F7);
    nav = dark ? const Color(0xE60A0D13) : const Color(0xE6FBFBFD);
    tile = dark ? const Color(0xFF0F131A) : const Color(0xFFFFFFFF);
    tileHi = dark ? const Color(0xFF1C232E) : const Color(0xFFE6E8EE);
    tileTop = dark ? const Color(0xFF283141) : const Color(0xFFFFFFFF);
    field = dark ? const Color(0xFF151A23) : const Color(0xFFEEF0F4);
    hairline = dark ? const Color(0xFF2A3240) : const Color(0xFFD2D5DC);
    hairlineSoft = dark ? const Color(0xFF1B212B) : const Color(0xFFE3E5EA);
    overlay = dark ? const Color(0x0FFFFFFF) : const Color(0x0D000000);
    link = dark ? const Color(0xFF5AA5FF) : const Color(0xFF0A6CFF);
    blueWash = dark ? const Color(0x290A6CFF) : const Color(0x1A0A6CFF);
    text = dark ? const Color(0xFFF4F6FA) : const Color(0xFF111318);
    secondary = dark ? const Color(0xFFAEB7C6) : const Color(0xFF555B69);
    tertiary = dark ? const Color(0xFF8590A2) : const Color(0xFF626B7A);
    warn = dark ? const Color(0xFFFFB454) : const Color(0xFFB45309);
    tileShadow = dark
        ? const <BoxShadow>[]
        : const <BoxShadow>[
            BoxShadow(color: Color(0x12101828), blurRadius: 24, offset: Offset(0, 8)),
            BoxShadow(color: Color(0x0A101828), blurRadius: 3, offset: Offset(0, 1)),
          ];
  }

  // Geometry
  static const radiusTile = 28.0; // apple.com tiles
  static const radiusGroup = 18.0;
  static const radiusField = 12.0;
  static const contentMax = 980.0; // apple.com's content width
  static const navHeight = 52.0;
  static const tabBarHeight = 64.0;

  // Motion. Apple's curves: a quick start that settles slowly, never a bounce on text.
  static const fast = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 380);
  static const slow = Duration(milliseconds: 650);
  static const page = Duration(milliseconds: 460);
  static const ease = Cubic(0.25, 0.1, 0.25, 1.0); // apple.com's default ease
  static const easeOut = Cubic(0.16, 1.0, 0.3, 1.0); // expo-out: arrivals
  static const easeInOut = Cubic(0.65, 0.0, 0.35, 1.0); // state morphs
  static const easeIn = Cubic(0.4, 0.0, 1.0, 1.0); // departures

  /// Headline type: Inter Display, tight tracking, like apple.com's product headlines.
  static TextStyle headline(double size, {Color? color, FontWeight weight = FontWeight.w700}) => TextStyle(
        fontFamily: display,
        fontFamilyFallback: fallback,
        fontSize: size,
        height: 1.08,
        fontWeight: weight,
        letterSpacing: -0.022 * size,
        color: color ?? text,
      );

  static TextStyle body(double size, {Color? color, FontWeight weight = FontWeight.w400, double height = 1.42}) =>
      TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallback,
        fontSize: size,
        height: height,
        fontWeight: weight,
        letterSpacing: size >= 17 ? -0.022 * size * 0.5 : -0.003 * size,
        color: color ?? text,
      );

  /// The small blue line above a headline ("Protected", "Activity").
  static TextStyle eyebrow({Color? color}) => TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallback,
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: color ?? link,
      );

  static TextStyle code(double size, {Color? color, FontWeight weight = FontWeight.w400, double height = 1.5}) =>
      TextStyle(
        fontFamily: mono,
        fontFamilyFallback: monoFallback,
        fontSize: size,
        height: height,
        fontWeight: weight,
        color: color ?? text,
      );
}

/// Breakpoints, by the width the page actually gets.
enum OxSize { compact, medium, expanded }

extension OxSizeOf on BuildContext {
  OxSize get oxSize {
    final w = MediaQuery.sizeOf(this).width;
    if (w >= 1024) return OxSize.expanded;
    if (w >= 640) return OxSize.medium;
    return OxSize.compact;
  }

  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}

/// Route transition for anything pushed on top of the tabs (licenses, sheets): the new page
/// rises a little and comes into focus, the old one sinks back and dims, like apple.com's
/// overlays. Same on every platform, so desktop and Android feel like one app.
class OxPageTransitionsBuilder extends PageTransitionsBuilder {
  const OxPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (context.reduceMotion) return child;
    final enter = CurvedAnimation(parent: animation, curve: Ox.easeOut, reverseCurve: Ox.easeIn);
    final behind = CurvedAnimation(parent: secondaryAnimation, curve: Ox.easeOut, reverseCurve: Ox.easeIn);
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.55).animate(behind),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 0.96).animate(behind),
        child: FadeTransition(
          opacity: enter,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(enter),
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.02, end: 1).animate(enter),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData buildOxTheme({required bool dark}) {
  Ox.setDarkMode(dark);
  final scheme = dark ? ColorScheme.dark(
    primary: Ox.blue,
    onPrimary: Colors.white,
    primaryContainer: Ox.blueCta,
    onPrimaryContainer: Colors.white,
    secondary: Ox.blueSoft,
    onSecondary: Colors.white,
    surface: Ox.canvas,
    onSurface: Ox.text,
    surfaceContainerHighest: Ox.tileHi,
    outline: Ox.hairline,
    error: Ox.danger,
    onError: Colors.white,
  ) : ColorScheme.light(
    primary: Ox.blue,
    onPrimary: Colors.white,
    primaryContainer: Ox.blueCta,
    onPrimaryContainer: Colors.white,
    secondary: Ox.blueSoft,
    onSecondary: Colors.white,
    surface: Ox.canvas,
    onSurface: Ox.text,
    surfaceContainerHighest: Ox.tileHi,
    outline: Ox.hairline,
    error: Ox.danger,
    onError: Colors.white,
  );

  const transitions = PageTransitionsTheme(builders: {
    TargetPlatform.android: OxPageTransitionsBuilder(),
    TargetPlatform.windows: OxPageTransitionsBuilder(),
    TargetPlatform.linux: OxPageTransitionsBuilder(),
    TargetPlatform.macOS: OxPageTransitionsBuilder(),
    TargetPlatform.iOS: OxPageTransitionsBuilder(),
  });

  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    fontFamily: Ox.sans,
    fontFamilyFallback: Ox.fallback,
    scaffoldBackgroundColor: Ox.canvas,
    canvasColor: Ox.canvas,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    hoverColor: Ox.overlay,
    focusColor: Ox.blue.withValues(alpha: 0.22),
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: transitions,
  );

  return base.copyWith(
    brightness: dark ? Brightness.dark : Brightness.light,
    textTheme: base.textTheme.apply(
      bodyColor: Ox.text,
      displayColor: Ox.text,
      fontFamily: Ox.sans,
    ),
    dividerTheme: DividerThemeData(color: Ox.hairlineSoft, thickness: 0.6, space: 0.6),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? Ox.tertiary : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return Ox.tileHi;
        return s.contains(WidgetState.selected)
            ? Ox.success
            : (dark ? const Color(0xFF3A4352) : const Color(0xFFD9DCE3));
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbIcon: const WidgetStatePropertyAll(null),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Ox.field,
      isDense: true,
      labelStyle: Ox.body(15, color: Ox.secondary),
      floatingLabelStyle: Ox.body(14, color: Ox.link),
      hintStyle: Ox.body(15, color: Ox.tertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ox.radiusField),
        borderSide: BorderSide(color: Ox.hairlineSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ox.radiusField),
        borderSide: BorderSide(color: Ox.hairlineSoft),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(Ox.radiusField)),
        borderSide: BorderSide(color: Ox.blue, width: 1.4),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(Ox.radiusField)),
        borderSide: BorderSide(color: Ox.danger),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Ox.blue,
      selectionColor: Ox.blue.withValues(alpha: 0.35),
      selectionHandleColor: Ox.blue,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(dark ? Colors.white.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.22)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Ox.tile,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Ox.hairline),
      ),
      textStyle: Ox.body(14, color: Ox.text),
      waitDuration: const Duration(milliseconds: 500),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Ox.tile,
      contentTextStyle: Ox.body(15),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Ox.hairline),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Ox.tile,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Ox.hairline),
      ),
      textStyle: Ox.body(15),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Ox.canvas,
      foregroundColor: Ox.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: Ox.headline(22, weight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: Ox.tile,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Ox.radiusTile))),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: Ox.blue, linearTrackColor: Ox.tileHi),
    iconTheme: IconThemeData(color: Ox.text),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Ox.tile,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: Ox.tile,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Ox.radiusTile))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Ox.tile,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Ox.blueCta,
        foregroundColor: Colors.white,
        textStyle: Ox.body(15, weight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Ox.link, textStyle: Ox.body(15, weight: FontWeight.w600)),
    ),
  );
}
