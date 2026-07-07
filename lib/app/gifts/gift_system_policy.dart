class GiftSystemPolicy {
  static const normalGiftType = 'normal';
  static const campaignGiftType = 'campaign';

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
    'gift_request_submitted',
    'gift_payment_succeeded',
    'campaign_waiting_for_match',
    'campaign_match_found',
    'campaign_match_confirmed',
    'gift_curation_started',
    'gift_ready_for_delivery_workflow',
    'gift_delivery_started',
    'gift_rider_assigned',
    'gift_delivered',
    'gift_story_unlocked',
    'gift_story_admin_locked',
    'gift_story_admin_unlocked',
    'gift_issue_or_dispute',
  ];

  static Map<String, Object?> progressPatch({
    required String userId,
    required String email,
    required String giftType,
    required String flowStatus,
    required int currentStep,
    required List<int> completedSteps,
    String paymentStatus = 'payment_pending',
    String deliveryStatus = 'not_started',
    String storyStatus = 'locked',
    Object? createdAt,
    required Object updatedAt,
    Object? lastActiveAt,
  }) {
    return {
      'userId': userId,
      'email': email.trim().toLowerCase(),
      'giftType': giftType,
      'flowStatus': flowStatus,
      'currentStep': currentStep,
      'completedSteps': completedSteps,
      'paymentStatus': paymentStatus,
      'deliveryStatus': deliveryStatus,
      'storyStatus': storyStatus,
      if (createdAt != null) 'createdAt': createdAt,
      'updatedAt': updatedAt,
      'lastActiveAt': lastActiveAt ?? updatedAt,
    };
  }

  static String resumeRoute(Map<String, dynamic> gift) {
    final giftType = '${gift['giftType'] ?? ''}';
    final flowStatus = _status(gift['flowStatus'] ?? gift['status']);
    final paymentStatus = _status(gift['paymentStatus']);
    final deliveryStatus = _status(gift['deliveryStatus']);
    final storyStatus = _status(gift['storyStatus'] ?? gift['giftStoryStatus']);
    if (storyStatus == 'unlocked') return '/sender-mobile/gifts/story';
    if (deliveryStatus == 'delivered') return '/sender-mobile/gifts/story';
    if (deliveryStatus == 'in_delivery' ||
        deliveryStatus == 'rider_assigned' ||
        deliveryStatus == 'out_for_delivery') {
      return '/sender-mobile/gifts/status';
    }
    if (flowStatus == 'submitted' ||
        flowStatus == 'paid' ||
        paymentStatus == 'paid') {
      return giftType == campaignGiftType
          ? '/sender-mobile/gifts/campaign'
          : '/sender-mobile/gifts/status';
    }
    final currentStep = _intValue(gift['currentStep']);
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
    return records.where((record) => statusBucket(record) == filter).toList();
  }

  static String statusBucket(Map<String, dynamic> record) {
    final storyStatus =
        _status(record['storyStatus'] ?? record['giftStoryStatus']);
    if (storyStatus == 'unlocked') return 'story_unlocked';
    if (storyStatus == 'locked' &&
        _status(record['flowStatus']) == 'delivered') {
      return 'story_locked';
    }
    if (_truthy(record['activeDeliveryDispute']) ||
        _truthy(record['deliveryInvestigationActive']) ||
        _status(record['flowStatus']).contains('dispute')) {
      return 'disputed';
    }
    final deliveryStatus = _status(record['deliveryStatus']);
    if (deliveryStatus == 'delivered') return 'delivered';
    if (deliveryStatus == 'in_delivery' ||
        deliveryStatus == 'rider_assigned' ||
        deliveryStatus == 'out_for_delivery') {
      return 'in_delivery';
    }
    final status = _status(record['flowStatus'] ??
        record['campaignStatus'] ??
        record['status'] ??
        record['paymentStatus']);
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
      ...adminActionPatch(
        adminUserId: adminUserId,
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
    required String giftId,
    required String title,
    required String body,
    String channel = 'in_app',
    Object? createdAt,
  }) {
    if (!notificationEvents.contains(event)) {
      throw ArgumentError('Unsupported Gifts notification event: $event');
    }
    return {
      'recipientId': userId,
      'recipientRole': 'sender',
      'giftId': giftId,
      'giftEvent': event,
      'title': title,
      'body': body,
      'channel': channel,
      'createdAt': createdAt,
      'read': false,
      'privacySafe': true,
    };
  }

  static String storyStatusFrom(Map<String, dynamic> record) {
    final overrideType = '${record['giftStoryOverrideType'] ?? ''}';
    final hasAudit = '${record['giftStoryAdminUserId'] ?? ''}'.isNotEmpty &&
        '${record['giftStoryAdminOverrideReason'] ?? ''}'.isNotEmpty &&
        record['giftStoryAdminOverrideAt'] != null &&
        '${record['giftStoryPreviousStatus'] ?? ''}'.isNotEmpty;
    if (hasAudit && overrideType == 'manual_lock') return 'locked';
    if (hasAudit && overrideType == 'manual_unlock') return 'unlocked';
    final delivered = _status(
            record['linkedGiftDeliveryStatus'] ?? record['deliveryStatus']) ==
        'delivered';
    final complete = delivered &&
        _truthy(record['riderCompletionAccepted']) &&
        _truthy(record['deliveryVerificationCompleted']) &&
        _truthy(record['deliveryAuditSuccessful']) &&
        !_truthy(record['activeDeliveryDispute']) &&
        !_truthy(record['deliveryInvestigationActive']);
    return complete ? 'unlocked' : 'locked';
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
