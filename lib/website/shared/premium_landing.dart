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
          {Color background = _landingPaper,
          Gradient? gradient,
          double vertical = 80}) =>
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
            color: gradient == null ? background : null, gradient: gradient),
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
      final handoverPhoto = ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 2.5,
          child: Image.network(
            Uri.base.resolve('/images/parcel-handover.jpg').toString(),
            fit: BoxFit.cover,
            semanticLabel:
                'Illustration of a thoughtful parcel handover at a doorstep',
            errorBuilder: (_, __, ___) => const ColoredBox(
                color: Color(0xffe1eee9),
                child: Center(
                    child: Icon(Icons.inventory_2_outlined,
                        color: _landingBlue, size: 44))),
          ),
        ),
      );
      final intro =
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ShaderMask(
          shaderCallback: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xff007d87),
              Color(0xff2455f5),
              Color(0xff7937c8),
              Color(0xffc32e79)
            ],
            stops: [0, 0.35, 0.7, 1],
          ).createShader,
          blendMode: BlendMode.srcIn,
          child: Text('Move what\nmatters.'.toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: headlineSize,
                height: 0.95,
                letterSpacing: small ? -1 : 1.6,
                fontFamily: 'D-DIN-Bold',
                fontWeight: FontWeight.w400,
              )),
        ),
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
          _link('Send a parcel', '/send', onStart),
          if (onGifts != null) _link('Explore Gifts ↗', '/gifts', onGifts!),
        ]),
        const SizedBox(height: 24),
        if (wide) handoverPhoto,
        const SizedBox(height: 24),
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
              if (wide) ...[
                _link('Business', '/send/business', onBusiness),
                _link('Health+', '/send/health', onHealthPlus),
                if (wide) _link('Rider', '/rider', onRider),
              ],
              if (!small) ...[
                _link('Help', '/support', onStart),
                _link('Account', '/send/profile', onStart),
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
                        value: '/support',
                        child:
                            Text('Help', style: TextStyle(color: _landingInk))),
                    PopupMenuItem(
                        value: '/send/profile',
                        child: Text('Account',
                            style: TextStyle(color: _landingInk))),
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
                  const Expanded(flex: 11, child: _LandingBookingPanel()),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  intro,
                  const SizedBox(height: 42),
                  const _LandingBookingPanel(),
                  const SizedBox(height: 28),
                  handoverPhoto,
                ]),
          vertical: small ? 36 : 62,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffe2f2ff), Color(0xffeee5fb), Color(0xffffe7ef)],
          ),
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
          ShaderMask(
            shaderCallback: _landingGiftsSheen.createShader,
            blendMode: BlendMode.srcIn,
            child: Text(
                'For the everyday.\nAnd the extraordinary.'.toUpperCase(),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: small ? 36 : 48,
                    height: 1.12,
                    letterSpacing: small ? 0.72 : 0.96,
                    fontFamily: 'D-DIN-Bold',
                    fontWeight: FontWeight.w400)),
          ),
          const SizedBox(height: 36),
          LayoutBuilder(builder: (_, box) {
            final cards = <Widget>[
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
                    'Delivery around the world',
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
            ];
            final columns = box.maxWidth >= 1000
                ? 4
                : box.maxWidth >= 620
                    ? 2
                    : 1;
            final width = (box.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(spacing: 16, runSpacing: 16, children: [
              for (final card in cards) SizedBox(width: width, child: card),
            ]);
          }),
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
                    ? IntrinsicHeight(
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                            for (var i = 0; i < cards.length; i++) ...[
                              if (i > 0) const SizedBox(width: 48),
                              Expanded(child: cards[i])
                            ]
                          ]))
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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xffdef5f1), Color(0xffe7ebff), Color(0xffefe3fa)],
            )),
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
            _eyebrow('YOUR NEXT MOVE.', color: const Color(0xffc9f7ef)),
            const SizedBox(height: 18),
            Text('Ready when you are.'.toUpperCase(),
                style: TextStyle(
                    color: const Color(0xffffd56a),
                    fontSize: small ? 36 : 48,
                    letterSpacing: small ? 0.72 : 0.96,
                    fontFamily: 'D-DIN-Bold',
                    fontWeight: FontWeight.w400)),
            const SizedBox(height: 18),
            const Text('Send something important. Or help someone else do it.',
                style:
                    TextStyle(color: Colors.white, fontSize: 16, height: 1.5)),
          ]);
          final actions = Wrap(spacing: 10, runSpacing: 10, children: [
            _link('Send a parcel', '/send', onStart, primary: true),
            _link('Earn as a Circum Rider', '/rider', onRider, inverse: true),
          ]);
          return box.maxWidth >= 1000
              ? Row(children: [Expanded(child: message), actions])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [message, const SizedBox(height: 28), actions]);
        }),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff006f78), Color(0xff1749a5), Color(0xff652ba0)],
              stops: [0, 0.48, 1],
            )),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: isGifts ? null : iconColor.withValues(alpha: 0.06),
          gradient: isGifts ? _landingGiftsPearl : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xffdce1dc))),
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

  Widget _step(String number, String title, String description) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: switch (number) {
            '1' => const Color(0xffdbeafe),
            '2' => const Color(0xffe9ddfa),
            _ => const Color(0xfffbe0ea),
          },
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                  color: _landingInk, fontSize: 16, height: 1.7)),
        ]),
      );
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

class _LandingBookingPanel extends StatefulWidget {
  const _LandingBookingPanel();

  @override
  State<_LandingBookingPanel> createState() => _LandingBookingPanelState();
}

class _LandingBookingPanelState extends State<_LandingBookingPanel> {
  final _form = GlobalKey<FormState>();
  final _pickup = TextEditingController();
  final _destination = TextEditingController();
  String? _error;
  bool _opening = false;

  @override
  void dispose() {
    _pickup.dispose();
    _destination.dispose();
    super.dispose();
  }

  void _continue() {
    if (_opening || !_form.currentState!.validate()) return;
    final draft = LandingBookingDraft(
        _pickup.text.trim(), _destination.text.trim(), DateTime.now());
    if (!saveLandingBookingDraft(draft)) {
      setState(() => _error =
          'Your browser could not save these details. Open the booking page to enter them there.');
      return;
    }
    setState(() => _opening = true);
    web.window.location
        .assign(Uri.base.resolve('/send?start=delivery').toString());
  }

  Widget _addressField(
          String label, TextEditingController controller, IconData icon,
          {bool last = false}) =>
      TextFormField(
        controller: controller,
        maxLength: 300,
        textInputAction: last ? TextInputAction.go : TextInputAction.next,
        onFieldSubmitted: last ? (_) => _continue() : null,
        style: const TextStyle(color: _landingInk, fontSize: 16),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Enter ${label.toLowerCase()}.'
            : null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xff42534e)),
          prefixIcon: Icon(icon, color: _landingBlue, size: 21),
          filled: true,
          fillColor: const Color(0xfff1f4f8),
          counterText: '',
          contentPadding:
              const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xffdce1e8))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xffdce1e8))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _landingBlue, width: 2)),
          errorStyle: const TextStyle(color: Color(0xffa21b38), fontSize: 13),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        padding:
            EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 24 : 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xffe0e5ed)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x14243b70), blurRadius: 40, offset: Offset(0, 14))
          ],
        ),
        child: Form(
            key: _form,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your delivery starts here.',
                  style: TextStyle(
                      fontFamily: 'D-DIN-Bold',
                      fontSize: 32,
                      height: 1.1,
                      color: _landingInk)),
              const SizedBox(height: 12),
              const Text('Where are we collecting and delivering?',
                  style: TextStyle(
                      color: _landingMuted, fontSize: 16, height: 1.5)),
              const SizedBox(height: 26),
              _addressField(
                  'Pickup address or postcode', _pickup, Icons.trip_origin),
              const SizedBox(height: 16),
              _addressField('Delivery address or postcode', _destination,
                  Icons.location_on_outlined,
                  last: true),
              const SizedBox(height: 24),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _opening ? null : _continue,
                    icon: const Icon(Icons.arrow_forward, size: 20),
                    label: Text(_opening
                        ? 'Opening your booking…'
                        : 'See delivery price'),
                    style: FilledButton.styleFrom(
                        backgroundColor: _landingBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 22),
                        textStyle: const TextStyle(
                            fontFamily: 'D-DIN-Bold', fontSize: 17),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                  )),
              const SizedBox(height: 16),
              const Text(
                  'Sign in and confirm your addresses and parcel details to see your price before payment.',
                  style: TextStyle(
                      color: _landingMuted, fontSize: 14, height: 1.5)),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        color: Color(0xffa21b38), fontSize: 14)),
                TextButton(
                    onPressed: () => web.window.location
                        .assign(Uri.base.resolve('/send').toString()),
                    child: const Text('Open booking page')),
              ],
              const SizedBox(height: 22),
              const Divider(color: Color(0xffe0e5ed)),
              const SizedBox(height: 12),
              const Row(children: [
                Icon(Icons.verified_user_outlined,
                    color: _landingBlue, size: 20),
                SizedBox(width: 10),
                Expanded(
                    child: Text('Secure handovers. Clear delivery progress.',
                        style: TextStyle(color: _landingInk, fontSize: 14)))
              ]),
            ])),
      );
}
