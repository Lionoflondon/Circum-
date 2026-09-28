import 'package:cloud_firestore/cloud_firestore.dart';

bool senderNotificationVisible(Map<String, dynamic> data, {DateTime? now}) {
  if (data['archived'] == true ||
      data['dismissed'] == true ||
      data['suppressed'] == true ||
      data['deletedAt'] != null ||
      data['archivedAt'] != null ||
      data['dismissedAt'] != null) {
    return false;
  }
  final expiresAt = _senderNotificationDate(data['expiresAt']);
  return expiresAt == null || expiresAt.isAfter(now ?? DateTime.now());
}

DateTime? senderNotificationDate(Object? value) =>
    _senderNotificationDate(value);

DateTime? _senderNotificationDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
