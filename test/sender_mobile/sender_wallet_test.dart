import 'dart:async';

import 'package:circum/app/sender_mobile/sender_wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeWalletRepository implements SenderWalletRepository {
  SenderWalletData wallet;
  List<SenderWalletPage> pages;
  Object? failure;
  int initialiseCalls = 0;
  int pageCalls = 0;
  final controller = StreamController<SenderWalletData>.broadcast();

  FakeWalletRepository(
      {required this.wallet, this.pages = const [], this.failure});

  @override
  Future<SenderWalletData> initialise() async {
    initialiseCalls += 1;
    if (failure != null) throw failure!;
    return wallet;
  }

  @override
  Stream<SenderWalletData> watch() async* {
    yield wallet;
    yield* controller.stream;
  }

  @override
  Future<SenderWalletPage> transactions({String? pageToken}) async {
    final index = pageCalls++;
    return index < pages.length
        ? pages[index]
        : const SenderWalletPage([], null);
  }

  @override
  Future<void> completeOnboarding() async {
    wallet = SenderWalletData(
      balance: wallet.balance,
      frozen: wallet.frozen,
      onboardingCompleted: true,
      updatedAt: wallet.updatedAt,
    );
  }

  @override
  Future<void> requestDebit(
      {required double amount,
      required String relatedEntityId,
      required String idempotencyKey}) async {}
}

Widget app(Widget child) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(backgroundColor: const Color(0xFF07090F), body: child));

void main() {
  testWidgets('first open creates once and completes onboarding',
      (tester) async {
    final repository = FakeWalletRepository(
        wallet: const SenderWalletData(
            balance: 0, frozen: false, onboardingCompleted: false));
    await tester.pumpWidget(app(SenderWalletView(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Meet Roth'), findsOneWidget);
    expect(repository.initialiseCalls, 1);
    await tester.tap(find.text('Continue to Wallet'));
    await tester.pumpAndSettle();
    expect(find.text('0 Roth'), findsOneWidget);
  });

  testWidgets('renders balance, ordered transactions and pagination',
      (tester) async {
    final repository = FakeWalletRepository(
      wallet: const SenderWalletData(
          balance: 25, frozen: false, onboardingCompleted: true),
      pages: [
        const SenderWalletPage([
          SenderWalletTransaction(
              id: 'new',
              description: 'Referral reward',
              direction: 'credit',
              status: 'completed',
              type: 'referral_reward',
              amount: 5,
              balanceAfter: 25),
        ], '1'),
        const SenderWalletPage([
          SenderWalletTransaction(
              id: 'old',
              description: 'Used on delivery',
              direction: 'debit',
              status: 'completed',
              type: 'checkout_spend',
              amount: 8,
              balanceAfter: 20),
        ], null),
      ],
    );
    await tester.pumpWidget(app(SenderWalletView(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('25 Roth'), findsOneWidget);
    expect(find.text('Referral reward'), findsOneWidget);
    await tester.tap(find.text('View all transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Used on delivery'), findsOneWidget);
  });

  testWidgets('shows empty and frozen states', (tester) async {
    final repository = FakeWalletRepository(
        wallet: const SenderWalletData(
            balance: 4, frozen: true, onboardingCompleted: true));
    await tester.pumpWidget(app(SenderWalletView(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wallet is frozen'), findsOneWidget);
    expect(find.textContaining('No Roth activity yet'), findsOneWidget);
  });

  testWidgets('permission failure exposes retry state', (tester) async {
    final repository = FakeWalletRepository(
        wallet: const SenderWalletData(
            balance: 0, frozen: false, onboardingCompleted: true),
        failure: Exception('permission-denied'));
    await tester.pumpWidget(app(SenderWalletView(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Wallet access unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Home summary matches Wallet balance and opens canonical tab',
      (tester) async {
    var opened = false;
    final repository = FakeWalletRepository(
        wallet: const SenderWalletData(
            balance: 19, frozen: false, onboardingCompleted: true));
    await tester.pumpWidget(app(SenderWalletHomeSummary(
        repository: repository, onOpenWallet: () => opened = true)));
    await tester.pumpAndSettle();
    expect(find.text('19 Roth'), findsOneWidget);
    await tester.tap(find.text('View Wallet'));
    expect(opened, isTrue);
  });
}
