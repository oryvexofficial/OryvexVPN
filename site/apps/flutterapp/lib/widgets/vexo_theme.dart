import 'package:flutter/material.dart';

/// VexoStream v25 "night-screening room" tokens, converted from the site's
/// dark-theme OKLCH values (site/src/styles/app.css).
class Vx {
  static const bg = Color(0xFF04060A);
  static const panel = Color(0xFF0B0D13);
  static const well = Color(0xFF12151C);
  static const well2 = Color(0xFF1C1F27);
  static const line = Color(0xFF20232A);
  static const text = Color(0xFFF4F5F8);
  static const text2 = Color(0xFFABAEB6);
  static const text3 = Color(0xFF777A83);
  static const blue = Color(0xFF378EFF);
  static const blueHover = Color(0xFF4CA1FF);
  static const link = Color(0xFF60B0FF);
  static const green = Color(0xFF51C672);
  static const amber = Color(0xFFF5AE39);
  static const red = Color(0xFFF85452);
  static const ring = Color(0x12FFFFFF);
  static const ringStrong = Color(0x24FFFFFF);
  static const glass = Color(0x9E05070C);

  static const radiusSm = 8.0;
  static const radiusMd = 10.0;
  static const radiusLg = 14.0;
  static const radiusXl = 18.0;
  static const radius2xl = 24.0;

  static const ease = Cubic(.16, 1, .3, 1);
  static const spring = Cubic(.32, .72, 0, 1);
  static const pop = Cubic(.34, 1.45, .64, 1);

  /// Bundled fonts (assets/fonts). Geist first, then the Persian font the site
  /// uses (Vazirmatn) and Noto Sans Arabic, so Persian text renders like the site.
  static const sansFamily = 'Geist';
  static const monoFamily = 'Geist Mono';
  static const sansFallback = <String>['Vazirmatn', 'NotoSansArabic', 'Segoe UI', 'Arial'];
  static const monoFallback = <String>['Vazirmatn', 'NotoSansArabic', 'Consolas'];

  static TextStyle sans({double size = 16, FontWeight weight = FontWeight.w400, Color color = text, double? height, double? spacing}) =>
      TextStyle(fontFamily: sansFamily, fontFamilyFallback: sansFallback, fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

  static TextStyle mono({double size = 12, FontWeight weight = FontWeight.w500, Color color = text3, double? spacing}) =>
      TextStyle(fontFamily: monoFamily, fontFamilyFallback: monoFallback, fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing);

  static BoxDecoration surface({Color color = panel, double radius = radiusXl, bool ring = true}) => BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: ring ? Border.all(color: line) : null,
      );
}

// Legacy names used by a few screens.
const vexoBackground = Vx.bg;
const vexoSurface = Vx.panel;
const vexoCard = Vx.well;
const vexoPurple = Vx.blue;
const vexoPink = Vx.red;

TextTheme _textTheme() {
  final base = ThemeData(brightness: Brightness.dark).textTheme.apply(bodyColor: Vx.text, displayColor: Vx.text);
  final themed = base.apply(fontFamily: Vx.sansFamily, fontFamilyFallback: Vx.sansFallback);
  return themed.copyWith(
    displayLarge: themed.displayLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -3.5, height: .95),
    displayMedium: themed.displayMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -2.4, height: .98),
    headlineLarge: themed.headlineLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -1.2, height: 1.05),
    headlineMedium: themed.headlineMedium?.copyWith(fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: -.9, height: 1.1),
    headlineSmall: themed.headlineSmall?.copyWith(fontSize: 23, fontWeight: FontWeight.w600, letterSpacing: -.55),
    titleLarge: themed.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -.3),
    titleMedium: themed.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -.15),
    bodyLarge: themed.bodyLarge?.copyWith(fontSize: 16, height: 1.55, color: Vx.text),
    bodyMedium: themed.bodyMedium?.copyWith(fontSize: 14, height: 1.5, color: Vx.text2),
    bodySmall: themed.bodySmall?.copyWith(fontSize: 13, color: Vx.text3),
    labelLarge: themed.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
  );
}

ThemeData buildVexoTheme() {
  final text = _textTheme();
  const scheme = ColorScheme.dark(
    primary: Vx.blue,
    onPrimary: Colors.white,
    secondary: Vx.blue,
    onSecondary: Colors.white,
    surface: Vx.panel,
    onSurface: Vx.text,
    surfaceContainerLowest: Vx.bg,
    surfaceContainerLow: Vx.panel,
    surfaceContainer: Vx.well,
    surfaceContainerHigh: Vx.well2,
    surfaceContainerHighest: Vx.well2,
    onSurfaceVariant: Vx.text2,
    outline: Vx.line,
    outlineVariant: Vx.line,
    error: Vx.red,
    onError: Colors.white,
  );
  final pill = WidgetStatePropertyAll<OutlinedBorder>(const StadiumBorder());
  final buttonText = WidgetStatePropertyAll(text.labelLarge?.copyWith(fontWeight: FontWeight.w500));
  final focusBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: Vx.blue, width: 1.5));
  final idleBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: Vx.line));

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: Vx.sansFamily,
    fontFamilyFallback: Vx.sansFallback,
    colorScheme: scheme,
    textTheme: text,
    primaryTextTheme: text,
    scaffoldBackgroundColor: Vx.bg,
    canvasColor: Vx.bg,
    cardColor: Vx.panel,
    dividerColor: Vx.line,
    splashFactory: InkSparkle.splashFactory,
    hoverColor: Vx.well,
    highlightColor: Colors.transparent,
    visualDensity: VisualDensity.standard,
    dividerTheme: const DividerThemeData(color: Vx.line, thickness: 1, space: 1),
    iconTheme: const IconThemeData(color: Vx.text2, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: Vx.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Vx.text,
      titleTextStyle: text.titleMedium,
      shape: const Border(bottom: BorderSide(color: Vx.line)),
    ),
    cardTheme: CardThemeData(
      color: Vx.panel,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Vx.radiusXl), side: const BorderSide(color: Vx.line)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: Vx.text2,
      textColor: Vx.text,
      titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w500, fontSize: 15),
      subtitleTextStyle: text.bodySmall,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Vx.radiusLg)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Vx.panel,
      hintStyle: text.bodyLarge?.copyWith(color: Vx.text3),
      labelStyle: text.bodyMedium?.copyWith(color: Vx.text3),
      floatingLabelStyle: text.bodyMedium?.copyWith(color: Vx.blue),
      prefixIconColor: Vx.text3,
      suffixIconColor: Vx.text2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: idleBorder,
      enabledBorder: idleBorder,
      focusedBorder: focusBorder,
      errorBorder: idleBorder.copyWith(borderSide: const BorderSide(color: Vx.red)),
      focusedErrorBorder: focusBorder.copyWith(borderSide: const BorderSide(color: Vx.red, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: pill,
        textStyle: buttonText,
        minimumSize: const WidgetStatePropertyAll(Size(64, 42)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
        elevation: const WidgetStatePropertyAll(0),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? Vx.text3 : Colors.white),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return Vx.well2;
          if (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)) return Vx.blueHover;
          return Vx.blue;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: pill,
        textStyle: buttonText,
        minimumSize: const WidgetStatePropertyAll(Size(64, 42)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? Vx.text3 : Vx.text),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? Vx.well : Vx.panel),
        side: WidgetStateProperty.resolveWith((s) => BorderSide(color: s.contains(WidgetState.hovered) ? Vx.ringStrong : Vx.line)),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: pill,
        textStyle: buttonText,
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? Vx.blueHover : Vx.link),
        overlayColor: const WidgetStatePropertyAll(Color(0x14378EFF)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? Vx.text : Vx.text2),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? Vx.well : Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Vx.panel,
      selectedColor: Vx.blue,
      disabledColor: Vx.well,
      side: const BorderSide(color: Vx.line),
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: text.labelLarge?.copyWith(color: Vx.text2),
      secondaryLabelStyle: text.labelLarge?.copyWith(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: pill,
        textStyle: buttonText,
        side: const WidgetStatePropertyAll(BorderSide(color: Vx.line)),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Vx.text : Vx.text2),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Vx.well2 : Vx.panel),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Vx.blue : Colors.transparent),
      side: const BorderSide(color: Vx.text3, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Vx.blue, linearTrackColor: Vx.well2, circularTrackColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Vx.text,
      contentTextStyle: text.bodyMedium?.copyWith(color: Vx.bg, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: const StadiumBorder(),
      width: 360,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: Vx.well2, borderRadius: BorderRadius.circular(Vx.radiusSm), border: Border.all(color: Vx.line)),
      textStyle: text.bodySmall?.copyWith(color: Vx.text),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Vx.well),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(Vx.radiusLg), side: const BorderSide(color: Vx.line))),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: const WidgetStatePropertyAll(Vx.well2),
      radius: const Radius.circular(999),
      thickness: const WidgetStatePropertyAll(8),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

/// Site ".section-head": title + optional subtitle, tools on the right.
class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, this.subtitle, this.trailing, this.kicker, this.large = true});
  final String title;
  final String? subtitle;
  final String? kicker;
  final Widget? trailing;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (kicker != null) ...[
              Text(kicker!.toUpperCase(), style: Vx.mono(size: 12, spacing: 1.4)),
              const SizedBox(height: 10),
            ],
            Text(title, style: large ? t.headlineMedium : t.headlineSmall),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: t.bodyMedium),
            ],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 16), trailing!],
      ]),
    );
  }
}

/// Pill with a status dot (site hero badge, "On air" tags).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.color = Vx.green, this.dense = false});
  final String label;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14, vertical: dense ? 5 : 7),
        decoration: BoxDecoration(color: Vx.panel, borderRadius: BorderRadius.circular(999), border: Border.all(color: Vx.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: .28), spreadRadius: 3)]),
          ),
          SizedBox(width: dense ? 7 : 9),
          Text(label, style: Vx.sans(size: 13, weight: FontWeight.w500, color: Vx.text2)),
        ]),
      );
}

/// Pill segmented control like the site's ".segmented" provider/filter bar.
class PillTabs<T> extends StatelessWidget {
  const PillTabs({super.key, required this.items, required this.value, required this.onChanged, this.iconFor});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final Widget? Function(T value)? iconFor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Vx.panel, borderRadius: BorderRadius.circular(999), border: Border.all(color: Vx.line)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final item in items)
              _PillTab(
                label: item.$2,
                icon: iconFor?.call(item.$1),
                selected: item.$1 == value,
                onTap: () => onChanged(item.$1),
              ),
          ]),
        ),
      );
}

class _PillTab extends StatefulWidget {
  const _PillTab({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? icon;
  @override
  State<_PillTab> createState() => _PillTabState();
}

class _PillTabState extends State<_PillTab> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Vx.ease,
            height: 34,
            padding: EdgeInsets.only(left: widget.icon != null ? 6 : 15, right: 15),
            decoration: BoxDecoration(
              color: widget.selected ? Vx.well2 : (_hover ? Vx.well : Colors.transparent),
              borderRadius: BorderRadius.circular(999),
              boxShadow: widget.selected ? const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))] : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.icon != null) ...[widget.icon!, const SizedBox(width: 8)],
              Text(widget.label, style: Vx.sans(size: 14, weight: FontWeight.w500, color: widget.selected ? Vx.text : Vx.text2)),
            ]),
          ),
        ),
      );
}

/// Round provider icon with letter fallback (site ".lib-dot").
class ProviderIcon extends StatelessWidget {
  const ProviderIcon({super.key, required this.id, required this.name, this.size = 24});
  final String id;
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Vx.well2, borderRadius: BorderRadius.circular(size * .32)),
        alignment: Alignment.center,
        child: Image.asset(
          'assets/providers/$id-icon.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(), style: Vx.sans(size: size * .45, weight: FontWeight.w700, color: Vx.text2)),
        ),
      );
}

class PageLoader extends StatelessWidget {
  const PageLoader({super.key, this.label = 'Loading…'});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Vx.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: Vx.line)),
            child: const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
          ),
          const SizedBox(height: 14),
          Text(label, textAlign: TextAlign.center, style: Vx.sans(size: 14, color: Vx.text2, weight: FontWeight.w500)),
        ]),
      );
}

/// Site "center-box" empty/error state.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, this.onRetry, this.action, this.title, this.icon = Icons.wifi_off_rounded});
  final String message;
  final String? title;
  final IconData icon;
  final VoidCallback? onRetry;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final login = message.toLowerCase().contains('log in') || message.toLowerCase().contains('sign in');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: Vx.well2, borderRadius: BorderRadius.circular(20)),
              child: Icon(login ? Icons.lock_outline_rounded : icon, color: Vx.text2, size: 28),
            ),
            const SizedBox(height: 20),
            Text(title ?? (login ? 'Please log in first.' : 'Something went wrong'), textAlign: TextAlign.center, style: t.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(fontSize: 15)),
            if (onRetry != null || action != null) ...[
              const SizedBox(height: 22),
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                if (action != null) action!,
                if (onRetry != null) OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Try again')),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Pulsing placeholder block (site skeleton cards).
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height, this.radius = Vx.radiusXl, this.aspectRatio});
  final double? width;
  final double? height;
  final double radius;
  final double? aspectRatio;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: Color.lerp(Vx.well, Vx.well2, _c.value), borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
    return widget.aspectRatio == null ? box : AspectRatio(aspectRatio: widget.aspectRatio!, child: box);
  }
}

/// Max-width page wrapper with the site's padding.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1400, this.padding = const EdgeInsets.fromLTRB(32, 32, 32, 48)});
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => ListView(
        padding: padding,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      );
}

int gridColumns(double width, {double min = 260}) => (width / min).floor().clamp(1, 6);
