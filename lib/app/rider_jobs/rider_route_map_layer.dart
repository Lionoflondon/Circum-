import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class RiderRouteMapLayer extends StatefulWidget {
  final bool active;

  const RiderRouteMapLayer({super.key, this.active = true});

  @override
  State<RiderRouteMapLayer> createState() => _RiderRouteMapLayerState();
}

class _RiderRouteMapLayerState extends State<RiderRouteMapLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _RiderMapPainter(
            t: _controller.value,
            active: widget.active,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _RiderMapPainter extends CustomPainter {
  final double t;
  final bool active;

  const _RiderMapPainter({required this.t, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF07090F), Color(0xFF0B1020)],
        ).createShader(rect),
    );

    final drift = math.sin(t * math.pi * 2) * 8;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1;
    for (var x = -80.0 + drift; x < size.width + 80; x += 54) {
      canvas.drawLine(Offset(x, 0), Offset(x + 34, size.height), grid);
    }
    for (var y = -80.0 - drift; y < size.height + 80; y += 64) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 22), grid);
    }

    final pickup = Offset(size.width * .25, size.height * .34);
    final dropoff = Offset(size.width * .72, size.height * .23);
    final rider = Offset(
      ui.lerpDouble(pickup.dx, dropoff.dx, .42)!,
      ui.lerpDouble(pickup.dy, dropoff.dy, .42)!,
    );
    final route = Path()
      ..moveTo(pickup.dx, pickup.dy)
      ..cubicTo(
        size.width * .20,
        size.height * .18,
        size.width * .68,
        size.height * .42,
        dropoff.dx,
        dropoff.dy,
      );

    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF3B82F6).withValues(alpha: .22),
            const Color(0xFF38BDF8).withValues(alpha: .72),
            const Color(0xFF2563EB).withValues(alpha: .26),
          ],
          stops: [0, (t * .8 + .15) % 1, 1],
        ).createShader(rect),
    );

    _pulse(canvas, pickup, const Color(0xFF3B82F6), t);
    _pulse(canvas, dropoff, const Color(0xFF18BC5A), (t + .4) % 1);
    if (active) _pulse(canvas, rider, const Color(0xFF60A5FA), (t * 3) % 1);
  }

  void _pulse(Canvas canvas, Offset point, Color color, double phase) {
    canvas.drawCircle(
      point,
      8 + phase * 16,
      Paint()..color = color.withValues(alpha: (.16 * (1 - phase))),
    );
    canvas.drawCircle(point, 5.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RiderMapPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.active != active;
  }
}
