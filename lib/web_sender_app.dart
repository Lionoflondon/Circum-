import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:circum/app/admin/admin_operations.dart';
import 'package:circum/app/authentication/access/role_access.dart';
import 'package:circum/app/health_plus/health_plus_pricing.dart';
import 'package:circum/app/health_plus/models/pickup_status.dart';
import 'package:circum/app/health_plus/models/recurring_pickup_schedule.dart';
import 'package:circum/app/rider_profiles/driver_performance.dart';
import 'package:circum/app/sender_profile/sender_profile.dart';
import 'package:circum/pricing/delivery_pricing.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

const _companyName = 'Circum';
const _webQuoteDistanceMiles = 4.8;
const _desktopWebBreakpoint = 760.0;
const _adminHostingTarget = bool.fromEnvironment('CIRCUM_ADMIN_HOSTING');
const _spectrumGradient = [
  Color(0xffff8c00),
  Color(0xfff80032),
  Color(0xffff00a0),
  Color(0xff8c28ff),
  Color(0xff0023ff),
  Color(0xff19a0ff),
];

enum _WebAppMode { landing, sender, rider, admin }

Future<void> _ensureCircumFirebaseReady() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  }
}

class WebSenderApp extends StatefulWidget {
  const WebSenderApp({super.key});

  @override
  State<WebSenderApp> createState() => _WebSenderAppState();
}

class _WebSenderAppState extends State<WebSenderApp> {
  bool _darkMode = true;
  late _WebAppMode _mode = _initialMode();
  late final _SenderStep _initialSenderStep =
      switch (Uri.base.queryParameters['app']) {
    'health' => _SenderStep.healthPlus,
    'profile' => _SenderStep.profile,
    _ => _SenderStep.dashboard,
  };

  _WebAppMode _initialMode() {
    if (_adminHostingTarget) return _WebAppMode.admin;
    return switch (Uri.base.queryParameters['app']) {
      'sender' || 'health' || 'profile' => _WebAppMode.sender,
      'rider' || 'driver' || 'earn' => _WebAppMode.rider,
      _ => _WebAppMode.landing,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = _CircumColors(_darkMode);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: _companyName,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Helvetica',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2563eb),
          brightness: _darkMode ? Brightness.dark : Brightness.light,
        ),
      ),
      home: Scaffold(
        backgroundColor: colors.background,
        body: Stack(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: switch (_mode) {
                _WebAppMode.sender => _PhoneStage(
                    key: const ValueKey('sender-app'),
                    colors: colors,
                    child: _CustomerPortal(
                      darkMode: _darkMode,
                      colors: colors,
                      initialStep: _initialSenderStep,
                      onBack: () => setState(() => _mode = _WebAppMode.landing),
                      onRoleSelected: _openRole,
                      onToggleTheme: () =>
                          setState(() => _darkMode = !_darkMode),
                    ),
                  ),
                _WebAppMode.rider => _PhoneStage(
                    key: const ValueKey('rider-app'),
                    colors: colors,
                    child: _RiderEnrollmentPortal(
                      darkMode: _darkMode,
                      colors: colors,
                      onBack: () => setState(() => _mode = _WebAppMode.landing),
                      onRoleSelected: _openRole,
                      onToggleTheme: () =>
                          setState(() => _darkMode = !_darkMode),
                    ),
                  ),
                _WebAppMode.admin => _AdminOperationsPanel(
                    key: const ValueKey('admin-ops'),
                    colors: colors,
                    darkMode: _darkMode,
                    onBack: _adminHostingTarget
                        ? () {}
                        : () => setState(() => _mode = _WebAppMode.landing),
                    onToggleTheme: () => setState(() => _darkMode = !_darkMode),
                  ),
                _WebAppMode.landing => _LandingPage(
                    key: const ValueKey('landing'),
                    colors: colors,
                    darkMode: _darkMode,
                    onStart: () => setState(() => _mode = _WebAppMode.sender),
                    onRider: () => setState(() => _mode = _WebAppMode.rider),
                    onToggleTheme: () => setState(() => _darkMode = !_darkMode),
                  ),
              },
            ),
            _CompanyLiveChatButton(colors: colors),
          ],
        ),
      ),
    );
  }

  void _openRole(CircumRole role) {
    setState(() {
      _mode = switch (role) {
        CircumRole.sender => _WebAppMode.sender,
        CircumRole.rider => _WebAppMode.rider,
        CircumRole.admin => _WebAppMode.admin,
        CircumRole.unknown => _WebAppMode.landing,
      };
    });
  }
}

class _LandingPage extends StatelessWidget {
  final _CircumColors colors;
  final bool darkMode;
  final VoidCallback onStart;
  final VoidCallback onRider;
  final VoidCallback onToggleTheme;

  const _LandingPage({
    super.key,
    required this.colors,
    required this.darkMode,
    required this.onStart,
    required this.onRider,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _LandingNav(
            colors: colors,
            darkMode: darkMode,
            onStart: onStart,
            onRider: onRider,
            onToggleTheme: onToggleTheme,
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors.dark
                    ? const [
                        Color(0xff050816),
                        Color(0xff251047),
                        Color(0xff1d4ed8),
                        Color(0xff061826),
                      ]
                    : const [
                        Color(0xffffffff),
                        Color(0xfffff4de),
                        Color(0xffffe5f3),
                        Color(0xffebe8ff),
                        Color(0xffdff8ff),
                        Color(0xffffffff),
                      ],
                stops: colors.dark
                    ? const [0, 0.36, 0.72, 1]
                    : const [0, 0.16, 0.39, 0.62, 0.84, 1],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(22, 58, 22, 46),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                children: [
                  _PoweredByTag(colors: colors),
                  const SizedBox(height: 28),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _SpectrumSweepPainter(dark: colors.dark),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Send anything across town.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: MediaQuery.sizeOf(context).width < 680
                                ? 48
                                : 76,
                            height: 1.02,
                            color: colors.dark
                                ? Colors.white
                                : const Color(0xff111827),
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(
                                color: colors.dark
                                    ? Colors.black.withOpacity(0.32)
                                    : Colors.white.withOpacity(0.78),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Book trusted riders for parcels, prescriptions, documents, and larger items. See the price, track the parcel, and stay in control.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.mutedText,
                      fontSize:
                          MediaQuery.sizeOf(context).width < 680 ? 18 : 22,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _PillButton(
                        label: 'Send a Parcel',
                        icon: Icons.arrow_forward,
                        dark: true,
                        onPressed: onStart,
                      ),
                      _PillButton(
                        label: 'Earn as a Rider',
                        icon: Icons.two_wheeler,
                        dark: false,
                        onPressed: onRider,
                      ),
                    ],
                  ),
                  const SizedBox(height: 58),
                  _HeroMockup(colors: colors, onStart: onStart),
                ],
              ),
            ),
          ),
          _FeatureBand(colors: colors),
          _LandingFooter(colors: colors),
        ],
      ),
    );
  }
}

enum _AdminSection {
  overview,
  adminUsers,
  senders,
  drivers,
  deliveries,
  finance,
  healthPlus,
  support,
  issues,
  analytics,
  audit,
}

class _AdminOperationsPanel extends StatefulWidget {
  final _CircumColors colors;
  final bool darkMode;
  final VoidCallback onBack;
  final VoidCallback onToggleTheme;

  const _AdminOperationsPanel({
    super.key,
    required this.colors,
    required this.darkMode,
    required this.onBack,
    required this.onToggleTheme,
  });

  @override
  State<_AdminOperationsPanel> createState() => _AdminOperationsPanelState();
}

class _AdminOperationsPanelState extends State<_AdminOperationsPanel> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _search = TextEditingController();
  final _adminInviteEmail = TextEditingController();
  final _adminInviteNote = TextEditingController();
  _AdminSection _section = _AdminSection.overview;
  AdminRole _adminInviteRole = AdminRole.operationsAdmin;
  User? _adminUser;
  List<String> _roles = const [];
  bool _loading = true;
  bool _signingIn = false;
  String? _message;
  AdminMetricSnapshot _metrics = AdminMetricSnapshot.empty();
  List<Map<String, dynamic>> _deliveries = const [];
  List<Map<String, dynamic>> _senders = const [];
  List<Map<String, dynamic>> _drivers = const [];
  List<Map<String, dynamic>> _payments = const [];
  List<Map<String, dynamic>> _ratings = const [];
  List<Map<String, dynamic>> _supportTickets = const [];
  List<Map<String, dynamic>> _healthPlusPayments = const [];
  List<Map<String, dynamic>> _healthPlusPickups = const [];
  List<Map<String, dynamic>> _recurringPickupSchedules = const [];
  List<Map<String, dynamic>> _payoutRequests = const [];
  List<Map<String, dynamic>> _adminUsers = const [];
  List<Map<String, dynamic>> _auditLogs = const [];

  @override
  void initState() {
    super.initState();
    _restoreAdmin();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _search.dispose();
    _adminInviteEmail.dispose();
    _adminInviteNote.dispose();
    super.dispose();
  }

  Future<void> _restoreAdmin() async {
    setState(() => _loading = true);
    try {
      await _ensureCircumFirebaseReady();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _adminUser = null;
          _roles = const [];
          _loading = false;
        });
        return;
      }
      await _loadAdminAccess(user);
      if (AdminAccessPolicy.hasAnyAdminRole(_roles)) {
        await _loadAdminData();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Could not load admin access.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAdminAccess(User user) async {
    final token = await user.getIdTokenResult(true);
    final claims = token.claims ?? const <String, dynamic>{};
    final claimRoles = <String>[
      if (claims['adminRole'] != null) '${claims['adminRole']}',
      if (claims['role'] != null) '${claims['role']}',
      if (claims['roles'] is List)
        ...(claims['roles'] as List<dynamic>).map((role) => '$role'),
    ];
    final adminDoc = await FirebaseFirestore.instance
        .collection('adminUsers')
        .doc(user.uid)
        .get();
    final email = user.email?.trim().toLowerCase();
    final emailDoc = email == null || email.isEmpty
        ? null
        : await FirebaseFirestore.instance
            .collection('adminUsers')
            .doc(email)
            .get();
    final adminRecords = [
      if (adminDoc.exists) adminDoc.data(),
      if (emailDoc?.exists == true) emailDoc?.data(),
    ];
    final inactiveAdmin = AdminUserAccess.hasInactiveAdminRecord(adminRecords);
    final docRoles = inactiveAdmin
        ? <String>[]
        : adminRecords
            .expand((record) => AdminUserAccess.activeRolesFromRecord(record))
            .toList();
    final nextRoles = {...claimRoles, ...docRoles}.toList();
    if (inactiveAdmin) nextRoles.clear();
    setState(() {
      _adminUser = user;
      _email.text = user.email ?? _email.text;
      _roles = nextRoles;
    });
    if (nextRoles.isNotEmpty) {
      final db = FirebaseFirestore.instance;
      final patch = {'lastLoginAt': FieldValue.serverTimestamp()};
      if (adminDoc.exists) {
        await db.collection('adminUsers').doc(user.uid).set(
              patch,
              SetOptions(merge: true),
            );
      }
      if (emailDoc?.exists == true && email != null) {
        await db.collection('adminUsers').doc(email).set(
              patch,
              SetOptions(merge: true),
            );
      }
    }
  }

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _message = 'Checking admin access...';
    });
    try {
      await _ensureCircumFirebaseReady();
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
      await _loadAdminAccess(credential.user!);
      if (!AdminAccessPolicy.hasAnyAdminRole(_roles)) {
        setState(() => _message =
            'This account is signed in but has no active Circum admin role.');
        return;
      }
      await _loadAdminData();
      setState(() => _message = 'Admin panel ready.');
    } on FirebaseAuthException catch (error) {
      setState(() => _message = _friendlyAdminAuthMessage(error));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    setState(() {
      _adminUser = null;
      _roles = const [];
      _message = 'Signed out of admin.';
    });
  }

  Future<void> _loadAdminData() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      _readCollection(db.collection('deliveryRequests').limit(80)),
      _readCollection(db.collection('users').limit(80)),
      _readCollection(db.collection('riderProfiles').limit(80)),
      _can(AdminPermission.manageAdmins)
          ? _readCollection(db.collection('adminUsers').limit(80))
          : Future.value(<Map<String, dynamic>>[]),
      _can(AdminPermission.viewFinance)
          ? _readCollection(db.collection('payments').limit(80))
          : Future.value(<Map<String, dynamic>>[]),
      _readCollection(db.collection('driverRatings').limit(80)),
      _can(AdminPermission.viewSupport)
          ? _readCollection(db.collection('supportTickets').limit(80))
          : Future.value(<Map<String, dynamic>>[]),
      (_can(AdminPermission.viewFinance) ||
              _roles.contains(AdminRole.operationsAdmin.value))
          ? _readCollection(db.collection('healthPlusPayments').limit(80))
          : Future.value(<Map<String, dynamic>>[]),
      _can(AdminPermission.viewHealthPlus)
          ? _readCollection(db.collection('prescriptionPickups').limit(80))
          : Future.value(<Map<String, dynamic>>[]),
      _can(AdminPermission.viewHealthPlus)
          ? _readCollection(db.collection('recurringPickupSchedules').limit(80))
          : Future.value(<Map<String, dynamic>>[]),
      _can(AdminPermission.viewFinance)
          ? _readCollection(db.collection('payoutRequests').limit(80))
          : Future.value(<Map<String, dynamic>>[]),
      _readCollection(
        db
            .collection('adminAuditLogs')
            .orderBy('createdAt', descending: true)
            .limit(40),
      ),
    ]);
    final deliveries = results[0];
    final senders = results[1];
    final drivers = results[2];
    final adminUsers = results[3];
    final payments = results[4];
    final ratings = results[5];
    final tickets = results[6];
    final healthPayments = results[7];
    final healthPickups = results[8];
    final schedules = results[9];
    final payouts = results[10];
    setState(() {
      _deliveries = deliveries;
      _senders = senders;
      _drivers = drivers;
      _adminUsers = adminUsers;
      _payments = payments;
      _ratings = ratings;
      _supportTickets = tickets;
      _healthPlusPayments = healthPayments;
      _healthPlusPickups = healthPickups;
      _recurringPickupSchedules = schedules;
      _payoutRequests = payouts;
      _auditLogs = results[11];
      _metrics = AdminMetricSnapshot.fromData(
        deliveries: deliveries,
        senders: senders,
        drivers: drivers,
        payments: payments,
        ratings: ratings,
        supportTickets: tickets,
        healthPlusPayments: healthPayments,
      );
    });
  }

  Future<List<Map<String, dynamic>>> _readCollection(
    Query<Map<String, dynamic>> query,
  ) async {
    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList(growable: false);
  }

  Future<void> _writeAudit(AdminAuditEntry entry) async {
    await FirebaseFirestore.instance.collection('adminAuditLogs').add({
      ...entry.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _saveAdminUser({
    Map<String, dynamic>? existing,
    String? status,
  }) async {
    if (!_can(AdminPermission.manageAdmins)) {
      setState(() => _message = 'Only super admins can manage admin users.');
      return;
    }
    final email = (existing?['email'] ?? _adminInviteEmail.text)
        .toString()
        .trim()
        .toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _message = 'Enter a valid employee email address.');
      return;
    }
    if (email == _adminUser?.email?.trim().toLowerCase()) {
      setState(
          () => _message = 'You cannot change your own admin access here.');
      return;
    }
    final role = existing == null
        ? _adminInviteRole.value
        : '${existing['role'] ?? (existing['roles'] is List && (existing['roles'] as List).isNotEmpty ? (existing['roles'] as List).first : AdminRole.operationsAdmin.value)}';
    final nextStatus = status ?? '${existing?['status'] ?? 'active'}';
    final id = '${existing?['id'] ?? AdminUserAccess.emailDocumentId(email)}';
    final patch = AdminUserAccess.adminUserPatch(
      email: email,
      role: role,
      status: nextStatus,
      invitedBy: _adminUser?.email ?? _adminUser?.uid ?? 'super_admin',
      createdAt: existing == null ? FieldValue.serverTimestamp() : null,
      updatedAt: FieldValue.serverTimestamp(),
    );
    await FirebaseFirestore.instance
        .collection('adminUsers')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(AdminAuditEntry(
      adminUserId: _adminUser?.uid ?? 'unknown-admin',
      actionType: existing == null ? 'admin_user_added' : 'admin_user_updated',
      recordType: 'adminUsers',
      recordId: id,
      oldValue: existing == null
          ? const {}
          : {
              'role': existing['role'] ?? existing['roles'],
              'status': existing['status'],
            },
      newValue: {'role': role, 'status': nextStatus, 'email': email},
      reason: _adminInviteNote.text.trim().isEmpty
          ? 'Admin access managed from admin panel'
          : _adminInviteNote.text.trim(),
    ));
    _adminInviteEmail.clear();
    _adminInviteNote.clear();
    setState(() => _message = 'Admin access saved for $email.');
    await _loadAdminData();
  }

  Future<void> _changeAdminRole(
    Map<String, dynamic> adminUser,
    AdminRole role,
  ) async {
    if (!_can(AdminPermission.manageAdmins)) return;
    final email = '${adminUser['email'] ?? ''}'.trim().toLowerCase();
    if (email == _adminUser?.email?.trim().toLowerCase()) {
      setState(() => _message = 'You cannot change your own admin role.');
      return;
    }
    final id = '${adminUser['id'] ?? AdminUserAccess.emailDocumentId(email)}';
    final oldRole = adminUser['role'] ?? adminUser['roles'];
    await FirebaseFirestore.instance.collection('adminUsers').doc(id).set({
      'role': role.value,
      'roles': [role.value],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _writeAudit(AdminAuditEntry(
      adminUserId: _adminUser?.uid ?? 'unknown-admin',
      actionType: 'admin_user_role_changed',
      recordType: 'adminUsers',
      recordId: id,
      oldValue: {'role': oldRole},
      newValue: {'role': role.value},
      reason: 'Role changed from admin users page',
    ));
    setState(() => _message = 'Updated $email to ${role.value}.');
    await _loadAdminData();
  }

  Future<void> _duplicateDelivery(Map<String, dynamic> delivery) async {
    if (!_can(AdminPermission.duplicateDeliveries)) {
      setState(() => _message = 'Your role cannot duplicate deliveries.');
      return;
    }
    final newId =
        'CIR-ADM-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final createdAt = FieldValue.serverTimestamp();
    final duplicate = AdminDeliveryTools.duplicateDelivery(
      delivery,
      newId: newId,
      createdAt: createdAt,
    );
    await FirebaseFirestore.instance
        .collection('deliveryRequests')
        .doc(newId)
        .set(duplicate);
    await _writeAudit(AdminAuditEntry(
      adminUserId: _adminUser?.uid ?? 'unknown-admin',
      actionType: 'delivery_duplicate',
      recordType: 'deliveryRequests',
      recordId: newId,
      oldValue: {'requestId': delivery['requestId'] ?? delivery['id']},
      newValue: {'requestId': newId},
      reason: 'Admin duplicated delivery from operations panel',
    ));
    setState(() => _message = 'Duplicated delivery as $newId.');
    await _loadAdminData();
  }

  Future<void> _updateRecordStatus(
    String collection,
    Map<String, dynamic> record,
    String status,
  ) async {
    final id = '${record['id'] ?? record['requestId'] ?? ''}';
    if (id.isEmpty) return;
    final oldStatus = '${record['status'] ?? record['driverStatus'] ?? ''}';
    await FirebaseFirestore.instance.collection(collection).doc(id).set({
      if (collection == 'riderProfiles')
        'driverStatus': status
      else
        'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _writeAudit(AdminAuditEntry(
      adminUserId: _adminUser?.uid ?? 'unknown-admin',
      actionType: 'status_update',
      recordType: collection,
      recordId: id,
      oldValue: {'status': oldStatus},
      newValue: {'status': status},
      reason: 'Updated from admin operations panel',
    ));
    setState(() => _message = 'Updated $id to $status.');
    await _loadAdminData();
  }

  Future<void> _updateSupportTicket(
    Map<String, dynamic> ticket,
    String status,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot update support tickets.');
      return;
    }
    final id = '${ticket['id'] ?? ''}';
    if (id.isEmpty) return;
    final oldStatus = '${ticket['status'] ?? ''}';
    final patch = AdminSupportTools.statusPatch(
      status: status,
      assignedTo: status == 'assigned' ? _adminUser?.email : null,
      resolutionNote: status == 'resolved'
          ? 'Resolved from the admin operations panel'
          : null,
      updatedAt: FieldValue.serverTimestamp(),
    );
    await FirebaseFirestore.instance
        .collection('supportTickets')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await _writeAudit(AdminAuditEntry(
      adminUserId: _adminUser?.uid ?? 'unknown-admin',
      actionType: 'support_ticket_$status',
      recordType: 'supportTickets',
      recordId: id,
      oldValue: {'status': oldStatus},
      newValue: {'status': status},
      reason: 'Updated from admin operations panel',
    ));
    setState(() => _message = 'Support ticket $id updated to $status.');
    await _loadAdminData();
  }

  Future<void> _updateHealthPlusPickup(
    Map<String, dynamic> pickup,
    String status,
  ) async {
    if (!_can(AdminPermission.manageHealthPlus)) {
      setState(() => _message = 'Your role cannot update Health+ pickups.');
      return;
    }
    final id = '${pickup['id'] ?? ''}';
    if (id.isEmpty) return;
    final oldStatus = '${pickup['status'] ?? ''}';
    final patch = AdminHealthPlusTools.statusPatch(
      status: status,
      updatedAt: FieldValue.serverTimestamp(),
    );
    await FirebaseFirestore.instance
        .collection('prescriptionPickups')
        .doc(id)
        .set(patch, SetOptions(merge: true));
    await FirebaseFirestore.instance.collection('healthPlusUsageEvents').add({
      'type': 'admin_status_updated',
      'pickupId': id,
      'status': status,
      'source': 'circum-admin',
      'adminUserId': _adminUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _writeAudit(AdminAuditEntry(
      adminUserId: _adminUser?.uid ?? 'unknown-admin',
      actionType: 'health_plus_status_update',
      recordType: 'prescriptionPickups',
      recordId: id,
      oldValue: {'status': oldStatus},
      newValue: {'status': status},
      reason: 'Updated from admin operations panel',
    ));
    setState(() => _message = 'Health+ pickup $id updated to $status.');
    await _loadAdminData();
  }

  Future<void> _addAdminNote(
    String recordType,
    String recordId,
    String note,
  ) async {
    if (note.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('adminNotes').add({
      'recordType': recordType,
      'recordId': recordId,
      'note': note.trim(),
      'adminUserId': _adminUser?.uid,
      'adminEmail': _adminUser?.email,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _writeAudit(AdminAuditEntry(
      adminUserId: _adminUser?.uid ?? 'unknown-admin',
      actionType: 'admin_note_added',
      recordType: recordType,
      recordId: recordId,
      newValue: {'note': note.trim()},
      reason: 'Internal note',
    ));
    setState(() => _message = 'Internal note saved.');
  }

  bool _can(AdminPermission permission) {
    return AdminAccessPolicy.can(_roles, permission);
  }

  String _friendlyAdminAuthMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'user-not-found' => 'No employee account found for that email.',
      'wrong-password' ||
      'invalid-credential' =>
        'Those sign-in details are not right.',
      _ => 'Admin sign in failed. Please check the details.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    if (_loading) {
      return Scaffold(
        backgroundColor: colors.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_adminUser == null || !AdminAccessPolicy.hasAnyAdminRole(_roles)) {
      return _AdminLoginView(
        colors: colors,
        darkMode: widget.darkMode,
        email: _email,
        password: _password,
        signingIn: _signingIn,
        message: _message,
        onBack: widget.onBack,
        onToggleTheme: widget.onToggleTheme,
        onSubmit: _signIn,
      );
    }

    final mobile = MediaQuery.sizeOf(context).width < 860;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Row(
          children: [
            if (!mobile)
              _AdminSidebar(
                colors: colors,
                section: _section,
                roles: _roles,
                onSection: (section) => setState(() => _section = section),
                onBack: widget.onBack,
                onSignOut: _signOut,
              ),
            Expanded(
              child: Column(
                children: [
                  _AdminTopBar(
                    colors: colors,
                    darkMode: widget.darkMode,
                    section: _section,
                    roles: _roles,
                    search: _search,
                    mobile: mobile,
                    onBack: widget.onBack,
                    onRefresh: _loadAdminData,
                    onToggleTheme: widget.onToggleTheme,
                    onSearchChanged: () => setState(() {}),
                    onSection: (section) => setState(() => _section = section),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                      child: _AdminNotice(colors: colors, message: _message!),
                    ),
                  Expanded(child: _buildSection(colors)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(_CircumColors colors) {
    final query = _search.text;
    return switch (_section) {
      _AdminSection.overview => _AdminOverviewSection(
          colors: colors,
          metrics: _metrics,
          issues: _issueRows(),
        ),
      _AdminSection.adminUsers => _AdminUsersSection(
          colors: colors,
          records: adminSearch(_adminUsers, query, ['email', 'role', 'status']),
          inviteEmail: _adminInviteEmail,
          inviteNote: _adminInviteNote,
          selectedRole: _adminInviteRole,
          canManage: _can(AdminPermission.manageAdmins),
          currentEmail: _adminUser?.email,
          onRoleChanged: (role) => setState(() => _adminInviteRole = role),
          onAdd: () => _saveAdminUser(),
          onChangeRole: _changeAdminRole,
          onStatus: (record, status) =>
              _confirmAdminAccessChange(record, status),
        ),
      _AdminSection.senders => _AdminDataSection(
          colors: colors,
          title: 'Senders',
          subtitle: 'Customer accounts, delivery history, notes, and value.',
          records: adminSearch(
              _senders, query, ['fullName', 'name', 'email', 'phone']),
          columns: const ['Name', 'Email', 'Phone', 'Status', 'Value'],
          rowBuilder: _senderRow,
          emptyText: 'No sender records yet.',
        ),
      _AdminSection.drivers => _AdminDataSection(
          colors: colors,
          title: 'Drivers',
          subtitle: 'Vehicle, ratings, verification, earnings, and quality.',
          records: adminSearch(_drivers, query, [
            'fullName',
            'name',
            'email',
            'phoneNumber',
            'plateNumber',
            'vehicleType'
          ]),
          columns: const ['Driver', 'Vehicle', 'Status', 'Rating', 'Actions'],
          rowBuilder: _driverRow,
          emptyText: 'No driver profiles yet.',
        ),
      _AdminSection.deliveries => _AdminDataSection(
          colors: colors,
          title: 'Deliveries',
          subtitle:
              'Track, edit safe fields, duplicate, cancel, and resolve orders.',
          records: adminSearch(_deliveries, query, [
            'requestId',
            'pickupAddress',
            'dropoffAddress',
            'senderName',
            'riderName',
            'status'
          ]),
          columns: const ['ID', 'Route', 'Status', 'Price', 'Actions'],
          rowBuilder: _deliveryRow,
          emptyText: 'No delivery records yet.',
        ),
      _AdminSection.finance => _AdminDataSection(
          colors: colors,
          title: 'Finance',
          subtitle:
              'Payments, refunds, driver payouts, commission checks, and revenue follow-up.',
          records: adminSearch(_financeRows(), query,
              ['id', 'senderId', 'riderId', 'status', 'type']),
          columns: const ['Type', 'Record', 'Status', 'Amount', 'Notes'],
          rowBuilder: _financeRow,
          emptyText: 'No finance records yet.',
        ),
      _AdminSection.healthPlus => _AdminDataSection(
          colors: colors,
          title: 'Health+',
          subtitle:
              'Prescription pickups, recurring schedules, payment status, and customer notes.',
          records: adminSearch(_healthPlusRows(), query, [
            'id',
            'fullName',
            'pharmacyAddress',
            'deliveryAddress',
            'status',
            'frequency'
          ]),
          columns: const [
            'Pickup',
            'Customer',
            'Schedule',
            'Status',
            'Actions'
          ],
          rowBuilder: _healthPlusRow,
          emptyText: 'No Health+ records yet.',
        ),
      _AdminSection.support => _AdminDataSection(
          colors: colors,
          title: 'Support',
          subtitle:
              'Live chat tickets, refund requests, customer messages, admin assignment, and resolution notes.',
          records: adminSearch(_supportTickets, query,
              ['id', 'name', 'email', 'message', 'status', 'type']),
          columns: const ['Ticket', 'Customer', 'Status', 'Message', 'Actions'],
          rowBuilder: _supportRow,
          emptyText: 'No support tickets yet.',
        ),
      _AdminSection.issues => _AdminDataSection(
          colors: colors,
          title: 'Troubleshooting',
          subtitle:
              'Stuck jobs, failed payments, unassigned requests, complaints, refunds, and low ratings.',
          records: _issueRows(),
          columns: const ['Issue', 'Record', 'Priority', 'Status', 'Action'],
          rowBuilder: _issueRow,
          emptyText: 'No operational issues found.',
        ),
      _AdminSection.analytics => _AdminAnalyticsSection(
          colors: colors,
          metrics: _metrics,
          deliveries: _deliveries,
          payments: _payments,
        ),
      _AdminSection.audit => _AdminDataSection(
          colors: colors,
          title: 'Audit trail',
          subtitle: 'Every important admin action should leave a trace.',
          records: _auditLogs,
          columns: const ['Action', 'Record', 'Admin', 'Reason'],
          rowBuilder: _auditRow,
          emptyText: 'No audit entries yet.',
        ),
    };
  }

  List<Widget> _senderRow(Map<String, dynamic> item) {
    final id = '${item['id'] ?? item['userId'] ?? ''}';
    final value = _deliveries
        .where((delivery) =>
            '${delivery['senderId'] ?? delivery['userId'] ?? ''}' == id)
        .fold<double>(0, (total, delivery) => total + _adminMoney(delivery));
    return [
      _AdminCell.primary('${item['fullName'] ?? item['name'] ?? 'Sender'}'),
      _AdminCell('${item['email'] ?? ''}'),
      _AdminCell('${item['phone'] ?? item['phoneNumber'] ?? ''}'),
      _AdminStatusCell(
          colors: widget.colors, status: '${item['status'] ?? 'active'}'),
      _AdminCell('£${value.toStringAsFixed(2)}'),
    ];
  }

  List<Widget> _driverRow(Map<String, dynamic> item) {
    final id = '${item['id'] ?? item['riderId'] ?? ''}';
    return [
      _AdminCell.primary('${item['fullName'] ?? item['name'] ?? 'Driver'}'),
      _AdminCell(
        '${item['vehicleColour'] ?? ''} ${item['vehicleMakeModel'] ?? item['vehicleType'] ?? ''}\n${item['plateNumber'] ?? ''}',
      ),
      _AdminStatusCell(
        colors: widget.colors,
        status:
            '${item['driverStatus'] ?? item['verificationStatus'] ?? item['status'] ?? 'pending'}',
      ),
      _AdminCell('${item['averageRating'] ?? item['rating'] ?? 'New'}'),
      _AdminActions(
        colors: widget.colors,
        actions: [
          _AdminAction(
            label: 'Approve',
            enabled: _can(AdminPermission.approveDrivers),
            onTap: () => _updateRecordStatus('riderProfiles', item, 'active'),
          ),
          _AdminAction(
            label: 'Suspend',
            enabled: _can(AdminPermission.approveDrivers),
            onTap: () =>
                _updateRecordStatus('riderProfiles', item, 'suspended'),
          ),
          _AdminAction(
            label: 'Note',
            enabled: _can(AdminPermission.editDrivers),
            onTap: () => _addAdminNote(
                'riderProfiles', id, 'Driver reviewed from admin panel'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _deliveryRow(Map<String, dynamic> item) {
    final id = '${item['id'] ?? item['requestId'] ?? ''}';
    return [
      _AdminCell.primary('${item['requestId'] ?? id}'),
      _AdminCell(
          '${item['pickupAddress'] ?? item['pickupLocality'] ?? ''}\n→ ${item['dropoffAddress'] ?? ''}'),
      _AdminStatusCell(
          colors: widget.colors, status: '${item['status'] ?? 'requested'}'),
      _AdminCell('£${_adminMoney(item).toStringAsFixed(2)}'),
      _AdminActions(
        colors: widget.colors,
        actions: [
          _AdminAction(
            label: 'Duplicate',
            enabled: _can(AdminPermission.duplicateDeliveries),
            onTap: () => _duplicateDelivery(item),
          ),
          _AdminAction(
            label: 'Failed',
            enabled: _can(AdminPermission.editDeliveries),
            onTap: () =>
                _updateRecordStatus('deliveryRequests', item, 'failed'),
          ),
          _AdminAction(
            label: 'Resolved',
            enabled: _can(AdminPermission.editDeliveries),
            onTap: () =>
                _updateRecordStatus('deliveryRequests', item, 'resolved'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _financeRow(Map<String, dynamic> item) {
    return [
      _AdminCell.primary('${item['type'] ?? 'payment'}'),
      _AdminCell(
          '${item['id'] ?? item['paymentId'] ?? item['payoutId'] ?? ''}'),
      _AdminStatusCell(
          colors: widget.colors, status: '${item['status'] ?? 'pending'}'),
      _AdminCell('£${_adminMoney(item).toStringAsFixed(2)}'),
      _AdminCell(
        '${item['senderId'] ?? item['riderId'] ?? item['userId'] ?? ''}',
      ),
    ];
  }

  List<Widget> _healthPlusRow(Map<String, dynamic> item) {
    final id = '${item['id'] ?? ''}';
    final isPickup = item['recordType'] == 'prescriptionPickups';
    return [
      _AdminCell.primary(id),
      _AdminCell(
        '${item['fullName'] ?? item['senderName'] ?? 'Health+ customer'}\n${item['phoneNumber'] ?? ''}',
      ),
      _AdminCell(
          '${item['frequency'] ?? 'one-off'}\n${item['preferredPickupTime'] ?? item['nextPickupAt'] ?? ''}'),
      _AdminStatusCell(
          colors: widget.colors, status: '${item['status'] ?? 'scheduled'}'),
      _AdminActions(
        colors: widget.colors,
        actions: [
          _AdminAction(
            label: 'Collected',
            enabled: isPickup && _can(AdminPermission.manageHealthPlus),
            onTap: () => _updateHealthPlusPickup(item, 'collected'),
          ),
          _AdminAction(
            label: 'Delivered',
            enabled: isPickup && _can(AdminPermission.manageHealthPlus),
            onTap: () => _updateHealthPlusPickup(item, 'delivered'),
          ),
          _AdminAction(
            label: 'Failed',
            enabled: isPickup && _can(AdminPermission.manageHealthPlus),
            onTap: () => _updateHealthPlusPickup(item, 'failed'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _supportRow(Map<String, dynamic> item) {
    return [
      _AdminCell.primary('${item['id'] ?? 'ticket'}'),
      _AdminCell('${item['name'] ?? 'Customer'}\n${item['email'] ?? ''}'),
      _AdminStatusCell(
          colors: widget.colors, status: '${item['status'] ?? 'open'}'),
      _AdminCell('${item['message'] ?? item['type'] ?? ''}'),
      _AdminActions(
        colors: widget.colors,
        actions: [
          _AdminAction(
            label: 'Assign',
            enabled: _can(AdminPermission.manageIssues),
            onTap: () => _updateSupportTicket(item, 'assigned'),
          ),
          _AdminAction(
            label: 'Resolve',
            enabled: _can(AdminPermission.manageIssues),
            onTap: () => _updateSupportTicket(item, 'resolved'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _issueRow(Map<String, dynamic> item) {
    return [
      _AdminCell.primary('${item['title']}'),
      _AdminCell('${item['recordId']}'),
      _AdminCell('${item['priority']}'),
      _AdminStatusCell(colors: widget.colors, status: '${item['status']}'),
      _AdminActions(
        colors: widget.colors,
        actions: [
          _AdminAction(
            label: 'Assign',
            enabled: _can(AdminPermission.manageIssues),
            onTap: () => _resolveIssueAction(item, 'assigned'),
          ),
          _AdminAction(
            label: 'Resolve',
            enabled: _can(AdminPermission.manageIssues),
            onTap: () => _resolveIssueAction(item, 'resolved'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _auditRow(Map<String, dynamic> item) {
    return [
      _AdminCell.primary('${item['actionType'] ?? 'action'}'),
      _AdminCell('${item['recordType'] ?? ''}\n${item['recordId'] ?? ''}'),
      _AdminCell('${item['adminEmail'] ?? item['adminUserId'] ?? ''}'),
      _AdminCell('${item['reason'] ?? ''}'),
    ];
  }

  Future<void> _confirmAdminAccessChange(
    Map<String, dynamic> adminUser,
    String status,
  ) async {
    final email = '${adminUser['email'] ?? ''}'.trim().toLowerCase();
    if (email == _adminUser?.email?.trim().toLowerCase()) {
      setState(() => _message = 'You cannot change your own admin access.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(status == 'active'
            ? 'Activate admin access?'
            : 'Deactivate admin access?'),
        content: Text(
          status == 'active'
              ? 'This will let $email access the admin panel with their Firebase Auth login.'
              : 'This will block $email from the admin panel.',
        ),
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
    if (confirmed == true) {
      await _saveAdminUser(existing: adminUser, status: status);
    }
  }

  List<Map<String, dynamic>> _issueRows() {
    final issues = <Map<String, dynamic>>[];
    for (final delivery in _deliveries) {
      final status = '${delivery['status'] ?? ''}'.toLowerCase();
      final id = '${delivery['requestId'] ?? delivery['id'] ?? ''}';
      if (status == 'requested' || status == 'pending') {
        issues.add({
          'title': 'Driver unassigned',
          'recordType': 'deliveryRequests',
          'recordId': id,
          'priority': 'High',
          'status': status,
        });
      }
      if (status.contains('failed') || status.contains('cancel')) {
        issues.add({
          'title':
              status.contains('failed') ? 'Failed delivery' : 'Cancelled job',
          'recordType': 'deliveryRequests',
          'recordId': id,
          'priority': 'Medium',
          'status': status,
        });
      }
    }
    for (final rating in _ratings) {
      final stars = rating['starRating'] as num?;
      if (stars != null && stars <= 2) {
        issues.add({
          'title': 'Low-rated driver',
          'recordType': 'driverRatings',
          'recordId': rating['id'] ?? rating['deliveryId'] ?? '',
          'priority': 'High',
          'status': 'open',
        });
      }
    }
    for (final ticket in _supportTickets
        .where((ticket) => '${ticket['type']}'.contains('refund'))) {
      issues.add({
        'title': 'Refund request',
        'recordType': 'supportTickets',
        'recordId': ticket['id'] ?? '',
        'priority': 'Medium',
        'status': ticket['status'] ?? 'open',
      });
    }
    return issues;
  }

  List<Map<String, dynamic>> _financeRows() {
    return [
      ..._payments.map((item) => {'type': 'payment', ...item}),
      ..._healthPlusPayments
          .map((item) => {'type': 'health_plus_payment', ...item}),
      ..._payoutRequests.map((item) => {'type': 'driver_payout', ...item}),
      ..._supportTickets
          .where((ticket) => '${ticket['type']}'.contains('refund'))
          .map((item) => {'type': 'refund_request', ...item}),
    ];
  }

  List<Map<String, dynamic>> _healthPlusRows() {
    return [
      ..._healthPlusPickups
          .map((item) => {'recordType': 'prescriptionPickups', ...item}),
      ..._recurringPickupSchedules
          .map((item) => {'recordType': 'recurringPickupSchedules', ...item}),
    ];
  }

  Future<void> _resolveIssueAction(
    Map<String, dynamic> issue,
    String status,
  ) async {
    if (issue['recordType'] == 'supportTickets') {
      final ticket = _supportTickets.firstWhere(
        (item) => '${item['id']}' == '${issue['recordId']}',
        orElse: () => {'id': issue['recordId']},
      );
      await _updateSupportTicket(ticket, status);
      return;
    }
    await _addAdminNote(
      '${issue['recordType']}',
      '${issue['recordId']}',
      'Issue marked $status from operations panel',
    );
  }

  double _adminMoney(Map<String, dynamic> item) {
    final value =
        item['amount'] ?? item['price'] ?? item['quote'] ?? item['total'];
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}

class _AdminLoginView extends StatelessWidget {
  final _CircumColors colors;
  final bool darkMode;
  final TextEditingController email;
  final TextEditingController password;
  final bool signingIn;
  final String? message;
  final VoidCallback onBack;
  final VoidCallback onToggleTheme;
  final VoidCallback onSubmit;

  const _AdminLoginView({
    required this.colors,
    required this.darkMode,
    required this.email,
    required this.password,
    required this.signingIn,
    required this.message,
    required this.onBack,
    required this.onToggleTheme,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: _GlassPanel(
                colors: colors,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (!_adminHostingTarget)
                          IconButton(
                            onPressed: onBack,
                            icon: Icon(Icons.arrow_back, color: colors.text),
                          ),
                        const Spacer(),
                        IconButton(
                          tooltip: darkMode ? 'Light mode' : 'Dark mode',
                          onPressed: onToggleTheme,
                          icon: Icon(
                            darkMode ? Icons.light_mode : Icons.dark_mode,
                            color: colors.text,
                          ),
                        ),
                      ],
                    ),
                    Image.asset(
                      'assets/images/circum_wordmark.png',
                      width: 132,
                      height: 32,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Admin operations',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Employee access only. Sign in with an account that has a Circum admin role.',
                      style: TextStyle(
                        color: colors.mutedText,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _InputBox(
                        colors: colors, controller: email, hint: 'Work email'),
                    const SizedBox(height: 10),
                    _InputBox(
                      colors: colors,
                      controller: password,
                      hint: 'Password',
                      obscureText: true,
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        message!,
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: signingIn ? null : onSubmit,
                        icon: signingIn
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.admin_panel_settings),
                        label: Text(
                            signingIn ? 'Checking...' : 'Open admin panel'),
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.text,
                          foregroundColor: colors.inverseText,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
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

class _AdminUsersSection extends StatelessWidget {
  final _CircumColors colors;
  final List<Map<String, dynamic>> records;
  final TextEditingController inviteEmail;
  final TextEditingController inviteNote;
  final AdminRole selectedRole;
  final bool canManage;
  final String? currentEmail;
  final ValueChanged<AdminRole> onRoleChanged;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>, AdminRole) onChangeRole;
  final void Function(Map<String, dynamic>, String) onStatus;

  const _AdminUsersSection({
    required this.colors,
    required this.records,
    required this.inviteEmail,
    required this.inviteNote,
    required this.selectedRole,
    required this.canManage,
    required this.currentEmail,
    required this.onRoleChanged,
    required this.onAdd,
    required this.onChangeRole,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Admin users',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Give trusted employees admin access. They must sign in with their own Firebase Auth account.',
                style: TextStyle(
                  color: colors.mutedText,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              if (canManage)
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: inviteEmail,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(
                            color: colors.text, fontWeight: FontWeight.w800),
                        decoration: InputDecoration(
                          labelText: 'Employee email',
                          labelStyle: TextStyle(color: colors.mutedText),
                          filled: true,
                          fillColor: colors.field,
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.field,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<AdminRole>(
                            value: selectedRole,
                            dropdownColor: colors.field,
                            style: TextStyle(
                              color: colors.text,
                              fontWeight: FontWeight.w800,
                            ),
                            items: AdminRole.values
                                .map(
                                  (role) => DropdownMenuItem(
                                    value: role,
                                    child: Text(role.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (role) {
                              if (role != null) onRoleChanged(role);
                            },
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: inviteNote,
                        style: TextStyle(
                            color: colors.text, fontWeight: FontWeight.w800),
                        decoration: InputDecoration(
                          labelText: 'Reason or note',
                          labelStyle: TextStyle(color: colors.mutedText),
                          filled: true,
                          fillColor: colors.field,
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add admin'),
                    ),
                  ],
                )
              else
                Text(
                  'Only super admins can add or change admin users.',
                  style: TextStyle(
                    color: colors.mutedText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const SizedBox(height: 18),
              if (records.isEmpty)
                Text(
                  'No admin users found.',
                  style: TextStyle(
                    color: colors.mutedText,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingTextStyle: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w900,
                    ),
                    dataTextStyle: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w700,
                    ),
                    columns: const [
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Role')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Last login')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: records.map(_row).toList(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _row(Map<String, dynamic> item) {
    final email = '${item['email'] ?? item['id'] ?? ''}'.trim().toLowerCase();
    final self = email == currentEmail?.trim().toLowerCase();
    final role = AdminRole.fromString(
          '${item['role'] ?? (item['roles'] is List && (item['roles'] as List).isNotEmpty ? (item['roles'] as List).first : '')}',
        ) ??
        AdminRole.operationsAdmin;
    final status = '${item['status'] ?? 'inactive'}';
    return DataRow(
      cells: [
        DataCell(_AdminCell.primary(email)),
        DataCell(
          canManage && !self
              ? DropdownButtonHideUnderline(
                  child: DropdownButton<AdminRole>(
                    value: role,
                    dropdownColor: colors.field,
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w800,
                    ),
                    items: AdminRole.values
                        .map(
                          (nextRole) => DropdownMenuItem(
                            value: nextRole,
                            child: Text(nextRole.value),
                          ),
                        )
                        .toList(),
                    onChanged: (nextRole) {
                      if (nextRole != null) onChangeRole(item, nextRole);
                    },
                  ),
                )
              : _AdminCell(role.value),
        ),
        DataCell(_AdminStatusCell(colors: colors, status: status)),
        DataCell(_AdminCell(_adminDateText(item['lastLoginAt']))),
        DataCell(
          _AdminActions(
            colors: colors,
            actions: [
              _AdminAction(
                label: status == 'active' ? 'Deactivate' : 'Activate',
                enabled: canManage && !self,
                onTap: () =>
                    onStatus(item, status == 'active' ? 'inactive' : 'active'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  final _CircumColors colors;
  final _AdminSection section;
  final List<String> roles;
  final ValueChanged<_AdminSection> onSection;
  final VoidCallback onBack;
  final VoidCallback onSignOut;

  const _AdminSidebar({
    required this.colors,
    required this.section,
    required this.roles,
    required this.onSection,
    required this.onBack,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/images/circum_wordmark.png',
            width: 132,
            height: 32,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 20),
          Text(
            'Operations',
            style: TextStyle(
              color: colors.text,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            roles.join(', '),
            style: TextStyle(
              color: colors.mutedText,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          ..._AdminSection.values.map(
            (item) => _AdminNavButton(
              colors: colors,
              label: _adminSectionLabel(item),
              icon: _adminSectionIcon(item),
              selected: item == section,
              onTap: () => onSection(item),
            ),
          ),
          const Spacer(),
          if (!_adminHostingTarget)
            _AdminNavButton(
              colors: colors,
              label: 'Back to site',
              icon: Icons.arrow_back,
              selected: false,
              onTap: onBack,
            ),
          _AdminNavButton(
            colors: colors,
            label: 'Sign out',
            icon: Icons.logout,
            selected: false,
            onTap: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  final _CircumColors colors;
  final bool darkMode;
  final _AdminSection section;
  final List<String> roles;
  final TextEditingController search;
  final bool mobile;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onToggleTheme;
  final VoidCallback onSearchChanged;
  final ValueChanged<_AdminSection> onSection;

  const _AdminTopBar({
    required this.colors,
    required this.darkMode,
    required this.section,
    required this.roles,
    required this.search,
    required this.mobile,
    required this.onBack,
    required this.onRefresh,
    required this.onToggleTheme,
    required this.onSearchChanged,
    required this.onSection,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (mobile)
                PopupMenuButton<_AdminSection>(
                  onSelected: onSection,
                  itemBuilder: (context) => _AdminSection.values
                      .map((item) => PopupMenuItem(
                            value: item,
                            child: Text(_adminSectionLabel(item)),
                          ))
                      .toList(),
                  icon: Icon(Icons.menu, color: colors.text),
                ),
              Expanded(
                child: Text(
                  _adminSectionLabel(section),
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: onRefresh,
                icon: Icon(Icons.refresh, color: colors.text),
              ),
              IconButton(
                tooltip: darkMode ? 'Light mode' : 'Dark mode',
                onPressed: onToggleTheme,
                icon: Icon(
                  darkMode ? Icons.light_mode : Icons.dark_mode,
                  color: colors.text,
                ),
              ),
              if (mobile && !_adminHostingTarget)
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: Icon(Icons.close, color: colors.text),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: search,
            onChanged: (_) => onSearchChanged(),
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'Search current section',
              prefixIcon: Icon(Icons.search, color: colors.mutedText),
              hintStyle: TextStyle(color: colors.mutedText),
              filled: true,
              fillColor: colors.field,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOverviewSection extends StatelessWidget {
  final _CircumColors colors;
  final AdminMetricSnapshot metrics;
  final List<Map<String, dynamic>> issues;

  const _AdminOverviewSection({
    required this.colors,
    required this.metrics,
    required this.issues,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _AdminMetricCard(
                colors: colors,
                label: 'Total deliveries',
                value: '${metrics.totalDeliveries}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Active deliveries',
                value: '${metrics.activeDeliveries}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Completed',
                value: '${metrics.completedDeliveries}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Failed',
                value: '${metrics.failedDeliveries}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Cancelled',
                value: '${metrics.cancelledDeliveries}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Total senders',
                value: '${metrics.totalSenders}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Active senders',
                value: '${metrics.activeSenders}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Total drivers',
                value: '${metrics.totalDrivers}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Active drivers',
                value: '${metrics.activeDrivers}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Pending drivers',
                value: '${metrics.pendingDrivers}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Revenue today',
                value: _adminMoneyText(metrics.revenueToday)),
            _AdminMetricCard(
                colors: colors,
                label: 'Revenue this week',
                value: _adminMoneyText(metrics.revenueThisWeek)),
            _AdminMetricCard(
                colors: colors,
                label: 'Revenue this month',
                value: _adminMoneyText(metrics.revenueThisMonth)),
            _AdminMetricCard(
                colors: colors,
                label: 'Average order',
                value: _adminMoneyText(metrics.averageDeliveryValue)),
            _AdminMetricCard(
                colors: colors,
                label: 'Driver rating',
                value: metrics.averageDriverRating.toStringAsFixed(2)),
            _AdminMetricCard(
                colors: colors,
                label: 'Satisfaction',
                value:
                    '${metrics.customerSatisfactionScore.toStringAsFixed(0)}%'),
            _AdminMetricCard(
                colors: colors,
                label: 'Complaints',
                value: '${metrics.complaintsCount}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Refund requests',
                value: '${metrics.refundRequests}'),
            _AdminMetricCard(
                colors: colors,
                label: 'Open support',
                value: '${metrics.unresolvedSupportIssues}'),
          ],
        ),
        const SizedBox(height: 18),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Operational pulse'),
              const SizedBox(height: 12),
              _AdminBar(
                  colors: colors,
                  label: 'Cancellation rate',
                  value: metrics.cancellationRate),
              _AdminBar(
                  colors: colors,
                  label: 'Failed delivery rate',
                  value: metrics.failedDeliveryRate),
              _AdminBar(
                  colors: colors,
                  label: 'Repeat customer rate',
                  value: metrics.repeatCustomerRate),
              _AdminBar(
                  colors: colors,
                  label: 'Refund rate',
                  value: metrics.refundRate),
              const SizedBox(height: 12),
              Text(
                issues.isEmpty
                    ? 'No urgent marketplace issues detected.'
                    : '${issues.length} operational issue(s) need review.',
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminDataSection extends StatelessWidget {
  final _CircumColors colors;
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> records;
  final List<String> columns;
  final List<Widget> Function(Map<String, dynamic>) rowBuilder;
  final String emptyText;

  const _AdminDataSection({
    required this.colors,
    required this.title,
    required this.subtitle,
    required this.records,
    required this.columns,
    required this.rowBuilder,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: colors.mutedText,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              if (records.isEmpty)
                Text(
                  emptyText,
                  style: TextStyle(
                      color: colors.mutedText, fontWeight: FontWeight.w700),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingTextStyle: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w900,
                    ),
                    dataTextStyle: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w700,
                    ),
                    columns: columns
                        .map((column) => DataColumn(label: Text(column)))
                        .toList(),
                    rows: records
                        .map(
                          (record) => DataRow(
                            cells: rowBuilder(record)
                                .map((child) => DataCell(child))
                                .toList(),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminAnalyticsSection extends StatelessWidget {
  final _CircumColors colors;
  final AdminMetricSnapshot metrics;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> payments;

  const _AdminAnalyticsSection({
    required this.colors,
    required this.metrics,
    required this.deliveries,
    required this.payments,
  });

  @override
  Widget build(BuildContext context) {
    final avgWeight = _average(deliveries, 'weightKg');
    final avgDistance = _average(deliveries, 'distanceMiles');
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Business intelligence'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _AdminMetricCard(
                      colors: colors,
                      label: 'Avg distance',
                      value: '${avgDistance.toStringAsFixed(1)} mi'),
                  _AdminMetricCard(
                      colors: colors,
                      label: 'Avg weight',
                      value: '${avgWeight.toStringAsFixed(1)} kg'),
                  _AdminMetricCard(
                      colors: colors,
                      label: 'Avg price',
                      value: _adminMoneyText(metrics.averageDeliveryValue)),
                  _AdminMetricCard(
                      colors: colors,
                      label: 'Health+ recurring',
                      value:
                          _adminMoneyText(metrics.healthPlusRecurringRevenue)),
                  _AdminMetricCard(
                      colors: colors,
                      label: 'Completion rate',
                      value:
                          '${(100 - metrics.failedDeliveryRate - metrics.cancellationRate).clamp(0, 100).toStringAsFixed(0)}%'),
                  _AdminMetricCard(
                      colors: colors,
                      label: 'Repeat customers',
                      value:
                          '${metrics.repeatCustomerRate.toStringAsFixed(0)}%'),
                ],
              ),
              const SizedBox(height: 18),
              _AdminBar(
                  colors: colors,
                  label: 'Revenue momentum',
                  value: payments.isEmpty ? 0 : 74),
              _AdminBar(
                  colors: colors,
                  label: 'Driver completion',
                  value: (100 - metrics.failedDeliveryRate)
                      .clamp(0, 100)
                      .toDouble()),
              _AdminBar(
                  colors: colors,
                  label: 'Customer repeat',
                  value: metrics.repeatCustomerRate),
            ],
          ),
        ),
      ],
    );
  }

  double _average(List<Map<String, dynamic>> records, String field) {
    final values = records
        .map((record) => record[field])
        .map((value) =>
            value is num ? value.toDouble() : double.tryParse('$value') ?? 0)
        .where((value) => value > 0)
        .toList();
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

class _AdminMetricCard extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;

  const _AdminMetricCard({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: _GlassPanel(
        colors: colors,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: colors.mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: colors.text,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminBar extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final double value;

  const _AdminBar({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = value.clamp(0, 100) / 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${value.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: colors.mutedText,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: normalized,
              backgroundColor: colors.field,
              color: const Color(0xff2563eb),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminCell extends StatelessWidget {
  final String value;
  final bool primary;

  const _AdminCell(this.value) : primary = false;
  const _AdminCell.primary(this.value) : primary = true;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Text(
        value,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        style: TextStyle(
          fontWeight: primary ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}

class _AdminStatusCell extends StatelessWidget {
  final _CircumColors colors;
  final String status;

  const _AdminStatusCell({required this.colors, required this.status});

  @override
  Widget build(BuildContext context) {
    final lower = status.toLowerCase();
    final good = lower.contains('active') ||
        lower.contains('complete') ||
        lower.contains('resolved') ||
        lower.contains('verified');
    final bad = lower.contains('failed') ||
        lower.contains('cancel') ||
        lower.contains('suspend');
    final color = good
        ? colors.success
        : bad
            ? const Color(0xffdc2626)
            : const Color(0xffca8a04);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _AdminAction {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _AdminAction({
    required this.label,
    required this.enabled,
    required this.onTap,
  });
}

class _AdminActions extends StatelessWidget {
  final _CircumColors colors;
  final List<_AdminAction> actions;

  const _AdminActions({required this.colors, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: actions
          .map(
            (action) => OutlinedButton(
              onPressed: action.enabled ? action.onTap : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.text,
                side: BorderSide(color: colors.border),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(action.label),
            ),
          )
          .toList(),
    );
  }
}

class _AdminNavButton extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AdminNavButton({
    required this.colors,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        selected: selected,
        onTap: onTap,
        leading: Icon(icon, color: selected ? colors.inverseText : colors.text),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? colors.inverseText : colors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        selectedTileColor: colors.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _AdminNotice extends StatelessWidget {
  final _CircumColors colors;
  final String message;

  const _AdminNotice({required this.colors, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
      ),
    );
  }
}

String _adminSectionLabel(_AdminSection section) {
  return switch (section) {
    _AdminSection.overview => 'Overview',
    _AdminSection.adminUsers => 'Admin users',
    _AdminSection.senders => 'Senders',
    _AdminSection.drivers => 'Drivers',
    _AdminSection.deliveries => 'Deliveries',
    _AdminSection.finance => 'Finance',
    _AdminSection.healthPlus => 'Health+',
    _AdminSection.support => 'Support',
    _AdminSection.issues => 'Troubleshooting',
    _AdminSection.analytics => 'Analytics',
    _AdminSection.audit => 'Audit',
  };
}

IconData _adminSectionIcon(_AdminSection section) {
  return switch (section) {
    _AdminSection.overview => Icons.dashboard,
    _AdminSection.adminUsers => Icons.admin_panel_settings,
    _AdminSection.senders => Icons.people,
    _AdminSection.drivers => Icons.two_wheeler,
    _AdminSection.deliveries => Icons.local_shipping,
    _AdminSection.finance => Icons.payments,
    _AdminSection.healthPlus => Icons.health_and_safety,
    _AdminSection.support => Icons.support_agent,
    _AdminSection.issues => Icons.report_problem,
    _AdminSection.analytics => Icons.query_stats,
    _AdminSection.audit => Icons.history,
  };
}

String _adminMoneyText(double value) => '£${value.toStringAsFixed(2)}';

String _adminDateText(dynamic value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (value is String) date = DateTime.tryParse(value);
  if (date == null) return 'Not yet';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _LandingNav extends StatelessWidget {
  final _CircumColors colors;
  final bool darkMode;
  final VoidCallback onStart;
  final VoidCallback onRider;
  final VoidCallback onToggleTheme;

  const _LandingNav({
    required this.colors,
    required this.darkMode,
    required this.onStart,
    required this.onRider,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Row(
            children: [
              Image.asset(
                'assets/images/circum_wordmark.png',
                width: 136,
                height: 32,
                fit: BoxFit.contain,
              ),
              const Spacer(),
              IconButton(
                tooltip: darkMode ? 'Light mode' : 'Dark mode',
                onPressed: onToggleTheme,
                icon: Icon(
                  darkMode ? Icons.light_mode : Icons.dark_mode,
                  color: colors.text,
                ),
              ),
              const SizedBox(width: 8),
              if (MediaQuery.sizeOf(context).width >= 560)
                TextButton(
                  onPressed: onRider,
                  child: Text(
                    'Rider',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.text,
                  foregroundColor: colors.inverseText,
                  shape: const StadiumBorder(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                child: const Text('Send a Parcel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpectrumSweepPainter extends CustomPainter {
  final bool dark;

  const _SpectrumSweepPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final sweepRect = Rect.fromLTWH(
      size.width * 0.02,
      size.height * 0.08,
      size.width * 0.96,
      size.height * 0.84,
    );
    final spectrum = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: _spectrumGradient,
      ).createShader(sweepRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = dark ? 22 : 18
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, dark ? 28 : 22);

    final path = Path()
      ..moveTo(sweepRect.left, sweepRect.center.dy + sweepRect.height * 0.16)
      ..cubicTo(
        sweepRect.left + sweepRect.width * 0.22,
        sweepRect.top - sweepRect.height * 0.12,
        sweepRect.left + sweepRect.width * 0.44,
        sweepRect.bottom + sweepRect.height * 0.14,
        sweepRect.left + sweepRect.width * 0.62,
        sweepRect.center.dy,
      )
      ..cubicTo(
        sweepRect.left + sweepRect.width * 0.78,
        sweepRect.top - sweepRect.height * 0.1,
        sweepRect.right - sweepRect.width * 0.12,
        sweepRect.bottom + sweepRect.height * 0.08,
        sweepRect.right,
        sweepRect.center.dy - sweepRect.height * 0.16,
      );

    canvas.drawPath(path, spectrum);
  }

  @override
  bool shouldRepaint(covariant _SpectrumSweepPainter oldDelegate) {
    return oldDelegate.dark != dark;
  }
}

class _HeroMockup extends StatelessWidget {
  final _CircumColors colors;
  final VoidCallback onStart;

  const _HeroMockup({required this.colors, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final map = _MiniMap(colors: colors, active: true);
        final panel = _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _LogoTile(colors: colors),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your rider is on the way',
                          style: TextStyle(
                            color: colors.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Bike courier arriving in 8 min',
                          style: TextStyle(
                            color: colors.mutedText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _RouteRow(
                colors: colors,
                from: 'Pickup address',
                to: 'Drop-off address',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MetricPill(
                      colors: colors,
                      label: 'ETA',
                      value: '14 min',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricPill(
                      colors: colors,
                      label: 'Quote',
                      value: '£9.80',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Start a delivery'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.text,
                    foregroundColor: colors.inverseText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(colors.dark ? 0.32 : 0.08),
                blurRadius: 36,
                offset: const Offset(0, 18),
              )
            ],
          ),
          child: wide
              ? Row(
                  children: [
                    Expanded(flex: 6, child: map),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: panel),
                  ],
                )
              : Column(
                  children: [
                    map,
                    const SizedBox(height: 16),
                    panel,
                  ],
                ),
        );
      },
    );
  }
}

class _FeatureBand extends StatelessWidget {
  final _CircumColors colors;

  const _FeatureBand({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: colors.band,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 70),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth < 760 ? 1 : 3;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                mainAxisSpacing: 18,
                crossAxisSpacing: 18,
                childAspectRatio: cols == 1 ? 2.1 : 1.05,
                children: [
                  _FeatureCard(
                    colors: colors,
                    icon: Icons.tune,
                    tint: const Color(0xffdbeafe),
                    title: 'Iris matching',
                    body:
                        'Tell Iris what you are sending and it helps choose the right rider, vehicle, route, and price.',
                  ),
                  _FeatureCard(
                    colors: colors,
                    icon: Icons.verified_user_outlined,
                    tint: const Color(0xffdcfce7),
                    title: 'Built-in reassurance',
                    body:
                        'Follow the journey with live location, rider details, status updates, and delivery proof.',
                  ),
                  _FeatureCard(
                    colors: colors,
                    icon: Icons.bolt,
                    tint: const Color(0xffede9fe),
                    title: 'Ready when you are',
                    body:
                        'Send the job to nearby riders and choose the option that fits the delivery.',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PhoneStage extends StatelessWidget {
  final _CircumColors colors;
  final Widget child;

  const _PhoneStage({super.key, required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= _desktopWebBreakpoint) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: colors.stage,
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 1180),
            decoration: BoxDecoration(
              color: colors.appBackground,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 32,
                  offset: Offset(0, 18),
                )
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: colors.stage,
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 520 ? 0 : 22,
        vertical: MediaQuery.sizeOf(context).width < 520 ? 0 : 22,
      ),
      child: Center(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 430),
          decoration: BoxDecoration(
            color: colors.appBackground,
            borderRadius: MediaQuery.sizeOf(context).width < 520
                ? BorderRadius.zero
                : BorderRadius.circular(42),
            border: MediaQuery.sizeOf(context).width < 520
                ? null
                : Border.all(
                    color: colors.dark ? Colors.black : Colors.black, width: 8),
            boxShadow: [
              if (MediaQuery.sizeOf(context).width >= 520)
                const BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 34,
                  offset: Offset(0, 18),
                )
            ],
          ),
          child: ClipRRect(
            borderRadius: MediaQuery.sizeOf(context).width < 520
                ? BorderRadius.zero
                : BorderRadius.circular(32),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _RiderEnrollmentPortal extends StatefulWidget {
  final bool darkMode;
  final _CircumColors colors;
  final VoidCallback onBack;
  final ValueChanged<CircumRole> onRoleSelected;
  final VoidCallback onToggleTheme;

  const _RiderEnrollmentPortal({
    required this.darkMode,
    required this.colors,
    required this.onBack,
    required this.onRoleSelected,
    required this.onToggleTheme,
  });

  @override
  State<_RiderEnrollmentPortal> createState() => _RiderEnrollmentPortalState();
}

class _RiderEnrollmentPortalState extends State<_RiderEnrollmentPortal> {
  final _fullName = TextEditingController(text: 'Alex Rider');
  final _phone = TextEditingController(text: '+44 7700 900456');
  final _email = TextEditingController(text: 'rider@circum.app');
  final _password = TextEditingController();
  final _postcode = TextEditingController(text: 'E1 6AN');
  final _vehicle = TextEditingController(text: 'Bike');
  final _vehicleMakeModel = TextEditingController(text: 'Volt London e-bike');
  final _vehicleColour = TextEditingController(text: 'Blue');
  final _plateNumber = TextEditingController(text: 'CIR 24K');
  final _availability = TextEditingController(text: 'Weekdays, evenings');
  final _notes = TextEditingController(text: 'Experienced London courier.');
  final _withdrawAmount = TextEditingController(text: '25');
  final _bankName = TextEditingController();
  final _sortCode = TextEditingController();
  final _accountNumber = TextEditingController();
  final _documentType = TextEditingController(text: 'Right to work');
  final _documentNotes = TextEditingController();
  bool _rightToWork = false;
  bool _sealedPackageConsent = false;
  bool _signupMode = true;
  bool _authSubmitting = false;
  bool _submitting = false;
  bool _withdrawSubmitting = false;
  bool _documentSubmitting = false;
  bool _saveBank = true;
  bool _roleChoiceConfirmed = false;
  User? _riderUser;
  _RiderEarningsSnapshot _earnings = _RiderEarningsSnapshot.empty();
  String? _message;
  String? _authMessage;
  String? _withdrawMessage;
  String? _documentMessage;
  String? _applicationId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _earningsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _performanceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ratingSub;
  DriverPerformanceMetric _performance =
      DriverPerformanceMetric.empty('web-rider');
  List<DriverRating> _recentRatings = const [];
  Set<CircumRole> _availableRoles = const {};

  @override
  void initState() {
    super.initState();
    _restoreRiderSession();
  }

  @override
  void dispose() {
    _earningsSub?.cancel();
    _performanceSub?.cancel();
    _ratingSub?.cancel();
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _postcode.dispose();
    _vehicle.dispose();
    _vehicleMakeModel.dispose();
    _vehicleColour.dispose();
    _plateNumber.dispose();
    _availability.dispose();
    _notes.dispose();
    _withdrawAmount.dispose();
    _bankName.dispose();
    _sortCode.dispose();
    _accountNumber.dispose();
    _documentType.dispose();
    _documentNotes.dispose();
    super.dispose();
  }

  Future<void> _restoreRiderSession() async {
    try {
      await _ensureCircumFirebaseReady();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !mounted) return;
      if (!await _allowRiderUser(user)) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() => _authMessage =
            'Use a rider account here. Sender and admin accounts have their own sign-in.');
        return;
      }
      setState(() {
        _riderUser = user;
        _email.text = user.email ?? _email.text;
        _roleChoiceConfirmed = false;
      });
      _listenToRiderEarnings(user.uid);
      _listenToRiderPerformance(user.uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _authMessage = 'Sign in to manage rider earnings.');
    }
  }

  Future<void> _submitAuth() async {
    if (_authSubmitting) return;
    final email = _email.text.trim();
    final password = _password.text.trim();
    if (email.isEmpty || password.length < 6) {
      setState(() => _authMessage =
          'Enter an email and a password with at least 6 characters.');
      return;
    }

    setState(() {
      _authSubmitting = true;
      _authMessage =
          _signupMode ? 'Creating your rider account...' : 'Signing you in...';
    });

    try {
      await _ensureCircumFirebaseReady();
      final auth = FirebaseAuth.instance;
      final credential = _signupMode
          ? await auth.createUserWithEmailAndPassword(
              email: email,
              password: password,
            )
          : await auth.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
      final user = credential.user!;
      if (_signupMode) {
        await user.updateDisplayName(_fullName.text.trim());
        await _saveRiderProfile(user);
        _availableRoles = {CircumRole.rider};
      } else if (!await _allowRiderUser(user)) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() => _authMessage =
            'This account is not a rider account. Use sender login or the admin site instead.');
        return;
      }
      _listenToRiderEarnings(user.uid);
      _listenToRiderPerformance(user.uid);
      if (!mounted) return;
      setState(() {
        _riderUser = user;
        _roleChoiceConfirmed = _availableRoles.length <= 1;
        _authMessage =
            _signupMode ? 'Your rider account is ready.' : 'You are signed in.';
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _authMessage = _friendlyAuthMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _authMessage = 'We could not continue. Please try again.');
    } finally {
      if (mounted) setState(() => _authSubmitting = false);
    }
  }

  Future<bool> _allowRiderUser(User user) async {
    final roles = await _rolesForUser(user);
    if (!mounted) return false;
    setState(() => _availableRoles = roles);
    return RoleAccessPolicy.rolesCanAccessRider(roles);
  }

  Future<Set<CircumRole>> _rolesForUser(User user) async {
    final token = await user.getIdTokenResult(true);
    final claims = token.claims ?? const <String, dynamic>{};
    final db = FirebaseFirestore.instance;
    final userDoc = await db.collection('users').doc(user.uid).get();
    final riderDoc = await db.collection('riderProfiles').doc(user.uid).get();
    final adminDoc = await db.collection('adminUsers').doc(user.uid).get();
    return RoleAccessPolicy.resolveRoles(
      claims: claims,
      user: userDoc.data() ?? const {},
      rider: riderDoc.data() ?? const {},
      adminUser: adminDoc.data() ?? const {},
    );
  }

  Future<void> _saveRiderProfile(User user) async {
    final db = FirebaseFirestore.instance;
    await db.collection('riderProfiles').doc(user.uid).set({
      'riderId': user.uid,
      'fullName': _fullName.text.trim().isEmpty
          ? user.displayName
          : _fullName.text.trim(),
      'phoneNumber': _phone.text.trim(),
      'email': user.email ?? _email.text.trim(),
      'postcode': _postcode.text.trim(),
      'vehicleType': _vehicle.text.trim(),
      'vehicleMakeModel': _vehicleMakeModel.text.trim(),
      'vehicleColour': _vehicleColour.text.trim(),
      'plateNumber': _plateNumber.text.trim(),
      'vehicle': DriverVehicle(
        type: _vehicle.text.trim(),
        makeModel: _vehicleMakeModel.text.trim(),
        colour: _vehicleColour.text.trim(),
        plateNumber: _plateNumber.text.trim(),
      ).toJson(),
      'availability': _availability.text.trim(),
      'verificationStatus': 'pending',
      'driverStatus': 'active',
      'role': 'rider',
      'roles': ['rider'],
      'source': 'circum-web',
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await db.collection('riders').doc(user.uid).set({
      'name': _fullName.text.trim().isEmpty
          ? user.displayName
          : _fullName.text.trim(),
      'phone': _phone.text.trim(),
      'role': 'delivery',
      'status': 'offline',
      'rating': _performance.averageRating.toStringAsFixed(2),
      'plateNumber': _plateNumber.text.trim(),
      'typeOfVehicle': _vehicle.text.trim(),
      'vehicleMakeModel': _vehicleMakeModel.text.trim(),
      'vehicleColour': _vehicleColour.text.trim(),
      'verificationStatus': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await db.collection('riderEarnings').doc(user.uid).set({
      'riderId': user.uid,
      'availableBalance': FieldValue.increment(0),
      'pendingWithdrawal': FieldValue.increment(0),
      'lifetimeEarnings': FieldValue.increment(0),
      'completedJobs': FieldValue.increment(0),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await db.collection('driverPerformanceMetrics').doc(user.uid).set(
          DriverPerformanceMetric.empty(user.uid).toJson()
            ..addAll({'updatedAt': FieldValue.serverTimestamp()}),
          SetOptions(merge: true),
        );
  }

  void _listenToRiderEarnings(String riderId) {
    _earningsSub?.cancel();
    _performanceSub?.cancel();
    _ratingSub?.cancel();
    _earningsSub = FirebaseFirestore.instance
        .collection('riderEarnings')
        .doc(riderId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _earnings = _RiderEarningsSnapshot.fromMap(snapshot.data());
      });
    });
  }

  void _listenToRiderPerformance(String riderId) {
    _performanceSub?.cancel();
    _ratingSub?.cancel();
    _performanceSub = FirebaseFirestore.instance
        .collection('driverPerformanceMetrics')
        .doc(riderId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _performance =
            DriverPerformanceMetric.fromMap(riderId, snapshot.data());
      });
    });
    _ratingSub = FirebaseFirestore.instance
        .collection('driverRatings')
        .where('driverId', isEqualTo: riderId)
        .limit(8)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _recentRatings = snapshot.docs
            .map((doc) => DriverRating.fromMap(doc.data()))
            .toList();
      });
    });
  }

  Future<void> _signOutRider() async {
    await _earningsSub?.cancel();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      _riderUser = null;
      _earnings = _RiderEarningsSnapshot.empty();
      _performance = DriverPerformanceMetric.empty('web-rider');
      _recentRatings = const [];
      _availableRoles = const {};
      _roleChoiceConfirmed = false;
      _authMessage = 'Signed out.';
    });
  }

  Future<void> _requestWithdrawal() async {
    final user = _riderUser;
    if (_withdrawSubmitting || user == null) {
      setState(() => _withdrawMessage = 'Sign in before requesting a payout.');
      return;
    }
    final amount = double.tryParse(_withdrawAmount.text.trim()) ?? 0;
    if (amount <= 0 ||
        _bankName.text.trim().isEmpty ||
        _sortCode.text.trim().isEmpty ||
        _accountNumber.text.trim().isEmpty) {
      setState(
          () => _withdrawMessage = 'Enter the amount and bank details first.');
      return;
    }
    if (amount > _earnings.availableBalance) {
      setState(() => _withdrawMessage =
          'The withdrawal amount is higher than your available balance.');
      return;
    }

    setState(() {
      _withdrawSubmitting = true;
      _withdrawMessage = 'Sending withdrawal request...';
    });

    try {
      await _ensureCircumFirebaseReady();
      final db = FirebaseFirestore.instance;
      final requestRef = db.collection('payoutRequests').doc();
      final batch = db.batch();
      batch.set(requestRef, {
        'requestId': requestRef.id,
        'riderId': user.uid,
        'riderEmail': user.email,
        'amount': amount,
        'bankName': _bankName.text.trim(),
        'sortCode': _sortCode.text.trim(),
        'accountNumber': _accountNumber.text.trim(),
        'saveAccountDetails': _saveBank,
        'status': 'pending',
        'source': 'circum-web',
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(
          db.collection('riderEarnings').doc(user.uid),
          {
            'pendingWithdrawal': FieldValue.increment(amount),
            'availableBalance': FieldValue.increment(-amount),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      if (_saveBank) {
        batch.set(
            db.collection('riderBankAccounts').doc(user.uid),
            {
              'riderId': user.uid,
              'bankName': _bankName.text.trim(),
              'sortCodeLast2': _sortCode.text.trim().length >= 2
                  ? _sortCode.text
                      .trim()
                      .substring(_sortCode.text.trim().length - 2)
                  : _sortCode.text.trim(),
              'accountLast4': _accountNumber.text.trim().length >= 4
                  ? _accountNumber.text
                      .trim()
                      .substring(_accountNumber.text.trim().length - 4)
                  : _accountNumber.text.trim(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }
      await batch.commit();
      if (!mounted) return;
      setState(() => _withdrawMessage =
          'Withdrawal request sent. Circum will process it to your bank.');
    } catch (_) {
      if (!mounted) return;
      setState(
          () => _withdrawMessage = 'We could not send the request. Try again.');
    } finally {
      if (mounted) setState(() => _withdrawSubmitting = false);
    }
  }

  Future<void> _uploadRiderDocument() async {
    final user = _riderUser;
    if (_documentSubmitting || user == null) {
      setState(() => _documentMessage = 'Sign in before uploading documents.');
      return;
    }

    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() {
        _documentSubmitting = true;
        _documentMessage = 'Uploading document...';
      });

      await _ensureCircumFirebaseReady();
      final bytes = await picked.readAsBytes();
      final safeName = picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path =
          'rider_documents/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final storageRef = FirebaseStorage.instance.ref(path);
      await storageRef.putData(bytes);
      final downloadUrl = await storageRef.getDownloadURL();

      final documentRef =
          FirebaseFirestore.instance.collection('riderDocuments').doc();
      await documentRef.set({
        'documentId': documentRef.id,
        'riderId': user.uid,
        'riderEmail': user.email,
        'type': _documentType.text.trim().isEmpty
            ? 'Rider document'
            : _documentType.text.trim(),
        'notes': _documentNotes.text.trim(),
        'fileName': picked.name,
        'storagePath': path,
        'downloadUrl': downloadUrl,
        'verificationStatus': 'pending',
        'source': 'circum-web',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance
          .collection('riderProfiles')
          .doc(user.uid)
          .set({
        'verificationStatus': 'pending',
        'lastDocumentUploadedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _documentMessage =
          'Document uploaded. Circum will review it before approval.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _documentMessage = 'Upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _documentSubmitting = false);
    }
  }

  String _friendlyAuthMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'email-already-in-use' => 'That email already has a rider account.',
      'user-not-found' => 'No rider account found for that email.',
      'wrong-password' ||
      'invalid-credential' =>
        'The sign-in details are not right.',
      'weak-password' => 'Use a stronger password.',
      _ => 'We could not sign you in. Please check the details.',
    };
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_rightToWork || !_sealedPackageConsent) {
      setState(() {
        _message =
            'Please confirm the two checks before sending your application.';
      });
      return;
    }

    final now = DateTime.now();
    final id = 'RWEB-${now.millisecondsSinceEpoch.toString().substring(6)}';
    setState(() {
      _submitting = true;
      _message = 'Sending your rider application...';
    });

    try {
      await _ensureCircumFirebaseReady();
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final application = {
        'id': id,
        'riderId': _riderUser?.uid,
        'fullName': _fullName.text.trim(),
        'phoneNumber': _phone.text.trim(),
        'email': _email.text.trim(),
        'postcode': _postcode.text.trim(),
        'vehicleType': _vehicle.text.trim(),
        'availability': _availability.text.trim(),
        'notes': _notes.text.trim(),
        'rightToWorkConfirmed': _rightToWork,
        'sealedPackageConsent': _sealedPackageConsent,
        'status': 'submitted',
        'source': 'circum-web',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      batch.set(db.collection('riderApplications').doc(id), application);
      batch.set(db.collection('riderOnboardingEvents').doc(), {
        'applicationId': id,
        'type': 'rider_application_submitted',
        'status': 'submitted',
        'source': 'circum-web',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (!mounted) return;
      setState(() {
        _applicationId = id;
        _message =
            'Thanks. Your rider application has been sent to the Circum team.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message =
            'We could not send the application just now. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _desktopWebBreakpoint;
        return Column(
          children: [
            _PortalHeader(
              colors: colors,
              darkMode: widget.darkMode,
              onBack: widget.onBack,
              onToggleTheme: widget.onToggleTheme,
            ),
            Expanded(
              child: _riderUser == null
                  ? ListView(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 28 : 18,
                        18,
                        wide ? 28 : 18,
                        34,
                      ),
                      children: [
                        _RiderPublicIntro(colors: colors),
                        const SizedBox(height: 14),
                        _RiderAccessPanel(
                          colors: colors,
                          email: _email,
                          password: _password,
                          signupMode: _signupMode,
                          submitting: _authSubmitting,
                          user: _riderUser,
                          message: _authMessage,
                          onToggleMode: () =>
                              setState(() => _signupMode = !_signupMode),
                          onSubmit: _submitAuth,
                          onSignOut: _signOutRider,
                        ),
                      ],
                    )
                  : !_roleChoiceConfirmed && _availableRoles.length > 1
                      ? ListView(
                          padding: EdgeInsets.fromLTRB(
                            wide ? 28 : 18,
                            18,
                            wide ? 28 : 18,
                            34,
                          ),
                          children: [
                            _MultiRoleChoicePanel(
                              colors: colors,
                              roles: _availableRoles,
                              onSender: () =>
                                  widget.onRoleSelected(CircumRole.sender),
                              onRider: () =>
                                  setState(() => _roleChoiceConfirmed = true),
                              onAdmin: () =>
                                  widget.onRoleSelected(CircumRole.admin),
                            ),
                          ],
                        )
                      : wide
                          ? Row(
                              children: [
                                Expanded(
                                  child: ListView(
                                    padding: const EdgeInsets.fromLTRB(
                                        28, 28, 28, 34),
                                    children: [
                                      _RiderAccessPanel(
                                        colors: colors,
                                        email: _email,
                                        password: _password,
                                        signupMode: _signupMode,
                                        submitting: _authSubmitting,
                                        user: _riderUser,
                                        message: _authMessage,
                                        onToggleMode: () => setState(
                                            () => _signupMode = !_signupMode),
                                        onSubmit: _submitAuth,
                                        onSignOut: _signOutRider,
                                      ),
                                      const SizedBox(height: 14),
                                      _RiderEnrollmentForm(
                                        colors: colors,
                                        nested: true,
                                        fullName: _fullName,
                                        phone: _phone,
                                        email: _email,
                                        postcode: _postcode,
                                        vehicle: _vehicle,
                                        vehicleMakeModel: _vehicleMakeModel,
                                        vehicleColour: _vehicleColour,
                                        plateNumber: _plateNumber,
                                        availability: _availability,
                                        notes: _notes,
                                        rightToWork: _rightToWork,
                                        sealedPackageConsent:
                                            _sealedPackageConsent,
                                        submitting: _submitting,
                                        message: _message,
                                        onRightToWork: (value) => setState(() =>
                                            _rightToWork = value ?? false),
                                        onSealedPackageConsent: (value) =>
                                            setState(() =>
                                                _sealedPackageConsent =
                                                    value ?? false),
                                        onSubmit: _submit,
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: _RiderWorkspace(
                                    colors: colors,
                                    user: _riderUser,
                                    earnings: _earnings,
                                    performance: _performance,
                                    recentRatings: _recentRatings,
                                    applicationId: _applicationId,
                                    withdrawAmount: _withdrawAmount,
                                    bankName: _bankName,
                                    sortCode: _sortCode,
                                    accountNumber: _accountNumber,
                                    documentType: _documentType,
                                    documentNotes: _documentNotes,
                                    saveBank: _saveBank,
                                    submittingWithdrawal: _withdrawSubmitting,
                                    submittingDocument: _documentSubmitting,
                                    withdrawMessage: _withdrawMessage,
                                    documentMessage: _documentMessage,
                                    onSaveBank: (value) => setState(
                                        () => _saveBank = value ?? false),
                                    onWithdraw: _requestWithdrawal,
                                    onUploadDocument: _uploadRiderDocument,
                                  ),
                                ),
                              ],
                            )
                          : ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 12, 18, 28),
                              children: [
                                _RiderAccessPanel(
                                  colors: colors,
                                  email: _email,
                                  password: _password,
                                  signupMode: _signupMode,
                                  submitting: _authSubmitting,
                                  user: _riderUser,
                                  message: _authMessage,
                                  onToggleMode: () => setState(
                                      () => _signupMode = !_signupMode),
                                  onSubmit: _submitAuth,
                                  onSignOut: _signOutRider,
                                ),
                                const SizedBox(height: 14),
                                _RiderEnrollmentForm(
                                  colors: colors,
                                  nested: true,
                                  fullName: _fullName,
                                  phone: _phone,
                                  email: _email,
                                  postcode: _postcode,
                                  vehicle: _vehicle,
                                  vehicleMakeModel: _vehicleMakeModel,
                                  vehicleColour: _vehicleColour,
                                  plateNumber: _plateNumber,
                                  availability: _availability,
                                  notes: _notes,
                                  rightToWork: _rightToWork,
                                  sealedPackageConsent: _sealedPackageConsent,
                                  submitting: _submitting,
                                  message: _message,
                                  onRightToWork: (value) => setState(
                                      () => _rightToWork = value ?? false),
                                  onSealedPackageConsent: (value) => setState(
                                      () => _sealedPackageConsent =
                                          value ?? false),
                                  onSubmit: _submit,
                                ),
                                const SizedBox(height: 14),
                                _RiderWorkspace(
                                  colors: colors,
                                  user: _riderUser,
                                  earnings: _earnings,
                                  performance: _performance,
                                  recentRatings: _recentRatings,
                                  applicationId: _applicationId,
                                  withdrawAmount: _withdrawAmount,
                                  bankName: _bankName,
                                  sortCode: _sortCode,
                                  accountNumber: _accountNumber,
                                  documentType: _documentType,
                                  documentNotes: _documentNotes,
                                  saveBank: _saveBank,
                                  submittingWithdrawal: _withdrawSubmitting,
                                  submittingDocument: _documentSubmitting,
                                  withdrawMessage: _withdrawMessage,
                                  documentMessage: _documentMessage,
                                  onSaveBank: (value) => setState(
                                      () => _saveBank = value ?? false),
                                  onWithdraw: _requestWithdrawal,
                                  onUploadDocument: _uploadRiderDocument,
                                  nested: true,
                                ),
                              ],
                            ),
            ),
          ],
        );
      },
    );
  }
}

class _RiderPublicIntro extends StatelessWidget {
  final _CircumColors colors;

  const _RiderPublicIntro({required this.colors});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Earn with Circum.',
            style: TextStyle(
              color: colors.text,
              fontSize: 34,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a rider account to apply, upload documents, accept jobs, track earnings, and manage payouts.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('Verified riders only'),
                backgroundColor: colors.field,
              ),
              Chip(
                avatar: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Earnings dashboard'),
                backgroundColor: colors.field,
              ),
              Chip(
                avatar: const Icon(Icons.route_outlined, size: 18),
                label: const Text('Local delivery jobs'),
                backgroundColor: colors.field,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiderAccessPanel extends StatelessWidget {
  final _CircumColors colors;
  final TextEditingController email;
  final TextEditingController password;
  final bool signupMode;
  final bool submitting;
  final User? user;
  final String? message;
  final VoidCallback onToggleMode;
  final VoidCallback onSubmit;
  final VoidCallback onSignOut;

  const _RiderAccessPanel({
    required this.colors,
    required this.email,
    required this.password,
    required this.signupMode,
    required this.submitting,
    required this.user,
    required this.message,
    required this.onToggleMode,
    required this.onSubmit,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final signedIn = user != null;
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
              colors: colors,
              title: signedIn ? 'Rider account' : 'Rider sign in'),
          const SizedBox(height: 10),
          Text(
            signedIn
                ? 'Signed in as ${user!.email ?? 'rider'}'
                : 'Create an account or sign in to upload documents, see earnings, and request bank withdrawals.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!signedIn) ...[
            const SizedBox(height: 12),
            _InputBox(colors: colors, controller: email, hint: 'Email'),
            const SizedBox(height: 10),
            _InputBox(
                colors: colors,
                controller: password,
                hint: 'Password',
                obscureText: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: submitting ? null : onSubmit,
                    icon: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open),
                    label: Text(submitting
                        ? 'Please wait...'
                        : signupMode
                            ? 'Create account'
                            : 'Sign in'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.text,
                      foregroundColor: colors.inverseText,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: submitting ? null : onToggleMode,
                  child: Text(signupMode ? 'Sign in' : 'Sign up'),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(message!,
                style:
                    TextStyle(color: colors.text, fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}

class _RiderEnrollmentForm extends StatelessWidget {
  final _CircumColors colors;
  final bool nested;
  final TextEditingController fullName;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController postcode;
  final TextEditingController vehicle;
  final TextEditingController vehicleMakeModel;
  final TextEditingController vehicleColour;
  final TextEditingController plateNumber;
  final TextEditingController availability;
  final TextEditingController notes;
  final bool rightToWork;
  final bool sealedPackageConsent;
  final bool submitting;
  final String? message;
  final ValueChanged<bool?> onRightToWork;
  final ValueChanged<bool?> onSealedPackageConsent;
  final VoidCallback onSubmit;

  const _RiderEnrollmentForm({
    required this.colors,
    this.nested = false,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.postcode,
    required this.vehicle,
    required this.vehicleMakeModel,
    required this.vehicleColour,
    required this.plateNumber,
    required this.availability,
    required this.notes,
    required this.rightToWork,
    required this.sealedPackageConsent,
    required this.submitting,
    required this.message,
    required this.onRightToWork,
    required this.onSealedPackageConsent,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: nested,
      physics: nested ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 34),
      children: [
        _StepTopBar(colors: colors, title: 'Earn as a Rider', onBack: null),
        const SizedBox(height: 14),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deliver with Circum.',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 30,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Apply to take local Circum jobs, including parcel runs and Health+ pharmacy pickups.',
                style: TextStyle(
                  color: colors.mutedText,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Rider details'),
              const SizedBox(height: 12),
              _InputBox(
                  colors: colors, controller: fullName, hint: 'Full name'),
              const SizedBox(height: 10),
              _InputBox(
                  colors: colors, controller: phone, hint: 'Phone number'),
              const SizedBox(height: 10),
              _InputBox(colors: colors, controller: email, hint: 'Email'),
              const SizedBox(height: 10),
              _InputBox(colors: colors, controller: postcode, hint: 'Postcode'),
              const SizedBox(height: 10),
              _InputBox(
                  colors: colors,
                  controller: vehicle,
                  hint: 'Vehicle type: bike, e-bike, car, van'),
              const SizedBox(height: 10),
              _InputBox(
                  colors: colors,
                  controller: vehicleMakeModel,
                  hint: 'Vehicle make/model'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _InputBox(
                        colors: colors,
                        controller: vehicleColour,
                        hint: 'Colour'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InputBox(
                        colors: colors,
                        controller: plateNumber,
                        hint: 'Plate number'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _InputBox(
                  colors: colors,
                  controller: availability,
                  hint: 'Availability'),
              const SizedBox(height: 10),
              _InputBox(
                  colors: colors,
                  controller: notes,
                  hint: 'Experience / notes',
                  maxLines: 3),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: colors.text,
          value: rightToWork,
          onChanged: onRightToWork,
          title: Text(
            'I have the right to work and can provide documents if asked.',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: colors.text,
          value: sealedPackageConsent,
          onChanged: onSealedPackageConsent,
          title: Text(
            'I will only collect sealed pharmacy bags and will not open or inspect them.',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(message!,
              style:
                  TextStyle(color: colors.text, fontWeight: FontWeight.w800)),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: submitting ? null : onSubmit,
          icon: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.two_wheeler),
          label: Text(submitting ? 'Sending...' : 'Send rider application'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.text,
            foregroundColor: colors.inverseText,
            padding: const EdgeInsets.symmetric(vertical: 17),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }
}

class _RiderWorkspace extends StatelessWidget {
  final _CircumColors colors;
  final User? user;
  final _RiderEarningsSnapshot earnings;
  final DriverPerformanceMetric performance;
  final List<DriverRating> recentRatings;
  final String? applicationId;
  final TextEditingController withdrawAmount;
  final TextEditingController bankName;
  final TextEditingController sortCode;
  final TextEditingController accountNumber;
  final TextEditingController documentType;
  final TextEditingController documentNotes;
  final bool saveBank;
  final bool submittingWithdrawal;
  final bool submittingDocument;
  final String? withdrawMessage;
  final String? documentMessage;
  final ValueChanged<bool?> onSaveBank;
  final VoidCallback onWithdraw;
  final VoidCallback onUploadDocument;
  final bool nested;

  const _RiderWorkspace({
    required this.colors,
    required this.user,
    required this.earnings,
    required this.performance,
    required this.recentRatings,
    required this.applicationId,
    required this.withdrawAmount,
    required this.bankName,
    required this.sortCode,
    required this.accountNumber,
    required this.documentType,
    required this.documentNotes,
    required this.saveBank,
    required this.submittingWithdrawal,
    required this.submittingDocument,
    required this.withdrawMessage,
    required this.documentMessage,
    required this.onSaveBank,
    required this.onWithdraw,
    required this.onUploadDocument,
    this.nested = false,
  });

  @override
  Widget build(BuildContext context) {
    final signedIn = user != null;
    return Container(
      color: colors.band,
      padding: const EdgeInsets.all(28),
      child: ListView(
        shrinkWrap: nested,
        physics: nested ? const NeverScrollableScrollPhysics() : null,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Rider dashboard',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _HealthChip(label: signedIn ? 'Signed in' : 'Account needed'),
            ],
          ),
          const SizedBox(height: 18),
          _MiniMap(colors: colors, active: true),
          const SizedBox(height: 18),
          _DriverPerformancePanel(
            colors: colors,
            performance: performance,
            recentRatings: recentRatings,
          ),
          const SizedBox(height: 14),
          _GlassPanel(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(colors: colors, title: 'Earnings'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RiderStatTile(
                        colors: colors,
                        label: 'Available',
                        value: _money(earnings.availableBalance),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RiderStatTile(
                        colors: colors,
                        label: 'Pending',
                        value: _money(earnings.pendingWithdrawal),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _RiderStatTile(
                        colors: colors,
                        label: 'Lifetime',
                        value: _money(earnings.lifetimeEarnings),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RiderStatTile(
                        colors: colors,
                        label: 'Jobs',
                        value: '${earnings.completedJobs}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GlassPanel(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(colors: colors, title: 'Withdraw to bank'),
                const SizedBox(height: 10),
                _InputBox(
                    colors: colors, controller: withdrawAmount, hint: 'Amount'),
                const SizedBox(height: 10),
                _InputBox(
                    colors: colors, controller: bankName, hint: 'Bank name'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _InputBox(
                          colors: colors,
                          controller: sortCode,
                          hint: 'Sort code'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InputBox(
                          colors: colors,
                          controller: accountNumber,
                          hint: 'Account number'),
                    ),
                  ],
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: saveBank,
                  onChanged: onSaveBank,
                  activeColor: colors.text,
                  title: Text(
                    'Save this bank for future withdrawals',
                    style: TextStyle(
                        color: colors.text, fontWeight: FontWeight.w700),
                  ),
                ),
                if (withdrawMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(withdrawMessage!,
                      style: TextStyle(
                          color: colors.text, fontWeight: FontWeight.w800)),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        signedIn && !submittingWithdrawal ? onWithdraw : null,
                    icon: submittingWithdrawal
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.account_balance),
                    label: Text(submittingWithdrawal
                        ? 'Sending request...'
                        : 'Request withdrawal'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.text,
                      foregroundColor: colors.inverseText,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GlassPanel(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(colors: colors, title: 'Driver documents'),
                const SizedBox(height: 8),
                Text(
                  'Upload right-to-work proof, driving licence, insurance, or vehicle documents for Circum review.',
                  style: TextStyle(
                      color: colors.mutedText,
                      height: 1.35,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _InputBox(
                    colors: colors,
                    controller: documentType,
                    hint: 'Document type'),
                const SizedBox(height: 10),
                _InputBox(
                    colors: colors,
                    controller: documentNotes,
                    hint: 'Notes for review',
                    maxLines: 2),
                if (documentMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(documentMessage!,
                      style: TextStyle(
                          color: colors.text, fontWeight: FontWeight.w800)),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: signedIn && !submittingDocument
                        ? onUploadDocument
                        : null,
                    icon: submittingDocument
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(submittingDocument
                        ? 'Uploading...'
                        : 'Upload document'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GlassPanel(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(colors: colors, title: 'What happens next'),
                _RiderChecklistRow(
                  colors: colors,
                  icon: Icons.assignment_turned_in,
                  label: 'Application received',
                  value: applicationId ?? 'Not sent yet',
                ),
                _RiderChecklistRow(
                  colors: colors,
                  icon: Icons.verified_user,
                  label: 'Circum review',
                  value: 'Documents, vehicle, and availability',
                ),
                _RiderChecklistRow(
                  colors: colors,
                  icon: Icons.medical_services,
                  label: 'Health+ pickups',
                  value: 'Sealed pharmacy packages only',
                ),
                _RiderChecklistRow(
                  colors: colors,
                  icon: Icons.route,
                  label: 'Jobs you can receive',
                  value: 'Sender requests and Health+ pickups',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _AdminDriverQualityPanel(colors: colors),
        ],
      ),
    );
  }

  static String _money(double value) => '£${value.toStringAsFixed(2)}';
}

class _DriverPerformancePanel extends StatelessWidget {
  final _CircumColors colors;
  final DriverPerformanceMetric performance;
  final List<DriverRating> recentRatings;

  const _DriverPerformancePanel({
    required this.colors,
    required this.performance,
    required this.recentRatings,
  });

  @override
  Widget build(BuildContext context) {
    final rating = performance.averageRating <= 0
        ? 'New'
        : performance.averageRating.toStringAsFixed(2);
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Driver rating'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RiderStatTile(
                  colors: colors,
                  label: 'Rating',
                  value: rating,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RiderStatTile(
                  colors: colors,
                  label: 'Quality',
                  value: '${performance.qualityScore.toStringAsFixed(0)}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _RiderStatTile(
                  colors: colors,
                  label: 'Reviews',
                  value: '${performance.totalRatings}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RiderStatTile(
                  colors: colors,
                  label: 'Trips',
                  value: '${performance.completedTrips}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HealthChip(label: _statusLabel(performance.driverStatus)),
              if (performance.averageRating >= 4.5)
                const _HealthChip(label: 'Excellent service'),
              if (performance.recentRatingTrend > 0)
                const _HealthChip(label: 'Improving'),
              if (DriverPerformanceService.shouldFlagLowRatedDriver(
                  performance))
                const _HealthChip(label: 'Needs review'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            recentRatings.isEmpty
                ? 'Recent feedback will appear here.'
                : 'Recent feedback',
            style: TextStyle(
              color: colors.mutedText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ...recentRatings.take(3).map(
                (rating) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RatingFeedbackRow(colors: colors, rating: rating),
                ),
              ),
          if (performance.averageRating < 4 && performance.totalRatings > 0)
            Text(
              'Focus areas: arrive on time, keep customers updated, and handle parcels carefully.',
              style: TextStyle(
                color: colors.text,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  static String _statusLabel(String status) {
    return switch (status) {
      'excellent' => 'Excellent',
      'good' => 'Good',
      'needs_monitoring' => 'Needs monitoring',
      'under_review' => 'Under review',
      'suspended_review' => 'Manual review',
      _ => 'Active',
    };
  }
}

class _RatingFeedbackRow extends StatelessWidget {
  final _CircumColors colors;
  final DriverRating rating;

  const _RatingFeedbackRow({required this.colors, required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '★ ${rating.starRating}',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rating.hiddenByAdmin
                  ? 'Written feedback hidden by admin.'
                  : (rating.feedbackText.isEmpty
                      ? rating.feedbackTags.join(', ')
                      : rating.feedbackText),
              style: TextStyle(
                color: colors.mutedText,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDriverQualityPanel extends StatelessWidget {
  final _CircumColors colors;

  const _AdminDriverQualityPanel({required this.colors});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Operations view'),
          const SizedBox(height: 8),
          Text(
            'Driver quality, poor ratings, complaints, and review status.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('driverPerformanceMetrics')
                .limit(12)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Could not load driver quality right now.',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? const [];
              if (docs.isEmpty) {
                return Text(
                  'No driver quality records yet.',
                  style: TextStyle(
                    color: colors.mutedText,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }
              return Column(
                children: docs.map((doc) {
                  final metric =
                      DriverPerformanceMetric.fromMap(doc.id, doc.data());
                  return _AdminDriverRow(colors: colors, metric: metric);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AdminDriverRow extends StatelessWidget {
  final _CircumColors colors;
  final DriverPerformanceMetric metric;

  const _AdminDriverRow({required this.colors, required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              metric.driverId,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            '★ ${metric.averageRating.toStringAsFixed(2)}',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 10),
          Text(
            '${metric.completedTrips} trips',
            style: TextStyle(
              color: colors.mutedText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${metric.qualityScore.toStringAsFixed(0)}%',
            style: TextStyle(
              color: DriverPerformanceService.shouldFlagLowRatedDriver(metric)
                  ? const Color(0xffdc2626)
                  : colors.success,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderEarningsSnapshot {
  final double availableBalance;
  final double pendingWithdrawal;
  final double lifetimeEarnings;
  final int completedJobs;

  const _RiderEarningsSnapshot({
    required this.availableBalance,
    required this.pendingWithdrawal,
    required this.lifetimeEarnings,
    required this.completedJobs,
  });

  factory _RiderEarningsSnapshot.empty() => const _RiderEarningsSnapshot(
        availableBalance: 0,
        pendingWithdrawal: 0,
        lifetimeEarnings: 0,
        completedJobs: 0,
      );

  factory _RiderEarningsSnapshot.fromMap(Map<String, dynamic>? data) {
    if (data == null) return _RiderEarningsSnapshot.empty();
    return _RiderEarningsSnapshot(
      availableBalance: (data['availableBalance'] as num? ??
              data['accountBalance'] as num? ??
              0)
          .toDouble(),
      pendingWithdrawal: (data['pendingWithdrawal'] as num? ?? 0).toDouble(),
      lifetimeEarnings: (data['lifetimeEarnings'] as num? ??
              data['totalAmountEarned'] as num? ??
              0)
          .toDouble(),
      completedJobs:
          (data['completedJobs'] as num? ?? data['totalTrips'] as num? ?? 0)
              .toInt(),
    );
  }
}

class _RiderStatTile extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;

  const _RiderStatTile({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: colors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _RiderChecklistRow extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String label;
  final String value;

  const _RiderChecklistRow({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: colors.text, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        color: colors.mutedText, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _SenderStep {
  dashboard,
  details,
  vehicle,
  payment,
  tracking,
  healthPlus,
  profile,
}

class _CustomerPortal extends StatefulWidget {
  final bool darkMode;
  final _CircumColors colors;
  final _SenderStep initialStep;
  final VoidCallback onBack;
  final ValueChanged<CircumRole> onRoleSelected;
  final VoidCallback onToggleTheme;

  const _CustomerPortal({
    required this.darkMode,
    required this.colors,
    required this.initialStep,
    required this.onBack,
    required this.onRoleSelected,
    required this.onToggleTheme,
  });

  @override
  State<_CustomerPortal> createState() => _CustomerPortalState();
}

class _CustomerPortalState extends State<_CustomerPortal> {
  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();
  final _description = TextEditingController();
  final _weight = TextEditingController();
  final _scheduledPickupDate = TextEditingController();
  final _scheduledPickupWindow = TextEditingController();
  final _scheduledDropoffDate = TextEditingController();
  final _scheduledDropoffWindow = TextEditingController();
  final _chatInput = TextEditingController();
  final _healthName = TextEditingController();
  final _healthPhone = TextEditingController();
  final _healthEmail = TextEditingController();
  final _healthPharmacy = TextEditingController();
  final _healthDelivery = TextEditingController();
  final _healthNotes = TextEditingController();
  final _healthPreferredTime = TextEditingController();
  final _healthCustomSchedule = TextEditingController();
  final _ratingFeedback = TextEditingController();
  final _senderEmail = TextEditingController();
  final _senderPassword = TextEditingController();
  final _senderName = TextEditingController();
  final _senderPhone = TextEditingController();
  final _savedAddressLabel = TextEditingController(text: 'Home');
  final _savedAddress = TextEditingController();
  String _savedAddressType = 'pickup';
  double? _irisEstimatedWeightKg;
  String? _irisWeightBand;
  String? _irisWeightConfidence;
  String? _irisWeightExplanation;
  double? _senderEnteredWeightKg;
  double? _confirmedWeightKg;
  String? _confirmedWeightBand;
  String? _weightSource;
  DateTime? _weightConfirmedAt;
  String? _weightMessage;
  String? _weightPricingReason;
  bool _weightVerificationRequired = false;
  bool _settingWeightFromConfirmation = false;

  late _SenderStep _step = widget.initialStep;
  _VehicleOption _selectedVehicle = _vehicles.first;
  String _selectedSpeed = 'Standard';
  HealthPlusFrequency _healthFrequency = HealthPlusFrequency.monthly;
  bool _analyzing = false;
  bool _broadcasting = false;
  bool _chatOpen = false;
  bool _supportChat = false;
  bool _healthConsent = false;
  bool _healthSavePayment = true;
  bool _healthSubmitting = false;
  bool _ratingSubmitting = false;
  bool _ratingSubmitted = false;
  String? _activeOrderId;
  String? _activeRequestDocId;
  String? _assignedDriverId;
  String? _healthProfileId;
  String? _healthScheduleId;
  String? _healthMessage;
  String? _healthCheckoutUrl;
  String? _firebaseError;
  String? _ratingMessage;
  String? _senderProfileMessage;
  bool _firebaseOnline = false;
  bool _senderAuthLoading = true;
  bool _senderAuthBusy = false;
  bool _senderProfileSaving = false;
  bool _senderSignupMode = false;
  bool _roleChoiceConfirmed = false;
  int _statusIndex = 0;
  int _selectedRating = 0;
  int _senderProfileTab = 0;
  User? _senderUser;
  SenderProfile? _senderProfile;
  List<SenderDeliveryRecord> _senderDeliveries = const [];
  SenderDeliveryRecord? _selectedSenderDelivery;
  DriverProfile? _assignedDriver;
  DriverPerformanceMetric? _assignedDriverMetric;
  Set<String> _selectedRatingTags = {};
  Set<CircumRole> _availableRoles = const {};
  final List<Map<String, dynamic>> _healthPickups = [];
  final List<Map<String, dynamic>> _healthPayments = [];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _requestSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _senderSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverProfileSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _driverPerformanceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _assignedDriverRatingsSub;

  final List<_ChatMessage> _driverMessages = [
    _ChatMessage(
      fromMe: false,
      text: "Hello! I've received your order and I'm on my way.",
      time: 'Now',
    ),
  ];
  final List<_ChatMessage> _supportMessages = [
    _ChatMessage(
      fromMe: false,
      text: "Hi, this is Iris. How can we help?",
      time: 'Now',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _weight.addListener(_handleWeightChanged);
    _restoreSenderSession();
  }

  @override
  void dispose() {
    _weight.removeListener(_handleWeightChanged);
    _pickup.dispose();
    _dropoff.dispose();
    _description.dispose();
    _weight.dispose();
    _scheduledPickupDate.dispose();
    _scheduledPickupWindow.dispose();
    _scheduledDropoffDate.dispose();
    _scheduledDropoffWindow.dispose();
    _chatInput.dispose();
    _healthName.dispose();
    _healthPhone.dispose();
    _healthEmail.dispose();
    _healthPharmacy.dispose();
    _healthDelivery.dispose();
    _healthNotes.dispose();
    _healthPreferredTime.dispose();
    _healthCustomSchedule.dispose();
    _ratingFeedback.dispose();
    _senderEmail.dispose();
    _senderPassword.dispose();
    _senderName.dispose();
    _senderPhone.dispose();
    _savedAddressLabel.dispose();
    _savedAddress.dispose();
    _requestSub?.cancel();
    _chatSub?.cancel();
    _senderSub?.cancel();
    _driverProfileSub?.cancel();
    _driverPerformanceSub?.cancel();
    _assignedDriverRatingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= _desktopWebBreakpoint;
            return Column(
              children: [
                _PortalHeader(
                  colors: colors,
                  darkMode: widget.darkMode,
                  onBack: widget.onBack,
                  onToggleTheme: widget.onToggleTheme,
                  onProfile: () => setState(() => _step = _SenderStep.profile),
                ),
                Expanded(
                  child: desktop
                      ? _DesktopPortalLayout(
                          colors: colors,
                          pickup: _pickup.text,
                          dropoff: _dropoff.text,
                          vehicle: _selectedVehicle,
                          speed: _selectedSpeed,
                          weightKg: _confirmedWeightKg ?? 0,
                          breakdown: _quoteBreakdown,
                          step: _step,
                          firebaseOnline: _firebaseOnline,
                          firebaseError: _firebaseError,
                          statusIndex: _statusIndex,
                          child: _buildCurrentStep(colors),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
                          child: _buildAnimatedStep(colors),
                        ),
                ),
              ],
            );
          },
        ),
        if (_chatOpen)
          _ChatSheet(
            colors: colors,
            title: _supportChat ? 'Iris Support' : 'Marcus A.',
            recipient: _supportChat ? 'Iris' : 'Rider',
            messages: _supportChat ? _supportMessages : _driverMessages,
            input: _chatInput,
            onClose: () => setState(() => _chatOpen = false),
            onSend: _sendMessage,
          ),
      ],
    );
  }

  Widget _buildAnimatedStep(_CircumColors colors) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: _buildCurrentStep(colors),
    );
  }

  Widget _buildCurrentStep(_CircumColors colors) {
    if (_senderAuthLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_senderUser == null) {
      return _SenderAccessGate(
        colors: colors,
        signupMode: _senderSignupMode,
        busy: _senderAuthBusy,
        message: _senderProfileMessage,
        email: _senderEmail,
        password: _senderPassword,
        fullName: _senderName,
        phone: _senderPhone,
        onToggleMode: () =>
            setState(() => _senderSignupMode = !_senderSignupMode),
        onSignIn: _signInSender,
        onSignUp: _signUpSender,
      );
    }
    if (!_roleChoiceConfirmed && _availableRoles.length > 1) {
      return _MultiRoleChoicePanel(
        colors: colors,
        roles: _availableRoles,
        onSender: () => setState(() => _roleChoiceConfirmed = true),
        onRider: () => widget.onRoleSelected(CircumRole.rider),
        onAdmin: () => widget.onRoleSelected(CircumRole.admin),
      );
    }
    return switch (_step) {
      _SenderStep.dashboard => _SenderDashboardStep(
          key: const ValueKey('sender-dashboard'),
          colors: colors,
          profile: _senderProfile,
          deliveries: _senderDeliveries,
          onSendParcel: () => setState(() => _step = _SenderStep.details),
          onHealthPlus: () => setState(() => _step = _SenderStep.healthPlus),
          onProfile: () => setState(() => _step = _SenderStep.profile),
          onSupport: () => setState(() {
            _supportChat = true;
            _chatOpen = true;
          }),
        ),
      _SenderStep.details => _DetailsStep(
          key: const ValueKey('details'),
          colors: colors,
          pickup: _pickup,
          dropoff: _dropoff,
          savedAddresses: _senderProfile?.savedAddresses ?? const [],
          onSavedPickup: (address) => setState(() => _pickup.text = address),
          onSavedDropoff: (address) => setState(() => _dropoff.text = address),
          description: _description,
          weight: _weight,
          irisEstimatedWeightKg: _irisEstimatedWeightKg,
          irisWeightBand: _irisWeightBand,
          irisWeightConfidence: _irisWeightConfidence,
          irisWeightExplanation: _irisWeightExplanation,
          senderEnteredWeightKg: _senderEnteredWeightKg,
          pricingWeightKg: _confirmedWeightKg,
          pricingReason: _weightPricingReason,
          verificationRequired: _weightVerificationRequired,
          weightMessage: _weightMessage,
          onConfirmIrisWeight: _confirmIrisWeight,
          scheduledPickupDate: _scheduledPickupDate,
          scheduledPickupWindow: _scheduledPickupWindow,
          scheduledDropoffDate: _scheduledDropoffDate,
          scheduledDropoffWindow: _scheduledDropoffWindow,
          analyzing: _analyzing,
          onSubmit: _analyseRequest,
        ),
      _SenderStep.vehicle => _VehicleStep(
          key: const ValueKey('vehicle'),
          colors: colors,
          pickup: _pickup.text,
          dropoff: _dropoff.text,
          chargeableWeightKg: _confirmedWeightKg ?? 0,
          selectedVehicle: _selectedVehicle,
          selectedSpeed: _selectedSpeed,
          onVehicle: (vehicle) => setState(() => _selectedVehicle = vehicle),
          onSpeed: (speed) => setState(() => _selectedSpeed = speed),
          onBack: () => setState(() => _step = _SenderStep.dashboard),
          onContinue: () => setState(() => _step = _SenderStep.payment),
        ),
      _SenderStep.payment => _PaymentStep(
          key: const ValueKey('payment'),
          colors: colors,
          vehicle: _effectiveVehicle,
          speed: _selectedSpeed,
          breakdown: _quoteBreakdown,
          irisEstimatedWeightKg: _irisEstimatedWeightKg,
          senderEnteredWeightKg: _senderEnteredWeightKg,
          weightKg: _confirmedWeightKg ?? 0,
          total: _quoteTotal,
          weightConfirmed: _hasConfirmedWeight,
          weightSource: _weightSourceText,
          pricingReason: _weightPricingReason,
          scheduledPickupDate: _scheduledPickupDate.text.trim(),
          scheduledPickupWindow: _scheduledPickupWindow.text.trim(),
          scheduledDropoffDate: _scheduledDropoffDate.text.trim(),
          scheduledDropoffWindow: _scheduledDropoffWindow.text.trim(),
          onBack: () => setState(() => _step = _SenderStep.vehicle),
          onPay: _confirmPayment,
        ),
      _SenderStep.tracking => _TrackingStep(
          key: const ValueKey('tracking'),
          colors: colors,
          orderId: _activeOrderId ?? 'CIR-2026',
          pickup: _pickup.text,
          dropoff: _dropoff.text,
          vehicle: _selectedVehicle,
          statusIndex: _statusIndex,
          broadcasting: _broadcasting,
          firebaseOnline: _firebaseOnline,
          firebaseError: _firebaseError,
          assignedDriver: _assignedDriver,
          assignedDriverMetric: _assignedDriverMetric,
          ratingStars: _selectedRating,
          ratingFeedback: _ratingFeedback,
          selectedRatingTags: _selectedRatingTags,
          ratingSubmitting: _ratingSubmitting,
          ratingSubmitted: _ratingSubmitted,
          ratingMessage: _ratingMessage,
          onRatingChanged: (rating) => setState(() => _selectedRating = rating),
          onRatingTag: _toggleRatingTag,
          onSubmitRating: _submitDriverRating,
          onChatDriver: () => setState(() {
            _supportChat = false;
            _chatOpen = true;
          }),
          onChatSupport: () => setState(() {
            _supportChat = true;
            _chatOpen = true;
          }),
          onNewOrder: _reset,
        ),
      _SenderStep.healthPlus => _HealthPlusStep(
          key: const ValueKey('health-plus'),
          colors: colors,
          fullName: _healthName,
          phone: _healthPhone,
          email: _healthEmail,
          pharmacyAddress: _healthPharmacy,
          deliveryAddress: _healthDelivery,
          notes: _healthNotes,
          preferredTime: _healthPreferredTime,
          customSchedule: _healthCustomSchedule,
          frequency: _healthFrequency,
          consent: _healthConsent,
          savePayment: _healthSavePayment,
          submitting: _healthSubmitting,
          message: _healthMessage,
          checkoutUrl: _healthCheckoutUrl,
          quote: _healthQuote,
          pickups: _healthPickups,
          payments: _healthPayments,
          onBack: () => setState(() => _step = _SenderStep.dashboard),
          onFrequency: (frequency) =>
              setState(() => _healthFrequency = frequency),
          onConsent: (value) => setState(() => _healthConsent = value ?? false),
          onSavePayment: (value) =>
              setState(() => _healthSavePayment = value ?? false),
          onSubmit: _bookHealthPlus,
          onPauseSchedule: _pauseHealthPlusSchedule,
          onCancelPickup: _cancelNextHealthPlusPickup,
          onUpdatePayment: _openHealthPlusCheckout,
          onAdminStatus: _adminUpdateHealthPlusStatus,
        ),
      _SenderStep.profile => _SenderProfileStep(
          key: const ValueKey('sender-profile'),
          colors: colors,
          user: _senderUser,
          profile: _senderProfile,
          deliveries: _senderDeliveries,
          selectedDelivery: _selectedSenderDelivery,
          loading: _senderAuthLoading,
          busy: _senderAuthBusy || _senderProfileSaving,
          message: _senderProfileMessage,
          tabIndex: _senderProfileTab,
          email: _senderEmail,
          password: _senderPassword,
          fullName: _senderName,
          phone: _senderPhone,
          savedAddressLabel: _savedAddressLabel,
          savedAddress: _savedAddress,
          savedAddressType: _savedAddressType,
          onBack: () => setState(() => _step = _SenderStep.dashboard),
          onTab: (index) => setState(() => _senderProfileTab = index),
          onSignIn: _signInSender,
          onSignUp: _signUpSender,
          onSignOut: _signOutSender,
          onSaveProfile: _saveSenderProfile,
          onAddAddress: _addSenderAddress,
          onSavedAddressType: (type) =>
              setState(() => _savedAddressType = type),
          onSelectDelivery: (delivery) =>
              setState(() => _selectedSenderDelivery = delivery),
          onCloseDelivery: () => setState(() => _selectedSenderDelivery = null),
        ),
    };
  }

  double get _quoteTotal {
    return _quoteBreakdown.total;
  }

  bool get _hasConfirmedWeight {
    return _confirmedWeightKg != null && _confirmedWeightKg! > 0;
  }

  String get _weightSourceText {
    return switch (_weightSource) {
      'iris_confirmed' => 'Iris estimate confirmed by sender',
      'manual' => 'Manual sender entry',
      _ => 'Not confirmed',
    };
  }

  _VehicleOption get _effectiveVehicle {
    final chargeableWeightKg = _confirmedWeightKg ?? 0;
    if (DeliveryPricing.vehicleCanCarryWeight(
      _selectedVehicle.name,
      chargeableWeightKg,
    )) {
      return _selectedVehicle;
    }
    final recommendedVehicleName =
        DeliveryPricing.recommendedVehicleForWeight(chargeableWeightKg);
    return _vehicles.firstWhere(
      (vehicle) => vehicle.name == recommendedVehicleName,
      orElse: () => _vehicles.last,
    );
  }

  DeliveryPricingBreakdown get _quoteBreakdown {
    final chargeableWeightKg = _confirmedWeightKg ?? 0;
    return DeliveryPricing.calculate(
      DeliveryPricingInput(
        distanceMiles: _webQuoteDistanceMiles,
        weightKg: chargeableWeightKg,
        vehicleType: _effectiveVehicle.name,
        express: _selectedSpeed == 'Express',
        priority: _selectedSpeed == 'Priority',
      ),
    );
  }

  HealthPlusPriceBreakdown get _healthQuote {
    return HealthPlusPricing.calculate(
      recurring: _healthFrequency != HealthPlusFrequency.oneOff,
    );
  }

  Future<void> _restoreSenderSession() async {
    try {
      await _ensureFirebaseReady();
      final user = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      if (user == null) {
        setState(() => _senderAuthLoading = false);
        return;
      }
      if (!await _allowSenderUser(user)) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() {
          _senderAuthLoading = false;
          _senderProfileMessage =
              'Use a sender account here. Rider and admin accounts have their own sign-in.';
        });
        return;
      }
      _attachSender(user);
      await _loadSenderDeliveries(user.uid);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _senderAuthLoading = false;
        _senderProfileMessage = 'We could not load your profile just now.';
      });
    }
  }

  void _attachSender(User user) {
    _senderSub?.cancel();
    setState(() {
      _senderUser = user;
      _senderEmail.text = user.email ?? _senderEmail.text;
      _senderAuthLoading = false;
      _roleChoiceConfirmed = _availableRoles.length <= 1;
    });
    _senderSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data() ?? <String, dynamic>{};
      final profile = SenderProfile.fromMap(user.uid, {
        'email': user.email,
        'photoURL': user.photoURL,
        'phoneNumber': user.phoneNumber,
        ...data,
      });
      if (!mounted) return;
      setState(() {
        _senderProfile = profile;
        if (_senderName.text.trim().isEmpty) {
          _senderName.text = profile.fullName;
        }
        if (_senderPhone.text.trim().isEmpty) {
          _senderPhone.text = profile.phoneNumber;
        }
      });
    });
  }

  Future<void> _signInSender() async {
    if (_senderAuthBusy) return;
    setState(() {
      _senderAuthBusy = true;
      _senderProfileMessage = 'Signing you in...';
    });
    try {
      await _ensureFirebaseReady();
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _senderEmail.text.trim(),
        password: _senderPassword.text.trim(),
      );
      final user = credential.user!;
      if (!await _allowSenderUser(user)) {
        await FirebaseAuth.instance.signOut();
        setState(() => _senderProfileMessage =
            'This account is not a sender account. Use the rider or admin sign-in instead.');
        return;
      }
      _attachSender(user);
      await _loadSenderDeliveries(user.uid);
      setState(() => _senderProfileMessage = 'Profile ready.');
    } on FirebaseAuthException catch (error) {
      setState(() => _senderProfileMessage = _friendlySenderAuthMessage(error));
    } finally {
      if (mounted) setState(() => _senderAuthBusy = false);
    }
  }

  Future<void> _signUpSender() async {
    if (_senderAuthBusy) return;
    setState(() {
      _senderAuthBusy = true;
      _senderProfileMessage = 'Creating your Circum profile...';
    });
    try {
      await _ensureFirebaseReady();
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _senderEmail.text.trim(),
        password: _senderPassword.text.trim(),
      );
      final user = credential.user!;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fullName': _senderName.text.trim(),
        'fullname': _senderName.text.trim(),
        'email': user.email,
        'phoneNumber': _senderPhone.text.trim(),
        'role': 'user',
        'roles': ['sender'],
        'userType': 'sender',
        'status': 'active',
        'verificationStatus': user.emailVerified ? 'verified' : 'unverified',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _availableRoles = {CircumRole.sender};
      _attachSender(user);
      await _loadSenderDeliveries(user.uid);
      setState(() => _senderProfileMessage = 'Your sender profile is ready.');
    } on FirebaseAuthException catch (error) {
      setState(() => _senderProfileMessage = _friendlySenderAuthMessage(error));
    } finally {
      if (mounted) setState(() => _senderAuthBusy = false);
    }
  }

  Future<bool> _allowSenderUser(User user) async {
    final roles = await _rolesForSenderUser(user);
    if (!mounted) return false;
    setState(() => _availableRoles = roles);
    if (RoleAccessPolicy.rolesCanAccessSender(roles)) return true;
    final db = FirebaseFirestore.instance;
    final riderDoc = await db.collection('riderProfiles').doc(user.uid).get();
    final adminDoc = await db.collection('adminUsers').doc(user.uid).get();
    if (!roles.contains(CircumRole.rider) &&
        !roles.contains(CircumRole.admin) &&
        !riderDoc.exists &&
        !adminDoc.exists) {
      await db.collection('users').doc(user.uid).set({
        'email': user.email,
        'role': 'user',
        'roles': ['sender'],
        'userType': 'sender',
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() => _availableRoles = {CircumRole.sender});
      return true;
    }
    return false;
  }

  Future<Set<CircumRole>> _rolesForSenderUser(User user) async {
    final token = await user.getIdTokenResult(true);
    final claims = token.claims ?? const <String, dynamic>{};
    final db = FirebaseFirestore.instance;
    final userDoc = await db.collection('users').doc(user.uid).get();
    final riderDoc = await db.collection('riderProfiles').doc(user.uid).get();
    final adminDoc = await db.collection('adminUsers').doc(user.uid).get();
    return RoleAccessPolicy.resolveRoles(
      claims: claims,
      user: userDoc.data() ?? const {},
      rider: riderDoc.data() ?? const {},
      adminUser: adminDoc.data() ?? const {},
    );
  }

  Future<void> _signOutSender() async {
    await FirebaseAuth.instance.signOut();
    await _senderSub?.cancel();
    if (!mounted) return;
    setState(() {
      _senderUser = null;
      _senderProfile = null;
      _senderDeliveries = const [];
      _selectedSenderDelivery = null;
      _availableRoles = const {};
      _roleChoiceConfirmed = false;
      _step = _SenderStep.dashboard;
      _senderProfileMessage = 'Signed out.';
    });
  }

  Future<void> _saveSenderProfile() async {
    final user = _senderUser;
    if (user == null) return;
    setState(() => _senderProfileSaving = true);
    try {
      final profile = _senderProfile ??
          SenderProfile.fromMap(user.uid, {
            'email': user.email,
            'fullName': _senderName.text.trim(),
            'phoneNumber': _senderPhone.text.trim(),
          });
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            profile.safeUpdatePatch(
              fullName: _senderName.text.trim(),
              phoneNumber: _senderPhone.text.trim(),
              savedAddresses: profile.savedAddresses,
              communicationPreferences: profile.communicationPreferences.isEmpty
                  ? const {'email': true, 'sms': true}
                  : profile.communicationPreferences,
            ),
            SetOptions(merge: true),
          );
      setState(() => _senderProfileMessage = 'Profile saved.');
    } catch (_) {
      setState(() => _senderProfileMessage = 'Could not save the profile.');
    } finally {
      if (mounted) setState(() => _senderProfileSaving = false);
    }
  }

  Future<void> _addSenderAddress() async {
    final user = _senderUser;
    final address = _savedAddress.text.trim();
    if (user == null || address.isEmpty) return;
    final next = [
      ...?_senderProfile?.savedAddresses,
      SavedSenderAddress(
        label: _savedAddressLabel.text.trim().isEmpty
            ? 'Saved address'
            : _savedAddressLabel.text.trim(),
        address: address,
        addressType: _savedAddressType,
      ),
    ];
    setState(() => _senderProfileSaving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'savedAddresses':
            next.map((senderAddress) => senderAddress.toJson()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _savedAddress.clear();
      setState(() => _senderProfileMessage = 'Saved address added.');
    } finally {
      if (mounted) setState(() => _senderProfileSaving = false);
    }
  }

  Future<void> _loadSenderDeliveries(String uid) async {
    final db = FirebaseFirestore.instance;
    final snapshots = await Future.wait([
      db.collection('deliveryRequests').where('senderId', isEqualTo: uid).get(),
      db.collection('deliveryRequests').where('userId', isEqualTo: uid).get(),
      db.collection('history').where('userId', isEqualTo: uid).get(),
    ]);
    final byId = <String, SenderDeliveryRecord>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        final record = SenderDeliveryRecord.fromMap(doc.id, doc.data());
        byId[record.requestId] = record;
      }
    }
    final records = SenderProfileService.ownDeliveries(uid, byId.values)
        .toList(growable: false)
      ..sort((a, b) {
        final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
    if (!mounted) return;
    setState(() => _senderDeliveries = records);
  }

  String _friendlySenderAuthMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'email-already-in-use' => 'That email already has a Circum profile.',
      'user-not-found' => 'No Circum profile found for that email.',
      'wrong-password' ||
      'invalid-credential' =>
        'Those sign-in details are not right.',
      'weak-password' => 'Use a stronger password.',
      _ => 'We could not sign you in. Please check the details.',
    };
  }

  Future<void> _analyseRequest() async {
    if (_pickup.text.trim().isEmpty || _dropoff.text.trim().isEmpty) return;
    setState(() => _analyzing = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final senderWeight =
        DeliveryPricing.parseWeightKg(_weight.text, fallbackKg: 0);
    final estimate = _estimateWeightWithIris();
    final decision = _resolvePricingWeight(
      estimate: estimate,
      senderWeightKg: senderWeight > 0 ? senderWeight : null,
    );
    setState(() {
      _senderEnteredWeightKg = senderWeight > 0 ? senderWeight : null;
      _irisEstimatedWeightKg = estimate.weightKg;
      _irisWeightBand = estimate.weightBand;
      _irisWeightConfidence = estimate.confidence;
      _irisWeightExplanation = estimate.explanation;
      _weightVerificationRequired = decision.verificationRequired;
      _weightPricingReason = decision.reason;
      _analyzing = false;
      if (estimate.confidence == 'high' && senderWeight <= 0) {
        _weight.text = _formatWeight(estimate.weightKg);
      }
      _weightMessage = decision.message;
    });
  }

  void _confirmIrisWeight() {
    final estimateWeight = _irisEstimatedWeightKg;
    if (estimateWeight == null || estimateWeight <= 0) return;
    final senderWeight =
        DeliveryPricing.parseWeightKg(_weight.text, fallbackKg: 0);
    final estimate = _IrisWeightEstimate(
      weightKg: estimateWeight,
      weightBand: _irisWeightBand ??
          DeliveryPricing.weightBandFor(estimateWeight).category,
      confidence: _irisWeightConfidence ?? 'low',
      explanation:
          _irisWeightExplanation ?? 'Iris estimate confirmed by sender.',
      packageType: _inferPackageType(),
      requiresVehicleReview: false,
    );
    final decision = _resolvePricingWeight(
      estimate: estimate,
      senderWeightKg: senderWeight > 0 ? senderWeight : null,
    );
    if (decision.weightKg == null) {
      setState(() => _weightMessage = decision.message);
      return;
    }
    if (senderWeight <= 0) {
      _settingWeightFromConfirmation = true;
      _weight.text = _formatWeight(decision.weightKg!);
      _settingWeightFromConfirmation = false;
    }
    _confirmWeight(
      decision.weightKg!,
      source: decision.source,
      reason: decision.reason,
      verificationRequired: decision.verificationRequired,
    );
    setState(() {
      _weightMessage =
          'Confirmed parcel weight: ${_formatWeight(decision.weightKg!)} kg.';
      _step = _SenderStep.vehicle;
    });
  }

  void _confirmWeight(
    double weightKg, {
    required String source,
    String? reason,
    bool verificationRequired = false,
  }) {
    final band = DeliveryPricing.weightBandFor(weightKg).category;
    final recommendedVehicleName =
        DeliveryPricing.recommendedVehicleForWeight(weightKg);
    final recommendedVehicle = _vehicles.firstWhere(
      (vehicle) => vehicle.name == recommendedVehicleName,
      orElse: () => _vehicles.last,
    );
    setState(() {
      _confirmedWeightKg = weightKg;
      _confirmedWeightBand = band;
      _weightSource = source;
      _weightConfirmedAt = DateTime.now();
      _weightPricingReason = reason;
      _weightVerificationRequired = verificationRequired;
      if (!DeliveryPricing.vehicleCanCarryWeight(
        _selectedVehicle.name,
        weightKg,
      )) {
        _selectedVehicle = recommendedVehicle;
      }
      _weightMessage =
          'Confirmed parcel weight: ${_formatWeight(weightKg)} kg.';
    });
  }

  void _handleWeightChanged() {
    if (_settingWeightFromConfirmation || _confirmedWeightKg == null) return;
    final typedWeight =
        DeliveryPricing.parseWeightKg(_weight.text, fallbackKg: 0);
    if ((typedWeight - _confirmedWeightKg!).abs() < 0.01) return;
    if (!mounted) return;
    setState(() {
      _confirmedWeightKg = null;
      _confirmedWeightBand = null;
      _weightSource = null;
      _weightConfirmedAt = null;
      _weightPricingReason = null;
      _weightMessage = 'Confirm parcel weight before payment.';
    });
  }

  _WeightPricingDecision _resolvePricingWeight({
    required _IrisWeightEstimate estimate,
    required double? senderWeightKg,
  }) {
    final hasSenderWeight = senderWeightKg != null && senderWeightKg > 0;
    final irisBand = DeliveryPricing.weightBandFor(estimate.weightKg);
    final senderBand =
        hasSenderWeight ? DeliveryPricing.weightBandFor(senderWeightKg) : null;
    final bandChanged =
        senderBand != null && senderBand.category != irisBand.category;
    final significantDifference = bandChanged;
    final higherWeight = hasSenderWeight
        ? DeliveryPricing.chargeableWeightKg(
            senderWeightKg: senderWeightKg,
            irisWeightKg: estimate.weightKg,
          )
        : estimate.weightKg;
    final higherBand = DeliveryPricing.weightBandFor(higherWeight);

    if (!hasSenderWeight && estimate.confidence == 'low') {
      return const _WeightPricingDecision(
        message: 'Confirm parcel weight before payment.',
        reason: 'Iris confidence is low, so sender weight is required.',
        verificationRequired: true,
      );
    }

    if (estimate.confidence == 'low') {
      return _WeightPricingDecision(
        weightKg: senderWeightKg,
        weightBand: senderBand?.category,
        source: 'manual',
        message: significantDifference
            ? 'Iris is not confident and the details may indicate a different weight band. Confirm your weight to continue; the rider will verify at pickup.'
            : 'Iris confidence is low. Confirm your weight to continue.',
        reason:
            'Low-confidence Iris estimate; sender-confirmed weight used and flagged for pickup verification.',
        verificationRequired: true,
      );
    }

    return _WeightPricingDecision(
      weightKg: higherWeight,
      weightBand: higherBand.category,
      source: estimate.confidence == 'high' &&
              estimate.weightKg >= (senderWeightKg ?? 0)
          ? 'iris_confirmed'
          : 'manual',
      message: significantDifference
          ? 'Iris and your entered weight fall into different pricing checks. Confirm the pricing weight before continuing.'
          : 'Confirm the parcel weight used for pricing before continuing.',
      reason: 'Highest credible weight used for pricing accuracy.',
      verificationRequired: significantDifference,
    );
  }

  _IrisWeightEstimate _estimateWeightWithIris() {
    final text = '${_description.text} ${_pickup.text} ${_dropoff.text}'
        .trim()
        .toLowerCase();
    double estimate = 2;
    var confidence = 'low';
    var packageType = 'Parcel';
    var vehicleReview = false;
    var explanation =
        'Iris could not estimate weight safely from the details provided.';

    if (text.contains('document') ||
        text.contains('letter') ||
        text.contains('passport')) {
      estimate = 0.5;
      confidence = 'high';
      packageType = 'Documents';
      explanation = 'The item sounds like documents or a small envelope.';
    } else if (text.contains('phone') ||
        text.contains('book') ||
        text.contains('clothes') ||
        text.contains('shoe')) {
      estimate = 2;
      confidence = 'medium';
      packageType = 'Small parcel';
      explanation = 'The item sounds like a small parcel.';
    } else if (text.contains('laptop') ||
        text.contains('computer') ||
        text.contains('console')) {
      estimate = 3;
      confidence = 'medium';
      packageType = 'Electronics';
      explanation = 'The item sounds like consumer electronics.';
    } else if (text.contains('box') ||
        text.contains('parcel') ||
        text.contains('package')) {
      estimate = 5;
      confidence = 'medium';
      packageType = 'Boxed parcel';
      explanation =
          'The description suggests a parcel, but exact contents are unclear.';
    } else if (text.contains('chair') ||
        text.contains('tv') ||
        text.contains('furniture') ||
        text.contains('bike')) {
      estimate = 15;
      confidence = 'low';
      packageType = 'Large item';
      vehicleReview = true;
      explanation =
          'The item may be oversized or heavy, so sender confirmation is required.';
    }

    return _IrisWeightEstimate(
      weightKg: estimate,
      weightBand: DeliveryPricing.weightBandFor(estimate).category,
      confidence: confidence,
      explanation: explanation,
      packageType: packageType,
      requiresVehicleReview: vehicleReview,
    );
  }

  String _inferPackageType() {
    final description = _description.text.toLowerCase();
    if (description.contains('document') || description.contains('letter')) {
      return 'Documents';
    }
    if (description.contains('laptop') ||
        description.contains('phone') ||
        description.contains('computer')) {
      return 'Electronics';
    }
    if (description.contains('chair') ||
        description.contains('furniture') ||
        description.contains('bike') ||
        description.contains('tv')) {
      return 'Large item';
    }
    if (description.contains('box')) return 'Boxed parcel';
    return 'Parcel';
  }

  String _formatWeight(double weightKg) {
    return weightKg.truncateToDouble() == weightKg
        ? weightKg.toStringAsFixed(0)
        : weightKg.toStringAsFixed(1);
  }

  Future<void> _confirmPayment() async {
    if (!_hasConfirmedWeight) {
      setState(() {
        _weightMessage = 'Confirm parcel weight before payment.';
        _step = _SenderStep.details;
      });
      return;
    }
    final id =
        'CIR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    setState(() {
      _activeOrderId = id;
      _activeRequestDocId = id;
      _broadcasting = true;
      _statusIndex = 0;
      _firebaseError = null;
      _step = _SenderStep.tracking;
    });

    try {
      await _ensureFirebaseReady();
      final db = FirebaseFirestore.instance;
      final request = _requestPayload(id);
      final senderId = '${request['senderId']}';
      final batch = db.batch();
      batch.set(db.collection('webSenderRequests').doc(id), request);
      batch.set(db.collection('deliveryRequests').doc(id), request);
      batch.set(
          db.collection('chats').doc(id),
          {
            'requestId': id,
            'participants': [senderId, 'circum-support'],
            'lastMessage':
                'Your request is live. Iris is checking nearby riders now.',
            'lastMessageTimestamp': FieldValue.serverTimestamp(),
            'source': 'circum-web',
          },
          SetOptions(merge: true));
      batch.set(db.collection('chats').doc(id).collection('messages').doc(), {
        'requestId': id,
        'senderId': 'circum-support',
        'senderType': 'support',
        'recipientId': senderId,
        'recipientType': 'user',
        'message': 'Your request is live. Iris is checking nearby riders now.',
        'status': 'sent',
        'createdAt': FieldValue.serverTimestamp(),
        'timeStamp': DateTime.now().toIso8601String(),
      });
      await batch.commit();
      _listenToRequest(id);
      _listenToChat(id);
      if (!mounted) return;
      setState(() => _firebaseOnline = true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _firebaseOnline = false;
        _firebaseError =
            'We could not save this delivery just now. Please try again.';
      });
    }
  }

  Future<void> _bookHealthPlus() async {
    if (_healthSubmitting || !_healthConsent) {
      setState(() => _healthMessage =
          'Please confirm the consent box before booking Health+.');
      return;
    }

    final now = DateTime.now();
    final senderId = _senderUser?.uid ?? FirebaseAuth.instance.currentUser?.uid;
    final id = 'HP-${now.millisecondsSinceEpoch.toString().substring(6)}';
    final scheduleId = _healthFrequency == HealthPlusFrequency.oneOff
        ? null
        : 'HPS-${now.millisecondsSinceEpoch.toString().substring(6)}';
    final pickupId =
        'HPP-${now.millisecondsSinceEpoch.toString().substring(6)}';
    final quote = _healthQuote;

    setState(() {
      _healthSubmitting = true;
      _healthMessage = 'Saving your Health+ pickup and preparing payment...';
      _firebaseError = null;
    });

    try {
      await _ensureFirebaseReady();
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final profileRef = db.collection('healthPlusProfiles').doc(id);
      final pickupRef = db.collection('prescriptionPickups').doc(pickupId);

      final profile = {
        'id': id,
        'senderId': senderId,
        'userId': senderId,
        'fullName': _healthName.text.trim(),
        'phoneNumber': _healthPhone.text.trim(),
        'email': _healthEmail.text.trim(),
        'pharmacyAddress': _healthPharmacy.text.trim(),
        'deliveryAddress': _healthDelivery.text.trim(),
        'notes': _healthNotes.text.trim(),
        'consentConfirmed': _healthConsent,
        'source': 'circum-web',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final pickup = {
        'id': pickupId,
        'senderId': senderId,
        'userId': senderId,
        'profileId': id,
        'scheduleId': scheduleId,
        'fullName': _healthName.text.trim(),
        'phoneNumber': _healthPhone.text.trim(),
        'pharmacyAddress': _healthPharmacy.text.trim(),
        'deliveryAddress': _healthDelivery.text.trim(),
        'notes': _healthNotes.text.trim(),
        'preferredPickupTime': _healthPreferredTime.text.trim(),
        'scheduledPickupDate': '',
        'scheduledPickupWindow': _healthPreferredTime.text.trim(),
        'scheduledDropoffDate': '',
        'scheduledDropoffWindow': _healthPreferredTime.text.trim(),
        'frequency': _healthFrequency.value,
        'status': PickupStatus.scheduled.value,
        'price': quote.total,
        'currency': 'GBP',
        'pricingBreakdown': quote.toJson(),
        'type': 'health_plus_prescription_pickup',
        'source': 'circum-web',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      batch.set(profileRef, profile, SetOptions(merge: true));
      batch.set(pickupRef, pickup, SetOptions(merge: true));

      if (scheduleId != null) {
        batch.set(db.collection('recurringPickupSchedules').doc(scheduleId), {
          'id': scheduleId,
          'senderId': senderId,
          'userId': senderId,
          'profileId': id,
          'frequency': _healthFrequency.value,
          'preferredDayTime': _healthPreferredTime.text.trim(),
          'scheduledPickupDate': '',
          'scheduledPickupWindow': _healthPreferredTime.text.trim(),
          'scheduledDropoffDate': '',
          'scheduledDropoffWindow': _healthPreferredTime.text.trim(),
          'customSchedule': _healthCustomSchedule.text.trim(),
          'paused': false,
          'nextPickupAt': _healthPreferredTime.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      batch.set(db.collection('healthPlusPayments').doc(pickupId), {
        'id': pickupId,
        'senderId': senderId,
        'userId': senderId,
        'profileId': id,
        'pickupId': pickupId,
        'amount': quote.total,
        'currency': 'GBP',
        'status': 'pending_secure_checkout',
        'savedPaymentMethod': _healthSavePayment,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(db.collection('healthPlusNotifications').doc(), {
        'senderId': senderId,
        'userId': senderId,
        'profileId': id,
        'pickupId': pickupId,
        'type': 'pickup_scheduled',
        'title': 'Health+ pickup scheduled',
        'body': 'Your prescription pickup has been scheduled.',
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(db.collection('healthPlusUsageEvents').doc(), {
        'type': 'pickup_created',
        'senderId': senderId,
        'userId': senderId,
        'profileId': id,
        'pickupId': pickupId,
        'scheduleId': scheduleId,
        'status': PickupStatus.scheduled.value,
        'amount': quote.total,
        'currency': 'GBP',
        'source': 'circum-web',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      final checkoutUrl = await _createHealthPlusCheckoutSession(
        pickupId: pickupId,
        profileId: id,
        quote: quote,
      );

      if (!mounted) return;
      setState(() {
        _healthProfileId = id;
        _healthScheduleId = scheduleId;
        _healthCheckoutUrl = checkoutUrl;
        _healthPickups.insert(0, pickup);
        _healthPayments.insert(0, {
          'pickupId': pickupId,
          'amount': quote.total,
          'status': checkoutUrl == null
              ? 'pending_secure_checkout'
              : 'checkout_created',
        });
        _healthMessage = checkoutUrl == null
            ? 'Your Health+ pickup is saved. Payment setup is not ready yet.'
            : 'Your Health+ pickup is saved. Payment is ready.';
        _firebaseOnline = true;
      });

      if (checkoutUrl != null) {
        await launchUrl(Uri.parse(checkoutUrl),
            mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _firebaseOnline = false;
        _healthMessage =
            'We could not save the Health+ pickup just now. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _healthSubmitting = false);
    }
  }

  Future<String?> _createHealthPlusCheckoutSession({
    required String pickupId,
    required String profileId,
    required HealthPlusPriceBreakdown quote,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-circum-2797c.cloudfunctions.net/createHealthPlusCheckoutSession',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': pickupId,
          'profileId': profileId,
          'email': _healthEmail.text.trim(),
          'frequency': _healthFrequency.value,
          'priceBreakdown': quote.toJson(),
          'successUrl':
              'https://circum-app-2797c.web.app/?app=sender&health=success',
          'cancelUrl':
              'https://circum-app-2797c.web.app/?app=sender&health=cancelled',
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['checkoutUrl'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openHealthPlusCheckout() async {
    final url = _healthCheckoutUrl;
    if (url == null) {
      setState(() => _healthMessage =
          'Payment is not ready yet. Create or refresh the Health+ booking first.');
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _pauseHealthPlusSchedule() async {
    final scheduleId = _healthScheduleId;
    if (scheduleId == null) {
      setState(() => _healthMessage = 'This Health+ pickup is one-off.');
      return;
    }
    await _ensureFirebaseReady();
    await FirebaseFirestore.instance
        .collection('recurringPickupSchedules')
        .doc(scheduleId)
        .set({
      'paused': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await FirebaseFirestore.instance.collection('healthPlusUsageEvents').add({
      'type': 'recurring_pickup_paused',
      'profileId': _healthProfileId,
      'scheduleId': scheduleId,
      'status': 'paused',
      'source': 'circum-web',
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() => _healthMessage = 'Your repeat Health+ pickup is paused.');
  }

  Future<void> _cancelNextHealthPlusPickup() async {
    if (_healthPickups.isEmpty) return;
    final pickupId = _healthPickups.first['id'] as String?;
    if (pickupId == null) return;
    await _ensureFirebaseReady();
    await FirebaseFirestore.instance
        .collection('prescriptionPickups')
        .doc(pickupId)
        .set({
      'status': PickupStatus.cancelled.value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await FirebaseFirestore.instance.collection('healthPlusUsageEvents').add({
      'type': 'pickup_cancelled',
      'profileId': _healthProfileId,
      'pickupId': pickupId,
      'scheduleId': _healthScheduleId,
      'status': PickupStatus.cancelled.value,
      'source': 'circum-web',
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() {
      _healthPickups.first['status'] = PickupStatus.cancelled.value;
      _healthMessage = 'The next Health+ pickup has been cancelled.';
    });
  }

  Future<void> _adminUpdateHealthPlusStatus(String status) async {
    if (_healthPickups.isEmpty) return;
    final pickupId = _healthPickups.first['id'] as String?;
    if (pickupId == null) return;
    await _ensureFirebaseReady();
    await FirebaseFirestore.instance
        .collection('prescriptionPickups')
        .doc(pickupId)
        .set({
      'status': status,
      'adminUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await FirebaseFirestore.instance.collection('healthPlusUsageEvents').add({
      'type': 'admin_status_updated',
      'profileId': _healthProfileId,
      'pickupId': pickupId,
      'scheduleId': _healthScheduleId,
      'status': status,
      'source': 'circum-web',
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() {
      _healthPickups.first['status'] = status;
      _healthMessage = 'Admin status updated to $status.';
    });
  }

  Map<String, dynamic> _requestPayload(String id) {
    final quote = _quoteBreakdown;
    final senderUser = _senderUser ?? FirebaseAuth.instance.currentUser;
    final senderId = senderUser?.uid ?? 'web-sender';
    final senderName = _senderProfile?.fullName.trim().isNotEmpty == true
        ? _senderProfile!.fullName
        : _senderName.text.trim().isNotEmpty
            ? _senderName.text.trim()
            : senderUser?.displayName ?? 'Web Sender';
    final senderPhone = _senderProfile?.phoneNumber.trim().isNotEmpty == true
        ? _senderProfile!.phoneNumber
        : _senderPhone.text.trim();
    final requestCode = id.replaceAll(RegExp(r'[^0-9]'), '').padLeft(6, '0');
    final pickupGeo = {
      'geopoint': const GeoPoint(51.5245, -0.0754),
      'geohash': 'gcpvn',
    };
    final dropoffGeo = {
      'geopoint': const GeoPoint(51.5054, -0.0235),
      'geohash': 'gcpuv',
    };
    final packageType = _inferPackageType();
    final hasPhoto = false;
    final safeVehicleName = DeliveryPricing.vehicleCanCarryWeight(
      _selectedVehicle.name,
      _confirmedWeightKg ?? 0,
    )
        ? _selectedVehicle.name
        : DeliveryPricing.recommendedVehicleForWeight(_confirmedWeightKg ?? 0);
    final driverPayout = double.parse((quote.total * 0.75).toStringAsFixed(2));
    final driverJobSummary = {
      'pickupDisplay': _pickup.text.trim(),
      'dropoffDisplay': _dropoff.text.trim(),
      'estimatedDistanceMiles': _webQuoteDistanceMiles,
      'estimatedDurationMinutes': 28,
      'scheduledPickupDate': _scheduledPickupDate.text.trim(),
      'scheduledPickupWindow': _scheduledPickupWindow.text.trim(),
      'scheduledDropoffDate': _scheduledDropoffDate.text.trim(),
      'scheduledDropoffWindow': _scheduledDropoffWindow.text.trim(),
      'confirmedWeightKg': _confirmedWeightKg,
      'confirmedWeightBand': _confirmedWeightBand,
      'packageType': packageType,
      'packageDescription': _description.text.trim(),
      'hasPhoto': hasPhoto,
      'photoUrl': null,
      'deliveryInstructions': _description.text.trim(),
      'vehicleType': safeVehicleName,
      'totalFare': quote.total,
      'driverPayout': driverPayout,
      'specialHandlingNotes': _weightVerificationRequired
          ? 'Weight verification required at pickup.'
          : '',
      'serviceType': 'Normal Delivery',
    };
    return {
      'requestId': id,
      'code': requestCode.substring(requestCode.length - 6),
      'pickupAddress': _pickup.text.trim(),
      'dropoffAddress': _dropoff.text.trim(),
      'packageType': packageType,
      'packageDescription': _description.text.trim(),
      'weight': _weight.text.trim(),
      'weightKg': _confirmedWeightKg,
      'irisEstimatedWeightKg': _irisEstimatedWeightKg,
      'irisWeightBand': _irisWeightBand,
      'irisWeightConfidence': _irisWeightConfidence,
      'irisWeightExplanation': _irisWeightExplanation,
      'senderEnteredWeightKg': _senderEnteredWeightKg,
      'confirmedWeightKg': _confirmedWeightKg,
      'confirmedWeightBand': _confirmedWeightBand,
      'declaredWeightKg': _senderEnteredWeightKg,
      'driverReportedWeightKg': null,
      'weightSource': _weightSource,
      'weightConfirmedAt': _weightConfirmedAt == null
          ? null
          : Timestamp.fromDate(_weightConfirmedAt!),
      'weightAccuracyScore': _weightVerificationRequired ? 80 : 100,
      'driverWeightAccuracyScore': null,
      'weightVerificationRequired': _weightVerificationRequired,
      'weightPricingReason': _weightPricingReason,
      'weightDisputeStatus': 'none',
      'driverWeightVerification': {
        'status': 'pending_pickup',
        'options': [
          'weight_appears_correct',
          'weight_appears_heavier',
          'weight_appears_significantly_heavier',
        ],
        'requiresPhotoForMajorIncrease': true,
      },
      'scheduledPickupDate': _scheduledPickupDate.text.trim(),
      'scheduledPickupWindow': _scheduledPickupWindow.text.trim(),
      'scheduledDropoffDate': _scheduledDropoffDate.text.trim(),
      'scheduledDropoffWindow': _scheduledDropoffWindow.text.trim(),
      'weightCategory': _confirmedWeightBand,
      'vehicle': safeVehicleName,
      'preferredVehicle': safeVehicleName.toLowerCase(),
      'vehicleType': safeVehicleName,
      'speed': _selectedSpeed,
      'quote': quote.total,
      'price': quote.total,
      'fare': quote.total,
      'driverPayout': driverPayout,
      'pricingBreakdown': quote.toJson(),
      'requiresManualQuote': quote.requiresManualQuote,
      'currency': 'GBP',
      'status': 'requested',
      'dispatchStatus': 'requested',
      'matchingStatus': 'available',
      'role': 'user',
      'source': 'circum-web',
      'serviceType': 'sender_delivery',
      'jobType': 'parcel_delivery',
      'senderId': senderId,
      'userId': senderId,
      'senderName': senderName,
      'senderEmail': senderUser?.email,
      'appMatchingCompatible': true,
      'driverJobSummary': driverJobSummary,
      'matchingRules': {
        'collection': 'deliveryRequests',
        'availableStatus': 'requested',
        'positionField': 'pickupPosition.geopoint',
        'sortBy': 'distanceFromRider',
        'preferredVehicle': safeVehicleName.toLowerCase(),
        'requiresVerifiedRider': true,
      },
      'pickupDetails': {
        'fullname': senderName,
        'phone': senderPhone,
        'position': pickupGeo,
        'address': _pickup.text.trim(),
        'subAddress': '',
        'locality': 'London',
        'moreInformation': _description.text.trim(),
        'scheduledDate': _scheduledPickupDate.text.trim(),
        'scheduledWindow': _scheduledPickupWindow.text.trim(),
      },
      'dropoffDetails': {
        'fullname': 'Recipient',
        'phone': '',
        'position': dropoffGeo,
        'address': _dropoff.text.trim(),
        'subAddress': '',
        'locality': 'London',
        'moreInformation': '',
        'scheduledDate': _scheduledDropoffDate.text.trim(),
        'scheduledWindow': _scheduledDropoffWindow.text.trim(),
      },
      'pickupPosition': pickupGeo,
      'dropoffPosition': dropoffGeo,
      'pickupLocality': 'London',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _ensureFirebaseReady() async {
    await _ensureCircumFirebaseReady();
  }

  void _listenToRequest(String id) {
    _requestSub?.cancel();
    _requestSub = FirebaseFirestore.instance
        .collection('deliveryRequests')
        .doc(id)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (!mounted || data == null) return;
      final status = '${data['status'] ?? 'requested'}'.toLowerCase();
      final driverId = _driverIdFromRequest(data);
      setState(() {
        _firebaseOnline = true;
        _firebaseError = null;
        _broadcasting = status == 'requested' || status == 'pending';
        _statusIndex = _statusIndexFromFirebase(status);
      });
      if (driverId != null && driverId != _assignedDriverId) {
        _assignedDriverId = driverId;
        _listenToAssignedDriver(driverId, data);
      }
      if (_statusIndexFromFirebase(status) >= 3) {
        _checkExistingDriverRating();
      }
    }, onError: (Object _) {
      if (!mounted) return;
      setState(() {
        _firebaseOnline = false;
        _firebaseError = 'Could not listen to this delivery in Firestore.';
      });
    });
  }

  String? _driverIdFromRequest(Map<String, dynamic> data) {
    for (final key in ['driverId', 'riderId', 'assignedDriverId']) {
      final value = data[key];
      if (value != null && '$value'.trim().isNotEmpty) return '$value';
    }
    return null;
  }

  void _listenToAssignedDriver(
    String driverId,
    Map<String, dynamic> deliveryData,
  ) {
    _driverProfileSub?.cancel();
    _driverPerformanceSub?.cancel();
    _assignedDriverRatingsSub?.cancel();
    final fallback = _driverProfileFromDelivery(driverId, deliveryData);
    setState(() => _assignedDriver = fallback);
    _driverProfileSub = FirebaseFirestore.instance
        .collection('riderProfiles')
        .doc(driverId)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;
      if (snapshot.exists) {
        setState(() {
          _assignedDriver = DriverProfile.fromMap(
            driverId,
            snapshot.data(),
            performance: _assignedDriverMetric,
          );
        });
        return;
      }
      final riderSnapshot = await FirebaseFirestore.instance
          .collection('riders')
          .doc(driverId)
          .get();
      if (!mounted || !riderSnapshot.exists) return;
      setState(() {
        _assignedDriver = DriverProfile.fromMap(
          driverId,
          riderSnapshot.data(),
          performance: _assignedDriverMetric,
        );
      });
    });
    _driverPerformanceSub = FirebaseFirestore.instance
        .collection('driverPerformanceMetrics')
        .doc(driverId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final metric = DriverPerformanceMetric.fromMap(driverId, snapshot.data());
      setState(() {
        _assignedDriverMetric = metric;
        final profile = _assignedDriver;
        if (profile != null) {
          _assignedDriver = DriverProfile.fromMap(
            profile.driverId,
            {
              'fullName': profile.fullName,
              'photoUrl': profile.photoUrl,
              'phoneNumber': profile.phoneNumber,
              'verificationStatus': profile.verificationStatus,
              'driverStatus': profile.status,
              'vehicle': profile.vehicle.toJson(),
            },
            performance: metric,
            recentRatings: profile.recentRatings,
          );
        }
      });
    });
    _assignedDriverRatingsSub = FirebaseFirestore.instance
        .collection('driverRatings')
        .where('driverId', isEqualTo: driverId)
        .limit(6)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final ratings = snapshot.docs
          .map((doc) => DriverRating.fromMap(doc.data()))
          .where((rating) => !rating.hiddenByAdmin)
          .take(3)
          .toList();
      final profile = _assignedDriver;
      if (profile == null) return;
      setState(() {
        _assignedDriver = DriverProfile.fromMap(
          profile.driverId,
          {
            'fullName': profile.fullName,
            'photoUrl': profile.photoUrl,
            'phoneNumber': profile.phoneNumber,
            'verificationStatus': profile.verificationStatus,
            'driverStatus': profile.status,
            'vehicle': profile.vehicle.toJson(),
          },
          performance: _assignedDriverMetric,
          recentRatings: ratings,
        );
      });
    });
  }

  DriverProfile _driverProfileFromDelivery(
    String driverId,
    Map<String, dynamic> data,
  ) {
    return DriverProfile.fromMap(
        driverId,
        {
          'fullName': data['driverName'] ?? data['riderName'] ?? 'Circum rider',
          'phoneNumber': data['driverPhone'] ?? data['riderPhone'] ?? '',
          'vehicleType':
              data['vehicleType'] ?? data['vehicle'] ?? _selectedVehicle.name,
          'vehicleMakeModel': data['vehicleMakeModel'] ?? '',
          'vehicleColour': data['vehicleColour'] ?? '',
          'plateNumber': data['plateNumber'] ?? '',
          'verificationStatus': data['verificationStatus'] ?? 'verified',
        },
        performance: _assignedDriverMetric);
  }

  Future<void> _checkExistingDriverRating() async {
    final requestId = _activeRequestDocId;
    final customerId = _senderUser?.uid;
    if (requestId == null || customerId == null) return;
    final ratingDoc = await FirebaseFirestore.instance
        .collection('driverRatings')
        .doc(DriverRating.documentId(
          deliveryId: requestId,
          customerId: customerId,
        ))
        .get();
    if (!mounted || !ratingDoc.exists) return;
    final rating = DriverRating.fromMap(ratingDoc.data()!);
    setState(() {
      _selectedRating = rating.starRating;
      _ratingFeedback.text = rating.feedbackText;
      _selectedRatingTags = rating.feedbackTags.toSet();
      _ratingSubmitted = true;
      _ratingMessage = 'Thanks. Your rating has been saved.';
    });
  }

  void _toggleRatingTag(String tag) {
    setState(() {
      final next = {..._selectedRatingTags};
      if (next.contains(tag)) {
        next.remove(tag);
      } else {
        next.add(tag);
      }
      _selectedRatingTags = next;
    });
  }

  Future<void> _submitDriverRating() async {
    final requestId = _activeRequestDocId;
    final driverId = _assignedDriverId ?? _assignedDriver?.driverId;
    final customerId = _senderUser?.uid;
    if (_ratingSubmitting || _ratingSubmitted) return;
    if (requestId == null ||
        driverId == null ||
        customerId == null ||
        _statusIndex < 3) {
      setState(() => _ratingMessage =
          'You can rate the rider after delivery is complete.');
      return;
    }
    if (_selectedRating < 1 || _selectedRating > 5) {
      setState(() => _ratingMessage = 'Choose a star rating first.');
      return;
    }
    setState(() {
      _ratingSubmitting = true;
      _ratingMessage = 'Saving your rating...';
    });

    try {
      final db = FirebaseFirestore.instance;
      final ratingId = DriverRating.documentId(
        deliveryId: requestId,
        customerId: customerId,
      );
      final ratingRef = db.collection('driverRatings').doc(ratingId);
      await db.runTransaction((transaction) async {
        final existing = await transaction.get(ratingRef);
        if (existing.exists) {
          throw StateError('duplicate-rating');
        }
        transaction.set(ratingRef, {
          'ratingId': ratingId,
          'driverId': driverId,
          'customerId': customerId,
          'deliveryId': requestId,
          'tripId': requestId,
          'starRating': _selectedRating,
          'feedbackText': _ratingFeedback.text.trim(),
          'feedbackTags': _selectedRatingTags.toList(),
          'hiddenByAdmin': false,
          'source': 'circum-web',
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(
          db.collection('deliveryRequests').doc(requestId),
          {
            'driverRatingId': ratingId,
            'driverRatedByCustomer': true,
            'ratedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      await _recalculateDriverPerformance(driverId);
      if (!mounted) return;
      setState(() {
        _ratingSubmitted = true;
        _ratingMessage = 'Thanks. Your rating has been saved.';
      });
    } on StateError {
      if (!mounted) return;
      setState(() {
        _ratingSubmitted = true;
        _ratingMessage = 'This delivery has already been rated.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(
          () => _ratingMessage = 'We could not save the rating. Try again.');
    } finally {
      if (mounted) setState(() => _ratingSubmitting = false);
    }
  }

  Future<void> _recalculateDriverPerformance(String driverId) async {
    final db = FirebaseFirestore.instance;
    final ratingsSnapshot = await db
        .collection('driverRatings')
        .where('driverId', isEqualTo: driverId)
        .get();
    final ratings = ratingsSnapshot.docs
        .map((doc) => DriverRating.fromMap(doc.data()))
        .toList();
    final completedIds = <String>{};
    for (final driverField in ['riderId', 'driverId', 'assignedDriverId']) {
      final completedSnapshot = await db
          .collection('deliveryRequests')
          .where(driverField, isEqualTo: driverId)
          .where('status', isEqualTo: 'completed')
          .get();
      completedIds.addAll(completedSnapshot.docs.map((doc) => doc.id));
    }
    final complaints = ratings.where((rating) => rating.isComplaint).length;
    final metric = DriverPerformanceService.calculate(
      DriverPerformanceInput(
        driverId: driverId,
        ratings: ratings,
        completedTrips:
            completedIds.isEmpty ? ratings.length : completedIds.length,
        complaints: complaints,
      ),
    );
    await db.collection('driverPerformanceMetrics').doc(driverId).set({
      ...metric.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lowRatingFlag':
          DriverPerformanceService.shouldFlagLowRatedDriver(metric),
    }, SetOptions(merge: true));
    await db.collection('riderProfiles').doc(driverId).set({
      'averageRating': metric.averageRating,
      'totalRatings': metric.totalRatings,
      'completedTrips': metric.completedTrips,
      'driverStatus': metric.driverStatus,
      'qualityScore': metric.qualityScore,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await db.collection('riders').doc(driverId).set({
      'rating': metric.averageRating.toStringAsFixed(2),
      'driverStatus': metric.driverStatus,
      'qualityScore': metric.qualityScore,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _listenToChat(String id) {
    _chatSub?.cancel();
    _chatSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(id)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final driverMessages = <_ChatMessage>[];
      final supportMessages = <_ChatMessage>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final senderType = '${data['senderType'] ?? 'support'}';
        final message = '${data['message'] ?? ''}'.trim();
        if (message.isEmpty) continue;
        final chatMessage = _ChatMessage(
          fromMe: senderType == 'user',
          text: message,
          time: _formatMessageTime(data['createdAt'], data['timeStamp']),
        );
        if (senderType == 'rider' || senderType == 'driver') {
          driverMessages.add(chatMessage);
        } else {
          supportMessages.add(chatMessage);
        }
      }
      setState(() {
        _driverMessages
          ..clear()
          ..addAll(driverMessages.isEmpty
              ? [
                  const _ChatMessage(
                    fromMe: false,
                    text: 'Rider chat will open when someone accepts the job.',
                    time: 'Now',
                  )
                ]
              : driverMessages);
        _supportMessages
          ..clear()
          ..addAll(supportMessages.isEmpty
              ? [
                  const _ChatMessage(
                    fromMe: false,
                    text: "Hi, this is Iris. How can we help?",
                    time: 'Now',
                  )
                ]
              : supportMessages);
      });
    });
  }

  int _statusIndexFromFirebase(String status) {
    if (status.contains('delivered') || status.contains('complete')) return 3;
    if (status.contains('picked') || status.contains('collected')) return 2;
    if (status.contains('accepted') ||
        status.contains('assigned') ||
        status.contains('transit')) {
      return 1;
    }
    return 0;
  }

  String _formatMessageTime(dynamic timestamp, dynamic fallback) {
    DateTime? date;
    if (timestamp is Timestamp) date = timestamp.toDate();
    if (date == null && fallback is String) {
      date = DateTime.tryParse(fallback);
    }
    if (date == null) return 'Now';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _sendMessage() async {
    final text = _chatInput.text.trim();
    final requestId = _activeRequestDocId;
    if (text.isEmpty) return;
    _chatInput.clear();
    setState(() {
      final target = _supportChat ? _supportMessages : _driverMessages;
      target.add(_ChatMessage(fromMe: true, text: text, time: 'Now'));
    });

    if (requestId == null) return;
    try {
      await _ensureFirebaseReady();
      final db = FirebaseFirestore.instance;
      final chatRef = db.collection('chats').doc(requestId);
      await chatRef.collection('messages').add({
        'requestId': requestId,
        'senderId': 'web-sender',
        'senderType': 'user',
        'recipientId': _supportChat ? 'circum-support' : 'assigned-rider',
        'recipientType': _supportChat ? 'support' : 'rider',
        'message': text,
        'status': 'sent',
        'createdAt': FieldValue.serverTimestamp(),
        'timeStamp': DateTime.now().toIso8601String(),
      });
      await chatRef.set({
        'requestId': requestId,
        'lastMessage': text,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'participants': [
          'web-sender',
          _supportChat ? 'circum-support' : 'assigned-rider'
        ],
        'source': 'circum-web',
      }, SetOptions(merge: true));
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _firebaseError = 'Message could not be sent. Please try again.');
    }
  }

  void _reset() {
    _requestSub?.cancel();
    _chatSub?.cancel();
    _driverProfileSub?.cancel();
    _driverPerformanceSub?.cancel();
    _assignedDriverRatingsSub?.cancel();
    setState(() {
      _step = _SenderStep.dashboard;
      _activeOrderId = null;
      _activeRequestDocId = null;
      _assignedDriverId = null;
      _assignedDriver = null;
      _assignedDriverMetric = null;
      _statusIndex = 0;
      _broadcasting = false;
      _selectedRating = 0;
      _selectedRatingTags = {};
      _ratingFeedback.clear();
      _ratingSubmitted = false;
      _ratingMessage = null;
      _firebaseError = null;
    });
  }
}

class _DesktopPortalLayout extends StatelessWidget {
  final _CircumColors colors;
  final String pickup;
  final String dropoff;
  final _VehicleOption vehicle;
  final String speed;
  final double weightKg;
  final DeliveryPricingBreakdown breakdown;
  final _SenderStep step;
  final bool firebaseOnline;
  final String? firebaseError;
  final int statusIndex;
  final Widget child;

  const _DesktopPortalLayout({
    required this.colors,
    required this.pickup,
    required this.dropoff,
    required this.vehicle,
    required this.speed,
    required this.weightKg,
    required this.breakdown,
    required this.step,
    required this.firebaseOnline,
    required this.firebaseError,
    required this.statusIndex,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final status = _trackingStatuses[
        statusIndex.clamp(0, _trackingStatuses.length - 1).toInt()];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: MediaQuery.sizeOf(context).width >= 1100 ? 560 : 430,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 28, 24, 36),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: child,
            ),
          ),
        ),
        Container(width: 1, color: colors.border),
        Expanded(
          child: Container(
            color: colors.field.withOpacity(colors.dark ? 0.22 : 0.38),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Live delivery',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _StepBadge(colors: colors, step: step),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'See the route, price, rider match, and delivery status in one place.',
                    style: TextStyle(
                      color: colors.mutedText,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 22),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: _MiniMap(colors: colors, active: true),
                  ),
                  const SizedBox(height: 20),
                  _GlassPanel(
                    colors: colors,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _RouteLine(
                          colors: colors,
                          icon: Icons.radio_button_checked,
                          label: 'Pickup',
                          value: pickup.isEmpty ? 'Pickup location' : pickup,
                          iconColor: const Color(0xff2563eb),
                        ),
                        const SizedBox(height: 14),
                        _RouteLine(
                          colors: colors,
                          icon: Icons.location_on,
                          label: 'Drop-off',
                          value:
                              dropoff.isEmpty ? 'Drop-off location' : dropoff,
                          iconColor: const Color(0xff22c55e),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _GlassPanel(
                    colors: colors,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Price breakdown',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _PriceLine(
                          colors: colors,
                          label: 'Base fare',
                          value: '£${breakdown.baseFare.toStringAsFixed(2)}',
                        ),
                        _PriceLine(
                          colors: colors,
                          label: 'Distance fare',
                          value:
                              '£${breakdown.distanceFare.toStringAsFixed(2)}',
                        ),
                        _PriceLine(
                          colors: colors,
                          label:
                              '${breakdown.weightCategory} (${_formatWeight(weightKg)} kg)',
                          value:
                              '£${breakdown.weightSurcharge.toStringAsFixed(2)}',
                        ),
                        _PriceLine(
                          colors: colors,
                          label: '${vehicle.name} vehicle',
                          value:
                              '£${breakdown.vehicleSurcharge.toStringAsFixed(2)}',
                        ),
                        if (breakdown.specialConditions > 0)
                          _PriceLine(
                            colors: colors,
                            label: speed == 'Express'
                                ? 'Special conditions incl. express'
                                : 'Special conditions',
                            value:
                                '£${breakdown.specialConditions.toStringAsFixed(2)}',
                          ),
                        Divider(color: colors.border, height: 24),
                        _PriceLine(
                          colors: colors,
                          label: 'Total',
                          value: breakdown.requiresManualQuote
                              ? 'Manual quote'
                              : '£${breakdown.total.toStringAsFixed(2)}',
                          strong: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _FirebaseStatusBanner(
                    colors: colors,
                    online: firebaseOnline,
                    error: firebaseError,
                  ),
                  const SizedBox(height: 18),
                  _GlassPanel(
                    colors: colors,
                    child: Row(
                      children: [
                        Icon(Icons.radar, color: colors.text),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                status.title,
                                style: TextStyle(
                                  color: colors.text,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                status.body,
                                style: TextStyle(
                                  color: colors.mutedText,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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
    );
  }

  static String _formatWeight(double weightKg) {
    return weightKg.truncateToDouble() == weightKg
        ? weightKg.toStringAsFixed(0)
        : weightKg.toStringAsFixed(1);
  }
}

class _StepBadge extends StatelessWidget {
  final _CircumColors colors;
  final _SenderStep step;

  const _StepBadge({required this.colors, required this.step});

  @override
  Widget build(BuildContext context) {
    final label = switch (step) {
      _SenderStep.dashboard => 'Dashboard',
      _SenderStep.details => 'Details',
      _SenderStep.vehicle => 'Vehicle',
      _SenderStep.payment => 'Payment',
      _SenderStep.tracking => 'Tracking',
      _SenderStep.healthPlus => 'Health+',
      _SenderStep.profile => 'Profile',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.text,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.inverseText,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  const _RouteLine({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SenderAccessGate extends StatelessWidget {
  final _CircumColors colors;
  final bool signupMode;
  final bool busy;
  final String? message;
  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController fullName;
  final TextEditingController phone;
  final VoidCallback onToggleMode;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;

  const _SenderAccessGate({
    required this.colors,
    required this.signupMode,
    required this.busy,
    required this.message,
    required this.email,
    required this.password,
    required this.fullName,
    required this.phone,
    required this.onToggleMode,
    required this.onSignIn,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(
                colors: colors,
                title: signupMode ? 'Create a sender account' : 'Sender login',
              ),
              const SizedBox(height: 8),
              Text(
                signupMode
                    ? 'Create your account first. Then you can book parcels, see history, save addresses, and talk to support.'
                    : 'Sign in to send parcels, track jobs, manage payments, and view your Circum history.',
                style: TextStyle(
                  color: colors.mutedText,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              if (signupMode) ...[
                _InputBox(
                    colors: colors, controller: fullName, hint: 'Full name'),
                const SizedBox(height: 10),
                _InputBox(
                    colors: colors, controller: phone, hint: 'Phone number'),
                const SizedBox(height: 10),
              ],
              _InputBox(
                  colors: colors, controller: email, hint: 'Email address'),
              const SizedBox(height: 10),
              _InputBox(
                colors: colors,
                controller: password,
                hint: 'Password',
                obscureText: true,
              ),
              if (message != null) ...[
                const SizedBox(height: 12),
                Text(
                  message!,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy
                          ? null
                          : signupMode
                              ? onSignUp
                              : onSignIn,
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open),
                      label: Text(
                        busy
                            ? 'Please wait'
                            : signupMode
                                ? 'Create account'
                                : 'Sign in',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.text,
                        foregroundColor: colors.inverseText,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: busy ? null : onToggleMode,
                    child: Text(signupMode ? 'Sign in' : 'Sign up'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MultiRoleChoicePanel extends StatelessWidget {
  final _CircumColors colors;
  final Set<CircumRole> roles;
  final VoidCallback onSender;
  final VoidCallback onRider;
  final VoidCallback onAdmin;

  const _MultiRoleChoicePanel({
    required this.colors,
    required this.roles,
    required this.onSender,
    required this.onRider,
    required this.onAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Choose how to continue'),
              const SizedBox(height: 8),
              Text(
                'This account has more than one Circum role. Pick the workspace you want for now.',
                style: TextStyle(
                  color: colors.mutedText,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              if (roles.contains(CircumRole.sender))
                _RoleChoiceButton(
                  colors: colors,
                  icon: Icons.inventory_2_outlined,
                  label: 'Continue as Sender',
                  onTap: onSender,
                ),
              if (roles.contains(CircumRole.rider)) ...[
                const SizedBox(height: 10),
                _RoleChoiceButton(
                  colors: colors,
                  icon: Icons.delivery_dining,
                  label: 'Continue as Rider',
                  onTap: onRider,
                ),
              ],
              if (roles.contains(CircumRole.admin)) ...[
                const SizedBox(height: 10),
                _RoleChoiceButton(
                  colors: colors,
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Continue as Admin',
                  onTap: onAdmin,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChoiceButton extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RoleChoiceButton({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: colors.text,
          foregroundColor: colors.inverseText,
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}

class _SavedAddressQuickPick extends StatelessWidget {
  final _CircumColors colors;
  final List<SavedSenderAddress> addresses;
  final String addressType;
  final ValueChanged<String> onSelect;

  const _SavedAddressQuickPick({
    required this.colors,
    required this.addresses,
    required this.addressType,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final matching = addresses
        .where((address) => addressType == 'pickup'
            ? address.addressType != 'dropoff'
            : address.addressType == 'dropoff')
        .toList(growable: false);
    if (matching.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: matching
            .map(
              (address) => ActionChip(
                avatar:
                    Icon(Icons.place_outlined, color: colors.text, size: 16),
                label: Text(address.label),
                onPressed: () => onSelect(address.address),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _WeightConfirmationPanel extends StatelessWidget {
  final _CircumColors colors;
  final double? estimatedWeightKg;
  final String? weightBand;
  final String? confidence;
  final String? explanation;
  final double? senderEnteredWeightKg;
  final double? pricingWeightKg;
  final String? pricingReason;
  final bool verificationRequired;
  final String message;
  final VoidCallback onConfirm;

  const _WeightConfirmationPanel({
    required this.colors,
    required this.estimatedWeightKg,
    required this.weightBand,
    required this.confidence,
    required this.explanation,
    required this.senderEnteredWeightKg,
    required this.pricingWeightKg,
    required this.pricingReason,
    required this.verificationRequired,
    required this.message,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final canConfirm = pricingWeightKg != null && pricingWeightKg! > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
          ),
          if (estimatedWeightKg != null) ...[
            const SizedBox(height: 6),
            Text(
              'Iris estimate: ${estimatedWeightKg!.toStringAsFixed(estimatedWeightKg!.truncateToDouble() == estimatedWeightKg ? 0 : 1)} kg'
              '${weightBand == null ? '' : ' · $weightBand'}'
              '${confidence == null ? '' : ' · $confidence confidence'}',
              style: TextStyle(color: colors.mutedText, height: 1.35),
            ),
          ],
          if (senderEnteredWeightKg != null) ...[
            const SizedBox(height: 4),
            Text(
              'Your weight: ${senderEnteredWeightKg!.toStringAsFixed(senderEnteredWeightKg!.truncateToDouble() == senderEnteredWeightKg ? 0 : 1)} kg',
              style: TextStyle(color: colors.mutedText, height: 1.35),
            ),
          ],
          if (pricingWeightKg != null) ...[
            const SizedBox(height: 4),
            Text(
              'Weight used for pricing: ${pricingWeightKg!.toStringAsFixed(pricingWeightKg!.truncateToDouble() == pricingWeightKg ? 0 : 1)} kg',
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
            ),
          ],
          if (explanation != null && explanation!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              explanation!,
              style: TextStyle(color: colors.mutedText, height: 1.35),
            ),
          ],
          if (pricingReason != null && pricingReason!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Reason: $pricingReason',
              style: TextStyle(color: colors.mutedText, height: 1.35),
            ),
          ],
          if (verificationRequired) ...[
            const SizedBox(height: 6),
            Text(
              'Rider will verify weight at pickup.',
              style:
                  TextStyle(color: colors.warning, fontWeight: FontWeight.w800),
            ),
          ],
          if (canConfirm) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Accept pricing weight'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SenderDashboardStep extends StatelessWidget {
  final _CircumColors colors;
  final SenderProfile? profile;
  final List<SenderDeliveryRecord> deliveries;
  final VoidCallback onSendParcel;
  final VoidCallback onHealthPlus;
  final VoidCallback onProfile;
  final VoidCallback onSupport;

  const _SenderDashboardStep({
    super.key,
    required this.colors,
    required this.profile,
    required this.deliveries,
    required this.onSendParcel,
    required this.onHealthPlus,
    required this.onProfile,
    required this.onSupport,
  });

  @override
  Widget build(BuildContext context) {
    final summary = SenderProfileService.summarize(deliveries);
    final firstName = (profile?.fullName ?? '').trim().split(' ').first;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GlassPanel(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstName.isEmpty ? 'What are you sending?' : 'Hi $firstName',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Book a parcel, check a past delivery, or update your sender details.',
                  style: TextStyle(
                    color: colors.mutedText,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: onSendParcel,
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Send a parcel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onHealthPlus,
                      icon: const Icon(Icons.local_pharmacy_outlined),
                      label: const Text('Health+ pickup'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: MediaQuery.sizeOf(context).width < 720 ? 2 : 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.5,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _MetricPill(
                colors: colors,
                label: 'Completed',
                value: '${summary.completedDeliveries}',
              ),
              _MetricPill(
                colors: colors,
                label: 'Parcels',
                value: '${summary.totalDeliveries}',
              ),
              _MetricPill(
                colors: colors,
                label: 'Spent',
                value: '£${summary.lifetimeValue.toStringAsFixed(2)}',
              ),
              _MetricPill(
                colors: colors,
                label: 'Account',
                value: summary.loyaltyLevel,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _GlassPanel(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(colors: colors, title: 'Next steps'),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_outline, color: colors.text),
                  title: Text('Profile and saved addresses',
                      style: TextStyle(
                          color: colors.text, fontWeight: FontWeight.w900)),
                  subtitle: Text(
                      'Keep pickup details ready for faster booking.',
                      style: TextStyle(color: colors.mutedText)),
                  onTap: onProfile,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.support_agent, color: colors.text),
                  title: Text('Support',
                      style: TextStyle(
                          color: colors.text, fontWeight: FontWeight.w900)),
                  subtitle: Text('Ask Circum for help with a delivery.',
                      style: TextStyle(color: colors.mutedText)),
                  onTap: onSupport,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SenderProfileStep extends StatelessWidget {
  final _CircumColors colors;
  final User? user;
  final SenderProfile? profile;
  final List<SenderDeliveryRecord> deliveries;
  final SenderDeliveryRecord? selectedDelivery;
  final bool loading;
  final bool busy;
  final String? message;
  final int tabIndex;
  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController fullName;
  final TextEditingController phone;
  final TextEditingController savedAddressLabel;
  final TextEditingController savedAddress;
  final String savedAddressType;
  final VoidCallback onBack;
  final ValueChanged<int> onTab;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final VoidCallback onSignOut;
  final VoidCallback onSaveProfile;
  final VoidCallback onAddAddress;
  final ValueChanged<String> onSavedAddressType;
  final ValueChanged<SenderDeliveryRecord> onSelectDelivery;
  final VoidCallback onCloseDelivery;

  const _SenderProfileStep({
    super.key,
    required this.colors,
    required this.user,
    required this.profile,
    required this.deliveries,
    required this.selectedDelivery,
    required this.loading,
    required this.busy,
    required this.message,
    required this.tabIndex,
    required this.email,
    required this.password,
    required this.fullName,
    required this.phone,
    required this.savedAddressLabel,
    required this.savedAddress,
    required this.savedAddressType,
    required this.onBack,
    required this.onTab,
    required this.onSignIn,
    required this.onSignUp,
    required this.onSignOut,
    required this.onSaveProfile,
    required this.onAddAddress,
    required this.onSavedAddressType,
    required this.onSelectDelivery,
    required this.onCloseDelivery,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (user == null) {
      return _GlassPanel(
        colors: colors,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(colors: colors, title: 'Your Circum profile'),
            const SizedBox(height: 8),
            Text(
              'Sign in to see parcel history, saved addresses, payments, reviews, and support notes.',
              style: TextStyle(color: colors.mutedText, height: 1.45),
            ),
            const SizedBox(height: 18),
            _InputBox(colors: colors, controller: fullName, hint: 'Full name'),
            const SizedBox(height: 10),
            _InputBox(colors: colors, controller: phone, hint: 'Phone number'),
            const SizedBox(height: 10),
            _InputBox(colors: colors, controller: email, hint: 'Email address'),
            const SizedBox(height: 10),
            _InputBox(
              colors: colors,
              controller: password,
              hint: 'Password',
              obscureText: true,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: busy ? null : onSignIn,
                  icon: const Icon(Icons.login),
                  label: Text(busy ? 'Please wait' : 'Sign in'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onSignUp,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Create profile'),
                ),
              ],
            ),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message!, style: TextStyle(color: colors.mutedText)),
            ],
          ],
        ),
      );
    }

    final summary = SenderProfileService.summarize(deliveries);
    final tabs = const [
      'Profile',
      'Delivery History',
      'Saved Addresses',
      'Payments',
      'Reviews',
      'Support',
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GlassPanel(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: colors.field,
                      backgroundImage: (profile?.photoUrl.isNotEmpty == true)
                          ? NetworkImage(profile!.photoUrl)
                          : null,
                      child: profile?.photoUrl.isNotEmpty == true
                          ? null
                          : Icon(Icons.person, color: colors.text),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile?.fullName.isNotEmpty == true
                                ? profile!.fullName
                                : user!.email ?? 'Circum sender',
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${profile?.verificationStatus ?? 'unverified'} account',
                            style: TextStyle(color: colors.mutedText),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Back to sending',
                      onPressed: onBack,
                      icon: Icon(Icons.close, color: colors.text),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount:
                      MediaQuery.sizeOf(context).width < 720 ? 2 : 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.55,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _MetricPill(
                      colors: colors,
                      label: 'Completed',
                      value: '${summary.completedDeliveries}',
                    ),
                    _MetricPill(
                      colors: colors,
                      label: 'All parcels',
                      value: '${summary.totalDeliveries}',
                    ),
                    _MetricPill(
                      colors: colors,
                      label: 'Spent',
                      value: '£${summary.lifetimeValue.toStringAsFixed(2)}',
                    ),
                    _MetricPill(
                      colors: colors,
                      label: 'Status',
                      value: summary.loyaltyLevel,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(tabs.length, (index) {
                final selected = tabIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selected,
                    onSelected: (_) => onTab(index),
                    label: Text(tabs[index]),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(message!, style: TextStyle(color: colors.mutedText)),
            ),
          _GlassPanel(colors: colors, child: _tabBody(context, summary)),
        ],
      ),
    );
  }

  Widget _tabBody(BuildContext context, SenderProfileSummary summary) {
    if (selectedDelivery != null) {
      return _SenderDeliveryDetails(
        colors: colors,
        delivery: selectedDelivery!,
        onClose: onCloseDelivery,
      );
    }
    return switch (tabIndex) {
      0 => _profileTab(summary),
      1 => _historyTab(),
      2 => _addressesTab(),
      3 => _paymentsTab(),
      4 => _reviewsTab(),
      _ => _supportTab(),
    };
  }

  Widget _profileTab(SenderProfileSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(colors: colors, title: 'Profile details'),
        const SizedBox(height: 12),
        _InputBox(colors: colors, controller: fullName, hint: 'Full name'),
        const SizedBox(height: 10),
        _InputBox(colors: colors, controller: phone, hint: 'Phone number'),
        const SizedBox(height: 10),
        _InputBox(
            colors: colors, controller: email, hint: 'Email', enabled: false),
        const SizedBox(height: 12),
        Text(
          'Created ${_readableDate(profile?.createdAt)}. ${summary.loyaltyLevel}.',
          style: TextStyle(color: colors.mutedText),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: busy ? null : onSaveProfile,
          icon: const Icon(Icons.save_outlined),
          label: Text(busy ? 'Saving' : 'Save profile'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }

  Widget _historyTab() {
    if (deliveries.isEmpty) {
      return _empty('No parcels yet',
          'When you send with Circum, your parcel history will appear here.');
    }
    return Column(
      children: deliveries
          .map(
            (delivery) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                delivery.parcelDescription,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(
                '${delivery.pickupAddress} to ${delivery.dropoffAddress}\n${_readableDate(delivery.createdAt)}',
                style: TextStyle(color: colors.mutedText),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '£${delivery.pricePaid.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(delivery.status,
                      style: TextStyle(color: colors.mutedText, fontSize: 12)),
                ],
              ),
              onTap: () => onSelectDelivery(delivery),
            ),
          )
          .toList(),
    );
  }

  Widget _addressesTab() {
    final addresses = profile?.savedAddresses ?? const <SavedSenderAddress>[];
    final pickupAddresses =
        addresses.where((address) => address.addressType != 'dropoff');
    final dropoffAddresses =
        addresses.where((address) => address.addressType == 'dropoff');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(colors: colors, title: 'Saved locations'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _savedLabelValue(savedAddressLabel.text),
          dropdownColor: colors.field,
          decoration: InputDecoration(
            labelText: 'Label',
            labelStyle: TextStyle(color: colors.mutedText),
            filled: true,
            fillColor: colors.field,
            border: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
          items: const ['Home', 'Work', 'Custom']
              .map(
                  (label) => DropdownMenuItem(value: label, child: Text(label)))
              .toList(),
          onChanged: (label) {
            if (label != null) savedAddressLabel.text = label;
          },
        ),
        if (_savedLabelValue(savedAddressLabel.text) == 'Custom') ...[
          const SizedBox(height: 10),
          _InputBox(
            colors: colors,
            controller: savedAddressLabel,
            hint: 'Custom label',
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              selected: savedAddressType == 'pickup',
              label: const Text('Pickup'),
              onSelected: (_) => onSavedAddressType('pickup'),
            ),
            ChoiceChip(
              selected: savedAddressType == 'dropoff',
              label: const Text('Drop-off'),
              onSelected: (_) => onSavedAddressType('dropoff'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _InputBox(
          colors: colors,
          controller: savedAddress,
          hint: savedAddressType == 'dropoff'
              ? 'Drop-off address'
              : 'Pickup address',
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: busy ? null : onAddAddress,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add address'),
        ),
        const SizedBox(height: 16),
        if (addresses.isEmpty)
          _empty('No saved locations', 'Add regular spots to book faster.')
        else ...[
          if (pickupAddresses.isNotEmpty) ...[
            _SectionTitle(colors: colors, title: 'Pickup favourites'),
            const SizedBox(height: 8),
            ...pickupAddresses.map(_savedAddressTile),
          ],
          if (dropoffAddresses.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionTitle(colors: colors, title: 'Drop-off favourites'),
            const SizedBox(height: 8),
            ...dropoffAddresses.map(_savedAddressTile),
          ],
        ],
      ],
    );
  }

  String _savedLabelValue(String label) {
    final normalized = label.trim();
    if (normalized == 'Home' || normalized == 'Work') return normalized;
    return 'Custom';
  }

  Widget _savedAddressTile(SavedSenderAddress address) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.place_outlined, color: colors.text),
      title: Text(
        address.label,
        style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
      ),
      subtitle:
          Text(address.address, style: TextStyle(color: colors.mutedText)),
    );
  }

  Widget _paymentsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(colors: colors, title: 'Payments'),
        const SizedBox(height: 10),
        Text(
          profile?.paymentCustomerReference ??
              'No saved payment profile is attached yet.',
          style: TextStyle(color: colors.mutedText, height: 1.4),
        ),
        const SizedBox(height: 10),
        Text(
          'Only safe payment references are shown here. Card numbers and security codes are never stored in Circum profiles.',
          style: TextStyle(color: colors.mutedText, height: 1.4),
        ),
      ],
    );
  }

  Widget _reviewsTab() {
    final rated = deliveries.where((delivery) => delivery.ratingGiven != null);
    if (rated.isEmpty) {
      return _empty('No reviews yet',
          'Ratings you leave after completed deliveries will show here.');
    }
    return Column(
      children: rated
          .map(
            (delivery) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.star, color: Colors.amber.shade700),
              title: Text('${delivery.ratingGiven} stars',
                  style: TextStyle(
                      color: colors.text, fontWeight: FontWeight.w900)),
              subtitle: Text(delivery.requestId,
                  style: TextStyle(color: colors.mutedText)),
            ),
          )
          .toList(),
    );
  }

  Widget _supportTab() {
    final notes = deliveries.expand((delivery) => delivery.supportNotes);
    if (notes.isEmpty) {
      return _empty('No support notes',
          'If anything needs attention, Circum support notes will sit here.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: notes
          .map((note) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('$note', style: TextStyle(color: colors.text)),
              ))
          .toList(),
    );
  }

  Widget _empty(String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: colors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(body, style: TextStyle(color: colors.mutedText, height: 1.45)),
        ],
      ),
    );
  }
}

class _SenderDeliveryDetails extends StatelessWidget {
  final _CircumColors colors;
  final SenderDeliveryRecord delivery;
  final VoidCallback onClose;

  const _SenderDeliveryDetails({
    required this.colors,
    required this.delivery,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final rows = {
      'Tracking reference': delivery.trackingReference,
      'Status': delivery.status,
      'Pickup': delivery.pickupAddress,
      'Drop-off': delivery.dropoffAddress,
      'Date sent': _readableDate(delivery.createdAt),
      'Driver': delivery.assignedDriverName.isEmpty
          ? 'Not assigned yet'
          : delivery.assignedDriverName,
      'Payment':
          '${delivery.paymentStatus} · £${delivery.pricePaid.toStringAsFixed(2)}',
      'Rating': delivery.ratingGiven == null
          ? 'Not rated yet'
          : '${delivery.ratingGiven} stars',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _SectionTitle(
                colors: colors,
                title: delivery.requestId,
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              icon: Icon(Icons.close, color: colors.text),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...rows.entries.map(
          (row) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.key.toUpperCase(),
                    style: TextStyle(
                        color: colors.mutedText,
                        fontSize: 10,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(row.value,
                    style: TextStyle(
                        color: colors.text, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
        if (delivery.proofOfDelivery.isNotEmpty)
          Text('Proof of delivery is attached.',
              style: TextStyle(color: colors.mutedText)),
      ],
    );
  }
}

String _readableDate(DateTime? date) {
  if (date == null) return 'not recorded yet';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

class _PortalHeader extends StatelessWidget {
  final _CircumColors colors;
  final bool darkMode;
  final VoidCallback onBack;
  final VoidCallback onToggleTheme;
  final VoidCallback? onProfile;

  const _PortalHeader({
    required this.colors,
    required this.darkMode,
    required this.onBack,
    required this.onToggleTheme,
    this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(
          color: colors.appBackground.withOpacity(0.95),
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: Icon(Icons.arrow_back, color: colors.text),
            ),
            const SizedBox(width: 8),
            Image.asset(
              'assets/images/circum_wordmark.png',
              width: 116,
              height: 28,
              fit: BoxFit.contain,
            ),
            const Spacer(),
            if (onProfile != null)
              IconButton(
                tooltip: 'Profile',
                onPressed: onProfile,
                icon: Icon(Icons.account_circle_outlined, color: colors.text),
              ),
            IconButton(
              tooltip: darkMode ? 'Light mode' : 'Dark mode',
              onPressed: onToggleTheme,
              icon: Icon(
                darkMode ? Icons.light_mode : Icons.dark_mode,
                color: colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsStep extends StatelessWidget {
  final _CircumColors colors;
  final TextEditingController pickup;
  final TextEditingController dropoff;
  final List<SavedSenderAddress> savedAddresses;
  final ValueChanged<String> onSavedPickup;
  final ValueChanged<String> onSavedDropoff;
  final TextEditingController description;
  final TextEditingController weight;
  final double? irisEstimatedWeightKg;
  final String? irisWeightBand;
  final String? irisWeightConfidence;
  final String? irisWeightExplanation;
  final double? senderEnteredWeightKg;
  final double? pricingWeightKg;
  final String? pricingReason;
  final bool verificationRequired;
  final String? weightMessage;
  final VoidCallback onConfirmIrisWeight;
  final TextEditingController scheduledPickupDate;
  final TextEditingController scheduledPickupWindow;
  final TextEditingController scheduledDropoffDate;
  final TextEditingController scheduledDropoffWindow;
  final bool analyzing;
  final VoidCallback onSubmit;

  const _DetailsStep({
    super.key,
    required this.colors,
    required this.pickup,
    required this.dropoff,
    required this.savedAddresses,
    required this.onSavedPickup,
    required this.onSavedDropoff,
    required this.description,
    required this.weight,
    required this.irisEstimatedWeightKg,
    required this.irisWeightBand,
    required this.irisWeightConfidence,
    required this.irisWeightExplanation,
    required this.senderEnteredWeightKg,
    required this.pricingWeightKg,
    required this.pricingReason,
    required this.verificationRequired,
    required this.weightMessage,
    required this.onConfirmIrisWeight,
    required this.scheduledPickupDate,
    required this.scheduledPickupWindow,
    required this.scheduledDropoffDate,
    required this.scheduledDropoffWindow,
    required this.analyzing,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Where is your package going?',
          style: TextStyle(
            color: colors.text,
            fontSize: 30,
            height: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add the pickup, drop-off, item details, and weight. Iris will show the best option before you pay.',
          style: TextStyle(
            color: colors.mutedText,
            fontSize: 15,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        _GlassPanel(
          colors: colors,
          child: Column(
            children: [
              _SavedAddressQuickPick(
                colors: colors,
                addresses: savedAddresses,
                addressType: 'pickup',
                onSelect: onSavedPickup,
              ),
              if (savedAddresses.isNotEmpty) const SizedBox(height: 12),
              _AddressField(
                colors: colors,
                icon: Icons.radio_button_checked,
                label: 'Pickup location',
                controller: pickup,
              ),
              const SizedBox(height: 12),
              _SavedAddressQuickPick(
                colors: colors,
                addresses: savedAddresses,
                addressType: 'dropoff',
                onSelect: onSavedDropoff,
              ),
              if (savedAddresses.isNotEmpty) const SizedBox(height: 12),
              _AddressField(
                colors: colors,
                icon: Icons.location_on,
                label: 'Drop-off location',
                controller: dropoff,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Schedule'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _InputBox(
                      colors: colors,
                      controller: scheduledPickupDate,
                      hint: 'Pickup date',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _InputBox(
                      colors: colors,
                      controller: scheduledPickupWindow,
                      hint: 'Pickup time window',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _InputBox(
                      colors: colors,
                      controller: scheduledDropoffDate,
                      hint: 'Delivery date',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _InputBox(
                      colors: colors,
                      controller: scheduledDropoffWindow,
                      hint: 'Delivery time window',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Pick the times that work best for collection and delivery.',
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Package details',
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  _IrisTag(colors: colors),
                ],
              ),
              const SizedBox(height: 12),
              _InputBox(
                colors: colors,
                controller: description,
                hint: 'Describe your item',
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _InputBox(
                      colors: colors,
                      controller: weight,
                      hint: 'Weight',
                    ),
                  ),
                  const SizedBox(width: 12),
                  _PhotoButton(colors: colors),
                ],
              ),
              if (weightMessage != null) ...[
                const SizedBox(height: 12),
                _WeightConfirmationPanel(
                  colors: colors,
                  estimatedWeightKg: irisEstimatedWeightKg,
                  weightBand: irisWeightBand,
                  confidence: irisWeightConfidence,
                  explanation: irisWeightExplanation,
                  senderEnteredWeightKg: senderEnteredWeightKg,
                  pricingWeightKg: pricingWeightKg,
                  pricingReason: pricingReason,
                  verificationRequired: verificationRequired,
                  message: weightMessage!,
                  onConfirm: onConfirmIrisWeight,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'A photo helps the rider understand the size and handle the item properly.',
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: analyzing ? null : onSubmit,
            icon: analyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
                analyzing ? 'Checking options...' : 'See delivery options'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.text,
              foregroundColor: colors.inverseText,
              disabledBackgroundColor: colors.text.withOpacity(0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 17),
            ),
          ),
        ),
      ],
    );
  }
}

class _HealthPlusStep extends StatelessWidget {
  final _CircumColors colors;
  final TextEditingController fullName;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController pharmacyAddress;
  final TextEditingController deliveryAddress;
  final TextEditingController notes;
  final TextEditingController preferredTime;
  final TextEditingController customSchedule;
  final HealthPlusFrequency frequency;
  final bool consent;
  final bool savePayment;
  final bool submitting;
  final String? message;
  final String? checkoutUrl;
  final HealthPlusPriceBreakdown quote;
  final List<Map<String, dynamic>> pickups;
  final List<Map<String, dynamic>> payments;
  final VoidCallback onBack;
  final ValueChanged<HealthPlusFrequency> onFrequency;
  final ValueChanged<bool?> onConsent;
  final ValueChanged<bool?> onSavePayment;
  final VoidCallback onSubmit;
  final VoidCallback onPauseSchedule;
  final VoidCallback onCancelPickup;
  final VoidCallback onUpdatePayment;
  final ValueChanged<String> onAdminStatus;

  const _HealthPlusStep({
    super.key,
    required this.colors,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.pharmacyAddress,
    required this.deliveryAddress,
    required this.notes,
    required this.preferredTime,
    required this.customSchedule,
    required this.frequency,
    required this.consent,
    required this.savePayment,
    required this.submitting,
    required this.message,
    required this.checkoutUrl,
    required this.quote,
    required this.pickups,
    required this.payments,
    required this.onBack,
    required this.onFrequency,
    required this.onConsent,
    required this.onSavePayment,
    required this.onSubmit,
    required this.onPauseSchedule,
    required this.onCancelPickup,
    required this.onUpdatePayment,
    required this.onAdminStatus,
  });

  @override
  Widget build(BuildContext context) {
    final nextPickup = pickups.isEmpty ? null : pickups.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTopBar(colors: colors, title: 'Health+', onBack: onBack),
        const SizedBox(height: 14),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xffdcfce7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.health_and_safety,
                        color: Color(0xff16a34a)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Get your meds before you run out.',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 26,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Book one-off or repeat prescription pickups from your pharmacy to your door. From £11.',
                          style: TextStyle(
                            color: colors.mutedText,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _HealthChip(label: 'One-off'),
                  _HealthChip(label: 'Recurring'),
                  _HealthChip(label: 'In-app payment'),
                  _HealthChip(label: 'Sealed packages only'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Your details'),
              const SizedBox(height: 12),
              _InputBox(
                  colors: colors, controller: fullName, hint: 'Full name'),
              const SizedBox(height: 10),
              _InputBox(
                  colors: colors, controller: phone, hint: 'Phone number'),
              const SizedBox(height: 10),
              _InputBox(colors: colors, controller: email, hint: 'Email'),
              const SizedBox(height: 10),
              _InputBox(
                  colors: colors,
                  controller: pharmacyAddress,
                  hint: 'Pickup address / pharmacy address'),
              const SizedBox(height: 10),
              _InputBox(
                  colors: colors,
                  controller: deliveryAddress,
                  hint: 'Delivery address'),
              const SizedBox(height: 10),
              _InputBox(
                colors: colors,
                controller: notes,
                hint: 'Prescription or pickup notes',
                maxLines: 3,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Pickup schedule'),
              const SizedBox(height: 12),
              _HealthFrequencyPicker(
                colors: colors,
                selected: frequency,
                onChanged: onFrequency,
              ),
              const SizedBox(height: 10),
              _InputBox(
                colors: colors,
                controller: preferredTime,
                hint: 'Preferred day and time',
              ),
              if (frequency == HealthPlusFrequency.custom) ...[
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: customSchedule,
                  hint: 'Custom repeat schedule',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Price breakdown'),
              const SizedBox(height: 10),
              _PriceLine(
                  colors: colors,
                  label: 'Base fare',
                  value: '£${quote.delivery.baseFare.toStringAsFixed(2)}'),
              _PriceLine(
                  colors: colors,
                  label: 'Mileage fare',
                  value: '£${quote.delivery.distanceFare.toStringAsFixed(2)}'),
              _PriceLine(
                  colors: colors,
                  label: 'Parcel weight fee',
                  value:
                      '£${quote.delivery.weightSurcharge.toStringAsFixed(2)}'),
              _PriceLine(
                  colors: colors,
                  label: 'Health+ care fee',
                  value: '£${quote.serviceFee.toStringAsFixed(2)}'),
              if (quote.minimumAdjustment > 0)
                _PriceLine(
                    colors: colors,
                    label: 'Minimum price adjustment',
                    value: '£${quote.minimumAdjustment.toStringAsFixed(2)}'),
              Divider(color: colors.border, height: 24),
              _PriceLine(
                  colors: colors,
                  label: frequency == HealthPlusFrequency.oneOff
                      ? 'One-off total'
                      : 'Recurring pickup total',
                  value: '£${quote.total.toStringAsFixed(2)}',
                  strong: true),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: savePayment,
                onChanged: onSavePayment,
                activeColor: colors.text,
                title: Text(
                  'Save this payment method',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _HealthDisclaimer(colors: colors),
        const SizedBox(height: 10),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: consent,
          onChanged: onConsent,
          activeColor: colors.text,
          title: Text(
            'I confirm the prescription is valid and ready, or will be ready, for collection.',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              message!,
              style: TextStyle(
                color: colors.text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: submitting ? null : onSubmit,
            icon: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock),
            label: Text(submitting
                ? 'Setting up Health+...'
                : 'Pay £${quote.total.toStringAsFixed(2)} securely'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.text,
              foregroundColor: colors.inverseText,
              padding: const EdgeInsets.symmetric(vertical: 17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        if (checkoutUrl != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onUpdatePayment,
              icon: const Icon(Icons.credit_card),
              label: const Text('Continue to payment'),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _HealthDashboard(
          colors: colors,
          pickup: nextPickup,
          payments: payments,
          onPauseSchedule: onPauseSchedule,
          onCancelPickup: onCancelPickup,
          onUpdatePayment: onUpdatePayment,
        ),
        const SizedBox(height: 14),
        _HealthAdminPanel(
          colors: colors,
          pickup: nextPickup,
          onStatus: onAdminStatus,
        ),
      ],
    );
  }
}

class _HealthChip extends StatelessWidget {
  final String label;

  const _HealthChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: const Color(0xffecfdf5),
      labelStyle: const TextStyle(
        color: Color(0xff166534),
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide.none,
    );
  }
}

class _HealthFrequencyPicker extends StatelessWidget {
  final _CircumColors colors;
  final HealthPlusFrequency selected;
  final ValueChanged<HealthPlusFrequency> onChanged;

  const _HealthFrequencyPicker({
    required this.colors,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: HealthPlusFrequency.values.map((frequency) {
        final active = frequency == selected;
        return ChoiceChip(
          selected: active,
          onSelected: (_) => onChanged(frequency),
          label: Text(frequency.label),
          selectedColor: colors.text,
          backgroundColor: colors.field,
          labelStyle: TextStyle(
            color: active ? colors.inverseText : colors.text,
            fontWeight: FontWeight.w800,
          ),
          side: BorderSide(color: active ? colors.text : colors.border),
        );
      }).toList(),
    );
  }
}

class _HealthDisclaimer extends StatelessWidget {
  final _CircumColors colors;

  const _HealthDisclaimer({required this.colors});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Safety and compliance'),
          const SizedBox(height: 8),
          ...[
            'Health+ is a pickup and delivery service only.',
            'Circum does not prescribe medication.',
            'Users are responsible for ensuring prescriptions are valid and ready for collection.',
            'Riders only collect and deliver sealed pharmacy packages.',
          ].map((copy) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, color: colors.success, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        copy,
                        style: TextStyle(
                          color: colors.mutedText,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _HealthDashboard extends StatelessWidget {
  final _CircumColors colors;
  final Map<String, dynamic>? pickup;
  final List<Map<String, dynamic>> payments;
  final VoidCallback onPauseSchedule;
  final VoidCallback onCancelPickup;
  final VoidCallback onUpdatePayment;

  const _HealthDashboard({
    required this.colors,
    required this.pickup,
    required this.payments,
    required this.onPauseSchedule,
    required this.onCancelPickup,
    required this.onUpdatePayment,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Your Health+ dashboard'),
          const SizedBox(height: 10),
          if (pickup == null)
            Text(
              'Your pickups, payments, and repeat settings will appear here after you book.',
              style: TextStyle(color: colors.mutedText, height: 1.4),
            )
          else ...[
            _HealthDashboardRow(
              colors: colors,
              label: 'Upcoming pickup',
              value: pickup!['preferredPickupTime']?.toString() ?? 'Scheduled',
            ),
            _HealthDashboardRow(
              colors: colors,
              label: 'Status',
              value: pickup!['status']?.toString() ?? 'scheduled',
            ),
            _HealthDashboardRow(
              colors: colors,
              label: 'Payments',
              value: payments.isEmpty
                  ? 'No payments yet'
                  : '£${payments.first['amount']} - ${payments.first['status']}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onPauseSchedule,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause recurring'),
                ),
                OutlinedButton.icon(
                  onPressed: onCancelPickup,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel pickup'),
                ),
                OutlinedButton.icon(
                  onPressed: onUpdatePayment,
                  icon: const Icon(Icons.credit_card),
                  label: const Text('Update payment'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HealthDashboardRow extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;

  const _HealthDashboardRow({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: colors.mutedText, fontWeight: FontWeight.w700)),
          ),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style:
                    TextStyle(color: colors.text, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _HealthAdminPanel extends StatelessWidget {
  final _CircumColors colors;
  final Map<String, dynamic>? pickup;
  final ValueChanged<String> onStatus;

  const _HealthAdminPanel({
    required this.colors,
    required this.pickup,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    final statuses = [
      PickupStatus.assigned.value,
      PickupStatus.awaitingPharmacyCollection.value,
      PickupStatus.collected.value,
      PickupStatus.outForDelivery.value,
      PickupStatus.delivered.value,
      PickupStatus.failed.value,
    ];

    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Admin operations'),
          const SizedBox(height: 8),
          Text(
            pickup == null
                ? 'Create a Health+ booking to see the operations controls.'
                : 'Assign a rider, update pickup and delivery status, flag problems, or contact the user.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: statuses
                .map(
                  (status) => ActionChip(
                    onPressed: pickup == null ? null : () => onStatus(status),
                    label: Text(status.replaceAll('_', ' ')),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _IrisWeightEstimate {
  final double weightKg;
  final String weightBand;
  final String confidence;
  final String explanation;
  final String packageType;
  final bool requiresVehicleReview;

  const _IrisWeightEstimate({
    required this.weightKg,
    required this.weightBand,
    required this.confidence,
    required this.explanation,
    required this.packageType,
    required this.requiresVehicleReview,
  });
}

class _WeightPricingDecision {
  final double? weightKg;
  final String? weightBand;
  final String source;
  final String message;
  final String reason;
  final bool verificationRequired;

  const _WeightPricingDecision({
    this.weightKg,
    this.weightBand,
    this.source = 'manual',
    required this.message,
    required this.reason,
    required this.verificationRequired,
  });
}

class _SectionTitle extends StatelessWidget {
  final _CircumColors colors;
  final String title;

  const _SectionTitle({required this.colors, required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: colors.text,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _VehicleStep extends StatelessWidget {
  final _CircumColors colors;
  final String pickup;
  final String dropoff;
  final double chargeableWeightKg;
  final _VehicleOption selectedVehicle;
  final String selectedSpeed;
  final ValueChanged<_VehicleOption> onVehicle;
  final ValueChanged<String> onSpeed;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _VehicleStep({
    super.key,
    required this.colors,
    required this.pickup,
    required this.dropoff,
    required this.chargeableWeightKg,
    required this.selectedVehicle,
    required this.selectedSpeed,
    required this.onVehicle,
    required this.onSpeed,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final recommendedVehicleName =
        DeliveryPricing.recommendedVehicleForWeight(chargeableWeightKg);
    final canContinue = DeliveryPricing.vehicleCanCarryWeight(
      selectedVehicle.name,
      chargeableWeightKg,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTopBar(
            colors: colors,
            title: 'Best fit for this delivery',
            onBack: onBack),
        const SizedBox(height: 14),
        _GlassPanel(
          colors: colors,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.tune, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recommended: $recommendedVehicleName',
                      style: TextStyle(
                        color: colors.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Based on the item, weight, and route, a ${recommendedVehicleName.toLowerCase()} should be the best fit.',
                      style: TextStyle(
                        color: colors.mutedText,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _RouteSummary(colors: colors, pickup: pickup, dropoff: dropoff),
        const SizedBox(height: 14),
        ..._vehicles.map(
          (vehicle) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _VehicleTile(
              colors: colors,
              vehicle: vehicle,
              selected: vehicle.name == selectedVehicle.name,
              onTap: () => onVehicle(vehicle),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _SpeedToggle(
          colors: colors,
          selected: selectedSpeed,
          onChanged: onSpeed,
        ),
        if (!canContinue) ...[
          const SizedBox(height: 12),
          _GlassPanel(
            colors: colors,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: colors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This item is too heavy for bike delivery. Car/van required.',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: canContinue ? onContinue : null,
            style: FilledButton.styleFrom(
              backgroundColor: colors.text,
              foregroundColor: colors.inverseText,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 17),
            ),
            child: const Text('Continue to Payment'),
          ),
        ),
      ],
    );
  }
}

class _PaymentStep extends StatelessWidget {
  final _CircumColors colors;
  final _VehicleOption vehicle;
  final String speed;
  final DeliveryPricingBreakdown breakdown;
  final double? irisEstimatedWeightKg;
  final double? senderEnteredWeightKg;
  final double weightKg;
  final double total;
  final bool weightConfirmed;
  final String weightSource;
  final String? pricingReason;
  final String scheduledPickupDate;
  final String scheduledPickupWindow;
  final String scheduledDropoffDate;
  final String scheduledDropoffWindow;
  final VoidCallback onBack;
  final VoidCallback onPay;

  const _PaymentStep({
    super.key,
    required this.colors,
    required this.vehicle,
    required this.speed,
    required this.breakdown,
    required this.irisEstimatedWeightKg,
    required this.senderEnteredWeightKg,
    required this.weightKg,
    required this.total,
    required this.weightConfirmed,
    required this.weightSource,
    required this.pricingReason,
    required this.scheduledPickupDate,
    required this.scheduledPickupWindow,
    required this.scheduledDropoffDate,
    required this.scheduledDropoffWindow,
    required this.onBack,
    required this.onPay,
  });

  String _scheduleText(String date, String window) {
    if (date.isEmpty && window.isEmpty) return 'Not set';
    if (date.isEmpty) return window;
    if (window.isEmpty) return date;
    return '$date, $window';
  }

  @override
  Widget build(BuildContext context) {
    final hasSchedule = scheduledPickupDate.isNotEmpty ||
        scheduledPickupWindow.isNotEmpty ||
        scheduledDropoffDate.isNotEmpty ||
        scheduledDropoffWindow.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTopBar(colors: colors, title: 'Payment', onBack: onBack),
        const SizedBox(height: 16),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Order Summary',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_webQuoteDistanceMiles.toStringAsFixed(1)} miles',
                    style: TextStyle(
                      color: colors.mutedText,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (hasSchedule) ...[
                _PriceLine(
                  colors: colors,
                  label: 'Pickup schedule',
                  value: _scheduleText(
                    scheduledPickupDate,
                    scheduledPickupWindow,
                  ),
                ),
                _PriceLine(
                  colors: colors,
                  label: 'Delivery schedule',
                  value: _scheduleText(
                    scheduledDropoffDate,
                    scheduledDropoffWindow,
                  ),
                ),
                Divider(color: colors.border, height: 26),
              ],
              _PriceLine(
                colors: colors,
                label: 'Confirmed parcel weight',
                value: weightConfirmed
                    ? '${weightKg.toStringAsFixed(weightKg.truncateToDouble() == weightKg ? 0 : 1)} kg'
                    : 'Confirm parcel weight before payment.',
                strong: true,
              ),
              if (irisEstimatedWeightKg != null)
                _PriceLine(
                  colors: colors,
                  label: 'Iris estimate',
                  value:
                      '${irisEstimatedWeightKg!.toStringAsFixed(irisEstimatedWeightKg!.truncateToDouble() == irisEstimatedWeightKg ? 0 : 1)} kg',
                ),
              if (senderEnteredWeightKg != null)
                _PriceLine(
                  colors: colors,
                  label: 'Your weight',
                  value:
                      '${senderEnteredWeightKg!.toStringAsFixed(senderEnteredWeightKg!.truncateToDouble() == senderEnteredWeightKg ? 0 : 1)} kg',
                ),
              _PriceLine(
                colors: colors,
                label: 'Weight source',
                value: weightSource,
              ),
              if (pricingReason != null && pricingReason!.trim().isNotEmpty)
                _PriceLine(
                  colors: colors,
                  label: 'Reason',
                  value: pricingReason!,
                ),
              Divider(color: colors.border, height: 26),
              _PriceLine(
                  colors: colors,
                  label: 'Base fare',
                  value: '£${breakdown.baseFare.toStringAsFixed(2)}'),
              _PriceLine(
                  colors: colors,
                  label: 'Distance fare',
                  value: '£${breakdown.distanceFare.toStringAsFixed(2)}'),
              _PriceLine(
                  colors: colors,
                  label:
                      '${breakdown.weightCategory} (${weightKg.toStringAsFixed(weightKg.truncateToDouble() == weightKg ? 0 : 1)} kg)',
                  value: '£${breakdown.weightSurcharge.toStringAsFixed(2)}'),
              _PriceLine(
                  colors: colors,
                  label: '${vehicle.name} vehicle',
                  value: '£${breakdown.vehicleSurcharge.toStringAsFixed(2)}'),
              if (breakdown.specialConditions > 0)
                _PriceLine(
                    colors: colors,
                    label: speed == 'Express'
                        ? 'Special conditions incl. express'
                        : 'Special conditions',
                    value:
                        '£${breakdown.specialConditions.toStringAsFixed(2)}'),
              Divider(color: colors.border, height: 26),
              _PriceLine(
                colors: colors,
                label: breakdown.requiresManualQuote ? 'Total' : 'Total',
                value: breakdown.requiresManualQuote
                    ? 'Manual quote'
                    : '£${total.toStringAsFixed(2)}',
                strong: true,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.field,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.credit_card, color: colors.text),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Visa ending 4242',
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(Icons.check_circle, color: colors.success),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: weightConfirmed ? onPay : null,
            icon: const Icon(Icons.lock),
            label: Text(
              weightConfirmed
                  ? 'Pay £${total.toStringAsFixed(2)} & Broadcast'
                  : 'Confirm parcel weight before payment',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: colors.text,
              foregroundColor: colors.inverseText,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 17),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackingStep extends StatelessWidget {
  final _CircumColors colors;
  final String orderId;
  final String pickup;
  final String dropoff;
  final _VehicleOption vehicle;
  final int statusIndex;
  final bool broadcasting;
  final bool firebaseOnline;
  final String? firebaseError;
  final DriverProfile? assignedDriver;
  final DriverPerformanceMetric? assignedDriverMetric;
  final int ratingStars;
  final TextEditingController ratingFeedback;
  final Set<String> selectedRatingTags;
  final bool ratingSubmitting;
  final bool ratingSubmitted;
  final String? ratingMessage;
  final ValueChanged<int> onRatingChanged;
  final ValueChanged<String> onRatingTag;
  final VoidCallback onSubmitRating;
  final VoidCallback onChatDriver;
  final VoidCallback onChatSupport;
  final VoidCallback onNewOrder;

  const _TrackingStep({
    super.key,
    required this.colors,
    required this.orderId,
    required this.pickup,
    required this.dropoff,
    required this.vehicle,
    required this.statusIndex,
    required this.broadcasting,
    required this.firebaseOnline,
    required this.firebaseError,
    required this.assignedDriver,
    required this.assignedDriverMetric,
    required this.ratingStars,
    required this.ratingFeedback,
    required this.selectedRatingTags,
    required this.ratingSubmitting,
    required this.ratingSubmitted,
    required this.ratingMessage,
    required this.onRatingChanged,
    required this.onRatingTag,
    required this.onSubmitRating,
    required this.onChatDriver,
    required this.onChatSupport,
    required this.onNewOrder,
  });

  @override
  Widget build(BuildContext context) {
    final assigned = statusIndex > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Live Tracking',
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    orderId,
                    style: TextStyle(
                      color: colors.mutedText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'New order',
              onPressed: onNewOrder,
              icon: Icon(Icons.add_circle_outline, color: colors.text),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _FirebaseStatusBanner(
          colors: colors,
          online: firebaseOnline,
          error: firebaseError,
        ),
        const SizedBox(height: 14),
        Stack(
          children: [
            _MiniMap(colors: colors, active: assigned),
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.panel.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'ESTIMATED',
                      style: TextStyle(
                        color: colors.mutedText,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      assigned ? '14 min' : 'Matching',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (broadcasting)
          _BroadcastCard(colors: colors)
        else
          _DriverCard(
            colors: colors,
            vehicle: vehicle,
            driver: assignedDriver,
            metric: assignedDriverMetric,
            onChatDriver: onChatDriver,
          ),
        if (statusIndex >= 3) ...[
          const SizedBox(height: 14),
          _DriverRatingPrompt(
            colors: colors,
            driver: assignedDriver,
            stars: ratingStars,
            feedback: ratingFeedback,
            selectedTags: selectedRatingTags,
            submitting: ratingSubmitting,
            submitted: ratingSubmitted,
            message: ratingMessage,
            onRatingChanged: onRatingChanged,
            onTag: onRatingTag,
            onSubmit: onSubmitRating,
          ),
        ],
        const SizedBox(height: 14),
        _RouteSummary(colors: colors, pickup: pickup, dropoff: dropoff),
        const SizedBox(height: 14),
        _Timeline(colors: colors, activeIndex: statusIndex),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onChatSupport,
            icon: const Icon(Icons.support_agent),
            label: const Text('Chat with Iris'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.text,
              side: BorderSide(color: colors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}

class _FirebaseStatusBanner extends StatelessWidget {
  final _CircumColors colors;
  final bool online;
  final String? error;

  const _FirebaseStatusBanner({
    required this.colors,
    required this.online,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final healthy = online && error == null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: healthy ? const Color(0xffdcfce7) : const Color(0xfffff7ed),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: healthy ? const Color(0xff86efac) : const Color(0xffffd7aa),
        ),
      ),
      child: Row(
        children: [
          Icon(
            healthy ? Icons.cloud_done : Icons.cloud_off,
            color: healthy ? const Color(0xff15803d) : const Color(0xffc2410c),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              healthy
                  ? 'This delivery is saved and live.'
                  : error ?? 'Connecting this delivery...',
              style: TextStyle(
                color:
                    healthy ? const Color(0xff166534) : const Color(0xff9a3412),
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatSheet extends StatelessWidget {
  final _CircumColors colors;
  final String title;
  final String recipient;
  final List<_ChatMessage> messages;
  final TextEditingController input;
  final VoidCallback onClose;
  final VoidCallback onSend;

  const _ChatSheet({
    required this.colors,
    required this.title,
    required this.recipient,
    required this.messages,
    required this.input,
    required this.onClose,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.45),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: MediaQuery.sizeOf(context).height * 0.78,
            decoration: BoxDecoration(
              color: colors.appBackground,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: colors.field,
                        child: Icon(Icons.chat_bubble, color: colors.text),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: colors.text,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              recipient,
                              style: TextStyle(
                                color: colors.mutedText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: onClose,
                        icon: Icon(Icons.close, color: colors.text),
                      ),
                    ],
                  ),
                ),
                Divider(color: colors.border, height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return Align(
                        alignment: message.fromMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          constraints: const BoxConstraints(maxWidth: 290),
                          decoration: BoxDecoration(
                            color: message.fromMe ? colors.text : colors.field,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            message.text,
                            style: TextStyle(
                              color: message.fromMe
                                  ? colors.inverseText
                                  : colors.text,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: _InputBox(
                          colors: colors,
                          controller: input,
                          hint: 'Type a message...',
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: onSend,
                        icon: const Icon(Icons.send),
                        style: IconButton.styleFrom(
                          backgroundColor: colors.text,
                          foregroundColor: colors.inverseText,
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
    );
  }
}

class _MiniMap extends StatelessWidget {
  final _CircumColors colors;
  final bool active;

  const _MiniMap({required this.colors, required this.active});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.65,
      child: CustomPaint(
        painter: _MapPainter(colors: colors, active: active),
        child: Stack(
          children: [
            Positioned(
              left: 22,
              bottom: 20,
              child: _MapPin(colors: colors, label: 'Pickup'),
            ),
            Positioned(
              right: 24,
              top: 22,
              child: _MapPin(colors: colors, label: 'Drop-off'),
            ),
            Positioned(
              left: active ? 175 : 132,
              top: active ? 78 : 98,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xff2563eb),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x552563eb),
                      blurRadius: 18,
                      spreadRadius: 4,
                    )
                  ],
                ),
                child: const Icon(
                  Icons.two_wheeler,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final _CircumColors colors;
  final bool active;

  _MapPainter({required this.colors, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = LinearGradient(
        colors: colors.dark
            ? [const Color(0xff111827), const Color(0xff1e293b)]
            : [const Color(0xffeff6ff), const Color(0xfff8fafc)],
      ).createShader(Offset.zero & size);
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(24),
    );
    canvas.drawRRect(rect, background);

    final road = Paint()
      ..color = colors.dark ? const Color(0xff334155) : const Color(0xffffffff)
      ..strokeWidth = 18
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.06, size.height * 0.78)
      ..quadraticBezierTo(size.width * 0.28, size.height * 0.46,
          size.width * 0.48, size.height * 0.58)
      ..quadraticBezierTo(size.width * 0.68, size.height * 0.70,
          size.width * 0.90, size.height * 0.18);
    canvas.drawPath(path, road);

    final route = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: _spectrumGradient,
      ).createShader(Offset.zero & size)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, route);

    final grid = Paint()
      ..color = colors.dark
          ? Colors.white.withOpacity(0.04)
          : Colors.black.withOpacity(0.04)
      ..strokeWidth = 1;
    for (double x = 30; x < size.width; x += 52) {
      canvas.drawLine(Offset(x, 0), Offset(x - 40, size.height), grid);
    }
    for (double y = 24; y < size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 28), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) {
    return oldDelegate.colors.dark != colors.dark ||
        oldDelegate.active != active;
  }
}

class _MapPin extends StatelessWidget {
  final _CircumColors colors;
  final String label;

  const _MapPin({required this.colors, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.panel.withOpacity(0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.text,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AddressField extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String label;
  final TextEditingController controller;

  const _AddressField({
    required this.colors,
    required this.icon,
    required this.label,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: colors.text, size: 18),
        labelText: label,
        labelStyle: TextStyle(color: colors.mutedText),
        filled: true,
        fillColor: colors.field,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _InputBox extends StatelessWidget {
  final _CircumColors colors;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final bool obscureText;
  final bool enabled;

  const _InputBox({
    required this.colors,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.obscureText = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      obscureText: obscureText,
      enabled: enabled,
      style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.mutedText),
        filled: true,
        fillColor: colors.field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _PhotoButton extends StatelessWidget {
  final _CircumColors colors;

  const _PhotoButton({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Add a photo',
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: colors.text,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.photo_camera, color: colors.inverseText),
      ),
    );
  }
}

class _IrisTag extends StatelessWidget {
  final _CircumColors colors;

  const _IrisTag({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xff2563eb).withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Iris check',
        style: TextStyle(
          color: Color(0xff2563eb),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  final _CircumColors colors;
  final String pickup;
  final String dropoff;

  const _RouteSummary({
    required this.colors,
    required this.pickup,
    required this.dropoff,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: _RouteRow(colors: colors, from: pickup, to: dropoff),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final _CircumColors colors;
  final String from;
  final String to;

  const _RouteRow({
    required this.colors,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RoutePoint(colors: colors, label: 'Pickup', value: from, first: true),
        Padding(
          padding: const EdgeInsets.only(left: 11),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(width: 2, height: 24, color: colors.border),
          ),
        ),
        _RoutePoint(colors: colors, label: 'Drop-off', value: to, first: false),
      ],
    );
  }
}

class _RoutePoint extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;
  final bool first;

  const _RoutePoint({
    required this.colors,
    required this.label,
    required this.value,
    required this.first,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          first ? Icons.radio_button_checked : Icons.location_on,
          color: first ? const Color(0xff2563eb) : const Color(0xff16a34a),
          size: 24,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VehicleTile extends StatelessWidget {
  final _CircumColors colors;
  final _VehicleOption vehicle;
  final bool selected;
  final VoidCallback onTap;

  const _VehicleTile({
    required this.colors,
    required this.vehicle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected ? colors.text : colors.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colors.text : colors.border,
            width: 1.3,
          ),
        ),
        child: Row(
          children: [
            Text(vehicle.emoji, style: const TextStyle(fontSize: 27)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.name,
                    style: TextStyle(
                      color: selected ? colors.inverseText : colors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    vehicle.caption,
                    style: TextStyle(
                      color: selected
                          ? colors.inverseText.withOpacity(0.72)
                          : colors.mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  vehicle.eta,
                  style: TextStyle(
                    color: selected ? colors.inverseText : colors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  DeliveryPricing.calculateVehicleSurcharge(vehicle.name) == 0
                      ? 'No surcharge'
                      : '+£${DeliveryPricing.calculateVehicleSurcharge(vehicle.name).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: selected
                        ? colors.inverseText.withOpacity(0.72)
                        : colors.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _SpeedToggle extends StatelessWidget {
  final _CircumColors colors;
  final String selected;
  final ValueChanged<String> onChanged;

  const _SpeedToggle({
    required this.colors,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['Standard', 'Express'].map((speed) {
        final active = selected == speed;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: speed == 'Standard' ? 8 : 0),
            child: ChoiceChip(
              selected: active,
              label: Center(child: Text(speed)),
              onSelected: (_) => onChanged(speed),
              selectedColor: colors.text,
              backgroundColor: colors.field,
              labelStyle: TextStyle(
                color: active ? colors.inverseText : colors.text,
                fontWeight: FontWeight.w900,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: BorderSide(color: colors.border),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StepTopBar extends StatelessWidget {
  final _CircumColors colors;
  final String title;
  final VoidCallback? onBack;

  const _StepTopBar({
    required this.colors,
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: Icon(Icons.arrow_back_ios_new, color: colors.text, size: 18),
          ),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: colors.text,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _PriceLine extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;
  final bool strong;

  const _PriceLine({
    required this.colors,
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong ? colors.text : colors.mutedText,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                fontSize: strong ? 17 : 14,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.text,
              fontWeight: FontWeight.w900,
              fontSize: strong ? 20 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _BroadcastCard extends StatelessWidget {
  final _CircumColors colors;

  const _BroadcastCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xff2563eb).withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
              ),
              const Icon(Icons.radar, color: Color(0xff2563eb), size: 42),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Finding nearby riders',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Iris is checking nearby riders for this delivery.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.mutedText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  final _CircumColors colors;
  final _VehicleOption vehicle;
  final DriverProfile? driver;
  final DriverPerformanceMetric? metric;
  final VoidCallback onChatDriver;

  const _DriverCard({
    required this.colors,
    required this.vehicle,
    required this.driver,
    required this.metric,
    required this.onChatDriver,
  });

  @override
  Widget build(BuildContext context) {
    final profile = driver ??
        DriverProfile.fromMap(
            'preview-rider',
            {
              'fullName': 'Marcus A.',
              'vehicleType': vehicle.name,
              'vehicleMakeModel':
                  vehicle.name == 'Bike' ? 'E-bike' : 'Toyota Prius',
              'vehicleColour': 'Blue',
              'plateNumber': 'CIR 24K',
              'verificationStatus': 'verified',
            },
            performance: metric);
    final performance = metric ?? profile.performance;
    final rating = performance.averageRating <= 0
        ? 'New'
        : performance.averageRating.toStringAsFixed(2);
    final initials = profile.fullName.trim().isEmpty
        ? 'C'
        : profile.fullName.trim().substring(0, 1).toUpperCase();
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(colors: _spectrumGradient),
                  image: profile.photoUrl == null
                      ? null
                      : DecorationImage(
                          image: NetworkImage(profile.photoUrl!),
                          fit: BoxFit.cover,
                        ),
                ),
                child: profile.photoUrl == null
                    ? Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.fullName,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '★ $rating  •  ${performance.completedTrips} trips  •  ${profile.vehicle.plateNumber.isEmpty ? 'Plate pending' : profile.vehicle.plateNumber}',
                      style: TextStyle(
                        color: colors.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                tooltip: 'Call',
                onPressed: profile.phoneNumber.isEmpty ? null : () {},
                icon: const Icon(Icons.call),
                style: IconButton.styleFrom(
                  backgroundColor: colors.field,
                  foregroundColor: colors.text,
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Message',
                onPressed: onChatDriver,
                icon: const Icon(Icons.chat_bubble),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xff2563eb),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.field,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.vehicle.summary,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Verified: ${profile.verificationStatus}  •  Status: ${_DriverPerformancePanel._statusLabel(performance.driverStatus)}',
                  style: TextStyle(
                    color: colors.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (profile.recentRatings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Recent reviews',
              style: TextStyle(
                color: colors.text,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            ...profile.recentRatings.map(
              (rating) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '★ ${rating.starRating}',
                      style: const TextStyle(
                        color: Color(0xffffb000),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rating.feedbackText.trim().isNotEmpty
                            ? rating.feedbackText.trim()
                            : rating.feedbackTags
                                .map(_DriverRatingPrompt.labelForTag)
                                .join(', '),
                        style: TextStyle(
                          color: colors.mutedText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DriverRatingPrompt extends StatelessWidget {
  static const _tags = [
    ('on_time', 'On time'),
    ('friendly', 'Friendly'),
    ('careful_handling', 'Careful handling'),
    ('good_communication', 'Good communication'),
    ('late', 'Late'),
    ('poor_communication', 'Poor communication'),
  ];

  static String labelForTag(String key) {
    for (final tag in _tags) {
      if (tag.$1 == key) return tag.$2;
    }
    return key.replaceAll('_', ' ');
  }

  final _CircumColors colors;
  final DriverProfile? driver;
  final int stars;
  final TextEditingController feedback;
  final Set<String> selectedTags;
  final bool submitting;
  final bool submitted;
  final String? message;
  final ValueChanged<int> onRatingChanged;
  final ValueChanged<String> onTag;
  final VoidCallback onSubmit;

  const _DriverRatingPrompt({
    required this.colors,
    required this.driver,
    required this.stars,
    required this.feedback,
    required this.selectedTags,
    required this.submitting,
    required this.submitted,
    required this.message,
    required this.onRatingChanged,
    required this.onTag,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final name = driver?.fullName ?? 'your rider';
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Rate $name'),
          const SizedBox(height: 8),
          Text(
            submitted
                ? 'Thanks for helping keep Circum reliable.'
                : 'How was this delivery?',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final value = index + 1;
              return IconButton(
                tooltip: '$value star',
                onPressed: submitted ? null : () => onRatingChanged(value),
                icon: Icon(
                  value <= stars ? Icons.star : Icons.star_border,
                  color: const Color(0xffffb000),
                  size: 36,
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tags.map((tag) {
              final selected = selectedTags.contains(tag.$1);
              return FilterChip(
                selected: selected,
                onSelected: submitted ? null : (_) => onTag(tag.$1),
                label: Text(tag.$2),
                selectedColor: colors.text,
                checkmarkColor: colors.inverseText,
                labelStyle: TextStyle(
                  color: selected ? colors.inverseText : colors.text,
                  fontWeight: FontWeight.w800,
                ),
                backgroundColor: colors.field,
                shape: StadiumBorder(side: BorderSide(color: colors.border)),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _InputBox(
            colors: colors,
            controller: feedback,
            hint: 'Optional feedback',
            maxLines: 3,
            enabled: !submitted,
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(
              message!,
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: submitting || submitted ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.star),
              label: Text(submitted
                  ? 'Rating submitted'
                  : submitting
                      ? 'Saving...'
                      : 'Submit rating'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.text,
                foregroundColor: colors.inverseText,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final _CircumColors colors;
  final int activeIndex;

  const _Timeline({required this.colors, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        children: List.generate(_trackingStatuses.length, (index) {
          final active = index <= activeIndex;
          final status = _trackingStatuses[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == _trackingStatuses.length - 1 ? 0 : 14,
            ),
            child: Row(
              children: [
                Icon(
                  active ? Icons.check_circle : Icons.circle_outlined,
                  color: active ? colors.success : colors.mutedText,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status.title,
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        status.body,
                        style: TextStyle(
                          color: colors.mutedText,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final _CircumColors colors;
  final Widget child;

  const _GlassPanel({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(colors.dark ? 0.18 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: child,
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final Color tint;
  final String title;
  final String body;

  const _FeatureCard({
    required this.colors,
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: const Color(0xff2563eb)),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: TextStyle(
              color: colors.text,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              color: colors.mutedText,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PoweredByTag extends StatelessWidget {
  final _CircumColors colors;

  const _PoweredByTag({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xff22c55e),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Live with Iris',
            style: TextStyle(
              color: colors.mutedText,
              fontSize: 12,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;

  const _MetricPill({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: colors.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoTile extends StatelessWidget {
  final _CircumColors colors;

  const _LogoTile({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.text,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.all_inclusive, color: colors.inverseText),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool dark;
  final VoidCallback onPressed;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.dark,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: dark ? Colors.black : const Color(0xfff3f4f6),
        foregroundColor: dark ? Colors.white : Colors.black,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        textStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LandingFooter extends StatelessWidget {
  final _CircumColors colors;

  const _LandingFooter({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 18,
            children: [
              Image.asset(
                'assets/images/circum_wordmark.png',
                width: 118,
                height: 28,
                fit: BoxFit.contain,
              ),
              Text(
                'Privacy Policy   Terms of Service',
                style: TextStyle(
                  color: colors.mutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '© ${DateTime.now().year} Circum Technologies Ltd.',
                style: TextStyle(color: colors.mutedText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyLiveChatButton extends StatefulWidget {
  final _CircumColors colors;

  const _CompanyLiveChatButton({required this.colors});

  @override
  State<_CompanyLiveChatButton> createState() => _CompanyLiveChatButtonState();
}

class _CompanyLiveChatButtonState extends State<_CompanyLiveChatButton> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _message = TextEditingController();
  bool _open = false;
  bool _sending = false;
  String? _note;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Positioned(
      right: 18,
      bottom: 18,
      child: SafeArea(
        minimum: const EdgeInsets.only(left: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_open) _panel(context, colors),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'company-live-chat',
              onPressed: () => setState(() => _open = !_open),
              backgroundColor: colors.text,
              foregroundColor: colors.inverseText,
              icon: Icon(_open ? Icons.close : Icons.chat_bubble_outline),
              label: Text(_open ? 'Close' : 'Live chat'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, _CircumColors colors) {
    final compact = MediaQuery.sizeOf(context).width < 480;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: compact ? MediaQuery.sizeOf(context).width - 36 : 360,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: colors.dark ? 0.34 : 0.16),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: _spectrumGradient),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.support_agent, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Talk to Circum',
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Send us a note and the team will pick it up.',
                        style: TextStyle(
                          color: colors.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _LiveChatField(
              colors: colors,
              controller: _name,
              label: 'Name',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 10),
            _LiveChatField(
              colors: colors,
              controller: _email,
              label: 'Email or phone',
              icon: Icons.alternate_email,
            ),
            const SizedBox(height: 10),
            _LiveChatField(
              colors: colors,
              controller: _message,
              label: 'How can we help?',
              icon: Icons.message_outlined,
              minLines: 3,
              maxLines: 5,
            ),
            if (_note != null) ...[
              const SizedBox(height: 10),
              Text(
                _note!,
                style: TextStyle(
                  color: _note!.startsWith('Sent')
                      ? colors.success
                      : const Color(0xffef4444),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_sending ? 'Sending' : 'Send message'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.text,
                  foregroundColor: colors.inverseText,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final message = _message.text.trim();
    final contact = _email.text.trim();
    if (message.isEmpty || contact.isEmpty) {
      setState(() => _note = 'Add your contact and message first.');
      return;
    }
    setState(() {
      _sending = true;
      _note = null;
    });
    try {
      await _ensureCircumFirebaseReady();
      await FirebaseFirestore.instance.collection('supportTickets').add({
        'channel': 'web_live_chat',
        'status': 'open',
        'priority': 'normal',
        'name': _name.text.trim(),
        'email': contact,
        'message': message,
        'pageUrl': Uri.base.toString(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _message.clear();
      setState(() => _note = 'Sent. Circum support has your message.');
    } catch (_) {
      setState(() => _note = 'We could not send that. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _LiveChatField extends StatelessWidget {
  final _CircumColors colors;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int minLines;
  final int maxLines;

  const _LiveChatField({
    required this.colors,
    required this.controller,
    required this.label,
    required this.icon,
    this.minLines = 1,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: colors.mutedText),
        filled: true,
        fillColor: colors.field,
        labelStyle: TextStyle(color: colors.mutedText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
    );
  }
}

class _CircumColors {
  final bool dark;

  const _CircumColors(this.dark);

  Color get background => dark ? Colors.black : Colors.white;
  Color get appBackground => dark ? const Color(0xff030712) : Colors.white;
  Color get stage => dark ? const Color(0xff111827) : const Color(0xfff3f4f6);
  Color get band => dark ? const Color(0xff0f172a) : const Color(0xfff8fafc);
  Color get panel => dark ? const Color(0xff111827) : Colors.white;
  Color get field => dark ? const Color(0xff1f2937) : const Color(0xfff3f4f6);
  Color get border => dark ? const Color(0xff1f2937) : const Color(0xffe5e7eb);
  Color get text => dark ? Colors.white : Colors.black;
  Color get inverseText => dark ? Colors.black : Colors.white;
  Color get mutedText =>
      dark ? const Color(0xff9ca3af) : const Color(0xff6b7280);
  Color get success => const Color(0xff16a34a);
  Color get warning => const Color(0xfff59e0b);
}

class _VehicleOption {
  final String name;
  final String emoji;
  final String caption;
  final String eta;

  const _VehicleOption({
    required this.name,
    required this.emoji,
    required this.caption,
    required this.eta,
  });
}

class _TrackingStatus {
  final String title;
  final String body;

  const _TrackingStatus(this.title, this.body);
}

class _ChatMessage {
  final bool fromMe;
  final String text;
  final String time;

  const _ChatMessage({
    required this.fromMe,
    required this.text,
    required this.time,
  });
}

const _vehicles = [
  _VehicleOption(
    name: 'Bike',
    emoji: '🚲',
    caption: 'Small parcels and documents across town',
    eta: '8 min',
  ),
  _VehicleOption(
    name: 'Car',
    emoji: '🚗',
    caption: 'Medium packages and fragile items',
    eta: '12 min',
  ),
  _VehicleOption(
    name: 'Van',
    emoji: '🚐',
    caption: 'Bulky items and multiple boxes',
    eta: '18 min',
  ),
];

const _trackingStatuses = [
  _TrackingStatus(
    'Finding a rider',
    'Iris is checking nearby riders for this delivery.',
  ),
  _TrackingStatus(
    'Rider accepted',
    'Marcus A. accepted the job and is heading to pickup.',
  ),
  _TrackingStatus(
    'Package picked up',
    'Your rider has collected the package.',
  ),
  _TrackingStatus(
    'Delivered',
    'Proof of delivery is saved in your Circum history.',
  ),
];
