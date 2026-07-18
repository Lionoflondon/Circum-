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
  discrepancyReview('Discrepancy review', Icons.fact_check_rounded),
  users('Users', Icons.people_alt_rounded),
  riders('Riders', Icons.two_wheeler_rounded),
  verification('Verification', Icons.verified_user_rounded),
  support('Support', Icons.support_agent_rounded),
  finance('Finance', Icons.account_balance_wallet_rounded),
  healthPlus('Health+', Icons.local_hospital_rounded),
  business('Business', Icons.business_center_rounded),
  gifts('Gifts', Icons.card_giftcard_rounded),
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
  Map<String, dynamic>? _selectedAccount;
  String _selectedAccountType = 'sender';
  Map<String, dynamic>? _selectedChat;
  AdminRole _adminInviteRole = AdminRole.operationsAdmin;
  bool _loading = true;
  bool _signingIn = false;
  bool _loadingData = false;
  String? _message;
  StreamSubscription<User?>? _authSub;

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
    _email.dispose();
    _password.dispose();
    _search.dispose();
    _adminInviteEmail.dispose();
    _adminInviteNote.dispose();
    _chatMessage.dispose();
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
        setState(() => _message =
            'This account is signed in but has no active Circum admin role.');
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
    await _writeAudit(AdminAuditEntry(
      adminUserId: _user?.uid ?? 'unknown-admin',
      actionType: 'delivery_duplicate',
      recordType: 'deliveryRequests',
      recordId: newId,
      oldValue: {'requestId': delivery['requestId'] ?? delivery['id']},
      newValue: {'requestId': newId},
      reason: 'Admin duplicated delivery from operations console',
    ));
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
    final patch = AdminRiderOperationsTools.statusPatch(
      status: status,
      updatedBy: _user?.email ?? _user?.uid ?? 'admin',
      updatedAt: FieldValue.serverTimestamp(),
      reason: 'Updated from Circum Admin Rider Operations',
    );
    await _db
        .collection('riderProfiles')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(AdminAuditEntry(
      adminUserId: _user?.uid ?? 'unknown-admin',
      actionType: 'rider_status_$status',
      recordType: 'riderProfiles',
      recordId: id,
      oldValue: {
        'approvalStatus': rider['approvalStatus'],
        'driverStatus': rider['driverStatus'],
      },
      newValue: patch,
      reason: 'Rider status updated from Admin',
    ));
    setState(() => _message = 'Rider $id updated to $status.');
    await _loadAdminData();
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
    await _writeAudit(AdminAuditEntry(
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
    ));
    setState(() => _message = 'Delivery $id queued for $status.');
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
    await _writeAudit(AdminAuditEntry(
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
    ));
    setState(() => _message = 'IRIS review for $id marked $status.');
    await _loadAdminData();
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
    await _writeAudit(AdminAuditEntry(
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
    ));
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
    await _writeAudit(AdminAuditEntry(
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
    ));
    setState(() => _message = 'Business account $id updated to $status.');
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
      await _writeAudit(AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'account_merge_review_requested',
        recordType: 'accountMergeReviews',
        recordId: '$id:$duplicateId',
        newValue: {
          'primaryAccountId': id,
          'duplicateAccountId': duplicateId,
        },
        reason: 'Duplicate account merge review requested from Admin',
      ));
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
    final patch = AdminSupportTools.statusPatch(
      status: status,
      assignedTo: status == 'assigned' ? _user?.email : null,
      resolutionNote:
          status == 'resolved' ? 'Resolved from Circum Admin' : null,
      updatedAt: FieldValue.serverTimestamp(),
    );
    await _db
        .collection('supportTickets')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(AdminAuditEntry(
      adminUserId: _user?.uid ?? 'unknown-admin',
      actionType: 'support_ticket_$status',
      recordType: 'supportTickets',
      recordId: id,
      oldValue: {'status': ticket['status']},
      newValue: {'status': status},
      reason: 'Support ticket updated from Admin',
    ));
    setState(() => _message = 'Support ticket $id updated to $status.');
    await _loadAdminData();
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
    await _writeAudit(AdminAuditEntry(
      adminUserId: _user?.uid ?? 'unknown-admin',
      actionType: 'health_plus_status_update',
      recordType: 'prescriptionPickups',
      recordId: id,
      oldValue: {'status': pickup['status']},
      newValue: {'status': status},
      reason: 'Health+ pickup updated from Admin',
    ));
    setState(() => _message = 'Health+ pickup $id updated to $status.');
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
    await _writeAudit(AdminAuditEntry(
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
    ));
    setState(() => _message = 'Finance record $id marked $status.');
    await _loadAdminData();
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
    final normalizedEmail =
        AdminUserAccess.emailDocumentId(email ?? '${existing?['email'] ?? ''}');
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      setState(() => _message = 'Enter a valid Admin email address.');
      return;
    }
    final selectedRole = role ??
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
    await _writeAudit(AdminAuditEntry(
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
    ));
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
      await _writeAudit(AdminAuditEntry(
        adminUserId: _user?.uid ?? 'unknown-admin',
        actionType: 'admin_chat_message',
        recordType: 'chats',
        recordId: chatId,
        newValue: {
          'chatId': chatId,
          'messageLength': message.length,
        },
        reason: 'Admin replied to chat thread',
      ));
      _chatMessage.clear();
      setState(() => _message = 'Message sent to $chatId.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = _functionsMessage(error));
    } catch (_) {
      setState(() => _message = 'Could not send this message.');
    }
  }

  void _openRiderProfile(Map<String, dynamic> rider) {
    setState(() {
      _selectedRider = rider;
      _selectedDelivery = null;
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
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  void _openDeliveryProfile(Map<String, dynamic> delivery) {
    setState(() {
      _selectedDelivery = delivery;
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
      'invalid-credential' =>
        'Those sign-in details are not right.',
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
                      canDuplicateDeliveries:
                          _can(AdminPermission.duplicateDeliveries),
                      canManageRiders: _can(AdminPermission.approveDrivers),
                      canEditDeliveries: _can(AdminPermission.editDeliveries),
                      canManageIssues: _can(AdminPermission.manageIssues),
                      canManageHealthPlus:
                          _can(AdminPermission.manageHealthPlus),
                      canManageFinance: _can(AdminPermission.manageFinance),
                      onDuplicateDelivery: _duplicateDelivery,
                      onSetRiderStatus: _setRiderStatus,
                      onSetDeliveryOperationStatus: _setDeliveryOperationStatus,
                      onSetIrisReviewStatus: _setIrisReviewStatus,
                      onUpdateSupportTicket: _updateSupportTicket,
                      onUpdateHealthPlusPickup: _updateHealthPlusPickup,
                      onUpdateFinanceWorkflow: _updateFinanceWorkflow,
                      onOpenRiderProfile: _openRiderProfile,
                      onOpenDeliveryProfile: _openDeliveryProfile,
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
                      onSelectChat: (chat) =>
                          setState(() => _selectedChat = chat),
                      onSendChatMessage: _sendChatMessage,
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
                      onClose: () => setState(() => _selectedAccount = null),
                      onSetSenderStatus: (status) =>
                          _setSenderAccountStatus(_selectedAccount!, status),
                      onSetBusinessStatus: (status) =>
                          _setBusinessAccountStatus(_selectedAccount!, status),
                      onRequestDuplicateMerge: (duplicate) =>
                          _requestDuplicateMerge(_selectedAccount!, duplicate),
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
    required this.ratings,
    required this.supportTickets,
    required this.healthPlusPayments,
    required this.healthPlusPickups,
    required this.businessAccounts,
    required this.giftOrders,
    required this.auditLogs,
    required this.chats,
    required this.riderDocuments,
    required this.websiteVisitors,
  });

  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> adminUsers;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> ratings;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> healthPlusPayments;
  final List<Map<String, dynamic>> healthPlusPickups;
  final List<Map<String, dynamic>> businessAccounts;
  final List<Map<String, dynamic>> giftOrders;
  final List<Map<String, dynamic>> auditLogs;
  final List<Map<String, dynamic>> chats;
  final List<Map<String, dynamic>> riderDocuments;
  final List<Map<String, dynamic>> websiteVisitors;

  static AdminDataBundle empty() => const AdminDataBundle(
        deliveries: [],
        users: [],
        riders: [],
        adminUsers: [],
        payments: [],
        ratings: [],
        supportTickets: [],
        healthPlusPayments: [],
        healthPlusPickups: [],
        businessAccounts: [],
        giftOrders: [],
        auditLogs: [],
        chats: [],
        riderDocuments: [],
        websiteVisitors: [],
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
      _read(_db.collection('driverRatings').limit(100)),
      canViewSupport
          ? _read(_db.collection('supportTickets').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      canViewHealthPlus || canViewFinance
          ? _read(_db.collection('healthPlusPayments').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      canViewHealthPlus
          ? _read(_db.collection('prescriptionPickups').limit(100))
          : Future.value(<Map<String, dynamic>>[]),
      _read(_db.collection('businessAccounts').limit(100)),
      _read(_db.collection('giftOrders').limit(100)),
      _read(_db
          .collection('adminAuditLogs')
          .orderBy('createdAt', descending: true)
          .limit(50)),
      _read(_db
          .collection('chats')
          .orderBy('updatedAt', descending: true)
          .limit(50)),
      _read(_db.collection('riderDocuments').limit(150)),
      _read(_db
          .collection('websiteVisitors')
          .orderBy('createdAt', descending: true)
          .limit(150)),
    ]);
    return AdminDataBundle(
      deliveries: results[0],
      users: results[1],
      riders: results[2],
      adminUsers: results[3],
      payments: results[4],
      ratings: results[5],
      supportTickets: results[6],
      healthPlusPayments: results[7],
      healthPlusPickups: results[8],
      businessAccounts: results[9],
      giftOrders: results[10],
      auditLogs: results[11],
      chats: results[12],
      riderDocuments: results[13],
      websiteVisitors: results[14],
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
                      style:
                          TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in with an active Admin role.',
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: .7)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        children: [
          Row(
            children: [
              if (mobile)
                PopupMenuButton<AdminModule>(
                  icon: const Icon(Icons.menu_rounded),
                  onSelected: onSelect,
                  itemBuilder: (_) => [
                    for (final module in AdminModule.values)
                      PopupMenuItem(
                        value: module,
                        child: Text(module.label),
                      ),
                  ],
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin surface',
                      style: TextStyle(
                        color: const Color(0xFF7DD3FC).withValues(alpha: .86),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      selected.label,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      user?.email ?? 'Admin',
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: .6)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: search,
            onChanged: (_) => onSearchChanged(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search current Admin module',
              border: OutlineInputBorder(),
            ),
          ),
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
    required this.onSetIrisReviewStatus,
    required this.onUpdateSupportTicket,
    required this.onUpdateHealthPlusPickup,
    required this.onUpdateFinanceWorkflow,
    required this.onOpenRiderProfile,
    required this.onOpenDeliveryProfile,
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
    required this.chatMessage,
    required this.selectedChat,
    required this.onSelectChat,
    required this.onSendChatMessage,
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
  final Future<void> Function(Map<String, dynamic>, String)
      onSetIrisReviewStatus;
  final Future<void> Function(Map<String, dynamic>, String)
      onUpdateSupportTicket;
  final Future<void> Function(Map<String, dynamic>, String)
      onUpdateHealthPlusPickup;
  final Future<void> Function(Map<String, dynamic>, String)
      onUpdateFinanceWorkflow;
  final ValueChanged<Map<String, dynamic>> onOpenRiderProfile;
  final ValueChanged<Map<String, dynamic>> onOpenDeliveryProfile;
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
  final TextEditingController chatMessage;
  final Map<String, dynamic>? selectedChat;
  final ValueChanged<Map<String, dynamic>> onSelectChat;
  final VoidCallback onSendChatMessage;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        switch (module) {
          AdminModule.dashboard => _Dashboard(metrics: metrics, data: data),
          AdminModule.visitorAnalytics =>
            _VisitorAnalyticsModule(records: data.websiteVisitors),
          AdminModule.discrepancyReview => _IrisOperationsModule(
              deliveries: data.deliveries,
              auditLogs: data.auditLogs,
              query: query,
              canManageIris: canEditDeliveries,
              onOpenDelivery: onOpenDeliveryProfile,
              onSetIrisReviewStatus: onSetIrisReviewStatus,
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
            ),
          AdminModule.users => _RecordModule(
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
                'verificationStatus'
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
              ),
            ),
          AdminModule.riders => _RiderOperationsModule(
              riders: data.riders,
              deliveries: data.deliveries,
              documents: data.riderDocuments,
              ratings: data.ratings,
              payments: data.payments,
              query: query,
              canManageRiders: canManageRiders,
              onOpenRiderProfile: onOpenRiderProfile,
              onSetRiderStatus: onSetRiderStatus,
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
                'approvalStatus'
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
                      )
                  : null,
            ),
          AdminModule.support => _RecordModule(
              title: 'Support',
              subtitle: 'Support tickets and operational issue intake.',
              records: data.supportTickets,
              query: query,
              fields: const [
                'id',
                'name',
                'email',
                'message',
                'status',
                'type'
              ],
              columns: const ['Ticket', 'Customer', 'Status', 'Message'],
              row: (record) => [
                _recordId(record),
                '${record['name'] ?? record['email'] ?? 'Customer'}',
                '${record['status'] ?? 'open'}',
                '${record['message'] ?? record['type'] ?? ''}',
              ],
              actions: canManageIssues
                  ? (record) => [
                        _MiniAction(
                          label: 'Assign',
                          onPressed: () =>
                              onUpdateSupportTicket(record, 'assigned'),
                        ),
                        _MiniAction(
                          label: 'Resolve',
                          onPressed: () =>
                              onUpdateSupportTicket(record, 'resolved'),
                        ),
                        _MiniAction(
                          label: 'Reopen',
                          onPressed: () =>
                              onUpdateSupportTicket(record, 'open'),
                        ),
                      ]
                  : null,
            ),
          AdminModule.finance => _FinanceOperationsModule(
              payments: data.payments,
              deliveries: data.deliveries,
              supportTickets: data.supportTickets,
              auditLogs: data.auditLogs,
              query: query,
              canManageFinance: canManageFinance,
              onUpdateFinanceWorkflow: onUpdateFinanceWorkflow,
            ),
          AdminModule.healthPlus => _RecordModule(
              title: 'Health+',
              subtitle: 'Prescription pickup and Health+ payment operations.',
              records: [...data.healthPlusPickups, ...data.healthPlusPayments],
              query: query,
              fields: const [
                'id',
                'fullName',
                'pharmacyAddress',
                'deliveryAddress',
                'status'
              ],
              columns: const ['Record', 'Customer', 'Status', 'Schedule'],
              row: (record) => [
                _recordId(record),
                '${record['fullName'] ?? record['customerName'] ?? 'Customer'}',
                '${record['status'] ?? 'pending'}',
                '${record['frequency'] ?? record['pickupTime'] ?? 'Not recorded'}',
              ],
              actions: canManageHealthPlus
                  ? (record) => [
                        _MiniAction(
                          label: 'Assign',
                          onPressed: () =>
                              onUpdateHealthPlusPickup(record, 'assigned'),
                        ),
                        _MiniAction(
                          label: 'Collected',
                          onPressed: () =>
                              onUpdateHealthPlusPickup(record, 'collected'),
                        ),
                        _MiniAction(
                          label: 'Complete',
                          onPressed: () =>
                              onUpdateHealthPlusPickup(record, 'completed'),
                        ),
                      ]
                  : null,
            ),
          AdminModule.business => _RecordModule(
              title: 'Business',
              subtitle:
                  'Business account applications and operational records.',
              records: data.businessAccounts,
              query: query,
              fields: const [
                'id',
                'businessName',
                'companyName',
                'email',
                'status',
                'verificationStatus'
              ],
              columns: const ['Business', 'Email', 'Status', 'Verification'],
              row: (record) => [
                '${record['businessName'] ?? record['companyName'] ?? record['id']}',
                '${record['email'] ?? 'Not recorded'}',
                '${record['status'] ?? 'pending'}',
                '${record['verificationStatus'] ?? 'pending'}',
              ],
              actions: (record) => _accountActions(
                account: record,
                accountType: 'business',
                allAccounts: data.businessAccounts,
                onOpen: onOpenAccountProfile,
                onSetStatus: onSetBusinessAccountStatus,
                onRequestDuplicateMerge: onRequestDuplicateMerge,
              ),
            ),
          AdminModule.gifts => _RecordModule(
              title: 'Gifts',
              subtitle: 'Gift orders and related fulfilment state.',
              records: data.giftOrders,
              query: query,
              fields: const ['id', 'giftName', 'recipientName', 'status'],
              columns: const ['Gift', 'Recipient', 'Status', 'Created'],
              row: (record) => [
                '${record['giftName'] ?? record['title'] ?? record['id']}',
                '${record['recipientName'] ?? 'Recipient'}',
                '${record['status'] ?? 'pending'}',
                _date(record['createdAt']),
              ],
            ),
          AdminModule.audit => _RecordModule(
              title: 'Audit',
              subtitle: 'Immutable Admin operational audit trail.',
              records: data.auditLogs,
              query: query,
              fields: const ['actionType', 'recordType', 'recordId', 'reason'],
              columns: const ['Action', 'Record', 'Admin', 'Reason'],
              row: (record) => [
                '${record['actionType'] ?? 'action'}',
                '${record['recordType'] ?? ''}/${record['recordId'] ?? record['id']}',
                '${record['adminUserId'] ?? 'admin'}',
                '${record['reason'] ?? ''}',
              ],
            ),
          AdminModule.chat => _ChatModule(
              records: data.chats,
              query: query,
              message: chatMessage,
              selectedChat: selectedChat,
              onSelectChat: onSelectChat,
              onSendChatMessage: onSendChatMessage,
            ),
          AdminModule.settings => _SettingsModule(
              canManageAdmins: canManageAdmins,
              adminUsers: data.adminUsers,
              inviteEmail: adminInviteEmail,
              inviteNote: adminInviteNote,
              inviteRole: adminInviteRole,
              onInviteRoleChanged: onAdminInviteRoleChanged,
              onCreateAdminUser: onCreateAdminUser,
              onSetAdminUserStatus: onSetAdminUserStatus,
              onSetAdminUserRole: onSetAdminUserRole,
            ),
        },
      ],
    );
  }
}

class _IrisOperationsModule extends StatelessWidget {
  const _IrisOperationsModule({
    required this.deliveries,
    required this.auditLogs,
    required this.query,
    required this.canManageIris,
    required this.onOpenDelivery,
    required this.onSetIrisReviewStatus,
  });

  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> auditLogs;
  final String query;
  final bool canManageIris;
  final ValueChanged<Map<String, dynamic>> onOpenDelivery;
  final Future<void> Function(Map<String, dynamic>, String)
      onSetIrisReviewStatus;

  @override
  Widget build(BuildContext context) {
    final irisRecords = deliveries.where(_hasIrisSignal).toList();
    final pending = irisRecords.where(_isIrisPending).length;
    final lowConfidence = irisRecords.where(_isLowConfidenceIris).length;
    final highConfidence = irisRecords.where(_isHighConfidenceIris).length;
    final disputed = irisRecords.where(_hasWeightDispute).length;
    final learning = irisRecords.where(_isLearningCandidate).length;
    final averageConfidence = _averageIrisConfidence(irisRecords);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard('Pending reviews', pending.toString(), 'IRIS queue'),
            _MetricCard('High confidence', highConfidence.toString(), '>= 85%'),
            _MetricCard('Low confidence', lowConfidence.toString(), '< 60%'),
            _MetricCard('Weight disputes', disputed.toString(),
                'sender, rider or IRIS mismatch'),
            _MetricCard('Admin overrides',
                _countIrisOverrides(auditLogs).toString(), 'audit records'),
            _MetricCard('Learning queue', learning.toString(), 'candidates'),
            _MetricCard('Avg confidence',
                '${averageConfidence.toStringAsFixed(0)}%', 'loaded records'),
            _MetricCard(
                'Categories',
                _categoryDistribution(irisRecords).length.toString(),
                'observed'),
          ],
        ),
        const SizedBox(height: 18),
        _IrisAnalyticsPanel(records: irisRecords),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'IRIS Review Queue',
          subtitle:
              'Review delivery estimates, evidence, confidence, category, vehicle and learning flags.',
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
            'vehicleType'
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
      ],
    );
  }
}

class _IrisAnalyticsPanel extends StatelessWidget {
  const _IrisAnalyticsPanel({required this.records});

  final List<Map<String, dynamic>> records;

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
            const Text('IRIS learning and recommendation analytics',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in categories.entries.take(8))
                  _HealthChip(entry.key, entry.value),
                for (final entry in vehicles.entries.take(8))
                  _HealthChip('Vehicle ${entry.key}', entry.value),
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
    required this.deliveries,
    required this.supportTickets,
    required this.auditLogs,
    required this.query,
    required this.canManageFinance,
    required this.onUpdateFinanceWorkflow,
  });

  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> supportTickets;
  final List<Map<String, dynamic>> auditLogs;
  final String query;
  final bool canManageFinance;
  final Future<void> Function(Map<String, dynamic>, String)
      onUpdateFinanceWorkflow;

  @override
  Widget build(BuildContext context) {
    final todayRevenue = _financeTotalToday(payments);
    final outstandingSettlements =
        payments.where(_isOutstandingSettlement).length;
    final pendingRefunds = payments.where(_isPendingRefund).length;
    final failedPayments = payments.where(_isFailedPayment).length;
    final investigations = payments.where(_isFinanceInvestigation).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard("Today's revenue", _money(todayRevenue), 'payments'),
            _MetricCard('Settlements', outstandingSettlements.toString(),
                'outstanding'),
            _MetricCard('Wallet liabilities',
                _money(_walletLiability(payments)), 'loaded ledger'),
            _MetricCard('Roth circulation', _money(_rothTotal(payments)),
                'loaded records'),
            _MetricCard('Pending refunds', pendingRefunds.toString(), 'review'),
            _MetricCard('Failed payments', failedPayments.toString(), 'failed'),
            _MetricCard('Investigations', investigations.toString(), 'open'),
            _MetricCard('Stripe reconciliation',
                _stripeReconciliationStatus(payments), 'status'),
          ],
        ),
        const SizedBox(height: 18),
        _FinanceAnalyticsPanel(
          payments: payments,
          deliveries: deliveries,
          supportTickets: supportTickets,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Wallet Centre and Payment Investigations',
          subtitle:
              'Search sender, rider, business, wallet id, transaction id, Stripe reference, delivery and status.',
          records: payments,
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
            'financeReviewStatus'
          ],
          columns: const ['Record', 'Wallet/Stripe', 'Amount', 'Review'],
          row: (record) => [
            _recordId(record),
            '${record['walletId'] ?? record['stripePaymentIntentId'] ?? record['paymentIntent'] ?? record['transactionId'] ?? 'Not recorded'}',
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
                        onPressed: () => unawaited(
                            onUpdateFinanceWorkflow(record, action.$2)),
                      ),
                  ]
              : null,
        ),
      ],
    );
  }
}

class _FinanceAnalyticsPanel extends StatelessWidget {
  const _FinanceAnalyticsPanel({
    required this.payments,
    required this.deliveries,
    required this.supportTickets,
  });

  final List<Map<String, dynamic>> payments;
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
            const Text('Revenue, Roth and settlement analytics',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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
                    'Wallet usage', _countFinanceType(payments, 'wallet')),
                _HealthChip('Roth usage', _countFinanceType(payments, 'roth')),
                _HealthChip('Business revenue',
                    _countRecordsContaining(deliveries, 'business')),
                _HealthChip('Health+ revenue',
                    _countRecordsContaining(deliveries, 'health')),
                _HealthChip('Gift revenue',
                    _countRecordsContaining(deliveries, 'gift')),
                _HealthChip(
                    'Refund tickets',
                    supportTickets
                        .where(
                            (ticket) => '${ticket['type']}'.contains('refund'))
                        .length),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderOperationsModule extends StatelessWidget {
  const _RiderOperationsModule({
    required this.riders,
    required this.deliveries,
    required this.documents,
    required this.ratings,
    required this.payments,
    required this.query,
    required this.canManageRiders,
    required this.onOpenRiderProfile,
    required this.onSetRiderStatus,
  });

  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> ratings;
  final List<Map<String, dynamic>> payments;
  final String query;
  final bool canManageRiders;
  final ValueChanged<Map<String, dynamic>> onOpenRiderProfile;
  final Future<void> Function(Map<String, dynamic>, String) onSetRiderStatus;

  @override
  Widget build(BuildContext context) {
    final online = riders.where(_isOnlineRider).length;
    final suspended = riders.where(_isSuspendedRider).length;
    final pending = riders.where(_isPendingRiderRecord).length;
    final busy = riders.where((rider) {
      final id = _riderId(rider);
      return deliveries.any((delivery) =>
          _deliveryBelongsToRider(delivery, id) && _isActiveDelivery(delivery));
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
            _MetricCard('Offline', (riders.length - online).toString(),
                'not currently online'),
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
            'riderRank'
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
            'vehicleRegistration'
          ],
          columns: const ['Document', 'Rider', 'Status', 'Updated'],
          row: (record) => [
            '${record['type'] ?? record['documentType'] ?? 'Document'}',
            '${record['riderId'] ?? record['driverId'] ?? record['uid'] ?? 'unknown'}',
            '${record['status'] ?? record['verificationStatus'] ?? 'pending'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
        ),
      ],
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
                'Completed today', completedToday.toString(), 'successful'),
            _MetricCard(
                'Cancelled today', cancelledToday.toString(), 'cancelled'),
            _MetricCard('Delayed', delayed.toString(), 'late or escalated'),
            _MetricCard('Health+', _countFlag(deliveries, 'health').toString(),
                'medical'),
            _MetricCard('Business',
                _countFlag(deliveries, 'business').toString(), 'business'),
            _MetricCard('Gift', _countFlag(deliveries, 'gift').toString(),
                'gift orders'),
            _MetricCard(
                'Vanguard',
                deliveries.where(_hasVanguardProtection).length.toString(),
                'protected'),
          ],
        ),
        const SizedBox(height: 18),
        _LiveDeliveryMapPanel(deliveries: deliveries, riders: riders),
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
            'noShowReviewStatus'
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
          ),
        ),
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
            const Text('Live delivery map',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Operational route view using loaded pickup, dropoff and rider location metadata.',
              style: TextStyle(color: Colors.white.withValues(alpha: .66)),
            ),
            const SizedBox(height: 16),
            if (live.isEmpty)
              Text('No active delivery locations loaded.',
                  style: TextStyle(color: Colors.white.withValues(alpha: .62)))
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
            _MetricCard('Deliveries', metrics.totalDeliveries.toString(),
                '${metrics.activeDeliveries} active'),
            _MetricCard('Completed', metrics.completedDeliveries.toString(),
                '${metrics.cancelledDeliveries} cancelled'),
            _MetricCard('Senders', metrics.totalSenders.toString(),
                '${metrics.activeSenders} active'),
            _MetricCard('Riders', metrics.totalDrivers.toString(),
                '${metrics.pendingDrivers} pending'),
            _MetricCard('Revenue today', _money(metrics.revenueToday),
                '${_money(metrics.revenueThisMonth)} month'),
            _MetricCard('Support', metrics.unresolvedSupportIssues.toString(),
                'unresolved'),
            _MetricCard('Wallet review', health.walletReviewItems.toString(),
                'payments and payouts'),
            _MetricCard('Platform health', health.status,
                '${health.alerts.length} active alerts'),
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
                const Icon(Icons.monitor_heart_rounded,
                    color: Color(0xFF7DD3FC)),
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
              Text(alert.title,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
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
      {
        ...delivery,
        'label': _recordId(delivery),
        'domain': 'Delivery',
      },
    for (final ticket in data.supportTickets.take(4))
      {
        ...ticket,
        'label': _recordId(ticket),
        'domain': 'Support',
      },
    for (final payment in data.payments.take(4))
      {
        ...payment,
        'label': _recordId(payment),
        'domain': 'Finance',
      },
    for (final pickup in data.healthPlusPickups.take(3))
      {
        ...pickup,
        'label': _recordId(pickup),
        'domain': 'Health+',
      },
    for (final business in data.businessAccounts.take(3))
      {
        ...business,
        'label': business['businessName'] ??
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
    required this.query,
    required this.message,
    required this.selectedChat,
    required this.onSelectChat,
    required this.onSendChatMessage,
  });

  final List<Map<String, dynamic>> records;
  final String query;
  final TextEditingController message;
  final Map<String, dynamic>? selectedChat;
  final ValueChanged<Map<String, dynamic>> onSelectChat;
  final VoidCallback onSendChatMessage;

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
            _date(record['updatedAt'] ??
                record['lastMessageAt'] ??
                record['lastMessageTimestamp']),
          ],
          actions: (record) => [
            _MiniAction(
              label: selectedId == _recordId(record) ? 'Selected' : 'Reply',
              onPressed: () => onSelectChat(record),
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
            _MetricCard('Known users', uniqueUsers.length.toString(),
                'unique user ids'),
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
    required this.inviteEmail,
    required this.inviteNote,
    required this.inviteRole,
    required this.onInviteRoleChanged,
    required this.onCreateAdminUser,
    required this.onSetAdminUserStatus,
    required this.onSetAdminUserRole,
  });

  final bool canManageAdmins;
  final List<Map<String, dynamic>> adminUsers;
  final TextEditingController inviteEmail;
  final TextEditingController inviteNote;
  final AdminRole inviteRole;
  final ValueChanged<AdminRole> onInviteRoleChanged;
  final VoidCallback onCreateAdminUser;
  final Future<void> Function(Map<String, dynamic>, String)
      onSetAdminUserStatus;
  final Future<void> Function(Map<String, dynamic>, AdminRole)
      onSetAdminUserRole;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: .66)),
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
    final filtered =
        fields.isEmpty ? records : adminSearch(records, query, fields);
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle,
                style: TextStyle(color: Colors.white.withValues(alpha: .66))),
            const SizedBox(height: 18),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text('No records found.',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: .62))),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
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
                                constraints:
                                    const BoxConstraints(maxWidth: 280),
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
    return SizedBox(
      width: 188,
      child: DecoratedBox(
        decoration: _panelDecoration(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: Colors.white.withValues(alpha: .64))),
              const SizedBox(height: 12),
              Text(
                value,
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(detail,
                  style: TextStyle(color: Colors.white.withValues(alpha: .68))),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
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
          PopupMenuItem(
            value: role,
            child: Text(_adminRoleLabel(role.value)),
          ),
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
}) {
  final status =
      '${account['accountStatus'] ?? account['status'] ?? ''}'.toLowerCase();
  final duplicate = _firstLikelyDuplicate(account, allAccounts);
  final isBusiness = accountType == 'business';
  return [
    _MiniAction(
      label: 'Profile',
      onPressed: () => onOpen(account, accountType),
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
  ValueChanged<Map<String, dynamic>> onOpenProfile,
) {
  final status =
      '${record['approvalStatus'] ?? record['driverStatus'] ?? record['status'] ?? ''}'
          .toLowerCase();
  final actions = <Widget>[
    _MiniAction(
      label: 'Profile',
      onPressed: () => onOpenProfile(record),
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
}) {
  return [
    _MiniAction(
      label: 'Details',
      onPressed: () => onOpen(record),
    ),
    if (canDuplicateDeliveries)
      _MiniAction(
        label: 'Duplicate',
        onPressed: () => onDuplicate(record),
      ),
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
    ],
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
                        '${account['status'] ?? account['accountStatus'] ?? 'active'}'),
                _StatusPill(
                    label:
                        '${account['verificationStatus'] ?? account['kycStatus'] ?? 'unverified'}'),
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
                  '${account['phone'] ?? account['phoneNumber'] ?? 'Not recorded'}'
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
                  _historyCount(account, const ['devices', 'deviceHistory'])
                ),
                (
                  'Notifications',
                  _historyCount(
                      account, const ['notifications', 'notificationHistory'])
                ),
              ],
            ),
            _DrawerSection(
              title: 'Recent delivery history',
              rows: [
                for (final delivery in relatedDeliveries.take(5))
                  (
                    _recordId(delivery),
                    '${delivery['status'] ?? delivery['deliveryStatus'] ?? 'unknown'}'
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
                    '${payment['status'] ?? 'unknown'} ${_money(payment['amount'] ?? payment['total'])}'
                  ),
                for (final ticket in relatedTickets.take(4))
                  (
                    _recordId(ticket),
                    '${ticket['type'] ?? 'support'} ${ticket['status'] ?? 'open'}'
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
        .where((audit) =>
            '${audit['recordId'] ?? ''}'.trim() == riderId ||
            '${audit['recordType'] ?? ''}'.contains('rider'))
        .toList(growable: false);
    final completed = riderDeliveries
        .where((delivery) =>
            '${delivery['status'] ?? delivery['deliveryStatus'] ?? ''}'
                .toLowerCase()
                .contains('complete') ||
            '${delivery['status'] ?? delivery['deliveryStatus'] ?? ''}'
                .toLowerCase()
                .contains('delivered'))
        .length;
    final active = riderDeliveries.length - completed;
    final earnings = riderDeliveries.fold<double>(0, (total, delivery) {
      final value = delivery['riderPayout'] ??
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
                  rider['stripeStatus'] ?? rider['stripeAccountStatus']
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
                  rider['trustProgress'] ?? rider['trustScore']
                ),
                (
                  'Online duration',
                  rider['onlineDuration'] ?? rider['onlineSince']
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
                  rider['currentState'] ?? rider['availability']
                ),
                ('Current delivery', rider['currentDeliveryId']),
                ('Last location', _locationSummary(rider)),
                ('GPS freshness', _date(rider['lastLocationAt'])),
                ('Jobs today', _jobsSince(riderDeliveries, DateTime.now())),
                (
                  'Earnings today',
                  _money(_earningsSince(riderDeliveries, DateTime.now()))
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
                              'pending'
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
                    '${delivery['status'] ?? delivery['deliveryStatus'] ?? 'unknown'}'
                  ),
                for (final rating in riderRatings.take(3))
                  (
                    'Rating',
                    '${rating['starRating'] ?? rating['rating'] ?? 'unknown'} ${rating['feedback'] ?? ''}'
                  ),
                for (final ticket in riderTickets.take(3))
                  (
                    _recordId(ticket),
                    '${ticket['status'] ?? 'open'} ${ticket['type'] ?? 'support'}'
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
                    _date(audit['createdAt'])
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
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
                      delivery['assignedRiderId']
                ),
                ('Vehicle', rider?['vehicleType'] ?? delivery['vehicleType']),
                (
                  'Registration',
                  rider?['plateNumber'] ?? rider?['vehicleRegistration']
                ),
                (
                  'Rider state',
                  rider?['driverStatus'] ?? rider?['availability']
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
                  _money(delivery['finalAmount'] ?? delivery['price'])
                ),
                (
                  'Quote',
                  _money(delivery['quote'] ?? delivery['estimatedPrice'])
                ),
                ('Payment', delivery['paymentStatus'] ?? delivery['paidState']),
                (
                  'Stripe',
                  delivery['stripePaymentIntentId'] ?? delivery['paymentIntent']
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
                  delivery['verifiedWeight'] ?? delivery['riderVerifiedWeight']
                ),
                (
                  'Confidence',
                  delivery['confidence'] ?? delivery['irisConfidence']
                ),
                (
                  'IRIS review',
                  delivery['irisReviewStatus'] ?? delivery['reviewType']
                ),
                ('Vanguard enabled', _hasVanguardProtection(delivery)),
                (
                  'PIN state',
                  delivery['pinVerificationStatus'] ??
                      delivery['vanguardStatus']
                ),
              ],
            ),
            _DrawerSection(
              title: 'Evidence, messages and support',
              rows: [
                (
                  'Evidence',
                  _historyCount(
                      delivery, const ['evidence', 'photos', 'images'])
                ),
                (
                  'PIN history',
                  _historyCount(
                      delivery, const ['pinHistory', 'verificationAttempts'])
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
                    _date(audit['createdAt'])
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
                    const Text('Delivery actions',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
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
        border:
            Border.all(color: const Color(0xFF7DD3FC).withValues(alpha: .24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message),
      ),
    );
  }
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: Colors.white.withValues(alpha: .055),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: Colors.white.withValues(alpha: .10)),
  );
}

String _recordId(Map<String, dynamic> record) {
  return '${record['requestId'] ?? record['threadId'] ?? record['id'] ?? ''}';
}

String _riderId(Map<String, dynamic> rider) {
  return '${rider['id'] ?? rider['uid'] ?? rider['riderId'] ?? rider['driverId'] ?? ''}'
      .trim();
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

bool _isLowConfidenceIris(Map<String, dynamic> record) =>
    _irisConfidence(record) > 0 && _irisConfidence(record) < 60;

bool _isHighConfidenceIris(Map<String, dynamic> record) =>
    _irisConfidence(record) >= 85;

bool _hasWeightDispute(Map<String, dynamic> record) {
  final estimated = _numberFrom(record['irisEstimatedWeight'] ??
      record['estimatedWeight'] ??
      record['weight']);
  final verified = _numberFrom(record['verifiedWeight'] ??
      record['riderVerifiedWeight'] ??
      record['actualWeight']);
  if (estimated > 0 && verified > 0) return (estimated - verified).abs() >= 2;
  final state = '${record['irisReviewStatus'] ?? record['reviewType'] ?? ''}'
      .toLowerCase();
  return state.contains('dispute') || state.contains('weight');
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
  final raw = record['irisConfidence'] ??
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
  final weight = record['irisEstimatedWeight'] ??
      record['estimatedWeight'] ??
      _mapValue(record['iris'], 'weight') ??
      _mapValue(record['irisEstimate'], 'weight');
  final verified = record['verifiedWeight'] ?? record['riderVerifiedWeight'];
  final category = record['category'] ??
      record['irisCategory'] ??
      _mapValue(record['iris'], 'category');
  final vehicle = record['recommendedVehicle'] ??
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
  return payments.where((payment) => _isSameDay(payment, now)).fold<double>(
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
  final text =
      '${payment['status'] ?? payment['paymentStatus'] ?? ''}'.toLowerCase();
  return text.contains('fail') || text.contains('declin');
}

bool _isFinanceInvestigation(Map<String, dynamic> payment) {
  final text = payment.values.join(' ').toLowerCase();
  return text.contains('investigation') || text.contains('dispute');
}

double _walletLiability(List<Map<String, dynamic>> payments) {
  return payments
      .where((payment) =>
          payment.values.join(' ').toLowerCase().contains('wallet'))
      .fold<double>(
        0,
        (total, payment) =>
            total + _numberFrom(payment['balance'] ?? payment['amount']),
      );
}

double _rothTotal(List<Map<String, dynamic>> payments) {
  return payments
      .where(
          (payment) => payment.values.join(' ').toLowerCase().contains('roth'))
      .fold<double>(
        0,
        (total, payment) =>
            total + _numberFrom(payment['roth'] ?? payment['amount']),
      );
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

bool _isCompletedDelivery(Map<String, dynamic> delivery) {
  final state =
      '${delivery['status'] ?? delivery['deliveryStatus'] ?? ''}'.toLowerCase();
  return state.contains('complete') || state.contains('delivered');
}

bool _isCancelledDelivery(Map<String, dynamic> delivery) {
  final state =
      '${delivery['status'] ?? delivery['deliveryStatus'] ?? ''}'.toLowerCase();
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

bool _isSameDay(Map<String, dynamic> record, DateTime day) {
  DateTime? date;
  final value = record['completedAt'] ??
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
  final riderDeliveries =
      deliveries.where((item) => _deliveryBelongsToRider(item, riderId));
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
  return deliveries.where((item) => _isSameDay(item, day)).fold<double>(
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
  return deliveries.where((item) {
    DateTime? date;
    final value = item['completedAt'] ?? item['updatedAt'] ?? item['createdAt'];
    if (value is Timestamp) date = value.toDate();
    if (value is DateTime) date = value;
    if (value is String) date = DateTime.tryParse(value);
    if (value is int) date = DateTime.fromMillisecondsSinceEpoch(value);
    return date != null && !date.isBefore(weekStart);
  }).fold<double>(
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

double _numberFrom(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

String _date(Object? value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (value is String) date = DateTime.tryParse(value);
  if (value is int) date = DateTime.fromMillisecondsSinceEpoch(value);
  if (date == null) return 'Not recorded';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
