import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class SenderNotificationProjection {
  final String type;
  final String category;
  final String route;
  final bool read;
  final bool archived;
  final bool suppressed;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final Map<String, dynamic> destination;
  final String visibilityReason;

  const SenderNotificationProjection({
    required this.type,
    required this.category,
    required this.route,
    required this.read,
    required this.archived,
    required this.suppressed,
    required this.createdAt,
    required this.expiresAt,
    required this.destination,
    required this.visibilityReason,
  });

  bool get visible => visibilityReason == 'visible';
}

SenderNotificationProjection projectSenderNotification(
  Map<String, dynamic> data, {
  DateTime? now,
}) {
  final nested = _nestedData(data);
  final type = _text(data['type'] ?? nested['type']).toLowerCase();
  final category = senderNotificationCategory(data);
  final rawDestination = data['destination'] ?? nested['destination'];
  final destination = rawDestination is Map
      ? Map<String, dynamic>.from(rawDestination)
      : <String, dynamic>{};
  final route = _route(
    destination['route'] ?? data['route'] ?? nested['route'],
    category,
    type,
  );
  final archived =
      data['archived'] == true ||
      data['dismissed'] == true ||
      data['deletedAt'] != null ||
      data['archivedAt'] != null ||
      data['dismissedAt'] != null;
  final suppressionReason = _text(data['suppressionReason']);
  final suppressed =
      data['suppressed'] == true ||
      data['recipientSuppressed'] == true ||
      suppressionReason.isNotEmpty;
  final expiresAt = senderNotificationDate(
    data['expiresAt'] ?? nested['expiresAt'],
  );
  final current = now ?? DateTime.now();
  final reason = archived
      ? 'archived'
      : suppressed
      ? 'suppressed'
      : expiresAt != null && !expiresAt.isAfter(current)
      ? 'expired'
      : 'visible';
  return SenderNotificationProjection(
    type: type,
    category: category,
    route: route,
    read: data['read'] == true,
    archived: archived,
    suppressed: suppressed,
    createdAt: senderNotificationDate(
      data['createdAt'] ?? data['timestamp'] ?? nested['createdAt'],
    ),
    expiresAt: expiresAt,
    destination: {...destination, if (route.isNotEmpty) 'route': route},
    visibilityReason: reason,
  );
}

String senderNotificationCategory(Map<String, dynamic> data) {
  final nested = _nestedData(data);
  final candidates = [
    data['category'],
    nested['category'],
    data['family'],
    data['product'],
    data['source'],
    data['type'],
  ];
  for (final candidate in candidates) {
    final value = _normalize('${candidate ?? ''}');
    if (value.isEmpty) continue;
    if (value == 'payment' ||
        value == 'payments' ||
        value == 'wallet' ||
        value == 'roth' ||
        value.startsWith('wallet_') ||
        value.startsWith('roth_') ||
        value.startsWith('payment_')) {
      return 'wallet';
    }
    if (value == 'delivery' ||
        value == 'deliveries' ||
        value == 'parcel' ||
        value.startsWith('delivery_')) {
      return 'deliveries';
    }
    if (value == 'gift' || value == 'gifts' || value.startsWith('gift_')) {
      return 'gifts';
    }
    if (value == 'health' ||
        value == 'health_plus' ||
        value.startsWith('health_')) {
      return 'health';
    }
    if (value == 'business' || value.startsWith('business_')) {
      return 'business';
    }
    if (value == 'system') return 'system';
  }
  return 'system';
}

String senderNotificationFilterCategory(String label) => switch (label) {
  'Health+' => 'health',
  'Deliveries' => 'deliveries',
  'Wallet' => 'wallet',
  'Gifts' => 'gifts',
  'Business' => 'business',
  'System' => 'system',
  _ => label.trim().toLowerCase(),
};

void traceSenderNotificationStage(
  String stage, {
  required int count,
  int qaWalletCount = 0,
  String? category,
  String? route,
  String? reason,
}) {
  // Deliberately log counts and classifications only. Never log titles, bodies,
  // recipient identifiers or raw document IDs from the notification payload.
  debugPrint(
    'sender_notification_trace stage=$stage count=$count '
    'qaWallet=$qaWalletCount${category == null ? '' : ' category=$category'}'
    '${route == null ? '' : ' route=$route'}'
    '${reason == null ? '' : ' reason=$reason'}',
  );
}

bool senderNotificationVisible(Map<String, dynamic> data, {DateTime? now}) {
  return projectSenderNotification(data, now: now).visible;
}

DateTime? senderNotificationDate(Object? value) =>
    _senderNotificationDate(value);

Map<String, dynamic> _nestedData(Map<String, dynamic> data) {
  final nested = data['data'];
  return nested is Map ? Map<String, dynamic>.from(nested) : const {};
}

String _route(Object? raw, String category, String type) {
  final value = _normalize('$raw');
  if (value == 'wallet' || value == 'profile_wallet') return 'wallet';
  if (value.isNotEmpty && value != 'null') return value;
  if (category == 'wallet' || type.startsWith('wallet_')) return 'wallet';
  if (category == 'gifts') return 'gift';
  if (category == 'health') return 'health';
  if (category == 'business') return 'business';
  if (category == 'deliveries') return 'tracking';
  return 'notifications';
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

String _text(Object? value) => '${value ?? ''}'.trim();

DateTime? _senderNotificationDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
