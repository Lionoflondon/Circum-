import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:circum/app/admin/delivery/proof_of_delivery.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_operations.dart';

enum AdminModule {
  dashboard('Dashboard', Icons.dashboard_rounded),
  visitorAnalytics('Visitor analytics', Icons.query_stats_rounded),
  deliveries('Deliveries', Icons.local_shipping_rounded),
  discrepancyReview('Parcel Intelligence', Icons.fact_check_rounded),
  irisRepository('Item Library', Icons.inventory_2_rounded),
  irisCandidates('Parcel Reviews', Icons.psychology_alt_rounded),
  governance('Operations Centre', Icons.health_and_safety_rounded),
  recognition('Recognition', Icons.workspace_premium_rounded),
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
    final result = await _functions.httpsCallable('adminResolveAccess').call();
    final data = Map<String, dynamic>.from(result.data as Map? ?? {});
    final serverRoles = ((data['roles'] as List?) ?? const []).map(
      (role) => '$role',
    );
    return {...claimRoles, ...serverRoles}.toList();
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
    await _functions
        .httpsCallable('adminRecordAuditEntry')
        .call(entry.toJson());
  }

  String _idFor(Map<String, dynamic> record) {
    return '${record['id'] ?? record['requestId'] ?? record['uid'] ?? ''}'
        .trim();
  }

  Future<void> _performGovernanceAction(
    Map<String, dynamic> record,
    String action, {
    String? reason,
  }) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot perform recovery actions.');
      return;
    }
    final id = _idFor(record);
    if (id.isEmpty) return;
    try {
      await _functions.httpsCallable('adminGovernanceAction').call({
        'action': action,
        'targetId': id,
        'userId': record['userId'] ?? record['senderId'] ?? record['uid'],
        'riderId': record['riderId'] ?? record['driverId'] ?? record['uid'],
        'deliveryId': record['deliveryId'] ?? record['requestId'] ?? id,
        'businessId': record['businessId'] ?? record['accountId'] ?? id,
        'healthPlusId': record['healthPlusId'] ?? record['pickupId'] ?? id,
        'reason': reason ?? 'Recovery requested from Admin Operations Centre.',
      });
      setState(() => _message = 'Governance action queued for $id.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message =
            error.message ?? 'Could not complete the governance action.',
      );
    }
  }

  Future<Map<String, dynamic>> _callRiderAuthority(
    Map<String, Object?> payload,
  ) async {
    final result =
        await _functions.httpsCallable('adminReviewRider').call(payload);
    return Map<String, dynamic>.from(result.data as Map? ?? {});
  }

  Future<void> _duplicateDelivery(Map<String, dynamic> delivery) async {
    if (!_can(AdminPermission.duplicateDeliveries)) {
      setState(() => _message = 'Your role cannot duplicate deliveries.');
      return;
    }
    final newId = 'CIR-ADM-${DateTime.now().millisecondsSinceEpoch}';
    await _functions.httpsCallable('adminDuplicateDelivery').call({
      'deliveryId': _idFor(delivery),
      'newId': newId,
      'reason': 'Admin duplicated delivery from operations console',
    });
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

  Future<String?> _generateRiderStripeOnboardingLink(
    Map<String, dynamic> rider, {
    bool copy = false,
    bool send = false,
  }) async {
    if (!_can(AdminPermission.approveDrivers)) {
      setState(() => _message = 'Your role cannot manage Rider payout setup.');
      return null;
    }
    final riderId = _riderId(rider);
    if (riderId.isEmpty) return null;
    try {
      final result = await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('refreshStripeOnboardingLink').call({'riderId': riderId});
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      final url = '${data['url'] ?? ''}'.trim();
      if (url.isEmpty) {
        setState(() => _message = 'Stripe onboarding link was not returned.');
        return null;
      }
      if (copy) await Clipboard.setData(ClipboardData(text: url));
      if (send) {
        final conversation = await _functions
            .httpsCallable('startAdminConversation')
            .call({'participantId': riderId, 'participantRole': 'rider'});
        final conversationData = Map<String, dynamic>.from(
          conversation.data as Map? ?? {},
        );
        final chatId =
            '${conversationData['chatId'] ?? conversationData['conversationId'] ?? conversationData['id'] ?? ''}'
                .trim();
        if (chatId.isNotEmpty) {
          await _functions.httpsCallable('sendCircumMessage').call({
            'chatId': chatId,
            'message': 'Please complete your secure payout setup here: $url',
            'messageType': 'text',
            'clientMessageId': const Uuid().v4(),
          });
        }
      }
      await _writeRiderAdminEvent(
        riderId,
        send
            ? 'stripe_onboarding_link_sent'
            : copy
                ? 'stripe_onboarding_link_copied'
                : 'stripe_onboarding_link_generated',
        previousStatus:
            '${rider['stripeConnectStatus'] ?? rider['stripeStatus'] ?? ''}',
        newStatus: 'onboarding_link_ready',
        note: 'Fresh Stripe Express onboarding link generated by Admin.',
      );
      setState(
        () => _message = send
            ? 'Payout setup link sent to Rider.'
            : copy
                ? 'Payout setup link copied.'
                : 'Fresh payout setup link generated.',
      );
      await _loadAdminData();
      return url;
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Could not prepare link.');
    } catch (_) {
      setState(() => _message = 'Could not prepare payout setup link.');
    }
    return null;
  }

  Future<void> _openRiderStripeDashboard(Map<String, dynamic> rider) async {
    final accountId =
        '${rider['stripeConnectAccountId'] ?? rider['stripeAccountId'] ?? ''}'
            .trim();
    if (accountId.isEmpty) {
      setState(() => _message = 'No Stripe account is connected.');
      return;
    }
    final opened = await launchUrl(
      Uri.parse('https://dashboard.stripe.com/connect/accounts/$accountId'),
      mode: LaunchMode.externalApplication,
    );
    await _writeRiderAdminEvent(
      _riderId(rider),
      'stripe_dashboard_opened',
      previousStatus: accountId,
      note: opened
          ? 'Stripe Dashboard opened for investigation.'
          : 'Stripe Dashboard could not be opened.',
    );
  }

  Future<void> _markRiderStripeInvestigation(
    Map<String, dynamic> rider,
    String action,
  ) async {
    if (!_can(AdminPermission.approveDrivers)) {
      setState(() => _message = 'Your role cannot manage Rider payout setup.');
      return;
    }
    final riderId = _riderId(rider);
    if (riderId.isEmpty) return;
    await _writeRiderAdminEvent(
      riderId,
      action,
      previousStatus:
          '${rider['stripeConnectStatus'] ?? rider['stripeStatus'] ?? ''}',
      newStatus: 'manual_review',
      note: action == 'stripe_support_escalated'
          ? 'Escalated to Stripe support.'
          : 'Marked for manual payout setup investigation.',
    );
    setState(
      () => _message = action == 'stripe_support_escalated'
          ? 'Stripe support escalation recorded.'
          : 'Manual investigation recorded.',
    );
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
    await _functions.httpsCallable('adminRecordRiderEvent').call({
      'riderId': riderId,
      'action': action,
      'previousStatus': previousStatus,
      'newStatus': newStatus,
      'note': note,
      'reason': note ?? 'Rider Admin event recorded',
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
    await _functions.httpsCallable('adminUpdateDeliveryOperation').call({
      'deliveryId': id,
      'status': status,
      'reason': 'Updated from Circum Admin Delivery Operations',
    });
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
    await _functions.httpsCallable('adminArchiveDelivery').call({
      'deliveryId': id,
      'reason': 'Delivery archived from Admin operations',
    });
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
    await _functions.httpsCallable('adminUpdateIrisReview').call({
      'deliveryId': id,
      'status': status,
      'reason': 'Updated from Circum Admin Parcel Intelligence',
    });
    setState(() => _message = 'IRIS review for $id marked $status.');
    await _loadAdminData();
  }

  Future<void> _adjudicateIrisReferral(
    Map<String, dynamic> delivery,
    String decision,
  ) async {
    if (!_can(AdminPermission.editDeliveries)) {
      setState(() => _message = 'Your role cannot manage IRIS referrals.');
      return;
    }
    final requestId =
        '${delivery['requestId'] ?? delivery['id'] ?? delivery['deliveryId'] ?? ''}'
            .trim();
    if (requestId.isEmpty) return;
    final reason = await _promptAdminReason(
      'Resolve IRIS referral',
      'Record why this parcel review should be marked ${_irisDecisionText(decision)}.',
    );
    if (reason == null) return;
    try {
      await _functions.httpsCallable('adjudicateIris').call({
        'requestId': requestId,
        'decision': decision,
        'finalCategory': delivery['category'] ?? delivery['irisCategory'],
        'finalWeightBand': delivery['weightBand'] ??
            delivery['irisWeightBand'] ??
            delivery['declaredWeight'],
        'reason': reason,
        if (decision == 'referral_required') 'referralType': 'specialist',
        if (decision == 'allowed') 'serviceabilityStatus': 'serviceable',
      });
      setState(
        () => _message =
            'IRIS referral $requestId marked ${_irisDecisionText(decision)}.',
      );
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'IRIS adjudication failed.');
    }
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
    await _functions.httpsCallable('adminUpdateSenderAccountStatus').call({
      'userId': id,
      'status': status,
      'reason': 'Sender account status updated from Admin',
    });
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
    await _functions.httpsCallable('adminUpdateBusinessAccountStatus').call({
      'businessId': id,
      'status': status,
      'reason': 'Business account status updated from Admin',
    });
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
    await _functions.httpsCallable('adminUpdateBusinessOperation').call({
      'businessId': id,
      'status': status,
      'reason': 'Updated from Circum Admin Business Operations',
    });
    setState(() => _message = 'Business operation $id marked $status.');
    await _loadAdminData();
  }

  Future<void> _createBusinessInvoice() async {
    if (!_can(AdminPermission.manageFinance)) {
      setState(() => _message = 'Your role cannot create Business invoices.');
      return;
    }
    if (_data.businessAccounts.isEmpty) {
      setState(() => _message = 'No Business accounts are available.');
      return;
    }
    var selectedBusinessId = _businessIdForAdmin(_data.businessAccounts.first);
    final description = TextEditingController(text: 'Business services');
    final amount = TextEditingController();
    final dueDate = TextEditingController();
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Generate Business invoice'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedBusinessId,
                  decoration: const InputDecoration(labelText: 'Business'),
                  items: [
                    for (final account in _data.businessAccounts)
                      DropdownMenuItem(
                        value: _businessIdForAdmin(account),
                        child: Text(
                          '${account['businessName'] ?? account['companyName'] ?? _businessIdForAdmin(account)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => selectedBusinessId = value ?? selectedBusinessId,
                  ),
                ),
                TextField(
                  controller: amount,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: dueDate,
                  decoration: const InputDecoration(
                    labelText: 'Due date (optional)',
                  ),
                ),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Generate invoice'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final result =
          await _functions.httpsCallable('adminCreateBusinessInvoice').call({
        'businessId': selectedBusinessId,
        'amount': double.tryParse(amount.text.trim()) ?? 0,
        'description': description.text.trim(),
        'dueDate': dueDate.text.trim(),
        'reason': reason.text.trim(),
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      setState(
        () => _message =
            'Business invoice ${data['invoiceNumber'] ?? data['invoiceId']} generated.',
      );
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Could not generate invoice.');
    } catch (_) {
      setState(() => _message = 'Could not generate invoice.');
    }
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
    final index =
        member['memberIndex'] is int ? member['memberIndex'] as int : -1;
    if (businessId.isEmpty || index < 0) return;
    await _functions.httpsCallable('adminUpdateBusinessMember').call({
      'businessId': businessId,
      'memberIndex': index,
      'role': role,
      'reason': 'Business member role updated from Admin',
    });
    setState(() => _message = 'Business member role updated to $role.');
    await _loadAdminData();
  }

  Future<void> _removeBusinessMember(Map<String, dynamic> member) async {
    if (!_can(AdminPermission.editCustomers)) {
      setState(() => _message = 'Your role cannot manage Business members.');
      return;
    }
    final businessId = '${member['businessId'] ?? member['id'] ?? ''}'.trim();
    final index =
        member['memberIndex'] is int ? member['memberIndex'] as int : -1;
    if (businessId.isEmpty || index < 0) return;
    await _functions.httpsCallable('adminUpdateBusinessMember').call({
      'businessId': businessId,
      'memberIndex': index,
      'remove': true,
      'reason': 'Business member removed from Admin',
    });
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
      AdminAccountTools.mergeReviewRecord(
        primaryAccountId: id,
        duplicateAccountId: duplicateId,
        requestedBy: _user?.email ?? _user?.uid ?? 'admin',
        createdAt: FieldValue.serverTimestamp(),
      );
      await _functions.httpsCallable('adminRequestAccountMergeReview').call({
        'primaryAccountId': id,
        'duplicateAccountId': duplicateId,
        'accountType': _selectedAccountType,
        'reason': 'Duplicate account merge review requested from Admin',
      });
      setState(() => _message = 'Merge review requested for $duplicateId.');
    } on ArgumentError catch (error) {
      setState(() => _message = error.message);
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Merge review failed.');
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
        'resolutionNote':
            status == 'resolved' ? 'Resolved from Circum Admin' : null,
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
      AdminGiftTools.workflowPatch(
        status: status,
        updatedBy: _user?.email ?? _user?.uid ?? 'admin',
        updatedAt: FieldValue.serverTimestamp(),
        reason: 'Gift workflow action confirmed from Admin',
      );
      await _functions.httpsCallable('adminUpdateGiftWorkflow').call({
        'giftId': id,
        'collection': '${gift['_collection'] ?? 'giftOrders'}',
        'status': status,
        'reason': 'Gift workflow action confirmed from Admin',
      });
      setState(() => _message = 'Gift $id updated to $status.');
      await _loadAdminData();
    } on ArgumentError catch (error) {
      setState(() => _message = error.message);
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Gift workflow failed.');
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
    try {
      await _functions
          .httpsCallable('adminUpdateGiftCampaignParticipant')
          .call({
        'participantId': id,
        'status': status,
        'reason': 'Gift campaign participant reviewed from Admin',
      });
      setState(() => _message = 'Gift campaign participant $id updated.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Campaign action failed.');
    }
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
    try {
      await _functions.httpsCallable('adminSaveGiftBrandPartner').call({
        'brandId': id,
        'partnerName': brand['partnerName'] ?? brand['brandName'] ?? id,
        'brandName': brand['brandName'] ?? brand['partnerName'] ?? id,
        'status': status,
        'reason': 'Gift Brand Partner workflow action from Admin',
      });
      setState(() => _message = 'Gift Brand Partner $id marked $status.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message = error.message ?? 'Brand Partner action failed.',
      );
    }
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
                    items: const [
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
    try {
      await _functions.httpsCallable('adminSaveGiftBrandPartner').call({
        'brandId': id,
        'partnerName': patch['partnerName'],
        'brandName': patch['brandName'],
        'category': patch['category'],
        'contactName': patch['contactName'],
        'contactEmail': patch['contactEmail'],
        'phone': patch['phone'],
        'website': patch['website'],
        'notes': patch['internalNotes'],
        'approvedFor': patch['approvedFor'] ?? const [],
        'status': status,
        'reason': 'Brand Partner profile saved from Admin',
      });
      setState(() => _message = 'Gift Brand Partner $id saved.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Brand Partner save failed.');
    }
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
    try {
      await _functions.httpsCallable('adminSuggestGiftCampaignMatch').call({
        'participantId': id,
        'suggestedParticipantId': _idFor(best),
        'suggestedMatchScore': bestScore,
        'suggestedMatchReason': bestReason,
      });
      setState(() => _message = 'Campaign match suggestion saved.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Match suggestion failed.');
    }
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
    try {
      await _functions.httpsCallable('adminApproveGiftCampaignMatch').call({
        'participantId': id,
        'reason': 'Campaign Matching approval confirmed from Admin',
      });
      setState(
        () => _message = 'Campaign match approved and draft gifts created.',
      );
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Campaign approval failed.');
    }
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
    try {
      await _functions.httpsCallable('adminBulkGiftCampaignAction').call({
        'participantIds':
            selected.map(_idFor).where((id) => id.isNotEmpty).toList(),
        'action': action,
        'reason': 'Bulk Campaign Matching workflow confirmed from Admin',
      });
      setState(() => _message = 'Campaign matching bulk $action complete.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message = error.message ?? 'Bulk campaign action failed.',
      );
    }
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
          title: Text('Gift Request Editor · $id'),
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
                      labelText: 'Procurement item',
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
                      labelText: 'Procurement notes',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: irisAccepted,
                    decoration: const InputDecoration(
                      labelText: 'Approved IRIS gift ideas',
                    ),
                  ),
                  TextField(
                    controller: irisRejected,
                    decoration: const InputDecoration(
                      labelText: 'Rejected IRIS gift ideas',
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
                    items: const [
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
                    items: const [
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
      'giftStoryCustomAudioUrl':
          storyAudio.text.trim().isEmpty ? null : storyAudio.text.trim(),
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
    try {
      await _functions.httpsCallable('adminSaveGiftRequestEditor').call({
        'giftId': id,
        'collection': collection,
        'patch': patch,
        'reason': 'Historical Gift Request editor workflow restored',
      });
      setState(() => _message = 'Gift Request $id saved.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Gift Request save failed.');
    }
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
          reason: 'Gift Story action submitted through Operations Centre',
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
      try {
        await _functions.httpsCallable('adminUpdateIrisRepositoryRecord').call({
          'recordId': id,
          'collection': collection,
          'action': action,
          'patch': patch,
          'reason': 'IRIS canonical editor confirmed from Admin',
        });
        setState(() => _message = 'IRIS repository record $targetId saved.');
        await _loadAdminData();
      } on FirebaseFunctionsException catch (error) {
        setState(
          () => _message = error.message ?? 'IRIS repository save failed.',
        );
      }
      return;
    }
    try {
      await _functions.httpsCallable('adminUpdateIrisRepositoryRecord').call({
        'recordId': id,
        'collection': collection,
        'action': action,
        'reason': 'IRIS repository governance action confirmed from Admin',
      });
      setState(() => _message = 'IRIS repository record $id marked $action.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message = error.message ?? 'IRIS repository action failed.',
      );
    }
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
      try {
        await _functions
            .httpsCallable('adminUpdateIrisCandidateWorkflow')
            .call({
          'candidateId': id,
          'collection': collection,
          'action': action,
          'reason': 'Candidate promoted to Canonical Repository from Admin',
        });
        setState(() => _message = 'IRIS candidate promoted to $canonicalId.');
        await _loadAdminData();
      } on FirebaseFunctionsException catch (error) {
        setState(
          () => _message = error.message ?? 'IRIS candidate promotion failed.',
        );
      }
      return;
    }
    try {
      await _functions.httpsCallable('adminUpdateIrisCandidateWorkflow').call({
        'candidateId': id,
        'collection': collection,
        'action': action,
        'reason': 'IRIS candidate workflow confirmed from Admin',
      });
      setState(() => _message = 'IRIS candidate $id marked $action.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message = error.message ?? 'IRIS candidate action failed.',
      );
    }
  }

  Future<void> _updateGiftWorkspace(
    Map<String, dynamic> gift,
    String action,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage gift workspaces.');
      return;
    }
    final id = _idFor(gift);
    if (id.isEmpty) return;
    final collection = '${gift['_collection'] ?? 'giftRequests'}';
    try {
      await _functions.httpsCallable('adminUpdateGiftWorkspace').call({
        'giftId': id,
        'collection': collection,
        'action': action,
        'reason': 'Gift Team workspace action confirmed from Admin',
      });
      setState(() => _message = 'Gift workspace $id marked $action.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message = error.message ?? 'Gift workspace action failed.',
      );
    }
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
          'privacy': gift['giftStorySharePrivacy'] ??
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
      await _functions.httpsCallable('adminUpdatePlatformRecord').call({
        'recordId': id,
        'collection': collection,
        'status': status,
        'reason': 'Platform operation confirmed from Admin',
      });
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
        'announcementId': const Uuid().v4(),
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
    await _functions.httpsCallable('adminUpdateHealthPlusPickup').call({
      'pickupId': id,
      'status': status,
      'reason': 'Updated from Circum Admin Health+ Operations',
    });
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
    await _functions.httpsCallable('adminUpdateHealthPlusSchedule').call({
      'scheduleId': id,
      'status': status,
      'reason': 'Health+ recurring schedule reviewed from Admin',
    });
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
    await _functions.httpsCallable('adminUpdateHealthPlusProfile').call({
      'profileId': id,
      'status': status,
      'reason': 'Health+ profile reviewed from Admin',
    });
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
    await _functions.httpsCallable('adminUpdateFinanceWorkflow').call({
      'paymentId': id,
      'status': status,
      'reason': 'Finance workflow updated from Admin',
    });
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
          reason: 'Roth issued through Operations Centre',
        ),
      );
      setState(() => _message = 'Roth issue submitted for $recipient.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Roth issue failed.');
    }
  }

  Future<void> _issueManualRothCredit({
    required String recipient,
    required double amount,
    required String reason,
    required String walletTarget,
  }) async {
    if (!_can(AdminPermission.manageFinance)) {
      setState(() => _message = 'Your role cannot issue Roth.');
      return;
    }
    final cleanRecipient = recipient.trim();
    final cleanReason = reason.trim();
    if (cleanRecipient.isEmpty || amount <= 0 || cleanReason.isEmpty) {
      setState(() => _message = 'Recipient, amount and reason are required.');
      return;
    }
    try {
      final idempotencyKey =
          'manual_${_user?.uid ?? _user?.email}_${DateTime.now().microsecondsSinceEpoch}';
      await _functions.httpsCallable('issueRothToWallets').call({
        cleanRecipient.contains('@') ? 'recipientEmail' : 'recipientUid':
            cleanRecipient,
        'walletTarget': walletTarget,
        'amount': amount,
        'reason': cleanReason,
        'idempotencyKey': idempotencyKey,
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'manual_roth_credit_requested',
          recordType: 'walletOperations',
          recordId: cleanRecipient,
          newValue: {
            'recipient': cleanRecipient,
            'amount': amount,
            'walletTarget': walletTarget,
          },
          reason: cleanReason,
        ),
      );
      setState(() => _message = 'Manual Roth credit submitted.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Roth issue failed.');
    }
  }

  Future<void> _manageRecognition(
    Map<String, dynamic> record,
    String action,
    String type,
  ) async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot manage recognition.');
      return;
    }
    final subject = _recognitionSubject(record);
    if (subject.id.isEmpty) {
      setState(() => _message = 'Recognition needs a selected user.');
      return;
    }
    final reason = await _promptAdminReason(
      action == 'grant' ? 'Grant recognition' : 'Revoke recognition',
      '${action == 'grant' ? 'Grant' : 'Revoke'} ${_recognitionTypeLabel(type)} for ${subject.label}.',
    );
    if (reason == null) return;
    try {
      await _functions
          .httpsCallable(
        action == 'grant' ? 'grantRecognition' : 'revokeRecognition',
      )
          .call({
        'type': type,
        'subjectCollection': subject.collection,
        'subjectId': subject.id,
        'reason': reason,
      });
      await _writeAudit(
        AdminAuditEntry(
          adminUserId: _user?.uid ?? 'unknown-admin',
          actionType: 'recognition_${action}_requested',
          recordType: subject.collection,
          recordId: subject.id,
          newValue: {'type': type, 'subject': subject.label},
          reason: reason,
        ),
      );
      setState(
        () => _message =
            '${_recognitionTypeLabel(type)} ${action == 'grant' ? 'granted' : 'revoked'} for ${subject.label}.',
      );
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Recognition update failed.');
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
          reason: 'Wallet freeze status updated through Operations Centre',
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
    final selectedRole = role ??
        AdminRole.fromString('${existing?['role'] ?? ''}') ??
        AdminRole.operationsAdmin;
    final documentId = '${existing?['id'] ?? normalizedEmail}'.trim();
    final note = _adminInviteNote.text.trim();
    await _functions.httpsCallable('adminSaveAdminUser').call({
      'documentId': documentId,
      'email': normalizedEmail,
      'role': selectedRole.value,
      'status': status,
      'adminNote': note,
      'reason': existing == null
          ? 'Admin access invitation created'
          : 'Admin access record updated',
    });
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
        'clientMessageId': const Uuid().v4(),
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
        'userId': ticket['userId'] ?? ticket['senderId'] ?? ticket['riderId'],
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
      final result =
          await _functions.httpsCallable('startAdminConversation').call({
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
    try {
      await _functions.httpsCallable('adminAddAdminNote').call({
        'recordType': recordType,
        'recordId': recordId,
        'body': body,
        'pinned': pinned,
        'reason': 'Internal Admin note added',
      });
      setState(() => _message = 'Admin note added.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Admin note failed.');
    }
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

  Future<String?> _promptAdminReason(String title, String body) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(body),
              const SizedBox(height: 14),
              TextField(
                controller: reason,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
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
    final value = reason.text.trim();
    reason.dispose();
    if (confirmed != true || value.isEmpty) return null;
    return value;
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
    final pointDelta =
        needsPoints ? (int.tryParse(points.text.trim()) ?? 0).abs() : 0;
    points.dispose();
    reason.dispose();
    if (confirmed != true) return;
    if (needsPoints && pointDelta == 0) {
      setState(() => _message = 'Enter a non-zero trust point amount.');
      return;
    }
    try {
      final result =
          await _functions.httpsCallable('adminUpdateSenderTrust').call({
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
    try {
      await _functions.httpsCallable('adminResolveMessageReport').call({
        'reportId': id,
        'status': status,
        'reason': 'Message report reviewed from Admin',
      });
      setState(() => _message = 'Message report $id marked $status.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _message = error.message ?? 'Message report update failed.',
      );
    }
  }

  Future<void> _pipelineHealthReset() async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot reset pipeline health.');
      return;
    }
    const reason =
        'Admin Operations Pipeline Health Reset for stale operational artefacts.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pipeline Health Reset'),
        content: const Text(
          'This expires only stale unaccepted deliveries and clears expired operational queue artefacts. Accepted, assigned, delivered and financial records are never touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Run reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await _functions.httpsCallable('pipelineHealthReset').call(
        {'reason': reason},
      );
      final data = Map<String, dynamic>.from(result.data as Map);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pipeline Health Reset complete'),
          content: Text(_pipelineHealthSummary(data)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      setState(() => _message = 'Pipeline Health Reset completed.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = _functionsMessage(error));
    }
  }

  Future<void> _operationsHealthScan() async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot run health scans.');
      return;
    }
    try {
      final result =
          await _functions.httpsCallable('operationsHealthScan').call({
        'correlationId':
            'admin-health-scan-${DateTime.now().millisecondsSinceEpoch}',
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Operations Health Scan'),
          content: Text(_operationsHealthSummary(data)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      setState(() => _message = 'Operations Health Scan completed.');
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = _functionsMessage(error));
    }
  }

  Future<void> _operationsHealthRepair() async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot run health repairs.');
      return;
    }
    const reason =
        'Admin Operations Health Repair for deterministic canonical inconsistencies.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Health Repair'),
        content: const Text(
          'This repairs deterministic canonical inconsistencies only. It never approves users, changes financial records, weakens security or edits active delivery lifecycle state.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Run repair'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await _functions
          .httpsCallable('operationsHealthRepair')
          .call({'reason': reason});
      final data = Map<String, dynamic>.from(result.data as Map);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Health Repair complete'),
          content: Text(_operationsRepairSummary(data)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      setState(() => _message = 'Health Repair completed.');
      await _loadAdminData();
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = _functionsMessage(error));
    }
  }

  Future<void> _liveDeliveryDiagnostics() async {
    if (!_can(AdminPermission.manageIssues)) {
      setState(() => _message = 'Your role cannot run delivery diagnostics.');
      return;
    }
    final controller = TextEditingController();
    final deliveryId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Live Delivery Diagnostics'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Delivery ID',
            hintText: 'deliveryRequests/{id}',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Inspect'),
          ),
        ],
      ),
    );
    if (deliveryId == null || deliveryId.trim().isEmpty) return;
    try {
      final result = await _functions
          .httpsCallable('liveDeliveryDiagnostics')
          .call({'deliveryId': deliveryId.trim()});
      final data = Map<String, dynamic>.from(result.data as Map);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Live Delivery Diagnostics'),
          content: Text(_deliveryDiagnosticsSummary(data)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      setState(() => _message = 'Live Delivery Diagnostics completed.');
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = _functionsMessage(error));
    }
  }

  String _pipelineHealthSummary(Map<String, dynamic> data) {
    final before = Map<String, dynamic>.from((data['before'] as Map?) ?? {});
    final after = Map<String, dynamic>.from((data['after'] as Map?) ?? {});
    return [
      'Before score: ${before['dispatchHealthScore'] ?? 'n/a'}',
      'After score: ${after['dispatchHealthScore'] ?? 'n/a'}',
      'Deliveries expired: ${data['deliveriesExpired'] ?? 0}',
      'Offers removed: ${data['offersRemoved'] ?? 0}',
      'Reservations released: ${data['reservationsReleased'] ?? 0}',
      'Queue entries cleared: ${data['queueEntriesCleared'] ?? 0}',
      'IRIS sessions cleaned: ${data['irisSessionsCleaned'] ?? 0}',
      'Temporary caches cleared: ${data['temporaryCachesCleared'] ?? 0}',
      'Audit ID: ${data['auditId'] ?? ''}',
    ].join('\n');
  }

  String _operationsHealthSummary(Map<String, dynamic> data) {
    final scores = Map<String, dynamic>.from((data['scores'] as Map?) ?? {});
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final failures = items
        .where((item) => item['status'] != 'PASS')
        .take(8)
        .map(
          (item) =>
              '${item['status']} ${item['service']}: ${item['rootCause']}\nRemediation: ${item['suggestedRemediation']}',
        )
        .join('\n\n');
    return [
      'Result: ${data['result'] ?? 'n/a'}',
      'Deployment gate: ${data['deploymentCertification'] ?? 'n/a'}',
      'Overall score: ${scores['overallProductionHealthScore'] ?? 'n/a'}',
      'Dispatch score: ${scores['dispatchHealthScore'] ?? 'n/a'}',
      'IRIS score: ${scores['irisHealthScore'] ?? 'n/a'}',
      'Maps score: ${scores['mapsHealthScore'] ?? 'n/a'}',
      'Payments score: ${scores['paymentsHealthScore'] ?? 'n/a'}',
      'Firebase score: ${scores['firebaseHealthScore'] ?? 'n/a'}',
      if (failures.isNotEmpty) '\nWarnings / failures:\n$failures',
    ].join('\n');
  }

  String _operationsRepairSummary(Map<String, dynamic> data) {
    final results = Map<String, dynamic>.from((data['results'] as Map?) ?? {});
    final after = Map<String, dynamic>.from((data['after'] as Map?) ?? {});
    final scores = Map<String, dynamic>.from((after['scores'] as Map?) ?? {});
    return [
      'Rider canonical synchronisations: ${results['riderCanonicalSynchronisations'] ?? 0}',
      'Dispatch eligibility recalculations: ${results['dispatchEligibilityRecalculations'] ?? 0}',
      'Financial records mutated: ${results['financialRecordsMutated'] ?? 0}',
      'Users approved: ${results['usersApproved'] ?? 0}',
      'Overall score after repair: ${scores['overallProductionHealthScore'] ?? 'n/a'}',
    ].join('\n');
  }

  String _deliveryDiagnosticsSummary(Map<String, dynamic> data) {
    final stages = (data['stages'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final lines = stages
        .map(
          (stage) =>
              '${stage['status']} ${stage['stage']}: ${stage['rootCause']}',
        )
        .join('\n');
    return [
      'Delivery: ${data['deliveryId'] ?? 'n/a'}',
      'Result: ${data['result'] ?? 'n/a'}',
      'Stopped at: ${data['stoppedAt'] ?? 'n/a'}',
      if (lines.isNotEmpty) '\n$lines',
    ].join('\n');
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

  String _businessIdForAdmin(Map<String, dynamic> account) =>
      '${account['businessId'] ?? account['businessAccountId'] ?? account['companyId'] ?? account['id'] ?? ''}'
          .trim();

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
                      onAdjudicateIrisReferral: _adjudicateIrisReferral,
                      onLoadIrisReferenceImage: _loadIrisReferenceImage,
                      onFinalizeIrisReferenceImage: _finalizeIrisReferenceImage,
                      onDeleteIrisReferenceImage: _deleteIrisReferenceImage,
                      onUpdateSupportTicket: _updateSupportTicket,
                      onUpdateGiftWorkflow: _updateGiftWorkflow,
                      onUpdateHealthPlusPickup: _updateHealthPlusPickup,
                      onUpdateFinanceWorkflow: _updateFinanceWorkflow,
                      onIssueRoth: _issueRothFromAdminRecord,
                      onIssueManualRothCredit: _issueManualRothCredit,
                      onManageRecognition: _manageRecognition,
                      onSetWalletFrozen: _setWalletFrozenFromAdminRecord,
                      onProcessPayoutRequest: _processPayoutRequestFromAdmin,
                      onModerateRating: _moderateRating,
                      onSyncRiderStripe: _syncRiderStripeStatus,
                      onResetRiderStripe: _resetRiderStripe,
                      onGenerateRiderStripeLink:
                          _generateRiderStripeOnboardingLink,
                      onOpenRiderStripeDashboard: _openRiderStripeDashboard,
                      onMarkRiderStripeInvestigation:
                          _markRiderStripeInvestigation,
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
                      onCreateBusinessInvoice: _createBusinessInvoice,
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
                      onGovernanceAction: _performGovernanceAction,
                      onPipelineHealthReset: _pipelineHealthReset,
                      onOperationsHealthScan: _operationsHealthScan,
                      onOperationsHealthRepair: _operationsHealthRepair,
                      onLiveDeliveryDiagnostics: _liveDeliveryDiagnostics,
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
                      onClose: () => setState(() => _selectedHealthPlus = null),
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
              applications: _data.riderApplications,
              documents: _data.riderDocuments,
              onboardingEvents: _data.riderOnboardingEvents,
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
    required this.riderApplications,
    required this.riderDocuments,
    required this.riderOnboardingEvents,
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
    required this.recognitionAwards,
    required this.recognitionAuditLogs,
    required this.recognitionCounters,
    required this.rateLimits,
    required this.senderDrafts,
    required this.riderPresence,
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
  final List<Map<String, dynamic>> riderApplications;
  final List<Map<String, dynamic>> riderDocuments;
  final List<Map<String, dynamic>> riderOnboardingEvents;
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
  final List<Map<String, dynamic>> recognitionAwards;
  final List<Map<String, dynamic>> recognitionAuditLogs;
  final List<Map<String, dynamic>> recognitionCounters;
  final List<Map<String, dynamic>> rateLimits;
  final List<Map<String, dynamic>> senderDrafts;
  final List<Map<String, dynamic>> riderPresence;

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
        riderApplications: [],
        riderDocuments: [],
        riderOnboardingEvents: [],
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
        recognitionAwards: [],
        recognitionAuditLogs: [],
        recognitionCounters: [],
        rateLimits: [],
        senderDrafts: [],
        riderPresence: [],
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
      _read(_db.collection('riderApplications').limit(150)),
      _read(_db.collection('riderDocuments').limit(150)),
      _read(_db.collection('riderOnboardingEvents').limit(150)),
      _read(_db.collection('driverPerformanceMetrics').limit(150)),
      _read(
        _db
            .collection('websiteVisitors')
            .orderBy('createdAt', descending: true)
            .limit(150),
      ),
      _readTagged(
        _db.collection('irisCanonicalObjects').limit(150),
        'irisCanonicalObjects',
      ),
      Future.wait([
        _readTagged(
          _db.collection('irisLearningCases').limit(150),
          'irisLearningCases',
        ),
        _readTagged(
          _db.collection('iris_learning_review_candidates').limit(150),
          'iris_learning_review_candidates',
        ),
      ]).then((groups) {
        final byId = <String, Map<String, dynamic>>{};
        for (final group in groups) {
          for (final record in group) {
            byId['${record['id']}'] = record;
          }
        }
        return byId.values.toList(growable: false);
      }),
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
      _read(_db.collection('recognitionAwards').limit(150)),
      _read(
        _db
            .collection('recognitionAuditLogs')
            .orderBy('createdAt', descending: true)
            .limit(150),
      ),
      _read(_db.collection('recognitionCounters').limit(20)),
      _read(_db.collection('rateLimits').limit(120)),
      _read(
        _db
            .collection('senderBookingDrafts')
            .orderBy('updatedAt', descending: true)
            .limit(120),
      ),
      _read(_db.collection('riderPresence').limit(150)),
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
      riderApplications: results[29],
      riderDocuments: results[30],
      riderOnboardingEvents: results[31],
      driverPerformanceMetrics: results[32],
      websiteVisitors: results[33],
      irisCanonicalObjects: results[34],
      irisLearningCases: results[35],
      irisLearningOutliers: results[36],
      irisPolicies: results[37],
      irisEvidence: results[38],
      irisReferenceImages: results[39],
      platformConfig: results[40],
      platformStatus: results[41],
      platformNotices: results[42],
      platformVersions: results[43],
      notifications: results[44],
      messageReports: results[45],
      adminNotes: results[46],
      senderTrustEvents: results[47],
      recognitionAwards: results[48],
      recognitionAuditLogs: results[49],
      recognitionCounters: results[50],
      rateLimits: results[51],
      senderDrafts: results[52],
      riderPresence: results[53],
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
    required this.onAdjudicateIrisReferral,
    required this.onLoadIrisReferenceImage,
    required this.onFinalizeIrisReferenceImage,
    required this.onDeleteIrisReferenceImage,
    required this.onUpdateSupportTicket,
    required this.onUpdateGiftWorkflow,
    required this.onUpdateHealthPlusPickup,
    required this.onUpdateFinanceWorkflow,
    required this.onIssueRoth,
    required this.onIssueManualRothCredit,
    required this.onManageRecognition,
    required this.onSetWalletFrozen,
    required this.onProcessPayoutRequest,
    required this.onModerateRating,
    required this.onSyncRiderStripe,
    required this.onResetRiderStripe,
    required this.onGenerateRiderStripeLink,
    required this.onOpenRiderStripeDashboard,
    required this.onMarkRiderStripeInvestigation,
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
    required this.onCreateBusinessInvoice,
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
    required this.onGovernanceAction,
    required this.onPipelineHealthReset,
    required this.onOperationsHealthScan,
    required this.onOperationsHealthRepair,
    required this.onLiveDeliveryDiagnostics,
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
  final Future<void> Function(Map<String, dynamic>, String)
      onAdjudicateIrisReferral;
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
  final Future<void> Function({
    required String recipient,
    required double amount,
    required String reason,
    required String walletTarget,
  }) onIssueManualRothCredit;
  final Future<void> Function(Map<String, dynamic>, String, String)
      onManageRecognition;
  final Future<void> Function(Map<String, dynamic>, bool) onSetWalletFrozen;
  final Future<void> Function(Map<String, dynamic>, String)
      onProcessPayoutRequest;
  final Future<void> Function(Map<String, dynamic>, String) onModerateRating;
  final Future<void> Function(Map<String, dynamic>) onSyncRiderStripe;
  final Future<void> Function(Map<String, dynamic>) onResetRiderStripe;
  final Future<String?> Function(Map<String, dynamic>, {bool copy, bool send})
      onGenerateRiderStripeLink;
  final Future<void> Function(Map<String, dynamic>) onOpenRiderStripeDashboard;
  final Future<void> Function(Map<String, dynamic>, String)
      onMarkRiderStripeInvestigation;
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
  final Future<void> Function() onCreateBusinessInvoice;
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
  final Future<void> Function(Map<String, dynamic>, String) onGovernanceAction;
  final Future<void> Function() onPipelineHealthReset;
  final Future<void> Function() onOperationsHealthScan;
  final Future<void> Function() onOperationsHealthRepair;
  final Future<void> Function() onLiveDeliveryDiagnostics;

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
          AdminModule.governance => _GovernanceOperationsModule(
              rateLimits: data.rateLimits,
              senderDrafts: data.senderDrafts,
              riderPresence: data.riderPresence,
              users: data.users,
              riders: data.riders,
              deliveries: data.deliveries,
              payments: data.payments,
              wallets: data.wallets,
              businessInvoices: data.businessInvoices,
              businessAccounts: data.businessAccounts,
              healthPlusPickups: data.healthPlusPickups,
              recurringPickupSchedules: data.recurringPickupSchedules,
              giftOrders: data.giftOrders,
              giftRequests: data.giftRequests,
              giftCampaignMatches: data.giftCampaignMatches,
              irisEvidence: data.irisEvidence,
              irisCanonicalObjects: data.irisCanonicalObjects,
              irisLearningCases: data.irisLearningCases,
              notifications: data.notifications,
              chats: data.chats,
              auditLogs: data.auditLogs,
              query: query,
              canRecover: canManageIssues,
              onGovernanceAction: onGovernanceAction,
              onPipelineHealthReset: onPipelineHealthReset,
              onOperationsHealthScan: onOperationsHealthScan,
              onOperationsHealthRepair: onOperationsHealthRepair,
              onLiveDeliveryDiagnostics: onLiveDeliveryDiagnostics,
              onRetryNotificationDelivery: onRetryNotificationDelivery,
              onOpenDelivery: onOpenDeliveryProfile,
            ),
          AdminModule.recognition => _RecognitionOperationsModule(
              users: data.users,
              riders: data.riders,
              businessAccounts: data.businessAccounts,
              awards: data.recognitionAwards,
              auditLogs: data.recognitionAuditLogs,
              counters: data.recognitionCounters,
              query: query,
              canManageRecognition: canManageIssues,
              onManageRecognition: onManageRecognition,
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
              onAdjudicateIrisReferral: onAdjudicateIrisReferral,
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
                  subtitle: 'Sender and customer account records.',
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
              applications: data.riderApplications,
              documents: data.riderDocuments,
              onboardingEvents: data.riderOnboardingEvents,
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
              users: data.users,
              riders: data.riders,
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
              onIssueManualRothCredit: onIssueManualRothCredit,
              onSetWalletFrozen: onSetWalletFrozen,
              onProcessPayoutRequest: onProcessPayoutRequest,
              onModerateRating: onModerateRating,
              onSyncRiderStripe: onSyncRiderStripe,
              onGenerateRiderStripeLink: onGenerateRiderStripeLink,
              onOpenRiderStripeDashboard: onOpenRiderStripeDashboard,
              onMarkRiderStripeInvestigation: onMarkRiderStripeInvestigation,
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
              onCreateBusinessInvoice: onCreateBusinessInvoice,
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
            _MetricCard(
              'Basic plans',
              schedules
                  .where((item) => _healthPlanKey(item) == 'basic')
                  .length
                  .toString(),
              '2 monthly pickups',
            ),
            _MetricCard(
              'Priority plans',
              schedules
                  .where((item) => _healthPlanKey(item) == 'priority')
                  .length
                  .toString(),
              '4 monthly pickups',
            ),
            _MetricCard(
              'Family plans',
              schedules
                  .where((item) => _healthPlanKey(item) == 'family')
                  .length
                  .toString(),
              'fair-use monitored',
            ),
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
            'subscriptionPlan',
            'planLabel',
            'remainingPickupsThisCycle',
            'fairUseMonitored',
          ],
          columns: const ['Prescription', 'Patient', 'Plan', 'Status'],
          row: (record) => [
            _recordId(record),
            '${record['patientName'] ?? record['fullName'] ?? record['customerName'] ?? 'Patient'}\n${record['pharmacyName'] ?? record['pharmacyAddress'] ?? 'Pharmacy'}',
            '${_healthPlanLabel(record)}\n${_healthAllowanceLabel(record)}',
            '${record['status'] ?? record['clinicalReviewStatus'] ?? 'pending'}\n${_healthFairUseLabel(record)}',
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
                      unawaited(onUpdateHealthPlusPickup(record, action.$2)),
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
            'subscriptionPlan',
            'planLabel',
            'remainingPickupsThisCycle',
            'fairUseMonitored',
          ]),
          query: '',
          fields: const [],
          columns: const ['Profile', 'Medical', 'Plan', 'Operational'],
          row: (record) => [
            '${record['patientName'] ?? record['fullName'] ?? record['name'] ?? _recordId(record)}\n${record['email'] ?? record['phoneNumber'] ?? record['userId'] ?? record['senderId'] ?? ''}',
            '${record['medication'] ?? record['medicationName'] ?? record['prescriptionSummary'] ?? 'Medication profile'}\n${record['allergySummary'] ?? record['handlingNotes'] ?? record['clinicalNotes'] ?? ''}',
            '${_healthPlanLabel(record)}\n${_healthAllowanceLabel(record)}',
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
                      unawaited(onUpdateHealthPlusProfile(record, action.$2)),
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
            'planLabel',
            'includedPickups',
            'usedPickupsThisCycle',
            'remainingPickupsThisCycle',
            'renewalDate',
            'fairUseMonitored',
            'preferredPickupTime',
          ]),
          query: '',
          fields: const [],
          columns: const ['Schedule', 'Customer', 'Allowance', 'Status'],
          row: (record) => [
            _recordId(record),
            '${record['fullName'] ?? record['senderName'] ?? record['userId'] ?? record['senderId'] ?? 'Customer'}',
            '${_healthPlanLabel(record)}\n${_healthAllowanceLabel(record)}',
            '${record['status'] ?? record['adminReviewStatus'] ?? 'scheduled'}\n${_healthRenewalLabel(record)}',
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
                      onPressed: () => unawaited(
                          onUpdateHealthPlusSchedule(record, 'paused')),
                    ),
                    _MiniAction(
                      label: 'Resume',
                      onPressed: () => unawaited(
                          onUpdateHealthPlusSchedule(record, 'active')),
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
    required this.onCreateBusinessInvoice,
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
  final Future<void> Function() onCreateBusinessInvoice;
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
  ) =>
      _tabWorkspace(
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
            final editable = (record['memberIndex'] is int) &&
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
  ) =>
      _tabWorkspace(
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
  ) =>
      _tabWorkspace(
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
  ) =>
      _tabWorkspace(
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
  ) =>
      _tabWorkspace(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => unawaited(onCreateBusinessInvoice()),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Generate invoice'),
              ),
            ),
            const SizedBox(height: 12),
            _RecordModule(
              title: 'Business Invoices',
              subtitle:
                  'Invoice generation, review, history, editing and audit.',
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
                  record['total'] ??
                      record['invoiceAmount'] ??
                      record['balanceDue'],
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
                    onPressed: () => unawaited(
                        onSetBusinessOperationStatus(record, action.$2)),
                  ),
              ],
            ),
          ],
        ),
      );

  Widget _businessRothWorkspace(
    List<Map<String, dynamic>> roth,
  ) =>
      _tabWorkspace(
        child: _RecordModule(
          title: 'Business Roth',
          subtitle:
              'Business Roth purchases, usage, ledger, history and audit.',
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
            _money(
                record['amount'] ?? record['amountGbp'] ?? record['balance']),
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
  ) =>
      _tabWorkspace(
        child: _RecordModule(
          title: 'Business Analytics',
          subtitle:
              'Per-business delivery volume, spend, service mix, Vanguard usage, Health+ and Gifts volume.',
          records: analytics,
          query: query,
          fields: const ['businessName', 'businessId'],
          columns: const [
            'Business',
            'Volume / Spend',
            'On-time',
            'Service Mix'
          ],
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
  ) =>
      _tabWorkspace(
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
  ) =>
      [
        ...businessDeliveries.where(
          (item) =>
              _serviceType(item).contains('health') ||
              '${item['sourceModule'] ?? ''}'.toLowerCase().contains('health'),
        ),
        ...healthPlusPickups.where(_isBusinessRecord),
      ].toList(growable: false);

  List<Map<String, dynamic>> _businessGiftRows(
    List<Map<String, dynamic>> businessDeliveries,
  ) =>
      [
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
    return accounts.map((account) {
      final id = _businessAccountId(account);
      final scoped = businessDeliveries
          .where((delivery) => _businessRecordId(delivery) == id)
          .toList(growable: false);
      final amount = scoped.fold<double>(
        0,
        (total, delivery) =>
            total +
            _numberFrom(
              delivery['finalAmount'] ?? delivery['price'] ?? delivery['quote'],
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
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> _businessAnalyticsRows(
    List<Map<String, dynamic>> businessDeliveries,
  ) =>
      accounts.map((account) {
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
      }).toList(growable: false);

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
    final direct =
        '${item['businessName'] ?? item['companyName'] ?? ''}'.trim();
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

class _RecognitionOperationsModule extends StatelessWidget {
  const _RecognitionOperationsModule({
    required this.users,
    required this.riders,
    required this.businessAccounts,
    required this.awards,
    required this.auditLogs,
    required this.counters,
    required this.query,
    required this.canManageRecognition,
    required this.onManageRecognition,
  });

  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> businessAccounts;
  final List<Map<String, dynamic>> awards;
  final List<Map<String, dynamic>> auditLogs;
  final List<Map<String, dynamic>> counters;
  final String query;
  final bool canManageRecognition;
  final Future<void> Function(Map<String, dynamic>, String, String)
      onManageRecognition;

  @override
  Widget build(BuildContext context) {
    final subjects = [
      for (final user in users) {'_recognitionCollection': 'users', ...user},
      for (final rider in riders)
        {'_recognitionCollection': 'riderProfiles', ...rider},
      for (final account in businessAccounts)
        {'_recognitionCollection': 'businessAccounts', ...account},
    ];
    final filtered = adminSearch(subjects, query, const [
      'id',
      'uid',
      'email',
      'fullName',
      'name',
      'businessName',
      'companyName',
      'recognitions',
      'legendNumber',
      'foundingRiderNumber',
      'patronNumber',
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _MetricCard('Awards', awards.length.toString(), 'active records'),
            _MetricCard('Audit', auditLogs.length.toString(), 'history'),
            _MetricCard('Counters', counters.length.toString(), 'limits'),
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Recognition Management',
          subtitle:
              'Search a user, Rider or Business account, select recognition and record a reason before granting or revoking.',
          records: filtered,
          query: '',
          fields: const [],
          columns: const ['Subject', 'Type', 'Recognition', 'Updated'],
          row: (record) {
            final subject = _recognitionSubject(record);
            return [
              '${subject.label}\n${subject.id}',
              _recognitionCollectionLabel(subject.collection),
              _recognitionSummary(record),
              _date(record['updatedAt'] ?? record['createdAt']),
            ];
          },
          actions: canManageRecognition
              ? (record) => [
                    for (final type in _recognitionTypesFor(record)) ...[
                      _MiniAction(
                        label: 'Grant ${_recognitionTypeLabel(type)}',
                        onPressed: () => unawaited(
                            onManageRecognition(record, 'grant', type)),
                      ),
                      _MiniAction(
                        label: 'Revoke ${_recognitionTypeLabel(type)}',
                        onPressed: () => unawaited(
                          onManageRecognition(record, 'revoke', type),
                        ),
                      ),
                    ],
                  ]
              : null,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Recognition Audit Trail',
          subtitle:
              'Grant and revoke history recorded by the backend recognition service.',
          records: auditLogs,
          query: query,
          fields: const [
            'action',
            'type',
            'subjectId',
            'subjectCollection',
            'reason',
            'awardedBy',
            'revokedBy',
          ],
          columns: const ['Action', 'Subject', 'Operator', 'Reason / Time'],
          row: (record) => [
            '${record['action'] ?? record['actionType'] ?? 'recognition'}\n${_recognitionTypeLabel('${record['type'] ?? record['recognitionType'] ?? ''}')}',
            '${record['subjectCollection'] ?? record['recordType'] ?? ''}\n${record['subjectId'] ?? record['recordId'] ?? _recordId(record)}',
            '${record['awardedBy'] ?? record['revokedBy'] ?? record['adminUserId'] ?? 'Admin'}',
            '${record['reason'] ?? 'Reason recorded'}\n${_date(record['createdAt'] ?? record['timestamp'])}',
          ],
        ),
      ],
    );
  }
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
    required this.onAdjudicateIrisReferral,
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
  final Future<void> Function(Map<String, dynamic>, String)
      onAdjudicateIrisReferral;
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
          title: 'IRIS Referrals Queue',
          subtitle:
              'Referral required, unsupported and prohibited parcel reviews awaiting Admin resolution.',
          records: irisRecords.where(_isIrisReferralRecord).toList(),
          query: query,
          fields: const [
            'id',
            'requestId',
            'senderName',
            'senderId',
            'irisStatus',
            'irisReviewStatus',
            'category',
            'irisCategory',
            'reason',
            'description',
          ],
          columns: const [
            'Delivery / Sender',
            'IRIS result',
            'Evidence',
            'Reason',
          ],
          row: (record) => [
            '${_recordId(record)}\n${record['senderName'] ?? record['senderId'] ?? 'Sender not recorded'}',
            '${_irisDecisionLabel(record)}\n${record['category'] ?? record['irisCategory'] ?? 'Category not recorded'}',
            'Images ${_irisImageCount(record)} / weight ${_irisWeightSummary(record)}',
            '${record['irisReason'] ?? record['reviewReason'] ?? record['reason'] ?? record['description'] ?? 'Review required'}',
          ],
          actions: (record) => [
            _MiniAction(
              label: 'Details',
              onPressed: () => onOpenDelivery(record),
            ),
            if (canManageIris)
              for (final action in const [
                ('Allow', 'allowed'),
                ('Refer', 'referral_required'),
                ('Unsupported', 'unsupported'),
                ('Prohibited', 'prohibited'),
              ])
                _MiniAction(
                  label: action.$1,
                  onPressed: () =>
                      unawaited(onAdjudicateIrisReferral(record, action.$2)),
                ),
          ],
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
                        ? null
                        : () => unawaited(
                              onUpdateRepositoryRecord(
                                  records.first, action.$2),
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
          title: 'Item Library Governance',
          subtitle:
              'Canonical item review, administration, reference images and lifecycle history.',
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
    final deliveryCandidates =
        deliveries.where(_isLearningCandidate).toList(growable: false);
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
    required this.users,
    required this.riders,
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
    required this.onIssueManualRothCredit,
    required this.onSetWalletFrozen,
    required this.onProcessPayoutRequest,
    required this.onModerateRating,
    required this.onSyncRiderStripe,
    required this.onGenerateRiderStripeLink,
    required this.onOpenRiderStripeDashboard,
    required this.onMarkRiderStripeInvestigation,
  });

  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> riders;
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
  final Future<void> Function({
    required String recipient,
    required double amount,
    required String reason,
    required String walletTarget,
  }) onIssueManualRothCredit;
  final Future<void> Function(Map<String, dynamic>, bool) onSetWalletFrozen;
  final Future<void> Function(Map<String, dynamic>, String)
      onProcessPayoutRequest;
  final Future<void> Function(Map<String, dynamic>, String) onModerateRating;
  final Future<void> Function(Map<String, dynamic>) onSyncRiderStripe;
  final Future<String?> Function(Map<String, dynamic>, {bool copy, bool send})
      onGenerateRiderStripeLink;
  final Future<void> Function(Map<String, dynamic>) onOpenRiderStripeDashboard;
  final Future<void> Function(Map<String, dynamic>, String)
      onMarkRiderStripeInvestigation;

  @override
  Widget build(BuildContext context) {
    final todayRevenue = _financeTotalToday(payments);
    final outstandingSettlements =
        payments.where(_isOutstandingSettlement).length;
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
                        onPressed: () => unawaited(
                            onUpdateFinanceWorkflow(record, action.$2)),
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
        _ManualRothCreditPanel(
          canManageFinance: canManageFinance,
          users: users,
          riders: riders,
          businessWallets: businessWallets,
          onIssueManualRothCredit: onIssueManualRothCredit,
        ),
        const SizedBox(height: 18),
        _StripeConnectOperationsPanel(
          riders: riders,
          payoutRequests: payoutRequests,
          auditLogs: auditLogs,
          query: query,
          canManageFinance: canManageFinance,
          onSyncRiderStripe: onSyncRiderStripe,
          onGenerateRiderStripeLink: onGenerateRiderStripeLink,
          onOpenRiderStripeDashboard: onOpenRiderStripeDashboard,
          onMarkRiderStripeInvestigation: onMarkRiderStripeInvestigation,
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
                      onPressed: () =>
                          unawaited(onSetWalletFrozen(record, true)),
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

class _ManualRothCreditPanel extends StatefulWidget {
  const _ManualRothCreditPanel({
    required this.canManageFinance,
    required this.users,
    required this.riders,
    required this.businessWallets,
    required this.onIssueManualRothCredit,
  });

  final bool canManageFinance;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> businessWallets;
  final Future<void> Function({
    required String recipient,
    required double amount,
    required String reason,
    required String walletTarget,
  }) onIssueManualRothCredit;

  @override
  State<_ManualRothCreditPanel> createState() => _ManualRothCreditPanelState();
}

class _ManualRothCreditPanelState extends State<_ManualRothCreditPanel> {
  final _recipient = TextEditingController();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _walletTarget = 'sender';

  @override
  void dispose() {
    _recipient.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final examples = [
      ...widget.users.take(4).map(
            (user) =>
                '${user['email'] ?? user['uid'] ?? user['id'] ?? 'Sender'}',
          ),
      ...widget.riders.take(2).map(
            (rider) =>
                '${rider['email'] ?? rider['uid'] ?? rider['id'] ?? 'Rider'}',
          ),
      ...widget.businessWallets.take(2).map(
            (wallet) =>
                '${wallet['businessId'] ?? wallet['walletId'] ?? wallet['id'] ?? 'Business'}',
          ),
    ].where((value) => value.trim().isNotEmpty).toList();
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manual Roth Credit',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Issue Roth to one account through the backend wallet service. A reason is required and every request is audited.',
              style: TextStyle(color: Colors.white.withValues(alpha: .66)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _recipient,
                    enabled: widget.canManageFinance,
                    decoration: const InputDecoration(
                      labelText: 'User email or account ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _amount,
                    enabled: widget.canManageFinance,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: _walletTarget,
                    decoration: const InputDecoration(
                      labelText: 'Account type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'sender', child: Text('Sender')),
                      DropdownMenuItem(value: 'rider', child: Text('Rider')),
                      DropdownMenuItem(
                        value: 'business',
                        child: Text('Business'),
                      ),
                    ],
                    onChanged: widget.canManageFinance
                        ? (value) =>
                            setState(() => _walletTarget = value ?? 'sender')
                        : null,
                  ),
                ),
                SizedBox(
                  width: 340,
                  child: TextField(
                    controller: _reason,
                    enabled: widget.canManageFinance,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: widget.canManageFinance
                      ? () => unawaited(
                            widget.onIssueManualRothCredit(
                              recipient: _recipient.text,
                              amount: double.tryParse(_amount.text.trim()) ?? 0,
                              reason: _reason.text,
                              walletTarget: _walletTarget,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.add_card_rounded),
                  label: const Text('Issue Roth'),
                ),
              ],
            ),
            if (examples.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Loaded account examples: ${examples.join(', ')}',
                style: TextStyle(color: Colors.white.withValues(alpha: .58)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StripeConnectOperationsPanel extends StatelessWidget {
  const _StripeConnectOperationsPanel({
    required this.riders,
    required this.payoutRequests,
    required this.auditLogs,
    required this.query,
    required this.canManageFinance,
    required this.onSyncRiderStripe,
    required this.onGenerateRiderStripeLink,
    required this.onOpenRiderStripeDashboard,
    required this.onMarkRiderStripeInvestigation,
  });

  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> payoutRequests;
  final List<Map<String, dynamic>> auditLogs;
  final String query;
  final bool canManageFinance;
  final Future<void> Function(Map<String, dynamic>) onSyncRiderStripe;
  final Future<String?> Function(Map<String, dynamic>, {bool copy, bool send})
      onGenerateRiderStripeLink;
  final Future<void> Function(Map<String, dynamic>) onOpenRiderStripeDashboard;
  final Future<void> Function(Map<String, dynamic>, String)
      onMarkRiderStripeInvestigation;

  @override
  Widget build(BuildContext context) {
    final records = adminSearch(riders, query, const [
      'id',
      'uid',
      'riderId',
      'fullName',
      'name',
      'email',
      'stripeConnectAccountId',
      'stripeAccountId',
      'stripeConnectStatus',
      'stripeStatus',
      'stripeDisabledReason',
    ]);
    final enabled = riders.where(_stripePayoutsEnabled).length;
    final actionRequired = riders.where(_stripeNeedsAction).length;
    final restricted = riders.where(_stripeRestricted).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: _panelDecoration(),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stripe Connect Operations',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Diagnose and recover Rider payout setup. Admin can send riders back to Stripe, but cannot complete verification for them.',
                  style: TextStyle(color: Color(0xFFA8B3C5), height: 1.45),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HealthChip('Payouts enabled', enabled),
                    _HealthChip('Action required', actionRequired),
                    _HealthChip('Restricted', restricted),
                    _HealthChip('Payout requests', payoutRequests.length),
                    _HealthChip(
                      'Webhook history',
                      auditLogs
                          .where(
                            (log) => _hasAnyText(log, const [
                              'stripe',
                              'payout',
                              'webhook',
                            ]),
                          )
                          .length,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Stripe Connect',
          subtitle:
              'Rider payout setup, outstanding requirements, sync history and recovery actions.',
          records: records,
          query: '',
          fields: const [],
          columns: const [
            'Rider',
            'Payout status',
            'Requirements due',
            'Recent activity',
            'Last payout',
            'Restrictions',
          ],
          row: (record) => [
            '${record['fullName'] ?? record['name'] ?? 'Rider'}\n${record['email'] ?? 'No email recorded'}',
            _stripeCustomerStatus(record),
            _stripeRequirements(record),
            'Sync: ${_date(record['stripeLastSyncedAt'] ?? record['lastStripeSyncAt'] ?? record['updatedAt'])}\n'
                'Webhook: ${_lastStripeAuditDate(auditLogs, record, 'webhook')}\n'
                'Onboarding: ${_date(record['lastOnboardingAttemptAt'] ?? record['stripeLastOnboardingAt'] ?? record['onboardingLinkCreatedAt'])}',
            _lastRiderPayoutDate(payoutRequests, record),
            _stripeRestrictionSummary(record),
          ],
          actions: canManageFinance
              ? (record) => [
                    _MiniAction(
                      label: 'Retry sync',
                      onPressed: () => unawaited(onSyncRiderStripe(record)),
                    ),
                    _MiniAction(
                      label: 'Generate link',
                      onPressed: () =>
                          unawaited(onGenerateRiderStripeLink(record)),
                    ),
                    _MiniAction(
                      label: 'Copy link',
                      onPressed: () => unawaited(
                        onGenerateRiderStripeLink(record, copy: true),
                      ),
                    ),
                    _MiniAction(
                      label: 'Send link',
                      onPressed: () => unawaited(
                        onGenerateRiderStripeLink(record, send: true),
                      ),
                    ),
                    _MiniAction(
                      label: 'Open Stripe',
                      onPressed: () =>
                          unawaited(onOpenRiderStripeDashboard(record)),
                    ),
                    _MiniAction(
                      label: 'Investigate',
                      onPressed: () => unawaited(
                        onMarkRiderStripeInvestigation(
                          record,
                          'stripe_manual_investigation',
                        ),
                      ),
                    ),
                    _MiniAction(
                      label: 'Escalate',
                      onPressed: () => unawaited(
                        onMarkRiderStripeInvestigation(
                          record,
                          'stripe_support_escalated',
                        ),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Payout Failures',
          subtitle: 'Failed or restricted payout records requiring review.',
          records: adminSearch(
            payoutRequests
                .where(
                  (record) =>
                      _hasAnyText(record, const ['failed', 'restricted']) ||
                      '${record['failureReason'] ?? ''}'.trim().isNotEmpty,
                )
                .toList(growable: false),
            query,
            const ['riderId', 'requestId', 'status', 'failureReason'],
          ),
          query: '',
          fields: const [],
          columns: const ['Payout', 'Rider', 'Amount', 'Reason'],
          row: (record) => [
            '${record['requestId'] ?? record['id']}',
            '${record['riderId'] ?? 'Rider'}',
            _money(record['amount'] ?? record['riderNetPayout']),
            '${record['failureReason'] ?? record['reviewReason'] ?? 'Needs review'}',
          ],
        ),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Stripe Audit History',
          subtitle:
              'Payout setup, sync, reminder and investigation events recorded by Operations.',
          records: adminSearch(
            auditLogs
                .where(
                  (log) => _hasAnyText(log, const [
                    'stripe',
                    'payout',
                    'onboarding',
                  ]),
                )
                .toList(growable: false),
            query,
            const ['riderId', 'action', 'adminEmail', 'note'],
          ),
          query: '',
          fields: const [],
          columns: const ['Action', 'Rider', 'Operator', 'Note'],
          row: (record) => [
            '${record['action'] ?? record['actionType'] ?? 'Recorded'}',
            '${record['riderId'] ?? record['recordId'] ?? 'Rider'}',
            '${record['adminEmail'] ?? record['adminUserId'] ?? 'Admin'}',
            '${record['note'] ?? record['reason'] ?? ''}',
          ],
        ),
      ],
    );
  }
}

String _stripeAccount(Map<String, dynamic> record) =>
    '${record['stripeConnectAccountId'] ?? record['stripeAccountId'] ?? ''}'
        .trim();

bool _stripePayoutsEnabled(Map<String, dynamic> record) {
  final status =
      '${record['stripeConnectStatus'] ?? record['stripeStatus'] ?? ''}'
          .toLowerCase();
  return record['stripePayoutsEnabled'] == true ||
      record['payoutsEnabled'] == true ||
      status.contains('payouts_enabled') ||
      status.contains('active');
}

bool _stripeNeedsAction(Map<String, dynamic> record) {
  final status =
      '${record['stripeConnectStatus'] ?? record['stripeStatus'] ?? ''}'
          .toLowerCase();
  return status.contains('action') ||
      status.contains('required') ||
      (record['stripeRequirementsDue'] is Iterable &&
          (record['stripeRequirementsDue'] as Iterable).isNotEmpty);
}

bool _stripeRestricted(Map<String, dynamic> record) {
  final status =
      '${record['stripeConnectStatus'] ?? record['stripeStatus'] ?? ''}'
          .toLowerCase();
  return status.contains('restrict') ||
      status.contains('disabled') ||
      '${record['stripeDisabledReason'] ?? ''}'.trim().isNotEmpty;
}

String _stripeCustomerStatus(Map<String, dynamic> record) {
  final status =
      '${record['stripeConnectStatus'] ?? record['stripeStatus'] ?? ''}'
          .toLowerCase();
  if (_stripePayoutsEnabled(record)) return 'Payouts enabled';
  if (_stripeRestricted(record)) return 'Restricted';
  if (_stripeNeedsAction(record)) return 'Action required';
  if (status.contains('pending') || status.contains('review')) {
    return 'Verification in progress';
  }
  if (status.contains('onboarding') || _stripeAccount(record).isNotEmpty) {
    return 'Additional information required';
  }
  return 'Needs payout setup';
}

String _stripeRequirements(Map<String, dynamic> record) {
  final due = record['stripeRequirementsDue'];
  final future = record['stripeRequirementsEventuallyDue'];
  final reason = '${record['stripeDisabledReason'] ?? ''}'.trim();
  final pieces = <String>[];
  if (due is Iterable && due.isNotEmpty) {
    pieces.add('${due.length} outstanding');
  }
  if (future is Iterable && future.isNotEmpty) {
    pieces.add('${future.length} upcoming');
  }
  if (reason.isNotEmpty) pieces.add('Restricted: $reason');
  return pieces.isEmpty ? 'None currently due' : pieces.join(' · ');
}

String _stripeRestrictionSummary(Map<String, dynamic> record) {
  final reason =
      '${record['stripeDisabledReason'] ?? record['stripeRestrictedReason'] ?? record['restrictedReason'] ?? ''}'
          .trim();
  if (reason.isNotEmpty) return reason;
  return _stripeRestricted(record) ? 'Restricted' : 'No active restrictions';
}

String _lastRiderPayoutDate(
  List<Map<String, dynamic>> payoutRequests,
  Map<String, dynamic> rider,
) {
  final matches = payoutRequests
      .where((payout) => _sameRiderRecord(payout, rider))
      .toList(growable: false);
  if (matches.isEmpty) return 'No payout recorded';
  matches.sort((a, b) => _sortDate(b).compareTo(_sortDate(a)));
  return _date(
    matches.first['paidAt'] ??
        matches.first['processedAt'] ??
        matches.first['createdAt'] ??
        matches.first['updatedAt'],
  );
}

String _lastStripeAuditDate(
  List<Map<String, dynamic>> auditLogs,
  Map<String, dynamic> rider,
  String signal,
) {
  final matches = auditLogs
      .where(
        (log) =>
            _sameRiderRecord(log, rider) &&
            _hasAnyText(log, ['stripe', 'payout', signal]),
      )
      .toList(growable: false);
  if (matches.isEmpty) return 'No event recorded';
  matches.sort((a, b) => _sortDate(b).compareTo(_sortDate(a)));
  return _date(
    matches.first['createdAt'] ??
        matches.first['timestamp'] ??
        matches.first['updatedAt'],
  );
}

bool _sameRiderRecord(Map<String, dynamic> record, Map<String, dynamic> rider) {
  final riderIds = {
    '${rider['id'] ?? ''}',
    '${rider['uid'] ?? ''}',
    '${rider['riderId'] ?? ''}',
  }..removeWhere((value) => value.trim().isEmpty);
  if (riderIds.isEmpty) return false;
  final recordIds = {
    '${record['riderId'] ?? ''}',
    '${record['uid'] ?? ''}',
    '${record['userId'] ?? ''}',
    '${record['recordId'] ?? ''}',
  }..removeWhere((value) => value.trim().isEmpty);
  return recordIds.any(riderIds.contains);
}

DateTime _sortDate(Map<String, dynamic> record) {
  final value = record['createdAt'] ?? record['updatedAt'] ?? record['paidAt'];
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.fromMillisecondsSinceEpoch(0);
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
    required this.applications,
    required this.documents,
    required this.onboardingEvents,
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
  final List<Map<String, dynamic>> applications;
  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> onboardingEvents;
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
            _MetricCard(
              'Applications',
              applications.length.toString(),
              'submitted records',
            ),
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
          title: 'Rider application review',
          subtitle:
              'Application Centre submissions, section progress and Admin review state.',
          records: applications,
          query: query,
          fields: const [
            'id',
            'riderId',
            'fullName',
            'email',
            'phoneNumber',
            'vehicleType',
            'status',
            'sectionStatus',
          ],
          columns: const ['Application', 'Rider', 'Status', 'Updated'],
          row: (record) => [
            '${record['fullName'] ?? record['id']}\n${record['vehicleType'] ?? 'Vehicle pending'}',
            '${record['riderId'] ?? 'unknown'}\n${record['email'] ?? record['phoneNumber'] ?? ''}',
            '${record['status'] ?? 'submitted'}\n${_sectionStatusSummary(record)}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canManageRiders
              ? (record) {
                  final rider = _riderForApplication(record);
                  return [
                    _MiniAction(
                      label: 'Open rider',
                      onPressed: rider.isEmpty
                          ? null
                          : () => onOpenRiderProfile(rider),
                    ),
                    _MiniAction(
                      label: 'Request info',
                      onPressed: rider.isEmpty
                          ? null
                          : () => unawaited(onRequestMoreInformation(rider)),
                    ),
                  ];
                }
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
          title: 'Rider onboarding events',
          subtitle:
              'Backend events emitted by Rider Application Centre submissions, document uploads and review actions.',
          records: onboardingEvents,
          query: query,
          fields: const [
            'id',
            'riderId',
            'action',
            'event',
            'eventType',
            'applicationId',
            'documentId',
            'status',
          ],
          columns: const ['Event', 'Rider', 'Record', 'Time'],
          row: (record) => [
            '${record['action'] ?? record['eventType'] ?? record['event'] ?? 'event'}\n${record['status'] ?? ''}',
            '${record['riderId'] ?? record['uid'] ?? 'unknown'}',
            '${record['applicationId'] ?? record['documentId'] ?? record['id']}',
            _date(record['createdAt'] ?? record['updatedAt']),
          ],
        ),
        const SizedBox(height: 18),
        _MarketplaceRiskPanel(query: query),
        const SizedBox(height: 18),
        _RecordModule(
          title: 'Rider Performance Metrics',
          subtitle:
              'Backend reliability intelligence alongside the existing Trust Points and Rank systems.',
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
            'reliabilityScore',
            'reliabilityTrend',
            'reliabilityRiskLevel',
            'lastReliabilityReason',
          ],
          columns: const ['Rider', 'Reliability', 'Trust / Rank', 'Factors'],
          row: (record) => [
            '${_riderNameForMetric(record)}\n${_metricRiderId(record)}',
            'Score ${record['reliabilityScore'] ?? 'Pending'} / ${record['reliabilityTrend'] ?? 'Stable'}\nRisk ${record['reliabilityRiskLevel'] ?? 'Pending'}',
            '${record['trustTier'] ?? record['trustLevel'] ?? 'standard'} / ${record['rank'] ?? record['riderRank'] ?? 'unranked'}\nHistory ${_historyCount(record['trustHistory']) + _historyCount(record['rankHistory'])}',
            '${record['lastReliabilityReason'] ?? _riderWarningSummary(record)}\nComplete ${_percent(record['completionRate'])} / Cancel ${_percent(record['cancellationRate'])}',
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

  Map<String, dynamic> _riderForApplication(Map<String, dynamic> application) {
    final id = '${application['riderId'] ?? application['uid'] ?? ''}'.trim();
    if (id.isEmpty) return const {};
    return riders.firstWhere(
      (rider) => _riderId(rider) == id,
      orElse: () => const {},
    );
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

class _MarketplaceRiskPanel extends StatefulWidget {
  const _MarketplaceRiskPanel({required this.query});

  final String query;

  @override
  State<_MarketplaceRiskPanel> createState() => _MarketplaceRiskPanelState();
}

class _MarketplaceRiskPanelState extends State<_MarketplaceRiskPanel> {
  Future<void> _review(
    BuildContext context,
    Map<String, dynamic> flag,
    String status,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review marketplace signal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Review reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (reason == null || reason.trim().isEmpty || !context.mounted) return;
    await FirebaseFunctions.instance
        .httpsCallable('reviewMarketplaceRiskFlag')
        .call({
      'flagId': '${flag['id'] ?? flag['flagId']}',
      'status': status,
      'resolution': reason.trim(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marketplace review recorded.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('marketplaceRiskFlags')
          .where('status', isEqualTo: 'OPEN')
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        final records = (snapshot.data?.docs ?? const [])
            .map((document) => {'id': document.id, ...document.data()})
            .toList(growable: false);
        return _RecordModule(
          title: 'Marketplace risk review',
          subtitle:
              'Review-only delivery and GPS signals. No flag automatically suspends a Rider or changes eligibility.',
          records: records,
          query: widget.query,
          fields: const [
            'id',
            'riderId',
            'deliveryId',
            'flagType',
            'severity',
            'status',
          ],
          columns: const [
            'Severity',
            'Signal',
            'Rider / Delivery',
            'Detected',
          ],
          row: (record) => [
            '${record['severity'] ?? 'AMBER'}',
            '${record['flagType'] ?? 'Operational review'}',
            '${record['riderId'] ?? 'Unknown Rider'}\n${record['deliveryId'] ?? 'Unknown delivery'}',
            _date(record['detectedAt']),
          ],
          actions: (record) => [
            _MiniAction(
              label: 'Dismiss',
              onPressed: () => _review(context, record, 'DISMISSED'),
            ),
            _MiniAction(
              label: 'Reviewed',
              onPressed: () => _review(context, record, 'REVIEWED'),
            ),
            _MiniAction(
              label: 'Action taken',
              onPressed: () => _review(context, record, 'ACTION_TAKEN'),
            ),
          ],
        );
      },
    );
  }
}

String _sectionStatusSummary(Map<String, dynamic> record) {
  final sections = record['sectionStatus'];
  if (sections is! Map || sections.isEmpty) return 'No section status';
  final complete = sections.values
      .where(
        (value) => {
          'submitted',
          'approved',
          'verified',
        }.contains('$value'.trim().toLowerCase()),
      )
      .length;
  return '$complete/${sections.length} sections complete';
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

class _DeliveryOperationsModule extends StatefulWidget {
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
  State<_DeliveryOperationsModule> createState() =>
      _DeliveryOperationsModuleState();
}

class _DeliveryOperationsModuleState extends State<_DeliveryOperationsModule> {
  String _attentionFilter = '';
  Map<String, dynamic>? _selectedDelivery;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final deliveries = widget.deliveries;
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
    final enhancedCustody =
        deliveries.where(_needsEnhancedCustodyReview).toList();
    final attentionCards = [
      _DeliveryAttentionData(
        title: 'Rider Offline',
        severity: 'Critical',
        icon: Icons.person_off_rounded,
        color: const Color(0xFFFF4D6D),
        records: deliveries.where(_deliveryNeedsRiderAttention).toList(),
        filter: 'rider_offline',
      ),
      _DeliveryAttentionData(
        title: 'Waiting >15 minutes',
        severity: 'High',
        icon: Icons.timer_rounded,
        color: const Color(0xFFF59E0B),
        records: deliveries.where(_isWaitingDelivery).toList(),
        filter: 'waiting',
      ),
      _DeliveryAttentionData(
        title: 'Vanguard Review',
        severity: 'Protected',
        icon: Icons.shield_rounded,
        color: const Color(0xFF8B5CF6),
        records: enhancedCustody,
        filter: 'vanguard',
      ),
      _DeliveryAttentionData(
        title: 'IRIS Review',
        severity: 'Review',
        icon: Icons.psychology_alt_rounded,
        color: const Color(0xFF7C3AED),
        records: deliveries.where(_deliveryNeedsIrisReview).toList(),
        filter: 'iris',
      ),
      _DeliveryAttentionData(
        title: 'Payment Issues',
        severity: 'Finance',
        icon: Icons.credit_card_off_rounded,
        color: const Color(0xFF38BDF8),
        records: deliveries.where(_deliveryHasPaymentIssue).toList(),
        filter: 'payment',
      ),
      _DeliveryAttentionData(
        title: 'Fraud Review',
        severity: 'Critical',
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFEF4444),
        records: deliveries.where(_deliveryNeedsFraudReview).toList(),
        filter: 'fraud',
      ),
    ];
    final tableRecords = _applyDeliveryAttentionFilter(
      deliveries,
      _attentionFilter,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DeliveryHeroPanel(
          selected: _selectedDelivery,
          onOpen: widget.onOpenDelivery,
          onSetStatus: widget.onSetDeliveryOperationStatus,
        ),
        const SizedBox(height: 18),
        _DeliveryNeedsAttentionPanel(
          cards: attentionCards,
          selectedFilter: _attentionFilter,
          onSelected: (filter) => setState(() {
            _attentionFilter = _attentionFilter == filter ? '' : filter;
          }),
        ),
        const SizedBox(height: 18),
        _DeliveryMetricPillGrid(
          metrics: [
            _DeliveryMetricData(
              'Active',
              active,
              Icons.bolt_rounded,
              const Color(0xFF22C55E),
            ),
            _DeliveryMetricData(
              'In Transit',
              active - waiting,
              Icons.route_rounded,
              const Color(0xFF38BDF8),
            ),
            _DeliveryMetricData(
              'Waiting',
              waiting,
              Icons.timer_rounded,
              const Color(0xFFFACC15),
            ),
            _DeliveryMetricData(
              'Vanguard',
              deliveries.where(_hasVanguardProtection).length,
              Icons.shield_rounded,
              const Color(0xFF8B5CF6),
            ),
            _DeliveryMetricData(
              'Health+',
              _countFlag(deliveries, 'health'),
              Icons.favorite_rounded,
              const Color(0xFFFF6B9A),
            ),
            _DeliveryMetricData(
              'Gifts',
              _countFlag(deliveries, 'gift'),
              Icons.card_giftcard_rounded,
              const Color(0xFFF59E0B),
            ),
            _DeliveryMetricData(
              'Business',
              _countFlag(deliveries, 'business'),
              Icons.business_center_rounded,
              const Color(0xFF60A5FA),
            ),
            _DeliveryMetricData(
              'No-show',
              noShow,
              Icons.person_off_rounded,
              const Color(0xFFEF4444),
            ),
            _DeliveryMetricData(
              'Archived',
              archived.length,
              Icons.inventory_2_rounded,
              const Color(0xFF94A3B8),
            ),
            _DeliveryMetricData(
              'Completed today',
              completedToday,
              Icons.verified_rounded,
              const Color(0xFF34D399),
            ),
            _DeliveryMetricData(
              'Cancelled today',
              cancelledToday,
              Icons.cancel_rounded,
              const Color(0xFFFF6B7A),
            ),
            _DeliveryMetricData(
              'Delayed',
              delayed,
              Icons.schedule_rounded,
              const Color(0xFFF97316),
            ),
            _DeliveryMetricData(
              'Recoverable',
              recoverable.length,
              Icons.settings_backup_restore_rounded,
              const Color(0xFFC084FC),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _LiveDeliveryMapPanel(deliveries: deliveries, riders: widget.riders),
        const SizedBox(height: 18),
        _DeliveryGlassSearchBanner(
          query: widget.query,
          activeFilter: _attentionFilter,
          onClearFilter: () => setState(() => _attentionFilter = ''),
        ),
        const SizedBox(height: 18),
        _DeliveryGlassList(
          title: 'Delivery Operations',
          subtitle:
              'Search by tracking id, sender, recipient, rider, business, phone, status, service, payment and review flags.',
          records: tableRecords,
          query: widget.query,
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
          selected: _selectedDelivery,
          onSelect: (record) => setState(() => _selectedDelivery = record),
          actions: (record) => _deliveryActions(
            record,
            canDuplicateDeliveries: widget.canDuplicateDeliveries,
            canEditDeliveries: widget.canEditDeliveries,
            onOpen: widget.onOpenDelivery,
            onDuplicate: widget.onDuplicateDelivery,
            onSetStatus: widget.onSetDeliveryOperationStatus,
            onResolveStaleDeliveryLock: widget.onResolveStaleDeliveryLock,
            onArchiveDelivery: widget.onArchiveDelivery,
          ),
        ),
        const SizedBox(height: 18),
        _DeliveryCommandCentre(
          delivery: _selectedDelivery,
          onOpen: widget.onOpenDelivery,
          onSetStatus: widget.onSetDeliveryOperationStatus,
        ),
        const SizedBox(height: 18),
        _EnhancedCustodyReviewPanel(
          records: enhancedCustody,
          query: widget.query,
          canEditDeliveries: widget.canEditDeliveries,
          onOpenDelivery: widget.onOpenDelivery,
          onSetStatus: widget.onSetDeliveryOperationStatus,
        ),
        const SizedBox(height: 18),
        _DeliveryArchiveBrowser(
          records: [...stale, ...recoverable, ...archived],
          query: widget.query,
          canEditDeliveries: widget.canEditDeliveries,
          onOpenDelivery: widget.onOpenDelivery,
          onResolveStaleDeliveryLock: widget.onResolveStaleDeliveryLock,
          onArchiveDelivery: widget.onArchiveDelivery,
        ),
      ],
    );
  }
}

class _DeliveryAttentionData {
  const _DeliveryAttentionData({
    required this.title,
    required this.severity,
    required this.icon,
    required this.color,
    required this.records,
    required this.filter,
  });

  final String title;
  final String severity;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> records;
  final String filter;
}

class _DeliveryMetricData {
  const _DeliveryMetricData(this.label, this.value, this.icon, this.color);

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _DeliveryHeroPanel extends StatelessWidget {
  const _DeliveryHeroPanel({
    required this.selected,
    required this.onOpen,
    required this.onSetStatus,
  });

  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final Future<void> Function(Map<String, dynamic>, String) onSetStatus;

  @override
  Widget build(BuildContext context) {
    final delivery = selected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _premiumDeliveryGlass(radius: 30),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          final intro = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF38BDF8).withValues(alpha: .14),
                      border: Border.all(
                        color: const Color(0xFF7DD3FC).withValues(alpha: .28),
                      ),
                    ),
                    child: const Icon(
                      Icons.radar_rounded,
                      color: Color(0xFFBAE6FD),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Premium Delivery Operations',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Live logistics command centre for investigation, recovery, tracking, IRIS, Vanguard, payments and audit review.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .68),
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
          final selectedCard = _DeliverySelectedSummary(
            delivery: delivery,
            onOpen: onOpen,
            onSetStatus: onSetStatus,
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [intro, const SizedBox(height: 18), selectedCard],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: intro),
              const SizedBox(width: 18),
              SizedBox(width: 430, child: selectedCard),
            ],
          );
        },
      ),
    );
  }
}

class _DeliverySelectedSummary extends StatelessWidget {
  const _DeliverySelectedSummary({
    required this.delivery,
    required this.onOpen,
    required this.onSetStatus,
  });

  final Map<String, dynamic>? delivery;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final Future<void> Function(Map<String, dynamic>, String) onSetStatus;

  @override
  Widget build(BuildContext context) {
    if (delivery == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: _premiumDeliveryGlass(radius: 22, opacity: .35),
        child: const Text(
          'Select a delivery to open the command centre.',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      );
    }
    final record = delivery!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _premiumDeliveryGlass(radius: 22, opacity: .42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _recordId(record).isEmpty
                      ? 'Selected delivery'
                      : _recordId(record),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _DeliveryStatusChip(_deliveryStatusLabel(record)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _deliveryRouteLabel(record),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: .70)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _GiftCompactAction(
                label: 'View',
                onPressed: () => onOpen(record),
              ),
              _GiftCompactAction(
                label: 'Escalate',
                onPressed: () => unawaited(onSetStatus(record, 'escalated')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeliveryNeedsAttentionPanel extends StatelessWidget {
  const _DeliveryNeedsAttentionPanel({
    required this.cards,
    required this.selectedFilter,
    required this.onSelected,
  });

  final List<_DeliveryAttentionData> cards;
  final String selectedFilter;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Needs Attention',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1320
                ? 6
                : constraints.maxWidth >= 980
                    ? 3
                    : constraints.maxWidth >= 620
                        ? 2
                        : 1;
            final width =
                (constraints.maxWidth - ((columns - 1) * 12)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: width,
                    child: _DeliveryAttentionCard(
                      data: card,
                      selected: card.filter == selectedFilter,
                      onTap: () => onSelected(card.filter),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DeliveryAttentionCard extends StatelessWidget {
  const _DeliveryAttentionCard({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _DeliveryAttentionData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest = data.records.isEmpty
        ? 'No active cases'
        : 'Latest ${_date(data.records.first['updatedAt'] ?? data.records.first['createdAt'])}';
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: _premiumDeliveryGlass(
          radius: 24,
          glow: data.color,
          selected: selected,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(data.icon, color: data.color, size: 22),
                const Spacer(),
                _DeliveryStatusChip(data.severity),
              ],
            ),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              tween: Tween(end: data.records.length.toDouble()),
              duration: const Duration(milliseconds: 260),
              builder: (context, value, _) => Text(
                value.round().toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data.title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              latest,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: .56)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryMetricPillGrid extends StatelessWidget {
  const _DeliveryMetricPillGrid({required this.metrics});

  final List<_DeliveryMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final metric in metrics)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: _premiumDeliveryGlass(radius: 999, glow: metric.color),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(metric.icon, color: metric.color, size: 18),
                const SizedBox(width: 9),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: metric.value.toDouble()),
                  duration: const Duration(milliseconds: 240),
                  builder: (context, value, _) => Text(
                    value.round().toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  metric.label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .72),
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

class _DeliveryGlassSearchBanner extends StatelessWidget {
  const _DeliveryGlassSearchBanner({
    required this.query,
    required this.activeFilter,
    required this.onClearFilter,
  });

  final String query;
  final String activeFilter;
  final VoidCallback onClearFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _premiumDeliveryGlass(radius: 24),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Color(0xFF7DD3FC)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              query.trim().isEmpty
                  ? 'Use the global Admin search to filter deliveries.'
                  : 'Searching deliveries for "$query"',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const Icon(Icons.tune_rounded, color: Color(0xFFC4B5FD), size: 19),
          if (activeFilter.isNotEmpty) ...[
            const SizedBox(width: 10),
            _GiftCompactAction(label: 'Clear filter', onPressed: onClearFilter),
          ],
        ],
      ),
    );
  }
}

class _DeliveryGlassList extends StatelessWidget {
  const _DeliveryGlassList({
    required this.title,
    required this.subtitle,
    required this.records,
    required this.query,
    required this.fields,
    required this.selected,
    required this.onSelect,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> records;
  final String query;
  final List<String> fields;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final List<Widget> Function(Map<String, dynamic>) actions;

  @override
  Widget build(BuildContext context) {
    final filtered = adminSearch(records, query, fields);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _premiumDeliveryGlass(radius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _DeliveryStatusChip('${filtered.length} records'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withValues(alpha: .62)),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            const _DeliveryPremiumEmptyState(
              title: 'No deliveries currently require review.',
              message:
                  'When a delivery matches this search or attention filter, it will appear here with route, status and recovery actions.',
            )
          else
            for (final record in filtered.take(90)) ...[
              _DeliveryGlassRow(
                record: record,
                selected: _recordId(selected ?? const {}) == _recordId(record),
                onTap: () => onSelect(record),
                actions: actions(record),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _DeliveryGlassRow extends StatelessWidget {
  const _DeliveryGlassRow({
    required this.record,
    required this.selected,
    required this.onTap,
    required this.actions,
  });

  final Map<String, dynamic> record;
  final bool selected;
  final VoidCallback onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final primary = actions.isNotEmpty ? actions.first : null;
    final secondary = actions.length > 2 ? actions[2] : null;
    final overflow =
        actions.length > 1 ? actions.skip(1).toList() : const <Widget>[];
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: _premiumDeliveryGlass(
          radius: 22,
          selected: selected,
          glow: _deliveryStatusColor(record),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 820;
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _recordId(record).isEmpty
                            ? 'Delivery'
                            : _recordId(record),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _DeliveryStatusChip(_deliveryStatusLabel(record)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _deliveryRouteLabel(record),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: .72)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final flag in _deliveryFlagSummary(record).split(', '))
                      _DeliveryStatusChip(flag),
                  ],
                ),
              ],
            );
            final actionRail = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (primary != null) primary,
                if (secondary != null) secondary,
                _GiftMoreMenu(
                  actions: overflow.whereType<_MiniAction>().toList(),
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [content, const SizedBox(height: 12), actionRail],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: content),
                const SizedBox(width: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: actionRail,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeliveryCommandCentre extends StatelessWidget {
  const _DeliveryCommandCentre({
    required this.delivery,
    required this.onOpen,
    required this.onSetStatus,
  });

  final Map<String, dynamic>? delivery;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final Future<void> Function(Map<String, dynamic>, String) onSetStatus;

  @override
  Widget build(BuildContext context) {
    if (delivery == null) {
      return const _DeliveryPremiumEmptyState(
        title: 'Select a delivery to open the command centre.',
        message:
            'Overview, timeline, live tracking, IRIS, Vanguard, payment, chat, GPS, media, audit and notes appear here.',
      );
    }
    final record = delivery!;
    final proof = proofOfDeliveryFromRecord(record);
    final sections = <(String, IconData, List<String>)>[
      (
        'Overview',
        Icons.space_dashboard_rounded,
        [
          'Sender: ${record['senderName'] ?? record['senderEmail'] ?? 'Not recorded'}',
          'Recipient: ${record['recipientName'] ?? record['recipientPhone'] ?? 'Not recorded'}',
        ],
      ),
      (
        'Timeline',
        Icons.timeline_rounded,
        [
          'Booking -> Accepted -> Collected -> Waiting -> Delivered -> Completed',
          'Updated ${_date(record['updatedAt'] ?? record['createdAt'])}',
        ],
      ),
      ('Live Tracking', Icons.route_rounded, [_locationSummary(record)]),
      (
        'IRIS',
        Icons.psychology_alt_rounded,
        [
          '${record['irisReviewStatus'] ?? record['reviewType'] ?? 'No review open'}',
          'Confidence ${record['confidence'] ?? record['irisConfidence'] ?? 'Not recorded'}',
        ],
      ),
      (
        'Vanguard',
        Icons.shield_rounded,
        [
          _hasVanguardProtection(record)
              ? 'Vanguard enabled'
              : 'Vanguard not enabled',
          _enhancedCustodyStatus(record),
        ],
      ),
      (
        'Proof of Delivery',
        Icons.fact_check_rounded,
        proof.hasAnyProof
            ? [
                proof.statusLabel,
                if (proof.hasPhoto) 'Delivery photo attached',
                ...proof.visibleRows.map((row) => '${row.$1}: ${row.$2}'),
                if (proof.vanguardIncomplete)
                  'Vanguard proof incomplete - review required',
              ]
            : [
                'Proof missing',
                'Proof of delivery is not available for this delivery.',
              ],
      ),
      (
        'Payment',
        Icons.payments_rounded,
        [
          '${record['paymentStatus'] ?? 'Payment status not recorded'}',
          _money(record['finalAmount'] ?? record['price']),
        ],
      ),
      (
        'Chat',
        Icons.forum_rounded,
        [
          'Conversation ${record['conversationId'] ?? record['chatId'] ?? 'Not linked'}',
        ],
      ),
      ('GPS', Icons.gps_fixed_rounded, [_locationSummary(record)]),
      (
        'Media',
        Icons.photo_library_rounded,
        [
          '${_historyCount(record, const [
                'evidence',
                'photos',
                'images'
              ])} media item(s)',
        ],
      ),
      (
        'Audit Log',
        Icons.history_rounded,
        [
          '${_historyCount(record, const [
                'auditTrail',
                'adminAuditTrail',
                'timeline'
              ])} audit item(s)',
        ],
      ),
      (
        'Notes',
        Icons.note_alt_rounded,
        ['${record['adminNotes'] ?? record['notes'] ?? 'No notes loaded'}'],
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _premiumDeliveryGlass(radius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Delivery Command Centre',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              _GiftCompactAction(
                label: 'View',
                onPressed: () => onOpen(record),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1220
                  ? 4
                  : constraints.maxWidth >= 820
                      ? 2
                      : 1;
              final width =
                  (constraints.maxWidth - ((columns - 1) * 12)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final section in sections)
                    SizedBox(
                      width: width,
                      child: _DeliveryDetailGlassCard(section: section),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _AdminProofOfDeliveryPanel(proof: proof),
          const SizedBox(height: 14),
          _DeliveryTimeline(record: record),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in const [
                ('Escalate', 'escalated'),
                ('Waiting', 'waiting_review'),
                ('No-show', 'no_show_review'),
                ('Fraud', 'fraud_flagged'),
                ('Resolve', 'resolved'),
              ])
                _GiftCompactAction(
                  label: action.$1,
                  onPressed: () => unawaited(onSetStatus(record, action.$2)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeliveryDetailGlassCard extends StatelessWidget {
  const _DeliveryDetailGlassCard({required this.section});

  final (String, IconData, List<String>) section;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 142),
      padding: const EdgeInsets.all(16),
      decoration: _premiumDeliveryGlass(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(section.$2, color: const Color(0xFF7DD3FC), size: 20),
          const SizedBox(height: 10),
          Text(section.$1, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          for (final line in section.$3)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: .62)),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminProofOfDeliveryPanel extends StatelessWidget {
  const _AdminProofOfDeliveryPanel({required this.proof});

  final ProofOfDeliveryDetails proof;

  @override
  Widget build(BuildContext context) {
    final color = proof.statusLabel.toLowerCase().contains('available')
        ? const Color(0xFF34D399)
        : proof.statusLabel.toLowerCase().contains('review')
            ? const Color(0xFFFBBF24)
            : const Color(0xFFF87171);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _premiumDeliveryGlass(radius: 22, glow: color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_rounded, color: color, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Proof of Delivery',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
              _DeliveryStatusChip(proof.statusLabel),
            ],
          ),
          const SizedBox(height: 12),
          if (!proof.hasAnyProof)
            Text(
              'Proof of delivery is not available for this delivery.',
              style: TextStyle(color: Colors.white.withValues(alpha: .62)),
            )
          else ...[
            if (proof.hasPhoto) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: Image.network(
                    proof.photoUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 140,
                      alignment: Alignment.center,
                      color: Colors.white.withValues(alpha: .05),
                      child: const Text('Proof photo could not be loaded.'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (proof.vanguardIncomplete) ...[
              const Text(
                'Vanguard proof is incomplete and should be reviewed before dispute closure.',
                style: TextStyle(
                  color: Color(0xFFFBBF24),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final row in proof.visibleRows)
                  Container(
                    width: 260,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.$1,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .58),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          row.$2,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OperationalIncidentPanel extends StatelessWidget {
  const _OperationalIncidentPanel();

  Future<void> _act(
    BuildContext context,
    String callable,
    String incidentId, [
    String? reason,
  ]) async {
    await FirebaseFunctions.instance.httpsCallable(callable).call(
      <String, dynamic>{
        'incidentId': incidentId,
        if (reason != null) 'reason': reason,
      },
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Incident updated.')));
    }
  }

  Future<void> _resolve(BuildContext context, String incidentId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve incident'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Resolution reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty || !context.mounted) return;
    await _act(context, 'resolveOperationalIncident', incidentId, reason);
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('operationalIncidents')
        .where('status', whereIn: const ['OPEN', 'ACKNOWLEDGED'])
        .orderBy('detectedAt', descending: true)
        .limit(50)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final incidents = snapshot.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return DecoratedBox(
          decoration: _panelDecoration(),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active delivery incidents',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  incidents.isEmpty
                      ? 'No intervention-required incidents.'
                      : '${incidents.length} incident(s) need attention.',
                ),
                if (snapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('Incidents could not be loaded.'),
                  ),
                for (final document in incidents) ...[
                  const Divider(height: 24),
                  Builder(
                    builder: (context) {
                      final incident = document.data();
                      final severity = '${incident['severity'] ?? 'AMBER'}';
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: severity == 'RED'
                                ? const Color(0xFFF87171)
                                : const Color(0xFFFBBF24),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$severity · ${incident['incidentType'] ?? 'Delivery incident'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'Delivery ${incident['deliveryId'] ?? 'Unknown'} · ${incident['currentDeliveryState'] ?? 'Unknown state'}',
                                ),
                                Text(
                                  'Detected ${_date(incident['detectedAt'])} · Rider ${incident['assignedRider'] ?? 'Not assigned'}',
                                ),
                              ],
                            ),
                          ),
                          if (incident['status'] == 'OPEN')
                            IconButton(
                              tooltip: 'Acknowledge',
                              onPressed: () => _act(
                                context,
                                'acknowledgeOperationalIncident',
                                document.id,
                              ),
                              icon: const Icon(Icons.visibility_rounded),
                            ),
                          IconButton(
                            tooltip: 'Resolve',
                            onPressed: () => _resolve(context, document.id),
                            icon: const Icon(Icons.check_circle_rounded),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DeliveryTimeline extends StatefulWidget {
  const _DeliveryTimeline({required this.record});

  final Map<String, dynamic> record;

  @override
  State<_DeliveryTimeline> createState() => _DeliveryTimelineState();
}

class _DeliveryTimelineState extends State<_DeliveryTimeline> {
  static const _pageSize = 50;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _events = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = true;
  bool _hasMore = true;

  String get _deliveryId =>
      '${widget.record['id'] ?? widget.record['requestId'] ?? ''}'.trim();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_deliveryId.isEmpty || !_hasMore) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('deliveryRequests')
        .doc(_deliveryId)
        .collection('timeline')
        .orderBy('timestamp', descending: true)
        .limit(_pageSize);
    if (_cursor != null) query = query.startAfterDocument(_cursor!);
    final page = await query.get();
    if (!mounted) return;
    setState(() {
      _events.addAll(page.docs);
      _cursor = page.docs.isEmpty ? _cursor : page.docs.last;
      _hasMore = page.docs.length == _pageSize;
      _loading = false;
    });
  }

  IconData _icon(String eventType) {
    if (eventType.contains('Payment') || eventType.contains('Refund')) {
      return Icons.payments_rounded;
    }
    if (eventType.contains('Notification') || eventType.contains('Chat')) {
      return Icons.notifications_active_rounded;
    }
    if (eventType.contains('Evidence') || eventType.contains('Verification')) {
      return Icons.fact_check_rounded;
    }
    if (eventType.contains('Incident')) return Icons.warning_amber_rounded;
    if (eventType.contains('Completed')) return Icons.check_circle_rounded;
    return Icons.route_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _premiumDeliveryGlass(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operational Timeline',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          if (_loading && _events.isEmpty) const LinearProgressIndicator(),
          if (!_loading && _events.isEmpty)
            const Text(
              'No operational events have been projected for this delivery.',
            ),
          for (final eventDocument in _events.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _icon(
                      '${eventDocument.data()['eventType'] ?? eventDocument.data()['event'] ?? ''}',
                    ),
                    color: const Color(0xFF7DD3FC),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${eventDocument.data()['eventType'] ?? eventDocument.data()['event'] ?? 'Operational event'}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_date(eventDocument.data()['timestamp'] ?? eventDocument.data()['createdAt'])} · ${eventDocument.data()['actorType'] ?? 'system'} · ${eventDocument.data()['source'] ?? 'backend'}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .62),
                            fontSize: 12,
                          ),
                        ),
                        if (eventDocument.data()['previousState'] != null ||
                            eventDocument.data()['newState'] != null)
                          Text(
                            '${eventDocument.data()['previousState'] ?? '—'} → ${eventDocument.data()['newState'] ?? '—'}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .72),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_hasMore)
            TextButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('Load earlier events'),
            ),
        ],
      ),
    );
  }
}

class _DeliveryArchiveBrowser extends StatelessWidget {
  const _DeliveryArchiveBrowser({
    required this.records,
    required this.query,
    required this.canEditDeliveries,
    required this.onOpenDelivery,
    required this.onResolveStaleDeliveryLock,
    required this.onArchiveDelivery,
  });

  final List<Map<String, dynamic>> records;
  final String query;
  final bool canEditDeliveries;
  final ValueChanged<Map<String, dynamic>> onOpenDelivery;
  final Future<void> Function(Map<String, dynamic>) onResolveStaleDeliveryLock;
  final Future<void> Function(Map<String, dynamic>) onArchiveDelivery;

  @override
  Widget build(BuildContext context) {
    final filtered = adminSearch(records, query, const [
      'id',
      'requestId',
      'trackingId',
      'status',
      'deliveryStatus',
      'adminArchiveStatus',
      'archiveReason',
    ]);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _premiumDeliveryGlass(radius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recoverable & Archived',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Stale Delivery Lock Queue, recoverable records and archive history with preview, restore path and audit context.',
            style: TextStyle(color: Colors.white.withValues(alpha: .62)),
          ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            const _DeliveryPremiumEmptyState(
              title: 'No archived deliveries currently require review.',
              message:
                  'Recoverable, stale and archived delivery records will appear here when present.',
            )
          else
            for (final record in filtered.take(40))
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 6),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                title: Text(
                  _recordId(record).isEmpty ? 'Delivery' : _recordId(record),
                ),
                subtitle: Text(_deliveryStatusLabel(record)),
                trailing: _DeliveryStatusChip(
                  '${record['adminArchiveStatus'] ?? record['archiveStatus'] ?? 'recoverable'}',
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _GiftCompactAction(
                          label: 'Preview',
                          onPressed: () => onOpenDelivery(record),
                        ),
                        if (canEditDeliveries && _isStaleDelivery(record))
                          _GiftCompactAction(
                            label: 'Restore',
                            onPressed: () =>
                                unawaited(onResolveStaleDeliveryLock(record)),
                          ),
                        if (canEditDeliveries && !_isArchivedDelivery(record))
                          _GiftCompactAction(
                            label: 'Archive',
                            onPressed: () =>
                                unawaited(onArchiveDelivery(record)),
                          ),
                        _DeliveryStatusChip(
                          'Audit ${_historyCount(record, const [
                                'auditTrail',
                                'adminAuditTrail'
                              ])}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

class _DeliveryPremiumEmptyState extends StatelessWidget {
  const _DeliveryPremiumEmptyState({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _premiumDeliveryGlass(radius: 24),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF38BDF8).withValues(alpha: .12),
              border: Border.all(
                color: const Color(0xFF7DD3FC).withValues(alpha: .24),
              ),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFBAE6FD),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(color: Colors.white.withValues(alpha: .62)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryStatusChip extends StatelessWidget {
  const _DeliveryStatusChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = _deliveryStatusTextColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .32)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .10), blurRadius: 14),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
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
          columns: const ['Conversation', 'Type', 'Last message', 'Updated'],
          row: (record) => [
            _chatConversationLabel(record),
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
                                : 'Replying to ${_chatConversationLabel(selectedChat!, selectedChatMessages)}',
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
                  : 'Timeline for ${_chatConversationLabel(selectedChat!, messages)}',
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
                    title: _chatSenderLabel(message),
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

String _chatSenderLabel(Map<String, dynamic> message) {
  final name =
      '${message['senderName'] ?? message['senderDisplayName'] ?? ''}'.trim();
  if (name.isNotEmpty) return name;
  final email = '${message['senderEmail'] ?? ''}'.trim();
  if (email.isNotEmpty) return email;
  final role = '${message['senderRole'] ?? message['senderType'] ?? ''}'
      .trim()
      .toLowerCase();
  if (role == 'admin' || role == 'support') return 'Circum Support';
  if (role == 'rider') return 'Rider';
  if (role == 'sender' || role == 'shipper' || role == 'user') return 'Sender';
  return 'Participant';
}

String _chatConversationLabel(
  Map<String, dynamic> chat, [
  List<Map<String, dynamic>> messages = const [],
]) {
  final senderName = _chatPartyName(chat, const [
        'senderName',
        'senderDisplayName',
        'customerName',
        'customerDisplayName',
        'bookedByName',
      ]) ??
      _chatMessagePartyName(messages, const ['sender', 'shipper', 'user']);
  final riderName = _chatPartyName(chat, const [
        'riderName',
        'driverName',
        'courierName',
        'riderDisplayName',
      ]) ??
      _chatMessagePartyName(messages, const ['rider', 'driver', 'courier']);
  final supportName = _chatMessagePartyName(messages, const [
    'admin',
    'support',
  ]);
  final type =
      '${chat['type'] ?? chat['conversationType'] ?? ''}'.trim().toLowerCase();

  if (senderName != null && riderName != null) {
    return '$senderName ↔ $riderName';
  }
  if (type == 'support' || supportName != null) {
    return '${senderName ?? riderName ?? 'Customer'} ↔ Circum Support';
  }
  return '${senderName ?? 'Sender'} ↔ ${riderName ?? 'Rider'}';
}

String? _chatPartyName(Map<String, dynamic> record, List<String> fields) {
  for (final field in fields) {
    final name = _safeChatDisplayName(record[field]);
    if (name != null) return name;
  }
  return null;
}

String? _chatMessagePartyName(
  List<Map<String, dynamic>> messages,
  List<String> roles,
) {
  for (final message in messages.reversed) {
    final role = '${message['senderRole'] ?? message['senderType'] ?? ''}'
        .trim()
        .toLowerCase();
    if (!roles.contains(role)) continue;
    final name = _safeChatDisplayName(
      message['senderName'] ?? message['senderDisplayName'],
    );
    if (name != null) return name;
  }
  return null;
}

String? _safeChatDisplayName(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  if (text.contains('@')) return null;
  if (RegExp(r'^[A-Za-z0-9_-]{18,}$').hasMatch(text)) return null;
  return text;
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
    final pinned =
        filtered.where((record) => record['pinned'] == true).toList();
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
  workflow('Gifts Workflow', Icons.inventory_2_rounded),
  campaigns('Campaigns', Icons.campaign_rounded),
  brandPartners('Brand Partners', Icons.storefront_rounded);

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
  _GiftsWorkspaceTab _tab = _GiftsWorkspaceTab.workflow;
  String _campaignFilter = '';
  String _priorityFilter = '';
  String _partnerFilter = '';
  String _staffFilter = '';
  String _storyFilter = '';
  String _stageFilter = '';
  String _matchFilter = '';
  bool _filtersVisible = true;
  Map<String, dynamic>? _selectedGift;

  @override
  Widget build(BuildContext context) {
    final query = widget.query.trim();
    final searchedGifts = adminSearch(widget.gifts, query, const [
      'id',
      'giftId',
      'storyId',
      'giftStoryId',
      'giftName',
      'title',
      'senderName',
      'senderEmail',
      'senderPhone',
      'senderPhoneNumber',
      'recipientName',
      'recipientEmail',
      'recipientPhone',
      'recipientPhoneNumber',
      'businessName',
      'campaign',
      'campaignName',
      'deliveryId',
      'occasion',
      'relationship',
      'story',
      'storyStatus',
      'status',
      'giftAdminStatus',
      'assignedCurator',
      'assignedStaff',
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
    final workflowGifts = filtered
        .where((gift) => !_isCampaignGiftRecord(gift))
        .toList(growable: false);
    final campaignGifts =
        filtered.where(_isCampaignGiftRecord).toList(growable: false);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              _GiftsWorkspaceTab.workflow => _giftWorkflowWorkspace(
                  workflowGifts,
                ),
              _GiftsWorkspaceTab.campaigns => _giftCampaignWorkspace(
                  campaignGifts,
                  filteredParticipants,
                  filteredMatches,
                ),
              _GiftsWorkspaceTab.brandPartners => _giftBrandPartnerWorkspace(
                  filteredBrands,
                ),
            },
          ),
        ),
      ],
    );
  }

  Widget _giftWorkflowWorkspace(List<Map<String, dynamic>> gifts) {
    final selected = _selectedGift != null &&
            gifts.any((gift) => _recordId(gift) == _recordId(_selectedGift!))
        ? _selectedGift!
        : gifts.isEmpty
            ? null
            : gifts.first;
    return Column(
      children: [
        _GiftWorkspaceHeader(
          title: 'People-Led Gifts Workspace',
          subtitle:
              'Concierge workspace organised around the sender, recipient, relationship, story, gift and delivery.',
          icon: Icons.inventory_2_rounded,
          metrics: [
            ('People Queue', gifts.where(_isGiftActive).length),
            ('IRIS Complete', gifts.where(_hasGiftIrisSignal).length),
            ('Stories', gifts.where(_hasGiftStory).length),
            ('Ready', gifts.where(_isGiftReadyForDispatch).length),
          ],
        ),
        const SizedBox(height: 18),
        _GiftPeopleLedWorkspace(
          gifts: gifts,
          selectedGift: selected,
          onEditGift: widget.onEditGiftRequest,
          onSelectGift: (gift) => setState(() => _selectedGift = gift),
          onUpdateGiftWorkflow: widget.onUpdateGiftWorkflow,
          onUpdateWorkspace: widget.onUpdateGiftWorkspace,
          onUpdateStoryAccess: widget.onUpdateGiftStoryAccess,
          onUpdateStoryMedia: widget.onUpdateGiftStoryMedia,
          canManage: widget.canManageIssues,
        ),
      ],
    );
  }

  Widget _giftCampaignWorkspace(
    List<Map<String, dynamic>> campaignGifts,
    List<Map<String, dynamic>> participants,
    List<Map<String, dynamic>> matches,
  ) {
    return Column(
      children: [
        _GiftWorkspaceHeader(
          title: 'Campaigns',
          subtitle:
              'Campaign creation, participants, matching, approvals, procurement, stories, brand allocations and reporting.',
          icon: Icons.campaign_rounded,
          metrics: [
            (
              'Active Campaigns',
              _campaignNames(campaignGifts, participants, matches).length,
            ),
            ('Participants', participants.length),
            (
              'Successful Matches',
              matches.where((m) => _giftMatchBucket(m) == 'approved').length,
            ),
            (
              'Pending Procurement',
              campaignGifts
                  .where(
                    (gift) =>
                        _giftProcurementSummary(gift) == 'No procurement plan',
                  )
                  .length,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _GiftActionBar(
          canManage: widget.canManageIssues,
          onBulkApprove: () => unawaited(
            widget.onBulkGiftCampaignAction(participants, 'approved'),
          ),
          onBulkReject: () => unawaited(
            widget.onBulkGiftCampaignAction(participants, 'rejected'),
          ),
          onAssign: () => unawaited(
            widget.onBulkGiftCampaignAction(participants, 'assign_later'),
          ),
          onExport: () => unawaited(
            widget.onBulkGiftCampaignAction(participants, 'exported'),
          ),
          onFilter: () => setState(() => _filtersVisible = !_filtersVisible),
          onNewCampaign: () => unawaited(widget.onEditGiftRequest({})),
          onInviteBrand: () => unawaited(widget.onEditGiftBrandPartner(null)),
        ),
        const SizedBox(height: 18),
        _giftCampaigns(campaignGifts),
        const SizedBox(height: 18),
        _giftParticipants(participants),
        const SizedBox(height: 18),
        _giftMatches(matches),
      ],
    );
  }

  Widget _giftBrandPartnerWorkspace(List<Map<String, dynamic>> brands) {
    return Column(
      children: [
        _GiftWorkspaceHeader(
          title: 'Brand Partners',
          subtitle:
              'Supplier directory, applications, products, catalogue availability, orders, invoices, contracts, ratings and performance.',
          icon: Icons.storefront_rounded,
          metrics: [
            ('Partners', brands.length),
            (
              'Approved',
              brands
                  .where(
                    (brand) => _hasAnyText(brand, const ['approved', 'active']),
                  )
                  .length,
            ),
            (
              'Awaiting Review',
              brands
                  .where(
                    (brand) => _hasAnyText(brand, const ['pending', 'review']),
                  )
                  .length,
            ),
            (
              'Catalogue Ready',
              brands
                  .where(
                    (brand) => _hasAnyText(brand, const [
                      'catalogue',
                      'inventory',
                      'available',
                    ]),
                  )
                  .length,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _GiftActionBar(
          canManage: widget.canManageIssues,
          onBulkApprove: () =>
              unawaited(widget.onBulkGiftCampaignAction(const [], 'approved')),
          onBulkReject: () =>
              unawaited(widget.onBulkGiftCampaignAction(const [], 'rejected')),
          onAssign: () => unawaited(
            widget.onBulkGiftCampaignAction(const [], 'assign_later'),
          ),
          onExport: () =>
              unawaited(widget.onBulkGiftCampaignAction(const [], 'exported')),
          onFilter: () => setState(() => _filtersVisible = !_filtersVisible),
          onNewCampaign: () => unawaited(widget.onEditGiftRequest({})),
          onInviteBrand: () => unawaited(widget.onEditGiftBrandPartner(null)),
          showCampaignActions: false,
          showReviewActions: false,
        ),
        const SizedBox(height: 18),
        _giftBrandPartners(brands),
      ],
    );
  }

  Widget _giftCampaigns(List<Map<String, dynamic>> records) {
    return _GiftGlassTable(
      title: 'Campaign Operations',
      subtitle:
          'Campaign matching, fulfilment, story, anonymous and escalation state.',
      emptyText: 'No campaign gifts match this search.',
      records: records,
      rowBuilder: (record) => _GiftTableRowData(
        status: '${record['giftAdminStatus'] ?? record['status'] ?? 'pending'}',
        title:
            '${record['campaignName'] ?? record['campaign'] ?? record['giftName'] ?? record['title'] ?? _recordId(record)}',
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
            '${record['displayName'] ?? record['recipientName'] ?? record['userId'] ?? _recordId(record)}',
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
                  '${record['campaignName'] ?? record['campaignId'] ?? _recordId(record)}',
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

  // ignore: unused_element
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
        title: '${record['giftName'] ?? record['title'] ?? _recordId(record)}',
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

  // ignore: unused_element
  Widget _giftWorkspace(List<Map<String, dynamic>> records) {
    return _GiftGlassTable(
      title: 'Workspace',
      subtitle:
          'Workspace status, IRIS recommendation, supplier, approval and progress.',
      emptyText: 'No Gift Team workspace records match this search.',
      records: records,
      rowBuilder: (record) => _GiftTableRowData(
        status: _giftWorkspaceStatus(record),
        title: '${record['giftName'] ?? record['title'] ?? _recordId(record)}',
        owner:
            '${record['procurementSupplier'] ?? record['merchantName'] ?? 'Supplier pending'}',
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
                  ('Supplier Pending', 'supplier_pending'),
                  ('Approval Pending', 'approval_pending'),
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

class _GiftPeopleLedWorkspace extends StatelessWidget {
  const _GiftPeopleLedWorkspace({
    required this.gifts,
    required this.selectedGift,
    required this.onSelectGift,
    required this.onEditGift,
    required this.onUpdateGiftWorkflow,
    required this.onUpdateWorkspace,
    required this.onUpdateStoryAccess,
    required this.onUpdateStoryMedia,
    required this.canManage,
  });

  final List<Map<String, dynamic>> gifts;
  final Map<String, dynamic>? selectedGift;
  final ValueChanged<Map<String, dynamic>> onSelectGift;
  final Future<void> Function(Map<String, dynamic>) onEditGift;
  final Future<void> Function(Map<String, dynamic>, String)
      onUpdateGiftWorkflow;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateWorkspace;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateStoryAccess;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateStoryMedia;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    if (gifts.isEmpty) {
      return const _GiftEmptyState(
        title: 'No gifts are currently in this stage.',
        message:
            'The People Queue will show each sender, recipient and gift request when records match the current filters.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final queue = _GiftPeopleQueue(
          gifts: gifts,
          selectedGift: selectedGift,
          onSelectGift: onSelectGift,
        );
        final workspace = _GiftPersonWorkspace(
          gift: selectedGift ?? gifts.first,
          canManage: canManage,
          onEditGift: onEditGift,
          onUpdateGiftWorkflow: onUpdateGiftWorkflow,
          onUpdateWorkspace: onUpdateWorkspace,
          onUpdateStoryAccess: onUpdateStoryAccess,
          onUpdateStoryMedia: onUpdateStoryMedia,
        );
        if (constraints.maxWidth < 1080) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [queue, const SizedBox(height: 18), workspace],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 372, child: queue),
            const SizedBox(width: 18),
            Expanded(child: workspace),
          ],
        );
      },
    );
  }
}

class _GiftPeopleQueue extends StatelessWidget {
  const _GiftPeopleQueue({
    required this.gifts,
    required this.selectedGift,
    required this.onSelectGift,
  });

  final List<Map<String, dynamic>> gifts;
  final Map<String, dynamic>? selectedGift;
  final ValueChanged<Map<String, dynamic>> onSelectGift;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(radius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt_rounded, color: Color(0xFF7DD3FC)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'People Queue',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              _GiftStatusChip('${gifts.length} requests'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Sender, recipient, relationship and story first. Search covers names, phone, email, Gift ID and Story ID.',
            style: TextStyle(color: Colors.white.withValues(alpha: .62)),
          ),
          const SizedBox(height: 14),
          for (final gift in gifts.take(80))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GiftPersonQueueCard(
                gift: gift,
                selected: _recordId(gift) == _recordId(selectedGift ?? {}),
                onTap: () => onSelectGift(gift),
              ),
            ),
        ],
      ),
    );
  }
}

class _GiftPersonQueueCard extends StatelessWidget {
  const _GiftPersonQueueCard({
    required this.gift,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> gift;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sender = _giftSenderName(gift);
    final recipient = _giftRecipientName(gift);
    return Semantics(
      button: true,
      label: 'Open gift request from $sender to $recipient',
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: selected
                  ? [
                      const Color(0xFF38BDF8).withValues(alpha: .18),
                      const Color(0xFFA78BFA).withValues(alpha: .10),
                    ]
                  : [
                      Colors.white.withValues(alpha: .060),
                      Colors.white.withValues(alpha: .030),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: selected
                  ? const Color(0xFF7DD3FC).withValues(alpha: .40)
                  : Colors.white.withValues(alpha: .09),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: .14),
                      blurRadius: 24,
                      offset: const Offset(0, 14),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _GiftPersonAvatar(
                    imageUrl: _giftSenderPhoto(gift),
                    label: sender,
                    icon: Icons.person_rounded,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Gift for',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .46),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_downward_rounded,
                    size: 18,
                    color: Color(0xFF7DD3FC),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _GiftPersonAvatar(
                    imageUrl: _giftRecipientPhoto(gift),
                    label: recipient,
                    icon: Icons.favorite_rounded,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipient,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '${gift['relationship'] ?? 'Relationship not recorded'} · ${gift['occasion'] ?? 'Occasion not recorded'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .62),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _GiftStatusChip(_giftBudgetSummary(gift)),
                  _GiftStatusChip(_giftIrisConfidenceSummary(gift)),
                  _GiftStatusChip(
                    '${gift['priority'] ?? gift['urgency'] ?? 'Standard'}',
                  ),
                  _GiftStatusChip(_giftWorkflowStatus(gift)),
                ],
              ),
              const SizedBox(height: 10),
              _GiftBoardMeta(label: 'Curator', value: _giftCurator(gift)),
              _GiftBoardMeta(label: 'Created', value: _date(gift['createdAt'])),
              _GiftBoardMeta(label: 'Story', value: _giftStorySummary(gift)),
              _GiftBoardMeta(
                label: 'Gift',
                value: _giftWorkspaceProgress(gift).join(' · '),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GiftPersonWorkspace extends StatelessWidget {
  const _GiftPersonWorkspace({
    required this.gift,
    required this.canManage,
    required this.onEditGift,
    required this.onUpdateGiftWorkflow,
    required this.onUpdateWorkspace,
    required this.onUpdateStoryAccess,
    required this.onUpdateStoryMedia,
  });

  final Map<String, dynamic> gift;
  final bool canManage;
  final Future<void> Function(Map<String, dynamic>) onEditGift;
  final Future<void> Function(Map<String, dynamic>, String)
      onUpdateGiftWorkflow;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateWorkspace;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateStoryAccess;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateStoryMedia;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GiftPersonWorkspaceHeader(
          gift: gift,
          canManage: canManage,
          onEditGift: onEditGift,
          onUpdateWorkspace: onUpdateWorkspace,
        ),
        const SizedBox(height: 14),
        _GiftWorkspaceTabStrip(),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final panels = [
              _GiftWorkspacePanel(
                title: 'People',
                icon: Icons.people_alt_rounded,
                children: _giftPeopleLines(gift),
              ),
              _GiftStudioPanel(
                gift: gift,
                canManage: canManage,
                onEditGift: onEditGift,
                onUpdateWorkspace: onUpdateWorkspace,
              ),
              _GiftStoryStudioPanel(
                gift: gift,
                canManage: canManage,
                onEditGift: onEditGift,
                onUpdateStoryAccess: onUpdateStoryAccess,
                onUpdateStoryMedia: onUpdateStoryMedia,
              ),
            ];
            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  for (final panel in panels) ...[
                    panel,
                    const SizedBox(height: 14),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: panels[0]),
                const SizedBox(width: 14),
                Expanded(child: panels[1]),
                const SizedBox(width: 14),
                Expanded(child: panels[2]),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final panels = [
              _GiftWorkspacePanel(
                title: 'IRIS Intelligence',
                icon: Icons.psychology_alt_rounded,
                children: _giftIrisLines(gift),
              ),
              _GiftTimelineWorkspacePanel(
                gift: gift,
                canManage: canManage,
                onUpdateGiftWorkflow: onUpdateGiftWorkflow,
                onUpdateWorkspace: onUpdateWorkspace,
              ),
              _GiftWorkspacePanel(
                title: 'Operations',
                icon: Icons.local_shipping_rounded,
                children: _giftOperationsLines(gift),
              ),
            ];
            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  for (final panel in panels) ...[
                    panel,
                    const SizedBox(height: 14),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: panels[0]),
                const SizedBox(width: 14),
                Expanded(child: panels[1]),
                const SizedBox(width: 14),
                Expanded(child: panels[2]),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _GiftPersonWorkspaceHeader extends StatelessWidget {
  const _GiftPersonWorkspaceHeader({
    required this.gift,
    required this.canManage,
    required this.onEditGift,
    required this.onUpdateWorkspace,
  });

  final Map<String, dynamic> gift;
  final bool canManage;
  final Future<void> Function(Map<String, dynamic>) onEditGift;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateWorkspace;

  @override
  Widget build(BuildContext context) {
    final sender = _giftSenderName(gift);
    final recipient = _giftRecipientName(gift);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _GiftPersonAvatar(
                      imageUrl: _giftSenderPhoto(gift),
                      label: sender,
                      icon: Icons.person_rounded,
                      large: true,
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sender,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Gift for',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .58),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          recipient,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  _GiftCompactAction(
                    label: 'Open workspace',
                    onPressed: () => unawaited(onEditGift(gift)),
                  ),
                  if (canManage)
                    _GiftCompactAction(
                      label: 'Mark ready',
                      onPressed: () => unawaited(
                        onUpdateWorkspace(gift, 'ready_for_delivery'),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _GiftStatusChip('${gift['occasion'] ?? 'Occasion not recorded'}'),
              _GiftStatusChip(_giftBudgetSummary(gift)),
              _GiftStatusChip(
                '${gift['deliveryDate'] ?? gift['deliveryWindow'] ?? gift['preferredDeliveryWindow'] ?? 'Delivery date not recorded'}',
              ),
              _GiftStatusChip(
                '${gift['priority'] ?? gift['urgency'] ?? 'Standard'}',
              ),
              _GiftStatusChip(_giftCurator(gift)),
              _GiftStatusChip(_giftWorkflowStatus(gift)),
            ],
          ),
        ],
      ),
    );
  }
}

class _GiftWorkspaceTabStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const tabs = [
      'Workspace',
      'Messages',
      'Internal Notes',
      'Timeline',
      'Audit Trail',
      'Files',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: _panelDecoration(radius: 20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final tab in tabs) _GiftStatusChip(tab)],
      ),
    );
  }
}

class _GiftWorkspacePanel extends StatelessWidget {
  const _GiftWorkspacePanel({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF7DD3FC)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final line in children)
            _GiftWorkspaceLine(label: line.$1, value: line.$2),
        ],
      ),
    );
  }
}

class _GiftStudioPanel extends StatelessWidget {
  const _GiftStudioPanel({
    required this.gift,
    required this.canManage,
    required this.onEditGift,
    required this.onUpdateWorkspace,
  });

  final Map<String, dynamic> gift;
  final bool canManage;
  final Future<void> Function(Map<String, dynamic>) onEditGift;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateWorkspace;

  @override
  Widget build(BuildContext context) {
    final lines = <(String, String)>[
      ('IRIS Suggestions', _giftIrisSelectionSummary(gift)),
      (
        'Curator Picks',
        '${gift['curatorPicks'] ?? gift['shortlist'] ?? 'Not added'}',
      ),
      (
        'Supplier Catalogue',
        '${gift['supplierCatalogue'] ?? gift['catalogue'] ?? 'Not selected'}',
      ),
      (
        'Shortlist',
        '${gift['shortlistStatus'] ?? gift['shortlist'] ?? 'Not added'}',
      ),
      (
        'Chosen Gift',
        '${gift['chosenGift'] ?? gift['giftName'] ?? gift['title'] ?? 'Not selected'}',
      ),
      (
        'Packaging',
        '${gift['packaging'] ?? gift['packagingStatus'] ?? 'Not selected'}',
      ),
      ('Ribbon', '${gift['ribbon'] ?? gift['ribbonStatus'] ?? 'Not selected'}'),
      ('Card', '${gift['cardStatus'] ?? gift['cardMessage'] ?? 'Not added'}'),
      (
        'Handwritten Note',
        '${gift['handwrittenNote'] ?? gift['noteStatus'] ?? 'Not added'}',
      ),
      ('Supplier', _giftProcurementSummary(gift)),
      (
        'Stock',
        '${gift['stockStatus'] ?? gift['inventoryStatus'] ?? 'Not confirmed'}',
      ),
      ('Procurement', _giftWorkspaceProgress(gift).join(' · ')),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFF7DD3FC)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Gift Creation Studio',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final line in lines)
            _GiftWorkspaceLine(label: line.$1, value: line.$2),
          if (canManage) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _GiftCompactAction(
                  label: 'Edit gift',
                  onPressed: () => unawaited(onEditGift(gift)),
                ),
                _GiftCompactAction(
                  label: 'Assign curator',
                  onPressed: () =>
                      unawaited(onUpdateWorkspace(gift, 'assigned')),
                ),
                _GiftCompactAction(
                  label: 'Quality review',
                  onPressed: () =>
                      unawaited(onUpdateWorkspace(gift, 'quality_review')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GiftStoryStudioPanel extends StatelessWidget {
  const _GiftStoryStudioPanel({
    required this.gift,
    required this.canManage,
    required this.onEditGift,
    required this.onUpdateStoryAccess,
    required this.onUpdateStoryMedia,
  });

  final Map<String, dynamic> gift;
  final bool canManage;
  final Future<void> Function(Map<String, dynamic>) onEditGift;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateStoryAccess;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateStoryMedia;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.video_camera_front_rounded, color: Color(0xFF7DD3FC)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Story Studio',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final line in _giftStoryStudioLines(gift))
            _GiftWorkspaceLine(label: line.$1, value: line.$2),
          if (canManage) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _GiftCompactAction(
                  label: 'Preview',
                  onPressed: () => unawaited(
                    onUpdateStoryMedia(gift, 'record_preview_event'),
                  ),
                ),
                _GiftCompactAction(
                  label: 'Retry render',
                  onPressed: () => unawaited(onUpdateStoryMedia(gift, 'retry')),
                ),
                _GiftCompactAction(
                  label: 'Regenerate link',
                  onPressed: () =>
                      unawaited(onUpdateStoryAccess(gift, 'regenerate')),
                ),
                _GiftCompactAction(
                  label: 'Edit story',
                  onPressed: () => unawaited(onEditGift(gift)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GiftTimelineWorkspacePanel extends StatelessWidget {
  const _GiftTimelineWorkspacePanel({
    required this.gift,
    required this.canManage,
    required this.onUpdateGiftWorkflow,
    required this.onUpdateWorkspace,
  });

  final Map<String, dynamic> gift;
  final bool canManage;
  final Future<void> Function(Map<String, dynamic>, String)
      onUpdateGiftWorkflow;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateWorkspace;

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('Created', 'new'),
      ('Matched', 'iris_complete'),
      ('Curator Assigned', 'assigned'),
      ('Gift Selected', 'gift_selected'),
      ('Purchased', 'supplier_pending'),
      ('Story Recorded', 'story_added'),
      ('Story Rendered', 'quality_review'),
      ('Packed', 'ready_for_delivery'),
      ('Ready', 'ready_for_delivery'),
      ('Collected', 'collected'),
      ('Delivered', 'delivered'),
      ('Recipient Viewed', 'recipient_viewed'),
      ('Archived', 'archived'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timeline_rounded, color: Color(0xFF7DD3FC)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Operations Timeline',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: canManage
                    ? () => unawaited(
                          step.$2 == 'archived'
                              ? onUpdateGiftWorkflow(gift, step.$2)
                              : onUpdateWorkspace(gift, step.$2),
                        )
                    : null,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF38BDF8).withValues(alpha: .88),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF38BDF8,
                            ).withValues(alpha: .20),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        step.$1,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (canManage)
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF7DD3FC),
                        size: 18,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GiftWorkspaceLine extends StatelessWidget {
  const _GiftWorkspaceLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final display =
        value.trim().isEmpty || value == 'null' ? 'Not recorded' : value.trim();
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
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            display,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .76),
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftPersonAvatar extends StatelessWidget {
  const _GiftPersonAvatar({
    required this.imageUrl,
    required this.label,
    required this.icon,
    this.large = false,
  });

  final String imageUrl;
  final String label;
  final IconData icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 58.0 : 42.0;
    return Semantics(
      image: true,
      label: label,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF38BDF8).withValues(alpha: .13),
          border: Border.all(
            color: const Color(0xFF7DD3FC).withValues(alpha: .28),
          ),
        ),
        child: imageUrl.isEmpty
            ? Icon(icon, color: const Color(0xFFBAE6FD), size: large ? 28 : 21)
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  icon,
                  color: const Color(0xFFBAE6FD),
                  size: large ? 28 : 21,
                ),
              ),
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
    this.showCampaignActions = true,
    this.showReviewActions = true,
  });

  final bool canManage;
  final VoidCallback onBulkApprove;
  final VoidCallback onBulkReject;
  final VoidCallback onAssign;
  final VoidCallback onExport;
  final VoidCallback onFilter;
  final VoidCallback onNewCampaign;
  final VoidCallback onInviteBrand;
  final bool showCampaignActions;
  final bool showReviewActions;

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
          if (showCampaignActions)
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
          if (showReviewActions)
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
            label: 'Utility',
            children: [
              _GiftCommandButton(
                label: 'Export',
                icon: Icons.download_rounded,
                onPressed: canManage ? onExport : null,
              ),
              _GiftCommandButton(
                label: 'Filter',
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

class _GiftWorkspaceHeader extends StatelessWidget {
  const _GiftWorkspaceHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.metrics,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<(String, int)> metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0EA5E9).withValues(alpha: .18),
            Colors.white.withValues(alpha: .055),
            const Color(0xFFA78BFA).withValues(alpha: .08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withValues(alpha: .10),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final titleBlock = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF7DD3FC).withValues(alpha: .14),
                  border: Border.all(
                    color: const Color(0xFF7DD3FC).withValues(alpha: .30),
                  ),
                ),
                child: Icon(icon, color: const Color(0xFFBAE6FD), size: 26),
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
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .70),
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final metricBlock = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              for (final metric in metrics)
                Container(
                  width: 150,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .10),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${metric.$2}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        metric.$1,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .62),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleBlock, const SizedBox(height: 18), metricBlock],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 18),
              Flexible(child: metricBlock),
            ],
          );
        },
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
        'No story',
        'Draft',
        'Approved',
        'Published',
        'Archived',
      ],
      stages: const [
        'New Gifts',
        'IRIS Complete',
        'Awaiting Curator',
        'Gift Selected',
        'Images Added',
        'Story Added',
        'Voice Note Added',
        'Quality Review',
        'Ready for Dispatch',
        'Completed',
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

// ignore: unused_element
class _GiftOperationsBoard extends StatelessWidget {
  const _GiftOperationsBoard({
    required this.gifts,
    required this.onEditGift,
    required this.onSelectGift,
    required this.onUpdateWorkspace,
    required this.canManage,
    required this.selectedGift,
  });

  final List<Map<String, dynamic>> gifts;
  final Future<void> Function(Map<String, dynamic>) onEditGift;
  final ValueChanged<Map<String, dynamic>> onSelectGift;
  final Future<void> Function(Map<String, dynamic>, String) onUpdateWorkspace;
  final bool canManage;
  final Map<String, dynamic>? selectedGift;

  @override
  Widget build(BuildContext context) {
    final lanes = <(String, List<Map<String, dynamic>>, String)>[
      (
        'New Gifts',
        gifts
            .where((record) => _giftWorkflowStage(record) == 'new_gifts')
            .toList(),
        'new_gifts',
      ),
      (
        'IRIS Complete',
        gifts
            .where((record) => _giftWorkflowStage(record) == 'iris_complete')
            .toList(),
        'iris_complete',
      ),
      (
        'Awaiting Curator',
        gifts
            .where((record) => _giftWorkflowStage(record) == 'awaiting_curator')
            .toList(),
        'awaiting_curator',
      ),
      (
        'Gift Selected',
        gifts
            .where((record) => _giftWorkflowStage(record) == 'gift_selected')
            .toList(),
        'gift_selected',
      ),
      (
        'Images Added',
        gifts
            .where((record) => _giftWorkflowStage(record) == 'images_added')
            .toList(),
        'images_added',
      ),
      (
        'Story Added',
        gifts
            .where((record) => _giftWorkflowStage(record) == 'story_added')
            .toList(),
        'story_added',
      ),
      (
        'Voice Note Added',
        gifts
            .where((record) => _giftWorkflowStage(record) == 'voice_note_added')
            .toList(),
        'voice_note_added',
      ),
      (
        'Quality Review',
        gifts
            .where((record) => _giftWorkflowStage(record) == 'quality_review')
            .toList(),
        'quality_review',
      ),
      (
        'Ready for Dispatch',
        gifts
            .where(
              (record) => _giftWorkflowStage(record) == 'ready_for_dispatch',
            )
            .toList(),
        'ready_for_dispatch',
      ),
      (
        'Completed',
        gifts
            .where((record) => _giftWorkflowStage(record) == 'completed')
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
            'Workspace Board',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Gift preparation queue organised from IRIS review through dispatch readiness.',
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
            'IRIS intelligence, recipient profile, story, voice, images and approval detail stay attached to each gift card.',
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
              'Clear.',
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
                        '${record['giftName'] ?? record['giftTitle'] ?? record['title'] ?? record['campaignName'] ?? record['displayName'] ?? _recordId(record)}',
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
                            '${record['campaignName'] ?? record['campaignId'] ?? record['campaign'] ?? 'Unassigned'}',
                      ),
                      _GiftBoardMeta(
                        label: 'Assigned staff',
                        value:
                            '${record['assignedStaff'] ?? record['assignedCurator'] ?? _mapValue(record['giftsTeamWorkspace'], 'assignedCurator') ?? 'Unassigned'}',
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
                        'ID ${_recordId(record)}',
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
                              label: 'Move',
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
              'Choose a card from the workflow board to review operational detail without leaving the workspace.',
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
                  '${gift['giftName'] ?? gift['title'] ?? gift['campaignName'] ?? _recordId(gift)}',
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
              'Occasion: ${gift['occasion'] ?? gift['relationship'] ?? 'Not recorded'}',
              'Budget: ${_giftBudgetSummary(gift)}',
              'Delivery window: ${gift['deliveryWindow'] ?? gift['preferredDeliveryWindow'] ?? gift['scheduledWindow'] ?? 'Not recorded'}',
              'Assigned staff: ${gift['assignedStaff'] ?? gift['assignedCurator'] ?? 'Awaiting assignment'}',
            ],
          ),
          _GiftDetailSection(
            title: 'IRIS Intelligence',
            lines: [
              _giftIrisSelectionSummary(gift),
              _giftIrisConfidenceSummary(gift),
              'Category: ${gift['category'] ?? gift['irisCategory'] ?? gift['giftCategory'] ?? 'Not recorded'}',
              'Exclusions: ${gift['allergies'] ?? gift['exclusions'] ?? gift['recipientExclusions'] ?? 'Not recorded'}',
            ],
          ),
          _GiftDetailSection(
            title: 'Recommended Gifts',
            lines: [
              'Recommendation: ${gift['irisGiftRecommendation'] ?? gift['recommendedGift'] ?? gift['giftSuggestion'] ?? 'Not recorded'}',
              'Interests: ${gift['interests'] ?? gift['recipientInterests'] ?? 'Not recorded'}',
              'Previous gifts: ${gift['previousGifts'] ?? gift['giftHistorySummary'] ?? 'Not recorded'}',
            ],
          ),
          _GiftDetailSection(
            title: 'Story Editor',
            lines: [
              _giftStorySummary(gift),
              'Story: ${gift['story'] ?? gift['storyDraft'] ?? gift['captionDraft'] ?? 'Story not added'}',
              'Visibility: ${gift['giftStorySharePrivacy'] ?? gift['contentUsageScope'] ?? 'private'}',
            ],
          ),
          _GiftDetailSection(
            title: 'Voice Notes',
            lines: [
              _giftVoiceSummary(gift),
              'Audio: ${_giftStoryAudioSummary(gift)}',
            ],
          ),
          _GiftDetailSection(
            title: 'Images',
            lines: [
              _giftImageSummary(gift),
              'Preview: ${gift['giftPreview'] ?? gift['giftImageUrl'] ?? gift['imageUrl'] ?? 'Not added'}',
            ],
          ),
          _GiftDetailSection(
            title: 'Timeline',
            lines: [
              'Created: ${_date(gift['createdAt'])}',
              'Updated: ${_date(gift['updatedAt'] ?? gift['createdAt'])}',
              'Deadline: ${gift['deadline'] ?? gift['deliveryDeadline'] ?? 'Not recorded'}',
            ],
          ),
          _GiftDetailSection(
            title: 'Delivery',
            lines: [
              'Delivery: ${gift['deliveryId'] ?? 'Not scheduled'}',
              'Status: ${gift['deliveryStatus'] ?? gift['status'] ?? 'Not recorded'}',
              'Window: ${gift['deliveryWindow'] ?? gift['preferredDeliveryWindow'] ?? 'Not recorded'}',
            ],
          ),
          _GiftDetailSection(
            title: 'Approval',
            lines: [
              'Approval: ${gift['approvalStatus'] ?? gift['approvedGiftPlan'] ?? 'Awaiting review'}',
              'Procurement: ${_giftProcurementSummary(gift)}',
              'Priority: ${gift['priority'] ?? gift['urgency'] ?? 'Standard'}',
            ],
          ),
          _GiftDetailSection(
            title: 'Audit',
            lines: [
              'Audit: ${gift['giftWorkspaceAuditTrail'] is List ? (gift['giftWorkspaceAuditTrail'] as List).length : 0} entries',
              'Sender notes: ${gift['senderNotes'] ?? gift['notes'] ?? 'Not recorded'}',
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
              message: 'Try a broader search or refresh the Admin data stream.',
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
          Checkbox(value: false, onChanged: (_) {}),
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
                _GiftMoreMenu(actions: data.menu),
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
    final enabledActions = actions
        .where((action) => action.onPressed != null)
        .toList(growable: false);
    return PopupMenuButton<int>(
      tooltip: 'More',
      enabled: enabledActions.isNotEmpty,
      color: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        for (var i = 0; i < enabledActions.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(
              enabledActions[i].label,
              style: const TextStyle(color: Colors.white),
            ),
          ),
      ],
      onSelected: (index) => enabledActions[index].onPressed!(),
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
    final logo = '${record['logoUrl'] ?? record['brandLogoUrl'] ?? ''}'.trim();
    return Container(
      constraints: const BoxConstraints(minHeight: 270),
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .08),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .12),
                  ),
                  image: logo.isEmpty
                      ? null
                      : DecorationImage(
                          image: NetworkImage(logo),
                          fit: BoxFit.cover,
                        ),
                ),
                child: logo.isEmpty
                    ? const Icon(
                        Icons.storefront_rounded,
                        color: Color(0xFFBAE6FD),
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  '${record['partnerName'] ?? record['brandName'] ?? _recordId(record)}',
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
            'Catalogue',
            '${record['category'] ?? record['categories'] ?? 'Uncategorised'}',
          ),
          _GiftCardMeta(
            'Campaigns',
            '${record['approvedFor'] ?? record['campaignName'] ?? 'No campaign association'}',
          ),
          _GiftCardMeta(
            'Response',
            '${record['responseTime'] ?? record['averageResponseTime'] ?? 'Not recorded'}',
          ),
          _GiftCardMeta(
            'Performance',
            '${record['performanceScore'] ?? record['rating'] ?? record['trustScore'] ?? 'Not recorded'}',
          ),
          _GiftCardMeta(
            'Inventory',
            '${record['inventoryStatus'] ?? record['availability'] ?? 'Not recorded'}',
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
  final status =
      '${record['status'] ?? record['matchStatus'] ?? ''}'.toLowerCase();
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
    values.add('Supplier Pending');
  }
  if (approval.isEmpty || approval.contains('pending')) {
    values.add('Approval Pending');
  }
  if (status.contains('ready')) values.add('Ready');
  if (status.contains('review')) values.add('Awaiting Review');
  if (status.contains('complete') || status.contains('delivered')) {
    values.add('Completed');
  }
  return values.isEmpty ? const ['Awaiting Review'] : values;
}

bool _isCampaignGiftRecord(Map<String, dynamic> record) {
  final type =
      '${record['anonymousGiftType'] ?? record['giftType'] ?? record['type'] ?? ''}'
          .toLowerCase();
  if (type.contains('campaign')) return true;
  return '${record['campaignId'] ?? record['campaignName'] ?? record['campaign'] ?? ''}'
      .trim()
      .isNotEmpty;
}

Set<String> _campaignNames(
  List<Map<String, dynamic>> gifts,
  List<Map<String, dynamic>> participants,
  List<Map<String, dynamic>> matches,
) {
  return {
    ..._distinctValues(gifts, 'campaignName'),
    ..._distinctValues(gifts, 'campaign'),
    ..._distinctValues(gifts, 'campaignId'),
    ..._distinctValues(participants, 'campaignName'),
    ..._distinctValues(participants, 'campaignId'),
    ..._distinctValues(matches, 'campaignName'),
    ..._distinctValues(matches, 'campaignId'),
  }..removeWhere((value) => value.trim().isEmpty);
}

bool _hasGiftIrisSignal(Map<String, dynamic> record) {
  return record['irisGiftRecommendation'] != null ||
      record['irisAnalysis'] != null ||
      record['iris'] != null ||
      '${record['irisConfidence'] ?? record['confidenceScore'] ?? ''}'
          .trim()
          .isNotEmpty;
}

bool _isGiftReadyForDispatch(Map<String, dynamic> record) {
  final stage = _giftWorkflowStage(record);
  return stage == 'ready_for_dispatch' || stage == 'completed';
}

String _giftWorkflowStatus(Map<String, dynamic> record) {
  return _giftWorkflowStage(record).replaceAll('_', ' ');
}

String _giftWorkflowStage(Map<String, dynamic> record) {
  final status = _giftWorkspaceStatus(record).toLowerCase();
  final progress = _giftWorkspaceProgress(record).join(' ').toLowerCase();
  if (status.contains('complete') ||
      status.contains('delivered') ||
      progress.contains('completed')) {
    return 'completed';
  }
  if (status.contains('ready') || progress.contains('ready')) {
    return 'ready_for_dispatch';
  }
  if (status.contains('quality') ||
      status.contains('approval') ||
      progress.contains('approval')) {
    return 'quality_review';
  }
  if (_hasGiftVoiceNote(record)) return 'voice_note_added';
  if (_hasGiftStory(record)) return 'story_added';
  if (_hasGiftImages(record)) return 'images_added';
  if ('${record['approvedGiftPlan'] ?? record['selectedGift'] ?? record['giftSelection'] ?? ''}'
      .trim()
      .isNotEmpty) {
    return 'gift_selected';
  }
  if ('${record['assignedStaff'] ?? record['assignedCurator'] ?? ''}'
      .trim()
      .isNotEmpty) {
    return 'awaiting_curator';
  }
  if (_hasGiftIrisSignal(record)) return 'iris_complete';
  return 'new_gifts';
}

String _giftBudgetSummary(Map<String, dynamic> record) {
  final value = record['budget'] ??
      record['giftBudget'] ??
      record['maxBudget'] ??
      record['budgetPence'];
  if (value is num) {
    final amount = value > 999 ? value / 100 : value;
    return _money(amount);
  }
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? 'Budget not recorded' : text;
}

String _giftIrisConfidenceSummary(Map<String, dynamic> record) {
  final value = record['irisConfidence'] ??
      record['confidenceScore'] ??
      _mapValue(record['iris'], 'confidence') ??
      _mapValue(record['irisAnalysis'], 'confidence');
  if (value is num) {
    final score = value <= 1 ? (value * 100).round() : value.round();
    return 'IRIS confidence $score%';
  }
  final text = '$value'.trim();
  return text.isEmpty || text == 'null'
      ? 'IRIS confidence not recorded'
      : 'IRIS confidence $text';
}

bool _hasGiftImages(Map<String, dynamic> record) {
  for (final key in const [
    'giftImageUrl',
    'imageUrl',
    'photoUrl',
    'giftStoryPhotoUrls',
    'imageUrls',
    'photos',
  ]) {
    final value = record[key];
    if (value is List && value.isNotEmpty) return true;
    if ('$value'.trim().isNotEmpty && '$value' != 'null') return true;
  }
  return false;
}

String _giftImageSummary(Map<String, dynamic> record) {
  final photos = record['giftStoryPhotoUrls'] ??
      record['imageUrls'] ??
      record['photos'] ??
      const [];
  if (photos is List && photos.isNotEmpty) return '${photos.length} images';
  return _hasGiftImages(record) ? 'Images added' : 'Images not added';
}

bool _hasGiftVoiceNote(Map<String, dynamic> record) {
  return '${record['giftStoryCustomAudioUrl'] ?? record['voiceNoteUrl'] ?? record['audioUrl'] ?? ''}'
      .trim()
      .isNotEmpty;
}

String _giftVoiceSummary(Map<String, dynamic> record) {
  if (_hasGiftVoiceNote(record)) return 'Voice note added';
  return 'Voice note not added';
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

String _giftSenderName(Map<String, dynamic> record) {
  return '${record['senderName'] ?? record['senderDisplayName'] ?? record['senderEmail'] ?? record['senderId'] ?? 'Sender not recorded'}';
}

String _giftRecipientName(Map<String, dynamic> record) {
  return '${record['recipientName'] ?? record['recipientDisplayName'] ?? record['recipientEmail'] ?? record['recipientPhone'] ?? 'Recipient not recorded'}';
}

String _giftSenderPhoto(Map<String, dynamic> record) {
  return '${record['senderPhotoUrl'] ?? record['senderAvatarUrl'] ?? record['senderImageUrl'] ?? ''}'
      .trim();
}

String _giftRecipientPhoto(Map<String, dynamic> record) {
  return '${record['recipientPhotoUrl'] ?? record['recipientAvatarUrl'] ?? record['recipientImageUrl'] ?? ''}'
      .trim();
}

String _giftCurator(Map<String, dynamic> record) {
  return '${record['assignedCurator'] ?? record['assignedStaff'] ?? _mapValue(record['giftsTeamWorkspace'], 'assignedCurator') ?? 'Awaiting assignment'}';
}

List<(String, String)> _giftPeopleLines(Map<String, dynamic> record) {
  return [
    ('Sender', _giftSenderName(record)),
    (
      'Sender Contact',
      '${record['senderEmail'] ?? record['senderPhone'] ?? record['senderPhoneNumber'] ?? 'Not recorded'}',
    ),
    ('Recipient', _giftRecipientName(record)),
    (
      'Recipient Contact',
      '${record['recipientEmail'] ?? record['recipientPhone'] ?? record['recipientPhoneNumber'] ?? 'Not recorded'}',
    ),
    ('Relationship', '${record['relationship'] ?? 'Not recorded'}'),
    (
      'Address',
      '${record['recipientAddress'] ?? record['dropoffAddress'] ?? record['deliveryAddress'] ?? 'Not recorded'}',
    ),
    (
      'Delivery Instructions',
      '${record['deliveryInstructions'] ?? record['recipientInstructions'] ?? 'Not recorded'}',
    ),
    ('Budget', _giftBudgetSummary(record)),
    (
      'Important Dates',
      '${record['deliveryDate'] ?? record['importantDate'] ?? record['deadline'] ?? 'Not recorded'}',
    ),
    (
      'Special Requests',
      '${record['specialRequests'] ?? record['senderNotes'] ?? record['notes'] ?? 'Not recorded'}',
    ),
    (
      'Preferences',
      '${record['preferences'] ?? record['recipientPreferences'] ?? record['interests'] ?? 'Not recorded'}',
    ),
    (
      'Restrictions',
      '${record['restrictions'] ?? record['exclusions'] ?? record['allergies'] ?? 'Not recorded'}',
    ),
    (
      'Previous Gifts',
      '${record['previousGifts'] ?? record['giftHistorySummary'] ?? 'Not recorded'}',
    ),
  ];
}

List<(String, String)> _giftIrisLines(Map<String, dynamic> record) {
  return [
    (
      'Recommended Gift',
      '${record['irisGiftRecommendation'] ?? record['recommendedGift'] ?? record['giftSuggestion'] ?? 'Not recorded'}',
    ),
    ('Confidence', _giftIrisConfidenceSummary(record)),
    (
      'Why It Matches',
      '${record['irisRationale'] ?? record['matchReason'] ?? record['whyItMatches'] ?? 'Not recorded'}',
    ),
    (
      'Recipient Interests',
      '${record['interests'] ?? record['recipientInterests'] ?? 'Not recorded'}',
    ),
    (
      'Avoid',
      '${record['avoid'] ?? record['exclusions'] ?? record['allergies'] ?? 'Not recorded'}',
    ),
    (
      'Risk Flags',
      '${record['riskFlags'] ?? record['irisRiskFlags'] ?? record['reviewReason'] ?? 'None recorded'}',
    ),
    (
      'Delivery Notes',
      '${record['deliveryNotes'] ?? record['deliveryInstructions'] ?? 'Not recorded'}',
    ),
    (
      'Handling Requirements',
      '${record['handlingRequirements'] ?? record['specialHandling'] ?? 'Standard handling'}',
    ),
  ];
}

List<(String, String)> _giftStoryStudioLines(Map<String, dynamic> record) {
  return [
    (
      'Story',
      '${record['story'] ?? record['storyDraft'] ?? record['captionDraft'] ?? 'Story not added'}',
    ),
    ('Voice Note', _giftVoiceSummary(record)),
    ('Photos', _giftImageSummary(record)),
    (
      'Video',
      '${record['giftStoryVideoStatus'] ?? record['videoStatus'] ?? 'Not rendered'}',
    ),
    (
      'Soundtrack',
      '${record['soundtrack'] ?? record['musicSelection'] ?? 'Not selected'}',
    ),
    (
      'Preview',
      '${record['previewUrl'] ?? record['giftStoryPreviewUrl'] ?? 'Not available'}',
    ),
    (
      'Gift Story Score',
      '${record['giftStoryScore'] ?? record['storyScore'] ?? 'Not scored'}',
    ),
    (
      'Render Status',
      '${record['renderStatus'] ?? record['giftStoryVideoStatus'] ?? 'Not rendered'}',
    ),
    (
      'Vault Status',
      '${record['vaultStatus'] ?? record['giftStoryVaultStatus'] ?? 'Not claimed'}',
    ),
    (
      'Story Timeline',
      '${record['storyTimelineStatus'] ?? record['timelineStatus'] ?? _giftStorySummary(record)}',
    ),
  ];
}

List<(String, String)> _giftOperationsLines(Map<String, dynamic> record) {
  return [
    (
      'Courier',
      '${record['courierName'] ?? record['riderName'] ?? 'Not assigned'}',
    ),
    (
      'Tracking',
      '${record['trackingId'] ?? record['deliveryId'] ?? 'Not scheduled'}',
    ),
    (
      'Delivery Window',
      '${record['deliveryWindow'] ?? record['preferredDeliveryWindow'] ?? 'Not recorded'}',
    ),
    (
      'Supplier',
      '${record['procurementSupplier'] ?? record['merchantName'] ?? 'Awaiting supplier'}',
    ),
    (
      'Purchase Status',
      '${record['purchaseStatus'] ?? record['procurementStatus'] ?? 'Not purchased'}',
    ),
    ('Gift Status', _giftWorkspaceProgress(record).join(' · ')),
    (
      'Dispatch Status',
      '${record['dispatchStatus'] ?? record['deliveryStatus'] ?? record['status'] ?? 'Not scheduled'}',
    ),
    ('Story Status', _giftStorySummary(record)),
    ('Ready Status', _giftWorkflowStatus(record)),
  ];
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
    if (lower == 'no story') return !_hasGiftStory(record);
    return summary.contains(lower) ||
        '${record['storyStatus'] ?? record['giftStoryVideoStatus'] ?? ''}'
            .toLowerCase()
            .contains(lower);
  }).where((record) {
    if (stage.isEmpty) return true;
    return _giftOperationalStage(record).toLowerCase() == stage.toLowerCase();
  }).where((record) {
    if (match.isEmpty) return true;
    final matched =
        '${record['suggestedParticipantId'] ?? record['matchedGiftId'] ?? record['brandName'] ?? record['partnerName'] ?? ''}'
                .trim()
                .isNotEmpty ||
            _giftMatchBucket(record) == 'approved';
    return match == 'Matched' ? matched : !matched;
  }).toList(growable: false);
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
  if (_giftWorkspaceProgress(record).contains('Approval Pending')) {
    return 'Awaiting Approval';
  }
  if (_hasGiftStory(record)) return 'Story Production';
  if (_giftIrisSelectionSummary(record).toLowerCase().contains('iris')) {
    return 'Gift Review';
  }
  if (_giftWorkspaceProgress(record).contains('Supplier Pending')) {
    return 'Supplier Pending';
  }
  if (_giftProcurementSummary(record) == 'No procurement plan') {
    return 'Needs Procurement';
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
            '${record['partnerName'] ?? record['brandName'] ?? _recordId(record)}\n${record['contactName'] ?? ''} ${record['contactEmail'] ?? ''}',
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
          title: 'Gift Team Workspace',
          subtitle:
              'Assignment, curation, supplier, experience, budget, IRIS review, approval and readiness controls.',
          records: records,
          query: '',
          fields: const [],
          columns: const ['Gift', 'Workspace', 'Procurement', 'IRIS'],
          row: (record) => [
            '${record['giftName'] ?? record['title'] ?? _recordId(record)}',
            _giftWorkspaceSummary(record),
            _giftProcurementSummary(record),
            _giftIrisSelectionSummary(record),
          ],
          actions: canManageIssues
              ? (record) => [
                    for (final action in const [
                      ('Assign', 'assigned'),
                      ('Curating', 'curating'),
                      ('Supplier pending', 'supplier_pending'),
                      ('Approval pending', 'approval_pending'),
                      ('Ready procurement', 'ready_for_procurement'),
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
                      onPressed: () => unawaited(
                          onUpdateGiftStoryMedia(record, 'regenerate')),
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
    final today =
        auditLogs.where((log) => _isSameDay(log, DateTime.now())).length;
    final approvals = auditLogs
        .where((log) => _hasAnyText(log, const ['approve', 'approved']))
        .length;
    final suspensions =
        auditLogs.where((log) => _hasAnyText(log, const ['suspend'])).length;
    final refunds =
        auditLogs.where((log) => _hasAnyText(log, const ['refund'])).length;
    final overrides =
        auditLogs.where((log) => _hasAnyText(log, const ['override'])).length;
    final escalations =
        auditLogs.where((log) => _hasAnyText(log, const ['escalat'])).length;
    final critical =
        auditLogs.where((log) => _auditSeverity(log) == 'critical').length;

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
    final activeServices =
        platformStatus.where((record) => _platformEnabled(record)).length;
    final maintenance = platformConfig
        .where((record) => record['maintenanceMode'] == true)
        .length;
    final activeNotices =
        platformNotices.where((record) => _platformPublished(record)).length;
    final failedNotifications =
        notifications.where(_notificationNeedsRetry).length;
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
              'version records',
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
              'Existing configuration records only. Operational control remains centralised.',
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
          subtitle: 'Existing platform service and status records.',
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
          subtitle: 'Admin and platform version records.',
          records: platformVersions,
          query: '',
          fields: const ['id', 'version', 'build', 'environment', 'surface'],
          columns: const ['Surface', 'Version', 'Release', 'Environment'],
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
              'Platform notification history, push delivery status, failure handling and Admin retry.',
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
            'correlationId',
            'retryCount',
            'pushProvider',
            'lastDeliveryAttemptAt',
          ],
          columns: const ['Notification', 'Delivery', 'Retry', 'Last attempt'],
          row: (record) => [
            '${record['title'] ?? record['type'] ?? record['id']}',
            '${record['deliveryState'] ?? record['deliveryStatus'] ?? 'persisted'} / ${record['pushDeliveryStatus'] ?? 'unknown'}',
            '${record['pushProvider'] ?? 'push'} / ${record['retryCount'] ?? record['deliveryAttempts'] ?? 0}',
            '${_date(record['lastDeliveryAttemptAt'] ?? record['updatedAt'] ?? record['createdAt'])} · ${record['failureReason'] ?? record['correlationId'] ?? 'No issue recorded'}',
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
                    'Create role-based access records. Passwords and employee credentials stay protected.',
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
              'Historical broadcast workflow using the existing announcement system.',
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

class _GovernanceOperationsModule extends StatelessWidget {
  const _GovernanceOperationsModule({
    required this.rateLimits,
    required this.senderDrafts,
    required this.riderPresence,
    required this.users,
    required this.riders,
    required this.deliveries,
    required this.payments,
    required this.wallets,
    required this.businessInvoices,
    required this.businessAccounts,
    required this.healthPlusPickups,
    required this.recurringPickupSchedules,
    required this.giftOrders,
    required this.giftRequests,
    required this.giftCampaignMatches,
    required this.irisEvidence,
    required this.irisCanonicalObjects,
    required this.irisLearningCases,
    required this.notifications,
    required this.chats,
    required this.auditLogs,
    required this.query,
    required this.canRecover,
    required this.onGovernanceAction,
    required this.onPipelineHealthReset,
    required this.onOperationsHealthScan,
    required this.onOperationsHealthRepair,
    required this.onLiveDeliveryDiagnostics,
    required this.onRetryNotificationDelivery,
    required this.onOpenDelivery,
  });

  final List<Map<String, dynamic>> rateLimits;
  final List<Map<String, dynamic>> senderDrafts;
  final List<Map<String, dynamic>> riderPresence;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> riders;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> businessInvoices;
  final List<Map<String, dynamic>> businessAccounts;
  final List<Map<String, dynamic>> healthPlusPickups;
  final List<Map<String, dynamic>> recurringPickupSchedules;
  final List<Map<String, dynamic>> giftOrders;
  final List<Map<String, dynamic>> giftRequests;
  final List<Map<String, dynamic>> giftCampaignMatches;
  final List<Map<String, dynamic>> irisEvidence;
  final List<Map<String, dynamic>> irisCanonicalObjects;
  final List<Map<String, dynamic>> irisLearningCases;
  final List<Map<String, dynamic>> notifications;
  final List<Map<String, dynamic>> chats;
  final List<Map<String, dynamic>> auditLogs;
  final String query;
  final bool canRecover;
  final Future<void> Function(Map<String, dynamic>, String) onGovernanceAction;
  final Future<void> Function() onPipelineHealthReset;
  final Future<void> Function() onOperationsHealthScan;
  final Future<void> Function() onOperationsHealthRepair;
  final Future<void> Function() onLiveDeliveryDiagnostics;
  final Future<void> Function(Map<String, dynamic>) onRetryNotificationDelivery;
  final ValueChanged<Map<String, dynamic>> onOpenDelivery;

  @override
  Widget build(BuildContext context) {
    final stuckDeliveries = deliveries
        .where(
          (record) =>
              _isStaleDelivery(record) ||
              _containsGovernanceSignal(record, const [
                'stuck',
                'orphan',
                'duplicate',
                'invalid_state',
                'tracking_failed',
                'tracking_stalled',
                'recovery_requested',
              ]),
        )
        .toList(growable: false);
    final failedNotifications = notifications
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'failed',
            'retry',
            'stuck',
            'error',
            'undelivered',
          ]),
        )
        .toList(growable: false);
    final senderIssues = users
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'sender',
            'failed',
            'blocked',
            'locked',
            'onboarding',
            'notification',
            'payment',
            'wallet',
          ]),
        )
        .toList(growable: false);
    final riderIssues = riders
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'failed',
            'blocked',
            'locked',
            'suspended',
            'verification',
            'onboarding',
            'stripe',
            'payout',
          ]),
        )
        .toList(growable: false);
    final draftIssues = senderDrafts
        .where(
          (record) =>
              _containsGovernanceSignal(record, const [
                'corrupt',
                'restore_failed',
                'restore_error',
                'blocked',
                'expired',
              ]) ||
              senderDrafts.length <= 120,
        )
        .toList(growable: false);
    final businessIssues = businessAccounts
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'pending',
            'failed',
            'blocked',
            'role',
            'membership',
            'onboarding',
            'invoice',
            'suspended',
          ]),
        )
        .toList(growable: false);
    final healthIssues = healthPlusPickups
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'failed',
            'blocked',
            'escalat',
            'custody',
            'medication',
            'checkout',
            'review',
          ]),
        )
        .toList(growable: false);
    final paymentIssues = payments
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'failed',
            'blocked',
            'checkout',
            'webhook',
            'stripe',
            'requires_action',
            'reconcile',
          ]),
        )
        .toList(growable: false);
    final walletIssues = wallets
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'failed',
            'blocked',
            'frozen',
            'mismatch',
            'reconcile',
            'ledger',
          ]),
        )
        .toList(growable: false);
    final invoiceIssues = businessInvoices
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'failed',
            'blocked',
            'overdue',
            'invoice',
            'subscription',
            'payment',
          ]),
        )
        .toList(growable: false);
    final scheduleIssues = recurringPickupSchedules
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'failed',
            'blocked',
            'paused',
            'schedule',
            'recurring',
          ]),
        )
        .toList(growable: false);
    final giftIssues = [...giftOrders, ...giftRequests]
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'failed',
            'blocked',
            'campaign',
            'procurement',
            'supplier',
            'story',
            'delivery',
          ]),
        )
        .toList(growable: false);
    final matchingIssues = giftCampaignMatches
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'failed',
            'blocked',
            'matching',
            'unmatched',
            'review',
          ]),
        )
        .toList(growable: false);
    final irisIssues = [...irisEvidence, ...irisLearningCases]
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'failed',
            'blocked',
            'review',
            'override',
            'weight',
            'learning',
            'classif',
          ]),
        )
        .toList(growable: false);
    final canonicalIssues = irisCanonicalObjects
        .where(
          (record) => _containsGovernanceSignal(record, const [
            'candidate',
            'pending',
            'review',
            'promote',
          ]),
        )
        .toList(growable: false);
    final recentGovernanceAudit = auditLogs
        .where(
          (record) => '${record['actionType'] ?? ''}'.toLowerCase().contains(
                'governance_',
              ),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AdminModuleIntro(
          title: 'Operations Centre',
          subtitle:
              'Observe, investigate, recover and resolve operational issues without impersonating users or editing private preferences.',
        ),
        const SizedBox(height: 14),
        const _OperationalIncidentPanel(),
        const SizedBox(height: 14),
        DecoratedBox(
          decoration: _panelDecoration(),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Operations Health Centre',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Continuous production health, deterministic repair, deployment gate and live delivery diagnostics with immutable audit.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: canRecover
                          ? () => unawaited(onOperationsHealthScan())
                          : null,
                      icon: const Icon(Icons.monitor_heart_rounded),
                      label: const Text('Operations Health Scan'),
                    ),
                    OutlinedButton.icon(
                      onPressed: canRecover
                          ? () => unawaited(onOperationsHealthRepair())
                          : null,
                      icon: const Icon(Icons.build_circle_rounded),
                      label: const Text('Health Repair'),
                    ),
                    OutlinedButton.icon(
                      onPressed: canRecover
                          ? () => unawaited(onPipelineHealthReset())
                          : null,
                      icon: const Icon(Icons.health_and_safety_rounded),
                      label: const Text('Pipeline Health Reset'),
                    ),
                    OutlinedButton.icon(
                      onPressed: canRecover
                          ? () => unawaited(onLiveDeliveryDiagnostics())
                          : null,
                      icon: const Icon(Icons.route_rounded),
                      label: const Text('Live Delivery Diagnostics'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard('Production health', 'Scan', 'PASS / WARNING / FAIL'),
            _MetricCard(
              'Address limits',
              '${rateLimits.length}',
              'Search throttling',
            ),
            _MetricCard('Drafts', '${senderDrafts.length}', 'Sender recovery'),
            _MetricCard(
              'Rider presence',
              '${riderPresence.length}',
              'Live availability',
            ),
            _MetricCard(
              'Delivery recovery',
              '${stuckDeliveries.length}',
              'Tracking/lifecycle',
            ),
            _MetricCard(
              'Payments',
              '${paymentIssues.length}',
              'Checkout/ledger recovery',
            ),
            _MetricCard(
              'Gifts',
              '${giftIssues.length + matchingIssues.length}',
              'Campaign recovery',
            ),
            _MetricCard(
              'IRIS',
              '${irisIssues.length + canonicalIssues.length}',
              'Review recovery',
            ),
            _MetricCard(
              'Notifications',
              '${failedNotifications.length}',
              'Retry queue',
            ),
            _MetricCard(
              'Audit',
              '${recentGovernanceAudit.length}',
              'Recovery log',
            ),
          ],
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Address Search Governance',
          subtitle:
              'Search volume and throttle state. Reset is audited and does not expose internal documents to customers.',
          records: rateLimits,
          query: query,
          fields: const ['id', 'key', 'userId', 'count'],
          columns: const ['Limit', 'Usage', 'Window', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['count'] ?? 0}',
            _date(record['windowStart']),
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Reset',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'reset_address_rate_limit'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Sender Draft Recovery',
          subtitle:
              'View, restore, expire or delete abandoned drafts. Admin does not edit customer draft contents.',
          records: draftIssues,
          query: query,
          fields: const ['id', 'senderId', 'userId', 'status', 'draftId'],
          columns: const ['Draft', 'Sender', 'Status', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['senderId'] ?? record['userId'] ?? record['id']}',
            '${record['status'] ?? 'draft'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Restore',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'restore_sender_draft'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Expire',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'expire_sender_draft'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Delete',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'delete_sender_draft'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Sender Recovery',
          subtitle:
              'Account, onboarding, booking, payment, wallet and notification recovery. Admin cannot edit saved cards or preferences.',
          records: senderIssues,
          query: query,
          fields: const ['id', 'uid', 'email', 'status', 'role'],
          columns: const ['Sender', 'Status', 'Contact', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['status'] ?? record['accountStatus'] ?? 'active'}',
            '${record['email'] ?? record['phone'] ?? ''}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Recover account',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                          record,
                          'recover_sender_account_state',
                        ),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover onboarding',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_sender_onboarding'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Repair notifications',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                          record,
                          'recover_sender_notifications',
                        ),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Rider Presence Recovery',
          subtitle:
              'Live status, stale riders and ghost availability. Admin may force offline or reset presence with audit.',
          records: riderPresence,
          query: query,
          fields: const ['id', 'riderId', 'status', 'availabilityStatus'],
          columns: const ['Rider', 'Status', 'Dispatch', 'Updated'],
          row: (record) => [
            '${record['riderId'] ?? record['id']}',
            '${record['status'] ?? record['availabilityStatus'] ?? 'unknown'}',
            '${record['dispatchEligible'] ?? false}',
            _date(record['updatedAt'] ?? record['lastSeenAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Recover',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'force_rider_offline'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Restore',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'force_rider_online'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Reset',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'reset_rider_presence'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Repair',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                            record, 'reset_rider_dispatch_state'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Rider Recovery',
          subtitle:
              'Verification, onboarding, suspension, payout and stuck-job recovery. Every action requires Super Admin approval server-side.',
          records: riderIssues,
          query: query,
          fields: const ['id', 'riderId', 'email', 'status'],
          columns: const ['Rider', 'Status', 'Verification', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['status'] ?? record['accountStatus'] ?? 'review'}',
            '${record['verificationStatus'] ?? record['onboardingStatus'] ?? ''}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Recover verification',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                            record, 'recover_rider_verification'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Restore',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'restore_suspended_rider'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover payout',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_payout_state'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Delivery Tracking and Lifecycle',
          subtitle:
              'Stuck, orphaned, duplicate or stalled deliveries. Admin may request recovery, not directly edit GPS coordinates.',
          records: stuckDeliveries,
          query: query,
          fields: const [
            'id',
            'senderId',
            'riderId',
            'status',
            'deliveryStatus',
          ],
          columns: const ['Delivery', 'Sender', 'Status', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['senderId'] ?? record['userId'] ?? ''}',
            '${record['status'] ?? record['deliveryStatus'] ?? 'unknown'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Open',
                      onPressed: () => onOpenDelivery(record),
                    ),
                    _MiniAction(
                      label: 'Repair tracking',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'repair_tracking_state'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                            record, 'recover_delivery_lifecycle'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Resolve duplicate',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                            record, 'resolve_duplicate_delivery'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover orphan',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_orphan_delivery'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Reassign',
                      onPressed: () => unawaited(
                          onGovernanceAction(record, 'reassign_rider')),
                    ),
                    _MiniAction(
                      label: 'Reopen',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'reopen_delivery'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Repair custody',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'repair_custody_chain'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Business Recovery',
          subtitle:
              'Membership, role, invoice and onboarding records requiring operational review.',
          records: businessIssues,
          query: query,
          fields: const ['id', 'businessName', 'companyName', 'status'],
          columns: const ['Business', 'Status', 'Contact', 'Updated'],
          row: (record) => [
            '${record['businessName'] ?? record['companyName'] ?? record['id']}',
            '${record['status'] ?? record['verificationStatus'] ?? 'review'}',
            '${record['businessEmail'] ?? record['email'] ?? ''}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Recover',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                            record, 'recover_business_membership'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Repair team',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_business_team'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Repair permissions',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                          record,
                          'recover_business_permissions',
                        ),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover subscription',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                          record,
                          'recover_business_subscription',
                        ),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Business Invoice Recovery',
          subtitle:
              'Invoice and invitation recovery without changing pricing or payment calculations.',
          records: invoiceIssues,
          query: query,
          fields: const ['id', 'businessId', 'invoiceNumber', 'status'],
          columns: const ['Invoice', 'Business', 'Status', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['businessId'] ?? record['accountId'] ?? ''}',
            '${record['status'] ?? record['paymentStatus'] ?? 'review'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Recover invoice',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_business_invoice'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover invitation',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                            record, 'recover_business_invitation'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Health+ Recovery',
          subtitle:
              'Failed bookings, custody review, medication workflow escalation and checkout recovery.',
          records: healthIssues,
          query: query,
          fields: const ['id', 'patientName', 'status', 'custodyStatus'],
          columns: const ['Health+ record', 'Status', 'Custody', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['status'] ?? record['pickupStatus'] ?? 'review'}',
            '${record['custodyStatus'] ?? record['custodyReviewStatus'] ?? ''}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Escalate',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'escalate_health_plus'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover booking',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_health_booking'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Repair custody',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_health_custody'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover checkout',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_health_checkout'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Health+ Schedule Recovery',
          subtitle:
              'Recurring schedule recovery for paused, blocked or failed Health+ bookings.',
          records: scheduleIssues,
          query: query,
          fields: const ['id', 'patientName', 'status', 'scheduleStatus'],
          columns: const ['Schedule', 'Status', 'Cadence', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['status'] ?? record['scheduleStatus'] ?? 'review'}',
            '${record['cadence'] ?? record['frequency'] ?? ''}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Recover schedule',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_health_schedule'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Gifts Recovery',
          subtitle:
              'Campaign, procurement, supplier, story and gift delivery recovery using existing gift records.',
          records: giftIssues,
          query: query,
          fields: const ['id', 'giftId', 'campaignId', 'status'],
          columns: const ['Gift', 'Campaign', 'Status', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['campaignId'] ?? record['campaignName'] ?? ''}',
            '${record['status'] ?? record['giftStatus'] ?? 'review'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Recover campaign',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_gift_campaign'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover sourcing',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_gift_procurement'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover supplier',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_gift_supplier'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Restore story',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_gift_story'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Gift Matching Recovery',
          subtitle:
              'Matching state recovery without changing the matching engine or campaign rules.',
          records: matchingIssues,
          query: query,
          fields: const ['id', 'campaignId', 'matchStatus', 'status'],
          columns: const ['Match', 'Campaign', 'Status', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['campaignId'] ?? record['campaignName'] ?? ''}',
            '${record['matchStatus'] ?? record['status'] ?? 'review'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Recover matching',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_gift_matching'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Parcel Intelligence Recovery',
          subtitle:
              'Review, override review, reclassification, weight dispute and learning-job recovery. Decisions are never silently overwritten.',
          records: irisIssues,
          query: query,
          fields: const ['id', 'deliveryId', 'status', 'classification'],
          columns: const ['Review', 'Delivery', 'Status', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['deliveryId'] ?? record['requestId'] ?? ''}',
            '${record['status'] ?? record['reviewStatus'] ?? 'review'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Escalate',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'override_iris_review'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Reclassify',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'reclassify_iris'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Resolve weight',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                            record, 'resolve_iris_weight_dispute'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover learning',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_iris_learning_job'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Item Library Promotion',
          subtitle:
              'Canonical item promotion requests with audit trail and manual review.',
          records: canonicalIssues,
          query: query,
          fields: const ['id', 'name', 'status', 'category'],
          columns: const ['Item', 'Category', 'Status', 'Updated'],
          row: (record) => [
            '${record['name'] ?? record['label'] ?? record['id']}',
            '${record['category'] ?? record['itemCategory'] ?? ''}',
            '${record['status'] ?? 'review'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Promote',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'promote_iris_canonical'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Payment Recovery',
          subtitle:
              'Checkout, payment-session, webhook and Stripe-state investigation. Admin does not edit cards or pricing.',
          records: paymentIssues,
          query: query,
          fields: const ['id', 'paymentId', 'status', 'checkoutStatus'],
          columns: const ['Payment', 'Status', 'Amount', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['status'] ?? record['paymentStatus'] ?? 'review'}',
            '${record['amount'] ?? record['total'] ?? ''}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Retry checkout',
                      onPressed: () => unawaited(
                          onGovernanceAction(record, 'retry_checkout')),
                    ),
                    _MiniAction(
                      label: 'Recover session',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_payment_session'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Retry webhook',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'retry_payment_webhook'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Investigate',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'investigate_stripe_state'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Wallet Recovery',
          subtitle:
              'Ledger and balance reconciliation requests. Wallet calculations remain controlled by finance policy.',
          records: walletIssues,
          query: query,
          fields: const ['id', 'userId', 'status', 'balance'],
          columns: const ['Wallet', 'Owner', 'Status', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['userId'] ?? record['ownerId'] ?? ''}',
            '${record['status'] ?? record['walletStatus'] ?? 'review'}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Reconcile',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'reconcile_ledger'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Recover wallet',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                            record, 'recover_sender_wallet_state'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Notification Recovery',
          subtitle:
              'Failed or stuck delivery notifications. Admin may retry delivery but cannot control read receipts.',
          records: failedNotifications,
          query: query,
          fields: const [
            'id',
            'userId',
            'status',
            'type',
            'title',
            'failureReason',
            'correlationId',
            'retryCount',
          ],
          columns: const ['Notification', 'Delivery', 'Issue', 'Last attempt'],
          row: (record) => [
            '${record['title'] ?? record['type'] ?? record['id']}',
            '${record['deliveryState'] ?? record['deliveryStatus'] ?? 'pending'} / ${record['pushDeliveryStatus'] ?? 'unknown'}',
            '${record['failureReason'] ?? 'Awaiting retry'} · ${record['correlationId'] ?? 'No correlation recorded'}',
            _date(
              record['lastDeliveryAttemptAt'] ??
                  record['updatedAt'] ??
                  record['createdAt'],
            ),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Retry',
                      onPressed: () =>
                          unawaited(onRetryNotificationDelivery(record)),
                    ),
                    _MiniAction(
                      label: 'Replay',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'replay_notification'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Repair',
                      onPressed: () => unawaited(
                        onGovernanceAction(
                            record, 'rebuild_notification_queue'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Clear',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'clear_stuck_notification'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Chat Moderation and Recovery',
          subtitle:
              'Conversation visibility for moderation, legal hold and recovery. Typing indicators and read receipts remain user-owned.',
          records: chats,
          query: query,
          fields: const ['id', 'status', 'lastMessage', 'deliveryId'],
          columns: const ['Conversation', 'Status', 'Delivery', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['status'] ?? 'open'}',
            '${record['deliveryId'] ?? record['bookingId'] ?? ''}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Recover',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_chat_conversation'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Restore',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'restore_chat_messages'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Moderate',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'moderate_chat_abuse'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Export',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'export_chat_conversation'),
                      ),
                    ),
                    _MiniAction(
                      label: 'Escalate',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'place_chat_legal_hold'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Security Recovery',
          subtitle:
              'Account lock, unlock, reauthentication, session invalidation and access recovery. Admin cannot impersonate users.',
          records: users,
          query: query,
          fields: const ['id', 'uid', 'email', 'status', 'accountStatus'],
          columns: const ['Account', 'Status', 'Contact', 'Updated'],
          row: (record) => [
            _governanceLabel(record),
            '${record['status'] ?? record['accountStatus'] ?? 'active'}',
            '${record['email'] ?? record['phone'] ?? ''}',
            _date(record['updatedAt'] ?? record['createdAt']),
          ],
          actions: canRecover
              ? (record) => [
                    _MiniAction(
                      label: 'Resolve',
                      onPressed: () =>
                          unawaited(onGovernanceAction(record, 'force_logout')),
                    ),
                    _MiniAction(
                      label: 'Lock',
                      onPressed: () =>
                          unawaited(onGovernanceAction(record, 'lock_account')),
                    ),
                    _MiniAction(
                      label: 'Unlock',
                      onPressed: () => unawaited(
                          onGovernanceAction(record, 'unlock_account')),
                    ),
                    _MiniAction(
                      label: 'Restore',
                      onPressed: () =>
                          unawaited(onGovernanceAction(record, 'reset_mfa')),
                    ),
                    _MiniAction(
                      label: 'Recover access',
                      onPressed: () => unawaited(
                        onGovernanceAction(record, 'recover_account_access'),
                      ),
                    ),
                  ]
              : null,
        ),
        const SizedBox(height: 14),
        _RecoveryMatrixPanel(),
        const SizedBox(height: 14),
        _LegacyFunctionsPanel(),
        const SizedBox(height: 14),
        _RecordModule(
          title: 'Recovery Log',
          subtitle:
              'Audited recovery actions with actor, target, reason and result.',
          records: recentGovernanceAudit,
          query: query,
          fields: const ['actionType', 'actorEmail', 'targetId', 'reason'],
          columns: const ['Action', 'Target', 'Actor', 'Time'],
          row: (record) => [
            '${record['action'] ?? record['actionType']}',
            '${record['targetCollection'] ?? record['recordType']}/${record['targetId'] ?? record['recordId']}',
            '${record['actorEmail'] ?? record['adminEmail'] ?? record['adminUserId']}',
            _date(record['createdAt']),
          ],
        ),
      ],
    );
  }
}

class _LegacyFunctionsPanel extends StatelessWidget {
  const _LegacyFunctionsPanel();

  @override
  Widget build(BuildContext context) {
    final records = <Map<String, dynamic>>[
      {
        'function': 'RetrieveCardDetails',
        'classification': 'REPLACE',
        'reason': 'Legacy card lookup must remain outside Admin card control.',
      },
      {
        'function': 'calculateEarnings',
        'classification': 'REPLACE',
        'reason': 'Earnings should be governed by ledger and payout reviews.',
      },
      {
        'function': 'endTrip',
        'classification': 'REPLACE',
        'reason': 'Lifecycle completion must use audited delivery recovery.',
      },
    ];
    return _RecordModule(
      title: 'Legacy Function Classification',
      subtitle:
          'Classification only. No deletion or production function removal is performed here.',
      records: records,
      query: '',
      fields: const ['function', 'classification'],
      columns: const ['Function', 'Class', 'Reason'],
      row: (record) => [
        '${record['function']}',
        '${record['classification']}',
        '${record['reason']}',
      ],
    );
  }
}

class _RecoveryMatrixPanel extends StatelessWidget {
  const _RecoveryMatrixPanel();

  @override
  Widget build(BuildContext context) {
    final records = <Map<String, dynamic>>[
      {
        'object': 'Deliveries',
        'path':
            'Recover lifecycle, cancelled state, duplicates, orphan records, rider reassignment, reopen review, tracking and custody chain.',
        'authority': 'Super Admin callable with audit',
      },
      {
        'object': 'Riders',
        'path':
            'Force online/offline, reset presence, reset dispatch, recover verification, onboarding, payout and stuck jobs.',
        'authority': 'Super Admin callable with audit',
      },
      {
        'object': 'Senders',
        'path':
            'Recover booking, draft, failed payment state, wallet state, notifications, account state and onboarding.',
        'authority': 'Super Admin callable with audit',
      },
      {
        'object': 'Business',
        'path':
            'Recover memberships, team, permissions, invoices, invitations and subscriptions.',
        'authority': 'Super Admin callable with audit',
      },
      {
        'object': 'Health+',
        'path':
            'Recover booking, custody, medication workflow, checkout and recurring schedule.',
        'authority': 'Super Admin callable with audit',
      },
      {
        'object': 'Gifts',
        'path':
            'Recover campaign, matching, sourcing, supplier, stories and delivery chain.',
        'authority': 'Super Admin callable with audit',
      },
      {
        'object': 'Parcel Intelligence',
        'path':
            'Review, override review, reclassify, resolve weight disputes, promote canonical items and recover learning jobs.',
        'authority': 'Super Admin callable with audit',
      },
      {
        'object': 'Payments and Wallet',
        'path':
            'Retry checkout, recover sessions, retry webhook, reconcile ledger and investigate payment state.',
        'authority': 'Super Admin callable with audit',
      },
      {
        'object': 'Notifications',
        'path':
            'Replay, retry, repair queues and clear stuck delivery notices.',
        'authority': 'Super Admin callable with audit',
      },
      {
        'object': 'Chat',
        'path':
            'Recover conversations, restore failed threads, moderate abuse, export and legal hold.',
        'authority': 'Super Admin callable with audit',
      },
      {
        'object': 'Security',
        'path':
            'Force logout, invalidate sessions, lock, unlock, reset MFA and recover account access.',
        'authority': 'Super Admin callable with audit',
      },
    ];
    return _RecordModule(
      title: 'Recovery Matrix',
      subtitle:
          'Every operational object has a named recovery path. No raw record editing or user impersonation is exposed.',
      records: records,
      query: '',
      fields: const ['object', 'path', 'authority'],
      columns: const ['Object', 'Recovery path', 'Authority'],
      row: (record) => [
        '${record['object']}',
        '${record['path']}',
        '${record['authority']}',
      ],
    );
  }
}

String _governanceLabel(Map<String, dynamic> record) {
  return '${record['displayId'] ?? record['publicId'] ?? record['id'] ?? record['requestId'] ?? record['uid'] ?? 'Record'}';
}

bool _containsGovernanceSignal(
  Map<String, dynamic> record,
  List<String> signals,
) {
  final text = record.entries
      .where((entry) => entry.value is! Map && entry.value is! List)
      .map((entry) => '${entry.key}:${entry.value}')
      .join(' ')
      .toLowerCase();
  return signals.any(text.contains);
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
  final VoidCallback? onPressed;

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
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .9),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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
  final status =
      '${account['accountStatus'] ?? account['status'] ?? ''}'.toLowerCase();
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
    required this.applications,
    required this.documents,
    required this.onboardingEvents,
    required this.ratings,
    required this.supportTickets,
    required this.auditLogs,
    required this.onClose,
    required this.onSetStatus,
  });

  final Map<String, dynamic> rider;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> applications;
  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> onboardingEvents;
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
    final riderApplications = applications
        .where(
          (application) =>
              '${application['riderId'] ?? application['uid'] ?? ''}'.trim() ==
              riderId,
        )
        .toList(growable: false);
    final riderOnboardingEvents = onboardingEvents
        .where(
          (event) =>
              '${event['riderId'] ?? event['uid'] ?? ''}'.trim() == riderId,
        )
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
              title: 'Application Centre',
              rows: riderApplications.isEmpty
                  ? const [('Application', 'No application records loaded')]
                  : [
                      for (final application in riderApplications.take(3))
                        (
                          '${application['status'] ?? 'submitted'}',
                          '${application['fullName'] ?? application['id']} · ${_sectionStatusSummary(application)}',
                        ),
                      (
                        'Latest update',
                        _date(
                          riderApplications.first['updatedAt'] ??
                              riderApplications.first['createdAt'],
                        ),
                      ),
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
              title: 'Onboarding events',
              rows: riderOnboardingEvents.isEmpty
                  ? const [('Events', 'No onboarding events loaded')]
                  : [
                      for (final event in riderOnboardingEvents.take(6))
                        (
                          '${event['action'] ?? event['eventType'] ?? event['event'] ?? 'event'}',
                          '${event['status'] ?? event['applicationId'] ?? event['documentId'] ?? ''} · ${_date(event['createdAt'] ?? event['updatedAt'])}',
                        ),
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

BoxDecoration _premiumDeliveryGlass({
  double radius = 24,
  Color glow = const Color(0xFF38BDF8),
  bool selected = false,
  double opacity = .55,
}) {
  return BoxDecoration(
    color: const Color(0xFF12161F).withValues(alpha: opacity),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: selected
          ? glow.withValues(alpha: .42)
          : Colors.white.withValues(alpha: .08),
    ),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: selected ? .14 : .08),
        glow.withValues(alpha: selected ? .10 : .045),
        const Color(0xFF8B5CF6).withValues(alpha: .035),
        Colors.white.withValues(alpha: .035),
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: glow.withValues(alpha: selected ? .18 : .09),
        blurRadius: selected ? 36 : 24,
        offset: const Offset(0, 14),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: .26),
        blurRadius: 34,
        offset: const Offset(0, 18),
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

class _RecognitionSubject {
  const _RecognitionSubject({
    required this.id,
    required this.collection,
    required this.label,
  });

  final String id;
  final String collection;
  final String label;
}

_RecognitionSubject _recognitionSubject(Map<String, dynamic> record) {
  final collection = '${record['_recognitionCollection'] ?? 'users'}'.trim();
  final id =
      '${record['uid'] ?? record['userId'] ?? record['riderId'] ?? record['businessId'] ?? record['id'] ?? ''}'
          .trim();
  final label =
      '${record['fullName'] ?? record['name'] ?? record['businessName'] ?? record['companyName'] ?? record['email'] ?? id}'
          .trim();
  return _RecognitionSubject(
    id: id,
    collection: collection,
    label: label.isEmpty ? id : label,
  );
}

String _recognitionCollectionLabel(String collection) {
  return switch (collection) {
    'riderProfiles' || 'riders' => 'Rider',
    'businessAccounts' => 'Business',
    _ => 'Sender',
  };
}

List<String> _recognitionTypesFor(Map<String, dynamic> record) {
  final collection = _recognitionSubject(record).collection;
  return switch (collection) {
    'riderProfiles' || 'riders' => const ['foundingRider'],
    'businessAccounts' => const ['patron'],
    _ => const ['legend'],
  };
}

String _recognitionTypeLabel(String type) {
  return switch (type) {
    'foundingRider' => 'Founding Rider',
    'patron' => 'Patron',
    'legend' => 'Legend',
    _ => 'Recognition',
  };
}

String _recognitionSummary(Map<String, dynamic> record) {
  final values = <String>[
    if (record['isLegend'] == true)
      'Legend #${record['legendNumber'] ?? 'recorded'}',
    if (record['isFoundingRider'] == true)
      'Founding Rider #${record['foundingRiderNumber'] ?? 'recorded'}',
    if (record['isPatron'] == true)
      'Patron #${record['patronNumber'] ?? 'recorded'}',
  ];
  final recognitions = record['recognitions'];
  if (recognitions is Map) {
    for (final entry in recognitions.entries) {
      final value = entry.value;
      if (value is Map && value['awarded'] == true) {
        values.add(
          '${_recognitionTypeLabel('${entry.key}')} #${value['numberLabel'] ?? value['number'] ?? 'recorded'}',
        );
      }
    }
  }
  return values.isEmpty ? 'No recognition recorded' : values.join('\n');
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

String _healthPlanKey(Map<String, dynamic> record) {
  final value =
      '${record['subscriptionPlan'] ?? record['planType'] ?? record['healthPlusPlan'] ?? ''}'
          .trim()
          .toLowerCase();
  if (value.contains('priority')) return 'priority';
  if (value.contains('family')) return 'family';
  return 'basic';
}

String _healthPlanLabel(Map<String, dynamic> record) {
  final label = '${record['planLabel'] ?? ''}'.trim();
  if (label.isNotEmpty) return label;
  return switch (_healthPlanKey(record)) {
    'priority' => 'Health+ Priority',
    'family' => 'Health+ Family',
    _ => 'Health+ Basic',
  };
}

String _healthAllowanceLabel(Map<String, dynamic> record) {
  final unlimited = record['unlimitedPickups'] == true ||
      record['unlimitedDeliveries'] == true;
  if (unlimited) return 'Unlimited pickups / fair-use monitored';
  final included = record['includedPickups'] ?? record['includedDeliveries'];
  final used =
      record['usedPickupsThisCycle'] ?? record['usedDeliveriesThisCycle'] ?? 0;
  final remaining = record['remainingPickupsThisCycle'] ??
      record['remainingDeliveriesThisCycle'];
  if (included != null && remaining != null) {
    return '$remaining of $included pickups remaining';
  }
  if (included != null) return '$included pickups monthly / $used used';
  return 'Standard one-off pricing after allowance';
}

String _healthRenewalLabel(Map<String, dynamic> record) {
  final renewal = record['renewalDate'] ?? record['currentCycleEndsAt'];
  final text = _date(renewal);
  return text == 'Not recorded' ? 'Monthly reset tracked' : 'Renews $text';
}

String _healthFairUseLabel(Map<String, dynamic> record) {
  if (record['fairUseMonitored'] == true) return 'Fair-use review';
  return 'Allowance monitored';
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
  final text =
      '${record['status'] ?? record['deliveryStatus'] ?? ''}'.toLowerCase();
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
  final state =
      '${gift['giftAdminStatus'] ?? gift['status'] ?? ''}'.trim().toLowerCase();
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
  final values = [
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
  return values.isEmpty ? 'No story' : values.join(' / ');
}

String _giftWorkspaceSummary(Map<String, dynamic> gift) {
  final workspace = gift['giftsTeamWorkspace'];
  if (workspace is! Map) return 'No workspace recorded';
  final assignment = workspace['assignment'];
  final readiness = workspace['readiness'];
  final values = [
    if (assignment is Map) assignment['assignedCurator'],
    if (assignment is Map) assignment['status'],
    workspace['curationNotesUpdatedBy'],
    if (readiness is Map && readiness['readyForProcurement'] == true)
      'ready procurement',
    if (readiness is Map && readiness['readyForDelivery'] == true)
      'ready delivery',
  ]
      .map((value) => '$value'.trim())
      .where((value) => value.isNotEmpty && value != 'null')
      .toList();
  return values.isEmpty ? 'Workspace open' : values.join(' / ');
}

String _giftProcurementSummary(Map<String, dynamic> gift) {
  final workspace = gift['giftsTeamWorkspace'];
  final supplier = workspace is Map ? workspace['supplierWorkspace'] : null;
  final values = [
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
  return values.isEmpty ? 'No procurement plan' : values.join(' / ');
}

String _giftIrisSelectionSummary(Map<String, dynamic> gift) {
  final workspace = gift['giftsTeamWorkspace'];
  final collaboration =
      workspace is Map ? workspace['irisCollaboration'] : null;
  final plan = gift['approvedGiftPlan'];
  final values = [
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
  return values.isEmpty ? 'No IRIS gift review' : values.join(' / ');
}

String _giftStoryAudioSummary(Map<String, dynamic> gift) {
  final mix = gift['giftStoryAudioMix'];
  final values = [
    gift['giftStoryMusicSource'],
    gift['giftStoryCustomAudioUrl'] == null ? null : 'custom audio',
    gift['giftStoryIncludeSenderVoiceNote'] == true ? 'sender voice' : null,
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
  final links = [
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
  return '${record['approvalStatus'] ?? record['status'] ?? record['businessStatus'] ?? record['verificationStatus'] ?? ''}'
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

bool _isIrisReferralRecord(Map<String, dynamic> record) {
  final text = [
    record['irisStatus'],
    record['irisReviewStatus'],
    record['reviewType'],
    record['status'],
    record['complianceStatus'],
    record['serviceabilityStatus'],
    _mapValue(record['iris'], 'status'),
    _mapValue(_mapValue(record['iris'], 'compliance'), 'status'),
    _mapValue(_mapValue(record['iris'], 'serviceability'), 'status'),
  ].join(' ').toLowerCase();
  return text.contains('referral_required') ||
      text.contains('unsupported') ||
      text.contains('prohibited');
}

String _irisDecisionLabel(Map<String, dynamic> record) {
  final values = [
    record['irisStatus'],
    record['complianceStatus'],
    _mapValue(record['iris'], 'status'),
    _mapValue(_mapValue(record['iris'], 'compliance'), 'status'),
    record['serviceabilityStatus'],
    _mapValue(_mapValue(record['iris'], 'serviceability'), 'status'),
  ]
      .map((value) => '$value'.trim())
      .where((value) => value.isNotEmpty && value != 'null')
      .toList();
  return values.isEmpty ? 'Review required' : values.join(' / ');
}

String _irisDecisionText(String decision) {
  return switch (decision) {
    'allowed' => 'allowed',
    'referral_required' => 'referred',
    'unsupported' => 'unsupported',
    'prohibited' => 'prohibited',
    _ => 'reviewed',
  };
}

int _irisImageCount(Map<String, dynamic> record) {
  final images = [
    record['irisImages'],
    record['irisPhotoUrls'],
    record['imageUrls'],
    record['photos'],
    record['evidenceImages'],
  ];
  var count = 0;
  for (final value in images) {
    if (value is Iterable) count += value.length;
    if (value is String && value.trim().isNotEmpty) count += 1;
  }
  return count;
}

String _irisWeightSummary(Map<String, dynamic> record) {
  final values = [
    record['irisEstimatedWeight'],
    record['estimatedWeight'],
    record['declaredWeight'],
    record['verifiedWeight'],
    record['riderVerifiedWeight'],
    _mapValue(record['iris'], 'weight'),
    _mapValue(record['irisEstimate'], 'weight'),
  ]
      .map((value) => '$value'.trim())
      .where((value) => value.isNotEmpty && value != 'null')
      .toList();
  return values.isEmpty ? 'not recorded' : values.join(' / ');
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
  final proof = proofOfDeliveryFromRecord(delivery);
  if (_hasVanguardProtection(delivery)) flags.add('Vanguard');
  if (_isWaitingDelivery(delivery)) flags.add('Waiting');
  if (_isNoShowDelivery(delivery)) flags.add('No-show');
  if (_isCompletedDelivery(delivery)) flags.add(proof.statusLabel);
  if (proof.vanguardIncomplete) flags.add('Vanguard proof review');
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

List<Map<String, dynamic>> _applyDeliveryAttentionFilter(
  List<Map<String, dynamic>> deliveries,
  String filter,
) {
  return switch (filter) {
    'rider_offline' => deliveries.where(_deliveryNeedsRiderAttention).toList(),
    'waiting' => deliveries.where(_isWaitingDelivery).toList(),
    'vanguard' => deliveries.where(_needsEnhancedCustodyReview).toList(),
    'iris' => deliveries.where(_deliveryNeedsIrisReview).toList(),
    'payment' => deliveries.where(_deliveryHasPaymentIssue).toList(),
    'fraud' => deliveries.where(_deliveryNeedsFraudReview).toList(),
    _ => deliveries,
  };
}

bool _deliveryNeedsRiderAttention(Map<String, dynamic> delivery) {
  final text = [
    delivery['riderStatus'],
    delivery['driverStatus'],
    delivery['availability'],
    delivery['assignedRiderStatus'],
    delivery['adminOperationStatus'],
    delivery['status'],
  ].join(' ').toLowerCase();
  return _isActiveDelivery(delivery) &&
      (text.contains('offline') ||
          text.contains('unassigned') ||
          text.contains('rider_unavailable'));
}

bool _deliveryNeedsIrisReview(Map<String, dynamic> delivery) {
  final text = [
    delivery['irisReviewStatus'],
    delivery['reviewType'],
    delivery['irisStatus'],
    delivery['adminOperationStatus'],
  ].join(' ').toLowerCase();
  return text.contains('iris') ||
      text.contains('review') ||
      text.contains('referral') ||
      text.contains('unsupported') ||
      text.contains('prohibited');
}

bool _deliveryHasPaymentIssue(Map<String, dynamic> delivery) {
  final text = [
    delivery['paymentStatus'],
    delivery['paidState'],
    delivery['stripeStatus'],
    delivery['checkoutStatus'],
    delivery['adminOperationStatus'],
  ].join(' ').toLowerCase();
  return text.contains('fail') ||
      text.contains('declin') ||
      text.contains('refund') ||
      text.contains('dispute') ||
      text.contains('requires') ||
      text.contains('unpaid');
}

bool _deliveryNeedsFraudReview(Map<String, dynamic> delivery) {
  final text = [
    delivery['fraudStatus'],
    delivery['riskStatus'],
    delivery['trustStatus'],
    delivery['adminOperationStatus'],
    delivery['reviewType'],
    delivery['supportStatus'],
  ].join(' ').toLowerCase();
  return text.contains('fraud') ||
      text.contains('abuse') ||
      text.contains('risk') ||
      text.contains('suspicious');
}

String _deliveryStatusLabel(Map<String, dynamic> delivery) {
  final value =
      '${delivery['status'] ?? delivery['deliveryStatus'] ?? delivery['deliveryStage'] ?? 'unknown'}'
          .replaceAll('_', ' ')
          .trim();
  return value.isEmpty ? 'unknown' : value;
}

String _deliveryRouteLabel(Map<String, dynamic> delivery) {
  final pickup =
      '${delivery['pickupAddress'] ?? delivery['pickup'] ?? 'Pickup'}';
  final dropoff =
      '${delivery['dropoffAddress'] ?? delivery['dropoff'] ?? 'Drop-off'}';
  return '$pickup -> $dropoff';
}

Color _deliveryStatusColor(Map<String, dynamic> delivery) =>
    _deliveryStatusTextColor(_deliveryStatusLabel(delivery));

Color _deliveryStatusTextColor(String label) {
  final lower = label.toLowerCase();
  if (lower.contains('fraud') ||
      lower.contains('no-show') ||
      lower.contains('no_show') ||
      lower.contains('failed') ||
      lower.contains('cancel')) {
    return const Color(0xFFEF4444);
  }
  if (lower.contains('wait') || lower.contains('pending')) {
    return const Color(0xFFFBBF24);
  }
  if (lower.contains('recover') ||
      lower.contains('review') ||
      lower.contains('iris')) {
    return const Color(0xFFC084FC);
  }
  if (lower.contains('vanguard') || lower.contains('transit')) {
    return const Color(0xFF38BDF8);
  }
  if (lower.contains('archive')) return const Color(0xFF94A3B8);
  if (lower.contains('complete') || lower.contains('delivered')) {
    return const Color(0xFF34D399);
  }
  return const Color(0xFFE5E7EB);
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
