part of 'circum_website_app.dart';

const _landingInk = Color(0xff10231f);
const _landingBlue = Color(0xff2455f5);
const _landingMuted = Color(0xff66706c);
const _landingPaper = Color(0xfffafaf7);

class _PremiumLanding extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onRider;
  final VoidCallback onHealthPlus;
  final VoidCallback onBusiness;
  final VoidCallback onVanguard;
  final VoidCallback? onGifts;

  const _PremiumLanding({
    required this.onStart,
    required this.onRider,
    required this.onHealthPlus,
    required this.onBusiness,
    required this.onVanguard,
    this.onGifts,
  });

  Widget _link(String label, String path, VoidCallback action,
      {bool primary = false, bool inverse = false}) {
    return Link(
      uri: _CircumWebsiteAppState._canonicalWebUri(path),
      target: LinkTarget.self,
      builder: (context, followLink) => TextButton(
        onPressed: followLink ?? action,
        style: TextButton.styleFrom(
          backgroundColor: primary ? _landingBlue : Colors.transparent,
          foregroundColor: primary || inverse ? Colors.white : _landingInk,
          padding:
              EdgeInsets.symmetric(horizontal: primary ? 24 : 14, vertical: 20),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label),
          if (primary) ...[
            const SizedBox(width: 18),
            const Icon(Icons.arrow_forward, size: 19)
          ],
        ]),
      ),
    );
  }

  Widget _eyebrow(String text, {Color color = _landingMuted}) => Text(
        text,
        style: TextStyle(
            color: color,
            fontSize: 11,
            letterSpacing: 2.1,
            fontWeight: FontWeight.w700),
      );

  Widget _section(Widget child,
          {Color background = _landingPaper, double vertical = 80}) =>
      Container(
        width: double.infinity,
        color: background,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: vertical),
        child: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: child)),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final small = constraints.maxWidth < 600;
      final headlineSize = small ? 54.0 : (wide ? 82.0 : 76.0);
      final intro =
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _eyebrow('LONDON DELIVERY. A LITTLE MORE HUMAN.'),
        const SizedBox(height: 26),
        Text('Move what\nmatters.',
            style: TextStyle(
              color: _landingInk,
              fontSize: headlineSize,
              height: 1.0,
              letterSpacing: -3.4,
              fontWeight: FontWeight.w800,
            )),
        const SizedBox(height: 28),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 445),
          child: const Text(
              'From everyday parcels to important handovers. Book a delivery, see the price, and follow its journey with Circum.',
              style:
                  TextStyle(color: _landingMuted, fontSize: 19, height: 1.6)),
        ),
        const SizedBox(height: 32),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _link('Send a parcel', '/send', onStart, primary: true),
          if (onGifts != null) _link('Explore Gifts ↗', '/gifts', onGifts!),
        ]),
        const SizedBox(height: 34),
        const Row(children: [
          Icon(Icons.location_on_outlined, size: 16, color: _landingMuted),
          SizedBox(width: 7),
          Flexible(
              child: Text('Deliveries across London & surrounding areas',
                  style: TextStyle(fontSize: 12, color: _landingMuted))),
        ]),
      ]);

      return Column(children: [
        _section(
            Row(children: [
              Image.asset('assets/images/circum_wordmark.png',
                  width: small ? 106 : 134, height: 32, fit: BoxFit.contain),
              const Spacer(),
              if (!small) ...[
                _link('Business', '/send/business', onBusiness),
                _link('Health+', '/send/health', onHealthPlus),
                if (wide) _link('Rider', '/rider', onRider),
              ],
              if (small)
                PopupMenuButton<String>(
                  tooltip: 'Explore Circum',
                  icon: const Icon(Icons.menu, color: _landingInk),
                  color: Colors.white,
                  onSelected: (path) => unawaited(launchUrl(
                      _CircumWebsiteAppState._canonicalWebUri(path),
                      webOnlyWindowName: '_self')),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: '/send/business',
                        child: Text('Business',
                            style: TextStyle(color: _landingInk))),
                    PopupMenuItem(
                        value: '/send/health',
                        child: Text('Health+',
                            style: TextStyle(color: _landingInk))),
                    PopupMenuItem(
                        value: '/gifts',
                        child: Text('Gifts',
                            style: TextStyle(color: _landingInk))),
                    PopupMenuItem(
                        value: '/rider',
                        child: Text('Become a Rider',
                            style: TextStyle(color: _landingInk))),
                  ],
                ),
              _link(small ? 'Send' : 'Send a parcel', '/send', onStart,
                  primary: true),
            ]),
            vertical: 20),
        _section(
          wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(flex: 10, child: intro),
                  const SizedBox(width: 54),
                  const Expanded(flex: 11, child: _ParcelJourneyVisual()),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  intro,
                  const SizedBox(height: 42),
                  const _ParcelJourneyVisual(),
                ]),
          vertical: small ? 36 : 62,
        ),
        _section(
            Container(
              padding: const EdgeInsets.symmetric(vertical: 25),
              decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(color: Color(0xffdce1dc)),
                      bottom: BorderSide(color: Color(0xffdce1dc)))),
              child: Wrap(
                  spacing: wide ? 100 : 30,
                  runSpacing: 22,
                  children: const [
                    _LandingPromise(
                        icon: Icons.receipt_long_outlined,
                        title: 'Clear price before payment'),
                    _LandingPromise(
                        icon: Icons.route_outlined,
                        title: 'Live delivery progress'),
                    _LandingPromise(
                        icon: Icons.verified_user_outlined,
                        title: 'PIN-verified handovers'),
                  ]),
            ),
            vertical: 12),
        _section(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _eyebrow('ONE CIRCUM. MORE POSSIBILITIES.'),
          const SizedBox(height: 22),
          Text('For the everyday.\nAnd the extraordinary.',
              style: TextStyle(
                  color: _landingInk,
                  fontSize: small ? 36 : 52,
                  height: 1.12,
                  letterSpacing: -1.7,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 36),
          _service(
              '01',
              'Personal deliveries',
              'A forgotten essential. An important document. A parcel that needs to get there.',
              'London & surrounding areas',
              '/send',
              onStart,
              Icons.inventory_2_outlined,
              wide),
          if (onGifts != null)
            _service(
                '02',
                'Gifts by Circum',
                'Make someone’s day. Thoughtful gifts, sent with care.',
                'UK-wide gifting',
                '/gifts',
                onGifts!,
                Icons.card_giftcard_outlined,
                wide),
          _service(
              '03',
              'Health+',
              'Prescription and healthcare pickups, with protected handovers.',
              'London',
              '/send/health',
              onHealthPlus,
              Icons.health_and_safety_outlined,
              wide),
          _service(
              '04',
              'Built for business',
              'Keep documents, packages and important deliveries moving with your working day.',
              'London & surrounding areas',
              '/send/business',
              onBusiness,
              Icons.business_center_outlined,
              wide),
        ])),
        _section(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _eyebrow('FROM YOUR DOOR TO THEIRS.'),
              const SizedBox(height: 22),
              Text('A simple way to send.',
                  style: TextStyle(
                      color: _landingInk,
                      fontSize: small ? 36 : 50,
                      height: 1.1,
                      letterSpacing: -1.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 42),
              LayoutBuilder(builder: (_, box) {
                final cards = [
                  _step('1', 'Tell us what’s moving.',
                      'Add your pickup, destination and parcel details. Get guidance from IRIS when you need it.'),
                  _step('2', 'Review. Then book.',
                      'See your delivery details and price before payment. Send now or choose a collection for later.'),
                  _step('3', 'Follow every handover.',
                      'Track delivery progress and stay connected through secure chat, all the way to your recipient.'),
                ];
                return box.maxWidth >= 800
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            for (var i = 0; i < cards.length; i++) ...[
                              if (i > 0) const SizedBox(width: 48),
                              Expanded(child: cards[i])
                            ]
                          ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            for (var i = 0; i < cards.length; i++) ...[
                              if (i > 0) const SizedBox(height: 34),
                              cards[i]
                            ]
                          ]);
              }),
            ]),
            background: Colors.white),
        _section(LayoutBuilder(builder: (_, box) {
          final heading =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _eyebrow('VANGUARD PROTECTION', color: const Color(0xff9fd0bd)),
            const SizedBox(height: 23),
            Text('Important things\ndeserve extra care.',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: small ? 36 : 48,
                    height: 1.13,
                    letterSpacing: -1.6,
                    fontWeight: FontWeight.w700)),
          ]);
          final detail =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.verified_user_outlined,
                size: 38, color: Color(0xff9fd0bd)),
            const SizedBox(height: 20),
            const Text(
                'Collection and receiver PIN verification help keep protected deliveries in the right hands. Circum assigns your rider. See what Vanguard adds to your delivery.',
                style: TextStyle(
                    color: Color(0xffd2dfd9), fontSize: 18, height: 1.65)),
            const SizedBox(height: 16),
            const Text('Enhanced Custody Tracking · Priority Support · Priority Dispute Review',
              style: TextStyle(color: Color(0xff9fd0bd), fontSize: 12, height: 1.7)),
            const SizedBox(height: 16),
            const Text('Add Vanguard for £1.99',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            _link('Explore Vanguard ↗', '/vanguard', onVanguard, inverse: true),
          ]);
          return box.maxWidth >= 800
              ? Row(children: [
                  Expanded(flex: 6, child: heading),
                  const SizedBox(width: 70),
                  Expanded(flex: 4, child: detail)
                ])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 34), detail]);
        }), background: _landingInk),
        _section(LayoutBuilder(builder: (_, box) {
          final message =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _eyebrow('YOUR NEXT MOVE.'),
            const SizedBox(height: 18),
            Text('Ready when you are.',
                style: TextStyle(
                    color: _landingInk,
                    fontSize: small ? 36 : 52,
                    letterSpacing: -1.8,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            const Text('Send something important. Or help someone else do it.',
                style:
                    TextStyle(color: _landingMuted, fontSize: 18, height: 1.5)),
          ]);
          final actions = Wrap(spacing: 10, runSpacing: 10, children: [
            _link('Send a parcel', '/send', onStart, primary: true),
            _link('Become a Rider ↗', '/rider', onRider),
          ]);
          return box.maxWidth >= 1000
              ? Row(children: [Expanded(child: message), actions])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [message, const SizedBox(height: 28), actions]);
        })),
      ]);
    });
  }

  Widget _service(
      String number,
      String title,
      String description,
      String coverage,
      String path,
      VoidCallback action,
      IconData icon,
      bool wide) {
    final content =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              color: _landingInk,
              fontSize: 26,
              letterSpacing: -0.7,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Text(description,
          style:
              const TextStyle(color: _landingMuted, fontSize: 16, height: 1.5)),
      const SizedBox(height: 14),
      Text(coverage,
          style: const TextStyle(
              color: _landingBlue, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xffdce1dc)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (wide) ...[
          Text(number,
              style: const TextStyle(color: _landingMuted, fontSize: 13)),
          const SizedBox(width: 36)
        ],
        Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: const Color(0xffedf1e9),
                borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: _landingInk, size: 27)),
        const SizedBox(width: 22),
        Expanded(child: content),
        const SizedBox(width: 12),
        Link(
            uri: _CircumWebsiteAppState._canonicalWebUri(path),
            target: LinkTarget.self,
            builder: (_, followLink) => IconButton(
                tooltip: 'Explore $title',
                onPressed: followLink ?? action,
                icon: const Icon(Icons.north_east, color: _landingInk))),
      ]),
    );
  }

  Widget _step(String number, String title, String description) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                border: Border.all(color: const Color(0xffd9dfd8)),
                shape: BoxShape.circle),
            child: Text(number,
                style: const TextStyle(
                    color: _landingBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w700))),
        const SizedBox(height: 22),
        Text(title,
            style: const TextStyle(
                color: _landingInk,
                fontSize: 23,
                letterSpacing: -0.6,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(description,
            style: const TextStyle(
                color: _landingMuted, fontSize: 16, height: 1.7)),
      ]);
}

class _LandingPromise extends StatelessWidget {
  final IconData icon;
  final String title;
  const _LandingPromise({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 23, color: _landingInk),
        const SizedBox(width: 12),
        Text(title,
            style: const TextStyle(
                color: _landingInk, fontSize: 14, fontWeight: FontWeight.w600)),
      ]);
}

class _ParcelJourneyVisual extends StatelessWidget {
  const _ParcelJourneyVisual();
  @override
  Widget build(BuildContext context) => Semantics(
        label:
            'Illustration of a parcel journey from collection to handover. This is a preview, not a live delivery.',
        child: Container(
          height: MediaQuery.sizeOf(context).width < 600 ? 440 : 540,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: const Color(0xffe8efeb),
              borderRadius: BorderRadius.circular(24)),
          child: Stack(children: [
            const Positioned.fill(
                child: CustomPaint(painter: _ParcelRoutePainter())),
            const Positioned(
                top: 24,
                left: 24,
                child: Text('YOUR CITY. CONNECTED.',
                    style: TextStyle(
                        color: _landingInk,
                        letterSpacing: 1.8,
                        fontSize: 10,
                        fontWeight: FontWeight.w700))),
            const Positioned(
                top: 24,
                right: 24,
                child: Text('LONDON',
                    style: TextStyle(
                        color: _landingMuted,
                        letterSpacing: 1.6,
                        fontSize: 10))),
            Positioned(
                top: 105,
                left: 26,
                child: _mapLabel(
                    Icons.radio_button_checked, 'Collection', _landingInk)),
            Positioned(
                top: 224,
                right: 24,
                child: _mapLabel(Icons.location_on, 'Handover', _landingBlue)),
            Positioned(
                left: 22,
                right: 22,
                bottom: 22,
                child: Container(
                  padding: const EdgeInsets.all(23),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: _landingInk.withValues(alpha: 0.08),
                            blurRadius: 30,
                            offset: const Offset(0, 12))
                      ]),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.inventory_2_outlined,
                              color: _landingBlue, size: 26),
                          SizedBox(width: 12),
                          Expanded(
                              child: Text('Every step, in sight.',
                                  style: TextStyle(
                                      color: _landingInk,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.4))),
                        ]),
                        const SizedBox(height: 20),
                        const Row(children: [
                          Icon(Icons.check_circle,
                              color: _landingBlue, size: 17),
                          Expanded(
                              child:
                                  Divider(color: _landingBlue, thickness: 2)),
                          Icon(Icons.radio_button_checked,
                              color: _landingBlue, size: 17),
                          Expanded(
                              child: Divider(
                                  color: Color(0xffdde4df), thickness: 2)),
                          Icon(Icons.radio_button_unchecked,
                              color: Color(0xffadb9b1), size: 17),
                        ]),
                        const SizedBox(height: 9),
                        const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Collected',
                                  style: TextStyle(
                                      color: _landingMuted, fontSize: 11)),
                              Text('In transit',
                                  style: TextStyle(
                                      color: _landingBlue,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                              Text('Delivered',
                                  style: TextStyle(
                                      color: _landingMuted, fontSize: 11)),
                            ]),
                        const SizedBox(height: 20),
                        const Text('A clear view from pickup to recipient.',
                            style:
                                TextStyle(color: _landingMuted, fontSize: 13)),
                        const SizedBox(height: 12),
                        const Text('ILLUSTRATIVE DELIVERY PREVIEW',
                            style: TextStyle(
                                color: _landingMuted,
                                fontSize: 8,
                                letterSpacing: 1.2)),
                      ]),
                )),
          ]),
        ),
      );

  Widget _mapLabel(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  color: _landingInk,
                  fontSize: 12,
                  fontWeight: FontWeight.w600))
        ]),
      );
}

class _ParcelRoutePainter extends CustomPainter {
  const _ParcelRoutePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final streets = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..strokeWidth = 7;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.24);
    for (double x = -size.width; x <= size.width; x += 68) {
      canvas.drawLine(Offset(x, -size.height), Offset(x, size.height), streets);
    }
    for (double y = -size.height; y <= size.height; y += 58) {
      canvas.drawLine(Offset(-size.width, y), Offset(size.width, y), streets);
    }
    canvas.restore();
    final river = Path()
      ..moveTo(-20, size.height * 0.46)
      ..cubicTo(size.width * 0.27, size.height * 0.27, size.width * 0.28,
          size.height * 0.57, size.width * 0.53, size.height * 0.43)
      ..cubicTo(size.width * 0.74, size.height * 0.32, size.width * 0.72,
          size.height * 0.25, size.width + 20, size.height * 0.31);
    canvas.drawPath(
        river,
        Paint()
          ..color = const Color(0xffc8dcf3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 36
          ..strokeCap = StrokeCap.round);
    final route = Path()
      ..moveTo(size.width * 0.16, 155)
      ..lineTo(size.width * 0.16, 184)
      ..lineTo(size.width * 0.4, 184)
      ..quadraticBezierTo(size.width * 0.46, 184, size.width * 0.46, 216)
      ..lineTo(size.width * 0.46, 265)
      ..lineTo(size.width * 0.82, 265);
    canvas.drawPath(
        route,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(
        route,
        Paint()
          ..color = _landingBlue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeJoin = StrokeJoin.round);
    for (final point in [
      Offset(size.width * 0.16, 155),
      Offset(size.width * 0.82, 265)
    ]) {
      canvas.drawCircle(point, 9, Paint()..color = Colors.white);
      canvas.drawCircle(point, 5, Paint()..color = _landingBlue);
    }
  }

  @override
  bool shouldRepaint(covariant _ParcelRoutePainter oldDelegate) => false;
}

class _StoreDownloads extends StatelessWidget {
  const _StoreDownloads();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 38, bottom: 30),
        child: LayoutBuilder(builder: (_, box) {
          final apps = [
            _app(
                'Circum',
                'Send, track and stay connected.',
                'https://apps.apple.com/gb/app/circum/id6463644284',
                'https://play.google.com/store/apps/details?id=com.circum.app'),
            _app(
                'Circum Rider',
                'Deliver with Circum.',
                'https://apps.apple.com/gb/app/circum-rider/id6476303139',
                'https://play.google.com/store/apps/details?id=com.circum.rider'),
          ];
          return box.maxWidth >= 850
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: apps[0]),
                  const SizedBox(width: 48),
                  Expanded(child: apps[1])
                ])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [apps[0], const SizedBox(height: 32), apps[1]]);
        }),
      );
  Widget _app(String title, String description, String apple, String google) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Download $title',
            style: const TextStyle(
                color: _landingInk, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(description,
            style: const TextStyle(color: _landingMuted, fontSize: 14)),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _storeLink('App Store', 'Download on the', Icons.apple, apple, title),
          _storeLink('Google Play', 'Get it on', Icons.play_arrow_rounded,
              google, title),
        ]),
      ]);
  Widget _storeLink(String store, String caption, IconData icon, String url,
          String app) =>
      Link(
        uri: Uri.parse(url),
        target: LinkTarget.blank,
        builder: (_, followLink) => Semantics(
          label: 'Download $app on $store, opens in a new tab',
          child: TextButton(
            onPressed: followLink ??
                () => unawaited(launchUrl(Uri.parse(url),
                    mode: LaunchMode.externalApplication)),
            style: TextButton.styleFrom(
                backgroundColor: _landingInk,
                foregroundColor: Colors.white,
                minimumSize: const Size(156, 58),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 28),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(caption,
                    style: const TextStyle(fontSize: 9, color: Colors.white)),
                Text(store,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white))
              ])
            ]),
          ),
        ),
      );
}
