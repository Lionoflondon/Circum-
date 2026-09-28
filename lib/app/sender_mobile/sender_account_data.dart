import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:share_plus/share_plus.dart';

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
  final FirebaseFunctions functions;

  SenderAccountDataRepository({FirebaseFunctions? functions})
    : functions = functions ?? FirebaseFunctions.instance;

  Future<List<SenderAccountActivityEvent>> loadActivity() async {
    final result = await functions
        .httpsCallable('getSenderAccountActivity')
        .call()
        .timeout(const Duration(seconds: 15));
    final data = result.data;
    if (data is! Map || data['events'] is! List) return const [];
    return (data['events'] as List)
        .whereType<Map>()
        .map(
          (item) => SenderAccountActivityEvent.fromMap(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> exportData() async {
    final result = await functions
        .httpsCallable('exportSenderData')
        .call()
        .timeout(const Duration(seconds: 30));
    final data = result.data;
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
