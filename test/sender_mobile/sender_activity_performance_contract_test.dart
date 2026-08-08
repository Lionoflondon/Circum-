import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender Activity loads independent sources without all-or-nothing waits',
      () {
    final source =
        File('lib/app/sender_mobile/sender_activity.dart').readAsStringSync();
    final historyStart = source.indexOf(
      'Future<SenderActivityPage> history({String? pageToken})',
    );
    final historyEnd = source.indexOf(
      'Future<QuerySnapshot<Map<String, dynamic>>> _timedActivityFuture',
    );
    expect(historyStart, isNonNegative);
    expect(historyEnd, greaterThan(historyStart));

    final historyBody = source.substring(historyStart, historyEnd);

    expect(historyBody, isNot(contains('Future.wait')));
    expect(historyBody, contains('deliveriesFuture'));
    expect(historyBody, contains('giftsFuture'));
    expect(historyBody, contains('healthFuture'));
    expect(historyBody, contains('walletFuture'));
  });

  test('Sender Activity optional sources are timed, bounded, and fail soft',
      () {
    final source =
        File('lib/app/sender_mobile/sender_activity.dart').readAsStringSync();

    expect(source, contains('_optionalSourceTimeout'));
    expect(source, contains('.timeout(_optionalSourceTimeout)'));
    expect(source, contains('_optionalWalletTransactions'));
    expect(source, contains('Sender Activity optional source unavailable'));
    expect(source, contains('return const SenderWalletPage([], null);'));
    expect(source, contains('return const [];'));
  });

  test('Sender Activity has warm-session cache and performance telemetry', () {
    final source =
        File('lib/app/sender_mobile/sender_activity.dart').readAsStringSync();

    expect(source, contains('static SenderActivityPage? _cachedHistoryPage'));
    expect(source, contains('_restoreCachedHistory'));
    expect(source, contains('stage=cacheRestore'));
    expect(source, contains('stage=widgetBuild'));
    expect(source, contains('stage=historyTotal'));
    expect(source, contains('stage=mergeSortRenderPrep'));
  });

  test('Sender Activity treats searching deliveries as live', () {
    final source =
        File('lib/app/sender_mobile/sender_activity.dart').readAsStringSync();

    final liveStart = source.indexOf('const live = {');
    final liveEnd = source.indexOf('};', liveStart);
    expect(liveStart, isNonNegative);
    expect(liveEnd, greaterThan(liveStart));
    expect(source.substring(liveStart, liveEnd), contains("'searching'"));
  });

  test('Sender Activity uses deterministic cursor pagination', () {
    final source =
        File('lib/app/sender_mobile/sender_activity.dart').readAsStringSync();

    final historyStart = source.indexOf(
      'Future<SenderActivityPage> history({String? pageToken})',
    );
    final historyEnd = source.indexOf(
      'Future<QuerySnapshot<Map<String, dynamic>>> _timedActivityFuture',
    );
    final historyBody = source.substring(historyStart, historyEnd);

    expect(historyBody, contains("orderBy('createdAt', descending: true)"));
    expect(historyBody, contains('orderBy(FieldPath.documentId'));
    expect(historyBody, contains('startAfter'));
    expect(historyBody, contains('_historyPageSize'));
    expect(historyBody, isNot(contains('final sourceLimit')));
    expect(source, contains('_HistoryCursor'));
    expect(source, contains('_searchHistoryIfNeeded'));
  });

  test('Sender Activity retains a bounded legacy delivery compatibility path',
      () {
    final source =
        File('lib/app/sender_mobile/sender_activity.dart').readAsStringSync();

    expect(source, contains('_legacyDeliveryDocs'));
    expect(source, contains("where('createdAt', isNull: true)"));
    expect(source, contains("'created_at'"));
    expect(source, contains("'bookingCreatedAt'"));
    expect(source, contains("'updatedAt'"));
    expect(source, contains('legacyAnchors'));
    expect(source, contains('docs.take(_historyPageSize)'));
  });
}
