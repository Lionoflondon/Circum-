import 'package:flutter/material.dart';

/// Public Rider introduction. Account access is a deliberate next step.
class RiderOrderExplainer extends StatelessWidget {
  const RiderOrderExplainer(
      {super.key,
      required this.onBack,
      required this.onLogin,
      required this.onJoin});
  final VoidCallback onBack;
  final VoidCallback onLogin;
  final VoidCallback onJoin;

  static const ranks = <(String, String, String, String)>[
    (
      'Agent',
      'I have joined the network.',
      'Every journey begins as an Agent. This rank represents ambition, potential and the beginning of a professional reputation. Learn Circum’s standards and build trust through action.',
      'Serve customers with care. Communicate clearly. Follow collection and handover requirements. Act with integrity and learn from feedback.'
    ),
    (
      'Sentinel',
      'I have proven myself.',
      'A Sentinel has demonstrated consistency and dependability. The name reflects attentiveness: someone who remains alert and can be trusted to protect something valuable.',
      'Maintain reliable service. Stay attentive to delivery details and customer instructions. Set an example for Agents through consistent professional conduct.'
    ),
    (
      'Warden',
      'Circum trusts me.',
      'Warden represents stewardship, protection and greater operational responsibility. A Warden understands that their decisions affect the customer and the reputation of the whole network.',
      'Protect Circum’s standards. Handle uncertainty with sound judgement. Raise problems through support and preserve accountability throughout the delivery.'
    ),
    (
      'Knight',
      'I defend the network.',
      'A Knight is entrusted with important and sensitive responsibilities. Honour, loyalty, courage and service are expressed through professional action when the network is tested.',
      'Uphold service quality during challenging assignments. Protect customer trust through careful handling and accountable handovers. Lead by example: leadership is responsibility.'
    ),
    (
      'Veteran',
      'I helped build this.',
      'Veteran is the highest Rider rank. It recognises someone who exemplifies Circum’s values and has helped strengthen the community. Experience matters, but time served alone is not enough.',
      'Create lasting value through trusted service. Strengthen the standards others depend on. Leave a record of contribution worthy of recognition. Veteran recognises building the network, not simply remaining in it.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 760;
    Text body(String value) => Text(value,
        style: TextStyle(
            color: scheme.onSurfaceVariant, fontSize: 18, height: 1.65));
    Widget title(String value) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Text(value,
            style: TextStyle(
                color: scheme.onSurface,
                fontFamily: 'D-DIN-Bold',
                fontSize: narrow ? 34 : 46,
                height: 1.15,
                fontWeight: FontWeight.w700)));
    Widget section(String heading, List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title(heading), ...children]));
    Widget actions() => Wrap(spacing: 16, runSpacing: 16, children: [
          FilledButton(
              onPressed: onJoin,
              child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Join Circum Riders'))),
          OutlinedButton(
              onPressed: onLogin,
              child: const Padding(
                  padding: EdgeInsets.all(12), child: Text('Rider login')))
        ]);
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
          child: ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: narrow ? 22 : 40, vertical: 28),
              children: [
            Row(children: [
              IconButton(
                  tooltip: 'Back to Circum',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back)),
              const SizedBox(width: 12),
              Image.asset('assets/images/circum_wordmark.png',
                  width: narrow ? 142 : 180)
            ]),
            Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 64),
                          Text('CIRCUM RIDER · THE CIRCUM ORDER',
                              style: TextStyle(
                                  color: scheme.primary,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 24),
                          Text('Every Veteran\nwas once an Agent.',
                              style: TextStyle(
                                  fontFamily: 'D-DIN-Bold',
                                  fontSize: narrow ? 48 : 76,
                                  height: 1.08,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface)),
                          const SizedBox(height: 28),
                          body(
                              'Deliver with Circum. Build a reputation through trust, service and contribution. Discover the Rider network, what each rank means and how progression is reviewed before you join or log in.'),
                          section('The Circum Order', [
                            body(
                                'Every delivery represents a promise: something valuable will be collected, protected and delivered with care. Technology coordinates the work, but people uphold that promise.'),
                            const SizedBox(height: 18),
                            body(
                                'The Circum Order is the founding framework for recognising the people who build trust in the Rider network. It turns participation into progression through merit, discipline and service. Its principles are trust, excellence, responsibility, recognition and legacy.'),
                            const SizedBox(height: 18),
                            body(
                                'The path remains open to everyone. Every Agent may compete, grow and rise. Rank recognises contribution; it does not close the marketplace to newer riders.')
                          ]),
                          section('One beginning. Five ranks.', [
                            body(
                                'Agent → Sentinel → Warden → Knight → Veteran'),
                            const SizedBox(height: 28),
                            ...ranks.asMap().entries.map((entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 32),
                                child: Card(
                                    child: Padding(
                                        padding: const EdgeInsets.all(26),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  '0${entry.key + 1} / ${entry.value.$1}',
                                                  style: TextStyle(
                                                      fontSize: 28,
                                                      fontFamily: 'D-DIN-Bold',
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: scheme.primary)),
                                              const SizedBox(height: 12),
                                              Text('“${entry.value.$2}”',
                                                  style: TextStyle(
                                                      fontSize: 20,
                                                      color: scheme.onSurface)),
                                              const SizedBox(height: 18),
                                              body(entry.value.$3),
                                              const SizedBox(height: 18),
                                              Text(
                                                  'What this means in practice',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: scheme.onSurface)),
                                              const SizedBox(height: 8),
                                              body(entry.value.$4)
                                            ])))))
                          ]),
                          section('How you progress', [
                            body(
                                'Trust Points open the door. Reliability, quality, experience, compliance, performance and administrative review determine whether you progress through it. Points, delivery count, ratings or time served alone do not guarantee promotion.'),
                            const SizedBox(height: 24),
                            ...const <(String, String)>[
                              (
                                'Trust Points',
                                'Your contribution to progression, considered alongside your wider record.'
                              ),
                              (
                                'Reliability',
                                'Consistency, dependability and fulfilment of the commitments you accept.'
                              ),
                              (
                                'Service quality',
                                'Care, communication and professionalism with customers and deliveries.'
                              ),
                              (
                                'Experience',
                                'Demonstrated judgement and learning across completed work.'
                              ),
                              (
                                'Compliance',
                                'Meeting the standards, requirements and procedures that apply to your work.'
                              ),
                              (
                                'Advanced delivery performance',
                                'Your performance when assignments involve greater complexity or responsibility.'
                              ),
                              (
                                'Vanguard performance',
                                'Your performance on protected deliveries, with careful handling and accountable custody.'
                              ),
                            ].map((factor) => Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(factor.$1,
                                          style: TextStyle(
                                              fontSize: 21,
                                              fontWeight: FontWeight.w700,
                                              color: scheme.onSurface)),
                                      body(factor.$2)
                                    ]))),
                            body(
                                'Admin and Super Admin retain final authority over promotions, demotions, rank reviews and bestowed ranks. Rank changes must be audited and include a reason.')
                          ]),
                          section('The promotion review journey', [
                            body(
                                'Not eligible: the requirements for review have not yet been met.\n\nEligible for Review: your contribution may be considered; this is not an automatic promotion.\n\nUnder Review: your full contribution and performance record is being assessed.\n\nPromoted: an authorised decision has approved and recorded the new rank.')
                          ]),
                          section('Trust in practice', [
                            body(
                                'For every assignment, review the offer and follow its handling and handover requirements. Keep your documents and vehicle details current, communicate professionally and use support when a problem needs attention.'),
                            const SizedBox(height: 18),
                            body(
                                'Vanguard adds responsibility for protected deliveries. A higher rank does not guarantee jobs, earnings or access to every assignment. Requirements shown in the Rider account and individual offers still apply.')
                          ]),
                          section('Questions about the Order', [
                            ExpansionTile(
                                title: const Text(
                                    'Do Trust Points automatically promote me?'),
                                children: [
                                  Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: body(
                                          'No. Promotion considers the full record, including reliability, quality, experience, compliance and performance, with an authorised administrative review.'))
                                ]),
                            ExpansionTile(
                                title: const Text('Can a rank be changed?'),
                                children: [
                                  Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: body(
                                          'Yes. The rank governance charter allows authorised promotions, demotions, reviews and bestowed ranks. Every change must have a documented reason and audit record.'))
                                ]),
                            ExpansionTile(
                                title: const Text('Where can I see my rank?'),
                                children: [
                                  Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: body(
                                          'Log in to your Rider account to check your recorded rank and Trust Points. Contact Circum support if you need help understanding your record.'))
                                ]),
                          ]),
                          section('Your journey starts here.', [
                            body(
                                'Create your Rider account, complete your profile and submit the required onboarding information and documents. Complete the required checks before taking deliveries. Already part of the network? Log in to continue.'),
                            const SizedBox(height: 28),
                            actions(),
                            const SizedBox(height: 40),
                            body(
                                'Trust is earned. Service matters. Contribution should be recognised. Leadership is responsibility. Every Veteran was once an Agent.')
                          ]),
                          const SizedBox(height: 40),
                        ]))),
          ])),
    );
  }
}
