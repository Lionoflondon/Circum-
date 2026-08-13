import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../gifts/gift_system_policy.dart';
import '../gifts/gifts_social_policy.dart';
import 'design_system/sender_design_system.dart';
import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';
import 'gift_story_view.dart';

const senderGiftCampaignParticipantsCollectionName = 'giftCampaignParticipants';
const senderGiftCampaignMatchesCollectionName = 'giftCampaignMatches';
const senderGiftCampaignPaymentSource = 'sender_mobile_campaign';

bool _isLocalCampaignPaymentPreview() {
  final uri = Uri.base;
  final host = uri.host.toLowerCase();
  final localHost = host == 'localhost' || host == '127.0.0.1';
  return localHost && uri.queryParameters['campaign_payment_preview'] == '1';
}

class GiftCampaignView extends StatefulWidget {
  const GiftCampaignView({super.key});

  static const routeName = '/sender-mobile/gifts/campaign';

  @override
  State<GiftCampaignView> createState() => _GiftCampaignViewState();
}

class _GiftCampaignViewState extends State<GiftCampaignView> {
  var _step = _isLocalCampaignPaymentPreview() ? 8 : 0;
  _CampaignOption? _campaign;
  String? _participantId;
  Map<String, dynamic>? _participantStatusData =
      _isLocalCampaignPaymentPreview()
          ? const {
              'status': 'paid_waiting_for_match',
              'campaignStatus': 'paid_waiting_for_match',
            }
          : null;
  Map<String, dynamic>? _approvedMatch;
  Map<String, dynamic>? _visibleRevealedMatch;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _participantSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _matchSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _visibleMatchSub;

  final _displayNameController = TextEditingController();
  final _customInspirationController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _dietaryController = TextEditingController();
  final _medicalController = TextEditingController();
  final _culturalController = TextEditingController();
  final _avoidController = TextEditingController();
  final _blockedController = TextEditingController();

  final _selected = <String, Set<String>>{
    'interests': <String>{},
    'hobbies': <String>{},
    'musicTaste': <String>{},
    'booksFilms': <String>{},
    'favouriteFoodsDrinks': <String>{},
    'lifestyle': <String>{},
    'preferredGiftCategories': <String>{},
  };

  var _senderRevealMode = 'mutual_consent';
  var _recipientContentConsent = false;
  var _allowCircumSocialUse = false;
  var _allowPublicPosting = false;
  var _allowBrandTagging = false;
  var _budget = 50.0;
  var _paymentMethod = 'Card';
  var _applyRoth = false;
  var _rothLoading = true;
  var _rothUnavailable = false;
  var _rothBalance = 0.0;
  var _submitting = false;
  String? _message;

  bool get _hasAboutSignal {
    final hasSelectedSignal =
        _selected.values.any((values) => values.isNotEmpty);
    final hasCustomSignal = _customInspirationController.text.trim().isNotEmpty;
    return _displayNameController.text.trim().isNotEmpty &&
        (hasSelectedSignal || hasCustomSignal);
  }

  bool get _wantsRoth => _paymentMethod != 'Card' && _applyRoth;
  double get _rothApplied =>
      _wantsRoth ? _rothBalance.clamp(0, _budget).toDouble() : 0;
  double get _cardAmount => (_budget - _rothApplied).clamp(0, _budget);
  String get _verifiedPaymentMethod {
    if (_paymentMethod == 'Roth') return 'roth';
    if (_paymentMethod == 'Roth + Card') return 'roth_card';
    return 'card';
  }

  String get _campaignParticipantStatus {
    final data = _participantStatusData ?? const <String, dynamic>{};
    final raw = '${data['status'] ?? data['campaignStatus'] ?? ''}';
    if (raw == 'waiting_for_match') return 'paid_waiting_for_match';
    if (raw == 'ready_for_delivery_planning') return 'ready_for_gift_delivery';
    if (raw.isNotEmpty) return raw;
    final matchStatus = '${data['matchStatus'] ?? ''}';
    if (matchStatus == 'match_found') return 'match_found';
    if (matchStatus == 'approved') return 'admin_pairing_approved';
    return 'paid_waiting_for_match';
  }

  _CampaignStatusCopy get _campaignStatusCopy {
    return switch (_campaignParticipantStatus) {
      'match_found' => const _CampaignStatusCopy(
          title: 'Anonymous match found',
          subtitle:
              'A compatible anonymous match is ready. Private identity remains protected.',
          body:
              'Your match has been found from shared interests and safety checks. We only show what the policy allows.',
          privacyNote:
              'Names, photos, addresses and private details remain hidden unless GiftsSocialPolicy allows reveal.',
          showAnonymousMatchSummary: true,
        ),
      'admin_pairing_pending' => const _CampaignStatusCopy(
          title: 'Pairing under review',
          subtitle:
              'The Gifts Team is reviewing the safe anonymous pairing before anything moves forward.',
          body:
              'Admin is checking compatibility, consent and restrictions. You do not need to do anything yet.',
          privacyNote: 'The match stays anonymous while review is pending.',
        ),
      'admin_pairing_approved' => const _CampaignStatusCopy(
          title: 'Pairing approved',
          subtitle: 'The Gifts Team approved the safe anonymous match.',
          body:
              'The pairing has passed policy review and can move into the internal Gifts workflow.',
          privacyNote:
              'Identity remains protected. Reveal timing is still governed by consent settings.',
          showAnonymousMatchSummary: true,
        ),
      'gift_request_linked' => const _CampaignStatusCopy(
          title: 'Gift journey linked',
          subtitle: 'The operational Gifts request is now linked internally.',
          body:
              'Campaign context, safety notes and anonymous compatibility now travel with the internal request.',
          privacyNote:
              'No known-recipient form is shown in Campaign. Details stay controlled by Admin and policy.',
        ),
      'gifts_team_curating' => const _CampaignStatusCopy(
          title: 'Gifts Team is curating',
          subtitle:
              'The concierge team is shaping the anonymous gift experience.',
          body:
              'The team is using compatibility, safety and consent notes to plan the next operational step.',
          privacyNote:
              'Private identity and handover details remain hidden from the sender.',
        ),
      'ready_for_gift_delivery' ||
      'ready_for_delivery_planning' =>
        const _CampaignStatusCopy(
          title: 'Ready for Gift Delivery',
          subtitle:
              'Your campaign journey is complete. Your gift is now moving into the standard Circum Gifts delivery workflow.',
          body:
              'Track fulfilment from the normal Gifts delivery experience. Campaign will stay here as the handoff record.',
          privacyNote:
              'Campaign does not show delivery tracking or delivered status. Delivery completion comes only from the linked Gift Delivery workflow.',
          showHandoff: true,
        ),
      _ => const _CampaignStatusCopy(
          title: 'Waiting for your match',
          subtitle:
              "We'll protect everyone's privacy until a safe match has been approved.",
          body:
              'Your campaign participation is paid and waiting for a compatible, policy-safe match.',
          privacyNote:
              'No recipient name, photo, address or private details are shown at this stage.',
        ),
    };
  }

  String? get _campaignStatusTimestampLabel {
    final data = _participantStatusData ?? const <String, dynamic>{};
    final value =
        data['statusUpdatedAt'] ?? data['updatedAt'] ?? data['paidAt'];
    final date = switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      DateTime dateTime => dateTime,
      String raw => DateTime.tryParse(raw),
      _ => null,
    };
    if (date == null) return null;
    return _formatStatusDate(date.toLocal());
  }

  String get _anonymousMatchSummary {
    final safe = GiftsSocialPolicy.recipientSafeView(
      _approvedMatch ?? const <String, dynamic>{},
    );
    final shared = ((safe['sharedInterests'] as List?) ?? const [])
        .map((value) => '$value')
        .where((value) => value.isNotEmpty)
        .toList();
    if (shared.isEmpty) {
      return 'A safe anonymous match is ready. Shared details appear only when policy allows.';
    }
    return 'You both connect around ${shared.join(', ')}.';
  }

  bool get _linkedGiftStoryUnlocked => _campaignStoryDraft.giftStoryUnlocked;

  GiftJourneyDraft get _campaignStoryDraft {
    final data = _participantStatusData ?? const <String, dynamic>{};
    return GiftJourneyDraft.forMode(SenderGiftMode.campaign).copyWith(
      campaignId: '${data['campaignId'] ?? _campaign?.id ?? ''}',
      campaignName: '${data['campaignName'] ?? _campaign?.name ?? ''}',
      campaignType: '${data['campaignType'] ?? _campaign?.type ?? ''}',
      campaignTagline: '${data['campaignTagline'] ?? _campaign?.tagline ?? ''}',
      campaignParticipantId: _participantId ?? '${data['id'] ?? ''}',
      giftRequestId:
          '${data['giftRequestId'] ?? data['linkedGiftRequestId'] ?? ''}',
      giftDeliveryId:
          '${data['giftDeliveryId'] ?? data['linkedGiftDeliveryId'] ?? ''}',
      linkedGiftDeliveryStatus:
          '${data['linkedGiftDeliveryStatus'] ?? data['giftDeliveryStatus'] ?? ''}',
      riderCompletionAccepted: _truthy(data['riderCompletionAccepted']) ||
          _truthy(data['riderCompletionAcceptedAt']),
      deliveryVerificationCompleted:
          _truthy(data['deliveryVerificationCompleted']) ||
              _truthy(data['requiredDeliveryVerificationCompleted']) ||
              _truthy(data['deliveryPinVerified']) ||
              _truthy(data['photoProofAccepted']) ||
              _truthy(data['signatureAccepted']),
      deliveryAuditSuccessful: _truthy(data['deliveryAuditSuccessful']) ||
          _truthy(data['backendDeliveryAuditSuccessful']),
      activeDeliveryDispute: _truthy(data['activeDeliveryDispute']) ||
          _truthy(data['hasActiveDeliveryDispute']) ||
          _truthy(data['deliveryInvestigationActive']) ||
          _truthy(data['activeDeliveryInvestigation']),
      giftStoryAdminOverride: data['giftStoryAdminOverride'] == true,
      giftStoryAdminUserId:
          '${data['giftStoryAdminUserId'] ?? data['adminUserId'] ?? ''}',
      giftStoryAdminOverrideReason:
          '${data['giftStoryAdminOverrideReason'] ?? data['overrideReason'] ?? ''}',
      giftStoryAdminOverrideAt:
          _stringValue(data['giftStoryAdminOverrideAt'] ?? data['overrideAt']),
      giftStoryPreviousStatus:
          '${data['giftStoryPreviousStatus'] ?? data['previousStoryStatus'] ?? ''}',
      giftStoryOverrideType:
          '${data['giftStoryOverrideType'] ?? data['overrideType'] ?? ''}',
    );
  }

  static String _stringValue(Object? value) {
    if (value == null) return '';
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    return '$value';
  }

  static bool _truthy(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is Timestamp || value is DateTime) return true;
    if (value is num) return value != 0;
    final text = '$value'.trim().toLowerCase();
    return text == 'true' ||
        text == 'yes' ||
        text == 'completed' ||
        text == 'accepted' ||
        text == 'successful';
  }

  String _formatStatusDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} ${date.year} · $hour:$minute';
  }

  bool get _canContinue {
    return switch (_step) {
      0 => true,
      1 => _campaign != null,
      2 => _hasAboutSignal,
      3 => true,
      4 => true,
      5 => _budget >= 50,
      6 => true,
      7 => !_submitting && _paymentMethod.isNotEmpty,
      8 => false,
      _ => false,
    };
  }

  @override
  void initState() {
    super.initState();
    _loadRothBalance();
    _listenForVisibleMatch();
  }

  @override
  void dispose() {
    _participantSub?.cancel();
    _matchSub?.cancel();
    _visibleMatchSub?.cancel();
    _displayNameController.dispose();
    _customInspirationController.dispose();
    _allergiesController.dispose();
    _dietaryController.dispose();
    _medicalController.dispose();
    _culturalController.dispose();
    _avoidController.dispose();
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
        enabled: _footerAction != null,
        label: _footerLabel,
        onTap: _footerAction,
      ),
    );
  }

  String get _footerLabel {
    if (_step == 8 && _linkedGiftStoryUnlocked) return 'View Gift Story';
    return _primaryLabel;
  }

  VoidCallback? get _footerAction {
    if (_step == 8 && _linkedGiftStoryUnlocked) {
      return () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GiftStoryView(draft: _campaignStoryDraft),
              settings: const RouteSettings(name: GiftStoryView.routeName),
            ),
          );
    }
    return _canContinue ? _goNext : null;
  }

  String get _eyebrow => switch (_step) {
        0 => 'CAMPAIGN',
        1 => 'STEP 01 — JOIN CAMPAIGN',
        2 => 'STEP 02 — ABOUT YOU',
        3 => 'STEP 03 — SAFETY',
        4 => 'STEP 04 — PRIVACY',
        5 => 'STEP 05 — BUDGET',
        6 => 'STEP 06 — REVIEW',
        7 => 'STEP 07 — PAYMENT',
        8 => 'CAMPAIGN STATUS',
        _ => 'CAMPAIGN',
      };

  String get _title => switch (_step) {
        0 => 'Bring London Closer',
        1 => 'Choose campaign',
        2 => 'About you',
        3 => 'Safety',
        4 => 'Privacy',
        5 => 'Campaign gift budget',
        6 => 'Review your campaign participation',
        7 => 'Secure participation',
        8 => _campaignStatusCopy.title,
        _ => 'Campaign',
      };

  String get _subtitle => switch (_step) {
        0 =>
          'Join an anonymous gift exchange shaped around shared interests, safety and consent.',
        1 => 'Choose the campaign you want to join.',
        2 =>
          'Share the participant signals used for anonymous matching. No recipient fields here.',
        3 =>
          'These notes help IRIS recommend only gifts that satisfy recorded safety requirements.',
        4 => 'Your identity stays private unless the reveal policy allows it.',
        5 => 'Set the budget for your anonymous campaign gift.',
        6 =>
          'No recipient, delivery address or delivery date is collected yet.',
        7 => 'Pay with Roth, card, or Roth plus card.',
        8 => _campaignStatusCopy.subtitle,
        _ => '',
      };

  String get _primaryLabel => switch (_step) {
        0 => 'Join Campaign',
        7 => _submitting ? 'Processing...' : 'Continue to Secure Payment',
        8 => 'Status updates automatically',
        _ => 'Continue',
      };

  List<Widget> get _children => switch (_step) {
        0 => _homeChildren,
        1 => _campaignChildren,
        2 => _aboutChildren,
        3 => _safetyChildren,
        4 => _privacyChildren,
        5 => _budgetChildren,
        6 => _reviewChildren,
        7 => _paymentChildren,
        8 => _campaignStatusChildren,
        _ => const <Widget>[],
      };

  List<Widget> get _homeChildren => [
        const _CampaignGlassCard(
          title: 'Anonymous exchange',
          body:
              'People anonymously exchange thoughtful gifts with others who share similar interests.',
        ),
        const SizedBox(height: 12),
        const _CampaignGlassCard(
          title: 'Policy protected',
          body:
              'Circum never reveals identities until GiftsSocialPolicy allows it.',
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
        GiftJourneyWidgets.inputCard(
          controller: _displayNameController,
          label: 'ANONYMOUS HANDLE',
          placeholder: 'What should the Gifts Team call you?',
          helper: 'This is not shown to your match.',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
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
        _chipSection('Food preferences', 'favouriteFoodsDrinks', const [
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
        const SizedBox(height: 4),
        GiftJourneyWidgets.inputCard(
          controller: _customInspirationController,
          label: 'ADD YOUR OWN INSPIRATION',
          placeholder: 'Write your own inspiration...',
          helper:
              'Choose from the ideas above, then add anything personal: memories, inside jokes, colours, places, dreams, style, dislikes, or the kind of person you want to meet.',
          onChanged: (_) => setState(() {}),
          maxLines: 4,
        ),
      ];

  List<Widget> get _safetyChildren => [
        GiftJourneyWidgets.inputCard(
          controller: _allergiesController,
          label: 'ALLERGIES',
          placeholder: 'Nuts, dairy, gluten...',
          helper: 'Used for automatic exclusion.',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _dietaryController,
          label: 'DIETARY RESTRICTIONS',
          placeholder: 'Vegan, halal, no alcohol...',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _medicalController,
          label: 'MEDICAL RESTRICTIONS',
          placeholder: 'Anything relevant to gifts',
          onChanged: (_) => setState(() {}),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _culturalController,
          label: 'CULTURAL OR RELIGIOUS CONSIDERATIONS',
          placeholder: 'Anything the Gifts Team should respect',
          onChanged: (_) => setState(() {}),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _avoidController,
          label: 'THINGS TO AVOID',
          placeholder: 'Perfume, flowers, jewellery...',
          onChanged: (_) => setState(() {}),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _blockedController,
          label: 'PEOPLE TO AVOID',
          placeholder: 'Name, handle, phone, or email if known',
          helper:
              'Optional. Add anyone you do not want to be matched with, if applicable.',
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

  List<Widget> get _budgetChildren => [
        _CampaignGlassCard(
          title: 'Experience Budget',
          body: '£${_budget.toStringAsFixed(0)}',
        ),
        Slider(
          value: _budget,
          min: 50,
          max: 1500,
          divisions: 29,
          activeColor: const Color(0xFFC9B8FF),
          inactiveColor: Colors.white.withValues(alpha: .12),
          label: '£${_budget.toStringAsFixed(0)}',
          onChanged: (value) => setState(() => _budget = value.roundToDouble()),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in const [50, 100, 250, 500, 1000, 1500])
              GiftJourneyWidgets.choiceChip(
                label: '£$value',
                selected: _budget == value,
                onTap: () => setState(() => _budget = value.toDouble()),
              ),
          ],
        ),
      ];

  List<Widget> get _reviewChildren => [
        _CampaignGlassCard(
          title: 'Campaign',
          body: _campaign?.name ?? 'Choose campaign',
        ),
        const SizedBox(height: 12),
        _CampaignGlassCard(
          title: 'Participant interests',
          body: _reviewList([
            ..._selected['interests']!,
            ..._selected['hobbies']!,
            ..._selected['musicTaste']!,
            ..._selected['booksFilms']!,
          ]),
        ),
        const SizedBox(height: 12),
        _CampaignGlassCard(
          title: 'Safety notes',
          body: _reviewList([
            _allergiesController.text,
            _dietaryController.text,
            _medicalController.text,
            _culturalController.text,
            _avoidController.text,
          ]),
        ),
        const SizedBox(height: 12),
        _CampaignGlassCard(title: 'Privacy mode', body: _senderRevealModeLabel),
        const SizedBox(height: 12),
        _CampaignGlassCard(
          title: 'Budget',
          body: '£${_budget.toStringAsFixed(0)}',
        ),
        const SizedBox(height: 12),
        const _CampaignGlassCard(
          title: 'No recipient yet',
          body:
              'Delivery address, recipient identity and handover details are handled after admin pairing approval.',
        ),
      ];

  List<Widget> get _paymentChildren => [
        _CampaignGlassCard(
          title: 'Gift Total',
          body: '£${_budget.toStringAsFixed(0)}',
        ),
        const SizedBox(height: 10),
        _CampaignGlassCard(
          title: 'Available Roth',
          body: _rothLoading
              ? 'Checking Roth balance...'
              : _rothUnavailable
                  ? 'Roth unavailable'
                  : '£${_rothBalance.toStringAsFixed(0)}',
        ),
        const SizedBox(height: 14),
        _chipSection('Payment method', 'paymentMethod', const [
          'Card',
          'Roth',
          'Roth + Card',
        ]),
        if (_paymentMethod != 'Card' && _rothBalance > 0) ...[
          const SizedBox(height: 12),
          _CampaignToggle(
            label: 'Apply Roth balance',
            value: _applyRoth,
            onChanged: (value) => setState(() => _applyRoth = value),
          ),
          const SizedBox(height: 10),
          _CampaignGlassCard(
            title: 'Roth applied',
            body: '£${_rothApplied.toStringAsFixed(0)}',
          ),
        ],
        const SizedBox(height: 10),
        _CampaignGlassCard(
          title: 'Remaining card amount',
          body: '£${_cardAmount.toStringAsFixed(0)}',
        ),
        const SizedBox(height: 12),
        _CampaignGlassCard(
          title: 'Payment',
          body: _submitting
              ? 'Processing payment...'
              : (_message ?? 'Payment ready'),
        ),
      ];

  List<Widget> get _campaignStatusChildren {
    final copy = _campaignStatusCopy;
    final timestamp = _campaignStatusTimestampLabel;
    return [
      AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFC9B8FF).withValues(alpha: .32),
          ),
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
              copy.title,
              style: GoogleFonts.dmSerifDisplay(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              copy.body,
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
      SizedBox(height: 12),
      _CampaignGlassCard(
        title: 'Privacy and safety',
        body: copy.privacyNote,
      ),
      if (timestamp != null) ...[
        const SizedBox(height: 12),
        _CampaignGlassCard(title: 'Last updated', body: timestamp),
      ],
      if (copy.showAnonymousMatchSummary) ...[
        const SizedBox(height: 12),
        _CampaignGlassCard(
          title: 'Anonymous compatibility',
          body: _anonymousMatchSummary,
        ),
      ],
      if (copy.showHandoff) ...[
        const SizedBox(height: 12),
        _CampaignGlassCard(
          title: 'Ready for Gift Delivery',
          body:
              'Your campaign journey is complete. Your gift is now moving into the standard Circum Gifts delivery workflow.',
        ),
        const SizedBox(height: 12),
        _CampaignGlassCard(
          title: _linkedGiftStoryUnlocked
              ? 'Your Gift Story is ready'
              : 'Gift Story locked',
          body: _linkedGiftStoryUnlocked
              ? 'View Gift Story'
              : _campaignStoryDraft.giftStoryManuallyLocked
                  ? 'This story is currently under review.'
                  : 'Your story will unlock after delivery is confirmed.',
        ),
      ],
      if (_visibleRevealedMatch != null) ...[
        const SizedBox(height: 12),
        const _CampaignGlassCard(
          title: 'Your campaign match is now revealed.',
          body:
              'View Match. We only show the identity details both participants agreed to reveal.',
        ),
      ] else if (_linkedGiftStoryUnlocked) ...[
        const SizedBox(height: 12),
        const _CampaignGlassCard(
          title: 'Waiting for mutual reveal consent.',
          body:
              'Your Gift Story is unlocked, but the match profile appears only after both people agree to identity reveal.',
        ),
      ],
      const SizedBox(height: 12),
      const _CampaignGlassCard(
        title: 'Recipient details',
        body:
            'Recipient details are collected only after a compatible match has been approved. Until then, both participants remain protected.',
      ),
    ];
  }

  Widget _chipSection(String title, String key, List<String> options) {
    if (key == 'senderRevealMode') {
      return _singleChoiceSection(
        title,
        options,
        selected: _senderRevealModeLabel,
        onSelected: (option) => setState(() {
          _senderRevealMode = switch (option) {
            'Reveal immediately' => 'reveal_immediately',
            'Reveal after delivery' => 'reveal_after_delivery',
            _ => 'mutual_consent',
          };
        }),
      );
    }
    if (key == 'paymentMethod') {
      return _singleChoiceSection(
        title,
        options,
        selected: _paymentMethod,
        onSelected: (option) => setState(() {
          _paymentMethod = option;
          _applyRoth = option != 'Card' && _rothBalance > 0;
        }),
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

  Widget _singleChoiceSection(
    String title,
    List<String> options, {
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
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
                selected: selected == option,
                onTap: () => onSelected(option),
              ),
          ],
        ),
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

  Future<void> _goNext() async {
    if (_step == 7) {
      await _submitCampaignParticipant();
      return;
    }
    if (_step == 8) return;
    setState(() => _step += 1);
  }

  Future<void> _loadRothBalance() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(senderGiftRothBalanceCallableName)
          .call();
      final data = Map<String, dynamic>.from(result.data as Map);
      final balance = (data['availableRoth'] ?? data['balance'] ?? 0) as num;
      if (!mounted) return;
      setState(() {
        _rothBalance = balance.toDouble();
        _rothLoading = false;
        _rothUnavailable = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rothBalance = 0;
        _rothLoading = false;
        _rothUnavailable = true;
      });
    }
  }

  Future<void> _submitCampaignParticipant() async {
    if (_canBypassCampaignPaymentForLocalPreview) {
      setState(() {
        _participantId ??= 'local-preview-campaign-participant';
        _message = null;
        _participantStatusData = const {
          'status': 'paid_waiting_for_match',
          'campaignStatus': 'paid_waiting_for_match',
        };
        _step = 8;
      });
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _message = 'Sign in to join this campaign.';
      });
      return;
    }
    if (_paymentMethod == 'Roth' && _rothBalance < _budget) {
      setState(() {
        _message = 'Roth balance is not enough for this campaign gift.';
      });
      return;
    }
    if (_paymentMethod == 'Roth + Card' && _rothBalance <= 0) {
      setState(() {
        _message = 'Roth is unavailable. Choose card to continue securely.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      final campaign = _campaign ?? _campaigns.first;
      final participant = _participantPayload(user.uid, user.email ?? '');
      final result = GiftsSocialPolicy.scoreMatch(
        participant,
        _policyOnlyMatchEligibilityPreview(campaign),
      );
      if (result.score == 0) {
        throw StateError(
          'Your payment is ready. IRIS will recommend only gifts that satisfy all recorded safety requirements.',
        );
      }
      final payment = await FirebaseFunctions.instance
          .httpsCallable(senderGiftPaymentCallableName)
          .call({
        'source': senderGiftCampaignPaymentSource,
        'returnOwner': 'sender_app',
        'campaignParticipant': participant,
        'applyRoth': _wantsRoth,
        'paymentMethod': _verifiedPaymentMethod,
        'grossGiftBudget': _budget,
      });
      final data = Map<String, dynamic>.from(payment.data as Map);
      _participantId = '${data['campaignParticipantId'] ?? ''}'.trim().isEmpty
          ? null
          : '${data['campaignParticipantId']}';
      if (data['walletPaidInFull'] == true ||
          data['campaignParticipantPaid'] == true) {
        _listenForApprovedMatch();
        _listenForParticipantStatus();
      } else {
        final checkoutUrl = Uri.tryParse('${data['url'] ?? ''}');
        if (checkoutUrl == null || checkoutUrl.host.isEmpty) {
          throw StateError('Secure checkout could not be opened.');
        }
        final opened = await launchUrl(checkoutUrl, webOnlyWindowName: '_self');
        if (!opened) throw StateError('Secure checkout could not be opened.');
        return;
      }
      _listenForApprovedMatch();
      _listenForParticipantStatus();
      if (!mounted) return;
      setState(() => _step = 8);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error is FirebaseFunctionsException
            ? (error.message ?? 'Could not secure campaign participation.')
            : '$error'.replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool get _canBypassCampaignPaymentForLocalPreview {
    return _isLocalCampaignPaymentPreview();
  }

  void _listenForApprovedMatch() {
    final participantId = _participantId;
    if (participantId == null) return;
    _matchSub?.cancel();
    _matchSub = FirebaseFirestore.instance
        .collection(senderGiftCampaignMatchesCollectionName)
        .where('participantIds', arrayContains: participantId)
        .where('adminStatus', isEqualTo: 'approved')
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (!mounted || snapshot.docs.isEmpty) return;
      setState(() {
        _approvedMatch = snapshot.docs.first.data();
      });
    });
  }

  void _listenForVisibleMatch() {
    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
    } catch (_) {
      return;
    }
    if (user == null) return;
    _visibleMatchSub?.cancel();
    _visibleMatchSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('matches')
        .where('source', isEqualTo: 'gift_campaign')
        .where('status', isEqualTo: 'revealed')
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _visibleRevealedMatch =
            snapshot.docs.isEmpty ? null : snapshot.docs.first.data();
      });
    });
  }

  void _listenForParticipantStatus() {
    final participantId = _participantId;
    if (participantId == null) return;
    _participantSub?.cancel();
    _participantSub = FirebaseFirestore.instance
        .collection(senderGiftCampaignParticipantsCollectionName)
        .doc(participantId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted || !snapshot.exists) return;
      setState(() => _participantStatusData = snapshot.data());
    });
    _listenForVisibleMatch();
  }

  Map<String, dynamic> _participantPayload(String userId, String email) {
    final campaign = _campaign ?? _campaigns.first;
    return {
      'userId': userId,
      'email': email,
      ...GiftSystemPolicy.progressPatch(
        userId: userId,
        email: email,
        giftType: GiftSystemPolicy.campaignGiftType,
        flowStatus: 'draft',
        currentStep: _step + 1,
        completedSteps: List<int>.generate(_step, (index) => index + 1),
        paymentStatus: 'payment_pending',
        deliveryStatus: 'not_started',
        storyStatus: 'locked',
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      ),
      'displayName': _displayNameController.text.trim(),
      'campaignId': campaign.id,
      'campaignName': campaign.name,
      'campaignType': campaign.type,
      'campaignTagline': campaign.tagline,
      'matchConsent': true,
      'matchStatus': 'awaiting_admin_pairing',
      'interests': _selected['interests']!.toList(),
      'hobbies': _selected['hobbies']!.toList(),
      'musicTaste': _selected['musicTaste']!.toList(),
      'booksFilms': _selected['booksFilms']!.toList(),
      'favouriteFoodsDrinks': _selected['favouriteFoodsDrinks']!.toList(),
      'lifestyle': _selected['lifestyle']!.toList(),
      'preferredGiftCategories': _selected['preferredGiftCategories']!.toList(),
      'customInspiration': _customInspirationController.text.trim(),
      'allergies': _commaList(_allergiesController.text),
      'dietaryRestrictions': _dietaryController.text.trim(),
      'medicalRestrictions': _medicalController.text.trim(),
      'culturalOrReligiousConsiderations': _culturalController.text.trim(),
      'thingsToAvoid': _avoidController.text.trim(),
      'blockedUserIds': _commaList(_blockedController.text),
      'avoidanceSignals': _commaList(_blockedController.text),
      'senderRevealMode': _senderRevealMode,
      'senderRevealConsent': 'pending',
      'recipientRevealRequestStatus': 'pending',
      'recipientContentConsent':
          _recipientContentConsent ? 'granted' : 'not_requested',
      'allowCircumSocialUse': _allowCircumSocialUse,
      'allowPublicPosting': _allowPublicPosting,
      'allowBrandTagging': _allowBrandTagging,
      'budget': _budget,
      'grossGiftBudget': _budget,
      'budgetPrivacyNote':
          'Budgets are private. Matching is based on compatibility and safety, not spend. Each participant funds their own gift.',
      'paymentMethod': 'card',
      'rothApplied': 0,
      'cardAmount': _budget,
      'walletContributionGbp': 0,
      'remainingStripeAmountGbp': _budget,
      'paymentStatus': 'payment_pending',
      'status': 'join_started',
      'campaignStatus': 'join_started',
      'source': senderGiftCampaignPaymentSource,
      'campaignParticipantId': null,
      'giftRequestId': null,
      'giftDeliveryId': null,
      'linkedGiftDeliveryStatus': 'not_started',
      'handoffStatus': 'not_ready',
      'giftRequestCreated': false,
      'recipientKnown': false,
      'deliveryCollected': false,
    };
  }

  Map<String, dynamic> _policyOnlyMatchEligibilityPreview(
    _CampaignOption campaign,
  ) =>
      {
        'userId': 'admin-approved-${campaign.id}',
        'matchConsent': true,
        'matchStatus': 'active',
        'interests': _selected['interests']!.toList(),
        'hobbies': _selected['hobbies']!.toList(),
        'musicTaste': _selected['musicTaste']!.toList(),
        'booksFilms': _selected['booksFilms']!.toList(),
        'favouriteFoodsDrinks': _selected['favouriteFoodsDrinks']!.toList(),
        'preferredGiftCategories':
            _selected['preferredGiftCategories']!.toList(),
        'allergies': const <String>[],
        'blockedUserIds': const <String>[],
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

  static String _reviewList(Iterable<String> values) {
    final clean = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return clean.isEmpty ? 'Not added' : clean.join(', ');
  }

  static List<String> _commaList(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
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

class _CampaignStatusCopy {
  final String title;
  final String subtitle;
  final String body;
  final String privacyNote;
  final bool showAnonymousMatchSummary;
  final bool showHandoff;

  const _CampaignStatusCopy({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.privacyNote,
    this.showAnonymousMatchSummary = false,
    this.showHandoff = false,
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
  Widget build(BuildContext context) => AppGlassContainer(
      padding: const EdgeInsets.all(18),
      radius: 20,
      accent: const Color(0xFFC9B8FF),
      surfaceColor: Colors.white.withValues(alpha: .052),
      borderColor: Colors.white.withValues(alpha: .10),
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
      ));
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
              'Join a campaign, share safe matching signals, set privacy and budget, then wait for Admin-approved anonymous pairing. Delivery details are handled only after matching.',
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
