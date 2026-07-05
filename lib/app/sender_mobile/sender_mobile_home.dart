import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'sender_booking_canvas.dart';

class SenderMobileHome extends StatefulWidget {
  const SenderMobileHome({super.key});

  @override
  State<SenderMobileHome> createState() => _SenderMobileHomeState();
}

class _SenderMobileHomeState extends State<SenderMobileHome> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SenderTokens.bg,
      body: Stack(
        children: [
          const _SenderMapBackdrop(active: false),
          SafeArea(
            child: IndexedStack(
              index: _index,
              children: const [
                _SenderDashboard(),
                SenderBookingCanvas(),
                _SenderActivitySurface(),
                _SenderProfileSurface(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _SenderBottomNav(
        index: _index,
        onChanged: (next) => setState(() => _index = next),
      ),
    );
  }
}

class _SenderDashboard extends StatelessWidget {
  const _SenderDashboard();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Row(
          children: [
            const _SenderAvatar(initials: 'JA'),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good morning, Jason',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Send with calm, verified delivery.',
                    style: TextStyle(color: _SenderTokens.muted),
                  ),
                ],
              ),
            ),
            _IconGlassButton(icon: Icons.notifications_none_rounded),
          ],
        ),
        const SizedBox(height: 22),
        _HeroSendCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SenderBookingCanvas()),
          ),
        ),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(child: _MetricCard(label: 'Track', value: 'Live map')),
            SizedBox(width: 10),
            Expanded(child: _MetricCard(label: 'Recent', value: '2 orders')),
          ],
        ),
        const SizedBox(height: 14),
        const _IrisHomeCard(),
        const SizedBox(height: 14),
        const _ServiceChips(),
        const SizedBox(height: 14),
        const _RecentOrdersCard(),
      ],
    );
  }
}

class _HeroSendCard extends StatelessWidget {
  final VoidCallback onTap;

  const _HeroSendCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF0B1020)],
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Send a parcel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Book, price, pay and track in one map-led flow.',
                      style: TextStyle(color: Color(0xFFD8E7FF)),
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                backgroundColor: Colors.white,
                foregroundColor: _SenderTokens.blue,
                child: Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IrisHomeCard extends StatelessWidget {
  const _IrisHomeCard();

  @override
  Widget build(BuildContext context) {
    return const _GlassCard(
      child: Row(
        children: [
          _IrisOrb(size: 54),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IRIS ready',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Weight, vehicle and handling intelligence for every booking.',
                  style: TextStyle(color: _SenderTokens.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceChips extends StatelessWidget {
  const _ServiceChips();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ServiceChip(label: 'Health+', icon: Icons.health_and_safety_outlined),
        _ServiceChip(label: 'Business', icon: Icons.business_center_outlined),
        _ServiceChip(label: 'Gifts', icon: Icons.card_giftcard_rounded),
        _ServiceChip(label: 'Vanguard', icon: Icons.shield_outlined),
      ],
    );
  }
}

class _ServiceChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _ServiceChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _SenderTokens.lightBlue, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentOrdersCard extends StatelessWidget {
  const _RecentOrdersCard();

  @override
  Widget build(BuildContext context) {
    return const _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent orders',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 12),
          _OrderLine(
              title: 'Passport delivery', subtitle: 'Marylebone to Chelsea'),
          _OrderLine(title: 'Prescription box', subtitle: 'Health+ verified'),
        ],
      ),
    );
  }
}

class _OrderLine extends StatelessWidget {
  final String title;
  final String subtitle;

  const _OrderLine({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                Text(subtitle,
                    style: const TextStyle(color: _SenderTokens.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: _SenderTokens.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _SenderActivitySurface extends StatelessWidget {
  const _SenderActivitySurface();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: _GlassCard(
        child: Text(
          'Activity and live tracking appear here after booking.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _SenderProfileSurface extends StatelessWidget {
  const _SenderProfileSurface();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: _GlassCard(
        child: Text(
          'Profile, saved places and support stay connected to the existing app.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _SenderBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _SenderBottomNav({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xEE0B1020),
        border: Border(top: BorderSide(color: _SenderTokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _NavItem(
                index: 0,
                selected: index,
                icon: Icons.home_rounded,
                label: 'Home',
                onTap: onChanged),
            _NavItem(
                index: 1,
                selected: index,
                icon: Icons.near_me_rounded,
                label: 'Send',
                onTap: onChanged),
            _NavItem(
                index: 2,
                selected: index,
                icon: Icons.route_rounded,
                label: 'Activity',
                onTap: onChanged),
            _NavItem(
                index: 3,
                selected: index,
                icon: Icons.person_rounded,
                label: 'Profile',
                onTap: onChanged),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final int selected;
  final IconData icon;
  final String label;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.index,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = index == selected;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color:
                      active ? _SenderTokens.lightBlue : _SenderTokens.muted),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: active ? _SenderTokens.lightBlue : _SenderTokens.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SenderAvatar extends StatelessWidget {
  final String initials;

  const _SenderAvatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: _SenderTokens.blue,
      child: Text(initials,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900)),
    );
  }
}

class _IconGlassButton extends StatelessWidget {
  final IconData icon;

  const _IconGlassButton({required this.icon});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(10),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _SenderTokens.glass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: _SenderTokens.border),
            boxShadow: [
              BoxShadow(
                color: _SenderTokens.blue.withValues(alpha: .10),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _IrisOrb extends StatefulWidget {
  final double size;

  const _IrisOrb({this.size = 48});

  @override
  State<_IrisOrb> createState() => _IrisOrbState();
}

class _IrisOrbState extends State<_IrisOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat(reverse: true);
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
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [
                _SenderTokens.iris,
                _SenderTokens.vanguard,
                _SenderTokens.bg
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _SenderTokens.iris
                    .withValues(alpha: .22 + _controller.value * .12),
                blurRadius: 24,
              ),
            ],
          ),
          child: Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: widget.size * .42),
        );
      },
    );
  }
}

class _SenderMapBackdrop extends StatefulWidget {
  final bool active;

  const _SenderMapBackdrop({required this.active});

  @override
  State<_SenderMapBackdrop> createState() => _SenderMapBackdropState();
}

class _SenderMapBackdropState extends State<_SenderMapBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 26))
          ..repeat();
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
      builder: (context, _) => CustomPaint(
        painter: _SenderMapPainter(t: _controller.value, active: widget.active),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SenderMapPainter extends CustomPainter {
  final double t;
  final bool active;

  const _SenderMapPainter({required this.t, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_SenderTokens.bg, _SenderTokens.midnight],
        ).createShader(rect),
    );

    final drift = math.sin(t * math.pi * 2) * 10;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = 1;
    for (var x = -80.0 + drift; x < size.width + 80; x += 52) {
      canvas.drawLine(Offset(x, 0), Offset(x + 26, size.height), grid);
    }
    for (var y = -80.0 - drift; y < size.height + 80; y += 58) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 18), grid);
    }

    final pickup = Offset(size.width * .26, size.height * .34);
    final dropoff = Offset(size.width * .78, size.height * .22);
    final route = Path()
      ..moveTo(pickup.dx, pickup.dy)
      ..cubicTo(size.width * .28, size.height * .14, size.width * .62,
          size.height * .44, dropoff.dx, dropoff.dy);
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = _SenderTokens.lightBlue.withValues(alpha: active ? .7 : .22),
    );
    _pin(canvas, pickup, _SenderTokens.blue, t);
    _pin(canvas, dropoff, const Color(0xFF22C55E), (t + .45) % 1);
  }

  void _pin(Canvas canvas, Offset point, Color color, double phase) {
    canvas.drawCircle(
      point,
      8 + phase * 20,
      Paint()..color = color.withValues(alpha: .15 * (1 - phase)),
    );
    canvas.drawCircle(point, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SenderMapPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.active != active;
}

class _SenderTokens {
  static const bg = Color(0xFF07090F);
  static const midnight = Color(0xFF0B1020);
  static const blue = Color(0xFF3B82F6);
  static const lightBlue = Color(0xFF60A5FA);
  static const vanguard = Color(0xFF2563EB);
  static const iris = Color(0xFF38BDF8);
  static const muted = Color(0xFF9CA3AF);
  static const border = Color(0x29FFFFFF);
  static const glass = Color(0x12FFFFFF);
}
