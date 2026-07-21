import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_operations.dart';

enum AdminModule {
  dashboard('Dashboard', Icons.dashboard_rounded),
  visitorAnalytics('Visitor analytics', Icons.query_stats_rounded),
  deliveries('Deliveries', Icons.local_shipping_rounded),
  discrepancyReview('IRIS Operations', Icons.fact_check_rounded),
  irisRepository('IRIS Repository', Icons.inventory_2_rounded),
  irisCandidates('IRIS Candidates', Icons.psychology_alt_rounded),
  users('Users', Icons.people_alt_rounded),
  riders('Riders', Icons.two_wheeler_rounded),
  verification('Verification', Icons.verified_user_rounded),
  support('Support', Icons.support_agent_rounded),
  finance('Finance', Icons.account_balance_wallet_rounded),
  healthPlus('Health+', Icons.local_hospital_rounded),
  business('Business', Icons.business_center_rounded),
  gifts('Gifts', Icons.card_giftcard_rounded),
  troubleshooting('Troubleshooting', Icons.report_problem_rounded),
  analytics('Analytics', Icons.insights_rounded),
  audit('Audit', Icons.history_rounded),
  chat('Chat', Icons.forum_rounded),
  settings('Settings', Icons.settings_rounded);

  const AdminModule(this.label, this.icon);

  final String label;
  final IconData icon;
}

class AdminPhaseOneShell extends StatefulWidget {
  const AdminPhaseOneShell({super.key});

  @override
  State<AdminPhaseOneShell> createState() => _AdminPhaseOneShellState();
}

class _AdminPhaseOneShellState extends State<AdminPhaseOneShell> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _search = TextEditingController();
  final _adminInviteEmail = TextEditingController();
  final _adminInviteNote = TextEditingController();
  final _chatMessage = TextEditingController();
  final _announcementTitle = TextEditingController();
  final _announcementBody = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;

  AdminModule _module = AdminModule.dashboard;
  User? _user;
  List<String> _roles = const [];
  AdminMetricSnapshot _metrics = AdminMetricSnapshot.empty();
  AdminDataBundle _data = AdminDataBundle.empty();
  Map<String, dynamic>? _selectedRider;
  Map<String, dynamic>? _selectedDelivery;
  Map<String, dynamic>? _selectedHealthPlus;
  Map<String, dynamic>? _selectedAccount;
  String _selectedAccountType = 'sender';
  Map<String, dynamic>? _selectedChat;
  List<Map<String, dynamic>> _selectedChatMessages = const [];
  AdminRole _adminInviteRole = AdminRole.operationsAdmin;
  bool _loading = true;
  bool _signingIn = false;
  bool _loadingData = false;
  String? _message;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatMessagesSub;

  @override
  void initState() {
    super.initState();
    _authSub = _auth.authStateChanges().listen((user) {
      unawaited(_restore(user));
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _chatMessagesSub?.cancel();
    _email.dispose();
    _password.dispose();
    _search.dispose();
    _adminInviteEmail.dispose();
    _adminInviteNote.dispose();
    _chatMessage.dispose();
    _announcementTitle.dispose();
    _announcementBody.dispose();
    super.dispose();
  }

  Future<void> _restore(User? user) async {
    setState(() {
      _loading = true;
      _message = null;
    });
    if (user == null) {
      setState(() {
        _user = null;
        _roles = const [];
        _data = AdminDataBundle.empty();
        _metrics = AdminMetricSnapshot.empty();
        _loading = false;
      });
      return;
    }
    try {
      final roles = await _loadRoles(user);
      setState(() {
        _user = user;
        _email.text = user.email ?? _email.text;
        _roles = roles;
      });
      if (AdminAccessPolicy.hasAnyAdminRole(roles)) {
        await _loadAdminData();
      } else {
        setState(
          () => _message =
              'This account is signed in but has no active Circum admin role.',
        );
      }
    } catch (_) {
      setState(() => _message = 'Could not load Admin access.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<String>> _loadRoles(User user) async {
    final token = await user.getIdTokenResult(true);
    final claims = token.claims ?? const <String, dynamic>{};
    final claimRoles = <String>[
      if (claims['adminRole'] != null) '${claims['adminRole']}',
      if (claims['role'] != null) '${claims['role']}',
      if (claims['roles'] is List)
        ...(claims['roles'] as List<dynamic>).map((role) => '$role'),
    ];
    final uidDoc = await _db.collection('adminUsers').doc(user.uid).get();
    final email = user.email?.trim().toLowerCase();
    final emailDoc = email == null || email.isEmpty
        ? null
        : await _db.collection('adminUsers').doc(email).get();
    final records = [
      if (uidDoc.exists) uidDoc.data(),
      if (emailDoc?.exists == true) emailDoc?.data(),
    ];
    if (AdminUserAccess.hasInactiveAdminRecord(records)) return const [];
    final docRoles = records
        .expand((record) => AdminUserAccess.activeRolesFromRecord(record))
        .toList();
    final roles = {...claimRoles, ...docRoles}.toList();
    if (roles.isNotEmpty) {
      final patch = {'lastLoginAt': FieldValue.serverTimestamp()};
      if (uidDoc.exists) {
        await _db
            .collection('adminUsers')
            .doc(user.uid)
            .set(patch, SetOptions(merge: true));
      }
      if (emailDoc?.exists == true && email != null) {
        await _db
            .collection('adminUsers')
            .doc(email)
            .set(patch, SetOptions(merge: true));
      }
    }
    return roles;
  }

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _message = 'Checking Admin access...';
    });
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
      await _restore(credential.user);
    } on FirebaseAuthException catch (error) {
      setState(() => _message = _authMessage(error));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    setState(() {
      _module = AdminModule.dashboard;
      _message = 'Signed out of Admin.';
    });
  }

  Future<void> _loadAdminData() async {
    setState(() => _loadingData = true);
    try {
      final data = await AdminRepository(_db).load(
        canManageAdmins: _can(AdminPermission.manageAdmins),
        canViewFinance: _can(AdminPermission.viewFinance),
        canViewSupport: _can(AdminPermission.viewSupport),
        canViewHealthPlus: _can(AdminPermission.viewHealthPlus),
      );
      setState(() {
        _data = data;
        _metrics = AdminMetricSnapshot.fromData(
          deliveries: data.deliveries,
          senders: data.users,
          drivers: data.riders,
          payments: data.payments,
          ratings: data.ratings,
          supportTickets: data.supportTickets,
          healthPlusPayments: data.healthPlusPayments,
        );
        _message = 'Admin data refreshed.';
      });
    } catch (_) {
      setState(() => _message = 'Could not load Admin data.');
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _writeAudit(AdminAuditEntry entry) async {
    await _db.collection('adminAuditLogs').add({
      ...entry.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  String _idFor(Map<String, dynamic> record) {
    return '${record['id'] ?? record['requestId'] ?? record['uid'] ?? ''}'
        .trim();
  }

  Future<Map<String, dynamic>> _callRiderAuthority(
    Map<String, Object?> payload,
  ) async {
    final result = await _functions
        .httpsCallable('adminReviewRider')
        .call(payload);
    return Map<String, dynamic>.from(result.data as Map? ?? {});
  }

  Future<void> _duplicateDelivery(Map<String, dynamic> delivery) async {
    if (!_can(AdminPermission.duplicateDeliveries)) {
      setState(() => _message = 'Your role cannot duplicate deliveries.');
      return;
    }
    final newId = 'CIR-ADM-${DateTime.now().millisecondsSinceEpoch}';
    final duplicate = AdminDeliveryTools.duplicateDelivery(
      delivery,
      newId: newId,
      createdAt: FieldValue.serverTimestamp(),
    );
    await _db.collection('deliveryRequests').doc(newId).set(duplicate);
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'delivery_duplicate',
        recordType: 'deliveryRequests',
        recordId: newId,
        oldValue: {'requestId': delivery['requestId'] ?? delivery['id']},
        newValue: {'requestId': newId},
        reason: 'Admin duplicated delivery from operations console',
      ),
    );
    setState(() => _message = 'Duplicated delivery as $newId.');
    await _loadAdminData();
  }

  Future<void> _setRiderStatus(
    Map<String, dynamic> rider,
    String status,
  ) async {
    if (!_can(AdminPermission.approveDrivers)) {
      setState(() => _message = 'Your role cannot manage rider status.');
      return;
    }
    final id = _idFor(rider);
    if (id.isEmpty) return;
    final action = switch (status) {
      'approved' => 'approve',
      'rejected' => 'reject',
      'suspended' => 'suspend',
      'reactivated' => 'reactivate',
      _ => 'set_eligibility',
    };
    final eligibilityState = switch (status) {
      'investigation_cleared' || 'documents_approved' => 'eligible',
      'documents_requested' || 'under_investigation' => 'under_review',
      _ => 'ineligible',
    };
    final result = await _callRiderAuthority({
      'riderId': id,
      'action': action,
      if (action == 'set_eligibility') 'eligibilityState': eligibilityState,
      'reason': 'Updated from Circum Admin Rider Operations',
    });
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'rider_status_$status',
        recordType: 'riderProfiles',
        recordId: id,
        oldValue: {
          'approvalStatus': rider['approvalStatus'],
          'driverStatus': rider['driverStatus'],
        },
        newValue: result,
        reason: 'Rider status updated from Admin',
      ),
    );
    setState(() => _message = 'Rider $id updated to $status.');
    await _loadAdminData();
  }

  Future<void> _syncRiderStripeStatus(Map<String, dynamic> rider) async {
    if (!_can(AdminPermission.approveDrivers)) {
      setState(() => _message = 'Your role cannot sync Rider Stripe.');
      return;
    }
    final riderId = _riderId(rider);
    if (riderId.isEmpty) return;
    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('syncStripeConnectStatus').call({'riderId': riderId});
      await _writeRiderAdminEvent(riderId, 'stripe_status_synced');
      setState(() => _message = 'Rider Stripe status synced.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message = error.message ?? 'Could not sync Rider Stripe.',
      );
    }
  }

  Future<void> _resetRiderStripe(Map<String, dynamic> rider) async {
    if (!_can(AdminPermission.approveDrivers)) {
      setState(() => _message = 'Your role cannot reset Rider Stripe.');
      return;
    }
    final riderId = _riderId(rider);
    if (riderId.isEmpty) return;
    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('resetRiderTestStripeAccount').call({'riderId': riderId});
      await _writeRiderAdminEvent(riderId, 'stripe_test_account_reset');
      setState(() => _message = 'Rider test Stripe account reset.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message = error.message ?? 'Could not reset Rider Stripe.',
      );
    }
  }

  Future<void> _requestRiderMoreInformation(Map<String, dynamic> rider) async {
    if (!_can(AdminPermission.approveDrivers)) {
      setState(() => _message = 'Your role cannot request Rider information.');
      return;
    }
    final riderId = _riderId(rider);
    if (riderId.isEmpty) return;
    const note = 'Additional information requested from Circum Admin.';
    await _callRiderAuthority({
      'riderId': riderId,
      'action': 'request_more_information',
      'reason': note,
    });
    await _writeRiderAdminEvent(
      riderId,
      'more_information_requested',
      previousStatus:
          '${rider['verificationStatus'] ?? rider['approvalStatus'] ?? ''}',
      newStatus: 'more_information_requested',
      note: note,
    );
    setState(() => _message = 'More information requested from Rider.');
    await _loadAdminData();
  }

  Future<void> _reviewRiderDocument(
    Map<String, dynamic> document,
    String nextStatus,
  ) async {
    if (!_can(AdminPermission.approveDrivers)) {
      setState(() => _message = 'Your role cannot review Rider documents.');
      return;
    }
    final documentId = _idFor(document);
    final riderId =
        '${document['riderId'] ?? document['driverId'] ?? document['uid'] ?? ''}'
            .trim();
    if (documentId.isEmpty || riderId.isEmpty) return;
    final previous =
        '${document['status'] ?? document['verificationStatus'] ?? 'missing'}';
    await _callRiderAuthority({
      'riderId': riderId,
      'action': 'review_document',
      'documentId': documentId,
      'documentStatus': nextStatus,
      'reason': 'Document $nextStatus from isolated Circum Admin.',
    });
    await _writeRiderAdminEvent(
      riderId,
      nextStatus == 'approved'
          ? 'document_approved'
          : nextStatus == 'rejected'
          ? 'document_rejected'
          : 'document_replacement_requested',
      previousStatus: previous,
      newStatus: nextStatus,
    );
    setState(() => _message = 'Rider document $documentId updated.');
    await _loadAdminData();
  }

  Future<void> _removeRiderProfilePhoto(Map<String, dynamic> rider) async {
    if (!_can(AdminPermission.approveDrivers)) {
      setState(() => _message = 'Your role cannot remove Rider photos.');
      return;
    }
    final riderId = _riderId(rider);
    if (riderId.isEmpty) return;
    await _callRiderAuthority({
      'riderId': riderId,
      'action': 'remove_profile_photo',
      'reason': 'Removed from isolated Circum Admin.',
      'profilePhotoPath': rider['profilePhotoPath'] ?? rider['photoPath'],
      'profileThumbnailPath': rider['profileThumbnailPath'],
    });
    await _writeRiderAdminEvent(
      riderId,
      'profile_photo_removed',
      previousStatus: '${rider['photoURL'] ?? rider['photoUrl'] ?? ''}',
      newStatus: 'removed',
      note: 'Removed from isolated Circum Admin.',
    );
    setState(() => _message = 'Rider profile photo removed.');
    await _loadAdminData();
  }

  Future<void> _writeRiderAdminEvent(
    String riderId,
    String action, {
    String? previousStatus,
    String? newStatus,
    String? note,
  }) async {
    await _db.collection('riderAdminEvents').add({
      'riderId': riderId,
      'adminId': _user?.uid ?? 'unknown-admin',
      'adminEmail': _user?.email,
      'action': action,
      'previousStatus': previousStatus,
      'newStatus': newStatus,
      'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _setDeliveryOperationStatus(
    Map<String, dynamic> delivery,
    String status,
  ) async {
    if (!_can(AdminPermission.editDeliveries)) {
      setState(() => _message = 'Your role cannot manage deliveries.');
      return;
    }
    final id = _idFor(delivery);
    if (id.isEmpty) return;
    final patch = AdminDeliveryOperationsTools.operationPatch(
      status: status,
      updatedBy: _user?.email ?? _user?.uid ?? 'admin',
      updatedAt: FieldValue.serverTimestamp(),
      reason: 'Updated from Circum Admin Delivery Operations',
    );
    await _db
        .collection('deliveryRequests')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'delivery_operation_$status',
        recordType: 'deliveryRequests',
        recordId: id,
        oldValue: {
          'status': delivery['status'],
          'deliveryStatus': delivery['deliveryStatus'],
          'adminOperationStatus': delivery['adminOperationStatus'],
        },
        newValue: patch,
        reason: 'Delivery operation status updated from Admin',
      ),
    );
    setState(() => _message = 'Delivery $id queued for $status.');
    await _loadAdminData();
  }

  Future<void> _resolveStaleDeliveryLock(Map<String, dynamic> delivery) async {
    if (!_can(AdminPermission.editDeliveries)) {
      setState(() => _message = 'Your role cannot resolve stale deliveries.');
      return;
    }
    final id = _idFor(delivery);
    if (id.isEmpty) return;
    try {
      await _functions.httpsCallable('resolveStaleDeliveryLock').call({
        'deliveryId': id,
        'action': 'admin_removed_stale',
        'reason': 'Resolved from isolated Circum Admin delivery operations',
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'delivery_stale_lock_resolved',
          recordType: 'deliveryRequests',
          recordId: id,
          oldValue: {
            'status': delivery['status'],
            'deliveryStatus': delivery['deliveryStatus'],
            'lockStatus': delivery['lockStatus'],
          },
          newValue: const {'action': 'admin_removed_stale'},
          reason: 'Historical stale delivery lock workflow restored',
        ),
      );
      setState(() => _message = 'Stale delivery lock resolved for $id.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message =
            error.message ?? 'Could not resolve stale delivery lock.',
      );
    }
  }

  Future<void> _archiveDeliveryFromAdmin(Map<String, dynamic> delivery) async {
    if (!_can(AdminPermission.editDeliveries)) {
      setState(() => _message = 'Your role cannot archive deliveries.');
      return;
    }
    final id = _idFor(delivery);
    if (id.isEmpty) return;
    await _db.collection('deliveryRequests').doc(id).set({
      'adminArchiveStatus': 'archived',
      'archivedByAdminId': _user?.uid,
      'archivedByAdminEmail': _user?.email,
      'archivedAt': FieldValue.serverTimestamp(),
      'adminArchiveReason': 'Archived from isolated Circum Admin',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'delivery_archived',
        recordType: 'deliveryRequests',
        recordId: id,
        oldValue: {
          'adminArchiveStatus': delivery['adminArchiveStatus'],
          'status': delivery['status'],
        },
        newValue: const {'adminArchiveStatus': 'archived'},
        reason: 'Delivery archived from Admin operations',
      ),
    );
    setState(() => _message = 'Delivery $id archived.');
    await _loadAdminData();
  }

  Future<void> _setIrisReviewStatus(
    Map<String, dynamic> delivery,
    String status,
  ) async {
    if (!_can(AdminPermission.editDeliveries)) {
      setState(() => _message = 'Your role cannot manage IRIS reviews.');
      return;
    }
    final id = _idFor(delivery);
    if (id.isEmpty) return;
    final patch = AdminIrisOperationsTools.reviewPatch(
      status: status,
      updatedBy: _user?.email ?? _user?.uid ?? 'admin',
      updatedAt: FieldValue.serverTimestamp(),
      reason: 'Updated from Circum Admin IRIS Operations',
    );
    await _db
        .collection('deliveryRequests')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'iris_review_$status',
        recordType: 'deliveryRequests',
        recordId: id,
        oldValue: {
          'irisReviewStatus': delivery['irisReviewStatus'],
          'reviewType': delivery['reviewType'],
        },
        newValue: patch,
        reason: 'IRIS review updated from Admin',
      ),
    );
    setState(() => _message = 'IRIS review for $id marked $status.');
    await _loadAdminData();
  }

  Future<void> _loadIrisReferenceImage(Map<String, dynamic> item) async {
    if (!_can(AdminPermission.editDeliveries)) {
      setState(() => _message = 'Your role cannot review IRIS images.');
      return;
    }
    final itemId = _idFor(item);
    if (itemId.isEmpty) return;
    try {
      await _functions.httpsCallable('getIrisReferenceImage').call({
        'itemId': itemId,
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'iris_reference_image_loaded',
          recordType: 'irisCanonicalObjects',
          recordId: itemId,
          reason: 'IRIS reference image opened from Admin',
        ),
      );
      setState(() => _message = 'Reference image loaded for $itemId.');
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message = error.message ?? 'Reference image could not load.',
      );
    }
  }

  Future<void> _finalizeIrisReferenceImage(Map<String, dynamic> item) async {
    if (!_can(AdminPermission.editDeliveries)) {
      setState(() => _message = 'Your role cannot finalise IRIS images.');
      return;
    }
    final itemId = _idFor(item);
    final storagePath =
        '${item['storagePath'] ?? item['referenceImageStoragePath'] ?? item['pendingStoragePath'] ?? ''}'
            .trim();
    if (itemId.isEmpty || storagePath.isEmpty) {
      setState(
        () =>
            _message = 'Reference finalisation needs an item and storage path.',
      );
      return;
    }
    try {
      await _functions.httpsCallable('finalizeIrisReferenceImage').call({
        'itemId': itemId,
        'storagePath': storagePath,
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'iris_reference_image_finalized',
          recordType: '${item['_collection'] ?? 'irisReferenceImages'}',
          recordId: itemId,
          newValue: {'storagePath': storagePath},
          reason: 'Historical IRIS reference image finalisation restored',
        ),
      );
      setState(() => _message = 'Reference image finalised for $itemId.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message =
            error.message ?? 'Reference image could not be finalised.',
      );
    }
  }

  Future<void> _deleteIrisReferenceImage(Map<String, dynamic> item) async {
    if (!_can(AdminPermission.editDeliveries)) {
      setState(() => _message = 'Your role cannot remove IRIS images.');
      return;
    }
    final itemId = _idFor(item);
    if (itemId.isEmpty) return;
    try {
      await _functions.httpsCallable('deleteIrisReferenceImage').call({
        'itemId': itemId,
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'iris_reference_image_deleted',
          recordType: '${item['_collection'] ?? 'irisReferenceImages'}',
          recordId: itemId,
          oldValue: {
            'previewUrl': item['previewUrl'],
            'referenceImageUrl': item['referenceImageUrl'],
          },
          reason: 'Historical IRIS reference image removal restored',
        ),
      );
      setState(() => _message = 'Reference image removed for $itemId.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () =>
            _message = error.message ?? 'Reference image could not be removed.',
      );
    }
  }

  Future<void> _setSenderAccountStatus(
    Map<String, dynamic> account,
    String status,
  ) async {
    if (!_can(AdminPermission.editCustomers)) {
      setState(() => _message = 'Your role cannot manage sender accounts.');
      return;
    }
    final id = _idFor(account);
    if (id.isEmpty) return;
    final patch = AdminAccountTools.accountStatusPatch(
      status: status,
      updatedBy: _user?.email ?? _user?.uid ?? 'admin',
      updatedAt: FieldValue.serverTimestamp(),
      reason: 'Updated from Circum Admin',
    );
    await _db.collection('users').doc(id).set(patch, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'sender_account_$status',
        recordType: 'users',
        recordId: id,
        oldValue: {
          'status': account['status'],
          'accountStatus': account['accountStatus'],
        },
        newValue: patch,
        reason: 'Sender account status updated from Admin',
      ),
    );
    setState(() => _message = 'Sender account $id updated to $status.');
    await _loadAdminData();
  }

  Future<void> _setBusinessAccountStatus(
    Map<String, dynamic> account,
    String status,
  ) async {
    if (!_can(AdminPermission.editCustomers)) {
      setState(() => _message = 'Your role cannot manage Business accounts.');
      return;
    }
    final id = _idFor(account);
    if (id.isEmpty) return;
    final patch = AdminAccountTools.businessStatusPatch(
      status: status,
      updatedBy: _user?.email ?? _user?.uid ?? 'admin',
      updatedAt: FieldValue.serverTimestamp(),
    );
    await _db
        .collection('businessAccounts')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'business_account_$status',
        recordType: 'businessAccounts',
        recordId: id,
        oldValue: {
          'status': account['status'],
          'verificationStatus': account['verificationStatus'],
        },
        newValue: patch,
        reason: 'Business account status updated from Admin',
      ),
    );
    setState(() => _message = 'Business account $id updated to $status.');
    await _loadAdminData();
  }

  Future<void> _setBusinessOperationStatus(
    Map<String, dynamic> account,
    String status,
  ) async {
    if (!_can(AdminPermission.editCustomers)) {
      setState(() => _message = 'Your role cannot manage Business operations.');
      return;
    }
    final id = _idFor(account);
    if (id.isEmpty) return;
    final patch = AdminBusinessOperationsTools.operationPatch(
      status: status,
      updatedBy: _user?.email ?? _user?.uid ?? 'admin',
      updatedAt: FieldValue.serverTimestamp(),
      reason: 'Updated from Circum Admin Business Operations',
    );
    await _db
        .collection('businessAccounts')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'business_operation_$status',
        recordType: 'businessAccounts',
        recordId: id,
        oldValue: {
          'status': account['status'],
          'businessOperationStatus': account['businessOperationStatus'],
        },
        newValue: patch,
        reason: 'Business operation updated from Admin',
      ),
    );
    setState(() => _message = 'Business operation $id marked $status.');
    await _loadAdminData();
  }

  Future<void> _changeBusinessMemberRole(
    Map<String, dynamic> member,
    String role,
  ) async {
    if (!_can(AdminPermission.editCustomers)) {
      setState(() => _message = 'Your role cannot manage Business members.');
      return;
    }
    final businessId = '${member['businessId'] ?? member['id'] ?? ''}'.trim();
    final index = member['memberIndex'] is int
        ? member['memberIndex'] as int
        : -1;
    if (businessId.isEmpty || index < 0) return;
    final snapshot = await _db
        .collection('businessAccounts')
        .doc(businessId)
        .get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final members = ((data['teamMembers'] as List?) ?? const [])
        .map(
          (item) => item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{},
        )
        .toList();
    if (index >= members.length) return;
    final previousRole = members[index]['role'];
    members[index]['role'] = role;
    members[index]['updatedAt'] = Timestamp.now();
    members[index]['updatedByAdmin'] = _user?.email ?? _user?.uid;
    await _db.collection('businessAccounts').doc(businessId).set({
      'teamMembers': members,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _user?.uid,
      'updatedByEmail': _user?.email,
    }, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'business_member_role_updated',
        recordType: 'businessAccounts',
        recordId: businessId,
        oldValue: {'role': previousRole},
        newValue: {'role': role, 'member': member['email'] ?? member['userId']},
        reason: 'Business member role updated from Admin',
      ),
    );
    setState(() => _message = 'Business member role updated to $role.');
    await _loadAdminData();
  }

  Future<void> _removeBusinessMember(Map<String, dynamic> member) async {
    if (!_can(AdminPermission.editCustomers)) {
      setState(() => _message = 'Your role cannot manage Business members.');
      return;
    }
    final businessId = '${member['businessId'] ?? member['id'] ?? ''}'.trim();
    final index = member['memberIndex'] is int
        ? member['memberIndex'] as int
        : -1;
    if (businessId.isEmpty || index < 0) return;
    final snapshot = await _db
        .collection('businessAccounts')
        .doc(businessId)
        .get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final members = ((data['teamMembers'] as List?) ?? const [])
        .map(
          (item) => item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{},
        )
        .toList();
    if (index >= members.length) return;
    final removed = members.removeAt(index);
    await _db.collection('businessAccounts').doc(businessId).set({
      'teamMembers': members,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _user?.uid,
      'updatedByEmail': _user?.email,
    }, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'business_member_removed',
        recordType: 'businessAccounts',
        recordId: businessId,
        oldValue: removed,
        newValue: {'memberRemoved': true},
        reason: 'Business member removed from Admin',
      ),
    );
    setState(() => _message = 'Business member removed.');
    await _loadAdminData();
  }

  Future<void> _requestDuplicateMerge(
    Map<String, dynamic> account,
    Map<String, dynamic> duplicate,
  ) async {
    if (!_can(AdminPermission.editCustomers)) {
      setState(() => _message = 'Your role cannot request account merges.');
      return;
    }
    final id = _idFor(account);
    final duplicateId = _idFor(duplicate);
    try {
      final record = AdminAccountTools.mergeReviewRecord(
        primaryAccountId: id,
        duplicateAccountId: duplicateId,
        requestedBy: _user?.email ?? _user?.uid ?? 'admin',
        createdAt: FieldValue.serverTimestamp(),
      );
      await _db.collection('accountMergeReviews').add(record);
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'account_merge_review_requested',
          recordType: 'accountMergeReviews',
          recordId: '$id:$duplicateId',
          newValue: {'primaryAccountId': id, 'duplicateAccountId': duplicateId},
          reason: 'Duplicate account merge review requested from Admin',
        ),
      );
      setState(() => _message = 'Merge review requested for $duplicateId.');
    } on ArgumentError catch (error) {
      setState(() => _message = error.message);
    }
  }

  Future<void> _updateSupportTicket(
    Map<String, dynamic> ticket,
    String status,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage support tickets.');
      return;
    }
    final id = _idFor(ticket);
    if (id.isEmpty) return;
    try {
      await _functions.httpsCallable('updateSupportConversationStatus').call({
        'ticketId': id,
        'conversationId': ticket['conversationId'] ?? ticket['chatId'],
        'status': status,
        'assignedTo': status == 'assigned' ? _user?.email : null,
        'resolutionNote': status == 'resolved'
            ? 'Resolved from Circum Admin'
            : null,
        'reason': 'Support workflow action confirmed from Admin',
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'support_ticket_$status',
          recordType: 'supportTickets',
          recordId: id,
          oldValue: {'status': ticket['status']},
          newValue: {'status': status},
          reason: 'Support ticket updated from Admin',
        ),
      );
      setState(() => _message = 'Support ticket $id updated to $status.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = _functionsMessage(error));
    } catch (_) {
      setState(() => _message = 'Could not update support ticket $id.');
    }
  }

  Future<void> _updateGiftWorkflow(
    Map<String, dynamic> gift,
    String status,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage gift operations.');
      return;
    }
    final id = _idFor(gift);
    if (id.isEmpty) return;
    try {
      final patch = AdminGiftTools.workflowPatch(
        status: status,
        updatedBy: _user?.email ?? _user?.uid ?? 'admin',
        updatedAt: FieldValue.serverTimestamp(),
        reason: 'Gift workflow action confirmed from Admin',
      );
      await _db
          .collection('${gift['_collection'] ?? 'giftOrders'}')
          .doc(id)
          .set(patch, SetOptions(merge: true));
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'gift_workflow_$status',
          recordType: '${gift['_collection'] ?? 'giftOrders'}',
          recordId: id,
          oldValue: {
            'status': gift['status'],
            'giftAdminStatus': gift['giftAdminStatus'],
          },
          newValue: patch,
          reason: 'Gift workflow updated from Admin',
        ),
      );
      setState(() => _message = 'Gift $id updated to $status.');
      await _loadAdminData();
    } on ArgumentError catch (error) {
      setState(() => _message = error.message);
    }
  }

  Future<void> _updateGiftCampaignParticipant(
    Map<String, dynamic> participant,
    String status,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage gift campaigns.');
      return;
    }
    final id = _idFor(participant);
    if (id.isEmpty) return;
    await _db.collection('giftCampaignParticipants').doc(id).set({
      'matchStatus': status,
      'adminReviewStatus': status,
      if (status == 'assign_later')
        'assignmentDeferredAt': FieldValue.serverTimestamp(),
      if (status == 'assign_later') 'assignmentDeferredBy': _user?.uid,
      if (status == 'rejected') 'suggestedParticipantId': FieldValue.delete(),
      if (status == 'rejected') 'suggestedMatchScore': FieldValue.delete(),
      if (status == 'rejected') 'suggestedMatchReason': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'gift_campaign_participant_$status',
        recordType: 'giftCampaignParticipants',
        recordId: id,
        oldValue: {'matchStatus': participant['matchStatus']},
        newValue: {'matchStatus': status},
        reason: 'Gift campaign participant reviewed from Admin',
      ),
    );
    setState(() => _message = 'Gift campaign participant $id updated.');
    await _loadAdminData();
  }

  Future<void> _setGiftBrandStatus(
    Map<String, dynamic> brand,
    String status,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage Gift Brand Partners.');
      return;
    }
    final id = _brandId(brand);
    if (id.isEmpty) return;
    final confirmed = await _confirmAdminAction(
      'Confirm Brand Partner action',
      'Set ${brand['partnerName'] ?? brand['brandName'] ?? id} to $status?',
    );
    if (!confirmed) return;
    final patch = AdminGiftTools.brandPartnerPatch(
      status: status,
      updatedBy: _user?.email ?? _user?.uid ?? 'admin',
      updatedAt: FieldValue.serverTimestamp(),
    );
    await _db
        .collection('giftBrands')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'gift_brand_partner_$status',
        recordType: 'giftBrands',
        recordId: id,
        oldValue: {
          'status': brand['status'],
          'partnershipStatus': brand['partnershipStatus'],
        },
        newValue: patch,
        reason: 'Historical Gift Brand Partner workflow restored',
      ),
    );
    setState(() => _message = 'Gift Brand Partner $id marked $status.');
    await _loadAdminData();
  }

  Future<void> _editGiftBrandPartner(Map<String, dynamic>? brand) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage Gift Brand Partners.');
      return;
    }
    final existing = brand ?? const <String, dynamic>{};
    final partnerName = TextEditingController(
      text: '${existing['partnerName'] ?? existing['brandName'] ?? ''}',
    );
    final category = TextEditingController(
      text: '${existing['category'] ?? ''}',
    );
    final contactName = TextEditingController(
      text: '${existing['contactName'] ?? ''}',
    );
    final contactEmail = TextEditingController(
      text: '${existing['contactEmail'] ?? ''}',
    );
    final phone = TextEditingController(text: '${existing['phone'] ?? ''}');
    final website = TextEditingController(text: '${existing['website'] ?? ''}');
    final approvedFor = TextEditingController(
      text: _adminStringList(existing['approvedFor']).join(', '),
    );
    final notes = TextEditingController(
      text: '${existing['internalNotes'] ?? existing['brandNotes'] ?? ''}',
    );
    var status =
        '${existing['status'] ?? existing['partnershipStatus'] ?? 'pending'}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            brand == null ? 'New Brand Partner' : 'Edit Brand Partner',
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: partnerName,
                    decoration: const InputDecoration(
                      labelText: 'Brand / partner name',
                    ),
                  ),
                  TextField(
                    controller: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  TextField(
                    controller: contactName,
                    decoration: const InputDecoration(
                      labelText: 'Contact name',
                    ),
                  ),
                  TextField(
                    controller: contactEmail,
                    decoration: const InputDecoration(
                      labelText: 'Contact email',
                    ),
                  ),
                  TextField(
                    controller: phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  TextField(
                    controller: website,
                    decoration: const InputDecoration(labelText: 'Website'),
                  ),
                  TextField(
                    controller: approvedFor,
                    decoration: const InputDecoration(
                      labelText: 'Campaign / catalogue association',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items:
                        const [
                              'pending',
                              'approved',
                              'paused',
                              'suspended',
                              'inactive',
                            ]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setDialogState(() => status = value ?? status),
                  ),
                  TextField(
                    controller: notes,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Brand notes'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final patch = AdminGiftTools.brandPartnerPatch(
      status: status,
      updatedBy: _user?.email ?? _user?.uid ?? 'admin',
      updatedAt: FieldValue.serverTimestamp(),
      partnerName: partnerName.text,
      brandName: partnerName.text,
      category: category.text,
      contactName: contactName.text,
      contactEmail: contactEmail.text,
      phone: phone.text,
      website: website.text,
      notes: notes.text,
      approvedFor: _csvValues(approvedFor.text),
    );
    final name = partnerName.text.trim();
    partnerName.dispose();
    category.dispose();
    contactName.dispose();
    contactEmail.dispose();
    phone.dispose();
    website.dispose();
    approvedFor.dispose();
    notes.dispose();
    if (confirmed != true || name.isEmpty) return;
    final id = _brandId(existing).isEmpty ? _slugId(name) : _brandId(existing);
    await _db.collection('giftBrands').doc(id).set({
      'partnerId': id,
      if (brand == null) 'createdAt': FieldValue.serverTimestamp(),
      if (brand == null) 'createdBy': _user?.email ?? _user?.uid,
      ...patch,
    }, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'gift_brand_partner_saved',
        recordType: 'giftBrands',
        recordId: id,
        newValue: patch,
        reason: 'Historical Brand Partner profile saved',
      ),
    );
    setState(() => _message = 'Gift Brand Partner $id saved.');
    await _loadAdminData();
  }

  Future<void> _suggestGiftCampaignMatch(
    Map<String, dynamic> participant,
    List<Map<String, dynamic>> participants,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage gift campaigns.');
      return;
    }
    final id = _idFor(participant);
    if (id.isEmpty) return;
    Map<String, dynamic>? best;
    double bestScore = 0;
    String bestReason = '';
    for (final candidate in participants) {
      if (_idFor(candidate) == id ||
          '${candidate['matchStatus']}' != 'unmatched') {
        continue;
      }
      final result = AdminGiftTools.campaignMatchScore(participant, candidate);
      if (result.score > bestScore) {
        best = candidate;
        bestScore = result.score;
        bestReason = result.reason;
      }
    }
    if (best == null || bestScore <= 0) {
      setState(() => _message = 'No safe eligible campaign match found.');
      return;
    }
    final confirmed = await _confirmAdminAction(
      'Suggest Campaign Match',
      'Suggest ${best['displayName'] ?? best['userId'] ?? _idFor(best)} for ${participant['displayName'] ?? participant['userId'] ?? id}?',
    );
    if (!confirmed) return;
    await _db.collection('giftCampaignParticipants').doc(id).set({
      'suggestedParticipantId': _idFor(best),
      'suggestedMatchScore': bestScore,
      'suggestedMatchReason': bestReason,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _user?.email ?? _user?.uid,
    }, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'gift_campaign_match_suggested',
        recordType: 'giftCampaignParticipants',
        recordId: id,
        newValue: {'suggestedParticipantId': _idFor(best), 'score': bestScore},
        reason: bestReason,
      ),
    );
    setState(() => _message = 'Campaign match suggestion saved.');
    await _loadAdminData();
  }

  Future<void> _approveGiftCampaignMatch(
    Map<String, dynamic> participant,
    List<Map<String, dynamic>> participants,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage gift campaigns.');
      return;
    }
    final id = _idFor(participant);
    final otherId = '${participant['suggestedParticipantId'] ?? ''}'.trim();
    if (id.isEmpty || otherId.isEmpty) {
      setState(() => _message = 'Generate a campaign match suggestion first.');
      return;
    }
    Map<String, dynamic>? other;
    for (final record in participants) {
      if (_idFor(record) == otherId) {
        other = record;
        break;
      }
    }
    if (other == null) {
      setState(() => _message = 'Suggested participant was not found.');
      return;
    }
    final confirmed = await _confirmAdminAction(
      'Approve Campaign Match',
      'Approve this match and create the historical draft Gift Requests?',
    );
    if (!confirmed) return;
    final matchId = _db.collection('giftCampaignMatches').doc().id;
    final batch = _db.batch();
    final reason = '${participant['suggestedMatchReason'] ?? ''}';
    final score = participant['suggestedMatchScore'] ?? 0;
    for (final pair in [(participant, other), (other, participant)]) {
      batch.set(
        _db.collection('giftCampaignParticipants').doc(_idFor(pair.$1)),
        {
          'matchStatus': 'matched',
          'adminReviewStatus': 'approved',
          'matchedParticipantId': _idFor(pair.$2),
          'matchId': matchId,
          'matchScore': score,
          'matchReason': reason,
          'matchLockedAt': FieldValue.serverTimestamp(),
          'matchApprovedBy': _user?.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      final gift = _db.collection('giftRequests').doc();
      batch.set(gift, {
        'senderId': pair.$1['userId'],
        'senderName': pair.$1['displayName'],
        'recipientName': pair.$2['displayName'],
        'giftMode': 'anonymous_gift',
        'anonymousGiftType': 'campaign',
        'senderRevealMode': 'anonymous_until_consent',
        'senderRevealConsent': 'not_requested',
        'recipientRevealRequestStatus': 'none',
        'campaignId': participant['campaignId'],
        'campaignName': participant['campaignName'] ?? 'Bringing London Closer',
        'campaignTagline':
            participant['campaignTagline'] ??
            '100 Londoners. 100 gifts. 100 stories.',
        'campaignType': 'anonymous_gifting',
        'matchId': matchId,
        'status': 'draft',
        'budgetStatus': 'pending_allocation',
        'recipientContentConsent': 'pending',
        'senderContentConsent': 'pending',
        'allowCircumSocialUse': false,
        'allowBrandTagging': false,
        'allowReactionRecording': false,
        'allowPublicPosting': false,
        'allowAnonymousPosting': false,
        'contentUsageScope': 'private',
        'anonymousByDefault': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.set(_db.collection('giftCampaignMatches').doc(matchId), {
      'campaignId': participant['campaignId'],
      'campaignName': participant['campaignName'],
      'participantIds': [id, otherId],
      'matchScore': score,
      'matchReason': reason,
      'status': 'approved',
      'approvedBy': _user?.uid,
      'approvedByEmail': _user?.email,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'gift_campaign_match_approved',
        recordType: 'giftCampaignMatches',
        recordId: matchId,
        newValue: {
          'participantIds': [id, otherId],
          'score': score,
        },
        reason: 'Historical Campaign Matching approval restored',
      ),
    );
    setState(
      () => _message = 'Campaign match approved and draft gifts created.',
    );
    await _loadAdminData();
  }

  Future<void> _bulkGiftCampaignAction(
    List<Map<String, dynamic>> participants,
    String action,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage gift campaigns.');
      return;
    }
    final selected = participants
        .where(
          (participant) =>
              '${participant['matchStatus'] ?? 'unmatched'}' != 'matched',
        )
        .take(25)
        .toList(growable: false);
    if (selected.isEmpty) return;
    final confirmed = await _confirmAdminAction(
      'Bulk Campaign Matching',
      'Apply $action to ${selected.length} campaign participant records?',
    );
    if (!confirmed) return;
    final batch = _db.batch();
    for (final participant in selected) {
      final id = _idFor(participant);
      if (id.isEmpty) continue;
      batch.set(
        _db.collection('giftCampaignParticipants').doc(id),
        {
          if (action != 'exported') 'matchStatus': action,
          if (action != 'exported') 'adminReviewStatus': action,
          if (action == 'assign_later')
            'assignmentDeferredAt': FieldValue.serverTimestamp(),
          if (action == 'assign_later') 'assignmentDeferredBy': _user?.uid,
          if (action == 'exported')
            'lastExportedAt': FieldValue.serverTimestamp(),
          if (action == 'exported')
            'lastExportedBy': _user?.email ?? _user?.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'gift_campaign_match_bulk_$action',
        recordType: 'giftCampaignParticipants',
        recordId: 'bulk',
        newValue: {'count': selected.length, 'action': action},
        reason: 'Historical bulk Campaign Matching workflow restored',
      ),
    );
    setState(() => _message = 'Campaign matching bulk $action complete.');
    await _loadAdminData();
  }

  Future<void> _editGiftRequestWorkflow(Map<String, dynamic> gift) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot edit Gift requests.');
      return;
    }
    final id = _idFor(gift);
    if (id.isEmpty) return;
    final status = TextEditingController(
      text: '${gift['status'] ?? 'submitted'}',
    );
    final plan = TextEditingController(text: '${gift['manualGiftPlan'] ?? ''}');
    final decision = TextEditingController(
      text: '${gift['adminDecision'] ?? ''}',
    );
    final notes = TextEditingController(text: '${gift['internalNotes'] ?? ''}');
    final procurementTitle = TextEditingController(
      text: '${gift['procurementItemTitle'] ?? ''}',
    );
    final procurementSupplier = TextEditingController(
      text: '${gift['procurementSupplier'] ?? ''}',
    );
    final procurementCost = TextEditingController(
      text:
          '${gift['procurementEstimatedCost'] ?? gift['procurementActualCost'] ?? ''}',
    );
    final procurementOrder = TextEditingController(
      text: '${gift['procurementOrderReference'] ?? ''}',
    );
    final procurementEta = TextEditingController(
      text: '${gift['procurementDeliveryEta'] ?? ''}',
    );
    final procurementNotes = TextEditingController(
      text: '${gift['procurementNotes'] ?? ''}',
    );
    final irisAccepted = TextEditingController(
      text: _adminStringList(
        gift['giftsTeamWorkspace'] is Map
            ? (gift['giftsTeamWorkspace'] as Map)['irisCollaboration'] is Map
                  ? ((gift['giftsTeamWorkspace'] as Map)['irisCollaboration']
                        as Map)['acceptedSignals']
                  : gift['irisAcceptedSignals']
            : gift['irisAcceptedSignals'],
      ).join(', '),
    );
    final irisRejected = TextEditingController(
      text: _adminStringList(gift['rejectedIrisGiftSuggestionIds']).join(', '),
    );
    final storyMessage = TextEditingController(
      text: '${gift['giftStoryCircumMessage'] ?? ''}',
    );
    final storyPhotos = TextEditingController(
      text: _adminStringList(
        gift['giftStoryPhotoUrls'] ?? gift['giftStoryPhotos'],
      ).join(', '),
    );
    final storyAudio = TextEditingController(
      text: '${gift['giftStoryCustomAudioUrl'] ?? ''}',
    );
    final caption = TextEditingController(
      text: '${gift['captionDraft'] ?? ''}',
    );
    final approvedCaption = TextEditingController(
      text: '${gift['approvedCaption'] ?? ''}',
    );
    final tiktok = TextEditingController(
      text: '${gift['postedTikTokUrl'] ?? ''}',
    );
    final instagram = TextEditingController(
      text: '${gift['postedInstagramUrl'] ?? ''}',
    );
    final youtube = TextEditingController(
      text: '${gift['postedYouTubeShortsUrl'] ?? ''}',
    );
    var contentStatus = '${gift['contentStatus'] ?? 'not_started'}';
    var privacy =
        '${gift['giftStorySharePrivacy'] ?? gift['contentUsageScope'] ?? 'private'}';
    var storyEnabled = gift['giftStoryEnabled'] != false;
    var storyApproved = gift['giftStoryApproved'] == true;
    var allowSocial = gift['allowCircumSocialUse'] == true;
    var allowPublic = gift['allowPublicPosting'] == true;
    var allowBrand = gift['allowBrandTagging'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Gift Assessment · ${_giftDisplayReference(gift)}'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: status,
                    decoration: const InputDecoration(
                      labelText: 'Workflow status',
                    ),
                  ),
                  TextField(
                    controller: plan,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Recommended experience / gift plan',
                    ),
                  ),
                  TextField(
                    controller: decision,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Admin decision',
                    ),
                  ),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Internal notes',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: procurementTitle,
                    decoration: const InputDecoration(
                      labelText: 'Sourcing item',
                    ),
                  ),
                  TextField(
                    controller: procurementSupplier,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                  ),
                  TextField(
                    controller: procurementCost,
                    decoration: const InputDecoration(labelText: 'Cost'),
                  ),
                  TextField(
                    controller: procurementOrder,
                    decoration: const InputDecoration(
                      labelText: 'Order reference',
                    ),
                  ),
                  TextField(
                    controller: procurementEta,
                    decoration: const InputDecoration(labelText: 'ETA'),
                  ),
                  TextField(
                    controller: procurementNotes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Sourcing notes',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: irisAccepted,
                    decoration: const InputDecoration(
                      labelText: 'Approved item recommendations',
                    ),
                  ),
                  TextField(
                    controller: irisRejected,
                    decoration: const InputDecoration(
                      labelText: 'Rejected item recommendations',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: storyEnabled,
                    onChanged: (value) =>
                        setDialogState(() => storyEnabled = value),
                    title: const Text('Enable Gift Story'),
                  ),
                  SwitchListTile.adaptive(
                    value: storyApproved,
                    onChanged: (value) =>
                        setDialogState(() => storyApproved = value),
                    title: const Text('Story approved'),
                  ),
                  TextField(
                    controller: storyMessage,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Message from Circum',
                    ),
                  ),
                  TextField(
                    controller: storyPhotos,
                    decoration: const InputDecoration(
                      labelText: 'Story photo URLs',
                    ),
                  ),
                  TextField(
                    controller: storyAudio,
                    decoration: const InputDecoration(
                      labelText: 'Story audio URL',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: privacy,
                    decoration: const InputDecoration(labelText: 'Privacy'),
                    items:
                        const [
                              'private',
                              'unlisted',
                              'public',
                              'social_media',
                              'circum_marketing',
                            ]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setDialogState(() => privacy = value ?? privacy),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: contentStatus,
                    decoration: const InputDecoration(
                      labelText: 'Content status',
                    ),
                    items:
                        const [
                              'not_started',
                              'consent_pending',
                              'ready_to_edit',
                              'approved',
                              'posted',
                              'archived',
                            ]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) => setDialogState(
                      () => contentStatus = value ?? contentStatus,
                    ),
                  ),
                  SwitchListTile.adaptive(
                    value: allowSocial,
                    onChanged: (value) =>
                        setDialogState(() => allowSocial = value),
                    title: const Text('Allow Circum social use'),
                  ),
                  SwitchListTile.adaptive(
                    value: allowPublic,
                    onChanged: (value) =>
                        setDialogState(() => allowPublic = value),
                    title: const Text('Allow public posting'),
                  ),
                  SwitchListTile.adaptive(
                    value: allowBrand,
                    onChanged: (value) =>
                        setDialogState(() => allowBrand = value),
                    title: const Text('Allow brand tagging'),
                  ),
                  TextField(
                    controller: caption,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Caption draft',
                    ),
                  ),
                  TextField(
                    controller: approvedCaption,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Approved caption',
                    ),
                  ),
                  TextField(
                    controller: tiktok,
                    decoration: const InputDecoration(labelText: 'TikTok URL'),
                  ),
                  TextField(
                    controller: instagram,
                    decoration: const InputDecoration(
                      labelText: 'Instagram URL',
                    ),
                  ),
                  TextField(
                    controller: youtube,
                    decoration: const InputDecoration(
                      labelText: 'YouTube Shorts URL',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final collection = '${gift['_collection'] ?? 'giftRequests'}';
    final patch = <String, Object?>{
      'status': status.text.trim(),
      'manualGiftPlan': plan.text.trim(),
      'adminDecision': decision.text.trim(),
      'internalNotes': notes.text.trim(),
      'procurementItemTitle': procurementTitle.text.trim(),
      'procurementSupplier': procurementSupplier.text.trim(),
      'procurementEstimatedCost': double.tryParse(procurementCost.text.trim()),
      'procurementActualCost': double.tryParse(procurementCost.text.trim()),
      'procurementOrderReference': procurementOrder.text.trim(),
      'procurementDeliveryEta': procurementEta.text.trim(),
      'procurementNotes': procurementNotes.text.trim(),
      'giftsTeamWorkspace.irisCollaboration.acceptedSignals': _csvValues(
        irisAccepted.text,
      ),
      'rejectedIrisGiftSuggestionIds': _csvValues(irisRejected.text),
      'giftStoryEnabled': storyEnabled,
      'giftStoryApproved': storyApproved,
      'giftStoryCircumMessage': storyMessage.text.trim(),
      'giftStoryPhotoUrls': _csvValues(storyPhotos.text),
      'giftStoryPhotos': _csvValues(storyPhotos.text),
      'giftStoryCustomAudioUrl': storyAudio.text.trim().isEmpty
          ? null
          : storyAudio.text.trim(),
      'giftStorySharePrivacy': privacy,
      'contentUsageScope': privacy,
      'contentStatus': contentStatus,
      'allowCircumSocialUse': allowSocial,
      'allowPublicPosting': allowPublic,
      'allowBrandTagging': allowBrand,
      'captionDraft': caption.text.trim(),
      'approvedCaption': approvedCaption.text.trim(),
      'postedTikTokUrl': tiktok.text.trim(),
      'postedInstagramUrl': instagram.text.trim(),
      'postedYouTubeShortsUrl': youtube.text.trim(),
      'giftWorkspaceAuditTrail': FieldValue.arrayUnion([
        {
          'event': 'gift_request_editor_saved',
          'updatedBy': _user?.email ?? _user?.uid,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _user?.email ?? _user?.uid,
    };
    for (final controller in [
      status,
      plan,
      decision,
      notes,
      procurementTitle,
      procurementSupplier,
      procurementCost,
      procurementOrder,
      procurementEta,
      procurementNotes,
      irisAccepted,
      irisRejected,
      storyMessage,
      storyPhotos,
      storyAudio,
      caption,
      approvedCaption,
      tiktok,
      instagram,
      youtube,
    ]) {
      controller.dispose();
    }
    if (confirmed != true) return;
    await _db
        .collection(collection)
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'gift_request_editor_saved',
        recordType: collection,
        recordId: id,
        newValue: patch,
        reason: 'Historical Gift Request editor workflow restored',
      ),
    );
    setState(() => _message = 'Gift Request $id saved.');
    await _loadAdminData();
  }

  Future<void> _updateGiftStoryAccess(
    Map<String, dynamic> gift,
    String action,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage Gift Stories.');
      return;
    }
    final id = _idFor(gift);
    if (id.isEmpty) return;
    try {
      if (action == 'retry' || action == 'regenerate') {
        await FirebaseFunctions.instanceFor(
          region: 'us-central1',
        ).httpsCallable('retryGiftStoryAutomation').call({
          'giftRequestId': id,
          if (action == 'regenerate') 'regenerateToken': true,
        });
      } else {
        await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('manageGiftStoryAccess')
            .call({'giftRequestId': id, 'action': action});
      }
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'gift_story_$action',
          recordType: '${gift['_collection'] ?? 'giftRequests'}',
          recordId: id,
          newValue: {'action': action},
          reason:
              'Gift Story action submitted through existing backend callable',
        ),
      );
      setState(() => _message = 'Gift Story $action submitted.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Gift Story action failed.');
    }
  }

  Future<void> _updateIrisRepositoryRecord(
    Map<String, dynamic> record,
    String action,
  ) async {
    if (!_can(AdminPermission.editDeliveries)) {
      setState(() => _message = 'Your role cannot govern IRIS records.');
      return;
    }
    final id = _idFor(record);
    final collection = '${record['_collection'] ?? 'irisCanonicalObjects'}';
    if (id.isEmpty) return;
    if (action == 'edited' || action == 'duplicate_review') {
      final patch = await _irisRepositoryEditPatch(
        record,
        duplicate: action == 'duplicate_review',
      );
      if (patch == null) return;
      final targetId = action == 'duplicate_review'
          ? _slugId(
              '${patch['canonicalName'] ?? patch['objectName'] ?? id}-copy',
            )
          : id;
      await _db.collection(collection).doc(targetId).set({
        ...patch,
        'adminRepositoryAction': action,
        'repositoryReviewStatus': action,
        if (action == 'duplicate_review') 'duplicatedFrom': id,
        if (action == 'duplicate_review')
          'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _user?.email ?? _user?.uid,
      }, SetOptions(merge: true));
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'iris_repository_$action',
          recordType: collection,
          recordId: targetId,
          oldValue: record,
          newValue: patch,
          reason: 'Historical IRIS canonical editor restored',
        ),
      );
      setState(() => _message = 'IRIS repository record $targetId saved.');
      await _loadAdminData();
      return;
    }
    final patch = <String, Object?>{
      'adminRepositoryAction': action,
      'repositoryReviewStatus': action,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _user?.email ?? _user?.uid,
      if (action == 'deactivated') 'status': 'deactivated',
      if (action == 'activated') 'status': 'active',
      if (action == 'bulk_exported')
        'lastExportedAt': FieldValue.serverTimestamp(),
    };
    await _db
        .collection(collection)
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'iris_repository_$action',
        recordType: collection,
        recordId: id,
        oldValue: {
          'status': record['status'],
          'repositoryReviewStatus': record['repositoryReviewStatus'],
        },
        newValue: patch,
        reason: 'Historical IRIS repository governance action restored',
      ),
    );
    setState(() => _message = 'IRIS repository record $id marked $action.');
    await _loadAdminData();
  }

  Future<void> _updateIrisCandidateWorkflow(
    Map<String, dynamic> record,
    String action,
  ) async {
    if (!_can(AdminPermission.editDeliveries)) {
      setState(() => _message = 'Your role cannot review IRIS candidates.');
      return;
    }
    final id = _idFor(record);
    final collection = '${record['_collection'] ?? 'irisLearningCases'}';
    if (id.isEmpty) return;
    if (action == 'promoted') {
      final canonicalId = _slugId(
        '${record['canonicalName'] ?? record['objectName'] ?? record['enteredText'] ?? record['category'] ?? id}',
      );
      if (canonicalId.isEmpty) return;
      final batch = _db.batch();
      batch.set(
        _db.collection('irisCanonicalObjects').doc(canonicalId),
        {
          'canonicalId': canonicalId,
          'objectName':
              record['objectName'] ??
              record['enteredText'] ??
              record['category'] ??
              id,
          'canonicalName':
              record['canonicalName'] ??
              record['enteredText'] ??
              record['objectName'] ??
              id,
          'category': record['category'] ?? record['irisCategory'],
          'subcategory': record['subcategory'],
          'knownWeight':
              record['knownWeight'] ??
              record['estimatedWeight'] ??
              record['irisEstimatedWeight'],
          'weightBand': record['weightBand'],
          'vehicleRecommendation':
              record['vehicleRecommendation'] ?? record['recommendedVehicle'],
          'handlingRequirements':
              record['handlingRequirements'] ?? record['handlingNotes'],
          'sourceCandidateId': id,
          'status': 'active',
          'repositoryReviewStatus': 'promoted',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _user?.email ?? _user?.uid,
        },
        SetOptions(merge: true),
      );
      batch.set(_db.collection(collection).doc(id), {
        'learningStatus': 'promoted',
        'reviewStatus': 'promoted',
        'repositoryPromotionStatus': 'committed',
        'promotedCanonicalId': canonicalId,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': _user?.email ?? _user?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'iris_candidate_promoted',
          recordType: collection,
          recordId: id,
          newValue: {'promotedCanonicalId': canonicalId},
          reason:
              'Historical Candidate to Canonical Repository transition restored',
        ),
      );
      setState(() => _message = 'IRIS candidate promoted to $canonicalId.');
      await _loadAdminData();
      return;
    }
    final patch = <String, Object?>{
      'learningStatus': action,
      'reviewStatus': action,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': _user?.email ?? _user?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      if (action == 'promoted') 'repositoryPromotionStatus': 'pending_commit',
      if (action == 'merge_existing') 'repositoryMergeStatus': 'pending',
      if (action == 'save_alias') 'aliasReviewStatus': 'pending',
      if (action == 'suspicious') 'riskReviewStatus': 'suspicious',
      if (action == 'rejected') 'rejectedAt': FieldValue.serverTimestamp(),
      if (action == 'approved') 'approvedAt': FieldValue.serverTimestamp(),
    };
    await _db
        .collection(collection)
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'iris_candidate_$action',
        recordType: collection,
        recordId: id,
        oldValue: {
          'learningStatus': record['learningStatus'],
          'reviewStatus': record['reviewStatus'],
        },
        newValue: patch,
        reason: 'Historical IRIS candidate workflow restored',
      ),
    );
    setState(() => _message = 'IRIS candidate $id marked $action.');
    await _loadAdminData();
  }

  Future<void> _updateGiftWorkspace(
    Map<String, dynamic> gift,
    String action,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage gift operations.');
      return;
    }
    final id = _idFor(gift);
    if (id.isEmpty) return;
    final collection = '${gift['_collection'] ?? 'giftRequests'}';
    final patch = <String, Object?>{
      'giftsTeamWorkspace.status': action,
      'giftsTeamWorkspace.updatedAt': FieldValue.serverTimestamp(),
      'giftsTeamWorkspace.updatedBy': _user?.email ?? _user?.uid,
      'giftWorkspaceAuditTrail': FieldValue.arrayUnion([
        {
          'event': action,
          'updatedBy': _user?.email ?? _user?.uid,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      ]),
      if (action == 'ready_for_procurement')
        'giftsTeamWorkspace.readiness.readyForProcurement': true,
      if (action == 'ready_for_rider')
        'giftsTeamWorkspace.readiness.readyForRider': true,
      if (action == 'ready_for_scheduling')
        'giftsTeamWorkspace.readiness.readyForScheduling': true,
      if (action == 'ready_for_delivery')
        'giftsTeamWorkspace.readiness.readyForDelivery': true,
    };
    await _db
        .collection(collection)
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'gift_workspace_$action',
        recordType: collection,
        recordId: id,
        newValue: {'workspaceStatus': action},
        reason: 'Historical Gift Team workspace action restored',
      ),
    );
    setState(
      () => _message =
          '${_giftDisplayReference(gift)} moved to ${action.replaceAll('_', ' ')}.',
    );
    await _loadAdminData();
  }

  Future<void> _updateGiftStoryMedia(
    Map<String, dynamic> gift,
    String action,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage Gift Story media.');
      return;
    }
    final id = _idFor(gift);
    if (id.isEmpty) return;
    try {
      if (action == 'download_video') {
        await _functions.httpsCallable('getGiftStoryVideoDownload').call({
          'giftRequestId': id,
        });
      } else if (action == 'create_video_upload') {
        await _functions.httpsCallable('createGiftStoryVideoUpload').call({
          'giftRequestId': id,
          'contentType': 'video/mp4',
        });
      } else if (action == 'finalize_video_upload') {
        await _functions.httpsCallable('finalizeGiftStoryVideoUpload').call({
          'giftRequestId': id,
          'storagePath':
              '${gift['giftStoryVideoStoragePath'] ?? gift['videoStoragePath'] ?? ''}',
        });
      } else if (action == 'record_preview_event') {
        await _functions.httpsCallable('recordGiftStoryEvent').call({
          'giftRequestId': id,
          'eventType': 'admin_preview',
        });
      } else if (action == 'update_privacy') {
        await _functions.httpsCallable('updateGiftStoryPrivacy').call({
          'giftRequestId': id,
          'privacy':
              gift['giftStorySharePrivacy'] ??
              gift['contentUsageScope'] ??
              'private',
        });
      } else {
        await _updateGiftStoryAccess(gift, action);
        return;
      }
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'gift_story_media_$action',
          recordType: '${gift['_collection'] ?? 'giftRequests'}',
          recordId: id,
          newValue: {'action': action},
          reason: 'Historical Gift Story media workflow restored',
        ),
      );
      setState(() => _message = 'Gift Story media $action submitted.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message = error.message ?? 'Gift Story media action failed.',
      );
    }
  }

  Future<void> _updatePlatformRecord(
    Map<String, dynamic> record,
    String status,
  ) async {
    if (!_can(AdminPermission.manageAdmins)) {
      setState(() => _message = 'Your role cannot manage platform settings.');
      return;
    }
    final id = _idFor(record);
    final collection = '${record['_collection'] ?? ''}'.trim();
    if (id.isEmpty || collection.isEmpty) return;
    try {
      final patch = AdminPlatformTools.operationPatch(
        status: status,
        updatedBy: _user?.email ?? _user?.uid ?? 'admin',
        updatedAt: FieldValue.serverTimestamp(),
        reason: 'Platform operation confirmed from Admin',
      );
      await _db
          .collection(collection)
          .doc(id)
          .set(patch, SetOptions(merge: true));
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'platform_operation_$status',
          recordType: collection,
          recordId: id,
          oldValue: {
            'status': record['status'],
            'adminOperationStatus': record['adminOperationStatus'],
          },
          newValue: patch,
          reason: 'Platform operation updated from Admin',
        ),
      );
      setState(() => _message = 'Platform record $id updated to $status.');
      await _loadAdminData();
    } on ArgumentError catch (error) {
      setState(() => _message = error.message);
    }
  }

  Future<void> _sendPlatformAnnouncement(String audience) async {
    if (!_can(AdminPermission.manageAdmins)) {
      setState(
        () => _message = 'Your role cannot send platform announcements.',
      );
      return;
    }
    final title = _announcementTitle.text.trim();
    final body = _announcementBody.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _message = 'Announcement title and message are required.');
      return;
    }
    try {
      await _functions.httpsCallable('sendCircumAnnouncement').call({
        'title': title,
        'body': body,
        'audience': audience,
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'platform_announcement_sent',
          recordType: 'platformNotices',
          recordId: audience,
          newValue: {'title': title, 'audience': audience},
          reason: 'Historical announcement workflow restored',
        ),
      );
      _announcementTitle.clear();
      _announcementBody.clear();
      setState(() => _message = 'Announcement queued for $audience.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Announcement failed.');
    }
  }

  Future<void> _retryNotificationDelivery(
    Map<String, dynamic> notification,
  ) async {
    if (!_can(AdminPermission.manageAdmins)) {
      setState(() => _message = 'Your role cannot retry notifications.');
      return;
    }
    final id = _idFor(notification);
    if (id.isEmpty) return;
    try {
      await _functions.httpsCallable('retryNotificationDelivery').call({
        'notificationId': id,
      });
      setState(() => _message = 'Notification retry sent for $id.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Notification retry failed.');
    }
  }

  Future<void> _updateHealthPlusPickup(
    Map<String, dynamic> pickup,
    String status,
  ) async {
    if (!_can(AdminPermission.manageHealthPlus)) {
      setState(() => _message = 'Your role cannot manage Health+ pickups.');
      return;
    }
    final id = _idFor(pickup);
    if (id.isEmpty) return;
    final patch = AdminHealthPlusTools.statusPatch(
      status: status,
      updatedBy: _user?.email ?? _user?.uid ?? 'admin',
      reason: 'Updated from Circum Admin Health+ Operations',
      updatedAt: FieldValue.serverTimestamp(),
    );
    await _db
        .collection('prescriptionPickups')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _db.collection('healthPlusUsageEvents').add({
      'type': 'admin_status_updated',
      'pickupId': id,
      'status': status,
      'source': 'circum-admin',
      'adminUserId': _user?.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'health_plus_status_update',
        recordType: 'prescriptionPickups',
        recordId: id,
        oldValue: {'status': pickup['status']},
        newValue: {'status': status},
        reason: 'Health+ pickup updated from Admin',
      ),
    );
    setState(() => _message = 'Health+ pickup $id updated to $status.');
    await _loadAdminData();
  }

  Future<void> _updateHealthPlusSchedule(
    Map<String, dynamic> schedule,
    String status,
  ) async {
    if (!_can(AdminPermission.manageHealthPlus)) {
      setState(() => _message = 'Your role cannot manage Health+ schedules.');
      return;
    }
    final id = _idFor(schedule);
    if (id.isEmpty) return;
    await _db.collection('recurringPickupSchedules').doc(id).set({
      'status': status,
      'adminReviewStatus': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'adminUpdatedBy': _user?.email ?? _user?.uid,
      'adminReason': 'Health+ recurring schedule reviewed from Admin',
    }, SetOptions(merge: true));
    await _db.collection('healthPlusCustodyArchive').add({
      'scheduleId': id,
      'profileId': schedule['profileId'],
      'userId': schedule['userId'] ?? schedule['senderId'],
      'eventType': 'schedule_$status',
      'timestamp': FieldValue.serverTimestamp(),
      'actorType': 'admin',
      'actorId': _user?.uid,
      'actorName': _user?.displayName ?? _user?.email,
      'publicMessage': 'Your Health+ recurring schedule has been reviewed.',
      'internalNote': 'Schedule $status from isolated Circum Admin.',
      'statusAfterEvent': status,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'health_plus_schedule_$status',
        recordType: 'recurringPickupSchedules',
        recordId: id,
        oldValue: {'status': schedule['status']},
        newValue: {'status': status},
        reason: 'Health+ recurring schedule reviewed from Admin',
      ),
    );
    setState(() => _message = 'Health+ schedule $id updated.');
    await _loadAdminData();
  }

  Future<void> _updateHealthPlusProfile(
    Map<String, dynamic> profile,
    String status,
  ) async {
    if (!_can(AdminPermission.manageHealthPlus)) {
      setState(() => _message = 'Your role cannot manage Health+ profiles.');
      return;
    }
    final id = _idFor(profile);
    if (id.isEmpty) return;
    await _db.collection('healthPlusProfiles').doc(id).set({
      'status': status,
      'adminReviewStatus': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'adminUpdatedBy': _user?.email ?? _user?.uid,
      'adminReason': 'Health+ profile reviewed from Admin',
    }, SetOptions(merge: true));
    await _db.collection('healthPlusCustodyArchive').add({
      'profileId': id,
      'userId': profile['userId'] ?? profile['senderId'],
      'eventType': 'profile_$status',
      'timestamp': FieldValue.serverTimestamp(),
      'actorType': 'admin',
      'actorId': _user?.uid,
      'actorName': _user?.displayName ?? _user?.email,
      'internalNote': 'Profile $status from isolated Circum Admin.',
      'statusAfterEvent': status,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'health_plus_profile_$status',
        recordType: 'healthPlusProfiles',
        recordId: id,
        oldValue: {'status': profile['status']},
        newValue: {'status': status},
        reason: 'Health+ profile reviewed from Admin',
      ),
    );
    setState(() => _message = 'Health+ profile $id updated.');
    await _loadAdminData();
  }

  Future<void> _updateFinanceWorkflow(
    Map<String, dynamic> financeRecord,
    String status,
  ) async {
    if (!_can(AdminPermission.manageFinance)) {
      setState(() => _message = 'Your role cannot manage finance workflows.');
      return;
    }
    final id = _idFor(financeRecord);
    if (id.isEmpty) return;
    final patch = AdminFinanceTools.workflowPatch(
      status: status,
      updatedBy: _user?.email ?? _user?.uid ?? 'admin',
      updatedAt: FieldValue.serverTimestamp(),
    );
    await _db
        .collection('payments')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'finance_workflow_$status',
        recordType: 'payments',
        recordId: id,
        oldValue: {
          'financeReviewStatus': financeRecord['financeReviewStatus'],
          'status': financeRecord['status'],
        },
        newValue: patch,
        reason: 'Finance workflow updated from Admin',
      ),
    );
    setState(() => _message = 'Finance record $id marked $status.');
    await _loadAdminData();
  }

  Future<void> _issueRothFromAdminRecord(Map<String, dynamic> record) async {
    if (!_can(AdminPermission.manageFinance)) {
      setState(() => _message = 'Your role cannot issue Roth.');
      return;
    }
    final recipient =
        '${record['userId'] ?? record['uid'] ?? record['email'] ?? record['riderId'] ?? record['senderId'] ?? ''}'
            .trim();
    final amount = _numberFrom(
      record['amount'] ?? record['rothAmount'] ?? record['balance'],
    );
    if (recipient.isEmpty || amount <= 0) {
      setState(() => _message = 'Roth issue needs a recipient and amount.');
      return;
    }
    try {
      final idempotencyKey =
          'admin_${_user?.uid ?? _user?.email}_${_idFor(record)}_${DateTime.now().microsecondsSinceEpoch}';
      await _functions.httpsCallable('issueRothToWallets').call({
        recipient.contains('@') ? 'recipientEmail' : 'recipientUid': recipient,
        'walletTarget':
            '${record['walletType'] ?? record['walletTarget'] ?? 'sender'}',
        'amount': amount,
        'reason': 'Historical Admin Roth issue restored in isolated Admin',
        'idempotencyKey': idempotencyKey,
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'admin_roth_issue_requested',
          recordType: '${record['_collection'] ?? 'wallets'}',
          recordId: _idFor(record),
          newValue: {'recipient': recipient, 'amount': amount},
          reason: 'Roth issued through backend callable',
        ),
      );
      setState(() => _message = 'Roth issue submitted for $recipient.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Roth issue failed.');
    }
  }

  Future<void> _setWalletFrozenFromAdminRecord(
    Map<String, dynamic> record,
    bool frozen,
  ) async {
    if (!_can(AdminPermission.manageFinance)) {
      setState(() => _message = 'Your role cannot freeze wallets.');
      return;
    }
    final userId =
        '${record['userId'] ?? record['uid'] ?? record['riderId'] ?? record['senderId'] ?? record['email'] ?? ''}'
            .trim();
    if (userId.isEmpty) {
      setState(() => _message = 'Wallet freeze needs a user id or email.');
      return;
    }
    try {
      await _functions.httpsCallable('setWalletFrozen').call({
        'userId': userId,
        'isFrozen': frozen,
        'reason': frozen
            ? 'Admin wallet freeze restored in isolated Admin'
            : 'Admin wallet unfreeze restored in isolated Admin',
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: frozen ? 'wallet_frozen' : 'wallet_unfrozen',
          recordType: '${record['_collection'] ?? 'wallets'}',
          recordId: _idFor(record),
          oldValue: {'isFrozen': record['isFrozen'] ?? record['frozen']},
          newValue: {'isFrozen': frozen, 'userId': userId},
          reason: 'Wallet freeze status updated through backend callable',
        ),
      );
      setState(() => _message = frozen ? 'Wallet frozen.' : 'Wallet unfrozen.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message = error.message ?? 'Wallet freeze action failed.',
      );
    }
  }

  Future<void> _processPayoutRequestFromAdmin(
    Map<String, dynamic> record,
    String nextStatus,
  ) async {
    if (!_can(AdminPermission.manageFinance)) {
      setState(() => _message = 'Your role cannot process payouts.');
      return;
    }
    final requestId = _idFor(record);
    final riderId = '${record['riderId'] ?? record['driverId'] ?? ''}'.trim();
    final amount = _numberFrom(record['amount'] ?? record['pendingAmount']);
    if (requestId.isEmpty || riderId.isEmpty || amount <= 0) {
      setState(
        () => _message = 'Payout action needs request, rider and amount.',
      );
      return;
    }
    try {
      if (nextStatus == 'approved') {
        await FirebaseFunctions.instanceFor(
          region: 'us-central1',
        ).httpsCallable('createRiderTransferOrPayout').call({
          'requestId': requestId,
          'riderId': riderId,
          'amount': amount,
        });
      } else {
        await FirebaseFunctions.instanceFor(
          region: 'us-central1',
        ).httpsCallable('adminReviewRiderWithdrawal').call({
          'requestId': requestId,
          'riderId': riderId,
          'action': 'rejected',
          'reason': 'Rider payout rejected from Admin finance review',
        });
      }
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: nextStatus == 'approved'
              ? 'rider_stripe_payout_started'
              : 'rider_withdrawal_rejected',
          recordType: 'payoutRequests',
          recordId: requestId,
          newValue: {
            'riderId': riderId,
            'amount': amount,
            'status': nextStatus,
          },
          reason: 'Rider payout processed from Admin',
        ),
      );
      setState(() => _message = 'Payout $requestId marked $nextStatus.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Payout action failed.');
    }
  }

  Future<void> _moderateRating(
    Map<String, dynamic> rating,
    String action,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot moderate ratings.');
      return;
    }
    try {
      final ratingId = _idFor(rating);
      final request = AdminRatingsTipsPolicy.moderationRequest(
        ratingId: ratingId,
        action: action,
        reason: 'Rating moderation action confirmed from Admin',
      );
      await _functions.httpsCallable('reportRating').call(request);
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'rating_moderation_$action',
          recordType: 'driverRatings',
          recordId: ratingId,
          oldValue: {'reportStatus': rating['reportStatus']},
          newValue: request,
          reason: 'Rating moderation updated from Admin',
        ),
      );
      setState(() => _message = 'Rating $ratingId moderation saved.');
      await _loadAdminData();
    } on ArgumentError catch (error) {
      setState(() => _message = error.message);
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Rating moderation failed.');
    }
  }

  Future<void> _saveAdminUser({
    Map<String, dynamic>? existing,
    String? email,
    AdminRole? role,
    String status = 'active',
  }) async {
    if (!_can(AdminPermission.manageAdmins)) {
      setState(() => _message = 'Your role cannot manage Admin users.');
      return;
    }
    final normalizedEmail = AdminUserAccess.emailDocumentId(
      email ?? '${existing?['email'] ?? ''}',
    );
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      setState(() => _message = 'Enter a valid Admin email address.');
      return;
    }
    final selectedRole =
        role ??
        AdminRole.fromString('${existing?['role'] ?? ''}') ??
        AdminRole.operationsAdmin;
    final documentId = '${existing?['id'] ?? normalizedEmail}'.trim();
    final createdAt = existing == null ? FieldValue.serverTimestamp() : null;
    final patch = AdminUserAccess.adminUserPatch(
      email: normalizedEmail,
      role: selectedRole.value,
      status: status,
      invitedBy: _user?.email ?? _user?.uid ?? 'admin',
      createdAt: createdAt,
      updatedAt: FieldValue.serverTimestamp(),
      lastLoginAt: existing?['lastLoginAt'],
    );
    final note = _adminInviteNote.text.trim();
    await _db.collection('adminUsers').doc(documentId).set({
      ...patch,
      if (note.isNotEmpty) 'adminNote': note,
    }, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: existing == null ? 'admin_user_invite' : 'admin_user_edit',
        recordType: 'adminUsers',
        recordId: documentId,
        oldValue: existing == null
            ? const {}
            : {
                'email': existing['email'],
                'role': existing['role'],
                'status': existing['status'],
              },
        newValue: {
          'email': normalizedEmail,
          'role': selectedRole.value,
          'status': status,
        },
        reason: existing == null
            ? 'Admin access invitation created'
            : 'Admin access record updated',
      ),
    );
    if (existing == null) {
      _adminInviteEmail.clear();
      _adminInviteNote.clear();
      setState(() => _adminInviteRole = AdminRole.operationsAdmin);
    }
    setState(() => _message = 'Admin access saved for $normalizedEmail.');
    await _loadAdminData();
  }

  Future<void> _setAdminUserStatus(
    Map<String, dynamic> adminUser,
    String status,
  ) async {
    await _saveAdminUser(existing: adminUser, status: status);
  }

  Future<void> _setAdminUserRole(
    Map<String, dynamic> adminUser,
    AdminRole role,
  ) async {
    await _saveAdminUser(existing: adminUser, role: role);
  }

  Future<void> _sendChatMessage() async {
    final chat = _selectedChat;
    final chatId = chat == null ? '' : _recordId(chat).trim();
    final message = _chatMessage.text.trim();
    if (chatId.isEmpty) {
      setState(() => _message = 'Select a chat thread first.');
      return;
    }
    if (message.isEmpty) {
      setState(() => _message = 'Enter a message before sending.');
      return;
    }
    try {
      await _functions.httpsCallable('sendCircumMessage').call({
        'chatId': chatId,
        'message': message,
        'messageType': 'text',
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'admin_chat_message',
          recordType: 'chats',
          recordId: chatId,
          newValue: {'chatId': chatId, 'messageLength': message.length},
          reason: 'Admin replied to chat thread',
        ),
      );
      _chatMessage.clear();
      setState(() => _message = 'Message sent to $chatId.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = _functionsMessage(error));
    } catch (_) {
      setState(() => _message = 'Could not send this message.');
    }
  }

  void _selectChat(Map<String, dynamic> chat) {
    final chatId = _recordId(chat).trim();
    _chatMessagesSub?.cancel();
    setState(() {
      _selectedChat = chat;
      _selectedChatMessages = const [];
      _module = AdminModule.chat;
    });
    if (chatId.isEmpty) return;
    _chatMessagesSub = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt')
        .limit(150)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              _selectedChatMessages = snapshot.docs
                  .map((doc) => {'id': doc.id, ...doc.data()})
                  .toList(growable: false);
            });
          },
          onError: (_) {
            if (mounted) {
              setState(() => _message = 'Could not load conversation history.');
            }
          },
        );
  }

  Future<void> _openSupportConversation(Map<String, dynamic> ticket) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot open support conversations.');
      return;
    }
    final ticketId = _recordId(ticket).trim();
    if (ticketId.isEmpty) return;
    try {
      final result = await _functions
          .httpsCallable('getOrCreateSupportConversation')
          .call({
            'ticketId': ticketId,
            'userId':
                ticket['userId'] ?? ticket['senderId'] ?? ticket['riderId'],
            'deliveryId': ticket['deliveryId'] ?? ticket['requestId'],
          });
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      final chatId =
          '${data['chatId'] ?? data['conversationId'] ?? ticket['chatId'] ?? ticket['conversationId'] ?? ''}'
              .trim();
      if (chatId.isEmpty) {
        setState(() => _message = 'Support conversation was not returned.');
        return;
      }
      _selectChat({
        'id': chatId,
        'threadId': chatId,
        'type': 'support',
        'ticketId': ticketId,
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'support_conversation_opened',
          recordType: 'supportTickets',
          recordId: ticketId,
          newValue: {'chatId': chatId},
          reason: 'Support ticket chat opened from Admin',
        ),
      );
      setState(() => _message = 'Support conversation opened.');
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = _functionsMessage(error));
    } catch (_) {
      setState(() => _message = 'Could not open support conversation.');
    }
  }

  Future<void> _startRiderConversation(Map<String, dynamic> rider) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot message riders.');
      return;
    }
    final riderId = _riderId(rider);
    if (riderId.isEmpty) return;
    try {
      final result = await _functions
          .httpsCallable('startAdminConversation')
          .call({
            'participantId': riderId,
            'participantRole': 'rider',
            'riderId': riderId,
          });
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      final chatId =
          '${data['chatId'] ?? data['conversationId'] ?? data['id'] ?? ''}'
              .trim();
      if (chatId.isEmpty) {
        setState(() => _message = 'Rider conversation was not returned.');
        return;
      }
      _selectChat({
        'id': chatId,
        'threadId': chatId,
        'type': 'admin_rider',
        'riderId': riderId,
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'admin_rider_conversation_opened',
          recordType: 'riderProfiles',
          recordId: riderId,
          newValue: {'chatId': chatId},
          reason: 'Admin to Rider conversation opened',
        ),
      );
      setState(() => _message = 'Rider conversation opened.');
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = _functionsMessage(error));
    } catch (_) {
      setState(() => _message = 'Could not open Rider conversation.');
    }
  }

  Future<void> _addAdminNote(
    Map<String, dynamic> record,
    String recordType,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot add Admin notes.');
      return;
    }
    final recordId = _recordId(record).trim();
    if (recordId.isEmpty) return;
    final note = TextEditingController();
    var pinned = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Internal Admin Note'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: note,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: pinned,
                onChanged: (value) => setDialogState(() => pinned = value),
                title: const Text('Pin note'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save note'),
            ),
          ],
        ),
      ),
    );
    final body = note.text.trim();
    note.dispose();
    if (confirmed != true || body.isEmpty) return;
    await _db.collection('adminNotes').add({
      'recordType': recordType,
      'recordId': recordId,
      'body': body,
      'note': body,
      'pinned': pinned,
      'operatorId': _user?.uid,
      'operatorEmail': _user?.email,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'admin_note_added',
        recordType: recordType,
        recordId: recordId,
        newValue: {'pinned': pinned},
        reason: 'Internal Admin note added',
      ),
    );
    setState(() => _message = 'Admin note added.');
    await _loadAdminData();
  }

  Future<bool> _confirmAdminAction(String title, String body) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<Map<String, Object?>?> _irisRepositoryEditPatch(
    Map<String, dynamic> record, {
    required bool duplicate,
  }) async {
    final objectName = TextEditingController(
      text: '${record['objectName'] ?? record['canonicalName'] ?? ''}',
    );
    final category = TextEditingController(text: '${record['category'] ?? ''}');
    final subcategory = TextEditingController(
      text: '${record['subcategory'] ?? ''}',
    );
    final weight = TextEditingController(
      text: '${record['knownWeight'] ?? record['weightBand'] ?? ''}',
    );
    final vehicle = TextEditingController(
      text:
          '${record['vehicleRecommendation'] ?? record['recommendedVehicle'] ?? ''}',
    );
    final handling = TextEditingController(
      text:
          '${record['handlingRequirements'] ?? record['handlingNotes'] ?? ''}',
    );
    final aliases = TextEditingController(
      text: _adminStringList(record['aliases']).join(', '),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          duplicate ? 'Duplicate Canonical Item' : 'Edit Canonical Item',
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: objectName,
                  decoration: const InputDecoration(
                    labelText: 'Canonical item',
                  ),
                ),
                TextField(
                  controller: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                TextField(
                  controller: subcategory,
                  decoration: const InputDecoration(labelText: 'Subcategory'),
                ),
                TextField(
                  controller: weight,
                  decoration: const InputDecoration(labelText: 'Weight / band'),
                ),
                TextField(
                  controller: vehicle,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle recommendation',
                  ),
                ),
                TextField(
                  controller: handling,
                  decoration: const InputDecoration(
                    labelText: 'Handling requirements',
                  ),
                ),
                TextField(
                  controller: aliases,
                  decoration: const InputDecoration(labelText: 'Aliases'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final patch = <String, Object?>{
      'objectName': objectName.text.trim(),
      'canonicalName': objectName.text.trim(),
      'category': category.text.trim(),
      'subcategory': subcategory.text.trim(),
      'knownWeight': weight.text.trim(),
      'weightBand': weight.text.trim(),
      'vehicleRecommendation': vehicle.text.trim(),
      'handlingRequirements': handling.text.trim(),
      'aliases': _csvValues(aliases.text),
    };
    objectName.dispose();
    category.dispose();
    subcategory.dispose();
    weight.dispose();
    vehicle.dispose();
    handling.dispose();
    aliases.dispose();
    return confirmed == true ? patch : null;
  }

  Future<void> _updateSenderTrust(
    Map<String, dynamic> account,
    String action,
  ) async {
    if (!_can(AdminPermission.editCustomers)) {
      setState(() => _message = 'Your role cannot update sender trust.');
      return;
    }
    final senderId = _recordId(account).trim();
    if (senderId.isEmpty) return;
    final points = TextEditingController();
    final reason = TextEditingController();
    var selectedTier = _canonicalSenderTrustTier(
      account['senderTier'] ?? account['trustTier'],
    );
    final needsPoints = action == 'award' || action == 'deduct';
    final needsTier = action == 'promote' || action == 'demote';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Sender trust: $action'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (needsPoints)
                TextField(
                  controller: points,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Trust points',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (needsTier)
                DropdownButtonFormField<String>(
                  initialValue: selectedTier,
                  decoration: const InputDecoration(
                    labelText: 'Trust tier',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'new_sender',
                      child: Text('New Sender'),
                    ),
                    DropdownMenuItem(
                      value: 'active_sender',
                      child: Text('Active Sender'),
                    ),
                    DropdownMenuItem(
                      value: 'regular_sender',
                      child: Text('Regular Sender'),
                    ),
                    DropdownMenuItem(
                      value: 'priority_sender',
                      child: Text('Priority Sender'),
                    ),
                    DropdownMenuItem(
                      value: 'platinum_sender',
                      child: Text('Platinum Sender'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => selectedTier = value ?? selectedTier,
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    final reasonText = reason.text.trim();
    final pointDelta = needsPoints
        ? (int.tryParse(points.text.trim()) ?? 0).abs()
        : 0;
    points.dispose();
    reason.dispose();
    if (confirmed != true) return;
    if (needsPoints && pointDelta == 0) {
      setState(() => _message = 'Enter a non-zero trust point amount.');
      return;
    }
    try {
      final result = await _functions
          .httpsCallable('adminUpdateSenderTrust')
          .call({
            'senderId': senderId,
            'action': action,
            if (needsPoints) 'points': pointDelta,
            if (needsTier) 'tier': selectedTier,
            'reason': reasonText,
          });
      final data = Map<String, dynamic>.from(result.data as Map);
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'sender_trust_$action',
          recordType: 'users',
          recordId: senderId,
          newValue: {
            'action': action,
            'pointsDelta': data['pointsChange'] ?? 0,
            'nextTier': data['nextTier'],
            'eventId': data['eventId'],
          },
          reason: reasonText,
        ),
      );
      setState(() => _message = 'Sender trust $action applied.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = _functionsMessage(error));
    }
  }

  Future<void> _resolveMessageReport(
    Map<String, dynamic> report,
    String status,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot resolve message reports.');
      return;
    }
    final id = _idFor(report);
    if (id.isEmpty) return;
    await _db.collection('messageReports').doc(id).set({
      'status': status,
      'reviewStatus': status,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': _user?.uid ?? _user?.email,
      'adminResolution': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _writeAudit(
      AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'message_report_$status',
        recordType: 'messageReports',
        recordId: id,
        oldValue: {'status': report['status']},
        newValue: {'status': status},
        reason: 'Message report reviewed from Admin',
      ),
    );
    setState(() => _message = 'Message report $id marked $status.');
    await _loadAdminData();
  }

  void _openRiderProfile(Map<String, dynamic> rider) {
    setState(() {
      _selectedRider = rider;
      _selectedDelivery = null;
      _selectedHealthPlus = null;
      _selectedAccount = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  void _openAccountProfile(Map<String, dynamic> account, String type) {
    setState(() {
      _selectedAccount = account;
      _selectedAccountType = type;
      _selectedRider = null;
      _selectedDelivery = null;
      _selectedHealthPlus = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  void _openDeliveryProfile(Map<String, dynamic> delivery) {
    setState(() {
      _selectedDelivery = delivery;
      _selectedRider = null;
      _selectedHealthPlus = null;
      _selectedAccount = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  void _openHealthPlusProfile(Map<String, dynamic> record) {
    setState(() {
      _selectedHealthPlus = record;
      _selectedDelivery = null;
      _selectedRider = null;
      _selectedAccount = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  bool _can(AdminPermission permission) {
    return AdminAccessPolicy.can(_roles, permission);
  }

  String _authMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'user-not-found' => 'No employee account found for that email.',
      'wrong-password' ||
      'invalid-credential' => 'Those sign-in details are not right.',
      _ => 'Admin sign in failed. Please check the details.',
    };
  }

  String _functionsMessage(FirebaseFunctionsException error) {
    return switch (error.code) {
      'unauthenticated' => 'Sign in again before sending messages.',
      'permission-denied' => 'Your Admin role cannot send to this chat.',
      'not-found' => 'This chat thread is no longer available.',
      'failed-precondition' => 'This chat thread is not available for replies.',
      'invalid-argument' => error.message ?? 'Check the message and try again.',
      _ => 'Could not send this message.',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_user == null || !AdminAccessPolicy.hasAnyAdminRole(_roles)) {
      return _AdminLoginView(
        email: _email,
        password: _password,
        message: _message,
        signingIn: _signingIn,
        onSubmit: _signIn,
      );
    }
    final mobile = MediaQuery.sizeOf(context).width < 900;
    return Scaffold(
      key: _scaffoldKey,
      body: SafeArea(
        child: Row(
          children: [
            if (!mobile)
              _AdminSidebar(
                selected: _module,
                roles: _roles,
                onSelect: (module) => setState(() => _module = module),
                onSignOut: _signOut,
              ),
            Expanded(
              child: Column(
                children: [
                  _AdminTopBar(
                    selected: _module,
                    user: _user,
                    roles: _roles,
                    search: _search,
                    loading: _loadingData,
                    mobile: mobile,
                    onRefresh: _loadAdminData,
                    onSearchChanged: () => setState(() {}),
                    onSelect: (module) => setState(() => _module = module),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: _AdminNotice(message: _message!),
                    ),
                  Expanded(
                    child: _AdminModuleBody(
                      module: _module,
                      query: _search.text,
                      data: _data,
                      metrics: _metrics,
                      canManageAdmins: _can(AdminPermission.manageAdmins),
                      canDuplicateDeliveries: _can(
                        AdminPermission.duplicateDeliveries,
                      ),
                      canManageRiders: _can(AdminPermission.approveDrivers),
                      canEditDeliveries: _can(AdminPermission.editDeliveries),
                      canManageIssues: _can(AdminPermission.manageIssues),
                      canManageHealthPlus: _can(
                        AdminPermission.manageHealthPlus,
                      ),
                      canManageFinance: _can(AdminPermission.manageFinance),
                      onDuplicateDelivery: _duplicateDelivery,
                      onSetRiderStatus: _setRiderStatus,
                      onSetDeliveryOperationStatus: _setDeliveryOperationStatus,
                      onResolveStaleDeliveryLock: _resolveStaleDeliveryLock,
                      onArchiveDelivery: _archiveDeliveryFromAdmin,
                      onSetIrisReviewStatus: _setIrisReviewStatus,
                      onLoadIrisReferenceImage: _loadIrisReferenceImage,
                      onFinalizeIrisReferenceImage: _finalizeIrisReferenceImage,
                      onDeleteIrisReferenceImage: _deleteIrisReferenceImage,
                      onUpdateSupportTicket: _updateSupportTicket,
                      onUpdateGiftWorkflow: _updateGiftWorkflow,
                      onUpdateHealthPlusPickup: _updateHealthPlusPickup,
                      onUpdateFinanceWorkflow: _updateFinanceWorkflow,
                      onIssueRoth: _issueRothFromAdminRecord,
                      onSetWalletFrozen: _setWalletFrozenFromAdminRecord,
                      onProcessPayoutRequest: _processPayoutRequestFromAdmin,
                      onModerateRating: _moderateRating,
                      onSyncRiderStripe: _syncRiderStripeStatus,
                      onResetRiderStripe: _resetRiderStripe,
                      onRequestRiderMoreInformation:
                          _requestRiderMoreInformation,
                      onReviewRiderDocument: _reviewRiderDocument,
                      onRemoveRiderProfilePhoto: _removeRiderProfilePhoto,
                      onUpdateHealthPlusProfile: _updateHealthPlusProfile,
                      onUpdateHealthPlusSchedule: _updateHealthPlusSchedule,
                      onUpdateGiftCampaignParticipant:
                          _updateGiftCampaignParticipant,
                      onSetGiftBrandStatus: _setGiftBrandStatus,
                      onEditGiftBrandPartner: _editGiftBrandPartner,
                      onSuggestGiftCampaignMatch: _suggestGiftCampaignMatch,
                      onApproveGiftCampaignMatch: _approveGiftCampaignMatch,
                      onBulkGiftCampaignAction: _bulkGiftCampaignAction,
                      onEditGiftRequest: _editGiftRequestWorkflow,
                      onUpdateGiftStoryAccess: _updateGiftStoryAccess,
                      onUpdateGiftStoryMedia: _updateGiftStoryMedia,
                      onUpdateGiftWorkspace: _updateGiftWorkspace,
                      onUpdateIrisRepositoryRecord: _updateIrisRepositoryRecord,
                      onUpdateIrisCandidateWorkflow:
                          _updateIrisCandidateWorkflow,
                      onSetBusinessOperationStatus: _setBusinessOperationStatus,
                      onChangeBusinessMemberRole: _changeBusinessMemberRole,
                      onRemoveBusinessMember: _removeBusinessMember,
                      onUpdatePlatformRecord: _updatePlatformRecord,
                      announcementTitle: _announcementTitle,
                      announcementBody: _announcementBody,
                      onSendPlatformAnnouncement: _sendPlatformAnnouncement,
                      onRetryNotificationDelivery: _retryNotificationDelivery,
                      onOpenRiderProfile: _openRiderProfile,
                      onOpenDeliveryProfile: _openDeliveryProfile,
                      onOpenHealthPlusProfile: _openHealthPlusProfile,
                      onOpenAccountProfile: _openAccountProfile,
                      onSetSenderAccountStatus: _setSenderAccountStatus,
                      onSetBusinessAccountStatus: _setBusinessAccountStatus,
                      onRequestDuplicateMerge: _requestDuplicateMerge,
                      adminInviteEmail: _adminInviteEmail,
                      adminInviteNote: _adminInviteNote,
                      adminInviteRole: _adminInviteRole,
                      onAdminInviteRoleChanged: (role) =>
                          setState(() => _adminInviteRole = role),
                      onCreateAdminUser: () => _saveAdminUser(
                        email: _adminInviteEmail.text,
                        role: _adminInviteRole,
                      ),
                      onSetAdminUserStatus: _setAdminUserStatus,
                      onSetAdminUserRole: _setAdminUserRole,
                      chatMessage: _chatMessage,
                      selectedChat: _selectedChat,
                      selectedChatMessages: _selectedChatMessages,
                      onSelectChat: _selectChat,
                      onSendChatMessage: _sendChatMessage,
                      onResolveMessageReport: _resolveMessageReport,
                      onOpenSupportConversation: _openSupportConversation,
                      onStartRiderConversation: _startRiderConversation,
                      onAddAdminNote: _addAdminNote,
                      onUpdateSenderTrust: _updateSenderTrust,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      endDrawer: _selectedRider == null
          ? _selectedDelivery == null
                ? _selectedHealthPlus == null
                      ? _selectedAccount == null
                            ? null
                            : _AccountProfileDrawer(
                                account: _selectedAccount!,
                                accountType: _selectedAccountType,
                                deliveries: _data.deliveries,
                                payments: _data.payments,
                                supportTickets: _data.supportTickets,
                                giftOrders: _data.giftOrders,
                                businessAccounts: _data.businessAccounts,
                                users: _data.users,
                                onClose: () =>
                                    setState(() => _selectedAccount = null),
                                onSetSenderStatus: (status) =>
                                    _setSenderAccountStatus(
                                      _selectedAccount!,
                                      status,
                                    ),
                                onSetBusinessStatus: (status) =>
                                    _setBusinessAccountStatus(
                                      _selectedAccount!,
                                      status,
                                    ),
                                onRequestDuplicateMerge: (duplicate) =>
                                    _requestDuplicateMerge(
                                      _selectedAccount!,
                                      duplicate,
                                    ),
                              )
                      : _HealthPlusOperationsDrawer(
                          record: _selectedHealthPlus!,
                          deliveries: _data.deliveries,
                          supportTickets: _data.supportTickets,
                          auditLogs: _data.auditLogs,
                          onClose: () =>
                              setState(() => _selectedHealthPlus = null),
                          onSetStatus: (status) => _updateHealthPlusPickup(
                            _selectedHealthPlus!,
                            status,
                          ),
                        )
                : _DeliveryOperationsDrawer(
                    delivery: _selectedDelivery!,
                    riders: _data.riders,
                    payments: _data.payments,
                    supportTickets: _data.supportTickets,
                    chats: _data.chats,
                    auditLogs: _data.auditLogs,
                    onClose: () => setState(() => _selectedDelivery = null),
                    onSetStatus: (status) =>
                        _setDeliveryOperationStatus(_selectedDelivery!, status),
                  )
          : _RiderProfileDrawer(
              rider: _selectedRider!,
              deliveries: _data.deliveries,
              documents: _data.riderDocuments,
              ratings: _data.ratings,
              supportTickets: _data.supportTickets,
              auditLogs: _data.auditLogs,
              onClose: () => setState(() => _selectedRider = null),
              onSetStatus: (status) => _setRiderStatus(_selectedRider!, status),
            ),
    );
  }
}

class AdminDataBundle {
  const AdminDataBundle({
    required this.deliveries,
    required this.users,
    required this.riders,
    required this.adminUsers,
    required this.payments,
    required this.payoutRequests,
    required this.riderEarnings,
    required this.riderWalletTransactions,
    required this.wallets,
    required this.walletTransactions,
    required this.businessWallets,
    required this.businessInvoices,
    required this.businessRothPurchases,
    required this.deliveryTips,
    required this.ratings,
    required this.supportTickets,
    required this.healthPlusPayments,
    required this.healthPlusPickups,
    required this.healthPlusProfiles,
    required this.recurringPickupSchedules,
    required this.healthPlusCustodyArchive,
    required this.businessAccounts,
    required this.giftOrders,
    required this.giftRequests,
    required this.giftBrands,
    required this.giftCampaignParticipants,
    required this.giftCampaignMatches,
    required this.auditLogs,
    required this.chats,
    required this.riderDocuments,
    required this.driverPerformanceMetrics,
    required this.websiteVisitors,
    required this.irisCanonicalObjects,
    required this.irisLearningCases,
    required this.irisLearningOutliers,
    required this.irisPolicies,
    required this.irisEvidence,
    required this.irisReferenceImages,
    required this.platformConfig,
    required this.platformStatus,
    required this.platformNotices,
    required this.platformVersions,
    required this.notifications,
    required this.messageReports,
    required this.adminNotes,
    required this.senderTrustEvents,
  });

  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> adminUsers;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> payoutRequests;
  final List<Map<String, dynamic>> riderEarnings;
  final List<Map<String, dynamic>> riderWalletTransactions;
  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> walletTransactions;
  final List<Map<String, dynamic>> businessWallets;
  final List<Map<String, dynamic>> businessInvoices;
  final List<Map<String, dynamic>> businessRothPurchases;
  final List<Map<String, dynamic>> deliveryTips;
  final List<Map<String, dynamic>> ratings;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> healthPlusPayments;
  final List<Map<String, dynamic>> healthPlusPickups;
  final List<Map<String, dynamic>> healthPlusProfiles;
  final List<Map<String, dynamic>> recurringPickupSchedules;
  final List<Map<String, dynamic>> healthPlusCustodyArchive;
  final List<Map<String, dynamic>> businessAccounts;
  final List<Map<String, dynamic>> giftOrders;
  final List<Map<String, dynamic>> giftRequests;
  final List<Map<String, dynamic>> giftBrands;
  final List<Map<String, dynamic>> giftCampaignParticipants;
  final List<Map<String, dynamic>> giftCampaignMatches;
  final List<Map<String, dynamic>> auditLogs;
  final List<Map<String, dynamic>> chats;
  final List<Map<String, dynamic>> riderDocuments;
  final List<Map<String, dynamic>> driverPerformanceMetrics;
  final List<Map<String, dynamic>> websiteVisitors;
  final List<Map<String, dynamic>> irisCanonicalObjects;
  final List<Map<String, dynamic>> irisLearningCases;
  final List<Map<String, dynamic>> irisLearningOutliers;
  final List<Map<String, dynamic>> irisPolicies;
  final List<Map<String, dynamic>> irisEvidence;
  final List<Map<String, dynamic>> irisReferenceImages;
  final List<Map<String, dynamic>> platformConfig;
  final List<Map<String, dynamic>> platformStatus;
  final List<Map<String, dynamic>> platformNotices;
  final List<Map<String, dynamic>> platformVersions;
  final List<Map<String, dynamic>> notifications;
  final List<Map<String, dynamic>> messageReports;
  final List<Map<String, dynamic>> adminNotes;
  final List<Map<String, dynamic>> senderTrustEvents;

  static AdminDataBundle empty() => const AdminDataBundle(
    deliveries: [],
    users: [],
    riders: [],
    adminUsers: [],
    payments: [],
    payoutRequests: [],
    riderEarnings: [],
    riderWalletTransactions: [],
    wallets: [],
    walletTransactions: [],
    businessWallets: [],
    businessInvoices: [],
    businessRothPurchases: [],
    deliveryTips: [],
    ratings: [],
    supportTickets: [],
    healthPlusPayments: [],
    healthPlusPickups: [],
    healthPlusProfiles: [],
    recurringPickupSchedules: [],
    healthPlusCustodyArchive: [],
    businessAccounts: [],
    giftOrders: [],
    giftRequests: [],
    giftBrands: [],
    giftCampaignParticipants: [],
    giftCampaignMatches: [],
    auditLogs: [],
    chats: [],
    riderDocuments: [],
    driverPerformanceMetrics: [],
    websiteVisitors: [],
    irisCanonicalObjects: [],
    irisLearningCases: [],
    irisLearningOutliers: [],
    irisPolicies: [],
    irisEvidence: [],
    irisReferenceImages: [],
    platformConfig: [],
    platformStatus: [],
    platformNotices: [],
    platformVersions: [],
    notifications: [],
    messageReports: [],
    adminNotes: [],
    senderTrustEvents: [],
  );
}

class AdminRepository {
  const AdminRepository(this._db);

  final FirebaseFirestore _db;

  Future<AdminDataBundle> load({
    required bool canManageAdmins,
    required bool canViewFinance,
    required bool canViewSupport,
    required bool canViewHealthPlus,
  }) async {
    final results = await Future.wait([
      _read(_db.collection('deliveryRequests').limit(100)),
      _read(_db.collection('users').limit(100)),
      _read(_db.collection('riderProfiles').limit(100)),
      canManageAdmins
          ? _read(_db.collection('adminUsers').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      canViewFinance
          ? _read(_db.collection('payments').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      canViewFinance
          ? _read(_db.collection('payoutRequests').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      canViewFinance
          ? _read(_db.collection('riderEarnings').limit(120))
          : Future.value(<Map<String, dynamic>>[]),
      canViewFinance
          ? _read(
              _db
                  .collection('riderWalletTransactions')
                  .orderBy('createdAt', descending: true)
                  .limit(120),
            )
          : Future.value(<Map<String, dynamic>>[]),
      canViewFinance
          ? _read(_db.collection('wallets').limit(120))
          : Future.value(<Map<String, dynamic>>[]),
      canViewFinance
          ? _read(
              _db
                  .collection('walletTransactions')
                  .orderBy('createdAt', descending: true)
                  .limit(160),
            )
          : Future.value(<Map<String, dynamic>>[]),
      canViewFinance
          ? _read(_db.collection('business_wallets').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      canViewFinance
          ? _read(
              _db
                  .collection('businessInvoices')
                  .orderBy('createdAt', descending: true)
                  .limit(80),
            )
          : Future.value(<Map<String, dynamic>>[]),
      canViewFinance
          ? _read(
              _db
                  .collection('businessRothPurchases')
                  .orderBy('createdAt', descending: true)
                  .limit(80),
            )
          : Future.value(<Map<String, dynamic>>[]),
      _read(_db.collection('driverRatings').limit(100)),
      _read(_db.collection('deliveryTips').limit(150)),
      canViewSupport
          ? _read(_db.collection('supportTickets').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      canViewHealthPlus || canViewFinance
          ? _read(_db.collection('healthPlusPayments').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      canViewHealthPlus
          ? _read(_db.collection('prescriptionPickups').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      canViewHealthPlus
          ? _read(_db.collection('healthPlusProfiles').limit(120))
          : Future.value(<Map<String, dynamic>>[]),
      canViewHealthPlus
          ? _read(_db.collection('recurringPickupSchedules').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      canViewHealthPlus
          ? _read(
              _db
                  .collection('healthPlusCustodyArchive')
                  .orderBy('createdAt', descending: true)
                  .limit(150),
            )
          : Future.value(<Map<String, dynamic>>[]),
      _read(_db.collection('businessAccounts').limit(100)),
      _read(_db.collection('giftOrders').limit(100)),
      _read(_db.collection('giftRequests').limit(150)),
      _read(_db.collection('giftBrands').limit(100)),
      _read(_db.collection('giftCampaignParticipants').limit(150)),
      _read(_db.collection('giftCampaignMatches').limit(150)),
      _read(
        _db
            .collection('adminAuditLogs')
            .orderBy('createdAt', descending: true)
            .limit(50),
      ),
      _read(
        _db
            .collection('chats')
            .orderBy('updatedAt', descending: true)
            .limit(50),
      ),
      _read(_db.collection('riderDocuments').limit(150)),
      _read(_db.collection('driverPerformanceMetrics').limit(150)),
      _read(
        _db
            .collection('websiteVisitors')
            .orderBy('createdAt', descending: true)
            .limit(150),
      ),
      _read(_db.collection('irisCanonicalObjects').limit(150)),
      _read(_db.collection('irisLearningCases').limit(150)),
      _read(_db.collection('irisLearningOutliers').limit(150)),
      _read(_db.collection('irisPolicies').limit(50)),
      _read(_db.collection('irisEvidence').limit(150)),
      _readTagged(
        _db.collection('irisReferenceImages').limit(150),
        'irisReferenceImages',
      ),
      _readTagged(
        _db.collection('platformConfig').limit(100),
        'platformConfig',
      ),
      _readTagged(
        _db.collection('platformStatus').limit(100),
        'platformStatus',
      ),
      _readTagged(
        _db.collection('platformNotices').limit(100),
        'platformNotices',
      ),
      _readTagged(
        _db.collection('platformVersions').limit(100),
        'platformVersions',
      ),
      _read(
        _db
            .collection('notifications')
            .orderBy('createdAt', descending: true)
            .limit(150),
      ),
      canViewSupport
          ? _read(_db.collection('messageReports').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      canViewSupport
          ? _read(
              _db
                  .collection('adminNotes')
                  .orderBy('createdAt', descending: true)
                  .limit(150),
            )
          : Future.value(<Map<String, dynamic>>[]),
      _read(
        _db
            .collection('senderTrustEvents')
            .orderBy('createdAt', descending: true)
            .limit(150),
      ),
    ]);
    return AdminDataBundle(
      deliveries: results[0],
      users: results[1],
      riders: results[2],
      adminUsers: results[3],
      payments: results[4],
      payoutRequests: results[5],
      riderEarnings: results[6],
      riderWalletTransactions: results[7],
      wallets: results[8],
      walletTransactions: results[9],
      businessWallets: results[10],
      businessInvoices: results[11],
      businessRothPurchases: results[12],
      ratings: results[13],
      deliveryTips: results[14],
      supportTickets: results[15],
      healthPlusPayments: results[16],
      healthPlusPickups: results[17],
      healthPlusProfiles: results[18],
      recurringPickupSchedules: results[19],
      healthPlusCustodyArchive: results[20],
      businessAccounts: results[21],
      giftOrders: results[22],
      giftRequests: results[23],
      giftBrands: results[24],
      giftCampaignParticipants: results[25],
      giftCampaignMatches: results[26],
      auditLogs: results[27],
      chats: results[28],
      riderDocuments: results[29],
      driverPerformanceMetrics: results[30],
      websiteVisitors: results[31],
      irisCanonicalObjects: results[32],
      irisLearningCases: results[33],
      irisLearningOutliers: results[34],
      irisPolicies: results[35],
      irisEvidence: results[36],
      irisReferenceImages: results[37],
      platformConfig: results[38],
      platformStatus: results[39],
      platformNotices: results[40],
      platformVersions: results[41],
      notifications: results[42],
      messageReports: results[43],
      adminNotes: results[44],
      senderTrustEvents: results[45],
    );
  }

  Future<List<Map<String, dynamic>>> _read(
    Query<Map<String, dynamic>> query,
  ) async {
    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _readTagged(
    Query<Map<String, dynamic>> query,
    String collection,
  ) async {
    final records = await _read(query);
    return records
        .map((record) => {'_collection': collection, ...record})
        .toList(growable: false);
  }
}

class _AdminLoginView extends StatelessWidget {
  const _AdminLoginView({
    required this.email,
    required this.password,
    required this.message,
    required this.signingIn,
    required this.onSubmit,
  });

  final TextEditingController email;
  final TextEditingController password;
  final String? message;
  final bool signingIn;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: DecoratedBox(
              decoration: _panelDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Admin surface',
                      style: TextStyle(
                        color: Color(0xFF7DD3FC),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Circum Admin',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in with an active Admin role.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .7),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => onSubmit(),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 14),
                      _AdminNotice(message: message!),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: signingIn ? null : onSubmit,
                      icon: signingIn
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open_rounded),
                      label: Text(signingIn ? 'Checking...' : 'Open Admin'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.selected,
    required this.roles,
    required this.onSelect,
    required this.onSignOut,
  });

  final AdminModule selected;
  final List<String> roles;
  final ValueChanged<AdminModule> onSelect;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      margin: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Text(
              'Admin',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              roles.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: .62)),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                for (final module in AdminModule.values)
                  _ModuleButton(
                    module: module,
                    selected: selected == module,
                    onTap: () => onSelect(module),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({
    required this.selected,
    required this.user,
    required this.roles,
    required this.search,
    required this.loading,
    required this.mobile,
    required this.onRefresh,
    required this.onSearchChanged,
    required this.onSelect,
  });

  final AdminModule selected;
  final User? user;
  final List<String> roles;
  final TextEditingController search;
  final bool loading;
  final bool mobile;
  final VoidCallback onRefresh;
  final VoidCallback onSearchChanged;
  final ValueChanged<AdminModule> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      decoration: _panelDecoration(radius: 22),
      child: Row(
        children: [
          if (mobile)
            PopupMenuButton<AdminModule>(
              icon: const Icon(Icons.menu_rounded),
              onSelected: onSelect,
              itemBuilder: (_) => [
                for (final module in AdminModule.values)
                  PopupMenuItem(value: module, child: Text(module.label)),
              ],
            ),
          Icon(selected.icon, color: const Color(0xFF7DD3FC), size: 22),
          const SizedBox(width: 12),
          SizedBox(
            width: mobile ? 122 : 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Circum / Admin',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF7DD3FC).withValues(alpha: .82),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  selected.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: search,
                onChanged: (_) => onSearchChanged(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: 'Search ${selected.label}',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: .10),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _StatusPill(label: loading ? 'Syncing' : 'Live'),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Refresh',
            onPressed: loading ? null : onRefresh,
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          if (!mobile) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF7C3AED).withValues(alpha: .22),
              child: Text(
                _adminInitials(user?.email),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminModuleBody extends StatelessWidget {
  const _AdminModuleBody({
    required this.module,
    required this.query,
    required this.data,
    required this.metrics,
    required this.canManageAdmins,
    required this.canDuplicateDeliveries,
    required this.canManageRiders,
    required this.canEditDeliveries,
    required this.canManageIssues,
    required this.canManageHealthPlus,
    required this.canManageFinance,
    required this.onDuplicateDelivery,
    required this.onSetRiderStatus,
    required this.onSetDeliveryOperationStatus,
    required this.onResolveStaleDeliveryLock,
    required this.onArchiveDelivery,
    required this.onSetIrisReviewStatus,
    required this.onLoadIrisReferenceImage,
    required this.onFinalizeIrisReferenceImage,
    required this.onDeleteIrisReferenceImage,
    required this.onUpdateSupportTicket,
    required this.onUpdateGiftWorkflow,
    required this.onUpdateHealthPlusPickup,
    required this.onUpdateFinanceWorkflow,
    required this.onIssueRoth,
    required this.onSetWalletFrozen,
    required this.onProcessPayoutRequest,
    required this.onModerateRating,
    required this.onSyncRiderStripe,
    required this.onResetRiderStripe,
    required this.onRequestRiderMoreInformation,
    required this.onReviewRiderDocument,
    required this.onRemoveRiderProfilePhoto,
    required this.onUpdateHealthPlusProfile,
    required this.onUpdateHealthPlusSchedule,
    required this.onUpdateGiftCampaignParticipant,
    required this.onSetGiftBrandStatus,
    required this.onEditGiftBrandPartner,
    required this.onSuggestGiftCampaignMatch,
    required this.onApproveGiftCampaignMatch,
    required this.onBulkGiftCampaignAction,
    required this.onEditGiftRequest,
    required this.onUpdateGiftStoryAccess,
    required this.onUpdateGiftStoryMedia,
    required this.onUpdateGiftWorkspace,
    required this.onUpdateIrisRepositoryRecord,
    required this.onUpdateIrisCandidateWorkflow,
    required this.onSetBusinessOperationStatus,
    required this.onChangeBusinessMemberRole,
    required this.onRemoveBusinessMember,
    required this.onUpdatePlatformRecord,
    required this.onOpenRiderProfile,
    required this.onOpenDeliveryProfile,
    required this.onOpenHealthPlusProfile,
    required this.onOpenAccountProfile,
    required this.onSetSenderAccountStatus,
    required this.onSetBusinessAccountStatus,
    required this.onRequestDuplicateMerge,
    required this.adminInviteEmail,
    required this.adminInviteNote,
    required this.adminInviteRole,
    required this.onAdminInviteRoleChanged,
    required this.onCreateAdminUser,
    required this.onSetAdminUserStatus,
    required this.onSetAdminUserRole,
    required this.announcementTitle,
    required this.announcementBody,
    required this.onSendPlatformAnnouncement,
    required this.chatMessage,
    required this.selectedChat,
    required this.selectedChatMessages,
    required this.onSelectChat,
    required this.onSendChatMessage,
    required this.onResolveMessageReport,
    required this.onOpenSupportConversation,
    required this.onStartRiderConversation,
    required this.onAddAdminNote,
    required this.onUpdateSenderTrust,
    required this.onRetryNotificationDelivery,
  });

  final AdminModule module;
  final String query;
  final AdminDataBundle data;
  final AdminMetricSnapshot metrics;
  final bool canManageAdmins;
  final bool canDuplicateDeliveries;
  final bool canManageRiders;
  final bool canEditDeliveries;
  final bool canManageIssues;
  final bool canManageHealthPlus;
  final bool canManageFinance;
  final ValueChanged<Map<String, dynamic>> onDuplicateDelivery;
  final Future<void> Function(Map<String, dynamic>, String) onSetRiderStatus;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetDeliveryOperationStatus;
  final Future<void> Function(Map<String, dynamic>) onResolveStaleDeliveryLock;
  final Future<void> Function(Map<String, dynamic>) onArchiveDelivery;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetIrisReviewStatus;
  final Future<void> Function(Map<String, dynamic>) onLoadIrisReferenceImage;
  final Future<void> Function(Map<String, dynamic>)
  onFinalizeIrisReferenceImage;
  final Future<void> Function(Map<String, dynamic>) onDeleteIrisReferenceImage;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateSupportTicket;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftWorkflow;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateHealthPlusPickup;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateFinanceWorkflow;
  final Future<void> Function(Map<String, dynamic>) onIssueRoth;
  final Future<void> Function(Map<String, dynamic>, bool) onSetWalletFrozen;
  final Future<void> Function(Map<String, dynamic>, String)
  onProcessPayoutRequest;
  final Future<void> Function(Map<String, dynamic>, String) onModerateRating;
  final Future<void> Function(Map<String, dynamic>) onSyncRiderStripe;
  final Future<void> Function(Map<String, dynamic>) onResetRiderStripe;
  final Future<void> Function(Map<String, dynamic>)
  onRequestRiderMoreInformation;
  final Future<void> Function(Map<String, dynamic>, String)
  onReviewRiderDocument;
  final Future<void> Function(Map<String, dynamic>) onRemoveRiderProfilePhoto;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateHealthPlusProfile;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateHealthPlusSchedule;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftCampaignParticipant;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetGiftBrandStatus;
  final Future<void> Function(Map<String, dynamic>?) onEditGiftBrandPartner;
  final Future<void> Function(Map<String, dynamic>, List<Map<String, dynamic>>)
  onSuggestGiftCampaignMatch;
  final Future<void> Function(Map<String, dynamic>, List<Map<String, dynamic>>)
  onApproveGiftCampaignMatch;
  final Future<void> Function(List<Map<String, dynamic>>, String)
  onBulkGiftCampaignAction;
  final Future<void> Function(Map<String, dynamic>) onEditGiftRequest;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftStoryAccess;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftStoryMedia;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftWorkspace;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateIrisRepositoryRecord;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateIrisCandidateWorkflow;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetBusinessOperationStatus;
  final Future<void> Function(Map<String, dynamic>, String)
  onChangeBusinessMemberRole;
  final Future<void> Function(Map<String, dynamic>) onRemoveBusinessMember;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdatePlatformRecord;
  final ValueChanged<Map<String, dynamic>> onOpenRiderProfile;
  final ValueChanged<Map<String, dynamic>> onOpenDeliveryProfile;
  final ValueChanged<Map<String, dynamic>> onOpenHealthPlusProfile;
  final void Function(Map<String, dynamic>, String) onOpenAccountProfile;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetSenderAccountStatus;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetBusinessAccountStatus;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>)
  onRequestDuplicateMerge;
  final TextEditingController adminInviteEmail;
  final TextEditingController adminInviteNote;
  final AdminRole adminInviteRole;
  final ValueChanged<AdminRole> onAdminInviteRoleChanged;
  final VoidCallback onCreateAdminUser;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetAdminUserStatus;
  final Future<void> Function(Map<String, dynamic>, AdminRole)
  onSetAdminUserRole;
  final TextEditingController announcementTitle;
  final TextEditingController announcementBody;
  final Future<void> Function(String) onSendPlatformAnnouncement;
  final TextEditingController chatMessage;
  final Map<String, dynamic>? selectedChat;
  final List<Map<String, dynamic>> selectedChatMessages;
  final ValueChanged<Map<String, dynamic>> onSelectChat;
  final VoidCallback onSendChatMessage;
  final Future<void> Function(Map<String, dynamic>, String)
  onResolveMessageReport;
  final Future<void> Function(Map<String, dynamic>) onOpenSupportConversation;
  final Future<void> Function(Map<String, dynamic>) onStartRiderConversation;
  final Future<void> Function(Map<String, dynamic>, String) onAddAdminNote;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateSenderTrust;
  final Future<void> Function(Map<String, dynamic>) onRetryNotificationDelivery;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        switch (module) {
          AdminModule.dashboard => _Dashboard(metrics: metrics, data: data),
          AdminModule.visitorAnalytics => _VisitorAnalyticsModule(
            records: data.websiteVisitors,
          ),
          AdminModule.discrepancyReview => _IrisOperationsModule(
            deliveries: data.deliveries,
            auditLogs: data.auditLogs,
            canonicalObjects: data.irisCanonicalObjects,
            learningCases: data.irisLearningCases,
            policies: data.irisPolicies,
            evidenceRecords: data.irisEvidence,
            referenceImages: data.irisReferenceImages,
            query: query,
            canManageIris: canEditDeliveries,
            onOpenDelivery: onOpenDeliveryProfile,
            onSetIrisReviewStatus: onSetIrisReviewStatus,
            onLoadReferenceImage: onLoadIrisReferenceImage,
            onFinalizeReferenceImage: onFinalizeIrisReferenceImage,
            onDeleteReferenceImage: onDeleteIrisReferenceImage,
            onUpdateRepositoryRecord: onUpdateIrisRepositoryRecord,
            onUpdateCandidateWorkflow: onUpdateIrisCandidateWorkflow,
          ),
          AdminModule.irisRepository => _IrisRepositoryGovernanceModule(
            canonicalObjects: data.irisCanonicalObjects,
            referenceImages: data.irisReferenceImages,
            auditLogs: data.auditLogs,
            query: query,
            canManageIris: canEditDeliveries,
            onUpdateRepositoryRecord: onUpdateIrisRepositoryRecord,
            onLoadReferenceImage: onLoadIrisReferenceImage,
            onFinalizeReferenceImage: onFinalizeIrisReferenceImage,
            onDeleteReferenceImage: onDeleteIrisReferenceImage,
          ),
          AdminModule.irisCandidates => _IrisCandidateWorkflowModule(
            deliveries: data.deliveries,
            learningCases: data.irisLearningCases,
            evidenceRecords: data.irisEvidence,
            query: query,
            canManageIris: canEditDeliveries,
            onUpdateCandidateWorkflow: onUpdateIrisCandidateWorkflow,
          ),
          AdminModule.deliveries => _DeliveryOperationsModule(
            deliveries: data.deliveries,
            riders: data.riders,
            query: query,
            canDuplicateDeliveries: canDuplicateDeliveries,
            canEditDeliveries: canEditDeliveries,
            onOpenDelivery: onOpenDeliveryProfile,
            onDuplicateDelivery: onDuplicateDelivery,
            onSetDeliveryOperationStatus: onSetDeliveryOperationStatus,
            onResolveStaleDeliveryLock: onResolveStaleDeliveryLock,
            onArchiveDelivery: onArchiveDelivery,
          ),
          AdminModule.users => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RecordModule(
                title: 'Users',
                subtitle: 'Sender/customer accounts from backend records.',
                records: data.users,
                query: query,
                fields: const [
                  'id',
                  'fullName',
                  'name',
                  'email',
                  'phone',
                  'status',
                  'accountStatus',
                  'verificationStatus',
                ],
                columns: const ['Name', 'Email', 'Status', 'Verification'],
                row: (record) => [
                  '${record['fullName'] ?? record['name'] ?? record['id']}',
                  '${record['email'] ?? 'Not recorded'}',
                  '${record['status'] ?? record['accountStatus'] ?? 'active'}',
                  '${record['verificationStatus'] ?? record['kycStatus'] ?? 'not_required'}',
                ],
                actions: (record) => _accountActions(
                  account: record,
                  accountType: 'sender',
                  allAccounts: data.users,
                  onOpen: onOpenAccountProfile,
                  onSetStatus: onSetSenderAccountStatus,
                  onRequestDuplicateMerge: onRequestDuplicateMerge,
                  onAddAdminNote: onAddAdminNote,
                  onUpdateSenderTrust: onUpdateSenderTrust,
                ),
              ),
              const SizedBox(height: 18),
              _SenderTrustTimelinePanel(
                records: data.senderTrustEvents,
                users: data.users,
                query: query,
              ),
            ],
          ),
          AdminModule.riders => _RiderOperationsModule(
            riders: data.riders,
            deliveries: data.deliveries,
            documents: data.riderDocuments,
            driverPerformanceMetrics: data.driverPerformanceMetrics,
            auditLogs: data.auditLogs,
            adminNotes: data.adminNotes,
            ratings: data.ratings,
            payments: data.payments,
            query: query,
            canManageRiders: canManageRiders,
            onOpenRiderProfile: onOpenRiderProfile,
            onSetRiderStatus: onSetRiderStatus,
            onSyncRiderStripe: onSyncRiderStripe,
            onResetRiderStripe: onResetRiderStripe,
            onRequestMoreInformation: onRequestRiderMoreInformation,
            onReviewDocument: onReviewRiderDocument,
            onRemoveProfilePhoto: onRemoveRiderProfilePhoto,
            onStartRiderConversation: onStartRiderConversation,
          ),
          AdminModule.verification => _RecordModule(
            title: 'Verification',
            subtitle: 'Rider verification and document review inputs.',
            records: data.riders,
            query: query,
            fields: const [
              'id',
              'fullName',
              'verificationStatus',
              'approvalStatus',
            ],
            columns: const ['Rider', 'Verification', 'Approval', 'Updated'],
            row: (record) => [
              '${record['fullName'] ?? record['name'] ?? record['id']}',
              '${record['verificationStatus'] ?? 'pending'}',
              '${record['approvalStatus'] ?? 'pending'}',
              _date(record['updatedAt'] ?? record['createdAt']),
            ],
            actions: canManageRiders
                ? (record) => _riderActions(
                    record,
                    onSetRiderStatus,
                    onOpenRiderProfile,
                    onSyncRiderStripe: onSyncRiderStripe,
                    onResetRiderStripe: onResetRiderStripe,
                    onRequestMoreInformation: onRequestRiderMoreInformation,
                    onRemoveProfilePhoto: onRemoveRiderProfilePhoto,
                  )
                : null,
          ),
          AdminModule.support => _SupportOperationsModule(
            tickets: data.supportTickets,
            deliveries: data.deliveries,
            payments: data.payments,
            chats: data.chats,
            adminNotes: data.adminNotes,
            auditLogs: data.auditLogs,
            query: query,
            canManageIssues: canManageIssues,
            onUpdateSupportTicket: onUpdateSupportTicket,
            onOpenSupportConversation: onOpenSupportConversation,
            onAddAdminNote: onAddAdminNote,
          ),
          AdminModule.finance => _FinanceOperationsModule(
            payments: data.payments,
            payoutRequests: data.payoutRequests,
            riderEarnings: data.riderEarnings,
            riderWalletTransactions: data.riderWalletTransactions,
            wallets: data.wallets,
            walletTransactions: data.walletTransactions,
            businessWallets: data.businessWallets,
            businessInvoices: data.businessInvoices,
            businessRothPurchases: data.businessRothPurchases,
            deliveryTips: data.deliveryTips,
            ratings: data.ratings,
            deliveries: data.deliveries,
            supportTickets: data.supportTickets,
            auditLogs: data.auditLogs,
            query: query,
            canManageFinance: canManageFinance,
            onUpdateFinanceWorkflow: onUpdateFinanceWorkflow,
            onIssueRoth: onIssueRoth,
            onSetWalletFrozen: onSetWalletFrozen,
            onProcessPayoutRequest: onProcessPayoutRequest,
            onModerateRating: onModerateRating,
          ),
          AdminModule.healthPlus => _HealthPlusOperationsModule(
            pickups: data.healthPlusPickups,
            profiles: data.healthPlusProfiles,
            schedules: data.recurringPickupSchedules,
            custodyArchive: data.healthPlusCustodyArchive,
            payments: data.healthPlusPayments,
            deliveries: data.deliveries,
            supportTickets: data.supportTickets,
            query: query,
            canManageHealthPlus: canManageHealthPlus,
            onOpen: onOpenHealthPlusProfile,
            onUpdateHealthPlusPickup: onUpdateHealthPlusPickup,
            onUpdateHealthPlusProfile: onUpdateHealthPlusProfile,
            onUpdateHealthPlusSchedule: onUpdateHealthPlusSchedule,
          ),
          AdminModule.business => _BusinessOperationsModule(
            accounts: data.businessAccounts,
            deliveries: data.deliveries,
            healthPlusPickups: data.healthPlusPickups,
            giftRecords: [...data.giftOrders, ...data.giftRequests],
            businessWallets: data.businessWallets,
            businessInvoices: data.businessInvoices,
            businessRothPurchases: data.businessRothPurchases,
            auditLogs: data.auditLogs,
            payments: data.payments,
            supportTickets: data.supportTickets,
            query: query,
            onOpenAccountProfile: onOpenAccountProfile,
            onSetBusinessAccountStatus: onSetBusinessAccountStatus,
            onSetBusinessOperationStatus: onSetBusinessOperationStatus,
            onChangeBusinessMemberRole: onChangeBusinessMemberRole,
            onRemoveBusinessMember: onRemoveBusinessMember,
            onRequestDuplicateMerge: onRequestDuplicateMerge,
          ),
          AdminModule.gifts => _GiftsOperationsModule(
            gifts: [...data.giftOrders, ...data.giftRequests],
            brands: data.giftBrands,
            participants: data.giftCampaignParticipants,
            campaignMatches: data.giftCampaignMatches,
            deliveries: data.deliveries,
            payments: data.payments,
            supportTickets: data.supportTickets,
            auditLogs: data.auditLogs,
            query: query,
            canManageIssues: canManageIssues,
            onUpdateGiftWorkflow: onUpdateGiftWorkflow,
            onUpdateGiftCampaignParticipant: onUpdateGiftCampaignParticipant,
            onSetGiftBrandStatus: onSetGiftBrandStatus,
            onEditGiftBrandPartner: onEditGiftBrandPartner,
            onSuggestGiftCampaignMatch: onSuggestGiftCampaignMatch,
            onApproveGiftCampaignMatch: onApproveGiftCampaignMatch,
            onBulkGiftCampaignAction: onBulkGiftCampaignAction,
            onEditGiftRequest: onEditGiftRequest,
            onUpdateGiftStoryAccess: onUpdateGiftStoryAccess,
            onUpdateGiftStoryMedia: onUpdateGiftStoryMedia,
            onUpdateGiftWorkspace: onUpdateGiftWorkspace,
          ),
          AdminModule.troubleshooting => _TroubleshootingModule(
            deliveries: data.deliveries,
            payments: data.payments,
            supportTickets: data.supportTickets,
            ratings: data.ratings,
            query: query,
            canManageIssues: canManageIssues,
            onOpenDelivery: onOpenDeliveryProfile,
            onUpdateSupportTicket: onUpdateSupportTicket,
            onSetDeliveryOperationStatus: onSetDeliveryOperationStatus,
            onUpdateFinanceWorkflow: onUpdateFinanceWorkflow,
            onModerateRating: onModerateRating,
          ),
          AdminModule.analytics => _HistoricalAnalyticsModule(
            metrics: metrics,
            deliveries: data.deliveries,
            payments: data.payments,
            users: data.users,
            riders: data.riders,
            driverPerformanceMetrics: data.driverPerformanceMetrics,
            giftCampaignMatches: data.giftCampaignMatches,
            irisLearningOutliers: data.irisLearningOutliers,
            healthPlusPickups: data.healthPlusPickups,
            gifts: [...data.giftOrders, ...data.giftRequests],
            supportTickets: data.supportTickets,
          ),
          AdminModule.audit => _AuditCentreModule(
            auditLogs: data.auditLogs,
            users: data.users,
            riders: data.riders,
            businessAccounts: data.businessAccounts,
            deliveries: data.deliveries,
            gifts: [...data.giftOrders, ...data.giftRequests],
            healthPlusPickups: data.healthPlusPickups,
            supportTickets: data.supportTickets,
            payments: data.payments,
            query: query,
          ),
          AdminModule.chat => _ChatModule(
            records: data.chats,
            messageReports: data.messageReports,
            selectedChatMessages: selectedChatMessages,
            query: query,
            message: chatMessage,
            selectedChat: selectedChat,
            onSelectChat: onSelectChat,
            onSendChatMessage: onSendChatMessage,
            onResolveMessageReport: onResolveMessageReport,
          ),
          AdminModule.settings => _SettingsModule(
            canManageAdmins: canManageAdmins,
            adminUsers: data.adminUsers,
            platformConfig: data.platformConfig,
            platformStatus: data.platformStatus,
            platformNotices: data.platformNotices,
            platformVersions: data.platformVersions,
            notifications: data.notifications,
            auditLogs: data.auditLogs,
            inviteEmail: adminInviteEmail,
            inviteNote: adminInviteNote,
            inviteRole: adminInviteRole,
            onInviteRoleChanged: onAdminInviteRoleChanged,
            onCreateAdminUser: onCreateAdminUser,
            onSetAdminUserStatus: onSetAdminUserStatus,
            onSetAdminUserRole: onSetAdminUserRole,
            announcementTitle: announcementTitle,
            announcementBody: announcementBody,
            onSendPlatformAnnouncement: onSendPlatformAnnouncement,
            onUpdatePlatformRecord: onUpdatePlatformRecord,
            onRetryNotificationDelivery: onRetryNotificationDelivery,
          ),
        },
      ],
    );
  }
}

class _HealthPlusOperationsModule extends StatelessWidget {
  const _HealthPlusOperationsModule({
    required this.pickups,
    required this.profiles,
    required this.schedules,
    required this.custodyArchive,
    required this.payments,
    required this.deliveries,
    required this.supportTickets,
    required this.query,
    required this.canManageHealthPlus,
    required this.onOpen,
    required this.onUpdateHealthPlusPickup,
    required this.onUpdateHealthPlusProfile,
    required this.onUpdateHealthPlusSchedule,
  });

  final List<Map<String, dynamic>> pickups;
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> schedules;
  final List<Map<String, dynamic>> custodyArchive;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> supportTickets;
  final String query;
  final bool canManageHealthPlus;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateHealthPlusPickup;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateHealthPlusProfile;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateHealthPlusSchedule;

  @override
  Widget build(BuildContext context) {
    final records = [...pickups, ...schedules, ...profiles, ...payments];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(
              'Active prescriptions',
              records.where(_isActiveHealthPlus).length.toString(),
              'active',
            ),
            _MetricCard(
              'Pending',
              records
                  .where((item) => _healthStatus(item).contains('pending'))
                  .length
                  .toString(),
              'review',
            ),
            _MetricCard(
              'Awaiting pharmacy',
              records
                  .where((item) => _healthStatus(item).contains('pharmacy'))
                  .length
                  .toString(),
              'pharmacy',
            ),
            _MetricCard(
              'Ready',
              records
                  .where((item) => _healthStatus(item).contains('ready'))
                  .length
                  .toString(),
              'collection',
            ),
            _MetricCard(
              'Collected',
              records
                  .where((item) => _healthStatus(item).contains('collected'))
                  .length
                  .toString(),
              'picked up',
            ),
            _MetricCard(
              'In transit',
              records
                  .where((item) => _healthStatus(item).contains('transit'))
                  .length
                  .toString(),
              'delivery',
            ),
            _MetricCard(
              'Delivered',
              records
                  .where(
                    (item) =>
                        _healthStatus(item).contains('delivered') ||
                        _healthStatus(item).contains('completed'),
                  )
                  .length
                  .toString(),
              'complete',
            ),
            _MetricCard(
              'Failed',
              records
                  .where((item) => _healthStatus(item).contains('failed'))
                  .length
                  .toString(),
              'delivery',
            ),
            _MetricCard(
              'Escalations',
              records
                  .where((item) => _healthStatus(item).contains('escalat'))
                  .length
                  .toString(),
              'open',
            ),
            _MetricCard(
              'Clinical reviews',
              records.where(_needsClinicalReview).length.toString(),
              'queue',
            ),
            _MetricCard(
              'Health+ revenue',
              _money(_healthRevenue(payments)),
              'loaded payments',
            ),
            _MetricCard(
              'Pharmacies',
              _activePharmacies(records).length.toString(),
              'active',
            ),
            _MetricCard('Recurring', schedules.length.toString(), 'schedules'),
            _MetricCard('Profiles', profiles.length.toString(), 'patients'),
            _MetricCard('Custody', custodyArchive.length.toString(), 'events'),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Prescription Queue',
          subtitle:
              'Search patient, sender, pharmacy, booking, prescription, medication and urgency.',
          records: records,
          query: query,
          fields: const [
            'id',
            'bookingId',
            'prescriptionId',
            'patientName',
            'fullName',
            'senderName',
            'pharmacyName',
            'pharmacyAddress',
            'medication',
            'medicationName',
            'status',
            'clinicalReviewStatus',
          ],
          columns: const ['Prescription', 'Patient', 'Pharmacy', 'Status'],
          row: (record) => [
            _recordId(record),
            '${record['patientName'] ?? record['fullName'] ?? record['customerName'] ?? 'Patient'}',
            '${record['pharmacyName'] ?? record['pharmacyAddress'] ?? 'Pharmacy'}',
            '${record['status'] ?? record['clinicalReviewStatus'] ?? 'pending'}',
          ],
          actions: (record) => [
            _MiniAction(label: 'Details', onPressed: () => onOpen(record)),
            if (canManageHealthPlus)
              for (final action in const [
                ('Assign pharmacy', 'pharmacy_assigned'),
                ('Reassign', 'pharmacy_reassigned'),
                ('Assign rider', 'rider_assigned'),
                ('Escalate', 'escalated'),
                ('Approve review', 'review_approved'),
                ('Reject review', 'review_rejected'),
                ('Evidence', 'evidence_requested'),
                ('Pause', 'paused'),
                ('Resume', 'resumed'),
                ('Close', 'closed'),
              ])
                _MiniAction(
                  label: action.$1,
                  onPressed: () =>
                      unawaited(onUpdateHealthPlusProfile(record, action.$2)),
                ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Health+ Profile Workspace',
          subtitle:
              'Historical Health+ profile administration, medical profile viewer, operational history and audit-linked records.',
          records: adminSearch(profiles, query, const [
            'id',
            'profileId',
            'userId',
            'senderId',
            'patientName',
            'fullName',
            'email',
            'phoneNumber',
            'nhsNumberLast4',
            'medication',
            'pharmacyName',
            'pharmacyAddress',
            'status',
            'reviewStatus',
            'riskStatus',
          ]),
          query: '',
          fields: const [],
          columns: const ['Profile', 'Medical', 'Pharmacy', 'Operational'],
          row: (record) => [
            '${record['patientName'] ?? record['fullName'] ?? record['name'] ?? _recordId(record)}\n${record['email'] ?? record['phoneNumber'] ?? record['userId'] ?? record['senderId'] ?? ''}',
            '${record['medication'] ?? record['medicationName'] ?? record['prescriptionSummary'] ?? 'Medication profile'}\n${record['allergySummary'] ?? record['handlingNotes'] ?? record['clinicalNotes'] ?? ''}',
            '${record['pharmacyName'] ?? 'Pharmacy'}\n${record['pharmacyAddress'] ?? record['preferredPharmacyAddress'] ?? ''}',
            '${record['status'] ?? record['reviewStatus'] ?? 'active'} / ${record['riskStatus'] ?? record['clinicalReviewStatus'] ?? 'standard'}',
          ],
          actions: (record) => [
            _MiniAction(label: 'Open', onPressed: () => onOpen(record)),
            if (canManageHealthPlus)
              for (final action in const [
                ('Approve', 'profile_approved'),
                ('Review', 'profile_review_requested'),
                ('Escalate', 'profile_escalated'),
                ('Pause', 'profile_paused'),
              ])
                _MiniAction(
                  label: action.$1,
                  onPressed: () =>
                      unawaited(onUpdateHealthPlusPickup(record, action.$2)),
                ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Recurring Schedule Review',
          subtitle:
              'Historical recurring pickup schedule management, review and lifecycle controls.',
          records: adminSearch(schedules, query, const [
            'id',
            'scheduleId',
            'profileId',
            'userId',
            'senderId',
            'fullName',
            'status',
            'frequency',
            'subscriptionPlan',
            'preferredPickupTime',
          ]),
          query: '',
          fields: const [],
          columns: const ['Schedule', 'Customer', 'Plan', 'Status'],
          row: (record) => [
            _recordId(record),
            '${record['fullName'] ?? record['senderName'] ?? record['userId'] ?? record['senderId'] ?? 'Customer'}',
            '${record['subscriptionPlan'] ?? record['planType'] ?? 'core'} / ${record['frequency'] ?? 'recurring'}',
            '${record['status'] ?? record['adminReviewStatus'] ?? 'scheduled'}',
          ],
          actions: canManageHealthPlus
              ? (record) => [
                  _MiniAction(
                    label: 'Approve',
                    onPressed: () => unawaited(
                      onUpdateHealthPlusSchedule(record, 'approved'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Pause',
                    onPressed: () =>
                        unawaited(onUpdateHealthPlusSchedule(record, 'paused')),
                  ),
                  _MiniAction(
                    label: 'Resume',
                    onPressed: () =>
                        unawaited(onUpdateHealthPlusSchedule(record, 'active')),
                  ),
                  _MiniAction(
                    label: 'Cancel',
                    onPressed: () => unawaited(
                      onUpdateHealthPlusSchedule(record, 'cancelled'),
                    ),
                  ),
                ]
              : null,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Custody Timeline',
          subtitle:
              'Historical Health+ custody archive, evidence and status history.',
          records: adminSearch(custodyArchive, query, const [
            'id',
            'pickupId',
            'scheduleId',
            'eventType',
            'actorName',
            'internalNote',
            'publicMessage',
          ]),
          query: '',
          fields: const [],
          columns: const ['Event', 'Record', 'Actor', 'Evidence'],
          row: (record) => [
            '${record['eventType'] ?? record['type'] ?? 'custody_event'}',
            '${record['pickupId'] ?? record['scheduleId'] ?? _recordId(record)}',
            '${record['actorName'] ?? record['actorId'] ?? 'system'}',
            '${record['evidenceUrl'] ?? record['internalNote'] ?? record['publicMessage'] ?? ''}',
          ],
        ),
        const SizedBox(height: 18),
        _HealthPlusAnalyticsPanel(records: records),
      ],
    );
  }
}

class _BusinessOperationsModule extends StatelessWidget {
  const _BusinessOperationsModule({
    required this.accounts,
    required this.deliveries,
    required this.healthPlusPickups,
    required this.giftRecords,
    required this.businessWallets,
    required this.businessInvoices,
    required this.businessRothPurchases,
    required this.auditLogs,
    required this.payments,
    required this.supportTickets,
    required this.query,
    required this.onOpenAccountProfile,
    required this.onSetBusinessAccountStatus,
    required this.onSetBusinessOperationStatus,
    required this.onChangeBusinessMemberRole,
    required this.onRemoveBusinessMember,
    required this.onRequestDuplicateMerge,
  });

  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> healthPlusPickups;
  final List<Map<String, dynamic>> giftRecords;
  final List<Map<String, dynamic>> businessWallets;
  final List<Map<String, dynamic>> businessInvoices;
  final List<Map<String, dynamic>> businessRothPurchases;
  final List<Map<String, dynamic>> auditLogs;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> supportTickets;
  final String query;
  final void Function(Map<String, dynamic>, String) onOpenAccountProfile;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetBusinessAccountStatus;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetBusinessOperationStatus;
  final Future<void> Function(Map<String, dynamic>, String)
  onChangeBusinessMemberRole;
  final Future<void> Function(Map<String, dynamic>) onRemoveBusinessMember;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>)
  onRequestDuplicateMerge;

  @override
  Widget build(BuildContext context) {
    final members = _businessMemberRows();
    final businessDeliveries = _businessDeliveryRows();
    final health = _businessHealthPlusRows(businessDeliveries);
    final gifts = _businessGiftRows(businessDeliveries);
    final vanguard = businessDeliveries.where(_hasVanguardProtection).toList();
    final invoices = _businessInvoiceRows(businessDeliveries);
    final roth = [...businessWallets, ...businessRothPurchases];
    final analytics = _businessAnalyticsRows(businessDeliveries);
    final audit = _businessAuditRows();
    final active = accounts
        .where((item) => _businessStatus(item).contains('approved'))
        .length;
    final pending = accounts
        .where((item) => _businessStatus(item).contains('pending'))
        .length;
    final suspended = accounts
        .where((item) => _businessStatus(item).contains('suspend'))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard('Active businesses', active.toString(), 'approved'),
            _MetricCard('Pending approvals', pending.toString(), 'review'),
            _MetricCard('Suspended', suspended.toString(), 'restricted'),
            _MetricCard(
              'Monthly revenue',
              _money(_businessRevenue(payments)),
              'loaded payments',
            ),
            _MetricCard(
              'Invoices due',
              accounts.where(_hasInvoiceDue).length.toString(),
              'due',
            ),
            _MetricCard(
              'Outstanding invoices',
              accounts.where(_hasOutstandingInvoice).length.toString(),
              'open',
            ),
            _MetricCard(
              'Subscriptions',
              accounts
                  .where(
                    (item) =>
                        '${item['subscriptionStatus'] ?? item['plan'] ?? ''}'
                            .trim()
                            .isNotEmpty,
                  )
                  .length
                  .toString(),
              'active data',
            ),
            _MetricCard(
              'Deliveries',
              _countRecordsContaining(deliveries, 'business').toString(),
              'business',
            ),
            _MetricCard(
              'Health+',
              accounts
                  .where(
                    (item) =>
                        '${item['healthPlusEnabled'] ?? item['services'] ?? ''}'
                            .toLowerCase()
                            .contains('health'),
                  )
                  .length
                  .toString(),
              'enabled',
            ),
            _MetricCard(
              'Gifts',
              accounts
                  .where(
                    (item) => '${item['giftEnabled'] ?? item['services'] ?? ''}'
                        .toLowerCase()
                        .contains('gift'),
                  )
                  .length
                  .toString(),
              'enabled',
            ),
          ],
        ),
        const SizedBox(height: 18),
        DefaultTabController(
          length: 10,
          child: DecoratedBox(
            decoration: _panelDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Companies'),
                    Tab(text: 'Members'),
                    Tab(text: 'Deliveries'),
                    Tab(text: 'Health+'),
                    Tab(text: 'Gifts'),
                    Tab(text: 'Vanguard'),
                    Tab(text: 'Invoices'),
                    Tab(text: 'Roth'),
                    Tab(text: 'Analytics'),
                    Tab(text: 'Audit Log'),
                  ],
                ),
                SizedBox(
                  height: 640,
                  child: TabBarView(
                    children: [
                      _businessCompaniesWorkspace(),
                      _businessMembersWorkspace(members),
                      _businessDeliveriesWorkspace(businessDeliveries),
                      _businessHealthWorkspace(health),
                      _businessGiftsWorkspace(gifts),
                      _businessVanguardWorkspace(vanguard),
                      _businessInvoicesWorkspace(invoices),
                      _businessRothWorkspace(roth),
                      _businessAnalyticsWorkspace(analytics),
                      _businessAuditWorkspace(audit),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _businessCompaniesWorkspace() => _tabWorkspace(
    child: _RecordModule(
      title: 'Business Companies',
      subtitle:
          'Company profiles, approval status, team members and linked business deliveries.',
      records: accounts,
      query: query,
      fields: const [
        'id',
        'businessId',
        'businessName',
        'companyName',
        'ownerName',
        'ownerEmail',
        'contactName',
        'contactEmail',
        'billingEmail',
        'status',
        'verificationStatus',
      ],
      columns: const ['Business', 'Contact', 'Team', 'Status'],
      row: (record) {
        final id = _businessAccountId(record);
        return [
          '${record['businessName'] ?? record['companyName'] ?? id}\n$id',
          '${record['contactName'] ?? record['ownerName'] ?? ''}\n${record['contactEmail'] ?? record['billingEmail'] ?? record['ownerEmail'] ?? ''}',
          '${_membersFor(id).length} members\n${_deliveriesFor(id).length} deliveries',
          '${record['status'] ?? 'pending'} / ${record['verificationStatus'] ?? 'pending'}',
        ];
      },
      actions: (record) => [
        ..._accountActions(
          account: record,
          accountType: 'business',
          allAccounts: accounts,
          onOpen: onOpenAccountProfile,
          onSetStatus: onSetBusinessAccountStatus,
          onRequestDuplicateMerge: onRequestDuplicateMerge,
        ),
        for (final action in const [
          ('Verify', 'verified'),
          ('Manager', 'manager_assigned'),
          ('Close review', 'business_close_review'),
        ])
          _MiniAction(
            label: action.$1,
            onPressed: () =>
                unawaited(onSetBusinessOperationStatus(record, action.$2)),
          ),
      ],
    ),
  );

  Widget _businessMembersWorkspace(
    List<Map<String, dynamic>> members,
  ) => _tabWorkspace(
    child: _RecordModule(
      title: 'Business Members',
      subtitle:
          'Owners, invites, permissions, roles, removal, history and audit.',
      records: members,
      query: query,
      fields: const [
        'businessName',
        'businessId',
        'name',
        'email',
        'userId',
        'role',
        'status',
        'inviteStatus',
      ],
      columns: const ['Member', 'Email / UID', 'Role', 'Status'],
      row: (record) => [
        '${record['name'] ?? record['email'] ?? 'Member'}\n${record['businessName'] ?? record['businessId'] ?? ''}',
        '${record['email'] ?? record['userId'] ?? record['uid'] ?? ''}',
        '${record['role'] ?? record['permission'] ?? 'member'}',
        '${record['status'] ?? record['inviteStatus'] ?? 'active'}',
      ],
      actions: (record) {
        final editable =
            (record['memberIndex'] is int) &&
            (record['memberIndex'] as int) >= 0;
        return [
          if (editable)
            for (final role in const [
              'owner',
              'admin',
              'operations',
              'finance',
              'viewer',
            ])
              _MiniAction(
                label: role,
                onPressed: () =>
                    unawaited(onChangeBusinessMemberRole(record, role)),
              ),
          if (editable)
            _MiniAction(
              label: 'Remove',
              onPressed: () => unawaited(onRemoveBusinessMember(record)),
            ),
        ];
      },
    ),
  );

  Widget _businessDeliveriesWorkspace(
    List<Map<String, dynamic>> records,
  ) => _tabWorkspace(
    child: _RecordModule(
      title: 'Business Deliveries',
      subtitle:
          'Business-created deliveries with tracking, exceptions, IRIS, Health+, Gifts, Vanguard and history.',
      records: records,
      query: query,
      fields: const [
        'id',
        'requestId',
        'trackingId',
        'businessId',
        'businessName',
        'senderName',
        'recipientName',
        'status',
        'deliveryStatus',
        'serviceType',
        'irisReviewStatus',
      ],
      columns: const ['Delivery', 'Business', 'Route', 'Status'],
      row: (record) => [
        '${_recordId(record)}\n${record['trackingId'] ?? ''}',
        _businessNameFor(record),
        '${record['pickupAddress'] ?? record['pickup'] ?? 'Pickup'} -> ${record['dropoffAddress'] ?? record['dropoff'] ?? 'Dropoff'}',
        '${record['status'] ?? record['deliveryStatus'] ?? 'unknown'} / ${record['irisReviewStatus'] ?? record['paymentStatus'] ?? 'review n/a'}',
      ],
    ),
  );

  Widget _businessHealthWorkspace(
    List<Map<String, dynamic>> records,
  ) => _tabWorkspace(
    child: _RecordModule(
      title: 'Business Health+',
      subtitle:
          'Health+ jobs created under Business accounts with intervention kept in Health+ authority.',
      records: records,
      query: query,
      fields: const [
        'id',
        'businessId',
        'businessName',
        'patientName',
        'customerName',
        'senderName',
        'pharmacyName',
        'status',
      ],
      columns: const ['Record', 'Customer', 'Pharmacy', 'Status'],
      row: (record) => [
        '${_recordId(record)}\n${_businessNameFor(record)}',
        '${record['patientName'] ?? record['customerName'] ?? record['senderName'] ?? ''}',
        '${record['pharmacyName'] ?? record['pharmacyAddress'] ?? ''}',
        '${record['status'] ?? 'scheduled'}',
      ],
    ),
  );

  Widget _businessGiftsWorkspace(List<Map<String, dynamic>> records) =>
      _tabWorkspace(
        child: _RecordModule(
          title: 'Business Gifts',
          subtitle: 'Corporate gift requests and linked gift delivery records.',
          records: records,
          query: query,
          fields: const [
            'id',
            'giftOrderId',
            'businessId',
            'businessName',
            'senderName',
            'recipientName',
            'occasion',
            'status',
          ],
          columns: const ['Gift', 'Sender / Recipient', 'Occasion', 'Status'],
          row: (record) => [
            '${_recordId(record)}\n${_businessNameFor(record)}',
            '${record['senderName'] ?? ''} -> ${record['recipientName'] ?? ''}',
            '${record['occasion'] ?? record['relationship'] ?? 'Gift'}',
            '${record['status'] ?? 'pending'}',
          ],
        ),
      );

  Widget _businessVanguardWorkspace(
    List<Map<String, dynamic>> records,
  ) => _tabWorkspace(
    child: _RecordModule(
      title: 'Business Vanguard',
      subtitle:
          'Vanguard status across business deliveries, selected, policy-applied and required handling.',
      records: records,
      query: query,
      fields: const [
        'id',
        'requestId',
        'businessId',
        'businessName',
        'status',
        'serviceType',
        'vanguardSource',
        'vanguardPolicySource',
      ],
      columns: const ['Delivery', 'Service', 'Status', 'Vanguard Source'],
      row: (record) => [
        '${_recordId(record)}\n${_businessNameFor(record)}',
        '${record['serviceType'] ?? record['service'] ?? 'business'}',
        '${record['status'] ?? record['deliveryStatus'] ?? 'active'}',
        '${record['vanguardSource'] ?? record['vanguardPolicySource'] ?? (record['vanguardRequired'] == true ? 'required' : 'selected')}',
      ],
    ),
  );

  Widget _businessInvoicesWorkspace(
    List<Map<String, dynamic>> invoices,
  ) => _tabWorkspace(
    child: _RecordModule(
      title: 'Business Invoices',
      subtitle: 'Invoice generation, review, history, editing and audit.',
      records: invoices,
      query: query,
      fields: const [
        'id',
        'invoiceId',
        'invoiceNumber',
        'businessId',
        'businessName',
        'status',
        'invoiceStatus',
        'billingEmail',
      ],
      columns: const ['Invoice', 'Breakdown', 'Status', 'Amount'],
      row: (record) => [
        '${record['invoiceNumber'] ?? record['invoiceId'] ?? _recordId(record)}\n${_businessNameFor(record)}',
        '${record['billingPeriodStart'] ?? 'Period'} -> ${record['billingPeriodEnd'] ?? ''}\n${(record['lineItems'] as List?)?.length ?? record['invoiceDeliveryCount'] ?? 0} line item(s)',
        '${record['status'] ?? record['invoiceStatus'] ?? 'draft'}',
        _money(
          record['total'] ?? record['invoiceAmount'] ?? record['balanceDue'],
        ),
      ],
      actions: (record) => [
        for (final action in const [
          ('Issue', 'invoice_issue_review'),
          ('Cancel', 'invoice_cancel_review'),
          ('Adjust', 'subscription_adjust_review'),
        ])
          _MiniAction(
            label: action.$1,
            onPressed: () =>
                unawaited(onSetBusinessOperationStatus(record, action.$2)),
          ),
      ],
    ),
  );

  Widget _businessRothWorkspace(
    List<Map<String, dynamic>> roth,
  ) => _tabWorkspace(
    child: _RecordModule(
      title: 'Business Roth',
      subtitle: 'Business Roth purchases, usage, ledger, history and audit.',
      records: roth,
      query: query,
      fields: const [
        'id',
        'businessId',
        'businessName',
        'purchaseId',
        'status',
        'direction',
        'type',
        'source',
      ],
      columns: const ['Business', 'Source', 'Status', 'Amount'],
      row: (record) => [
        '${_businessNameFor(record)}\n${record['purchaseId'] ?? record['businessId'] ?? _recordId(record)}',
        '${record['type'] ?? record['source'] ?? 'business_roth'}\n${record['note'] ?? record['reason'] ?? ''}',
        '${record['status'] ?? record['direction'] ?? 'active'}',
        _money(record['amount'] ?? record['amountGbp'] ?? record['balance']),
      ],
      actions: (record) => [
        for (final action in const [
          ('Credit', 'roth_credit_review'),
          ('Debit', 'roth_debit_review'),
          ('Freeze', 'roth_freeze_review'),
        ])
          _MiniAction(
            label: action.$1,
            onPressed: () =>
                unawaited(onSetBusinessOperationStatus(record, action.$2)),
          ),
      ],
    ),
  );

  Widget _businessAnalyticsWorkspace(
    List<Map<String, dynamic>> analytics,
  ) => _tabWorkspace(
    child: _RecordModule(
      title: 'Business Analytics',
      subtitle:
          'Per-business delivery volume, spend, service mix, Vanguard usage, Health+ and Gifts volume.',
      records: analytics,
      query: query,
      fields: const ['businessName', 'businessId'],
      columns: const ['Business', 'Volume / Spend', 'On-time', 'Service Mix'],
      row: (record) => [
        '${record['businessName'] ?? 'Business'}',
        '${record['monthlyDeliveries'] ?? 0} deliveries\n${_money(record['spend'])} spend',
        '${(_numberFrom(record['onTimeRate'])).toStringAsFixed(1)}% complete/on-time proxy',
        'Vanguard ${record['vanguardUsage'] ?? 0}\nHealth+ ${record['healthUsage'] ?? 0}\nGifts ${record['giftsUsage'] ?? 0}',
      ],
    ),
  );

  Widget _businessAuditWorkspace(
    List<Map<String, dynamic>> audit,
  ) => _tabWorkspace(
    child: _RecordModule(
      title: 'Business Audit Log',
      subtitle:
          'Company, member, delivery, invoice, Roth and admin intervention events tied to Business accounts.',
      records: audit,
      query: query,
      fields: const [
        'businessId',
        'businessName',
        'action',
        'actionType',
        'recordType',
        'recordId',
        'adminEmail',
        'reason',
      ],
      columns: const ['Action', 'Record', 'Admin', 'Reason / Time'],
      row: (record) => [
        '${record['actionType'] ?? record['action'] ?? 'Business action'}\n${_businessNameFor(record)}',
        '${record['recordType'] ?? ''}\n${record['recordId'] ?? record['businessId'] ?? ''}',
        '${record['adminEmail'] ?? record['adminId'] ?? 'admin'}',
        '${record['reason'] ?? ''}\n${_date(record['createdAt'] ?? record['timestamp'])}',
      ],
    ),
  );

  Widget _tabWorkspace({required Widget child}) {
    return ListView(padding: const EdgeInsets.all(16), children: [child]);
  }

  List<Map<String, dynamic>> _businessDeliveryRows() =>
      deliveries.where(_isBusinessRecord).toList(growable: false);

  List<Map<String, dynamic>> _businessHealthPlusRows(
    List<Map<String, dynamic>> businessDeliveries,
  ) => [
    ...businessDeliveries.where(
      (item) =>
          _serviceType(item).contains('health') ||
          '${item['sourceModule'] ?? ''}'.toLowerCase().contains('health'),
    ),
    ...healthPlusPickups.where(_isBusinessRecord),
  ].toList(growable: false);

  List<Map<String, dynamic>> _businessGiftRows(
    List<Map<String, dynamic>> businessDeliveries,
  ) => [
    ...businessDeliveries.where(
      (item) =>
          _serviceType(item).contains('gift') ||
          '${item['sourceModule'] ?? ''}'.toLowerCase().contains('gift'),
    ),
    ...giftRecords.where(_isBusinessRecord),
  ].toList(growable: false);

  List<Map<String, dynamic>> _businessInvoiceRows(
    List<Map<String, dynamic>> businessDeliveries,
  ) {
    if (businessInvoices.isNotEmpty) return businessInvoices;
    return accounts
        .map((account) {
          final id = _businessAccountId(account);
          final scoped = businessDeliveries
              .where((delivery) => _businessRecordId(delivery) == id)
              .toList(growable: false);
          final amount = scoped.fold<double>(
            0,
            (total, delivery) =>
                total +
                _numberFrom(
                  delivery['finalAmount'] ??
                      delivery['price'] ??
                      delivery['quote'],
                ),
          );
          return {
            ...account,
            'id': id,
            'businessId': id,
            'invoiceAmount': account['outstandingInvoiceAmount'] ?? amount,
            'invoiceStatus': account['invoiceStatus'] ?? 'draft',
            'invoiceDeliveryCount': scoped.length,
          };
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _businessAnalyticsRows(
    List<Map<String, dynamic>> businessDeliveries,
  ) => accounts
      .map((account) {
        final id = _businessAccountId(account);
        final scoped = businessDeliveries
            .where((delivery) => _businessRecordId(delivery) == id)
            .toList(growable: false);
        final completed = scoped
            .where(
              (item) =>
                  '${item['status'] ?? item['deliveryStatus'] ?? ''}'
                      .toLowerCase()
                      .contains('complete') ||
                  '${item['status'] ?? item['deliveryStatus'] ?? ''}'
                      .toLowerCase()
                      .contains('deliver'),
            )
            .length;
        final spend = scoped.fold<double>(
          0,
          (total, item) =>
              total +
              _numberFrom(
                item['finalAmount'] ?? item['price'] ?? item['quote'],
              ),
        );
        return {
          ...account,
          'businessId': id,
          'monthlyDeliveries': scoped.length,
          'onTimeRate': scoped.isEmpty ? 0 : (completed / scoped.length) * 100,
          'spend': spend,
          'vanguardUsage': scoped.where(_hasVanguardProtection).length,
          'healthUsage': scoped
              .where((item) => _serviceType(item).contains('health'))
              .length,
          'giftsUsage': scoped
              .where((item) => _serviceType(item).contains('gift'))
              .length,
        };
      })
      .toList(growable: false);

  List<Map<String, dynamic>> _businessMemberRows() {
    final rows = <Map<String, dynamic>>[];
    for (final account in accounts) {
      final id = _businessAccountId(account);
      final members = account['teamMembers'];
      if (members is List) {
        for (var index = 0; index < members.length; index++) {
          final member = members[index];
          if (member is Map) {
            rows.add({
              ...member.cast<String, dynamic>(),
              'id': id,
              'businessId': id,
              'businessName': account['businessName'] ?? account['companyName'],
              'memberIndex': index,
            });
          }
        }
      }
      final ownerId =
          '${account['createdByUserId'] ?? account['ownerId'] ?? ''}';
      if (ownerId.isNotEmpty) {
        rows.add({
          'id': id,
          'businessId': id,
          'businessName': account['businessName'] ?? account['companyName'],
          'userId': ownerId,
          'email': account['contactEmail'] ?? account['billingEmail'],
          'name': account['contactName'] ?? account['ownerName'],
          'role': 'owner',
          'status': 'active',
          'memberIndex': -1,
        });
      }
    }
    return rows;
  }

  List<Map<String, dynamic>> _membersFor(String businessId) =>
      _businessMemberRows()
          .where((member) => _businessRecordId(member) == businessId)
          .toList(growable: false);

  List<Map<String, dynamic>> _deliveriesFor(String businessId) => deliveries
      .where((delivery) => _businessRecordId(delivery) == businessId)
      .toList(growable: false);

  List<Map<String, dynamic>> _businessAuditRows() => auditLogs
      .where(
        (item) =>
            _isBusinessRecord(item) ||
            '${item['action'] ?? item['actionType'] ?? ''}'
                .toLowerCase()
                .contains('business'),
      )
      .toList(growable: false);

  bool _isBusinessRecord(Map<String, dynamic> item) =>
      item['isBusinessDelivery'] == true ||
      item['businessDelivery'] == true ||
      '${item['sourceModule'] ?? ''}'.toLowerCase() == 'business' ||
      _businessRecordId(item).isNotEmpty;

  String _businessRecordId(Map<String, dynamic> item) =>
      '${item['businessId'] ?? item['businessAccountId'] ?? item['companyId'] ?? ''}'
          .trim();

  String _businessAccountId(Map<String, dynamic> item) =>
      '${item['businessId'] ?? item['businessAccountId'] ?? item['companyId'] ?? item['id'] ?? ''}'
          .trim();

  String _businessNameFor(Map<String, dynamic> item) {
    final direct = '${item['businessName'] ?? item['companyName'] ?? ''}'
        .trim();
    if (direct.isNotEmpty) return direct;
    final businessId = _businessRecordId(item);
    final account = accounts.firstWhere(
      (candidate) => _businessAccountId(candidate) == businessId,
      orElse: () => const {},
    );
    return '${account['businessName'] ?? account['companyName'] ?? businessId}';
  }

  String _serviceType(Map<String, dynamic> item) =>
      '${item['serviceType'] ?? item['service'] ?? item['category'] ?? ''}'
          .toLowerCase();
}

class _HealthPlusAnalyticsPanel extends StatelessWidget {
  const _HealthPlusAnalyticsPanel({required this.records});

  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Health+ analytics',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HealthChip('Orders', records.length),
                _HealthChip(
                  'Success',
                  records
                      .where(
                        (item) =>
                            _healthStatus(item).contains('complete') ||
                            _healthStatus(item).contains('delivered'),
                      )
                      .length,
                ),
                _HealthChip(
                  'Turnaround',
                  records.where((item) => item['completedAt'] != null).length,
                ),
                _HealthChip(
                  'Escalations',
                  records
                      .where((item) => _healthStatus(item).contains('escalat'))
                      .length,
                ),
                for (final pharmacy in _activePharmacies(records).take(6))
                  _HealthChip(
                    pharmacy,
                    records
                        .where(
                          (item) =>
                              '${item['pharmacyName'] ?? item['pharmacyAddress'] ?? ''}' ==
                              pharmacy,
                        )
                        .length,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IrisOperationsModule extends StatelessWidget {
  const _IrisOperationsModule({
    required this.deliveries,
    required this.auditLogs,
    required this.canonicalObjects,
    required this.learningCases,
    required this.policies,
    required this.evidenceRecords,
    required this.referenceImages,
    required this.query,
    required this.canManageIris,
    required this.onOpenDelivery,
    required this.onSetIrisReviewStatus,
    required this.onLoadReferenceImage,
    required this.onFinalizeReferenceImage,
    required this.onDeleteReferenceImage,
    required this.onUpdateRepositoryRecord,
    required this.onUpdateCandidateWorkflow,
  });

  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> auditLogs;
  final List<Map<String, dynamic>> canonicalObjects;
  final List<Map<String, dynamic>> learningCases;
  final List<Map<String, dynamic>> policies;
  final List<Map<String, dynamic>> evidenceRecords;
  final List<Map<String, dynamic>> referenceImages;
  final String query;
  final bool canManageIris;
  final ValueChanged<Map<String, dynamic>> onOpenDelivery;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetIrisReviewStatus;
  final Future<void> Function(Map<String, dynamic>) onLoadReferenceImage;
  final Future<void> Function(Map<String, dynamic>) onFinalizeReferenceImage;
  final Future<void> Function(Map<String, dynamic>) onDeleteReferenceImage;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateRepositoryRecord;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateCandidateWorkflow;

  @override
  Widget build(BuildContext context) {
    final irisRecords = deliveries.where(_hasIrisSignal).toList();
    final pending = irisRecords.where(_isIrisPending).length;
    final lowConfidence = irisRecords.where(_isLowConfidenceIris).length;
    final highConfidence = irisRecords.where(_isHighConfidenceIris).length;
    final disputed = irisRecords.where(_hasWeightDispute).length;
    final learning = irisRecords.where(_isLearningCandidate).length;
    final averageConfidence = _averageIrisConfidence(irisRecords);
    final completedToday = irisRecords
        .where(
          (record) =>
              _isSameDay(record, DateTime.now()) && !_isIrisPending(record),
        )
        .length;
    final engineering = irisRecords
        .where((record) => _irisState(record).contains('engineering'))
        .length;
    final evidenceRequests = irisRecords
        .where((record) => _irisState(record).contains('evidence'))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard('Pending reviews', pending.toString(), 'IRIS queue'),
            _MetricCard(
              'Completed today',
              completedToday.toString(),
              'reviews closed',
            ),
            _MetricCard(
              'Avg review time',
              _averageIrisReviewTime(irisRecords),
              'loaded records',
            ),
            _MetricCard('High confidence', highConfidence.toString(), '>= 85%'),
            _MetricCard('Low confidence', lowConfidence.toString(), '< 60%'),
            _MetricCard(
              'Weight disputes',
              disputed.toString(),
              'sender, rider or IRIS mismatch',
            ),
            _MetricCard(
              'Category disputes',
              irisRecords.where(_hasCategoryDispute).length.toString(),
              'category variance',
            ),
            _MetricCard(
              'Vehicle disputes',
              irisRecords.where(_hasVehicleDispute).length.toString(),
              'vehicle variance',
            ),
            _MetricCard(
              'Admin overrides',
              _countIrisOverrides(auditLogs).toString(),
              'audit records',
            ),
            _MetricCard('Learning queue', learning.toString(), 'candidates'),
            _MetricCard(
              'Failures',
              irisRecords.where(_hasIrisFailure).length.toString(),
              'processing',
            ),
            _MetricCard(
              'Evidence requests',
              evidenceRequests.toString(),
              'open',
            ),
            _MetricCard('Engineering', engineering.toString(), 'escalations'),
            _MetricCard(
              'Active reviewers',
              _activeIrisReviewers(auditLogs).length.toString(),
              'today',
            ),
            _MetricCard(
              'Queue health',
              _irisQueueHealth(pending, lowConfidence),
              'command',
            ),
            _MetricCard(
              'Avg confidence',
              '${averageConfidence.toStringAsFixed(0)}%',
              'loaded records',
            ),
            _MetricCard(
              'Categories',
              _categoryDistribution(irisRecords).length.toString(),
              'observed',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _IrisHealthPanel(records: irisRecords, evidence: evidenceRecords),
        const SizedBox(height: 18),
        _IrisAnalyticsPanel(
          records: irisRecords,
          auditLogs: auditLogs,
          learningCases: learningCases,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Global IRIS Search and Review Queue',
          subtitle:
              'Search delivery, booking, IRIS ID, sender, recipient, rider, business, canonical object, category, evidence, vehicle, weight and reviewer.',
          records: irisRecords,
          query: query,
          fields: const [
            'id',
            'requestId',
            'trackingId',
            'senderName',
            'recipientName',
            'riderId',
            'businessName',
            'category',
            'irisCategory',
            'irisReviewStatus',
            'reviewType',
            'serviceType',
            'vehicleType',
            'recommendedVehicle',
            'weight',
            'verifiedWeight',
            'reviewer',
            'irisId',
          ],
          columns: const ['Delivery', 'Estimate', 'Confidence', 'Review'],
          row: (record) => [
            _recordId(record),
            _irisEstimateSummary(record),
            '${_irisConfidence(record).toStringAsFixed(0)}%',
            '${record['irisReviewStatus'] ?? record['reviewType'] ?? 'pending'}',
          ],
          actions: (record) => [
            _MiniAction(
              label: 'Details',
              onPressed: () => onOpenDelivery(record),
            ),
            if (canManageIris) ...[
              for (final action in const [
                ('Approve', 'approved'),
                ('Reject', 'rejected'),
                ('Weight review', 'weight_override_review'),
                ('Category review', 'category_override_review'),
                ('Vehicle review', 'vehicle_override_review'),
                ('More evidence', 'more_evidence_requested'),
                ('Engineering', 'engineering_review'),
                ('Learning', 'learning_flagged'),
                ('Approve evidence', 'evidence_approved'),
                ('Reject evidence', 'evidence_rejected'),
                ('Archive evidence', 'evidence_archived'),
                ('Assign reviewer', 'review_assigned'),
                ('Merge duplicate', 'duplicate_merge_review'),
                ('Promote learning', 'learning_promoted'),
                ('Reject learning', 'learning_rejected'),
                ('Restore archived', 'archived_review_restored'),
                ('Close', 'closed'),
              ])
                _MiniAction(
                  label: action.$1,
                  onPressed: () =>
                      unawaited(onSetIrisReviewStatus(record, action.$2)),
                ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        _IrisCanonicalLibraryModule(
          records: canonicalObjects,
          query: query,
          auditLogs: auditLogs,
          canManageIris: canManageIris,
          onLoadReferenceImage: onLoadReferenceImage,
          onFinalizeReferenceImage: onFinalizeReferenceImage,
          onDeleteReferenceImage: onDeleteReferenceImage,
          onUpdateRepositoryRecord: onUpdateRepositoryRecord,
        ),
        const SizedBox(height: 18),
        _IrisAliasManagerModule(
          records: canonicalObjects,
          query: query,
          canManageIris: canManageIris,
          onUpdateRepositoryRecord: onUpdateRepositoryRecord,
        ),
        const SizedBox(height: 18),
        _IrisCategoryGovernanceModule(
          records: canonicalObjects,
          query: query,
          canManageIris: canManageIris,
          onUpdateRepositoryRecord: onUpdateRepositoryRecord,
        ),
        const SizedBox(height: 18),
        _IrisImportSettingsModule(
          records: canonicalObjects,
          auditLogs: auditLogs,
          canManageIris: canManageIris,
          onUpdateRepositoryRecord: onUpdateRepositoryRecord,
        ),
        const SizedBox(height: 18),
        _IrisReferenceImageLifecycleModule(
          records: referenceImages,
          canonicalObjects: canonicalObjects,
          query: query,
          canManageIris: canManageIris,
          onLoadReferenceImage: onLoadReferenceImage,
          onFinalizeReferenceImage: onFinalizeReferenceImage,
          onDeleteReferenceImage: onDeleteReferenceImage,
        ),
        const SizedBox(height: 18),
        _IrisEvidenceCentre(records: evidenceRecords, query: query),
        const SizedBox(height: 18),
        _IrisLearningCentre(
          learningCases: learningCases,
          reviewRecords: irisRecords,
          query: query,
          canManageIris: canManageIris,
          onUpdateCandidateWorkflow: onUpdateCandidateWorkflow,
        ),
        const SizedBox(height: 18),
        _IrisPolicyCentre(records: policies),
        const SizedBox(height: 18),
        _IrisExportCentre(records: irisRecords, auditLogs: auditLogs),
      ],
    );
  }
}

class _IrisCanonicalLibraryModule extends StatelessWidget {
  const _IrisCanonicalLibraryModule({
    required this.records,
    required this.query,
    required this.auditLogs,
    required this.canManageIris,
    required this.onLoadReferenceImage,
    required this.onFinalizeReferenceImage,
    required this.onDeleteReferenceImage,
    required this.onUpdateRepositoryRecord,
  });

  final List<Map<String, dynamic>> records;
  final String query;
  final List<Map<String, dynamic>> auditLogs;
  final bool canManageIris;
  final Future<void> Function(Map<String, dynamic>) onLoadReferenceImage;
  final Future<void> Function(Map<String, dynamic>) onFinalizeReferenceImage;
  final Future<void> Function(Map<String, dynamic>) onDeleteReferenceImage;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateRepositoryRecord;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canManageIris)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniAction(
                  label: 'New Canonical Item',
                  onPressed: () => unawaited(
                    onUpdateRepositoryRecord({
                      'id':
                          'canonical-${DateTime.now().millisecondsSinceEpoch}',
                      '_collection': 'irisCanonicalObjects',
                    }, 'edited'),
                  ),
                ),
                for (final action in const [
                  ('Bulk edit', 'bulk_edited'),
                  ('Bulk merge', 'bulk_merged'),
                  ('Bulk category', 'bulk_category_changed'),
                  ('Bulk vehicle', 'bulk_vehicle_changed'),
                  ('Bulk activate', 'activated'),
                  ('Bulk deactivate', 'deactivated'),
                  ('Export', 'bulk_exported'),
                ])
                  _MiniAction(
                    label: action.$1,
                    onPressed: records.isEmpty
                        ? () {}
                        : () => unawaited(
                            onUpdateRepositoryRecord(records.first, action.$2),
                          ),
                  ),
              ],
            ),
          ),
        _RecordModule(
          title: 'Canonical Knowledge Base',
          subtitle:
              'Categories, objects, dimensions, weight bands, handling, fragility, dangerous goods and eligibility records.',
          records: records,
          query: query,
          fields: const [
            'id',
            'category',
            'subcategory',
            'objectName',
            'canonicalName',
            'weightBand',
            'vehicleRecommendation',
            'handlingRequirements',
            'marketplaceEligible',
            'healthPlusEligible',
            'giftEligible',
            'businessEligible',
            'adminNotes',
          ],
          columns: const ['Object', 'Category', 'Weight/Vehicle', 'Policy'],
          row: (record) => [
            '${record['objectName'] ?? record['canonicalName'] ?? _recordId(record)}',
            '${record['category'] ?? 'Uncategorised'} / ${record['subcategory'] ?? 'none'}',
            '${record['knownWeight'] ?? record['weightBand'] ?? 'unknown'} / ${record['vehicleRecommendation'] ?? 'vehicle n/a'}',
            _canonicalPolicySummary(record),
          ],
          actions: canManageIris
              ? (record) => [
                  _MiniAction(
                    label: 'Edit',
                    onPressed: () =>
                        unawaited(onUpdateRepositoryRecord(record, 'edited')),
                  ),
                  _MiniAction(
                    label: 'Duplicate',
                    onPressed: () => unawaited(
                      onUpdateRepositoryRecord(record, 'duplicate_review'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Deactivate',
                    onPressed: () => unawaited(
                      onUpdateRepositoryRecord(record, 'deactivated'),
                    ),
                  ),
                  _MiniAction(
                    label: 'History',
                    onPressed: () => unawaited(
                      onUpdateRepositoryRecord(record, 'history_reviewed'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Bulk export',
                    onPressed: () => unawaited(
                      onUpdateRepositoryRecord(record, 'bulk_exported'),
                    ),
                  ),
                  ..._irisReferenceImageActions(
                    record,
                    onLoadReferenceImage: onLoadReferenceImage,
                    onFinalizeReferenceImage: onFinalizeReferenceImage,
                    onDeleteReferenceImage: onDeleteReferenceImage,
                  ),
                ]
              : null,
        ),
      ],
    );
  }
}

class _IrisRepositoryGovernanceModule extends StatelessWidget {
  const _IrisRepositoryGovernanceModule({
    required this.canonicalObjects,
    required this.referenceImages,
    required this.auditLogs,
    required this.query,
    required this.canManageIris,
    required this.onUpdateRepositoryRecord,
    required this.onLoadReferenceImage,
    required this.onFinalizeReferenceImage,
    required this.onDeleteReferenceImage,
  });

  final List<Map<String, dynamic>> canonicalObjects;
  final List<Map<String, dynamic>> referenceImages;
  final List<Map<String, dynamic>> auditLogs;
  final String query;
  final bool canManageIris;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateRepositoryRecord;
  final Future<void> Function(Map<String, dynamic>) onLoadReferenceImage;
  final Future<void> Function(Map<String, dynamic>) onFinalizeReferenceImage;
  final Future<void> Function(Map<String, dynamic>) onDeleteReferenceImage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AdminModuleIntro(
          title: 'IRIS Repository Governance',
          subtitle:
              'Canonical repository review, administration, reference images and lifecycle history.',
        ),
        const SizedBox(height: 16),
        _IrisCanonicalLibraryModule(
          records: canonicalObjects,
          query: query,
          auditLogs: auditLogs,
          canManageIris: canManageIris,
          onLoadReferenceImage: onLoadReferenceImage,
          onFinalizeReferenceImage: onFinalizeReferenceImage,
          onDeleteReferenceImage: onDeleteReferenceImage,
          onUpdateRepositoryRecord: onUpdateRepositoryRecord,
        ),
        const SizedBox(height: 18),
        _IrisReferenceImageLifecycleModule(
          records: referenceImages,
          canonicalObjects: canonicalObjects,
          query: query,
          canManageIris: canManageIris,
          onLoadReferenceImage: onLoadReferenceImage,
          onFinalizeReferenceImage: onFinalizeReferenceImage,
          onDeleteReferenceImage: onDeleteReferenceImage,
        ),
      ],
    );
  }
}

class _IrisCandidateWorkflowModule extends StatelessWidget {
  const _IrisCandidateWorkflowModule({
    required this.deliveries,
    required this.learningCases,
    required this.evidenceRecords,
    required this.query,
    required this.canManageIris,
    required this.onUpdateCandidateWorkflow,
  });

  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> learningCases;
  final List<Map<String, dynamic>> evidenceRecords;
  final String query;
  final bool canManageIris;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateCandidateWorkflow;

  @override
  Widget build(BuildContext context) {
    final deliveryCandidates = deliveries
        .where(_isLearningCandidate)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AdminModuleIntro(
          title: 'IRIS Candidate Workflows',
          subtitle:
              'Candidate review, approval, rejection, promotion and learning evidence.',
        ),
        const SizedBox(height: 16),
        _IrisLearningCentre(
          reviewRecords: deliveryCandidates,
          learningCases: learningCases,
          query: query,
          canManageIris: canManageIris,
          onUpdateCandidateWorkflow: onUpdateCandidateWorkflow,
        ),
        const SizedBox(height: 18),
        _IrisEvidenceCentre(records: evidenceRecords, query: query),
      ],
    );
  }
}

class _IrisAliasManagerModule extends StatelessWidget {
  const _IrisAliasManagerModule({
    required this.records,
    required this.query,
    required this.canManageIris,
    required this.onUpdateRepositoryRecord,
  });

  final List<Map<String, dynamic>> records;
  final String query;
  final bool canManageIris;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateRepositoryRecord;

  @override
  Widget build(BuildContext context) {
    final aliases = <Map<String, dynamic>>[];
    for (final record in records) {
      for (final alias in _adminStringList(record['aliases'])) {
        aliases.add({
          ...record,
          'alias': alias,
          'aliasStatus': record['aliasStatus'] ?? 'active',
        });
      }
    }
    return _RecordModule(
      title: 'Alias Manager',
      subtitle:
          'Historical alias browser, alias editor, merge, deletion and audit workflow.',
      records: aliases,
      query: query,
      fields: const ['alias', 'canonicalName', 'objectName', 'category'],
      columns: const ['Alias', 'Canonical Item', 'Status', 'History'],
      row: (record) => [
        '${record['alias']}',
        '${record['canonicalName'] ?? record['objectName'] ?? _recordId(record)}',
        '${record['aliasStatus'] ?? 'active'}',
        '${record['lastHistoryReviewedAt'] ?? record['updatedAt'] ?? 'No review'}',
      ],
      actions: canManageIris
          ? (record) => [
              for (final action in const [
                ('Edit', 'alias_edited'),
                ('Merge', 'alias_merged'),
                ('Delete', 'alias_deleted'),
                ('Audit', 'alias_history_reviewed'),
              ])
                _MiniAction(
                  label: action.$1,
                  onPressed: () =>
                      unawaited(onUpdateRepositoryRecord(record, action.$2)),
                ),
            ]
          : null,
    );
  }
}

class _IrisCategoryGovernanceModule extends StatelessWidget {
  const _IrisCategoryGovernanceModule({
    required this.records,
    required this.query,
    required this.canManageIris,
    required this.onUpdateRepositoryRecord,
  });

  final List<Map<String, dynamic>> records;
  final String query;
  final bool canManageIris;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateRepositoryRecord;

  @override
  Widget build(BuildContext context) {
    final categories = <String, Map<String, dynamic>>{};
    for (final record in records) {
      final category = '${record['category'] ?? 'Uncategorised'}';
      categories.putIfAbsent(
        category,
        () => {
          'id': _slugId(category),
          '_collection': record['_collection'] ?? 'irisCanonicalObjects',
          'category': category,
          'count': 0,
          'status': record['categoryStatus'] ?? 'active',
        },
      );
      categories[category]!['count'] =
          (categories[category]!['count'] as int) + 1;
    }
    return _RecordModule(
      title: 'Category Management',
      subtitle:
          'Historical categories, category editor, merge, activation and history workflow.',
      records: categories.values.toList(growable: false),
      query: query,
      fields: const ['category', 'status'],
      columns: const ['Category', 'Records', 'Status', 'History'],
      row: (record) => [
        '${record['category']}',
        '${record['count']}',
        '${record['status']}',
        '${record['lastHistoryReviewedAt'] ?? 'No review'}',
      ],
      actions: canManageIris
          ? (record) => [
              for (final action in const [
                ('Edit', 'category_edited'),
                ('Merge', 'category_merged'),
                ('Activate', 'activated'),
                ('History', 'category_history_reviewed'),
              ])
                _MiniAction(
                  label: action.$1,
                  onPressed: () =>
                      unawaited(onUpdateRepositoryRecord(record, action.$2)),
                ),
            ]
          : null,
    );
  }
}

class _IrisImportSettingsModule extends StatelessWidget {
  const _IrisImportSettingsModule({
    required this.records,
    required this.auditLogs,
    required this.canManageIris,
    required this.onUpdateRepositoryRecord,
  });

  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> auditLogs;
  final bool canManageIris;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateRepositoryRecord;

  @override
  Widget build(BuildContext context) {
    final importRows = [
      {
        'id': 'repository-import-review',
        '_collection': 'irisCanonicalObjects',
        'name': 'Repository import review',
        'status': 'pending_validation',
        'records': records.length,
      },
      {
        'id': 'repository-governance-settings',
        '_collection': 'irisCanonicalObjects',
        'name': 'Repository governance configuration',
        'status': 'guarded',
        'records': auditLogs
            .where((log) => '${log['actionType']}'.contains('iris'))
            .length,
      },
    ];
    return _RecordModule(
      title: 'Imports and Repository Settings',
      subtitle:
          'Historical import review, validation, approval and governance configuration.',
      records: importRows,
      query: '',
      fields: const [],
      columns: const ['Workspace', 'Status', 'Records', 'Governance'],
      row: (record) => [
        '${record['name']}',
        '${record['status']}',
        '${record['records']}',
        'Admin governed',
      ],
      actions: canManageIris
          ? (record) => [
              for (final action in const [
                ('Review import', 'import_reviewed'),
                ('Validate', 'import_validated'),
                ('Approve import', 'import_approved'),
                ('Settings', 'settings_reviewed'),
              ])
                _MiniAction(
                  label: action.$1,
                  onPressed: () =>
                      unawaited(onUpdateRepositoryRecord(record, action.$2)),
                ),
            ]
          : null,
    );
  }
}

class _IrisReferenceImageLifecycleModule extends StatelessWidget {
  const _IrisReferenceImageLifecycleModule({
    required this.records,
    required this.canonicalObjects,
    required this.query,
    required this.canManageIris,
    required this.onLoadReferenceImage,
    required this.onFinalizeReferenceImage,
    required this.onDeleteReferenceImage,
  });

  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> canonicalObjects;
  final String query;
  final bool canManageIris;
  final Future<void> Function(Map<String, dynamic>) onLoadReferenceImage;
  final Future<void> Function(Map<String, dynamic>) onFinalizeReferenceImage;
  final Future<void> Function(Map<String, dynamic>) onDeleteReferenceImage;

  @override
  Widget build(BuildContext context) {
    final pending = records.where(_isPendingReferenceImage).toList();
    final approved = records.where(_isApprovedReferenceImage).toList();
    final queue = records.isEmpty
        ? canonicalObjects.where(_hasReferenceImageSignal).toList()
        : records;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(
              'Pending reference images',
              '${pending.length}',
              'awaiting finalisation',
            ),
            _MetricCard(
              'Approved images',
              '${approved.length}',
              'available for IRIS review',
            ),
            _MetricCard(
              'Lifecycle records',
              '${queue.length}',
              'historical reference queue',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'IRIS Reference Image Lifecycle',
          subtitle:
              'Pending and approved reference images using the historical Admin callables.',
          records: queue,
          query: query,
          fields: const [
            'id',
            'itemId',
            'canonicalName',
            'objectName',
            'status',
            'referenceImageStatus',
            'storagePath',
            'referenceImageStoragePath',
            'previewUrl',
            'referenceImageUrl',
          ],
          columns: const ['Reference', 'Status', 'Storage', 'Updated'],
          row: (record) => [
            '${record['canonicalName'] ?? record['objectName'] ?? record['itemId'] ?? record['id']}',
            '${record['referenceImageStatus'] ?? record['status'] ?? 'pending'}',
            '${record['storagePath'] ?? record['referenceImageStoragePath'] ?? record['fileName'] ?? 'no storage path'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canManageIris
              ? (record) => _irisReferenceImageActions(
                  record,
                  onLoadReferenceImage: onLoadReferenceImage,
                  onFinalizeReferenceImage: onFinalizeReferenceImage,
                  onDeleteReferenceImage: onDeleteReferenceImage,
                )
              : null,
        ),
      ],
    );
  }
}

class _IrisEvidenceCentre extends StatelessWidget {
  const _IrisEvidenceCentre({required this.records, required this.query});

  final List<Map<String, dynamic>> records;
  final String query;

  @override
  Widget build(BuildContext context) {
    return _RecordModule(
      title: 'Evidence Centre',
      subtitle:
          'Original capture, additional evidence, comparison metadata, device, orientation and quality indicators.',
      records: records,
      query: query,
      fields: const [
        'id',
        'deliveryId',
        'requestId',
        'irisId',
        'captureType',
        'device',
        'orientation',
        'quality',
        'status',
        'metadata',
      ],
      columns: const ['Evidence', 'Capture', 'Quality', 'Status'],
      row: (record) => [
        _recordId(record),
        '${record['captureType'] ?? record['imageType'] ?? 'image'} / ${record['device'] ?? 'device n/a'}',
        '${record['quality'] ?? record['qualityScore'] ?? 'unknown'} / ${record['orientation'] ?? 'orientation n/a'}',
        '${record['status'] ?? record['evidenceReviewStatus'] ?? 'pending'}',
      ],
    );
  }
}

class _IrisLearningCentre extends StatelessWidget {
  const _IrisLearningCentre({
    required this.learningCases,
    required this.reviewRecords,
    required this.query,
    required this.canManageIris,
    required this.onUpdateCandidateWorkflow,
  });

  final List<Map<String, dynamic>> learningCases;
  final List<Map<String, dynamic>> reviewRecords;
  final String query;
  final bool canManageIris;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateCandidateWorkflow;

  @override
  Widget build(BuildContext context) {
    final records = learningCases.isEmpty
        ? reviewRecords.where(_isLearningCandidate).toList()
        : learningCases;
    return _RecordModule(
      title: 'Learning Centre',
      subtitle:
          'Learning candidates, repeated mistakes, false positives, false negatives, drift, reviewer agreement and promotion history.',
      records: records,
      query: query,
      fields: const [
        'id',
        'deliveryId',
        'category',
        'misclassification',
        'learningStatus',
        'driftType',
        'reviewerAgreement',
        'status',
      ],
      columns: const ['Case', 'Signal', 'Agreement', 'Status'],
      row: (record) => [
        _recordId(record),
        '${record['misclassification'] ?? record['driftType'] ?? record['category'] ?? 'learning signal'}',
        '${record['reviewerAgreement'] ?? record['agreementScore'] ?? 'not measured'}',
        '${record['learningStatus'] ?? record['irisLearningQueueStatus'] ?? record['status'] ?? 'pending'}',
      ],
      actions: canManageIris
          ? (record) => [
              for (final action in const [
                ('Approve', 'approved'),
                ('Reject', 'rejected'),
                ('Promote', 'promoted'),
                ('Merge existing', 'merge_existing'),
                ('Save alias', 'save_alias'),
                ('Suspicious', 'suspicious'),
                ('History', 'history_reviewed'),
              ])
                _MiniAction(
                  label: action.$1,
                  onPressed: () =>
                      unawaited(onUpdateCandidateWorkflow(record, action.$2)),
                ),
            ]
          : null,
    );
  }
}

class _IrisPolicyCentre extends StatelessWidget {
  const _IrisPolicyCentre({required this.records});

  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) {
    return _RecordModule(
      title: 'Policy Centre',
      subtitle:
          'Reviewed policy records for confidence, escalation, auto approval, tolerance, evidence, SLA and override permissions.',
      records: records,
      query: '',
      fields: const [],
      columns: const ['Policy', 'Thresholds', 'Evidence/SLA', 'Review'],
      row: (record) => [
        '${record['name'] ?? record['policyName'] ?? _recordId(record)}',
        'confidence ${record['confidenceThreshold'] ?? 'n/a'} / weight ${record['weightTolerance'] ?? 'n/a'} / vehicle ${record['vehicleTolerance'] ?? 'n/a'}',
        '${record['evidenceRequirement'] ?? 'evidence n/a'} / ${record['reviewSla'] ?? 'SLA n/a'}',
        '${record['status'] ?? record['reviewStatus'] ?? 'draft'}',
      ],
    );
  }
}

class _IrisHealthPanel extends StatelessWidget {
  const _IrisHealthPanel({required this.records, required this.evidence});

  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> evidence;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'IRIS Health',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HealthChip(
                  'Queue depth',
                  records.where(_isIrisPending).length,
                ),
                _HealthChip('Failures', records.where(_hasIrisFailure).length),
                _HealthChip(
                  'Retries',
                  _countRecordsContaining(records, 'retry'),
                ),
                _HealthChip('Evidence growth', evidence.length),
                _HealthChip(
                  'Storage records',
                  evidence
                      .where(
                        (item) => '${item['storagePath'] ?? item['url'] ?? ''}'
                            .trim()
                            .isNotEmpty,
                      )
                      .length,
                ),
                _HealthChip(
                  'Active model',
                  _distinctValues(records, 'modelVersion').length,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IrisExportCentre extends StatelessWidget {
  const _IrisExportCentre({required this.records, required this.auditLogs});

  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> auditLogs;

  @override
  Widget build(BuildContext context) {
    return _RecordModule(
      title: 'Exports',
      subtitle:
          'Operational export scopes for CSV, PDF, accuracy, learning, reviewer and audit reports.',
      records: [
        {
          'id': 'operational-summary',
          'type': 'CSV/PDF',
          'records': records.length,
          'status': 'available',
        },
        {
          'id': 'accuracy-report',
          'type': 'CSV/PDF',
          'records': records.where((item) => _irisConfidence(item) > 0).length,
          'status': 'available',
        },
        {
          'id': 'learning-report',
          'type': 'CSV',
          'records': records.where(_isLearningCandidate).length,
          'status': 'available',
        },
        {
          'id': 'audit-report',
          'type': 'CSV/PDF',
          'records': _countIrisOverrides(auditLogs),
          'status': 'available',
        },
      ],
      query: '',
      fields: const [],
      columns: const ['Export', 'Format', 'Records', 'Status'],
      row: (record) => [
        '${record['id']}',
        '${record['type']}',
        '${record['records']}',
        '${record['status']}',
      ],
    );
  }
}

class _IrisAnalyticsPanel extends StatelessWidget {
  const _IrisAnalyticsPanel({
    required this.records,
    required this.auditLogs,
    required this.learningCases,
  });

  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> auditLogs;
  final List<Map<String, dynamic>> learningCases;

  @override
  Widget build(BuildContext context) {
    final categories = _categoryDistribution(records);
    final vehicles = _vehicleDistribution(records);
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'IRIS learning and recommendation analytics',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in categories.entries.take(8))
                  _HealthChip(entry.key, entry.value),
                for (final entry in vehicles.entries.take(8))
                  _HealthChip('Vehicle ${entry.key}', entry.value),
                _HealthChip('Overrides', _countIrisOverrides(auditLogs)),
                _HealthChip(
                  'Reviewer productivity',
                  _activeIrisReviewers(auditLogs).length,
                ),
                _HealthChip('Learning performance', learningCases.length),
                _HealthChip(
                  'Turnaround',
                  records.where((item) => !_isIrisPending(item)).length,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FinanceOperationsModule extends StatelessWidget {
  const _FinanceOperationsModule({
    required this.payments,
    required this.payoutRequests,
    required this.riderEarnings,
    required this.riderWalletTransactions,
    required this.wallets,
    required this.walletTransactions,
    required this.businessWallets,
    required this.businessInvoices,
    required this.businessRothPurchases,
    required this.deliveryTips,
    required this.ratings,
    required this.deliveries,
    required this.supportTickets,
    required this.auditLogs,
    required this.query,
    required this.canManageFinance,
    required this.onUpdateFinanceWorkflow,
    required this.onIssueRoth,
    required this.onSetWalletFrozen,
    required this.onProcessPayoutRequest,
    required this.onModerateRating,
  });

  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> payoutRequests;
  final List<Map<String, dynamic>> riderEarnings;
  final List<Map<String, dynamic>> riderWalletTransactions;
  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> walletTransactions;
  final List<Map<String, dynamic>> businessWallets;
  final List<Map<String, dynamic>> businessInvoices;
  final List<Map<String, dynamic>> businessRothPurchases;
  final List<Map<String, dynamic>> deliveryTips;
  final List<Map<String, dynamic>> ratings;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> auditLogs;
  final String query;
  final bool canManageFinance;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateFinanceWorkflow;
  final Future<void> Function(Map<String, dynamic>) onIssueRoth;
  final Future<void> Function(Map<String, dynamic>, bool) onSetWalletFrozen;
  final Future<void> Function(Map<String, dynamic>, String)
  onProcessPayoutRequest;
  final Future<void> Function(Map<String, dynamic>, String) onModerateRating;

  @override
  Widget build(BuildContext context) {
    final todayRevenue = _financeTotalToday(payments);
    final outstandingSettlements = payments
        .where(_isOutstandingSettlement)
        .length;
    final pendingRefunds = payments.where(_isPendingRefund).length;
    final failedPayments = payments.where(_isFailedPayment).length;
    final investigations = payments.where(_isFinanceInvestigation).length;
    final allFinanceRecords = [
      ...payments,
      ...payoutRequests,
      ...riderEarnings,
      ...riderWalletTransactions,
      ...wallets,
      ...walletTransactions,
      ...businessWallets,
      ...businessInvoices,
      ...businessRothPurchases,
      ...deliveryTips,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard("Today's revenue", _money(todayRevenue), 'payments'),
            _MetricCard(
              'Settlements',
              outstandingSettlements.toString(),
              'outstanding',
            ),
            _MetricCard(
              'Wallet liabilities',
              _money(_walletLiability(payments)),
              'loaded ledger',
            ),
            _MetricCard(
              'Roth circulation',
              _money(_rothTotal(payments)),
              'loaded records',
            ),
            _MetricCard('Pending refunds', pendingRefunds.toString(), 'review'),
            _MetricCard('Failed payments', failedPayments.toString(), 'failed'),
            _MetricCard('Investigations', investigations.toString(), 'open'),
            _MetricCard(
              'Stripe reconciliation',
              _stripeReconciliationStatus(payments),
              'status',
            ),
            _MetricCard(
              'Payout requests',
              '${payoutRequests.length}',
              'rider withdrawals',
            ),
            _MetricCard(
              'Rider earnings',
              '${riderEarnings.length}',
              'earnings records',
            ),
            _MetricCard(
              'Business invoices',
              '${businessInvoices.length}',
              'invoice records',
            ),
            _MetricCard(
              'Tips',
              _money(_tipsTotal(deliveryTips)),
              'delivery tips',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _FinanceAnalyticsPanel(
          payments: payments,
          payoutRequests: payoutRequests,
          riderEarnings: riderEarnings,
          walletTransactions: walletTransactions,
          businessInvoices: businessInvoices,
          businessRothPurchases: businessRothPurchases,
          deliveryTips: deliveryTips,
          ratings: ratings,
          deliveries: deliveries,
          supportTickets: supportTickets,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Wallet Explorer and Finance Review',
          subtitle:
              'Wallets, ledgers, payments, payout requests, rider earnings, business invoices, Roth purchases and tips.',
          records: allFinanceRecords,
          query: query,
          fields: const [
            'id',
            'walletId',
            'transactionId',
            'senderId',
            'riderId',
            'businessId',
            'deliveryId',
            'requestId',
            'paymentIntent',
            'stripePaymentIntentId',
            'status',
            'type',
            'financeReviewStatus',
          ],
          columns: const ['Record', 'Source', 'Amount', 'Review'],
          row: (record) => [
            _recordId(record),
            '${record['_collection'] ?? record['walletId'] ?? record['stripePaymentIntentId'] ?? record['paymentIntent'] ?? record['transactionId'] ?? 'Not recorded'}',
            _money(record['amount'] ?? record['total'] ?? record['price']),
            '${record['financeReviewStatus'] ?? record['refundReviewStatus'] ?? record['investigationStatus'] ?? 'unreviewed'}',
          ],
          actions: canManageFinance
              ? (record) => [
                  for (final action in const [
                    ('Assign', 'review_assigned'),
                    ('Reconcile', 'reconciled'),
                    ('Escalate', 'escalated'),
                    ('Credit review', 'wallet_credit_review'),
                    ('Debit review', 'wallet_debit_review'),
                    ('Issue Roth', 'roth_issue_review'),
                    ('Remove Roth', 'roth_remove_review'),
                    ('Approve refund', 'refund_approved'),
                    ('Reject refund', 'refund_rejected'),
                    ('Investigate', 'investigation_flagged'),
                    ('Resolve', 'investigation_resolved'),
                  ])
                    _MiniAction(
                      label: action.$1,
                      onPressed: () =>
                          unawaited(onUpdateFinanceWorkflow(record, action.$2)),
                    ),
                ]
              : null,
        ),
        const SizedBox(height: 18),
        _FinanceLedgerPanel(
          wallets: wallets,
          walletTransactions: walletTransactions,
          riderWalletTransactions: riderWalletTransactions,
          businessWallets: businessWallets,
          riderEarnings: riderEarnings,
          payoutRequests: payoutRequests,
          query: query,
          canManageFinance: canManageFinance,
          onIssueRoth: onIssueRoth,
          onSetWalletFrozen: onSetWalletFrozen,
          onProcessPayoutRequest: onProcessPayoutRequest,
        ),
        const SizedBox(height: 18),
        _BusinessFinancePanel(
          wallets: businessWallets,
          invoices: businessInvoices,
          rothPurchases: businessRothPurchases,
          query: query,
        ),
        const SizedBox(height: 18),
        _RatingsTipsModule(
          ratings: ratings,
          tips: deliveryTips,
          auditLogs: auditLogs,
          query: query,
          onModerateRating: onModerateRating,
        ),
      ],
    );
  }
}

class _FinanceAnalyticsPanel extends StatelessWidget {
  const _FinanceAnalyticsPanel({
    required this.payments,
    required this.payoutRequests,
    required this.riderEarnings,
    required this.walletTransactions,
    required this.businessInvoices,
    required this.businessRothPurchases,
    required this.deliveryTips,
    required this.ratings,
    required this.deliveries,
    required this.supportTickets,
  });

  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> payoutRequests;
  final List<Map<String, dynamic>> riderEarnings;
  final List<Map<String, dynamic>> walletTransactions;
  final List<Map<String, dynamic>> businessInvoices;
  final List<Map<String, dynamic>> businessRothPurchases;
  final List<Map<String, dynamic>> deliveryTips;
  final List<Map<String, dynamic>> ratings;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> supportTickets;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revenue, Roth and settlement analytics',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HealthChip('Orders', deliveries.length),
                _HealthChip('Fees', _countFinanceType(payments, 'fee')),
                _HealthChip('Refunds', _countFinanceType(payments, 'refund')),
                _HealthChip('Tips', _countFinanceType(payments, 'tip')),
                _HealthChip(
                  'Wallet usage',
                  _countFinanceType(payments, 'wallet'),
                ),
                _HealthChip('Roth usage', _countFinanceType(payments, 'roth')),
                _HealthChip(
                  'Business revenue',
                  _countRecordsContaining(deliveries, 'business'),
                ),
                _HealthChip(
                  'Health+ revenue',
                  _countRecordsContaining(deliveries, 'health'),
                ),
                _HealthChip(
                  'Gift revenue',
                  _countRecordsContaining(deliveries, 'gift'),
                ),
                _HealthChip('Payout requests', payoutRequests.length),
                _HealthChip('Rider earnings', riderEarnings.length),
                _HealthChip('Wallet ledger', walletTransactions.length),
                _HealthChip('Business invoices', businessInvoices.length),
                _HealthChip('Business Roth', businessRothPurchases.length),
                _HealthChip('Tips', deliveryTips.length),
                _HealthChip(
                  'Reported ratings',
                  ratings.where((rating) => _ratingReported(rating)).length,
                ),
                _HealthChip(
                  'Refund tickets',
                  supportTickets
                      .where((ticket) => '${ticket['type']}'.contains('refund'))
                      .length,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FinanceLedgerPanel extends StatelessWidget {
  const _FinanceLedgerPanel({
    required this.wallets,
    required this.walletTransactions,
    required this.riderWalletTransactions,
    required this.businessWallets,
    required this.riderEarnings,
    required this.payoutRequests,
    required this.query,
    required this.canManageFinance,
    required this.onIssueRoth,
    required this.onSetWalletFrozen,
    required this.onProcessPayoutRequest,
  });

  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> walletTransactions;
  final List<Map<String, dynamic>> riderWalletTransactions;
  final List<Map<String, dynamic>> businessWallets;
  final List<Map<String, dynamic>> riderEarnings;
  final List<Map<String, dynamic>> payoutRequests;
  final String query;
  final bool canManageFinance;
  final Future<void> Function(Map<String, dynamic>) onIssueRoth;
  final Future<void> Function(Map<String, dynamic>, bool) onSetWalletFrozen;
  final Future<void> Function(Map<String, dynamic>, String)
  onProcessPayoutRequest;

  @override
  Widget build(BuildContext context) {
    final ledgers = [
      ...walletTransactions,
      ...riderWalletTransactions,
      ...riderEarnings,
      ...payoutRequests,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RecordModule(
          title: 'Wallet Ledgers',
          subtitle:
              'Historical wallet, Rider earnings, Rider payout and ledger transaction records.',
          records: adminSearch(ledgers, query, const [
            'id',
            'walletId',
            'userId',
            'riderId',
            'transactionId',
            'type',
            'status',
          ]),
          query: '',
          fields: const [],
          columns: const ['Ledger', 'Owner', 'Amount', 'Status'],
          row: (record) => [
            '${record['transactionId'] ?? record['id']}',
            '${record['userId'] ?? record['riderId'] ?? record['walletId'] ?? 'Not recorded'}',
            _money(
              record['amount'] ??
                  record['availableBalance'] ??
                  record['balance'] ??
                  record['pendingAmount'],
            ),
            '${record['status'] ?? record['type'] ?? record['payoutStatus'] ?? 'recorded'}',
          ],
          actions: canManageFinance
              ? (record) {
                  final source = '${record['_collection'] ?? ''}';
                  if (source == 'payoutRequests') {
                    return [
                      _MiniAction(
                        label: 'Approve payout',
                        onPressed: () => unawaited(
                          onProcessPayoutRequest(record, 'approved'),
                        ),
                      ),
                      _MiniAction(
                        label: 'Reject payout',
                        onPressed: () => unawaited(
                          onProcessPayoutRequest(record, 'rejected'),
                        ),
                      ),
                    ];
                  }
                  return [
                    _MiniAction(
                      label: 'Issue Roth',
                      onPressed: () => unawaited(onIssueRoth(record)),
                    ),
                  ];
                }
              : null,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Wallet Accounts',
          subtitle: 'Sender, Rider and Business wallet records.',
          records: adminSearch(
            [...wallets, ...businessWallets],
            query,
            const [
              'id',
              'walletId',
              'userId',
              'businessId',
              'email',
              'walletType',
            ],
          ),
          query: '',
          fields: const [],
          columns: const ['Wallet', 'Owner', 'Type', 'Balance'],
          row: (record) => [
            '${record['walletId'] ?? record['id']}',
            '${record['userId'] ?? record['businessId'] ?? record['email'] ?? 'Not recorded'}',
            '${record['walletType'] ?? record['type'] ?? 'wallet'}',
            _money(
              record['balance'] ??
                  record['availableBalance'] ??
                  record['pendingBalance'],
            ),
          ],
          actions: canManageFinance
              ? (record) => [
                  _MiniAction(
                    label: 'Issue Roth',
                    onPressed: () => unawaited(onIssueRoth(record)),
                  ),
                  _MiniAction(
                    label: 'Freeze',
                    onPressed: () => unawaited(onSetWalletFrozen(record, true)),
                  ),
                  _MiniAction(
                    label: 'Unfreeze',
                    onPressed: () =>
                        unawaited(onSetWalletFrozen(record, false)),
                  ),
                ]
              : null,
        ),
      ],
    );
  }
}

class _BusinessFinancePanel extends StatelessWidget {
  const _BusinessFinancePanel({
    required this.wallets,
    required this.invoices,
    required this.rothPurchases,
    required this.query,
  });

  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>> rothPurchases;
  final String query;

  @override
  Widget build(BuildContext context) {
    final records = [...wallets, ...invoices, ...rothPurchases];
    return _RecordModule(
      title: 'Business Finance',
      subtitle:
          'Historical Business wallets, invoices and Business Roth purchase records.',
      records: adminSearch(records, query, const [
        'id',
        'businessId',
        'businessName',
        'invoiceStatus',
        'billingEmail',
        'walletType',
        'reason',
      ]),
      query: '',
      fields: const [],
      columns: const ['Business record', 'Business', 'Amount', 'Status'],
      row: (record) => [
        '${record['invoiceId'] ?? record['walletId'] ?? record['id']}',
        '${record['businessName'] ?? record['businessId'] ?? record['billingEmail'] ?? 'Business'}',
        _money(record['amount'] ?? record['total'] ?? record['balance']),
        '${record['invoiceStatus'] ?? record['status'] ?? record['walletType'] ?? 'recorded'}',
      ],
    );
  }
}

class _RatingsTipsModule extends StatelessWidget {
  const _RatingsTipsModule({
    required this.ratings,
    required this.tips,
    required this.auditLogs,
    required this.query,
    required this.onModerateRating,
  });

  final List<Map<String, dynamic>> ratings;
  final List<Map<String, dynamic>> tips;
  final List<Map<String, dynamic>> auditLogs;
  final String query;
  final Future<void> Function(Map<String, dynamic>, String) onModerateRating;

  @override
  Widget build(BuildContext context) {
    final tipByDelivery = {
      for (final tip in tips) '${tip['deliveryId'] ?? tip['id']}': tip,
    };
    final records = ratings
        .map(
          (rating) => AdminRatingTipRecord.fromBackend(
            ratingId: _recordId(rating),
            rating: rating,
            tip:
                tipByDelivery['${rating['deliveryId'] ?? _recordId(rating)}'] ??
                const {},
          ),
        )
        .toList(growable: false);
    final visible = AdminRatingsTipsPolicy.filter(records, search: query);
    final tipped = records.where((record) => record.tipped).length;
    final reported = records.where((record) => record.reported).length;
    final avgStars = records.isEmpty
        ? 0.0
        : records.fold<num>(0, (total, record) => total + record.stars) /
              records.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard('Ratings', '${records.length}', 'loaded reviews'),
            _MetricCard(
              'Average stars',
              avgStars.toStringAsFixed(1),
              'driver ratings',
            ),
            _MetricCard('Tips', '$tipped', _money(_tipsTotal(tips))),
            _MetricCard('Reported', '$reported', 'needs moderation'),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Ratings & Tips Management',
          subtitle:
              'Historical review moderation, reported ratings, tip review, filters and audit visibility.',
          records: [
            for (final record in visible)
              {
                'id': record.ratingId,
                'deliveryId': record.deliveryId,
                'riderId': record.riderId,
                'senderId': record.senderId,
                'stars': record.stars,
                'feedback': record.feedback,
                'tipAmount': record.tipAmount,
                'paymentMethod': record.paymentMethod,
                'reportStatus': record.reportStatus,
                'timestamp': record.timestamp,
              },
          ],
          query: '',
          fields: const [],
          columns: const ['Rating', 'Rider/Sender', 'Tip', 'Report'],
          row: (record) => [
            '${record['stars']}★ / ${record['deliveryId']}',
            '${record['riderId']} / ${record['senderId']}',
            _money(record['tipAmount']),
            '${record['reportStatus'] ?? 'clear'}',
          ],
          actions: (record) => [
            _MiniAction(
              label: 'Investigate',
              onPressed: () =>
                  unawaited(onModerateRating(record, 'investigate')),
            ),
            _MiniAction(
              label: 'Hide',
              onPressed: () => unawaited(onModerateRating(record, 'hide')),
            ),
            _MiniAction(
              label: 'Unhide',
              onPressed: () => unawaited(onModerateRating(record, 'unhide')),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Ratings Audit',
          subtitle: 'Historical audit records linked to ratings and tips.',
          records: auditLogs
              .where((log) => _hasAnyText(log, const ['rating', 'tip']))
              .toList(growable: false),
          query: '',
          fields: const [],
          columns: const ['Action', 'Record', 'Operator', 'Reason'],
          row: (record) => [
            '${record['actionType'] ?? 'rating_action'}',
            '${record['recordType'] ?? ''}/${record['recordId'] ?? record['id']}',
            '${record['adminUserId'] ?? 'admin'}',
            '${record['reason'] ?? ''}',
          ],
        ),
      ],
    );
  }
}

class _RiderOperationsModule extends StatelessWidget {
  const _RiderOperationsModule({
    required this.riders,
    required this.deliveries,
    required this.documents,
    required this.driverPerformanceMetrics,
    required this.auditLogs,
    required this.adminNotes,
    required this.ratings,
    required this.payments,
    required this.query,
    required this.canManageRiders,
    required this.onOpenRiderProfile,
    required this.onSetRiderStatus,
    required this.onSyncRiderStripe,
    required this.onResetRiderStripe,
    required this.onRequestMoreInformation,
    required this.onReviewDocument,
    required this.onRemoveProfilePhoto,
    required this.onStartRiderConversation,
  });

  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> driverPerformanceMetrics;
  final List<Map<String, dynamic>> auditLogs;
  final List<Map<String, dynamic>> adminNotes;
  final List<Map<String, dynamic>> ratings;
  final List<Map<String, dynamic>> payments;
  final String query;
  final bool canManageRiders;
  final ValueChanged<Map<String, dynamic>> onOpenRiderProfile;
  final Future<void> Function(Map<String, dynamic>, String) onSetRiderStatus;
  final Future<void> Function(Map<String, dynamic>) onSyncRiderStripe;
  final Future<void> Function(Map<String, dynamic>) onResetRiderStripe;
  final Future<void> Function(Map<String, dynamic>) onRequestMoreInformation;
  final Future<void> Function(Map<String, dynamic>, String) onReviewDocument;
  final Future<void> Function(Map<String, dynamic>) onRemoveProfilePhoto;
  final Future<void> Function(Map<String, dynamic>) onStartRiderConversation;

  @override
  Widget build(BuildContext context) {
    final online = riders.where(_isOnlineRider).length;
    final suspended = riders.where(_isSuspendedRider).length;
    final pending = riders.where(_isPendingRiderRecord).length;
    final busy = riders.where((rider) {
      final id = _riderId(rider);
      return deliveries.any(
        (delivery) =>
            _deliveryBelongsToRider(delivery, id) &&
            _isActiveDelivery(delivery),
      );
    }).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard('Riders', riders.length.toString(), 'loaded profiles'),
            _MetricCard('Online', online.toString(), 'available now'),
            _MetricCard('Busy', busy.toString(), 'active delivery'),
            _MetricCard(
              'Offline',
              (riders.length - online).toString(),
              'not currently online',
            ),
            _MetricCard('Suspended', suspended.toString(), 'restricted'),
            _MetricCard('Pending', pending.toString(), 'verification review'),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Rider Operations',
          subtitle:
              'Search riders by identity, contact, vehicle, registration, city, verification and trust.',
          records: riders,
          query: query,
          fields: const [
            'id',
            'uid',
            'riderId',
            'driverId',
            'fullName',
            'name',
            'email',
            'phone',
            'phoneNumber',
            'vehicleType',
            'vehicle',
            'plateNumber',
            'vehicleRegistration',
            'city',
            'status',
            'driverStatus',
            'approvalStatus',
            'verificationStatus',
            'trustTier',
            'rank',
            'riderRank',
          ],
          columns: const ['Rider', 'State', 'Vehicle', 'Monitoring'],
          row: (record) => [
            '${record['fullName'] ?? record['name'] ?? _riderId(record)}\n${record['email'] ?? record['phoneNumber'] ?? ''}',
            '${record['approvalStatus'] ?? record['driverStatus'] ?? record['status'] ?? 'pending'} / ${record['verificationStatus'] ?? 'pending'}',
            '${record['vehicleType'] ?? record['vehicle'] ?? 'Vehicle'} ${record['plateNumber'] ?? record['vehicleRegistration'] ?? ''}',
            _riderMonitoringSummary(record, deliveries, payments),
          ],
          actions: canManageRiders
              ? (record) => _riderActions(
                  record,
                  onSetRiderStatus,
                  onOpenRiderProfile,
                  onSyncRiderStripe: onSyncRiderStripe,
                  onResetRiderStripe: onResetRiderStripe,
                  onRequestMoreInformation: onRequestMoreInformation,
                  onRemoveProfilePhoto: onRemoveProfilePhoto,
                  onStartRiderConversation: onStartRiderConversation,
                )
              : null,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Rider document review',
          subtitle:
              'Insurance, MOT, V5C and identity document signals from loaded Rider records.',
          records: documents,
          query: query,
          fields: const [
            'id',
            'riderId',
            'driverId',
            'uid',
            'type',
            'documentType',
            'status',
            'verificationStatus',
            'vehicleRegistration',
          ],
          columns: const ['Document', 'Rider', 'Status', 'Updated'],
          row: (record) => [
            '${record['type'] ?? record['documentType'] ?? 'Document'}',
            '${record['riderId'] ?? record['driverId'] ?? record['uid'] ?? 'unknown'}',
            '${record['status'] ?? record['verificationStatus'] ?? 'pending'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canManageRiders
              ? (record) => [
                  _MiniAction(
                    label: 'Approve',
                    onPressed: () =>
                        unawaited(onReviewDocument(record, 'approved')),
                  ),
                  _MiniAction(
                    label: 'Reject',
                    onPressed: () =>
                        unawaited(onReviewDocument(record, 'rejected')),
                  ),
                  _MiniAction(
                    label: 'Request replacement',
                    onPressed: () => unawaited(
                      onReviewDocument(record, 'replacement_requested'),
                    ),
                  ),
                ]
              : null,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Rider Performance Metrics',
          subtitle:
              'Historical driverPerformanceMetrics workspace with acceptance, completion, cancellation, late arrival, trust, rank, warnings, history and audit.',
          records: driverPerformanceMetrics,
          query: query,
          fields: const [
            'id',
            'riderId',
            'driverId',
            'uid',
            'fullName',
            'acceptanceRate',
            'completionRate',
            'cancellationRate',
            'lateArrivals',
            'trustHistory',
            'rankHistory',
            'rank',
            'riderRank',
            'lowRatingFlag',
            'operationalWarnings',
          ],
          columns: const ['Rider', 'Performance', 'Trust / Rank', 'Warnings'],
          row: (record) => [
            '${_riderNameForMetric(record)}\n${_metricRiderId(record)}',
            'Accept ${_percent(record['acceptanceRate'])} / Complete ${_percent(record['completionRate'])}\nCancel ${_percent(record['cancellationRate'])} / Late ${record['lateArrivals'] ?? record['lateArrivalCount'] ?? 0}',
            '${record['trustTier'] ?? record['trustLevel'] ?? 'standard'} / ${record['rank'] ?? record['riderRank'] ?? 'unranked'}\nHistory ${_historyCount(record['trustHistory']) + _historyCount(record['rankHistory'])}',
            _riderWarningSummary(record),
          ],
          actions: canManageRiders
              ? (record) => [
                  _MiniAction(
                    label: 'Review',
                    onPressed: () => unawaited(
                      onSetRiderStatus(
                        _riderForMetric(record),
                        'performance_review',
                      ),
                    ),
                  ),
                  _MiniAction(
                    label: 'Warn',
                    onPressed: () => unawaited(
                      onSetRiderStatus(
                        _riderForMetric(record),
                        'warning_issued',
                      ),
                    ),
                  ),
                  _MiniAction(
                    label: 'Suspend',
                    onPressed: () => unawaited(
                      onSetRiderStatus(_riderForMetric(record), 'suspended'),
                    ),
                  ),
                ]
              : null,
        ),
        const SizedBox(height: 18),
        _RiderOperationsHistoryPanel(
          auditLogs: auditLogs,
          adminNotes: adminNotes,
          query: query,
        ),
      ],
    );
  }

  String _metricRiderId(Map<String, dynamic> record) =>
      '${record['riderId'] ?? record['driverId'] ?? record['uid'] ?? record['id'] ?? ''}'
          .trim();

  Map<String, dynamic> _riderForMetric(Map<String, dynamic> metric) {
    final id = _metricRiderId(metric);
    return riders.firstWhere(
      (rider) => _riderId(rider) == id,
      orElse: () => {'id': id, ...metric},
    );
  }

  String _riderNameForMetric(Map<String, dynamic> metric) {
    final rider = _riderForMetric(metric);
    return '${rider['fullName'] ?? rider['name'] ?? metric['fullName'] ?? 'Rider'}';
  }

  int _historyCount(Object? value) => value is List ? value.length : 0;

  String _riderWarningSummary(Map<String, dynamic> record) {
    final warnings = <String>[];
    if (record['lowRatingFlag'] == true) warnings.add('Low rating');
    if (record['trustReviewRequired'] == true) warnings.add('Trust review');
    final operational = record['operationalWarnings'];
    if (operational is List && operational.isNotEmpty) {
      warnings.add('${operational.length} operational');
    }
    if (warnings.isEmpty) return 'No active warnings';
    return warnings.join(' / ');
  }
}

class _RiderOperationsHistoryPanel extends StatelessWidget {
  const _RiderOperationsHistoryPanel({
    required this.auditLogs,
    required this.adminNotes,
    required this.query,
  });

  final List<Map<String, dynamic>> auditLogs;
  final List<Map<String, dynamic>> adminNotes;
  final String query;

  @override
  Widget build(BuildContext context) {
    final riderAudit = auditLogs
        .where(
          (record) =>
              '${record['recordType'] ?? record['actionType'] ?? record['action'] ?? ''}'
                  .toLowerCase()
                  .contains('rider') ||
              '${record['recordType'] ?? record['actionType'] ?? record['action'] ?? ''}'
                  .toLowerCase()
                  .contains('driver'),
        )
        .toList(growable: false);
    final riderNotes = adminNotes
        .where(
          (record) =>
              '${record['subjectType'] ?? record['recordType'] ?? ''}'
                  .toLowerCase()
                  .contains('rider') ||
              '${record['subjectType'] ?? record['recordType'] ?? ''}'
                  .toLowerCase()
                  .contains('driver'),
        )
        .toList(growable: false);
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rider operational history',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HealthChip('Audit events', riderAudit.length),
                _HealthChip('Operational notes', riderNotes.length),
                _HealthChip(
                  'Warnings',
                  riderAudit
                      .where(
                        (record) =>
                            '${record['actionType'] ?? record['action'] ?? ''}'
                                .toLowerCase()
                                .contains('warning'),
                      )
                      .length,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _RecordModule(
              title: 'Rider audit and notes',
              subtitle:
                  'Performance reviews, operational notes, warnings, status changes and historical Rider management.',
              records: [...riderAudit, ...riderNotes],
              query: query,
              fields: const [
                'id',
                'recordId',
                'riderId',
                'driverId',
                'subjectId',
                'action',
                'actionType',
                'note',
                'body',
                'reason',
                'adminEmail',
              ],
              columns: const ['Type', 'Rider', 'Operator', 'Time'],
              row: (record) => [
                '${record['actionType'] ?? record['action'] ?? record['noteType'] ?? 'operational_note'}\n${record['reason'] ?? record['note'] ?? record['body'] ?? ''}',
                '${record['recordId'] ?? record['riderId'] ?? record['driverId'] ?? record['subjectId'] ?? ''}',
                '${record['adminEmail'] ?? record['operatorEmail'] ?? record['adminId'] ?? 'admin'}',
                _date(record['createdAt'] ?? record['timestamp']),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryOperationsModule extends StatelessWidget {
  const _DeliveryOperationsModule({
    required this.deliveries,
    required this.riders,
    required this.query,
    required this.canDuplicateDeliveries,
    required this.canEditDeliveries,
    required this.onOpenDelivery,
    required this.onDuplicateDelivery,
    required this.onSetDeliveryOperationStatus,
    required this.onResolveStaleDeliveryLock,
    required this.onArchiveDelivery,
  });

  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> riders;
  final String query;
  final bool canDuplicateDeliveries;
  final bool canEditDeliveries;
  final ValueChanged<Map<String, dynamic>> onOpenDelivery;
  final ValueChanged<Map<String, dynamic>> onDuplicateDelivery;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetDeliveryOperationStatus;
  final Future<void> Function(Map<String, dynamic>) onResolveStaleDeliveryLock;
  final Future<void> Function(Map<String, dynamic>) onArchiveDelivery;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final active = deliveries.where(_isActiveDelivery).length;
    final waiting = deliveries.where(_isWaitingDelivery).length;
    final noShow = deliveries.where(_isNoShowDelivery).length;
    final completedToday = deliveries
        .where((item) => _isCompletedDelivery(item) && _isSameDay(item, today))
        .length;
    final cancelledToday = deliveries
        .where((item) => _isCancelledDelivery(item) && _isSameDay(item, today))
        .length;
    final delayed = deliveries.where(_isDelayedDelivery).length;
    final stale = deliveries.where(_isStaleDelivery).toList();
    final recoverable = deliveries.where(_isRecoverableDelivery).toList();
    final archived = deliveries.where(_isArchivedDelivery).toList();
    final enhancedCustody = deliveries
        .where(_needsEnhancedCustodyReview)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard('Active', active.toString(), 'live deliveries'),
            _MetricCard('Waiting', waiting.toString(), 'pickup/dropoff'),
            _MetricCard('No-show', noShow.toString(), 'review required'),
            _MetricCard(
              'Completed today',
              completedToday.toString(),
              'successful',
            ),
            _MetricCard(
              'Cancelled today',
              cancelledToday.toString(),
              'cancelled',
            ),
            _MetricCard('Delayed', delayed.toString(), 'late or escalated'),
            _MetricCard(
              'Stale locks',
              stale.length.toString(),
              'historical recovery queue',
            ),
            _MetricCard(
              'Recoverable',
              recoverable.length.toString(),
              'can re-enter operations',
            ),
            _MetricCard(
              'Health+',
              _countFlag(deliveries, 'health').toString(),
              'medical',
            ),
            _MetricCard(
              'Business',
              _countFlag(deliveries, 'business').toString(),
              'business',
            ),
            _MetricCard(
              'Gift',
              _countFlag(deliveries, 'gift').toString(),
              'gift orders',
            ),
            _MetricCard(
              'Vanguard',
              deliveries.where(_hasVanguardProtection).length.toString(),
              'protected',
            ),
            _MetricCard(
              'Enhanced custody',
              enhancedCustody.length.toString(),
              'review path',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _LiveDeliveryMapPanel(deliveries: deliveries, riders: riders),
        const SizedBox(height: 18),
        _EnhancedCustodyReviewPanel(
          records: enhancedCustody,
          query: query,
          canEditDeliveries: canEditDeliveries,
          onOpenDelivery: onOpenDelivery,
          onSetStatus: onSetDeliveryOperationStatus,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Stale Delivery Lock Queue',
          subtitle:
              'Historical stale-lock recovery workflow using resolveStaleDeliveryLock.',
          records: stale,
          query: query,
          fields: const [
            'id',
            'requestId',
            'trackingId',
            'status',
            'deliveryStatus',
            'lockStatus',
            'adminOperationStatus',
            'senderName',
            'riderId',
          ],
          columns: const ['Delivery', 'State', 'Lock', 'Updated'],
          row: (record) => [
            _recordId(record),
            '${record['status'] ?? record['deliveryStatus'] ?? 'unknown'}',
            '${record['lockStatus'] ?? record['staleLockStatus'] ?? record['adminOperationStatus'] ?? 'stale'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: (record) => [
            _MiniAction(
              label: 'Details',
              onPressed: () => onOpenDelivery(record),
            ),
            if (canEditDeliveries)
              _MiniAction(
                label: 'Resolve lock',
                onPressed: () => unawaited(onResolveStaleDeliveryLock(record)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Recoverable and Archived Deliveries',
          subtitle:
              'Recoverable records and historical archive filters from delivery operations.',
          records: [...recoverable, ...archived],
          query: query,
          fields: const [
            'id',
            'requestId',
            'trackingId',
            'status',
            'deliveryStatus',
            'adminArchiveStatus',
            'archivedByAdminEmail',
            'archiveReason',
          ],
          columns: const ['Delivery', 'State', 'Archive', 'Updated'],
          row: (record) => [
            _recordId(record),
            '${record['status'] ?? record['deliveryStatus'] ?? 'unknown'}',
            '${record['adminArchiveStatus'] ?? record['archiveStatus'] ?? 'recoverable'}',
            _date(record['archivedAt'] ?? record['updatedAt']),
          ],
          actions: (record) => [
            _MiniAction(
              label: 'Details',
              onPressed: () => onOpenDelivery(record),
            ),
            if (canEditDeliveries && !_isArchivedDelivery(record))
              _MiniAction(
                label: 'Archive',
                onPressed: () => unawaited(onArchiveDelivery(record)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Delivery Operations',
          subtitle:
              'Search by tracking id, sender, recipient, rider, business, phone, status, service, payment and review flags.',
          records: deliveries,
          query: query,
          fields: const [
            'id',
            'requestId',
            'trackingId',
            'status',
            'deliveryStatus',
            'service',
            'serviceType',
            'senderName',
            'senderEmail',
            'recipientName',
            'recipientPhone',
            'riderId',
            'assignedRiderId',
            'businessName',
            'businessId',
            'paymentStatus',
            'irisReviewStatus',
            'waitingReviewStatus',
            'noShowReviewStatus',
          ],
          columns: const ['ID', 'Route', 'Status', 'Flags'],
          row: (record) => [
            _recordId(record),
            '${record['pickupAddress'] ?? record['pickup'] ?? 'Pickup'} -> ${record['dropoffAddress'] ?? record['dropoff'] ?? 'Dropoff'}',
            '${record['status'] ?? record['deliveryStatus'] ?? 'unknown'} / ${record['paymentStatus'] ?? 'payment unknown'}',
            _deliveryFlagSummary(record),
          ],
          actions: (record) => _deliveryActions(
            record,
            canDuplicateDeliveries: canDuplicateDeliveries,
            canEditDeliveries: canEditDeliveries,
            onOpen: onOpenDelivery,
            onDuplicate: onDuplicateDelivery,
            onSetStatus: onSetDeliveryOperationStatus,
            onResolveStaleDeliveryLock: onResolveStaleDeliveryLock,
            onArchiveDelivery: onArchiveDelivery,
          ),
        ),
      ],
    );
  }
}

class _EnhancedCustodyReviewPanel extends StatelessWidget {
  const _EnhancedCustodyReviewPanel({
    required this.records,
    required this.query,
    required this.canEditDeliveries,
    required this.onOpenDelivery,
    required this.onSetStatus,
  });

  final List<Map<String, dynamic>> records;
  final String query;
  final bool canEditDeliveries;
  final ValueChanged<Map<String, dynamic>> onOpenDelivery;
  final Future<void> Function(Map<String, dynamic>, String) onSetStatus;

  @override
  Widget build(BuildContext context) {
    return _RecordModule(
      title: 'Enhanced Custody Review',
      subtitle:
          'Vanguard custody chain, checkpoint evidence, transfer history, exceptions and Admin review status.',
      records: records,
      query: query,
      fields: const [
        'id',
        'requestId',
        'trackingId',
        'senderName',
        'recipientName',
        'riderId',
        'assignedRiderId',
        'vanguardCustodyReviewStatus',
        'vanguardCustodyEvidenceStatus',
        'custodyIntegrityStatus',
        'chainOfCustodyStatus',
        'proofTimelineStatus',
      ],
      columns: const ['Delivery', 'Custody', 'Evidence', 'Checkpoint'],
      row: (record) => [
        _recordId(record),
        _enhancedCustodyStatus(record),
        _enhancedCustodyEvidenceSummary(record),
        _enhancedCustodyCheckpointSummary(record),
      ],
      actions: (record) => [
        _MiniAction(label: 'Details', onPressed: () => onOpenDelivery(record)),
        if (canEditDeliveries) ...[
          _MiniAction(
            label: 'Flag concern',
            onPressed: () =>
                unawaited(onSetStatus(record, 'vanguard_custody_flagged')),
          ),
          _MiniAction(
            label: 'Escalate',
            onPressed: () =>
                unawaited(onSetStatus(record, 'vanguard_custody_escalated')),
          ),
          _MiniAction(
            label: 'Request evidence',
            onPressed: () =>
                unawaited(onSetStatus(record, 'vanguard_evidence_requested')),
          ),
          _MiniAction(
            label: 'Assign reviewer',
            onPressed: () =>
                unawaited(onSetStatus(record, 'vanguard_reviewer_assigned')),
          ),
          _MiniAction(
            label: 'Close review',
            onPressed: () =>
                unawaited(onSetStatus(record, 'vanguard_custody_closed')),
          ),
        ],
      ],
    );
  }
}

class _LiveDeliveryMapPanel extends StatelessWidget {
  const _LiveDeliveryMapPanel({required this.deliveries, required this.riders});

  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> riders;

  @override
  Widget build(BuildContext context) {
    final live = deliveries.where(_isActiveDelivery).take(8).toList();
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Live delivery map',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Operational route view using loaded pickup, dropoff and rider location metadata.',
              style: TextStyle(color: Colors.white.withValues(alpha: .66)),
            ),
            const SizedBox(height: 16),
            if (live.isEmpty)
              Text(
                'No active delivery locations loaded.',
                style: TextStyle(color: Colors.white.withValues(alpha: .62)),
              )
            else
              for (final delivery in live)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.route_rounded, color: Color(0xFF7DD3FC)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_recordId(delivery)}: ${delivery['pickupAddress'] ?? 'Pickup'} -> ${delivery['dropoffAddress'] ?? 'Dropoff'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _StatusPill(
                        label:
                            '${delivery['status'] ?? delivery['deliveryStatus'] ?? 'active'}',
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.metrics, required this.data});

  final AdminMetricSnapshot metrics;
  final AdminDataBundle data;

  @override
  Widget build(BuildContext context) {
    final health = AdminPlatformHealthSnapshot.fromData(
      deliveries: data.deliveries,
      payments: data.payments,
      supportTickets: data.supportTickets,
      healthPlusPickups: data.healthPlusPickups,
      businessAccounts: data.businessAccounts,
      giftOrders: data.giftOrders,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(
              'Deliveries',
              metrics.totalDeliveries.toString(),
              '${metrics.activeDeliveries} active',
            ),
            _MetricCard(
              'Completed',
              metrics.completedDeliveries.toString(),
              '${metrics.cancelledDeliveries} cancelled',
            ),
            _MetricCard(
              'Senders',
              metrics.totalSenders.toString(),
              '${metrics.activeSenders} active',
            ),
            _MetricCard(
              'Riders',
              metrics.totalDrivers.toString(),
              '${metrics.pendingDrivers} pending',
            ),
            _MetricCard(
              'Revenue today',
              _money(metrics.revenueToday),
              '${_money(metrics.revenueThisMonth)} month',
            ),
            _MetricCard(
              'Support',
              metrics.unresolvedSupportIssues.toString(),
              'unresolved',
            ),
            _MetricCard(
              'Wallet review',
              health.walletReviewItems.toString(),
              'payments and payouts',
            ),
            _MetricCard(
              'Platform health',
              health.status,
              '${health.alerts.length} active alerts',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _PlatformHealthPanel(health: health),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Realtime monitoring',
          subtitle:
              'Live delivery, support, finance, Health+, Business and Gifts signals.',
          records: _platformPulseRecords(data),
          query: '',
          fields: const [],
          columns: const ['Signal', 'Domain', 'Status', 'Updated'],
          row: (record) => [
            '${record['label'] ?? _recordId(record)}',
            '${record['domain'] ?? 'Platform'}',
            '${record['status'] ?? 'open'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
        ),
      ],
    );
  }
}

class _PlatformHealthPanel extends StatelessWidget {
  const _PlatformHealthPanel({required this.health});

  final AdminPlatformHealthSnapshot health;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.monitor_heart_rounded,
                  color: Color(0xFF7DD3FC),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Live platform health',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                _StatusPill(label: health.status),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HealthChip('Jobs', health.activeJobs),
                _HealthChip('Waiting', health.waitingJobs),
                _HealthChip('Vanguard', health.vanguardJobs),
                _HealthChip('IRIS reviews', health.discrepancyReviews),
                _HealthChip('Support', health.supportOpen),
                _HealthChip('Health+', health.healthPlusOpen),
                _HealthChip('Business', health.businessPending),
                _HealthChip('Gifts', health.giftsPending),
              ],
            ),
            const SizedBox(height: 16),
            if (health.alerts.isEmpty)
              Text(
                'No platform alerts from the currently loaded records.',
                style: TextStyle(color: Colors.white.withValues(alpha: .68)),
              )
            else
              Column(
                children: [
                  for (final alert in health.alerts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PlatformAlertRow(alert: alert),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _HealthChip extends StatelessWidget {
  const _HealthChip(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: Colors.white.withValues(alpha: .08),
      side: BorderSide(color: Colors.white.withValues(alpha: .12)),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Critical' => const Color(0xFFF87171),
      'Watch' => const Color(0xFFFBBF24),
      _ => const Color(0xFF34D399),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _PlatformAlertRow extends StatelessWidget {
  const _PlatformAlertRow({required this.alert});

  final AdminPlatformAlert alert;

  @override
  Widget build(BuildContext context) {
    final icon = switch (alert.severity) {
      'critical' => Icons.error_rounded,
      'warning' => Icons.warning_amber_rounded,
      _ => Icons.info_rounded,
    };
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF7DD3FC)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                alert.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                alert.detail,
                style: TextStyle(color: Colors.white.withValues(alpha: .66)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

List<Map<String, dynamic>> _platformPulseRecords(AdminDataBundle data) {
  return [
    for (final delivery in data.deliveries.take(5))
      {...delivery, 'label': _recordId(delivery), 'domain': 'Delivery'},
    for (final ticket in data.supportTickets.take(4))
      {...ticket, 'label': _recordId(ticket), 'domain': 'Support'},
    for (final payment in data.payments.take(4))
      {...payment, 'label': _recordId(payment), 'domain': 'Finance'},
    for (final pickup in data.healthPlusPickups.take(3))
      {...pickup, 'label': _recordId(pickup), 'domain': 'Health+'},
    for (final business in data.businessAccounts.take(3))
      {
        ...business,
        'label':
            business['businessName'] ??
            business['companyName'] ??
            _recordId(business),
        'domain': 'Business',
      },
    for (final gift in data.giftOrders.take(3))
      {
        ...gift,
        'label': gift['giftName'] ?? gift['title'] ?? _recordId(gift),
        'domain': 'Gifts',
      },
  ];
}

class _ChatModule extends StatelessWidget {
  const _ChatModule({
    required this.records,
    required this.messageReports,
    required this.selectedChatMessages,
    required this.query,
    required this.message,
    required this.selectedChat,
    required this.onSelectChat,
    required this.onSendChatMessage,
    required this.onResolveMessageReport,
  });

  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> messageReports;
  final List<Map<String, dynamic>> selectedChatMessages;
  final String query;
  final TextEditingController message;
  final Map<String, dynamic>? selectedChat;
  final ValueChanged<Map<String, dynamic>> onSelectChat;
  final VoidCallback onSendChatMessage;
  final Future<void> Function(Map<String, dynamic>, String)
  onResolveMessageReport;

  @override
  Widget build(BuildContext context) {
    final selectedId = selectedChat == null ? '' : _recordId(selectedChat!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RecordModule(
          title: 'Chat',
          subtitle: 'Admin-visible booking and support chat threads.',
          records: records,
          query: query,
          fields: const ['id', 'threadId', 'lastMessage', 'type'],
          columns: const ['Thread', 'Type', 'Last message', 'Updated'],
          row: (record) => [
            '${record['threadId'] ?? record['id']}',
            '${record['type'] ?? record['conversationType'] ?? 'chat'}',
            '${record['lastMessage'] ?? ''}',
            _date(
              record['updatedAt'] ??
                  record['lastMessageAt'] ??
                  record['lastMessageTimestamp'],
            ),
          ],
          actions: (record) => [
            _MiniAction(
              label: selectedId == _recordId(record) ? 'Selected' : 'Reply',
              onPressed: () => onSelectChat(record),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Message Report Queue',
          subtitle:
              'Historical reported-message review, message context and resolution workflow.',
          records: messageReports,
          query: query,
          fields: const [
            'id',
            'chatId',
            'conversationId',
            'messageId',
            'reporterId',
            'reportedUserId',
            'reason',
            'status',
          ],
          columns: const ['Report', 'Context', 'Parties', 'Status'],
          row: (record) => [
            _recordId(record),
            '${record['chatId'] ?? record['conversationId'] ?? ''}\n${record['messageId'] ?? record['messagePreview'] ?? ''}',
            'Reporter: ${record['reporterId'] ?? 'unknown'}\nReported: ${record['reportedUserId'] ?? record['offenderId'] ?? 'unknown'}',
            '${record['reviewStatus'] ?? record['status'] ?? 'open'}',
          ],
          actions: (record) => [
            _MiniAction(
              label: 'Select chat',
              onPressed: () {
                final chatId =
                    '${record['chatId'] ?? record['conversationId'] ?? ''}'
                        .trim();
                if (chatId.isNotEmpty) {
                  onSelectChat({'id': chatId, 'threadId': chatId});
                }
              },
            ),
            for (final action in const [
              ('Resolve', 'resolved'),
              ('Dismiss', 'dismissed'),
              ('Escalate', 'escalated'),
            ])
              _MiniAction(
                label: action.$1,
                onPressed: () =>
                    unawaited(onResolveMessageReport(record, action.$2)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _ChatMessageHistoryPanel(
          selectedChat: selectedChat,
          messages: selectedChatMessages,
          query: query,
        ),
        const SizedBox(height: 18),
        DecoratedBox(
          decoration: _panelDecoration(),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.reply_rounded, color: Color(0xFF7DD3FC)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Composer',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            selectedChat == null
                                ? 'Select a chat thread to reply.'
                                : 'Replying to ${_recordId(selectedChat!)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .66),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: message,
                  enabled: selectedChat != null,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Write an Admin reply...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: selectedChat == null ? null : onSendChatMessage,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Send reply'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatMessageHistoryPanel extends StatelessWidget {
  const _ChatMessageHistoryPanel({
    required this.selectedChat,
    required this.messages,
    required this.query,
  });

  final Map<String, dynamic>? selectedChat;
  final List<Map<String, dynamic>> messages;
  final String query;

  @override
  Widget build(BuildContext context) {
    final filtered = adminSearch(messages, query, const [
      'id',
      'text',
      'message',
      'body',
      'senderName',
      'senderEmail',
      'senderId',
      'authorId',
      'attachmentUrl',
      'imageUrl',
      'fileUrl',
    ]);
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.forum_rounded, color: Color(0xFF7DD3FC)),
                SizedBox(width: 10),
                Text(
                  'Conversation History',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              selectedChat == null
                  ? 'Select a conversation to inspect historical messages.'
                  : 'Timeline for ${_recordId(selectedChat!)}',
              style: TextStyle(color: Colors.white.withValues(alpha: .66)),
            ),
            const SizedBox(height: 14),
            if (selectedChat == null)
              const _EmptyState('No conversation selected.')
            else if (filtered.isEmpty)
              const _EmptyState('No message history loaded.')
            else
              for (final message in filtered.take(12))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TimelineRow(
                    title:
                        '${message['senderName'] ?? message['senderEmail'] ?? message['senderId'] ?? message['authorId'] ?? 'Participant'}',
                    subtitle:
                        '${message['text'] ?? message['message'] ?? message['body'] ?? ''}',
                    trailing: _date(
                      message['createdAt'] ??
                          message['sentAt'] ??
                          message['timestamp'],
                    ),
                    footer:
                        '${message['attachmentUrl'] ?? message['imageUrl'] ?? message['fileUrl'] ?? message['attachments'] ?? ''}',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _AdminNotesPanel extends StatelessWidget {
  const _AdminNotesPanel({
    required this.title,
    required this.subtitle,
    required this.records,
    required this.query,
    this.recordType,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> records;
  final String query;
  final String? recordType;

  @override
  Widget build(BuildContext context) {
    final scoped = recordType == null
        ? records
        : records
              .where((record) => '${record['recordType']}' == recordType)
              .toList(growable: false);
    final filtered = adminSearch(scoped, query, const [
      'id',
      'recordId',
      'recordType',
      'body',
      'note',
      'operatorEmail',
      'operatorId',
    ]);
    final pinned = filtered
        .where((record) => record['pinned'] == true)
        .toList();
    final ordered = [...pinned, ...filtered.where((r) => r['pinned'] != true)];
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.push_pin_rounded, color: Color(0xFFA78BFA)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .66),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (ordered.isEmpty)
              const _EmptyState('No Admin notes loaded.')
            else
              for (final note in ordered.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TimelineRow(
                    title:
                        '${note['pinned'] == true ? 'Pinned note' : 'Internal note'} - ${note['recordId'] ?? 'record'}',
                    subtitle: '${note['body'] ?? note['note'] ?? ''}',
                    trailing:
                        '${note['operatorEmail'] ?? note['operatorId'] ?? 'Admin'}\n${_date(note['createdAt'])}',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _SenderTrustTimelinePanel extends StatelessWidget {
  const _SenderTrustTimelinePanel({
    required this.records,
    required this.users,
    required this.query,
  });

  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> users;
  final String query;

  @override
  Widget build(BuildContext context) {
    final filtered = adminSearch(records, query, const [
      'id',
      'senderId',
      'action',
      'reason',
      'operatorEmail',
      'nextTier',
      'previousTier',
    ]);
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.workspace_premium_rounded, color: Color(0xFFFDE68A)),
                SizedBox(width: 10),
                Text(
                  'Sender Trust Timeline',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Award, deduct, promote, demote, freeze and restore actions with operator audit context.',
              style: TextStyle(color: Colors.white.withValues(alpha: .66)),
            ),
            const SizedBox(height: 14),
            if (filtered.isEmpty)
              const _EmptyState('No sender trust events loaded.')
            else
              for (final event in filtered.take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TimelineRow(
                    title:
                        '${event['action'] ?? 'trust'} - ${_senderName(event['senderId'], users)}',
                    subtitle:
                        '${event['previousTier'] ?? '-'} -> ${event['nextTier'] ?? '-'}\n${event['reason'] ?? ''}',
                    trailing:
                        '${event['pointsDelta'] ?? 0} pts\n${_date(event['createdAt'])}',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.title,
    required this.subtitle,
    this.trailing = '',
    this.footer = '',
  });

  final String title;
  final String subtitle;
  final String trailing;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (trailing.trim().isNotEmpty)
                Text(
                  trailing,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .62),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withValues(alpha: .74)),
            ),
          ],
          if (footer.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              footer,
              style: TextStyle(
                color: const Color(0xFF7DD3FC).withValues(alpha: .82),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Text(
        message,
        style: TextStyle(color: Colors.white.withValues(alpha: .64)),
      ),
    );
  }
}

enum _GiftsWorkspaceTab {
  overview('Overview', Icons.space_dashboard_rounded),
  campaigns('Campaigns', Icons.campaign_rounded),
  participants('Participants', Icons.diversity_3_rounded),
  matches('Matching', Icons.hub_rounded),
  workspace('Operations', Icons.groups_2_rounded),
  stories('Stories', Icons.auto_stories_rounded),
  brandPartners('Partners', Icons.storefront_rounded);

  const _GiftsWorkspaceTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _GiftsOperationsModule extends StatefulWidget {
  const _GiftsOperationsModule({
    required this.gifts,
    required this.brands,
    required this.participants,
    required this.campaignMatches,
    required this.deliveries,
    required this.payments,
    required this.supportTickets,
    required this.auditLogs,
    required this.query,
    required this.canManageIssues,
    required this.onUpdateGiftWorkflow,
    required this.onUpdateGiftCampaignParticipant,
    required this.onSetGiftBrandStatus,
    required this.onEditGiftBrandPartner,
    required this.onSuggestGiftCampaignMatch,
    required this.onApproveGiftCampaignMatch,
    required this.onBulkGiftCampaignAction,
    required this.onEditGiftRequest,
    required this.onUpdateGiftStoryAccess,
    required this.onUpdateGiftStoryMedia,
    required this.onUpdateGiftWorkspace,
  });

  final List<Map<String, dynamic>> gifts;
  final List<Map<String, dynamic>> brands;
  final List<Map<String, dynamic>> participants;
  final List<Map<String, dynamic>> campaignMatches;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> auditLogs;
  final String query;
  final bool canManageIssues;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftWorkflow;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftCampaignParticipant;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetGiftBrandStatus;
  final Future<void> Function(Map<String, dynamic>?) onEditGiftBrandPartner;
  final Future<void> Function(Map<String, dynamic>, List<Map<String, dynamic>>)
  onSuggestGiftCampaignMatch;
  final Future<void> Function(Map<String, dynamic>, List<Map<String, dynamic>>)
  onApproveGiftCampaignMatch;
  final Future<void> Function(List<Map<String, dynamic>>, String)
  onBulkGiftCampaignAction;
  final Future<void> Function(Map<String, dynamic>) onEditGiftRequest;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftStoryAccess;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftStoryMedia;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftWorkspace;

  @override
  State<_GiftsOperationsModule> createState() => _GiftsOperationsModuleState();
}

class _GiftsOperationsModuleState extends State<_GiftsOperationsModule> {
  _GiftsWorkspaceTab _tab = _GiftsWorkspaceTab.overview;
  String _campaignFilter = '';
  String _priorityFilter = '';
  String _partnerFilter = '';
  String _staffFilter = '';
  String _storyFilter = '';
  String _stageFilter = '';
  String _matchFilter = '';
  bool _filtersVisible = false;
  Map<String, dynamic>? _selectedGift;

  @override
  Widget build(BuildContext context) {
    final query = widget.query.trim();
    final searchedGifts = adminSearch(widget.gifts, query, const [
      'id',
      'giftId',
      'giftName',
      'title',
      'senderName',
      'senderEmail',
      'recipientName',
      'recipientEmail',
      'businessName',
      'campaign',
      'campaignName',
      'deliveryId',
      'story',
      'storyStatus',
      'status',
      'giftAdminStatus',
      'irisGiftRecommendation',
      'procurementSupplier',
    ]);
    final searchedParticipants = adminSearch(widget.participants, query, const [
      'id',
      'campaignId',
      'campaignName',
      'displayName',
      'userId',
      'recipientName',
      'senderName',
      'matchStatus',
      'suggestedParticipantId',
    ]);
    final searchedMatches = adminSearch(widget.campaignMatches, query, const [
      'id',
      'campaignId',
      'campaignName',
      'brandName',
      'giftName',
      'recipientName',
      'senderName',
      'status',
      'matchStatus',
      'matchReason',
    ]);
    final searchedBrands = adminSearch(widget.brands, query, const [
      'id',
      'partnerId',
      'partnerName',
      'brandName',
      'category',
      'categories',
      'status',
      'partnershipStatus',
      'contactName',
      'contactEmail',
      'approvedFor',
      'internalNotes',
    ]);
    final filterOptions = _GiftFilterOptions.from(
      gifts: searchedGifts,
      participants: searchedParticipants,
      matches: searchedMatches,
      brands: searchedBrands,
    );
    final filtered = _applyGiftOperationalFilters(
      searchedGifts,
      campaign: _campaignFilter,
      priority: _priorityFilter,
      partner: _partnerFilter,
      staff: _staffFilter,
      story: _storyFilter,
      stage: _stageFilter,
      match: _matchFilter,
    );
    final filteredParticipants = _applyGiftOperationalFilters(
      searchedParticipants,
      campaign: _campaignFilter,
      priority: _priorityFilter,
      partner: _partnerFilter,
      staff: _staffFilter,
      story: _storyFilter,
      stage: _stageFilter,
      match: _matchFilter,
    );
    final filteredMatches = _applyGiftOperationalFilters(
      searchedMatches,
      campaign: _campaignFilter,
      priority: _priorityFilter,
      partner: _partnerFilter,
      staff: _staffFilter,
      story: _storyFilter,
      stage: _stageFilter,
      match: _matchFilter,
    );
    final filteredBrands = _applyGiftOperationalFilters(
      searchedBrands,
      campaign: _campaignFilter,
      priority: _priorityFilter,
      partner: _partnerFilter,
      staff: _staffFilter,
      story: _storyFilter,
      stage: _stageFilter,
      match: _matchFilter,
    );
    final campaigns = {
      ..._distinctValues(widget.gifts, 'campaignName'),
      ..._distinctValues(widget.gifts, 'campaign'),
      ..._distinctValues(widget.participants, 'campaignName'),
      ..._distinctValues(widget.campaignMatches, 'campaignName'),
    };
    final activeMatches = widget.campaignMatches
        .where((match) => !_hasAnyText(match, const ['rejected', 'closed']))
        .length;
    final pending = widget.gifts
        .where(
          (gift) => _hasAnyText(gift, const ['pending', 'preparing', 'review']),
        )
        .length;
    final pendingReviews =
        pending +
        widget.participants
            .where((record) => _hasAnyText(record, const ['pending', 'review']))
            .length +
        widget.brands
            .where((record) => _hasAnyText(record, const ['pending', 'review']))
            .length;
    final stories = widget.gifts.where(_hasGiftStory).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width >= 1500
              ? 6
              : MediaQuery.sizeOf(context).width >= 980
              ? 3
              : 2,
          childAspectRatio: MediaQuery.sizeOf(context).width >= 1500
              ? 1.55
              : 2.15,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _GiftKpiCard(
              label: 'Active Campaigns',
              value: '${campaigns.length}',
              icon: Icons.campaign_rounded,
              trend: 'Open programmes',
            ),
            _GiftKpiCard(
              label: 'Participants',
              value: '${widget.participants.length}',
              icon: Icons.diversity_3_rounded,
              trend: 'Campaign records',
            ),
            _GiftKpiCard(
              label: 'Successful Matches',
              value:
                  '${widget.campaignMatches.where((m) => _giftMatchBucket(m) == 'approved').length}',
              icon: Icons.verified_rounded,
              trend: '$activeMatches active',
            ),
            _GiftKpiCard(
              label: 'Brand Partners',
              value: '${widget.brands.length}',
              icon: Icons.storefront_rounded,
              trend: 'Directory',
            ),
            _GiftKpiCard(
              label: 'Stories In Progress',
              value: '$stories',
              icon: Icons.auto_stories_rounded,
              trend: 'Media enabled',
            ),
            _GiftKpiCard(
              label: 'Awaiting Approval',
              value: '$pendingReviews',
              icon: Icons.rate_review_rounded,
              trend: 'Operator attention',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _GiftActionBar(
          canManage: widget.canManageIssues,
          onBulkApprove: () => unawaited(
            widget.onBulkGiftCampaignAction(filteredParticipants, 'approved'),
          ),
          onBulkReject: () => unawaited(
            widget.onBulkGiftCampaignAction(filteredParticipants, 'rejected'),
          ),
          onAssign: () => unawaited(
            widget.onBulkGiftCampaignAction(
              filteredParticipants,
              'assign_later',
            ),
          ),
          onExport: () => unawaited(
            widget.onBulkGiftCampaignAction(filteredParticipants, 'exported'),
          ),
          onFilter: () => setState(() => _filtersVisible = !_filtersVisible),
          onNewCampaign: () => unawaited(widget.onEditGiftRequest({})),
          onInviteBrand: () => unawaited(widget.onEditGiftBrandPartner(null)),
        ),
        const SizedBox(height: 18),
        _GiftSegmentedTabs(
          selected: _tab,
          onSelected: (tab) => setState(() => _tab = tab),
        ),
        if (_filtersVisible) ...[
          const SizedBox(height: 18),
          _GiftFilterPanel(
            options: filterOptions,
            campaign: _campaignFilter,
            priority: _priorityFilter,
            partner: _partnerFilter,
            staff: _staffFilter,
            story: _storyFilter,
            stage: _stageFilter,
            match: _matchFilter,
            onCampaignChanged: (value) =>
                setState(() => _campaignFilter = value),
            onPriorityChanged: (value) =>
                setState(() => _priorityFilter = value),
            onPartnerChanged: (value) => setState(() => _partnerFilter = value),
            onStaffChanged: (value) => setState(() => _staffFilter = value),
            onStoryChanged: (value) => setState(() => _storyFilter = value),
            onStageChanged: (value) => setState(() => _stageFilter = value),
            onMatchChanged: (value) => setState(() => _matchFilter = value),
            onClear: () => setState(() {
              _campaignFilter = '';
              _priorityFilter = '';
              _partnerFilter = '';
              _staffFilter = '';
              _storyFilter = '';
              _stageFilter = '';
              _matchFilter = '';
            }),
          ),
        ],
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(
            key: ValueKey(_tab),
            child: switch (_tab) {
              _GiftsWorkspaceTab.overview => _giftOverview(
                filtered,
                filteredParticipants,
                filteredMatches,
                filteredBrands,
              ),
              _GiftsWorkspaceTab.campaigns => _giftCampaigns(filtered),
              _GiftsWorkspaceTab.participants => _giftParticipants(
                filteredParticipants,
              ),
              _GiftsWorkspaceTab.matches => _giftMatches(filteredMatches),
              _GiftsWorkspaceTab.stories => _giftStories(filtered),
              _GiftsWorkspaceTab.brandPartners => _giftBrandPartners(
                filteredBrands,
              ),
              _GiftsWorkspaceTab.workspace => _giftWorkspace(filtered),
            },
          ),
        ),
      ],
    );
  }

  Widget _giftOverview(
    List<Map<String, dynamic>> gifts,
    List<Map<String, dynamic>> participants,
    List<Map<String, dynamic>> matches,
    List<Map<String, dynamic>> brands,
  ) {
    return Column(
      children: [
        _GiftOperationsBoard(
          gifts: gifts,
          participants: participants,
          matches: matches,
          onEditGift: widget.onEditGiftRequest,
          onSelectGift: (gift) => setState(() => _selectedGift = gift),
          onUpdateWorkspace: widget.onUpdateGiftWorkspace,
          canManage: widget.canManageIssues,
          selectedGift: _selectedGift,
        ),
        const SizedBox(height: 18),
        _GiftGlassTable(
          title: 'Recent Gift Operations',
          subtitle:
              'Campaigns, participants, brand partners, story records and matching records in one operational stream.',
          emptyText: 'No Gifts records match this search.',
          records: [
            ...gifts.take(18),
            ...participants.take(8),
            ...matches.take(8),
            ...brands.take(6),
          ],
          rowBuilder: (record) => _GiftTableRowData(
            status:
                '${record['status'] ?? record['giftAdminStatus'] ?? record['matchStatus'] ?? record['partnershipStatus'] ?? 'review'}',
            title:
                '${record['giftName'] ?? record['campaignName'] ?? record['partnerName'] ?? record['brandName'] ?? record['displayName'] ?? _giftDisplayReference(record)}',
            owner:
                '${record['senderName'] ?? record['recipientName'] ?? record['contactName'] ?? record['brandName'] ?? 'Circum'}',
            updated: _date(record['updatedAt'] ?? record['createdAt']),
            metadata:
                '${record['matchReason'] ?? record['procurementSupplier'] ?? record['giftStorySharePrivacy'] ?? record['category'] ?? 'Operational record'}',
            onView:
                record.containsKey('partnerName') ||
                    record.containsKey('brandName')
                ? null
                : () => unawaited(widget.onEditGiftRequest(record)),
            onEdit:
                record.containsKey('partnerName') ||
                    record.containsKey('brandName')
                ? null
                : () => unawaited(widget.onEditGiftRequest(record)),
            menu: const [],
          ),
        ),
      ],
    );
  }

  Widget _giftCampaigns(List<Map<String, dynamic>> records) {
    return _GiftGlassTable(
      title: 'Campaigns',
      subtitle:
          'Gift matching, fulfilment, story, anonymous and escalation state.',
      emptyText: 'No gift campaigns match this search.',
      records: records,
      rowBuilder: (record) => _GiftTableRowData(
        status: '${record['giftAdminStatus'] ?? record['status'] ?? 'pending'}',
        title:
            '${record['campaignName'] ?? record['campaign'] ?? record['giftName'] ?? record['title'] ?? _giftDisplayReference(record, fallbackPrefix: 'Campaign')}',
        owner:
            '${record['senderName'] ?? record['senderEmail'] ?? record['senderId'] ?? 'Sender'}',
        updated: _date(record['updatedAt'] ?? record['createdAt']),
        metadata:
            '${record['recipientName'] ?? record['recipientEmail'] ?? 'Recipient'} · ${_giftStorySummary(record)}',
        onView: () => unawaited(widget.onEditGiftRequest(record)),
        onEdit: () => unawaited(widget.onEditGiftRequest(record)),
        menu: widget.canManageIssues
            ? _giftActions(
                record,
                widget.onUpdateGiftWorkflow,
              ).whereType<_MiniAction>().toList()
            : const [],
      ),
    );
  }

  Widget _giftParticipants(List<Map<String, dynamic>> records) {
    return _GiftGlassTable(
      title: 'Participants',
      subtitle:
          'Historical anonymous campaign participant review, matching and assignment management.',
      emptyText: 'No campaign participants match this search.',
      records: records,
      rowBuilder: (record) => _GiftTableRowData(
        status: '${record['matchStatus'] ?? record['status'] ?? 'pending'}',
        title:
            '${record['displayName'] ?? record['recipientName'] ?? _giftDisplayReference(record, fallbackPrefix: 'Recipient')}',
        owner:
            '${record['campaignName'] ?? record['campaignId'] ?? 'Campaign'}',
        updated: _date(record['updatedAt'] ?? record['createdAt']),
        metadata:
            'Match: ${record['suggestedParticipantId'] ?? record['matchReason'] ?? 'Not assigned'}',
        onView: null,
        onEdit: null,
        menu: widget.canManageIssues
            ? [
                _MiniAction(
                  label: 'Suggest',
                  onPressed: () => unawaited(
                    widget.onSuggestGiftCampaignMatch(
                      record,
                      widget.participants,
                    ),
                  ),
                ),
                _MiniAction(
                  label: 'Approve match',
                  onPressed: () => unawaited(
                    widget.onApproveGiftCampaignMatch(
                      record,
                      widget.participants,
                    ),
                  ),
                ),
                _MiniAction(
                  label: 'Reject',
                  onPressed: () => unawaited(
                    widget.onUpdateGiftCampaignParticipant(record, 'rejected'),
                  ),
                ),
                _MiniAction(
                  label: 'Assign later',
                  onPressed: () => unawaited(
                    widget.onUpdateGiftCampaignParticipant(
                      record,
                      'assign_later',
                    ),
                  ),
                ),
              ]
            : const [],
      ),
    );
  }

  Widget _giftMatches(List<Map<String, dynamic>> records) {
    final groups = <String, List<Map<String, dynamic>>>{
      'Pending': records
          .where((record) => _giftMatchBucket(record) == 'pending')
          .toList(),
      'Approved': records
          .where((record) => _giftMatchBucket(record) == 'approved')
          .toList(),
      'Rejected': records
          .where((record) => _giftMatchBucket(record) == 'rejected')
          .toList(),
      'Needs Manual Review': records
          .where((record) => _giftMatchBucket(record) == 'manual')
          .toList(),
    };
    final visible = groups.entries.where((entry) => entry.value.isNotEmpty);
    if (visible.isEmpty) {
      return const _GiftEmptyState(
        title: 'No pending matches.',
        message:
            'Campaign match records will appear here when a Gift workflow needs Admin review.',
      );
    }
    return Column(
      children: [
        for (final group in visible) ...[
          _GiftGlassTable(
            title: group.key,
            subtitle:
                'Campaign, brand, gift, recipient, budget and operator state.',
            emptyText: 'No ${group.key.toLowerCase()} matches.',
            records: group.value,
            rowBuilder: (record) => _GiftTableRowData(
              status:
                  '${record['status'] ?? record['matchStatus'] ?? 'pending'}',
              title:
                  '${record['campaignName'] ?? _giftDisplayReference(record, fallbackPrefix: 'Campaign')}',
              owner: '${record['brandName'] ?? record['giftName'] ?? 'Brand'}',
              updated: _date(record['updatedAt'] ?? record['createdAt']),
              metadata:
                  '${record['recipientName'] ?? record['senderName'] ?? 'Recipient'} · ${record['budget'] ?? record['matchingScore'] ?? record['matchReason'] ?? 'No score'}',
              onView: null,
              onEdit: null,
              menu: const [],
            ),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  Widget _giftStories(List<Map<String, dynamic>> records) {
    final stories = records.where(_hasGiftStory).toList(growable: false);
    return _GiftGlassTable(
      title: 'Stories',
      subtitle:
          'Gift Story Media and Video controls with preview-first row actions.',
      emptyText: 'No Gift Story media records match this search.',
      records: stories,
      rowBuilder: (record) => _GiftTableRowData(
        status:
            '${record['giftStoryVideoStatus'] ?? record['videoStatus'] ?? record['storyStatus'] ?? 'review'}',
        title:
            '${record['giftName'] ?? record['title'] ?? _giftDisplayReference(record)}',
        owner:
            '${record['recipientName'] ?? record['senderName'] ?? 'Gift Story'}',
        updated: _date(record['updatedAt'] ?? record['createdAt']),
        metadata:
            '${_giftStoryAudioSummary(record)} · ${record['giftStorySharePrivacy'] ?? record['contentUsageScope'] ?? 'private'}',
        onView: () => unawaited(
          widget.onUpdateGiftStoryMedia(record, 'record_preview_event'),
        ),
        onEdit: () => unawaited(widget.onEditGiftRequest(record)),
        menu: widget.canManageIssues
            ? [
                _MiniAction(
                  label: 'Download',
                  onPressed: () => unawaited(
                    widget.onUpdateGiftStoryMedia(record, 'download_video'),
                  ),
                ),
                _MiniAction(
                  label: 'Retry Render',
                  onPressed: () =>
                      unawaited(widget.onUpdateGiftStoryMedia(record, 'retry')),
                ),
                _MiniAction(
                  label: 'Regenerate Link',
                  onPressed: () => unawaited(
                    widget.onUpdateGiftStoryAccess(record, 'regenerate'),
                  ),
                ),
                _MiniAction(
                  label: 'Extend',
                  onPressed: () => unawaited(
                    widget.onUpdateGiftStoryMedia(record, 'extend'),
                  ),
                ),
                _MiniAction(
                  label: 'Revoke',
                  onPressed: () => unawaited(
                    widget.onUpdateGiftStoryMedia(record, 'revoke'),
                  ),
                ),
              ]
            : const [],
      ),
    );
  }

  Widget _giftBrandPartners(List<Map<String, dynamic>> records) {
    if (records.isEmpty) {
      return const _GiftEmptyState(
        title: 'No Brand Partners found.',
        message:
            'Brand Partner directory cards will appear when partner records match the current search.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1500
            ? 3
            : constraints.maxWidth >= 980
            ? 2
            : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 16)) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final record in records)
              SizedBox(
                width: width,
                child: _GiftBrandCard(
                  record: record,
                  auditCount: _relatedCount(record, widget.auditLogs),
                  canManage: widget.canManageIssues,
                  onEdit: () =>
                      unawaited(widget.onEditGiftBrandPartner(record)),
                  onSetStatus: (status) =>
                      unawaited(widget.onSetGiftBrandStatus(record, status)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _giftWorkspace(List<Map<String, dynamic>> records) {
    return _GiftGlassTable(
      title: 'Operations',
      subtitle:
          'Assignment, sourcing, item review, approval and delivery readiness.',
      emptyText: 'No gifts are currently in this stage.',
      records: records,
      rowBuilder: (record) => _GiftTableRowData(
        status: _giftWorkspaceStatus(record),
        title:
            '${record['giftName'] ?? record['title'] ?? _giftDisplayReference(record)}',
        owner:
            '${record['procurementSupplier'] ?? record['merchantName'] ?? 'Awaiting supplier'}',
        updated: _date(record['updatedAt'] ?? record['createdAt']),
        metadata:
            '${_giftIrisSelectionSummary(record)} · ${_giftProcurementSummary(record)}',
        progress: _giftWorkspaceProgress(record),
        onView: () => unawaited(widget.onEditGiftRequest(record)),
        onEdit: () => unawaited(widget.onEditGiftRequest(record)),
        menu: widget.canManageIssues
            ? [
                for (final action in const [
                  ('Assign', 'assigned'),
                  ('Awaiting Supplier', 'supplier_pending'),
                  ('Awaiting Approval', 'approval_pending'),
                  ('Ready', 'ready_for_delivery'),
                  ('Completed', 'completed'),
                ])
                  _MiniAction(
                    label: action.$1,
                    onPressed: () => unawaited(
                      widget.onUpdateGiftWorkspace(record, action.$2),
                    ),
                  ),
              ]
            : const [],
      ),
    );
  }
}

class _GiftActionBar extends StatelessWidget {
  const _GiftActionBar({
    required this.canManage,
    required this.onBulkApprove,
    required this.onBulkReject,
    required this.onAssign,
    required this.onExport,
    required this.onFilter,
    required this.onNewCampaign,
    required this.onInviteBrand,
  });

  final bool canManage;
  final VoidCallback onBulkApprove;
  final VoidCallback onBulkReject;
  final VoidCallback onAssign;
  final VoidCallback onExport;
  final VoidCallback onFilter;
  final VoidCallback onNewCampaign;
  final VoidCallback onInviteBrand;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(radius: 22),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _GiftActionGroup(
            label: 'Primary',
            children: [
              _GiftCommandButton(
                label: 'New Campaign',
                icon: Icons.add_rounded,
                tone: _GiftCommandTone.primary,
                onPressed: canManage ? onNewCampaign : null,
              ),
              _GiftCommandButton(
                label: 'Invite Brand',
                icon: Icons.storefront_rounded,
                tone: _GiftCommandTone.primary,
                onPressed: canManage ? onInviteBrand : null,
              ),
            ],
          ),
          _GiftActionGroup(
            label: 'Review',
            children: [
              _GiftCommandButton(
                label: 'Approve',
                icon: Icons.check_circle_rounded,
                tone: _GiftCommandTone.primary,
                onPressed: canManage ? onBulkApprove : null,
              ),
              _GiftCommandButton(
                label: 'Reject',
                icon: Icons.block_rounded,
                tone: _GiftCommandTone.danger,
                onPressed: canManage ? onBulkReject : null,
              ),
              _GiftCommandButton(
                label: 'Assign',
                icon: Icons.assignment_ind_rounded,
                tone: _GiftCommandTone.primary,
                onPressed: canManage ? onAssign : null,
              ),
            ],
          ),
          _GiftActionGroup(
            label: 'Reports',
            children: [
              _GiftCommandButton(
                label: 'Export Report',
                icon: Icons.download_rounded,
                onPressed: canManage ? onExport : null,
              ),
              _GiftCommandButton(
                label: 'Filter Results',
                icon: Icons.tune_rounded,
                onPressed: onFilter,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GiftActionGroup extends StatelessWidget {
  const _GiftActionGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: .44),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        ...children,
      ],
    );
  }
}

class _GiftKpiCard extends StatelessWidget {
  const _GiftKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.trend,
  });

  final String label;
  final String value;
  final IconData icon;
  final String trend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: .105),
            Colors.white.withValues(alpha: .042),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .13)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: .12),
            blurRadius: 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF7DD3FC).withValues(alpha: .14),
                  border: Border.all(
                    color: const Color(0xFF7DD3FC).withValues(alpha: .24),
                  ),
                ),
                child: Icon(icon, color: const Color(0xFFBAE6FD), size: 20),
              ),
              const Spacer(),
              _GiftStatusChip(trend),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .72),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftFilterOptions {
  const _GiftFilterOptions({
    required this.campaigns,
    required this.priorities,
    required this.partners,
    required this.staff,
    required this.stories,
    required this.stages,
    required this.matches,
  });

  final List<String> campaigns;
  final List<String> priorities;
  final List<String> partners;
  final List<String> staff;
  final List<String> stories;
  final List<String> stages;
  final List<String> matches;

  static _GiftFilterOptions from({
    required List<Map<String, dynamic>> gifts,
    required List<Map<String, dynamic>> participants,
    required List<Map<String, dynamic>> matches,
    required List<Map<String, dynamic>> brands,
  }) {
    final all = [...gifts, ...participants, ...matches, ...brands];
    return _GiftFilterOptions(
      campaigns: _giftFilterValues(all, const [
        'campaignName',
        'campaign',
        'campaignId',
      ]),
      priorities: _giftFilterValues(all, const ['priority', 'urgency']),
      partners: _giftFilterValues(all, const [
        'brandName',
        'partnerName',
        'procurementSupplier',
        'merchantName',
      ]),
      staff: _giftFilterValues(all, const [
        'assignedStaff',
        'assignedCurator',
        'operatorEmail',
      ]),
      stories: const [
        'Story available',
        'Story not added',
        'Draft',
        'Approved',
        'Published',
        'Archived',
      ],
      stages: const [
        'Campaign Created',
        'Participants',
        'Matches Found',
        'Needs Sourcing',
        'Awaiting Supplier',
        'Gift Assessment',
        'Story Production',
        'Awaiting Approval',
        'Ready',
        'Delivered',
      ],
      matches: const ['Matched', 'Unmatched'],
    );
  }
}

class _GiftFilterPanel extends StatelessWidget {
  const _GiftFilterPanel({
    required this.options,
    required this.campaign,
    required this.priority,
    required this.partner,
    required this.staff,
    required this.story,
    required this.stage,
    required this.match,
    required this.onCampaignChanged,
    required this.onPriorityChanged,
    required this.onPartnerChanged,
    required this.onStaffChanged,
    required this.onStoryChanged,
    required this.onStageChanged,
    required this.onMatchChanged,
    required this.onClear,
  });

  final _GiftFilterOptions options;
  final String campaign;
  final String priority;
  final String partner;
  final String staff;
  final String story;
  final String stage;
  final String match;
  final ValueChanged<String> onCampaignChanged;
  final ValueChanged<String> onPriorityChanged;
  final ValueChanged<String> onPartnerChanged;
  final ValueChanged<String> onStaffChanged;
  final ValueChanged<String> onStoryChanged;
  final ValueChanged<String> onStageChanged;
  final ValueChanged<String> onMatchChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: Color(0xFF7DD3FC)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Operational filters',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _GiftFilterDropdown(
                label: 'Campaign',
                value: campaign,
                options: options.campaigns,
                onChanged: onCampaignChanged,
              ),
              _GiftFilterDropdown(
                label: 'Priority',
                value: priority,
                options: options.priorities,
                onChanged: onPriorityChanged,
              ),
              _GiftFilterDropdown(
                label: 'Partner',
                value: partner,
                options: options.partners,
                onChanged: onPartnerChanged,
              ),
              _GiftFilterDropdown(
                label: 'Assigned Staff',
                value: staff,
                options: options.staff,
                onChanged: onStaffChanged,
              ),
              _GiftFilterDropdown(
                label: 'Story Status',
                value: story,
                options: options.stories,
                onChanged: onStoryChanged,
              ),
              _GiftFilterDropdown(
                label: 'Current Stage',
                value: stage,
                options: options.stages,
                onChanged: onStageChanged,
              ),
              _GiftFilterDropdown(
                label: 'Matched / Unmatched',
                value: match,
                options: options.matches,
                onChanged: onMatchChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GiftFilterDropdown extends StatelessWidget {
  const _GiftFilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final unique = options.toSet().toList()..sort();
    final items = ['', ...unique.take(40)];
    return SizedBox(
      width: 206,
      child: DropdownButtonFormField<String>(
        initialValue: items.contains(value) ? value : '',
        isExpanded: true,
        dropdownColor: const Color(0xFF111827),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: Colors.white.withValues(alpha: .045),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .12)),
          ),
        ),
        items: [
          for (final item in items)
            DropdownMenuItem<String>(
              value: item,
              child: Text(item.isEmpty ? 'Any' : item),
            ),
        ],
        onChanged: (next) => onChanged(next ?? ''),
      ),
    );
  }
}

enum _GiftCommandTone { primary, danger, neutral }

class _GiftCommandButton extends StatelessWidget {
  const _GiftCommandButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tone = _GiftCommandTone.neutral,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final _GiftCommandTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _GiftCommandTone.primary => const Color(0xFF7DD3FC),
      _GiftCommandTone.danger => const Color(0xFFFF7A90),
      _GiftCommandTone.neutral => Colors.white,
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: Colors.white.withValues(alpha: .32),
          side: BorderSide(color: color.withValues(alpha: .24)),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _GiftSegmentedTabs extends StatelessWidget {
  const _GiftSegmentedTabs({required this.selected, required this.onSelected});

  final _GiftsWorkspaceTab selected;
  final ValueChanged<_GiftsWorkspaceTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: _panelDecoration(),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tab in _GiftsWorkspaceTab.values)
            _GiftTabButton(
              tab: tab,
              selected: tab == selected,
              onTap: () => onSelected(tab),
            ),
        ],
      ),
    );
  }
}

class _GiftOperationsBoard extends StatelessWidget {
  const _GiftOperationsBoard({
    required this.gifts,
    required this.participants,
    required this.matches,
    required this.onEditGift,
    required this.onSelectGift,
    required this.onUpdateWorkspace,
    required this.canManage,
    required this.selectedGift,
  });

  final List<Map<String, dynamic>> gifts;
  final List<Map<String, dynamic>> participants;
  final List<Map<String, dynamic>> matches;
  final Future<void> Function(Map<String, dynamic>) onEditGift;
  final ValueChanged<Map<String, dynamic>> onSelectGift;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateWorkspace;
  final bool canManage;
  final Map<String, dynamic>? selectedGift;

  @override
  Widget build(BuildContext context) {
    final lanes = <(String, List<Map<String, dynamic>>, String)>[
      (
        'Campaign Created',
        gifts
            .where(
              (record) =>
                  _hasAnyText(record, const ['draft', 'campaign', 'created']),
            )
            .toList(),
        'campaign_created',
      ),
      ('Participants', participants, 'participants'),
      (
        'Matches Found',
        [
          ...matches.where((record) => _giftMatchBucket(record) == 'approved'),
          ...participants.where(
            (record) =>
                '${record['suggestedParticipantId'] ?? record['matchedGiftId'] ?? ''}'
                    .trim()
                    .isNotEmpty,
          ),
        ],
        'matches_found',
      ),
      (
        'Needs Sourcing',
        gifts
            .where(
              (record) =>
                  _giftProcurementSummary(record) == 'Sourcing not started',
            )
            .toList(),
        'supplier_pending',
      ),
      (
        'Awaiting Supplier',
        gifts
            .where(
              (record) =>
                  _giftWorkspaceProgress(record).contains('Awaiting Supplier'),
            )
            .toList(),
        'supplier_pending',
      ),
      (
        'In Transit',
        gifts
            .where(
              (record) => _hasAnyText(record, const [
                'in transit',
                'in_transit',
                'collected',
                'rider assigned',
              ]),
            )
            .toList(),
        'in_transit',
      ),
      (
        'Delivered',
        gifts
            .where(
              (record) => _giftWorkspaceProgress(record).contains('Completed'),
            )
            .toList(),
        'completed',
      ),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operations Board',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Gift operations queue organised by stage.',
            style: TextStyle(color: Colors.white.withValues(alpha: .62)),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final board = SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final lane in lanes)
                      _GiftBoardLane(
                        title: lane.$1,
                        records: lane.$2.take(8).toList(),
                        actionStatus: lane.$3,
                        onEditGift: onEditGift,
                        onSelectGift: onSelectGift,
                        onUpdateWorkspace: onUpdateWorkspace,
                        canManage: canManage,
                      ),
                  ],
                ),
              );
              final detail = _GiftDetailPanel(
                record: selectedGift,
                onEditGift: onEditGift,
              );
              if (constraints.maxWidth < 980) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [board, const SizedBox(height: 14), detail],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: board),
                  const SizedBox(width: 14),
                  SizedBox(width: 340, child: detail),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Gift Assessment: parcel recommendations reviewed before approval.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .58),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftBoardLane extends StatelessWidget {
  const _GiftBoardLane({
    required this.title,
    required this.records,
    required this.actionStatus,
    required this.onEditGift,
    required this.onSelectGift,
    required this.onUpdateWorkspace,
    required this.canManage,
  });

  final String title;
  final List<Map<String, dynamic>> records;
  final String actionStatus;
  final Future<void> Function(Map<String, dynamic>) onEditGift;
  final ValueChanged<Map<String, dynamic>> onSelectGift;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateWorkspace;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      margin: const EdgeInsets.only(right: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              _GiftStatusChip('${records.length}'),
            ],
          ),
          const SizedBox(height: 10),
          if (records.isEmpty)
            Text(
              'No gifts are currently in this stage.',
              style: TextStyle(color: Colors.white.withValues(alpha: .48)),
            )
          else
            for (final record in records) ...[
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelectGift(record),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .055),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${record['giftName'] ?? record['giftTitle'] ?? record['title'] ?? record['campaignName'] ?? record['displayName'] ?? _giftDisplayReference(record)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      _GiftBoardMeta(
                        label: 'Recipient',
                        value:
                            '${record['recipientName'] ?? record['recipientEmail'] ?? 'Not recorded'}',
                      ),
                      _GiftBoardMeta(
                        label: 'Campaign',
                        value:
                            '${record['campaignName'] ?? record['campaign'] ?? 'Awaiting assignment'}',
                      ),
                      _GiftBoardMeta(
                        label: 'Assigned staff',
                        value:
                            '${record['assignedStaff'] ?? record['assignedCurator'] ?? _mapValue(record['giftsTeamWorkspace'], 'assignedCurator') ?? 'Awaiting assignment'}',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _GiftStatusChip(
                            '${record['priority'] ?? record['urgency'] ?? 'Standard'}',
                          ),
                          _GiftStatusChip(_giftStorySummary(record)),
                          if ('${record['brandName'] ?? record['partnerName'] ?? ''}'
                              .trim()
                              .isNotEmpty)
                            _GiftStatusChip(
                              '${record['brandName'] ?? record['partnerName']}',
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Updated ${_date(record['updatedAt'] ?? record['createdAt'])}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .44),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _giftDisplayReference(record),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .34),
                          fontSize: 10,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (canManage) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _MiniAction(
                              label: 'Advance',
                              onPressed: () => unawaited(
                                onUpdateWorkspace(record, actionStatus),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _MiniAction(
                              label: 'Edit',
                              onPressed: () => unawaited(onEditGift(record)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _GiftBoardMeta extends StatelessWidget {
  const _GiftBoardMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .40),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value.trim().isEmpty ? 'Not recorded' : value,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .68),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftDetailPanel extends StatelessWidget {
  const _GiftDetailPanel({required this.record, required this.onEditGift});

  final Map<String, dynamic>? record;
  final Future<void> Function(Map<String, dynamic>) onEditGift;

  @override
  Widget build(BuildContext context) {
    if (record == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: _panelDecoration(radius: 22),
        child: const _GiftEmptyState(
          title: 'Select a gift',
          message:
              'Choose a card from the workflow board to review operational detail without leaving operations.',
        ),
      );
    }
    final gift = record!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${gift['giftName'] ?? gift['title'] ?? gift['campaignName'] ?? _giftDisplayReference(gift)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _GiftStatusChip(_giftWorkspaceStatus(gift)),
            ],
          ),
          const SizedBox(height: 14),
          _GiftDetailSection(
            title: 'Overview',
            lines: [
              'Recipient: ${gift['recipientName'] ?? gift['recipientEmail'] ?? 'Not recorded'}',
              'Campaign: ${gift['campaignName'] ?? gift['campaign'] ?? 'Awaiting assignment'}',
              'Assigned: ${gift['assignedStaff'] ?? gift['assignedCurator'] ?? 'Awaiting assignment'}',
            ],
          ),
          _GiftDetailSection(
            title: 'Story',
            lines: [
              _giftStorySummary(gift),
              'Audio: ${_giftStoryAudioSummary(gift)}',
              'Visibility: ${gift['giftStorySharePrivacy'] ?? gift['contentUsageScope'] ?? 'private'}',
            ],
          ),
          _GiftDetailSection(
            title: 'Matching',
            lines: [
              'Brand: ${gift['brandName'] ?? gift['partnerName'] ?? 'Not matched'}',
              'Score: ${gift['matchingScore'] ?? gift['matchScore'] ?? 'Not recorded'}',
            ],
          ),
          _GiftDetailSection(
            title: 'Sourcing',
            lines: [_giftProcurementSummary(gift)],
          ),
          _GiftDetailSection(
            title: 'Delivery',
            lines: [
              'Delivery: ${gift['deliveryId'] ?? 'Not scheduled'}',
              'Status: ${gift['deliveryStatus'] ?? gift['status'] ?? 'Not recorded'}',
            ],
          ),
          _GiftDetailSection(
            title: 'Delivery History',
            lines: [
              'Created: ${_date(gift['createdAt'])}',
              'Updated: ${_date(gift['updatedAt'] ?? gift['createdAt'])}',
              'Audit: ${gift['giftWorkspaceAuditTrail'] is List ? (gift['giftWorkspaceAuditTrail'] as List).length : 0} entries',
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: _GiftCompactAction(
              label: 'Edit',
              onPressed: () => unawaited(onEditGift(gift)),
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftDetailSection extends StatelessWidget {
  const _GiftDetailSection({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .46),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: .2,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .72),
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GiftTabButton extends StatelessWidget {
  const _GiftTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _GiftsWorkspaceTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0x665A7CFF), Color(0x665DE0E6)],
                  )
                : null,
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: .26)
                  : Colors.white.withValues(alpha: .08),
            ),
            color: selected ? null : Colors.white.withValues(alpha: .04),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha: .18),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                tab.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GiftTableRowData {
  const _GiftTableRowData({
    required this.status,
    required this.title,
    required this.owner,
    required this.updated,
    required this.metadata,
    required this.onView,
    required this.onEdit,
    required this.menu,
    this.progress = const [],
  });

  final String status;
  final String title;
  final String owner;
  final String updated;
  final String metadata;
  final VoidCallback? onView;
  final VoidCallback? onEdit;
  final List<_MiniAction> menu;
  final List<String> progress;
}

class _GiftGlassTable extends StatelessWidget {
  const _GiftGlassTable({
    required this.title,
    required this.subtitle,
    required this.emptyText,
    required this.records,
    required this.rowBuilder,
  });

  final String title;
  final String subtitle;
  final String emptyText;
  final List<Map<String, dynamic>> records;
  final _GiftTableRowData Function(Map<String, dynamic>) rowBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .62),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          if (records.isEmpty)
            _GiftEmptyState(
              title: emptyText,
              message: 'Try a broader search or clear filters.',
            )
          else ...[
            _GiftTableHeader(),
            const SizedBox(height: 8),
            for (final record in records.take(80)) ...[
              _GiftTableRow(data: rowBuilder(record)),
              const SizedBox(height: 8),
            ],
            _GiftTableFooter(
              showing: records.take(80).length,
              total: records.length,
            ),
          ],
        ],
      ),
    );
  }
}

class _GiftTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const SizedBox(width: 34),
          Expanded(flex: 4, child: _giftHeaderText('Title')),
          Expanded(flex: 3, child: _giftHeaderText('Owner')),
          Expanded(flex: 2, child: _giftHeaderText('Updated')),
          Expanded(flex: 3, child: _giftHeaderText('Actions')),
        ],
      ),
    );
  }
}

Widget _giftHeaderText(String value) {
  return Text(
    value,
    style: TextStyle(
      color: Colors.white.withValues(alpha: .54),
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: .2,
    ),
  );
}

class _GiftTableRow extends StatelessWidget {
  const _GiftTableRow({required this.data});

  final _GiftTableRowData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF7DD3FC).withValues(alpha: .14),
              border: Border.all(
                color: const Color(0xFF7DD3FC).withValues(alpha: .28),
              ),
            ),
            child: const Icon(
              Icons.card_giftcard_rounded,
              color: Color(0xFFBAE6FD),
              size: 13,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(flex: 4, child: _GiftRowTitle(data: data)),
          Expanded(
            flex: 3,
            child: Text(
              data.owner,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: .74)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              data.updated,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: .56)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                _GiftCompactAction(label: 'View', onPressed: data.onView),
                _GiftCompactAction(label: 'Edit', onPressed: data.onEdit),
                if (data.menu.isNotEmpty) _GiftMoreMenu(actions: data.menu),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftRowTitle extends StatelessWidget {
  const _GiftRowTitle({required this.data});

  final _GiftTableRowData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _GiftStatusChip(data.status),
            for (final progress in data.progress) _GiftStatusChip(progress),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          data.title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          data.metadata,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .56),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _GiftCompactAction extends StatelessWidget {
  const _GiftCompactAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: .28),
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label),
    );
  }
}

class _GiftMoreMenu extends StatelessWidget {
  const _GiftMoreMenu({required this.actions});

  final List<_MiniAction> actions;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'More',
      enabled: actions.isNotEmpty,
      color: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(
              actions[i].label,
              style: const TextStyle(color: Colors.white),
            ),
          ),
      ],
      onSelected: (index) => actions[index].onPressed(),
      child: Container(
        width: 42,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .1)),
          color: Colors.white.withValues(alpha: .05),
        ),
        child: const Icon(Icons.more_horiz_rounded, color: Colors.white),
      ),
    );
  }
}

class _GiftTableFooter extends StatelessWidget {
  const _GiftTableFooter({required this.showing, required this.total});

  final int showing;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Showing $showing of $total records',
        style: TextStyle(
          color: Colors.white.withValues(alpha: .48),
          fontSize: 12,
        ),
      ),
    );
  }
}

class _GiftEmptyState extends StatelessWidget {
  const _GiftEmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF7C3AED).withValues(alpha: .10),
            const Color(0xFF22D3EE).withValues(alpha: .08),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .08),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .62),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftStatusChip extends StatelessWidget {
  const _GiftStatusChip(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    final lower = value.toLowerCase();
    final color = lower.contains('reject') || lower.contains('suspend')
        ? const Color(0xFFFF6B7A)
        : lower.contains('supplier') || lower.contains('await')
        ? const Color(0xFFFBBF24)
        : lower.contains('pending') || lower.contains('review')
        ? const Color(0xFFC084FC)
        : lower.contains('active') || lower.contains('publish')
        ? const Color(0xFF60A5FA)
        : lower.contains('approve') ||
              lower.contains('complete') ||
              lower.contains('ready')
        ? const Color(0xFF34D399)
        : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _GiftBrandCard extends StatelessWidget {
  const _GiftBrandCard({
    required this.record,
    required this.auditCount,
    required this.canManage,
    required this.onEdit,
    required this.onSetStatus,
  });

  final Map<String, dynamic> record;
  final int auditCount;
  final bool canManage;
  final VoidCallback onEdit;
  final ValueChanged<String> onSetStatus;

  @override
  Widget build(BuildContext context) {
    final status =
        '${record['status'] ?? record['partnershipStatus'] ?? 'pending'}';
    return Container(
      constraints: const BoxConstraints(minHeight: 270),
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${record['partnerName'] ?? record['brandName'] ?? _giftDisplayReference(record, fallbackPrefix: 'Partner')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _GiftStatusChip(status),
            ],
          ),
          const SizedBox(height: 14),
          _GiftCardMeta(
            'Contact',
            '${record['contactName'] ?? 'Not recorded'} · ${record['contactEmail'] ?? ''}',
          ),
          _GiftCardMeta(
            'Categories',
            '${record['category'] ?? record['categories'] ?? 'Uncategorised'}',
          ),
          _GiftCardMeta(
            'Trust Score',
            '${record['trustScore'] ?? record['recommendationScore'] ?? 'Not recorded'}',
          ),
          _GiftCardMeta(
            'Campaigns',
            '${record['approvedFor'] ?? record['campaignName'] ?? 'No campaign association'}',
          ),
          _GiftCardMeta('Recent Activity', '$auditCount audit entries'),
          const Spacer(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _GiftCompactAction(label: 'View', onPressed: onEdit),
              _GiftCompactAction(label: 'Edit', onPressed: onEdit),
              _GiftMoreMenu(
                actions: canManage
                    ? [
                        _MiniAction(
                          label: 'Approve',
                          onPressed: () => onSetStatus('approved'),
                        ),
                        _MiniAction(
                          label: 'Suspend',
                          onPressed: () => onSetStatus('suspended'),
                        ),
                        _MiniAction(
                          label: 'Reactivate',
                          onPressed: () => onSetStatus('active'),
                        ),
                        _MiniAction(label: 'View history', onPressed: onEdit),
                      ]
                    : const [],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GiftCardMeta extends StatelessWidget {
  const _GiftCardMeta(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .42),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value.trim().isEmpty ? 'Not recorded' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .76),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

String _giftMatchBucket(Map<String, dynamic> record) {
  final status = '${record['status'] ?? record['matchStatus'] ?? ''}'
      .toLowerCase();
  if (status.contains('approve')) return 'approved';
  if (status.contains('reject')) return 'rejected';
  if (status.contains('manual') || status.contains('review')) return 'manual';
  return 'pending';
}

String _giftWorkspaceStatus(Map<String, dynamic> record) {
  final raw =
      '${record['giftsTeamWorkspaceStatus'] ?? record['workspaceStatus'] ?? record['giftAdminStatus'] ?? record['status'] ?? 'Awaiting Review'}';
  return raw.replaceAll('_', ' ');
}

String _giftDisplayReference(
  Map<String, dynamic> record, {
  String fallbackPrefix = 'Gift',
}) {
  final explicitReferences =
      [
            record['displayReference'],
            record['giftReference'],
            record['campaignReference'],
            record['recipientReference'],
            record['orderNumber'],
          ]
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty && value != 'null')
          .toList(growable: false);
  if (explicitReferences.isNotEmpty) return explicitReferences.first;
  final id = _recordId(record).trim();
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  final number = 10000 + (hash % 90000);
  return '$fallbackPrefix #$number';
}

List<String> _giftWorkspaceProgress(Map<String, dynamic> record) {
  final values = <String>[];
  final supplier =
      '${record['procurementSupplier'] ?? record['supplierStatus'] ?? ''}'
          .toLowerCase();
  final approval =
      '${record['approvedGiftPlan'] ?? record['approvalStatus'] ?? ''}'
          .toLowerCase();
  final status = _giftWorkspaceStatus(record).toLowerCase();
  if (supplier.isEmpty || supplier.contains('pending')) {
    values.add('Awaiting Supplier');
  }
  if (approval.isEmpty || approval.contains('pending')) {
    values.add('Awaiting Approval');
  }
  if (status.contains('ready')) values.add('Ready');
  if (status.contains('review')) values.add('Awaiting Review');
  if (status.contains('complete') || status.contains('delivered')) {
    values.add('Completed');
  }
  return values.isEmpty ? const ['Awaiting Review'] : values;
}

List<String> _giftFilterValues(
  List<Map<String, dynamic>> records,
  List<String> fields,
) {
  return records
      .expand((record) => fields.map((field) => '${record[field] ?? ''}'))
      .expand((value) => value.split(','))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty && value != 'null')
      .toSet()
      .toList()
    ..sort();
}

List<Map<String, dynamic>> _applyGiftOperationalFilters(
  List<Map<String, dynamic>> records, {
  required String campaign,
  required String priority,
  required String partner,
  required String staff,
  required String story,
  required String stage,
  required String match,
}) {
  return records
      .where(
        (record) => _giftRecordMatchesFilter(record, campaign, const [
          'campaignName',
          'campaign',
          'campaignId',
        ]),
      )
      .where(
        (record) => _giftRecordMatchesFilter(record, priority, const [
          'priority',
          'urgency',
        ]),
      )
      .where(
        (record) => _giftRecordMatchesFilter(record, partner, const [
          'brandName',
          'partnerName',
          'procurementSupplier',
          'merchantName',
        ]),
      )
      .where(
        (record) => _giftRecordMatchesFilter(record, staff, const [
          'assignedStaff',
          'assignedCurator',
          'operatorEmail',
        ]),
      )
      .where((record) {
        if (story.isEmpty) return true;
        final lower = story.toLowerCase();
        final summary = _giftStorySummary(record).toLowerCase();
        if (lower == 'story available') return _hasGiftStory(record);
        if (lower == 'story not added') return !_hasGiftStory(record);
        return summary.contains(lower) ||
            '${record['storyStatus'] ?? record['giftStoryVideoStatus'] ?? ''}'
                .toLowerCase()
                .contains(lower);
      })
      .where((record) {
        if (stage.isEmpty) return true;
        return _giftOperationalStage(record).toLowerCase() ==
            stage.toLowerCase();
      })
      .where((record) {
        if (match.isEmpty) return true;
        final matched =
            '${record['suggestedParticipantId'] ?? record['matchedGiftId'] ?? record['brandName'] ?? record['partnerName'] ?? ''}'
                .trim()
                .isNotEmpty ||
            _giftMatchBucket(record) == 'approved';
        return match == 'Matched' ? matched : !matched;
      })
      .toList(growable: false);
}

bool _giftRecordMatchesFilter(
  Map<String, dynamic> record,
  String filter,
  List<String> fields,
) {
  if (filter.isEmpty) return true;
  final lower = filter.toLowerCase();
  return fields.any(
    (field) => '${record[field] ?? ''}'
        .toLowerCase()
        .split(',')
        .map((value) => value.trim())
        .contains(lower),
  );
}

String _giftOperationalStage(Map<String, dynamic> record) {
  final text = record.values.join(' ').toLowerCase();
  final participantRecord =
      record.containsKey('userId') || record.containsKey('displayName');
  if (participantRecord) {
    if (_giftMatchBucket(record) == 'approved' ||
        '${record['suggestedParticipantId'] ?? record['matchedGiftId'] ?? ''}'
            .trim()
            .isNotEmpty) {
      return 'Matches Found';
    }
    return 'Participants';
  }
  if (_giftWorkspaceProgress(record).contains('Completed') ||
      text.contains('delivered')) {
    return 'Delivered';
  }
  if (_giftWorkspaceProgress(record).contains('Ready')) return 'Ready';
  if (_giftWorkspaceProgress(record).contains('Awaiting Approval')) {
    return 'Awaiting Approval';
  }
  if (_hasGiftStory(record)) return 'Story Production';
  if (_giftIrisSelectionSummary(
    record,
  ).toLowerCase().contains('recommendation')) {
    return 'Gift Assessment';
  }
  if (_giftWorkspaceProgress(record).contains('Awaiting Supplier')) {
    return 'Awaiting Supplier';
  }
  if (_giftProcurementSummary(record) == 'Sourcing not started') {
    return 'Needs Sourcing';
  }
  if (_giftMatchBucket(record) == 'approved' ||
      '${record['suggestedParticipantId'] ?? record['matchedGiftId'] ?? ''}'
          .trim()
          .isNotEmpty) {
    return 'Matches Found';
  }
  return 'Campaign Created';
}

// ignore: unused_element
class _GiftBrandPartnersModule extends StatelessWidget {
  const _GiftBrandPartnersModule({
    required this.brands,
    required this.gifts,
    required this.auditLogs,
    required this.query,
    required this.canManageIssues,
    required this.onSetGiftBrandStatus,
    required this.onEditGiftBrandPartner,
  });

  final List<Map<String, dynamic>> brands;
  final List<Map<String, dynamic>> gifts;
  final List<Map<String, dynamic>> auditLogs;
  final String query;
  final bool canManageIssues;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetGiftBrandStatus;
  final Future<void> Function(Map<String, dynamic>?) onEditGiftBrandPartner;

  @override
  Widget build(BuildContext context) {
    final filtered = adminSearch(brands, query, const [
      'id',
      'partnerId',
      'partnerName',
      'brandName',
      'category',
      'status',
      'partnershipStatus',
      'contactName',
      'contactEmail',
      'approvedFor',
      'internalNotes',
    ]);
    final active = brands
        .where(
          (brand) =>
              '${brand['status'] ?? brand['partnershipStatus'] ?? ''}' ==
              'approved',
        )
        .length;
    final pending = brands
        .where(
          (brand) =>
              '${brand['status'] ?? brand['partnershipStatus'] ?? ''}' ==
              'pending',
        )
        .length;
    final suspended = brands.where((brand) {
      final status = '${brand['status'] ?? brand['partnershipStatus'] ?? ''}';
      return status == 'paused' || status == 'suspended';
    }).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AdminModuleIntro(
          title: 'Gift Brand Partners',
          subtitle:
              'Historical Brand Partner directory, verification, catalogue association, contact records, campaign participation and audit history.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard('Active partners', '$active', 'approved'),
            _MetricCard('Pending', '$pending', 'verification'),
            _MetricCard('Suspended', '$suspended', 'paused/inactive'),
            _MetricCard(
              'Gift links',
              '${_brandGiftLinks(brands, gifts)}',
              'catalogue/campaign',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Brand Partner Directory',
          subtitle:
              'Search by Brand, Category and Status. Actions require confirmation and write Admin audit records.',
          records: filtered,
          query: '',
          fields: const [],
          columns: const ['Brand', 'Category', 'Status', 'Campaigns'],
          row: (record) => [
            '${record['partnerName'] ?? record['brandName'] ?? _giftDisplayReference(record, fallbackPrefix: 'Partner')}\n${record['contactName'] ?? ''} ${record['contactEmail'] ?? ''}',
            '${record['category'] ?? 'Uncategorised'}',
            '${record['status'] ?? record['partnershipStatus'] ?? 'pending'}',
            '${record['approvedFor'] ?? record['campaignName'] ?? 'No campaign association'}',
          ],
          actions: canManageIssues
              ? (record) => _giftBrandPartnerActions(
                  record,
                  onSetGiftBrandStatus,
                  onEditGiftBrandPartner,
                )
              : null,
        ),
        const SizedBox(height: 18),
        _OperationalDetailGrid(
          title: 'Partner Profiles and History',
          records: filtered,
          emptyText: 'No Brand Partner profiles loaded.',
          rowsFor: (record) => [
            (
              'Partner',
              '${record['partnerName'] ?? record['brandName'] ?? ''}',
            ),
            (
              'Contact',
              '${record['contactName'] ?? ''} · ${record['contactEmail'] ?? ''} · ${record['phone'] ?? ''}',
            ),
            ('Website', '${record['website'] ?? 'Not recorded'}'),
            (
              'Catalogue',
              '${record['productGroups'] ?? record['approvedFor'] ?? 'No catalogue association'}',
            ),
            (
              'Notes',
              '${record['internalNotes'] ?? record['brandNotes'] ?? 'No notes'}',
            ),
            (
              'Performance',
              '${record['performanceMetrics'] ?? record['recommendationScore'] ?? 'No historical metrics loaded'}',
            ),
            ('Audit history', '${_relatedCount(record, auditLogs)} entries'),
          ],
        ),
      ],
    );
  }
}

// ignore: unused_element
class _GiftTeamWorkspaceModule extends StatelessWidget {
  const _GiftTeamWorkspaceModule({
    required this.gifts,
    required this.query,
    required this.canManageIssues,
    required this.onUpdateGiftWorkspace,
    required this.onUpdateGiftStoryMedia,
  });

  final List<Map<String, dynamic>> gifts;
  final String query;
  final bool canManageIssues;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftWorkspace;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftStoryMedia;

  @override
  Widget build(BuildContext context) {
    final records = adminSearch(gifts, query, const [
      'id',
      'giftId',
      'giftName',
      'title',
      'giftsTeamWorkspace',
      'procurementItemTitle',
      'procurementSupplier',
      'irisGiftRecommendation',
      'approvedGiftPlan',
      'giftIrisLearning',
      'giftStoryEnabled',
      'giftStoryVideoStatus',
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RecordModule(
          title: 'Gift Operations',
          subtitle:
              'Assignment, curation, supplier, experience, budget, parcel review, approval and readiness controls.',
          records: records,
          query: '',
          fields: const [],
          columns: const ['Gift', 'Operations', 'Sourcing', 'Item Review'],
          row: (record) => [
            '${record['giftName'] ?? record['title'] ?? _giftDisplayReference(record)}',
            _giftWorkspaceSummary(record),
            _giftProcurementSummary(record),
            _giftIrisSelectionSummary(record),
          ],
          actions: canManageIssues
              ? (record) => [
                  for (final action in const [
                    ('Assign', 'assigned'),
                    ('Curating', 'curating'),
                    ('Awaiting supplier', 'supplier_pending'),
                    ('Awaiting approval', 'approval_pending'),
                    ('Ready sourcing', 'ready_for_procurement'),
                    ('Ready rider', 'ready_for_rider'),
                    ('Ready scheduling', 'ready_for_scheduling'),
                    ('Ready delivery', 'ready_for_delivery'),
                  ])
                    _MiniAction(
                      label: action.$1,
                      onPressed: () =>
                          unawaited(onUpdateGiftWorkspace(record, action.$2)),
                    ),
                ]
              : null,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Gift Story Media and Video',
          subtitle:
              'Historical Admin controls for Gift Story media, video upload/download, preview readiness and access.',
          records: records.where(_hasGiftStory).toList(growable: false),
          query: '',
          fields: const [],
          columns: const ['Story', 'Audio', 'Video', 'Privacy'],
          row: (record) => [
            '${record['giftName'] ?? record['title'] ?? _giftDisplayReference(record)}',
            _giftStoryAudioSummary(record),
            '${record['giftStoryVideoStatus'] ?? record['videoStatus'] ?? 'not rendered'}',
            '${record['giftStorySharePrivacy'] ?? record['contentUsageScope'] ?? 'private'}',
          ],
          actions: canManageIssues
              ? (record) => [
                  _MiniAction(
                    label: 'Download video',
                    onPressed: () => unawaited(
                      onUpdateGiftStoryMedia(record, 'download_video'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Create upload',
                    onPressed: () => unawaited(
                      onUpdateGiftStoryMedia(record, 'create_video_upload'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Finalize upload',
                    onPressed: () => unawaited(
                      onUpdateGiftStoryMedia(record, 'finalize_video_upload'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Record preview',
                    onPressed: () => unawaited(
                      onUpdateGiftStoryMedia(record, 'record_preview_event'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Update privacy',
                    onPressed: () => unawaited(
                      onUpdateGiftStoryMedia(record, 'update_privacy'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Extend',
                    onPressed: () =>
                        unawaited(onUpdateGiftStoryMedia(record, 'extend')),
                  ),
                  _MiniAction(
                    label: 'Revoke',
                    onPressed: () =>
                        unawaited(onUpdateGiftStoryMedia(record, 'revoke')),
                  ),
                ]
              : null,
        ),
      ],
    );
  }
}

class _TroubleshootingModule extends StatelessWidget {
  const _TroubleshootingModule({
    required this.deliveries,
    required this.payments,
    required this.supportTickets,
    required this.ratings,
    required this.query,
    required this.canManageIssues,
    required this.onOpenDelivery,
    required this.onUpdateSupportTicket,
    required this.onSetDeliveryOperationStatus,
    required this.onUpdateFinanceWorkflow,
    required this.onModerateRating,
  });

  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> ratings;
  final String query;
  final bool canManageIssues;
  final ValueChanged<Map<String, dynamic>> onOpenDelivery;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateSupportTicket;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetDeliveryOperationStatus;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateFinanceWorkflow;
  final Future<void> Function(Map<String, dynamic>, String) onModerateRating;

  @override
  Widget build(BuildContext context) {
    final stuckDeliveries = deliveries.where(_isTroubleshootingDelivery);
    final failedPayments = payments.where(_isTroubleshootingPayment);
    final complaints = supportTickets.where(_isComplaintTicket);
    final refunds = supportTickets.where(_isRefundTicket);
    final lowRatings = ratings.where(_isLowRating);
    final issues = [
      for (final record in stuckDeliveries)
        {'issueType': 'Stuck delivery', '_source': 'delivery', ...record},
      for (final record in failedPayments)
        {'issueType': 'Failed payment', '_source': 'payment', ...record},
      for (final record in complaints)
        {'issueType': 'Complaint', '_source': 'support', ...record},
      for (final record in refunds)
        {'issueType': 'Refund', '_source': 'support', ...record},
      for (final record in lowRatings)
        {'issueType': 'Low rating', '_source': 'rating', ...record},
    ];
    final filtered = adminSearch(issues, query, const [
      'issueType',
      'id',
      'requestId',
      'deliveryId',
      'status',
      'type',
      'message',
      'email',
      'riderId',
      'senderId',
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(
              'Stuck deliveries',
              '${stuckDeliveries.length}',
              'waiting/unassigned/stale',
            ),
            _MetricCard(
              'Failed payments',
              '${failedPayments.length}',
              'payment review',
            ),
            _MetricCard('Complaints', '${complaints.length}', 'support'),
            _MetricCard('Refunds', '${refunds.length}', 'review'),
            _MetricCard('Low ratings', '${lowRatings.length}', 'quality'),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Troubleshooting',
          subtitle:
              'Historical stuck jobs, failed payments, unassigned requests, complaints, refunds and low rating workspace.',
          records: filtered,
          query: '',
          fields: const [],
          columns: const ['Issue', 'Record', 'Priority', 'Status'],
          row: (record) => [
            '${record['issueType']}',
            _recordId(record),
            _troubleshootingPriority(record),
            '${record['status'] ?? record['paymentStatus'] ?? record['reviewStatus'] ?? 'open'}',
          ],
          actions: canManageIssues
              ? (record) => _troubleshootingActions(
                  record,
                  onOpenDelivery: onOpenDelivery,
                  onUpdateSupportTicket: onUpdateSupportTicket,
                  onSetDeliveryOperationStatus: onSetDeliveryOperationStatus,
                  onUpdateFinanceWorkflow: onUpdateFinanceWorkflow,
                  onModerateRating: onModerateRating,
                )
              : null,
        ),
      ],
    );
  }
}

class _HistoricalAnalyticsModule extends StatelessWidget {
  const _HistoricalAnalyticsModule({
    required this.metrics,
    required this.deliveries,
    required this.payments,
    required this.users,
    required this.riders,
    required this.driverPerformanceMetrics,
    required this.giftCampaignMatches,
    required this.irisLearningOutliers,
    required this.healthPlusPickups,
    required this.gifts,
    required this.supportTickets,
  });

  final AdminMetricSnapshot metrics;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> driverPerformanceMetrics;
  final List<Map<String, dynamic>> giftCampaignMatches;
  final List<Map<String, dynamic>> irisLearningOutliers;
  final List<Map<String, dynamic>> healthPlusPickups;
  final List<Map<String, dynamic>> gifts;
  final List<Map<String, dynamic>> supportTickets;

  @override
  Widget build(BuildContext context) {
    final avgDistance = _averageNumber(deliveries, const [
      'distanceMiles',
      'distance',
      'miles',
    ]);
    final avgWeight = _averageNumber(deliveries, const [
      'weightKg',
      'weight',
      'verifiedWeight',
    ]);
    final completionRate = deliveries.isEmpty
        ? 0
        : deliveries.where(_isCompletedRecord).length / deliveries.length * 100;
    final revenue = payments.fold<double>(
      0,
      (total, payment) =>
          total + _numberFrom(payment['amount'] ?? payment['total']),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(
              'Avg distance',
              '${avgDistance.toStringAsFixed(1)} mi',
              'deliveries',
            ),
            _MetricCard(
              'Avg weight',
              '${avgWeight.toStringAsFixed(1)} kg',
              'IRIS',
            ),
            _MetricCard(
              'Avg price',
              _money(metrics.averageDeliveryValue),
              'delivery value',
            ),
            _MetricCard(
              'Completion rate',
              '${completionRate.toStringAsFixed(0)}%',
              'loaded jobs',
            ),
            _MetricCard(
              'Repeat customers',
              '${metrics.repeatCustomerRate.toStringAsFixed(0)}%',
              'users',
            ),
            _MetricCard('Revenue', _money(revenue), 'loaded payments'),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Business intelligence',
          subtitle:
              'Historical standalone Admin analytics for delivery, finance, quality and operations signals.',
          records: [
            {
              'id': 'deliveries',
              'metric': 'Deliveries',
              'count': deliveries.length,
              'value': completionRate,
              'status': 'completion',
            },
            {
              'id': 'users',
              'metric': 'Users',
              'count': users.length,
              'value': metrics.repeatCustomerRate,
              'status': 'repeat customers',
            },
            {
              'id': 'riders',
              'metric': 'Riders',
              'count': riders.length,
              'value': driverPerformanceMetrics.length,
              'status': 'performance records',
            },
            {
              'id': 'gifts',
              'metric': 'Gifts',
              'count': gifts.length,
              'value': giftCampaignMatches.length,
              'status': 'campaign matches',
            },
            {
              'id': 'iris',
              'metric': 'IRIS',
              'count': irisLearningOutliers.length,
              'value': avgWeight,
              'status': 'learning outliers',
            },
            {
              'id': 'health-plus',
              'metric': 'Health+',
              'count': healthPlusPickups.length,
              'value': metrics.healthPlusRecurringRevenue,
              'status': 'recurring revenue',
            },
            {
              'id': 'support',
              'metric': 'Support',
              'count': supportTickets.length,
              'value': metrics.unresolvedSupportIssues,
              'status': 'open issues',
            },
          ],
          query: '',
          fields: const [],
          columns: const ['Report', 'Records', 'Value', 'Status'],
          row: (record) => [
            '${record['metric']}',
            '${record['count']}',
            '${record['value']}',
            '${record['status']}',
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Driver performance analytics',
          subtitle:
              'Historical driver performance metric records used by Admin analytics.',
          records: driverPerformanceMetrics,
          query: '',
          fields: const [],
          columns: const ['Rider', 'Metric', 'Value', 'Updated'],
          row: (record) => [
            '${record['riderId'] ?? record['driverId'] ?? _recordId(record)}',
            '${record['metric'] ?? record['metricName'] ?? record['type'] ?? 'performance'}',
            '${record['value'] ?? record['score'] ?? record['rating'] ?? 'n/a'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
        ),
      ],
    );
  }
}

// ignore: unused_element
class _GiftStoryMediaModule extends StatelessWidget {
  const _GiftStoryMediaModule({
    required this.gifts,
    required this.query,
    required this.canManageIssues,
    required this.onUpdateGiftStoryMedia,
  });

  final List<Map<String, dynamic>> gifts;
  final String query;
  final bool canManageIssues;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftStoryMedia;

  @override
  Widget build(BuildContext context) {
    final records = adminSearch(gifts, query, const [
      'id',
      'giftId',
      'giftName',
      'title',
      'giftStoryEnabled',
      'giftStoryStatus',
      'giftStoryVideoStatus',
      'giftStoryAudioStatus',
      'videoStatus',
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AdminModuleIntro(
          title: 'Gift Story Media',
          subtitle:
              'Historical Admin media and video workflow for Gift Story operations.',
        ),
        const SizedBox(height: 16),
        _RecordModule(
          title: 'Gift Story Media and Video',
          subtitle:
              'Video upload/download, preview readiness, audio status and access lifecycle.',
          records: records,
          query: '',
          fields: const [],
          columns: const ['Story', 'Audio', 'Video', 'Privacy'],
          row: (record) => [
            '${record['giftName'] ?? record['title'] ?? _recordId(record)}',
            _giftStoryAudioSummary(record),
            '${record['giftStoryVideoStatus'] ?? record['videoStatus'] ?? 'not rendered'}',
            '${record['giftStorySharePrivacy'] ?? record['contentUsageScope'] ?? 'private'}',
          ],
          actions: canManageIssues
              ? (record) => [
                  _MiniAction(
                    label: 'Download video',
                    onPressed: () => unawaited(
                      onUpdateGiftStoryMedia(record, 'download_video'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Create upload',
                    onPressed: () => unawaited(
                      onUpdateGiftStoryMedia(record, 'create_video_upload'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Finalize upload',
                    onPressed: () => unawaited(
                      onUpdateGiftStoryMedia(record, 'finalize_video_upload'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Retry story',
                    onPressed: () =>
                        unawaited(onUpdateGiftStoryMedia(record, 'retry')),
                  ),
                  _MiniAction(
                    label: 'Regenerate link',
                    onPressed: () =>
                        unawaited(onUpdateGiftStoryMedia(record, 'regenerate')),
                  ),
                  _MiniAction(
                    label: 'Extend',
                    onPressed: () =>
                        unawaited(onUpdateGiftStoryMedia(record, 'extend')),
                  ),
                  _MiniAction(
                    label: 'Revoke',
                    onPressed: () =>
                        unawaited(onUpdateGiftStoryMedia(record, 'revoke')),
                  ),
                ]
              : null,
        ),
      ],
    );
  }
}

// ignore: unused_element
class _GiftCampaignMatchesModule extends StatelessWidget {
  const _GiftCampaignMatchesModule({
    required this.campaignMatches,
    required this.participants,
    required this.query,
    required this.canManageIssues,
    required this.onUpdateGiftCampaignParticipant,
    required this.onSuggestGiftCampaignMatch,
    required this.onApproveGiftCampaignMatch,
    required this.onBulkGiftCampaignAction,
  });

  final List<Map<String, dynamic>> campaignMatches;
  final List<Map<String, dynamic>> participants;
  final String query;
  final bool canManageIssues;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateGiftCampaignParticipant;
  final Future<void> Function(Map<String, dynamic>, List<Map<String, dynamic>>)
  onSuggestGiftCampaignMatch;
  final Future<void> Function(Map<String, dynamic>, List<Map<String, dynamic>>)
  onApproveGiftCampaignMatch;
  final Future<void> Function(List<Map<String, dynamic>>, String)
  onBulkGiftCampaignAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AdminModuleIntro(
          title: 'Gift Campaign Matches',
          subtitle:
              'Historical campaign match records, participant review and assignment workflow.',
        ),
        const SizedBox(height: 16),
        if (canManageIssues)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniAction(
                  label: 'Bulk approve',
                  onPressed: () => unawaited(
                    onBulkGiftCampaignAction(participants, 'approved'),
                  ),
                ),
                _MiniAction(
                  label: 'Bulk reject',
                  onPressed: () => unawaited(
                    onBulkGiftCampaignAction(participants, 'rejected'),
                  ),
                ),
                _MiniAction(
                  label: 'Bulk assign later',
                  onPressed: () => unawaited(
                    onBulkGiftCampaignAction(participants, 'assign_later'),
                  ),
                ),
                _MiniAction(
                  label: 'Export selected',
                  onPressed: () => unawaited(
                    onBulkGiftCampaignAction(participants, 'exported'),
                  ),
                ),
              ],
            ),
          ),
        _RecordModule(
          title: 'Campaign Match Records',
          subtitle:
              'Approved, rejected and pending anonymous Gift campaign matches.',
          records: adminSearch(campaignMatches, query, const [
            'id',
            'campaignId',
            'campaignName',
            'participantIds',
            'status',
            'matchReason',
          ]),
          query: '',
          fields: const [],
          columns: const ['Match', 'Campaign', 'Participants', 'Status'],
          row: (record) => [
            _recordId(record),
            '${record['campaignName'] ?? record['campaignId'] ?? 'Campaign'}',
            '${record['participantIds'] ?? record['matchedParticipantIds'] ?? 'participants n/a'}',
            '${record['status'] ?? record['matchStatus'] ?? 'pending'}',
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Campaign Participants',
          subtitle:
              'Historical participant review, matching and assignment controls.',
          records: adminSearch(participants, query, const [
            'id',
            'campaignId',
            'campaignName',
            'displayName',
            'userId',
            'matchStatus',
            'suggestedParticipantId',
          ]),
          query: '',
          fields: const [],
          columns: const ['Participant', 'Campaign', 'Match', 'Reason'],
          row: (record) => [
            '${record['displayName'] ?? record['userId'] ?? _recordId(record)}',
            '${record['campaignName'] ?? record['campaignId'] ?? 'Campaign'}',
            '${record['matchStatus'] ?? 'unmatched'} -> ${record['suggestedParticipantId'] ?? 'none'}',
            '${record['suggestedMatchReason'] ?? record['matchReason'] ?? ''}',
          ],
          actions: canManageIssues
              ? (record) => [
                  _MiniAction(
                    label: 'Suggest',
                    onPressed: () => unawaited(
                      onSuggestGiftCampaignMatch(record, participants),
                    ),
                  ),
                  _MiniAction(
                    label: 'Approve match',
                    onPressed: () => unawaited(
                      onApproveGiftCampaignMatch(record, participants),
                    ),
                  ),
                  _MiniAction(
                    label: 'Approve',
                    onPressed: () => unawaited(
                      onUpdateGiftCampaignParticipant(record, 'approved'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Reject',
                    onPressed: () => unawaited(
                      onUpdateGiftCampaignParticipant(record, 'rejected'),
                    ),
                  ),
                  _MiniAction(
                    label: 'Assign later',
                    onPressed: () => unawaited(
                      onUpdateGiftCampaignParticipant(record, 'assign_later'),
                    ),
                  ),
                ]
              : null,
        ),
      ],
    );
  }
}

class _SupportOperationsModule extends StatelessWidget {
  const _SupportOperationsModule({
    required this.tickets,
    required this.deliveries,
    required this.payments,
    required this.chats,
    required this.adminNotes,
    required this.auditLogs,
    required this.query,
    required this.canManageIssues,
    required this.onUpdateSupportTicket,
    required this.onOpenSupportConversation,
    required this.onAddAdminNote,
  });

  final List<Map<String, dynamic>> tickets;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> chats;
  final List<Map<String, dynamic>> adminNotes;
  final List<Map<String, dynamic>> auditLogs;
  final String query;
  final bool canManageIssues;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdateSupportTicket;
  final Future<void> Function(Map<String, dynamic>) onOpenSupportConversation;
  final Future<void> Function(Map<String, dynamic>, String) onAddAdminNote;

  @override
  Widget build(BuildContext context) {
    final filtered = adminSearch(tickets, query, const [
      'id',
      'ticketId',
      'name',
      'email',
      'phone',
      'senderName',
      'riderName',
      'businessName',
      'healthPlusId',
      'giftId',
      'deliveryId',
      'message',
      'status',
      'type',
    ]);
    final open = tickets.where((ticket) => !_isSupportClosed(ticket)).length;
    final assigned = tickets
        .where((ticket) => _hasAnyText(ticket, const ['assigned']))
        .length;
    final escalated = tickets
        .where((ticket) => _hasAnyText(ticket, const ['escalated']))
        .length;
    final waitingCustomer = tickets
        .where(
          (ticket) => _hasAnyText(ticket, const [
            'waiting_customer',
            'waiting customer',
          ]),
        )
        .length;
    final waitingAdmin = tickets
        .where(
          (ticket) =>
              _hasAnyText(ticket, const ['waiting_admin', 'waiting admin']),
        )
        .length;
    final resolvedToday = tickets
        .where(
          (ticket) =>
              _isSupportClosed(ticket) && _isSameDay(ticket, DateTime.now()),
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard('Open tickets', '$open', 'unresolved'),
            _MetricCard('Assigned', '$assigned', 'owned tickets'),
            _MetricCard('Escalated', '$escalated', 'priority support'),
            _MetricCard('Waiting customer', '$waitingCustomer', 'needs reply'),
            _MetricCard('Waiting admin', '$waitingAdmin', 'needs operator'),
            _MetricCard('Resolved today', '$resolvedToday', 'closed today'),
            _MetricCard(
              'Avg response',
              _averageSupportTime(tickets),
              'first response',
            ),
            _MetricCard(
              'Avg resolution',
              _averageSupportResolution(tickets),
              'resolved cases',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Support Queue',
          subtitle:
              'Support queue with Sender, Rider, Business, Health+, Gift and Delivery context.',
          records: filtered,
          query: '',
          fields: const [],
          columns: const ['Ticket', 'Customer', 'State', 'Message'],
          row: (record) => [
            _recordId(record),
            '${record['name'] ?? record['email'] ?? record['senderName'] ?? record['riderName'] ?? 'Customer'}',
            '${record['supportWorkflowStatus'] ?? record['status'] ?? 'open'}',
            '${record['message'] ?? record['type'] ?? ''}',
          ],
          actions: canManageIssues
              ? (record) => _supportActions(
                  record,
                  onUpdateSupportTicket,
                  onOpenSupportConversation,
                  onAddAdminNote,
                )
              : null,
        ),
        const SizedBox(height: 18),
        _AdminNotesPanel(
          title: 'Internal Admin Notes',
          subtitle:
              'Pinned notes, operator notes, timestamps and support history visible only to Admin.',
          records: adminNotes,
          query: query,
          recordType: 'supportTickets',
        ),
        const SizedBox(height: 18),
        _OperationalDetailGrid(
          title: 'Support Drawer',
          records: filtered,
          emptyText: 'No support tickets loaded.',
          rowsFor: (record) => [
            (
              'Customer',
              '${record['name'] ?? record['email'] ?? 'Not recorded'}',
            ),
            (
              'Account',
              '${record['accountId'] ?? record['userId'] ?? record['senderId'] ?? 'Not linked'}',
            ),
            (
              'Delivery',
              '${record['deliveryId'] ?? record['requestId'] ?? 'Not linked'}',
            ),
            (
              'Business',
              '${record['businessId'] ?? record['businessName'] ?? 'Not linked'}',
            ),
            (
              'Health+',
              '${record['healthPlusId'] ?? record['prescriptionPickupId'] ?? 'Not linked'}',
            ),
            (
              'Gift',
              '${record['giftId'] ?? record['giftOrderId'] ?? 'Not linked'}',
            ),
            (
              'Ticket history',
              '${record['history'] ?? record['statusHistory'] ?? 'No history field'}',
            ),
            (
              'Internal notes',
              '${record['internalNotes'] ?? record['adminNote'] ?? 'None'}',
            ),
            (
              'Attachments',
              '${record['attachments'] ?? record['evidenceUrls'] ?? 'None'}',
            ),
            ('Messages', '${_relatedCount(record, chats)} chat threads'),
            ('Previous tickets', '${_relatedCount(record, tickets)} related'),
            (
              'Related deliveries',
              '${_relatedCount(record, deliveries)} deliveries',
            ),
            ('Related payments', '${_relatedCount(record, payments)} payments'),
            ('Audit history', '${_relatedCount(record, auditLogs)} entries'),
          ],
        ),
      ],
    );
  }
}

class _AuditCentreModule extends StatelessWidget {
  const _AuditCentreModule({
    required this.auditLogs,
    required this.users,
    required this.riders,
    required this.businessAccounts,
    required this.deliveries,
    required this.gifts,
    required this.healthPlusPickups,
    required this.supportTickets,
    required this.payments,
    required this.query,
  });

  final List<Map<String, dynamic>> auditLogs;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> businessAccounts;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> gifts;
  final List<Map<String, dynamic>> healthPlusPickups;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> payments;
  final String query;

  @override
  Widget build(BuildContext context) {
    final filtered = adminSearch(auditLogs, query, const [
      'adminUserId',
      'operator',
      'actionType',
      'recordType',
      'recordId',
      'reason',
      'severity',
      'outcome',
    ]);
    final today = auditLogs
        .where((log) => _isSameDay(log, DateTime.now()))
        .length;
    final approvals = auditLogs
        .where((log) => _hasAnyText(log, const ['approve', 'approved']))
        .length;
    final suspensions = auditLogs
        .where((log) => _hasAnyText(log, const ['suspend']))
        .length;
    final refunds = auditLogs
        .where((log) => _hasAnyText(log, const ['refund']))
        .length;
    final overrides = auditLogs
        .where((log) => _hasAnyText(log, const ['override']))
        .length;
    final escalations = auditLogs
        .where((log) => _hasAnyText(log, const ['escalat']))
        .length;
    final critical = auditLogs
        .where((log) => _auditSeverity(log) == 'critical')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard("Today's activity", '$today', 'admin actions'),
            _MetricCard('Approvals', '$approvals', 'approval actions'),
            _MetricCard('Suspensions', '$suspensions', 'account/rider'),
            _MetricCard('Refunds', '$refunds', 'finance actions'),
            _MetricCard('Overrides', '$overrides', 'manual overrides'),
            _MetricCard('Escalations', '$escalations', 'priority events'),
            _MetricCard('Critical', '$critical', 'critical actions'),
            _MetricCard(
              'Recent activity',
              '${auditLogs.length}',
              'loaded logs',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Global Audit Search',
          subtitle:
              'Search Admin, Sender, Rider, Business, Gift, Health+, Delivery, Finance, Support, IRIS and object IDs.',
          records: filtered,
          query: '',
          fields: const [],
          columns: const [
            'Timestamp',
            'Operator',
            'Action',
            'Entity',
            'Reason',
          ],
          row: (record) => [
            _date(record['createdAt'] ?? record['timestamp']),
            '${record['adminUserId'] ?? record['operator'] ?? 'admin'}',
            '${record['actionType'] ?? 'action'}',
            '${record['recordType'] ?? ''}/${record['recordId'] ?? _recordId(record)}',
            '${record['reason'] ?? record['outcome'] ?? ''}',
          ],
        ),
        const SizedBox(height: 18),
        _OperationalDetailGrid(
          title: 'Audit Detail',
          records: filtered,
          emptyText: 'No audit records loaded.',
          rowsFor: (record) => [
            ('Timestamp', _date(record['createdAt'] ?? record['timestamp'])),
            (
              'Operator',
              '${record['adminUserId'] ?? record['operator'] ?? 'admin'}',
            ),
            ('Action', '${record['actionType'] ?? 'action'}'),
            (
              'Affected entity',
              '${record['recordType'] ?? ''}/${record['recordId'] ?? _recordId(record)}',
            ),
            ('Previous value', '${record['oldValue'] ?? 'Not recorded'}'),
            ('Current value', '${record['newValue'] ?? 'Not recorded'}'),
            ('Reason', '${record['reason'] ?? 'No reason recorded'}'),
            ('Source', '${record['source'] ?? 'circum-admin'}'),
            ('Linked objects', _linkedAuditObjects(record)),
            (
              'Supporting notes',
              '${record['notes'] ?? record['adminNote'] ?? 'None'}',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _AuditEntityCoverage(
          users: users,
          riders: riders,
          businessAccounts: businessAccounts,
          deliveries: deliveries,
          gifts: gifts,
          healthPlusPickups: healthPlusPickups,
          supportTickets: supportTickets,
          payments: payments,
          auditLogs: auditLogs,
        ),
      ],
    );
  }
}

class _OperationalDetailGrid extends StatelessWidget {
  const _OperationalDetailGrid({
    required this.title,
    required this.records,
    required this.rowsFor,
    required this.emptyText,
  });

  final String title;
  final List<Map<String, dynamic>> records;
  final List<(String, String)> Function(Map<String, dynamic>) rowsFor;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Full operational context for the latest loaded records.',
              style: TextStyle(color: Colors.white.withValues(alpha: .66)),
            ),
            const SizedBox(height: 18),
            if (records.isEmpty)
              Text(
                emptyText,
                style: TextStyle(color: Colors.white.withValues(alpha: .62)),
              )
            else
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final record in records.take(6))
                    SizedBox(
                      width: 360,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .1),
                          ),
                          color: Colors.white.withValues(alpha: .045),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _recordId(record).isEmpty
                                    ? 'Record'
                                    : _recordId(record),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              for (final row in rowsFor(record))
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 118,
                                        child: Text(
                                          row.$1,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: .62,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          row.$2,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AuditEntityCoverage extends StatelessWidget {
  const _AuditEntityCoverage({
    required this.users,
    required this.riders,
    required this.businessAccounts,
    required this.deliveries,
    required this.gifts,
    required this.healthPlusPickups,
    required this.supportTickets,
    required this.payments,
    required this.auditLogs,
  });

  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> businessAccounts;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> gifts;
  final List<Map<String, dynamic>> healthPlusPickups;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> auditLogs;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Sender', users.length, _auditCount('sender')),
      ('Rider', riders.length, _auditCount('rider')),
      ('Business', businessAccounts.length, _auditCount('business')),
      ('Delivery', deliveries.length, _auditCount('delivery')),
      ('Gift', gifts.length, _auditCount('gift')),
      ('Health+', healthPlusPickups.length, _auditCount('health')),
      ('Support', supportTickets.length, _auditCount('support')),
      ('Finance', payments.length, _auditCount('finance')),
      ('IRIS', deliveries.where(_hasIrisSignal).length, _auditCount('iris')),
      (
        'Wallet',
        payments.where((p) => _hasAnyText(p, const ['wallet'])).length,
        _auditCount('wallet'),
      ),
    ];
    return _RecordModule(
      title: 'Entity Audit',
      subtitle:
          'Audit coverage by operational entity: Sender, Rider, Business, Delivery, Gift, Health+, Support, Finance, IRIS and Wallet.',
      records: [
        for (final row in rows)
          {'entity': row.$1, 'records': row.$2, 'audit': row.$3},
      ],
      query: '',
      fields: const [],
      columns: const ['Entity', 'Loaded records', 'Audit records'],
      row: (record) => [
        '${record['entity']}',
        '${record['records']}',
        '${record['audit']}',
      ],
    );
  }

  int _auditCount(String needle) {
    return auditLogs
        .where((log) => _hasAnyText(log, [needle.toLowerCase()]))
        .length;
  }
}

class _VisitorAnalyticsModule extends StatelessWidget {
  const _VisitorAnalyticsModule({required this.records});

  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) {
    final modes = <String, int>{};
    var signedIn = 0;
    final uniqueUsers = <String>{};
    for (final record in records) {
      final mode = '${record['appMode'] ?? 'unknown'}';
      modes[mode] = (modes[mode] ?? 0) + 1;
      if (record['signedIn'] == true) signedIn += 1;
      final userId = '${record['userId'] ?? ''}'.trim();
      if (userId.isNotEmpty) uniqueUsers.add(userId);
    }
    final topMode = modes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard('Visits', records.length.toString(), 'latest records'),
            _MetricCard('Signed in', signedIn.toString(), 'known sessions'),
            _MetricCard(
              'Known users',
              uniqueUsers.length.toString(),
              'unique user ids',
            ),
            _MetricCard(
              'Top surface',
              topMode.isEmpty ? 'None' : topMode.first.key,
              topMode.isEmpty ? 'no visits' : '${topMode.first.value} visits',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Visitor analytics',
          subtitle: 'Website visit records captured by the public Website.',
          records: records,
          query: '',
          fields: const ['path', 'appMode', 'email', 'url'],
          columns: const ['Path', 'Surface', 'Signed in', 'Created'],
          row: (record) => [
            '${record['path'] ?? '/'}',
            '${record['appMode'] ?? 'unknown'}',
            record['signedIn'] == true
                ? '${record['email'] ?? record['userId'] ?? 'yes'}'
                : 'No',
            _date(record['createdAt']),
          ],
        ),
      ],
    );
  }
}

class _SettingsModule extends StatelessWidget {
  const _SettingsModule({
    required this.canManageAdmins,
    required this.adminUsers,
    required this.platformConfig,
    required this.platformStatus,
    required this.platformNotices,
    required this.platformVersions,
    required this.notifications,
    required this.auditLogs,
    required this.inviteEmail,
    required this.inviteNote,
    required this.inviteRole,
    required this.onInviteRoleChanged,
    required this.onCreateAdminUser,
    required this.onSetAdminUserStatus,
    required this.onSetAdminUserRole,
    required this.announcementTitle,
    required this.announcementBody,
    required this.onSendPlatformAnnouncement,
    required this.onUpdatePlatformRecord,
    required this.onRetryNotificationDelivery,
  });

  final bool canManageAdmins;
  final List<Map<String, dynamic>> adminUsers;
  final List<Map<String, dynamic>> platformConfig;
  final List<Map<String, dynamic>> platformStatus;
  final List<Map<String, dynamic>> platformNotices;
  final List<Map<String, dynamic>> platformVersions;
  final List<Map<String, dynamic>> notifications;
  final List<Map<String, dynamic>> auditLogs;
  final TextEditingController inviteEmail;
  final TextEditingController inviteNote;
  final AdminRole inviteRole;
  final ValueChanged<AdminRole> onInviteRoleChanged;
  final VoidCallback onCreateAdminUser;
  final Future<void> Function(Map<String, dynamic>, String)
  onSetAdminUserStatus;
  final Future<void> Function(Map<String, dynamic>, AdminRole)
  onSetAdminUserRole;
  final TextEditingController announcementTitle;
  final TextEditingController announcementBody;
  final Future<void> Function(String) onSendPlatformAnnouncement;
  final Future<void> Function(Map<String, dynamic>, String)
  onUpdatePlatformRecord;
  final Future<void> Function(Map<String, dynamic>) onRetryNotificationDelivery;

  @override
  Widget build(BuildContext context) {
    final platformRecords = [
      ...platformConfig,
      ...platformStatus,
      ...platformNotices,
      ...platformVersions,
    ];
    final activeServices = platformStatus
        .where((record) => _platformEnabled(record))
        .length;
    final maintenance = platformConfig
        .where((record) => record['maintenanceMode'] == true)
        .length;
    final activeNotices = platformNotices
        .where((record) => _platformPublished(record))
        .length;
    final failedNotifications = notifications
        .where(_notificationNeedsRetry)
        .length;
    final platformAudit = auditLogs
        .where(
          (log) =>
              '${log['actionType'] ?? ''}'.toLowerCase().contains('platform') ||
              '${log['recordType'] ?? ''}'.toLowerCase().contains('platform'),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard(
              'Platform status',
              _platformStatusLabel(platformStatus),
              'existing status records',
            ),
            _MetricCard(
              'Environment',
              _platformEnvironment(platformConfig),
              'loaded configuration',
            ),
            _MetricCard(
              'Active services',
              '$activeServices',
              '${platformStatus.length} status records',
            ),
            _MetricCard(
              'Platform notices',
              '$activeNotices',
              '${platformNotices.length} loaded',
            ),
            _MetricCard(
              'Maintenance',
              maintenance > 0 ? 'Enabled' : 'Off',
              'existing controls',
            ),
            _MetricCard(
              'Versions',
              '${platformVersions.length}',
              'build/version records',
            ),
            _MetricCard(
              'Notifications',
              '$failedNotifications',
              '${notifications.length} loaded / retryable',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Platform Configuration',
          subtitle:
              'Existing configuration records only. Backend remains authoritative.',
          records: platformConfig,
          query: '',
          fields: const ['id', 'key', 'name', 'status', 'environment'],
          columns: const ['Setting', 'Environment', 'Status', 'Updated'],
          row: (record) => [
            '${record['name'] ?? record['key'] ?? record['id']}',
            '${record['environment'] ?? record['env'] ?? 'production'}',
            '${record['adminOperationStatus'] ?? record['status'] ?? record['enabled'] ?? 'recorded'}',
            _date(record['adminUpdatedAt'] ?? record['updatedAt']),
          ],
          actions: canManageAdmins
              ? (record) => _platformActions(record, onUpdatePlatformRecord)
              : null,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'System Status',
          subtitle: 'Existing platform service/status pages from backend data.',
          records: platformStatus,
          query: '',
          fields: const ['id', 'service', 'name', 'status', 'incident'],
          columns: const ['Service', 'Status', 'Incident', 'Updated'],
          row: (record) => [
            '${record['service'] ?? record['name'] ?? record['id']}',
            '${record['status'] ?? record['adminOperationStatus'] ?? 'unknown'}',
            '${record['incident'] ?? record['message'] ?? 'None'}',
            _date(record['adminUpdatedAt'] ?? record['updatedAt']),
          ],
          actions: canManageAdmins
              ? (record) => _platformActions(record, onUpdatePlatformRecord)
              : null,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Version Information',
          subtitle: 'Admin and platform build identifiers already recorded.',
          records: platformVersions,
          query: '',
          fields: const ['id', 'version', 'build', 'environment', 'surface'],
          columns: const ['Surface', 'Version', 'Build', 'Environment'],
          row: (record) => [
            '${record['surface'] ?? record['app'] ?? record['id']}',
            '${record['version'] ?? record['versionName'] ?? 'Not recorded'}',
            '${record['build'] ?? record['buildNumber'] ?? record['commit'] ?? 'Not recorded'}',
            '${record['environment'] ?? record['env'] ?? 'production'}',
          ],
        ),
        const SizedBox(height: 18),
        if (canManageAdmins) ...[
          _AnnouncementComposer(
            title: announcementTitle,
            body: announcementBody,
            onSend: onSendPlatformAnnouncement,
          ),
          const SizedBox(height: 18),
        ],
        _RecordModule(
          title: 'Platform Announcements',
          subtitle:
              'Historical announcement/notices management where records exist.',
          records: platformNotices,
          query: '',
          fields: const ['id', 'title', 'message', 'status', 'audience'],
          columns: const ['Notice', 'Audience', 'Status', 'Updated'],
          row: (record) => [
            '${record['title'] ?? record['name'] ?? record['id']}',
            '${record['audience'] ?? record['surface'] ?? 'platform'}',
            '${record['adminOperationStatus'] ?? record['status'] ?? record['published'] ?? 'draft'}',
            _date(record['adminUpdatedAt'] ?? record['updatedAt']),
          ],
          actions: canManageAdmins
              ? (record) =>
                    _platformNoticeActions(record, onUpdatePlatformRecord)
              : null,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Notification Operations',
          subtitle:
              'Backend-authored notification history, push delivery status, failure handling and Admin retry.',
          records: notifications,
          query: '',
          fields: const [
            'id',
            'recipientId',
            'recipientRole',
            'type',
            'category',
            'deliveryStatus',
            'pushDeliveryStatus',
            'failureReason',
          ],
          columns: const ['Notification', 'Recipient', 'Status', 'Updated'],
          row: (record) => [
            '${record['title'] ?? record['type'] ?? record['id']}',
            '${record['recipientRole'] ?? 'role'} / ${record['recipientId'] ?? 'broadcast'}',
            '${record['deliveryStatus'] ?? 'persisted'} / ${record['pushDeliveryStatus'] ?? 'unknown'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canManageAdmins
              ? (record) => [
                  if (_notificationNeedsRetry(record))
                    _MiniAction(
                      label: 'Retry',
                      onPressed: () =>
                          unawaited(onRetryNotificationDelivery(record)),
                    ),
                ]
              : null,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Platform Audit',
          subtitle:
              'Immutable audit entries for platform operations and setting changes.',
          records: platformAudit,
          query: '',
          fields: const ['actionType', 'recordType', 'recordId', 'reason'],
          columns: const ['Action', 'Record', 'Operator', 'Reason'],
          row: (record) => [
            '${record['actionType'] ?? 'platform_action'}',
            '${record['recordType'] ?? ''}/${record['recordId'] ?? record['id']}',
            '${record['adminUserId'] ?? 'admin'}',
            '${record['reason'] ?? ''}',
          ],
        ),
        const SizedBox(height: 18),
        if (platformRecords.isEmpty)
          DecoratedBox(
            decoration: _panelDecoration(),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'No historical platform configuration, status, notice or version records are loaded.',
                style: TextStyle(color: Colors.white.withValues(alpha: .68)),
              ),
            ),
          ),
        const SizedBox(height: 18),
        if (canManageAdmins) ...[
          DecoratedBox(
            decoration: _panelDecoration(),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Invite Admin user',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Create role-based access records. Passwords and employee credentials stay in Firebase Auth.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .66),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 300,
                        child: TextField(
                          controller: inviteEmail,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Admin email',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: DropdownButtonFormField<AdminRole>(
                          initialValue: inviteRole,
                          decoration: const InputDecoration(
                            labelText: 'Role',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final role in AdminRole.values)
                              DropdownMenuItem(
                                value: role,
                                child: Text(_adminRoleLabel(role.value)),
                              ),
                          ],
                          onChanged: (role) {
                            if (role != null) onInviteRoleChanged(role);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 320,
                        child: TextField(
                          controller: inviteNote,
                          decoration: const InputDecoration(
                            labelText: 'Internal note',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: onCreateAdminUser,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Create access'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        _RecordModule(
          title: 'Settings',
          subtitle: canManageAdmins
              ? 'Admin users and role access records.'
              : 'Your role can view Admin settings but cannot manage access.',
          records: adminUsers,
          query: '',
          fields: const ['email', 'role', 'status'],
          columns: const ['Admin', 'Role', 'Status', 'Last login'],
          row: (record) => [
            '${record['email'] ?? record['id']}',
            _adminRoleLabel('${record['role'] ?? ''}'),
            '${record['status'] ?? 'inactive'}',
            _date(record['lastLoginAt']),
          ],
          actions: canManageAdmins
              ? (record) => _adminUserActions(
                  record,
                  onSetAdminUserStatus,
                  onSetAdminUserRole,
                )
              : null,
        ),
      ],
    );
  }
}

class _AnnouncementComposer extends StatefulWidget {
  const _AnnouncementComposer({
    required this.title,
    required this.body,
    required this.onSend,
  });

  final TextEditingController title;
  final TextEditingController body;
  final Future<void> Function(String) onSend;

  @override
  State<_AnnouncementComposer> createState() => _AnnouncementComposerState();
}

class _AnnouncementComposerState extends State<_AnnouncementComposer> {
  String _audience = 'everyone';

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Announcement Composer',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Historical broadcast workflow using the existing backend announcement callable.',
              style: TextStyle(color: Colors.white.withValues(alpha: .66)),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: widget.title,
                    decoration: const InputDecoration(
                      labelText: 'Announcement title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    initialValue: _audience,
                    decoration: const InputDecoration(
                      labelText: 'Audience',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'everyone',
                        child: Text('Everyone'),
                      ),
                      DropdownMenuItem(
                        value: 'senders',
                        child: Text('Senders'),
                      ),
                      DropdownMenuItem(value: 'riders', child: Text('Riders')),
                      DropdownMenuItem(
                        value: 'business',
                        child: Text('Business accounts'),
                      ),
                      DropdownMenuItem(value: 'health', child: Text('Health+')),
                    ],
                    onChanged: (value) =>
                        setState(() => _audience = value ?? 'everyone'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.body,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => unawaited(widget.onSend(_audience)),
                icon: const Icon(Icons.campaign_rounded),
                label: const Text('Send announcement'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordModule extends StatelessWidget {
  const _RecordModule({
    required this.title,
    required this.subtitle,
    required this.records,
    required this.query,
    required this.fields,
    required this.columns,
    required this.row,
    this.actions,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> records;
  final String query;
  final List<String> fields;
  final List<String> columns;
  final List<String> Function(Map<String, dynamic>) row;
  final List<Widget> Function(Map<String, dynamic>)? actions;

  @override
  Widget build(BuildContext context) {
    final filtered = fields.isEmpty
        ? records
        : adminSearch(records, query, fields);
    return DecoratedBox(
      decoration: _panelDecoration(radius: 20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusPill(label: '${filtered.length} records'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withValues(alpha: .66)),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: _EmptyState('No records found.'),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 64,
                  columnSpacing: 24,
                  horizontalMargin: 12,
                  headingTextStyle: TextStyle(
                    color: Colors.white.withValues(alpha: .58),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                  columns: [
                    for (final column in columns)
                      DataColumn(label: Text(column)),
                    if (actions != null)
                      const DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (final record in filtered.take(80))
                      DataRow(
                        cells: [
                          for (final value in row(record))
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 280,
                                ),
                                child: Text(
                                  value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          if (actions != null)
                            DataCell(
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: actions!(record),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.detail);

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 142, maxWidth: 190),
      child: DecoratedBox(
        decoration: _panelDecoration(radius: 999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .72),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminModuleIntro extends StatelessWidget {
  const _AdminModuleIntro({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withValues(alpha: .68)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(40, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Text(label),
    );
  }
}

String _adminRoleLabel(String value) {
  return switch (value) {
    'super_admin' => 'Super Admin',
    'operations_admin' => 'Operations Admin',
    'support_agent' => 'Support Agent',
    'finance_admin' => 'Finance Admin',
    'driver_manager' => 'Driver Manager',
    _ => 'Not recorded',
  };
}

List<Widget> _adminUserActions(
  Map<String, dynamic> record,
  Future<void> Function(Map<String, dynamic>, String) onSetStatus,
  Future<void> Function(Map<String, dynamic>, AdminRole) onSetRole,
) {
  final active = '${record['status'] ?? ''}'.toLowerCase() == 'active';
  return [
    PopupMenuButton<AdminRole>(
      tooltip: 'Change role',
      onSelected: (role) => unawaited(onSetRole(record, role)),
      itemBuilder: (_) => [
        for (final role in AdminRole.values)
          PopupMenuItem(value: role, child: Text(_adminRoleLabel(role.value))),
      ],
      child: const _MiniActionButton(label: 'Role'),
    ),
    _MiniAction(
      label: active ? 'Deactivate' : 'Activate',
      onPressed: () =>
          unawaited(onSetStatus(record, active ? 'inactive' : 'active')),
    ),
  ];
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: null,
      style: OutlinedButton.styleFrom(
        disabledForegroundColor: Colors.white.withValues(alpha: .9),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(label),
    );
  }
}

List<Widget> _accountActions({
  required Map<String, dynamic> account,
  required String accountType,
  required List<Map<String, dynamic>> allAccounts,
  required void Function(Map<String, dynamic>, String) onOpen,
  required Future<void> Function(Map<String, dynamic>, String) onSetStatus,
  required Future<void> Function(Map<String, dynamic>, Map<String, dynamic>)
  onRequestDuplicateMerge,
  Future<void> Function(Map<String, dynamic>, String)? onAddAdminNote,
  Future<void> Function(Map<String, dynamic>, String)? onUpdateSenderTrust,
}) {
  final status = '${account['accountStatus'] ?? account['status'] ?? ''}'
      .toLowerCase();
  final duplicate = _firstLikelyDuplicate(account, allAccounts);
  final isBusiness = accountType == 'business';
  return [
    _MiniAction(
      label: 'Profile',
      onPressed: () => onOpen(account, accountType),
    ),
    if (!isBusiness && onAddAdminNote != null)
      _MiniAction(
        label: 'Add note',
        onPressed: () => unawaited(onAddAdminNote(account, 'users')),
      ),
    if (!isBusiness && onUpdateSenderTrust != null)
      for (final action in const [
        ('Award trust', 'award'),
        ('Deduct trust', 'deduct'),
        ('Promote', 'promote'),
        ('Demote', 'demote'),
        ('Freeze trust', 'freeze'),
        ('Restore trust', 'restore'),
      ])
        _MiniAction(
          label: action.$1,
          onPressed: () => unawaited(onUpdateSenderTrust(account, action.$2)),
        ),
    if (isBusiness && !status.contains('approved'))
      _MiniAction(
        label: 'Approve',
        onPressed: () => unawaited(onSetStatus(account, 'approved')),
      ),
    if (isBusiness && !status.contains('reject'))
      _MiniAction(
        label: 'Reject',
        onPressed: () => unawaited(onSetStatus(account, 'rejected')),
      ),
    if (status.contains('suspend'))
      _MiniAction(
        label: 'Reactivate',
        onPressed: () => unawaited(onSetStatus(account, 'reactivated')),
      )
    else
      _MiniAction(
        label: 'Suspend',
        onPressed: () => unawaited(onSetStatus(account, 'suspended')),
      ),
    if (!isBusiness)
      _MiniAction(
        label: 'Close review',
        onPressed: () => unawaited(onSetStatus(account, 'closure_review')),
      ),
    if (duplicate != null)
      _MiniAction(
        label: 'Merge review',
        onPressed: () => unawaited(onRequestDuplicateMerge(account, duplicate)),
      ),
  ];
}

Map<String, dynamic>? _firstLikelyDuplicate(
  Map<String, dynamic> account,
  List<Map<String, dynamic>> allAccounts,
) {
  final id = _recordId(account);
  final email = '${account['email'] ?? ''}'.trim().toLowerCase();
  final phone = '${account['phone'] ?? account['phoneNumber'] ?? ''}'.trim();
  if (email.isEmpty && phone.isEmpty) return null;
  for (final candidate in allAccounts) {
    if (_recordId(candidate) == id) continue;
    final candidateEmail = '${candidate['email'] ?? ''}'.trim().toLowerCase();
    final candidatePhone =
        '${candidate['phone'] ?? candidate['phoneNumber'] ?? ''}'.trim();
    if (email.isNotEmpty && candidateEmail == email) return candidate;
    if (phone.isNotEmpty && candidatePhone == phone) return candidate;
  }
  return null;
}

List<Widget> _riderActions(
  Map<String, dynamic> record,
  Future<void> Function(Map<String, dynamic>, String) onSetStatus,
  ValueChanged<Map<String, dynamic>> onOpenProfile, {
  Future<void> Function(Map<String, dynamic>)? onSyncRiderStripe,
  Future<void> Function(Map<String, dynamic>)? onResetRiderStripe,
  Future<void> Function(Map<String, dynamic>)? onRequestMoreInformation,
  Future<void> Function(Map<String, dynamic>)? onRemoveProfilePhoto,
  Future<void> Function(Map<String, dynamic>)? onStartRiderConversation,
}) {
  final status =
      '${record['approvalStatus'] ?? record['driverStatus'] ?? record['status'] ?? ''}'
          .toLowerCase();
  final actions = <Widget>[
    _MiniAction(label: 'Profile', onPressed: () => onOpenProfile(record)),
    if (onSyncRiderStripe != null)
      _MiniAction(
        label: 'Sync Stripe',
        onPressed: () => unawaited(onSyncRiderStripe(record)),
      ),
    if (onResetRiderStripe != null)
      _MiniAction(
        label: 'Reset Stripe',
        onPressed: () => unawaited(onResetRiderStripe(record)),
      ),
    if (onRequestMoreInformation != null)
      _MiniAction(
        label: 'More info',
        onPressed: () => unawaited(onRequestMoreInformation(record)),
      ),
    if (onRemoveProfilePhoto != null)
      _MiniAction(
        label: 'Remove photo',
        onPressed: () => unawaited(onRemoveProfilePhoto(record)),
      ),
    if (onStartRiderConversation != null)
      _MiniAction(
        label: 'Message Rider',
        onPressed: () => unawaited(onStartRiderConversation(record)),
      ),
  ];
  if (status.contains('suspend')) {
    return [
      ...actions,
      _MiniAction(
        label: 'Reactivate',
        onPressed: () => unawaited(onSetStatus(record, 'approved')),
      ),
    ];
  }
  if (status.contains('reject')) {
    return [
      ...actions,
      _MiniAction(
        label: 'Reactivate',
        onPressed: () => unawaited(onSetStatus(record, 'approved')),
      ),
    ];
  }
  if (status.contains('active') ||
      status.contains('approve') ||
      status.contains('verified')) {
    return [
      ...actions,
      _MiniAction(
        label: 'Suspend',
        onPressed: () => unawaited(onSetStatus(record, 'suspended')),
      ),
    ];
  }
  return [
    ...actions,
    _MiniAction(
      label: 'Approve',
      onPressed: () => unawaited(onSetStatus(record, 'approved')),
    ),
    _MiniAction(
      label: 'Reject',
      onPressed: () => unawaited(onSetStatus(record, 'rejected')),
    ),
  ];
}

List<Widget> _deliveryActions(
  Map<String, dynamic> record, {
  required bool canDuplicateDeliveries,
  required bool canEditDeliveries,
  required ValueChanged<Map<String, dynamic>> onOpen,
  required ValueChanged<Map<String, dynamic>> onDuplicate,
  required Future<void> Function(Map<String, dynamic>, String) onSetStatus,
  required Future<void> Function(Map<String, dynamic>)
  onResolveStaleDeliveryLock,
  required Future<void> Function(Map<String, dynamic>) onArchiveDelivery,
}) {
  return [
    _MiniAction(label: 'Details', onPressed: () => onOpen(record)),
    if (canDuplicateDeliveries)
      _MiniAction(label: 'Duplicate', onPressed: () => onDuplicate(record)),
    if (canEditDeliveries) ...[
      _MiniAction(
        label: 'Escalate',
        onPressed: () => unawaited(onSetStatus(record, 'escalated')),
      ),
      _MiniAction(
        label: 'Waiting',
        onPressed: () => unawaited(onSetStatus(record, 'waiting_review')),
      ),
      _MiniAction(
        label: 'No-show',
        onPressed: () => unawaited(onSetStatus(record, 'no_show_review')),
      ),
      _MiniAction(
        label: 'Fraud',
        onPressed: () => unawaited(onSetStatus(record, 'fraud_flagged')),
      ),
      if (_isStaleDelivery(record))
        _MiniAction(
          label: 'Resolve lock',
          onPressed: () => unawaited(onResolveStaleDeliveryLock(record)),
        ),
      if (!_isArchivedDelivery(record))
        _MiniAction(
          label: 'Archive',
          onPressed: () => unawaited(onArchiveDelivery(record)),
        ),
    ],
  ];
}

List<Widget> _irisReferenceImageActions(
  Map<String, dynamic> record, {
  required Future<void> Function(Map<String, dynamic>) onLoadReferenceImage,
  required Future<void> Function(Map<String, dynamic>) onFinalizeReferenceImage,
  required Future<void> Function(Map<String, dynamic>) onDeleteReferenceImage,
}) {
  return [
    _MiniAction(
      label: 'Open image',
      onPressed: () => unawaited(onLoadReferenceImage(record)),
    ),
    _MiniAction(
      label: 'Finalise',
      onPressed: () => unawaited(onFinalizeReferenceImage(record)),
    ),
    _MiniAction(
      label: 'Remove',
      onPressed: () => unawaited(onDeleteReferenceImage(record)),
    ),
  ];
}

class _AccountProfileDrawer extends StatelessWidget {
  const _AccountProfileDrawer({
    required this.account,
    required this.accountType,
    required this.deliveries,
    required this.payments,
    required this.supportTickets,
    required this.giftOrders,
    required this.businessAccounts,
    required this.users,
    required this.onClose,
    required this.onSetSenderStatus,
    required this.onSetBusinessStatus,
    required this.onRequestDuplicateMerge,
  });

  final Map<String, dynamic> account;
  final String accountType;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> giftOrders;
  final List<Map<String, dynamic>> businessAccounts;
  final List<Map<String, dynamic>> users;
  final VoidCallback onClose;
  final Future<void> Function(String) onSetSenderStatus;
  final Future<void> Function(String) onSetBusinessStatus;
  final Future<void> Function(Map<String, dynamic>) onRequestDuplicateMerge;

  @override
  Widget build(BuildContext context) {
    final accountId = _recordId(account);
    final relatedDeliveries = deliveries
        .where((item) => _recordReferencesAccount(item, accountId, account))
        .toList();
    final relatedPayments = payments
        .where((item) => _recordReferencesAccount(item, accountId, account))
        .toList();
    final relatedTickets = supportTickets
        .where((item) => _recordReferencesAccount(item, accountId, account))
        .toList();
    final relatedGifts = giftOrders
        .where((item) => _recordReferencesAccount(item, accountId, account))
        .toList();
    final duplicate = _firstLikelyDuplicate(
      account,
      accountType == 'business' ? businessAccounts : users,
    );
    final title = accountType == 'business'
        ? '${account['businessName'] ?? account['companyName'] ?? accountId}'
        : '${account['fullName'] ?? account['name'] ?? account['email'] ?? accountId}';
    return Drawer(
      width: 460,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              accountType == 'business' ? 'Business account' : 'Sender account',
              style: TextStyle(color: Colors.white.withValues(alpha: .62)),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(
                  label:
                      '${account['status'] ?? account['accountStatus'] ?? 'active'}',
                ),
                _StatusPill(
                  label:
                      '${account['verificationStatus'] ?? account['kycStatus'] ?? 'unverified'}',
                ),
              ],
            ),
            const SizedBox(height: 18),
            _DrawerSection(
              title: 'Profile',
              rows: [
                ('ID', accountId),
                ('Email', '${account['email'] ?? 'Not recorded'}'),
                (
                  'Phone',
                  '${account['phone'] ?? account['phoneNumber'] ?? 'Not recorded'}',
                ),
                ('Created', _date(account['createdAt'])),
                ('Last login', _date(account['lastLoginAt'])),
              ],
            ),
            _DrawerSection(
              title: 'History',
              rows: [
                ('Deliveries', '${relatedDeliveries.length}'),
                ('Wallet/payment records', '${relatedPayments.length}'),
                ('Support/disputes', '${relatedTickets.length}'),
                ('Gifts', '${relatedGifts.length}'),
                (
                  'Devices',
                  _historyCount(account, const ['devices', 'deviceHistory']),
                ),
                (
                  'Notifications',
                  _historyCount(account, const [
                    'notifications',
                    'notificationHistory',
                  ]),
                ),
              ],
            ),
            _DrawerSection(
              title: 'Recent delivery history',
              rows: [
                for (final delivery in relatedDeliveries.take(5))
                  (
                    _recordId(delivery),
                    '${delivery['status'] ?? delivery['deliveryStatus'] ?? 'unknown'}',
                  ),
                if (relatedDeliveries.isEmpty) ('None', 'No records loaded'),
              ],
            ),
            _DrawerSection(
              title: 'Wallet and dispute history',
              rows: [
                for (final payment in relatedPayments.take(4))
                  (
                    _recordId(payment),
                    '${payment['status'] ?? 'unknown'} ${_money(payment['amount'] ?? payment['total'])}',
                  ),
                for (final ticket in relatedTickets.take(4))
                  (
                    _recordId(ticket),
                    '${ticket['type'] ?? 'support'} ${ticket['status'] ?? 'open'}',
                  ),
                if (relatedPayments.isEmpty && relatedTickets.isEmpty)
                  ('None', 'No records loaded'),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (accountType == 'business') ...[
                  _MiniAction(
                    label: 'Approve',
                    onPressed: () => unawaited(onSetBusinessStatus('approved')),
                  ),
                  _MiniAction(
                    label: 'Suspend',
                    onPressed: () =>
                        unawaited(onSetBusinessStatus('suspended')),
                  ),
                  _MiniAction(
                    label: 'Reactivate',
                    onPressed: () =>
                        unawaited(onSetBusinessStatus('reactivated')),
                  ),
                ] else ...[
                  _MiniAction(
                    label: 'Suspend',
                    onPressed: () => unawaited(onSetSenderStatus('suspended')),
                  ),
                  _MiniAction(
                    label: 'Reactivate',
                    onPressed: () =>
                        unawaited(onSetSenderStatus('reactivated')),
                  ),
                  _MiniAction(
                    label: 'Close review',
                    onPressed: () =>
                        unawaited(onSetSenderStatus('closure_review')),
                  ),
                ],
                if (duplicate != null)
                  _MiniAction(
                    label: 'Request merge review',
                    onPressed: () =>
                        unawaited(onRequestDuplicateMerge(duplicate)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthPlusOperationsDrawer extends StatelessWidget {
  const _HealthPlusOperationsDrawer({
    required this.record,
    required this.deliveries,
    required this.supportTickets,
    required this.auditLogs,
    required this.onClose,
    required this.onSetStatus,
  });

  final Map<String, dynamic> record;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> auditLogs;
  final VoidCallback onClose;
  final Future<void> Function(String) onSetStatus;

  @override
  Widget build(BuildContext context) {
    final id = _recordId(record);
    final relatedDeliveries = deliveries
        .where((item) => _recordReferencesDelivery(item, id))
        .toList();
    final relatedTickets = supportTickets
        .where(
          (item) =>
              _recordReferencesDelivery(item, id) ||
              '${item['email'] ?? ''}' ==
                  '${record['email'] ?? record['senderEmail'] ?? ''}',
        )
        .toList();
    final relatedAudit = auditLogs
        .where((item) => '${item['recordId'] ?? ''}'.trim() == id)
        .toList();
    return Drawer(
      width: 500,
      backgroundColor: const Color(0xFF07090F),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Health+ $id',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              '${record['status'] ?? record['clinicalReviewStatus'] ?? 'pending'}',
              style: TextStyle(color: Colors.white.withValues(alpha: .62)),
            ),
            const SizedBox(height: 18),
            _DrawerSection(
              title: 'Patient and sender',
              rows: [
                ('Patient', record['patientName'] ?? record['fullName']),
                ('Sender', record['senderName'] ?? record['senderEmail']),
                ('Recipient', record['recipientName']),
                ('Booking ID', record['bookingId']),
                ('Prescription ID', record['prescriptionId']),
              ],
            ),
            _DrawerSection(
              title: 'Pharmacy and medication',
              rows: [
                (
                  'Pharmacy',
                  record['pharmacyName'] ?? record['pharmacyAddress'],
                ),
                (
                  'Medication',
                  record['medication'] ?? record['medicationName'],
                ),
                ('Verification', record['verificationStatus']),
                ('Clinical review', record['clinicalReviewStatus']),
                ('Controlled medication', record['controlledMedication']),
              ],
            ),
            _DrawerSection(
              title: 'Collection and delivery',
              rows: [
                (
                  'Assigned rider',
                  record['assignedDriverId'] ?? record['riderId'],
                ),
                (
                  'Collection status',
                  record['collectionStatus'] ?? record['status'],
                ),
                ('Pickup time', record['pickupTime']),
                ('Collected', _date(record['collectedAt'])),
                (
                  'Delivered',
                  _date(record['completedAt'] ?? record['deliveredAt']),
                ),
                (
                  'Evidence',
                  _historyCount(record, const ['evidence', 'photos', 'images']),
                ),
              ],
            ),
            _DrawerSection(
              title: 'Handling',
              rows: [
                ('Temperature', record['temperatureRequirement']),
                ('Special handling', record['specialHandling']),
                ('Urgent', record['urgent']),
                ('Escalation', record['escalationStatus']),
              ],
            ),
            _DrawerSection(
              title: 'Support and audit',
              rows: [
                ('Related deliveries', relatedDeliveries.length),
                ('Support cases', relatedTickets.length),
                for (final audit in relatedAudit.take(4))
                  (
                    '${audit['actionType'] ?? 'action'}',
                    _date(audit['createdAt']),
                  ),
                if (relatedAudit.isEmpty) ('Audit', 'No audit records loaded'),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in const [
                  ('Assign pharmacy', 'pharmacy_assigned'),
                  ('Reassign pharmacy', 'pharmacy_reassigned'),
                  ('Assign rider', 'rider_assigned'),
                  ('Escalate', 'escalated'),
                  ('Approve review', 'review_approved'),
                  ('Reject review', 'review_rejected'),
                  ('Request evidence', 'evidence_requested'),
                  ('Pause', 'paused'),
                  ('Resume', 'resumed'),
                  ('Close case', 'closed'),
                ])
                  _MiniAction(
                    label: action.$1,
                    onPressed: () => unawaited(onSetStatus(action.$2)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderProfileDrawer extends StatelessWidget {
  const _RiderProfileDrawer({
    required this.rider,
    required this.deliveries,
    required this.documents,
    required this.ratings,
    required this.supportTickets,
    required this.auditLogs,
    required this.onClose,
    required this.onSetStatus,
  });

  final Map<String, dynamic> rider;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> ratings;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> auditLogs;
  final VoidCallback onClose;
  final Future<void> Function(String) onSetStatus;

  @override
  Widget build(BuildContext context) {
    final riderId = _riderId(rider);
    final riderDeliveries = deliveries
        .where((delivery) => _deliveryBelongsToRider(delivery, riderId))
        .toList(growable: false);
    final riderDocs = documents
        .where((document) => _documentBelongsToRider(document, riderId))
        .toList(growable: false);
    final riderRatings = ratings
        .where((rating) => _recordReferencesRider(rating, riderId))
        .toList(growable: false);
    final riderTickets = supportTickets
        .where((ticket) => _recordReferencesRider(ticket, riderId))
        .toList(growable: false);
    final riderAudit = auditLogs
        .where(
          (audit) =>
              '${audit['recordId'] ?? ''}'.trim() == riderId ||
              '${audit['recordType'] ?? ''}'.contains('rider'),
        )
        .toList(growable: false);
    final completed = riderDeliveries
        .where(
          (delivery) =>
              '${delivery['status'] ?? delivery['deliveryStatus'] ?? ''}'
                  .toLowerCase()
                  .contains('complete') ||
              '${delivery['status'] ?? delivery['deliveryStatus'] ?? ''}'
                  .toLowerCase()
                  .contains('delivered'),
        )
        .length;
    final active = riderDeliveries.length - completed;
    final earnings = riderDeliveries.fold<double>(0, (total, delivery) {
      final value =
          delivery['riderPayout'] ??
          delivery['driverPayout'] ??
          delivery['estimatedDriverPayout'];
      if (value is num) return total + value.toDouble();
      return total + (double.tryParse('$value') ?? 0);
    });
    return Drawer(
      width: 420,
      backgroundColor: const Color(0xFF07090F),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Rider profile',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            DecoratedBox(
              decoration: _panelDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _RiderAvatar(rider: rider),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${rider['fullName'] ?? rider['name'] ?? 'Rider'}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${rider['email'] ?? 'No email recorded'}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .66),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _InfoPill('Rank', RiderRankPolicy.fromProfile(rider)),
                        _InfoPill(
                          'Approval',
                          '${rider['approvalStatus'] ?? rider['driverStatus'] ?? 'pending'}',
                        ),
                        _InfoPill(
                          'Verification',
                          '${rider['verificationStatus'] ?? 'pending'}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _DrawerSection(
              title: 'Personal details',
              rows: [
                ('Rider ID', riderId),
                ('Phone', rider['phoneNumber'] ?? rider['phone']),
                ('Address', _addressSummary(rider)),
                ('City', rider['city']),
                ('Vehicle', rider['vehicleType'] ?? rider['vehicle']),
                ('Plate', rider['plateNumber'] ?? rider['vehicleRegistration']),
                ('Joined', _date(rider['createdAt'])),
                ('Last updated', _date(rider['updatedAt'])),
                (
                  'Stripe',
                  rider['stripeStatus'] ?? rider['stripeAccountStatus'],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DrawerSection(
              title: 'Performance',
              rows: [
                ('Completed jobs', completed),
                ('Active jobs', active < 0 ? 0 : active),
                ('Known deliveries', riderDeliveries.length),
                ('Estimated earnings', _money(earnings)),
                ('Rating', rider['rating'] ?? rider['averageRating']),
                ('Trust tier', rider['trustTier'] ?? rider['trustLevel']),
                (
                  'Trust progress',
                  rider['trustProgress'] ?? rider['trustScore'],
                ),
                (
                  'Online duration',
                  rider['onlineDuration'] ?? rider['onlineSince'],
                ),
                ('Battery', rider['batteryLevel']),
              ],
            ),
            const SizedBox(height: 14),
            _DrawerSection(
              title: 'GPS health',
              rows: [
                (
                  'Current state',
                  rider['currentState'] ?? rider['availability'],
                ),
                ('Current delivery', rider['currentDeliveryId']),
                ('Last location', _locationSummary(rider)),
                ('GPS freshness', _date(rider['lastLocationAt'])),
                ('Jobs today', _jobsSince(riderDeliveries, DateTime.now())),
                (
                  'Earnings today',
                  _money(_earningsSince(riderDeliveries, DateTime.now())),
                ),
                ('Weekly earnings', _money(_earningsThisWeek(riderDeliveries))),
              ],
            ),
            const SizedBox(height: 14),
            _DrawerSection(
              title: 'Documents',
              rows: riderDocs.isEmpty
                  ? const [('Documents', 'No documents found')]
                  : [
                      for (final doc in riderDocs.take(8))
                        (
                          '${doc['type'] ?? doc['documentType'] ?? 'Document'}',
                          doc['status'] ??
                              doc['verificationStatus'] ??
                              'pending',
                        ),
                    ],
            ),
            const SizedBox(height: 14),
            _DrawerSection(
              title: 'Insurance, MOT and V5C',
              rows: [
                ('Insurance', _documentStatus(riderDocs, 'insurance')),
                ('MOT', _documentStatus(riderDocs, 'mot')),
                ('V5C', _documentStatus(riderDocs, 'v5c')),
                ('Vehicle review', rider['vehicleVerificationStatus']),
              ],
            ),
            const SizedBox(height: 14),
            _DrawerSection(
              title: 'Recent operations',
              rows: [
                for (final delivery in riderDeliveries.take(4))
                  (
                    _recordId(delivery),
                    '${delivery['status'] ?? delivery['deliveryStatus'] ?? 'unknown'}',
                  ),
                for (final rating in riderRatings.take(3))
                  (
                    'Rating',
                    '${rating['starRating'] ?? rating['rating'] ?? 'unknown'} ${rating['feedback'] ?? ''}',
                  ),
                for (final ticket in riderTickets.take(3))
                  (
                    _recordId(ticket),
                    '${ticket['status'] ?? 'open'} ${ticket['type'] ?? 'support'}',
                  ),
                if (riderDeliveries.isEmpty &&
                    riderRatings.isEmpty &&
                    riderTickets.isEmpty)
                  ('None', 'No recent rider operations loaded'),
              ],
            ),
            const SizedBox(height: 14),
            _DrawerSection(
              title: 'Audit history',
              rows: [
                for (final audit in riderAudit.take(6))
                  (
                    '${audit['actionType'] ?? 'action'}',
                    _date(audit['createdAt']),
                  ),
                if (riderAudit.isEmpty) ('None', 'No audit records loaded'),
              ],
            ),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: _panelDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status actions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MiniAction(
                          label: 'Approve',
                          onPressed: () => unawaited(onSetStatus('approved')),
                        ),
                        _MiniAction(
                          label: 'Suspend',
                          onPressed: () => unawaited(onSetStatus('suspended')),
                        ),
                        _MiniAction(
                          label: 'Reject',
                          onPressed: () => unawaited(onSetStatus('rejected')),
                        ),
                        _MiniAction(
                          label: 'Request docs',
                          onPressed: () =>
                              unawaited(onSetStatus('documents_requested')),
                        ),
                        _MiniAction(
                          label: 'Approve docs',
                          onPressed: () =>
                              unawaited(onSetStatus('documents_approved')),
                        ),
                        _MiniAction(
                          label: 'Reject docs',
                          onPressed: () =>
                              unawaited(onSetStatus('documents_rejected')),
                        ),
                        _MiniAction(
                          label: 'Investigate',
                          onPressed: () =>
                              unawaited(onSetStatus('under_investigation')),
                        ),
                        _MiniAction(
                          label: 'Clear investigation',
                          onPressed: () =>
                              unawaited(onSetStatus('investigation_cleared')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryOperationsDrawer extends StatelessWidget {
  const _DeliveryOperationsDrawer({
    required this.delivery,
    required this.riders,
    required this.payments,
    required this.supportTickets,
    required this.chats,
    required this.auditLogs,
    required this.onClose,
    required this.onSetStatus,
  });

  final Map<String, dynamic> delivery;
  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> chats;
  final List<Map<String, dynamic>> auditLogs;
  final VoidCallback onClose;
  final Future<void> Function(String) onSetStatus;

  @override
  Widget build(BuildContext context) {
    final deliveryId = _recordId(delivery);
    final rider = _assignedRiderForDelivery(delivery, riders);
    final relatedPayments = payments
        .where((item) => _recordReferencesDelivery(item, deliveryId))
        .toList();
    final relatedTickets = supportTickets
        .where((item) => _recordReferencesDelivery(item, deliveryId))
        .toList();
    final relatedChats = chats
        .where((item) => _recordReferencesDelivery(item, deliveryId))
        .toList();
    final relatedAudit = auditLogs
        .where((item) => '${item['recordId'] ?? ''}'.trim() == deliveryId)
        .toList();
    return Drawer(
      width: 500,
      backgroundColor: const Color(0xFF07090F),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Delivery $deliveryId',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              '${delivery['status'] ?? delivery['deliveryStatus'] ?? 'unknown'}',
              style: TextStyle(color: Colors.white.withValues(alpha: .62)),
            ),
            const SizedBox(height: 18),
            _DrawerSection(
              title: 'Timeline',
              rows: [
                ('Created', _date(delivery['createdAt'])),
                ('Accepted', _date(delivery['acceptedAt'])),
                ('Collected', _date(delivery['collectedAt'])),
                ('Completed', _date(delivery['completedAt'])),
                ('Admin status', delivery['adminOperationStatus']),
              ],
            ),
            _DrawerSection(
              title: 'Sender and recipient',
              rows: [
                ('Sender', delivery['senderName'] ?? delivery['senderEmail']),
                ('Sender ID', delivery['senderId'] ?? delivery['userId']),
                ('Recipient', delivery['recipientName']),
                ('Recipient phone', delivery['recipientPhone']),
              ],
            ),
            _DrawerSection(
              title: 'Rider and vehicle',
              rows: [
                (
                  'Rider',
                  rider?['fullName'] ??
                      delivery['riderId'] ??
                      delivery['assignedRiderId'],
                ),
                ('Vehicle', rider?['vehicleType'] ?? delivery['vehicleType']),
                (
                  'Registration',
                  rider?['plateNumber'] ?? rider?['vehicleRegistration'],
                ),
                (
                  'Rider state',
                  rider?['driverStatus'] ?? rider?['availability'],
                ),
              ],
            ),
            _DrawerSection(
              title: 'Route and live map',
              rows: [
                ('Pickup', delivery['pickupAddress'] ?? delivery['pickup']),
                ('Dropoff', delivery['dropoffAddress'] ?? delivery['dropoff']),
                ('Stops', delivery['stops'] ?? delivery['stopCount']),
                ('ETA', delivery['eta'] ?? delivery['estimatedArrival']),
                ('Last location', _locationSummary(delivery)),
              ],
            ),
            _DrawerSection(
              title: 'Pricing, wallet and Stripe',
              rows: [
                (
                  'Final amount',
                  _money(delivery['finalAmount'] ?? delivery['price']),
                ),
                (
                  'Quote',
                  _money(delivery['quote'] ?? delivery['estimatedPrice']),
                ),
                ('Payment', delivery['paymentStatus'] ?? delivery['paidState']),
                (
                  'Stripe',
                  delivery['stripePaymentIntentId'] ??
                      delivery['paymentIntent'],
                ),
                ('Wallet records', relatedPayments.length),
              ],
            ),
            _DrawerSection(
              title: 'IRIS and Vanguard',
              rows: [
                ('IRIS estimate', delivery['iris'] ?? delivery['irisEstimate']),
                (
                  'Verified weight',
                  delivery['verifiedWeight'] ?? delivery['riderVerifiedWeight'],
                ),
                (
                  'Confidence',
                  delivery['confidence'] ?? delivery['irisConfidence'],
                ),
                (
                  'IRIS review',
                  delivery['irisReviewStatus'] ?? delivery['reviewType'],
                ),
                ('Vanguard enabled', _hasVanguardProtection(delivery)),
                (
                  'PIN state',
                  delivery['pinVerificationStatus'] ??
                      delivery['vanguardStatus'],
                ),
              ],
            ),
            if (_hasVanguardProtection(delivery))
              _DrawerSection(
                title: 'Enhanced Custody Review',
                rows: [
                  ('Review status', _enhancedCustodyStatus(delivery)),
                  (
                    'Custody integrity',
                    delivery['custodyIntegrityStatus'] ??
                        delivery['chainOfCustodyStatus'] ??
                        delivery['enhancedCustodyStatus'],
                  ),
                  (
                    'Chain of custody',
                    _historyCount(delivery, const [
                      'chainOfCustody',
                      'custodyTimeline',
                      'custodyEvents',
                    ]),
                  ),
                  (
                    'Collection evidence',
                    _historyCount(delivery, const [
                      'collectionEvidence',
                      'pickupEvidence',
                      'collectionPhotos',
                    ]),
                  ),
                  (
                    'Transfer evidence',
                    _historyCount(delivery, const [
                      'transferEvidence',
                      'handoffEvidence',
                      'custodyTransfers',
                    ]),
                  ),
                  (
                    'Drop-off evidence',
                    _historyCount(delivery, const [
                      'dropoffEvidence',
                      'deliveryEvidence',
                      'proofOfDelivery',
                    ]),
                  ),
                  (
                    'Proof timeline',
                    _enhancedCustodyCheckpointSummary(delivery),
                  ),
                  (
                    'Evidence history',
                    _enhancedCustodyEvidenceSummary(delivery),
                  ),
                ],
              ),
            _DrawerSection(
              title: 'Evidence, messages and support',
              rows: [
                (
                  'Evidence',
                  _historyCount(delivery, const [
                    'evidence',
                    'photos',
                    'images',
                  ]),
                ),
                (
                  'PIN history',
                  _historyCount(delivery, const [
                    'pinHistory',
                    'verificationAttempts',
                  ]),
                ),
                ('Messages', relatedChats.length),
                ('Support cases', relatedTickets.length),
              ],
            ),
            _DrawerSection(
              title: 'Audit history',
              rows: [
                for (final audit in relatedAudit.take(6))
                  (
                    '${audit['actionType'] ?? 'action'}',
                    _date(audit['createdAt']),
                  ),
                if (relatedAudit.isEmpty) ('None', 'No audit records loaded'),
              ],
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: _panelDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delivery actions',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final action in const [
                          ('Pause', 'paused'),
                          ('Resume', 'resumed'),
                          ('Escalate', 'escalated'),
                          ('Cancel review', 'cancel_review'),
                          ('Force complete review', 'force_complete_review'),
                          ('Archive review', 'archive_review'),
                          ('Waiting review', 'waiting_review'),
                          ('No-show review', 'no_show_review'),
                          ('IRIS override review', 'iris_review_override'),
                          ('Flag fraud', 'fraud_flagged'),
                        ])
                          _MiniAction(
                            label: action.$1,
                            onPressed: () => unawaited(onSetStatus(action.$2)),
                          ),
                        if (_hasVanguardProtection(delivery))
                          for (final action in const [
                            (
                              'Flag custody concern',
                              'vanguard_custody_flagged',
                            ),
                            ('Escalate custody', 'vanguard_custody_escalated'),
                            (
                              'Request custody evidence',
                              'vanguard_evidence_requested',
                            ),
                            (
                              'Reopen custody review',
                              'vanguard_custody_reopened',
                            ),
                            ('Close custody review', 'vanguard_custody_closed'),
                            (
                              'Assign custody reviewer',
                              'vanguard_reviewer_assigned',
                            ),
                          ])
                            _MiniAction(
                              label: action.$1,
                              onPressed: () =>
                                  unawaited(onSetStatus(action.$2)),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderAvatar extends StatelessWidget {
  const _RiderAvatar({required this.rider});

  final Map<String, dynamic> rider;

  @override
  Widget build(BuildContext context) {
    final url = '${rider['profilePhotoUrl'] ?? rider['photoUrl'] ?? ''}'.trim();
    return CircleAvatar(
      radius: 34,
      backgroundColor: const Color(0xFF0EA5E9).withValues(alpha: .18),
      foregroundImage: url.isEmpty ? null : NetworkImage(url),
      child: url.isEmpty
          ? const Icon(Icons.person_rounded, size: 34, color: Color(0xFF7DD3FC))
          : null,
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill(this.label, this.value);

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text('$label: ${value ?? 'Not recorded'}'),
      ),
    );
  }
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection({required this.title, required this.rows});

  final String title;
  final List<(String, Object?)> rows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 128,
                      child: Text(
                        row.$1,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .62),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${row.$2 ?? 'Not recorded'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModuleButton extends StatelessWidget {
  const _ModuleButton({
    required this.module,
    required this.selected,
    required this.onTap,
  });

  final AdminModule module;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        selected: selected,
        selectedTileColor: const Color(0xFF0EA5E9).withValues(alpha: .18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(module.icon),
        title: Text(module.label),
        onTap: onTap,
      ),
    );
  }
}

class _AdminNotice extends StatelessWidget {
  const _AdminNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0EA5E9).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF7DD3FC).withValues(alpha: .24),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
    );
  }
}

BoxDecoration _panelDecoration({double radius = 18}) {
  return BoxDecoration(
    color: Colors.white.withValues(alpha: .06),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withValues(alpha: .12)),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: .09),
        const Color(0xFF7C3AED).withValues(alpha: .035),
        const Color(0xFF22D3EE).withValues(alpha: .025),
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF0EA5E9).withValues(alpha: .08),
        blurRadius: 24,
        offset: const Offset(0, 12),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: .20),
        blurRadius: 28,
        offset: const Offset(0, 14),
      ),
    ],
  );
}

String _adminInitials(String? email) {
  final clean = (email ?? 'A').trim();
  if (clean.isEmpty) return 'A';
  final name = clean.split('@').first;
  final parts = name.split(RegExp(r'[._\-\s]+')).where((p) => p.isNotEmpty);
  final initials = parts.take(2).map((p) => p[0].toUpperCase()).join();
  return initials.isEmpty ? clean[0].toUpperCase() : initials;
}

String _recordId(Map<String, dynamic> record) {
  return '${record['requestId'] ?? record['threadId'] ?? record['id'] ?? ''}';
}

String _riderId(Map<String, dynamic> rider) {
  return '${rider['id'] ?? rider['uid'] ?? rider['riderId'] ?? rider['driverId'] ?? ''}'
      .trim();
}

String _canonicalSenderTrustTier(Object? value) {
  final raw = '$value'.trim().toLowerCase().replaceAll(RegExp(r'[-\s]+'), '_');
  const tiers = {
    'new_sender',
    'active_sender',
    'regular_sender',
    'priority_sender',
    'platinum_sender',
  };
  if (tiers.contains(raw)) return raw;
  if (raw == 'standard') return 'new_sender';
  if (raw == 'priority') return 'priority_sender';
  if (raw == 'vanguard') return 'platinum_sender';
  return 'new_sender';
}

String _senderName(Object? senderId, List<Map<String, dynamic>> users) {
  final id = '$senderId'.trim();
  if (id.isEmpty) return 'Unknown sender';
  for (final user in users) {
    if (_recordId(user) != id) continue;
    return '${user['fullName'] ?? user['name'] ?? user['email'] ?? id}';
  }
  return id;
}

bool _deliveryBelongsToRider(Map<String, dynamic> delivery, String riderId) {
  if (riderId.isEmpty) return false;
  return [
    delivery['riderId'],
    delivery['driverId'],
    delivery['assignedRiderId'],
    delivery['assignedDriverId'],
  ].map((value) => '$value').contains(riderId);
}

bool _documentBelongsToRider(Map<String, dynamic> document, String riderId) {
  if (riderId.isEmpty) return false;
  return [
    document['riderId'],
    document['driverId'],
    document['uid'],
  ].map((value) => '$value').contains(riderId);
}

Map<String, dynamic>? _assignedRiderForDelivery(
  Map<String, dynamic> delivery,
  List<Map<String, dynamic>> riders,
) {
  for (final rider in riders) {
    if (_deliveryBelongsToRider(delivery, _riderId(rider))) return rider;
  }
  return null;
}

bool _recordReferencesRider(Map<String, dynamic> record, String riderId) {
  if (riderId.isEmpty) return false;
  return [
    record['riderId'],
    record['driverId'],
    record['assignedRiderId'],
    record['assignedDriverId'],
    record['uid'],
  ].map((value) => '$value'.trim()).contains(riderId);
}

bool _recordReferencesDelivery(Map<String, dynamic> record, String deliveryId) {
  if (deliveryId.isEmpty) return false;
  return [
    record['deliveryId'],
    record['requestId'],
    record['trackingId'],
    record['bookingId'],
    record['id'],
  ].map((value) => '$value'.trim()).contains(deliveryId);
}

String _healthStatus(Map<String, dynamic> record) {
  return '${record['status'] ?? record['clinicalReviewStatus'] ?? record['collectionStatus'] ?? ''}'
      .toLowerCase();
}

bool _isActiveHealthPlus(Map<String, dynamic> record) {
  final status = _healthStatus(record);
  return status.isNotEmpty &&
      !status.contains('complete') &&
      !status.contains('deliver') &&
      !status.contains('cancel') &&
      !status.contains('failed') &&
      !status.contains('closed');
}

bool _needsClinicalReview(Map<String, dynamic> record) {
  final text = record.values.join(' ').toLowerCase();
  return text.contains('clinical') ||
      text.contains('controlled') ||
      text.contains('missing evidence') ||
      text.contains('rejected') ||
      text.contains('escalat');
}

bool _hasAnyText(Map<String, dynamic> record, List<String> needles) {
  final text = record.entries
      .where((entry) => entry.value is! Map && entry.value is! List)
      .map((entry) => '${entry.key}:${entry.value}'.toLowerCase())
      .join(' ');
  return needles.any((needle) => text.contains(needle.toLowerCase()));
}

List<Widget> _giftActions(
  Map<String, dynamic> record,
  Future<void> Function(Map<String, dynamic>, String) onUpdateGiftWorkflow,
) {
  return [
    for (final action in const [
      ('Approve', 'approved'),
      ('Reject', 'rejected'),
      ('Assign', 'assigned'),
      ('Reassign', 'reassigned'),
      ('Escalate', 'escalated'),
      ('Pause', 'paused'),
      ('Resume', 'resumed'),
      ('Close', 'closed'),
      ('Request info', 'information_requested'),
    ])
      _MiniAction(
        label: action.$1,
        onPressed: () => unawaited(onUpdateGiftWorkflow(record, action.$2)),
      ),
  ];
}

List<Widget> _giftBrandPartnerActions(
  Map<String, dynamic> record,
  Future<void> Function(Map<String, dynamic>, String) onSetStatus,
  Future<void> Function(Map<String, dynamic>?) onEdit,
) {
  return [
    _MiniAction(label: 'Edit', onPressed: () => unawaited(onEdit(record))),
    for (final action in const [
      ('Approve', 'approved'),
      ('Suspend', 'suspended'),
      ('Reactivate', 'approved'),
      ('Inactive', 'inactive'),
      ('History', 'history_reviewed'),
    ])
      _MiniAction(
        label: action.$1,
        onPressed: () => unawaited(onSetStatus(record, action.$2)),
      ),
  ];
}

String _brandId(Map<String, dynamic> brand) {
  return '${brand['id'] ?? brand['partnerId'] ?? brand['brandId'] ?? ''}'
      .trim();
}

String _slugId(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

List<String> _csvValues(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

List<String> _adminStringList(Object? value) {
  if (value is Iterable) {
    return value
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return const [];
  return [text];
}

int _brandGiftLinks(
  List<Map<String, dynamic>> brands,
  List<Map<String, dynamic>> gifts,
) {
  final brandNames = brands
      .expand(
        (brand) => [
          brand['partnerName'],
          brand['brandName'],
          brand['partnerId'],
        ],
      )
      .map((value) => '$value'.trim().toLowerCase())
      .where((value) => value.isNotEmpty && value != 'null')
      .toSet();
  return gifts.where((gift) {
    final text = [
      gift['brandName'],
      gift['partnerName'],
      gift['brandId'],
      gift['supplier'],
      gift['procurementSupplier'],
    ].join(' ').toLowerCase();
    return brandNames.any(text.contains);
  }).length;
}

bool _isTroubleshootingDelivery(Map<String, dynamic> delivery) {
  final text = delivery.values.join(' ').toLowerCase();
  return text.contains('stale') ||
      text.contains('lock') ||
      text.contains('unassigned') ||
      text.contains('waiting') ||
      text.contains('no_show') ||
      text.contains('no-show') ||
      text.contains('failed') ||
      text.contains('stuck');
}

bool _isTroubleshootingPayment(Map<String, dynamic> payment) {
  return _isFailedPayment(payment) ||
      _isPendingRefund(payment) ||
      _isFinanceInvestigation(payment);
}

bool _isComplaintTicket(Map<String, dynamic> ticket) {
  return _hasAnyText(ticket, const ['complaint', 'dispute', 'escalat']);
}

bool _isRefundTicket(Map<String, dynamic> ticket) {
  return _hasAnyText(ticket, const ['refund']);
}

bool _isLowRating(Map<String, dynamic> rating) {
  final stars = rating['starRating'] ?? rating['rating'] ?? rating['stars'];
  if (stars is num && stars <= 2) return true;
  return _ratingReported(rating);
}

bool _isCompletedRecord(Map<String, dynamic> record) {
  final text = '${record['status'] ?? record['deliveryStatus'] ?? ''}'
      .toLowerCase();
  return text.contains('complete') || text.contains('delivered');
}

String _troubleshootingPriority(Map<String, dynamic> record) {
  final text = record.values.join(' ').toLowerCase();
  if (text.contains('failed') ||
      text.contains('stale') ||
      text.contains('refund') ||
      text.contains('complaint')) {
    return 'High';
  }
  if (text.contains('waiting') || text.contains('unassigned')) return 'Medium';
  return 'Standard';
}

List<Widget> _troubleshootingActions(
  Map<String, dynamic> record, {
  required ValueChanged<Map<String, dynamic>> onOpenDelivery,
  required Future<void> Function(Map<String, dynamic>, String)
  onUpdateSupportTicket,
  required Future<void> Function(Map<String, dynamic>, String)
  onSetDeliveryOperationStatus,
  required Future<void> Function(Map<String, dynamic>, String)
  onUpdateFinanceWorkflow,
  required Future<void> Function(Map<String, dynamic>, String) onModerateRating,
}) {
  final source = '${record['_source'] ?? ''}';
  if (source == 'delivery') {
    return [
      _MiniAction(label: 'Details', onPressed: () => onOpenDelivery(record)),
      _MiniAction(
        label: 'Assign review',
        onPressed: () =>
            unawaited(onSetDeliveryOperationStatus(record, 'review_assigned')),
      ),
      _MiniAction(
        label: 'Escalate',
        onPressed: () =>
            unawaited(onSetDeliveryOperationStatus(record, 'escalated')),
      ),
    ];
  }
  if (source == 'payment') {
    return [
      _MiniAction(
        label: 'Investigate',
        onPressed: () =>
            unawaited(onUpdateFinanceWorkflow(record, 'investigation_flagged')),
      ),
      _MiniAction(
        label: 'Approve refund',
        onPressed: () =>
            unawaited(onUpdateFinanceWorkflow(record, 'refund_approved')),
      ),
    ];
  }
  if (source == 'rating') {
    return [
      _MiniAction(
        label: 'Investigate',
        onPressed: () => unawaited(onModerateRating(record, 'investigate')),
      ),
      _MiniAction(
        label: 'Hide',
        onPressed: () => unawaited(onModerateRating(record, 'hide')),
      ),
    ];
  }
  return [
    _MiniAction(
      label: 'Assign',
      onPressed: () => unawaited(onUpdateSupportTicket(record, 'assigned')),
    ),
    _MiniAction(
      label: 'Escalate',
      onPressed: () => unawaited(onUpdateSupportTicket(record, 'escalated')),
    ),
    _MiniAction(
      label: 'Resolve',
      onPressed: () => unawaited(onUpdateSupportTicket(record, 'resolved')),
    ),
  ];
}

double _averageNumber(List<Map<String, dynamic>> records, List<String> keys) {
  final values = <double>[];
  for (final record in records) {
    for (final key in keys) {
      final value = _numberFrom(record[key]);
      if (value > 0) {
        values.add(value);
        break;
      }
    }
  }
  if (values.isEmpty) return 0;
  return values.reduce((a, b) => a + b) / values.length;
}

List<Widget> _supportActions(
  Map<String, dynamic> record,
  Future<void> Function(Map<String, dynamic>, String) onUpdateSupportTicket,
  Future<void> Function(Map<String, dynamic>) onOpenSupportConversation,
  Future<void> Function(Map<String, dynamic>, String) onAddAdminNote,
) {
  return [
    _MiniAction(
      label: 'Open chat',
      onPressed: () => unawaited(onOpenSupportConversation(record)),
    ),
    _MiniAction(
      label: 'Add note',
      onPressed: () => unawaited(onAddAdminNote(record, 'supportTickets')),
    ),
    for (final action in const [
      ('Open', 'open'),
      ('Assign', 'assigned'),
      ('Waiting', 'waiting'),
      ('Escalate', 'escalated'),
      ('Resolve', 'resolved'),
      ('Close', 'closed'),
    ])
      _MiniAction(
        label: action.$1,
        onPressed: () => unawaited(onUpdateSupportTicket(record, action.$2)),
      ),
  ];
}

List<Widget> _platformActions(
  Map<String, dynamic> record,
  Future<void> Function(Map<String, dynamic>, String) onUpdatePlatformRecord,
) {
  return [
    for (final action in const [
      ('Enable', 'enabled'),
      ('Disable', 'disabled'),
      ('Maintenance on', 'maintenance_enabled'),
      ('Maintenance off', 'maintenance_disabled'),
      ('Acknowledge', 'acknowledged'),
      ('Resolve', 'resolved'),
    ])
      _MiniAction(
        label: action.$1,
        onPressed: () => unawaited(onUpdatePlatformRecord(record, action.$2)),
      ),
  ];
}

List<Widget> _platformNoticeActions(
  Map<String, dynamic> record,
  Future<void> Function(Map<String, dynamic>, String) onUpdatePlatformRecord,
) {
  return [
    for (final action in const [
      ('Publish', 'published'),
      ('Unpublish', 'unpublished'),
      ('Enable', 'enabled'),
      ('Disable', 'disabled'),
      ('Resolve', 'resolved'),
    ])
      _MiniAction(
        label: action.$1,
        onPressed: () => unawaited(onUpdatePlatformRecord(record, action.$2)),
      ),
  ];
}

bool _platformEnabled(Map<String, dynamic> record) {
  if (record['enabled'] == true) return true;
  final status = '${record['adminOperationStatus'] ?? record['status'] ?? ''}'
      .toLowerCase();
  return status.contains('active') ||
      status.contains('enabled') ||
      status.contains('healthy') ||
      status.contains('ok');
}

bool _platformPublished(Map<String, dynamic> record) {
  if (record['published'] == true) return true;
  final status = '${record['adminOperationStatus'] ?? record['status'] ?? ''}'
      .toLowerCase();
  return status.contains('published') ||
      status.contains('active') ||
      status.contains('enabled');
}

bool _notificationNeedsRetry(Map<String, dynamic> record) {
  final status =
      '${record['pushDeliveryStatus'] ?? record['deliveryStatus'] ?? ''}'
          .toLowerCase();
  return record['retryable'] == true ||
      status == 'failed' ||
      status == 'skipped' ||
      status == 'retry';
}

String _platformStatusLabel(List<Map<String, dynamic>> statusRecords) {
  if (statusRecords.isEmpty) return 'Not recorded';
  if (statusRecords.any(
    (record) => _hasAnyText(record, const ['critical', 'down', 'incident']),
  )) {
    return 'Incident';
  }
  if (statusRecords.any(
    (record) => _hasAnyText(record, const ['degraded', 'warning']),
  )) {
    return 'Watch';
  }
  return 'Operational';
}

String _platformEnvironment(List<Map<String, dynamic>> configRecords) {
  final values = configRecords
      .map((record) => '${record['environment'] ?? record['env'] ?? ''}'.trim())
      .where((value) => value.isNotEmpty && value != 'null')
      .toSet();
  if (values.isEmpty) return 'production';
  if (values.length == 1) return values.first;
  return values.join(', ');
}

// ignore: unused_element
bool _isGiftActive(Map<String, dynamic> gift) {
  final state = '${gift['giftAdminStatus'] ?? gift['status'] ?? ''}'
      .trim()
      .toLowerCase();
  return state.isEmpty ||
      (!state.contains('delivered') &&
          !state.contains('cancel') &&
          !state.contains('failed') &&
          !state.contains('closed') &&
          !state.contains('reject'));
}

bool _hasGiftStory(Map<String, dynamic> gift) {
  return gift['storyEnabled'] == true ||
      gift['giftStoryEnabled'] == true ||
      '${gift['story'] ?? gift['storyStatus'] ?? ''}'.trim().isNotEmpty;
}

String _giftStorySummary(Map<String, dynamic> gift) {
  final values =
      [
            if (_hasGiftStory(gift)) 'available',
            gift['storyStatus'],
            gift['unlockStatus'],
            gift['moderationState'],
            gift['visibility'],
            gift['archiveState'],
          ]
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty && value != 'null')
          .toList();
  return values.isEmpty ? 'Story not added' : values.join(' / ');
}

String _giftWorkspaceSummary(Map<String, dynamic> gift) {
  final workspace = gift['giftsTeamWorkspace'];
  if (workspace is! Map) return 'Operations not opened';
  final assignment = workspace['assignment'];
  final readiness = workspace['readiness'];
  final values =
      [
            if (assignment is Map) assignment['assignedCurator'],
            if (assignment is Map) assignment['status'],
            workspace['curationNotesUpdatedBy'],
            if (readiness is Map && readiness['readyForProcurement'] == true)
              'ready sourcing',
            if (readiness is Map && readiness['readyForDelivery'] == true)
              'ready delivery',
          ]
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty && value != 'null')
          .toList();
  return values.isEmpty ? 'Operations open' : values.join(' / ');
}

String _giftProcurementSummary(Map<String, dynamic> gift) {
  final workspace = gift['giftsTeamWorkspace'];
  final supplier = workspace is Map ? workspace['supplierWorkspace'] : null;
  final values =
      [
            gift['procurementItemTitle'],
            gift['procurementSupplier'],
            if (supplier is Map) supplier['supplierStatus'],
            if (supplier is Map) supplier['expectedFulfilment'],
            gift['procurementEstimatedCost'],
            gift['procurementActualCost'],
          ]
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty && value != 'null')
          .toList();
  return values.isEmpty ? 'Sourcing not started' : values.join(' / ');
}

String _giftIrisSelectionSummary(Map<String, dynamic> gift) {
  final workspace = gift['giftsTeamWorkspace'];
  final collaboration = workspace is Map
      ? workspace['irisCollaboration']
      : null;
  final plan = gift['approvedGiftPlan'];
  final values =
      [
            gift['irisSuggestion'],
            if (gift['irisGiftRecommendation'] != null) 'recommendation saved',
            if (plan is Map) plan['selectedRepositoryItemIds'],
            if (collaboration is Map) collaboration['acceptedSignals'],
            if (collaboration is Map) collaboration['rejectedSignals'],
            if (collaboration is Map) collaboration['curatorFeedback'],
          ]
          .map((value) => '$value'.trim())
          .where(
            (value) => value.isNotEmpty && value != 'null' && value != '[]',
          )
          .toList();
  return values.isEmpty ? 'No parcel recommendation' : values.join(' / ');
}

String _giftStoryAudioSummary(Map<String, dynamic> gift) {
  final mix = gift['giftStoryAudioMix'];
  final values =
      [
            gift['giftStoryMusicSource'],
            gift['giftStoryCustomAudioUrl'] == null ? null : 'custom audio',
            gift['giftStoryIncludeSenderVoiceNote'] == true
                ? 'sender voice'
                : null,
            if (mix is Map) mix['voicePlacement'],
            if (mix is Map) mix['musicDuckingLevel'],
          ]
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty && value != 'null')
          .toList();
  return values.isEmpty ? 'No audio mix' : values.join(' / ');
}

// ignore: unused_element
String _relatedDeliverySummary(
  Map<String, dynamic> record,
  List<Map<String, dynamic>> deliveries,
) {
  final related = deliveries.where(
    (delivery) => _recordsRelated(record, delivery),
  );
  if (related.isEmpty) return 'No delivery linked';
  final delivery = related.first;
  return '${_recordId(delivery)} / ${delivery['status'] ?? delivery['deliveryStatus'] ?? 'status n/a'} / ${_date(delivery['updatedAt'] ?? delivery['createdAt'])}';
}

int _relatedCount(
  Map<String, dynamic> record,
  List<Map<String, dynamic>> candidates,
) {
  return candidates
      .where((candidate) => _recordsRelated(record, candidate))
      .length;
}

bool _recordsRelated(Map<String, dynamic> a, Map<String, dynamic> b) {
  final identifiers = <String>{
    for (final key in const [
      'id',
      'requestId',
      'deliveryId',
      'giftId',
      'giftOrderId',
      'ticketId',
      'supportTicketId',
      'userId',
      'senderId',
      'riderId',
      'businessId',
      'email',
      'senderEmail',
      'riderEmail',
      'businessEmail',
    ])
      '${a[key] ?? ''}'.trim().toLowerCase(),
  }..removeWhere((value) => value.isEmpty || value == 'null');
  if (identifiers.isEmpty) return false;
  final other = [
    for (final key in const [
      'id',
      'requestId',
      'recordId',
      'deliveryId',
      'giftId',
      'giftOrderId',
      'ticketId',
      'supportTicketId',
      'userId',
      'senderId',
      'riderId',
      'businessId',
      'email',
      'senderEmail',
      'riderEmail',
      'businessEmail',
    ])
      '${b[key] ?? ''}'.trim().toLowerCase(),
  ];
  return other.any(identifiers.contains);
}

bool _isSupportClosed(Map<String, dynamic> ticket) {
  final state = '${ticket['supportWorkflowStatus'] ?? ticket['status'] ?? ''}'
      .trim()
      .toLowerCase();
  return state == 'resolved' || state == 'closed';
}

String _averageSupportTime(List<Map<String, dynamic>> tickets) {
  final durations = <Duration>[];
  for (final ticket in tickets) {
    final created = _dateTimeFrom(ticket['createdAt']);
    final firstResponse = _dateTimeFrom(
      ticket['firstResponseAt'] ?? ticket['assignedAt'],
    );
    if (created != null &&
        firstResponse != null &&
        firstResponse.isAfter(created)) {
      durations.add(firstResponse.difference(created));
    }
  }
  return _averageDurationLabel(durations);
}

String _averageSupportResolution(List<Map<String, dynamic>> tickets) {
  final durations = <Duration>[];
  for (final ticket in tickets.where(_isSupportClosed)) {
    final created = _dateTimeFrom(ticket['createdAt']);
    final resolved = _dateTimeFrom(
      ticket['resolvedAt'] ?? ticket['closedAt'] ?? ticket['updatedAt'],
    );
    if (created != null && resolved != null && resolved.isAfter(created)) {
      durations.add(resolved.difference(created));
    }
  }
  return _averageDurationLabel(durations);
}

String _averageDurationLabel(List<Duration> durations) {
  if (durations.isEmpty) return 'Not recorded';
  final minutes =
      durations.fold<int>(0, (total, item) => total + item.inMinutes) ~/
      durations.length;
  if (minutes < 60) return '${minutes}m';
  return '${(minutes / 60).toStringAsFixed(1)}h';
}

String _auditSeverity(Map<String, dynamic> log) {
  final text = '${log['severity'] ?? log['actionType'] ?? log['reason'] ?? ''}'
      .toLowerCase();
  if (text.contains('critical') ||
      text.contains('delete') ||
      text.contains('suspend') ||
      text.contains('refund') ||
      text.contains('override')) {
    return 'critical';
  }
  if (text.contains('escalat') || text.contains('reject')) return 'warning';
  return 'info';
}

String _linkedAuditObjects(Map<String, dynamic> log) {
  final links =
      [
            log['recordId'],
            log['deliveryId'],
            log['senderId'],
            log['riderId'],
            log['businessId'],
            log['giftId'],
            log['supportTicketId'],
            log['paymentId'],
            log['irisReviewId'],
          ]
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty && value != 'null')
          .toSet();
  return links.isEmpty ? 'No linked objects' : links.join(', ');
}

double _healthRevenue(List<Map<String, dynamic>> payments) {
  return payments.fold<double>(
    0,
    (total, payment) =>
        total + _numberFrom(payment['amount'] ?? payment['total']),
  );
}

Set<String> _activePharmacies(List<Map<String, dynamic>> records) {
  return records
      .map(
        (record) =>
            '${record['pharmacyName'] ?? record['pharmacyAddress'] ?? ''}'
                .trim(),
      )
      .where((value) => value.isNotEmpty)
      .toSet();
}

String _businessStatus(Map<String, dynamic> record) {
  return '${record['status'] ?? record['verificationStatus'] ?? ''}'
      .toLowerCase();
}

bool _hasInvoiceDue(Map<String, dynamic> record) {
  final text = '${record['invoiceStatus'] ?? record['billingStatus'] ?? ''}'
      .toLowerCase();
  return text.contains('due') || text.contains('overdue');
}

bool _hasOutstandingInvoice(Map<String, dynamic> record) {
  final text = '${record['invoiceStatus'] ?? record['billingStatus'] ?? ''}'
      .toLowerCase();
  return text.contains('outstanding') ||
      text.contains('due') ||
      text.contains('open');
}

double _businessRevenue(List<Map<String, dynamic>> payments) {
  return payments
      .where(
        (payment) =>
            '${payment['businessId'] ?? payment['businessName'] ?? payment['type'] ?? ''}'
                .toLowerCase()
                .contains('business'),
      )
      .fold<double>(
        0,
        (total, payment) =>
            total + _numberFrom(payment['amount'] ?? payment['total']),
      );
}

bool _recordReferencesAccount(
  Map<String, dynamic> record,
  String accountId,
  Map<String, dynamic> account,
) {
  final email = '${account['email'] ?? ''}'.trim().toLowerCase();
  final values = [
    record['senderId'],
    record['userId'],
    record['customerId'],
    record['businessId'],
    record['accountId'],
    record['uid'],
    record['ownerId'],
    record['email'],
    record['senderEmail'],
    record['customerEmail'],
  ].map((value) => '$value'.trim().toLowerCase());
  return values.contains(accountId.toLowerCase()) ||
      (email.isNotEmpty && values.contains(email));
}

bool _hasIrisSignal(Map<String, dynamic> record) {
  return record.containsKey('iris') ||
      record.containsKey('irisEstimate') ||
      record.containsKey('irisCalculationMetadata') ||
      record.containsKey('irisReviewStatus') ||
      record.containsKey('irisConfidence') ||
      '${record['reviewType'] ?? ''}'.toLowerCase().contains('iris');
}

bool _isIrisPending(Map<String, dynamic> record) {
  final state =
      '${record['irisReviewStatus'] ?? record['reviewType'] ?? 'pending'}'
          .toLowerCase();
  return state.contains('pending') ||
      state.contains('review') ||
      state.contains('disputed');
}

String _irisState(Map<String, dynamic> record) {
  return '${record['irisReviewStatus'] ?? record['reviewType'] ?? record['evidenceRequestStatus'] ?? record['engineeringReviewStatus'] ?? ''}'
      .toLowerCase();
}

bool _isLowConfidenceIris(Map<String, dynamic> record) =>
    _irisConfidence(record) > 0 && _irisConfidence(record) < 60;

bool _isHighConfidenceIris(Map<String, dynamic> record) =>
    _irisConfidence(record) >= 85;

bool _hasWeightDispute(Map<String, dynamic> record) {
  final estimated = _numberFrom(
    record['irisEstimatedWeight'] ??
        record['estimatedWeight'] ??
        record['weight'],
  );
  final verified = _numberFrom(
    record['verifiedWeight'] ??
        record['riderVerifiedWeight'] ??
        record['actualWeight'],
  );
  if (estimated > 0 && verified > 0) return (estimated - verified).abs() >= 2;
  final state = '${record['irisReviewStatus'] ?? record['reviewType'] ?? ''}'
      .toLowerCase();
  return state.contains('dispute') || state.contains('weight');
}

bool _hasCategoryDispute(Map<String, dynamic> record) {
  final irisCategory =
      '${record['irisCategory'] ?? _mapValue(record['iris'], 'category') ?? ''}'
          .trim()
          .toLowerCase();
  final category = '${record['category'] ?? record['verifiedCategory'] ?? ''}'
      .trim()
      .toLowerCase();
  if (irisCategory.isNotEmpty && category.isNotEmpty) {
    return irisCategory != category;
  }
  return _irisState(record).contains('category');
}

bool _hasVehicleDispute(Map<String, dynamic> record) {
  final recommended =
      '${record['recommendedVehicle'] ?? record['vehicleRecommendation'] ?? _mapValue(record['iris'], 'vehicleType') ?? ''}'
          .trim()
          .toLowerCase();
  final actual = '${record['actualVehicle'] ?? record['vehicleType'] ?? ''}'
      .trim()
      .toLowerCase();
  if (recommended.isNotEmpty && actual.isNotEmpty) return recommended != actual;
  return _irisState(record).contains('vehicle');
}

bool _hasIrisFailure(Map<String, dynamic> record) {
  final text = record.values.join(' ').toLowerCase();
  return text.contains('iris') &&
      (text.contains('fail') ||
          text.contains('error') ||
          text.contains('timeout') ||
          text.contains('retry'));
}

bool _isLearningCandidate(Map<String, dynamic> record) {
  final state =
      '${record['irisLearningQueueStatus'] ?? record['irisReviewStatus'] ?? record['reviewType'] ?? ''}'
          .toLowerCase();
  return state.contains('learning') ||
      state.contains('misclassification') ||
      state.contains('category');
}

double _irisConfidence(Map<String, dynamic> record) {
  final raw =
      record['irisConfidence'] ??
      record['confidence'] ??
      record['confidenceScore'] ??
      _mapValue(record['iris'], 'confidence') ??
      _mapValue(record['irisEstimate'], 'confidence') ??
      _mapValue(record['irisCalculationMetadata'], 'confidence');
  final value = _numberFrom(raw);
  return value <= 1 && value > 0 ? value * 100 : value;
}

double _averageIrisConfidence(List<Map<String, dynamic>> records) {
  final values = records.map(_irisConfidence).where((value) => value > 0);
  if (values.isEmpty) return 0;
  return values.reduce((a, b) => a + b) / values.length;
}

int _countIrisOverrides(List<Map<String, dynamic>> auditLogs) {
  return auditLogs
      .where((log) => '${log['actionType'] ?? ''}'.contains('iris_review'))
      .length;
}

Set<String> _activeIrisReviewers(List<Map<String, dynamic>> auditLogs) {
  final today = DateTime.now();
  return auditLogs
      .where(
        (log) =>
            '${log['actionType'] ?? ''}'.contains('iris') &&
            _isSameDay(log, today),
      )
      .map((log) => '${log['adminUserId'] ?? log['reviewer'] ?? ''}'.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
}

String _irisQueueHealth(int pending, int lowConfidence) {
  if (pending > 25 || lowConfidence > 10) return 'Critical';
  if (pending > 10 || lowConfidence > 3) return 'Watch';
  return 'Healthy';
}

String _averageIrisReviewTime(List<Map<String, dynamic>> records) {
  final durations = <Duration>[];
  for (final record in records) {
    final created = _dateTimeFrom(record['createdAt']);
    final reviewed = _dateTimeFrom(
      record['irisReviewedAt'] ?? record['updatedAt'],
    );
    if (created != null && reviewed != null && reviewed.isAfter(created)) {
      durations.add(reviewed.difference(created));
    }
  }
  if (durations.isEmpty) return 'Not recorded';
  final minutes =
      durations.fold<int>(0, (total, item) => total + item.inMinutes) ~/
      durations.length;
  if (minutes < 60) return '${minutes}m';
  return '${(minutes / 60).toStringAsFixed(1)}h';
}

String _canonicalPolicySummary(Map<String, dynamic> record) {
  final flags = <String>[];
  if (record['fragile'] == true) flags.add('Fragile');
  if (record['dangerousGoods'] == true) flags.add('Dangerous');
  if (record['marketplaceEligible'] == true) flags.add('Marketplace');
  if (record['healthPlusEligible'] == true) flags.add('Health+');
  if (record['giftEligible'] == true) flags.add('Gift');
  if (record['businessEligible'] == true) flags.add('Business');
  final handling = record['handlingRequirements'];
  if (handling != null && '$handling'.trim().isNotEmpty) {
    flags.add('$handling');
  }
  return flags.isEmpty ? 'No policy flags' : flags.join(', ');
}

bool _hasReferenceImageSignal(Map<String, dynamic> record) {
  return [
    record['referenceImageUrl'],
    record['referenceImageStoragePath'],
    record['referenceImageStatus'],
    record['pendingStoragePath'],
    record['storagePath'],
    record['previewUrl'],
  ].any((value) => '$value'.trim().isNotEmpty && '$value' != 'null');
}

bool _isPendingReferenceImage(Map<String, dynamic> record) {
  final state =
      '${record['referenceImageStatus'] ?? record['status'] ?? record['reviewStatus'] ?? ''}'
          .toLowerCase();
  return state.contains('pending') ||
      state.contains('review') ||
      state.contains('draft');
}

bool _isApprovedReferenceImage(Map<String, dynamic> record) {
  final state =
      '${record['referenceImageStatus'] ?? record['status'] ?? record['reviewStatus'] ?? ''}'
          .toLowerCase();
  return state.contains('approved') ||
      state.contains('final') ||
      state.contains('active');
}

Set<String> _distinctValues(List<Map<String, dynamic>> records, String field) {
  return records
      .map((record) => '${record[field] ?? ''}'.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
}

Map<String, int> _categoryDistribution(List<Map<String, dynamic>> records) {
  final result = <String, int>{};
  for (final record in records) {
    final category =
        '${record['category'] ?? record['irisCategory'] ?? _mapValue(record['iris'], 'category') ?? 'Uncategorised'}';
    result[category] = (result[category] ?? 0) + 1;
  }
  return result;
}

Map<String, int> _vehicleDistribution(List<Map<String, dynamic>> records) {
  final result = <String, int>{};
  for (final record in records) {
    final vehicle =
        '${record['recommendedVehicle'] ?? record['vehicleRecommendation'] ?? record['vehicleType'] ?? _mapValue(record['iris'], 'vehicleType') ?? 'Unknown'}';
    result[vehicle] = (result[vehicle] ?? 0) + 1;
  }
  return result;
}

String _irisEstimateSummary(Map<String, dynamic> record) {
  final weight =
      record['irisEstimatedWeight'] ??
      record['estimatedWeight'] ??
      _mapValue(record['iris'], 'weight') ??
      _mapValue(record['irisEstimate'], 'weight');
  final verified = record['verifiedWeight'] ?? record['riderVerifiedWeight'];
  final category =
      record['category'] ??
      record['irisCategory'] ??
      _mapValue(record['iris'], 'category');
  final vehicle =
      record['recommendedVehicle'] ??
      record['vehicleRecommendation'] ??
      _mapValue(record['iris'], 'vehicleType');
  return '${category ?? 'Object'} / ${weight ?? 'unknown'}kg / verified ${verified ?? 'n/a'} / ${vehicle ?? 'vehicle n/a'}';
}

Object? _mapValue(Object? value, String key) {
  if (value is Map) return value[key];
  return null;
}

double _financeTotalToday(List<Map<String, dynamic>> payments) {
  final now = DateTime.now();
  return payments
      .where((payment) => _isSameDay(payment, now))
      .fold<double>(
        0,
        (total, payment) =>
            total + _numberFrom(payment['amount'] ?? payment['total']),
      );
}

bool _isOutstandingSettlement(Map<String, dynamic> payment) {
  final text = payment.values.join(' ').toLowerCase();
  return text.contains('settlement') &&
      !text.contains('complete') &&
      !text.contains('paid');
}

bool _isPendingRefund(Map<String, dynamic> payment) {
  final text = payment.values.join(' ').toLowerCase();
  return text.contains('refund') &&
      (text.contains('pending') || text.contains('review'));
}

bool _isFailedPayment(Map<String, dynamic> payment) {
  final text = '${payment['status'] ?? payment['paymentStatus'] ?? ''}'
      .toLowerCase();
  return text.contains('fail') || text.contains('declin');
}

bool _isFinanceInvestigation(Map<String, dynamic> payment) {
  final text = payment.values.join(' ').toLowerCase();
  return text.contains('investigation') || text.contains('dispute');
}

double _walletLiability(List<Map<String, dynamic>> payments) {
  return payments
      .where(
        (payment) => payment.values.join(' ').toLowerCase().contains('wallet'),
      )
      .fold<double>(
        0,
        (total, payment) =>
            total + _numberFrom(payment['balance'] ?? payment['amount']),
      );
}

double _rothTotal(List<Map<String, dynamic>> payments) {
  return payments
      .where(
        (payment) => payment.values.join(' ').toLowerCase().contains('roth'),
      )
      .fold<double>(
        0,
        (total, payment) =>
            total + _numberFrom(payment['roth'] ?? payment['amount']),
      );
}

double _tipsTotal(List<Map<String, dynamic>> tips) {
  return tips.fold<double>(
    0,
    (total, tip) =>
        total + _numberFrom(tip['amount'] ?? tip['tipAmount'] ?? tip['total']),
  );
}

bool _ratingReported(Map<String, dynamic> rating) {
  final status = '${rating['reportStatus'] ?? rating['moderationStatus'] ?? ''}'
      .toLowerCase();
  return status.isNotEmpty && status != 'clear' && status != 'none';
}

String _stripeReconciliationStatus(List<Map<String, dynamic>> payments) {
  if (payments.any(_isFailedPayment)) return 'Action';
  if (payments.any(_isFinanceInvestigation)) return 'Review';
  return 'OK';
}

int _countFinanceType(List<Map<String, dynamic>> payments, String type) {
  return payments
      .where((payment) => payment.values.join(' ').toLowerCase().contains(type))
      .length;
}

int _countRecordsContaining(List<Map<String, dynamic>> records, String text) {
  return records
      .where((record) => record.values.join(' ').toLowerCase().contains(text))
      .length;
}

bool _isOnlineRider(Map<String, dynamic> rider) {
  final state =
      '${rider['availability'] ?? rider['onlineStatus'] ?? rider['status'] ?? rider['driverStatus'] ?? ''}'
          .toLowerCase();
  return state.contains('online') || state.contains('available');
}

bool _isSuspendedRider(Map<String, dynamic> rider) {
  final state =
      '${rider['approvalStatus'] ?? rider['driverStatus'] ?? rider['status'] ?? ''}'
          .toLowerCase();
  return state.contains('suspend');
}

bool _isPendingRiderRecord(Map<String, dynamic> rider) {
  final state =
      '${rider['verificationStatus'] ?? rider['approvalStatus'] ?? rider['driverStatus'] ?? ''}'
          .toLowerCase();
  return state.contains('pending') || state.contains('review');
}

bool _isActiveDelivery(Map<String, dynamic> delivery) {
  final state =
      '${delivery['status'] ?? delivery['deliveryStatus'] ?? delivery['deliveryStage'] ?? ''}'
          .toLowerCase();
  return state.isNotEmpty &&
      !state.contains('complete') &&
      !state.contains('deliver') &&
      !state.contains('cancel') &&
      !state.contains('archive') &&
      !state.contains('failed');
}

bool _isStaleDelivery(Map<String, dynamic> delivery) {
  final haystack = [
    delivery['status'],
    delivery['deliveryStatus'],
    delivery['adminOperationStatus'],
    delivery['lockStatus'],
    delivery['staleLockStatus'],
    delivery['recoveryStatus'],
    delivery['issueType'],
  ].join(' ').toLowerCase();
  return haystack.contains('stale') ||
      haystack.contains('locked') ||
      haystack.contains('orphaned');
}

bool _isRecoverableDelivery(Map<String, dynamic> delivery) {
  final haystack = [
    delivery['status'],
    delivery['deliveryStatus'],
    delivery['adminOperationStatus'],
    delivery['recoveryStatus'],
    delivery['archiveStatus'],
  ].join(' ').toLowerCase();
  return haystack.contains('recover') ||
      haystack.contains('restore') ||
      haystack.contains('stale');
}

bool _isArchivedDelivery(Map<String, dynamic> delivery) {
  final haystack = [
    delivery['adminArchiveStatus'],
    delivery['archiveStatus'],
    delivery['status'],
    delivery['deliveryStatus'],
  ].join(' ').toLowerCase();
  return haystack.contains('archive') || delivery['archivedAt'] != null;
}

bool _isCompletedDelivery(Map<String, dynamic> delivery) {
  final state = '${delivery['status'] ?? delivery['deliveryStatus'] ?? ''}'
      .toLowerCase();
  return state.contains('complete') || state.contains('delivered');
}

bool _isCancelledDelivery(Map<String, dynamic> delivery) {
  final state = '${delivery['status'] ?? delivery['deliveryStatus'] ?? ''}'
      .toLowerCase();
  return state.contains('cancel');
}

bool _isWaitingDelivery(Map<String, dynamic> delivery) {
  final state =
      '${delivery['status'] ?? delivery['deliveryStatus'] ?? delivery['waitingReviewStatus'] ?? ''}'
          .toLowerCase();
  return state.contains('waiting') || state.contains('wait');
}

bool _isNoShowDelivery(Map<String, dynamic> delivery) {
  final state =
      '${delivery['status'] ?? delivery['deliveryStatus'] ?? delivery['noShowReviewStatus'] ?? ''}'
          .toLowerCase();
  return state.contains('no_show') || state.contains('no-show');
}

bool _isDelayedDelivery(Map<String, dynamic> delivery) {
  final state =
      '${delivery['status'] ?? delivery['deliveryStatus'] ?? delivery['escalationStatus'] ?? ''}'
          .toLowerCase();
  return state.contains('delay') ||
      state.contains('late') ||
      state.contains('escalat');
}

bool _hasVanguardProtection(Map<String, dynamic> delivery) {
  final value = delivery['vanguardProtection'] ?? delivery['vanguard'];
  if (value is bool) return value;
  if (value is Map) {
    return value['enabled'] == true ||
        '${value['status'] ?? ''}'.toLowerCase().contains('enabled');
  }
  return '$value'.toLowerCase().contains('true') ||
      '$value'.toLowerCase().contains('enabled');
}

bool _needsEnhancedCustodyReview(Map<String, dynamic> delivery) {
  if (!_hasVanguardProtection(delivery)) return false;
  final haystack = [
    delivery['vanguardCustodyReviewStatus'],
    delivery['vanguardCustodyEvidenceStatus'],
    delivery['custodyIntegrityStatus'],
    delivery['chainOfCustodyStatus'],
    delivery['enhancedCustodyStatus'],
    delivery['proofTimelineStatus'],
    delivery['exceptionStatus'],
    delivery['supportStatus'],
    delivery['adminOperationStatus'],
  ].join(' ').toLowerCase();
  if (haystack.contains('closed') || haystack.contains('resolved')) {
    return false;
  }
  if (haystack.contains('review') ||
      haystack.contains('flag') ||
      haystack.contains('concern') ||
      haystack.contains('missing') ||
      haystack.contains('exception') ||
      haystack.contains('escalat') ||
      haystack.contains('request')) {
    return true;
  }
  return _historyCountValue(delivery, const [
        'chainOfCustody',
        'custodyTimeline',
        'custodyEvents',
        'collectionEvidence',
        'pickupEvidence',
        'transferEvidence',
        'handoffEvidence',
        'dropoffEvidence',
        'deliveryEvidence',
        'proofOfDelivery',
      ]) >
      0;
}

String _enhancedCustodyStatus(Map<String, dynamic> delivery) {
  final values = [
    delivery['vanguardCustodyReviewStatus'],
    delivery['custodyIntegrityStatus'],
    delivery['chainOfCustodyStatus'],
    delivery['enhancedCustodyStatus'],
  ].where((value) => '$value'.trim().isNotEmpty).toList();
  return values.isEmpty ? 'Review not opened' : values.join(' / ');
}

String _enhancedCustodyEvidenceSummary(Map<String, dynamic> delivery) {
  final collection = _historyCount(delivery, const [
    'collectionEvidence',
    'pickupEvidence',
    'collectionPhotos',
  ]);
  final transfer = _historyCount(delivery, const [
    'transferEvidence',
    'handoffEvidence',
    'custodyTransfers',
  ]);
  final dropoff = _historyCount(delivery, const [
    'dropoffEvidence',
    'deliveryEvidence',
    'proofOfDelivery',
  ]);
  final status = '${delivery['vanguardCustodyEvidenceStatus'] ?? ''}'.trim();
  final summary =
      'Collection $collection / Transfer $transfer / Drop-off $dropoff';
  return status.isEmpty ? summary : '$summary / $status';
}

String _enhancedCustodyCheckpointSummary(Map<String, dynamic> delivery) {
  final checkpoints = _historyCount(delivery, const [
    'vanguardCheckpoints',
    'proofTimeline',
    'custodyTimeline',
    'custodyEvents',
    'chainOfCustody',
  ]);
  final status = '${delivery['proofTimelineStatus'] ?? ''}'.trim();
  return status.isEmpty
      ? '$checkpoints checkpoint(s)'
      : '$checkpoints checkpoint(s) / $status';
}

int _historyCountValue(Map<String, dynamic> record, List<String> fields) {
  var total = 0;
  for (final field in fields) {
    final value = record[field];
    if (value is List) total += value.length;
    if (value is Map) total += value.length;
    if (value is String && value.trim().isNotEmpty) total += 1;
  }
  return total;
}

bool _isSameDay(Map<String, dynamic> record, DateTime day) {
  DateTime? date;
  final value =
      record['completedAt'] ??
      record['cancelledAt'] ??
      record['updatedAt'] ??
      record['createdAt'];
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (value is String) date = DateTime.tryParse(value);
  if (value is int) date = DateTime.fromMillisecondsSinceEpoch(value);
  return date != null &&
      date.year == day.year &&
      date.month == day.month &&
      date.day == day.day;
}

int _countFlag(List<Map<String, dynamic>> records, String flag) {
  return records.where((record) {
    final text = record.values.join(' ').toLowerCase();
    return text.contains(flag);
  }).length;
}

String _deliveryFlagSummary(Map<String, dynamic> delivery) {
  final flags = <String>[];
  if (_hasVanguardProtection(delivery)) flags.add('Vanguard');
  if (_isWaitingDelivery(delivery)) flags.add('Waiting');
  if (_isNoShowDelivery(delivery)) flags.add('No-show');
  if ('${delivery['irisReviewStatus'] ?? delivery['reviewType'] ?? ''}'
      .toLowerCase()
      .contains('iris')) {
    flags.add('IRIS');
  }
  if ('${delivery['paymentStatus'] ?? ''}'.toLowerCase().contains('paid')) {
    flags.add('Paid');
  }
  return flags.isEmpty ? 'No flags' : flags.join(', ');
}

String _riderMonitoringSummary(
  Map<String, dynamic> rider,
  List<Map<String, dynamic>> deliveries,
  List<Map<String, dynamic>> payments,
) {
  final riderId = _riderId(rider);
  final riderDeliveries = deliveries.where(
    (item) => _deliveryBelongsToRider(item, riderId),
  );
  final active = riderDeliveries.where(_isActiveDelivery).length;
  final jobsToday = _jobsSince(riderDeliveries, DateTime.now());
  final earningsToday = _earningsSince(riderDeliveries, DateTime.now());
  return '$active active / $jobsToday today / ${_money(earningsToday)} today';
}

String _addressSummary(Map<String, dynamic> record) {
  final address = record['address'];
  if (address is Map) {
    return [
      address['line1'],
      address['city'],
      address['postcode'],
    ].where((part) => '$part'.trim().isNotEmpty).join(', ');
  }
  return '${record['address'] ?? record['homeAddress'] ?? 'Not recorded'}';
}

String _locationSummary(Map<String, dynamic> record) {
  final location = record['lastLocation'] ?? record['location'];
  if (location is GeoPoint) {
    return '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
  }
  if (location is Map) {
    final lat = location['latitude'] ?? location['lat'];
    final lng = location['longitude'] ?? location['lng'];
    if (lat != null && lng != null) return '$lat, $lng';
  }
  final lat = record['latitude'] ?? record['lat'];
  final lng = record['longitude'] ?? record['lng'];
  if (lat != null && lng != null) return '$lat, $lng';
  return 'Not recorded';
}

String _documentStatus(List<Map<String, dynamic>> docs, String type) {
  for (final doc in docs) {
    final docType = '${doc['type'] ?? doc['documentType'] ?? ''}'.toLowerCase();
    if (docType.contains(type)) {
      return '${doc['status'] ?? doc['verificationStatus'] ?? 'pending'}';
    }
  }
  return 'Not loaded';
}

int _jobsSince(Iterable<Map<String, dynamic>> deliveries, DateTime day) {
  return deliveries.where((item) => _isSameDay(item, day)).length;
}

double _earningsSince(Iterable<Map<String, dynamic>> deliveries, DateTime day) {
  return deliveries
      .where((item) => _isSameDay(item, day))
      .fold<double>(
        0,
        (total, delivery) =>
            total +
            (double.tryParse(
                  '${delivery['riderPayout'] ?? delivery['driverPayout'] ?? delivery['estimatedDriverPayout'] ?? 0}',
                ) ??
                0),
      );
}

double _earningsThisWeek(Iterable<Map<String, dynamic>> deliveries) {
  final now = DateTime.now();
  final weekStart = now.subtract(Duration(days: now.weekday - 1));
  return deliveries
      .where((item) {
        DateTime? date;
        final value =
            item['completedAt'] ?? item['updatedAt'] ?? item['createdAt'];
        if (value is Timestamp) date = value.toDate();
        if (value is DateTime) date = value;
        if (value is String) date = DateTime.tryParse(value);
        if (value is int) date = DateTime.fromMillisecondsSinceEpoch(value);
        return date != null && !date.isBefore(weekStart);
      })
      .fold<double>(
        0,
        (total, delivery) =>
            total +
            (double.tryParse(
                  '${delivery['riderPayout'] ?? delivery['driverPayout'] ?? delivery['estimatedDriverPayout'] ?? 0}',
                ) ??
                0),
      );
}

String _historyCount(Map<String, dynamic> account, List<String> fields) {
  var total = 0;
  for (final field in fields) {
    final value = account[field];
    if (value is List) total += value.length;
    if (value is Map) total += value.length;
    if (value is num) total += value.toInt();
  }
  return total == 0 ? 'No records loaded' : '$total';
}

String _money(Object? value) {
  if (value is num) return '£${value.toStringAsFixed(2)}';
  final parsed = double.tryParse('$value');
  if (parsed == null) return '£0.00';
  return '£${parsed.toStringAsFixed(2)}';
}

String _percent(Object? value) {
  final amount = _numberFrom(value);
  final normalized = amount <= 1 && amount > 0 ? amount * 100 : amount;
  return '${normalized.toStringAsFixed(1)}%';
}

double _numberFrom(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

String _date(Object? value) {
  final date = _dateTimeFrom(value);
  if (date == null) return 'Not recorded';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

DateTime? _dateTimeFrom(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}
