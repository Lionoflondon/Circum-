import 'package:circum/app/business/business_models.dart';
import 'package:circum/app/business/business_repository.dart';
import 'package:circum/app/business/business_view.dart';
import 'package:circum/app/sender_mobile/sender_finance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders all canonical Business tabs and backend verification',
      (tester) async {
    await tester.pumpWidget(_app(status: 'approved'));
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Deliveries'), findsWidgets);
    expect(find.text('Invoices'), findsWidgets);
    expect(find.text('Team'), findsWidgets);
    expect(find.text('Health+'), findsWidgets);
    expect(find.text('Gifts'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(-900, 0));
    await tester.pumpAndSettle();
    expect(find.text('Vanguard'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Verified Business ✓'), findsOneWidget);
    expect(find.text('18'), findsNothing);
    expect(find.text('£412.60'), findsNothing);
  });

  testWidgets('pending account shows complete verification journey',
      (tester) async {
    await tester.pumpWidget(_app(status: 'pending'));
    await tester.pumpAndSettle();

    expect(find.text('Pending Approval'), findsOneWidget);
    expect(find.text('Business verification'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
  });

  testWidgets('delivery tabs filter existing delivery engine records',
      (tester) async {
    await tester.pumpWidget(_app(status: 'approved'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Deliveries'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Active pickup'), findsOneWidget);
    expect(find.textContaining('Scheduled pickup'), findsNothing);

    await tester.tap(find.text('Scheduled'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Scheduled pickup'), findsOneWidget);
    expect(find.textContaining('Active pickup'), findsNothing);

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Completed pickup'), findsOneWidget);
  });

  testWidgets('Finance consumes the shared payment profile', (tester) async {
    await tester.pumpWidget(_app(status: 'approved'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(-900, 0));
    await tester.pumpAndSettle();
    final financeTab = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('business-tab-finance')),
    );
    financeTab.onSelected!(true);
    await tester.pumpAndSettle();

    expect(find.text('PAYMENT METHODS'), findsOneWidget);
    expect(find.text('Visa •••• 4242'), findsOneWidget);
    expect(find.text('Default payment method'), findsOneWidget);
  });

  testWidgets('Connected Products contains only current Business products',
      (tester) async {
    await tester.pumpWidget(_app(status: 'approved'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(-1100, 0));
    await tester.pumpAndSettle();
    final settingsTab = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('business-tab-settings')),
    );
    settingsTab.onSelected!(true);
    await tester.pumpAndSettle();

    expect(find.text('CONNECTED PRODUCTS'), findsOneWidget);
    expect(find.text('Business'), findsWidgets);
    expect(find.text('Health+'), findsWidgets);
    expect(find.text('Gifts'), findsWidgets);
    expect(find.text('Marketplace'), findsNothing);
    expect(find.text('Portal'), findsNothing);
    expect(find.text('ParkPal'), findsNothing);
    expect(find.text('FUTURE ACCESS'), findsNothing);
    expect(find.text('API Access'), findsNothing);
    expect(find.text('Approval Workflows'), findsNothing);
  });

  testWidgets('all four Quick Actions launch their canonical flows',
      (tester) async {
    var deliveries = 0;
    var health = 0;
    var gifts = 0;
    await tester.pumpWidget(MaterialApp(
      home: BusinessView(
        repository: _FakeBusinessRepository('approved'),
        paymentProfileRepository: _FakePaymentRepository(),
        onBookDelivery: () => deliveries += 1,
        onOpenHealthPlus: () => health += 1,
        onOpenGifts: () => gifts += 1,
      ),
    ));
    await tester.pumpAndSettle();

    for (final label in const [
      'Book a delivery',
      'Health+ request',
      'Corporate gift',
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
    }
    expect(deliveries, 1);
    expect(health, 1);
    expect(gifts, 1);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
    await tester.pumpAndSettle();
    final inviteTile = find.ancestor(
      of: find.text('Invite teammate'),
      matching: find.byType(InkWell),
    );
    await tester.tap(inviteTile);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Send invite'), findsOneWidget);
    expect(
      find.text('Booking uses the existing Circum Delivery Engine.'),
      findsNothing,
    );
  });
}

Widget _app({required String status}) {
  return MaterialApp(
    home: BusinessView(
      repository: _FakeBusinessRepository(status),
      paymentProfileRepository: _FakePaymentRepository(),
    ),
  );
}

class _FakeBusinessRepository implements BusinessRepository {
  final String status;
  _FakeBusinessRepository(this.status);

  BusinessAccount get account => BusinessAccount.fromMap('business-1', {
        'businessName': 'Lumen Studios Ltd',
        'status': status,
        'contactName': 'Jason Adesanya',
        'contactEmail': 'jason@example.com',
        'teamMembers': [
          {
            'userId': 'owner',
            'name': 'Jason Adesanya',
            'role': 'owner',
            'status': 'active',
          }
        ],
      });

  @override
  Future<List<BusinessAccount>> loadAccounts() async => [account];

  @override
  Future<BusinessWorkspaceData> loadWorkspace(BusinessAccount account) async {
    return BusinessWorkspaceData(
      account: account,
      deliveries: [
        BusinessDelivery.fromMap('active', {
          'pickupAddress': 'Active pickup',
          'dropoffAddress': 'Active drop-off',
          'status': 'in_transit',
          'totalAmount': 22,
        }),
        BusinessDelivery.fromMap('scheduled', {
          'pickupAddress': 'Scheduled pickup',
          'dropoffAddress': 'Scheduled drop-off',
          'status': 'scheduled',
          'totalAmount': 32,
        }),
        BusinessDelivery.fromMap('completed', {
          'pickupAddress': 'Completed pickup',
          'dropoffAddress': 'Completed drop-off',
          'status': 'delivered',
          'totalAmount': 42,
        }),
      ],
      invoices: const [
        BusinessInvoice(
          id: 'invoice-1',
          number: 'INV-001',
          status: 'due',
          total: 96,
          balanceDue: 96,
          rothApplied: 4,
          deliveryCount: 3,
          paymentReference: '',
        ),
      ],
      healthRequests: const [],
      giftRequests: const [],
      wallet: const BusinessWalletSummary(
        rothBalance: 25,
        lifetimeOffset: 12,
        status: 'active',
      ),
    );
  }

  @override
  Future<void> inviteMember(
      {required BusinessAccount account,
      required String email,
      required String role}) async {}

  @override
  Future<void> saveAccount(BusinessAccount account) async {}

  @override
  Future<void> updateMember(
      {required BusinessAccount account,
      required Map<String, dynamic> member,
      String? role,
      String? status,
      bool remove = false}) async {}

  @override
  Future<Uri> createInvoiceCheckout(
          {required BusinessAccount account,
          required BusinessInvoice invoice}) async =>
      Uri.parse('https://example.com');
}

class _FakePaymentRepository implements SenderPaymentProfileRepository {
  @override
  Future<SenderPaymentProfile> paymentMethods() async =>
      const SenderPaymentProfile(
        methods: [
          SenderPaymentMethod(
              id: 'pm_1', brand: 'Visa', last4: '4242', isDefault: true),
        ],
        preference: SenderCheckoutPreference.defaultCard,
        defaultPaymentMethodId: 'pm_1',
        applePaySupported: false,
        googlePaySupported: false,
      );

  @override
  Future<SenderSetupIntentData> createSetupIntent() =>
      throw UnimplementedError();
  @override
  Future<void> detachPaymentMethod(String paymentMethodId) =>
      throw UnimplementedError();
  @override
  Future<void> saveCheckoutPreference(SenderCheckoutPreference preference) =>
      throw UnimplementedError();
  @override
  Future<void> setDefaultPaymentMethod(String paymentMethodId) =>
      throw UnimplementedError();
}
