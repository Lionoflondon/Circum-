import 'dart:async';

import 'package:circum/app/sender_mobile/sender_finance.dart';
import 'package:circum/app/sender_mobile/sender_wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeWalletRepository implements SenderWalletRepository {
  SenderWalletData wallet;
  List<SenderWalletPage> pages;
  SenderPaymentMethodsData methods;
  Object? failure;
  int initialiseCalls = 0;
  int pageCalls = 0;
  final controller = StreamController<SenderWalletData>.broadcast();

  FakeWalletRepository(
      {required this.wallet,
      this.pages = const [],
      this.methods = const SenderPaymentMethodsData(
        methods: [],
        preference: SenderCheckoutPreference.askEveryCheckout,
      ),
      this.failure});

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
  Future<SenderPaymentMethodsData> paymentMethods() async => methods;

  @override
  Future<SenderSetupIntentData> createSetupIntent() async =>
      const SenderSetupIntentData(
          customerId: 'cus_test',
          ephemeralKeySecret: 'eph_test',
          setupIntentClientSecret: 'seti_secret');

  @override
  Future<void> detachPaymentMethod(String paymentMethodId) async {
    methods = SenderPaymentMethodsData(
      methods:
          methods.methods.where((item) => item.id != paymentMethodId).toList(),
      preference: methods.preference,
      defaultPaymentMethodId: methods.defaultPaymentMethodId,
    );
  }

  @override
  Future<void> setDefaultPaymentMethod(String paymentMethodId) async {
    methods = SenderPaymentMethodsData(
      methods: methods.methods
          .map((item) => SenderPaymentMethod(
                id: item.id,
                brand: item.brand,
                last4: item.last4,
                expMonth: item.expMonth,
                expYear: item.expYear,
                isDefault: item.id == paymentMethodId,
              ))
          .toList(),
      preference: methods.preference,
      defaultPaymentMethodId: paymentMethodId,
    );
  }

  @override
  Future<void> saveCheckoutPreference(
      SenderCheckoutPreference preference) async {
    methods = SenderPaymentMethodsData(
      methods: methods.methods,
      preference: preference,
      defaultPaymentMethodId: methods.defaultPaymentMethodId,
    );
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
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Pay With'), findsOneWidget);
    expect(find.text('Available Roth'), findsOneWidget);
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
    await tester.scrollUntilVisible(find.text('Available Roth'), 120,
        scrollable: find.byType(Scrollable));
    expect(find.text('Available Roth'), findsOneWidget);
    expect(find.text('ROTH'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Referral reward'), 120,
        scrollable: find.byType(Scrollable));
    expect(find.text('Referral reward'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('View all activity'), 120,
        scrollable: find.byType(Scrollable));
    await tester.tap(find.text('View all activity'));
    await tester.pumpAndSettle();
    expect(find.text('Used on delivery'), findsOneWidget);
  });

  testWidgets('recent activity includes payment metadata', (tester) async {
    final repository = FakeWalletRepository(
      wallet: const SenderWalletData(
          balance: 25, frozen: false, onboardingCompleted: true),
      pages: const [
        SenderWalletPage([
          SenderWalletTransaction(
              id: 'card_payment',
              description: 'Parcel Delivery',
              direction: 'debit',
              status: 'completed',
              type: 'checkout_spend',
              paymentMethodLabel: 'Apple Pay',
              amount: 16.49,
              balanceAfter: 25),
        ], null),
      ],
    );
    await tester.pumpWidget(app(SenderWalletView(repository: repository)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Parcel Delivery'), 120,
        scrollable: find.byType(Scrollable));
    expect(find.textContaining('Paid with Apple Pay'), findsOneWidget);
  });

  testWidgets('renders payment methods and checkout preferences',
      (tester) async {
    final repository = FakeWalletRepository(
      wallet: const SenderWalletData(
          balance: 25, frozen: false, onboardingCompleted: true),
      methods: const SenderPaymentMethodsData(
        preference: SenderCheckoutPreference.rothThenCard,
        defaultPaymentMethodId: 'pm_1',
        methods: [
          SenderPaymentMethod(
            id: 'pm_1',
            brand: 'visa',
            last4: '4242',
            expMonth: 12,
            expYear: 2030,
            isDefault: true,
          ),
        ],
      ),
    );
    await tester.pumpWidget(app(SenderWalletView(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Pay With'), findsOneWidget);
    expect(find.text('Visa •••• 4242'), findsOneWidget);
    expect(find.text('Roth'), findsOneWidget);
    expect(find.text('✓ Default'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Manage Payments'), 120,
        scrollable: find.byType(Scrollable));
    expect(find.text('Manage Payments'), findsOneWidget);
  });

  testWidgets('wallet actions and offers render after recent activity',
      (tester) async {
    final repository = FakeWalletRepository(
        wallet: const SenderWalletData(
            balance: 4, frozen: false, onboardingCompleted: true));
    await tester.pumpWidget(app(SenderWalletView(repository: repository)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Wallet Actions'), 120,
        scrollable: find.byType(Scrollable));
    expect(find.text('Redeem Roth Card'), findsOneWidget);
    expect(find.text('Earn Roth'), findsOneWidget);
    expect(find.text('Manage Payments'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Offers'), 120,
        scrollable: find.byType(Scrollable));
    expect(find.text('Earn 5 Roth'), findsOneWidget);
    expect(find.text('Health+ Bonus'), findsOneWidget);
  });

  testWidgets('shows empty and frozen states', (tester) async {
    final repository = FakeWalletRepository(
        wallet: const SenderWalletData(
            balance: 4, frozen: true, onboardingCompleted: true));
    await tester.pumpWidget(app(SenderWalletView(repository: repository)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.textContaining('Wallet is frozen'), 120,
        scrollable: find.byType(Scrollable));
    expect(find.textContaining('Wallet is frozen'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.textContaining('No Roth activity yet'), 120,
        scrollable: find.byType(Scrollable));
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

  test('payment profile ordering follows platform defaults', () {
    const profile = SenderPaymentProfile(
      preference: SenderCheckoutPreference.askEveryCheckout,
      applePaySupported: true,
      googlePaySupported: true,
      defaultPaymentMethodId: 'pm_default',
      methods: [
        SenderPaymentMethod(
          id: 'pm_other',
          brand: 'mastercard',
          last4: '9981',
          expMonth: 8,
          expYear: 2030,
        ),
        SenderPaymentMethod(
          id: 'pm_default',
          brand: 'visa',
          last4: '4242',
          expMonth: 12,
          expYear: 2030,
          isDefault: true,
        ),
      ],
    );

    expect(
      senderOrderedPaymentOptions(profile, platform: TargetPlatform.iOS)
          .map((option) => option.title)
          .toList(),
      [
        'Apple Pay',
        'Visa •••• 4242',
        'Mastercard •••• 9981',
        'Google Pay',
        '+ Add Payment Method'
      ],
    );
    expect(
      senderOrderedPaymentOptions(profile, platform: TargetPlatform.android)
          .map((option) => option.title)
          .toList(),
      [
        'Google Pay',
        'Visa •••• 4242',
        'Mastercard •••• 9981',
        'Apple Pay',
        '+ Add Payment Method'
      ],
    );
    expect(
      senderOrderedPaymentOptions(profile, platform: TargetPlatform.macOS)
          .map((option) => option.title)
          .toList(),
      [
        'Visa •••• 4242',
        'Mastercard •••• 9981',
        'Apple Pay',
        'Google Pay',
        '+ Add Payment Method'
      ],
    );
  });
}
