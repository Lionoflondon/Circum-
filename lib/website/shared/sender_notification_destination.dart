import 'dart:convert';

const _deepLinkVersion = 1;
const _allowedRoutes = <String>{
  'tracking',
  'conversation',
  'wallet',
  'gift',
  'health',
  'business',
  'profile',
  'activity',
  'notifications',
};

Map<String, dynamic> parseWebsiteSenderNotificationDestination(
  Map<String, dynamic> payload,
) {
  final data = _decodeMap(payload['data']);
  final explicit = _decodeMap(
    payload['deepLink'] ??
        data['deepLink'] ??
        payload['destination'] ??
        data['destination'],
  );
  final type = _firstText([payload['type'], data['type']]);
  final route = _firstText([
    explicit['route'],
    payload['route'],
    payload['screen'],
    data['route'],
    data['screen'],
    _legacyRoute(type),
  ]);
  final destination = <String, dynamic>{
    'version': _deepLinkVersion,
    'route': _safeRoute(route, type),
  };
  for (final key in const [
    'chatId',
    'conversationId',
    'deliveryId',
    'requestId',
    'bookingId',
    'giftId',
    'transactionId',
    'walletTransactionId',
    'referralId',
    'healthPickupId',
    'businessId',
    'invoiceId',
    'orderId',
    'action',
  ]) {
    final value = _firstText([explicit[key], payload[key], data[key]]);
    if (value.isNotEmpty && _isSafeId(value)) {
      destination[key == 'conversationId'
          ? 'chatId'
          : key == 'requestId'
          ? 'deliveryId'
          : key == 'walletTransactionId'
          ? 'transactionId'
          : key] = value;
    }
  }
  return destination;
}

Map<String, dynamic> _decodeMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value.trim().replaceAll("'", '"'));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const {};
    }
  }
  return const {};
}

String _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = '${value ?? ''}'.trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

bool _isSafeId(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$').hasMatch(value);

String _safeRoute(String value, String type) {
  final normalized = value.trim().toLowerCase();
  if (_allowedRoutes.contains(normalized)) return normalized;
  return _legacyRoute(type);
}

String _legacyRoute(String type) {
  final normalized = type.trim().toLowerCase();
  if (normalized == 'message' || normalized == 'chat_message') {
    return 'conversation';
  }
  if (normalized.startsWith('delivery_') ||
      normalized == 'delivery' ||
      normalized == 'connection' ||
      normalized == 'location-broadcast') {
    return 'tracking';
  }
  if (normalized.startsWith('gift_') || normalized == 'gift') return 'gift';
  if (normalized.startsWith('health_') || normalized == 'health_plus') {
    return 'health';
  }
  if (normalized.startsWith('business_') || normalized == 'business') {
    return 'business';
  }
  if (normalized.startsWith('wallet_') ||
      normalized.startsWith('payment_') ||
      normalized.startsWith('roth_') ||
      normalized.startsWith('referral_')) {
    return 'wallet';
  }
  return 'notifications';
}
