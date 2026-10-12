import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'app_store_badge.dart';
import 'package:url_launcher/link.dart';

/// Public recruitment surface; account creation and approval stay in onboarding.
class RiderRecruitmentPage extends StatelessWidget {
  const RiderRecruitmentPage(
      {super.key,
      required this.onBack,
      required this.onJoin,
      required this.onLogin,
      required this.onVision});

  final VoidCallback onBack;
  final VoidCallback onJoin;
  final VoidCallback onLogin;
  final VoidCallback onVision;

  static final appStore =
      Uri.parse('https://apps.apple.com/gb/app/circum-rider/id6476303139');
  static final playStore = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.circum.rider');
  static const ink = Color(0xff102942);
  static const blue = Color(0xff2455f5);
  static const teal = Color(0xff007d87);
  static const paper = Color(0xffeffaff);

  Widget _copy(String text, {Color color = ink, double size = 18}) =>
      Text(text, style: TextStyle(fontSize: size, height: 1.6, color: color));

  Widget _heading(String text, {double size = 40, Color color = ink}) =>
      Text(text,
          style: TextStyle(
              fontFamily: 'D-DIN-Bold',
              fontSize: size,
              fontWeight: FontWeight.w700,
              height: 1.08,
              color: color));

  Widget _label(String text, {Color color = teal}) => Text(text,
      style: TextStyle(
          color: color,
          fontSize: 12,
          letterSpacing: 2,
          fontWeight: FontWeight.w800));

  Widget _join({bool inverse = false}) => FilledButton.icon(
      onPressed: onJoin,
      style: FilledButton.styleFrom(
          backgroundColor: inverse ? Colors.white : blue,
          foregroundColor: inverse ? ink : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22)),
      icon: const Icon(Icons.arrow_outward, size: 20),
      label: const Text('Join Circum Riders'));

  Widget _section(
          {required Widget child, Color color = Colors.white}) =>
      Container(
          width: double.infinity,
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: child)));

  Widget _feature(
          String number, String title, String description, Color accent) =>
      Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
              color: accent.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(24),
              border:
                  Border.all(color: accent.withValues(alpha: .25), width: 1.5)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(number, color: accent),
            const SizedBox(height: 30),
            _heading(title, size: 27),
            const SizedBox(height: 16),
            _copy(description, size: 16),
          ]));

  Widget _columns(List<Widget> children, bool wide) => wide
      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 20),
            Expanded(child: children[i]),
          ],
        ])
      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            children[i],
          ],
        ]);

  Widget _storeLink(String label, Uri uri, {required bool apple}) => Link(
      uri: uri,
      target: LinkTarget.blank,
      builder: (context, followLink) => Semantics(
            label: label,
            link: true,
            child: InkWell(
              key: ValueKey(label),
              onTap: followLink,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 190,
                height: 72,
                child: Center(
                    child: apple
                        ? SvgPicture.string(appStoreBadgeSvg,
                            width: 166, height: 56, excludeFromSemantics: true)
                        : Image.network(
                            Uri.base
                                .resolve('/images/store-badges/google-play.png')
                                .toString(),
                            width: 190,
                            excludeFromSemantics: true,
                            errorBuilder: (context, error, stack) => Text(label,
                                style: const TextStyle(color: Colors.white)))),
              ),
            ),
          ));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: paper,
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return ListView(children: [
            Container(
                color: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: Row(children: [
                          IconButton(
                              onPressed: onBack,
                              tooltip: 'Back to Circum',
                              icon: const Icon(Icons.arrow_back, color: ink)),
                          const SizedBox(width: 8),
                          Flexible(
                              child: Image.asset(
                                  'assets/images/circum_wordmark.png',
                                  width: wide ? 150 : 112)),
                          const Spacer(),
                          TextButton(
                              onPressed: onLogin,
                              style: TextButton.styleFrom(foregroundColor: ink),
                              child: const Text('Rider login')),
                        ])))),
            Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                      Color(0xffe5f6ff),
                      Color(0xffbceaff),
                      Color(0xff87d8fa)
                    ])),
                padding: EdgeInsets.symmetric(
                    horizontal: 24, vertical: wide ? 84 : 52),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: _columns([
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('CIRCUM RIDER / YOUR NEXT CHAPTER',
                                    color: teal),
                                const SizedBox(height: 24),
                                _heading(
                                    'Move with\npurpose.\nEarn with\nCircum.',
                                    size: wide ? 74 : 54,
                                    color: ink),
                                const SizedBox(height: 28),
                                _copy(
                                    'Connect people with what matters. Explore delivery work, build your reputation and become part of the Circum Rider community.',
                                    color: ink),
                                const SizedBox(height: 32),
                                Wrap(
                                    spacing: 14,
                                    runSpacing: 14,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      _join(),
                                      TextButton.icon(
                                          onPressed: onVision,
                                          style: TextButton.styleFrom(
                                              foregroundColor: blue,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 20,
                                                      horizontal: 14)),
                                          icon: const Icon(Icons.north_east,
                                              size: 18),
                                          label: const Text(
                                              'Explore the Rider vision'))
                                    ]),
                              ]),
                          Padding(
                              padding: EdgeInsets.only(
                                  top: wide ? 54 : 20, left: wide ? 28 : 0),
                              child: Container(
                                  padding: const EdgeInsets.all(30),
                                  decoration: BoxDecoration(
                                      color: const Color(0xffeffaff),
                                      borderRadius: BorderRadius.circular(28)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _label('MORE THAN THE NEXT DELIVERY'),
                                        const SizedBox(height: 32),
                                        const ExcludeSemantics(
                                            child: Icon(Icons.public,
                                                size: 104, color: blue)),
                                        const SizedBox(height: 30),
                                        _heading('Your work.\nA wider impact.',
                                            size: 38),
                                        const SizedBox(height: 20),
                                        _copy(
                                            'Behind every collection is a person counting on you. Care, reliability and good judgement are what move our network forward.',
                                            size: 16),
                                        const SizedBox(height: 30),
                                        const Divider(),
                                        const SizedBox(height: 20),
                                        _label('TRUST. SERVICE. PROGRESSION.',
                                            color: blue),
                                      ]))),
                        ], wide)))),
            _section(
                color: paper,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('DELIVERY WORK, WITH DIRECTION'),
                      const SizedBox(height: 18),
                      _heading('Make your next move count.',
                          size: wide ? 46 : 34),
                      const SizedBox(height: 32),
                      _columns([
                        _feature(
                            '01 / OPPORTUNITY',
                            'Find your rhythm.',
                            'Explore available delivery opportunities through Circum Rider. Build a routine that works around your circumstances.',
                            blue),
                        _feature(
                            '02 / EARNINGS',
                            'See what you can earn.',
                            'Review the offer and its payment details before accepting. Keep track of your delivery activity and earnings in your Rider account.',
                            teal),
                        _feature(
                            '03 / COMMUNITY',
                            'Build your name.',
                            'Reliable service means something. Grow your reputation through careful handling, clear communication and accountable handovers.',
                            const Color(0xff7937c8)),
                      ], wide),
                    ])),
            _section(
                child: _columns([
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('DELIVERIES & EARNINGS'),
                const SizedBox(height: 18),
                _heading('A clearer view\nof your earnings.',
                    size: wide ? 46 : 34),
                const SizedBox(height: 22),
                _copy(
                    'Every opportunity starts with the details. Make an informed choice about the work you take on.'),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _earningStep('01', 'Review the offer',
                    'Check the delivery details, requirements and displayed payment before you accept.'),
                _earningStep('02', 'Deliver with care',
                    'Follow collection and handover instructions, and record the required delivery evidence.'),
                _earningStep('03', 'Track your earnings',
                    'Use your account to review earnings and available payout information.'),
                _copy(
                    'Delivery availability and earnings vary by demand, location and eligibility. There is no guaranteed income or number of jobs. Allow for your own costs and applicable deductions.',
                    size: 14),
              ]),
            ], wide)),
            _section(
                color: const Color(0xffccefff),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('THE RIDER VISION'),
                      const SizedBox(height: 18),
                      _heading('Every Veteran\nwas once an Agent.',
                          size: wide ? 58 : 40),
                      const SizedBox(height: 24),
                      ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 740),
                          child: _copy(
                              'The Circum Order recognises the people who build the network through trust, service and contribution. Discover the values behind each rank and the path from joining to lasting impact.')),
                      const SizedBox(height: 30),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        for (final rank in const [
                          'Agent',
                          'Sentinel',
                          'Warden',
                          'Knight',
                          'Veteran'
                        ])
                          Chip(
                              label: Text(rank),
                              backgroundColor: Colors.white,
                              labelStyle: const TextStyle(
                                  color: ink, fontWeight: FontWeight.w700),
                              side: const BorderSide(color: Color(0xffc4d5ee)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10)),
                      ]),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                          onPressed: onVision,
                          style: FilledButton.styleFrom(
                              backgroundColor: ink,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 20)),
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Discover the Circum Order')),
                    ])),
            _section(
                color: paper,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('YOUR FIRST STEPS'),
                      const SizedBox(height: 18),
                      _heading('Ready for a new chapter?',
                          size: wide ? 46 : 34),
                      const SizedBox(height: 30),
                      _columns([
                        _feature(
                            '01',
                            'Create your account.',
                            'Start your Rider application and tell us about yourself.',
                            blue),
                        _feature(
                            '02',
                            'Complete your checks.',
                            'Provide the profile information and documents requested during onboarding. Requirements depend on your circumstances.',
                            teal),
                        _feature(
                            '03',
                            'Get ready to deliver.',
                            'Complete the required checks and receive approval before accepting deliveries. Availability depends on your area.',
                            const Color(0xff7937c8)),
                      ], wide),
                      const SizedBox(height: 32),
                      _join(),
                    ])),
            _section(
                color: ink,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('TAKE THE NEXT STEP',
                          color: const Color(0xff94eeea)),
                      const SizedBox(height: 18),
                      _heading('Circum Rider.\nWith you on the move.',
                          size: wide ? 46 : 34, color: Colors.white),
                      const SizedBox(height: 22),
                      _copy('Download the Rider app for your phone.',
                          color: const Color(0xffe0ecfa)),
                      const SizedBox(height: 26),
                      Wrap(spacing: 16, runSpacing: 16, children: [
                        _storeLink('Download on the App Store', appStore,
                            apple: true),
                        _storeLink('Get it on Google Play', playStore,
                            apple: false),
                      ]),
                      const SizedBox(height: 40),
                      const Divider(color: Color(0xff7794b5)),
                      const SizedBox(height: 16),
                      Wrap(spacing: 18, runSpacing: 8, children: [
                        TextButton(
                            onPressed: onBack,
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.white),
                            child: const Text('Circum home')),
                        TextButton(
                            onPressed: onVision,
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.white),
                            child: const Text('Rider vision')),
                        Link(
                            uri: Uri.base.resolve('/support'),
                            builder: (context, followLink) => TextButton(
                                onPressed: followLink,
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.white),
                                child: const Text('Support'))),
                        Link(
                            uri: Uri.base.resolve('/privacy_policy'),
                            builder: (context, followLink) => TextButton(
                                onPressed: followLink,
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.white),
                                child: const Text('Privacy policy'))),
                      ]),
                      const SizedBox(height: 16),
                      _copy('© ${DateTime.now().year} Circum Technologies Ltd.',
                          color: const Color(0xffd4e3f6), size: 13),
                    ])),
          ]);
        })),
      );

  Widget _earningStep(String number, String title, String copy) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(number,
            style: const TextStyle(
                color: blue, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(width: 18),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _heading(title, size: 25),
          const SizedBox(height: 8),
          _copy(copy, size: 16),
        ])),
      ]));
}
