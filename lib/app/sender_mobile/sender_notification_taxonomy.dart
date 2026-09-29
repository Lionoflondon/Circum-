import 'package:cloud_firestore/cloud_firestore.dart';

/// The customer-facing notification families shared by Home and the centre.
enum SenderNotificationCategory {
  deliveries,
  wallet,
  health,
  gifts,
  business,
  chat,
  system,
}

String senderNotificationCategoryLabel(SenderNotificationCategory category) =>
    category.name;

SenderNotificationCategory senderNotificationCategory(
  Map<String, dynamic> data,
) {
  final category = _normalizedText(data['category']);
  final type = _normalizedText(data['type']);
  final route = _normalizedText(
    data['destination'] is Map
        ? (data['destination'] as Map)['route']
        : data['destinationRoute'],
  );
  final value = category.isNotEmpty ? category : type;

  if (_matches(value, const {'wallet', 'payment', 'payments'}) ||
      type.startsWith('wallet_') ||
      type.startsWith('payment_') ||
      route == 'wallet') {
    return SenderNotificationCategory.wallet;
  }
  if (_matches(value, const {'delivery', 'deliveries', 'tracking'}) ||
      type.startsWith('delivery_') ||
      route == 'tracking') {
    return SenderNotificationCategory.deliveries;
  }
  if (_matches(value, const {'health', 'health+', 'health_plus'}) ||
      type.startsWith('health_') ||
      route == 'health') {
    return SenderNotificationCategory.health;
  }
  if (_matches(value, const {'gift', 'gifts'}) ||
      type.startsWith('gift_') ||
      route == 'gift') {
    return SenderNotificationCategory.gifts;
  }
  if (_matches(value, const {'business', 'invoice', 'invoices'}) ||
      type.startsWith('business_') ||
      type.startsWith('invoice_') ||
      route == 'business') {
    return SenderNotificationCategory.business;
  }
  if (_matches(value, const {'chat', 'message', 'messages', 'conversation'}) ||
      type == 'chat_message' ||
      route == 'conversation') {
    return SenderNotificationCategory.chat;
  }
  return SenderNotificationCategory.system;
}

String senderNotificationCategoryKey(Map<String, dynamic> data) =>
    senderNotificationCategoryLabel(senderNotificationCategory(data));

/// Shared customer-visible predicate. Read notifications remain visible.
/// Ownership is checked here as well as in the Firestore query so a caller
/// cannot accidentally render a cross-account document from a mixed snapshot.
bool senderNotificationVisible(
  Map<String, dynamic> data, {
  DateTime? now,
  String? recipientId,
}) {
  if (recipientId != null &&
      '${data['recipientId'] ?? ''}'.trim() != recipientId.trim()) {
    return false;
  }
  if (data['archived'] == true ||
      data['dismissed'] == true ||
      data['suppressed'] == true ||
      data['deletedAt'] != null ||
      data['archivedAt'] != null ||
      data['dismissedAt'] != null ||
      data['suppressedAt'] != null) {
    return false;
  }
  final expiresAt = senderNotificationDate(data['expiresAt']);
  if (expiresAt == null) return true;
  return expiresAt.isAfter(now ?? DateTime.now());
}

DateTime? senderNotificationDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

bool _matches(String value, Set<String> values) => values.contains(value);

String _normalizedText(Object? value) => '${value ?? ''}'.trim().toLowerCase();
