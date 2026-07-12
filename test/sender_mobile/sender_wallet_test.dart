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

Widget app(Widget child, {TargetPlatform platform = TargetPlatform.iOS}) =>
    MaterialApp(
        theme: ThemeData.dark().copyWith(platform: platform),
        home: Scaffold(backgroundColor: const Color(0xFF07090F), body: child));

void main() {
  testWidgets('first open creates once and completes onboarding',
      (tester) async {
    final repository = FakeWalletRepository(
        wallet: const SenderWalletData(
            balance: 0, frozen: false, onboardingCompleted: false));
    await tester.pumpWidget(app(
      SenderWalletView(repository: repository),
      platform: TargetPlatform.iOS,
    ));
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
    expect(find.text('Recent Activity'), findsOneWidget);
    await tester.tap(find.text('Load more'));
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
    expect(find.textContaining('Pending date'), findsNothing);
  });

  testWidgets('ledger rows preserve admin copy and render audited status dates',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final repository = FakeWalletRepository(
      wallet: const SenderWalletData(
          balance: 25, frozen: false, onboardingCompleted: true),
      pages: [
        SenderWalletPage([
          SenderWalletTransaction(
            id: 'admin-1',
            description: 'nrt',
            direction: 'credit',
            status: 'completed',
            type: 'admin_credit',
            amount: 20,
            balanceAfter: 25,
            createdAt: now,
            completedAt: now,
            referenceId: 'campaign-1',
            createdBy: 'admin-user-1',
          ),
          const SenderWalletTransaction(
            id: 'pending-1',
            description: 'Delivery payment',
            direction: 'debit',
            status: 'pending',
            type: 'checkout_spend',
            amount: 8,
            balanceAfter: 17,
          ),
        ], null),
      ],
    );
    await tester.pumpWidget(app(SenderWalletView(repository: repository)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Issued by Circum').first, 120,
        scrollable: find.byType(Scrollable));

    expect(find.text('Issued by Circum'), findsWidgets);
    expect(find.text('nrt'), findsNothing);
    expect(find.textContaining('Completed • Today'), findsOneWidget);
    expect(find.text('Pending • Estimated completion'), findsOneWidget);
    expect(find.textContaining('Pending date'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);

    await tester.tap(find.text('Issued by Circum').first);
    await tester.pumpAndSettle();
    expect(find.text('Activity Details'), findsOneWidget);
    expect(find.text('Reference ID'), findsOneWidget);
    expect(find.text('campaign-1'), findsOneWidget);
    expect(find.text('Created by'), findsOneWidget);
    expect(find.text('Circum'), findsOneWidget);
    expect(
      find.text('This Roth has been added to your account by the Circum team.'),
      findsOneWidget,
    );
    expect(find.text('Current balance'), findsOneWidget);
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

  testWidgets('Manage Payments renders the visual payment profile polish',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeWalletRepository(
      wallet: const SenderWalletData(
        balance: 40,
        frozen: false,
        onboardingCompleted: true,
      ),
      methods: const SenderPaymentMethodsData(
        preference: SenderCheckoutPreference.rothThenCard,
        defaultPaymentMethodId: 'pm_1',
        applePaySupported: true,
        googlePaySupported: false,
        methods: [
          SenderPaymentMethod(
            id: 'pm_1',
            brand: 'visa',
            last4: '4242',
            expMonth: 8,
            expYear: 2029,
            isDefault: true,
          ),
        ],
      ),
    );
    await tester.pumpWidget(app(SenderWalletView(repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Payments'));
    await tester.pumpAndSettle();

    expect(find.text('Preferred Checkout Behaviour'), findsOneWidget);
    expect(find.text('Use Roth first'), findsOneWidget);
    expect(find.text('Use Apple Pay first'), findsOneWidget);
    expect(find.text('Use Google Pay first'), findsNothing);
    expect(find.text('Delivery Total'), findsOneWidget);
    expect(find.text('−40.00 Roth'), findsOneWidget);
    expect(find.text('Remaining charged automatically'), findsOneWidget);
    expect(find.text('Business Payment Profile'), findsOneWidget);
    expect(
      find.text('No Business payment profile connected.'),
      findsOneWidget,
    );
    expect(find.text('Visa'), findsOneWidget);
    expect(find.text('•••• 4242'), findsOneWidget);
    expect(find.text('Expires 08/2029'), findsOneWidget);

    await tester.tap(find.text('Use Apple Pay first'));
    await tester.pumpAndSettle();
    expect(
        repository.methods.preference, SenderCheckoutPreference.applePayFirst);
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
    expect(find.text('Health+ Bonus'), findsNothing);
    expect(find.text('Business Reward'), findsNothing);
    expect(
      find.text(
          'Refer friends and earn 5 Roth when they complete their first successful Circum delivery.'),
      findsOneWidget,
    );
  });

  testWidgets('all Wallet chevrons open an intentional destination',
      (tester) async {
    final repository = FakeWalletRepository(
      wallet: const SenderWalletData(
          balance: 25, frozen: false, onboardingCompleted: true),
      methods: const SenderPaymentMethodsData(
        methods: [],
        preference: SenderCheckoutPreference.rothThenCard,
        applePaySupported: true,
        googlePaySupported: true,
      ),
    );
    await tester.pumpWidget(app(SenderWalletView(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apple Pay'));
    await tester.pumpAndSettle();
    expect(find.text('Apple Pay'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Google Pay'), findsNothing);

    await tester.tap(find.text('Roth').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Use Roth to reduce'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('View all activity'), 120,
        scrollable: find.byType(Scrollable));
    await tester.tap(find.text('View all activity'));
    await tester.pumpAndSettle();
    expect(find.text('Recent Activity'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Manage Payments'), 120,
        scrollable: find.byType(Scrollable));
    await tester.tap(find.text('Manage Payments'));
    await tester.pumpAndSettle();
    expect(find.text('Manage Payments'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Split Payment'), 120,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Split Payment'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Redeem Roth Card'), 120,
        scrollable: find.byType(Scrollable));
    await tester.tap(find.text('Redeem Roth Card'));
    await tester.pumpAndSettle();
    expect(find.text('Card code'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();
    expect(find.text('Wallet Support'), findsOneWidget);
    await tester.tap(find.text('Contact Circum Support'));
    await tester.pumpAndSettle();
    expect(find.text('Circum Support'), findsOneWidget);
    expect(find.text('Support is unavailable'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Earn Roth'), 120,
        scrollable: find.byType(Scrollable));
    await tester.tap(find.text('Earn Roth'));
    await tester.pump();
    expect(find.text('Earn Roth'), findsOneWidget);
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
        '+ Add Payment Method'
      ],
    );
    expect(
      senderOrderedPaymentOptions(profile, platform: TargetPlatform.macOS)
          .map((option) => option.title)
          .toList(),
      ['Visa •••• 4242', 'Mastercard •••• 9981', '+ Add Payment Method'],
    );
  });
}
