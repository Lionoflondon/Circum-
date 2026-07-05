import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'sender_booking_canvas.dart';

const senderMobileDashboardServiceNames = ['Health+', 'Business', 'Gifts'];

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
              children: [
                _SenderDashboard(
                    onStartDelivery: () => setState(() => _index = 1)),
                const SenderBookingCanvas(),
                const _SenderActivitySurface(),
                const _SenderProfileSurface(),
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
  final VoidCallback onStartDelivery;

  const _SenderDashboard({required this.onStartDelivery});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Row(
          children: [
            const Text(
              'CIRCUM',
              style: TextStyle(
                color: _SenderTokens.lightBlue,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.4,
              ),
            ),
            const Spacer(),
            _IconGlassButton(icon: Icons.notifications_none_rounded),
            const SizedBox(width: 10),
            const _SenderAvatar(initials: 'JA'),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Good morning, Jason',
          style: TextStyle(
            color: Colors.white,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Send with calm, verified delivery.',
          style: TextStyle(color: _SenderTokens.muted),
        ),
        const SizedBox(height: 18),
        _HeroSendCard(onTap: onStartDelivery),
        const SizedBox(height: 18),
        const _YourCircumHub(),
        const SizedBox(height: 16),
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
      radius: 32,
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: Container(
          height: 236,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _SenderTokens.midnight.withValues(alpha: .94),
                _SenderTokens.blue.withValues(alpha: .42),
                _SenderTokens.bg,
              ],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: _HeroRouteArt()),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .25),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _SenderTokens.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded,
                          color: _SenderTokens.lightBlue, size: 16),
                      SizedBox(width: 6),
                      Text(
                        '2 orders',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                top: 0,
                child: _IrisOrb(size: 58),
              ),
              Positioned(
                left: 0,
                right: 118,
                bottom: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Send a parcel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Book, price, pay and track in one map-led flow.',
                      style: TextStyle(
                        color: Color(0xFFD8E7FF),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: _SenderTokens.blue.withValues(alpha: .28),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Start a delivery',
                            style: TextStyle(
                              color: _SenderTokens.bg,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded,
                              color: _SenderTokens.blue, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YourCircumHub extends StatelessWidget {
  const _YourCircumHub();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Circum',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ServiceCard(
                title: 'Health+',
                subtitle: 'Care-led delivery',
                icon: Icons.health_and_safety_rounded,
                accent: _SenderTokens.health,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _ServiceCard(
                title: 'Business',
                subtitle: 'Company sending',
                icon: Icons.business_center_rounded,
                accent: _SenderTokens.business,
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        _ServiceCard(
          title: 'Gifts',
          subtitle: 'Premium moments, tracked beautifully',
          icon: Icons.redeem_rounded,
          accent: _SenderTokens.gifts,
          wide: true,
        ),
      ],
    );
  }
}

class _ServiceCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final bool wide;

  const _ServiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.wide = false,
  });

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _pressed ? 1.02 : 1,
        child: _GlassCard(
          radius: 24,
          padding: const EdgeInsets.all(15),
          child: SizedBox(
            height: widget.wide ? 92 : 124,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ServiceIcon(icon: widget.icon, accent: widget.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.subtitle,
                            style: const TextStyle(
                              color: _SenderTokens.muted,
                              height: 1.25,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Icon(Icons.arrow_forward_rounded,
                            color: widget.accent, size: 18),
                      ),
                    ],
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

class _ServiceIcon extends StatelessWidget {
  final IconData icon;
  final Color accent;

  const _ServiceIcon({required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .38)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 18),
        ],
      ),
      child: Icon(icon, color: accent, size: 24),
    );
  }
}

class _HeroRouteArt extends StatelessWidget {
  const _HeroRouteArt();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HeroRoutePainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _HeroRoutePainter extends CustomPainter {
  const _HeroRoutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .035)
      ..strokeWidth = 1;
    for (var x = size.width * .42; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x - 16, size.height), grid);
    }
    for (var y = 8.0; y < size.height; y += 28) {
      canvas.drawLine(
          Offset(size.width * .38, y), Offset(size.width, y + 6), grid);
    }
    final start = Offset(size.width * .58, size.height * .70);
    final end = Offset(size.width * .90, size.height * .38);
    final route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(size.width * .66, size.height * .36, size.width * .82,
          size.height * .86, end.dx, end.dy);
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            _SenderTokens.lightBlue.withValues(alpha: .18),
            _SenderTokens.iris.withValues(alpha: .74),
            _SenderTokens.health.withValues(alpha: .35),
          ],
        ).createShader(rect),
    );
    _dot(canvas, start, _SenderTokens.blue);
    _dot(canvas, end, _SenderTokens.health);
  }

  void _dot(Canvas canvas, Offset point, Color color) {
    canvas.drawCircle(point, 16, Paint()..color = color.withValues(alpha: .11));
    canvas.drawCircle(point, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HeroRoutePainter oldDelegate) => false;
}

class _RecentOrdersCard extends StatelessWidget {
  const _RecentOrdersCard();

  @override
  Widget build(BuildContext context) {
    return const _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent orders',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Live tracking and status',
                      style: TextStyle(color: _SenderTokens.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: _SenderTokens.muted),
            ],
          ),
          SizedBox(height: 14),
          _OrderLine(
            title: 'Passport delivery',
            subtitle: 'Marylebone → Chelsea',
            status: 'In transit',
            icon: Icons.badge_rounded,
            accent: _SenderTokens.business,
          ),
          _OrderLine(
            title: 'Prescription box',
            subtitle: 'Health+ verified',
            status: 'Delivered',
            icon: Icons.medical_services_rounded,
            accent: _SenderTokens.health,
          ),
        ],
      ),
    );
  }
}

class _OrderLine extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final IconData icon;
  final Color accent;

  const _OrderLine({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _SenderTokens.border),
      ),
      child: Row(
        children: [
          _ServiceIcon(icon: icon, accent: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(color: _SenderTokens.muted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _SenderTokens.health.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: _SenderTokens.health.withValues(alpha: .32)),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: _SenderTokens.health,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
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
  static const health = Color(0xFF22C55E);
  static const business = Color(0xFF94A3B8);
  static const gifts = Color(0xFFE8B4A0);
  static const muted = Color(0xFF9CA3AF);
  static const border = Color(0x29FFFFFF);
  static const glass = Color(0x12FFFFFF);
}
