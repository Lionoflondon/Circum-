import 'circum_home_link.dart';
import 'package:flutter/material.dart';

/// A flowing presentation around the existing sender authentication form.
/// Controllers, callbacks and authentication state remain with the sender.
class ServiceAccessFrame extends StatelessWidget {
  const ServiceAccessFrame(
      {super.key, required this.health, required this.child});
  final bool health;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = health ? const Color(0xffd2f6ee) : const Color(0xfff0d9ba);
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.dark,
        colorScheme:
            ColorScheme.dark(primary: accent, surface: const Color(0xff030506)),
        textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: accent)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800;
        final story = DecoratedBox(
          decoration: BoxDecoration(
              gradient: RadialGradient(
            center: Alignment.bottomLeft,
            radius: 1.35,
            colors: [
              health ? const Color(0xff163b3b) : const Color(0xff352e23),
              const Color(0xff030506)
            ],
          )),
          child: CustomPaint(
            painter: _ServiceOrbitPainter(accent),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: wide ? 68 : 28, vertical: wide ? 84 : 38),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircumHomeLink(child: Text(health ? 'HEALTH+' : 'CIRCUM BUSINESS',
                        style: TextStyle(
                            color: accent, fontSize: 11, letterSpacing: 2.5))),
                    const SizedBox(height: 34),
                    Text(health ? 'A little help.' : 'Business moves.',
                        style: TextStyle(
                            color: const Color(0xfff4f3f0),
                            fontFamily: 'D-DIN',
                            fontSize: wide ? 58 : 40,
                            height: 1.06,
                            letterSpacing: -1.5)),
                    Text(health ? 'A lighter day.' : 'We deliver.',
                        style: TextStyle(
                            color: accent,
                            fontFamily: 'D-DIN',
                            fontStyle: FontStyle.normal,
                            fontSize: wide ? 62 : 44,
                            height: 1.12,
                            letterSpacing: -1.5)),
                    const SizedBox(height: 30),
                    Text(
                        health
                            ? 'Prescription and pharmacy collections, with care from pickup to handover.'
                            : 'Your company’s deliveries, members and invoices. Together in your Business Centre.',
                        style: const TextStyle(
                            color: Color(0xffb3c3c0),
                            fontFamily: 'D-DIN',
                            fontSize: 19,
                            height: 1.6)),
                    if (wide) ...[
                      const SizedBox(height: 68),
                      const Divider(color: Color(0xff34453f)),
                      const SizedBox(height: 24),
                      Text(
                          health
                              ? 'CARE IN THE EVERYDAY'
                              : 'BUILT AROUND YOUR WORKING DAY',
                          style: TextStyle(
                              color: accent, fontSize: 10, letterSpacing: 1.7)),
                      const SizedBox(height: 16),
                      Text(
                          health
                              ? 'One less journey.\nA little more ease.'
                              : 'Less chasing.\nMore doing.',
                          style: TextStyle(
                              color: accent, fontSize: 25, height: 1.4)),
                    ],
                  ]),
            ),
          ),
        );
        final form = Padding(
          padding: EdgeInsets.symmetric(
              horizontal: wide ? 60 : 28, vertical: wide ? 92 : 38),
          child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 410),
                  child: child)),
        );
        return wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: story), Expanded(child: form)])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [story, form]);
      }),
    );
  }
}

class _ServiceOrbitPainter extends CustomPainter {
  const _ServiceOrbitPainter(this.accent);
  final Color accent;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: .13);
    canvas.drawCircle(
        Offset(size.width * .12, size.height * 1.12), size.width * .83, stroke);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(size.width * .65, size.height * 1.1),
            width: size.width * 1.4,
            height: size.height * .6),
        stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ServiceOrbitPainter oldDelegate) =>
      accent != oldDelegate.accent;
}
