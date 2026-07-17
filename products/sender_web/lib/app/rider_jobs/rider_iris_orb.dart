import 'package:flutter/material.dart';

enum RiderIrisOrbState { rest, beckon, reasoning, verified }

class RiderIrisOrb extends StatefulWidget {
  final RiderIrisOrbState state;
  final double size;

  const RiderIrisOrb({
    super.key,
    this.state = RiderIrisOrbState.rest,
    this.size = 54,
  });

  @override
  State<RiderIrisOrb> createState() => _RiderIrisOrbState();
}

class _RiderIrisOrbState extends State<RiderIrisOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verified = widget.state == RiderIrisOrbState.verified;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = .65 + _controller.value * .35;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: verified
                  ? const [Color(0xFF18BC5A), Color(0xFF0B1020)]
                  : const [
                      Color(0xFF38BDF8),
                      Color(0xFF2563EB),
                      Color(0xFF0B1020)
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: (verified
                        ? const Color(0xFF18BC5A)
                        : const Color(0xFF38BDF8))
                    .withValues(alpha: .22 * pulse),
                blurRadius: 26,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Icon(
            verified ? Icons.check_rounded : Icons.auto_awesome_rounded,
            color: Colors.white,
            size: widget.size * .42,
          ),
        );
      },
    );
  }
}
