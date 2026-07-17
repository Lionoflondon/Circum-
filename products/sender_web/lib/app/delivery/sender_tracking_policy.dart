import 'package:circum/app/delivery_security/vanguard_protection.dart';

enum SenderTrackingBadge {
  none,
  vanguard,
  healthPlus,
  gift,
}

class SenderTrackingCopy {
  final String label;
  final String body;

  const SenderTrackingCopy({
    required this.label,
    required this.body,
  });
}

class SenderTrackingPolicy {
  static String normalizeStatus(Object? value) {
    return '${value ?? ''}'
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  static SenderTrackingCopy copyFor(Object? status) {
    return switch (normalizeStatus(status)) {
      'finding_rider' ||
      'requested' ||
      'pending' ||
      'unmatched' =>
        const SenderTrackingCopy(
          label: 'Finding a rider',
          body: 'We are matching your delivery with an eligible Circum rider.',
        ),
      'accepted' => const SenderTrackingCopy(
          label: 'Rider accepted your delivery',
          body: 'Your rider has accepted and is preparing to move.',
        ),
      'navigating_to_pickup' => const SenderTrackingCopy(
          label: 'Rider on the way to pickup',
          body: 'Your rider is heading to collect your parcel.',
        ),
      'arrived_at_pickup' => const SenderTrackingCopy(
          label: 'Your rider is outside',
          body: 'Your rider has arrived and is waiting at pickup.',
        ),
      'waiting' => const SenderTrackingCopy(
          label: 'Rider is waiting',
          body: 'Your rider is outside. Free waiting time is included.',
        ),
      'pickup_verification' => const SenderTrackingCopy(
          label: 'Verifying your parcel',
          body: 'Your rider is checking the parcel before collection.',
        ),
      'pickup_verified' => const SenderTrackingCopy(
          label: 'Parcel verified',
          body: 'The parcel has been checked and is ready to move.',
        ),
      'collected' => const SenderTrackingCopy(
          label: 'Parcel collected',
          body: 'Your parcel is now with your rider.',
        ),
      'navigating_to_dropoff' => const SenderTrackingCopy(
          label: 'On the way to drop-off',
          body: 'Your rider is travelling to the receiver.',
        ),
      'arrived_at_dropoff' => const SenderTrackingCopy(
          label: 'Rider has arrived at drop-off',
          body: 'Your rider is outside at the drop-off address.',
        ),
      'pin_required' => const SenderTrackingCopy(
          label: 'PIN required to complete delivery',
          body: 'A PIN is required before the handover can be completed.',
        ),
      'delivered' || 'completed' => const SenderTrackingCopy(
          label: 'Delivered',
          body: 'Your delivery has been completed successfully.',
        ),
      'issue_reported' => const SenderTrackingCopy(
          label: 'Delivery update',
          body:
              "We're reviewing something about this delivery. Our team is already assisting your rider. We'll keep this timeline updated.",
        ),
      _ => const SenderTrackingCopy(
          label: 'Delivery in progress',
          body: 'Your delivery timeline will update as the rider progresses.',
        ),
    };
  }

  static int timelineIndex(Object? status, {bool collected = false}) {
    final normalized = normalizeStatus(status);
    if (normalized == 'delivered' || normalized == 'completed') return 4;
    if (normalized == 'collected') return 2;
    if (normalized == 'navigating_to_dropoff' ||
        normalized == 'arrived_at_dropoff' ||
        (normalized == 'pin_required' && collected)) {
      return 3;
    }
    if (normalized == 'navigating_to_pickup' ||
        normalized == 'arrived_at_pickup' ||
        normalized == 'pickup_verification' ||
        normalized == 'pickup_verified' ||
        normalized == 'waiting' ||
        normalized == 'collection_pin_required' ||
        (normalized == 'pin_required' && !collected)) {
      return 1;
    }
    return 0;
  }

  static SenderTrackingBadge badgeFor(Map<String, dynamic> delivery) {
    if (delivery['isVanguard'] == true ||
        delivery['requiresVanguard'] == true ||
        VanguardProtection.isProtocolEnabled(delivery)) {
      return SenderTrackingBadge.vanguard;
    }
    if (delivery['isHealthPlus'] == true || delivery['healthPlus'] == true) {
      return SenderTrackingBadge.healthPlus;
    }
    if (delivery['isGift'] == true || delivery['giftDelivery'] == true) {
      return SenderTrackingBadge.gift;
    }
    return SenderTrackingBadge.none;
  }

  static bool shouldShowVanguardTimeline(Map<String, dynamic> delivery) {
    return VanguardProtection.isProtocolEnabled(delivery);
  }

  static List<String> vanguardTimeline(Map<String, dynamic> delivery) {
    if (!shouldShowVanguardTimeline(delivery)) return const [];
    return VanguardProtection.protocolTimeline;
  }

  static String vanguardStatusLabel(Map<String, dynamic> delivery) {
    return VanguardProtection.statusLabel(
      VanguardProtection.statusFromDelivery(delivery),
    );
  }

  static bool isFindingRider(Object? status) {
    final normalized = normalizeStatus(status);
    return normalized == 'finding_rider' ||
        normalized == 'requested' ||
        normalized == 'pending' ||
        normalized == 'unmatched';
  }

  static bool isDelivered(Object? status) {
    final normalized = normalizeStatus(status);
    return normalized == 'delivered' || normalized == 'completed';
  }

  static bool shouldShowWaitingCard(Object? status, bool hasWaitStartedAt) {
    final normalized = normalizeStatus(status);
    return normalized == 'arrived_at_pickup' ||
        normalized == 'arrived_at_dropoff' ||
        (normalized == 'waiting' && hasWaitStartedAt);
  }

  static bool showCollectionPin(Map<String, dynamic> delivery) {
    final status = normalizeStatus(delivery['status']);
    return status == 'pin_required' && !hasCollected(delivery);
  }

  static bool showDeliveryPinNotice(Map<String, dynamic> delivery) {
    final status = normalizeStatus(delivery['status']);
    return status == 'pin_required' && hasCollected(delivery);
  }

  static bool hasCollected(Map<String, dynamic> delivery) {
    if (delivery['collectionPinVerified'] == true ||
        delivery['collectedAt'] != null ||
        delivery['pickupVerifiedAt'] != null) {
      return true;
    }
    final status = normalizeStatus(delivery['status']);
    return status == 'collected' ||
        status == 'navigating_to_dropoff' ||
        status == 'arrived_at_dropoff' ||
        status == 'delivered' ||
        status == 'completed';
  }
}
