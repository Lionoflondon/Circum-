class GiftSystemPolicy {
  static const sendToSomeoneGiftType = 'send_to_someone';
  static const sendToMeGiftType = 'send_to_me';
  static const campaignGiftType = 'campaign';
  static const anonymousGiftType = 'anonymous';
  static const normalGiftType = sendToSomeoneGiftType;

  static const giftTypes = [
    sendToSomeoneGiftType,
    sendToMeGiftType,
    campaignGiftType,
    anonymousGiftType,
  ];

  static const backendFields = [
    'giftId',
    'giftType',
    'userId',
    'email',
    'flowStatus',
    'currentStep',
    'completedSteps',
    'paymentStatus',
    'deliveryStatus',
    'storyStatus',
    'approvalStatus',
    'curationStatus',
    'giftRequestId',
    'giftDeliveryId',
    'notificationStatus',
    'createdAt',
    'updatedAt',
    'lastActiveAt',
  ];

  static const campaignBackendFields = [
    'campaignStatus',
    'matchStatus',
    'revealPolicy',
    'linkedGiftId',
    'linkedParticipantId',
  ];

  static const sendToMeBackendFields = [
    'selfGiftFrequency',
    'stripeMode',
    'stripeSubscriptionId',
    'subscriptionStatus',
    'subscriptionInterval',
    'subscriptionIntervalCount',
    'cancelAtPeriodEnd',
  ];

  static const canonicalLifecycle = [
    'draft',
    'submitted',
    'paid',
    'approved',
    'curating',
    'ready_for_gift_delivery',
    'in_delivery',
    'delivered',
    'story_locked',
    'story_unlocked',
  ];

  static const matchLifecycle = [
    'waiting_for_match',
    'match_found',
    'match_review_required',
    'match_confirmed',
  ];

  static const filters = [
    'draft',
    'submitted',
    'paid',
    'waiting_for_match',
    'match_found',
    'admin_review_required',
    'approved',
    'curating',
    'ready_for_gift_delivery',
    'in_delivery',
    'delivered',
    'story_locked',
    'story_unlocked',
    'disputed',
  ];

  static const notificationEvents = [
    'gift_draft_saved',
    'gift_submitted',
    'payment_succeeded',
    'payment_failed',
    'subscription_created',
    'subscription_cancelled',
    'campaign_waiting_for_match',
    'campaign_match_found',
    'campaign_match_confirmed',
    'gift_approved',
    'gift_rejected',
    'curation_started',
    'ready_for_gift_delivery',
    'delivery_started',
    'rider_assigned',
    'gift_delivered',
    'story_locked',
    'story_unlocked',
    'story_manually_locked',
    'story_manually_unlocked',
    'issue_raised',
    'dispute_opened',
    'dispute_resolved',
  ];

  static Map<String, Object?> progressPatch({
    String? giftId,
    required String userId,
    required String email,
    required String giftType,
    required String flowStatus,
    required int currentStep,
    required List<int> completedSteps,
    String paymentStatus = 'payment_pending',
    String deliveryStatus = 'not_started',
    String storyStatus = 'locked',
    String approvalStatus = 'draft',
    String curationStatus = 'not_started',
    String? giftRequestId,
    String? giftDeliveryId,
    String notificationStatus = 'none',
    Map<String, Object?> pathFields = const {},
    Object? createdAt,
    required Object updatedAt,
    Object? lastActiveAt,
  }) {
    final normalizedType = normalizeGiftType(giftType);
    return {
      if (giftId != null && giftId.trim().isNotEmpty) 'giftId': giftId.trim(),
      'userId': userId,
      'email': email.trim().toLowerCase(),
      'giftType': normalizedType,
      'flowStatus': flowStatus,
      'currentStep': currentStep,
      'completedSteps': completedSteps,
      'paymentStatus': paymentStatus,
      'deliveryStatus': deliveryStatus,
      'storyStatus': storyStatus,
      'approvalStatus': approvalStatus,
      'curationStatus': curationStatus,
      'giftRequestId': giftRequestId?.trim() ?? '',
      'giftDeliveryId': giftDeliveryId?.trim() ?? '',
      'notificationStatus': notificationStatus,
      ...pathFields,
      'createdAt': createdAt ?? updatedAt,
      'updatedAt': updatedAt,
      'lastActiveAt': lastActiveAt ?? updatedAt,
    };
  }

  static Map<String, Object?> canonicalRecord({
    required String giftId,
    required String giftType,
    required String userId,
    required String email,
    String flowStatus = 'draft',
    int currentStep = 1,
    List<int> completedSteps = const [],
    String paymentStatus = 'payment_pending',
    String deliveryStatus = 'not_started',
    String storyStatus = 'locked',
    String approvalStatus = 'draft',
    String curationStatus = 'not_started',
    String? giftRequestId,
    String? giftDeliveryId,
    String notificationStatus = 'none',
    Object? createdAt,
    required Object updatedAt,
    Object? lastActiveAt,
    Map<String, Object?> pathFields = const {},
  }) =>
      progressPatch(
        giftId: giftId,
        userId: userId,
        email: email,
        giftType: giftType,
        flowStatus: flowStatus,
        currentStep: currentStep,
        completedSteps: completedSteps,
        paymentStatus: paymentStatus,
        deliveryStatus: deliveryStatus,
        storyStatus: storyStatus,
        approvalStatus: approvalStatus,
        curationStatus: curationStatus,
        giftRequestId: giftRequestId,
        giftDeliveryId: giftDeliveryId,
        notificationStatus: notificationStatus,
        pathFields: pathFields,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastActiveAt: lastActiveAt,
      );

  static String normalizeGiftType(Object? value) {
    final raw = _status(value);
    return switch (raw) {
      'normal' || 'send_to_someone' || 'someone' => sendToSomeoneGiftType,
      'send_to_me' || 'self' || 'myself' => sendToMeGiftType,
      'campaign' || 'campaign_gift' || 'anonymous_campaign' => campaignGiftType,
      'anonymous' || 'anonymous_gift' => anonymousGiftType,
      _ => sendToSomeoneGiftType,
    };
  }

  static String resumeRoute(Map<String, dynamic> gift) {
    final state = resolve(gift);
    if (state.storyStatus == 'unlocked') return '/sender-mobile/gifts/story';
    if (state.deliveryStatus == 'delivered') {
      return '/sender-mobile/gifts/story';
    }
    if (state.deliveryStatus == 'in_delivery' ||
        state.deliveryStatus == 'rider_assigned' ||
        state.deliveryStatus == 'out_for_delivery') {
      return '/sender-mobile/gifts/status';
    }
    if ([
      'submitted',
      'paid',
      'approved',
      'curating',
      'ready_for_gift_delivery',
    ].contains(state.flowStatus)) {
      return state.giftType == campaignGiftType
          ? '/sender-mobile/gifts/campaign'
          : '/sender-mobile/gifts/status';
    }
    if (state.paymentStatus == 'paid') {
      return state.giftType == campaignGiftType
          ? '/sender-mobile/gifts/campaign'
          : '/sender-mobile/gifts/status';
    }
    final currentStep = state.currentStep;
    return routeForStep(currentStep <= 0 ? 1 : currentStep);
  }

  static String routeForStep(int step) {
    return switch (step) {
      1 => '/sender-mobile/gifts/relationship',
      2 => '/sender-mobile/gifts/relationship',
      3 => '/sender-mobile/gifts/delivery',
      4 => '/sender-mobile/gifts/message',
      5 => '/sender-mobile/gifts/voice-note',
      6 => '/sender-mobile/gifts/themes',
      7 => '/sender-mobile/gifts/iris',
      8 => '/sender-mobile/gifts/style',
      9 => '/sender-mobile/gifts/privacy',
      10 => '/sender-mobile/gifts/budget',
      11 => '/sender-mobile/gifts/review',
      12 => '/sender-mobile/gifts/payment',
      13 => '/sender-mobile/gifts/status',
      _ => '/sender-mobile/gifts',
    };
  }

  static List<Map<String, dynamic>> filterGifts(
    Iterable<Map<String, dynamic>> records,
    String filter,
  ) {
    if (filter.trim().isEmpty || filter == 'all') return records.toList();
    return records.where((record) => _matchesFilter(record, filter)).toList();
  }

  static bool _matchesFilter(Map<String, dynamic> record, String filter) {
    final state = resolve(record);
    return switch (filter) {
      'delivered' => state.deliveryStatus == 'delivered',
      'in_delivery' => [
          'in_delivery',
          'rider_assigned',
          'out_for_delivery',
          'delivery_started',
        ].contains(state.deliveryStatus),
      'story_locked' => state.storyStatus == 'locked',
      'story_unlocked' => state.storyStatus == 'unlocked',
      _ => statusBucket(record) == filter,
    };
  }

  static String statusBucket(Map<String, dynamic> record) {
    final state = resolve(record);
    final storyStatus = state.storyStatus;
    if (storyStatus == 'unlocked') return 'story_unlocked';
    if (storyStatus == 'locked' && state.flowStatus == 'delivered') {
      return 'story_locked';
    }
    if (_truthy(record['activeDeliveryDispute']) ||
        _truthy(record['deliveryInvestigationActive']) ||
        _status(record['flowStatus']).contains('dispute')) {
      return 'disputed';
    }
    final deliveryStatus = state.deliveryStatus;
    if (deliveryStatus == 'delivered') return 'delivered';
    if (deliveryStatus == 'in_delivery' ||
        deliveryStatus == 'rider_assigned' ||
        deliveryStatus == 'out_for_delivery') {
      return 'in_delivery';
    }
    final status = state.flowStatus;
    if (status == 'ready_for_gift_delivery') return 'ready_for_gift_delivery';
    if (status == 'gifts_team_curating' || status == 'curating') {
      return 'curating';
    }
    if (status == 'approved' || status == 'admin_pairing_approved') {
      return 'approved';
    }
    if (status == 'admin_review_required' ||
        status == 'admin_pairing_pending') {
      return 'admin_review_required';
    }
    if (status == 'match_found') return 'match_found';
    if (status == 'paid_waiting_for_match' || status == 'waiting_for_match') {
      return 'waiting_for_match';
    }
    if (_status(record['paymentStatus']) == 'paid' || status == 'paid') {
      return 'paid';
    }
    if (status == 'submitted' || status == 'pending_approval') {
      return 'submitted';
    }
    return 'draft';
  }

  static Map<String, Object?> adminActionPatch({
    required String adminUserId,
    String? adminEmail,
    required String actionType,
    required String previousStatus,
    required String newStatus,
    required String reason,
    required Object actionAt,
  }) {
    if (reason.trim().isEmpty) {
      throw ArgumentError('An audit reason is required.');
    }
    return {
      'adminUserId': adminUserId,
      if (adminEmail != null && adminEmail.trim().isNotEmpty)
        'adminEmail': adminEmail.trim().toLowerCase(),
      'actionType': actionType,
      'previousStatus': previousStatus,
      'newStatus': newStatus,
      'reason': reason.trim(),
      'actionAt': actionAt,
      'updatedAt': actionAt,
    };
  }

  static Map<String, Object?> storyOverridePatch({
    required String adminUserId,
    String? adminEmail,
    required String previousStoryStatus,
    required String overrideReason,
    required Object overrideAt,
    required bool unlock,
  }) {
    final overrideType = unlock ? 'manual_unlock' : 'manual_lock';
    return {
      'storyStatus': unlock ? 'unlocked' : 'locked',
      'giftStoryStatus': unlock ? 'unlocked' : 'locked',
      'giftStoryAdminUserId': adminUserId,
      'giftStoryAdminOverrideReason': overrideReason.trim(),
      'giftStoryAdminOverrideAt': overrideAt,
      'giftStoryPreviousStatus': previousStoryStatus,
      'giftStoryOverrideType': overrideType,
      'giftStoryAdminOverride': true,
      if (!unlock) 'giftStoryAccessStatus': 'revoked',
      if (!unlock) 'recipientStoryAccessStatus': 'revoked',
      ...adminActionPatch(
        adminUserId: adminUserId,
        adminEmail: adminEmail,
        actionType: overrideType,
        previousStatus: previousStoryStatus,
        newStatus: unlock ? 'unlocked' : 'locked',
        reason: overrideReason,
        actionAt: overrideAt,
      ),
    };
  }

  static Map<String, Object?> deliveryHandoffPatch({
    required String campaignParticipantId,
    required String giftRequestId,
    required String giftDeliveryId,
    required Object updatedAt,
  }) {
    return {
      'campaignParticipantId': campaignParticipantId,
      'giftRequestId': giftRequestId,
      'giftDeliveryId': giftDeliveryId,
      'flowStatus': 'ready_for_gift_delivery',
      'campaignStatus': 'ready_for_gift_delivery',
      'deliveryStatus': 'ready_for_gift_delivery',
      'storyStatus': 'locked',
      'updatedAt': updatedAt,
      'lastActiveAt': updatedAt,
    };
  }

  static Map<String, Object?> notificationPayload({
    required String event,
    required String userId,
    String? email,
    required String giftId,
    String giftType = sendToSomeoneGiftType,
    required String title,
    required String body,
    String channel = 'in_app',
    String deliveryStatus = 'pending',
    String? failureReason,
    Object? sentAt,
    Object? createdAt,
  }) {
    if (!notificationEvents.contains(event)) {
      throw ArgumentError('Unsupported Gifts notification event: $event');
    }
    return {
      'notificationId': giftId.isEmpty ? event : '${giftId}_$event',
      'userId': userId,
      if (email != null && email.trim().isNotEmpty)
        'email': email.trim().toLowerCase(),
      'giftId': giftId,
      'giftType': normalizeGiftType(giftType),
      'eventType': event,
      'title': title,
      'body': body,
      'channel': channel,
      'deliveryStatus': deliveryStatus,
      'createdAt': createdAt,
      if (sentAt != null) 'sentAt': sentAt,
      if (failureReason != null && failureReason.trim().isNotEmpty)
        'failureReason': failureReason.trim(),
      // Compatibility for existing admin tests/readers.
      'recipientId': userId,
      'recipientRole': 'sender',
      'giftEvent': event,
      'read': false,
      'privacySafe': true,
    };
  }

  static Map<String, Object?>? statusChangeNotificationPayload({
    required String previousStatus,
    required String newStatus,
    required String userId,
    String? email,
    required String giftId,
    String giftType = sendToSomeoneGiftType,
    Object? createdAt,
  }) {
    if (_status(previousStatus) == _status(newStatus)) return null;
    final event = _eventForStatus(newStatus);
    if (event == null) return null;
    final copy = _notificationCopyForEvent(event);
    return notificationPayload(
      event: event,
      userId: userId,
      email: email,
      giftId: giftId,
      giftType: giftType,
      title: copy.$1,
      body: copy.$2,
      createdAt: createdAt,
    );
  }

  static GiftLifecycleState resolve(Map<String, dynamic> record) {
    final giftType = _giftType(record);
    final paymentStatus = _status(record['paymentStatus']);
    final deliveryStatus = _deliveryStatus(record);
    final storyStatus = storyStatusFrom(record);
    final flowStatus = _flowStatus(record, paymentStatus, deliveryStatus);
    final currentStep = _currentStep(record, flowStatus, paymentStatus);
    return GiftLifecycleState(
      giftId:
          '${record['giftId'] ?? record['id'] ?? record['requestId'] ?? ''}',
      giftType: giftType,
      userId: '${record['userId'] ?? record['senderId'] ?? ''}',
      email: '${record['email'] ?? record['senderEmail'] ?? ''}',
      flowStatus: flowStatus,
      currentStep: currentStep,
      completedSteps: _completedSteps(record),
      paymentStatus: paymentStatus.isEmpty ? 'payment_pending' : paymentStatus,
      deliveryStatus: deliveryStatus,
      storyStatus: storyStatus,
      visibleUserStatus: _visibleUserStatus(
        flowStatus,
        paymentStatus,
        deliveryStatus,
        storyStatus,
      ),
      nextAllowedUserAction: _nextUserAction(
        flowStatus,
        paymentStatus,
        deliveryStatus,
        storyStatus,
      ),
      nextAllowedAdminAction: _nextAdminAction(
        flowStatus,
        paymentStatus,
        deliveryStatus,
        storyStatus,
      ),
    );
  }

  static String storyStatusFrom(Map<String, dynamic> record) {
    final overrideType = '${record['giftStoryOverrideType'] ?? ''}';
    final hasAudit = '${record['giftStoryAdminUserId'] ?? ''}'.isNotEmpty &&
        '${record['giftStoryAdminOverrideReason'] ?? ''}'.isNotEmpty &&
        record['giftStoryAdminOverrideAt'] != null &&
        '${record['giftStoryPreviousStatus'] ?? ''}'.isNotEmpty;
    if (hasAudit && overrideType == 'manual_lock') return 'locked';
    if (hasAudit && overrideType == 'manual_unlock') return 'unlocked';
    final explicit =
        _status(record['storyStatus'] ?? record['giftStoryStatus']);
    if (explicit == 'locked' || explicit == 'unlocked') return explicit;
    final delivered = _status(record['linkedDeliveryStatus'] ??
            record['linkedGiftDeliveryStatus'] ??
            record['giftDeliveryStatus'] ??
            record['deliveryStatus']) ==
        'delivered';
    final complete = delivered &&
        _truthy(record['riderCompletionAccepted']) &&
        _truthy(record['deliveryVerificationCompleted']) &&
        _truthy(record['deliveryAuditSuccessful']) &&
        !_truthy(record['activeDeliveryDispute']) &&
        !_truthy(record['deliveryInvestigationActive']);
    return complete ? 'unlocked' : 'locked';
  }

  static String _giftType(Map<String, dynamic> record) {
    final normalized = normalizeGiftType(record['giftType']);
    if (record['giftType'] != null && giftTypes.contains(normalized)) {
      return normalized;
    }
    final mode = _status(record['giftMode']);
    final anonymousType = _status(record['anonymousGiftType']);
    if (mode == 'campaign' || anonymousType == 'campaign') {
      return campaignGiftType;
    }
    if (mode == 'myself' || mode == 'self') return sendToMeGiftType;
    if (mode == 'anonymous' || anonymousType == 'anonymous_gift') {
      return anonymousGiftType;
    }
    return sendToSomeoneGiftType;
  }

  static String _deliveryStatus(Map<String, dynamic> record) {
    final linked = _status(record['linkedDeliveryStatus'] ??
        record['linkedGiftDeliveryStatus'] ??
        record['giftDeliveryStatus']);
    if (linked.isNotEmpty) return linked;
    final deliveryStatus = _status(record['deliveryStatus']);
    return deliveryStatus.isEmpty ? 'not_started' : deliveryStatus;
  }

  static String _flowStatus(
    Map<String, dynamic> record,
    String paymentStatus,
    String deliveryStatus,
  ) {
    final campaignStatus = _status(record['campaignStatus']);
    final matchStatus = _status(record['matchStatus']);
    final approvalStatus = _status(record['approvalStatus'] ??
        record['adminReviewStatus'] ??
        record['status']);
    final curationStatus =
        _status(record['curationStatus'] ?? record['giftsTeamStatus']);
    final explicit = _status(record['flowStatus']);
    if (explicit.isNotEmpty) return _normalizeFlowStatus(explicit);
    if (deliveryStatus == 'delivered') return 'delivered';
    if ([
      'in_delivery',
      'rider_assigned',
      'out_for_delivery',
      'delivery_started',
    ].contains(deliveryStatus)) {
      return 'in_delivery';
    }
    if (campaignStatus == 'ready_for_gift_delivery') {
      return 'ready_for_gift_delivery';
    }
    if (curationStatus == 'curating' ||
        curationStatus == 'gifts_team_curating') {
      return 'curating';
    }
    if (approvalStatus == 'approved' ||
        campaignStatus == 'admin_pairing_approved') {
      return 'approved';
    }
    if (matchStatus == 'approved' || campaignStatus == 'match_confirmed') {
      return 'match_confirmed';
    }
    if (campaignStatus == 'match_found' || matchStatus == 'match_found') {
      return 'match_found';
    }
    if (campaignStatus == 'admin_pairing_pending' ||
        matchStatus == 'review_required') {
      return 'match_review_required';
    }
    if (campaignStatus == 'paid_waiting_for_match' ||
        campaignStatus == 'waiting_for_match') {
      return 'waiting_for_match';
    }
    if (paymentStatus == 'paid') return 'paid';
    if (approvalStatus == 'submitted' || approvalStatus == 'pending_approval') {
      return 'submitted';
    }
    return 'draft';
  }

  static String _normalizeFlowStatus(String status) {
    return switch (status) {
      'pending_approval' => 'submitted',
      'paid_waiting_for_match' => 'waiting_for_match',
      'admin_pairing_pending' => 'match_review_required',
      'admin_pairing_approved' => 'match_confirmed',
      'gifts_team_curating' => 'curating',
      _ => status,
    };
  }

  static int _currentStep(
    Map<String, dynamic> record,
    String flowStatus,
    String paymentStatus,
  ) {
    final explicit = _intValue(record['currentStep']);
    if (explicit > 0 && flowStatus == 'draft') return explicit;
    if (flowStatus == 'draft') return explicit <= 0 ? 1 : explicit;
    if (flowStatus == 'submitted' || paymentStatus == 'payment_pending') {
      return 13;
    }
    return 13;
  }

  static List<int> _completedSteps(Map<String, dynamic> record) {
    final raw = record['completedSteps'];
    if (raw is List) {
      return raw
          .map(_intValue)
          .where((step) => step > 0)
          .toList(growable: false);
    }
    return const [];
  }

  static String _visibleUserStatus(
    String flowStatus,
    String paymentStatus,
    String deliveryStatus,
    String storyStatus,
  ) {
    if (storyStatus == 'unlocked') return 'Gift Story ready';
    if (deliveryStatus == 'delivered') return 'Delivered';
    return switch (flowStatus) {
      'draft' => 'Draft saved',
      'submitted' => 'Gift submitted',
      'paid' => 'Payment confirmed',
      'waiting_for_match' => 'Waiting for your match',
      'match_found' => 'Anonymous match found',
      'match_review_required' => 'Match under review',
      'match_confirmed' => 'Match confirmed',
      'approved' => 'Approved',
      'curating' => 'Gifts Team curating',
      'ready_for_gift_delivery' => 'Ready for Gift Delivery',
      'in_delivery' => 'In delivery',
      'delivered' => 'Delivered',
      _ => 'Gift in progress',
    };
  }

  static String _nextUserAction(
    String flowStatus,
    String paymentStatus,
    String deliveryStatus,
    String storyStatus,
  ) {
    if (storyStatus == 'unlocked') return 'view_gift_story';
    if (deliveryStatus == 'delivered') return 'view_story_status';
    if (deliveryStatus == 'in_delivery' ||
        deliveryStatus == 'rider_assigned' ||
        deliveryStatus == 'out_for_delivery') {
      return 'open_gift_delivery_tracking';
    }
    if (flowStatus == 'draft') return 'resume_draft';
    if (paymentStatus != 'paid' &&
        (flowStatus == 'submitted' || flowStatus == 'draft')) {
      return 'complete_payment';
    }
    return 'view_status';
  }

  static String _nextAdminAction(
    String flowStatus,
    String paymentStatus,
    String deliveryStatus,
    String storyStatus,
  ) {
    if (storyStatus == 'unlocked') return 'review_or_lock_story';
    if (deliveryStatus == 'delivered') return 'review_story_unlock';
    return switch (flowStatus) {
      'submitted' => 'approve_or_reject_gift',
      'paid' => 'approve_or_reject_gift',
      'waiting_for_match' => 'review_campaign_match',
      'match_found' => 'approve_or_reject_campaign_match',
      'match_review_required' => 'approve_or_reject_campaign_match',
      'match_confirmed' => 'create_or_link_gift_request',
      'approved' => 'move_to_curation',
      'curating' => 'mark_ready_for_gift_delivery',
      'ready_for_gift_delivery' => 'link_gift_delivery',
      'in_delivery' => 'monitor_delivery',
      _ => 'review_gift_profile',
    };
  }

  static String? _eventForStatus(String status) {
    return switch (_normalizeFlowStatus(_status(status))) {
      'draft' => 'gift_draft_saved',
      'submitted' => 'gift_submitted',
      'paid' => 'payment_succeeded',
      'waiting_for_match' => 'campaign_waiting_for_match',
      'match_found' => 'campaign_match_found',
      'match_confirmed' => 'campaign_match_confirmed',
      'approved' => 'gift_approved',
      'curating' => 'curation_started',
      'ready_for_gift_delivery' => 'ready_for_gift_delivery',
      'in_delivery' => 'delivery_started',
      'delivered' => 'gift_delivered',
      'story_locked' => 'story_locked',
      'story_unlocked' => 'story_unlocked',
      'disputed' => 'dispute_opened',
      _ => null,
    };
  }

  static (String, String) _notificationCopyForEvent(String event) {
    return switch (event) {
      'gift_draft_saved' => (
          'Gift draft saved',
          'Your gift progress is saved.'
        ),
      'gift_submitted' => (
          'Gift request submitted',
          'Your gift request has been saved for the Gifts Team.',
        ),
      'payment_succeeded' => (
          'Gift payment confirmed',
          'Your gift is secured with the Gifts Team.',
        ),
      'payment_failed' => (
          'Gift payment failed',
          'Your payment did not complete. Your gift progress is still saved.',
        ),
      'subscription_created' => (
          'Gift subscription active',
          'Your recurring self-gift is active.',
        ),
      'subscription_cancelled' => (
          'Gift subscription cancelled',
          'Your recurring self-gift subscription has been cancelled.',
        ),
      'campaign_waiting_for_match' => (
          'Campaign joined',
          'Your anonymous campaign gift is waiting for a safe match.',
        ),
      'campaign_match_found' => (
          'Match found',
          'A policy-safe anonymous match has been found.',
        ),
      'campaign_match_confirmed' => (
          'Match confirmed',
          'The Gifts Team confirmed your anonymous match.',
        ),
      'gift_approved' => (
          'Gift approved',
          'The Gifts Team approved your gift.'
        ),
      'gift_rejected' => (
          'Gift needs attention',
          'The Gifts Team could not approve this request yet.',
        ),
      'curation_started' => (
          'Curation started',
          'The Gifts Team has started shaping your gift.',
        ),
      'ready_for_gift_delivery' => (
          'Ready for Gift Delivery',
          'Your gift is moving into the standard delivery workflow.',
        ),
      'delivery_started' => (
          'Delivery started',
          'Your gift delivery has started.',
        ),
      'rider_assigned' => (
          'Rider assigned',
          'A rider has been assigned to your gift delivery.',
        ),
      'gift_delivered' => ('Gift delivered', 'Your gift has been delivered.'),
      'story_locked' => (
          'Gift Story locked',
          'Your story will unlock after delivery is confirmed.',
        ),
      'story_unlocked' => (
          'Gift Story unlocked',
          'Your Gift Story is ready.',
        ),
      'story_manually_locked' => (
          'Gift Story locked',
          'This story is currently under review.',
        ),
      'story_manually_unlocked' => (
          'Gift Story unlocked',
          'Your Gift Story is ready.',
        ),
      'issue_raised' => (
          'Gift issue raised',
          'The Gifts Team is reviewing an issue with this gift.',
        ),
      'dispute_opened' => (
          'Gift update',
          'The Gifts Team is reviewing an issue with this gift.',
        ),
      'dispute_resolved' => (
          'Gift issue resolved',
          'The Gifts Team has resolved the issue with this gift.',
        ),
      _ => ('Gift update', 'There is an update on your gift.'),
    };
  }

  static String _status(Object? value) => '${value ?? ''}'.trim().toLowerCase();

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static bool _truthy(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = '$value'.trim().toLowerCase();
    return text == 'true' ||
        text == 'yes' ||
        text == 'completed' ||
        text == 'accepted' ||
        text == 'successful' ||
        text == 'active';
  }
}

class GiftLifecycleState {
  final String giftId;
  final String giftType;
  final String userId;
  final String email;
  final String flowStatus;
  final int currentStep;
  final List<int> completedSteps;
  final String paymentStatus;
  final String deliveryStatus;
  final String storyStatus;
  final String visibleUserStatus;
  final String nextAllowedUserAction;
  final String nextAllowedAdminAction;

  const GiftLifecycleState({
    required this.giftId,
    required this.giftType,
    required this.userId,
    required this.email,
    required this.flowStatus,
    required this.currentStep,
    required this.completedSteps,
    required this.paymentStatus,
    required this.deliveryStatus,
    required this.storyStatus,
    required this.visibleUserStatus,
    required this.nextAllowedUserAction,
    required this.nextAllowedAdminAction,
  });
}
