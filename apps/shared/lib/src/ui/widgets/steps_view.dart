import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/steps.dart';
import '../theme.dart';
import 'motion.dart';

/// The connection's stages for the chosen protocol, live from the core's log, as a vertical
/// timeline: the rail fills in blue as stages complete, the live stage pulses, and a stage that
/// takes unusually long says so, with a way into Activity.
class StepsView extends StatelessWidget {
  const StepsView({
    super.key,
    required this.plan,
    required this.stageSince,
    this.onOpenActivity,
  });

  final ConnectionPlan plan;

  /// When the current stage started, for the "taking a while" hint.
  final DateTime? stageSince;
  final VoidCallback? onOpenActivity;

  static String? _slowHint(ConnStep? step, Duration elapsed) {
    if (step == null) return null;
    final limit = switch (step.id) {
      'identity' => 15,
      'scan' => 40,
      'tor' => 60,
      _ => 30,
    };
    if (elapsed.inSeconds < limit) return null;
    return switch (step.id) {
      'identity' =>
        'Setting up your Cloudflare identity can take a minute on filtered networks. If it stalls, try HTTP/2 or enable TLS fragmentation in Settings.',
      'scan' => 'Still searching for a reachable gateway. A Thorough scan or a different protocol may help.',
      'tor' => 'Tor is building a circuit. The first connection can take a few minutes.',
      _ => 'This step is taking longer than usual.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final steps = plan.steps;
    final pct = (plan.progress * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(color: Ox.tile, borderRadius: BorderRadius.circular(Ox.radiusTile)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Building your secure connection', style: Ox.headline(19, weight: FontWeight.w600))),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: pct.toDouble()),
                duration: Ox.slow,
                curve: Ox.easeOut,
                builder: (context, v, _) =>
                    Text('${v.round()}%', style: Ox.code(14, color: Ox.secondary, weight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            _StepRow(
              step: steps[i],
              last: i == steps.length - 1,
              nextReached: i + 1 < steps.length && steps[i + 1].status != StepStatus.pending,
            ),
          Ticking(
            enabled: stageSince != null,
            builder: (context) {
              final since = stageSince;
              final hint = since == null ? null : _slowHint(plan.current, DateTime.now().difference(since));
              return AnimatedSize(
                duration: Ox.medium,
                curve: Ox.easeOut,
                alignment: Alignment.topCenter,
                child: hint == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(hint, style: Ox.body(14, color: Ox.secondary)),
                            if (onOpenActivity != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: OxLink('View live details', onTap: onOpenActivity),
                              ),
                          ],
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.last, required this.nextReached});

  final ConnStep step;
  final bool last;
  final bool nextReached;

  @override
  Widget build(BuildContext context) {
    final done = step.status == StepStatus.done;
    final retrying = step.status == StepStatus.retrying;
    final live = step.status == StepStatus.active || retrying;
    return SizedBox(
      height: last ? 34 : 50,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                SizedBox.square(dimension: 22, child: _Dot(status: step.status)),
                if (!last)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: _Rail(filled: done && nextReached, half: done && !nextReached),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: Ox.medium,
                      curve: Ox.ease,
                      style: Ox.body(16, weight: FontWeight.w600, color: done || live ? Ox.text : Ox.tertiary),
                      child: Text(step.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: Ox.medium,
                      switchInCurve: Ox.easeOut,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(a),
                          child: child,
                        ),
                      ),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topRight,
                        children: [...previous, if (current != null) current],
                      ),
                      child: Text(
                        step.detail,
                        key: ValueKey<String>(step.detail),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: Ox.body(14, color: retrying ? Ox.warn : Ox.secondary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.filled, required this.half});

  final bool filled;
  final bool half;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 2,
        decoration: BoxDecoration(color: Ox.hairline, borderRadius: BorderRadius.circular(1)),
        alignment: Alignment.topCenter,
        child: LayoutBuilder(
          builder: (context, box) => AnimatedContainer(
            duration: Ox.slow,
            curve: Ox.easeOut,
            width: 2,
            height: box.maxHeight * (filled ? 1 : (half ? 0.5 : 0)),
            decoration: BoxDecoration(color: Ox.blue, borderRadius: BorderRadius.circular(1)),
          ),
        ),
      ),
    );
  }
}

/// A stage's marker: hollow when pending, a pulsing blue ring while live (amber when retrying),
/// and a filled blue check that pops in when done.
class _Dot extends StatefulWidget {
  const _Dot({required this.status});

  final StepStatus status;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  bool get _live => widget.status == StepStatus.active || widget.status == StepStatus.retrying;

  @override
  void initState() {
    super.initState();
    if (_live) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _Dot old) {
    super.didUpdateWidget(old);
    if (_live && !_c.isAnimating) {
      _c.repeat();
    } else if (!_live && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final Widget child;
    if (status == StepStatus.done) {
      child = Container(
        key: const ValueKey('done'),
        decoration: BoxDecoration(shape: BoxShape.circle, color: Ox.blue),
        child: const Icon(Icons.check_rounded, size: 15, color: Colors.white),
      );
    } else if (_live) {
      final color = status == StepStatus.retrying ? Ox.warn : Ox.blue;
      child = RepaintBoundary(
        key: ValueKey(status),
        child: CustomPaint(painter: _LivePainter(_c, color)),
      );
    } else {
      child = Container(
        key: const ValueKey('pending'),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Ox.hairline, width: 2)),
      );
    }
    return AnimatedSwitcher(
      duration: Ox.medium,
      // The pop overshoots on scale only: an opacity past 1 is not allowed.
      transitionBuilder: (child, a) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Ox.easeOut, reverseCurve: Ox.easeIn),
        child: ScaleTransition(
          scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack, reverseCurve: Ox.easeIn),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _LivePainter extends CustomPainter {
  _LivePainter(this.t, this.color) : super(repaint: t);

  final Animation<double> t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    final v = t.value;
    // A soft pulse behind, and a short arc running round the ring.
    final p = Curves.easeOut.transform(v);
    canvas.drawCircle(c, r * (0.55 + 0.45 * p), Paint()..color = color.withValues(alpha: 0.28 * (1 - p)));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.25),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2 + v * math.pi * 2,
      math.pi * 0.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawCircle(c, r * 0.32, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LivePainter old) => old.color != color || old.t != t;
}

/// apple.com's blue text link with a chevron: "Learn more ›".
class OxLink extends StatelessWidget {
  const OxLink(this.text, {super.key, this.onTap, this.size = 15});

  final String text;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: Ox.body(size, color: Ox.blue, weight: FontWeight.w500)),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: size + 3, color: Ox.blue),
          ],
        ),
      ),
    );
  }
}
