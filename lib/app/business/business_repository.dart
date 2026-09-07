import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import 'business_models.dart';

abstract class BusinessRepository {
  Future<List<BusinessAccount>> loadAccounts();
  Future<BusinessWorkspaceData> loadWorkspace(BusinessAccount account);
  Future<BusinessRequestHistory> loadRequestHistory(BusinessAccount account);
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
  Future<BusinessRothCheckoutResult> createRothCheckout({
    required BusinessAccount account,
    required double amount,
    required String idempotencyKey,
  });
}

const businessOperationTimeout = Duration(seconds: 15);

class BusinessRothCheckoutResult {
  final Uri checkoutUrl;
  final String purchaseId;

  const BusinessRothCheckoutResult({
    required this.checkoutUrl,
    required this.purchaseId,
  });
}

class BusinessRequestHistory {
  final List<BusinessRequestSummary> healthRequests;
  final List<BusinessRequestSummary> giftRequests;
  final List<BusinessRothTransaction> rothTransactions;

  const BusinessRequestHistory({
    required this.healthRequests,
    required this.giftRequests,
    required this.rothTransactions,
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

  Future<T> _bounded<T>(Future<T> operation) =>
      operation.timeout(businessOperationTimeout);

  @override
  Future<List<BusinessAccount>> loadAccounts() async {
    final user = _user;
    final email = (user.email ?? '').trim().toLowerCase();
    final snapshots = await _bounded(Future.wait([
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
    ]));
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
    final results = await _bounded(Future.wait<dynamic>([
      firestore
          .collection('deliveryRequests')
          .where('businessId', isEqualTo: account.id)
          .limit(25)
          .get(),
      firestore
          .collection('businessInvoices')
          .where('businessId', isEqualTo: account.id)
          .limit(25)
          .get(),
      firestore.collection('business_wallets').doc(account.id).get(),
    ]));
    final deliveryDocs = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final invoiceDocs = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final walletDoc = results[2] as DocumentSnapshot<Map<String, dynamic>>;

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
      healthRequests: const [],
      giftRequests: const [],
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
  Future<BusinessRequestHistory> loadRequestHistory(
      BusinessAccount account) async {
    final results = await _bounded(Future.wait([
      firestore
          .collection('prescriptionPickups')
          .where('businessId', isEqualTo: account.id)
          .limit(25)
          .get(),
      firestore
          .collection('giftRequests')
          .where('businessId', isEqualTo: account.id)
          .limit(25)
          .get(),
      functions.httpsCallable('listBusinessRothTransactions').call({
        'businessId': account.id,
      }),
    ]));
    final healthDocs = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final giftDocs = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final rothResult = results[2] as HttpsCallableResult<dynamic>;
    final rothData = Map<String, dynamic>.from(rothResult.data as Map);
    return BusinessRequestHistory(
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
      rothTransactions: (rothData['transactions'] as List? ?? const [])
          .map((item) => BusinessRothTransaction.fromMap(
              Map<String, dynamic>.from(item as Map)))
          .toList(growable: false),
    );
  }

  @override
  Future<BusinessCreatedResult> createBusinessAccount(
      BusinessCreateDraft draft) async {
    final result =
        await _bounded(functions.httpsCallable('createBusinessAccount').call({
      'companyName': draft.companyName,
      'businessType': draft.businessType,
      'businessEmail': draft.businessEmail,
      'businessPhone': draft.businessPhone,
      'businessAddress': draft.businessAddress,
      'vatNumber': draft.vatNumber,
      'businessSize': draft.businessSize,
      'acceptTerms': draft.acceptTerms,
    }));
    return BusinessCreatedResult.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  @override
  Future<BusinessCodeLookupResult> lookupCompanyCode(String companyCode) async {
    final result = await _bounded(
        functions.httpsCallable('lookupBusinessByCompanyCode').call({
      'companyCode': companyCode,
    }));
    return BusinessCodeLookupResult.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  @override
  Future<String> requestBusinessAccess({
    required BusinessCodeLookupResult business,
  }) async {
    final result =
        await _bounded(functions.httpsCallable('requestBusinessAccess').call({
      'businessId': business.businessId,
      'role': business.roleRequested,
    }));
    final data = Map<String, dynamic>.from(result.data as Map);
    return '${data['status'] ?? 'pending'}';
  }

  @override
  Future<String> ensureCompanyCode({
    required BusinessAccount account,
    bool rotate = false,
  }) async {
    final result = await _bounded(
        functions.httpsCallable('ensureBusinessCompanyCode').call({
      'businessId': account.id,
      'rotate': rotate,
    }));
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
        .get()
        .timeout(businessOperationTimeout);
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
    await _bounded(functions.httpsCallable('reviewBusinessAccessRequest').call({
      'requestId': request.id,
      'businessId': account.id,
      'approved': approved,
    }));
  }

  @override
  Future<void> saveAccount(BusinessAccount account) async {
    await _bounded(functions.httpsCallable('updateBusinessProfile').call({
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
    }));
  }

  @override
  Future<void> inviteMember({
    required BusinessAccount account,
    required String email,
    required String role,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) throw ArgumentError('Enter an email address.');
    await _bounded(functions.httpsCallable('inviteBusinessMember').call({
      'businessId': account.id,
      'email': normalized,
      'role': role,
    }));
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
      await _bounded(functions.httpsCallable('removeBusinessMember').call({
        'businessId': account.id,
        'memberUserId': memberId,
      }));
      return;
    }
    if (role != null) {
      await _bounded(functions.httpsCallable('updateBusinessMemberRole').call({
        'businessId': account.id,
        'memberUserId': memberId,
        'role': role,
      }));
    }
    if (status != null) {
      await _bounded(
          functions.httpsCallable('updateBusinessMemberStatus').call({
        'businessId': account.id,
        'memberUserId': memberId,
        'status': status,
      }));
    }
  }

  @override
  Future<void> addIrisMoment({
    required BusinessAccount account,
    required Map<String, dynamic> moment,
  }) async {
    await _bounded(functions.httpsCallable('recordBusinessIrisMoment').call({
      'businessId': account.id,
      'moment': moment,
    }));
  }

  @override
  Future<BusinessInvoicePaymentResult> payInvoice({
    required BusinessAccount account,
    required BusinessInvoice invoice,
    required bool useRoth,
    required String paymentMethod,
  }) async {
    final result = await _bounded(
        functions.httpsCallable('createBusinessInvoiceCheckout').call({
      'businessId': account.id,
      'invoiceId': invoice.id,
      'paymentAmount': invoice.balanceDue,
      'useRoth': useRoth,
      'paymentMethod': paymentMethod,
    }));
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

  @override
  Future<BusinessRothCheckoutResult> createRothCheckout({
    required BusinessAccount account,
    required double amount,
    required String idempotencyKey,
  }) async {
    if (!amount.isFinite ||
        amount < 1 ||
        amount > 10000 ||
        (amount * 100).roundToDouble() != amount * 100) {
      throw ArgumentError('Enter a Roth amount between £1 and £10,000.');
    }
    final requestKey = idempotencyKey.trim().isEmpty
        ? const Uuid().v4()
        : idempotencyKey.trim();
    final result = await _bounded(
      functions.httpsCallable('createBusinessRothCheckout').call({
        'businessId': account.id,
        'amount': amount,
        'idempotencyKey': requestKey,
        'returnUrl': 'https://circumuk.com/?app=business&section=finance',
      }),
    );
    final data = Map<String, dynamic>.from(result.data as Map);
    final checkoutUrl = Uri.tryParse('${data['checkoutUrl'] ?? ''}');
    if (checkoutUrl == null || !checkoutUrl.hasScheme) {
      throw StateError('Secure Roth checkout is unavailable.');
    }
    return BusinessRothCheckoutResult(
      checkoutUrl: checkoutUrl,
      purchaseId: '${data['purchaseId'] ?? ''}',
    );
  }
}

DateTime? _timestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
