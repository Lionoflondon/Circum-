class SenderWebBookingRecovery {
  static const draft = 'draft';
  static const awaitingPayment = 'awaiting_payment';
  static const paymentComplete = 'payment_complete';
  static const awaitingBroadcast = 'awaiting_broadcast';
  static const broadcasting = 'broadcasting';
  static const riderAssigned = 'rider_assigned';
  static const riderEnRoute = 'rider_en_route';
  static const riderArrivedPickup = 'rider_arrived_pickup';
  static const pickupVerified = 'pickup_verified';
  static const inTransit = 'in_transit';
  static const riderArrivedDropoff = 'rider_arrived_dropoff';
  static const dropoffVerified = 'dropoff_verified';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';
  static const failed = 'failed';
  static const underReview = 'under_review';
  static const recoverableIncomplete = 'recoverable_incomplete';

  static const recoverableStatuses = {
    draft,
    awaitingPayment,
    paymentComplete,
    awaitingBroadcast,
    recoverableIncomplete,
  };

  static const activeStatuses = {
    broadcasting,
    'requested',
    'pending',
    'finding_rider',
    riderAssigned,
    'assigned',
    'accepted',
    riderEnRoute,
    'en_route_to_pickup',
    riderArrivedPickup,
    'arrived_at_pickup',
    pickupVerified,
    'collected',
    'picked_up',
    inTransit,
    riderArrivedDropoff,
    dropoffVerified,
    underReview,
    'disputed',
  };

  static const terminalStatuses = {
    delivered,
    'completed',
    'complete',
    cancelled,
    'canceled',
    'cancelled_by_sender',
    failed,
    'refunded',
    'archived',
    'voided',
  };

  static String normalizeStatus(Object? value) {
    return '${value ?? ''}'.trim().toLowerCase().replaceAll('-', '_');
  }

  static String visibleStatus(Map<String, dynamic> delivery) {
    final deliveryStatus = normalizeStatus(delivery['deliveryStatus']);
    final status = normalizeStatus(delivery['status']);
    final flowStatus = normalizeStatus(delivery['flowStatus']);
    final paymentStatus = normalizeStatus(delivery['paymentStatus']);
    for (final value in [deliveryStatus, status, flowStatus]) {
      if (value.isNotEmpty && value != 'null') {
        if (value == 'requested' || value == 'finding_rider') {
          return broadcasting;
        }
        return value;
      }
    }
    if (paymentStatus == 'paid') return paymentComplete;
    if (paymentStatus == 'payment_pending' || paymentStatus == 'pending') {
      return awaitingPayment;
    }
    return draft;
  }

  static bool isRecoverableOrActive(Map<String, dynamic> delivery) {
    final status = visibleStatus(delivery);
    return recoverableStatuses.contains(status) ||
        activeStatuses.contains(status);
  }

  static bool isTerminal(Map<String, dynamic> delivery) {
    return terminalStatuses.contains(visibleStatus(delivery));
  }

  static List<String> missingCanonicalFields(Map<String, dynamic> delivery) {
    final missing = <String>[];
    void requireText(String label, Iterable<Object?> values) {
      if (_firstText(values).isEmpty) missing.add(label);
    }

    requireText('deliveryId', [delivery['deliveryId'], delivery['requestId']]);
    requireText('senderId', [delivery['senderId'], delivery['userId']]);
    requireText(
        'sender contact', [delivery['senderEmail'], delivery['senderPhone']]);
    requireText('pickup address', [
      delivery['pickupAddress'],
      _mapValue(delivery['pickupDetails'])['address'],
    ]);
    requireText('drop-off address', [
      delivery['dropoffAddress'],
      _mapValue(delivery['dropoffDetails'])['address'],
    ]);
    requireText('recipient details', [
      delivery['receiverName'],
      _mapValue(delivery['receiverDetails'])['name'],
      _mapValue(delivery['dropoffDetails'])['fullname'],
    ]);
    requireText('item details', [
      delivery['packageDescription'],
      delivery['originalDescription'],
      delivery['normalizedItemName'],
    ]);
    requireText('IRIS estimate', [
      delivery['irisDeliveryEstimateId'],
      delivery['irisDeliveryEstimate'],
      delivery['irisEstimatedWeight'],
    ]);
    requireText('selected delivery option', [
      delivery['selectedServiceLevel'],
      delivery['serviceLevel'],
      delivery['selectedTier'],
    ]);
    requireText('payment status', [delivery['paymentStatus']]);
    requireText('delivery status', [
      delivery['deliveryStatus'],
      delivery['status'],
      delivery['flowStatus'],
    ]);

    final vanguardEnabled = delivery['vanguardEnabled'] == true;
    final requiresPins = vanguardEnabled ||
        _firstText([
          delivery['pickupPin'],
          delivery['collectionPin'],
          delivery['dropoffPin'],
          delivery['receiverPin'],
        ]).isNotEmpty;
    final vanguardProtection = _mapValue(delivery['vanguardProtection']);
    if (requiresPins) {
      requireText('pickup PIN', [
        delivery['pickupPin'],
        delivery['collectionPin'],
        vanguardProtection?['collectionPin'],
      ]);
      requireText('drop-off PIN', [
        delivery['dropoffPin'],
        delivery['receiverPin'],
        delivery['deliveryPin'],
        vanguardProtection?['deliveryPin'],
      ]);
      requireText('PIN createdAt', [
        delivery['pinCreatedAt'],
        delivery['pickupPinCreatedAt'],
        delivery['dropoffPinCreatedAt'],
        delivery['createdAt'],
      ]);
      requireText('pickup PIN verification status', [
        delivery['pickupPinVerificationStatus'],
        delivery['collectionPinVerificationStatus'],
        delivery['collectionPinVerified'],
        _mapValue(delivery['pinVerification'])['pickupStatus'],
      ]);
      requireText('drop-off PIN verification status', [
        delivery['dropoffPinVerificationStatus'],
        delivery['receiverPinVerificationStatus'],
        delivery['deliveryPinVerified'],
        _mapValue(delivery['pinVerification'])['dropoffStatus'],
      ]);
    }
    return missing;
  }

  static bool canBroadcast(Map<String, dynamic> delivery) {
    final paymentStatus = normalizeStatus(delivery['paymentStatus']);
    return paymentStatus == 'paid' && missingCanonicalFields(delivery).isEmpty;
  }

  static Map<String, dynamic> lifecycleFields({
    required String status,
    required String currentStep,
  }) {
    return {
      'status': status == broadcasting ? 'requested' : status,
      'deliveryStatus': status,
      'flowStatus': status,
      'currentStep': currentStep,
    };
  }

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null' && text != 'undefined') {
        return text;
      }
    }
    return '';
  }

  static Map<String, dynamic> _mapValue(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const <String, dynamic>{};
  }
}
