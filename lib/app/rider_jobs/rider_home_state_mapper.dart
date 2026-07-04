import 'rider_job_models.dart';

class RiderHomeStateMapper {
  static RiderJobUiState fromBackend({
    required Map<String, dynamic>? riderProfile,
    Map<String, dynamic>? activeDelivery,
    Map<String, dynamic>? presence,
    bool hasAvailableOffers = false,
    bool localGoingOnline = false,
    bool loading = false,
  }) {
    if (loading) return RiderJobUiState.loading;
    if (localGoingOnline) return RiderJobUiState.goingOnline;

    final status = _text(activeDelivery?['status']);
    if (status.isNotEmpty) {
      return switch (status) {
        'accepted' => RiderJobUiState.accepted,
        'navigating_to_pickup' => RiderJobUiState.navigatingToPickup,
        'arrived_at_pickup' || 'waiting' => RiderJobUiState.arrivedWaiting,
        'pickup_verification' ||
        'pickup_verified' =>
          RiderJobUiState.verification,
        'collected' ||
        'navigating_to_dropoff' ||
        'arrived_at_dropoff' =>
          RiderJobUiState.inTransit,
        'delivered' || 'completed' => RiderJobUiState.completed,
        'issue_reported' || 'review' => RiderJobUiState.deliveryUpdate,
        _ => RiderJobUiState.accepted,
      };
    }

    final approval = _text(
      riderProfile?['onboardingStatus'] ??
          riderProfile?['approvalStatus'] ??
          riderProfile?['verificationStatus'],
    );
    if (approval != 'approved') return RiderJobUiState.pendingApproval;

    final busy = presence?['busy'] == true ||
        _text(presence?['availabilityStatus']) == 'busy' ||
        _text(presence?['currentDeliveryId']).isNotEmpty ||
        _text(presence?['activeDeliveryId']).isNotEmpty;
    if (busy) return RiderJobUiState.accepted;

    final online = presence?['isOnline'] == true ||
        riderProfile?['isOnline'] == true ||
        riderProfile?['online'] == true ||
        _text(riderProfile?['availability']) == 'online';
    final available = _text(presence?['availabilityStatus']) == 'available';
    if (hasAvailableOffers && online && available) {
      return RiderJobUiState.offerAvailable;
    }
    return online ? RiderJobUiState.onlineWaiting : RiderJobUiState.offline;
  }

  static String titleFor(RiderJobUiState state, {String firstName = 'Rider'}) {
    return switch (state) {
      RiderJobUiState.loading => 'Loading rider state',
      RiderJobUiState.pendingApproval => "You're under review.",
      RiderJobUiState.offline => 'Good evening, $firstName.',
      RiderJobUiState.goingOnline => 'Getting you ready…',
      RiderJobUiState.onlineWaiting => 'Looking for deliveries…',
      RiderJobUiState.offerAvailable => 'New delivery offer',
      RiderJobUiState.accepted => 'Job confirmed.',
      RiderJobUiState.navigatingToPickup => 'Navigate to pickup',
      RiderJobUiState.arrivedWaiting => 'You have arrived.',
      RiderJobUiState.verification => 'Pickup verification',
      RiderJobUiState.inTransit => 'On the way to drop-off',
      RiderJobUiState.completed => 'Delivery complete',
      RiderJobUiState.deliveryUpdate => 'Delivery Update',
    };
  }

  static String copyFor(RiderJobUiState state) {
    return switch (state) {
      RiderJobUiState.loading => 'Preparing your rider workspace.',
      RiderJobUiState.pendingApproval =>
        "We're verifying your documents. This usually takes under 24 hours.",
      RiderJobUiState.offline =>
        "You're ready to deliver. Go online whenever you're ready.",
      RiderJobUiState.goingOnline =>
        'Checking vehicle, approval and connection.',
      RiderJobUiState.onlineWaiting =>
        'Stay nearby. We will surface eligible jobs here.',
      RiderJobUiState.offerAvailable =>
        'Swipe to compare offers. Accept only writes when tapped.',
      RiderJobUiState.accepted => 'Head to pickup.',
      RiderJobUiState.navigatingToPickup =>
        'Follow the route and confirm when you arrive.',
      RiderJobUiState.arrivedWaiting =>
        'The sender has been notified. Waiting time follows backend policy.',
      RiderJobUiState.verification =>
        'IRIS is checking the parcel against the booking.',
      RiderJobUiState.inTransit =>
        'Keep custody secure and continue to drop-off.',
      RiderJobUiState.completed =>
        'Trust points added. Ready for your next opportunity.',
      RiderJobUiState.deliveryUpdate =>
        "We're reviewing something about this delivery. Support has already been notified. Continue following instructions.",
    };
  }

  static String _text(Object? value) => '${value ?? ''}'.trim().toLowerCase();
}
