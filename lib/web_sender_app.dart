import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:circum/app/admin/admin_operations.dart';
import 'package:circum/app/authentication/access/role_access.dart';
import 'package:circum/app/delivery_security/vanguard_protection.dart';
import 'package:circum/app/health_plus/health_plus_pricing.dart';
import 'package:circum/app/health_plus/models/pickup_status.dart';
import 'package:circum/app/health_plus/models/recurring_pickup_schedule.dart';
import 'package:circum/app/iris/iris_weight_estimator.dart';
import 'package:circum/app/rider_profiles/driver_performance.dart';
import 'package:circum/app/sender_profile/sender_profile.dart';
import 'package:circum/pricing/delivery_pricing.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

const _companyName = 'Circum';
const _webQuoteDistanceMiles = 4.8;
const _desktopWebBreakpoint = 760.0;
const _adminHostingTarget = bool.fromEnvironment('CIRCUM_ADMIN_HOSTING');
const _googlePlacesApiKey = String.fromEnvironment(
  'GOOGLE_PLACES_API_KEY',
  defaultValue: 'AIzaSyDWH0L6pjdf2W_ZZrjfv6z5OvMZQ2TVNMI',
);
const _spectrumGradient = [
  Color(0xffff8c00),
  Color(0xfff80032),
  Color(0xffff00a0),
  Color(0xff8c28ff),
  Color(0xff0023ff),
  Color(0xff19a0ff),
];

enum _WebAppMode { landing, sender, rider, admin }

bool _isPublicHostingHost() {
  final host = Uri.base.host.toLowerCase();
  return host == 'circumuk.com' ||
      host == 'www.circumuk.com' ||
      host == 'circum-2797c.web.app' ||
      host == 'circum-app-2797c.web.app';
}

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
  late _SenderStep _senderInitialStep =
      switch (Uri.base.queryParameters['app']) {
    'health' => _SenderStep.healthPlus,
    'profile' => _SenderStep.profile,
    _ => _SenderStep.dashboard,
  };

  @override
  void initState() {
    super.initState();
    _logWebsiteVisit();
  }

  _WebAppMode _initialMode() {
    if (_adminHostingTarget && !_isPublicHostingHost()) {
      return _WebAppMode.admin;
    }
    return switch (Uri.base.queryParameters['app']) {
      'sender' || 'health' || 'profile' => _WebAppMode.sender,
      'rider' || 'driver' || 'earn' || 'circum-order' => _WebAppMode.rider,
      _ => _WebAppMode.landing,
    };
  }

  Future<void> _logWebsiteVisit() async {
    try {
      await _ensureCircumFirebaseReady();
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('websiteVisitors').add({
        'url': Uri.base.toString(),
        'path': Uri.base.path,
        'query': Uri.base.queryParameters,
        'appMode': _mode.name,
        'userId': user?.uid,
        'email': user?.email,
        'signedIn': user != null,
        'source': 'circum-web',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Visitor analytics must never block the app.
    }
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
                      initialStep: _senderInitialStep,
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
                    onStart: () => setState(() {
                      _senderInitialStep = _SenderStep.dashboard;
                      _mode = _WebAppMode.sender;
                    }),
                    onRider: () => setState(() => _mode = _WebAppMode.rider),
                    onHealthPlus: () => setState(() {
                      _senderInitialStep = _SenderStep.healthPlus;
                      _mode = _WebAppMode.sender;
                    }),
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
  final VoidCallback onHealthPlus;
  final VoidCallback onToggleTheme;

  const _LandingPage({
    super.key,
    required this.colors,
    required this.darkMode,
    required this.onStart,
    required this.onRider,
    required this.onHealthPlus,
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
            onHealthPlus: onHealthPlus,
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
                      _PillButton(
                        label: 'Get started with Health+',
                        icon: Icons.health_and_safety,
                        dark: false,
                        onPressed: onHealthPlus,
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
  visitors,
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
  final _adminChatInput = TextEditingController();
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
  List<Map<String, dynamic>> _websiteVisitors = const [];
  List<Map<String, dynamic>> _riderDocuments = const [];
  bool _adminChatOpen = false;
  String? _activeAdminChatId;
  String _activeAdminChatTitle = 'Booking chat';
  bool _driverProfileOpen = false;
  Map<String, dynamic>? _selectedDriverProfile;
  final List<_ChatMessage> _adminChatMessages = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _adminChatSub;

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
    _adminChatInput.dispose();
    _adminChatSub?.cancel();
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
    await _adminChatSub?.cancel();
    await FirebaseAuth.instance.signOut();
    setState(() {
      _adminUser = null;
      _roles = const [];
      _message = 'Signed out of admin.';
      _adminChatOpen = false;
      _activeAdminChatId = null;
      _activeAdminChatTitle = 'Booking chat';
      _adminChatMessages.clear();
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
            .collection('websiteVisitors')
            .orderBy('createdAt', descending: true)
            .limit(80),
      ),
      _readCollection(db.collection('riderDocuments').limit(120)),
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
    final visitors = results[11];
    final riderDocuments = results[12];
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
      _websiteVisitors = visitors;
      _riderDocuments = riderDocuments;
      _auditLogs = results[13];
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

  String _driverId(Map<String, dynamic> driver) {
    return '${driver['id'] ?? driver['uid'] ?? driver['riderId'] ?? driver['driverId'] ?? ''}'
        .trim();
  }

  String _driverWorkflowStatus(Map<String, dynamic> driver) {
    final raw = [
      driver['approvalStatus'],
      driver['driverStatus'],
      driver['verificationStatus'],
      driver['status'],
    ]
        .where((value) => value != null)
        .map((value) => '$value'.toLowerCase())
        .join(' ')
        .toLowerCase()
        .trim();
    if (raw.contains('suspend')) return 'suspended';
    if (raw.contains('reject')) return 'rejected';
    if (raw.contains('active') ||
        raw.contains('approve') ||
        raw.contains('verified')) {
      return 'approved';
    }
    return 'pending';
  }

  String _driverStatusLabel(Map<String, dynamic> driver) {
    return switch (_driverWorkflowStatus(driver)) {
      'approved' => 'approved',
      'suspended' => 'suspended',
      'rejected' => 'rejected',
      _ => 'pending',
    };
  }

  Future<void> _setDriverWorkflowStatus(
    Map<String, dynamic> driver,
    String nextStatus,
  ) async {
    if (!_can(AdminPermission.approveDrivers)) {
      setState(() => _message = 'Your role cannot manage driver status.');
      return;
    }
    final id = _driverId(driver);
    if (id.isEmpty) return;
    final previous = _driverWorkflowStatus(driver);
    final action = switch (nextStatus) {
      'approved' => previous == 'suspended' || previous == 'rejected'
          ? 'driver_reactivated'
          : 'driver_approved',
      'rejected' => 'driver_rejected',
      'suspended' => 'driver_suspended',
      _ => 'driver_status_updated',
    };
    final driverStatus = switch (nextStatus) {
      'approved' => 'active',
      'rejected' => 'rejected',
      'suspended' => 'suspended',
      _ => nextStatus,
    };
    await FirebaseFirestore.instance.collection('riderProfiles').doc(id).set({
      'approvalStatus': nextStatus,
      'driverStatus': driverStatus,
      'verificationStatus': nextStatus == 'approved' ? 'approved' : nextStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _writeAudit(AdminAuditEntry(
      adminUserId: _adminUser?.uid ?? 'unknown-admin',
      actionType: action,
      recordType: 'riderProfiles',
      recordId: id,
      oldValue: {'status': previous},
      newValue: {
        'status': nextStatus,
        'adminId': _adminUser?.uid ?? 'unknown-admin',
        'action': action,
        'driverId': id,
      },
      reason: 'Driver management workflow action',
    ));
    setState(() {
      _message = 'Driver $id updated to $nextStatus.';
      if (_selectedDriverProfile != null &&
          _driverId(_selectedDriverProfile!) == id) {
        _selectedDriverProfile = {
          ..._selectedDriverProfile!,
          'approvalStatus': nextStatus,
          'driverStatus': driverStatus,
          'verificationStatus':
              nextStatus == 'approved' ? 'approved' : nextStatus,
        };
      }
    });
    await _loadAdminData();
  }

  List<_AdminAction> _driverWorkflowActions(Map<String, dynamic> driver) {
    final status = _driverWorkflowStatus(driver);
    final canApprove = _can(AdminPermission.approveDrivers);
    final canEdit = _can(AdminPermission.editDrivers);
    final actions = <_AdminAction>[];
    if (status == 'pending') {
      actions.addAll([
        _AdminAction(
          label: 'Approve',
          enabled: canApprove,
          onTap: () => _setDriverWorkflowStatus(driver, 'approved'),
        ),
        _AdminAction(
          label: 'Reject',
          enabled: canApprove,
          onTap: () => _setDriverWorkflowStatus(driver, 'rejected'),
        ),
      ]);
    } else if (status == 'approved') {
      actions.addAll([
        _AdminAction(
          label: 'Suspend',
          enabled: canApprove,
          onTap: () => _setDriverWorkflowStatus(driver, 'suspended'),
        ),
        _AdminAction(
          label: 'Message',
          enabled: canEdit,
          onTap: () => _openDriverMessage(driver),
        ),
      ]);
    } else if (status == 'suspended') {
      actions.addAll([
        _AdminAction(
          label: 'Reactivate',
          enabled: canApprove,
          onTap: () => _setDriverWorkflowStatus(driver, 'approved'),
        ),
        _AdminAction(
          label: 'Message',
          enabled: canEdit,
          onTap: () => _openDriverMessage(driver),
        ),
      ]);
    } else if (status == 'rejected') {
      actions.add(
        _AdminAction(
          label: 'Reactivate',
          enabled: canApprove,
          onTap: () => _setDriverWorkflowStatus(driver, 'approved'),
        ),
      );
    }
    actions.add(_AdminAction(
      label: 'View Profile',
      enabled: true,
      onTap: () => _openDriverProfile(driver),
    ));
    return actions;
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

  void _openAdminChat(Map<String, dynamic> delivery) {
    final id = '${delivery['id'] ?? delivery['requestId'] ?? ''}'.trim();
    if (id.isEmpty) return;
    _adminChatSub?.cancel();
    _adminChatSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(id)
        .collection('messages')
        .orderBy('createdAt')
        .limit(100)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _adminChatMessages
          ..clear()
          ..addAll(snapshot.docs.map((doc) {
            final data = doc.data();
            final role = '${data['senderRole'] ?? data['senderType'] ?? ''}';
            return _ChatMessage(
              fromMe: role == 'admin' || data['senderId'] == _adminUser?.uid,
              text: '${data['messageText'] ?? data['message'] ?? ''}',
              time: _formatMessageTime(data['createdAt'], data['timeStamp']),
              label: role == 'admin' || role == 'support'
                  ? 'CIRCUM Support'
                  : role == 'rider' || role == 'driver'
                      ? 'Rider'
                      : 'Sender',
            );
          }).where((message) => message.text.trim().isNotEmpty));
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _message = 'Could not open booking chat.');
    });
    setState(() {
      _activeAdminChatId = id;
      _activeAdminChatTitle = 'Booking chat';
      _adminChatOpen = true;
    });
  }

  void _openDriverProfile(Map<String, dynamic> driver) {
    setState(() {
      _selectedDriverProfile = driver;
      _driverProfileOpen = true;
    });
  }

  Future<void> _openDriverMessage(Map<String, dynamic> driver) async {
    final id = _driverId(driver);
    if (id.isEmpty) return;
    final chatId = 'driver_$id';
    await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
      'threadId': chatId,
      'driverId': id,
      'participants': FieldValue.arrayUnion([id, 'circum-support']),
      'type': 'driver_admin',
      'source': 'circum-admin',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _adminChatSub?.cancel();
    _adminChatSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt')
        .limit(100)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _adminChatMessages
          ..clear()
          ..addAll(snapshot.docs.map((doc) {
            final data = doc.data();
            final role = '${data['senderRole'] ?? data['senderType'] ?? ''}';
            return _ChatMessage(
              fromMe: role == 'admin' || data['senderId'] == _adminUser?.uid,
              text: '${data['messageText'] ?? data['message'] ?? ''}',
              time: _formatMessageTime(data['createdAt'], data['timeStamp']),
              label: role == 'admin' || role == 'support'
                  ? 'CIRCUM Support'
                  : 'Driver',
            );
          }).where((message) => message.text.trim().isNotEmpty));
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _message = 'Could not open driver chat.');
    });
    setState(() {
      _activeAdminChatId = chatId;
      _activeAdminChatTitle = 'Driver chat';
      _adminChatOpen = true;
    });
  }

  bool _isDeliveryForDriver(Map<String, dynamic> delivery, String driverId) {
    final ids = [
      delivery['riderId'],
      delivery['driverId'],
      delivery['assignedRiderId'],
      delivery['assignedDriverId'],
    ].map((value) => '$value');
    return ids.contains(driverId);
  }

  int _driverJobCount(String driverId, Iterable<String> statuses) {
    final wanted = statuses.map((status) => status.toLowerCase()).toSet();
    return _deliveries.where((delivery) {
      if (!_isDeliveryForDriver(delivery, driverId)) return false;
      final status = '${delivery['status'] ?? delivery['deliveryStatus'] ?? ''}'
          .toLowerCase();
      return wanted.any(status.contains);
    }).length;
  }

  double _driverTotalEarnings(String driverId) {
    return _deliveries.where((delivery) {
      final status = '${delivery['status'] ?? delivery['deliveryStatus'] ?? ''}'
          .toLowerCase();
      return _isDeliveryForDriver(delivery, driverId) &&
          (status.contains('complete') || status.contains('delivered'));
    }).fold<double>(0, (total, delivery) {
      final payout = delivery['driverPayout'] ??
          delivery['riderPayout'] ??
          delivery['estimatedDriverPayout'];
      if (payout is num) return total + payout.toDouble();
      return total;
    });
  }

  List<Map<String, dynamic>> _documentsForDriver(String driverId) {
    return _riderDocuments.where((document) {
      return '${document['riderId'] ?? document['driverId'] ?? document['uid'] ?? ''}' ==
          driverId;
    }).toList(growable: false);
  }

  Future<void> _sendAdminChatMessage() async {
    final id = _activeAdminChatId;
    final text = _adminChatInput.text.trim();
    if (id == null || text.isEmpty) return;
    _adminChatInput.clear();
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(id);
    await chatRef.collection('messages').add({
      'threadId': id,
      'bookingId': id,
      'requestId': id,
      'senderId': _adminUser?.uid ?? 'circum-support',
      'senderRole': 'admin',
      'senderType': 'support',
      'messageText': text,
      'message': text,
      'readBy': [_adminUser?.uid ?? 'circum-support'],
      'system': false,
      'createdAt': FieldValue.serverTimestamp(),
      'timeStamp': DateTime.now().toIso8601String(),
    });
    await chatRef.set({
      'threadId': id,
      'bookingId': id,
      'requestId': id,
      'participants': FieldValue.arrayUnion(['circum-support']),
      'lastMessage': text,
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
      'unreadBy': FieldValue.arrayUnion(['sender', 'rider']),
      'updatedAt': FieldValue.serverTimestamp(),
      'source': 'circum-admin',
    }, SetOptions(merge: true));
  }

  String _formatMessageTime(dynamic timestamp, dynamic fallback) {
    DateTime? date;
    if (timestamp is Timestamp) date = timestamp.toDate();
    if (date == null && fallback is String) date = DateTime.tryParse(fallback);
    if (date == null) return 'Now';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topLeft,
                    radius: 1.1,
                    colors: [
                      Color(0x3322d3ee),
                      Color(0x221e3a8a),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0x22f472b6),
                      Colors.transparent,
                      Color(0x1a14b8a6),
                    ],
                  ),
                ),
              ),
            ),
            Row(
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
                        onSection: (section) =>
                            setState(() => _section = section),
                      ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child:
                              _AdminNotice(colors: colors, message: _message!),
                        ),
                      Expanded(child: _buildSection(colors)),
                    ],
                  ),
                ),
              ],
            ),
            if (_adminChatOpen)
              _ChatSheet(
                colors: colors,
                title: _activeAdminChatTitle,
                recipient: 'CIRCUM Support',
                messages: _adminChatMessages,
                input: _adminChatInput,
                onClose: () => setState(() => _adminChatOpen = false),
                onSend: _sendAdminChatMessage,
              ),
            if (_driverProfileOpen && _selectedDriverProfile != null)
              _AdminDriverProfileDrawer(
                colors: colors,
                driver: _selectedDriverProfile!,
                documents:
                    _documentsForDriver(_driverId(_selectedDriverProfile!)),
                statusLabel: _driverStatusLabel(_selectedDriverProfile!),
                signupDate:
                    _adminDateText(_selectedDriverProfile!['createdAt']),
                completedJobs: _driverJobCount(
                  _driverId(_selectedDriverProfile!),
                  const ['complete', 'delivered'],
                ),
                cancelledJobs: _driverJobCount(
                  _driverId(_selectedDriverProfile!),
                  const ['cancel'],
                ),
                activeJobs: _driverJobCount(
                  _driverId(_selectedDriverProfile!),
                  const ['pending', 'accepted', 'assigned', 'transit'],
                ),
                totalEarnings:
                    _driverTotalEarnings(_driverId(_selectedDriverProfile!)),
                actions: _driverWorkflowActions(_selectedDriverProfile!),
                onClose: () => setState(() => _driverProfileOpen = false),
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
            'vehicleRegistration',
            'vehicleType',
            'approvalStatus',
            'driverStatus',
            'verificationStatus'
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
          columns: const [
            'ID',
            'Route',
            'Status',
            'Weight / IRIS',
            'Price',
            'Actions'
          ],
          rowBuilder: _deliveryRow,
          emptyText: 'No delivery records yet.',
        ),
      _AdminSection.finance => _AdminDataSection(
          colors: colors,
          title: 'Finance',
          subtitle:
              'Payments, refunds, driver payouts, and revenue follow-up. CIRCUM retains 35% to operate the platform, support disputes, payments, safety, and system maintenance.',
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
      _AdminSection.visitors => _AdminDataSection(
          colors: colors,
          title: 'Website visitors',
          subtitle:
              'Recent web visits by route, mode, account status, and timestamp.',
          records: adminSearch(_websiteVisitors, query,
              ['url', 'appMode', 'email', 'userId', 'source']),
          columns: const ['Visit', 'Mode', 'User', 'When'],
          rowBuilder: _visitorRow,
          emptyText: 'No website visits logged yet.',
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
    return [
      _AdminCell.primary('${item['fullName'] ?? item['name'] ?? 'Driver'}'),
      _AdminCell(
        '${item['vehicleColour'] ?? ''} ${item['vehicleMakeModel'] ?? item['vehicleType'] ?? ''}\n${item['plateNumber'] ?? item['vehicleRegistration'] ?? ''}',
      ),
      _AdminStatusCell(
        colors: widget.colors,
        status: _driverStatusLabel(item),
      ),
      _AdminCell('${item['averageRating'] ?? item['rating'] ?? 'New'}'),
      _AdminActions(
        colors: widget.colors,
        actions: _driverWorkflowActions(item),
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
      _AdminCell(_adminIrisWeightSummary(item)),
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
          _AdminAction(
            label: 'Chat',
            enabled: _can(AdminPermission.viewSupport),
            onTap: () => _openAdminChat(item),
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

  List<Widget> _visitorRow(Map<String, dynamic> item) {
    final signedIn = item['signedIn'] == true ? 'Signed in' : 'Guest';
    return [
      _AdminCell.primary('${item['url'] ?? item['path'] ?? ''}'),
      _AdminCell('${item['appMode'] ?? 'web'}'),
      _AdminCell('${item['email'] ?? item['userId'] ?? signedIn}'),
      _AdminCell(_adminDateText(item['createdAt'])),
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
      if (delivery['weightReviewRequired'] == true ||
          '${delivery['weightDisputeStatus'] ?? ''}' == 'admin_review') {
        issues.add({
          'title': 'Weight verification review',
          'recordType': 'deliveryRequests',
          'recordId': id,
          'priority': 'High',
          'status': delivery['weightDisputeStatus'] ?? 'open',
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

  String _adminIrisWeightSummary(Map<String, dynamic> item) {
    final learning = item['irisLearningData'] is Map
        ? Map<String, dynamic>.from(item['irisLearningData'] as Map)
        : const <String, dynamic>{};
    final finalWeight = item['finalWeightUsed'] ??
        item['finalChargeableWeight'] ??
        item['confirmedWeightKg'] ??
        item['weightKg'] ??
        'n/a';
    final source = item['weightSource'] ??
        item['irisWeightSource'] ??
        learning['source'] ??
        'unknown';
    final reason = '${learning['reason'] ?? ''}'.trim();
    final vanguard = item['vanguardEnabled'] == true
        ? '\nVanguard: collection ${item['collectionPinVerified'] == true ? 'passed' : 'pending'}, delivery ${item['deliveryPinVerified'] == true ? 'passed' : 'pending'}'
        : '';
    return reason.isEmpty
        ? '$finalWeight kg\n$source$vanguard'
        : '$finalWeight kg\n$source\n$reason$vanguard';
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
                    columnSpacing: 24,
                    horizontalMargin: 16,
                    dataRowMinHeight: 58,
                    dataRowMaxHeight: 82,
                    headingRowColor: WidgetStatePropertyAll(
                      colors.adminAccent.withOpacity(0.10),
                    ),
                    dataRowColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.hovered)) {
                        return colors.adminAccent.withOpacity(0.08);
                      }
                      return Colors.transparent;
                    }),
                    dividerThickness: 0.5,
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
        color: colors.adminChrome.withOpacity(colors.dark ? 0.9 : 0.82),
        border: Border(right: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff38bdf8).withOpacity(0.12),
            blurRadius: 28,
            offset: const Offset(10, 0),
          ),
        ],
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
        color: colors.adminChrome.withOpacity(colors.dark ? 0.88 : 0.78),
        border: Border(bottom: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff8b5cf6).withOpacity(0.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
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

class _AdminDriverProfileDrawer extends StatelessWidget {
  final _CircumColors colors;
  final Map<String, dynamic> driver;
  final List<Map<String, dynamic>> documents;
  final String statusLabel;
  final String signupDate;
  final int completedJobs;
  final int cancelledJobs;
  final int activeJobs;
  final double totalEarnings;
  final List<_AdminAction> actions;
  final VoidCallback onClose;

  const _AdminDriverProfileDrawer({
    required this.colors,
    required this.driver,
    required this.documents,
    required this.statusLabel,
    required this.signupDate,
    required this.completedJobs,
    required this.cancelledJobs,
    required this.activeJobs,
    required this.totalEarnings,
    required this.actions,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final drawerWidth = width < 720 ? width : 520.0;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.42),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: drawerWidth,
            height: double.infinity,
            decoration: BoxDecoration(
              color: colors.background,
              border: Border(left: BorderSide(color: colors.border)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 28,
                  offset: const Offset(-10, 0),
                ),
              ],
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${driver['fullName'] ?? driver['name'] ?? 'Driver profile'}',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                        color: colors.text,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _AdminStatusCell(colors: colors, status: statusLabel),
                  const SizedBox(height: 18),
                  _GlassPanel(
                    colors: colors,
                    child: Column(
                      children: [
                        _profileRow('Email', '${driver['email'] ?? ''}'),
                        _profileRow(
                          'Phone',
                          '${driver['phone'] ?? driver['phoneNumber'] ?? ''}',
                        ),
                        _profileRow(
                          'Vehicle type',
                          '${driver['vehicleType'] ?? driver['typeOfVehicle'] ?? ''}',
                        ),
                        _profileRow(
                          'Vehicle registration',
                          '${driver['plateNumber'] ?? driver['vehicleRegistration'] ?? ''}',
                        ),
                        _profileRow('Signup date', signupDate),
                        _profileRow(
                          'Rating',
                          '${driver['averageRating'] ?? driver['rating'] ?? 'New'}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _profileStat('Completed jobs', '$completedJobs'),
                      _profileStat('Cancelled jobs', '$cancelledJobs'),
                      _profileStat('Active jobs', '$activeJobs'),
                      _profileStat(
                        'Total earnings',
                        _adminMoneyText(totalEarnings),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _GlassPanel(
                    colors: colors,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Documents',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (documents.isEmpty)
                          Text(
                            'No rider documents found yet.',
                            style: TextStyle(
                              color: colors.mutedText,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else
                          ...documents.map((document) {
                            final url = '${document['downloadUrl'] ?? ''}';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: colors.border),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.description_outlined,
                                      color: colors.text),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${document['type'] ?? document['documentType'] ?? 'Document'}',
                                          style: TextStyle(
                                            color: colors.text,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        Text(
                                          '${document['verificationStatus'] ?? document['status'] ?? 'pending'}',
                                          style: TextStyle(
                                            color: colors.mutedText,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (url.startsWith('http'))
                                    TextButton(
                                      onPressed: () =>
                                          launchUrl(Uri.parse(url)),
                                      child: const Text('Open'),
                                    ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _GlassPanel(
                    colors: colors,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin actions',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _AdminActions(colors: colors, actions: actions),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                color: colors.mutedText,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? 'Not provided' : value,
              style: TextStyle(
                color: colors.text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileStat(String label, String value) {
    return SizedBox(
      width: 150,
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
            const SizedBox(height: 6),
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
      ),
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
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: colors.adminAccent.withOpacity(0.16),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: _spectrumGradient),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
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
        lower.contains('suspend') ||
        lower.contains('reject');
    final color = good
        ? colors.success
        : bad
            ? const Color(0xffdc2626)
            : const Color(0xffca8a04);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(colors.dark ? 0.16 : 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.36)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
    final narrow = MediaQuery.sizeOf(context).width < 768;
    final buttons = actions.map(_buttonFor).toList(growable: false);
    if (narrow) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 260),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              buttons[i],
              if (i != buttons.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 300),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: buttons,
      ),
    );
  }

  Widget _buttonFor(_AdminAction action) {
    final intent = _adminActionColor(action.label);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 108),
      child: OutlinedButton(
        onPressed: action.enabled ? action.onTap : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: intent,
          backgroundColor: intent.withOpacity(colors.dark ? 0.14 : 0.10),
          disabledForegroundColor: colors.mutedText,
          disabledBackgroundColor: colors.field.withOpacity(0.5),
          side: BorderSide(color: intent.withOpacity(0.55)),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          shadowColor: intent.withOpacity(0.26),
          elevation: action.enabled ? 1 : 0,
        ),
        child: Text(
          action.label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Color _adminActionColor(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('approve') ||
        lower.contains('resolve') ||
        lower.contains('delivered') ||
        lower.contains('collected') ||
        lower.contains('reactivate')) {
      return const Color(0xff14b8a6);
    }
    if (lower.contains('failed') ||
        lower.contains('reject') ||
        lower.contains('suspend') ||
        lower.contains('cancel') ||
        lower.contains('delete')) {
      return const Color(0xfff97316);
    }
    if (lower.contains('message') ||
        lower.contains('chat') ||
        lower.contains('view')) {
      return const Color(0xff8b5cf6);
    }
    if (lower.contains('duplicate') || lower.contains('assign')) {
      return const Color(0xff0ea5e9);
    }
    return colors.adminAccent;
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient:
              selected ? const LinearGradient(colors: _spectrumGradient) : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xff38bdf8).withOpacity(0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: ListTile(
          selected: selected,
          onTap: onTap,
          leading: Icon(icon, color: selected ? Colors.white : colors.text),
          title: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : colors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          selectedTileColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
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
    _AdminSection.visitors => 'Visitors',
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
    _AdminSection.visitors => Icons.visibility,
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
  final VoidCallback onHealthPlus;
  final VoidCallback onToggleTheme;

  const _LandingNav({
    required this.colors,
    required this.darkMode,
    required this.onStart,
    required this.onRider,
    required this.onHealthPlus,
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
              if (MediaQuery.sizeOf(context).width >= 680)
                TextButton(
                  onPressed: onHealthPlus,
                  child: Text(
                    'Health+',
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

class _CircumOrderRank {
  final String name;
  final String motto;
  final String title;
  final String badge;
  final IconData icon;

  const _CircumOrderRank({
    required this.name,
    required this.motto,
    required this.title,
    required this.badge,
    required this.icon,
  });

  String get label => name.toUpperCase();
  String get customerLabel => '${_titleCase(name)} $title';
}

const _circumOrderRanks = [
  _CircumOrderRank(
    name: 'Agent',
    motto: 'I Have Joined The Network',
    title: 'Verified by Circum',
    badge: 'AGENT',
    icon: Icons.radio_button_checked,
  ),
  _CircumOrderRank(
    name: 'Sentinel',
    motto: 'I Have Proven Myself',
    title: 'Proven Operator',
    badge: 'SENTINEL',
    icon: Icons.task_alt,
  ),
  _CircumOrderRank(
    name: 'Warden',
    motto: 'Circum Trusts Me',
    title: 'Reliability Specialist',
    badge: 'WARDEN',
    icon: Icons.verified_user_outlined,
  ),
  _CircumOrderRank(
    name: 'Knight',
    motto: 'I Defend The Network',
    title: 'Elite Delivery Specialist',
    badge: 'KNIGHT',
    icon: Icons.workspace_premium_outlined,
  ),
  _CircumOrderRank(
    name: 'Veteran',
    motto: 'I Helped Build This',
    title: 'Circum Veteran',
    badge: 'VETERAN',
    icon: Icons.auto_awesome,
  ),
];

class _CircumOrderSection {
  final String title;
  final List<String> paragraphs;

  const _CircumOrderSection({
    required this.title,
    required this.paragraphs,
  });
}

const _circumOrderCharterSections = [
  _CircumOrderSection(
    title: 'A Declaration of Purpose',
    paragraphs: [
      'Circum was not founded merely to move parcels.',
      'It was founded to move trust.',
      'Every delivery entrusted to our network represents more than an item. It represents a promise.',
      'A promise that something valuable will be collected, protected and delivered by people who understand the responsibility placed upon them.',
      'Technology may power the platform.',
      'Artificial intelligence may assist decision-making.',
      'Systems may coordinate logistics.',
      'But none of these things are the foundation of Circum.',
      'People are.',
      'The strength of Circum has never been software.',
      'The strength of Circum is the character of those who choose to serve within it.',
      'For this reason, Circum rejects the idea that every participant should remain forever anonymous, interchangeable and forgotten.',
      'A person who completes one delivery is not the same as a person who completes one thousand.',
      'A person who builds trust deserves recognition.',
      'A person who helps create value deserves honour.',
      'A person who protects the network deserves remembrance.',
      'The Circum Order exists to recognise this truth.',
    ],
  ),
  _CircumOrderSection(
    title: 'Why The Order Exists',
    paragraphs: [
      'Most platforms reduce people to metrics.',
      'A rating.',
      'A number.',
      'A profile.',
      'A transaction.',
      'Circum believes people are more than data.',
      'Human beings require purpose.',
      'They require progression.',
      'They require achievement.',
      'They require recognition.',
      'Most importantly, they require a reason to remain committed when challenges arise.',
      'The Order exists because contribution matters.',
      'Trust matters.',
      'Service matters.',
      'Character matters.',
      'The Order transforms participation into progression.',
      'It creates a pathway through which every individual may rise through merit, discipline and service.',
      'No promotion is purchased.',
      'No title is gifted.',
      'Every rank is earned.',
    ],
  ),
  _CircumOrderSection(
    title: 'The Journey Begins',
    paragraphs: [
      'Every person who joins Circum begins in the same place.',
      'No exceptions.',
      'No shortcuts.',
      'No privileges.',
      'Everyone begins as an Agent.',
      'This principle is sacred.',
      'The newest recruit and the most respected Veteran share the same origin.',
      'Every Veteran was once an Agent.',
      'Every Knight was once an Agent.',
      'Every Warden was once an Agent.',
      'Every Sentinel was once an Agent.',
      'The Order begins with humility because true trust must always be earned.',
    ],
  ),
  _CircumOrderSection(
    title: 'The Agent',
    paragraphs: [
      '“I Have Joined The Network”',
      'An Agent is ambitious.',
      'An Agent is determined.',
      'An Agent is building a reputation.',
      'The Agent represents possibility.',
      'They are the lifeblood of the network.',
      'They carry the future of Circum.',
      'They are hungry to succeed and eager to prove themselves.',
      'The Order does not view Agents as inexperienced participants.',
      'The Order views Agents as future leaders.',
      'The responsibility of every Agent is simple:',
      'Serve customers well.',
      'Act with integrity.',
      'Build trust through action.',
      'Grow through service.',
    ],
  ),
  _CircumOrderSection(
    title: 'The Sentinel',
    paragraphs: [
      '“I Have Proven Myself”',
      'The title Sentinel was chosen carefully.',
      'A Sentinel is one who watches.',
      'One who remains alert.',
      'One who can be trusted to stand guard over something valuable.',
      'The Sentinel has moved beyond potential.',
      'They have demonstrated reliability.',
      'They have shown consistency.',
      'They have proven through action that they can be trusted.',
      'The Sentinel stands as an example to Agents who follow behind them.',
      'Their reputation has begun to speak before they arrive.',
    ],
  ),
  _CircumOrderSection(
    title: 'The Warden',
    paragraphs: [
      '“Circum Trusts Me”',
      'Trust is one of the rarest commodities in the world.',
      'The Warden is a person who has earned it.',
      'The title Warden represents stewardship.',
      'Responsibility.',
      'Protection.',
      'A Warden does not merely complete deliveries.',
      'A Warden protects the standards of the network.',
      'When uncertainty emerges, Wardens step forward.',
      'When reliability is required, Wardens answer the call.',
      'A Warden understands that their actions affect more than themselves.',
      'They carry responsibility for the reputation of Circum itself.',
    ],
  ),
  _CircumOrderSection(
    title: 'The Knight',
    paragraphs: [
      '“I Defend The Network”',
      'A Knight is not merely trusted.',
      'A Knight is entrusted.',
      'Throughout history, Knights represented honour, loyalty, courage and service.',
      'The Circum Knight embodies the same ideals.',
      'Knights stand ready when challenges arise.',
      'They protect service quality.',
      'They uphold standards.',
      'They answer difficult assignments.',
      'They defend the trust customers place in the platform.',
      'The Knight understands that leadership is not authority.',
      'Leadership is responsibility.',
      'When the network is tested, Knights stand firm.',
    ],
  ),
  _CircumOrderSection(
    title: 'The Veteran',
    paragraphs: [
      '“I Helped Build This”',
      'The highest rank within Circum is Veteran.',
      'This title was chosen because experience alone is not enough.',
      'A person may spend years within a network and contribute very little.',
      'A Veteran is different.',
      'A Veteran creates value.',
      'A Veteran strengthens the network.',
      'A Veteran leaves a legacy.',
      'Veterans are builders.',
      'They helped create the community others now enjoy.',
      'They remained committed when growth was uncertain.',
      'They helped transform an idea into an institution.',
      'Their contribution is remembered.',
      'Their service is honoured.',
      'Their legacy is protected.',
      'The title Veteran is not a reward for surviving.',
      'It is recognition for building.',
    ],
  ),
  _CircumOrderSection(
    title: 'The Principle of Recognition',
    paragraphs: [
      'Circum believes that contribution should never be forgotten.',
      'The people who create value should share in the success they helped create.',
      'The people who protect the network should be recognised.',
      'The people who build trust should be rewarded.',
      'The people who strengthen the community should be remembered.',
      'This principle sits at the heart of the Order.',
      'It is the reason the hierarchy exists.',
      'It is the reason promotions exist.',
      'It is the reason Veterans exist.',
      'Circum does not forget its builders.',
    ],
  ),
  _CircumOrderSection(
    title: 'The Open Market Principle',
    paragraphs: [
      'The Order is not a barrier.',
      'It is not a caste system.',
      'It is not a gatekeeping mechanism.',
      'Every Agent may compete.',
      'Every Agent may grow.',
      'Every Agent may rise.',
      'Opportunity remains open.',
      'The marketplace belongs to everyone.',
      'The Order exists not to restrict opportunity but to recognise merit.',
      'The path upward remains available to all who are willing to earn it.',
    ],
  ),
  _CircumOrderSection(
    title: 'The Circum Declaration',
    paragraphs: [
      'We believe trust is earned.',
      'We believe service matters.',
      'We believe contribution should be recognised.',
      'We believe loyalty should be remembered.',
      'We believe leadership is responsibility.',
      'We believe those who build value deserve honour.',
      'We believe every Veteran was once an Agent.',
      'We believe the strength of Circum is not technology.',
      'The strength of Circum is its people.',
      'And so we commit ourselves to building a network founded upon trust, discipline, service, excellence and legacy.',
      'This is the Circum Order.',
      'This is our charter.',
      'This is our promise.',
      'Every Veteran Was Once An Agent.',
    ],
  ),
];

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value.substring(0, 1).toUpperCase() + value.substring(1).toLowerCase();
}

_CircumOrderRank _circumOrderRankForPerformance(
  DriverPerformanceMetric performance,
) {
  final trips = performance.completedTrips;
  final rating = performance.averageRating;
  if (trips >= 1000 && rating >= 4.7) return _circumOrderRanks[4];
  if (trips >= 500 && rating >= 4.6) return _circumOrderRanks[3];
  if (trips >= 200 && rating >= 4.5) return _circumOrderRanks[2];
  if (trips >= 50 && rating >= 4.2) return _circumOrderRanks[1];
  return _circumOrderRanks[0];
}

String _pdfTextEscape(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');
}

Uri _circumOrderPdfUri() {
  final rawLines = <String>[
    'THE CIRCUM ORDER',
    'Every Veteran Was Once An Agent.',
    '',
    'Founding Charter of the Driver Network',
    '',
    'Agent - I Have Joined The Network',
    'Sentinel - I Have Proven Myself',
    'Warden - Circum Trusts Me',
    'Knight - I Defend The Network',
    'Veteran - I Helped Build This',
    '',
    'Circum rewards contribution.',
    'Those who create value, protect the network, serve customers and',
    'help build the platform will be recognised and rewarded.',
    '',
    ..._circumOrderCharterSections.expand(
      (section) => [
        '',
        section.title,
        ...section.paragraphs.expand((paragraph) => [paragraph, '']),
      ],
    ),
  ];
  final lines = <String>[];
  for (final line in rawLines) {
    if (line.length <= 72) {
      lines.add(line);
      continue;
    }
    final words = line.split(' ');
    var current = '';
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length > 72) {
        lines.add(current);
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) lines.add(current);
  }

  final pages = <List<String>>[];
  for (var i = 0; i < lines.length; i += 28) {
    pages.add(lines.skip(i).take(28).toList());
  }

  final kids = <String>[];
  final objects = <String>[
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
    '',
    '3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
  ];
  var nextObject = 4;
  for (final pageLines in pages) {
    final pageObject = nextObject++;
    final contentObject = nextObject++;
    kids.add('$pageObject 0 R');
    var y = 742;
    final stream = StringBuffer();
    for (final line in pageLines) {
      final isTitle = line == 'THE CIRCUM ORDER';
      final isSectionTitle =
          _circumOrderCharterSections.any((section) => section.title == line);
      final size = isTitle ? 22 : (isSectionTitle ? 15 : 11);
      stream.writeln(
        'BT /F1 $size Tf 72 $y Td (${_pdfTextEscape(line)}) Tj ET',
      );
      y -= line.isEmpty ? 12 : (isSectionTitle ? 24 : 20);
    }
    final content = stream.toString();
    objects.add(
      '$pageObject 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents $contentObject 0 R >>\nendobj\n',
    );
    objects.add(
      '$contentObject 0 obj\n<< /Length ${content.length} >>\nstream\n$content\nendstream\nendobj\n',
    );
  }
  objects[1] =
      '2 0 obj\n<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${pages.length} >>\nendobj\n';
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  var length = buffer.toString().length;
  for (final object in objects) {
    offsets.add(length);
    buffer.write(object);
    length += object.length;
  }
  final xrefOffset = length;
  buffer
    ..writeln('xref')
    ..writeln('0 ${objects.length + 1}')
    ..writeln('0000000000 65535 f ');
  for (final offset in offsets) {
    buffer.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
  }
  buffer
    ..writeln('trailer')
    ..writeln('<< /Size ${objects.length + 1} /Root 1 0 R >>')
    ..writeln('startxref')
    ..writeln('$xrefOffset')
    ..writeln('%%EOF');
  return Uri.parse(
    'data:application/pdf;base64,${base64Encode(ascii.encode(buffer.toString()))}',
  );
}

class _CircumOrderContent extends StatefulWidget {
  final _CircumColors colors;
  final VoidCallback onBecomeRider;

  const _CircumOrderContent({
    required this.colors,
    required this.onBecomeRider,
  });

  @override
  State<_CircumOrderContent> createState() => _CircumOrderContentState();
}

class _CircumOrderContentState extends State<_CircumOrderContent> {
  final _charterKey = GlobalKey();
  final _sectionKeys = List.generate(
    _circumOrderCharterSections.length,
    (_) => GlobalKey(),
  );

  void _readCharter() {
    final context = _charterKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToSection(int index) {
    final context = _sectionKeys[index].currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  Future<void> _downloadCharter() async {
    await launchUrl(_circumOrderPdfUri(), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final narrow = MediaQuery.sizeOf(context).width < 720;
    return ListView(
      padding: EdgeInsets.fromLTRB(narrow ? 18 : 28, 18, narrow ? 18 : 28, 34),
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(narrow ? 22 : 34),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors.dark
                  ? const [
                      Color(0xff050816),
                      Color(0xff221142),
                      Color(0xff173f8a),
                      Color(0xff061826),
                    ]
                  : const [
                      Color(0xffffffff),
                      Color(0xffffeef7),
                      Color(0xffeaf7ff),
                      Color(0xffffffff),
                    ],
            ),
            border: Border.all(color: colors.adminAccent.withOpacity(0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HealthChip(label: 'Riders · The Circum Order'),
              const SizedBox(height: 18),
              Text(
                'THE CIRCUM ORDER',
                style: TextStyle(
                  color: colors.text,
                  fontSize: narrow ? 42 : 68,
                  height: 0.96,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Every Veteran Was Once An Agent.',
                style: TextStyle(
                  color: colors.text,
                  fontSize: narrow ? 23 : 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Founding Charter of the Driver Network',
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: narrow ? 16 : 19,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _readCharter,
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Read Charter'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.text,
                      foregroundColor: colors.inverseText,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _downloadCharter,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Download Charter PDF'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onBecomeRider,
                    icon: const Icon(Icons.two_wheeler),
                    label: const Text('Become a Rider'),
                  ),
                ],
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
              _SectionTitle(colors: colors, title: 'Rank progression'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < _circumOrderRanks.length; i++) ...[
                    _CircumOrderRankCard(
                      colors: colors,
                      rank: _circumOrderRanks[i],
                    ),
                    if (i < _circumOrderRanks.length - 1)
                      Icon(Icons.arrow_forward, color: colors.mutedText),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _GlassPanel(
          key: _charterKey,
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Founding principle'),
              const SizedBox(height: 12),
              Text(
                'Circum rewards contribution.\n\nThose who create value, protect the network, serve customers and help build the platform will be recognised and rewarded.\n\nEvery Veteran Was Once An Agent.',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 18,
                  height: 1.45,
                  fontWeight: FontWeight.w800,
                ),
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
              _SectionTitle(colors: colors, title: 'Charter sections'),
              const SizedBox(height: 10),
              Text(
                'Jump through the founding charter inside the Riders experience.',
                style: TextStyle(
                  color: colors.mutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _circumOrderCharterSections.length; i++)
                    ActionChip(
                      label: Text(
                        '${i + 1}. ${_circumOrderCharterSections[i].title}',
                      ),
                      onPressed: () => _scrollToSection(i),
                      backgroundColor: colors.field,
                      side: BorderSide(color: colors.border),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < _circumOrderCharterSections.length; i++) ...[
          _CircumOrderCharterCard(
            key: _sectionKeys[i],
            colors: colors,
            index: i + 1,
            section: _circumOrderCharterSections[i],
          ),
          const SizedBox(height: 18),
        ],
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Future rank data'),
              const SizedBox(height: 10),
              Text(
                'This layout can later attach delivery requirements, profit-share percentages, badges, benefits, and promotion criteria to each rank without redesigning the Riders page.',
                style: TextStyle(
                  color: colors.mutedText,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CircumOrderCharterCard extends StatelessWidget {
  final _CircumColors colors;
  final int index;
  final _CircumOrderSection section;

  const _CircumOrderCharterCard({
    super.key,
    required this.colors,
    required this.index,
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            index.toString().padLeft(2, '0'),
            style: TextStyle(
              color: colors.adminAccent,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            section.title,
            style: TextStyle(
              color: colors.text,
              fontSize: MediaQuery.sizeOf(context).width < 680 ? 24 : 34,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          for (final paragraph in section.paragraphs) ...[
            Text(
              paragraph,
              style: TextStyle(
                color: colors.mutedText,
                fontSize: 16,
                height: 1.55,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _CircumOrderRankCard extends StatelessWidget {
  final _CircumColors colors;
  final _CircumOrderRank rank;

  const _CircumOrderRankCard({
    required this.colors,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(rank.icon, color: colors.text),
          const SizedBox(height: 10),
          Text(
            rank.badge,
            style: TextStyle(
              color: colors.text,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rank.motto,
            style: TextStyle(
              color: colors.mutedText,
              height: 1.25,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            rank.title,
            style: TextStyle(
              color: colors.text,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderOrderProfileCard extends StatelessWidget {
  final _CircumColors colors;
  final Map<String, dynamic>? profile;
  final DriverPerformanceMetric performance;

  const _RiderOrderProfileCard({
    required this.colors,
    required this.profile,
    required this.performance,
  });

  @override
  Widget build(BuildContext context) {
    final rank = _circumOrderRankForPerformance(performance);
    final name = '${profile?['fullName'] ?? profile?['email'] ?? 'Rider'}';
    final rating = performance.averageRating <= 0
        ? 'New'
        : performance.averageRating.toStringAsFixed(2);
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
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: _spectrumGradient),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xff8c28ff).withOpacity(0.28),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: Icon(rank.icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rank.badge,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      rank.title,
                      style: TextStyle(
                        color: colors.mutedText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _HealthChip(label: 'The Circum Order'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            name,
            style: TextStyle(
              color: colors.text,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _RiderStatTile(
                  colors: colors,
                  label: 'Deliveries',
                  value: '${performance.completedTrips}',
                ),
              ),
              const SizedBox(width: 10),
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
                  label: 'Member since',
                  value: _adminDateText(profile?['createdAt']),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _RiderPortalTab { overview, earnings, referrals, order }

String _riderTabLabel(_RiderPortalTab tab) {
  return switch (tab) {
    _RiderPortalTab.overview => 'Overview',
    _RiderPortalTab.earnings => 'Earnings',
    _RiderPortalTab.referrals => 'Referrals',
    _RiderPortalTab.order => 'The Circum Order',
  };
}

IconData _riderTabIcon(_RiderPortalTab tab) {
  return switch (tab) {
    _RiderPortalTab.overview => Icons.dashboard_outlined,
    _RiderPortalTab.earnings => Icons.payments_outlined,
    _RiderPortalTab.referrals => Icons.group_add_outlined,
    _RiderPortalTab.order => Icons.auto_awesome,
  };
}

class _RiderPortalTabs extends StatelessWidget {
  final _CircumColors colors;
  final _RiderPortalTab selected;
  final ValueChanged<_RiderPortalTab> onSelected;

  const _RiderPortalTabs({
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in _RiderPortalTab.values) ...[
              ChoiceChip(
                selected: selected == tab,
                avatar: Icon(_riderTabIcon(tab), size: 18),
                label: Text(_riderTabLabel(tab)),
                onSelected: (_) => onSelected(tab),
                selectedColor: colors.text,
                backgroundColor: colors.field,
                labelStyle: TextStyle(
                  color: selected == tab ? colors.inverseText : colors.text,
                  fontWeight: FontWeight.w900,
                ),
                side: BorderSide(color: colors.border),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _RiderEarningsTab extends StatelessWidget {
  final _CircumColors colors;
  final _RiderEarningsSnapshot earnings;

  const _RiderEarningsTab({
    required this.colors,
    required this.earnings,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
      children: [
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Rider earnings'),
              const SizedBox(height: 10),
              Text(
                'Drivers earn 65% of each completed delivery. Track completed jobs, available balance, pending withdrawals, tips, and lifetime earnings from your rider dashboard.',
                style: TextStyle(
                  color: colors.mutedText,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _RiderStatTile(
                      colors: colors,
                      label: 'Available',
                      value: _RiderWorkspace._money(earnings.availableBalance),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _RiderStatTile(
                      colors: colors,
                      label: 'Tips',
                      value: _RiderWorkspace._money(earnings.tipsReceived),
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
                      value: _RiderWorkspace._money(earnings.lifetimeEarnings),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _RiderStatTile(
                      colors: colors,
                      label: 'Completed',
                      value: '${earnings.completedJobs}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RiderReferralsTab extends StatelessWidget {
  final _CircumColors colors;

  const _RiderReferralsTab({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
      children: [
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Referrals'),
              const SizedBox(height: 10),
              Text(
                'Invite reliable operators into the Circum network. Referral rewards, eligibility rules, and progress tracking can be attached here when the referral programme launches.',
                style: TextStyle(
                  color: colors.mutedText,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _HealthChip(label: 'Future rewards'),
                  _HealthChip(label: 'Trusted operators'),
                  _HealthChip(label: 'Network growth'),
                ],
              ),
            ],
          ),
        ),
      ],
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
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmNewPassword = TextEditingController();
  final _newEmail = TextEditingController();
  final _emailChangePassword = TextEditingController();
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
  bool _securitySubmitting = false;
  bool _submitting = false;
  bool _withdrawSubmitting = false;
  bool _documentSubmitting = false;
  bool _saveBank = true;
  bool _roleChoiceConfirmed = false;
  User? _riderUser;
  _RiderEarningsSnapshot _earnings = _RiderEarningsSnapshot.empty();
  String? _message;
  String? _authMessage;
  String? _securityMessage;
  String? _withdrawMessage;
  String? _documentMessage;
  String? _applicationId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _earningsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _performanceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ratingSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _availableJobsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _acceptedJobsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _completedJobsSub;
  DriverPerformanceMetric _performance =
      DriverPerformanceMetric.empty('web-rider');
  List<DriverRating> _recentRatings = const [];
  List<Map<String, dynamic>> _availableJobs = const [];
  List<Map<String, dynamic>> _acceptedJobs = const [];
  List<Map<String, dynamic>> _completedJobs = const [];
  Map<String, dynamic>? _riderProfile;
  Set<CircumRole> _availableRoles = const {};
  late _RiderPortalTab _riderTab = _initialRiderTab();
  String? _jobMessage;
  bool _riderChatOpen = false;
  Map<String, dynamic>? _activeRiderChatJob;
  final _riderChatInput = TextEditingController();
  final List<_ChatMessage> _riderChatMessages = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _riderChatSub;
  Timer? _riderLiveLocationTimer;
  String? _trackingDeliveryId;

  @override
  void initState() {
    super.initState();
    _restoreRiderSession();
  }

  _RiderPortalTab _initialRiderTab() {
    final section = Uri.base.queryParameters['section'] ??
        Uri.base.queryParameters['tab'] ??
        Uri.base.queryParameters['app'];
    return switch (section) {
      'earnings' => _RiderPortalTab.earnings,
      'referrals' => _RiderPortalTab.referrals,
      'circum-order' || 'order' => _RiderPortalTab.order,
      _ => _RiderPortalTab.overview,
    };
  }

  @override
  void dispose() {
    _earningsSub?.cancel();
    _performanceSub?.cancel();
    _ratingSub?.cancel();
    _availableJobsSub?.cancel();
    _acceptedJobsSub?.cancel();
    _completedJobsSub?.cancel();
    _riderChatSub?.cancel();
    _stopRiderLiveLocationPublishing(status: 'offline');
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmNewPassword.dispose();
    _newEmail.dispose();
    _emailChangePassword.dispose();
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
    _riderChatInput.dispose();
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
      final riderProfile = await _loadRiderProfile(user.uid);
      setState(() {
        _riderUser = user;
        _riderProfile = riderProfile;
        _email.text = user.email ?? _email.text;
        _roleChoiceConfirmed = false;
      });
      _listenToRiderEarnings(user.uid);
      _listenToRiderPerformance(user.uid);
      _listenToAvailableJobs();
      _listenToRiderJobs(user.uid);
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
        _riderProfile = await _loadRiderProfile(user.uid);
        _availableRoles = {CircumRole.rider};
      } else if (!await _allowRiderUser(user)) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() => _authMessage =
            'This account is not a rider account. Use sender login or the admin site instead.');
        return;
      } else {
        _riderProfile = await _loadRiderProfile(user.uid);
      }
      _listenToRiderEarnings(user.uid);
      _listenToRiderPerformance(user.uid);
      _listenToAvailableJobs();
      _listenToRiderJobs(user.uid);
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

  Future<void> _sendRiderPasswordReset() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _authMessage = 'Enter your email address first.');
      return;
    }
    setState(() {
      _authSubmitting = true;
      _authMessage = 'Sending password reset email...';
    });
    try {
      await _ensureCircumFirebaseReady();
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() => _authMessage =
          'Password reset sent. Check your email and follow the secure link.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _authMessage = switch (error.code) {
            'invalid-email' => 'Enter a valid email address.',
            'user-not-found' => 'No rider account found for that email.',
            _ =>
              'We could not send the reset email. Check the address and try again.',
          });
    } finally {
      if (mounted) setState(() => _authSubmitting = false);
    }
  }

  Future<UserCredential> _reauthenticateRider(String password) async {
    final user = _riderUser ?? FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'requires-recent-login',
        message: 'Sign in again before changing account security settings.',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    return user.reauthenticateWithCredential(credential);
  }

  Future<void> _changeRiderPassword() async {
    if (_securitySubmitting) return;
    final current = _currentPassword.text.trim();
    final next = _newPassword.text.trim();
    final confirm = _confirmNewPassword.text.trim();
    if (current.isEmpty || next.length < 6 || next != confirm) {
      setState(() => _securityMessage =
          'Enter your current password and make sure the new passwords match.');
      return;
    }
    setState(() {
      _securitySubmitting = true;
      _securityMessage = 'Updating password...';
    });
    try {
      await _ensureCircumFirebaseReady();
      await _reauthenticateRider(current);
      await (_riderUser ?? FirebaseAuth.instance.currentUser)
          ?.updatePassword(next);
      _currentPassword.clear();
      _newPassword.clear();
      _confirmNewPassword.clear();
      if (!mounted) return;
      setState(() => _securityMessage = 'Password updated.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _securityMessage = _friendlyAuthMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _securityMessage = 'Could not update password.');
    } finally {
      if (mounted) setState(() => _securitySubmitting = false);
    }
  }

  Future<void> _changeRiderEmail() async {
    if (_securitySubmitting) return;
    final nextEmail = _newEmail.text.trim();
    final password = _emailChangePassword.text.trim();
    if (nextEmail.isEmpty || !nextEmail.contains('@') || password.isEmpty) {
      setState(() =>
          _securityMessage = 'Enter the new email and your current password.');
      return;
    }
    setState(() {
      _securitySubmitting = true;
      _securityMessage = 'Updating email...';
    });
    try {
      await _ensureCircumFirebaseReady();
      await _reauthenticateRider(password);
      final user = _riderUser ?? FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(code: 'requires-recent-login');
      }
      await user.verifyBeforeUpdateEmail(nextEmail);
      await FirebaseFirestore.instance
          .collection('riderProfiles')
          .doc(user.uid)
          .set({
        'pendingEmail': nextEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _newEmail.clear();
      _emailChangePassword.clear();
      if (!mounted) return;
      setState(() => _securityMessage =
          'Verification sent. Open the email link to confirm the new address.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _securityMessage = _friendlyAuthMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _securityMessage = 'Could not update email.');
    } finally {
      if (mounted) setState(() => _securitySubmitting = false);
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

  Future<Map<String, dynamic>?> _loadRiderProfile(String uid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('riderProfiles')
        .doc(uid)
        .get();
    if (!snapshot.exists) return null;
    return {'id': snapshot.id, ...?snapshot.data()};
  }

  String _riderApprovalStatus() {
    final profile = _riderProfile;
    if (profile == null) return 'missing';
    final approval = '${profile['approvalStatus'] ?? ''}'.trim().toLowerCase();
    if (approval == 'pending' ||
        approval == 'approved' ||
        approval == 'rejected' ||
        approval == 'suspended') {
      return approval;
    }

    final verification =
        '${profile['verificationStatus'] ?? ''}'.trim().toLowerCase();
    if (verification == 'approved' || verification == 'verified') {
      return 'approved';
    }
    if (verification == 'rejected') return 'rejected';
    if (verification == 'suspended') return 'suspended';
    return 'pending';
  }

  Future<void> _saveRiderProfile(User user) async {
    final db = FirebaseFirestore.instance;
    await db.collection('riderProfiles').doc(user.uid).set({
      'uid': user.uid,
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
      'vehicleRegistration': _plateNumber.text.trim(),
      'vehicle': DriverVehicle(
        type: _vehicle.text.trim(),
        makeModel: _vehicleMakeModel.text.trim(),
        colour: _vehicleColour.text.trim(),
        plateNumber: _plateNumber.text.trim(),
      ).toJson(),
      'availability': _availability.text.trim(),
      'approvalStatus': 'pending',
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
      'tipsReceived': FieldValue.increment(0),
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

  void _listenToAvailableJobs() {
    _availableJobsSub?.cancel();
    _availableJobsSub = FirebaseFirestore.instance
        .collection('deliveryRequests')
        .where('status', isEqualTo: 'requested')
        .limit(20)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        final jobs = snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .where((job) {
          final matchingStatus =
              '${job['matchingStatus'] ?? 'available'}'.toLowerCase();
          final ignoredBy = (job['ignoredByRiders'] as List?) ?? const [];
          final rejectedBy = (job['rejectedByRiders'] as List?) ?? const [];
          final currentRider = _riderUser?.uid;
          if (currentRider != null &&
              (ignoredBy.contains(currentRider) ||
                  rejectedBy.contains(currentRider))) {
            return false;
          }
          return matchingStatus == 'available' || matchingStatus == 'requested';
        }).toList();
        jobs.sort(_compareRiderJobs);
        _availableJobs = jobs;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _jobMessage = 'Could not load available jobs right now.');
    });
  }

  int _compareRiderJobs(Map<String, dynamic> a, Map<String, dynamic> b) {
    final serviceA = '${a['selectedServiceLevel'] ?? a['serviceLevel'] ?? ''}';
    final serviceB = '${b['selectedServiceLevel'] ?? b['serviceLevel'] ?? ''}';
    final priorityCompare = DeliveryPricing.matchingPriorityRank(serviceA)
        .compareTo(DeliveryPricing.matchingPriorityRank(serviceB));
    if (priorityCompare != 0) return priorityCompare;

    final pickupCompare =
        '${a['scheduledPickupDate'] ?? ''} ${a['scheduledPickupWindow'] ?? ''}'
            .compareTo(
                '${b['scheduledPickupDate'] ?? ''} ${b['scheduledPickupWindow'] ?? ''}');
    if (pickupCompare != 0) return pickupCompare;

    return _jobDistanceMiles(a).compareTo(_jobDistanceMiles(b));
  }

  void _listenToRiderJobs(String riderId) {
    _acceptedJobsSub?.cancel();
    _completedJobsSub?.cancel();
    _acceptedJobsSub = FirebaseFirestore.instance
        .collection('deliveryRequests')
        .where('riderId', isEqualTo: riderId)
        .where('status', whereIn: ['accepted', 'picked_up', 'in_transit'])
        .limit(20)
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          setState(() {
            _acceptedJobs = snapshot.docs
                .map((doc) => {'id': doc.id, ...doc.data()})
                .toList(growable: false);
          });
          _syncRiderLiveLocationPublishing();
        }, onError: (_) {
          if (!mounted) return;
          setState(() => _jobMessage = 'Could not load accepted jobs.');
        });
    _completedJobsSub = FirebaseFirestore.instance
        .collection('deliveryRequests')
        .where('riderId', isEqualTo: riderId)
        .where('status', isEqualTo: 'completed')
        .limit(20)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _completedJobs = snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList(growable: false);
      });
    });
  }

  Future<void> _acceptDeliveryJob(Map<String, dynamic> job) async {
    final user = _riderUser;
    if (user == null) {
      setState(() => _jobMessage = 'Sign in before accepting a job.');
      return;
    }
    final requestId = '${job['requestId'] ?? job['id'] ?? ''}'.trim();
    if (requestId.isEmpty) return;
    setState(() => _jobMessage = 'Accepting job $requestId...');
    try {
      await _ensureCircumFirebaseReady();
      final db = FirebaseFirestore.instance;
      final riderDoc = await db.collection('riderProfiles').doc(user.uid).get();
      final rider = riderDoc.data() ?? const <String, dynamic>{};
      await db.collection('deliveryRequests').doc(requestId).set({
        'status': 'accepted',
        'dispatchStatus': 'accepted',
        'matchingStatus': 'accepted',
        'riderId': user.uid,
        'driverId': user.uid,
        'assignedDriverId': user.uid,
        'riderName': rider['fullName'] ?? user.displayName ?? user.email,
        'driverName': rider['fullName'] ?? user.displayName ?? user.email,
        'driverVehicle': rider['vehicle'],
        'driverPlateNumber': rider['plateNumber'],
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _startRiderLiveLocationPublishing(requestId, user.uid, 'accepted');
      await db.collection('chats').doc(requestId).set({
        'threadId': requestId,
        'bookingId': requestId,
        'requestId': requestId,
        'participants': FieldValue.arrayUnion([user.uid, 'circum-support']),
        'participantRoles': {
          user.uid: 'rider',
          'circum-support': 'admin',
        },
        'assignedRiderId': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'circum-web',
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _jobMessage = 'Job accepted. Head to pickup.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _jobMessage = 'Could not accept this job. Try again.');
    }
  }

  void _syncRiderLiveLocationPublishing() {
    final user = _riderUser;
    if (user == null) {
      _stopRiderLiveLocationPublishing(status: 'offline');
      return;
    }
    final activeJob = _acceptedJobs.cast<Map<String, dynamic>?>().firstWhere(
      (job) {
        final status = '${job?['status'] ?? ''}'.toLowerCase();
        return status == 'accepted' ||
            status == 'picked_up' ||
            status == 'in_transit' ||
            status == 'in_progress';
      },
      orElse: () => null,
    );
    if (activeJob == null) {
      _stopRiderLiveLocationPublishing(status: 'offline');
      return;
    }
    final requestId =
        '${activeJob['requestId'] ?? activeJob['id'] ?? ''}'.trim();
    final status = '${activeJob['status'] ?? 'accepted'}'.toLowerCase();
    if (requestId.isEmpty || requestId == _trackingDeliveryId) return;
    _startRiderLiveLocationPublishing(requestId, user.uid, status);
  }

  Future<void> _startRiderLiveLocationPublishing(
    String deliveryId,
    String riderId,
    String status,
  ) async {
    if (_trackingDeliveryId == deliveryId && _riderLiveLocationTimer != null) {
      return;
    }
    _stopRiderLiveLocationPublishing(status: 'switching');
    final allowed = await _ensureRiderLocationPermission();
    if (!allowed) {
      if (mounted) {
        setState(() => _jobMessage =
            'Location permission is needed for live tracking while travelling.');
      }
      return;
    }
    _trackingDeliveryId = deliveryId;
    await _publishRiderLiveLocation(deliveryId, riderId, status);
    _riderLiveLocationTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      _publishRiderLiveLocation(deliveryId, riderId, status);
    });
  }

  void _stopRiderLiveLocationPublishing({required String status}) {
    final deliveryId = _trackingDeliveryId;
    final riderId = _riderUser?.uid;
    _riderLiveLocationTimer?.cancel();
    _riderLiveLocationTimer = null;
    _trackingDeliveryId = null;
    if (deliveryId != null && riderId != null) {
      FirebaseFirestore.instance
          .collection('deliveryRequests')
          .doc(deliveryId)
          .collection('tracking')
          .doc('liveLocation')
          .set({
        'riderId': riderId,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<bool> _ensureRiderLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  Future<void> _publishRiderLiveLocation(
    String deliveryId,
    String riderId,
    String status,
  ) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      await FirebaseFirestore.instance
          .collection('deliveryRequests')
          .doc(deliveryId)
          .collection('tracking')
          .doc('liveLocation')
          .set({
        'riderId': riderId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'heading': position.heading,
        'speed': position.speed,
        'accuracy': position.accuracy,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      if (mounted) {
        setState(() => _jobMessage = 'Live tracking update could not be sent.');
      }
    }
  }

  Future<void> _rejectOrIgnoreJob(
    Map<String, dynamic> job,
    String action,
  ) async {
    final user = _riderUser;
    if (user == null) {
      setState(() => _jobMessage = 'Sign in before updating a job.');
      return;
    }
    final requestId = '${job['requestId'] ?? job['id'] ?? ''}'.trim();
    if (requestId.isEmpty) return;
    final field = action == 'reject' ? 'rejectedByRiders' : 'ignoredByRiders';
    final timestampField = action == 'reject' ? 'rejectedAt' : 'ignoredAt';
    try {
      await FirebaseFirestore.instance
          .collection('deliveryRequests')
          .doc(requestId)
          .set({
        field: FieldValue.arrayUnion([user.uid]),
        timestampField: FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _jobMessage =
          action == 'reject' ? 'Job rejected.' : 'Job hidden for now.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _jobMessage = 'Could not update this job. Try again.');
    }
  }

  Future<void> _updateAcceptedJobStatus(
    Map<String, dynamic> job,
    String status,
  ) async {
    final user = _riderUser;
    if (user == null) {
      setState(() => _jobMessage = 'Sign in before updating a job.');
      return;
    }
    final requestId = '${job['requestId'] ?? job['id'] ?? ''}'.trim();
    if (requestId.isEmpty) return;
    setState(() => _jobMessage = 'Updating job $requestId...');
    try {
      final db = FirebaseFirestore.instance;
      final vanguardPatch = await _collectVanguardPinVerification(
        job,
        requestId,
        user.uid,
        status,
      );
      if (vanguardPatch == null &&
          _jobVanguardEnabled(job) &&
          (status == 'picked_up' || status == 'completed')) {
        return;
      }
      final verificationPatch = status == 'picked_up'
          ? await _collectWeightVerification(job, requestId, user.uid)
          : null;
      if (status == 'picked_up' && verificationPatch == null) {
        if (!mounted) return;
        setState(() => _jobMessage = 'Verify parcel weight before pickup.');
        return;
      }
      final updates = <String, dynamic>{
        'status': status,
        'dispatchStatus': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (status == 'picked_up') {
        updates['pickedUpAt'] = FieldValue.serverTimestamp();
        if (vanguardPatch != null) updates.addAll(vanguardPatch);
        updates.addAll(verificationPatch!);
      }
      if (status == 'in_transit') {
        updates['outForDeliveryAt'] = FieldValue.serverTimestamp();
      }
      if (status == 'completed') {
        updates['completedAt'] = FieldValue.serverTimestamp();
        if (vanguardPatch != null) updates.addAll(vanguardPatch);
        final payout = _jobPayout(job);
        final tip = _jobTip(job);
        final totalCredit = payout + tip;
        final txId = '${requestId}_${user.uid}_completion';
        final deliveryRef = db.collection('deliveryRequests').doc(requestId);
        final walletRef = db.collection('riderWalletTransactions').doc(txId);
        final earningsRef = db.collection('riderEarnings').doc(user.uid);
        await db.runTransaction((transaction) async {
          final existingWallet = await transaction.get(walletRef);
          transaction.set(deliveryRef, updates, SetOptions(merge: true));
          if (existingWallet.exists) return;
          transaction.set(
            walletRef,
            {
              'transactionId': txId,
              'requestId': requestId,
              'riderId': user.uid,
              'type': 'job_completed',
              'deliveryEarning': payout,
              'tipAmount': tip,
              'amount': totalCredit,
              'status': 'available',
              'createdAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          transaction.set(
            earningsRef,
            {
              'availableBalance': FieldValue.increment(totalCredit),
              'lifetimeEarnings': FieldValue.increment(totalCredit),
              'tipsReceived': FieldValue.increment(tip),
              'completedJobs': FieldValue.increment(1),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        });
      } else {
        await db
            .collection('deliveryRequests')
            .doc(requestId)
            .set(updates, SetOptions(merge: true));
      }
      if (status == 'completed' || status == 'cancelled') {
        _stopRiderLiveLocationPublishing(status: status);
      }
      if (!mounted) return;
      setState(() => _jobMessage = status == 'completed'
          ? 'Job completed. Earnings updated.'
          : 'Job updated.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _jobMessage = 'Could not update this job. Try again.');
    }
  }

  Future<Map<String, dynamic>?> _collectVanguardPinVerification(
    Map<String, dynamic> job,
    String requestId,
    String riderId,
    String status,
  ) async {
    if (!_jobVanguardEnabled(job) ||
        (status != 'picked_up' && status != 'completed')) {
      return const <String, dynamic>{};
    }
    final stage = status == 'completed' ? 'delivery' : 'collection';
    final alreadyVerified = stage == 'delivery'
        ? job['deliveryPinVerified'] == true
        : job['collectionPinVerified'] == true;
    if (alreadyVerified) return const <String, dynamic>{};

    final summary =
        (job['driverJobSummary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final collectionContact =
        (job['collectionContact'] as Map?)?.cast<String, dynamic>();
    final receiverDetails =
        (job['receiverDetails'] as Map?)?.cast<String, dynamic>();
    final collectionName =
        '${summary['collectionContactName'] ?? job['collectionContactName'] ?? collectionContact?['name'] ?? job['senderName'] ?? 'the sender or collection contact'}'
            .trim();
    final receiverName =
        '${summary['receiverName'] ?? job['receiverName'] ?? receiverDetails?['name'] ?? 'the receiver'}'
            .trim();
    final pinController = TextEditingController();
    String? errorText;
    final enteredPin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(stage == 'delivery'
              ? 'Enter delivery PIN'
              : 'Enter collection PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stage == 'delivery'
                    ? 'This is a Vanguard protected delivery. Enter ${receiverName.isEmpty ? 'the receiver' : receiverName}’s delivery PIN to complete delivery.'
                    : 'This is a Vanguard protected delivery. Enter ${collectionName.isEmpty ? 'the sender or collection contact' : collectionName}’s collection PIN to confirm handover.',
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: '6-digit PIN',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = pinController.text.trim();
                if (!RegExp(r'^\d{6}$').hasMatch(value)) {
                  setDialogState(
                      () => errorText = 'Enter the 6-digit Vanguard PIN.');
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('Verify PIN'),
            ),
          ],
        ),
      ),
    );
    pinController.dispose();
    if (enteredPin == null) {
      setState(() => _jobMessage = stage == 'delivery'
          ? 'Delivery PIN required before completion.'
          : 'Collection PIN required before pickup.');
      return null;
    }

    final attemptField = stage == 'delivery'
        ? 'deliveryPinAttemptCount'
        : 'collectionPinAttemptCount';
    final attemptCount = _numberValue(job[attemptField])?.toInt() ?? 0;
    final expectedPin = stage == 'delivery'
        ? VanguardProtection.deliveryPin(job)
        : VanguardProtection.collectionPin(job);
    final check = VanguardProtection.verifyPin(
      enabled: true,
      expectedPin: expectedPin,
      enteredPin: enteredPin,
      attemptCount: attemptCount,
      stage: stage,
    );
    if (!check.passed) {
      await FirebaseFirestore.instance
          .collection('deliveryRequests')
          .doc(requestId)
          .set({
        attemptField: check.attemptCount,
        'vanguardReviewRequired': check.flagForReview,
        'vanguardLastFailedStage': stage,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return null;
      setState(() => _jobMessage = check.errorMessage);
      return null;
    }

    final protection =
        (job['vanguardProtection'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final nextProtection = {
      ...protection,
      stage == 'delivery' ? 'deliveryPin' : 'collectionPin': null,
    };
    final verifiedField =
        stage == 'delivery' ? 'deliveryPinVerified' : 'collectionPinVerified';
    final verifiedAtField = stage == 'delivery'
        ? 'deliveryPinVerifiedAt'
        : 'collectionPinVerifiedAt';
    final verifiedByField = stage == 'delivery'
        ? 'deliveryPinVerifiedBy'
        : 'collectionPinVerifiedBy';
    return {
      verifiedField: true,
      verifiedAtField: FieldValue.serverTimestamp(),
      verifiedByField: riderId,
      attemptField: check.attemptCount,
      'vanguardProtection': nextProtection,
      'vanguardVerification': {
        stage: {
          'status': 'passed',
          'riderId': riderId,
          'verifiedAt': FieldValue.serverTimestamp(),
          'attemptCount': check.attemptCount,
        },
      },
    };
  }

  bool _jobVanguardEnabled(Map<String, dynamic> job) {
    if (job['vanguardEnabled'] == true) return true;
    final protection =
        (job['vanguardProtection'] as Map?)?.cast<String, dynamic>();
    return protection?['enabled'] == true;
  }

  Future<Map<String, dynamic>?> _collectWeightVerification(
    Map<String, dynamic> job,
    String requestId,
    String riderId,
  ) async {
    final currentFinalWeight = _jobFinalWeight(job);
    final weightController =
        TextEditingController(text: currentFinalWeight.toStringAsFixed(1));
    final noteController = TextEditingController();
    var option = 'accurate';
    var pickedPhotos = <XFile>[];
    String? errorText;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Verify parcel weight'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Before pickup, confirm whether the parcel matches the paid weight. Evidence is required for increases.',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  value: 'accurate',
                  groupValue: option,
                  onChanged: (value) =>
                      setDialogState(() => option = value ?? option),
                  title: const Text('Confirm weight is accurate'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  value: 'heavier',
                  groupValue: option,
                  onChanged: (value) =>
                      setDialogState(() => option = value ?? option),
                  title: const Text('Weight is heavier than declared'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  value: 'significant',
                  groupValue: option,
                  onChanged: (value) =>
                      setDialogState(() => option = value ?? option),
                  title: const Text('Weight is significantly heavier'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: weightController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Verified weight in kg',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Optional note',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await ImagePicker()
                        .pickMultiImage(imageQuality: 80, maxWidth: 1800);
                    setDialogState(() => pickedPhotos = picked);
                  },
                  icon: const Icon(Icons.photo_camera),
                  label: Text(pickedPhotos.isEmpty
                      ? 'Add evidence photo'
                      : '${pickedPhotos.length} photo(s) added'),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(errorText!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final verifiedWeight =
                    double.tryParse(weightController.text.trim()) ?? 0;
                final requiresEvidence = option != 'accurate';
                if (verifiedWeight <= 0) {
                  setDialogState(() => errorText = 'Enter a valid weight.');
                  return;
                }
                if (requiresEvidence && verifiedWeight <= currentFinalWeight) {
                  setDialogState(() => errorText =
                      'Corrected weight must be higher than the current paid weight.');
                  return;
                }
                if (requiresEvidence && pickedPhotos.isEmpty) {
                  setDialogState(
                      () => errorText = 'Add at least one evidence photo.');
                  return;
                }
                Navigator.pop(context, {
                  'option': option,
                  'verifiedWeightKg': verifiedWeight,
                  'note': noteController.text.trim(),
                  'photos': pickedPhotos,
                });
              },
              child: const Text('Save verification'),
            ),
          ],
        ),
      ),
    );
    weightController.dispose();
    noteController.dispose();
    if (result == null) return null;

    final optionValue = '${result['option']}';
    final verifiedWeight = result['verifiedWeightKg'] as double;
    final photos = (result['photos'] as List<XFile>? ?? const <XFile>[]);
    final evidenceUrls = <String>[];
    final storagePaths = <String>[];
    for (final photo in photos) {
      final bytes = await photo.readAsBytes();
      final safeName = photo.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path =
          'delivery_weight_evidence/$requestId/$riderId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes);
      storagePaths.add(path);
      evidenceUrls.add(await ref.getDownloadURL());
    }

    final customerWeight = _jobCustomerWeight(job);
    final irisWeight = _jobIrisWeight(job);
    final finalWeightUsed = DeliveryPricing.finalVerifiedWeightKg(
      customerWeightKg: customerWeight,
      irisWeightKg: irisWeight,
      riderVerifiedWeightKg: verifiedWeight,
    );
    final distanceMiles = _jobDistanceMiles(job);
    final vehicle =
        DeliveryPricing.recommendedVehicleForWeight(finalWeightUsed);
    final revisedQuote = DeliveryPricing.calculate(DeliveryPricingInput(
      distanceMiles: distanceMiles,
      weightKg: finalWeightUsed,
      vehicleType: vehicle,
    ));
    final revisedPayout =
        DeliveryPricing.riderPayoutFromFare(revisedQuote.total);
    final revisedPlatformRevenue =
        DeliveryPricing.platformRevenueFromFare(revisedQuote.total);
    final heavier = finalWeightUsed > currentFinalWeight + 0.01;
    final summary =
        (job['driverJobSummary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};

    if (heavier) {
      await FirebaseFirestore.instance.collection('notifications').add({
        'recipientId': job['senderId'] ?? job['userId'],
        'requestId': requestId,
        'type': 'weight_adjusted',
        'title': 'Parcel weight updated',
        'message':
            'Parcel weight differs from original declaration. Pricing has been adjusted.',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
        'source': 'circum-web',
      });
    }

    return {
      'riderVerifiedWeight': verifiedWeight,
      'riderVerifiedWeightKg': verifiedWeight,
      'finalVerifiedWeight': finalWeightUsed,
      'finalWeightUsed': finalWeightUsed,
      'finalChargeableWeight': finalWeightUsed,
      'confirmedWeightKg': finalWeightUsed,
      'confirmedWeightBand':
          DeliveryPricing.weightBandFor(finalWeightUsed).category,
      'weightCategory': DeliveryPricing.weightBandFor(finalWeightUsed).category,
      'vehicleType': vehicle,
      'vehicle': vehicle,
      'preferredVehicle': vehicle.toLowerCase(),
      'quote': revisedQuote.total,
      'price': revisedQuote.total,
      'fare': revisedQuote.total,
      'driverPayout': revisedPayout,
      'riderPayout': revisedPayout,
      'platformRevenue': revisedPlatformRevenue,
      'platformShare': DeliveryPricing.platformDeliveryFareShare,
      'driverShare': DeliveryPricing.riderDeliveryFareShare,
      'pricingBreakdown': revisedQuote.toJson(),
      'weightReviewRequired': optionValue != 'accurate',
      'weightDisputeStatus':
          optionValue == 'accurate' ? 'verified' : 'admin_review',
      'driverWeightDispute': {
        'reported': optionValue != 'accurate',
        'issueType': optionValue,
        'reportedBy': riderId,
        'reportedAt': FieldValue.serverTimestamp(),
        'status': optionValue == 'accurate' ? 'verified' : 'admin_review',
      },
      'weightVerification': {
        'customerWeight': customerWeight,
        'irisWeight': irisWeight,
        'riderVerifiedWeight': verifiedWeight,
        'finalWeightUsed': finalWeightUsed,
        'previousFinalWeight': currentFinalWeight,
        'option': optionValue,
        'riderId': riderId,
        'note': result['note'],
        'supportingImages': evidenceUrls,
        'storagePaths': storagePaths,
        'timestamp': FieldValue.serverTimestamp(),
      },
      'driverJobSummary': {
        ...summary,
        'finalWeightUsed': finalWeightUsed,
        'finalChargeableWeight': finalWeightUsed,
        'confirmedWeightKg': finalWeightUsed,
        'confirmedWeightBand':
            DeliveryPricing.weightBandFor(finalWeightUsed).category,
        'driverPayout': revisedPayout,
        'riderPayout': revisedPayout,
        'platformRevenue': revisedPlatformRevenue,
        'totalFare': revisedQuote.total,
        'vehicleType': vehicle,
      },
    };
  }

  double _jobPayout(Map<String, dynamic> job) {
    final summary = (job['driverJobSummary'] as Map?)?.cast<String, dynamic>();
    final value = summary?['driverPayout'] ?? job['driverPayout'];
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  double _jobTip(Map<String, dynamic> job) {
    final value = job['tipAmount'] ?? job['riderTip'] ?? job['tip'];
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  double _jobCustomerWeight(Map<String, dynamic> job) {
    return _jobNumber(job, [
      'customerWeight',
      'customerDeclaredWeight',
      'senderEnteredWeightKg',
      'declaredWeightKg',
    ]);
  }

  double _jobIrisWeight(Map<String, dynamic> job) {
    return _jobNumber(job, [
      'irisWeight',
      'irisEstimatedWeight',
      'irisEstimatedWeightKg',
    ]);
  }

  double _jobFinalWeight(Map<String, dynamic> job) {
    final summary = (job['driverJobSummary'] as Map?)?.cast<String, dynamic>();
    return _numberValue(job['finalWeightUsed']) ??
        _numberValue(job['finalChargeableWeight']) ??
        _numberValue(job['confirmedWeightKg']) ??
        _numberValue(summary?['finalWeightUsed']) ??
        _numberValue(summary?['confirmedWeightKg']) ??
        0;
  }

  double _jobDistanceMiles(Map<String, dynamic> job) {
    final summary = (job['driverJobSummary'] as Map?)?.cast<String, dynamic>();
    final pricing = (job['pricingBreakdown'] as Map?)?.cast<String, dynamic>();
    return _numberValue(summary?['estimatedDistanceMiles']) ??
        _numberValue(job['estimatedDistanceMiles']) ??
        _numberValue(pricing?['distanceMiles']) ??
        _webQuoteDistanceMiles;
  }

  double _jobNumber(Map<String, dynamic> job, List<String> keys) {
    final summary = (job['driverJobSummary'] as Map?)?.cast<String, dynamic>();
    for (final key in keys) {
      final direct = _numberValue(job[key]);
      if (direct != null) return direct;
      final nested = _numberValue(summary?[key]);
      if (nested != null) return nested;
    }
    return 0;
  }

  double? _numberValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  Future<void> _reportParcelIssue(
    Map<String, dynamic> job,
    String issueType,
  ) async {
    final user = _riderUser;
    if (user == null) {
      setState(() => _jobMessage = 'Sign in before reporting an issue.');
      return;
    }
    final requestId = '${job['requestId'] ?? job['id'] ?? ''}'.trim();
    if (requestId.isEmpty) return;
    setState(() => _jobMessage = 'Reporting issue for $requestId...');
    try {
      await FirebaseFirestore.instance
          .collection('deliveryRequests')
          .doc(requestId)
          .set({
        'reportedParcelIssue': issueType != 'weight',
        'reportedWeightIssue': issueType == 'weight',
        'driverWeightDispute': {
          'reported': issueType == 'weight',
          'issueType': issueType,
          'reportedBy': user.uid,
          'reportedAt': FieldValue.serverTimestamp(),
          'status': 'admin_review',
        },
        'weightReviewRequired': true,
        'weightDisputeStatus': 'admin_review',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _jobMessage = 'Issue flagged for Circum review.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _jobMessage = 'Could not report this issue. Try again.');
    }
  }

  void _openRiderChat(Map<String, dynamic> job) {
    final requestId = '${job['requestId'] ?? job['id'] ?? ''}'.trim();
    if (requestId.isEmpty) return;
    _riderChatSub?.cancel();
    _riderChatSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(requestId)
        .collection('messages')
        .orderBy('createdAt')
        .limit(80)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _riderChatMessages
          ..clear()
          ..addAll(snapshot.docs.map((doc) {
            final data = doc.data();
            final role = '${data['senderRole'] ?? data['senderType'] ?? ''}';
            return _ChatMessage(
              fromMe: data['senderId'] == _riderUser?.uid,
              text: '${data['messageText'] ?? data['message'] ?? ''}',
              time: _formatMessageTime(data['createdAt'], data['timeStamp']),
              label: role == 'admin' || role == 'support'
                  ? 'CIRCUM Support'
                  : role == 'sender' || role == 'user'
                      ? 'Sender'
                      : 'Rider',
            );
          }).where((message) => message.text.trim().isNotEmpty));
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _jobMessage = 'Could not open this chat.');
    });
    setState(() {
      _activeRiderChatJob = job;
      _riderChatOpen = true;
    });
  }

  Future<void> _sendRiderChatMessage() async {
    final user = _riderUser;
    final job = _activeRiderChatJob;
    final text = _riderChatInput.text.trim();
    if (user == null || job == null || text.isEmpty) return;
    final requestId = '${job['requestId'] ?? job['id'] ?? ''}'.trim();
    if (requestId.isEmpty) return;
    _riderChatInput.clear();
    try {
      await _ensureCircumFirebaseReady();
      final chatRef =
          FirebaseFirestore.instance.collection('chats').doc(requestId);
      await chatRef.collection('messages').add({
        'threadId': requestId,
        'bookingId': requestId,
        'requestId': requestId,
        'senderId': user.uid,
        'senderRole': 'rider',
        'senderType': 'rider',
        'messageText': text,
        'message': text,
        'readBy': [user.uid],
        'createdAt': FieldValue.serverTimestamp(),
        'timeStamp': DateTime.now().toIso8601String(),
      });
      await chatRef.set({
        'threadId': requestId,
        'bookingId': requestId,
        'requestId': requestId,
        'participants': FieldValue.arrayUnion([user.uid, 'circum-support']),
        'lastMessage': text,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'unreadBy': FieldValue.arrayUnion(['sender', 'admin']),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'circum-web',
      }, SetOptions(merge: true));
    } catch (_) {
      if (!mounted) return;
      setState(() => _jobMessage = 'Message could not be sent.');
    }
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

  Future<void> _signOutRider() async {
    await _earningsSub?.cancel();
    await _performanceSub?.cancel();
    await _ratingSub?.cancel();
    await _availableJobsSub?.cancel();
    await _acceptedJobsSub?.cancel();
    await _completedJobsSub?.cancel();
    await _riderChatSub?.cancel();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      _riderUser = null;
      _riderProfile = null;
      _earnings = _RiderEarningsSnapshot.empty();
      _performance = DriverPerformanceMetric.empty('web-rider');
      _recentRatings = const [];
      _availableJobs = const [];
      _acceptedJobs = const [];
      _completedJobs = const [];
      _availableRoles = const {};
      _roleChoiceConfirmed = false;
      _authMessage = 'Signed out.';
      _riderChatOpen = false;
      _activeRiderChatJob = null;
      _riderChatMessages.clear();
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
      final pending = await db
          .collection('payoutRequests')
          .where('riderId', isEqualTo: user.uid)
          .where('status', whereIn: ['pending', 'processing'])
          .limit(1)
          .get();
      if (pending.docs.isNotEmpty) {
        if (!mounted) return;
        setState(() => _withdrawMessage =
            'You already have a withdrawal being processed.');
        return;
      }
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
        'auditTrail': [
          {
            'type': 'withdrawal_requested',
            'riderId': user.uid,
            'amount': amount,
            'status': 'pending',
            'source': 'circum-web',
            'createdAt': Timestamp.now(),
          }
        ],
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

  Widget _buildRiderAccessPanel(_CircumColors colors) {
    return _RiderAccessPanel(
      colors: colors,
      email: _email,
      password: _password,
      signupMode: _signupMode,
      submitting: _authSubmitting,
      user: _riderUser,
      message: _authMessage,
      onToggleMode: () => setState(() => _signupMode = !_signupMode),
      onSubmit: _submitAuth,
      onForgotPassword: _sendRiderPasswordReset,
      onSignOut: _signOutRider,
    );
  }

  Widget _buildRiderEnrollmentForm(_CircumColors colors) {
    return _RiderEnrollmentForm(
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
      onRightToWork: (value) => setState(() => _rightToWork = value ?? false),
      onSealedPackageConsent: (value) =>
          setState(() => _sealedPackageConsent = value ?? false),
      onSubmit: _submit,
    );
  }

  Widget _buildRiderWorkspace(_CircumColors colors, {bool nested = false}) {
    return _RiderWorkspace(
      colors: colors,
      user: _riderUser,
      riderProfile: _riderProfile,
      earnings: _earnings,
      performance: _performance,
      recentRatings: _recentRatings,
      availableJobs: _availableJobs,
      acceptedJobs: _acceptedJobs,
      completedJobs: _completedJobs,
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
      jobMessage: _jobMessage,
      currentPassword: _currentPassword,
      newPassword: _newPassword,
      confirmNewPassword: _confirmNewPassword,
      newEmail: _newEmail,
      emailChangePassword: _emailChangePassword,
      securitySubmitting: _securitySubmitting,
      securityMessage: _securityMessage,
      onSaveBank: (value) => setState(() => _saveBank = value ?? false),
      onWithdraw: _requestWithdrawal,
      onUploadDocument: _uploadRiderDocument,
      onChangePassword: _changeRiderPassword,
      onChangeEmail: _changeRiderEmail,
      onAcceptJob: _acceptDeliveryJob,
      onRejectJob: (job) => _rejectOrIgnoreJob(job, 'reject'),
      onIgnoreJob: (job) => _rejectOrIgnoreJob(job, 'ignore'),
      onUpdateJobStatus: _updateAcceptedJobStatus,
      onReportIssue: _reportParcelIssue,
      onOpenChat: _openRiderChat,
      nested: nested,
    );
  }

  Widget _buildSignedInRiderContent(_CircumColors colors, bool wide) {
    if (_riderProfile == null) {
      final children = [
        _buildRiderAccessPanel(colors),
        const SizedBox(height: 14),
        _buildRiderEnrollmentForm(colors),
      ];
      return ListView(
        padding: EdgeInsets.fromLTRB(wide ? 28 : 18, 18, wide ? 28 : 18, 34),
        children: children,
      );
    }

    final approvalStatus = _riderApprovalStatus();
    if (approvalStatus != 'approved') {
      return ListView(
        padding: EdgeInsets.fromLTRB(wide ? 28 : 18, 18, wide ? 28 : 18, 34),
        children: [
          _buildRiderAccessPanel(colors),
          const SizedBox(height: 14),
          _RiderApprovalStatusPanel(
            colors: colors,
            status: approvalStatus,
            profile: _riderProfile!,
          ),
        ],
      );
    }

    return _buildRiderWorkspace(colors, nested: !wide);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Stack(
      children: [
        LayoutBuilder(
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
                _RiderPortalTabs(
                  colors: colors,
                  selected: _riderTab,
                  onSelected: (tab) => setState(() => _riderTab = tab),
                ),
                Expanded(
                  child: switch (_riderTab) {
                    _RiderPortalTab.order => _CircumOrderContent(
                        colors: colors,
                        onBecomeRider: () => setState(
                            () => _riderTab = _RiderPortalTab.overview),
                      ),
                    _RiderPortalTab.earnings => _RiderEarningsTab(
                        colors: colors,
                        earnings: _earnings,
                      ),
                    _RiderPortalTab.referrals =>
                      _RiderReferralsTab(colors: colors),
                    _RiderPortalTab.overview => _riderUser == null
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
                                onForgotPassword: _sendRiderPasswordReset,
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
                                    onSender: () => widget
                                        .onRoleSelected(CircumRole.sender),
                                    onRider: () => setState(
                                        () => _roleChoiceConfirmed = true),
                                    onAdmin: () =>
                                        widget.onRoleSelected(CircumRole.admin),
                                  ),
                                ],
                              )
                            : _buildSignedInRiderContent(colors, wide),
                  },
                ),
              ],
            );
          },
        ),
        if (_riderChatOpen)
          _ChatSheet(
            colors: colors,
            title: 'Delivery chat',
            recipient: 'Sender and CIRCUM Support',
            messages: _riderChatMessages,
            input: _riderChatInput,
            onClose: () => setState(() => _riderChatOpen = false),
            onSend: _sendRiderChatMessage,
          ),
      ],
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
            'Create a rider account to apply, upload documents, accept jobs, and manage payouts. Drivers earn 65% of each completed delivery.',
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
  final VoidCallback onForgotPassword;
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
    required this.onForgotPassword,
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
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: submitting ? null : onForgotPassword,
                child: const Text('Forgot Password?'),
              ),
            ),
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

class _RiderApprovalStatusPanel extends StatelessWidget {
  final _CircumColors colors;
  final String status;
  final Map<String, dynamic> profile;

  const _RiderApprovalStatusPanel({
    required this.colors,
    required this.status,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final title = switch (normalized) {
      'rejected' => 'Application needs attention',
      'suspended' => 'Rider account suspended',
      _ => 'Application pending',
    };
    final body = switch (normalized) {
      'rejected' =>
        'Circum could not approve this rider profile yet. Check the note below and contact support if you need help.',
      'suspended' =>
        'This rider account cannot accept jobs right now. Contact Circum support for the next step.',
      _ =>
        'Your rider profile has been created. Circum will review your details and documents before jobs appear here.',
    };
    final note = [
      profile['adminMessage'],
      profile['approvalNote'],
      profile['rejectionReason'],
      profile['accountNote'],
    ]
        .where((value) => '${value ?? ''}'.trim().isNotEmpty)
        .map((value) => '$value'.trim())
        .join('\n');

    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                normalized == 'suspended'
                    ? Icons.block
                    : normalized == 'rejected'
                        ? Icons.report_problem_outlined
                        : Icons.pending_actions,
                color: colors.text,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SectionTitle(colors: colors, title: title),
              ),
              _HealthChip(label: normalized),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: TextStyle(
              color: colors.mutedText,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          _RiderChecklistRow(
            colors: colors,
            icon: Icons.person_outline,
            label: 'Rider',
            value: '${profile['fullName'] ?? profile['email'] ?? 'Signed in'}',
          ),
          _RiderChecklistRow(
            colors: colors,
            icon: Icons.directions_bike,
            label: 'Vehicle',
            value:
                '${profile['vehicleType'] ?? 'Vehicle'} ${profile['vehicleRegistration'] ?? profile['plateNumber'] ?? ''}'
                    .trim(),
          ),
          _RiderChecklistRow(
            colors: colors,
            icon: Icons.verified_user_outlined,
            label: 'Approval status',
            value: normalized,
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.field,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                note,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
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
  final Map<String, dynamic>? riderProfile;
  final _RiderEarningsSnapshot earnings;
  final DriverPerformanceMetric performance;
  final List<DriverRating> recentRatings;
  final List<Map<String, dynamic>> availableJobs;
  final List<Map<String, dynamic>> acceptedJobs;
  final List<Map<String, dynamic>> completedJobs;
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
  final String? jobMessage;
  final TextEditingController currentPassword;
  final TextEditingController newPassword;
  final TextEditingController confirmNewPassword;
  final TextEditingController newEmail;
  final TextEditingController emailChangePassword;
  final bool securitySubmitting;
  final String? securityMessage;
  final ValueChanged<bool?> onSaveBank;
  final VoidCallback onWithdraw;
  final VoidCallback onUploadDocument;
  final VoidCallback onChangePassword;
  final VoidCallback onChangeEmail;
  final ValueChanged<Map<String, dynamic>> onAcceptJob;
  final ValueChanged<Map<String, dynamic>> onRejectJob;
  final ValueChanged<Map<String, dynamic>> onIgnoreJob;
  final void Function(Map<String, dynamic> job, String status)
      onUpdateJobStatus;
  final void Function(Map<String, dynamic> job, String issueType) onReportIssue;
  final ValueChanged<Map<String, dynamic>> onOpenChat;
  final bool nested;

  const _RiderWorkspace({
    required this.colors,
    required this.user,
    required this.riderProfile,
    required this.earnings,
    required this.performance,
    required this.recentRatings,
    required this.availableJobs,
    required this.acceptedJobs,
    required this.completedJobs,
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
    required this.jobMessage,
    required this.currentPassword,
    required this.newPassword,
    required this.confirmNewPassword,
    required this.newEmail,
    required this.emailChangePassword,
    required this.securitySubmitting,
    required this.securityMessage,
    required this.onSaveBank,
    required this.onWithdraw,
    required this.onUploadDocument,
    required this.onChangePassword,
    required this.onChangeEmail,
    required this.onAcceptJob,
    required this.onRejectJob,
    required this.onIgnoreJob,
    required this.onUpdateJobStatus,
    required this.onReportIssue,
    required this.onOpenChat,
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
          _RiderOrderProfileCard(
            colors: colors,
            profile: riderProfile,
            performance: performance,
          ),
          const SizedBox(height: 14),
          _DriverPerformancePanel(
            colors: colors,
            performance: performance,
            recentRatings: recentRatings,
          ),
          const SizedBox(height: 14),
          _AccountSecurityPanel(
            colors: colors,
            title: 'Security',
            currentPassword: currentPassword,
            newPassword: newPassword,
            confirmNewPassword: confirmNewPassword,
            newEmail: newEmail,
            emailChangePassword: emailChangePassword,
            submitting: securitySubmitting,
            message: securityMessage,
            onChangePassword: onChangePassword,
            onChangeEmail: onChangeEmail,
          ),
          const SizedBox(height: 14),
          _AvailableDriverJobsPanel(
            colors: colors,
            jobs: availableJobs,
            message: jobMessage,
            onAcceptJob: onAcceptJob,
            onRejectJob: onRejectJob,
            onIgnoreJob: onIgnoreJob,
            onReportIssue: onReportIssue,
            onOpenChat: onOpenChat,
          ),
          const SizedBox(height: 14),
          _RiderJobListPanel(
            colors: colors,
            title: 'Accepted jobs',
            emptyText: 'Accepted jobs will appear here.',
            jobs: acceptedJobs,
            onUpdateJobStatus: onUpdateJobStatus,
            onReportIssue: onReportIssue,
            onOpenChat: onOpenChat,
          ),
          const SizedBox(height: 14),
          _RiderJobListPanel(
            colors: colors,
            title: 'Completed jobs',
            emptyText: 'Completed deliveries will appear here.',
            jobs: completedJobs,
            completed: true,
            onUpdateJobStatus: onUpdateJobStatus,
            onReportIssue: onReportIssue,
            onOpenChat: onOpenChat,
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _RiderStatTile(
                        colors: colors,
                        label: 'Tips',
                        value: _money(earnings.tipsReceived),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RiderStatTile(
                        colors: colors,
                        label: 'Withdrawn',
                        value: _money(earnings.withdrawnEarnings),
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
                  'Upload your driving licence, insurance, proof of address, vehicle documents, and profile photo for Circum review.',
                  style: TextStyle(
                      color: colors.mutedText,
                      height: 1.35,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    'Driving licence',
                    'Insurance',
                    'Proof of address',
                    'Vehicle documents',
                    'Profile photo',
                  ].map((type) {
                    return ActionChip(
                      label: Text(type),
                      onPressed: () => documentType.text = type,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
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

class _AccountSecurityPanel extends StatelessWidget {
  final _CircumColors colors;
  final String title;
  final TextEditingController currentPassword;
  final TextEditingController newPassword;
  final TextEditingController confirmNewPassword;
  final TextEditingController newEmail;
  final TextEditingController emailChangePassword;
  final bool submitting;
  final String? message;
  final VoidCallback onChangePassword;
  final VoidCallback onChangeEmail;

  const _AccountSecurityPanel({
    required this.colors,
    required this.title,
    required this.currentPassword,
    required this.newPassword,
    required this.confirmNewPassword,
    required this.newEmail,
    required this.emailChangePassword,
    required this.submitting,
    required this.message,
    required this.onChangePassword,
    required this.onChangeEmail,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: title),
          const SizedBox(height: 8),
          Text(
            'Manage your sign-in details with Firebase Authentication.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _InputBox(
            colors: colors,
            controller: currentPassword,
            hint: 'Current password',
            obscureText: true,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _InputBox(
                  colors: colors,
                  controller: newPassword,
                  hint: 'New password',
                  obscureText: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InputBox(
                  colors: colors,
                  controller: confirmNewPassword,
                  hint: 'Confirm new password',
                  obscureText: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: submitting ? null : onChangePassword,
              icon: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.password),
              label: const Text('Change password'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.text,
                foregroundColor: colors.inverseText,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _InputBox(
            colors: colors,
            controller: newEmail,
            hint: 'New email address',
          ),
          const SizedBox(height: 10),
          _InputBox(
            colors: colors,
            controller: emailChangePassword,
            hint: 'Current password for email change',
            obscureText: true,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: submitting ? null : onChangeEmail,
              icon: const Icon(Icons.mark_email_read_outlined),
              label: const Text('Change email and send verification'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.text,
                side: BorderSide(color: colors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(
              message!,
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
            ),
          ],
        ],
      ),
    );
  }
}

class _AvailableDriverJobsPanel extends StatelessWidget {
  final _CircumColors colors;
  final List<Map<String, dynamic>> jobs;
  final String? message;
  final ValueChanged<Map<String, dynamic>> onAcceptJob;
  final ValueChanged<Map<String, dynamic>> onRejectJob;
  final ValueChanged<Map<String, dynamic>> onIgnoreJob;
  final void Function(Map<String, dynamic> job, String issueType) onReportIssue;
  final ValueChanged<Map<String, dynamic>> onOpenChat;

  const _AvailableDriverJobsPanel({
    required this.colors,
    required this.jobs,
    required this.message,
    required this.onAcceptJob,
    required this.onRejectJob,
    required this.onIgnoreJob,
    required this.onReportIssue,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Available jobs'),
          const SizedBox(height: 8),
          Text(
            'Review the route, parcel, weight, and payout before accepting.',
            style: TextStyle(
              color: colors.mutedText,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
            ),
          ],
          const SizedBox(height: 12),
          if (jobs.isEmpty)
            Text(
              'No sender requests are waiting right now.',
              style: TextStyle(color: colors.mutedText),
            )
          else
            ...jobs.take(8).map((job) => _DriverJobCard(
                  colors: colors,
                  job: job,
                  onAccept: () => onAcceptJob(job),
                  onReject: () => onRejectJob(job),
                  onIgnore: () => onIgnoreJob(job),
                  onReportWeight: () => onReportIssue(job, 'weight'),
                  onReportParcel: () => onReportIssue(job, 'parcel'),
                  onOpenChat: () => onOpenChat(job),
                )),
        ],
      ),
    );
  }
}

class _RiderJobListPanel extends StatelessWidget {
  final _CircumColors colors;
  final String title;
  final String emptyText;
  final List<Map<String, dynamic>> jobs;
  final bool completed;
  final void Function(Map<String, dynamic> job, String status)
      onUpdateJobStatus;
  final void Function(Map<String, dynamic> job, String issueType) onReportIssue;
  final ValueChanged<Map<String, dynamic>> onOpenChat;

  const _RiderJobListPanel({
    required this.colors,
    required this.title,
    required this.emptyText,
    required this.jobs,
    this.completed = false,
    required this.onUpdateJobStatus,
    required this.onReportIssue,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: title),
          const SizedBox(height: 12),
          if (jobs.isEmpty)
            Text(emptyText, style: TextStyle(color: colors.mutedText))
          else
            ...jobs.take(8).map((job) => _DriverJobCard(
                  colors: colors,
                  job: job,
                  completed: completed,
                  onAccept: () => onUpdateJobStatus(job, 'accepted'),
                  onUpdateStatus: completed
                      ? null
                      : (status) => onUpdateJobStatus(job, status),
                  onReportWeight: () => onReportIssue(job, 'weight'),
                  onReportParcel: () => onReportIssue(job, 'parcel'),
                  onOpenChat: () => onOpenChat(job),
                )),
        ],
      ),
    );
  }
}

class _DriverJobCard extends StatelessWidget {
  final _CircumColors colors;
  final Map<String, dynamic> job;
  final VoidCallback onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onIgnore;
  final void Function(String status)? onUpdateStatus;
  final VoidCallback onReportWeight;
  final VoidCallback onReportParcel;
  final VoidCallback onOpenChat;
  final bool completed;

  const _DriverJobCard({
    required this.colors,
    required this.job,
    required this.onAccept,
    this.onReject,
    this.onIgnore,
    this.onUpdateStatus,
    required this.onReportWeight,
    required this.onReportParcel,
    required this.onOpenChat,
    this.completed = false,
  });

  @override
  Widget build(BuildContext context) {
    final summary =
        (job['driverJobSummary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final pricing =
        (job['pricingBreakdown'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final customerWeight =
        _num(job['customerDeclaredWeight'] ?? job['senderEnteredWeightKg']);
    final irisWeight =
        _num(job['irisEstimatedWeight'] ?? job['irisEstimatedWeightKg']);
    final chargeableWeight = _num(job['finalWeightUsed'] ??
        job['finalChargeableWeight'] ??
        job['confirmedWeightKg']);
    final category =
        '${job['weightCategory'] ?? job['confirmedWeightBand'] ?? summary['confirmedWeightBand'] ?? 'Parcel'}';
    final confidence =
        '${job['irisConfidenceScore'] ?? job['irisWeightConfidence'] ?? 'unknown'}';
    final weightSource =
        '${job['irisWeightSource'] ?? summary['irisWeightSource'] ?? 'unknown'}';
    final distance = _num(summary['estimatedDistanceMiles']);
    final fare = _num(summary['totalFare'] ?? job['fare'] ?? job['price']);
    final payout = _num(summary['driverPayout'] ?? job['driverPayout']);
    final tip =
        _num(job['tipAmount'] ?? job['riderTip'] ?? summary['tipAmount']);
    final vehicle =
        '${summary['vehicleType'] ?? job['vehicleType'] ?? 'Vehicle'}';
    final serviceLevel =
        '${job['selectedServiceLevel'] ?? job['serviceLevel'] ?? summary['serviceLevel'] ?? 'standard'}';
    final vanguardEnabled = job['vanguardEnabled'] == true ||
        summary['vanguardEnabled'] == true ||
        ((job['vanguardProtection'] as Map?)?['enabled'] == true);
    final duration = _num(summary['estimatedDurationMinutes'] ??
        job['estimatedDurationMinutes'] ??
        job['etaMinutes']);
    final dimensions =
        '${summary['packageDimensions'] ?? job['packageDimensions'] ?? job['dimensions'] ?? ''}'
            .trim();
    final warnings = _warnings(chargeableWeight, category, job);
    final showContactDetails = onReject == null && onIgnore == null;
    final senderName = _contactValue(job, summary, 'senderName',
        nestedKey: 'senderDetails', nestedName: 'name');
    final senderPhone = _contactValue(job, summary, 'senderPhone',
        nestedKey: 'senderDetails', nestedName: 'phone');
    final receiverName = _contactValue(job, summary, 'receiverName',
        nestedKey: 'receiverDetails', nestedName: 'name');
    final receiverPhone = _contactValue(job, summary, 'receiverPhone',
        nestedKey: 'receiverDetails', nestedName: 'phone');
    final collectionName = _contactValue(job, summary, 'collectionContactName',
        nestedKey: 'collectionContact', nestedName: 'name');
    final collectionPhone = _contactValue(
        job, summary, 'collectionContactPhone',
        nestedKey: 'collectionContact', nestedName: 'phone');
    final collectionDifferent = (job['collectionContactDifferent'] == true ||
        summary['collectionContactDifferent'] == true ||
        ((job['collectionContact'] as Map?)?['differentFromSender'] == true));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${job['requestId'] ?? job['id'] ?? 'Delivery request'}',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if ('${job['selectedServiceLevel'] ?? job['serviceLevel'] ?? ''}'
                      .toLowerCase() ==
                  'express') ...[
                _HealthChip(label: 'Express'),
                const SizedBox(width: 8),
              ],
              if (vanguardEnabled) ...[
                _HealthChip(label: 'Vanguard'),
                const SizedBox(width: 8),
              ],
              _HealthChip(label: vehicle),
            ],
          ),
          const SizedBox(height: 10),
          _JobInfoLine(
            colors: colors,
            icon: Icons.bolt,
            label: 'Service',
            value: serviceLevel.toLowerCase() == 'express'
                ? 'Express priority'
                : 'Standard',
          ),
          _JobInfoLine(
            colors: colors,
            icon: Icons.trip_origin,
            label: 'Pickup',
            value: '${summary['pickupDisplay'] ?? job['pickupAddress'] ?? ''}',
          ),
          _JobInfoLine(
            colors: colors,
            icon: Icons.place,
            label: 'Drop-off',
            value:
                '${summary['dropoffDisplay'] ?? job['dropoffAddress'] ?? ''}',
          ),
          if (showContactDetails) ...[
            _JobInfoLine(
              colors: colors,
              icon: Icons.person,
              label: 'Sender',
              value:
                  '${senderName.isEmpty ? 'Not set' : senderName}${senderPhone.isEmpty ? '' : ' • $senderPhone'}',
            ),
            if (collectionDifferent)
              _JobInfoLine(
                colors: colors,
                icon: Icons.handshake_outlined,
                label: 'Collection contact',
                value:
                    '${collectionName.isEmpty ? 'Not set' : collectionName}${collectionPhone.isEmpty ? '' : ' • $collectionPhone'}',
              ),
            _JobInfoLine(
              colors: colors,
              icon: Icons.person_pin_circle,
              label: 'Receiver',
              value:
                  '${receiverName.isEmpty ? 'Not set' : receiverName}${receiverPhone.isEmpty ? '' : ' • $receiverPhone'}',
            ),
          ],
          _JobInfoLine(
            colors: colors,
            icon: Icons.route,
            label: 'Distance',
            value: distance > 0
                ? '${distance.toStringAsFixed(1)} miles'
                : 'Not set',
          ),
          _JobInfoLine(
            colors: colors,
            icon: Icons.timer,
            label: 'ETA',
            value:
                duration > 0 ? '${duration.toStringAsFixed(0)} min' : 'Not set',
          ),
          _JobInfoLine(
            colors: colors,
            icon: Icons.schedule,
            label: 'Pickup window',
            value:
                '${summary['scheduledPickupDate'] ?? job['scheduledPickupDate'] ?? 'Flexible'} ${summary['scheduledPickupWindow'] ?? job['scheduledPickupWindow'] ?? ''}',
          ),
          _JobInfoLine(
            colors: colors,
            icon: Icons.inventory_2,
            label: 'Parcel',
            value:
                '${summary['packageType'] ?? job['packageType'] ?? 'Parcel'} - ${summary['packageDescription'] ?? job['packageDescription'] ?? ''}',
          ),
          _JobInfoLine(
            colors: colors,
            icon: Icons.straighten,
            label: 'Dimensions',
            value: dimensions.isEmpty ? 'Not provided' : dimensions,
          ),
          _JobInfoLine(
            colors: colors,
            icon: Icons.scale,
            label: 'Weight',
            value:
                'Customer ${_weight(customerWeight)} kg, Iris ${_weight(irisWeight)} kg, chargeable ${_weight(chargeableWeight)} kg',
          ),
          _JobInfoLine(
            colors: colors,
            icon: Icons.fact_check,
            label: 'Checks',
            value:
                '$category, Iris confidence $confidence, source $weightSource',
          ),
          _JobInfoLine(
            colors: colors,
            icon: Icons.payments,
            label: 'Price',
            value:
                'Total ${_money(fare)} • distance ${_money(_num(pricing['distanceFare']))} • weight ${_money(_num(pricing['weightSurcharge']))} • payout ${_money(payout)}${tip > 0 ? ' • tip ${_money(tip)}' : ''}',
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: warnings
                  .map((warning) => _HealthChip(label: warning))
                  .toList(),
            ),
          ],
          if (vanguardEnabled) ...[
            const SizedBox(height: 8),
            _JobInfoLine(
              colors: colors,
              icon: Icons.security,
              label: 'Vanguard',
              value:
                  'PIN verification required at collection and final delivery.',
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: completed ? null : onAccept,
                icon: Icon(completed ? Icons.done_all : Icons.check_circle),
                label: Text(completed ? 'Completed' : 'Accept job'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenChat,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Messages'),
              ),
              if (onUpdateStatus != null && !completed) ...[
                OutlinedButton.icon(
                  onPressed: () => onUpdateStatus!('picked_up'),
                  icon: const Icon(Icons.inventory),
                  label: const Text('Verify pickup'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onUpdateStatus!('in_transit'),
                  icon: const Icon(Icons.delivery_dining),
                  label: const Text('In transit'),
                ),
                OutlinedButton.icon(
                  onPressed: () => onUpdateStatus!('completed'),
                  icon: const Icon(Icons.flag_circle),
                  label: const Text('Complete'),
                ),
              ],
              if (onReject != null)
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
                ),
              if (onIgnore != null)
                OutlinedButton.icon(
                  onPressed: onIgnore,
                  icon: const Icon(Icons.visibility_off),
                  label: const Text('Ignore'),
                ),
              OutlinedButton.icon(
                onPressed: onReportWeight,
                icon: const Icon(Icons.scale),
                label: const Text('Weight issue'),
              ),
              OutlinedButton.icon(
                onPressed: onReportParcel,
                icon: const Icon(Icons.report_problem),
                label: const Text('Parcel issue'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static String _money(double value) => '£${value.toStringAsFixed(2)}';

  static String _weight(double value) => value <= 0
      ? 'not set'
      : value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);

  static String _contactValue(
    Map<String, dynamic> job,
    Map<String, dynamic> summary,
    String key, {
    required String nestedKey,
    required String nestedName,
  }) {
    final nested = (job[nestedKey] as Map?)?.cast<String, dynamic>();
    return '${summary[key] ?? job[key] ?? nested?[nestedName] ?? ''}'.trim();
  }

  static List<String> _warnings(
    double weightKg,
    String category,
    Map<String, dynamic> job,
  ) {
    final warnings = <String>[];
    if (weightKg > 20) {
      warnings.add('Two-person handling may be required');
    } else if (weightKg > 10) {
      warnings.add('Heavy parcel');
    }
    final lowerCategory = category.toLowerCase();
    final description =
        '${job['packageDescription'] ?? ''} ${job['packageType'] ?? ''}'
            .toLowerCase();
    if (lowerCategory.contains('large') ||
        description.contains('furniture') ||
        description.contains('piano') ||
        description.contains('tv')) {
      warnings.add('Large item');
    }
    if (job['weightReviewRequired'] == true ||
        job['weightVerificationRequired'] == true) {
      warnings.add('Check weight at pickup');
    }
    return warnings;
  }
}

class _JobInfoLine extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String label;
  final String value;

  const _JobInfoLine({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.mutedText, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: colors.mutedText,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(text: value.trim().isEmpty ? 'Not set' : value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
  final double tipsReceived;
  final double withdrawnEarnings;
  final int completedJobs;

  const _RiderEarningsSnapshot({
    required this.availableBalance,
    required this.pendingWithdrawal,
    required this.lifetimeEarnings,
    required this.tipsReceived,
    required this.withdrawnEarnings,
    required this.completedJobs,
  });

  factory _RiderEarningsSnapshot.empty() => const _RiderEarningsSnapshot(
        availableBalance: 0,
        pendingWithdrawal: 0,
        lifetimeEarnings: 0,
        tipsReceived: 0,
        withdrawnEarnings: 0,
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
      tipsReceived: (data['tipsReceived'] as num? ?? 0).toDouble(),
      withdrawnEarnings: (data['withdrawnEarnings'] as num? ??
              data['totalWithdrawn'] as num? ??
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

enum _CheckoutState {
  draft,
  validating,
  optionsReady,
  awaitingPayment,
  processingPayment,
  bookingCreated,
  matchingRiders,
  riderAssigned,
  failed,
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
  final _healthPharmacyName = TextEditingController();
  final _healthPharmacy = TextEditingController();
  final _healthDelivery = TextEditingController();
  final _healthNotes = TextEditingController();
  final _healthPreferredDay = TextEditingController();
  final _healthPreferredTime = TextEditingController();
  final _healthCustomSchedule = TextEditingController();
  final _ratingFeedback = TextEditingController();
  final _senderEmail = TextEditingController();
  final _senderPassword = TextEditingController();
  final _senderCurrentPassword = TextEditingController();
  final _senderNewPassword = TextEditingController();
  final _senderConfirmNewPassword = TextEditingController();
  final _senderNewEmail = TextEditingController();
  final _senderEmailChangePassword = TextEditingController();
  final _senderName = TextEditingController();
  final _senderPhone = TextEditingController();
  final _receiverName = TextEditingController();
  final _receiverPhone = TextEditingController();
  final _collectionContactName = TextEditingController();
  final _collectionContactPhone = TextEditingController();
  final _savedAddressLabel = TextEditingController(text: 'Home');
  final _savedAddress = TextEditingController();
  String _savedAddressType = 'pickup';
  _ValidatedAddress? _validatedSavedAddress;
  double? _irisEstimatedWeightKg;
  String? _irisWeightBand;
  String? _irisWeightConfidence;
  String? _irisWeightExplanation;
  String? _irisWeightSource;
  String? _irisMatchedItemName;
  double? _irisWeightConfidenceScore;
  double? _irisHistoricalVerifiedWeightKg;
  String? _irisLearningReason;
  ItemDimensionsCm? _irisTypicalDimensions;
  String? _irisVehicleSuitability;
  bool _irisFragile = false;
  bool _irisStackable = true;
  String? _irisHandlingNotes;
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
  HealthPlusFrequency _healthFrequency = HealthPlusFrequency.oneOff;
  _CheckoutState _checkoutState = _CheckoutState.draft;
  bool _analyzing = false;
  bool _broadcasting = false;
  bool _chatOpen = false;
  bool _supportChat = false;
  bool _healthConsent = false;
  bool _healthSavePayment = true;
  bool _healthSubmitting = false;
  String _healthPrescriptionType = 'NHS prescription';
  String _healthSubscriptionPlan = 'basic';
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
  String? _senderSecurityMessage;
  _ValidatedAddress? _validatedPickup;
  _ValidatedAddress? _validatedDropoff;
  bool _firebaseOnline = false;
  bool _senderAuthLoading = true;
  bool _senderAuthBusy = false;
  bool _senderSecurityBusy = false;
  bool _senderProfileSaving = false;
  bool _senderSignupMode = false;
  bool _roleChoiceConfirmed = false;
  bool _differentCollectionContact = false;
  int _statusIndex = 0;
  int _selectedRating = 0;
  double _selectedTipAmount = 0;
  int _senderProfileTab = 0;
  User? _senderUser;
  SenderProfile? _senderProfile;
  List<SenderDeliveryRecord> _senderDeliveries = const [];
  SenderDeliveryRecord? _selectedSenderDelivery;
  DriverProfile? _assignedDriver;
  DriverPerformanceMetric? _assignedDriverMetric;
  Map<String, dynamic>? _activeVanguardData;
  Map<String, dynamic>? _liveLocationData;
  Set<String> _selectedRatingTags = {};
  Set<CircumRole> _availableRoles = const {};
  final List<Map<String, dynamic>> _healthPickups = [];
  final List<Map<String, dynamic>> _healthPayments = [];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _requestSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _liveLocationSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _senderSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverProfileSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _driverPerformanceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _assignedDriverRatingsSub;

  bool get _matchingHasStarted =>
      _checkoutState == _CheckoutState.matchingRiders ||
      _checkoutState == _CheckoutState.riderAssigned;

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
    _senderName.addListener(_handleContactDetailsChanged);
    _senderPhone.addListener(_handleContactDetailsChanged);
    _receiverName.addListener(_handleContactDetailsChanged);
    _receiverPhone.addListener(_handleContactDetailsChanged);
    _collectionContactName.addListener(_handleContactDetailsChanged);
    _collectionContactPhone.addListener(_handleContactDetailsChanged);
    _restoreSenderSession();
  }

  @override
  void dispose() {
    _weight.removeListener(_handleWeightChanged);
    _senderName.removeListener(_handleContactDetailsChanged);
    _senderPhone.removeListener(_handleContactDetailsChanged);
    _receiverName.removeListener(_handleContactDetailsChanged);
    _receiverPhone.removeListener(_handleContactDetailsChanged);
    _collectionContactName.removeListener(_handleContactDetailsChanged);
    _collectionContactPhone.removeListener(_handleContactDetailsChanged);
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
    _healthPharmacyName.dispose();
    _healthPharmacy.dispose();
    _healthDelivery.dispose();
    _healthNotes.dispose();
    _healthPreferredDay.dispose();
    _healthPreferredTime.dispose();
    _healthCustomSchedule.dispose();
    _ratingFeedback.dispose();
    _senderEmail.dispose();
    _senderPassword.dispose();
    _senderCurrentPassword.dispose();
    _senderNewPassword.dispose();
    _senderConfirmNewPassword.dispose();
    _senderNewEmail.dispose();
    _senderEmailChangePassword.dispose();
    _senderName.dispose();
    _senderPhone.dispose();
    _receiverName.dispose();
    _receiverPhone.dispose();
    _collectionContactName.dispose();
    _collectionContactPhone.dispose();
    _savedAddressLabel.dispose();
    _savedAddress.dispose();
    _requestSub?.cancel();
    _liveLocationSub?.cancel();
    _chatSub?.cancel();
    _senderSub?.cancel();
    _driverProfileSub?.cancel();
    _driverPerformanceSub?.cancel();
    _assignedDriverRatingsSub?.cancel();
    super.dispose();
  }

  void _handleContactDetailsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= _desktopWebBreakpoint &&
                _step != _SenderStep.healthPlus;
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
                          vehicle: _effectiveVehicle,
                          speed: _selectedSpeed,
                          weightKg: _deliveryClassification.finalWeightKg,
                          breakdown: _quoteBreakdown,
                          step: _step,
                          checkoutState: _checkoutState,
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
        onForgotPassword: _sendSenderPasswordReset,
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
          onSavedPickup: _applySavedPickupAddress,
          onSavedDropoff: _applySavedDropoffAddress,
          pickupVerified: _pickupAddressVerified,
          dropoffVerified: _dropoffAddressVerified,
          locationValidationMessage: _locationValidationMessage,
          checkoutState: _checkoutState,
          canSubmit: _canAnalyzeDelivery,
          senderName: _senderName,
          senderPhone: _senderPhone,
          senderDisplayName: _effectiveSenderName,
          senderDisplayPhone: _effectiveSenderPhone,
          senderDetailsRequired: _senderDetailsRequired,
          receiverName: _receiverName,
          receiverPhone: _receiverPhone,
          differentCollectionContact: _differentCollectionContact,
          collectionContactName: _collectionContactName,
          collectionContactPhone: _collectionContactPhone,
          contactDetailsReady: _hasRequiredContactDetails,
          contactValidationMessage: _contactValidationMessage,
          onDifferentCollectionContact: (value) {
            setState(() {
              _differentCollectionContact = value;
              if (!value) {
                _collectionContactName.clear();
                _collectionContactPhone.clear();
              }
            });
          },
          onPickupSelected: _selectPickupAddress,
          onDropoffSelected: _selectDropoffAddress,
          onPickupEdited: _handlePickupEdited,
          onDropoffEdited: _handleDropoffEdited,
          description: _description,
          weight: _weight,
          irisEstimatedWeightKg: _irisEstimatedWeightKg,
          irisWeightBand: _irisWeightBand,
          irisWeightConfidence: _irisWeightConfidence,
          irisWeightExplanation: _irisWeightExplanation,
          irisMatchedItemName: _irisMatchedItemName,
          irisTruthBand: _irisTruthBand(),
          senderEnteredWeightKg: _senderEnteredWeightKg,
          pricingWeightKg: _confirmedWeightKg,
          weightSource: _weightSourceText,
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
          chargeableWeightKg: _deliveryClassification.finalWeightKg,
          vehicleSuitability: _vehicleSuitability,
          selectedVehicle: _effectiveVehicle,
          selectedSpeed: _selectedSpeed,
          onVehicle: (vehicle) {
            final suitability = _vehicleSuitability;
            if (!DeliveryPricing.vehicleCanCarryDelivery(
              vehicle.name,
              suitability,
            )) {
              setState(() {
                _selectedVehicle = _effectiveVehicle;
                _weightMessage =
                    'Vehicle recommendation based on weight, dimensions, and item type. Recommended vehicle: ${suitability.recommendedVehicle}.';
              });
              return;
            }
            setState(() {
              _selectedVehicle = vehicle;
              _checkoutState = _CheckoutState.awaitingPayment;
            });
          },
          onSpeed: (speed) => setState(() {
            _selectedSpeed = speed;
            _checkoutState = _CheckoutState.awaitingPayment;
          }),
          onBack: () => setState(() => _step = _SenderStep.dashboard),
          onContinue: () => setState(() {
            _checkoutState = _CheckoutState.awaitingPayment;
            _step = _SenderStep.payment;
          }),
        ),
      _SenderStep.payment => _PaymentStep(
          key: const ValueKey('payment'),
          colors: colors,
          vehicle: _effectiveVehicle,
          speed: _selectedSpeed,
          breakdown: _quoteBreakdown,
          distanceMiles: _confirmedRouteDistanceMiles,
          locationsConfirmed: _hasValidatedRoute,
          routeMessage: _locationValidationMessage,
          irisEstimatedWeightKg: _irisEstimatedWeightKg,
          senderEnteredWeightKg: _senderEnteredWeightKg,
          weightKg: _deliveryClassification.finalWeightKg,
          total: _quoteTotal,
          checkoutState: _checkoutState,
          weightConfirmed: _hasConfirmedWeight,
          weightSource: _weightSourceText,
          pricingReason: _weightPricingReason,
          scheduledPickupDate: _scheduledPickupDate.text.trim(),
          scheduledPickupWindow: _scheduledPickupWindow.text.trim(),
          scheduledDropoffDate: _scheduledDropoffDate.text.trim(),
          scheduledDropoffWindow: _scheduledDropoffWindow.text.trim(),
          onBack: () => setState(() {
            if (!_matchingHasStarted) {
              _checkoutState = _CheckoutState.awaitingPayment;
            }
            _step = _SenderStep.vehicle;
          }),
          onPay: _confirmPayment,
        ),
      _SenderStep.tracking => _TrackingStep(
          key: const ValueKey('tracking'),
          colors: colors,
          orderId: _activeOrderId ?? 'CIR-2026',
          pickup: _pickup.text,
          dropoff: _dropoff.text,
          vehicle: _effectiveVehicle,
          statusIndex: _statusIndex,
          broadcasting: _broadcasting,
          checkoutState: _checkoutState,
          firebaseOnline: _firebaseOnline,
          firebaseError: _firebaseError,
          pickupAddress: _validatedPickup,
          dropoffAddress: _validatedDropoff,
          liveLocation: _liveLocationData,
          vanguardData: _activeVanguardData,
          assignedDriver: _assignedDriver,
          assignedDriverMetric: _assignedDriverMetric,
          ratingStars: _selectedRating,
          ratingFeedback: _ratingFeedback,
          selectedRatingTags: _selectedRatingTags,
          selectedTipAmount: _selectedTipAmount,
          ratingSubmitting: _ratingSubmitting,
          ratingSubmitted: _ratingSubmitted,
          ratingMessage: _ratingMessage,
          onRatingChanged: (rating) => setState(() => _selectedRating = rating),
          onRatingTag: _toggleRatingTag,
          onTipChanged: (amount) => setState(() => _selectedTipAmount = amount),
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
          pharmacyName: _healthPharmacyName,
          pharmacyAddress: _healthPharmacy,
          deliveryAddress: _healthDelivery,
          notes: _healthNotes,
          preferredDay: _healthPreferredDay,
          preferredTime: _healthPreferredTime,
          customSchedule: _healthCustomSchedule,
          frequency: _healthFrequency,
          prescriptionType: _healthPrescriptionType,
          subscriptionPlan: _healthSubscriptionPlan,
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
          onPrescriptionType: (type) =>
              setState(() => _healthPrescriptionType = type),
          onSubscriptionPlan: (plan) =>
              setState(() => _healthSubscriptionPlan = plan),
          onStartSubscription: (plan) {
            setState(() {
              _healthSubscriptionPlan = plan;
              if (_healthFrequency == HealthPlusFrequency.oneOff) {
                _healthFrequency = HealthPlusFrequency.weekly;
              }
            });
            _bookHealthPlus();
          },
          onContinueOneOff: () {
            setState(() => _healthFrequency = HealthPlusFrequency.oneOff);
            _bookHealthPlus();
          },
          onConsent: (value) => setState(() => _healthConsent = value ?? false),
          onSavePayment: (value) =>
              setState(() => _healthSavePayment = value ?? false),
          onSubmit: _bookHealthPlus,
          onPauseSchedule: _pauseHealthPlusSchedule,
          onResumeSchedule: _resumeHealthPlusSchedule,
          onCancelSchedule: _cancelHealthPlusSchedule,
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
          currentPassword: _senderCurrentPassword,
          newPassword: _senderNewPassword,
          confirmNewPassword: _senderConfirmNewPassword,
          newEmail: _senderNewEmail,
          emailChangePassword: _senderEmailChangePassword,
          securitySubmitting: _senderSecurityBusy,
          securityMessage: _senderSecurityMessage,
          savedAddressLabel: _savedAddressLabel,
          savedAddress: _savedAddress,
          savedAddressType: _savedAddressType,
          onBack: () => setState(() => _step = _SenderStep.dashboard),
          onTab: (index) => setState(() => _senderProfileTab = index),
          onSignIn: _signInSender,
          onSignUp: _signUpSender,
          onForgotPassword: _sendSenderPasswordReset,
          onChangePassword: _changeSenderPassword,
          onChangeEmail: _changeSenderEmail,
          onSignOut: _signOutSender,
          onSaveProfile: _saveSenderProfile,
          onAddAddress: _addSenderAddress,
          onSavedAddressType: (type) =>
              setState(() => _savedAddressType = type),
          onSavedAddressSelected: (address) => setState(() {
            _validatedSavedAddress = address;
            _savedAddress.text = address.displayAddress;
          }),
          onSavedAddressEdited: (_) =>
              setState(() => _validatedSavedAddress = null),
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
    return _confirmedWeightKg != null &&
        _confirmedWeightKg! > 0 &&
        _confirmedWeightBand != null;
  }

  DeliveryClassification get _deliveryClassification {
    return DeliveryPricing.resolveClassification(
      description: _description.text,
      userEnteredWeightKg: _senderEnteredWeightKg ??
          DeliveryPricing.parseWeightKg(_weight.text, fallbackKg: 0),
      irisEstimateKg: _irisEstimatedWeightKg,
      historicalVerifiedMaxKg: _irisHistoricalVerifiedWeightKg,
      confidence: _irisWeightConfidence ?? 'unknown',
    );
  }

  bool get _hasValidatedRoute {
    return _pickupAddressVerified &&
        _dropoffAddressVerified &&
        _confirmedRouteDistanceMiles != null &&
        _confirmedRouteDistanceMiles! > 0;
  }

  bool get _pickupAddressVerified => _validatedPickup?.hasCoordinates == true;

  bool get _dropoffAddressVerified => _validatedDropoff?.hasCoordinates == true;

  bool get _canAnalyzeDelivery {
    return _hasValidatedRoute && _hasRequiredContactDetails && !_analyzing;
  }

  String get _effectiveSenderName {
    final profileName = _senderProfile?.fullName.trim() ?? '';
    if (profileName.isNotEmpty) return profileName;
    final enteredName = _senderName.text.trim();
    if (enteredName.isNotEmpty) return enteredName;
    return _senderUser?.displayName?.trim() ?? '';
  }

  String get _effectiveSenderPhone {
    final profilePhone = _senderProfile?.phoneNumber.trim() ?? '';
    if (profilePhone.isNotEmpty) return profilePhone;
    return _senderPhone.text.trim();
  }

  bool get _senderDetailsRequired =>
      _effectiveSenderName.isEmpty || _effectiveSenderPhone.isEmpty;

  String get _effectiveCollectionContactName => _differentCollectionContact
      ? _collectionContactName.text.trim()
      : _effectiveSenderName;

  String get _effectiveCollectionContactPhone => _differentCollectionContact
      ? _collectionContactPhone.text.trim()
      : _effectiveSenderPhone;

  bool get _hasRequiredContactDetails {
    if (_effectiveSenderName.isEmpty || _effectiveSenderPhone.isEmpty) {
      return false;
    }
    if (_receiverName.text.trim().isEmpty ||
        _receiverPhone.text.trim().isEmpty) {
      return false;
    }
    if (_differentCollectionContact &&
        (_collectionContactName.text.trim().isEmpty ||
            _collectionContactPhone.text.trim().isEmpty)) {
      return false;
    }
    return true;
  }

  String get _contactValidationMessage {
    if (_effectiveSenderName.isEmpty || _effectiveSenderPhone.isEmpty) {
      return 'Add sender name and phone number before pricing.';
    }
    if (_receiverName.text.trim().isEmpty ||
        _receiverPhone.text.trim().isEmpty) {
      return 'Add receiver name and phone number before pricing.';
    }
    if (_differentCollectionContact &&
        (_collectionContactName.text.trim().isEmpty ||
            _collectionContactPhone.text.trim().isEmpty)) {
      return 'Add the collection contact name and phone number.';
    }
    return 'Sender, receiver, and collection contact details are ready.';
  }

  String get _locationValidationMessage {
    if (!_pickupAddressVerified && !_dropoffAddressVerified) {
      return 'Choose pickup and drop-off from the address suggestions before pricing.';
    }
    if (!_pickupAddressVerified) {
      return 'Choose a verified pickup address from the suggestions.';
    }
    if (!_dropoffAddressVerified) {
      return 'Choose a verified drop-off address from the suggestions.';
    }
    if (_confirmedRouteDistanceMiles == null) {
      return 'Route distance not confirmed';
    }
    return 'Verified route: ${_confirmedRouteDistanceMiles!.toStringAsFixed(1)} miles.';
  }

  double? get _confirmedRouteDistanceMiles {
    final pickup = _validatedPickup;
    final dropoff = _validatedDropoff;
    if (pickup == null || dropoff == null) return null;
    if (!_coordinatesAreUsable(pickup.lat, pickup.lng) ||
        !_coordinatesAreUsable(dropoff.lat, dropoff.lng)) {
      return null;
    }
    if (_coordinatesAreSame(pickup.lat, pickup.lng, dropoff.lat, dropoff.lng)) {
      return null;
    }
    final miles = _coordinateDistanceMiles(
      pickup.lat,
      pickup.lng,
      dropoff.lat,
      dropoff.lng,
    );
    if (miles == null || miles < 0.2) return null;
    return miles;
  }

  String get _weightSourceText {
    return DeliveryPricing.weightSourceLabel(_weightSource);
  }

  bool get _hasConsistentDispatchClassification {
    if (!_hasConfirmedWeight) return false;
    final classification = _deliveryClassification;
    final quote = _quoteBreakdown;
    return classification.finalWeightKg > 0 &&
        classification.finalWeightBand == quote.weightCategory &&
        _vehicleSuitability.recommendedVehicle == _effectiveVehicle.name &&
        DeliveryPricing.vehicleCanCarryDelivery(
          _effectiveVehicle.name,
          _vehicleSuitability,
        ) &&
        !(classification.finalWeightBand != 'Small Parcel' &&
            _effectiveVehicle.name == 'Bike');
  }

  _VehicleOption get _effectiveVehicle {
    final recommendedVehicleName = _vehicleSuitability.recommendedVehicle;
    return _vehicles.firstWhere(
      (vehicle) => vehicle.name == recommendedVehicleName,
      orElse: () => _vehicles.last,
    );
  }

  VehicleSuitability get _vehicleSuitability {
    final classification = _deliveryClassification;
    return DeliveryPricing.resolveVehicleSuitability(
      weightKg: classification.finalWeightKg,
      description: _description.text,
      itemCategory: _irisMatchedItemName ?? _inferPackageType(),
      dimensions: _irisTypicalDimensions == null
          ? null
          : DeliveryItemDimensions(
              lengthCm: _irisTypicalDimensions!.length,
              widthCm: _irisTypicalDimensions!.width,
              heightCm: _irisTypicalDimensions!.height,
            ),
      repositoryVehicleSuitability: _irisVehicleSuitability,
      fragile: _irisFragile,
      stackable: _irisStackable,
      handlingNotes: _irisHandlingNotes,
    );
  }

  DeliveryPricingBreakdown get _quoteBreakdown {
    final classification = _deliveryClassification;
    final chargeableWeightKg = classification.finalWeightKg;
    final distanceMiles = _confirmedRouteDistanceMiles ?? 0;
    return DeliveryPricing.calculate(
      DeliveryPricingInput(
        distanceMiles: distanceMiles,
        weightKg: chargeableWeightKg,
        vehicleType: _effectiveVehicle.name,
        economy: _selectedSpeed == 'Economy',
        express: _selectedSpeed == 'Express',
      ),
    );
  }

  void _selectPickupAddress(_ValidatedAddress address) {
    if (!address.hasCoordinates) {
      setState(() {
        _checkoutState = _CheckoutState.draft;
        _broadcasting = false;
        _validatedPickup = null;
        _firebaseError =
            'Pickup address selected, but no usable coordinates were returned. Choose a verified suggestion.';
      });
      return;
    }
    setState(() {
      _checkoutState = _CheckoutState.draft;
      _broadcasting = false;
      _validatedPickup = address;
      _pickup.text = address.displayAddress;
      _firebaseError = null;
    });
    _debugPricingInputs();
  }

  void _selectDropoffAddress(_ValidatedAddress address) {
    if (!address.hasCoordinates) {
      setState(() {
        _checkoutState = _CheckoutState.draft;
        _broadcasting = false;
        _validatedDropoff = null;
        _firebaseError =
            'Drop-off address selected, but no usable coordinates were returned. Choose a verified suggestion.';
      });
      return;
    }
    setState(() {
      _checkoutState = _CheckoutState.draft;
      _broadcasting = false;
      _validatedDropoff = address;
      _dropoff.text = address.displayAddress;
      _firebaseError = null;
    });
    _debugPricingInputs();
  }

  void _handlePickupEdited(String value) {
    if (_validatedPickup == null) return;
    if (value.trim() == _validatedPickup!.displayAddress) return;
    setState(() {
      _checkoutState = _CheckoutState.draft;
      _broadcasting = false;
      _validatedPickup = null;
    });
  }

  void _handleDropoffEdited(String value) {
    if (_validatedDropoff == null) return;
    if (value.trim() == _validatedDropoff!.displayAddress) return;
    setState(() {
      _checkoutState = _CheckoutState.draft;
      _broadcasting = false;
      _validatedDropoff = null;
    });
  }

  void _applySavedPickupAddress(SavedSenderAddress address) {
    final validated = address.toValidatedAddress();
    setState(() {
      _checkoutState = _CheckoutState.draft;
      _broadcasting = false;
      _pickup.text = address.address;
      _validatedPickup = validated;
      if (validated == null) {
        _firebaseError =
            'Saved pickup address needs revalidation. Choose it again from address suggestions.';
      } else {
        _firebaseError = null;
      }
    });
    if (validated != null) _debugPricingInputs();
  }

  void _applySavedDropoffAddress(SavedSenderAddress address) {
    final validated = address.toValidatedAddress();
    setState(() {
      _checkoutState = _CheckoutState.draft;
      _broadcasting = false;
      _dropoff.text = address.address;
      _validatedDropoff = validated;
      if (validated == null) {
        _firebaseError =
            'Saved drop-off address needs revalidation. Choose it again from address suggestions.';
      } else {
        _firebaseError = null;
      }
    });
    if (validated != null) _debugPricingInputs();
  }

  void _debugPricingInputs() {
    assert(() {
      debugPrint(
        'Circum booking debug: pickup=${_validatedPickup?.displayAddress}, '
        'dropoff=${_validatedDropoff?.displayAddress}, '
        'pickupLatLng=${_validatedPickup?.lat}/${_validatedPickup?.lng}, '
        'dropoffLatLng=${_validatedDropoff?.lat}/${_validatedDropoff?.lng}, '
        'distanceMiles=${_confirmedRouteDistanceMiles?.toStringAsFixed(2)}, '
        'pickupVerified=$_pickupAddressVerified, '
        'dropoffVerified=$_dropoffAddressVerified, '
        'pricingUnlocked=$_canAnalyzeDelivery, '
        'chargeableWeight=$_confirmedWeightKg, '
        'finalPrice=${_quoteBreakdown.total.toStringAsFixed(2)}',
      );
      return true;
    }());
  }

  HealthPlusPriceBreakdown get _healthQuote {
    return HealthPlusPricing.calculate(
      recurring: _healthFrequency != HealthPlusFrequency.oneOff,
      subscriptionPlan: _healthSubscriptionPlan,
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

  Future<void> _sendSenderPasswordReset() async {
    final email = _senderEmail.text.trim();
    if (email.isEmpty) {
      setState(() => _senderProfileMessage = 'Enter your email address first.');
      return;
    }
    setState(() {
      _senderAuthBusy = true;
      _senderProfileMessage = 'Sending password reset email...';
    });
    try {
      await _ensureFirebaseReady();
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() => _senderProfileMessage =
          'Password reset sent. Check your email and follow the secure link.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _senderProfileMessage = switch (error.code) {
            'invalid-email' => 'Enter a valid email address.',
            'user-not-found' =>
              'No Circum sender profile found for that email.',
            _ =>
              'We could not send the reset email. Check the address and try again.',
          });
    } finally {
      if (mounted) setState(() => _senderAuthBusy = false);
    }
  }

  Future<UserCredential> _reauthenticateSender(String password) async {
    final user = _senderUser ?? FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'requires-recent-login',
        message: 'Sign in again before changing account security settings.',
      );
    }
    return user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  Future<void> _changeSenderPassword() async {
    if (_senderSecurityBusy) return;
    final current = _senderCurrentPassword.text.trim();
    final next = _senderNewPassword.text.trim();
    final confirm = _senderConfirmNewPassword.text.trim();
    if (current.isEmpty || next.length < 6 || next != confirm) {
      setState(() => _senderSecurityMessage =
          'Enter your current password and make sure the new passwords match.');
      return;
    }
    setState(() {
      _senderSecurityBusy = true;
      _senderSecurityMessage = 'Updating password...';
    });
    try {
      await _ensureFirebaseReady();
      await _reauthenticateSender(current);
      await (_senderUser ?? FirebaseAuth.instance.currentUser)
          ?.updatePassword(next);
      _senderCurrentPassword.clear();
      _senderNewPassword.clear();
      _senderConfirmNewPassword.clear();
      if (!mounted) return;
      setState(() => _senderSecurityMessage = 'Password updated.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(
          () => _senderSecurityMessage = _friendlySenderAuthMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _senderSecurityMessage = 'Could not update password.');
    } finally {
      if (mounted) setState(() => _senderSecurityBusy = false);
    }
  }

  Future<void> _changeSenderEmail() async {
    if (_senderSecurityBusy) return;
    final nextEmail = _senderNewEmail.text.trim();
    final password = _senderEmailChangePassword.text.trim();
    if (nextEmail.isEmpty || !nextEmail.contains('@') || password.isEmpty) {
      setState(() => _senderSecurityMessage =
          'Enter the new email and your current password.');
      return;
    }
    setState(() {
      _senderSecurityBusy = true;
      _senderSecurityMessage = 'Updating email...';
    });
    try {
      await _ensureFirebaseReady();
      await _reauthenticateSender(password);
      final user = _senderUser ?? FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(code: 'requires-recent-login');
      }
      await user.verifyBeforeUpdateEmail(nextEmail);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'pendingEmail': nextEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _senderNewEmail.clear();
      _senderEmailChangePassword.clear();
      if (!mounted) return;
      setState(() => _senderSecurityMessage =
          'Verification sent. Open the email link to confirm the new address.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(
          () => _senderSecurityMessage = _friendlySenderAuthMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _senderSecurityMessage = 'Could not update email.');
    } finally {
      if (mounted) setState(() => _senderSecurityBusy = false);
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
    final validated = _validatedSavedAddress;
    if (user == null || address.isEmpty || validated == null) {
      setState(() => _senderProfileMessage =
          'Choose a verified address suggestion before saving.');
      return;
    }
    final next = [
      ...?_senderProfile?.savedAddresses,
      SavedSenderAddress(
        label: _savedAddressLabel.text.trim().isEmpty
            ? 'Saved address'
            : _savedAddressLabel.text.trim(),
        address: address,
        addressType: _savedAddressType,
        postcode: validated.postcode,
        lat: validated.lat,
        lng: validated.lng,
        placeId: validated.placeId,
        provider: validated.provider,
        locationId: validated.locationId,
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
      _validatedSavedAddress = null;
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
    if (!_hasValidatedRoute) {
      setState(() {
        _checkoutState = _CheckoutState.failed;
        _firebaseError = _locationValidationMessage;
      });
      return;
    }
    if (!_hasRequiredContactDetails) {
      setState(() {
        _checkoutState = _CheckoutState.failed;
        _firebaseError = _contactValidationMessage;
      });
      return;
    }
    setState(() {
      _checkoutState = _CheckoutState.validating;
      _analyzing = true;
      _broadcasting = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final senderWeight =
        DeliveryPricing.parseWeightKg(_weight.text, fallbackKg: 0);
    final estimate = await _estimateWeightWithIris();
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
      _irisWeightSource = estimate.weightSource;
      _irisMatchedItemName = estimate.matchedItemName;
      _irisWeightConfidenceScore = estimate.confidenceScore;
      _irisHistoricalVerifiedWeightKg = estimate.historicalVerifiedWeightKg;
      _irisLearningReason = estimate.learningReason;
      _irisTypicalDimensions = estimate.typicalDimensions;
      _irisVehicleSuitability = estimate.vehicleSuitability;
      _irisFragile = estimate.fragile;
      _irisStackable = estimate.stackable;
      _irisHandlingNotes = estimate.handlingNotes;
      _weightVerificationRequired = decision.verificationRequired;
      _weightPricingReason = decision.reason;
      _analyzing = false;
      _checkoutState = decision.weightKg == null
          ? _CheckoutState.draft
          : _CheckoutState.optionsReady;
      if (estimate.confidence == 'high' && senderWeight <= 0) {
        _weight.text = _formatWeight(estimate.weightKg);
      }
      _weightMessage = decision.message;
    });
    if (decision.weightKg != null) {
      _confirmWeight(
        decision.weightKg!,
        source: decision.source,
        reason: decision.reason,
        verificationRequired: decision.verificationRequired,
      );
    }
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
      weightSource: _irisWeightSource ?? 'category_fallback',
      matchedItemName: _irisMatchedItemName,
      confidenceScore: _irisWeightConfidenceScore,
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
      _checkoutState = _CheckoutState.awaitingPayment;
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
    final recommendedVehicleName = _vehicleSuitability.recommendedVehicle;
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
      if (!_matchingHasStarted) {
        _checkoutState = _CheckoutState.optionsReady;
      }
      if (!DeliveryPricing.vehicleCanCarryDelivery(
        _selectedVehicle.name,
        _vehicleSuitability,
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
      _checkoutState = _CheckoutState.draft;
      _broadcasting = false;
      _weightMessage = 'Confirm parcel weight before payment.';
    });
  }

  _WeightPricingDecision _resolvePricingWeight({
    required _IrisWeightEstimate estimate,
    required double? senderWeightKg,
  }) {
    final classification = DeliveryPricing.resolveClassification(
      description: _description.text,
      userEnteredWeightKg: senderWeightKg,
      irisEstimateKg: estimate.weightKg,
      historicalVerifiedMaxKg: estimate.historicalVerifiedWeightKg,
      confidence: estimate.confidence,
    );
    final hasSenderWeight = senderWeightKg != null && senderWeightKg > 0;
    final irisBand = DeliveryPricing.weightBandFor(estimate.weightKg);
    final senderBand =
        hasSenderWeight ? DeliveryPricing.weightBandFor(senderWeightKg) : null;
    final bandChanged =
        senderBand != null && senderBand.category != irisBand.category;
    final significantDifference = bandChanged ||
        classification.selectedWeightSource == 'keyword_override';
    final mismatchReview = _hasIrisMismatchReview(
      senderWeightKg: senderWeightKg,
      estimateWeightKg: estimate.weightKg,
    );
    final higherWeight = classification.finalWeightKg;
    final higherBand = DeliveryPricing.weightBandFor(higherWeight);

    if (!hasSenderWeight &&
        estimate.confidence == 'low' &&
        classification.selectedWeightSource != 'keyword_override') {
      return const _WeightPricingDecision(
        message: 'Confirm parcel weight before payment.',
        reason: 'Iris confidence is low, so sender weight is required.',
        verificationRequired: true,
      );
    }

    if (estimate.confidence == 'low') {
      return _WeightPricingDecision(
        weightKg: higherWeight,
        weightBand: higherBand.category,
        source: classification.selectedWeightSource,
        message: significantDifference
            ? 'Iris is not confident and the details may indicate a different weight band. Confirm your weight to continue; the rider will verify at pickup.'
            : 'IRIS has analysed this item and selected the most reliable weight available.',
        reason: classification.resolutionReason,
        verificationRequired: true,
      );
    }

    final source = classification.selectedWeightSource == 'keyword_override'
        ? 'keyword_override'
        : estimate.weightSource == 'known_product_lookup'
            ? 'repository_match'
            : estimate.weightKg >= (senderWeightKg ?? 0)
                ? 'photo_match'
                : 'customer_declared';

    return _WeightPricingDecision(
      weightKg: higherWeight,
      weightBand: higherBand.category,
      source: source,
      message: mismatchReview
          ? 'Potential mismatch detected — manual review required.'
          : significantDifference
              ? 'Iris and your entered weight fall into different pricing checks. Confirm the pricing weight before continuing.'
              : 'IRIS has analysed this item and selected the most reliable weight available.',
      reason: classification.resolutionReason,
      verificationRequired: mismatchReview ||
          significantDifference ||
          classification.requiresManualReview,
    );
  }

  bool _hasIrisMismatchReview({
    required double? senderWeightKg,
    required double estimateWeightKg,
  }) {
    return IrisWeightEstimator.potentialMismatchDetected(
      description: _description.text,
      customerDeclaredWeightKg: senderWeightKg,
      irisEstimatedWeightKg: estimateWeightKg,
    );
  }

  Future<_IrisWeightEstimate> _estimateWeightWithIris() async {
    final text = '${_description.text} ${_pickup.text} ${_dropoff.text}'
        .trim()
        .toLowerCase();
    final knownProduct = _knownProductWeightEstimate(text);
    if (knownProduct != null) {
      return _applyVerifiedParcelLearning(knownProduct, text);
    }

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

    final estimateResult = _IrisWeightEstimate(
      weightKg: estimate,
      weightBand: DeliveryPricing.weightBandFor(estimate).category,
      confidence: confidence,
      explanation: explanation,
      packageType: packageType,
      requiresVehicleReview: vehicleReview,
      weightSource: 'category_fallback',
      confidenceScore: _scoreForIrisConfidence(confidence),
    );
    return _applyVerifiedParcelLearning(estimateResult, text);
  }

  Future<_IrisWeightEstimate> _applyVerifiedParcelLearning(
    _IrisWeightEstimate base,
    String text,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return base;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('deliveryRequests')
          .where('senderId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'completed')
          .limit(40)
          .get();
      final matches = <double>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final description =
            '${data['packageDescription'] ?? data['description'] ?? ''}'
                .toLowerCase();
        if (!_looksLikeSimilarParcel(text, description)) continue;
        final verified = _readWeightKg(data['finalVerifiedWeight']) ??
            _readWeightKg(data['riderVerifiedWeight']) ??
            _readWeightKg(data['driverReportedWeightKg']) ??
            _readWeightKg(data['finalWeightUsed']) ??
            _readWeightKg(data['finalChargeableWeight']);
        if (verified != null && verified > 0) matches.add(verified);
      }
      if (matches.isEmpty) return base;
      matches.sort();
      final high = matches.last;
      final low = matches.first;
      final baseBand = DeliveryPricing.weightBandFor(base.weightKg).category;
      final learnedBand = DeliveryPricing.weightBandFor(high).category;
      if (high <= base.weightKg || learnedBand == baseBand) {
        return base.copyWith(
          historicalVerifiedWeightKg: high,
          learningReason:
              'Similar completed parcels were verified at ${_formatWeight(low)}–${_formatWeight(high)}kg.',
        );
      }
      return base.copyWith(
        weightKg: high,
        weightBand: learnedBand,
        confidence: base.confidence == 'low' ? 'medium' : base.confidence,
        confidenceScore: base.confidenceScore == null
            ? 0.7
            : base.confidenceScore!.clamp(0.7, 0.9).toDouble(),
        explanation:
            'Similar completed parcels were verified at ${_formatWeight(low)}–${_formatWeight(high)}kg.',
        weightSource: 'verified_parcel_history',
        truthBand: 'High Confidence',
        historicalVerifiedWeightKg: high,
        learningReason:
            'Similar completed parcels were verified at ${_formatWeight(low)}–${_formatWeight(high)}kg.',
      );
    } catch (_) {
      return base;
    }
  }

  bool _looksLikeSimilarParcel(String current, String previous) {
    final currentTokens = _parcelTokens(current);
    final previousTokens = _parcelTokens(previous);
    if (currentTokens.isEmpty || previousTokens.isEmpty) return false;
    return currentTokens.intersection(previousTokens).length >= 2 ||
        currentTokens.any(previousTokens.contains);
  }

  Set<String> _parcelTokens(String value) {
    const ignored = {
      'the',
      'and',
      'for',
      'with',
      'parcel',
      'package',
      'delivery',
      'send',
      'box',
    };
    return value
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length > 2 && !ignored.contains(token))
        .toSet();
  }

  double? _readWeightKg(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = DeliveryPricing.parseWeightKg(value, fallbackKg: 0);
      return parsed > 0 ? parsed : null;
    }
    return null;
  }

  _IrisWeightEstimate? _knownProductWeightEstimate(String text) {
    final product = IrisWeightEstimator.knownProductEstimate(text);
    if (product == null) return null;
    return _IrisWeightEstimate(
      weightKg: product.weightKg,
      weightBand: product.weightBand,
      confidence: product.confidence,
      explanation: product.explanation,
      packageType: product.packageType,
      requiresVehicleReview: product.requiresVehicleReview,
      weightSource: product.weightSource,
      truthBand: product.truthBand,
      matchedItemName: product.matchedItemName,
      confidenceScore: product.confidenceScore,
      typicalDimensions: product.typicalDimensions,
      vehicleSuitability: product.vehicleSuitability,
      fragile: product.fragile,
      stackable: product.stackable,
      handlingNotes: product.handlingNotes,
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

  double _irisConfidenceScore() {
    return _irisWeightConfidenceScore ??
        _scoreForIrisConfidence(_irisWeightConfidence);
  }

  String _irisTruthBand() {
    if (_irisWeightSource == 'known_product_lookup') return 'Exact Match';
    if (_irisWeightSource == 'verified_parcel_history') {
      return 'High Confidence';
    }
    return switch ((_irisWeightConfidence ?? '').toLowerCase()) {
      'high' => 'High Confidence',
      'medium' => 'Medium Confidence',
      'low' => 'Low Confidence',
      _ => 'Low Confidence',
    };
  }

  Map<String, dynamic>? _irisLearningData() {
    if (_irisHistoricalVerifiedWeightKg == null &&
        (_irisLearningReason == null || _irisLearningReason!.trim().isEmpty)) {
      return null;
    }
    return {
      'source': 'completed_sender_delivery_history',
      'historicalVerifiedWeightKg': _irisHistoricalVerifiedWeightKg,
      'reason': _irisLearningReason,
      'matchedDescription': _description.text.trim(),
      'adminReviewStatus': 'open',
      'canAdminOverride': true,
    };
  }

  double _scoreForIrisConfidence(String? confidence) {
    return switch ((confidence ?? '').toLowerCase()) {
      'high' => 0.9,
      'medium' => 0.65,
      'low' => 0.3,
      _ => 0,
    };
  }

  String _formatWeight(double weightKg) {
    return weightKg.truncateToDouble() == weightKg
        ? weightKg.toStringAsFixed(0)
        : weightKg.toStringAsFixed(1);
  }

  Future<void> _confirmPayment() async {
    if (!_hasValidatedRoute) {
      setState(() {
        _checkoutState = _CheckoutState.failed;
        _firebaseError = _locationValidationMessage;
        _step = _SenderStep.details;
      });
      return;
    }
    if (!_hasConfirmedWeight) {
      setState(() {
        _checkoutState = _CheckoutState.failed;
        _weightMessage = 'Confirm parcel weight before payment.';
        _step = _SenderStep.details;
      });
      return;
    }
    if (!_hasConsistentDispatchClassification) {
      final classification = _deliveryClassification;
      _confirmWeight(
        classification.finalWeightKg,
        source: classification.selectedWeightSource,
        reason: classification.resolutionReason,
        verificationRequired: true,
      );
      if (!_hasConsistentDispatchClassification) {
        setState(() {
          _checkoutState = _CheckoutState.failed;
          _firebaseError =
              'This delivery needs recalculation because weight, vehicle, and pricing do not match.';
          _step = _SenderStep.details;
        });
        return;
      }
    }
    if (_quoteBreakdown.requiresManualQuote ||
        _deliveryClassification.requiresManualReview) {
      setState(() {
        _checkoutState = _CheckoutState.failed;
        _firebaseError =
            'This delivery needs manual review because the item is heavy or specialist.';
        _step = _SenderStep.payment;
      });
      return;
    }
    final id =
        'CIR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    setState(() {
      _checkoutState = _CheckoutState.processingPayment;
      _activeOrderId = id;
      _activeRequestDocId = id;
      _broadcasting = false;
      _statusIndex = 0;
      _firebaseError = null;
    });

    try {
      await _ensureFirebaseReady();
      final db = FirebaseFirestore.instance;
      final request = _requestPayload(id);
      _activeVanguardData = request['vanguardEnabled'] == true
          ? Map<String, dynamic>.from(request)
          : null;
      final senderId = '${request['senderId']}';
      final batch = db.batch();
      batch.set(db.collection('webSenderRequests').doc(id), request);
      batch.set(db.collection('deliveryRequests').doc(id), request);
      batch.set(
          db.collection('chats').doc(id),
          {
            'threadId': id,
            'bookingId': id,
            'requestId': id,
            'participants': [senderId, 'circum-support'],
            'participantRoles': {
              senderId: 'sender',
              'circum-support': 'admin',
            },
            'lastMessage':
                'Your request is live. Iris is checking nearby riders now.',
            'lastMessageTimestamp': FieldValue.serverTimestamp(),
            'unreadBy': ['admin'],
            'updatedAt': FieldValue.serverTimestamp(),
            'source': 'circum-web',
          },
          SetOptions(merge: true));
      batch.set(db.collection('chats').doc(id).collection('messages').doc(), {
        'threadId': id,
        'bookingId': id,
        'requestId': id,
        'senderId': senderId,
        'senderRole': 'system',
        'senderType': 'support',
        'recipientId': senderId,
        'recipientType': 'sender',
        'messageText':
            'Your request is live. Iris is checking nearby riders now.',
        'message': 'Your request is live. Iris is checking nearby riders now.',
        'readBy': [senderId],
        'system': true,
        'status': 'sent',
        'createdAt': FieldValue.serverTimestamp(),
        'timeStamp': DateTime.now().toIso8601String(),
      });
      await batch.commit();
      _listenToRequest(id);
      _listenToChat(id);
      if (!mounted) return;
      setState(() {
        _checkoutState = _CheckoutState.matchingRiders;
        _broadcasting = true;
        _firebaseOnline = true;
        _step = _SenderStep.tracking;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkoutState = _CheckoutState.failed;
        _broadcasting = false;
        _firebaseOnline = false;
        _firebaseError =
            'We could not save this delivery just now. Please try again.';
      });
    }
  }

  Future<void> _bookHealthPlus() async {
    String? validationMessage;
    if (_healthName.text.trim().isEmpty) {
      validationMessage = 'Add your full name to continue.';
    } else if (_healthPhone.text.trim().isEmpty) {
      validationMessage = 'Add a phone number for pickup updates.';
    } else if (_healthEmail.text.trim().isEmpty) {
      validationMessage = 'Add an email address for your receipt.';
    } else if (_healthPharmacy.text.trim().isEmpty) {
      validationMessage = 'Add the pharmacy pickup address.';
    } else if (_healthDelivery.text.trim().isEmpty) {
      validationMessage = 'Add the delivery address.';
    } else if (_healthPrescriptionType.trim().isEmpty) {
      validationMessage = 'Choose the prescription type.';
    } else if (_healthFrequency == HealthPlusFrequency.custom &&
        _healthCustomSchedule.text.trim().isEmpty) {
      validationMessage = 'Add the custom pickup date or repeat pattern.';
    } else if (!_healthConsent) {
      validationMessage =
          'Please confirm the consent box before booking Health+.';
    }

    if (_healthSubmitting) return;
    if (validationMessage != null) {
      setState(() => _healthMessage = validationMessage);
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
        'pharmacyName': _healthPharmacyName.text.trim(),
        'pharmacyAddress': _healthPharmacy.text.trim(),
        'deliveryAddress': _healthDelivery.text.trim(),
        'notes': _healthNotes.text.trim(),
        'prescriptionNotes': _healthNotes.text.trim(),
        'prescriptionType': _healthPrescriptionType,
        'subscriptionPlan': _healthSubscriptionPlan,
        'healthPlusPlan': _healthSubscriptionPlan,
        'preferredDay': _healthPreferredDay.text.trim(),
        'preferredTime': _healthPreferredTime.text.trim(),
        'preferredPickupDay': _healthPreferredDay.text.trim(),
        'preferredPickupTime': _healthPreferredTime.text.trim(),
        'frequency': _healthFrequency.value,
        'recurring': scheduleId != null,
        'customSchedule': _healthCustomSchedule.text.trim(),
        'priorityRiderMatching': _healthSubscriptionPlan == 'priority',
        'consentConfirmed': _healthConsent,
        'consentAccepted': _healthConsent,
        'status': scheduleId == null ? 'one_off' : 'active',
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
        'pharmacyName': _healthPharmacyName.text.trim(),
        'pharmacyAddress': _healthPharmacy.text.trim(),
        'deliveryAddress': _healthDelivery.text.trim(),
        'notes': _healthNotes.text.trim(),
        'prescriptionNotes': _healthNotes.text.trim(),
        'prescriptionType': _healthPrescriptionType,
        'subscriptionPlan': _healthSubscriptionPlan,
        'healthPlusPlan': _healthSubscriptionPlan,
        'preferredDay': _healthPreferredDay.text.trim(),
        'preferredTime': _healthPreferredTime.text.trim(),
        'consentAccepted': _healthConsent,
        'preferredPickupTime': _healthPreferredTime.text.trim(),
        'preferredPickupDay': _healthPreferredDay.text.trim(),
        'scheduledPickupDate': _healthPreferredDay.text.trim(),
        'scheduledPickupWindow': _healthPreferredTime.text.trim(),
        'scheduledDropoffDate': _healthPreferredDay.text.trim(),
        'scheduledDropoffWindow': _healthPreferredTime.text.trim(),
        'frequency': _healthFrequency.value,
        'recurring': scheduleId != null,
        'customSchedule': _healthCustomSchedule.text.trim(),
        'priorityRiderMatching': _healthSubscriptionPlan == 'priority',
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
          'pharmacyName': _healthPharmacyName.text.trim(),
          'pharmacyAddress': _healthPharmacy.text.trim(),
          'deliveryAddress': _healthDelivery.text.trim(),
          'prescriptionType': _healthPrescriptionType,
          'subscriptionPlan': _healthSubscriptionPlan,
          'healthPlusPlan': _healthSubscriptionPlan,
          'preferredDay': _healthPreferredDay.text.trim(),
          'preferredTime': _healthPreferredTime.text.trim(),
          'prescriptionNotes': _healthNotes.text.trim(),
          'consentAccepted': _healthConsent,
          'status': 'active',
          'preferredDayTime':
              '${_healthPreferredDay.text.trim()} ${_healthPreferredTime.text.trim()}'
                  .trim(),
          'scheduledPickupDate': _healthPreferredDay.text.trim(),
          'scheduledPickupWindow': _healthPreferredTime.text.trim(),
          'scheduledDropoffDate': _healthPreferredDay.text.trim(),
          'scheduledDropoffWindow': _healthPreferredTime.text.trim(),
          'customSchedule': _healthCustomSchedule.text.trim(),
          'paused': false,
          'nextPickupAt':
              '${_healthPreferredDay.text.trim()} ${_healthPreferredTime.text.trim()}'
                  .trim(),
          'stripeCustomerId': null,
          'stripeSubscriptionId': null,
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
        'frequency': _healthFrequency.value,
        'subscriptionPlan': _healthSubscriptionPlan,
        'paymentType':
            scheduleId == null ? 'one_time_checkout' : 'subscription_checkout',
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
        'frequency': _healthFrequency.value,
        'prescriptionType': _healthPrescriptionType,
        'subscriptionPlan': _healthSubscriptionPlan,
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
          'frequency': _healthFrequency == HealthPlusFrequency.every28Days
              ? HealthPlusFrequency.custom.value
              : _healthFrequency.value,
          'subscriptionPlan': _healthSubscriptionPlan,
          'prescriptionType': _healthPrescriptionType,
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
      'status': 'paused',
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

  Future<void> _resumeHealthPlusSchedule() async {
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
      'paused': false,
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await FirebaseFirestore.instance.collection('healthPlusUsageEvents').add({
      'type': 'recurring_pickup_resumed',
      'profileId': _healthProfileId,
      'scheduleId': scheduleId,
      'status': 'active',
      'source': 'circum-web',
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() => _healthMessage = 'Your repeat Health+ pickup is active.');
  }

  Future<void> _cancelHealthPlusSchedule() async {
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
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await FirebaseFirestore.instance.collection('healthPlusUsageEvents').add({
      'type': 'recurring_pickup_cancelled',
      'profileId': _healthProfileId,
      'scheduleId': scheduleId,
      'status': 'cancelled',
      'source': 'circum-web',
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() => _healthMessage = 'Your repeat Health+ pickup is cancelled.');
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
    final classification = _deliveryClassification;
    final pickupAddress = _validatedPickup!;
    final dropoffAddress = _validatedDropoff!;
    final distanceMiles = _confirmedRouteDistanceMiles!;
    final economyQuote = DeliveryPricing.calculate(DeliveryPricingInput(
      distanceMiles: distanceMiles,
      weightKg: classification.finalWeightKg,
      vehicleType: _effectiveVehicle.name,
      economy: true,
    ));
    final standardQuote = DeliveryPricing.calculate(DeliveryPricingInput(
      distanceMiles: distanceMiles,
      weightKg: classification.finalWeightKg,
      vehicleType: _effectiveVehicle.name,
    ));
    final expressQuote = DeliveryPricing.calculate(DeliveryPricingInput(
      distanceMiles: distanceMiles,
      weightKg: classification.finalWeightKg,
      vehicleType: _effectiveVehicle.name,
      express: true,
    ));
    final selectedServiceLevel = switch (_selectedSpeed) {
      'Economy' => 'economy',
      'Express' => 'express',
      _ => 'standard',
    };
    final serviceLevelSurcharge = double.parse(
      (quote.total - standardQuote.total).toStringAsFixed(2),
    );
    final irisVerified = (_irisWeightConfidence ?? '').toLowerCase() != 'low';
    final senderUser = _senderUser ?? FirebaseAuth.instance.currentUser;
    final senderId = senderUser?.uid ?? 'web-sender';
    final senderName = _effectiveSenderName;
    final senderPhone = _effectiveSenderPhone;
    final receiverName = _receiverName.text.trim();
    final receiverPhone = _receiverPhone.text.trim();
    final collectionContactName = _effectiveCollectionContactName;
    final collectionContactPhone = _effectiveCollectionContactPhone;
    final collectionContactDifferent = _differentCollectionContact;
    final requestCode = id.replaceAll(RegExp(r'[^0-9]'), '').padLeft(6, '0');
    final pickupGeo = pickupAddress.toPositionMap();
    final dropoffGeo = dropoffAddress.toPositionMap();
    final packageType = _inferPackageType();
    final vanguardFields = VanguardProtection.initialFields(
      description: _description.text.trim(),
      packageType: packageType,
      declaredValueGbp: null,
    );
    final vanguardEnabled = vanguardFields['vanguardEnabled'] == true;
    final hasPhoto = false;
    final suitability = _vehicleSuitability;
    final safeVehicleName = suitability.recommendedVehicle;
    final driverPayout = DeliveryPricing.riderPayoutFromFare(quote.total);
    final platformRevenue =
        DeliveryPricing.platformRevenueFromFare(quote.total);
    final driverJobSummary = {
      'pickupDisplay': _pickup.text.trim(),
      'dropoffDisplay': _dropoff.text.trim(),
      'estimatedDistanceMiles': distanceMiles,
      'estimatedDurationMinutes': 28,
      'scheduledPickupDate': _scheduledPickupDate.text.trim(),
      'scheduledPickupWindow': _scheduledPickupWindow.text.trim(),
      'scheduledDropoffDate': _scheduledDropoffDate.text.trim(),
      'scheduledDropoffWindow': _scheduledDropoffWindow.text.trim(),
      'confirmedWeightKg': classification.finalWeightKg,
      'confirmedWeightBand': classification.finalWeightBand,
      'deliveryClassification': {
        ...classification.toJson(),
        'vehicleType': safeVehicleName,
      },
      'vehicleSuitability': {
        'recommendedVehicle': suitability.recommendedVehicle,
        'allowedVehicles': suitability.allowedVehicles,
        'score': suitability.score,
        'factors': suitability.factors,
        'explanation': suitability.explanation,
        'handlingNotes': suitability.handlingNotes,
        'fragile': suitability.fragile,
        'stackable': suitability.stackable,
      },
      'finalWeightKg': classification.finalWeightKg,
      'finalWeightBand': classification.finalWeightBand,
      'selectedWeightSource': classification.selectedWeightSource,
      'displayWeightSource': _weightSource,
      'resolutionReason': classification.resolutionReason,
      'requiresManualReview': classification.requiresManualReview,
      'packageType': packageType,
      'packageDescription': _description.text.trim(),
      'hasPhoto': hasPhoto,
      'photoUrl': null,
      'deliveryInstructions': _description.text.trim(),
      'vehicleType': safeVehicleName,
      'totalFare': quote.total,
      'driverPayout': driverPayout,
      'riderPayout': driverPayout,
      'platformRevenue': platformRevenue,
      'serviceLevel': selectedServiceLevel,
      'selectedServiceLevel': selectedServiceLevel,
      'senderName': senderName,
      'senderPhone': senderPhone,
      'collectionContactName': collectionContactName,
      'collectionContactPhone': collectionContactPhone,
      'collectionContactDifferent': collectionContactDifferent,
      'receiverName': receiverName,
      'receiverPhone': receiverPhone,
      'priority': selectedServiceLevel == 'express',
      'matchingPriority': selectedServiceLevel == 'express' ? 'high' : 'normal',
      'broadcastRank': DeliveryPricing.matchingPriorityRank(
        selectedServiceLevel,
      ),
      'customerDeclaredWeight': _senderEnteredWeightKg,
      'customerWeight': _senderEnteredWeightKg,
      'irisEstimatedWeight': _irisEstimatedWeightKg,
      'irisWeight': _irisEstimatedWeightKg,
      'irisWeightSource': _irisWeightSource ?? 'unknown',
      'irisMatchedItemName': _irisMatchedItemName,
      'catalogueMatchWeight': _irisWeightSource == 'known_product_lookup'
          ? _irisEstimatedWeightKg
          : null,
      'aiEstimatedWeight': _irisWeightSource == 'known_product_lookup'
          ? null
          : _irisEstimatedWeightKg,
      'irisVerified': irisVerified,
      'irisConfidence': _irisWeightConfidence ?? 'unknown',
      'irisTruthBand': _irisTruthBand(),
      'irisLearningData': _irisLearningData(),
      'finalChargeableWeight': classification.finalWeightKg,
      'finalWeight': classification.finalWeightKg,
      'finalWeightUsed': classification.finalWeightKg,
      'irisConfidenceScore': _irisConfidenceScore(),
      'specialHandlingNotes': _weightVerificationRequired
          ? 'Weight verification required at pickup.'
          : vanguardEnabled
              ? 'Vanguard protected delivery. PIN verification required at pickup and delivery.'
              : '',
      'vanguardEnabled': vanguardEnabled,
      'serviceType': selectedServiceLevel == 'express'
          ? 'Express Delivery'
          : selectedServiceLevel == 'economy'
              ? 'Economy Delivery'
              : 'Normal Delivery',
    };
    return {
      'requestId': id,
      'code': requestCode.substring(requestCode.length - 6),
      'pickupAddress': pickupAddress.displayAddress,
      'dropoffAddress': dropoffAddress.displayAddress,
      'pickupAddressRaw': pickupAddress.rawInput,
      'dropoffAddressRaw': dropoffAddress.rawInput,
      'pickupAddressCanonical': pickupAddress.toJson(),
      'dropoffAddressCanonical': dropoffAddress.toJson(),
      'distanceMiles': distanceMiles,
      'routeDistanceMiles': distanceMiles,
      'routeDistanceSource': 'validated_coordinates',
      'routeDistanceConfirmed': true,
      'packageType': packageType,
      'packageDescription': _description.text.trim(),
      'weight': _weight.text.trim(),
      'weightKg': classification.finalWeightKg,
      'deliveryClassification': classification.toJson(),
      'finalWeightKg': classification.finalWeightKg,
      'finalWeightBand': classification.finalWeightBand,
      'selectedWeightSource': classification.selectedWeightSource,
      'displayWeightSource': _weightSource,
      'resolutionReason': classification.resolutionReason,
      'requiresManualReview': classification.requiresManualReview,
      'customerDeclaredWeight': _senderEnteredWeightKg,
      'customerWeight': _senderEnteredWeightKg,
      'irisEstimatedWeight': _irisEstimatedWeightKg,
      'irisWeight': _irisEstimatedWeightKg,
      'irisWeightSource': _irisWeightSource ?? 'unknown',
      'irisMatchedItemName': _irisMatchedItemName,
      'catalogueMatchWeight': _irisWeightSource == 'known_product_lookup'
          ? _irisEstimatedWeightKg
          : null,
      'aiEstimatedWeight': _irisWeightSource == 'known_product_lookup'
          ? null
          : _irisEstimatedWeightKg,
      'irisVerified': irisVerified,
      'irisConfidence': _irisWeightConfidence ?? 'unknown',
      'irisTruthBand': _irisTruthBand(),
      'irisLearningData': _irisLearningData(),
      'finalChargeableWeight': classification.finalWeightKg,
      'finalWeight': classification.finalWeightKg,
      'finalWeightUsed': classification.finalWeightKg,
      'irisConfidenceScore': _irisConfidenceScore(),
      'weightReviewRequired': _weightVerificationRequired,
      'irisEstimatedWeightKg': _irisEstimatedWeightKg,
      'irisWeightBand': _irisWeightBand,
      'irisWeightConfidence': _irisWeightConfidence,
      'irisWeightExplanation': _irisWeightExplanation,
      'senderEnteredWeightKg': _senderEnteredWeightKg,
      'confirmedWeightKg': classification.finalWeightKg,
      'confirmedWeightBand': classification.finalWeightBand,
      'declaredWeightKg': _senderEnteredWeightKg,
      'driverReportedWeightKg': null,
      'driverWeightDispute': {
        'reported': false,
        'status': 'none',
      },
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
      'weightCategory': classification.finalWeightBand,
      'vehicle': safeVehicleName,
      'selectedVehicle': safeVehicleName,
      'preferredVehicle': safeVehicleName.toLowerCase(),
      'vehicleType': safeVehicleName,
      'speed': _selectedSpeed,
      'selectedTier': selectedServiceLevel,
      'serviceLevel': selectedServiceLevel,
      'selectedServiceLevel': selectedServiceLevel,
      'economyPrice': economyQuote.total,
      'standardPrice': standardQuote.total,
      'expressPrice': expressQuote.total,
      'basePrice': standardQuote.total,
      'finalPrice': quote.total,
      'finalCustomerPrice': quote.total,
      'serviceLevelSurcharge':
          serviceLevelSurcharge < 0 ? 0 : serviceLevelSurcharge,
      'priority': selectedServiceLevel == 'express',
      'matchingPriority': selectedServiceLevel == 'express' ? 'high' : 'normal',
      'broadcastRank': DeliveryPricing.matchingPriorityRank(
        selectedServiceLevel,
      ),
      'quote': quote.total,
      'price': quote.total,
      'fare': quote.total,
      'driverPayout': driverPayout,
      'riderPayout': driverPayout,
      'platformRevenue': platformRevenue,
      'platformShare': DeliveryPricing.platformDeliveryFareShare,
      'driverShare': DeliveryPricing.riderDeliveryFareShare,
      'pricingBreakdown': quote.toJson(),
      ...vanguardFields,
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
      'senderPhone': senderPhone,
      'senderEmail': senderUser?.email,
      'senderDetails': {
        'userId': senderId,
        'name': senderName,
        'phone': senderPhone,
        'email': senderUser?.email,
      },
      'collectionContact': {
        'name': collectionContactName,
        'phone': collectionContactPhone,
        'sameAsSender': !collectionContactDifferent,
        'differentFromSender': collectionContactDifferent,
      },
      'receiverDetails': {
        'name': receiverName,
        'phone': receiverPhone,
      },
      'collectionContactName': collectionContactName,
      'collectionContactPhone': collectionContactPhone,
      'collectionContactDifferent': collectionContactDifferent,
      'receiverName': receiverName,
      'receiverPhone': receiverPhone,
      'appMatchingCompatible': true,
      'driverJobSummary': driverJobSummary,
      'matchingRules': {
        'collection': 'deliveryRequests',
        'availableStatus': 'requested',
        'positionField': 'pickupPosition.geopoint',
        'sortBy': selectedServiceLevel == 'express'
            ? 'priorityThenPickupThenDistance'
            : 'distanceFromRider',
        'preferredVehicle': safeVehicleName.toLowerCase(),
        'requiresVerifiedRider': true,
        'matchingPriority':
            selectedServiceLevel == 'express' ? 'high' : 'normal',
      },
      'pickupDetails': {
        'fullname': collectionContactName,
        'phone': collectionContactPhone,
        'senderName': senderName,
        'senderPhone': senderPhone,
        'collectionContactName': collectionContactName,
        'collectionContactPhone': collectionContactPhone,
        'collectionContactDifferent': collectionContactDifferent,
        'position': pickupGeo,
        'address': pickupAddress.displayAddress,
        'rawAddress': pickupAddress.rawInput,
        'postcode': pickupAddress.postcode,
        'geocodeConfidence': pickupAddress.confidence,
        'subAddress': '',
        'locality': 'London',
        'moreInformation': _description.text.trim(),
        'scheduledDate': _scheduledPickupDate.text.trim(),
        'scheduledWindow': _scheduledPickupWindow.text.trim(),
      },
      'dropoffDetails': {
        'fullname': receiverName,
        'phone': receiverPhone,
        'receiverName': receiverName,
        'receiverPhone': receiverPhone,
        'position': dropoffGeo,
        'address': dropoffAddress.displayAddress,
        'rawAddress': dropoffAddress.rawInput,
        'postcode': dropoffAddress.postcode,
        'geocodeConfidence': dropoffAddress.confidence,
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
    _listenToLiveLocation(id);
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
        final matchingStatus = status == 'requested' || status == 'pending';
        if (driverId != null || _statusIndexFromFirebase(status) > 0) {
          _checkoutState = _CheckoutState.riderAssigned;
        } else if (matchingStatus &&
            (_checkoutState == _CheckoutState.bookingCreated ||
                _checkoutState == _CheckoutState.matchingRiders)) {
          _checkoutState = _CheckoutState.matchingRiders;
        }
        _firebaseOnline = true;
        _firebaseError = null;
        _broadcasting =
            _checkoutState == _CheckoutState.matchingRiders && matchingStatus;
        _statusIndex = _statusIndexFromFirebase(status);
        _activeVanguardData = data['vanguardEnabled'] == true
            ? Map<String, dynamic>.from(data)
            : null;
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
        _checkoutState = _CheckoutState.failed;
        _broadcasting = false;
        _firebaseOnline = false;
        _firebaseError = 'Could not listen to this delivery in Firestore.';
      });
    });
  }

  void _listenToLiveLocation(String deliveryId) {
    _liveLocationSub?.cancel();
    _liveLocationSub = FirebaseFirestore.instance
        .collection('deliveryRequests')
        .doc(deliveryId)
        .collection('tracking')
        .doc('liveLocation')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _liveLocationData = snapshot.data();
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() => _liveLocationData = null);
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
            if (_selectedTipAmount > 0) ...{
              'tipAmount': _selectedTipAmount,
              'riderTip': _selectedTipAmount,
              'tipStatus': 'paid',
            },
            'ratedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        if (_selectedTipAmount > 0) {
          final tipTxId = '${requestId}_${driverId}_tip';
          transaction.set(
            db.collection('riderWalletTransactions').doc(tipTxId),
            {
              'transactionId': tipTxId,
              'requestId': requestId,
              'riderId': driverId,
              'customerId': customerId,
              'type': 'tip',
              'tipAmount': _selectedTipAmount,
              'amount': _selectedTipAmount,
              'status': 'available',
              'source': 'circum-web',
              'createdAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          transaction.set(
            db.collection('riderEarnings').doc(driverId),
            {
              'availableBalance': FieldValue.increment(_selectedTipAmount),
              'lifetimeEarnings': FieldValue.increment(_selectedTipAmount),
              'tipsReceived': FieldValue.increment(_selectedTipAmount),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
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
        final senderRole = '${data['senderRole'] ?? senderType}';
        final message =
            '${data['messageText'] ?? data['message'] ?? ''}'.trim();
        if (message.isEmpty) continue;
        final chatMessage = _ChatMessage(
          fromMe: data['senderId'] == _senderUser?.uid &&
              senderRole != 'system' &&
              senderType != 'support',
          text: message,
          time: _formatMessageTime(data['createdAt'], data['timeStamp']),
          label: senderRole == 'system' ||
                  senderType == 'support' ||
                  senderType == 'admin'
              ? 'CIRCUM Support'
              : senderType == 'rider' || senderType == 'driver'
                  ? 'Rider'
                  : 'You',
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
        'threadId': requestId,
        'bookingId': requestId,
        'requestId': requestId,
        'senderId': _senderUser?.uid ?? 'web-sender',
        'senderRole': 'sender',
        'senderType': 'user',
        'recipientId': _supportChat
            ? 'circum-support'
            : (_assignedDriverId ?? 'assigned-rider'),
        'recipientType': _supportChat ? 'admin' : 'rider',
        'messageText': text,
        'message': text,
        'status': 'sent',
        'readBy': [_senderUser?.uid ?? 'web-sender'],
        'createdAt': FieldValue.serverTimestamp(),
        'timeStamp': DateTime.now().toIso8601String(),
      });
      await chatRef.set({
        'threadId': requestId,
        'bookingId': requestId,
        'requestId': requestId,
        'lastMessage': text,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'participants': FieldValue.arrayUnion([
          _senderUser?.uid ?? 'web-sender',
          _supportChat
              ? 'circum-support'
              : (_assignedDriverId ?? 'assigned-rider')
        ]),
        'unreadBy': FieldValue.arrayUnion([_supportChat ? 'admin' : 'rider']),
        'updatedAt': FieldValue.serverTimestamp(),
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
    _liveLocationSub?.cancel();
    _chatSub?.cancel();
    _driverProfileSub?.cancel();
    _driverPerformanceSub?.cancel();
    _assignedDriverRatingsSub?.cancel();
    setState(() {
      _step = _SenderStep.dashboard;
      _checkoutState = _CheckoutState.draft;
      _activeOrderId = null;
      _activeRequestDocId = null;
      _assignedDriverId = null;
      _assignedDriver = null;
      _assignedDriverMetric = null;
      _activeVanguardData = null;
      _liveLocationData = null;
      _statusIndex = 0;
      _broadcasting = false;
      _selectedRating = 0;
      _selectedTipAmount = 0;
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
  final _CheckoutState checkoutState;
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
    required this.checkoutState,
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
                          'Delivery Status',
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
                    'See the current milestone, route summary, price, rider match, and delivery status in one place.',
                    style: TextStyle(
                      color: colors.mutedText,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _GlassPanel(
                    colors: colors,
                    child: Row(
                      children: [
                        Icon(Icons.flag_circle, color: colors.text),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                status.title,
                                style: TextStyle(
                                  color: colors.text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                status.body,
                                style: TextStyle(
                                  color: colors.mutedText,
                                  height: 1.35,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
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
                                ? 'Express service'
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
                    checkoutState: checkoutState,
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
  final VoidCallback onForgotPassword;

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
    required this.onForgotPassword,
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : onForgotPassword,
                  child: const Text('Forgot Password?'),
                ),
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
  final ValueChanged<SavedSenderAddress> onSelect;

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
                onPressed: () => onSelect(address),
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
  final String? matchedItemName;
  final String truthBand;
  final double? senderEnteredWeightKg;
  final double? pricingWeightKg;
  final String weightSource;
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
    required this.matchedItemName,
    required this.truthBand,
    required this.senderEnteredWeightKg,
    required this.pricingWeightKg,
    required this.weightSource,
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
              'IRIS estimate: ${estimatedWeightKg!.toStringAsFixed(estimatedWeightKg!.truncateToDouble() == estimatedWeightKg ? 0 : 1)} kg'
              '${weightBand == null ? '' : ' · $weightBand'}'
              '${confidence == null ? '' : ' · ${_confidenceDisplayText()}'}',
              style: TextStyle(color: colors.mutedText, height: 1.35),
            ),
          ],
          if (matchedItemName != null &&
              matchedItemName!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Matched item: $matchedItemName · $truthBand',
              style: TextStyle(
                color: colors.text,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (senderEnteredWeightKg != null) ...[
            const SizedBox(height: 4),
            Text(
              'Your estimate: ${senderEnteredWeightKg!.toStringAsFixed(senderEnteredWeightKg!.truncateToDouble() == senderEnteredWeightKg ? 0 : 1)} kg',
              style: TextStyle(color: colors.mutedText, height: 1.35),
            ),
          ],
          if (pricingWeightKg != null) ...[
            const SizedBox(height: 8),
            Text(
              '✓ Final pricing weight: ${pricingWeightKg!.toStringAsFixed(pricingWeightKg!.truncateToDouble() == pricingWeightKg ? 0 : 3)}kg',
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '✓ Source: $weightSource',
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
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
              pricingReason!,
              style: TextStyle(color: colors.mutedText, height: 1.35),
            ),
          ],
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => _showIrisInfo(context),
            icon: Icon(Icons.info_outline, color: colors.adminAccent, size: 18),
            label: Text(
              'Learn how IRIS works',
              style: TextStyle(
                color: colors.adminAccent,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
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
              label: const Text(
                'IRIS has calculated the pricing weight. Rider will verify at collection.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _confidenceDisplayText() {
    final source = weightSource.toLowerCase();
    if (truthBand == 'Exact Match') return 'Exact Match (High Confidence)';
    if (source == 'repository match')
      return 'Repository Match (Medium Confidence)';
    if (source == 'photo match') return 'Image Estimate (Medium Confidence)';
    if (source == 'customer declared')
      return 'User Declared Only (Low Confidence)';
    return '$truthBand${confidence == null ? '' : ' (${confidence!} confidence)'}';
  }

  void _showIrisInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.panel,
        title: Text(
          'How IRIS works',
          style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
        ),
        content: Text(
          'IRIS compares:\n'
          '• Item description\n'
          '• Product catalogue matches\n'
          '• Image analysis, if provided\n'
          '• Customer declared weight\n'
          '• Rider verification\n\n'
          'To ensure fair pricing, the most reliable credible weight is used.',
          style: TextStyle(color: colors.mutedText, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
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
  final TextEditingController currentPassword;
  final TextEditingController newPassword;
  final TextEditingController confirmNewPassword;
  final TextEditingController newEmail;
  final TextEditingController emailChangePassword;
  final bool securitySubmitting;
  final String? securityMessage;
  final TextEditingController savedAddressLabel;
  final TextEditingController savedAddress;
  final String savedAddressType;
  final VoidCallback onBack;
  final ValueChanged<int> onTab;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final VoidCallback onForgotPassword;
  final VoidCallback onChangePassword;
  final VoidCallback onChangeEmail;
  final VoidCallback onSignOut;
  final VoidCallback onSaveProfile;
  final VoidCallback onAddAddress;
  final ValueChanged<String> onSavedAddressType;
  final ValueChanged<_ValidatedAddress> onSavedAddressSelected;
  final ValueChanged<String> onSavedAddressEdited;
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
    required this.currentPassword,
    required this.newPassword,
    required this.confirmNewPassword,
    required this.newEmail,
    required this.emailChangePassword,
    required this.securitySubmitting,
    required this.securityMessage,
    required this.savedAddressLabel,
    required this.savedAddress,
    required this.savedAddressType,
    required this.onBack,
    required this.onTab,
    required this.onSignIn,
    required this.onSignUp,
    required this.onForgotPassword,
    required this.onChangePassword,
    required this.onChangeEmail,
    required this.onSignOut,
    required this.onSaveProfile,
    required this.onAddAddress,
    required this.onSavedAddressType,
    required this.onSavedAddressSelected,
    required this.onSavedAddressEdited,
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
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : onForgotPassword,
                child: const Text('Forgot Password?'),
              ),
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
        const SizedBox(height: 14),
        _AccountSecurityPanel(
          colors: colors,
          title: 'Security',
          currentPassword: currentPassword,
          newPassword: newPassword,
          confirmNewPassword: confirmNewPassword,
          newEmail: newEmail,
          emailChangePassword: emailChangePassword,
          submitting: securitySubmitting,
          message: securityMessage,
          onChangePassword: onChangePassword,
          onChangeEmail: onChangeEmail,
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
        _AddressField(
          colors: colors,
          icon: Icons.place_outlined,
          label: savedAddressType == 'dropoff'
              ? 'Drop-off address'
              : 'Pickup address',
          controller: savedAddress,
          verified: false,
          onSelected: onSavedAddressSelected,
          onEdited: onSavedAddressEdited,
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
  final ValueChanged<SavedSenderAddress> onSavedPickup;
  final ValueChanged<SavedSenderAddress> onSavedDropoff;
  final bool pickupVerified;
  final bool dropoffVerified;
  final String locationValidationMessage;
  final _CheckoutState checkoutState;
  final bool canSubmit;
  final TextEditingController senderName;
  final TextEditingController senderPhone;
  final String senderDisplayName;
  final String senderDisplayPhone;
  final bool senderDetailsRequired;
  final TextEditingController receiverName;
  final TextEditingController receiverPhone;
  final bool differentCollectionContact;
  final TextEditingController collectionContactName;
  final TextEditingController collectionContactPhone;
  final bool contactDetailsReady;
  final String contactValidationMessage;
  final ValueChanged<bool> onDifferentCollectionContact;
  final ValueChanged<_ValidatedAddress> onPickupSelected;
  final ValueChanged<_ValidatedAddress> onDropoffSelected;
  final ValueChanged<String> onPickupEdited;
  final ValueChanged<String> onDropoffEdited;
  final TextEditingController description;
  final TextEditingController weight;
  final double? irisEstimatedWeightKg;
  final String? irisWeightBand;
  final String? irisWeightConfidence;
  final String? irisWeightExplanation;
  final String? irisMatchedItemName;
  final String irisTruthBand;
  final double? senderEnteredWeightKg;
  final double? pricingWeightKg;
  final String weightSource;
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
    required this.pickupVerified,
    required this.dropoffVerified,
    required this.locationValidationMessage,
    required this.checkoutState,
    required this.canSubmit,
    required this.senderName,
    required this.senderPhone,
    required this.senderDisplayName,
    required this.senderDisplayPhone,
    required this.senderDetailsRequired,
    required this.receiverName,
    required this.receiverPhone,
    required this.differentCollectionContact,
    required this.collectionContactName,
    required this.collectionContactPhone,
    required this.contactDetailsReady,
    required this.contactValidationMessage,
    required this.onDifferentCollectionContact,
    required this.onPickupSelected,
    required this.onDropoffSelected,
    required this.onPickupEdited,
    required this.onDropoffEdited,
    required this.description,
    required this.weight,
    required this.irisEstimatedWeightKg,
    required this.irisWeightBand,
    required this.irisWeightConfidence,
    required this.irisWeightExplanation,
    required this.irisMatchedItemName,
    required this.irisTruthBand,
    required this.senderEnteredWeightKg,
    required this.pricingWeightKg,
    required this.weightSource,
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
    final matchingHasStarted = checkoutState == _CheckoutState.matchingRiders ||
        checkoutState == _CheckoutState.riderAssigned;
    final validating = analyzing || checkoutState == _CheckoutState.validating;
    final ctaLabel = matchingHasStarted
        ? 'Delivery is connecting'
        : validating
            ? 'Checking options...'
            : canSubmit
                ? 'See delivery options'
                : !pickupVerified || !dropoffVerified
                    ? 'Verify addresses before pricing'
                    : !contactDetailsReady
                        ? 'Add contact details before pricing'
                        : 'Confirm route before pricing';
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
                verified: pickupVerified,
                onSelected: onPickupSelected,
                onEdited: onPickupEdited,
                verifiedMessage: 'Verified pickup address selected',
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
                verified: dropoffVerified,
                onSelected: onDropoffSelected,
                onEdited: onDropoffEdited,
                verifiedMessage: 'Verified drop-off address selected',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    pickupVerified && dropoffVerified
                        ? Icons.verified
                        : Icons.info_outline,
                    color: pickupVerified && dropoffVerified
                        ? colors.success
                        : colors.mutedText,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      locationValidationMessage,
                      style: TextStyle(
                        color: pickupVerified && dropoffVerified
                            ? colors.text
                            : colors.mutedText,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
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
              _SectionTitle(colors: colors, title: 'People involved'),
              const SizedBox(height: 10),
              if (senderDetailsRequired) ...[
                Text(
                  'Add sender details for the person booking this delivery.',
                  style: TextStyle(
                    color: colors.mutedText,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _InputBox(
                        colors: colors,
                        controller: senderName,
                        hint: 'Sender name',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _InputBox(
                        colors: colors,
                        controller: senderPhone,
                        hint: 'Sender phone',
                      ),
                    ),
                  ],
                ),
              ] else ...[
                _ContactSummaryLine(
                  colors: colors,
                  icon: Icons.person,
                  label: 'Sender',
                  value: '$senderDisplayName • $senderDisplayPhone',
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _InputBox(
                      colors: colors,
                      controller: receiverName,
                      hint: 'Receiver name',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _InputBox(
                      colors: colors,
                      controller: receiverPhone,
                      hint: 'Receiver phone',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: differentCollectionContact,
                onChanged: (value) =>
                    onDifferentCollectionContact(value ?? false),
                activeColor: colors.text,
                title: Text(
                  'Is someone else handing over the parcel?',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (differentCollectionContact) ...[
                Row(
                  children: [
                    Expanded(
                      child: _InputBox(
                        colors: colors,
                        controller: collectionContactName,
                        hint: 'Collection contact name',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _InputBox(
                        colors: colors,
                        controller: collectionContactPhone,
                        hint: 'Collection contact phone',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              _ContactSummaryLine(
                colors: colors,
                icon: contactDetailsReady ? Icons.verified : Icons.info_outline,
                label: 'Contact check',
                value: contactValidationMessage,
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
                    child: _CompactSelectBox(
                      colors: colors,
                      controller: scheduledPickupDate,
                      label: 'Pickup date',
                      options: _scheduleDateOptions,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CompactSelectBox(
                      colors: colors,
                      controller: scheduledPickupWindow,
                      label: 'Pickup window',
                      options: _pickupWindowOptions,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _CompactSelectBox(
                      colors: colors,
                      controller: scheduledDropoffDate,
                      label: 'Delivery date',
                      options: _scheduleDateOptions,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CompactSelectBox(
                      colors: colors,
                      controller: scheduledDropoffWindow,
                      label: 'Delivery window',
                      options: _deliveryWindowOptions,
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
                  matchedItemName: irisMatchedItemName,
                  truthBand: irisTruthBand,
                  senderEnteredWeightKg: senderEnteredWeightKg,
                  pricingWeightKg: pricingWeightKg,
                  weightSource: weightSource,
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
            onPressed: validating || matchingHasStarted || !canSubmit
                ? null
                : onSubmit,
            icon: validating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(ctaLabel),
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

class _ContactSummaryLine extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String label;
  final String value;

  const _ContactSummaryLine({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colors.mutedText, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label: $value',
            style: TextStyle(
              color: colors.mutedText,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w700,
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
  final TextEditingController pharmacyName;
  final TextEditingController pharmacyAddress;
  final TextEditingController deliveryAddress;
  final TextEditingController notes;
  final TextEditingController preferredDay;
  final TextEditingController preferredTime;
  final TextEditingController customSchedule;
  final HealthPlusFrequency frequency;
  final String prescriptionType;
  final String subscriptionPlan;
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
  final ValueChanged<String> onPrescriptionType;
  final ValueChanged<String> onSubscriptionPlan;
  final ValueChanged<String> onStartSubscription;
  final VoidCallback onContinueOneOff;
  final ValueChanged<bool?> onConsent;
  final ValueChanged<bool?> onSavePayment;
  final VoidCallback onSubmit;
  final VoidCallback onPauseSchedule;
  final VoidCallback onResumeSchedule;
  final VoidCallback onCancelSchedule;
  final VoidCallback onCancelPickup;
  final VoidCallback onUpdatePayment;
  final ValueChanged<String> onAdminStatus;

  const _HealthPlusStep({
    super.key,
    required this.colors,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.pharmacyName,
    required this.pharmacyAddress,
    required this.deliveryAddress,
    required this.notes,
    required this.preferredDay,
    required this.preferredTime,
    required this.customSchedule,
    required this.frequency,
    required this.prescriptionType,
    required this.subscriptionPlan,
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
    required this.onPrescriptionType,
    required this.onSubscriptionPlan,
    required this.onStartSubscription,
    required this.onContinueOneOff,
    required this.onConsent,
    required this.onSavePayment,
    required this.onSubmit,
    required this.onPauseSchedule,
    required this.onResumeSchedule,
    required this.onCancelSchedule,
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
                          'Arrange one-off or recurring prescription pickups from a pharmacy to your door. From £11.',
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
                  _HealthChip(label: 'Prescription pickup'),
                  _HealthChip(label: 'Recurring reminders'),
                  _HealthChip(label: 'Secure checkout'),
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
              _SectionTitle(colors: colors, title: 'Pharmacy / pickup details'),
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
                  controller: pharmacyName,
                  hint: 'Pharmacy name'),
              const SizedBox(height: 10),
              _AddressField(
                  colors: colors,
                  icon: Icons.local_pharmacy,
                  controller: pharmacyAddress,
                  label: 'Pharmacy pickup address',
                  pharmacyMode: true),
              const SizedBox(height: 10),
              _AddressField(
                  colors: colors,
                  icon: Icons.home_outlined,
                  controller: deliveryAddress,
                  label: 'Delivery address'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(colors: colors, title: 'Prescription details'),
              const SizedBox(height: 12),
              _PrescriptionTypePicker(
                colors: colors,
                selected: prescriptionType,
                onChanged: onPrescriptionType,
              ),
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
              _SectionTitle(colors: colors, title: 'Recurring schedule'),
              const SizedBox(height: 12),
              _HealthFrequencyPicker(
                colors: colors,
                selected: frequency,
                onChanged: onFrequency,
              ),
              const SizedBox(height: 10),
              _InputBox(
                colors: colors,
                controller: preferredDay,
                hint: 'Preferred pickup day',
              ),
              const SizedBox(height: 10),
              _InputBox(
                colors: colors,
                controller: preferredTime,
                hint: 'Preferred pickup time',
              ),
              if (frequency == HealthPlusFrequency.custom) ...[
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: customSchedule,
                  hint: 'Custom pickup date or repeat pattern',
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
              _SectionTitle(colors: colors, title: 'Subscription plan'),
              const SizedBox(height: 12),
              _HealthPlanGrid(
                colors: colors,
                selectedPlan: subscriptionPlan,
                onSelect: onSubscriptionPlan,
                onStartSubscription: onStartSubscription,
                onContinueOneOff: onContinueOneOff,
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
              _SectionTitle(colors: colors, title: 'Price breakdown'),
              const SizedBox(height: 10),
              _PriceLine(
                  colors: colors,
                  label: 'Base pickup fee',
                  value: '£${quote.delivery.baseFare.toStringAsFixed(2)}'),
              _PriceLine(
                  colors: colors,
                  label: 'Distance estimate',
                  value: '£${quote.delivery.distanceFare.toStringAsFixed(2)}'),
              _PriceLine(
                  colors: colors,
                  label: 'Health+ care fee',
                  value: '£${quote.serviceFee.toStringAsFixed(2)}'),
              if (quote.priorityFee > 0)
                _PriceLine(
                    colors: colors,
                    label: 'Priority fee',
                    value: '£${quote.priorityFee.toStringAsFixed(2)}'),
              if (quote.familySupportFee > 0)
                _PriceLine(
                    colors: colors,
                    label: 'Family support',
                    value: '£${quote.familySupportFee.toStringAsFixed(2)}'),
              if (quote.recurringDiscount > 0)
                _PriceLine(
                    colors: colors,
                    label: 'Recurring discount',
                    value: '-£${quote.recurringDiscount.toStringAsFixed(2)}'),
              if (quote.minimumAdjustment > 0)
                _PriceLine(
                    colors: colors,
                    label: 'Health+ minimum adjustment',
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
        _HealthTrustGrid(colors: colors),
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
          onResumeSchedule: onResumeSchedule,
          onCancelSchedule: onCancelSchedule,
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
    const visibleFrequencies = [
      HealthPlusFrequency.oneOff,
      HealthPlusFrequency.weekly,
      HealthPlusFrequency.everyTwoWeeks,
      HealthPlusFrequency.every28Days,
      HealthPlusFrequency.monthly,
      HealthPlusFrequency.custom,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: visibleFrequencies.map((frequency) {
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

class _PrescriptionTypePicker extends StatelessWidget {
  static const types = [
    'NHS prescription',
    'Private prescription',
    'Repeat prescription',
    'Over-the-counter sealed package',
  ];

  final _CircumColors colors;
  final String selected;
  final ValueChanged<String> onChanged;

  const _PrescriptionTypePicker({
    required this.colors,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((type) {
        final active = type == selected;
        return ChoiceChip(
          selected: active,
          onSelected: (_) => onChanged(type),
          label: Text(type),
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

class _HealthPlanGrid extends StatelessWidget {
  final _CircumColors colors;
  final String selectedPlan;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onStartSubscription;
  final VoidCallback onContinueOneOff;

  const _HealthPlanGrid({
    required this.colors,
    required this.selectedPlan,
    required this.onSelect,
    required this.onStartSubscription,
    required this.onContinueOneOff,
  });

  @override
  Widget build(BuildContext context) {
    const plans = [
      _HealthPlanCopy(
        id: 'basic',
        title: 'Health+ Basic',
        price: 'From £11',
        benefits: [
          'Discounted recurring pickups',
          'Medicine delivery reminders',
          'Secure sealed-package handover',
        ],
      ),
      _HealthPlanCopy(
        id: 'priority',
        title: 'Health+ Priority',
        price: 'Priority matching',
        benefits: [
          'Priority rider matching',
          'Faster pickup target',
          'Recurring prescription reminders',
        ],
      ),
      _HealthPlanCopy(
        id: 'family',
        title: 'Health+ Family',
        price: 'Family support',
        benefits: [
          'Support for elderly relatives',
          'Shared pickup notes',
          'Repeat medicine reminders',
        ],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 720;
        return Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: plans.map((plan) {
            final card = _HealthPlanCard(
              colors: colors,
              plan: plan,
              selected: plan.id == selectedPlan,
              onSelect: () => onSelect(plan.id),
              onStartSubscription: () => onStartSubscription(plan.id),
              onContinueOneOff: onContinueOneOff,
            );
            return stacked
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: card,
                  )
                : Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: card,
                    ),
                  );
          }).toList(),
        );
      },
    );
  }
}

class _HealthPlanCopy {
  final String id;
  final String title;
  final String price;
  final List<String> benefits;

  const _HealthPlanCopy({
    required this.id,
    required this.title,
    required this.price,
    required this.benefits,
  });
}

class _HealthPlanCard extends StatelessWidget {
  final _CircumColors colors;
  final _HealthPlanCopy plan;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onStartSubscription;
  final VoidCallback onContinueOneOff;

  const _HealthPlanCard({
    required this.colors,
    required this.plan,
    required this.selected,
    required this.onSelect,
    required this.onStartSubscription,
    required this.onContinueOneOff,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.field.withAlpha(209),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xff38bdf8) : colors.border,
            width: selected ? 1.6 : 1,
          ),
          gradient: selected
              ? LinearGradient(
                  colors: _spectrumGradient
                      .map((color) => color.withAlpha(41))
                      .toList(),
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.title,
              style: TextStyle(
                color: colors.text,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              plan.price,
              style: TextStyle(
                color: colors.mutedText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ...plan.benefits.map((benefit) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check, color: colors.success, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          benefit,
                          style: TextStyle(
                            color: colors.mutedText,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onStartSubscription,
              child: const Text('Start subscription'),
            ),
            TextButton(
              onPressed: onContinueOneOff,
              child: const Text('Continue one-off pickup'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthTrustGrid extends StatelessWidget {
  final _CircumColors colors;

  const _HealthTrustGrid({required this.colors});

  @override
  Widget build(BuildContext context) {
    const cards = [
      (Icons.verified_user, 'Verified rider'),
      (Icons.inventory_2_outlined, 'Sealed package only'),
      (Icons.handshake_outlined, 'Secure handover'),
      (Icons.medical_information_outlined, 'No medical advice provided'),
      (
        Icons.assignment_turned_in_outlined,
        'Prescription remains customer/pharmacy responsibility'
      ),
    ];

    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Rider and security trust'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cards
                .map(
                  (card) => Container(
                    width: 220,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.field,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(card.$1, color: colors.text, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            card.$2,
                            style: TextStyle(
                              color: colors.text,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
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
            'Health+ is a prescription pickup and delivery service only.',
            'Circum does not prescribe medication or provide medical advice.',
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
  final VoidCallback onResumeSchedule;
  final VoidCallback onCancelSchedule;
  final VoidCallback onCancelPickup;
  final VoidCallback onUpdatePayment;

  const _HealthDashboard({
    required this.colors,
    required this.pickup,
    required this.payments,
    required this.onPauseSchedule,
    required this.onResumeSchedule,
    required this.onCancelSchedule,
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
                  onPressed: onResumeSchedule,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume recurring'),
                ),
                OutlinedButton.icon(
                  onPressed: onCancelSchedule,
                  icon: const Icon(Icons.event_busy),
                  label: const Text('Cancel subscription'),
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
  final String weightSource;
  final String truthBand;
  final String? matchedItemName;
  final double? confidenceScore;
  final double? historicalVerifiedWeightKg;
  final String? learningReason;
  final ItemDimensionsCm? typicalDimensions;
  final String? vehicleSuitability;
  final bool fragile;
  final bool stackable;
  final String? handlingNotes;

  const _IrisWeightEstimate({
    required this.weightKg,
    required this.weightBand,
    required this.confidence,
    required this.explanation,
    required this.packageType,
    required this.requiresVehicleReview,
    this.weightSource = 'category_fallback',
    this.truthBand = 'Low Confidence',
    this.matchedItemName,
    this.confidenceScore,
    this.historicalVerifiedWeightKg,
    this.learningReason,
    this.typicalDimensions,
    this.vehicleSuitability,
    this.fragile = false,
    this.stackable = true,
    this.handlingNotes,
  });

  _IrisWeightEstimate copyWith({
    double? weightKg,
    String? weightBand,
    String? confidence,
    String? explanation,
    String? packageType,
    bool? requiresVehicleReview,
    String? weightSource,
    String? truthBand,
    String? matchedItemName,
    double? confidenceScore,
    double? historicalVerifiedWeightKg,
    String? learningReason,
    ItemDimensionsCm? typicalDimensions,
    String? vehicleSuitability,
    bool? fragile,
    bool? stackable,
    String? handlingNotes,
  }) {
    return _IrisWeightEstimate(
      weightKg: weightKg ?? this.weightKg,
      weightBand: weightBand ?? this.weightBand,
      confidence: confidence ?? this.confidence,
      explanation: explanation ?? this.explanation,
      packageType: packageType ?? this.packageType,
      requiresVehicleReview:
          requiresVehicleReview ?? this.requiresVehicleReview,
      weightSource: weightSource ?? this.weightSource,
      truthBand: truthBand ?? this.truthBand,
      matchedItemName: matchedItemName ?? this.matchedItemName,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      historicalVerifiedWeightKg:
          historicalVerifiedWeightKg ?? this.historicalVerifiedWeightKg,
      learningReason: learningReason ?? this.learningReason,
      typicalDimensions: typicalDimensions ?? this.typicalDimensions,
      vehicleSuitability: vehicleSuitability ?? this.vehicleSuitability,
      fragile: fragile ?? this.fragile,
      stackable: stackable ?? this.stackable,
      handlingNotes: handlingNotes ?? this.handlingNotes,
    );
  }
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

class _AddressSuggestion {
  final String displayAddress;
  final double? lat;
  final double? lng;
  final double confidence;
  final String provider;
  final String sourceInput;
  final String? placeId;
  final String? searchText;
  final String? category;
  final Map<String, String> components;

  const _AddressSuggestion({
    required this.displayAddress,
    this.lat,
    this.lng,
    required this.confidence,
    required this.provider,
    required this.sourceInput,
    this.placeId,
    this.searchText,
    this.category,
    this.components = const {},
  });

  bool get isPopularPlace => provider == 'circum_popular_place';

  _ValidatedAddress toValidatedAddress() {
    final resolvedLat = lat ?? 0;
    final resolvedLng = lng ?? 0;
    return _ValidatedAddress(
      rawInput: sourceInput,
      displayAddress: displayAddress,
      postcode: components['postcode'] ?? _extractUkPostcode(displayAddress),
      lat: resolvedLat,
      lng: resolvedLng,
      confidence: confidence,
      provider: provider,
      locationId: placeId ??
          _stableLocationId(displayAddress, resolvedLat, resolvedLng),
      placeId: placeId,
      buildingNumber: components['buildingNumber'],
      street: components['street'],
      city: components['city'],
      county: components['county'],
      country: components['country'],
    );
  }
}

class _ValidatedAddress {
  final String rawInput;
  final String displayAddress;
  final String? postcode;
  final double lat;
  final double lng;
  final double confidence;
  final String provider;
  final String locationId;
  final String? placeId;
  final String? buildingNumber;
  final String? street;
  final String? city;
  final String? county;
  final String? country;

  const _ValidatedAddress({
    required this.rawInput,
    required this.displayAddress,
    required this.postcode,
    required this.lat,
    required this.lng,
    required this.confidence,
    required this.provider,
    required this.locationId,
    this.placeId,
    this.buildingNumber,
    this.street,
    this.city,
    this.county,
    this.country,
  });

  bool get hasCoordinates => _coordinatesAreUsable(lat, lng);

  Map<String, dynamic> toJson() => {
        'rawInput': rawInput,
        'displayAddress': displayAddress,
        'postcode': postcode,
        'lat': lat,
        'lng': lng,
        'geocodeConfidence': confidence,
        'provider': provider,
        'locationId': locationId,
        if (placeId != null) 'placeId': placeId,
        if (buildingNumber != null) 'buildingNumber': buildingNumber,
        if (street != null) 'street': street,
        if (city != null) 'city': city,
        if (county != null) 'county': county,
        if (country != null) 'country': country,
      };

  Map<String, dynamic> toPositionMap() => {
        'geopoint': GeoPoint(lat, lng),
        'lat': lat,
        'lng': lng,
        'geocodeConfidence': confidence,
        'locationId': locationId,
        if (placeId != null) 'placeId': placeId,
        'provider': provider,
      };
}

extension _SavedSenderAddressValidation on SavedSenderAddress {
  _ValidatedAddress? toValidatedAddress() {
    final savedLat = lat;
    final savedLng = lng;
    if (savedLat == null ||
        savedLng == null ||
        !_coordinatesAreUsable(savedLat, savedLng)) {
      return null;
    }
    return _ValidatedAddress(
      rawInput: address,
      displayAddress: address,
      postcode: postcode ?? _extractUkPostcode(address),
      lat: savedLat,
      lng: savedLng,
      confidence: 0.98,
      provider: provider ?? 'saved_google_place',
      locationId: locationId ?? _stableLocationId(address, savedLat, savedLng),
      placeId: placeId,
    );
  }
}

String? _extractUkPostcode(String address) {
  final match = RegExp(
    r'\b([A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2})\b',
    caseSensitive: false,
  ).firstMatch(address);
  return match?.group(1)?.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
}

Map<String, String> _googleAddressComponents(List<dynamic> components) {
  String? byType(String type) {
    for (final component in components.whereType<Map<String, dynamic>>()) {
      final types = (component['types'] as List<dynamic>? ?? const [])
          .map((value) => '$value')
          .toSet();
      if (types.contains(type)) return '${component['long_name']}';
    }
    return null;
  }

  final streetNumber = byType('street_number');
  final route = byType('route');
  final city = byType('postal_town') ?? byType('locality');
  final county = byType('administrative_area_level_2');
  final postcode = byType('postal_code');
  final country = byType('country');
  return {
    if (streetNumber != null) 'buildingNumber': streetNumber,
    if (route != null) 'street': route,
    if (city != null) 'city': city,
    if (county != null) 'county': county,
    if (postcode != null) 'postcode': postcode,
    if (country != null) 'country': country,
  };
}

String _cleanGoogleAddress(String address) {
  return address
      .replaceAll(', UK', ', United Kingdom')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _stableLocationId(String address, double lat, double lng) {
  final normalized =
      address.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return '${normalized.substring(0, math.min(normalized.length, 48))}'
      '-${lat.toStringAsFixed(4)}-${lng.toStringAsFixed(4)}';
}

String _cityForAddress(String value) {
  final lower = value.toLowerCase();
  for (final city in _ukCityCoordinates.keys) {
    if (lower.contains(city.toLowerCase())) return city;
  }
  final postcode = _extractUkPostcode(value);
  if (postcode != null) {
    final outward = _postcodeOutward(postcode);
    if (outward.startsWith('CR')) return 'Croydon';
    if (outward.startsWith('SE') ||
        outward.startsWith('SW') ||
        outward.startsWith('E') ||
        outward.startsWith('N') ||
        outward.startsWith('NW') ||
        outward.startsWith('W')) {
      return 'London';
    }
  }
  return 'London';
}

bool _coordinatesAreUsable(double lat, double lng) {
  if (!lat.isFinite || !lng.isFinite) return false;
  if (lat == 0 || lng == 0) return false;
  return lat >= 49 && lat <= 61 && lng >= -9 && lng <= 2;
}

bool _coordinatesAreSame(
  double pickupLat,
  double pickupLng,
  double dropoffLat,
  double dropoffLng,
) {
  return (pickupLat - dropoffLat).abs() < 0.0005 &&
      (pickupLng - dropoffLng).abs() < 0.0005;
}

double? _coordinateDistanceMiles(
  double pickupLat,
  double pickupLng,
  double dropoffLat,
  double dropoffLng,
) {
  if (!_coordinatesAreUsable(pickupLat, pickupLng) ||
      !_coordinatesAreUsable(dropoffLat, dropoffLng)) {
    return null;
  }
  if (_coordinatesAreSame(pickupLat, pickupLng, dropoffLat, dropoffLng)) {
    return null;
  }
  const earthRadiusMiles = 3958.8;
  final dLat = _degreesToRadians(dropoffLat - pickupLat);
  final dLng = _degreesToRadians(dropoffLng - pickupLng);
  final lat1 = _degreesToRadians(pickupLat);
  final lat2 = _degreesToRadians(dropoffLat);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  final directMiles = earthRadiusMiles * c;
  if (directMiles < 0.15) return null;
  return double.parse((directMiles * 1.25).clamp(0.2, 999).toStringAsFixed(2));
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180;

String _postcodeOutward(String postcode) {
  return postcode
      .toUpperCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .split(' ')
      .first;
}

(double, double)? _postcodeCoordinatesForAddress(String address) {
  final postcode = _extractUkPostcode(address);
  if (postcode == null) return null;
  final outward = _postcodeOutward(postcode);
  final area = RegExp(r'^[A-Z]+').firstMatch(outward)?.group(0);
  return _ukPostcodeCoordinates[outward] ??
      (area == null ? null : _ukPostcodeCoordinates[area]);
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
  final VehicleSuitability vehicleSuitability;
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
    required this.vehicleSuitability,
    required this.selectedVehicle,
    required this.selectedSpeed,
    required this.onVehicle,
    required this.onSpeed,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final recommendedVehicleName = vehicleSuitability.recommendedVehicle;
    final canContinue = DeliveryPricing.vehicleCanCarryDelivery(
      selectedVehicle.name,
      vehicleSuitability,
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
                      '${vehicleSuitability.explanation}\nRecommended vehicle: $recommendedVehicleName.',
                      style: TextStyle(
                        color: colors.mutedText,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: vehicleSuitability.factors
                          .map((factor) => _HealthChip(label: '✓ $factor'))
                          .toList(),
                    ),
                    if (vehicleSuitability.handlingNotes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        vehicleSuitability.handlingNotes,
                        style: TextStyle(
                          color: colors.mutedText,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                    'Vehicle recommendation based on weight, dimensions, and item type. Recommended vehicle: $recommendedVehicleName.',
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
  final double? distanceMiles;
  final bool locationsConfirmed;
  final String routeMessage;
  final double? irisEstimatedWeightKg;
  final double? senderEnteredWeightKg;
  final double weightKg;
  final double total;
  final _CheckoutState checkoutState;
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
    required this.distanceMiles,
    required this.locationsConfirmed,
    required this.routeMessage,
    required this.irisEstimatedWeightKg,
    required this.senderEnteredWeightKg,
    required this.weightKg,
    required this.total,
    required this.checkoutState,
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
    final processingPayment = checkoutState == _CheckoutState.processingPayment;
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
                    distanceMiles == null
                        ? 'Distance not confirmed'
                        : '${distanceMiles!.toStringAsFixed(1)} miles',
                    style: TextStyle(
                      color: colors.mutedText,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _PriceLine(
                colors: colors,
                label: 'Route',
                value: routeMessage,
                strong: locationsConfirmed,
              ),
              Divider(color: colors.border, height: 26),
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
                label: 'Service',
                value: switch (speed) {
                  'Economy' => 'Economy - lowest price',
                  'Express' => 'Express - priority matching',
                  _ => 'Standard - flexible pickup',
                },
              ),
              _PriceLine(
                colors: colors,
                label: 'Final pricing weight',
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
                  label: 'Your estimate',
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
                  label: 'IRIS note',
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
                        ? 'Express service'
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
            onPressed: weightConfirmed &&
                    locationsConfirmed &&
                    !breakdown.requiresManualQuote &&
                    !processingPayment
                ? onPay
                : null,
            icon: processingPayment
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock),
            label: Text(
              processingPayment
                  ? 'Processing payment...'
                  : !locationsConfirmed
                      ? 'Confirm pickup and drop-off before payment'
                      : breakdown.requiresManualQuote
                          ? 'Manual review required'
                          : weightConfirmed
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
  final _CheckoutState checkoutState;
  final bool firebaseOnline;
  final String? firebaseError;
  final _ValidatedAddress? pickupAddress;
  final _ValidatedAddress? dropoffAddress;
  final Map<String, dynamic>? liveLocation;
  final Map<String, dynamic>? vanguardData;
  final DriverProfile? assignedDriver;
  final DriverPerformanceMetric? assignedDriverMetric;
  final int ratingStars;
  final TextEditingController ratingFeedback;
  final Set<String> selectedRatingTags;
  final double selectedTipAmount;
  final bool ratingSubmitting;
  final bool ratingSubmitted;
  final String? ratingMessage;
  final ValueChanged<int> onRatingChanged;
  final ValueChanged<String> onRatingTag;
  final ValueChanged<double> onTipChanged;
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
    required this.checkoutState,
    required this.firebaseOnline,
    required this.firebaseError,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.liveLocation,
    required this.vanguardData,
    required this.assignedDriver,
    required this.assignedDriverMetric,
    required this.ratingStars,
    required this.ratingFeedback,
    required this.selectedRatingTags,
    required this.selectedTipAmount,
    required this.ratingSubmitting,
    required this.ratingSubmitted,
    required this.ratingMessage,
    required this.onRatingChanged,
    required this.onRatingTag,
    required this.onTipChanged,
    required this.onSubmitRating,
    required this.onChatDriver,
    required this.onChatSupport,
    required this.onNewOrder,
  });

  @override
  Widget build(BuildContext context) {
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
                    'Delivery Status',
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
          checkoutState: checkoutState,
        ),
        if (vanguardData?['vanguardEnabled'] == true) ...[
          const SizedBox(height: 14),
          _VanguardCustomerPanel(colors: colors, data: vanguardData!),
        ],
        const SizedBox(height: 14),
        _LiveDeliveryTrackingPanel(
          colors: colors,
          pickup: pickupAddress,
          dropoff: dropoffAddress,
          liveLocation: liveLocation,
          statusIndex: statusIndex,
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
            selectedTipAmount: selectedTipAmount,
            submitting: ratingSubmitting,
            submitted: ratingSubmitted,
            message: ratingMessage,
            onRatingChanged: onRatingChanged,
            onTag: onRatingTag,
            onTipChanged: onTipChanged,
            onSubmit: onSubmitRating,
          ),
        ],
        const SizedBox(height: 14),
        _RouteSummary(colors: colors, pickup: pickup, dropoff: dropoff),
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

class _LiveDeliveryTrackingPanel extends StatelessWidget {
  final _CircumColors colors;
  final _ValidatedAddress? pickup;
  final _ValidatedAddress? dropoff;
  final Map<String, dynamic>? liveLocation;
  final int statusIndex;

  const _LiveDeliveryTrackingPanel({
    required this.colors,
    required this.pickup,
    required this.dropoff,
    required this.liveLocation,
    required this.statusIndex,
  });

  @override
  Widget build(BuildContext context) {
    final live = liveLocation;
    final riderLat = _num(live?['latitude']);
    final riderLng = _num(live?['longitude']);
    final updatedAt = _dateTimeFromFirestore(live?['updatedAt']);
    final fresh = updatedAt != null &&
        DateTime.now().difference(updatedAt).inSeconds <= 60;
    final hasLiveTracking = fresh &&
        pickup?.hasCoordinates == true &&
        dropoff?.hasCoordinates == true &&
        riderLat != null &&
        riderLng != null &&
        _coordinatesAreUsable(riderLat, riderLng);

    if (!hasLiveTracking) {
      return _GlassPanel(
        colors: colors,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_off, color: colors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tracking temporarily unavailable',
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Live GPS will appear when the assigned rider is travelling and has location enabled.',
              style: TextStyle(
                color: colors.mutedText,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _Timeline(colors: colors, activeIndex: statusIndex),
          ],
        ),
      );
    }

    final destination = statusIndex < 2 ? pickup! : dropoff!;
    final remainingMiles = _coordinateDistanceMiles(
          riderLat,
          riderLng,
          destination.lat,
          destination.lng,
        ) ??
        0;
    final etaMinutes = math.max(1, (remainingMiles / 18 * 60).round());
    final mapUrl = _staticLiveMapUrl(
      pickup: pickup!,
      dropoff: dropoff!,
      riderLat: riderLat,
      riderLng: riderLng,
    );

    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gps_fixed, color: colors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Live rider location',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'Updated ${_relativeSeconds(updatedAt!)} ago',
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 1.65,
              child: Image.network(
                mapUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _Timeline(
                  colors: colors,
                  activeIndex: statusIndex,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RiderStatTile(
                  colors: colors,
                  label: 'Remaining',
                  value: '${remainingMiles.toStringAsFixed(1)} mi',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RiderStatTile(
                  colors: colors,
                  label: 'Dynamic ETA',
                  value: '$etaMinutes min',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static double? _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static DateTime? _dateTimeFromFirestore(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String _relativeSeconds(DateTime updatedAt) {
    final seconds = DateTime.now().difference(updatedAt).inSeconds;
    if (seconds < 1) return 'now';
    return '${seconds}s';
  }

  static String _staticLiveMapUrl({
    required _ValidatedAddress pickup,
    required _ValidatedAddress dropoff,
    required double riderLat,
    required double riderLng,
  }) {
    final params = {
      'size': '900x540',
      'scale': '2',
      'maptype': 'roadmap',
      'markers': [
        'color:blue|label:P|${pickup.lat},${pickup.lng}',
        'color:green|label:D|${dropoff.lat},${dropoff.lng}',
        'color:red|label:R|$riderLat,$riderLng',
      ],
      'path':
          'color:0x2563ebff|weight:5|${pickup.lat},${pickup.lng}|$riderLat,$riderLng|${dropoff.lat},${dropoff.lng}',
      'key': _googlePlacesApiKey,
    };
    return Uri.https(
      'maps.googleapis.com',
      '/maps/api/staticmap',
      params,
    ).toString();
  }
}

class _FirebaseStatusBanner extends StatelessWidget {
  final _CircumColors colors;
  final bool online;
  final String? error;
  final _CheckoutState checkoutState;

  const _FirebaseStatusBanner({
    required this.colors,
    required this.online,
    required this.error,
    required this.checkoutState,
  });

  @override
  Widget build(BuildContext context) {
    final healthy = online &&
        error == null &&
        (checkoutState == _CheckoutState.matchingRiders ||
            checkoutState == _CheckoutState.riderAssigned);
    final message = switch (checkoutState) {
      _CheckoutState.bookingCreated =>
        'Booking created. Preparing rider search.',
      _CheckoutState.matchingRiders => 'Connecting this delivery...',
      _CheckoutState.riderAssigned => 'Rider assigned. Tracking is live.',
      _CheckoutState.failed => error ?? 'This delivery could not be started.',
      _ => error ?? 'Delivery has not started matching yet.',
    };
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
              healthy ? 'This delivery is saved and live.' : message,
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

class _VanguardCustomerPanel extends StatelessWidget {
  final _CircumColors colors;
  final Map<String, dynamic> data;

  const _VanguardCustomerPanel({
    required this.colors,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final protection =
        (data['vanguardProtection'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final collectionVerified = data['collectionPinVerified'] == true;
    final deliveryVerified = data['deliveryPinVerified'] == true;
    final collectionPin = '${protection['collectionPin'] ?? ''}'.trim();
    final deliveryPin = '${protection['deliveryPin'] ?? ''}'.trim();
    final collectionContact =
        (data['collectionContact'] as Map?)?.cast<String, dynamic>();
    final receiverDetails =
        (data['receiverDetails'] as Map?)?.cast<String, dynamic>();
    final collectionName =
        '${data['collectionContactName'] ?? collectionContact?['name'] ?? data['senderName'] ?? 'the sender or collection contact'}'
            .trim();
    final receiverName =
        '${data['receiverName'] ?? receiverDetails?['name'] ?? 'the receiver'}'
            .trim();
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security, color: colors.text),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Circum Vanguard Protection',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Vanguard Protection Activated\n\nThis item qualifies for enhanced delivery protection.\n\n✓ Collection PIN required\n✓ Receiver delivery PIN required\n✓ Chain of custody enabled\n✓ Vanguard verification active\n\nGive this collection PIN to the rider only when ${collectionName.isEmpty ? 'the sender or collection contact' : collectionName} hands over the sealed parcel.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _VanguardPinRow(
            colors: colors,
            label: 'Collection PIN',
            pin: collectionVerified ? 'Verified' : collectionPin,
            verified: collectionVerified,
          ),
          const SizedBox(height: 8),
          Text(
            'Give this receiver delivery PIN to the rider only when ${receiverName.isEmpty ? 'the receiver' : receiverName} physically receives the parcel.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _VanguardPinRow(
            colors: colors,
            label: 'Delivery PIN',
            pin: deliveryVerified ? 'Verified' : deliveryPin,
            verified: deliveryVerified,
          ),
        ],
      ),
    );
  }
}

class _VanguardPinRow extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String pin;
  final bool verified;

  const _VanguardPinRow({
    required this.colors,
    required this.label,
    required this.pin,
    required this.verified,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(
            verified ? Icons.verified : Icons.pin,
            color: verified ? colors.success : colors.text,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.mutedText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            pin.isEmpty ? 'Pending' : pin,
            style: TextStyle(
              color: colors.text,
              fontWeight: FontWeight.w900,
              fontFamily: pin.length == 6 ? 'monospace' : null,
              fontSize: pin.length == 6 ? 18 : 14,
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if ((message.label ?? '').isNotEmpty)
                                Text(
                                  message.label!,
                                  style: TextStyle(
                                    color: message.fromMe
                                        ? colors.inverseText
                                        : colors.mutedText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              Text(
                                message.text,
                                style: TextStyle(
                                  color: message.fromMe
                                      ? colors.inverseText
                                      : colors.text,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                message.time,
                                style: TextStyle(
                                  color: message.fromMe
                                      ? colors.inverseText
                                      : colors.mutedText,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
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

class _AddressField extends StatefulWidget {
  final _CircumColors colors;
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool pharmacyMode;
  final bool verified;
  final ValueChanged<_ValidatedAddress>? onSelected;
  final ValueChanged<String>? onEdited;
  final String verifiedMessage;

  const _AddressField({
    required this.colors,
    required this.icon,
    required this.label,
    required this.controller,
    this.pharmacyMode = false,
    this.verified = false,
    this.onSelected,
    this.onEdited,
    this.verifiedMessage = 'Verified address selected',
  });

  @override
  State<_AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<_AddressField> {
  List<_AddressSuggestion> _suggestions = const [];
  bool _selectingSuggestion = false;
  bool _loadingSuggestions = false;
  bool _resolvingSuggestion = false;
  String? _suggestionError;
  int _suggestionRequest = 0;
  late final String _placesSessionToken =
      '${DateTime.now().millisecondsSinceEpoch}-${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateSuggestions);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateSuggestions);
    super.dispose();
  }

  void _updateSuggestions() {
    if (_selectingSuggestion) return;
    final value = widget.controller.text.trim();
    final requestId = ++_suggestionRequest;
    if (value.length < 3) {
      if (mounted) setState(() => _suggestions = const []);
      return;
    }
    setState(() {
      _loadingSuggestions = true;
      _suggestionError = null;
    });
    _buildAddressSuggestions(value).then((next) {
      if (!mounted || requestId != _suggestionRequest) return;
      setState(() {
        _suggestions = next;
        _loadingSuggestions = false;
      });
    });
  }

  Future<List<_AddressSuggestion>> _buildAddressSuggestions(
      String value) async {
    if (value.length < 3) return const [];
    final clean = value.replaceAll(RegExp(r'\s+'), ' ');
    if (clean.toLowerCase().contains('united kingdom')) return const [];
    final popular = _popularPlaceSuggestions(clean);
    final google = await _googlePlacesAutocomplete(clean);
    final combined = <_AddressSuggestion>[
      ...popular,
      ...google.where(
        (suggestion) => !popular.any(
          (place) => _sameSuggestionText(
            place.displayAddress,
            suggestion.displayAddress,
          ),
        ),
      ),
    ];
    if (combined.isNotEmpty) return combined.take(8).toList(growable: false);
    return _localAddressSuggestions(clean);
  }

  List<_AddressSuggestion> _popularPlaceSuggestions(String clean) {
    final typed = _normalizePlaceQuery(clean);
    if (typed.length < 3) return const [];
    return _circumPopularPlaces
        .where((place) => place.matches(typed))
        .map(
          (place) => _AddressSuggestion(
            displayAddress: place.displayName,
            lat: place.lat,
            lng: place.lng,
            confidence: 0.98,
            provider: 'circum_popular_place',
            sourceInput: clean,
            searchText: place.formattedAddress,
            category: place.category,
          ),
        )
        .take(4)
        .toList(growable: false);
  }

  List<_AddressSuggestion> _localAddressSuggestions(String clean) {
    final typed = clean.toLowerCase();
    final seeded = _ukAddressSuggestionSeeds.entries
        .where((entry) {
          final lower = entry.key.toLowerCase();
          final words = typed.split(' ').where((word) => word.isNotEmpty);
          return words.every(lower.contains);
        })
        .map(
          (entry) => _AddressSuggestion(
            displayAddress: entry.key,
            lat: entry.value.$1,
            lng: entry.value.$2,
            confidence: 0.96,
            provider: 'circum_seeded_geocoder',
            sourceInput: clean,
          ),
        )
        .take(4)
        .toList(growable: false);
    if (seeded.isNotEmpty) return seeded;
    final coords = _postcodeCoordinatesForAddress(clean);
    if (coords == null) return const [];
    final city = _cityForAddress(clean);
    if (widget.pharmacyMode) {
      return [
        _AddressSuggestion(
          displayAddress: '$clean Pharmacy, High Street, $city, United Kingdom',
          lat: coords.$1,
          lng: coords.$2,
          confidence: 0.82,
          provider: 'circum_postcode_geocoder',
          sourceInput: clean,
        ),
        _AddressSuggestion(
          displayAddress: '$clean, Pharmacy Counter, $city, United Kingdom',
          lat: coords.$1,
          lng: coords.$2,
          confidence: 0.8,
          provider: 'circum_postcode_geocoder',
          sourceInput: clean,
        ),
      ];
    }
    return [
      _AddressSuggestion(
        displayAddress: '$clean, $city, United Kingdom',
        lat: coords.$1,
        lng: coords.$2,
        confidence: 0.82,
        provider: 'circum_postcode_geocoder',
        sourceInput: clean,
      ),
      _AddressSuggestion(
        displayAddress: '$clean, United Kingdom',
        lat: coords.$1,
        lng: coords.$2,
        confidence: 0.8,
        provider: 'circum_postcode_geocoder',
        sourceInput: clean,
      ),
    ];
  }

  Future<List<_AddressSuggestion>> _googlePlacesAutocomplete(
    String input,
  ) async {
    if (_googlePlacesApiKey.trim().isEmpty) return const [];
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {
          'input': input,
          'language': 'en',
          'components': 'country:uk',
          'key': _googlePlacesApiKey,
          'sessiontoken': _placesSessionToken,
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if ('${body['status']}' != 'OK') return const [];
      final predictions = body['predictions'] as List<dynamic>? ?? const [];
      return predictions
          .whereType<Map<String, dynamic>>()
          .where((prediction) =>
              prediction['place_id'] != null &&
              prediction['description'] != null)
          .map(
            (prediction) => _AddressSuggestion(
              displayAddress: '${prediction['description']}',
              confidence: 0.99,
              provider: 'google_places',
              sourceInput: input,
              placeId: '${prediction['place_id']}',
            ),
          )
          .take(6)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<_AddressSuggestion?> _googlePlaceDetails(
    _AddressSuggestion suggestion,
  ) async {
    final placeId = suggestion.placeId;
    if (placeId == null || _googlePlacesApiKey.trim().isEmpty) {
      return suggestion;
    }
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        {
          'place_id': placeId,
          'language': 'en',
          'fields':
              'formatted_address,address_components,geometry,place_id,name',
          'key': _googlePlacesApiKey,
          'sessiontoken': _placesSessionToken,
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if ('${body['status']}' != 'OK') return null;
      final result = body['result'] as Map<String, dynamic>;
      final geometry = result['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      final components = _googleAddressComponents(
        result['address_components'] as List<dynamic>? ?? const [],
      );
      return _AddressSuggestion(
        displayAddress: _cleanGoogleAddress(
            '${result['formatted_address'] ?? suggestion.displayAddress}'),
        lat: lat,
        lng: lng,
        confidence: 0.99,
        provider: 'google_places',
        sourceInput: suggestion.sourceInput,
        placeId: placeId,
        components: components,
      );
    } catch (_) {
      return null;
    }
  }

  Future<_AddressSuggestion?> _googleFindPlaceFromText(
    _AddressSuggestion suggestion,
  ) async {
    final query = suggestion.searchText ?? suggestion.displayAddress;
    if (_googlePlacesApiKey.trim().isEmpty) return null;
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/findplacefromtext/json',
        {
          'input': query,
          'inputtype': 'textquery',
          'language': 'en',
          'fields': 'formatted_address,geometry,place_id,name',
          'key': _googlePlacesApiKey,
          'locationbias': 'country:uk',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if ('${body['status']}' != 'OK') return null;
      final candidates = body['candidates'] as List<dynamic>? ?? const [];
      final typedCandidates = candidates.whereType<Map<String, dynamic>>();
      if (typedCandidates.isEmpty) return null;
      final result = typedCandidates.first;
      final geometry = result['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return _AddressSuggestion(
        displayAddress: _cleanGoogleAddress(
            '${result['formatted_address'] ?? suggestion.displayAddress}'),
        lat: lat,
        lng: lng,
        confidence: 0.98,
        provider: 'google_places',
        sourceInput: suggestion.sourceInput,
        placeId: '${result['place_id'] ?? ''}'.isEmpty
            ? null
            : '${result['place_id']}',
      );
    } catch (_) {
      return null;
    }
  }

  Future<_AddressSuggestion?> _resolvePopularPlace(
    _AddressSuggestion suggestion,
  ) async {
    final query = suggestion.searchText ?? suggestion.displayAddress;
    final predictions = await _googlePlacesAutocomplete(query);
    if (predictions.isNotEmpty) {
      final resolved = await _googlePlaceDetails(predictions.first);
      if (resolved != null) return resolved;
    }
    final found = await _googleFindPlaceFromText(suggestion);
    if (found != null) return found;
    if (suggestion.lat != null &&
        suggestion.lng != null &&
        _coordinatesAreUsable(suggestion.lat!, suggestion.lng!)) {
      return _AddressSuggestion(
        displayAddress: suggestion.searchText ?? suggestion.displayAddress,
        lat: suggestion.lat,
        lng: suggestion.lng,
        confidence: 0.97,
        provider: 'circum_popular_place',
        sourceInput: suggestion.sourceInput,
        placeId: suggestion.placeId,
        searchText: suggestion.searchText,
        category: suggestion.category,
      );
    }
    return null;
  }

  Future<void> _selectSuggestion(_AddressSuggestion suggestion) async {
    if (_resolvingSuggestion) return;
    setState(() {
      _resolvingSuggestion = true;
      _suggestionError = null;
    });
    final resolved = suggestion.isPopularPlace
        ? await _resolvePopularPlace(suggestion)
        : suggestion.provider == 'google_places'
            ? await _googlePlaceDetails(suggestion)
            : suggestion;
    if (!mounted) return;
    if (resolved == null || !resolved.toValidatedAddress().hasCoordinates) {
      setState(() {
        _resolvingSuggestion = false;
        _suggestionError =
            'Could not verify this place with Google Places. Try a different suggestion or type more detail.';
      });
      return;
    }
    _selectingSuggestion = true;
    widget.controller.text = resolved.displayAddress;
    widget.controller.selection = TextSelection.collapsed(
      offset: resolved.displayAddress.length,
    );
    _selectingSuggestion = false;
    widget.onSelected?.call(resolved.toValidatedAddress());
    setState(() {
      _suggestions = const [];
      _resolvingSuggestion = false;
      _suggestionError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: (value) {
            if (!_selectingSuggestion) widget.onEdited?.call(value);
          },
          style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            prefixIcon: Icon(widget.icon, color: colors.text, size: 18),
            labelText: widget.label,
            suffixIcon: widget.verified
                ? Icon(Icons.verified, color: colors.success, size: 18)
                : null,
            labelStyle: TextStyle(color: colors.mutedText),
            filled: true,
            fillColor: colors.field,
            border: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map(
                  (suggestion) => InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _resolvingSuggestion
                        ? null
                        : () => _selectSuggestion(suggestion),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 340),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: colors.field,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: suggestion.isPopularPlace
                              ? colors.adminAccent
                              : colors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            suggestion.isPopularPlace
                                ? Icons.star_rounded
                                : widget.pharmacyMode
                                    ? Icons.local_pharmacy
                                    : Icons.place_outlined,
                            color: colors.text,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  suggestion.displayAddress,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.text,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (suggestion.isPopularPlace)
                                  Text(
                                    _resolvingSuggestion
                                        ? 'Verifying with Google Places...'
                                        : 'Popular place',
                                    style: TextStyle(
                                      color: colors.mutedText,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        if (_loadingSuggestions || _resolvingSuggestion) ...[
          const SizedBox(height: 6),
          Text(
            _resolvingSuggestion
                ? 'Verifying selected place...'
                : 'Checking Google Places...',
            style: TextStyle(
              color: colors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (_suggestionError != null) ...[
          const SizedBox(height: 6),
          Text(
            _suggestionError!,
            style: TextStyle(
              color: colors.warning,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ],
        if (widget.verified) ...[
          const SizedBox(height: 6),
          Text(
            widget.verifiedMessage,
            style: TextStyle(
              color: colors.success,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}

class _PopularPlace {
  final String displayName;
  final List<String> searchAliases;
  final String formattedAddress;
  final double lat;
  final double lng;
  final String category;

  const _PopularPlace({
    required this.displayName,
    required this.searchAliases,
    required this.formattedAddress,
    required this.lat,
    required this.lng,
    required this.category,
  });

  bool matches(String normalizedInput) {
    return _normalizedSearchTerms.any(
      (term) =>
          term.contains(normalizedInput) || normalizedInput.contains(term),
    );
  }

  Iterable<String> get _normalizedSearchTerms sync* {
    yield _normalizePlaceQuery(displayName);
    yield _normalizePlaceQuery(formattedAddress);
    for (final alias in searchAliases) {
      yield _normalizePlaceQuery(alias);
    }
  }
}

const List<_PopularPlace> _circumPopularPlaces = [
  _PopularPlace(
    displayName: 'Heathrow Airport',
    searchAliases: ['heathrow', 'lhr', 'london heathrow'],
    formattedAddress: 'Heathrow Airport, Hounslow TW6, United Kingdom',
    lat: 51.4700,
    lng: -0.4543,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Heathrow Terminal 2 & 3',
    searchAliases: ['heathrow t2', 'heathrow t3', 'terminal 2', 'terminal 3'],
    formattedAddress:
        'Heathrow Terminal 2 & 3, Hounslow TW6 1EW, United Kingdom',
    lat: 51.4713,
    lng: -0.4524,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Heathrow Terminal 4',
    searchAliases: ['heathrow t4', 'terminal 4'],
    formattedAddress: 'Heathrow Terminal 4, Hounslow TW6 3XA, United Kingdom',
    lat: 51.4590,
    lng: -0.4464,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Heathrow Terminal 5',
    searchAliases: ['heathrow t5', 'terminal 5'],
    formattedAddress: 'Heathrow Terminal 5, Hounslow TW6 2GA, United Kingdom',
    lat: 51.4722,
    lng: -0.4870,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'King\'s Cross Station',
    searchAliases: ['kings cross', 'king cross', 'kings x', 'kx station'],
    formattedAddress:
        'King\'s Cross Station, Euston Road, London N1C 4TB, United Kingdom',
    lat: 51.5308,
    lng: -0.1238,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'St Pancras International',
    searchAliases: ['st pancras', 'saint pancras', 'st pancras station'],
    formattedAddress:
        'St Pancras International, Euston Road, London N1C 4QP, United Kingdom',
    lat: 51.5320,
    lng: -0.1252,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Euston Station',
    searchAliases: ['euston', 'london euston'],
    formattedAddress: 'Euston Station, London NW1 2RT, United Kingdom',
    lat: 51.5281,
    lng: -0.1339,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Paddington Station',
    searchAliases: ['paddington', 'london paddington'],
    formattedAddress:
        'Paddington Station, Praed Street, London W2 1HQ, United Kingdom',
    lat: 51.5154,
    lng: -0.1755,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Victoria Station',
    searchAliases: ['victoria', 'london victoria'],
    formattedAddress: 'Victoria Station, London SW1V 1JU, United Kingdom',
    lat: 51.4952,
    lng: -0.1441,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Waterloo Station',
    searchAliases: ['waterloo', 'london waterloo'],
    formattedAddress: 'Waterloo Station, London SE1 8SW, United Kingdom',
    lat: 51.5033,
    lng: -0.1147,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Liverpool Street Station',
    searchAliases: ['liverpool street', 'london liverpool street'],
    formattedAddress:
        'Liverpool Street Station, London EC2M 7QA, United Kingdom',
    lat: 51.5178,
    lng: -0.0817,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'London Bridge Station',
    searchAliases: ['london bridge'],
    formattedAddress: 'London Bridge Station, London SE1 9SP, United Kingdom',
    lat: 51.5050,
    lng: -0.0864,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Stratford Station',
    searchAliases: ['stratford', 'london stratford'],
    formattedAddress: 'Stratford Station, London E15 1AZ, United Kingdom',
    lat: 51.5413,
    lng: -0.0030,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Gatwick Airport',
    searchAliases: ['gatwick', 'lgw', 'london gatwick'],
    formattedAddress: 'Gatwick Airport, Horley RH6 0NP, United Kingdom',
    lat: 51.1537,
    lng: -0.1821,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Luton Airport',
    searchAliases: ['luton', 'ltn', 'london luton'],
    formattedAddress: 'London Luton Airport, Luton LU2 9LY, United Kingdom',
    lat: 51.8747,
    lng: -0.3683,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Stansted Airport',
    searchAliases: ['stansted', 'stn', 'london stansted'],
    formattedAddress:
        'London Stansted Airport, Stansted CM24 1QW, United Kingdom',
    lat: 51.8860,
    lng: 0.2389,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'London City Airport',
    searchAliases: ['city airport', 'lcy'],
    formattedAddress:
        'London City Airport, Hartmann Road, London E16 2PX, United Kingdom',
    lat: 51.5053,
    lng: 0.0553,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Westfield Stratford City',
    searchAliases: ['westfield stratford', 'stratford westfield', 'westfield'],
    formattedAddress:
        'Westfield Stratford City, Montfichet Road, London E20 1EJ, United Kingdom',
    lat: 51.5432,
    lng: -0.0076,
    category: 'shopping centre',
  ),
  _PopularPlace(
    displayName: 'Westfield London White City',
    searchAliases: ['westfield white city', 'westfield london', 'westfield'],
    formattedAddress:
        'Westfield London, Ariel Way, London W12 7GF, United Kingdom',
    lat: 51.5074,
    lng: -0.2217,
    category: 'shopping centre',
  ),
  _PopularPlace(
    displayName: 'Canary Wharf',
    searchAliases: ['canary wharf'],
    formattedAddress: 'Canary Wharf, London E14, United Kingdom',
    lat: 51.5054,
    lng: -0.0235,
    category: 'business district',
  ),
  _PopularPlace(
    displayName: 'Oxford Street',
    searchAliases: ['oxford street'],
    formattedAddress: 'Oxford Street, London W1, United Kingdom',
    lat: 51.5154,
    lng: -0.1410,
    category: 'shopping area',
  ),
  _PopularPlace(
    displayName: 'Selfridges London',
    searchAliases: ['selfridges', 'selfridges london'],
    formattedAddress:
        'Selfridges, 400 Oxford Street, London W1A 1AB, United Kingdom',
    lat: 51.5145,
    lng: -0.1527,
    category: 'retail',
  ),
  _PopularPlace(
    displayName: 'Harrods',
    searchAliases: ['harrods', 'harrods london'],
    formattedAddress:
        'Harrods, 87-135 Brompton Road, London SW1X 7XL, United Kingdom',
    lat: 51.4994,
    lng: -0.1633,
    category: 'retail',
  ),
  _PopularPlace(
    displayName: 'IKEA Wembley',
    searchAliases: ['ikea wembley', 'ikea'],
    formattedAddress:
        'IKEA Wembley, 2 Drury Way, Wembley HA9 0TH, United Kingdom',
    lat: 51.5587,
    lng: -0.2600,
    category: 'retail',
  ),
  _PopularPlace(
    displayName: 'IKEA Greenwich',
    searchAliases: ['ikea greenwich', 'ikea'],
    formattedAddress:
        'IKEA Greenwich, 55-57 Bugsby\'s Way, London SE10 0QJ, United Kingdom',
    lat: 51.4907,
    lng: 0.0127,
    category: 'retail',
  ),
  _PopularPlace(
    displayName: 'IKEA Croydon',
    searchAliases: ['ikea croydon', 'ikea'],
    formattedAddress:
        'IKEA Croydon, Valley Park, Croydon CR0 4UZ, United Kingdom',
    lat: 51.3751,
    lng: -0.1220,
    category: 'retail',
  ),
  _PopularPlace(
    displayName: 'The O2 Arena',
    searchAliases: ['o2', 'o2 arena', 'the o2'],
    formattedAddress:
        'The O2 Arena, Peninsula Square, London SE10 0DX, United Kingdom',
    lat: 51.5030,
    lng: 0.0032,
    category: 'landmark',
  ),
  _PopularPlace(
    displayName: 'ExCeL London',
    searchAliases: ['excel', 'excel london', 'exhibition centre london'],
    formattedAddress:
        'ExCeL London, Royal Victoria Dock, London E16 1XL, United Kingdom',
    lat: 51.5085,
    lng: 0.0290,
    category: 'landmark',
  ),
  _PopularPlace(
    displayName: 'Wembley Stadium',
    searchAliases: ['wembley', 'wembley arena'],
    formattedAddress: 'Wembley Stadium, Wembley HA9 0WS, United Kingdom',
    lat: 51.5560,
    lng: -0.2796,
    category: 'stadium',
  ),
  _PopularPlace(
    displayName: 'Emirates Stadium',
    searchAliases: ['emirates stadium', 'arsenal stadium'],
    formattedAddress:
        'Emirates Stadium, Hornsey Road, London N7 7AJ, United Kingdom',
    lat: 51.5549,
    lng: -0.1084,
    category: 'stadium',
  ),
  _PopularPlace(
    displayName: 'Stamford Bridge',
    searchAliases: ['stamford bridge', 'chelsea stadium'],
    formattedAddress:
        'Stamford Bridge, Fulham Road, London SW6 1HS, United Kingdom',
    lat: 51.4816,
    lng: -0.1910,
    category: 'stadium',
  ),
  _PopularPlace(
    displayName: 'Tottenham Hotspur Stadium',
    searchAliases: ['tottenham stadium', 'spurs stadium'],
    formattedAddress:
        'Tottenham Hotspur Stadium, 782 High Road, London N17 0BX, United Kingdom',
    lat: 51.6043,
    lng: -0.0664,
    category: 'stadium',
  ),
];

String _normalizePlaceQuery(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r"[\u2018\u2019']"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

bool _sameSuggestionText(String left, String right) {
  return _normalizePlaceQuery(left) == _normalizePlaceQuery(right);
}

const Map<String, (double, double)> _ukAddressSuggestionSeeds = {
  '10 Downing Street, Westminster, London SW1A 2AA, United Kingdom': (
    51.5034,
    -0.1276
  ),
  '221B Baker Street, Marylebone, London NW1 6XE, United Kingdom': (
    51.5237,
    -0.1585
  ),
  '1 Canada Square, Canary Wharf, London E14 5AB, United Kingdom': (
    51.5054,
    -0.0235
  ),
  'The Shard, 32 London Bridge Street, London SE1 9SG, United Kingdom': (
    51.5045,
    -0.0865
  ),
  'Westfield London, Ariel Way, London W12 7GF, United Kingdom': (
    51.5074,
    -0.2217
  ),
  'Selfridges, 400 Oxford Street, London W1A 1AB, United Kingdom': (
    51.5145,
    -0.1527
  ),
  'King\'s Cross Station, Euston Road, London N1C 4TB, United Kingdom': (
    51.5308,
    -0.1238
  ),
  'Manchester Piccadilly Station, Manchester M1 2BN, United Kingdom': (
    53.4774,
    -2.2309
  ),
  'Bullring, Birmingham B5 4BU, United Kingdom': (52.4776, -1.8936),
  'Cabot Circus, Bristol BS1 3BD, United Kingdom': (51.4581, -2.5837),
  'St James Quarter, Edinburgh EH1 3AD, United Kingdom': (55.9547, -3.1882),
  'Cardiff Central Station, Cardiff CF10 1EP, United Kingdom': (
    51.4755,
    -3.1780
  ),
  'Leeds Station, New Station Street, Leeds LS1 4DY, United Kingdom': (
    53.7947,
    -1.5479
  ),
  'Liverpool ONE, Liverpool L1 8JQ, United Kingdom': (53.4049, -2.9876),
  'Brighton Station, Queens Road, Brighton BN1 3XP, United Kingdom': (
    50.8290,
    -0.1413
  ),
  'Oxford City Centre, Oxford OX1 1BX, United Kingdom': (51.7520, -1.2577),
};

const Map<String, (double, double)> _ukCityCoordinates = {
  'London': (51.5074, -0.1278),
  'Croydon': (51.3762, -0.0982),
  'Manchester': (53.4808, -2.2426),
  'Birmingham': (52.4862, -1.8904),
  'Bristol': (51.4545, -2.5879),
  'Edinburgh': (55.9533, -3.1883),
  'Cardiff': (51.4816, -3.1791),
  'Leeds': (53.8008, -1.5491),
  'Liverpool': (53.4084, -2.9916),
  'Brighton': (50.8225, -0.1372),
  'Oxford': (51.7520, -1.2577),
};

const Map<String, (double, double)> _ukPostcodeCoordinates = {
  'SE1': (51.5033, -0.0890),
  'SE2': (51.4882, 0.1213),
  'SE3': (51.4685, 0.0196),
  'SE4': (51.4612, -0.0379),
  'SE5': (51.4736, -0.0920),
  'SE6': (51.4339, -0.0166),
  'SE7': (51.4869, 0.0312),
  'SE8': (51.4825, -0.0279),
  'SE9': (51.4504, 0.0513),
  'SE10': (51.4816, -0.0011),
  'SE11': (51.4901, -0.1101),
  'SE12': (51.4452, 0.0138),
  'SE13': (51.4589, -0.0117),
  'SE14': (51.4757, -0.0406),
  'SE15': (51.4735, -0.0671),
  'SE16': (51.4979, -0.0535),
  'SE17': (51.4880, -0.0923),
  'SE18': (51.4896, 0.0708),
  'SE19': (51.4195, -0.0868),
  'SE20': (51.4125, -0.0551),
  'SE21': (51.4402, -0.0886),
  'SE22': (51.4530, -0.0720),
  'SE23': (51.4416, -0.0497),
  'SE24': (51.4538, -0.1012),
  'SE25': (51.3995, -0.0751),
  'SE26': (51.4267, -0.0546),
  'SE27': (51.4306, -0.1033),
  'SE28': (51.5029, 0.1042),
  'CR0': (51.3762, -0.0982),
  'CR2': (51.3452, -0.0920),
  'CR3': (51.2853, -0.0801),
  'CR4': (51.4035, -0.1604),
  'CR5': (51.3093, -0.1392),
  'CR6': (51.3095, -0.0579),
  'CR7': (51.3987, -0.1071),
  'CR8': (51.3373, -0.1151),
  'E': (51.5326, 0.0553),
  'EC': (51.5155, -0.0922),
  'N': (51.5680, -0.1080),
  'NW': (51.5480, -0.1980),
  'SW': (51.4450, -0.1700),
  'W': (51.5120, -0.2200),
  'WC': (51.5190, -0.1200),
  'BR': (51.4060, 0.0150),
  'DA': (51.4470, 0.2190),
  'EN': (51.6520, -0.0810),
  'HA': (51.5810, -0.3370),
  'IG': (51.5590, 0.0750),
  'KT': (51.3920, -0.3000),
  'RM': (51.5600, 0.1830),
  'SM': (51.3650, -0.1950),
  'TW': (51.4490, -0.4100),
  'UB': (51.5200, -0.4100),
  'WD': (51.6600, -0.3900),
  'M': (53.4808, -2.2426),
  'B': (52.4862, -1.8904),
  'BS': (51.4545, -2.5879),
  'EH': (55.9533, -3.1883),
  'CF': (51.4816, -3.1791),
  'LS': (53.8008, -1.5491),
  'L': (53.4084, -2.9916),
  'BN': (50.8225, -0.1372),
  'OX': (51.7520, -1.2577),
};

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

const _scheduleDateOptions = [
  'Today',
  'Tomorrow',
  'Next 2 days',
  'This week',
  'Choose later',
];

const _pickupWindowOptions = [
  'ASAP',
  'Morning',
  'Afternoon',
  'Evening',
  'Flexible',
];

const _deliveryWindowOptions = [
  'Same day',
  'Morning',
  'Afternoon',
  'Evening',
  'Flexible',
];

class _CompactSelectBox extends StatefulWidget {
  final _CircumColors colors;
  final TextEditingController controller;
  final String label;
  final List<String> options;

  const _CompactSelectBox({
    required this.colors,
    required this.controller,
    required this.label,
    required this.options,
  });

  @override
  State<_CompactSelectBox> createState() => _CompactSelectBoxState();
}

class _CompactSelectBoxState extends State<_CompactSelectBox> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    super.dispose();
  }

  void _handleControllerChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final selected = widget.options.contains(widget.controller.text)
        ? widget.controller.text
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 10, 5),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(color: colors.mutedText, fontSize: 11),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected,
              isExpanded: true,
              isDense: true,
              hint: Text(
                'Select',
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: Icon(Icons.expand_more, color: colors.text, size: 18),
              dropdownColor: colors.panel,
              style: TextStyle(
                color: colors.text,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              items: widget.options
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(
                        option,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                widget.controller.text = value;
              },
            ),
          ),
        ],
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
    const serviceCopy = {
      'Economy':
          'Cheapest option. Slower matching. Best when the parcel is not urgent.',
      'Standard':
          'Balanced price. Normal rider broadcast. Best for everyday deliveries.',
      'Express':
          'Priority matching. Faster pickup. Best for urgent deliveries.',
    };
    return Column(
      children: ['Economy', 'Standard', 'Express'].map((speed) {
        final active = selected == speed;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onChanged(speed),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: active ? colors.text : colors.field,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    active
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: active ? colors.inverseText : colors.text,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          speed,
                          style: TextStyle(
                            color: active ? colors.inverseText : colors.text,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          serviceCopy[speed]!,
                          style: TextStyle(
                            color: active
                                ? colors.inverseText.withOpacity(0.76)
                                : colors.mutedText,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
    final orderRank = _circumOrderRankForPerformance(performance);
    final rating = performance.averageRating <= 0
        ? 'New'
        : performance.averageRating.toStringAsFixed(1);
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
                child: _RiderRankPresentation(
                  colors: colors,
                  rank: orderRank.label,
                  rankTitle: orderRank.title,
                  name: profile.fullName,
                  rating: rating,
                  tripCount: performance.completedTrips,
                  vehiclePlate: profile.vehicle.plateNumber,
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

class _RiderRankPresentation extends StatelessWidget {
  final _CircumColors colors;
  final String rank;
  final String rankTitle;
  final String name;
  final String rating;
  final int tripCount;
  final String vehiclePlate;

  const _RiderRankPresentation({
    required this.colors,
    required this.rank,
    required this.rankTitle,
    required this.name,
    required this.rating,
    required this.tripCount,
    required this.vehiclePlate,
  });

  @override
  Widget build(BuildContext context) {
    final plate = vehiclePlate.trim().isEmpty ? 'Plate pending' : vehiclePlate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: _spectrumGradient),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              '◈ ${rank.toUpperCase()}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.text,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$rankTitle\n$tripCount Deliveries Completed\n$rating Rating\n$plate',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.mutedText,
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
  final double selectedTipAmount;
  final bool submitting;
  final bool submitted;
  final String? message;
  final ValueChanged<int> onRatingChanged;
  final ValueChanged<String> onTag;
  final ValueChanged<double> onTipChanged;
  final VoidCallback onSubmit;

  const _DriverRatingPrompt({
    required this.colors,
    required this.driver,
    required this.stars,
    required this.feedback,
    required this.selectedTags,
    required this.selectedTipAmount,
    required this.submitting,
    required this.submitted,
    required this.message,
    required this.onRatingChanged,
    required this.onTag,
    required this.onTipChanged,
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
          const SizedBox(height: 12),
          Text(
            'Add a tip',
            style: TextStyle(
              color: colors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [0.0, 2.0, 5.0, 10.0].map((amount) {
              final selected = selectedTipAmount == amount;
              return ChoiceChip(
                selected: selected,
                onSelected: submitted ? null : (_) => onTipChanged(amount),
                label: Text(
                    amount == 0 ? 'No tip' : '+£${amount.toStringAsFixed(0)}'),
                selectedColor: colors.text,
                labelStyle: TextStyle(
                  color: selected ? colors.inverseText : colors.text,
                  fontWeight: FontWeight.w900,
                ),
                backgroundColor: colors.field,
                shape: StadiumBorder(side: BorderSide(color: colors.border)),
              );
            }).toList(),
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

  const _GlassPanel({super.key, required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.panel.withOpacity(colors.dark ? 0.92 : 0.96),
            colors.adminAccent.withOpacity(colors.dark ? 0.10 : 0.06),
            colors.panel.withOpacity(colors.dark ? 0.86 : 0.94),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.adminAccent.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(colors.dark ? 0.18 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: colors.adminGlow.withOpacity(colors.dark ? 0.12 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
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
  Color get adminChrome =>
      dark ? const Color(0xff07111f) : const Color(0xfff8fbff);
  Color get adminAccent =>
      dark ? const Color(0xff38bdf8) : const Color(0xff2563eb);
  Color get adminGlow =>
      dark ? const Color(0xffa855f7) : const Color(0xff38bdf8);
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
  final String? label;

  const _ChatMessage({
    required this.fromMe,
    required this.text,
    required this.time,
    this.label,
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
