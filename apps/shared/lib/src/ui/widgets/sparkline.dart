import 'package:flutter/material.dart';

import '../theme.dart';

/// A live rate graph: a smooth line over a soft fill. A new sample eases in instead of jumping,
/// because the whole curve is tweened from the last frame's values to the new ones.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.samples,
    this.tick = 0,
    this.color = Ox.blue,
    this.height = 46,
    this.slots = 48,
  });

  final List<double> samples;

  /// Bumped for every new sample, so the newest point grows in even when the list is full.
  final int tick;
  final Color color;
  final double height;

  /// How many samples the graph spans; fewer are drawn right-aligned.
  final int slots;

  @override
  Widget build(BuildContext context) {
    final data = List<double>.of(samples);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        key: ValueKey<int>(tick),
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Ox.easeOut,
        builder: (context, t, _) => RepaintBoundary(
          child: CustomPaint(painter: _SparkPainter(data, color, slots, t)),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.data, this.color, this.slots, this.t);

  final List<double> data;
  final Color color;
  final int slots;

  /// 0..1: how far the newest sample has grown in.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) {
      final y = size.height - 1;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = Ox.hairline
          ..strokeWidth = 1,
      );
      return;
    }
    var peak = 1.0;
    for (final v in data) {
      if (v > peak) peak = v;
    }
    final n = slots < 2 ? 2 : slots;
    final dx = size.width / (n - 1);
    final first = n - data.length;
    final pts = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      var v = data[i] / peak;
      if (i == data.length - 1) {
        final prev = data.length > 1 ? data[i - 1] / peak : 0.0;
        v = prev + (v - prev) * t;
      }
      final x = (first + i) * dx;
      final y = size.height - 2 - v * (size.height - 6);
      pts.add(Offset(x, y));
    }
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      line.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
      if (i == pts.length - 1) line.lineTo(b.dx, b.dy);
    }
    final fill = Path.from(line)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    final rect = Offset.zero & size;
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(rect),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.drawCircle(pts.last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.t != t || old.color != color || old.data.length != data.length || !_same(old.data, data);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
