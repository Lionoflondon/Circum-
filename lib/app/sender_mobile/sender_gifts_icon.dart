import 'package:flutter/material.dart';

class SenderGiftsIcon extends StatelessWidget {
  final double size;
  final bool filled;

  const SenderGiftsIcon({super.key, this.size = 44, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .36),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _GiftIconTokens.iri1,
            _GiftIconTokens.iri2,
            _GiftIconTokens.iri3,
            _GiftIconTokens.iri4,
            _GiftIconTokens.iri5,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _GiftIconTokens.iri2.withValues(alpha: .18),
            blurRadius: size * .45,
          ),
        ],
      ),
      child: CustomPaint(
        painter: _SenderGiftsIconPainter(filled: filled),
      ),
    );
  }
}

class _SenderGiftsIconPainter extends CustomPainter {
  final bool filled;

  const _SenderGiftsIconPainter({required this.filled});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.translate(
        (size.width - 24 * scale) / 2, (size.height - 24 * scale) / 2);
    canvas.scale(scale);

    final stroke = Paint()
      ..color = const Color(0xFF1A1330)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = const Color(0x331A1330)
      ..style = PaintingStyle.fill;

    final box = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3, 9, 18, 11),
      const Radius.circular(1.5),
    );
    if (filled) canvas.drawRRect(box, fill);
    canvas.drawRRect(box, stroke);
    canvas.drawLine(const Offset(3, 9), const Offset(21, 9), stroke);
    canvas.drawLine(const Offset(12, 9), const Offset(12, 20), stroke);

    final bow = Path()
      ..moveTo(12, 9)
      ..cubicTo(10, 5, 5, 5, 5, 8)
      ..cubicTo(5, 11, 8, 9, 12, 9)
      ..moveTo(12, 9)
      ..cubicTo(14, 5, 19, 5, 19, 8)
      ..cubicTo(19, 11, 16, 9, 12, 9);
    canvas.drawPath(bow, stroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SenderGiftsIconPainter oldDelegate) =>
      oldDelegate.filled != filled;
}

class _GiftIconTokens {
  static const iri1 = Color(0xFFA8EDEA);
  static const iri2 = Color(0xFFC9B8FF);
  static const iri3 = Color(0xFFFFD6E8);
  static const iri4 = Color(0xFFB8F0D8);
  static const iri5 = Color(0xFFD4C5FF);
}
