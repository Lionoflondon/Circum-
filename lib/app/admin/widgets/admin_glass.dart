import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/admin_tokens.dart';

class AdminGlassBackground extends StatelessWidget {
  const AdminGlassBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AdminTokens.pageGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            child: CustomPaint(painter: _AdminGlowPainter()),
          ),
          child,
        ],
      ),
    );
  }
}

class AdminGlassPanel extends StatelessWidget {
  const AdminGlassPanel({
    required this.child,
    this.padding,
    this.width,
    this.height,
    this.margin,
    this.radius,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? margin;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final panelRadius = radius ?? AdminTokens.panelRadius;
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(panelRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AdminTokens.blurSigma,
            sigmaY: AdminTokens.blurSigma,
          ),
          child: Container(
            padding: padding ?? const EdgeInsets.all(AdminTokens.panelPadding),
            decoration: BoxDecoration(
              color: AdminTokens.glass,
              gradient: const LinearGradient(
                colors: [AdminTokens.glassStrong, AdminTokens.glass],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(panelRadius),
              border: Border.all(color: AdminTokens.glassBorder),
            ),
            child: Stack(
              children: [
                child,
                Positioned(
                  left: 1,
                  right: 1,
                  top: 0,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(color: AdminTokens.hairline)),
                      ),
                      child: const SizedBox(height: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminChip extends StatelessWidget {
  const AdminChip({required this.label, this.warning = false, super.key});

  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (warning ? AdminTokens.warning : AdminTokens.accent)
            .withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AdminTokens.controlRadius),
        border: Border.all(
          color: (warning ? AdminTokens.warning : AdminTokens.accent)
              .withValues(alpha: .28),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: warning ? AdminTokens.warning : AdminTokens.accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class AdminStatTile extends StatelessWidget {
  const AdminStatTile({
    required this.label,
    required this.value,
    this.accent = AdminTokens.accent,
    super.key,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AdminGlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AdminTokens.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminStatusTag extends StatelessWidget {
  const AdminStatusTag({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final lower = status.toLowerCase();
    final color = switch (lower) {
      final value
          when value.contains('cancel') ||
              value.contains('fail') ||
              value.contains('reject') ||
              value.contains('escalat') =>
        AdminTokens.danger,
      final value
          when value.contains('deliver') ||
              value.contains('complete') ||
              value.contains('approv') =>
        AdminTokens.success,
      final value
          when value.contains('transit') ||
              value.contains('resolv') ||
              value.contains('schedul') =>
        Colors.lightBlueAccent,
      _ => AdminTokens.warning,
    };
    return AdminChip(label: status, warning: color == AdminTokens.warning);
  }
}

class _AdminGlowPainter extends CustomPainter {
  const _AdminGlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final topRight = Paint()
      ..shader = RadialGradient(
        colors: [AdminTokens.blueGlow, Colors.transparent],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .92, size.height * .03),
          radius: size.shortestSide * .64,
        ),
      );
    final left = Paint()
      ..shader = RadialGradient(
        colors: [AdminTokens.cyanGlow, Colors.transparent],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .02, size.height * .36),
          radius: size.shortestSide * .55,
        ),
      );
    canvas.drawRect(Offset.zero & size, topRight);
    canvas.drawRect(Offset.zero & size, left);
  }

  @override
  bool shouldRepaint(covariant _AdminGlowPainter oldDelegate) => false;
}
