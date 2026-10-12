import 'package:flutter/material.dart';

/// Informational surface. Booking, prices and verification stay server-owned.
class VanguardLandingPage extends StatefulWidget {
  const VanguardLandingPage(
      {super.key, required this.onBack, required this.onStart});
  final VoidCallback onBack, onStart;

  @override
  State<VanguardLandingPage> createState() => _VanguardLandingPageState();
}

class _VanguardLandingPageState extends State<VanguardLandingPage> {
  static const ink = Color(0xff06172d);
  static const muted = Color(0xff596c85);
  static const paper = Color(0xfff5f9ff);
  static const vanguardBlue = Color(0xff0a84ff);
  int stage = 0;
  final journeyKey = GlobalKey();
  static const stages = [
    (
      'Collection',
      'The right start.',
      'Your collection PIN verifies the handover to your Circum Rider. Share it when your item is ready to be collected.',
      Icons.inventory_2_outlined
    ),
    (
      'In transit',
      'Follow the delivery.',
      'Custody milestones help you follow your item from collection through to its handover.',
      Icons.route_outlined
    ),
    (
      'Handover',
      'The right hands.',
      'The receiver PIN verifies the final handover. Your recipient shares it when the delivery reaches them.',
      Icons.verified_user_outlined
    ),
  ];

  Text copy(String text,
          {double size = 17, Color color = ink, bool bold = false}) =>
      Text(text,
          style: TextStyle(
              fontFamily: bold ? 'D-DIN-Bold' : 'D-DIN',
              fontSize: size,
              height: 1.35,
              color: color));
  Widget eyebrow(String text, {Color color = muted}) => Text(text,
      style: TextStyle(
          fontFamily: 'D-DIN-Bold',
          fontSize: 12,
          letterSpacing: 2,
          color: color));
  Widget heading(String text, double size, {Color color = ink}) => Text(text,
      style: TextStyle(
          fontFamily: 'D-DIN-Bold',
          fontSize: size,
          height: 1.02,
          letterSpacing: -1.8,
          color: color));
  Widget startButton() => FilledButton.icon(
        onPressed: widget.onStart,
        style: FilledButton.styleFrom(
            backgroundColor: vanguardBlue,
            foregroundColor: ink,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        icon: const Icon(Icons.arrow_outward, size: 18),
        iconAlignment: IconAlignment.end,
        label: const Text('Plan a delivery'),
      );

  @override
  Widget build(BuildContext context) => Theme(
      data: ThemeData(
          brightness: Brightness.light,
          fontFamily: 'D-DIN',
          colorScheme: ColorScheme.fromSeed(
              seedColor: ink, primary: ink, surface: paper)),
      child: DefaultTextStyle(
          style: const TextStyle(fontFamily: 'D-DIN', color: ink),
          child: Scaffold(
              backgroundColor: paper,
              body: SafeArea(
                  child: LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth >= 850;
                final pad = wide ? 48.0 : 24.0;
                Widget section(Widget child,
                        {Color? color, bool compact = false}) =>
                    ColoredBox(
                        color: color ?? paper,
                        child: Center(
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1280),
                                child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: pad,
                                        vertical:
                                            compact ? 32 : (wide ? 72 : 44)),
                                    child: child))));
                return SingleChildScrollView(
                    child: Column(children: [
                  Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1280),
                          child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: pad, vertical: 24),
                              child: Row(children: [
                                Image.asset('assets/images/circum_wordmark.png',
                                    width: 124,
                                    height: 30,
                                    semanticLabel: 'CIRCUM'),
                                const Spacer(),
                                TextButton.icon(
                                    onPressed: widget.onBack,
                                    icon:
                                        const Icon(Icons.arrow_back, size: 16),
                                    label: const Text('Home')),
                              ])))),
                  section(
                      wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                  Expanded(child: hero(wide)),
                                  const SizedBox(width: 54),
                                  Expanded(child: artwork())
                                ])
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  hero(wide),
                                  const SizedBox(height: 36),
                                  artwork()
                                ]),
                      compact: true),
                  section(
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            eyebrow('CARE AT EVERY HANDOVER'),
                            const SizedBox(height: 18),
                            heading('More confidence.\nFrom door to door.',
                                wide ? 48 : 36),
                            const SizedBox(height: 36),
                            LayoutBuilder(builder: (context, c) {
                              final columns = c.maxWidth >= 760;
                              final cards = [
                                benefit(
                                    '01',
                                    Icons.pin_outlined,
                                    'Verified handovers',
                                    'Collection and receiver PINs add a verification step at both ends of the delivery.'),
                                benefit(
                                    '02',
                                    Icons.route_outlined,
                                    'A clearer journey',
                                    'Custody milestones give important deliveries a clearer record from pickup to handover.'),
                                benefit(
                                    '03',
                                    Icons.support_agent_outlined,
                                    'Support that stays close',
                                    'Priority support and dispute review, with trusted Circum Riders prioritised during assignment.'),
                              ];
                              return columns
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                          for (var i = 0;
                                              i < cards.length;
                                              i++) ...[
                                            if (i > 0)
                                              const SizedBox(width: 32),
                                            Expanded(child: cards[i])
                                          ]
                                        ])
                                  : Column(children: [
                                      for (final card in cards)
                                        Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 28),
                                            child: card)
                                    ]);
                            }),
                          ]),
                      color: Colors.white),
                  section(
                      Container(
                          key: journeyKey,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                eyebrow('SEE HOW DELIVERY WORKS',
                                    color: const Color(0xff82c3ff)),
                                const SizedBox(height: 18),
                                heading(
                                    'Three moments.\nOne considered delivery.',
                                    wide ? 48 : 36,
                                    color: paper),
                                const SizedBox(height: 30),
                                Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: List.generate(
                                        3,
                                        (i) => ChoiceChip(
                                            label: Text(
                                                '0${i + 1}  ${stages[i].$1}'),
                                            selected: stage == i,
                                            showCheckmark: false,
                                            selectedColor: vanguardBlue,
                                            backgroundColor:
                                                const Color(0xff102d50),
                                            labelStyle: TextStyle(
                                                color:
                                                    stage == i ? ink : paper),
                                            side: BorderSide(
                                                color: stage == i
                                                    ? vanguardBlue
                                                    : const Color(0xff365779)),
                                            onSelected: (_) =>
                                                setState(() => stage = i)))),
                                const SizedBox(height: 30),
                                AnimatedSwitcher(
                                    duration:
                                        MediaQuery.disableAnimationsOf(context)
                                            ? Duration.zero
                                            : const Duration(milliseconds: 260),
                                    child: Container(
                                        key: ValueKey(stage),
                                        width: double.infinity,
                                        padding: EdgeInsets.all(wide ? 36 : 24),
                                        decoration: BoxDecoration(
                                            color: const Color(0xff102d50),
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            border: Border.all(
                                                color:
                                                    const Color(0xff2b527b))),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(stages[stage].$4,
                                                  color: vanguardBlue,
                                                  size: 34),
                                              const SizedBox(height: 24),
                                              heading(stages[stage].$2,
                                                  wide ? 38 : 30,
                                                  color: paper),
                                              const SizedBox(height: 16),
                                              ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                          maxWidth: 630),
                                                  child: copy(stages[stage].$3,
                                                      color: const Color(
                                                          0xffd7e8fa))),
                                              const SizedBox(height: 28),
                                              Row(
                                                  children: List.generate(
                                                      3,
                                                      (i) => Expanded(
                                                          child: Container(
                                                              height: 4,
                                                              margin:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      right: 8),
                                                              decoration: BoxDecoration(
                                                                  color: i <=
                                                                          stage
                                                                      ? vanguardBlue
                                                                      : const Color(
                                                                          0xff3b5675),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              4)))))),
                                            ]))),
                                const SizedBox(height: 20),
                                copy(
                                    'Circum assigns your rider. Keep each PIN private until the matching handover.',
                                    size: 14,
                                    color: const Color(0xffb7d3f0)),
                              ])),
                      color: ink),
                  section(wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Expanded(child: occasions(wide)),
                              const SizedBox(width: 64),
                              Expanded(child: pricing(wide))
                            ])
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              occasions(wide),
                              const SizedBox(height: 40),
                              pricing(wide)
                            ])),
                  section(
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            eyebrow('BEFORE YOUR DELIVERY'),
                            const SizedBox(height: 18),
                            heading('Clear expectations.\nThoughtful delivery.',
                                wide ? 40 : 32),
                            const SizedBox(height: 20),
                            copy(
                                'Vanguard is not insurance. It does not provide reimbursement, financial cover or guarantees. It adds delivery verification, custody visibility, rider prioritisation and priority support.'),
                            const SizedBox(height: 18),
                            copy(
                                'Pack your item securely and check that it is accepted for delivery. Your booking shows whether Vanguard is optional or required and confirms the final price.',
                                color: muted)
                          ]),
                      color: const Color(0xffe6f0fc)),
                  Padding(
                      padding: EdgeInsets.fromLTRB(pad, 28, pad, 80),
                      child: Row(children: [
                        Expanded(
                            child: copy('Thoughtfully delivered. CIRCUM.',
                                size: 14, color: muted)),
                        TextButton(
                            onPressed: widget.onBack,
                            child: const Text('Back to home'))
                      ])),
                ]));
              })))));

  Widget hero(bool wide) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.shield_outlined, size: 18, color: ink),
          const SizedBox(width: 10),
          eyebrow('CIRCUM VANGUARD', color: ink)
        ]),
        const SizedBox(height: 26),
        heading('When it means\nmore, deliver\nwith care.', wide ? 66 : 48),
        const SizedBox(height: 24),
        copy(
            'For deliveries that deserve extra attention. Verified handovers, clearer custody tracking and priority support, all the way to their door.',
            size: 19,
            color: muted),
        const SizedBox(height: 28),
        Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              startButton(),
              TextButton.icon(
                  icon: const Icon(Icons.arrow_downward, size: 16),
                  iconAlignment: IconAlignment.end,
                  onPressed: () => Scrollable.ensureVisible(
                      journeyKey.currentContext!,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 400)),
                  label: const Text('See how it works'))
            ]),
        const SizedBox(height: 18),
        copy('Optional upgrade £1.99. Included when required.',
            size: 14, color: muted),
      ]);

  Widget artwork() => AspectRatio(
      aspectRatio: 1.08,
      child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xff0859cf),
                    Color(0xff0a84ff),
                    Color(0xff66b9ff)
                  ])),
          child: LayoutBuilder(
              builder: (context, box) =>
                  Stack(alignment: Alignment.center, children: [
                    Positioned.fill(
                        child: CustomPaint(painter: _DeliveryOrbitPainter())),
                    Positioned(
                        top: 28,
                        left: 28,
                        child: eyebrow('IMPORTANT TO YOU.\nCONSIDERED BY US.',
                            color: const Color(0xffffffff))),
                    Transform.rotate(
                        angle: -.10,
                        child: Container(
                            width: box.maxWidth * .47,
                            height: box.maxWidth * .47,
                            decoration: BoxDecoration(
                                color: const Color(0xfff8fbff),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                      color: ink.withValues(alpha: .17),
                                      blurRadius: 35,
                                      offset: const Offset(15, 28))
                                ]),
                            child:
                                Stack(alignment: Alignment.center, children: [
                              Container(
                                  width: 36, color: const Color(0xffc4dfff)),
                              Container(
                                  height: 36, color: const Color(0xffc4dfff)),
                              Container(
                                  width: 90,
                                  height: 90,
                                  decoration: BoxDecoration(
                                      color: vanguardBlue,
                                      borderRadius: BorderRadius.circular(24)),
                                  child: const Icon(
                                      Icons.verified_user_outlined,
                                      size: 48,
                                      color: Colors.white)),
                            ]))),
                    Positioned(
                        bottom: 26,
                        left: 24,
                        right: 24,
                        child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .94),
                                borderRadius: BorderRadius.circular(14)),
                            child: Row(children: [
                              const Icon(Icons.pin_outlined, color: ink),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    copy('Care at both ends.',
                                        size: 17, bold: true),
                                    copy('Collection PIN + receiver PIN',
                                        size: 13, color: muted)
                                  ])),
                              const Icon(Icons.check_circle,
                                  color: Color(0xff0874dc), size: 22)
                            ]))),
                  ]))));

  Widget benefit(String number, IconData icon, String title, String body) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 28, color: ink),
          const Spacer(),
          eyebrow(number)
        ]),
        const SizedBox(height: 22),
        copy(title, size: 24, bold: true),
        const SizedBox(height: 12),
        copy(body, color: muted)
      ]);
  Widget occasions(bool wide) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        eyebrow('FOR THE DELIVERIES THAT MATTER'),
        const SizedBox(height: 18),
        heading('Some things carry\nmore than their weight.', wide ? 44 : 34),
        const SizedBox(height: 24),
        copy(
            'A gift with a story. Documents for an important day. The equipment someone is waiting for.',
            color: muted),
        const SizedBox(height: 26),
        Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              'Gifts & keepsakes',
              'Important documents',
              'Electronics',
              'Sentimental items'
            ]
                .map((label) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xffc5d7ed)),
                        borderRadius: BorderRadius.circular(30)),
                    child: copy(label, size: 14)))
                .toList())
      ]);
  Widget pricing(bool wide) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffd0dff1)),
          borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        eyebrow('A LITTLE EXTRA CARE'),
        const SizedBox(height: 20),
        heading('£1.99', 60),
        copy('Optional upgrade per delivery', color: muted),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        copy('Already included when required.', size: 22, bold: true),
        const SizedBox(height: 12),
        copy(
            'Gifts, Business, Health+ and deliveries that require Vanguard include it under their booking rules. Check your quote for the final price.',
            color: muted),
        const SizedBox(height: 24),
        startButton()
      ]));
}

class _DeliveryOrbitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xffffffff).withValues(alpha: .22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final scale in [.7, 1.0, 1.3]) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(size.width * .5, size.height * .48),
              width: size.width * scale,
              height: size.height * scale * .7),
          paint);
    }
    canvas.drawCircle(Offset(size.width * .14, size.height * .38), 5,
        Paint()..color = const Color(0xffffffff));
    canvas.drawCircle(Offset(size.width * .87, size.height * .61), 5,
        Paint()..color = const Color(0xffffffff));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
