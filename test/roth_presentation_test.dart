import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:circum/app/shared/roth/roth_presentation.dart';

void main() {
  test('legacy wallet route delegates to the canonical Sender wallet', () {
    final source = File('lib/app/account/view/wallet.dart').readAsStringSync();

    expect(source, contains('const SenderWalletView()'));
    expect(source, isNot(contains('Circum Wallet')));
    expect(source, isNot(contains('Payment methods')));
  });

  test('Roth checkout surfaces use the shared presentation primitives', () {
    final business =
        File('lib/app/business/business_view.dart').readAsStringSync();
    final health =
        File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();
    final gifts =
        File('lib/app/sender_mobile/gift_payment_view.dart').readAsStringSync();

    expect(business, contains('RothChoiceCard'));
    expect(health, contains('RothChoiceCard'));
    expect(gifts, contains('RothSummaryCard'));
    expect(gifts, contains('RothApplyCard'));
  });

  testWidgets('Roth choice card exposes one canonical presentation',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RothChoiceCard(
            selected: true,
            title: 'Use Roth',
            description: 'Available: £10.00',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Use Roth'), findsOneWidget);
    expect(find.text('Available: £10.00'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('Roth summary keeps balance values readable', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RothSummaryCard(
            loading: false,
            unavailable: false,
            balance: 12.5,
            applied: 4,
            remaining: 8.5,
          ),
        ),
      ),
    );

    expect(find.text('£12.50'), findsOneWidget);
    expect(find.text('£4.00'), findsOneWidget);
    expect(find.text('£8.50'), findsOneWidget);
  });
}
