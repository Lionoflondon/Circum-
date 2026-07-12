import 'package:circum/app/business/business_access_view.dart';
import 'package:circum/app/business/business_models.dart';
import 'package:circum/app/business/business_repository.dart';
import 'package:circum/app/sender_mobile/sender_finance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('non-member sees Business Entry before dashboard',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home:
          BusinessAccessView(repository: _AccessRepository(hasAccount: false)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Business for Circum'), findsOneWidget);
    expect(find.text('Create Business Account'), findsOneWidget);
    expect(find.text('Join Existing Business'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
  });

  testWidgets('member opens existing Business dashboard immediately',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BusinessAccessView(
        repository: _AccessRepository(hasAccount: true),
        paymentProfileRepository: _AccessPaymentRepository(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Business for Circum'), findsNothing);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Deliveries'), findsWidgets);
  });
}

class _AccessPaymentRepository implements SenderPaymentProfileRepository {
  @override
  Future<SenderPaymentProfile> paymentMethods() async =>
      SenderPaymentProfile.empty();

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

class _AccessRepository implements BusinessRepository {
  final bool hasAccount;

  _AccessRepository({required this.hasAccount});

  BusinessAccount get account => BusinessAccount.fromMap('business-1', {
        'businessName': 'Lumen Studios Ltd',
        'status': 'approved',
        'contactEmail': 'owner@example.com',
        'teamMembers': [
          {
            'userId': 'owner',
            'name': 'Owner',
            'role': 'owner',
            'status': 'active',
          }
        ],
      });

  @override
  Future<List<BusinessAccount>> loadAccounts() async =>
      hasAccount ? [account] : [];

  @override
  Future<BusinessWorkspaceData> loadWorkspace(BusinessAccount account) async =>
      BusinessWorkspaceData(
        account: account,
        deliveries: const [],
        invoices: const [],
        healthRequests: const [],
        giftRequests: const [],
        wallet: BusinessWalletSummary.empty,
      );

  @override
  Future<BusinessCreatedResult> createBusinessAccount(
          BusinessCreateDraft draft) async =>
      BusinessCreatedResult(
        businessId: 'business-1',
        companyName: draft.companyName,
        companyCode: '483917265',
      );

  @override
  Future<BusinessCodeLookupResult> lookupCompanyCode(
          String companyCode) async =>
      const BusinessCodeLookupResult(
        businessId: 'business-1',
        companyName: 'Lumen Studios Ltd',
        businessLogo: '',
        businessAddress: '1 Studio Way',
        businessStatus: 'approved',
        joinPolicy: 'approval_required',
        roleRequested: 'member',
      );

  @override
  Future<String> requestBusinessAccess({
    required BusinessCodeLookupResult business,
  }) async =>
      'pending';

  @override
  Future<List<BusinessAccessRequest>> loadPendingAccessRequests(
          BusinessAccount account) async =>
      const [];

  @override
  Future<void> reviewAccessRequest({
    required BusinessAccount account,
    required BusinessAccessRequest request,
    required bool approved,
  }) async {}

  @override
  Future<void> saveAccount(BusinessAccount account) async {}

  @override
  Future<void> inviteMember({
    required BusinessAccount account,
    required String email,
    required String role,
  }) async {}

  @override
  Future<void> updateMember({
    required BusinessAccount account,
    required Map<String, dynamic> member,
    String? role,
    String? status,
    bool remove = false,
  }) async {}

  @override
  Future<void> addIrisMoment({
    required BusinessAccount account,
    required Map<String, dynamic> moment,
  }) async {}

  @override
  Future<BusinessInvoicePaymentResult> payInvoice({
    required BusinessAccount account,
    required BusinessInvoice invoice,
    required bool useRoth,
    required String paymentMethod,
  }) async =>
      BusinessInvoicePaymentResult(
        paid: true,
        method: paymentMethod,
        totalInvoice: invoice.total,
        rothApplied: 0,
        cardAmount: invoice.balanceDue,
      );
}
