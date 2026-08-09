import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'business_models.dart';

abstract class BusinessRepository {
  Future<List<BusinessAccount>> loadAccounts();
  Future<BusinessWorkspaceData> loadWorkspace(BusinessAccount account);
  Future<List<BusinessDeliveryTimelineEvent>> loadDeliveryTimeline({
    required BusinessAccount account,
    required String deliveryId,
  });
  Future<BusinessDeliveryPage> loadDeliveryPage({
    required BusinessAccount account,
    required Map<String, dynamic> cursor,
  });
  Future<BusinessCreatedResult> createBusinessAccount(
    BusinessCreateDraft draft,
  );
  Future<BusinessCodeLookupResult> lookupCompanyCode(String companyCode);
  Future<String> requestBusinessAccess({
    required BusinessCodeLookupResult business,
  });
  Future<String> ensureCompanyCode({
    required BusinessAccount account,
    bool rotate = false,
  });
  Future<List<BusinessAccessRequest>> loadPendingAccessRequests(
    BusinessAccount account,
  );
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
  Future<List<BusinessCustomRole>> loadCustomRoles(BusinessAccount account);
  Future<void> saveCustomRole({
    required BusinessAccount account,
    String? roleId,
    required String name,
    required String description,
    required List<String> permissions,
  });
  Future<void> deleteCustomRole({
    required BusinessAccount account,
    required String roleId,
  });
  Future<void> assignCustomRole({
    required BusinessAccount account,
    required Map<String, dynamic> member,
    required String roleId,
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
    final callable = await functions
        .httpsCallable('getBusinessOperationsWorkspace')
        .call({'businessId': account.id, 'pageSize': 20});
    final data = Map<String, dynamic>.from(callable.data as Map);
    final deliveries =
        (data['deliveries'] as List? ?? const []).whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      return BusinessDelivery.fromMap('${map['id'] ?? ''}', map);
    }).toList(growable: false)
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
              a.createdAt ?? DateTime(1970),
            ),
          );
    final invoices =
        (data['invoices'] as List? ?? const []).whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      return BusinessInvoice.fromMap('${map['id'] ?? ''}', map);
    }).toList(growable: false)
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
              a.createdAt ?? DateTime(1970),
            ),
          );
    return BusinessWorkspaceData(
      account: account,
      deliveries: deliveries,
      invoices: invoices,
      healthRequests: (data['healthRequests'] as List? ?? const [])
          .whereType<Map>()
          .map((item) {
        final map = Map<String, dynamic>.from(item);
        return BusinessRequestSummary(
          id: '${map['id'] ?? ''}',
          title: '${map['title'] ?? 'Health+ request'}',
          status: '${map['status'] ?? 'requested'}'.toLowerCase(),
          createdAt: _timestamp(map['createdAtMillis']),
        );
      }).toList(growable: false),
      giftRequests: (data['giftRequests'] as List? ?? const [])
          .whereType<Map>()
          .map((item) {
        final map = Map<String, dynamic>.from(item);
        return BusinessRequestSummary(
          id: '${map['id'] ?? ''}',
          title: '${map['title'] ?? 'Corporate gift'}',
          status: '${map['status'] ?? 'requested'}'.toLowerCase(),
          createdAt: _timestamp(map['createdAtMillis']),
        );
      }).toList(growable: false),
      wallet: data['wallet'] is Map
          ? BusinessWalletSummary(
              rothBalance:
                  (Map<String, dynamic>.from(data['wallet'] as Map)['balance']
                              as num?)
                          ?.toDouble() ??
                      0,
              lifetimeOffset: (Map<String, dynamic>.from(
                    data['wallet'] as Map,
                  )['lifetimeSpent'] as num?)
                      ?.toDouble() ??
                  0,
              status:
                  '${Map<String, dynamic>.from(data['wallet'] as Map)['status'] ?? 'active'}',
            )
          : BusinessWalletSummary.empty,
      summary: BusinessOperationsSummary.fromMap(
        Map<String, dynamic>.from(data['summary'] as Map? ?? const {}),
      ),
      permissions: BusinessWorkspacePermissions.fromMap(
        Map<String, dynamic>.from(data['permissions'] as Map? ?? const {}),
      ),
      role: '${data['role'] ?? ''}',
      nextDeliveryCursor: data['nextCursor'] is Map
          ? Map<String, dynamic>.from(data['nextCursor'] as Map)
          : null,
    );
  }

  @override
  Future<List<BusinessDeliveryTimelineEvent>> loadDeliveryTimeline({
    required BusinessAccount account,
    required String deliveryId,
  }) async {
    final callable = await functions
        .httpsCallable('getBusinessDeliveryTimeline')
        .call({'businessId': account.id, 'deliveryId': deliveryId});
    final data = Map<String, dynamic>.from(callable.data as Map);
    return (data['events'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => BusinessDeliveryTimelineEvent.fromMap(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<BusinessDeliveryPage> loadDeliveryPage({
    required BusinessAccount account,
    required Map<String, dynamic> cursor,
  }) async {
    final callable = await functions
        .httpsCallable('getBusinessOperationsWorkspace')
        .call({'businessId': account.id, 'pageSize': 20, 'cursor': cursor});
    final data = Map<String, dynamic>.from(callable.data as Map);
    return BusinessDeliveryPage(
      deliveries: (data['deliveries'] as List? ?? const [])
          .whereType<Map>()
          .map((item) {
        final map = Map<String, dynamic>.from(item);
        return BusinessDelivery.fromMap('${map['id'] ?? ''}', map);
      }).toList(growable: false),
      nextCursor: data['nextCursor'] is Map
          ? Map<String, dynamic>.from(data['nextCursor'] as Map)
          : null,
    );
  }

  @override
  Future<BusinessCreatedResult> createBusinessAccount(
    BusinessCreateDraft draft,
  ) async {
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
    final result = await functions
        .httpsCallable('lookupBusinessByCompanyCode')
        .call({'companyCode': companyCode});
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
    final result = await functions
        .httpsCallable('ensureBusinessCompanyCode')
        .call({'businessId': account.id, 'rotate': rotate});
    final data = Map<String, dynamic>.from(result.data as Map);
    return '${data['companyCode'] ?? ''}'.trim();
  }

  @override
  Future<List<BusinessAccessRequest>> loadPendingAccessRequests(
    BusinessAccount account,
  ) async {
    final snapshot = await firestore
        .collection('businessJoinRequests')
        .where('businessId', isEqualTo: account.id)
        .where('status', isEqualTo: 'pending')
        .limit(50)
        .get();
    return snapshot.docs
        .map((doc) => BusinessAccessRequest.fromMap(doc.id, doc.data()))
        .toList(growable: false)
      ..sort(
        (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
          a.createdAt ?? DateTime(1970),
        ),
      );
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
  Future<List<BusinessCustomRole>> loadCustomRoles(
      BusinessAccount account) async {
    final result = await functions
        .httpsCallable('listBusinessCustomRoles')
        .call({'businessId': account.id});
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['roles'] as List? ?? const [])
        .whereType<Map>()
        .map((item) =>
            BusinessCustomRole.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  @override
  Future<void> saveCustomRole({
    required BusinessAccount account,
    String? roleId,
    required String name,
    required String description,
    required List<String> permissions,
  }) async {
    await functions.httpsCallable('saveBusinessCustomRole').call({
      'businessId': account.id,
      if (roleId != null && roleId.isNotEmpty) 'roleId': roleId,
      'name': name,
      'description': description,
      'permissions': permissions,
    });
  }

  @override
  Future<void> deleteCustomRole({
    required BusinessAccount account,
    required String roleId,
  }) async {
    await functions.httpsCallable('deleteBusinessCustomRole').call({
      'businessId': account.id,
      'roleId': roleId,
    });
  }

  @override
  Future<void> assignCustomRole({
    required BusinessAccount account,
    required Map<String, dynamic> member,
    required String roleId,
  }) async {
    await functions.httpsCallable('assignBusinessCustomRole').call({
      'businessId': account.id,
      'memberUserId': '${member['userId'] ?? member['email'] ?? ''}',
      'roleId': roleId,
    });
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
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}
