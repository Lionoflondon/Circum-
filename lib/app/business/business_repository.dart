import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'business_models.dart';

abstract class BusinessRepository {
  Future<List<BusinessAccount>> loadAccounts();
  Future<BusinessWorkspaceData> loadWorkspace(BusinessAccount account);
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
  Future<Uri> createInvoiceCheckout({
    required BusinessAccount account,
    required BusinessInvoice invoice,
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
  Future<void> saveAccount(BusinessAccount account) async {
    await firestore.collection('businessAccounts').doc(account.id).set({
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
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> inviteMember({
    required BusinessAccount account,
    required String email,
    required String role,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) throw ArgumentError('Enter an email address.');
    final member = {
      'userId': normalized,
      'email': normalized,
      'name': '',
      'role': role,
      'status': 'invited',
      'invitedAt': Timestamp.now(),
    };
    await firestore.collection('businessAccounts').doc(account.id).set({
      'teamMemberIds': FieldValue.arrayUnion([normalized]),
      if (role == 'owner' || role == 'admin')
        'managerIds': FieldValue.arrayUnion([normalized]),
      'teamMembers': FieldValue.arrayUnion([member]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
    final members = account.teamMembers
        .where((item) =>
            '${item['userId'] ?? item['email'] ?? ''}'.trim() != memberId)
        .map(Map<String, dynamic>.from)
        .toList(growable: true);
    if (!remove) {
      members.add({
        ...member,
        if (role != null) 'role': role,
        if (status != null) 'status': status,
        'updatedAt': Timestamp.now(),
      });
    }
    final ids = members
        .map((item) => '${item['userId'] ?? item['email'] ?? ''}'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final managers = members
        .where((item) => item['role'] == 'owner' || item['role'] == 'admin')
        .map((item) => '${item['userId'] ?? item['email'] ?? ''}'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    await firestore.collection('businessAccounts').doc(account.id).set({
      'teamMembers': members,
      'teamMemberIds': ids,
      'managerIds': managers,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> addIrisMoment({
    required BusinessAccount account,
    required Map<String, dynamic> moment,
  }) async {
    await firestore.collection('businessAccounts').doc(account.id).set({
      'irisMoments': FieldValue.arrayUnion([moment]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<Uri> createInvoiceCheckout({
    required BusinessAccount account,
    required BusinessInvoice invoice,
  }) async {
    final result =
        await functions.httpsCallable('createBusinessInvoiceCheckout').call({
      'businessId': account.id,
      'invoiceId': invoice.id,
      'amount': invoice.balanceDue,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final uri = Uri.tryParse('${data['url'] ?? data['checkoutUrl'] ?? ''}');
    if (uri == null || !uri.hasScheme) {
      throw StateError('Secure invoice checkout is unavailable.');
    }
    return uri;
  }
}

DateTime? _timestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
