import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/controller.dart';
import '../theme.dart';
import 'motion.dart';

/// The hero control, drawn from the logo: an orbit ring with a gap, and the core that slips out
/// through it.
///
///  * Off: the ring rests with its gap open, the core parked in the gap, dim.
///  * Connecting: the core leaves the gap and circles the ring with a comet tail, sonar rings
///    roll outward, and the ring fills in blue as each stage of the route completes.
///  * Connected: the ring closes, a single shock ring bursts out, the core docks back in the
///    gap and glows, and the whole orb breathes slowly while the tunnel is up.
///  * Disconnecting: everything cross-fades back to rest; nothing ever snaps.
///
/// Every layer is one CustomPainter repainted straight from its animation controllers (no
/// widget rebuilds per frame), inside a RepaintBoundary, so it stays at 60 fps on cheap phones.
class ConnectOrb extends StatefulWidget {
  const ConnectOrb({
    super.key,
    required this.state,
    required this.progress,
    required this.onTap,
    this.size = 260,
  });

  final CoreState state;

  /// 0..1: how far along the connection plan is.
  final double progress;
  final VoidCallback? onTap;
  final double size;

  @override
  State<ConnectOrb> createState() => _ConnectOrbState();
}

class _ConnectOrbState extends State<ConnectOrb> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1900));
  late final AnimationController _ripple =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3800));
  late final AnimationController _on =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _hunt =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _burst =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  late final AnimationController _prog =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  bool _reduce = false;
  double _progTarget = 0;

  double _targetProgress() {
    final s = widget.state;
    if (s == CoreState.connected) return 1.0;
    if (s == CoreState.stopped || s == CoreState.stopping) return 0.0;
    return widget.progress.clamp(0.0, 1.0);
  }

  static bool _isHunting(CoreState s) =>
      s == CoreState.starting || s == CoreState.connecting || s == CoreState.reconnecting;

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    _on.value = s == CoreState.connected ? 1 : 0;
    _hunt.value = _isHunting(s) ? 1 : 0;
    _progTarget = _targetProgress();
    _prog.value = _progTarget;
    _burst.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = context.reduceMotion;
    _syncLoops();
  }

  @override
  void didUpdateWidget(covariant ConnectOrb old) {
    super.didUpdateWidget(old);
    final s = widget.state;
    final wasHunting = _isHunting(old.state);
    final isHunting = _isHunting(s);
    if (isHunting && !wasHunting && !_reduce) {
      // Launch a fresh wave as soon as a new connection attempt begins.
      _burst.forward(from: 0);
    }
    if (s != old.state) {
      final nowOn = s == CoreState.connected;
      final wasOn = old.state == CoreState.connected;
      if (nowOn && !wasOn) {
        _on.animateTo(1); // The painter applies the easing.
        if (!_reduce) _burst.forward(from: 0);
        HapticFeedback.mediumImpact();
      } else if (!nowOn && wasOn) {
        _on.animateTo(0, duration: const Duration(milliseconds: 650));
      }
      if (wasHunting != isHunting) {
        _hunt.animateTo(
          isHunting ? 1 : 0,
          duration: _reduce ? Duration.zero : Duration(milliseconds: isHunting ? 900 : 650),
          curve: Ox.easeInOut,
        );
      }
      _syncLoops();
    }
    final target = _targetProgress();
    if ((target - _progTarget).abs() > 0.001) {
      _progTarget = target;
      _prog.animateTo(target, curve: Ox.easeOut);
    }
  }

  void _syncLoops() {
    final s = widget.state;
    if (_reduce) {
      _spin.stop();
      _ripple.stop();
      _breath.stop();
      return;
    }
    final moving = _isHunting(s) || s == CoreState.stopping;
    if (moving) {
      if (!_spin.isAnimating) _spin.repeat();
      if (_isHunting(s) && !_ripple.isAnimating) _ripple.repeat();
    } else if (_spin.isAnimating || _ripple.isAnimating) {
      // Let the comet and the sonar fade out with _hunt before they stop.
      Future<void>.delayed(const Duration(milliseconds: 560), () {
        if (!mounted) return;
        final st = widget.state;
        if (!_isHunting(st) && st != CoreState.stopping) {
          _spin.stop();
          _ripple.stop();
        }
      });
    }
    if (s == CoreState.connected) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _ripple.dispose();
    _breath.dispose();
    _on.dispose();
    _hunt.dispose();
    _burst.dispose();
    _prog.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final size = widget.size;
    final on = s == CoreState.connected;
    final hunting = _isHunting(s);

    final IconData icon = switch (s) {
      CoreState.stopped => Icons.power_settings_new_rounded,
      CoreState.starting || CoreState.connecting => Icons.radar_rounded,
      CoreState.reconnecting => Icons.autorenew_rounded,
      CoreState.connected => Icons.verified_user_rounded,
      CoreState.stopping => Icons.hourglass_top_rounded,
    };
    final Color iconColor = on
        ? Colors.white
        : (s == CoreState.reconnecting ? Ox.warn : (hunting ? Ox.blue : Ox.secondary));
    final label = switch (s) {
      CoreState.stopped => 'Connect',
      CoreState.connected => 'Disconnect',
      CoreState.stopping => 'Disconnecting',
      _ => 'Cancel connection',
    };

    return Pressable(
      onTap: widget.onTap,
      scale: 0.95,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(size),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: Size.square(size),
                painter: _OrbPainter(
                  spin: _spin,
                  ripple: _ripple,
                  breath: _breath,
                  on: _on,
                  hunt: _hunt,
                  burst: _burst,
                  progress: _prog,
                  stopping: s == CoreState.stopping,
                  retrying: s == CoreState.reconnecting,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Ox.easeOut,
              switchOutCurve: Ox.easeIn,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween<double>(begin: 0.6, end: 1).animate(a), child: child),
              ),
              child: AnimatedBuilder(
                key: ValueKey<IconData>(icon),
                animation: _spin,
                child: TweenAnimationBuilder<Color?>(
                  key: ValueKey<IconData>(icon),
                  tween: ColorTween(end: iconColor),
                  duration: Ox.medium,
                  builder: (context, color, _) => Icon(icon, size: size * 0.17, color: color),
                ),
                builder: (context, child) {
                  final angle = hunting && !_reduce ? _spin.value * math.pi * 2 : 0.0;
                  final pulse = hunting && !_reduce
                      ? 1 + 0.055 * math.sin(_spin.value * math.pi * 2)
                      : 1.0;
                  return Transform.rotate(
                    angle: angle,
                    child: Transform.scale(scale: pulse, child: child),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.spin,
    required this.ripple,
    required this.breath,
    required this.on,
    required this.hunt,
    required this.burst,
    required this.progress,
    required this.stopping,
    required this.retrying,
  }) : super(repaint: Listenable.merge([spin, ripple, breath, on, hunt, burst, progress]));

  final Animation<double> spin;
  final Animation<double> ripple;
  final Animation<double> breath;
  final Animation<double> on;
  final Animation<double> hunt;
  final Animation<double> burst;
  final Animation<double> progress;
  final bool stopping;
  final bool retrying;

  // The logo's geometry: the ring's gap is centred at the upper right (-45 degrees) and spans
  // 1.153 rad; the core sits in it, slightly outside the ring.
  static const _gapCentre = -math.pi / 4;
  static const _gapSpan = 1.153;

  static Color _a(Color c, double alpha) => c.withValues(alpha: (c.a * alpha).clamp(0.0, 1.0));

  static double _lerpAngle(double a, double b, double t) {
    var d = (b - a) % (math.pi * 2);
    if (d > math.pi) d -= math.pi * 2;
    if (d < -math.pi) d += math.pi * 2;
    return a + d * t;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final ringR = s * 0.34;
    final w = s * 0.024;
    final discR = s * 0.255;
    final outer = s * 0.5;

    final vOn = Ox.easeInOut.transform(on.value.clamp(0.0, 1.0));
    final vHunt = hunt.value.clamp(0.0, 1.0);
    final vBreath = Curves.easeInOut.transform(breath.value);
    final vProg = progress.value.clamp(0.0, 1.0);
    final vBurst = burst.value;
    final huntColor = retrying ? Ox.warn : Ox.blue;

    // 1. Ambient glow behind everything.
    final pulse = 0.5 + 0.5 * math.sin(spin.value * math.pi * 2);
    final glowA = 0.10 * vHunt * (0.7 + 0.3 * pulse) + 0.30 * vOn * (0.8 + 0.2 * vBreath);
    if (glowA > 0.003) {
      final glowRect = Rect.fromCircle(center: c, radius: outer);
      canvas.drawCircle(
        c,
        outer,
        Paint()
          ..shader = RadialGradient(
            colors: [_a(Ox.blue, glowA), _a(Ox.blue, glowA * 0.35), _a(Ox.blue, 0)],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(glowRect),
      );
    }

    // 2. Sonar rings while hunting for a route.
    if (vHunt > 0.01) {
      for (var k = 0; k < 3; k++) {
        final p = (ripple.value + k / 3) % 1.0;
        final e = Ox.easeOut.transform(p);
        final r = ringR + (outer - ringR) * e;
        final alpha = math.pow(1 - p, 1.6).toDouble() * 0.42 * vHunt;
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0 + (1 - p) * 1.6
            ..color = _a(retrying ? Ox.warn : Ox.blueSoft, alpha),
        );
      }
    }

    // 3. The shock ring when the tunnel comes up.
    if (vBurst > 0 && vBurst < 1) {
      final e = Ox.easeOut.transform(vBurst);
      canvas.drawCircle(
        c,
        ringR + (outer - ringR) * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * (1 - e) + 0.8
          ..color = _a(Ox.blueIce, (1 - e) * 0.75),
      );
    }

    final ringRect = Rect.fromCircle(center: c, radius: ringR);

    // 4. Track.
    canvas.drawCircle(
      c,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = Color.lerp(Ox.hairlineSoft, _a(Ox.blue, 0.22), vOn)!,
    );

    // 5a. Resting ring: the logo's open "O".
    final idleA = (1 - vOn) * (1 - vHunt);
    if (idleA > 0.01) {
      final start = _gapCentre + _gapSpan / 2;
      canvas.drawArc(
        ringRect,
        start,
        math.pi * 2 - _gapSpan,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = _a(stopping ? Ox.tertiary : const Color(0xFFC7C7CC), idleA),
      );
    }

    // 5b. Progress: the ring fills in as each stage completes.
    final progA = vHunt * (1 - vOn);
    if (progA > 0.01 && vProg > 0.005) {
      canvas.drawArc(
        ringRect,
        -math.pi / 2,
        math.pi * 2 * vProg,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [_a(Ox.blueDeep, progA), _a(huntColor, progA), _a(Ox.blueSoft, progA)],
            stops: const [0.0, 0.6, 1.0],
            transform: const GradientRotation(-math.pi / 2),
          ).createShader(ringRect),
      );
    }

    // 5c. Closed ring once connected, its light slowly turning.
    if (vOn > 0.01) {
      final turn = -math.pi / 2 + vBreath * 0.6;
      canvas.drawArc(
        ringRect,
        -math.pi / 2,
        math.pi * 2 * vOn,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [Ox.blueSoft, Ox.blue, Ox.blueDeep, Ox.blue, Ox.blueSoft],
            stops: const [0.0, 0.3, 0.55, 0.8, 1.0],
            transform: GradientRotation(turn),
          ).createShader(ringRect),
      );
    }

    // 6. The comet: the core circling the ring, looking for the way out.
    final head = -math.pi / 2 + spin.value * math.pi * 2;
    if (vHunt > 0.01) {
      const trail = 1.7;
      canvas.drawArc(
        ringRect,
        head - trail,
        trail,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 1.05
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [_a(Ox.blueIce, 0), _a(Ox.blueIce, 0.95 * vHunt)],
            stops: const [0.0, trail / (math.pi * 2)],
            transform: GradientRotation(head - trail),
          ).createShader(ringRect),
      );
    }

    // 7. The disc, lit from above like glass.
    final pop = vBurst > 0 && vBurst < 1 ? math.sin(math.pi * Ox.easeOut.transform(vBurst)) * 0.045 : 0.0;
    final dr = discR * (1 + pop + 0.012 * vOn * vBreath);
    canvas.drawCircle(
      c.translate(0, s * 0.02),
      dr,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.10 + 0.12 * vOn)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.04),
    );
    final discRect = Rect.fromCircle(center: c, radius: dr);
    canvas.drawCircle(
      c,
      dr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(const Color(0xFFFFFFFF), const Color(0xFF3AA0FF), vOn)!,
            Color.lerp(const Color(0xFFEDEDF0), const Color(0xFF0058E0), vOn)!,
          ],
        ).createShader(discRect),
    );
    canvas.drawCircle(
      c,
      dr - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(Colors.black.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.18), vOn)!,
    );
    final shine = Rect.fromCenter(center: c.translate(0, -dr * 0.45), width: dr * 1.5, height: dr * 0.9);
    canvas.drawOval(
      shine,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.09 + 0.06 * vOn), Colors.white.withValues(alpha: 0)],
        ).createShader(shine),
    );

    // 8. The core itself: parked in the gap at rest, riding the comet's head while hunting.
    final parkedR = ringR * (1.07 - 0.07 * vOn);
    final angle = _lerpAngle(_gapCentre, head, vHunt);
    final radius = parkedR + (ringR - parkedR) * vHunt;
    final node = c + Offset(math.cos(angle), math.sin(angle)) * radius;
    final haloA = 0.55 * vHunt + vOn * (0.35 + 0.3 * vBreath);
    if (haloA > 0.01) {
      final haloR = w * 3.4;
      canvas.drawCircle(
        node,
        haloR,
        Paint()
          ..shader = RadialGradient(
            colors: [_a(Ox.blueSoft, haloA), _a(Ox.blueSoft, 0)],
          ).createShader(Rect.fromCircle(center: node, radius: haloR)),
      );
    }
    final restCore = stopping ? Ox.tertiary : const Color(0xFFAEAEB2);
    final coreColor = Color.lerp(Color.lerp(restCore, Ox.blueIce, vHunt), Colors.white, vOn)!;
    canvas.drawCircle(node, w * 0.95, Paint()..color = coreColor);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.stopping != stopping ||
      old.retrying != retrying ||
      old.spin != spin ||
      old.on != on;
}
