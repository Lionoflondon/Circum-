part of 'circum_website_app.dart';

const _landingInk = Color(0xff10231f);
const _landingBlue = Color(0xff2455f5);
const _landingVanguard = Color(0xff2563eb);
const _landingHealth = Color(0xff064e3b);
const _landingGiftsSheen = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xff176b9a),
    Color(0xff248c78),
    Color(0xff7851a9),
    Color(0xffb24c82)
  ],
);
const _landingGiftsPearl = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xffe1f4ed),
    Color(0xffe4efff),
    Color(0xfff3e7fa),
    Color(0xffffedf1)
  ],
  stops: [0, 0.34, 0.68, 1],
);
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
        onPressed: kIsWeb
            ? () => web.window.location.assign(
                _CircumWebsiteAppState._canonicalWebUri(path).toString())
            : action,
        style: TextButton.styleFrom(
          backgroundColor: primary ? _landingBlue : Colors.transparent,
          foregroundColor: primary || inverse ? Colors.white : _landingInk,
          padding:
              EdgeInsets.symmetric(horizontal: primary ? 24 : 14, vertical: 20),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
              fontSize: 13,
              letterSpacing: 1.17,
              fontFamily: 'D-DIN-Bold',
              fontWeight: FontWeight.w400),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label.toUpperCase()),
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
            fontFamily: 'D-DIN-Bold',
            fontWeight: FontWeight.w400),
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
      final headlineSize = small ? 60.0 : 80.0;
      final intro =
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Move what\n'.toUpperCase()),
              TextSpan(
                  text: 'matters.'.toUpperCase(),
                  style: const TextStyle(color: _landingBlue)),
            ]),
            style: TextStyle(
              color: _landingInk,
              fontSize: headlineSize,
              height: 0.95,
              letterSpacing: small ? -1 : 1.6,
              fontFamily: 'D-DIN-Bold',
              fontWeight: FontWeight.w400,
            )),
        const SizedBox(height: 28),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 445),
          child: const Text(
              'From everyday parcels to important handovers. Book a delivery, see the price, and follow its journey with Circum.',
              style:
                  TextStyle(color: _landingMuted, fontSize: 16, height: 1.5)),
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
              _link(small ? 'Send' : 'Send a Parcel', '/send', onStart,
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
          Text('For the everyday.\nAnd the extraordinary.'.toUpperCase(),
              style: TextStyle(
                  color: _landingInk,
                  fontSize: small ? 36 : 48,
                  height: 1.12,
                  letterSpacing: small ? 0.72 : 0.96,
                  fontFamily: 'D-DIN-Bold',
                  fontWeight: FontWeight.w400)),
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
                'Gifts',
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
              Text('A simple way to send.'.toUpperCase(),
                  style: TextStyle(
                      color: _landingInk,
                      fontSize: small ? 36 : 48,
                      height: 1.1,
                      letterSpacing: small ? 0.72 : 0.96,
                      fontFamily: 'D-DIN-Bold',
                      fontWeight: FontWeight.w400)),
              const SizedBox(height: 42),
              LayoutBuilder(builder: (_, box) {
                final cards = [
                  _step('1', 'Tell us what’s moving.',
                      'Add your pickup, destination and parcel details.'),
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
          final message =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _eyebrow('MEET IRIS', color: const Color(0xff67e8f9)),
            const SizedBox(height: 22),
            Text('A little intelligence.\nA lot of confidence.'.toUpperCase(),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: small ? 36 : 48,
                    height: 1.12,
                    letterSpacing: small ? 0.72 : 0.96,
                    fontFamily: 'D-DIN-Bold',
                    fontWeight: FontWeight.w400)),
            const SizedBox(height: 24),
            const Text(
                'IRIS brings your parcel details and photos together to help assess weight and handling before you book.',
                style: TextStyle(
                    color: Color(0xffdbeafe), fontSize: 16, height: 1.5)),
            const SizedBox(height: 22),
            const Wrap(spacing: 18, runSpacing: 12, children: [
              Text('Parcel details',
                  style: TextStyle(color: Color(0xff67e8f9))),
              Text('Photo insights',
                  style: TextStyle(color: Color(0xffc4b5fd))),
              Text('Handling guidance',
                  style: TextStyle(color: Color(0xfff9a8d4))),
            ]),
            const SizedBox(height: 20),
            _link('Send with Circum ↗', '/send', onStart, inverse: true),
          ]);
          const visual = _IrisLandingVisual();
          return box.maxWidth >= 800
              ? Row(children: [
                  Expanded(flex: 6, child: message),
                  const SizedBox(width: 50),
                  const Expanded(flex: 4, child: visual),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  message,
                  const SizedBox(height: 36),
                  visual,
                ]);
        }), background: const Color(0xff081530)),
        _section(LayoutBuilder(builder: (_, box) {
          final heading =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _eyebrow('VANGUARD PROTECTION', color: Colors.white),
            const SizedBox(height: 23),
            Text('Important things\ndeserve extra care.'.toUpperCase(),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: small ? 36 : 48,
                    height: 1.13,
                    letterSpacing: small ? 0.72 : 0.96,
                    fontFamily: 'D-DIN-Bold',
                    fontWeight: FontWeight.w400)),
          ]);
          final detail =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.verified_user_outlined,
                size: 38, color: Colors.white),
            const SizedBox(height: 20),
            const Text(
                'Collection and receiver PIN verification help keep protected deliveries in the right hands. Circum assigns your rider. See what Vanguard adds to your delivery.',
                style:
                    TextStyle(color: Colors.white, fontSize: 16, height: 1.5)),
            const SizedBox(height: 16),
            const Text(
                'Enhanced Custody Tracking · Priority Support · Priority Dispute Review',
                style:
                    TextStyle(color: Colors.white, fontSize: 12, height: 1.7)),
            const SizedBox(height: 16),
            const Text('Add Vanguard for £1.99',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'D-DIN-Bold',
                    fontWeight: FontWeight.w400)),
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
        }), background: _landingVanguard),
        _section(LayoutBuilder(builder: (_, box) {
          final message =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _eyebrow('YOUR NEXT MOVE.'),
            const SizedBox(height: 18),
            Text('Ready when you are.'.toUpperCase(),
                style: TextStyle(
                    color: _landingInk,
                    fontSize: small ? 36 : 48,
                    letterSpacing: small ? 0.72 : 0.96,
                    fontFamily: 'D-DIN-Bold',
                    fontWeight: FontWeight.w400)),
            const SizedBox(height: 18),
            const Text('Send something important. Or help someone else do it.',
                style:
                    TextStyle(color: _landingMuted, fontSize: 16, height: 1.5)),
          ]);
          final actions = Wrap(spacing: 10, runSpacing: 10, children: [
            _link('Send a parcel', '/send', onStart, primary: true),
            _link('Earn as a Circum Rider', '/rider', onRider),
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
    final iconColor = switch (path) {
      '/send/health' => _landingHealth,
      '/gifts' => const Color(0xff7851a9),
      '/send/business' => const Color(0xffb96508),
      _ => _landingBlue,
    };
    final isGifts = path == '/gifts';
    Widget serviceIcon(double size) {
      final glyph = Icon(icon, color: iconColor, size: size);
      return isGifts
          ? ShaderMask(
              shaderCallback: _landingGiftsSheen.createShader,
              blendMode: BlendMode.srcIn,
              child: glyph,
            )
          : glyph;
    }

    final content =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              color: _landingInk,
              fontSize: 26,
              letterSpacing: -0.7,
              fontFamily: 'D-DIN-Bold',
              fontWeight: FontWeight.w400)),
      const SizedBox(height: 10),
      Text(description,
          style:
              const TextStyle(color: _landingMuted, fontSize: 16, height: 1.5)),
      const SizedBox(height: 14),
      Text(coverage,
          style: TextStyle(
              color: path == '/send/health' ? _landingHealth : _landingBlue,
              fontSize: 12,
              fontFamily: 'D-DIN-Bold',
              fontWeight: FontWeight.w400)),
    ]);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
          color: isGifts ? null : iconColor.withValues(alpha: 0.06),
          gradient: isGifts ? _landingGiftsPearl : null,
          border: const Border(top: BorderSide(color: Color(0xffdce1dc)))),
      child: LayoutBuilder(builder: (_, box) {
        final actionLink = Link(
          uri: _CircumWebsiteAppState._canonicalWebUri(path),
          target: LinkTarget.self,
          builder: (_, followLink) => IconButton(
            tooltip: 'Explore $title',
            onPressed: kIsWeb
                ? () => web.window.location.assign(
                    _CircumWebsiteAppState._canonicalWebUri(path).toString())
                : action,
            icon: const Icon(Icons.north_east, color: _landingInk),
          ),
        );
        if (box.maxWidth < 550) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  serviceIcon(28),
                  const Spacer(),
                  actionLink,
                ]),
                const SizedBox(height: 12),
                content,
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (wide) ...[
            Text(number,
                style: const TextStyle(color: _landingMuted, fontSize: 13)),
            const SizedBox(width: 36)
          ],
          Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: isGifts ? null : iconColor.withValues(alpha: 0.12),
                  gradient: isGifts ? _landingGiftsPearl : null,
                  borderRadius: BorderRadius.circular(16)),
              child: serviceIcon(27)),
          const SizedBox(width: 22),
          Expanded(child: content),
          const SizedBox(width: 12),
          actionLink,
        ]);
      }),
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
                    fontFamily: 'D-DIN-Bold',
                    fontWeight: FontWeight.w400))),
        const SizedBox(height: 22),
        Text(title,
            style: const TextStyle(
                color: _landingInk,
                fontSize: 23,
                letterSpacing: -0.6,
                fontFamily: 'D-DIN-Bold',
                fontWeight: FontWeight.w400)),
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
                color: _landingInk,
                fontSize: 14,
                fontFamily: 'D-DIN-Bold',
                fontWeight: FontWeight.w400)),
      ]);
}

class _IrisLandingVisual extends StatelessWidget {
  const _IrisLandingVisual();

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'IRIS parcel intelligence',
        child: SizedBox(
          height: 290,
          child: Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.35, -0.4),
                  colors: [
                    Color(0xffe0fbff),
                    Color(0xff38bdf8),
                    Color(0xff6366f1),
                    Color(0xffd946ef),
                    Color(0xff172554)
                  ],
                  stops: [0, 0.25, 0.55, 0.8, 1],
                ),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xff38bdf8).withValues(alpha: 0.25),
                      blurRadius: 70,
                      spreadRadius: 10),
                  BoxShadow(
                      color: const Color(0xffd946ef).withValues(alpha: 0.2),
                      blurRadius: 55),
                ],
              ),
              child: const Center(
                child: Text('IRIS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        letterSpacing: 8,
                        fontFamily: 'D-DIN-Bold',
                        fontWeight: FontWeight.w400)),
              ),
            ),
          ),
        ),
      );
}

class _ParcelJourneyVisual extends StatelessWidget {
  const _ParcelJourneyVisual();
  @override
  Widget build(BuildContext context) => Semantics(
        label:
            'Illustration of a parcel journey from collection to handover. This is a preview, not a live delivery.',
        child: Container(
          height: 540,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xffb9e8ff),
                    Color(0xffd1cbff),
                    Color(0xffffd2e2)
                  ]),
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
                        fontFamily: 'D-DIN-Bold',
                        fontWeight: FontWeight.w400))),
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
                                      fontFamily: 'D-DIN-Bold',
                                      fontWeight: FontWeight.w400,
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
                                      fontFamily: 'D-DIN-Bold',
                                      fontWeight: FontWeight.w400)),
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
                  fontFamily: 'D-DIN-Bold',
                  fontWeight: FontWeight.w400))
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
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.only(top: 38, bottom: 30),
        child: _app(
          'Circum',
          'Send, track and stay connected.',
          'https://apps.apple.com/gb/app/circum/id6463644284',
          'https://play.google.com/store/apps/details?id=com.circum.app',
        ),
      );
  Widget _app(String title, String description, String apple, String google) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Download $title',
            style: const TextStyle(
                color: _landingInk,
                fontSize: 20,
                fontFamily: 'D-DIN-Bold',
                fontWeight: FontWeight.w400)),
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
        target: LinkTarget.self,
        builder: (_, followLink) => Semantics(
          label: 'Download $app on $store',
          child: TextButton(
            onPressed: kIsWeb
                ? () => web.window.location.assign(url)
                : () => unawaited(launchUrl(Uri.parse(url),
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
              if (store == 'Google Play')
                const CustomPaint(
                    size: Size(26, 28), painter: _PlayIconPainter())
              else
                Icon(icon, size: 28),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(caption,
                    style: const TextStyle(fontSize: 9, color: Colors.white)),
                Text(store,
                    style: const TextStyle(
                        fontSize: 17,
                        fontFamily: 'D-DIN-Bold',
                        fontWeight: FontWeight.w400,
                        color: Colors.white))
              ])
            ]),
          ),
        ),
      );
}

class _PlayIconPainter extends CustomPainter {
  const _PlayIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    void polygon(Color color, List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path..close(), Paint()..color = color);
    }

    final top = Offset.zero;
    final bottom = Offset(0, size.height);
    final center = Offset(size.width * 0.54, size.height * 0.5);
    final upper = Offset(size.width * 0.76, size.height * 0.36);
    final lower = Offset(size.width * 0.76, size.height * 0.64);
    final tip = Offset(size.width, size.height * 0.5);
    polygon(const Color(0xff4285f4), [top, center, bottom]);
    polygon(const Color(0xff34a853), [top, upper, center]);
    polygon(const Color(0xfffbbc04), [upper, tip, lower, center]);
    polygon(const Color(0xffea4335), [center, lower, bottom]);
  }

  @override
  bool shouldRepaint(covariant _PlayIconPainter oldDelegate) => false;
}
