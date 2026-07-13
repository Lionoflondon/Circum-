class BookingCancellationPolicy {
  static const allowedStatuses = {
    'pending',
    'awaiting_rider',
    'finding_rider',
    'broadcast',
    'broadcasted',
    'rider_assigned',
    'accepted',
    'navigating_to_pickup',
    'en_route_to_pickup',
    'rider_en_route',
    'arrived',
    'arrived_at_pickup',
    'waiting',
    'waiting_for_collection',
    'waiting_charge_active',
    'waiting_charges_active',
    'no_show_review',
    'pickup_verification',
  };

  static String normalize(String status) =>
      status.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

  static bool canSenderCancel(String status) =>
      allowedStatuses.contains(normalize(status));
}
