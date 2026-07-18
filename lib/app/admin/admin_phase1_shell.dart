import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_operations.dart';
import 'admin_root.dart';

enum AdminModule {
  dashboard('Dashboard', Icons.dashboard_rounded),
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
    final driverStatus = switch (status) {
      'approved' => 'active',
      'rejected' => 'rejected',
      'suspended' => 'suspended',
      _ => status,
    };
    await _db.collection('riderProfiles').doc(id).set({
      'approvalStatus': status,
      'driverStatus': driverStatus,
      'verificationStatus': status == 'approved' ? 'approved' : status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _writeAudit(AdminAuditEntry(
      adminUserId: _user?.uid ?? 'unknown-admin',
      actionType: 'rider_status_$status',
      recordType: 'riderProfiles',
      recordId: id,
      oldValue: {
        'approvalStatus': rider['approvalStatus'],
        'driverStatus': rider['driverStatus'],
      },
      newValue: {'approvalStatus': status, 'driverStatus': driverStatus},
      reason: 'Rider status updated from Admin',
    ));
    setState(() => _message = 'Rider $id updated to $status.');
    await _loadAdminData();
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
    setState(() => _selectedRider = rider);
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
                      canManageIssues: _can(AdminPermission.manageIssues),
                      canManageHealthPlus:
                          _can(AdminPermission.manageHealthPlus),
                      onDuplicateDelivery: _duplicateDelivery,
                      onSetRiderStatus: _setRiderStatus,
                      onUpdateSupportTicket: _updateSupportTicket,
                      onUpdateHealthPlusPickup: _updateHealthPlusPickup,
                      onOpenRiderProfile: _openRiderProfile,
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
          ? null
          : _RiderProfileDrawer(
              rider: _selectedRider!,
              deliveries: _data.deliveries,
              documents: _data.riderDocuments,
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
    required this.canManageIssues,
    required this.canManageHealthPlus,
    required this.onDuplicateDelivery,
    required this.onSetRiderStatus,
    required this.onUpdateSupportTicket,
    required this.onUpdateHealthPlusPickup,
    required this.onOpenRiderProfile,
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
  final bool canManageIssues;
  final bool canManageHealthPlus;
  final ValueChanged<Map<String, dynamic>> onDuplicateDelivery;
  final Future<void> Function(Map<String, dynamic>, String) onSetRiderStatus;
  final Future<void> Function(Map<String, dynamic>, String)
      onUpdateSupportTicket;
  final Future<void> Function(Map<String, dynamic>, String)
      onUpdateHealthPlusPickup;
  final ValueChanged<Map<String, dynamic>> onOpenRiderProfile;
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
          AdminModule.discrepancyReview =>
            const AdminDeliveryAdjustmentReviewQueue(),
          AdminModule.deliveries => _RecordModule(
              title: 'Deliveries',
              subtitle:
                  'Live delivery requests, lifecycle state, route and value.',
              records: data.deliveries,
              query: query,
              fields: const [
                'id',
                'requestId',
                'status',
                'senderName',
                'pickupAddress',
                'dropoffAddress'
              ],
              columns: const ['ID', 'Route', 'Status', 'Value'],
              row: (record) => [
                _recordId(record),
                '${record['pickupAddress'] ?? 'Pickup'} -> ${record['dropoffAddress'] ?? 'Dropoff'}',
                '${record['status'] ?? record['deliveryStatus'] ?? 'unknown'}',
                _money(record['finalAmount'] ??
                    record['quote'] ??
                    record['price']),
              ],
              actions: canDuplicateDeliveries
                  ? (record) => [
                        _MiniAction(
                          label: 'Duplicate',
                          onPressed: () => onDuplicateDelivery(record),
                        ),
                      ]
                  : null,
            ),
          AdminModule.users => _RecordModule(
              title: 'Users',
              subtitle: 'Sender/customer accounts from backend records.',
              records: data.users,
              query: query,
              fields: const ['id', 'fullName', 'name', 'email', 'phone'],
              columns: const ['Name', 'Email', 'Phone', 'Status'],
              row: (record) => [
                '${record['fullName'] ?? record['name'] ?? record['id']}',
                '${record['email'] ?? 'Not recorded'}',
                '${record['phone'] ?? record['phoneNumber'] ?? 'Not recorded'}',
                '${record['status'] ?? record['accountStatus'] ?? 'active'}',
              ],
            ),
          AdminModule.riders => _RecordModule(
              title: 'Riders',
              subtitle:
                  'Rider profiles, verification status, vehicle and rank.',
              records: data.riders,
              query: query,
              fields: const [
                'id',
                'fullName',
                'name',
                'email',
                'vehicleType',
                'driverStatus',
                'approvalStatus'
              ],
              columns: const ['Rider', 'Vehicle', 'Status', 'Rank'],
              row: (record) => [
                '${record['fullName'] ?? record['name'] ?? record['id']}',
                '${record['vehicleType'] ?? record['vehicle'] ?? 'Not recorded'}',
                '${record['approvalStatus'] ?? record['driverStatus'] ?? record['status'] ?? 'pending'}',
                RiderRankPolicy.fromProfile(record),
              ],
              actions: canManageRiders
                  ? (record) => _riderActions(
                        record,
                        onSetRiderStatus,
                        onOpenRiderProfile,
                      )
                  : null,
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
          AdminModule.finance => _RecordModule(
              title: 'Finance',
              subtitle:
                  'Payments, payouts and wallet-relevant finance records.',
              records: data.payments,
              query: query,
              fields: const ['id', 'status', 'senderId', 'riderId', 'type'],
              columns: const ['Record', 'Status', 'Amount', 'Created'],
              row: (record) => [
                _recordId(record),
                '${record['status'] ?? 'unknown'}',
                _money(record['amount'] ?? record['total'] ?? record['price']),
                _date(record['createdAt'] ?? record['timestamp']),
              ],
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
              fields: const ['id', 'businessName', 'email', 'status'],
              columns: const ['Business', 'Email', 'Status', 'Updated'],
              row: (record) => [
                '${record['businessName'] ?? record['companyName'] ?? record['id']}',
                '${record['email'] ?? 'Not recorded'}',
                '${record['status'] ?? 'pending'}',
                _date(record['updatedAt'] ?? record['createdAt']),
              ],
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

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.metrics, required this.data});

  final AdminMetricSnapshot metrics;
  final AdminDataBundle data;

  @override
  Widget build(BuildContext context) {
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
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Operational pulse',
          subtitle: 'Recent live records loaded from production collections.',
          records: [
            ...data.deliveries.take(6),
            ...data.supportTickets.take(4),
          ],
          query: '',
          fields: const [],
          columns: const ['Record', 'Type', 'Status', 'Updated'],
          row: (record) => [
            _recordId(record),
            record.containsKey('pickupAddress') ? 'Delivery' : 'Support',
            '${record['status'] ?? record['deliveryStatus'] ?? 'open'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
        ),
      ],
    );
  }
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

class _RiderProfileDrawer extends StatelessWidget {
  const _RiderProfileDrawer({
    required this.rider,
    required this.deliveries,
    required this.documents,
    required this.onClose,
    required this.onSetStatus,
  });

  final Map<String, dynamic> rider;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> documents;
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
                ('Phone', rider['phoneNumber'] ?? rider['phone']),
                ('Vehicle', rider['vehicleType'] ?? rider['vehicle']),
                ('Plate', rider['plateNumber'] ?? rider['vehicleRegistration']),
                ('Joined', _date(rider['createdAt'])),
                ('Last updated', _date(rider['updatedAt'])),
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

String _money(Object? value) {
  if (value is num) return '£${value.toStringAsFixed(2)}';
  final parsed = double.tryParse('$value');
  if (parsed == null) return '£0.00';
  return '£${parsed.toStringAsFixed(2)}';
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
