import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'business_models.dart';

abstract class BusinessRepository {
  Future<List<BusinessAccount>> loadAccounts();
  Future<BusinessWorkspaceData> loadWorkspace(BusinessAccount account);
  Future<BusinessCreatedResult> createBusinessAccount(
      BusinessCreateDraft draft);
  Future<BusinessCodeLookupResult> lookupCompanyCode(String companyCode);
  Future<String> requestBusinessAccess({
    required BusinessCodeLookupResult business,
  });
  Future<String> ensureCompanyCode({
    required BusinessAccount account,
    bool rotate = false,
  });
  Future<List<BusinessAccessRequest>> loadPendingAccessRequests(
      BusinessAccount account);
  Future<void> reviewAccessRequest({
    required BusinessAccount account,
    required BusinessAccessRequest request,
    required bool approved,
  });
  Future<void> saveAccount(BusinessAccount account);
  Future<void> inviteMember({
    required BusinessAccount account,
    required String email,
    required String role,
  });
  Future<void> updateMember({
    required BusinessAccount account,
    required Map<String, dynamic> member,
    String? role,
    String? status,
    bool remove = false,
  });
  Future<void> addIrisMoment({
    required BusinessAccount account,
    required Map<String, dynamic> moment,
  });
  Future<BusinessInvoicePaymentResult> payInvoice({
    required BusinessAccount account,
    required BusinessInvoice invoice,
    required bool useRoth,
    required String paymentMethod,
  });
}

class FirebaseBusinessRepository implements BusinessRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  FirebaseBusinessRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  User get _user {
    final user = auth.currentUser;
    if (user == null) throw StateError('Sign in to open Circum Business.');
    return user;
  }

  @override
  Future<List<BusinessAccount>> loadAccounts() async {
    final user = _user;
    final email = (user.email ?? '').trim().toLowerCase();
    final snapshots = await Future.wait([
      firestore
          .collection('businessAccounts')
          .where('createdByUserId', isEqualTo: user.uid)
          .limit(20)
          .get(),
      firestore
          .collection('businessAccounts')
          .where(
            'teamMemberIds',
            arrayContainsAny: [user.uid, if (email.isNotEmpty) email],
          )
          .limit(20)
          .get(),
    ]);
    final byId = <String, BusinessAccount>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        byId[doc.id] = BusinessAccount.fromMap(doc.id, doc.data());
      }
    }
    final accounts = byId.values.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    return accounts;
  }

  @override
  Future<BusinessWorkspaceData> loadWorkspace(BusinessAccount account) async {
    final results = await Future.wait([
      firestore
          .collection('deliveryRequests')
          .where('businessId', isEqualTo: account.id)
          .limit(200)
          .get(),
      firestore
          .collection('businessInvoices')
          .where('businessId', isEqualTo: account.id)
          .limit(100)
          .get(),
      firestore
          .collection('prescriptionPickups')
          .where('businessId', isEqualTo: account.id)
          .limit(100)
          .get(),
      firestore
          .collection('giftRequests')
          .where('businessId', isEqualTo: account.id)
          .limit(100)
          .get(),
      firestore.collection('business_wallets').doc(account.id).get(),
    ]);
    final deliveryDocs = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final invoiceDocs = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final healthDocs = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final giftDocs = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final walletDoc = results[4] as DocumentSnapshot<Map<String, dynamic>>;

    final deliveries = deliveryDocs.docs
        .map((doc) => BusinessDelivery.fromMap(doc.id, doc.data()))
        .toList(growable: false)
      ..sort((a, b) => (b.createdAt ?? DateTime(1970))
          .compareTo(a.createdAt ?? DateTime(1970)));
    final invoices = invoiceDocs.docs
        .map((doc) => BusinessInvoice.fromMap(doc.id, doc.data()))
        .toList(growable: false)
      ..sort((a, b) => (b.createdAt ?? DateTime(1970))
          .compareTo(a.createdAt ?? DateTime(1970)));
    return BusinessWorkspaceData(
      account: account,
      deliveries: deliveries,
      invoices: invoices,
      healthRequests: healthDocs.docs
          .map((doc) => BusinessRequestSummary(
                id: doc.id,
                title: '${doc.data()['patientName'] ?? 'Health+ request'}',
                status: '${doc.data()['status'] ?? 'requested'}'.toLowerCase(),
                createdAt: _timestamp(doc.data()['createdAt']),
              ))
          .toList(growable: false),
      giftRequests: giftDocs.docs
          .map((doc) => BusinessRequestSummary(
                id: doc.id,
                title: '${doc.data()['occasion'] ?? 'Corporate gift'}',
                status: '${doc.data()['status'] ?? 'requested'}'.toLowerCase(),
                createdAt: _timestamp(doc.data()['createdAt']),
              ))
          .toList(growable: false),
      wallet: walletDoc.exists
          ? BusinessWalletSummary(
              rothBalance:
                  (walletDoc.data()?['balance'] as num?)?.toDouble() ?? 0,
              lifetimeOffset:
                  (walletDoc.data()?['lifetimeSpent'] as num?)?.toDouble() ?? 0,
              status: '${walletDoc.data()?['status'] ?? 'active'}',
            )
          : BusinessWalletSummary.empty,
    );
  }

  @override
  Future<BusinessCreatedResult> createBusinessAccount(
      BusinessCreateDraft draft) async {
    final result = await functions.httpsCallable('createBusinessAccount').call({
      'companyName': draft.companyName,
      'businessType': draft.businessType,
      'businessEmail': draft.businessEmail,
      'businessPhone': draft.businessPhone,
      'businessAddress': draft.businessAddress,
      'vatNumber': draft.vatNumber,
      'businessSize': draft.businessSize,
      'acceptTerms': draft.acceptTerms,
    });
    return BusinessCreatedResult.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  @override
  Future<BusinessCodeLookupResult> lookupCompanyCode(String companyCode) async {
    final result =
        await functions.httpsCallable('lookupBusinessByCompanyCode').call({
      'companyCode': companyCode,
    });
    return BusinessCodeLookupResult.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  @override
  Future<String> requestBusinessAccess({
    required BusinessCodeLookupResult business,
  }) async {
    final result = await functions.httpsCallable('requestBusinessAccess').call({
      'businessId': business.businessId,
      'role': business.roleRequested,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return '${data['status'] ?? 'pending'}';
  }

  @override
  Future<String> ensureCompanyCode({
    required BusinessAccount account,
    bool rotate = false,
  }) async {
    final result =
        await functions.httpsCallable('ensureBusinessCompanyCode').call({
      'businessId': account.id,
      'rotate': rotate,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return '${data['companyCode'] ?? ''}'.trim();
  }

  @override
  Future<List<BusinessAccessRequest>> loadPendingAccessRequests(
      BusinessAccount account) async {
    final snapshot = await firestore
        .collection('businessJoinRequests')
        .where('businessId', isEqualTo: account.id)
        .where('status', isEqualTo: 'pending')
        .limit(50)
        .get();
    return snapshot.docs
        .map((doc) => BusinessAccessRequest.fromMap(doc.id, doc.data()))
        .toList(growable: false)
      ..sort((a, b) => (b.createdAt ?? DateTime(1970))
          .compareTo(a.createdAt ?? DateTime(1970)));
  }

  @override
  Future<void> reviewAccessRequest({
    required BusinessAccount account,
    required BusinessAccessRequest request,
    required bool approved,
  }) async {
    await functions.httpsCallable('reviewBusinessAccessRequest').call({
      'requestId': request.id,
      'businessId': account.id,
      'approved': approved,
    });
  }

  @override
  Future<void> saveAccount(BusinessAccount account) async {
    await functions.httpsCallable('updateBusinessProfile').call({
      'businessId': account.id,
      'businessName': account.name,
      'contactName': account.contactName,
      'contactEmail': account.contactEmail.toLowerCase(),
      'phone': account.phone,
      'billingEmail': account.billingEmail.toLowerCase(),
      'businessAddress': account.businessAddress,
      'companyNumber': account.companyNumber,
      'defaultPickupAddresses': [
        if (account.defaultPickupAddress.isNotEmpty)
          account.defaultPickupAddress,
      ],
      'notificationPreferences': account.notificationPreferences,
      'paymentPreferences': account.paymentPreferences,
    });
  }

  @override
  Future<void> inviteMember({
    required BusinessAccount account,
    required String email,
    required String role,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) throw ArgumentError('Enter an email address.');
    await functions.httpsCallable('inviteBusinessMember').call({
      'businessId': account.id,
      'email': normalized,
      'role': role,
    });
  }

  @override
  Future<void> updateMember({
    required BusinessAccount account,
    required Map<String, dynamic> member,
    String? role,
    String? status,
    bool remove = false,
  }) async {
    final memberId = '${member['userId'] ?? member['email'] ?? ''}'.trim();
    if (remove) {
      await functions.httpsCallable('removeBusinessMember').call({
        'businessId': account.id,
        'memberUserId': memberId,
      });
      return;
    }
    if (role != null) {
      await functions.httpsCallable('updateBusinessMemberRole').call({
        'businessId': account.id,
        'memberUserId': memberId,
        'role': role,
      });
    }
    if (status != null) {
      await functions.httpsCallable('updateBusinessMemberStatus').call({
        'businessId': account.id,
        'memberUserId': memberId,
        'status': status,
      });
    }
  }

  @override
  Future<void> addIrisMoment({
    required BusinessAccount account,
    required Map<String, dynamic> moment,
  }) async {
    await functions.httpsCallable('recordBusinessIrisMoment').call({
      'businessId': account.id,
      'moment': moment,
    });
  }

  @override
  Future<BusinessInvoicePaymentResult> payInvoice({
    required BusinessAccount account,
    required BusinessInvoice invoice,
    required bool useRoth,
    required String paymentMethod,
  }) async {
    final result =
        await functions.httpsCallable('createBusinessInvoiceCheckout').call({
      'businessId': account.id,
      'invoiceId': invoice.id,
      'paymentAmount': invoice.balanceDue,
      'useRoth': useRoth,
      'paymentMethod': paymentMethod,
      'returnUrl':
          'https://circum-app-2797c.web.app/?app=business&section=invoicing',
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final uri = Uri.tryParse('${data['url'] ?? data['checkoutUrl'] ?? ''}');
    final paid = data['paid'] == true;
    if (!paid && (uri == null || !uri.hasScheme)) {
      throw StateError('Secure invoice checkout is unavailable.');
    }
    return BusinessInvoicePaymentResult(
      paid: paid,
      method: '${data['method'] ?? paymentMethod}',
      totalInvoice: (data['totalInvoice'] as num?)?.toDouble() ?? invoice.total,
      rothApplied: (data['rothApplied'] as num?)?.toDouble() ?? 0,
      cardAmount:
          (data['cardAmount'] as num?)?.toDouble() ?? invoice.balanceDue,
      checkoutUrl: uri != null && uri.hasScheme ? uri : null,
    );
  }
}

DateTime? _timestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
