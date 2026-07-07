import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../gifts/gifts_social_policy.dart';
import 'gift_delivery_view.dart';
import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';

class GiftCampaignView extends StatefulWidget {
  const GiftCampaignView({super.key});

  static const routeName = '/sender-mobile/gifts/campaign';

  @override
  State<GiftCampaignView> createState() => _GiftCampaignViewState();
}

class _GiftCampaignViewState extends State<GiftCampaignView> {
  var _step = 0;
  _CampaignOption? _campaign;
  final _selected = <String, Set<String>>{
    'interests': <String>{},
    'hobbies': <String>{},
    'musicTaste': <String>{},
    'booksFilms': <String>{},
    'favouriteFoodsDrinks': <String>{},
    'lifestyle': <String>{},
    'preferredGiftCategories': <String>{},
  };
  final _allergiesController = TextEditingController();
  final _medicalController = TextEditingController();
  final _blockedController = TextEditingController();
  var _senderRevealMode = 'anonymous_forever';
  var _recipientContentConsent = false;
  var _allowCircumSocialUse = false;
  var _allowPublicPosting = false;
  var _allowBrandTagging = false;
  _CampaignMatch? _match;
  Timer? _matchTimer;

  bool get _hasAboutSignal =>
      _selected.values.any((values) => values.isNotEmpty);

  bool get _canContinue {
    return switch (_step) {
      0 => true,
      1 => _campaign != null,
      2 => _hasAboutSignal,
      3 => true,
      4 => true,
      5 => _match != null,
      6 => _match != null,
      _ => false,
    };
  }

  @override
  void dispose() {
    _matchTimer?.cancel();
    _allergiesController.dispose();
    _medicalController.dispose();
    _blockedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: _step + 1,
      eyebrow: _eyebrow,
      title: _title,
      subtitle: _subtitle,
      onBack: _goBack,
      children: _children,
      footer: GiftJourneyWidgets.primaryButton(
        enabled: _canContinue,
        label: _primaryLabel,
        onTap: _canContinue ? _goNext : null,
      ),
    );
  }

  String get _eyebrow => switch (_step) {
        0 => 'CAMPAIGN',
        1 => 'STEP 01 — JOIN CAMPAIGN',
        2 => 'STEP 02 — ABOUT YOU',
        3 => 'STEP 03 — SAFETY',
        4 => 'STEP 04 — PRIVACY',
        5 => 'STEP 05 — MATCHING',
        6 => 'STEP 06 — MATCHED',
        _ => 'CAMPAIGN',
      };

  String get _title => switch (_step) {
        0 => 'Gift a stranger. Bring London closer.',
        1 => 'Choose campaign',
        2 => 'About you',
        3 => 'Safety',
        4 => 'Privacy',
        5 => _match == null ? 'Finding your match...' : 'Match found',
        6 => 'Your anonymous match is ready',
        _ => 'Campaign',
      };

  String get _subtitle => switch (_step) {
        0 =>
          'People anonymously exchange thoughtful gifts with others who share similar interests. Circum never reveals identities until the policy allows.',
        1 => 'Choose the anonymous gift exchange you want to join.',
        2 =>
          'Share only the interests GiftsSocialPolicy uses for anonymous matching.',
        3 =>
          'We use these details to avoid unsafe matches, including allergy conflicts.',
        4 => 'Reveal and sharing choices are governed by GiftsSocialPolicy.',
        5 =>
          'We compare anonymous compatibility only. No names, photos, addresses or private profile details are shown.',
        6 => 'Continue into the normal Gifts flow with this match attached.',
        _ => '',
      };

  String get _primaryLabel => switch (_step) {
        0 => 'Join Campaign',
        5 => _match == null ? 'Finding match...' : 'View match',
        6 => 'Continue to Gift',
        _ => 'Continue',
      };

  List<Widget> get _children => switch (_step) {
        0 => _homeChildren,
        1 => _campaignChildren,
        2 => _aboutChildren,
        3 => _safetyChildren,
        4 => _privacyChildren,
        5 => _matchingChildren,
        6 => _matchedChildren,
        _ => const <Widget>[],
      };

  List<Widget> get _homeChildren => [
        _CampaignGlassCard(
          title: 'How it works',
          body:
              'You join a campaign, share safe matching signals, choose your reveal policy, then receive an anonymous compatibility match.',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: const Color(0xFF12101B),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              builder: (_) => const _HowItWorksSheet(),
            ),
            child: Text(
              'How it works',
              style: GoogleFonts.inter(
                color: const Color(0xFFC9B8FF),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _CampaignGlassCard(
          title: 'Privacy first',
          body:
              'Circum uses GiftsSocialPolicy for reveal, public posting and brand tagging decisions.',
        ),
      ];

  List<Widget> get _campaignChildren => [
        for (final campaign in _campaigns) ...[
          _CampaignOptionCard(
            campaign: campaign,
            selected: _campaign?.id == campaign.id,
            onTap: () => setState(() => _campaign = campaign),
          ),
          const SizedBox(height: 10),
        ],
      ];

  List<Widget> get _aboutChildren => [
        _chipSection('Interests', 'interests', const [
          'Travel',
          'Architecture',
          'Coffee',
          'Art',
          'Fashion',
        ]),
        _chipSection('Hobbies', 'hobbies', const [
          'Reading',
          'Running',
          'Photography',
          'Cooking',
          'Cycling',
        ]),
        _chipSection('Music', 'musicTaste', const [
          'Jazz',
          'Afrobeats',
          'Classical',
          'Indie',
          'Gospel',
        ]),
        _chipSection('Books', 'booksFilms', const [
          'Fiction',
          'Poetry',
          'Design',
          'History',
          'Biographies',
        ]),
        _chipSection('Food', 'favouriteFoodsDrinks', const [
          'Tea',
          'Coffee',
          'Chocolate',
          'Baking',
          'Fine Dining',
        ]),
        _chipSection('Lifestyle', 'lifestyle', const [
          'Wellness',
          'Sustainability',
          'Home',
          'Fitness',
          'Creativity',
        ]),
        _chipSection('Favourite categories', 'preferredGiftCategories', const [
          'Beauty',
          'Books',
          'Experiences',
          'Home Fragrance',
          'Accessories',
        ]),
      ];

  List<Widget> get _safetyChildren => [
        GiftJourneyWidgets.inputCard(
          controller: _allergiesController,
          label: 'FOOD ALLERGIES',
          placeholder: 'Nuts, dairy, gluten...',
          helper: 'Comma-separated. Used for automatic exclusion.',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _medicalController,
          label: 'MEDICAL RESTRICTIONS',
          placeholder: 'Anything gifts should avoid',
          helper: 'Only include what is relevant to gifts.',
          onChanged: (_) => setState(() {}),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _blockedController,
          label: 'BLOCKED USERS',
          placeholder: 'Optional user IDs',
          helper: 'Used only if applicable.',
          onChanged: (_) => setState(() {}),
        ),
      ];

  List<Widget> get _privacyChildren {
    final policyGift = _policyGiftPreview;
    final canShowBrandTags = GiftsSocialPolicy.canPostPublicly(policyGift);
    return [
      _chipSection('Reveal mode', 'senderRevealMode', const [
        'Reveal immediately',
        'Reveal after delivery',
        'Anonymous until mutual consent',
      ]),
      const SizedBox(height: 14),
      _CampaignToggle(
        label: 'recipientContentConsent',
        value: _recipientContentConsent,
        onChanged: (value) => setState(() => _recipientContentConsent = value),
      ),
      _CampaignToggle(
        label: 'allowCircumSocialUse',
        value: _allowCircumSocialUse,
        onChanged: (value) => setState(() => _allowCircumSocialUse = value),
      ),
      _CampaignToggle(
        label: 'allowPublicPosting',
        value: _allowPublicPosting,
        onChanged: (value) => setState(() => _allowPublicPosting = value),
      ),
      if (canShowBrandTags)
        _CampaignToggle(
          label: 'allowBrandTagging',
          value: _allowBrandTagging,
          onChanged: (value) => setState(() => _allowBrandTagging = value),
        ),
      const SizedBox(height: 12),
      _CampaignGlassCard(
        title: 'Policy result',
        body:
            'Reveal now: ${GiftsSocialPolicy.canRevealSender(policyGift) ? 'Allowed' : 'Not yet'} · Public posting: ${GiftsSocialPolicy.canPostPublicly(policyGift) ? 'Allowed' : 'Not allowed'} · Brand tags: ${GiftsSocialPolicy.canApproveBrandTags(policyGift) ? 'Allowed' : 'Not allowed'}',
      ),
    ];
  }

  List<Widget> get _matchingChildren => [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: const Color(0xFFC9B8FF).withValues(alpha: .32)),
            gradient: LinearGradient(
              colors: [
                const Color(0xFFC9B8FF).withValues(alpha: .12),
                const Color(0xFFFF8BD1).withValues(alpha: .08),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _match == null
                    ? 'Finding your match...'
                    : 'Anonymous compatibility summary',
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _match?.reason ??
                    'Looking for safe overlap across interests, food, books, music and lifestyle.',
                style: GoogleFonts.inter(
                  color: const Color(0xFFE7DFF5),
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ];

  List<Widget> get _matchedChildren => [
        _CampaignGlassCard(
          title: 'Compatibility score',
          body: '${_match?.score.toStringAsFixed(0) ?? '0'} / 100',
        ),
        const SizedBox(height: 12),
        _CampaignGlassCard(
          title: 'Shared interests',
          body: _match?.sharedInterests.join(', ') ?? 'Broad compatibility',
        ),
        const SizedBox(height: 12),
        _CampaignGlassCard(
          title: 'Campaign',
          body: _campaign?.name ?? 'Bringing London Closer',
        ),
        const SizedBox(height: 12),
        _CampaignGlassCard(
          title: 'Reveal policy',
          body: _senderRevealModeLabel,
        ),
        const SizedBox(height: 12),
        const _CampaignGlassCard(
          title: 'Anonymous status',
          body:
              'Names, photos, addresses and private profile details remain hidden.',
        ),
      ];

  Widget _chipSection(String title, String key, List<String> options) {
    if (key == 'senderRevealMode') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(title),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                GiftJourneyWidgets.choiceChip(
                  label: option,
                  selected: _senderRevealModeLabel == option,
                  onTap: () => setState(() {
                    _senderRevealMode = switch (option) {
                      'Reveal immediately' => 'reveal_immediately',
                      'Reveal after delivery' => 'reveal_after_delivery',
                      _ => 'anonymous_forever',
                    };
                  }),
                ),
            ],
          ),
        ],
      );
    }
    final selected = _selected[key]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              GiftJourneyWidgets.choiceChip(
                label: option,
                selected: selected.contains(option),
                onTap: () => setState(() {
                  if (!selected.remove(option)) selected.add(option);
                }),
              ),
          ],
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.jetBrainsMono(
          color: const Color(0xFFC9B8FF),
          fontSize: 10.5,
          letterSpacing: .9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _step -= 1);
  }

  void _goNext() {
    if (_step == 0) {
      setState(() => _step = 1);
      return;
    }
    if (_step == 4) {
      setState(() {
        _step = 5;
        _match = null;
      });
      _startMatching();
      return;
    }
    if (_step == 5) {
      setState(() => _step = 6);
      return;
    }
    if (_step == 6) {
      _continueToGift();
      return;
    }
    setState(() => _step += 1);
  }

  void _startMatching() {
    _matchTimer?.cancel();
    _matchTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _match = _bestMatch());
    });
  }

  _CampaignMatch _bestMatch() {
    final participant = _participantPolicyMap;
    _CampaignMatch? best;
    for (final candidate in _candidatePool) {
      final result = GiftsSocialPolicy.scoreMatch(participant, candidate);
      if (result.score <= 0) continue;
      final safe = GiftsSocialPolicy.recipientSafeView(candidate);
      final overlap = _terms(participant).intersection(_terms(safe)).toList()
        ..sort();
      final match = _CampaignMatch(
        score: result.score,
        reason: result.reason,
        sharedInterests:
            overlap.isEmpty ? const ['Broad thoughtful exchange'] : overlap,
      );
      if (best == null || match.score > best.score) best = match;
    }
    return best ??
        const _CampaignMatch(
          score: 25,
          reason: 'A broad campaign match with no obvious preference conflict.',
          sharedInterests: ['Broad thoughtful exchange'],
        );
  }

  void _continueToGift() {
    final campaign = _campaign ?? _campaigns.first;
    final match = _match;
    final draft = GiftJourneyDraft.forMode(SenderGiftMode.campaign).copyWith(
      recipientName: 'Anonymous campaign match',
      relationship: 'Anonymous Recipient',
      occasion: campaign.name,
      notes:
          'Campaign match: ${match?.reason ?? 'Anonymous compatibility match.'}',
      interests: _selected['interests']!.toList(),
      giftThemes: [
        for (final label in _selected['preferredGiftCategories']!)
          SenderGiftTheme.catalogue(label),
      ],
      senderRevealMode: _senderRevealMode,
      allowCircumSocialUse: _allowCircumSocialUse,
      allowPublicPosting: _allowPublicPosting,
      allowBrandTagging: _allowBrandTagging,
      recipientContentConsent:
          _recipientContentConsent ? 'granted' : 'not_requested',
      campaignId: campaign.id,
      campaignName: campaign.name,
      campaignType: campaign.type,
      campaignTagline: campaign.tagline,
      campaignCompatibilityScore: match?.score,
      campaignMatchSummary: match?.reason,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GiftDeliveryView(draft: draft),
        settings: const RouteSettings(name: GiftDeliveryView.routeName),
      ),
    );
  }

  Map<String, dynamic> get _participantPolicyMap => {
        'userId': 'sender-mobile-campaign-participant',
        'matchConsent': true,
        'matchStatus': 'active',
        'interests': _selected['interests']!.toList(),
        'hobbies': _selected['hobbies']!.toList(),
        'musicTaste': _selected['musicTaste']!.toList(),
        'booksFilms': _selected['booksFilms']!.toList(),
        'favouriteFoodsDrinks': _selected['favouriteFoodsDrinks']!.toList(),
        'lifestyle': _selected['lifestyle']!.toList(),
        'preferredGiftCategories':
            _selected['preferredGiftCategories']!.toList(),
        'allergies': _commaList(_allergiesController.text),
        'medicalRestrictions': _medicalController.text.trim(),
        'blockedUserIds': _commaList(_blockedController.text),
        ..._policyGiftPreview,
      };

  Map<String, dynamic> get _policyGiftPreview => {
        'senderRevealMode': _senderRevealMode,
        'senderRevealConsent': 'pending',
        'recipientRevealRequestStatus': 'pending',
        'recipientContentConsent':
            _recipientContentConsent ? 'granted' : 'not_requested',
        'allowCircumSocialUse': _allowCircumSocialUse,
        'allowPublicPosting': _allowPublicPosting,
        'allowBrandTagging': _allowBrandTagging,
        'status': 'matching',
      };

  String get _senderRevealModeLabel => switch (_senderRevealMode) {
        'reveal_immediately' => 'Reveal immediately',
        'reveal_after_delivery' => 'Reveal after delivery',
        _ => 'Anonymous until mutual consent',
      };

  static List<String> _commaList(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  static Set<String> _terms(Map<String, dynamic> participant) {
    final values = <dynamic>[
      ...?participant['interests'] as List?,
      ...?participant['hobbies'] as List?,
      ...?participant['preferredGiftCategories'] as List?,
      ...?participant['favouriteFoodsDrinks'] as List?,
      ...?participant['musicTaste'] as List?,
      ...?participant['booksFilms'] as List?,
    ];
    return values.map((value) => '$value'.toLowerCase()).toSet();
  }
}

class _CampaignOption {
  final String id;
  final String name;
  final String type;
  final String tagline;

  const _CampaignOption({
    required this.id,
    required this.name,
    required this.type,
    required this.tagline,
  });
}

class _CampaignMatch {
  final double score;
  final String reason;
  final List<String> sharedInterests;

  const _CampaignMatch({
    required this.score,
    required this.reason,
    required this.sharedInterests,
  });
}

const _campaigns = [
  _CampaignOption(
    id: 'bringing-london-closer',
    name: 'Bringing London Closer',
    type: 'anonymous_gifting',
    tagline: 'Thoughtful exchanges across the city.',
  ),
  _CampaignOption(
    id: 'christmas-giving',
    name: 'Christmas Giving',
    type: 'seasonal_kindness',
    tagline: 'Small gestures for the festive season.',
  ),
  _CampaignOption(
    id: 'student-welcome-week',
    name: 'Student Welcome Week',
    type: 'community_welcome',
    tagline: 'Help someone feel at home in London.',
  ),
  _CampaignOption(
    id: 'nhs-thank-you',
    name: 'NHS Thank You',
    type: 'gratitude',
    tagline: 'A quiet thank-you for people who care for others.',
  ),
  _CampaignOption(
    id: 'ramadan-kindness',
    name: 'Ramadan Kindness',
    type: 'seasonal_kindness',
    tagline: 'Anonymous generosity during Ramadan.',
  ),
  _CampaignOption(
    id: 'community-christmas',
    name: 'Community Christmas',
    type: 'community_kindness',
    tagline: 'Neighbourly gifts for a warmer Christmas.',
  ),
  _CampaignOption(
    id: 'valentines-anonymous',
    name: "Valentine's Anonymous",
    type: 'anonymous_gifting',
    tagline: 'A thoughtful moment without pressure.',
  ),
];

const _candidatePool = [
  {
    'userId': 'campaign-candidate-travel-coffee',
    'matchConsent': true,
    'matchStatus': 'active',
    'interests': ['Travel', 'Architecture', 'Coffee'],
    'hobbies': ['Photography', 'Reading'],
    'musicTaste': ['Jazz'],
    'booksFilms': ['Design', 'History'],
    'favouriteFoodsDrinks': ['Coffee', 'Tea'],
    'preferredGiftCategories': ['Books', 'Experiences'],
    'allergies': <String>[],
    'blockedUserIds': <String>[],
  },
  {
    'userId': 'campaign-candidate-wellness-art',
    'matchConsent': true,
    'matchStatus': 'active',
    'interests': ['Art', 'Fashion'],
    'hobbies': ['Cooking', 'Running'],
    'musicTaste': ['Classical'],
    'booksFilms': ['Poetry'],
    'favouriteFoodsDrinks': ['Chocolate'],
    'preferredGiftCategories': ['Beauty', 'Home Fragrance'],
    'allergies': ['nuts'],
    'blockedUserIds': <String>[],
  },
];

class _CampaignOptionCard extends StatelessWidget {
  final _CampaignOption campaign;
  final bool selected;
  final VoidCallback onTap;

  const _CampaignOptionCard({
    required this.campaign,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: _CampaignGlassCard(
        title: campaign.name,
        body: campaign.tagline,
        trailing: Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_off_rounded,
          color: selected ? const Color(0xFFC9B8FF) : const Color(0xFFB8AAB8),
          size: 18,
        ),
      ),
    );
  }
}

class _CampaignGlassCard extends StatelessWidget {
  final String title;
  final String body;
  final Widget? trailing;

  const _CampaignGlassCard({
    required this.title,
    required this.body,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: const Color(0xFFB8AAB8),
                    fontSize: 12.5,
                    height: 1.42,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _CampaignToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CampaignToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(
        label,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
      activeThumbColor: const Color(0xFFC9B8FF),
    );
  }
}

class _HowItWorksSheet extends StatelessWidget {
  const _HowItWorksSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How it works',
              style: GoogleFonts.dmSerifDisplay(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Join a campaign, share safe matching signals, receive an anonymous compatibility match, then continue into the normal Gifts journey.',
              style: GoogleFonts.inter(
                color: const Color(0xFFE7DFF5),
                fontSize: 13.5,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
