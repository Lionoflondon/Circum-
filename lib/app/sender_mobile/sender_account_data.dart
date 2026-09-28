import 'dart:async';
import 'dart:convert';

import 'package:share_plus/share_plus.dart';

import 'account_bootstrap_api.dart';

class SenderAccountActivityEvent {
  final String action;
  final String source;
  final DateTime? createdAt;
  final Map<String, dynamic> details;

  const SenderAccountActivityEvent({
    required this.action,
    required this.source,
    required this.createdAt,
    required this.details,
  });

  factory SenderAccountActivityEvent.fromMap(Map<String, dynamic> data) {
    final rawDate = data['createdAt'] ?? data['closedAt'];
    return SenderAccountActivityEvent(
      action: '${data['action'] ?? data['status'] ?? 'Account activity'}',
      source: '${data['source'] ?? 'Circum'}',
      createdAt: rawDate is String ? DateTime.tryParse(rawDate) : null,
      details: Map<String, dynamic>.from(data)
        ..removeWhere(
          (key, _) =>
              {'action', 'source', 'createdAt', 'closedAt'}.contains(key),
        ),
    );
  }
}

class SenderAccountDataRepository {
  Future<List<SenderAccountActivityEvent>> loadActivity() async {
    final data = await callAccountBootstrap(
      'getSenderAccountActivity',
      const <String, dynamic>{},
    ).timeout(const Duration(seconds: 15));
    final events = data['events'];
    if (events is! List) return const [];
    return events
        .whereType<Map>()
        .map(
          (item) => SenderAccountActivityEvent.fromMap(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> exportData() async {
    final data = await callAccountBootstrap(
      'exportSenderData',
      const <String, dynamic>{},
    ).timeout(const Duration(seconds: 30));
    if (data is! Map) throw StateError('Export returned no data.');
    return Map<String, dynamic>.from(data);
  }

  Future<ShareResult> shareExport(Map<String, dynamic> data) {
    return Share.shareWithResult(
      const JsonEncoder.withIndent('  ').convert(data),
      subject: 'Circum Sender data export',
    );
  }
}
