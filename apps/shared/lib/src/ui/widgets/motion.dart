import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Anything you can press: it gives under the finger (a 4% scale, like iOS buttons), shows a
/// hand cursor on desktop, and works from the keyboard (Enter / Space) with a focus ring.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.semanticLabel,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final String? semanticLabel;
  final BorderRadius borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _focused = false;
  bool _hover = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduce = context.reduceMotion;
    final scale = !enabled || reduce ? 1.0 : (_down ? widget.scale : (_hover ? 1.01 : 1.0));
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _set(true) : null,
          onTapUp: enabled ? (_) => _set(false) : null,
          onTapCancel: enabled ? () => _set(false) : null,
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                }
              : null,
          child: AnimatedScale(
            scale: scale,
            duration: _down ? const Duration(milliseconds: 110) : const Duration(milliseconds: 320),
            curve: _down ? Curves.easeOut : Ox.easeOut,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(
                  color: _focused ? Ox.blue.withValues(alpha: 0.9) : Colors.transparent,
                  width: 2,
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts its child into place once, after [delay]: apple.com's scroll-in reveal,
/// used to stagger a page's tiles on first show.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero, this.offset = 18});

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 720));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Ox.easeOut);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        if (v >= 1) return child!;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - v) * widget.offset), child: child),
        );
      },
    );
  }
}

/// A text (or any widget) swap that blurs out and blurs in, the way apple.com changes a headline.
class BlurSwitcher extends StatelessWidget {
  const BlurSwitcher({super.key, required this.child, this.duration = const Duration(milliseconds: 520)});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: Duration(milliseconds: (duration.inMilliseconds * 0.6).round()),
      switchInCurve: Ox.easeOut,
      switchOutCurve: Ox.easeIn,
      transitionBuilder: (child, a) => AnimatedBuilder(
        animation: a,
        child: child,
        builder: (context, child) {
          final v = a.value;
          final sigma = (1 - v) * 10;
          Widget out = Transform.translate(
            offset: Offset(0, (1 - v) * 10),
            child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
          );
          if (sigma > 0.2) {
            out = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: out,
            );
          }
          return Opacity(opacity: v.clamp(0.0, 1.0), child: out);
        },
      ),
      child: child,
    );
  }
}

/// Keeps every tab alive (scroll positions, text fields) and moves between them with a
/// shared-axis transition: the old page drifts away and dims, the new one slides in from the
/// side you are heading to and settles. Hidden tabs are offstage with their tickers paused.
class PageSwitcher extends StatefulWidget {
  const PageSwitcher({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<PageSwitcher> createState() => _PageSwitcherState();
}

class _PageSwitcherState extends State<PageSwitcher> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Ox.page, value: 1);
  late int _to = widget.index;
  int _from = -1;

  @override
  void didUpdateWidget(covariant PageSwitcher old) {
    super.didUpdateWidget(old);
    if (widget.index != _to) {
      _from = _to;
      _to = widget.index;
      if (context.reduceMotion) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final raw = _c.value;
        final animating = raw < 1 && _from >= 0;
        final t = Ox.easeOut.transform(raw);
        final dir = _to >= _from ? 1.0 : -1.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              _layer(i, t, raw, animating, dir),
          ],
        );
      },
    );
  }

  Widget _layer(int i, double t, double raw, bool animating, double dir) {
    final isTo = i == _to;
    final isFrom = animating && i == _from;
    final visible = isTo || isFrom;
    final Widget child = KeyedSubtree(key: ValueKey<int>(i), child: widget.children[i]);

    double opacity = 1;
    double dx = 0;
    double scale = 1;
    if (isTo && animating) {
      opacity = (raw * 1.6).clamp(0.0, 1.0);
      dx = dir * (1 - t) * 36;
      scale = 0.985 + 0.015 * t;
    } else if (isFrom) {
      final out = Ox.easeIn.transform((raw * 1.8).clamp(0.0, 1.0));
      opacity = 1 - out;
      dx = -dir * out * 22;
      scale = 1 - 0.015 * out;
    }

    // The wrapper chain is the same in every frame, animating or not: changing it would make
    // Flutter rebuild the page from scratch and lose its scroll position and fields.
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: IgnorePointer(
          ignoring: !isTo,
          child: Opacity(
            opacity: visible ? opacity : 0,
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: Transform.scale(scale: scale, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rebuilds [builder] once a second, for clocks (uptime, time on a stage).
class Ticking extends StatefulWidget {
  const Ticking({super.key, required this.builder, this.enabled = true});

  final WidgetBuilder builder;
  final bool enabled;

  @override
  State<Ticking> createState() => _TickingState();
}

class _TickingState extends State<Ticking> {
  Stream<int>? _ticks;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant Ticking oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  void _sync() {
    _ticks = widget.enabled ? Stream<int>.periodic(const Duration(seconds: 1), (i) => i) : null;
  }

  @override
  Widget build(BuildContext context) {
    final ticks = _ticks;
    if (ticks == null) return widget.builder(context);
    return StreamBuilder<int>(stream: ticks, builder: (context, _) => widget.builder(context));
  }
}
