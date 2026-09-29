import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Sender Activity loads independent sources without all-or-nothing waits',
    () {
      final source = File(
        'lib/app/sender_mobile/sender_activity.dart',
      ).readAsStringSync();
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
    },
  );

  test(
    'Sender Activity optional sources are timed, bounded, and fail soft',
    () {
      final source = File(
        'lib/app/sender_mobile/sender_activity.dart',
      ).readAsStringSync();

      expect(source, contains('_optionalSourceTimeout'));
      expect(source, contains('.timeout(_optionalSourceTimeout)'));
      expect(source, contains('_optionalWalletTransactions'));
      expect(source, contains('Sender Activity optional source unavailable'));
      expect(source, contains('return const SenderWalletPage([], null);'));
      expect(source, contains('return const [];'));
    },
  );

  test('Sender Activity orders each authoritative source before limiting', () {
    final source = File(
      'lib/app/sender_mobile/sender_activity.dart',
    ).readAsStringSync();
    for (final collection in [
      "collection('deliveryRequests')",
      "collection('giftRequests')",
      "collection('prescriptionPickups')",
    ]) {
      final start = source.indexOf(collection);
      final limit = source.indexOf('.limit(_senderActivityPageSize)', start);
      final order = source.indexOf(
        ".orderBy('updatedAt', descending: true)",
        start,
      );
      expect(start, isNonNegative);
      expect(order, greaterThan(start));
      expect(limit, greaterThan(order));
    }
    expect(source, contains('startAfter(['));
    expect(source, contains('Timestamp.fromMillisecondsSinceEpoch'));
    expect(source, contains('_encodeActivityPageToken'));
    expect(source, isNot(contains('final start = page * 20')));
  });

  test('Sender Activity uses document ID as the equal-timestamp tie-break', () {
    final source = File(
      'lib/app/sender_mobile/sender_activity.dart',
    ).readAsStringSync();

    expect(source, contains('_compareActivityItemsDescending'));
    expect(source, contains('return right.id.compareTo(left.id);'));
    expect(source, contains('items.sort(_compareActivityItemsDescending);'));
    expect(source, contains('merged.sort(_compareActivityItemsDescending);'));
  });

  test(
    'Sender Activity requests the next page at the real scroll boundary',
    () {
      final source = File(
        'lib/app/sender_mobile/sender_activity.dart',
      ).readAsStringSync();
      final shell = File(
        'lib/app/sender_mobile/sender_page_shell.dart',
      ).readAsStringSync();
      expect(source, contains('onScrollNearEnd: _loadMoreWhenNearEnd'));
      expect(source, contains('void _loadMoreWhenNearEnd()'));
      expect(source, contains('_loadingMore'));
      expect(shell, contains('notification.metrics.extentAfter'));
      expect(shell, contains('onScrollNearEnd!();'));
    },
  );

  test('Sender Activity pagination failure is safe and retryable', () {
    final source = File(
      'lib/app/sender_mobile/sender_activity.dart',
    ).readAsStringSync();
    expect(source, contains('_loadMoreError'));
    expect(source, contains('More activity could not load'));
    expect(source, contains('Retry loading activity'));
    expect(source, contains('catch (_)'));
    expect(source, isNot(contains("_loadMoreError = '\$error'")));
  });

  test('Sender Activity has warm-session cache and performance telemetry', () {
    final source = File(
      'lib/app/sender_mobile/sender_activity.dart',
    ).readAsStringSync();

    expect(source, contains('static SenderActivityPage? _cachedHistoryPage'));
    expect(source, contains('_restoreCachedHistory'));
    expect(source, contains('stage=cacheRestore'));
    expect(source, contains('stage=widgetBuild'));
    expect(source, contains('stage=historyTotal'));
    expect(source, contains('stage=mergeSortRenderPrep'));
  });
}
