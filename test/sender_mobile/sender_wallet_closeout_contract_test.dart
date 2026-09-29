import 'dart:io';

import 'package:circum/app/sender_mobile/sender_wallet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SenderWalletTransaction transaction(
    String id,
    DateTime createdAt, {
    String status = 'completed',
  }) {
    return SenderWalletTransaction(
      id: id,
      description: 'Roth activity',
      direction: 'credit',
      status: status,
      type: 'referral_reward',
      amount: 5,
      balanceAfter: 5,
      createdAt: createdAt,
    );
  }

  test('wallet page merge is newest-first and duplicate-free', () {
    final old = transaction('tx-old', DateTime.utc(2026, 1, 1));
    final newer = transaction('tx-new', DateTime.utc(2026, 1, 2));
    final refreshed = transaction(
      'tx-old',
      DateTime.utc(2026, 1, 1),
      status: 'reversed',
    );

    final merged = mergeSenderWalletTransactions(
      [old, newer],
      [refreshed, newer],
    );

    expect(merged.map((item) => item.id), ['tx-new', 'tx-old']);
    expect(merged.last.status, 'reversed');
  });

  test('legacy Wallet entry delegates to the canonical Sender Wallet', () {
    final source = File('lib/app/account/view/wallet.dart').readAsStringSync();
    expect(source, contains('SenderWalletView'));
    expect(source, isNot(contains('Payment methods, Roth balance')));
    expect(source, isNot(contains('Receipts')));
  });

  test('Wallet UI has no inert referral or activity fallback controls', () {
    final source =
        File('lib/app/sender_mobile/sender_wallet.dart').readAsStringSync();
    expect(source, contains('Clipboard.setData'));
    expect(source, contains('RefreshIndicator('));
    expect(source, contains('mergeSenderWalletTransactions'));
    expect(source, contains('Action needed'));
    expect(source, contains('Unknown status'));
    expect(source, contains("title: 'Wallet Support'"));
    expect(source, isNot(contains('_SplitPaymentPreview')));
    expect(source, isNot(contains('£58.50')));
    expect(source, isNot(contains('Preparing link')));
    expect(source, isNot(contains('Your referral link is still loading.')));
  });

  test('Wallet transaction details do not render internal identifiers', () {
    final source =
        File('lib/app/sender_mobile/sender_wallet.dart').readAsStringSync();
    final detailsStart = source.indexOf('class _TransactionDetailsScreen');
    final detailsEnd = source.indexOf('class _DetailRow', detailsStart);
    final details = source.substring(detailsStart, detailsEnd);
    expect(details, contains('Available to Circum Support'));
    expect(details, isNot(contains('Reference ID')));
    expect(details, isNot(contains("_DetailRow(label: 'Reference ID'")));
    expect(details, isNot(contains("_DetailRow(label: 'Transaction ID'")));
  });
}
