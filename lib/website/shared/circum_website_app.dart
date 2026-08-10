import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:circum/website/shared/delivery/proof_of_delivery.dart';
import 'package:circum/website/shared/health_plus/health_plus_pricing.dart';
import 'package:circum/website/shared/health_plus/pickup_status.dart';
import 'package:circum/website/shared/health_plus/recurring_pickup_schedule.dart';
import 'package:circum/website/shared/iris/iris_weight_estimator.dart';
import 'package:circum/website/shared/policies/booking_cancellation.dart';
import 'package:circum/website/shared/policies/driver_performance.dart';
import 'package:circum/website/shared/policies/gift_request_policy.dart';
import 'package:circum/website/shared/policies/rider_onboarding_policy.dart';
import 'package:circum/website/shared/policies/role_access.dart';
import 'package:circum/website/shared/policies/sender_profile.dart';
import 'package:circum/website/shared/policies/vanguard_protection.dart';
import 'package:circum/env/env.dart';
import 'package:circum/web_platform_routing.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/link.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import 'firebase/website_firebase_options.dart';
import 'pricing/website_delivery_pricing.dart';
import 'pricing/website_special_handling_engine.dart';

const _companyName = 'Circum';
const _webQuoteDistanceMiles = 4.8;
const _webVanguardAddOnPriceGbp = 1.99;
const _desktopWebBreakpoint = 760.0;
const _googlePlacesApiKey = String.fromEnvironment('GOOGLE_PLACES_API_KEY');
const _spectrumGradient = [
  Color(0xffff8c00),
  Color(0xfff80032),
  Color(0xffff00a0),
  Color(0xff8c28ff),
  Color(0xff0023ff),
  Color(0xff19a0ff),
];

enum _WebAppMode { landing, sender, rider, gifts, vanguard }

Future<void> _ensureCircumFirebaseReady() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  }
}

class CircumWebsiteApp extends StatefulWidget {
  const CircumWebsiteApp({super.key});

  @override
  State<CircumWebsiteApp> createState() => _CircumWebsiteAppState();
}

class _CircumWebsiteAppState extends State<CircumWebsiteApp> {
  bool _darkMode = true;
  late final CircumWebRouteResolution _initialRoute = resolveCircumWebRoute(
    Uri.base,
    adminHostingTarget: false,
    publicHostingHost: true,
  );
  late _WebAppMode _mode = _modeFromRoute(_initialRoute);
  late _SenderStep _senderInitialStep = _senderStepFromRoute(
    _initialRoute.senderEntry,
  );

  @override
  void initState() {
    super.initState();
    _redirectLegacyQueryIfNeeded();
    _logWebsiteVisit();
  }

  _WebAppMode _modeFromRoute(CircumWebRouteResolution route) {
    return switch (route.surface) {
      CircumWebSurface.public => _WebAppMode.landing,
      CircumWebSurface.sender => _WebAppMode.sender,
      CircumWebSurface.rider => _WebAppMode.rider,
      CircumWebSurface.gifts => _WebAppMode.gifts,
      CircumWebSurface.vanguard => _WebAppMode.vanguard,
      CircumWebSurface.admin => _WebAppMode.landing,
    };
  }

  _SenderStep _senderStepFromRoute(CircumSenderEntry entry) {
    return switch (entry) {
      CircumSenderEntry.dashboard => _SenderStep.dashboard,
      CircumSenderEntry.healthPlus => _SenderStep.healthPlus,
      CircumSenderEntry.business => _SenderStep.business,
      CircumSenderEntry.profile => _SenderStep.profile,
    };
  }

  Future<void> _redirectLegacyQueryIfNeeded() async {
    final path = _initialRoute.legacyRedirectPath;
    if (path == null || !kIsWeb) return;
    await _openCanonicalPath(path);
  }

  Future<void> _openCanonicalPath(String path) async {
    final target = _canonicalWebUri(path);
    final opened = await launchUrl(target, webOnlyWindowName: '_self');
    if (!opened) {
      debugPrint('Could not navigate to ${target.path}');
    }
  }

  static Uri _canonicalWebUri(String path) {
    return Uri.base.replace(path: path, queryParameters: {}, fragment: '');
  }

  Future<void> _openSurface(
    _WebAppMode mode, {
    _SenderStep senderStep = _SenderStep.dashboard,
  }) async {
    final path = switch (mode) {
      _WebAppMode.landing => '/',
      _WebAppMode.sender => switch (senderStep) {
          _SenderStep.healthPlus => '/send/health',
          _SenderStep.business => '/send/business',
          _SenderStep.profile => '/send/profile',
          _ => '/send',
        },
      _WebAppMode.rider => '/rider',
      _WebAppMode.gifts => '/gifts',
      _WebAppMode.vanguard => '/vanguard',
    };
    if (kIsWeb) {
      await _openCanonicalPath(path);
      return;
    }
    setState(() {
      _senderInitialStep = senderStep;
      _mode = mode;
    });
  }

  Future<void> _logWebsiteVisit() async {
    try {
      await _ensureCircumFirebaseReady();
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('recordWebsiteVisit').call({
        'url': Uri.base.toString(),
        'path': Uri.base.path,
        'query': Uri.base.queryParameters,
        'appMode': _mode.name,
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
              child: _surfaceStage(colors),
            ),
            _PlatformNotificationCenter(colors: colors, mode: _mode),
            _CompanyLiveChatButton(colors: colors),
          ],
        ),
      ),
    );
  }

  Widget _surfaceStage(_CircumColors colors) {
    return switch (_mode) {
      _WebAppMode.sender => _PhoneStage(
          key: const ValueKey(circumSenderWebIdentity),
          colors: colors,
          child: _CustomerPortal(
            darkMode: _darkMode,
            colors: colors,
            initialStep: _senderInitialStep,
            onBack: () => _openSurface(_WebAppMode.landing),
            onRoleSelected: _openRole,
            onGifts: () => _openSurface(_WebAppMode.gifts),
            onToggleTheme: () => setState(() => _darkMode = !_darkMode),
          ),
        ),
      _WebAppMode.rider => _PhoneStage(
          key: const ValueKey(circumRiderWebIdentity),
          colors: colors,
          child: _RiderEnrollmentPortal(
            darkMode: _darkMode,
            colors: colors,
            onBack: () => _openSurface(_WebAppMode.landing),
            onRoleSelected: _openRole,
            onToggleTheme: () => setState(() => _darkMode = !_darkMode),
          ),
        ),
      _WebAppMode.gifts => _GiftsRequestPage(
          key: const ValueKey('gifts-request'),
          colors: colors,
          onBack: () => _openSurface(_WebAppMode.landing),
        ),
      _WebAppMode.vanguard => _VanguardLandingPage(
          key: const ValueKey('vanguard-page'),
          colors: colors,
          onBack: () => _openSurface(_WebAppMode.landing),
        ),
      _WebAppMode.landing => _LandingPage(
          key: const ValueKey(circumPublicWebIdentity),
          colors: colors,
          darkMode: _darkMode,
          onStart: () => _openSurface(_WebAppMode.sender),
          onRider: () => _openSurface(_WebAppMode.rider),
          onHealthPlus: () => _openSurface(
            _WebAppMode.sender,
            senderStep: _SenderStep.healthPlus,
          ),
          onBusiness: () => _openSurface(_WebAppMode.sender,
              senderStep: _SenderStep.business),
          onVanguard: () => _openSurface(_WebAppMode.vanguard),
          onGifts: () => _openSurface(_WebAppMode.gifts),
          onToggleTheme: () => setState(() => _darkMode = !_darkMode),
        ),
    };
  }

  void _openRole(CircumRole role) {
    switch (role) {
      case CircumRole.sender:
        _openSurface(_WebAppMode.sender);
      case CircumRole.rider:
        _openSurface(_WebAppMode.rider);
      case CircumRole.admin:
        _openSurface(_WebAppMode.landing);
      case CircumRole.unknown:
        _openSurface(_WebAppMode.landing);
    }
  }
}

class _PlatformNotificationCenter extends StatefulWidget {
  final _CircumColors colors;
  final _WebAppMode mode;

  const _PlatformNotificationCenter({required this.colors, required this.mode});

  @override
  State<_PlatformNotificationCenter> createState() =>
      _PlatformNotificationCenterState();
}

class _PlatformNotificationCenterState
    extends State<_PlatformNotificationCenter> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  StreamSubscription<User?>? _authSubscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _items = const [];
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _listen();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      _listen();
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _PlatformNotificationCenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _listen();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _listen() async {
    await _subscription?.cancel();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _items = const []);
      return;
    }
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('notifications').limit(80);
    query = query.where('recipientId', isEqualTo: user.uid);
    _subscription = query.snapshots().listen((snapshot) {
      final docs = snapshot.docs.toList(growable: false)
        ..sort((a, b) {
          final left = a.data()['createdAt'];
          final right = b.data()['createdAt'];
          final leftDate = left is Timestamp ? left.toDate() : DateTime(1970);
          final rightDate =
              right is Timestamp ? right.toDate() : DateTime(1970);
          return rightDate.compareTo(leftDate);
        });
      if (mounted) setState(() => _items = docs);
    });
    await _registerToken(user);
  }

  Future<void> _registerToken(User user) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(provisional: true);
      final token = await messaging.getToken();
      if (token == null) return;
      final callable = widget.mode == _WebAppMode.rider
          ? 'updateRiderPushToken'
          : 'updateSenderPushToken';
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable(callable).call({'fcmToken': token});
    } catch (_) {
      // In-app notification history remains available if push is unavailable.
    }
  }

  Future<void> _markRead(
    QueryDocumentSnapshot<Map<String, dynamic>> item,
  ) async {
    if (item.data()['read'] == true) return;
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
      widget.mode == _WebAppMode.rider
          ? 'updateRiderNotificationState'
          : 'updateSenderNotificationState',
    )
        .call({'notificationId': item.id, 'action': 'mark_read'});
  }

  Future<void> _markAllRead() async {
    final unread = _items.where((item) => item.data()['read'] != true).toList();
    if (unread.isEmpty) return;
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
      widget.mode == _WebAppMode.rider
          ? 'updateRiderNotificationState'
          : 'updateSenderNotificationState',
    )
        .call({
      'notificationIds': unread.map((item) => item.id).toList(),
      'action': 'mark_read',
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((item) => item.data()['read'] != true).length;
    if (FirebaseAuth.instance.currentUser == null) {
      return const SizedBox.shrink();
    }
    if (_open) return _panel(context, unread);
    return Positioned(
      right: 18,
      bottom: 82,
      child: SafeArea(
        child: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: Tooltip(
            message: 'Notifications',
            child: IconButton.filled(
              onPressed: () => setState(() => _open = true),
              icon: const Icon(Icons.notifications_none_rounded),
              style: IconButton.styleFrom(
                fixedSize: const Size(48, 48),
                backgroundColor: widget.colors.panel,
                foregroundColor: widget.colors.text,
                side: BorderSide(color: widget.colors.border),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, int unread) {
    final desktop = MediaQuery.sizeOf(context).width >= 720;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.46),
        child: Align(
          alignment: desktop ? Alignment.centerRight : Alignment.bottomCenter,
          child: SafeArea(
            child: Container(
              width: desktop ? 420 : double.infinity,
              height: desktop
                  ? MediaQuery.sizeOf(context).height
                  : MediaQuery.sizeOf(context).height * 0.9,
              decoration: BoxDecoration(
                color: widget.colors.appBackground,
                borderRadius: desktop
                    ? const BorderRadius.horizontal(left: Radius.circular(24))
                    : const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: widget.colors.border),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_rounded,
                          color: widget.colors.text,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Notifications${unread > 0 ? ' · $unread unread' : ''}',
                            style: TextStyle(
                              color: widget.colors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: unread == 0 ? null : _markAllRead,
                          child: const Text('Mark all read'),
                        ),
                        IconButton(
                          tooltip: 'Close notifications',
                          onPressed: () => setState(() => _open = false),
                          icon: Icon(Icons.close, color: widget.colors.text),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: widget.colors.border, height: 1),
                  Expanded(
                    child: _items.isEmpty
                        ? Center(
                            child: Text(
                              'No notifications yet.',
                              style: TextStyle(color: widget.colors.mutedText),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(14),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              final data = item.data();
                              final isUnread = data['read'] != true;
                              return InkWell(
                                onTap: () => _markRead(item),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(13),
                                  decoration: BoxDecoration(
                                    color: isUnread
                                        ? widget.colors.field
                                        : widget.colors.panel,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isUnread
                                          ? widget.colors.adminAccent
                                              .withValues(alpha: 0.45)
                                          : widget.colors.border,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        isUnread
                                            ? Icons.notifications_active
                                            : Icons.notifications_none,
                                        color: isUnread
                                            ? widget.colors.adminAccent
                                            : widget.colors.mutedText,
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${data['title'] ?? 'Circum update'}',
                                              style: TextStyle(
                                                color: widget.colors.text,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '${data['message'] ?? ''}',
                                              style: TextStyle(
                                                color: widget.colors.mutedText,
                                                height: 1.3,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              _adminDateText(data['createdAt']),
                                              style: TextStyle(
                                                color: widget.colors.mutedText,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
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
}

class _LandingPage extends StatelessWidget {
  final _CircumColors colors;
  final bool darkMode;
  final VoidCallback onStart;
  final VoidCallback onRider;
  final VoidCallback onHealthPlus;
  final VoidCallback onBusiness;
  final VoidCallback onVanguard;
  final VoidCallback? onGifts;
  final VoidCallback onToggleTheme;

  const _LandingPage({
    super.key,
    required this.colors,
    required this.darkMode,
    required this.onStart,
    required this.onRider,
    required this.onHealthPlus,
    required this.onBusiness,
    required this.onVanguard,
    this.onGifts,
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
            onBusiness: onBusiness,
            onGifts: onGifts,
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
                                    ? Colors.black.withValues(alpha: 0.32)
                                    : Colors.white.withValues(alpha: 0.78),
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
                    'Book trusted Circum Riders for parcels, prescriptions, documents, and larger items. See the price, track the parcel, and stay in control.',
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
                        uri: _CircumWebsiteAppState._canonicalWebUri('/send'),
                        icon: Icons.arrow_forward,
                        dark: true,
                        onPressed: onStart,
                      ),
                      _PillButton(
                        label: 'Earn as a Circum Rider',
                        uri: _CircumWebsiteAppState._canonicalWebUri('/rider'),
                        icon: Icons.two_wheeler,
                        dark: false,
                        onPressed: onRider,
                      ),
                      _PillButton(
                        label: 'Get started with Health+',
                        uri: _CircumWebsiteAppState._canonicalWebUri(
                          '/send/health',
                        ),
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
          _ServiceTrustBand(
            colors: colors,
            onHealthPlus: onHealthPlus,
            onBusiness: onBusiness,
            onVanguard: onVanguard,
          ),
          _LandingFooter(
            colors: colors,
            onDeliveries: onStart,
            onHealthPlus: onHealthPlus,
            onGifts: onGifts,
            onBusiness: onBusiness,
            onVanguard: onVanguard,
          ),
        ],
      ),
    );
  }
}

const _shortMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime? _jobReceivedDate(Map<String, dynamic> job) {
  for (final key in ['createdAt', 'requestedAt', 'timestamp', 'timeStamp']) {
    final date = _dateFromAny(job[key]);
    if (date != null) return date;
  }
  return null;
}

DateTime? _dateFromAny(dynamic value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (value is String) date = DateTime.tryParse(value);
  return date?.toLocal();
}

String _jobReceivedText(Map<String, dynamic> job) {
  return _jobReceivedTextFromDate(_jobReceivedDate(job));
}

String _jobReceivedTextFromDate(DateTime? date) {
  if (date == null) return 'Time received unavailable';
  final local = date.toLocal();
  final now = DateTime.now();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return 'Received: Today, $hour:$minute';
  }
  final monthIndex = local.month < 1
      ? 0
      : local.month > 12
          ? 11
          : local.month - 1;
  final month = _shortMonthNames[monthIndex];
  return 'Received: ${local.day} $month, $hour:$minute';
}

bool _isActiveSenderDeliveryStatus(String status) {
  final normalized = status.toLowerCase().trim().replaceAll('-', '_');
  const activeStatuses = {
    'pending',
    'requested',
    'received',
    'finding_rider',
    'rider_assigned',
    'assigned',
    'accepted',
    'en_route_to_pickup',
    'collected',
    'picked_up',
    'in_transit',
    'arriving',
    'disputed',
  };
  const inactiveStatuses = {
    'completed',
    'complete',
    'delivered',
    'cancelled',
    'cancelled_by_sender',
    'canceled',
    'failed',
    'refunded',
    'archived',
  };
  if (inactiveStatuses.contains(normalized)) return false;
  return activeStatuses.contains(normalized);
}

String _displayStatusLabel(String status) {
  final normalized = status.trim().replaceAll('_', ' ');
  if (normalized.isEmpty) return 'Status pending';
  return normalized
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _displayDeliveryReference(String reference) {
  final value = reference.trim();
  if (value.isEmpty) return 'Reference pending';
  final normalized = value.toLowerCase();
  final compact = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  final suffix = compact.length <= 6
      ? compact.toUpperCase()
      : compact.substring(compact.length - 6).toUpperCase();
  if (normalized.startsWith('gift_')) return 'Gift #$suffix';
  if (normalized.startsWith('health_')) return 'Health+ #$suffix';
  if (normalized.contains('_') || compact.length > 18) {
    return 'Delivery #$suffix';
  }
  return value;
}

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
  final VoidCallback onBusiness;
  final VoidCallback? onGifts;
  final VoidCallback onToggleTheme;

  const _LandingNav({
    required this.colors,
    required this.darkMode,
    required this.onStart,
    required this.onRider,
    required this.onHealthPlus,
    required this.onBusiness,
    this.onGifts,
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
                _LandingNavLink(
                  label: 'Rider',
                  uri: _CircumWebsiteAppState._canonicalWebUri('/rider'),
                  colors: colors,
                  onPressed: onRider,
                ),
              if (MediaQuery.sizeOf(context).width >= 680)
                _LandingNavLink(
                  label: 'Health+',
                  uri: _CircumWebsiteAppState._canonicalWebUri('/send/health'),
                  colors: colors,
                  onPressed: onHealthPlus,
                ),
              if (MediaQuery.sizeOf(context).width >= 760)
                _LandingNavLink(
                  label: 'Business',
                  uri: _CircumWebsiteAppState._canonicalWebUri(
                    '/send/business',
                  ),
                  colors: colors,
                  onPressed: onBusiness,
                ),
              if (onGifts != null && MediaQuery.sizeOf(context).width >= 760)
                Link(
                  uri: _CircumWebsiteAppState._canonicalWebUri('/gifts'),
                  target: LinkTarget.self,
                  builder: (context, followLink) {
                    return TextButton.icon(
                      onPressed: followLink ?? onGifts,
                      icon: const Icon(Icons.card_giftcard, size: 18),
                      label: Text(
                        'Gifts',
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                )
              else if (onGifts != null)
                Link(
                  uri: _CircumWebsiteAppState._canonicalWebUri('/gifts'),
                  target: LinkTarget.self,
                  builder: (context, followLink) {
                    return IconButton(
                      tooltip: 'Gifts',
                      onPressed: followLink ?? onGifts,
                      icon: Icon(Icons.card_giftcard, color: colors.text),
                    );
                  },
                ),
              const SizedBox(width: 8),
              Link(
                uri: _CircumWebsiteAppState._canonicalWebUri('/send'),
                target: LinkTarget.self,
                builder: (context, followLink) {
                  return FilledButton(
                    onPressed: followLink ?? onStart,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.text,
                      foregroundColor: colors.inverseText,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    child: const Text('Send a Parcel'),
                  );
                },
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

class _LandingNavLink extends StatelessWidget {
  final String label;
  final Uri uri;
  final _CircumColors colors;
  final VoidCallback onPressed;

  const _LandingNavLink({
    required this.label,
    required this.uri,
    required this.colors,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Link(
      uri: uri,
      target: LinkTarget.self,
      builder: (context, followLink) {
        return TextButton(
          onPressed: followLink ?? onPressed,
          child: Text(
            label,
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
          ),
        );
      },
    );
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
                          'Your Circum Rider is on the way',
                          style: TextStyle(
                            color: colors.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Motorbike courier arriving in 8 min',
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
                child: Link(
                  uri: _CircumWebsiteAppState._canonicalWebUri('/send'),
                  target: LinkTarget.self,
                  builder: (context, followLink) {
                    return FilledButton.icon(
                      onPressed: followLink ?? onStart,
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
                    );
                  },
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
                color:
                    Colors.black.withValues(alpha: colors.dark ? 0.32 : 0.08),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
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
              : Column(children: [map, const SizedBox(height: 16), panel]),
        );
      },
    );
  }
}

class _ServiceTrustBand extends StatelessWidget {
  final _CircumColors colors;
  final VoidCallback onHealthPlus;
  final VoidCallback onBusiness;
  final VoidCallback onVanguard;

  const _ServiceTrustBand({
    required this.colors,
    required this.onHealthPlus,
    required this.onBusiness,
    required this.onVanguard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: colors.band,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 76),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServiceIntroCard(
                colors: colors,
                icon: Icons.health_and_safety,
                title: 'Health+',
                headline: 'Care logistics without the loose ends.',
                body:
                    'Prescription pickups, recurring reminders, sealed handling, and the same trusted custody layer built into important deliveries.',
                actionLabel: 'Open Health+',
                uri: _CircumWebsiteAppState._canonicalWebUri('/send/health'),
                badge: 'Vanguard Included',
                highlights: const [
                  'Prescription pickups',
                  'Recurring reminders',
                  'Sealed custody',
                  'Priority handling',
                ],
                onPressed: onHealthPlus,
              ),
              const SizedBox(height: 24),
              _ServiceIntroCard(
                colors: colors,
                icon: Icons.business_center,
                title: 'Business',
                headline: 'Operational delivery for teams.',
                body:
                    'Manage company deliveries, invoices, Health+, Gifts, Roth, and recurring work from one Circum workspace.',
                actionLabel: 'Open Business',
                uri: _CircumWebsiteAppState._canonicalWebUri('/send/business'),
                badge: 'Corporate Gifts · Vanguard Included',
                highlights: const [
                  'Company deliveries',
                  'Team access',
                  'Invoices',
                  'Recurring work',
                ],
                onPressed: onBusiness,
              ),
              const SizedBox(height: 24),
              _VanguardHomepageSection(
                colors: colors,
                uri: _CircumWebsiteAppState._canonicalWebUri('/vanguard'),
                onLearnMore: onVanguard,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceIntroCard extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String title;
  final String headline;
  final String body;
  final String actionLabel;
  final Uri uri;
  final String badge;
  final List<String> highlights;
  final VoidCallback onPressed;

  const _ServiceIntroCard({
    required this.colors,
    required this.icon,
    required this.title,
    required this.headline,
    required this.body,
    required this.actionLabel,
    required this.uri,
    required this.badge,
    required this.highlights,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final iconMark = Container(
          width: compact ? 74 : 88,
          height: compact ? 74 : 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xff1d4ed8).withValues(alpha: 0.34),
                const Color(0xff0b2340).withValues(alpha: 0.8),
              ],
            ),
            border: Border.all(
              color: const Color(0xff3b82f6).withValues(alpha: 0.48),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xff0a84ff).withValues(alpha: 0.13),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: const Color(0xff0a84ff),
            size: compact ? 30 : 34,
          ),
        );

        final action = _VanguardBlueActionButton(
          label: actionLabel,
          uri: uri,
          onPressed: onPressed,
        );

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 24 : 32),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.78, -0.95),
              radius: 1.35,
              colors: [
                const Color(0xff123d6f).withValues(alpha: 0.58),
                const Color(0xff07192f).withValues(alpha: 0.94),
                const Color(0xff040811).withValues(alpha: 0.98),
              ],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: const Color(0xff5b7fa8).withValues(alpha: 0.34),
              width: 1.35,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xff0a84ff).withValues(alpha: 0.09),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.26),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  iconMark,
                  const SizedBox(width: 18),
                  Expanded(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _VanguardBlueChip(label: title),
                        _VanguardBlueChip(label: badge),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 22 : 26),
              Text(
                headline,
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Georgia',
                  fontSize: compact ? 34 : 48,
                  height: 1.08,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                body,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: compact ? 16 : 18,
                  height: 1.48,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final highlight in highlights)
                    _ServiceHighlightPill(label: highlight),
                ],
              ),
              const SizedBox(height: 24),
              action,
            ],
          ),
        );
      },
    );
  }
}

class _VanguardBlueChip extends StatelessWidget {
  final String label;

  const _VanguardBlueChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xff0a84ff).withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xff3b82f6).withValues(alpha: 0.38),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0a84ff).withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xffdbeafe),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _VanguardBlueActionButton extends StatelessWidget {
  final String label;
  final Uri uri;
  final VoidCallback onPressed;

  const _VanguardBlueActionButton({
    required this.label,
    required this.uri,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0a84ff).withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Link(
        uri: uri,
        target: LinkTarget.self,
        builder: (context, followLink) {
          return FilledButton.icon(
            onPressed: followLink ?? onPressed,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff0a84ff),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 50),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              textStyle: const TextStyle(
                fontFamily: 'Georgia',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
              shape: const StadiumBorder(),
            ),
          );
        },
      ),
    );
  }
}

class _ServiceHighlightPill extends StatelessWidget {
  final String label;

  const _ServiceHighlightPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.052),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xff5b7fa8).withValues(alpha: 0.26),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: Color(0xff0a84ff),
            size: 17,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _VanguardHomepageSection extends StatelessWidget {
  final _CircumColors colors;
  final Uri uri;
  final VoidCallback onLearnMore;

  const _VanguardHomepageSection({
    required this.colors,
    required this.uri,
    required this.onLearnMore,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 720;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        narrow ? 24 : 34,
        narrow ? 36 : 42,
        narrow ? 24 : 34,
        narrow ? 30 : 36,
      ),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.72),
          radius: 1.15,
          colors: [
            const Color(0xff0b3764).withValues(alpha: 0.72),
            const Color(0xff07192f).withValues(alpha: 0.94),
            const Color(0xff030812).withValues(alpha: 0.98),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0xff5b7fa8).withValues(alpha: 0.36),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0a84ff).withValues(alpha: 0.1),
            blurRadius: 38,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _VanguardShieldFallback(size: 94),
          const SizedBox(height: 28),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.center,
            children: const [
              _VanguardBlueChip(label: 'Vanguard'),
              _VanguardBlueChip(label: 'Optional add-on at checkout — £1.99'),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Trust matters more than speed.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Georgia',
              fontSize: narrow ? 34 : 50,
              height: 1.12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Add Vanguard for £1.99 and receive enhanced custody tracking, trusted Circum Rider prioritisation, priority support, and better handling for important deliveries.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: narrow ? 17 : 19,
              height: 1.48,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 26),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth < 640 ? 1 : 4;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: cols == 1 ? 2.45 : 0.95,
                children: const [
                  _VanguardMiniCard(
                    icon: Icons.verified_user_outlined,
                    title: 'Trusted Rider Prioritisation',
                    body:
                        'Circum prioritises experienced and highly trusted Circum Riders during assignment. Customers do not choose riders.',
                  ),
                  _VanguardMiniCard(
                    icon: Icons.timeline_outlined,
                    title: 'Enhanced Custody Tracking',
                    body:
                        'Clear delivery milestones from assignment to delivery.',
                  ),
                  _VanguardMiniCard(
                    icon: Icons.support_agent,
                    title: 'Priority Support',
                    body: 'Priority support and faster dispute review.',
                  ),
                  _VanguardMiniCard(
                    icon: Icons.gavel_outlined,
                    title: 'Priority Dispute Review',
                    body: 'Priority review for Vanguard deliveries.',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const _VanguardHomepageTimeline(),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _VanguardBlueActionButton(
                label: 'Learn more',
                uri: uri,
                onPressed: onLearnMore,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VanguardMiniCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _VanguardMiniCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _vanguardCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xff0a84ff), size: 24),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              height: 1.32,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _VanguardHomepageTimeline extends StatelessWidget {
  const _VanguardHomepageTimeline();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final steps = compact
        ? const ['Assigned', 'Collected', 'In transit', 'Delivered']
        : const [
            'Circum Rider assigned',
            'Item collected',
            'In transit',
            'Delivered',
          ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: _vanguardCardDecoration(darker: true),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var index = 0; index < steps.length; index++) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xff0a84ff),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  steps[index],
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (index != steps.length - 1 && !compact)
              Container(
                width: 28,
                height: 1.2,
                color: const Color(0xff5b7fa8).withValues(alpha: 0.48),
              ),
          ],
        ],
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
                ),
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
                    color: colors.dark ? Colors.black : Colors.black,
                    width: 8,
                  ),
            boxShadow: [
              if (MediaQuery.sizeOf(context).width >= 520)
                const BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 34,
                  offset: Offset(0, 18),
                ),
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

  const _CircumOrderSection({required this.title, required this.paragraphs});
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

String _pdfMoney(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return (parsed ?? 0).toStringAsFixed(2);
}

Uri _pdfUriFromLines(
  List<String> rawLines, {
  String? title,
  Set<String> sectionTitles = const {},
}) {
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
      final isTitle = title != null && line == title;
      final isSectionTitle = sectionTitles.contains(line);
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
  return _pdfUriFromLines(
    rawLines,
    title: 'THE CIRCUM ORDER',
    sectionTitles:
        _circumOrderCharterSections.map((section) => section.title).toSet(),
  );
}

Uri _businessInvoicePdfUri(Map<String, dynamic> invoice) {
  final id = '${invoice['id'] ?? ''}'.trim();
  final invoiceNumber = '${invoice['invoiceNumber'] ?? id}'.trim();
  final displayNumber =
      invoiceNumber.isEmpty ? 'Business invoice' : invoiceNumber;
  final status = _displayStatusLabel(
    '${invoice['status'] ?? invoice['paymentStatus'] ?? 'open'}',
  );
  final total = _pdfMoney(invoice['total'] ?? invoice['subtotal']);
  final paid = _pdfMoney(invoice['amountPaid']);
  final balance = _pdfMoney(invoice['balanceDue'] ?? invoice['total']);
  final roth = _pdfMoney(invoice['rothApplied'] ?? invoice['rothAmount']);
  final deliveryCount = invoice['deliveryCount'] ??
      (invoice['deliveryIds'] is List
          ? (invoice['deliveryIds'] as List).length
          : null);
  final issued = _adminDateText(invoice['issuedAt'] ?? invoice['createdAt']);
  final due = _adminDateText(invoice['dueAt'] ?? invoice['dueDate']);

  return _pdfUriFromLines(
    [
      'CIRCUM BUSINESS INVOICE',
      displayNumber,
      '',
      'Status: $status',
      'Issued: $issued',
      'Due: $due',
      '',
      'Summary',
      'Total: GBP $total',
      'Paid: GBP $paid',
      'Roth applied: GBP $roth',
      'Balance due: GBP $balance',
      if (deliveryCount != null) 'Deliveries: $deliveryCount',
      '',
      'Payment',
      'Business invoices are created by Circum Operations.',
      'Use Stripe or Business Roth in the Business Centre to settle this invoice.',
      '',
      'Records',
      'This copy is provided for business records and may be printed or saved as PDF.',
    ],
    title: 'CIRCUM BUSINESS INVOICE',
    sectionTitles: const {'Summary', 'Payment', 'Records'},
  );
}

String _businessInvoicePdfFileName(Map<String, dynamic> invoice) {
  final id = '${invoice['invoiceNumber'] ?? invoice['id'] ?? 'invoice'}';
  final safe = id
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return 'circum-business-${safe.isEmpty ? 'invoice' : safe}.pdf';
}

void _downloadBusinessPdf(Uri uri, String fileName) {
  final anchor = web.HTMLAnchorElement()
    ..download = fileName
    ..href = uri.toString()
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
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
            border:
                Border.all(color: colors.adminAccent.withValues(alpha: 0.18)),
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
                    label: const Text('Become a Circum Rider'),
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

  const _CircumOrderRankCard({required this.colors, required this.rank});

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
    final verificationStatus =
        '${profile?['verificationStatus'] ?? profile?['approvalStatus'] ?? 'pending'}';
    final verified = verificationStatus.toLowerCase() == 'approved' ||
        verificationStatus.toLowerCase() == 'verified';
    final memberSince = _dateFromAny(
      profile?['memberSince'] ?? profile?['createdAt'],
    );
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
                      color: const Color(0xff8c28ff).withValues(alpha: 0.28),
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
              if (MediaQuery.sizeOf(context).width >= 430)
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HealthChip(
                label: verified
                    ? 'Verified by Circum'
                    : _displayStatusLabel(verificationStatus),
              ),
              _HealthChip(
                label:
                    'Quality ${performance.qualityScore.toStringAsFixed(0)}%',
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _RiderStatTile(
                colors: colors,
                label: 'Deliveries',
                value: '${performance.completedTrips}',
              ),
              _RiderStatTile(colors: colors, label: 'Rating', value: rating),
              if (memberSince != null)
                _RiderStatTile(
                  colors: colors,
                  label: 'Member since',
                  value: _adminDateText(memberSince),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xff030712),
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
                selectedColor: const Color(0xff2563eb),
                backgroundColor: const Color(0xff111827),
                labelStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
                side: BorderSide(
                  color: selected == tab
                      ? const Color(0xff60a5fa)
                      : const Color(0xff253047),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
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

  const _RiderEarningsTab({required this.colors, required this.earnings});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff2563eb), Color(0xff4f46e5)],
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x552563eb),
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AVAILABLE TO WITHDRAW',
                style: TextStyle(
                  color: Color(0xffdbeafe),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _RiderWorkspace._money(earnings.availableBalance),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your cleared delivery earnings are ready when you are.',
                style: TextStyle(
                  color: Color(0xffdbeafe),
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.55,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _RiderStatTile(
              colors: colors,
              label: 'Tips',
              value: _RiderWorkspace._money(earnings.tipsReceived),
            ),
            _RiderStatTile(
              colors: colors,
              label: 'Pending',
              value: _RiderWorkspace._money(earnings.pendingBalance),
            ),
            _RiderStatTile(
              colors: colors,
              label: 'Jobs',
              value: '${earnings.completedJobs}',
            ),
            _RiderStatTile(
              colors: colors,
              label: 'Withdrawn',
              value: _RiderWorkspace._money(earnings.withdrawnEarnings),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _GlassPanel(
          colors: colors,
          child: Text(
            'Drivers earn 65% of each completed delivery. Withdrawal requests and bank details remain available in your Circum Rider overview.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
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
                'Earn £10 for every verified rider you refer.',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 21,
                  height: 1.45,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xff0b1730),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xff2563eb)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR REFERRAL CODE',
                      style: TextStyle(
                        color: colors.mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Available after rider verification',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Referral sharing becomes available after rider verification.',
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
  final _vehicle = TextEditingController(text: 'Motorbike');
  final _vehicleMakeModel = TextEditingController(text: 'Honda PCX');
  final _vehicleColour = TextEditingController(text: 'Blue');
  final _plateNumber = TextEditingController(text: 'CIR 24K');
  final _availability = TextEditingController(text: 'Weekdays, evenings');
  final _notes = TextEditingController(text: 'Experienced London courier.');
  final _withdrawAmount = TextEditingController();
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
  Timer? _riderJobProjectionTimer;
  bool _riderJobProjectionLoading = false;
  DriverPerformanceMetric _performance = DriverPerformanceMetric.empty(
    'web-rider',
  );
  List<DriverRating> _recentRatings = const [];
  List<Map<String, dynamic>> _availableJobs = const [];
  List<Map<String, dynamic>> _acceptedJobs = const [];
  List<Map<String, dynamic>> _completedJobs = const [];
  Map<String, dynamic>? _riderProfile;
  Set<CircumRole> _availableRoles = const {};
  bool _superAdminRiderBypass = false;
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
    for (final controller in [
      _withdrawAmount,
      _bankName,
      _sortCode,
      _accountNumber,
    ]) {
      controller.addListener(_refreshWithdrawalForm);
    }
    _restoreRiderSession();
  }

  void _refreshWithdrawalForm() {
    if (mounted) setState(() {});
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
    _riderJobProjectionTimer?.cancel();
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
    for (final controller in [
      _withdrawAmount,
      _bankName,
      _sortCode,
      _accountNumber,
    ]) {
      controller.removeListener(_refreshWithdrawalForm);
    }
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
        setState(
          () => _authMessage =
              'Use a Circum Rider account here. Circum and admin accounts have their own sign-in.',
        );
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
      if (RiderOnboardingPolicy.canViewJobs(
        email: user.email,
        profile: riderProfile,
        verifiedSuperAdmin: _superAdminRiderBypass,
      )) {
        _startRiderJobProjection();
      }
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
      setState(
        () => _authMessage =
            'Enter an email and a password with at least 6 characters.',
      );
      return;
    }

    setState(() {
      _authSubmitting = true;
      _authMessage = _signupMode
          ? 'Creating your Circum Rider account...'
          : 'Signing you in...';
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
        setState(
          () => _authMessage =
              'This account is not a Circum Rider account. Use Circum login or the admin site instead.',
        );
        return;
      } else {
        _riderProfile = await _loadRiderProfile(user.uid);
      }
      _listenToRiderEarnings(user.uid);
      _listenToRiderPerformance(user.uid);
      if (RiderOnboardingPolicy.canViewJobs(
        email: user.email,
        profile: _riderProfile,
        verifiedSuperAdmin: _superAdminRiderBypass,
      )) {
        _startRiderJobProjection();
      }
      if (!mounted) return;
      setState(() {
        _riderUser = user;
        _roleChoiceConfirmed = _availableRoles.length <= 1;
        _authMessage = _signupMode
            ? 'Your Circum Rider account is ready.'
            : 'You are signed in.';
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
      setState(
        () => _authMessage =
            'Password reset sent. Check your email and follow the secure link.',
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(
        () => _authMessage = switch (error.code) {
          'invalid-email' => 'Enter a valid email address.',
          'user-not-found' => 'No Circum Rider account found for that email.',
          _ =>
            'We could not send the reset email. Check the address and try again.',
        },
      );
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
      setState(
        () => _securityMessage =
            'Enter your current password and make sure the new passwords match.',
      );
      return;
    }
    setState(() {
      _securitySubmitting = true;
      _securityMessage = 'Updating password...';
    });
    try {
      await _ensureCircumFirebaseReady();
      await _reauthenticateRider(current);
      await (_riderUser ?? FirebaseAuth.instance.currentUser)?.updatePassword(
        next,
      );
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
      setState(
        () =>
            _securityMessage = 'Enter the new email and your current password.',
      );
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
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('requestRiderEmailChange')
          .call({'pendingEmail': nextEmail});
      _newEmail.clear();
      _emailChangePassword.clear();
      if (!mounted) return;
      setState(
        () => _securityMessage =
            'Verification sent. Open the email link to confirm the new address.',
      );
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
    _superAdminRiderBypass = RoleAccessPolicy.isSuperAdmin(
      email: user.email,
      claims: claims,
      adminUser: adminDoc.data() ?? const {},
    );
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
    if (_superAdminRiderBypass) return 'approved';
    return RiderOnboardingPolicy.status(_riderProfile);
  }

  Future<void> _saveRiderProfile(User user) async {
    await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('updateRiderProfile').call({
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
      'availability': _availability.text.trim(),
    });
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
        _performance = DriverPerformanceMetric.fromMap(
          riderId,
          snapshot.data(),
        );
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

  void _startRiderJobProjection() {
    _riderJobProjectionTimer?.cancel();
    unawaited(_refreshRiderJobProjection());
    _riderJobProjectionTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refreshRiderJobProjection()),
    );
  }

  Future<void> _refreshRiderJobProjection() async {
    if (_riderJobProjectionLoading || _riderUser == null) return;
    _riderJobProjectionLoading = true;
    try {
      await _ensureCircumFirebaseReady();
      final result = await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('getAvailableRequests').call();
      final payload = Map<String, dynamic>.from(result.data as Map);
      List<Map<String, dynamic>> jobs(String key) =>
          ((payload[key] as List?) ?? const [])
              .whereType<Map>()
              .map((job) => Map<String, dynamic>.from(job))
              .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _availableJobs = jobs('nearestRequests');
        _acceptedJobs = jobs('activeJobs');
        _completedJobs = jobs('completedJobs');
      });
      _syncRiderLiveLocationPublishing();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _jobMessage = 'Could not load Rider jobs right now.',
      );
    } finally {
      _riderJobProjectionLoading = false;
    }
  }

  Future<void> _acceptDeliveryJob(Map<String, dynamic> job) async {
    final user = _riderUser;
    if (user == null) {
      setState(() => _jobMessage = 'Sign in before accepting a job.');
      return;
    }
    if (!RiderOnboardingPolicy.canAcceptJobs(
      email: user.email,
      profile: _riderProfile,
      verifiedSuperAdmin: _superAdminRiderBypass,
    )) {
      setState(
        () => _jobMessage =
            'Your Circum Rider account must be approved before accepting jobs.',
      );
      return;
    }
    final requestId = '${job['requestId'] ?? job['id'] ?? ''}'.trim();
    if (requestId.isEmpty) return;
    setState(() => _jobMessage = 'Accepting job $requestId...');
    try {
      await _ensureCircumFirebaseReady();
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('acceptRideRequests').call({'requestId': requestId});
      await _startRiderLiveLocationPublishing(requestId, user.uid, 'accepted');
      await _refreshRiderJobProjection();
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
    final activeJob = _acceptedJobs.cast<Map<String, dynamic>?>().firstWhere((
      job,
    ) {
      final status = '${job?['status'] ?? ''}'.toLowerCase();
      return status == 'accepted' ||
          status == 'picked_up' ||
          status == 'in_transit' ||
          status == 'in_progress';
    }, orElse: () => null);
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
        setState(
          () => _jobMessage =
              'Location permission is needed for live tracking while travelling.',
        );
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
    _riderLiveLocationTimer?.cancel();
    _riderLiveLocationTimer = null;
    _trackingDeliveryId = null;
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
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('updateDeliveryLiveLocation').call({
        'deliveryId': deliveryId,
        'status': status,
        'location': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'heading': position.heading,
          'speed': position.speed,
          'accuracy': position.accuracy,
          'clientRecordedAt': DateTime.now().millisecondsSinceEpoch,
        },
      });
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
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('recordRiderJobDecision')
          .call({'requestId': requestId, 'action': action});
      if (!mounted) return;
      setState(
        () => _jobMessage =
            action == 'reject' ? 'Job rejected.' : 'Job hidden for now.',
      );
      await _refreshRiderJobProjection();
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
      await _advanceAcceptedJobThroughBackend(
        job: job,
        requestId: requestId,
        targetStatus: status,
        vanguardPatch: vanguardPatch,
        verificationPatch: verificationPatch,
      );
      if (status == 'completed' || status == 'cancelled') {
        _stopRiderLiveLocationPublishing(status: status);
      }
      if (!mounted) return;
      setState(
        () => _jobMessage =
            status == 'completed' ? 'Delivery completed.' : 'Job updated.',
      );
      await _refreshRiderJobProjection();
    } catch (_) {
      if (!mounted) return;
      setState(() => _jobMessage = 'Could not update this job. Try again.');
    }
  }

  Future<void> _advanceAcceptedJobThroughBackend({
    required Map<String, dynamic> job,
    required String requestId,
    required String targetStatus,
    Map<String, dynamic>? vanguardPatch,
    Map<String, dynamic>? verificationPatch,
  }) async {
    final currentStatus = _canonicalRiderBackendStatus(
      '${job['status'] ?? 'accepted'}'.trim().toLowerCase().replaceAll(
            RegExp(r'[-\s]+'),
            '_',
          ),
    );
    final actions = _backendActionsForRiderTarget(currentStatus, targetStatus);
    final callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('updateDeliveryTrackingStatus');
    for (final action in actions) {
      await callable.call({
        'deliveryId': requestId,
        'action': action,
        if (action == 'verify_collection_pin' ||
            action == 'verify_receiver_pin') ...{
          if (vanguardPatch?['enteredPin'] != null)
            'pin': vanguardPatch!['enteredPin'],
          'evidence': {
            if (verificationPatch?['riderVerifiedWeightKg'] != null)
              'actualWeightKg': verificationPatch!['riderVerifiedWeightKg'],
            if ((verificationPatch?['riderWeightEvidenceUrls'] as List?)
                    ?.isNotEmpty ==
                true)
              'photoUrl':
                  (verificationPatch!['riderWeightEvidenceUrls'] as List).first,
            'conditionConfirmed': true,
            'riderDeclarationAccepted': true,
          },
        },
      });
    }
  }

  List<String> _backendActionsForRiderTarget(
    String currentStatus,
    String targetStatus,
  ) {
    const pickupAdvance = {
      'accepted': ['start_heading_to_pickup', 'arrived_at_pickup'],
      'navigating_to_pickup': ['arrived_at_pickup'],
      'arrived_at_pickup': <String>[],
      'waiting': <String>[],
      'pickup_verification': <String>[],
    };
    final actions = <String>[];
    if (targetStatus == 'picked_up') {
      actions.addAll(pickupAdvance[currentStatus] ?? const <String>[]);
      if (currentStatus != 'pickup_verified' && currentStatus != 'collected') {
        actions.add('verify_collection_pin');
      }
      if (currentStatus != 'collected') actions.add('confirm_collected');
      return actions;
    }
    if (targetStatus == 'in_transit') {
      if (currentStatus != 'collected' &&
          currentStatus != 'navigating_to_dropoff') {
        actions.addAll(
          _backendActionsForRiderTarget(currentStatus, 'picked_up'),
        );
      }
      if (currentStatus != 'navigating_to_dropoff') {
        actions.add('start_delivery');
      }
      return actions;
    }
    if (targetStatus == 'completed') {
      if (currentStatus != 'navigating_to_dropoff' &&
          currentStatus != 'arrived_at_dropoff' &&
          currentStatus != 'pin_required') {
        actions.addAll(
          _backendActionsForRiderTarget(currentStatus, 'in_transit'),
        );
      }
      if (currentStatus != 'arrived_at_dropoff' &&
          currentStatus != 'pin_required') {
        actions.add('near_dropoff');
      }
      actions.add('verify_receiver_pin');
      return actions;
    }
    if (targetStatus == 'cancelled') return ['cancel'];
    return const <String>[];
  }

  String _canonicalRiderBackendStatus(String status) {
    return switch (status) {
      'picked_up' => 'collected',
      'in_transit' || 'out_for_delivery' => 'navigating_to_dropoff',
      'completed' => 'delivered',
      _ => status,
    };
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
          title: Text(
            stage == 'delivery' ? 'Enter delivery PIN' : 'Enter collection PIN',
          ),
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
                    () => errorText = 'Enter the 6-digit Vanguard PIN.',
                  );
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
      setState(
        () => _jobMessage = stage == 'delivery'
            ? 'Delivery PIN required before completion.'
            : 'Collection PIN required before pickup.',
      );
      return null;
    }

    final verifiedField =
        stage == 'delivery' ? 'deliveryPinVerified' : 'collectionPinVerified';
    final verifiedAtField = stage == 'delivery'
        ? 'deliveryPinVerifiedAt'
        : 'collectionPinVerifiedAt';
    final verifiedByField = stage == 'delivery'
        ? 'deliveryPinVerifiedBy'
        : 'collectionPinVerifiedBy';
    return {
      'enteredPin': enteredPin,
      verifiedField: true,
      verifiedAtField: FieldValue.serverTimestamp(),
      verifiedByField: riderId,
      'vanguardVerification': {
        stage: {
          'status': 'passed',
          'riderId': riderId,
          'verifiedAt': FieldValue.serverTimestamp(),
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
    final weightController = TextEditingController(
      text: currentFinalWeight.toStringAsFixed(1),
    );
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
                RadioGroup<String>(
                  groupValue: option,
                  onChanged: (value) =>
                      setDialogState(() => option = value ?? option),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String>(
                        value: 'accurate',
                        title: Text('Confirm weight is accurate'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<String>(
                        value: 'heavier',
                        title: Text('Weight is heavier than declared'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<String>(
                        value: 'significant',
                        title: Text('Weight is significantly heavier'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: weightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
                    final picked = await ImagePicker().pickMultiImage(
                      imageQuality: 80,
                      maxWidth: 1800,
                    );
                    setDialogState(() => pickedPhotos = picked);
                  },
                  icon: const Icon(Icons.photo_camera),
                  label: Text(
                    pickedPhotos.isEmpty
                        ? 'Add evidence photo'
                        : '${pickedPhotos.length} photo(s) added',
                  ),
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
                  setDialogState(
                    () => errorText =
                        'Corrected weight must be higher than the current paid weight.',
                  );
                  return;
                }
                if (requiresEvidence && pickedPhotos.isEmpty) {
                  setDialogState(
                    () => errorText = 'Add at least one evidence photo.',
                  );
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
    final vehicle = DeliveryPricing.recommendedVehicleForWeight(
      finalWeightUsed,
    );
    DeliveryAccess accessValue(Object? value) {
      return switch ('$value') {
        'stairs' => DeliveryAccess.stairs,
        'liftAvailable' => DeliveryAccess.liftAvailable,
        _ => DeliveryAccess.groundFloor,
      };
    }

    final revisedHandling = SpecialHandlingEngine.evaluate(
      description: '${job['packageDescription'] ?? ''}',
      itemName: '${job['normalizedItemName'] ?? ''}',
      pickupAccess: accessValue(job['pickupAccess']),
      dropoffAccess: accessValue(job['dropoffAccess']),
    );
    final revisedQuote = revisedHandling.applyTo(
      DeliveryPricing.calculate(
        DeliveryPricingInput(
          distanceMiles: distanceMiles,
          weightKg: finalWeightUsed,
          vehicleType: vehicle,
        ),
      ),
    );
    final revisedPayout = revisedQuote.totalRiderEarnings;
    final revisedPlatformRevenue = revisedQuote.totalCircumRevenue;
    final heavier = finalWeightUsed > currentFinalWeight + 0.01;
    final summary =
        (job['driverJobSummary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};

    if (heavier) {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createWeightAdjustedNotification')
          .call({'requestId': requestId});
    }

    return {
      'riderVerifiedWeight': verifiedWeight,
      'riderVerifiedWeightKg': verifiedWeight,
      'finalVerifiedWeight': finalWeightUsed,
      'finalWeightUsed': finalWeightUsed,
      'finalChargeableWeight': finalWeightUsed,
      'confirmedWeightKg': finalWeightUsed,
      'confirmedWeightBand': DeliveryPricing.weightBandFor(
        finalWeightUsed,
      ).category,
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
      'riderBaseShare': revisedQuote.riderBaseShare,
      'riderLabourShare': revisedQuote.riderLabourShare,
      'circumBaseShare': revisedQuote.circumBaseShare,
      'circumLabourShare': revisedQuote.circumLabourShare,
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
        'confirmedWeightBand': DeliveryPricing.weightBandFor(
          finalWeightUsed,
        ).category,
        'driverPayout': revisedPayout,
        'riderPayout': revisedPayout,
        'platformRevenue': revisedPlatformRevenue,
        'totalFare': revisedQuote.total,
        'vehicleType': vehicle,
      },
    };
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
    final reason = await _showLoadDiscrepancyDialog(job);
    if (reason == null) return;
    setState(() => _jobMessage = 'Recalculating this booking...');
    try {
      await FirebaseFunctions.instance
          .httpsCallable('reportLoadDiscrepancy')
          .call(reason);
      if (!mounted) return;
      setState(
        () => _jobMessage =
            'Discrepancy reported. Collection is paused for the sender.',
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _jobMessage =
            error.message ?? 'Could not report this discrepancy. Try again.',
      );
    }
  }

  Future<Map<String, dynamic>?> _showLoadDiscrepancyDialog(
    Map<String, dynamic> job,
  ) async {
    final user = _riderUser;
    if (user == null) return null;
    final requestId = '${job['requestId'] ?? job['id'] ?? ''}'.trim();
    var reason = 'weight_exceeded';
    String? observedVehicleType;
    final weight = TextEditingController();
    final description = TextEditingController();
    final dimensions = TextEditingController();
    final notes = TextEditingController();
    final photos = <XFile>[];
    var uploading = false;
    String? error;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report Load Discrepancy'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: reason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: const [
                      DropdownMenuItem(
                        value: 'weight_exceeded',
                        child: Text('Weight exceeded'),
                      ),
                      DropdownMenuItem(
                        value: 'dimensions_exceeded',
                        child: Text('Dimensions exceeded'),
                      ),
                      DropdownMenuItem(
                        value: 'additional_undeclared_items',
                        child: Text('Additional undeclared items'),
                      ),
                      DropdownMenuItem(
                        value: 'item_differs_from_booking',
                        child: Text('Item differs from booking'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => reason = value ?? reason),
                  ),
                  const SizedBox(height: 12),
                  if (reason == 'weight_exceeded')
                    TextField(
                      controller: weight,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Observed weight (kg)',
                      ),
                    ),
                  if (reason == 'dimensions_exceeded')
                    TextField(
                      controller: dimensions,
                      decoration: const InputDecoration(
                        labelText: 'Observed dimensions',
                      ),
                    ),
                  if (reason == 'dimensions_exceeded' ||
                      reason == 'item_differs_from_booking') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: observedVehicleType,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle now required',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'motorbike',
                          child: Text('Motorbike'),
                        ),
                        DropdownMenuItem(value: 'car', child: Text('Car')),
                        DropdownMenuItem(value: 'van', child: Text('Van')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => observedVehicleType = value),
                    ),
                  ],
                  if (reason == 'item_differs_from_booking' ||
                      reason == 'additional_undeclared_items')
                    TextField(
                      controller: description,
                      decoration: const InputDecoration(
                        labelText: 'What is actually present?',
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Optional note',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: uploading
                        ? null
                        : () async {
                            final selected = await ImagePicker().pickMultiImage(
                              imageQuality: 75,
                              limit: 4,
                            );
                            setDialogState(
                              () => photos
                                ..clear()
                                ..addAll(selected),
                            );
                          },
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(
                      photos.isEmpty
                          ? 'Add evidence photo'
                          : '${photos.length} photo(s) selected',
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  uploading ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: uploading
                  ? null
                  : () async {
                      final observedWeight = double.tryParse(
                        weight.text.trim(),
                      );
                      if (photos.isEmpty) {
                        setDialogState(
                          () => error = 'Add at least one evidence photo.',
                        );
                        return;
                      }
                      if (reason == 'weight_exceeded' &&
                          (observedWeight == null || observedWeight <= 0)) {
                        setDialogState(
                          () => error = 'Enter the observed weight.',
                        );
                        return;
                      }
                      if (reason == 'dimensions_exceeded' &&
                          observedVehicleType == null) {
                        setDialogState(
                          () => error =
                              'Select the vehicle now required for this load.',
                        );
                        return;
                      }
                      setDialogState(() {
                        uploading = true;
                        error = null;
                      });
                      try {
                        final evidenceReferences = <Map<String, dynamic>>[];
                        for (var index = 0; index < photos.length; index++) {
                          final photo = photos[index];
                          final ref = FirebaseStorage.instance.ref(
                            'delivery-discrepancies/$requestId/${user.uid}/${DateTime.now().millisecondsSinceEpoch}-$index.jpg',
                          );
                          await ref.putData(
                            await photo.readAsBytes(),
                            SettableMetadata(
                              contentType: photo.mimeType,
                              customMetadata: {
                                'deliveryId': requestId,
                                'uploadedBy': user.uid,
                                'evidenceType': 'weight_discrepancy',
                              },
                            ),
                          );
                          evidenceReferences.add({'storagePath': ref.fullPath});
                        }
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop({
                          'requestId': requestId,
                          'reason': reason,
                          'evidencePhotos': evidenceReferences,
                          if (observedWeight != null)
                            'observedWeightKg': observedWeight,
                          if (description.text.trim().isNotEmpty)
                            'observedDescription': description.text.trim(),
                          if (dimensions.text.trim().isNotEmpty)
                            'dimensions': dimensions.text.trim(),
                          if (observedVehicleType != null)
                            'observedVehicleType': observedVehicleType,
                          if (notes.text.trim().isNotEmpty)
                            'riderNotes': notes.text.trim(),
                        });
                      } catch (_) {
                        setDialogState(() {
                          uploading = false;
                          error = 'Evidence upload failed. Try again.';
                        });
                      }
                    },
              child: Text(uploading ? 'Uploading...' : 'Submit report'),
            ),
          ],
        ),
      ),
    );
    weight.dispose();
    description.dispose();
    dimensions.dispose();
    notes.dispose();
    return result;
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
        .listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _riderChatMessages
            ..clear()
            ..addAll(
              snapshot.docs.map((doc) {
                final data = doc.data();
                final role =
                    '${data['senderRole'] ?? data['senderType'] ?? ''}';
                return _ChatMessage(
                  fromMe: data['senderId'] == _riderUser?.uid,
                  text: '${data['messageText'] ?? data['message'] ?? ''}',
                  time: _formatMessageTime(
                    data['createdAt'],
                    data['timeStamp'],
                  ),
                  label: role == 'admin' || role == 'support'
                      ? 'CIRCUM Support'
                      : role == 'sender' || role == 'user'
                          ? 'Sender'
                          : 'Rider',
                );
              }).where((message) => message.text.trim().isNotEmpty),
            );
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _jobMessage = 'Could not open this chat.');
      },
    );
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
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('sendCircumMessage')
          .call({
        'chatId': requestId,
        'requestId': requestId,
        'message': text,
        'clientMessageId': const Uuid().v4(),
      });
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
    _riderJobProjectionTimer?.cancel();
    _riderJobProjectionTimer = null;
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
    if (!RiderOnboardingPolicy.canWithdraw(
      email: user.email,
      profile: _riderProfile,
      verifiedSuperAdmin: _superAdminRiderBypass,
    )) {
      setState(
        () => _withdrawMessage =
            'Your Circum Rider account must be approved before requesting a withdrawal.',
      );
      return;
    }
    final amount = double.tryParse(_withdrawAmount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _withdrawMessage = 'Enter the amount first.');
      return;
    }
    if (amount > _earnings.availableBalance) {
      setState(
        () => _withdrawMessage =
            'The withdrawal amount is higher than your available balance.',
      );
      return;
    }

    setState(() {
      _withdrawSubmitting = true;
      _withdrawMessage = 'Sending withdrawal request...';
    });

    try {
      await _ensureCircumFirebaseReady();
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('requestRiderWithdrawal').call({'amount': amount});
      if (!mounted) return;
      setState(
        () => _withdrawMessage =
            'Withdrawal request sent. Circum will process it through Stripe Connect.',
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _withdrawMessage =
            error.message ?? 'We could not send the request. Try again.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _withdrawMessage = 'We could not send the request. Try again.',
      );
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
      final documentType = _riderDocumentType(_documentType.text);
      final contentType = picked.mimeType ?? 'image/jpeg';
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('submitRiderDocument').call({
        'documentType': documentType,
        'notes': _documentNotes.text.trim(),
        'fileName': picked.name,
        'contentType': contentType,
        'fileBase64': base64Encode(bytes),
      });
      _riderProfile = await _loadRiderProfile(user.uid);
      if (!mounted) return;
      setState(
        () => _documentMessage =
            'Document uploaded. Circum will review it before approval.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _documentMessage = 'Upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _documentSubmitting = false);
    }
  }

  String _riderDocumentType(String input) {
    final normalized = input.trim().toLowerCase();
    if (normalized.contains('licence') || normalized.contains('license')) {
      return 'driving_licence';
    }
    if (normalized.contains('address')) return 'proof_of_address';
    if (normalized.contains('insurance')) return 'vehicle_insurance';
    if (normalized.contains('right') && normalized.contains('work')) {
      return 'right_to_work';
    }
    return normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String _friendlyAuthMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'email-already-in-use' =>
        'That email already has a Circum Rider account.',
      'user-not-found' => 'No Circum Rider account found for that email.',
      'wrong-password' ||
      'invalid-credential' =>
        'The sign-in details are not right.',
      'weak-password' => 'Use a stronger password.',
      _ => 'We could not sign you in. Please check the details.',
    };
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_fullName.text.trim().isEmpty ||
        _phone.text.trim().isEmpty ||
        _vehicle.text.trim().isEmpty ||
        _plateNumber.text.trim().isEmpty) {
      setState(() {
        _message = 'Add your name, phone, vehicle type, and registration.';
      });
      return;
    }
    if (!_rightToWork || !_sealedPackageConsent) {
      setState(() {
        _message =
            'Accept the rider terms and confirm your details are accurate.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _message = 'Sending your Circum Rider application...';
    });

    try {
      await _ensureCircumFirebaseReady();
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('submitRiderApplication')
          .call<Map<String, dynamic>>({
        'fullName': _fullName.text.trim(),
        'phoneNumber': _phone.text.trim(),
        'email': _email.text.trim(),
        'postcode': _postcode.text.trim(),
        'vehicleType': _vehicle.text.trim(),
        'vehicleRegistration': _plateNumber.text.trim(),
        'availability': _availability.text.trim(),
        'notes': _notes.text.trim(),
        'rightToWorkConfirmed': _rightToWork,
        'sealedPackageConsent': _sealedPackageConsent,
        'idempotencyKey': 'web-rider-application:${_riderUser?.uid}',
      });
      final applicationId = '${result.data['applicationId'] ?? ''}'.trim();
      if (_riderUser != null) {
        _riderProfile = await _loadRiderProfile(_riderUser!.uid);
      }
      if (!mounted) return;
      setState(() {
        _applicationId = applicationId;
        _message =
            'Thanks. Your Circum Rider application has been sent to the Circum team.';
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
    if (_riderProfile == null && !_superAdminRiderBypass) {
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
    if (approvalStatus == 'not_started') {
      return ListView(
        padding: EdgeInsets.fromLTRB(wide ? 28 : 18, 18, wide ? 28 : 18, 34),
        children: [
          _buildRiderAccessPanel(colors),
          const SizedBox(height: 14),
          _buildRiderEnrollmentForm(colors),
        ],
      );
    }
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
          const SizedBox(height: 14),
          _buildPendingDocumentUpload(colors),
        ],
      );
    }

    return _buildRiderWorkspace(colors, nested: !wide);
  }

  Widget _buildPendingDocumentUpload(_CircumColors colors) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Required documents'),
          const SizedBox(height: 8),
          Text(
            'Upload your driving licence, proof of address, vehicle insurance, and right to work evidence.',
            style: TextStyle(color: colors.mutedText, height: 1.4),
          ),
          const SizedBox(height: 12),
          _RiderDocumentStatusList(
            colors: colors,
            profile: _riderProfile,
            onSelectType: (type) => setState(() => _documentType.text = type),
          ),
          const SizedBox(height: 10),
          _InputBox(
            colors: colors,
            controller: _documentType,
            hint: 'Document type',
          ),
          const SizedBox(height: 10),
          _InputBox(
            colors: colors,
            controller: _documentNotes,
            hint: 'Notes for review',
            maxLines: 2,
          ),
          if (_documentMessage != null) ...[
            const SizedBox(height: 8),
            Text(_documentMessage!, style: TextStyle(color: colors.text)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _documentSubmitting ? null : _uploadRiderDocument,
              icon: _documentSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(
                _documentSubmitting ? 'Uploading...' : 'Upload document',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const colors = _CircumColors(true);
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
                    _RiderPortalTab.referrals => _RiderReferralsTab(
                        colors: colors,
                      ),
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
                                onToggleMode: () => setState(
                                  () => _signupMode = !_signupMode,
                                ),
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
                                      () => _roleChoiceConfirmed = true,
                                    ),
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
            'Create a Circum Rider account to apply, upload documents, accept jobs, and manage payouts. Drivers earn 65% of each completed delivery.',
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
                label: const Text('Verified Circum Riders only'),
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
            title: signedIn ? 'Circum Rider account' : 'Circum Rider sign in',
          ),
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
              obscureText: true,
            ),
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
                    label: Text(
                      submitting
                          ? 'Please wait...'
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
        'This Circum Rider account cannot accept jobs right now. Contact Circum support for the next step.',
      _ =>
        'Your Circum Rider profile has been created. Circum will review your details and documents before jobs appear here.',
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
                color: const Color(0xff0f172a),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xff26334d)),
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
        _StepTopBar(
          colors: colors,
          title: 'Earn as a Circum Rider',
          onBack: null,
        ),
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
              _SectionTitle(colors: colors, title: 'Circum Rider details'),
              const SizedBox(height: 12),
              _InputBox(
                colors: colors,
                controller: fullName,
                hint: 'Full name',
              ),
              const SizedBox(height: 10),
              _InputBox(
                colors: colors,
                controller: phone,
                hint: 'Phone number',
              ),
              const SizedBox(height: 10),
              _InputBox(colors: colors, controller: email, hint: 'Email'),
              const SizedBox(height: 10),
              _InputBox(colors: colors, controller: postcode, hint: 'Postcode'),
              const SizedBox(height: 10),
              _CompactSelectBox(
                colors: colors,
                controller: vehicle,
                label: 'Vehicle type',
                options: const ['Motorbike', 'Car', 'Van'],
              ),
              const SizedBox(height: 5),
              Text(
                'Choose Motorbike Rider, Car Driver, or Van Driver.',
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              _InputBox(
                colors: colors,
                controller: vehicleMakeModel,
                hint: 'Vehicle make/model',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _InputBox(
                      colors: colors,
                      controller: vehicleColour,
                      hint: 'Colour',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InputBox(
                      colors: colors,
                      controller: plateNumber,
                      hint: 'Plate number',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _InputBox(
                colors: colors,
                controller: availability,
                hint: 'Availability',
              ),
              const SizedBox(height: 10),
              _InputBox(
                colors: colors,
                controller: notes,
                hint: 'Experience / notes',
                maxLines: 3,
              ),
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
            'I accept the Circum rider terms.',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: colors.text,
          value: sealedPackageConsent,
          onChanged: onSealedPackageConsent,
          title: Text(
            'I confirm the information and documents I provide are accurate.',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(
            message!,
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
          ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      color: const Color(0xff030712),
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 28,
        compact ? 18 : 28,
        compact ? 16 : 28,
        34,
      ),
      child: ListView(
        shrinkWrap: nested,
        physics: nested ? const NeverScrollableScrollPhysics() : null,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Circum Rider dashboard',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: compact ? 28 : 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _HealthChip(label: signedIn ? 'Signed in' : 'Account needed'),
            ],
          ),
          const SizedBox(height: 18),
          if (jobMessage != null &&
              !jobMessage!.toLowerCase().contains('completed')) ...[
            _GlassPanel(
              colors: colors,
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colors.text),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      jobMessage!,
                      style: TextStyle(
                        color: colors.text,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _GlassPanel(
            colors: colors,
            child: Row(
              children: [
                Icon(Icons.route_outlined, color: colors.text),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No live route at the moment.',
                    style: TextStyle(
                      color: colors.mutedText,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xff2563eb), Color(0xff4f46e5)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AVAILABLE TO WITHDRAW',
                        style: TextStyle(
                          color: Color(0xffdbeafe),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _money(earnings.availableBalance),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
                        label: 'Pending',
                        value: _money(earnings.pendingBalance),
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
                _RiderStatTile(
                  colors: colors,
                  label: 'Withdrawn',
                  value: _money(earnings.withdrawnEarnings),
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
                  colors: colors,
                  controller: withdrawAmount,
                  hint: 'Amount to withdraw',
                ),
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: bankName,
                  hint: 'Bank name',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _InputBox(
                        colors: colors,
                        controller: sortCode,
                        hint: 'Sort code',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InputBox(
                        colors: colors,
                        controller: accountNumber,
                        hint: 'Account number',
                      ),
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
                      color: colors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (withdrawMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    withdrawMessage!,
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: signedIn &&
                            !submittingWithdrawal &&
                            _canRequestWithdrawal(
                              amountText: withdrawAmount.text,
                              availableBalance: earnings.availableBalance,
                            )
                        ? onWithdraw
                        : null,
                    icon: submittingWithdrawal
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.account_balance),
                    label: Text(
                      submittingWithdrawal
                          ? 'Sending request...'
                          : 'Request withdrawal',
                    ),
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
                  'Upload each document for Circum review. Replace a file if support asks for a new copy.',
                  style: TextStyle(
                    color: colors.mutedText,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _RiderDocumentStatusList(
                  colors: colors,
                  profile: riderProfile,
                  onSelectType: (type) => documentType.text = type,
                ),
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: documentType,
                  hint: 'Document type',
                ),
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: documentNotes,
                  hint: 'Notes for review',
                  maxLines: 2,
                ),
                if (documentMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    documentMessage!,
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
                    label: Text(
                      submittingDocument ? 'Uploading...' : 'Upload document',
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
                  value: 'Circum requests and Health+ pickups',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _money(double value) => '£${value.toStringAsFixed(2)}';

  static bool _canRequestWithdrawal({
    required String amountText,
    required double availableBalance,
  }) {
    final amount = double.tryParse(amountText.trim()) ?? 0;
    return amount > 0 && amount <= availableBalance;
  }
}

class _RiderDocumentStatusList extends StatelessWidget {
  static const documentTypes = [
    'Driving licence',
    'Insurance',
    'Proof of address',
    'Vehicle documents',
    'Profile photo',
    'Right to work',
  ];

  final _CircumColors colors;
  final Map<String, dynamic>? profile;
  final ValueChanged<String> onSelectType;

  const _RiderDocumentStatusList({
    required this.colors,
    required this.profile,
    required this.onSelectType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: documentTypes.map((type) {
        final status = _statusFor(type);
        final rejected = status == 'rejected';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xff0f172a),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xff26334d)),
          ),
          child: Row(
            children: [
              Icon(
                _statusIcon(status),
                color: rejected
                    ? const Color(0xfff97316)
                    : status == 'approved'
                        ? const Color(0xff22c55e)
                        : status == 'missing'
                            ? const Color(0xff60a5fa)
                            : const Color(0xfff59e0b),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type,
                      style: TextStyle(
                        color: colors.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _friendlyStatus(status),
                      style: TextStyle(
                        color: colors.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (rejected && _rejectionReason(type).isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _rejectionReason(type),
                        style: const TextStyle(
                          color: Color(0xffdc2626),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: () => onSelectType(type),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xff60a5fa),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                child: Text(status == 'missing' ? 'Upload' : 'Replace'),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _statusFor(String type) {
    final key = type.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final documents =
        (profile?['verificationDocuments'] as Map?)?.cast<String, dynamic>() ??
            (profile?['documents'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final entry = documents[key] ??
        documents[type] ??
        documents[type.toLowerCase()] ??
        documents[key.replaceAll('_', '')];
    if (entry is Map) {
      final status =
          '${entry['status'] ?? entry['verificationStatus'] ?? 'uploaded'}'
              .toLowerCase();
      return status == 'pending' ? 'under_review' : status;
    }
    if (entry == true) return 'uploaded';
    return 'missing';
  }

  String _rejectionReason(String type) {
    final key = type.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final documents =
        (profile?['verificationDocuments'] as Map?)?.cast<String, dynamic>() ??
            (profile?['documents'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final entry =
        documents[key] ?? documents[type] ?? documents[type.toLowerCase()];
    if (entry is Map) {
      return '${entry['rejectionReason'] ?? entry['reason'] ?? ''}'.trim();
    }
    return '';
  }

  static IconData _statusIcon(String status) {
    return switch (status) {
      'approved' => Icons.verified,
      'uploaded' || 'under_review' => Icons.hourglass_top,
      'rejected' => Icons.error_outline,
      _ => Icons.upload_file,
    };
  }

  static String _friendlyStatus(String status) {
    return switch (status) {
      'approved' => 'Approved',
      'uploaded' => 'Uploaded',
      'under_review' || 'pending' => 'Under review',
      'rejected' => 'Rejected',
      _ => 'Missing',
    };
  }
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
            'Manage your sign-in details.',
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
  final ValueChanged<Map<String, dynamic>> onAcceptJob;
  final ValueChanged<Map<String, dynamic>> onRejectJob;
  final ValueChanged<Map<String, dynamic>> onIgnoreJob;
  final void Function(Map<String, dynamic> job, String issueType) onReportIssue;
  final ValueChanged<Map<String, dynamic>> onOpenChat;

  const _AvailableDriverJobsPanel({
    required this.colors,
    required this.jobs,
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
          const SizedBox(height: 12),
          if (jobs.isEmpty)
            Text(
              'No Circum requests are waiting right now.',
              style: TextStyle(color: colors.mutedText),
            )
          else
            ...jobs.take(8).map(
                  (job) => _DriverJobCard(
                    colors: colors,
                    job: job,
                    onAccept: () => onAcceptJob(job),
                    onReject: () => onRejectJob(job),
                    onIgnore: () => onIgnoreJob(job),
                    onReportDiscrepancy: () =>
                        onReportIssue(job, 'discrepancy'),
                    onOpenChat: () => onOpenChat(job),
                  ),
                ),
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
            ...jobs.take(8).map(
                  (job) => _DriverJobCard(
                    colors: colors,
                    job: job,
                    completed: completed,
                    onAccept: () => onUpdateJobStatus(job, 'accepted'),
                    onUpdateStatus: completed
                        ? null
                        : (status) => onUpdateJobStatus(job, status),
                    onReportDiscrepancy: () =>
                        onReportIssue(job, 'discrepancy'),
                    onOpenChat: () => onOpenChat(job),
                  ),
                ),
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
  final VoidCallback onReportDiscrepancy;
  final VoidCallback onOpenChat;
  final bool completed;

  const _DriverJobCard({
    required this.colors,
    required this.job,
    required this.onAccept,
    this.onReject,
    this.onIgnore,
    this.onUpdateStatus,
    required this.onReportDiscrepancy,
    required this.onOpenChat,
    this.completed = false,
  });

  @override
  Widget build(BuildContext context) {
    final summary =
        (job['driverJobSummary'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final customerWeight = _num(
      job['customerDeclaredWeight'] ?? job['senderEnteredWeightKg'],
    );
    final irisWeight = _num(
      job['irisEstimatedWeight'] ?? job['irisEstimatedWeightKg'],
    );
    final chargeableWeight = _num(
      job['finalWeightUsed'] ??
          job['finalChargeableWeight'] ??
          job['confirmedWeightKg'],
    );
    final category =
        '${job['weightCategory'] ?? job['confirmedWeightBand'] ?? summary['confirmedWeightBand'] ?? 'Parcel'}';
    final confidence =
        '${job['irisConfidenceScore'] ?? job['irisWeightConfidence'] ?? 'unknown'}';
    final weightSource =
        '${job['irisWeightSource'] ?? summary['irisWeightSource'] ?? 'unknown'}';
    final distance = _num(summary['estimatedDistanceMiles']);
    final payout = _num(summary['driverPayout'] ?? job['driverPayout']);
    final riderBaseShare = _num(
      summary['riderBaseShare'] ?? job['riderBaseShare'],
    );
    final riderLabourShare = _num(
      summary['riderLabourShare'] ?? job['riderLabourShare'],
    );
    final assistedFee = _num(
      summary['assistedFee'] ?? job['assistedFee'],
    );
    final heavyDutyFee = _num(
      summary['heavyDutyFee'] ?? job['heavyDutyFee'],
    );
    final twoPersonFee = _num(
      summary['twoPersonFee'] ?? job['twoPersonFee'],
    );
    final tip = _num(
      job['tipAmount'] ?? job['riderTip'] ?? summary['tipAmount'],
    );
    final vehicle =
        '${summary['vehicleType'] ?? job['vehicleType'] ?? 'Vehicle'}';
    final serviceLevel =
        '${job['selectedServiceLevel'] ?? job['serviceLevel'] ?? summary['serviceLevel'] ?? 'standard'}';
    final vanguardEnabled = job['vanguardEnabled'] == true ||
        summary['vanguardEnabled'] == true ||
        ((job['vanguardProtection'] as Map?)?['enabled'] == true);
    final duration = _num(
      summary['estimatedDurationMinutes'] ??
          job['estimatedDurationMinutes'] ??
          job['etaMinutes'],
    );
    final dimensions =
        '${summary['packageDimensions'] ?? job['packageDimensions'] ?? job['dimensions'] ?? ''}'
            .trim();
    final warnings = _warnings(chargeableWeight, category, job);
    final showContactDetails = onReject == null && onIgnore == null;
    final senderName = _contactValue(
      job,
      summary,
      'senderName',
      nestedKey: 'senderDetails',
      nestedName: 'name',
    );
    final senderPhone = _contactValue(
      job,
      summary,
      'senderPhone',
      nestedKey: 'senderDetails',
      nestedName: 'phone',
    );
    final receiverName = _contactValue(
      job,
      summary,
      'receiverName',
      nestedKey: 'receiverDetails',
      nestedName: 'name',
    );
    final receiverPhone = _contactValue(
      job,
      summary,
      'receiverPhone',
      nestedKey: 'receiverDetails',
      nestedName: 'phone',
    );
    final collectionName = _contactValue(
      job,
      summary,
      'collectionContactName',
      nestedKey: 'collectionContact',
      nestedName: 'name',
    );
    final collectionPhone = _contactValue(
      job,
      summary,
      'collectionContactPhone',
      nestedKey: 'collectionContact',
      nestedName: 'phone',
    );
    final collectionDifferent = (job['collectionContactDifferent'] == true ||
        summary['collectionContactDifferent'] == true ||
        ((job['collectionContact'] as Map?)?['differentFromSender'] == true));
    final jobStatus = '${job['status'] ?? ''}'.toLowerCase();
    final proof = proofOfDeliveryFromRecord(job);
    final canReportDiscrepancy = const {
      'accepted',
      'rider_assigned',
      'en_route_to_pickup',
      'arrived_at_pickup',
    }.contains(jobStatus);

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
              if (assistedFee > 0) ...[
                _HealthChip(label: 'Assisted Delivery'),
                const SizedBox(width: 8),
              ],
              if (heavyDutyFee > 0) ...[
                _HealthChip(label: 'Heavy Duty'),
                const SizedBox(width: 8),
              ],
              if (twoPersonFee > 0) ...[
                _HealthChip(label: 'Two Person Required'),
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
          if (assistedFee > 0 || heavyDutyFee > 0 || twoPersonFee > 0)
            _JobInfoLine(
              colors: colors,
              icon: Icons.handyman,
              label: 'Special handling earnings',
              value:
                  'Base ${_money(riderBaseShare)}${assistedFee > 0 ? ' • Assisted bonus ${_money(assistedFee * 0.80)}' : ''}${heavyDutyFee > 0 ? ' • Heavy Duty bonus ${_money(heavyDutyFee * 0.80)}' : ''}${twoPersonFee > 0 ? ' • Two Person bonus ${_money(twoPersonFee * 0.80)}' : ''} • Total ${_money(riderBaseShare + riderLabourShare)}',
            ),
          _JobInfoLine(
            colors: colors,
            icon: Icons.schedule,
            label: 'Received',
            value: _jobReceivedText(job),
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
              value: receiverName.isEmpty
                  ? 'Receiver not provided'
                  : '$receiverName${receiverPhone.isEmpty ? '' : ' • $receiverPhone'}',
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
            label: 'Delivery timing',
            value: _deliveryTimingLabel(summary, job),
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
            label: 'Rider earnings',
            value: '${_money(payout)}${tip > 0 ? ' • tip ${_money(tip)}' : ''}',
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
              label: 'Vanguard Handling',
              value:
                  'Enhanced custody tracking and trusted Circum Rider prioritisation.',
            ),
          ],
          if (completed) ...[
            const SizedBox(height: 8),
            _JobInfoLine(
              colors: colors,
              icon: Icons.fact_check_outlined,
              label: 'Proof of delivery',
              value: proof.hasAnyProof
                  ? 'Proof submitted - ${proof.statusLabel}'
                  : 'Proof missing',
            ),
            if (proof.vanguardIncomplete)
              _JobInfoLine(
                colors: colors,
                icon: Icons.warning_amber_rounded,
                label: 'Vanguard review',
                value: 'Vanguard proof is incomplete.',
              ),
          ] else if (vanguardEnabled && !proof.hasAnyProof) ...[
            const SizedBox(height: 8),
            _JobInfoLine(
              colors: colors,
              icon: Icons.fact_check_outlined,
              label: 'Proof required',
              value: 'Proof required to complete this delivery.',
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (completed)
                _HealthChip(label: 'Completed')
              else
                FilledButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Accept job'),
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
              if (!completed && canReportDiscrepancy) ...[
                OutlinedButton.icon(
                  onPressed: onReportDiscrepancy,
                  icon: const Icon(Icons.report_problem),
                  label: const Text('Report Load Discrepancy'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _deliveryTimingLabel(
    Map<String, dynamic> summary,
    Map<String, dynamic> job,
  ) {
    final type =
        '${summary['deliveryTimingType'] ?? job['deliveryTimingType'] ?? ''}'
            .toLowerCase();
    if (type == 'asap') return 'Immediate Delivery';
    if (type == 'today') {
      return 'Today Delivery · ${summary['scheduledPickupWindow'] ?? job['scheduledPickupWindow'] ?? 'Flexible'}';
    }
    return '${summary['scheduledPickupDate'] ?? job['scheduledPickupDate'] ?? 'Scheduled'} · ${summary['scheduledPickupWindow'] ?? job['scheduledPickupWindow'] ?? 'Flexible'}';
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
                performance,
              ))
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
    final feedback = rating.hiddenByAdmin
        ? 'Written feedback hidden by Circum.'
        : rating.feedbackText.trim().isNotEmpty
            ? rating.feedbackText.trim()
            : rating.feedbackTags.isNotEmpty
                ? rating.feedbackTags.join(', ')
                : 'No written feedback';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '★' * rating.starRating.clamp(0, 5),
                style: const TextStyle(
                  color: Color(0xffffb020),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                rating.deliveryId.isEmpty
                    ? 'Delivery'
                    : 'Ref ${rating.deliveryId}',
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            feedback,
            style: TextStyle(
              color: colors.mutedText,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderEarningsSnapshot {
  final double availableBalance;
  final double pendingBalance;
  final double pendingWithdrawal;
  final double lifetimeEarnings;
  final double tipsReceived;
  final double withdrawnEarnings;
  final int completedJobs;

  const _RiderEarningsSnapshot({
    required this.availableBalance,
    required this.pendingBalance,
    required this.pendingWithdrawal,
    required this.lifetimeEarnings,
    required this.tipsReceived,
    required this.withdrawnEarnings,
    required this.completedJobs,
  });

  factory _RiderEarningsSnapshot.empty() => const _RiderEarningsSnapshot(
        availableBalance: 0,
        pendingBalance: 0,
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
      pendingBalance: (data['pendingBalance'] as num? ?? 0).toDouble(),
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
        color: const Color(0xff111827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xff253047)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: colors.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
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
                Text(
                  label,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
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
  business,
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
  final VoidCallback onGifts;
  final VoidCallback onToggleTheme;

  const _CustomerPortal({
    required this.darkMode,
    required this.colors,
    required this.initialStep,
    required this.onBack,
    required this.onRoleSelected,
    required this.onGifts,
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
  String? _deliveryTimingType;
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
  final _businessCompanyName = TextEditingController();
  final _businessType = TextEditingController(text: 'Limited company');
  final _businessEmail = TextEditingController();
  final _businessPhone = TextEditingController();
  final _businessAddress = TextEditingController();
  final _businessVatNumber = TextEditingController();
  final _businessWebsite = TextEditingController();
  final _businessCompanyCode = TextEditingController();
  final _businessInvoiceAmount = TextEditingController();
  final _businessRothAmount = TextEditingController(text: '50');
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
  int _irisQuantity = 1;
  double? _irisSingleItemWeightKg;
  double? _irisWeightConfidenceScore;
  double? _irisHistoricalVerifiedWeightKg;
  String? _irisLearningReason;
  ItemDimensionsCm? _irisTypicalDimensions;
  String? _irisVehicleSuitability;
  bool _irisFragile = false;
  bool _irisValueSensitive = false;
  bool _irisVanguardRecommended = false;
  bool _webVanguardSelected = false;
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
  DeliveryAccess _pickupAccess = DeliveryAccess.groundFloor;
  DeliveryAccess _dropoffAccess = DeliveryAccess.groundFloor;
  HealthPlusFrequency _healthFrequency = HealthPlusFrequency.oneOff;
  _CheckoutState _checkoutState = _CheckoutState.draft;
  bool _analyzing = false;
  bool _broadcasting = false;
  bool _chatOpen = false;
  bool _supportChat = false;
  bool _healthConsent = false;
  bool _healthSavePayment = true;
  bool _deliveryUseRoth = false;
  bool _healthUseRoth = false;
  bool _healthSubmitting = false;
  bool _businessLoading = false;
  bool _businessBusy = false;
  String _healthPrescriptionType = 'NHS prescription';
  String _healthSubscriptionPlan = 'basic';
  bool _ratingSubmitting = false;
  bool _ratingSubmitted = false;
  String? _activeOrderId;
  String? _activeRequestDocId;
  String? _assignedDriverId;
  String? _healthScheduleId;
  String? _healthMessage;
  String? _healthCheckoutUrl;
  double _healthRothBalance = 0;
  String? _businessMessage;
  String? _selectedBusinessId;
  String? _firebaseError;
  String? _ratingMessage;
  String? _senderProfileMessage;
  String? _senderDeliveryLoadError;
  String? _senderSecurityMessage;
  _ValidatedAddress? _validatedPickup;
  _ValidatedAddress? _validatedDropoff;
  _ValidatedAddress? _validatedHealthPharmacy;
  _ValidatedAddress? _validatedHealthDelivery;
  bool _firebaseOnline = false;
  bool _senderAuthLoading = true;
  bool _senderAuthBusy = false;
  bool _senderSecurityBusy = false;
  bool _senderProfileSaving = false;
  bool _senderSignupMode = false;
  bool _senderCheckoutReturnHandled = false;
  bool _roleChoiceConfirmed = false;
  bool _differentCollectionContact = false;
  bool _parcelPhotoBusy = false;
  int _statusIndex = 0;
  int _selectedRating = 0;
  double _selectedTipAmount = 0;
  int _senderProfileTab = 0;
  User? _senderUser;
  SenderProfile? _senderProfile;
  bool _legendCelebrationShowing = false;
  List<SenderDeliveryRecord> _senderDeliveries = const [];
  SenderDeliveryRecord? _selectedSenderDelivery;
  DriverProfile? _assignedDriver;
  DriverPerformanceMetric? _assignedDriverMetric;
  Map<String, dynamic>? _activeVanguardData;
  Map<String, dynamic>? _liveLocationData;
  XFile? _parcelPhoto;
  DateTime? _parcelPhotoCapturedAt;
  String? _parcelPhotoMessage;
  String? _irisPhotoAnalysisId;
  _IrisImageInsight? _irisImageInsight;
  DateTime? _activeRequestReceivedAt;
  Set<String> _selectedRatingTags = {};
  Set<CircumRole> _availableRoles = const {};
  final List<Map<String, dynamic>> _healthPickups = [];
  final List<Map<String, dynamic>> _healthPayments = [];
  List<Map<String, dynamic>> _businessAccounts = const [];
  List<Map<String, dynamic>> _businessInvoices = const [];
  List<Map<String, dynamic>> _businessJoinRequests = const [];
  List<Map<String, dynamic>> _businessAuditLogs = const [];
  Map<String, dynamic>? _businessWallet;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _requestSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _liveLocationSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _senderSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverProfileSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _driverPerformanceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _assignedDriverRatingsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _deliveryAdjustmentSub;
  String? _visibleAdjustmentId;

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
    _applyHealthPlusReturnState();
    _restoreSenderSession();
  }

  void _applyHealthPlusReturnState() {
    if (widget.initialStep != _SenderStep.healthPlus) return;
    final result = Uri.base.queryParameters['health'];
    if (result == 'success') {
      _healthMessage =
          'Health+ payment confirmed. Your pickup is being updated.';
    } else if (result == 'cancelled') {
      _healthMessage =
          'Health+ payment was cancelled. You can continue checkout when ready.';
    }
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
    _businessCompanyName.dispose();
    _businessType.dispose();
    _businessEmail.dispose();
    _businessPhone.dispose();
    _businessAddress.dispose();
    _businessVatNumber.dispose();
    _businessWebsite.dispose();
    _businessCompanyCode.dispose();
    _businessInvoiceAmount.dispose();
    _businessRothAmount.dispose();
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
    _deliveryAdjustmentSub?.cancel();
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
                          vehicle: _effectiveVehicle,
                          speed: _selectedSpeed,
                          weightKg: _deliveryClassification.finalWeightKg,
                          breakdown: _quoteBreakdown,
                          step: _step,
                          checkoutState: _checkoutState,
                          firebaseOnline: _firebaseOnline,
                          firebaseError: _firebaseError,
                          statusIndex: _statusIndex,
                          receivedAt: _activeRequestReceivedAt,
                          activeDelivery: _activeSenderDelivery,
                          deliveryLoadError: _senderDeliveryLoadError,
                          onSendParcel: () =>
                              setState(() => _step = _SenderStep.details),
                          onViewHistory: () => setState(() {
                            _step = _SenderStep.profile;
                            _senderProfileTab = 1;
                          }),
                          onCancelBooking: _cancelSenderBooking,
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
            title: _supportChat
                ? 'Iris Support'
                : _assignedDriver?.fullName.trim().isNotEmpty == true
                    ? _assignedDriver!.fullName.trim()
                    : 'Delivery chat',
            recipient: _supportChat
                ? 'Iris'
                : _assignedDriver?.fullName.trim().isNotEmpty == true
                    ? 'Your Circum Rider'
                    : 'Rider not assigned yet',
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
          onBusiness: () => setState(() => _step = _SenderStep.business),
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
          irisQuantity: _irisQuantity,
          irisTruthBand: _irisTruthBand(),
          senderEnteredWeightKg: _senderEnteredWeightKg,
          pricingWeightKg: _confirmedWeightKg,
          weightSource: _weightSourceText,
          pricingReason: _weightPricingReason,
          verificationRequired: _weightVerificationRequired,
          weightMessage: _weightMessage,
          onConfirmIrisWeight: _confirmIrisWeight,
          parcelPhotoName: _parcelPhoto?.name,
          parcelPhotoBusy: _parcelPhotoBusy,
          parcelPhotoMessage: _parcelPhotoMessage,
          onPickParcelPhoto: _pickParcelPhoto,
          onRemoveParcelPhoto: () => setState(() {
            _parcelPhoto = null;
            _parcelPhotoCapturedAt = null;
            _irisPhotoAnalysisId = null;
            _irisImageInsight = null;
            _parcelPhotoMessage = 'Parcel photo removed.';
          }),
          scheduledPickupDate: _scheduledPickupDate,
          scheduledPickupWindow: _scheduledPickupWindow,
          scheduledDropoffDate: _scheduledDropoffDate,
          scheduledDropoffWindow: _scheduledDropoffWindow,
          deliveryTimingType: _deliveryTimingType,
          onDeliveryTimingChanged: _setDeliveryTimingType,
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
          locationsConfirmed: _hasValidatedRoute,
          priceReady: _quoteTotal > 0,
          weightReady: _deliveryClassification.finalWeightKg > 0,
          specialHandling: _specialHandling,
          vanguardRequired: _webVanguardRequired,
          vanguardEnabled: _webVanguardEnabled,
          onVanguardChanged: (value) =>
              setState(() => _webVanguardSelected = value),
          pickupAccess: _pickupAccess,
          dropoffAccess: _dropoffAccess,
          onPickupAccess: (value) => setState(() => _pickupAccess = value),
          onDropoffAccess: (value) => setState(() => _dropoffAccess = value),
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
          specialHandling: _specialHandling,
          vanguardEnabled: _webVanguardEnabled,
          useRoth: _deliveryUseRoth,
          rothBalance: _healthRothBalance,
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
          onUseRoth: (value) => setState(() {
            _deliveryUseRoth = value ?? false;
          }),
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
          receivedAt: _activeRequestReceivedAt,
          pickupAddress: _validatedPickup,
          dropoffAddress: _validatedDropoff,
          liveLocation: _liveLocationData,
          vanguardData: _activeVanguardData,
          irisItemName: _irisMatchedItemName,
          irisQuantity: _irisQuantity,
          irisConfidence: _irisWeightConfidence,
          irisWeightKg: _deliveryClassification.finalWeightKg,
          irisWeightBand: _deliveryClassification.finalWeightBand,
          irisRepositoryMatched: _irisMatchedItemName != null,
          irisCorrected: _weightSource == 'sender_confirmed' ||
              _weightSource == 'manual_sender_entry',
          recommendedVehicle: _vehicleSuitability.recommendedVehicle,
          breakdown: _quoteBreakdown,
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
          onViewHistory: () => setState(() {
            _step = _SenderStep.profile;
            _senderProfileTab = 1;
          }),
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
          pharmacyVerified: _validatedHealthPharmacy?.isVerified == true,
          deliveryVerified: _validatedHealthDelivery?.isVerified == true,
          notes: _healthNotes,
          preferredDay: _healthPreferredDay,
          preferredTime: _healthPreferredTime,
          customSchedule: _healthCustomSchedule,
          frequency: _healthFrequency,
          prescriptionType: _healthPrescriptionType,
          subscriptionPlan: _healthSubscriptionPlan,
          consent: _healthConsent,
          savePayment: _healthSavePayment,
          useRoth: _healthUseRoth,
          rothBalance: _healthRothBalance,
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
          onUseRoth: (value) => setState(() => _healthUseRoth = value ?? false),
          onPharmacySelected: (address) => setState(() {
            _validatedHealthPharmacy = address;
            _healthPharmacy.text = address.displayAddress;
          }),
          onPharmacyEdited: (_) =>
              setState(() => _validatedHealthPharmacy = null),
          onDeliverySelected: (address) => setState(() {
            _validatedHealthDelivery = address;
            _healthDelivery.text = address.displayAddress;
          }),
          onDeliveryEdited: (_) =>
              setState(() => _validatedHealthDelivery = null),
          onSubmit: _bookHealthPlus,
          onPauseSchedule: _pauseHealthPlusSchedule,
          onResumeSchedule: _resumeHealthPlusSchedule,
          onCancelSchedule: _cancelHealthPlusSchedule,
          onCancelPickup: _cancelNextHealthPlusPickup,
          onUpdatePayment: _openHealthPlusCheckout,
          onAdminStatus: _adminUpdateHealthPlusStatus,
        ),
      _SenderStep.business => _BusinessCentreStep(
          key: const ValueKey('business-centre'),
          colors: colors,
          loading: _businessLoading,
          busy: _businessBusy,
          message: _businessMessage,
          accounts: _businessAccounts,
          selectedBusinessId: _selectedBusinessId,
          account: _selectedBusinessAccount,
          currentUserId: _senderUser?.uid,
          currentUserEmail: _senderUser?.email,
          invoices: _businessInvoices,
          deliveries: _senderDeliveries,
          joinRequests: _businessJoinRequests,
          auditLogs: _businessAuditLogs,
          wallet: _businessWallet,
          companyName: _businessCompanyName,
          businessType: _businessType,
          businessEmail: _businessEmail,
          businessPhone: _businessPhone,
          businessAddress: _businessAddress,
          vatNumber: _businessVatNumber,
          website: _businessWebsite,
          companyCode: _businessCompanyCode,
          rothAmount: _businessRothAmount,
          onBack: () => setState(() => _step = _SenderStep.dashboard),
          onRefresh: () {
            final user = _senderUser;
            if (user != null) _loadBusinessWorkspaces(user.uid);
          },
          onSelectBusiness: (id) async {
            setState(() {
              _selectedBusinessId = id;
              final account = _selectedBusinessAccount;
              if (account != null) _populateBusinessControllers(account);
            });
            final user = _senderUser;
            if (user != null) await _loadBusinessWorkspaces(user.uid);
          },
          onCreateBusiness: _createBusinessAccount,
          onJoinBusiness: _joinBusinessByCode,
          onEnsureCompanyCode: _ensureBusinessCompanyCode,
          onRotateCompanyCode: () => _ensureBusinessCompanyCode(rotate: true),
          onSaveProfile: _saveBusinessProfile,
          onReviewRequest: _reviewBusinessRequest,
          onUpdateMemberRole: _updateBusinessMemberRole,
          onRemoveMember: _removeBusinessMember,
          onPayInvoice: (invoiceId) => _openBusinessInvoiceCheckout(invoiceId),
          onPayInvoiceWithRoth: (invoiceId) =>
              _openBusinessInvoiceCheckout(invoiceId, useRoth: true),
          onDownloadInvoice: _downloadBusinessInvoice,
          onBuyRoth: _openBusinessRothCheckout,
          onCreateDelivery: () => setState(() => _step = _SenderStep.details),
          onHealthPlus: () => setState(() => _step = _SenderStep.healthPlus),
          onGifts: widget.onGifts,
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
          onCancelBooking: _cancelSenderBooking,
        ),
    };
  }

  double get _quoteTotal {
    return _quoteBreakdown.total +
        (_webVanguardEnabled && !_webVanguardRequired
            ? _webVanguardAddOnPriceGbp
            : 0);
  }

  bool get _hasConfirmedWeight {
    return _confirmedWeightKg != null &&
        _confirmedWeightKg! > 0 &&
        _confirmedWeightBand != null;
  }

  DeliveryClassification get _deliveryClassification {
    final pricingWeightKg = DeliveryPricing.checkoutPricingWeightKg(
      userEnteredWeightKg: _senderEnteredWeightKg ??
          DeliveryPricing.parseWeightKg(_weight.text, fallbackKg: 0),
      irisEstimatedWeightKg: _irisEstimatedWeightKg,
      matchedCatalogueWeightKg: _matchedCatalogueWeightKg,
    );
    return DeliveryPricing.resolveClassification(
      description: '',
      userEnteredWeightKg: pricingWeightKg,
      irisEstimateKg: null,
      historicalVerifiedMaxKg: null,
      confidence: _irisWeightConfidence ?? 'unknown',
    );
  }

  double? get _matchedCatalogueWeightKg {
    final singleWeight = _irisSingleItemWeightKg;
    if (singleWeight == null || singleWeight <= 0) return null;
    final quantity = _irisQuantity < 1 ? 1 : _irisQuantity;
    return singleWeight * quantity;
  }

  bool get _hasValidatedRoute {
    return _pickupAddressVerified &&
        _dropoffAddressVerified &&
        _confirmedRouteDistanceMiles != null &&
        _confirmedRouteDistanceMiles! > 0;
  }

  bool get _pickupAddressVerified => _validatedPickup?.isVerified == true;

  bool get _dropoffAddressVerified => _validatedDropoff?.isVerified == true;

  bool get _canAnalyzeDelivery {
    return _hasValidatedRoute &&
        _hasRequiredContactDetails &&
        _hasValidDeliveryTiming &&
        !_analyzing;
  }

  bool get _hasValidDeliveryTiming {
    return switch (_deliveryTimingType) {
      'asap' => true,
      'today' => _scheduledPickupWindow.text.trim().isNotEmpty &&
          _scheduledDropoffWindow.text.trim().isNotEmpty,
      'scheduled' => _scheduledPickupDate.text.trim().isNotEmpty &&
          _scheduledDropoffDate.text.trim().isNotEmpty &&
          _scheduledPickupWindow.text.trim().isNotEmpty &&
          _scheduledDropoffWindow.text.trim().isNotEmpty,
      _ => false,
    };
  }

  void _setDeliveryTimingType(String value) {
    final today = _dateInputValue(DateTime.now());
    setState(() {
      _deliveryTimingType = value;
      _scheduledPickupDate.clear();
      _scheduledPickupWindow.clear();
      _scheduledDropoffDate.clear();
      _scheduledDropoffWindow.clear();
      if (value == 'asap') {
        _scheduledPickupDate.text = today;
        _scheduledPickupWindow.text = 'ASAP';
        _scheduledDropoffDate.text = today;
        _scheduledDropoffWindow.text = 'ASAP';
      } else if (value == 'today') {
        _scheduledPickupDate.text = today;
        _scheduledDropoffDate.text = today;
      }
    });
  }

  static String _dateInputValue(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
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
    final pickup = _validatedPickup!;
    final dropoff = _validatedDropoff!;
    if (_coordinatesAreSame(pickup.lat, pickup.lng, dropoff.lat, dropoff.lng)) {
      return 'Pickup and drop-off cannot be the same place.';
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
        DeliveryPricing.vehicleCanCarryDelivery(
          _effectiveVehicle.name,
          _vehicleSuitability,
        ) &&
        !(classification.finalWeightBand != 'Small Parcel' &&
            _effectiveVehicle.name == 'Motorbike');
  }

  _VehicleOption get _effectiveVehicle {
    if (DeliveryPricing.vehicleCanCarryDelivery(
      _selectedVehicle.name,
      _vehicleSuitability,
    )) {
      return _selectedVehicle;
    }
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
      highValue: _irisValueSensitive,
      vanguardRequired: _irisVanguardRecommended,
      stackable: _irisStackable,
      quantity: _irisQuantity,
      singleItemWeightKg: _irisSingleItemWeightKg,
      handlingNotes: _irisHandlingNotes,
    );
  }

  DeliveryPricingBreakdown get _quoteBreakdown {
    final classification = _deliveryClassification;
    final chargeableWeightKg = classification.finalWeightKg;
    final distanceMiles = _confirmedRouteDistanceMiles ?? 0;
    final baseQuote = DeliveryPricing.calculate(
      DeliveryPricingInput(
        distanceMiles: distanceMiles,
        weightKg: chargeableWeightKg,
        vehicleType: _effectiveVehicle.name,
        quantity: _irisQuantity,
        singleItemWeightKg: _irisSingleItemWeightKg,
        stackable: _irisStackable,
        express: _selectedSpeed == 'Express',
      ),
    );
    return _specialHandling.applyTo(baseQuote);
  }

  void _logCheckoutPricing() {
    if (!kDebugMode) return;
    final classification = _deliveryClassification;
    final quote = _quoteBreakdown;
    debugPrint('[CIRCUM pricing] itemName=${_description.text.trim()}');
    debugPrint('[CIRCUM pricing] quantity=$_irisQuantity');
    debugPrint('[CIRCUM pricing] userEnteredWeight=$_senderEnteredWeightKg');
    debugPrint('[CIRCUM pricing] irisEstimatedWeight=$_irisEstimatedWeightKg');
    debugPrint(
      '[CIRCUM pricing] matchedCatalogueWeight=$_matchedCatalogueWeightKg',
    );
    debugPrint(
      '[CIRCUM pricing] finalPricingWeightKg=${classification.finalWeightKg}',
    );
    debugPrint(
      '[CIRCUM pricing] pricingWeightKg=${classification.finalWeightKg}',
    );
    debugPrint('[CIRCUM pricing] weightBand=${quote.weightCategory}');
    debugPrint('[CIRCUM pricing] vehicleType=${_effectiveVehicle.name}');
    debugPrint('[CIRCUM pricing] finalCheckoutPrice=${quote.total}');
  }

  SpecialHandlingResult get _specialHandling => SpecialHandlingEngine.evaluate(
        description: _description.text,
        itemName: _irisMatchedItemName,
        pickupAccess: _pickupAccess,
        dropoffAccess: _dropoffAccess,
      );

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
        'Circum booking check: pickup=${_validatedPickup?.displayAddress}, '
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

  SenderDeliveryRecord? get _activeSenderDelivery {
    for (final delivery in _senderDeliveries) {
      if (_isActiveSenderDeliveryStatus(delivery.status)) return delivery;
    }
    return null;
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
      var senderRestoreTimedOut = false;
      final senderAllowed = await _allowSenderUser(user).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          senderRestoreTimedOut = true;
          return false;
        },
      );
      if (!senderAllowed) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() {
          _senderAuthLoading = false;
          _senderProfileMessage = senderRestoreTimedOut
              ? 'We could not restore your session. Sign in again to continue.'
              : 'Use a Circum account here. Circum Rider and admin accounts have their own sign-in.';
        });
        return;
      }
      _attachSender(user);
      await _loadSenderDeliveries(user.uid);
      await _loadBusinessWorkspaces(user.uid);
      await _loadSenderRothBalance();
      await _handleSenderCheckoutReturn();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _senderAuthLoading = false;
        _senderProfileMessage = 'We could not load your profile just now.';
      });
    }
  }

  Future<void> _handleSenderCheckoutReturn() async {
    if (_senderCheckoutReturnHandled) return;
    final result = Uri.base.queryParameters['sender_payment'];
    if (result == null) return;
    _senderCheckoutReturnHandled = true;
    if (result == 'cancelled') {
      if (!mounted) return;
      setState(() {
        _step = _SenderStep.payment;
        _checkoutState = _CheckoutState.awaitingPayment;
        _firebaseError =
            'Payment was cancelled. Your delivery has not been created.';
      });
      return;
    }
    if (result != 'success') return;
    final checkoutSessionId = Uri.base.queryParameters['checkoutSessionId'];
    final paymentSessionId = Uri.base.queryParameters['paymentSessionId'];
    if (checkoutSessionId == null || paymentSessionId == null) return;
    if (!mounted) return;
    setState(() {
      _step = _SenderStep.payment;
      _checkoutState = _CheckoutState.processingPayment;
      _firebaseError = 'Confirming your payment with Stripe...';
    });
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('finalizeSenderWebCheckout')
          .call({
        'checkoutSessionId': checkoutSessionId,
        'paymentSessionId': paymentSessionId,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final requestId = '${data['requestId'] ?? data['deliveryId'] ?? ''}';
      if (requestId.isNotEmpty) {
        _listenToRequest(requestId);
        _listenToChat(requestId);
      }
      await _loadSenderDeliveries(_senderUser!.uid);
      if (!mounted) return;
      setState(() {
        _activeOrderId = requestId;
        _activeRequestDocId = requestId;
        _checkoutState = _CheckoutState.matchingRiders;
        _broadcasting = true;
        _firebaseOnline = true;
        _firebaseError = null;
        _step = _SenderStep.tracking;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _checkoutState = _CheckoutState.failed;
        _broadcasting = false;
        _firebaseError = error.message ??
            'Stripe payment could not be confirmed. Please contact support.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkoutState = _CheckoutState.failed;
        _broadcasting = false;
        _firebaseError =
            'Stripe payment could not be confirmed. Please contact support.';
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
      _loadBusinessWorkspaces(user.uid);
      if (profile.isLegend &&
          profile.legendNumber != null &&
          profile.legendCelebrationSeenAt == null &&
          !_legendCelebrationShowing) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showLegendCelebration(profile),
        );
      }
    });
    _listenForDeliveryAdjustments(user.uid);
    _loadSenderRothBalance();
  }

  Future<void> _loadSenderRothBalance() async {
    try {
      await _ensureFirebaseReady();
      final result = await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('getSenderRothBalance').call<Map<String, dynamic>>();
      final data = Map<String, dynamic>.from(result.data);
      if (!mounted) return;
      setState(() {
        _healthRothBalance = (data['availableRoth'] as num?)?.toDouble() ??
            (data['balance'] as num?)?.toDouble() ??
            0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _healthRothBalance = 0);
    }
  }

  Future<void> _showLegendCelebration(SenderProfile profile) async {
    if (!mounted || _legendCelebrationShowing) return;
    _legendCelebrationShowing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: _LegendCard(
            colors: widget.colors,
            name: profile.fullName.isEmpty ? 'Circum member' : profile.fullName,
            number: profile.legendNumber!,
            awardedAt: profile.legendAwardedAt,
            celebratory: true,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('markSenderLegendCelebrationSeen')
          .call({'profileId': profile.id});
    } finally {
      _legendCelebrationShowing = false;
    }
  }

  void _listenForDeliveryAdjustments(String senderId) {
    _deliveryAdjustmentSub?.cancel();
    _deliveryAdjustmentSub = FirebaseFirestore.instance
        .collection('deliveryAdjustments')
        .where('senderId', isEqualTo: senderId)
        .limit(20)
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;
        final pending = snapshot.docs.where((doc) {
          final status = '${doc.data()['status'] ?? ''}';
          return {
            'awaiting_admin_review',
            'more_evidence_requested',
            'awaiting_sender_payment',
            'rejected_by_admin',
          }.contains(status);
        }).toList();
        if (pending.isEmpty) return;
        pending.sort(
          (a, b) => _timestampMillis(
            b.data()['createdAt'],
          ).compareTo(_timestampMillis(a.data()['createdAt'])),
        );
        final doc = pending.first;
        if (_visibleAdjustmentId == doc.id) return;
        _visibleAdjustmentId = doc.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showSenderAdjustmentDialog(doc.id, doc.data());
        });
      },
      onError: (error) {
        debugPrint('Could not load delivery adjustment: $error');
      },
    );
  }

  static int _timestampMillis(Object? value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is num) return value.toInt();
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is String) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  Future<void> _showSenderAdjustmentDialog(
    String adjustmentId,
    Map<String, dynamic> adjustment,
  ) async {
    var busy = false;
    String? error;
    final status = '${adjustment['status'] ?? ''}';
    final approvedForPayment = status == 'awaiting_sender_payment';
    final moreEvidence = status == 'more_evidence_requested';
    final rejected = status == 'rejected_by_admin';
    final title = rejected
        ? 'Adjustment rejected'
        : approvedForPayment
            ? 'Adjustment approved'
            : moreEvidence
                ? 'More evidence requested'
                : 'Adjustment under review';
    await showDialog<void>(
      context: context,
      barrierDismissible: !approvedForPayment,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _senderAdjustmentStateCopy(
                    status: status,
                    note: '${adjustment['adminReviewNote'] ?? ''}',
                  ),
                ),
                const SizedBox(height: 16),
                _adjustmentTimeline(status),
                const SizedBox(height: 16),
                Text(
                  _discrepancyReasonLabel('${adjustment['riderReason'] ?? ''}'),
                ),
                const SizedBox(height: 10),
                _adjustmentPriceRow(
                  'Original quote',
                  adjustment['originalQuote'],
                ),
                _adjustmentPriceRow(
                  'Revised quote',
                  adjustment['revisedQuote'],
                ),
                _adjustmentPriceRow(
                  'Additional amount',
                  adjustment['additionalAmount'],
                  emphasized: true,
                ),
                if ('${adjustment['observations'] ?? ''}'
                    .trim()
                    .isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Updated delivery evidence is attached for Admin review.',
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
          ),
          actions: [
            if (!approvedForPayment)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            if (approvedForPayment)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        setDialogState(() => busy = true);
                        try {
                          await FirebaseFunctions.instance
                              .httpsCallable('cancelAdjustedCollection')
                              .call({'adjustmentId': adjustmentId});
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();
                        } on FirebaseFunctionsException catch (exception) {
                          setDialogState(() {
                            busy = false;
                            error = exception.message ??
                                'Could not cancel this collection.';
                          });
                        }
                      },
                child: const Text('Cancel Collection'),
              ),
            if (approvedForPayment)
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setDialogState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          if (Env.stripePublishableKey.trim().isEmpty) {
                            throw StateError(
                              'Stripe publishable key is not configured.',
                            );
                          }
                          Stripe.publishableKey = Env.stripePublishableKey;
                          await Stripe.instance.applySettings();
                          final payment = await FirebaseFunctions.instance
                              .httpsCallable('createDeliveryAdjustmentPayment')
                              .call({'adjustmentId': adjustmentId});
                          final data = Map<String, dynamic>.from(
                            payment.data as Map,
                          );
                          await Stripe.instance.initPaymentSheet(
                            paymentSheetParameters: SetupPaymentSheetParameters(
                              paymentIntentClientSecret:
                                  '${data['clientSecret']}',
                              merchantDisplayName: 'Circum',
                              style: ThemeMode.dark,
                            ),
                          );
                          await Stripe.instance.presentPaymentSheet();
                          await FirebaseFunctions.instance
                              .httpsCallable(
                            'finalizeDeliveryAdjustmentPayment',
                          )
                              .call({'adjustmentId': adjustmentId});
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();
                          final uid = _senderUser?.uid;
                          if (uid != null) await _loadSenderDeliveries(uid);
                        } catch (exception) {
                          setDialogState(() {
                            busy = false;
                            error = exception is FirebaseFunctionsException
                                ? exception.message
                                : 'Payment was not completed. Please try again.';
                          });
                        }
                      },
                child: Text(busy ? 'Please wait...' : 'Pay & Continue'),
              ),
          ],
        ),
      ),
    );
  }

  String _senderAdjustmentStateCopy({
    required String status,
    required String note,
  }) {
    final cleanNote = note.trim();
    switch (status) {
      case 'more_evidence_requested':
        return cleanNote.isEmpty
            ? 'Admin has requested additional information before making a decision.'
            : 'Admin has requested additional information: $cleanNote';
      case 'awaiting_sender_payment':
        return 'Adjustment approved. Review the updated delivery summary and complete the additional payment to continue.';
      case 'rejected_by_admin':
        return cleanNote.isEmpty
            ? 'Adjustment rejected. The original booking remains authoritative and the delivery can continue.'
            : 'Adjustment rejected: $cleanNote';
      default:
        return 'Rider has reported a discrepancy. Delivery and payment are temporarily paused while Admin reviews the evidence.';
    }
  }

  Widget _adjustmentTimeline(String status) {
    final second = switch (status) {
      'more_evidence_requested' => 'More Evidence Requested',
      'awaiting_sender_payment' => 'Approved',
      'rejected_by_admin' => 'Rejected',
      _ => 'Awaiting Review',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 18),
            const SizedBox(width: 8),
            const Text('Submitted'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.arrow_forward_rounded, size: 16),
            ),
            Flexible(child: Text(second)),
          ],
        ),
      ),
    );
  }

  Widget _adjustmentPriceRow(
    String label,
    Object? value, {
    bool emphasized = false,
  }) {
    final amount = value is num ? value.toDouble() : double.tryParse('$value');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '£${(amount ?? 0).toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static String _discrepancyReasonLabel(String reason) => switch (reason) {
        'weight_exceeded' => 'The collected parcel is heavier than booked.',
        'dimensions_exceeded' =>
          'The parcel dimensions exceed the booking details.',
        'additional_undeclared_items' =>
          'Additional undeclared items were presented.',
        'item_differs_from_booking' =>
          'The item differs from the original booking.',
        _ => 'The rider reported a material load discrepancy.',
      };

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
        setState(
          () => _senderProfileMessage =
              'This account is not a Circum account. Use the Circum Rider or admin sign-in instead.',
        );
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
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('updateSenderProfile').call({
        'displayName': _senderName.text.trim(),
        'phone': _senderPhone.text.trim(),
      });
      _availableRoles = {CircumRole.sender};
      _attachSender(user);
      await _loadSenderDeliveries(user.uid);
      setState(() => _senderProfileMessage = 'Your Circum profile is ready.');
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
      setState(
        () => _senderProfileMessage =
            'Password reset sent. Check your email and follow the secure link.',
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(
        () => _senderProfileMessage = switch (error.code) {
          'invalid-email' => 'Enter a valid email address.',
          'user-not-found' => 'No Circum profile found for that email.',
          _ =>
            'We could not send the reset email. Check the address and try again.',
        },
      );
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
      setState(
        () => _senderSecurityMessage =
            'Enter your current password and make sure the new passwords match.',
      );
      return;
    }
    setState(() {
      _senderSecurityBusy = true;
      _senderSecurityMessage = 'Updating password...';
    });
    try {
      await _ensureFirebaseReady();
      await _reauthenticateSender(current);
      await (_senderUser ?? FirebaseAuth.instance.currentUser)?.updatePassword(
        next,
      );
      _senderCurrentPassword.clear();
      _senderNewPassword.clear();
      _senderConfirmNewPassword.clear();
      if (!mounted) return;
      setState(() => _senderSecurityMessage = 'Password updated.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(
        () => _senderSecurityMessage = _friendlySenderAuthMessage(error),
      );
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
      setState(
        () => _senderSecurityMessage =
            'Enter the new email and your current password.',
      );
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
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('requestSenderEmailChange')
          .call({'pendingEmail': nextEmail});
      _senderNewEmail.clear();
      _senderEmailChangePassword.clear();
      if (!mounted) return;
      setState(
        () => _senderSecurityMessage =
            'Verification sent. Open the email link to confirm the new address.',
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(
        () => _senderSecurityMessage = _friendlySenderAuthMessage(error),
      );
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
    if (!roles.contains(CircumRole.rider) &&
        !roles.contains(CircumRole.admin)) {
      final result = await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('ensureSenderAccount').call();
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['allowed'] == true) {
        setState(() => _availableRoles = {CircumRole.sender});
        return true;
      }
    }
    return false;
  }

  Future<Set<CircumRole>> _rolesForSenderUser(User user) async {
    final token = await user.getIdTokenResult(true);
    final claims = token.claims ?? const <String, dynamic>{};
    final db = FirebaseFirestore.instance;
    final userDoc = await _safeRoleDocument(
      db.collection('users').doc(user.uid),
    );
    final riderDoc = await _safeRoleDocument(
      db.collection('riderProfiles').doc(user.uid),
    );
    final adminDoc = await _safeRoleDocument(
      db.collection('adminUsers').doc(user.uid),
    );
    return RoleAccessPolicy.resolveRoles(
      claims: claims,
      user: userDoc,
      rider: riderDoc,
      adminUser: adminDoc,
    );
  }

  Future<Map<String, dynamic>> _safeRoleDocument(
    DocumentReference<Map<String, dynamic>> reference,
  ) async {
    try {
      final snapshot = await reference.get();
      return snapshot.data() ?? const {};
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' || error.code == 'not-found') {
        return const {};
      }
      rethrow;
    }
  }

  Future<void> _signOutSender() async {
    await FirebaseAuth.instance.signOut();
    await _senderSub?.cancel();
    await _deliveryAdjustmentSub?.cancel();
    if (!mounted) return;
    setState(() {
      _senderUser = null;
      _senderProfile = null;
      _senderDeliveries = const [];
      _selectedSenderDelivery = null;
      _senderDeliveryLoadError = null;
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
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('updateSenderProfile').call({
        'displayName': _senderName.text.trim(),
        'phone': _senderPhone.text.trim(),
        'communicationPreferences': profile.communicationPreferences.isEmpty
            ? const {'email': true, 'sms': true}
            : profile.communicationPreferences,
      });
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
      setState(
        () => _senderProfileMessage =
            'Choose a verified address suggestion before saving.',
      );
      return;
    }
    final labelText = _savedAddressLabel.text.trim();
    final normalizedLabel = switch (labelText.toLowerCase()) {
      'home' => 'home',
      'work' => 'work',
      _ => 'other',
    };
    final customLabel = normalizedLabel == 'other'
        ? (labelText.isEmpty ? 'Saved address' : labelText)
        : '';
    final addressLine1 = [
      validated.buildingNumber,
      validated.street,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
    final city = (validated.city?.trim().isNotEmpty == true
            ? validated.city!.trim()
            : _cityFromAddress(validated.displayAddress)) ??
        'United Kingdom';
    setState(() => _senderProfileSaving = true);
    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('saveSenderSavedAddress').call({
        'label': normalizedLabel,
        'customLabel': customLabel,
        'address': {
          'formattedAddress': validated.displayAddress,
          'addressLine1': addressLine1.isEmpty ? address : addressLine1,
          if (validated.street?.trim().isNotEmpty == true)
            'addressLine2': validated.street!.trim(),
          'city': city,
          if (validated.county?.trim().isNotEmpty == true)
            'county': validated.county!.trim(),
          'postcode': validated.postcode ?? '',
          'country': validated.country?.trim().isNotEmpty == true
              ? validated.country!.trim()
              : 'United Kingdom',
          'latitude': validated.lat,
          'longitude': validated.lng,
          if (validated.placeId?.trim().isNotEmpty == true)
            'placeId': validated.placeId,
          'provider': validated.provider,
          'locationId': validated.locationId,
        },
        'deliveryInstructions': '',
        'isDefaultPickup': _savedAddressType == 'pickup',
        'isDefaultDropoff': _savedAddressType == 'dropoff',
      });
      _savedAddress.clear();
      _validatedSavedAddress = null;
      setState(() => _senderProfileMessage = 'Saved address added.');
    } finally {
      if (mounted) setState(() => _senderProfileSaving = false);
    }
  }

  Future<void> _loadSenderDeliveries(String uid) async {
    try {
      final db = FirebaseFirestore.instance;
      final snapshots = await Future.wait([
        db
            .collection('deliveryRequests')
            .where('senderId', isEqualTo: uid)
            .get(),
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
      final records = SenderProfileService.ownDeliveries(
        uid,
        byId.values,
      ).toList(growable: false)
        ..sort((a, b) {
          final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return right.compareTo(left);
        });
      if (!mounted) return;
      setState(() {
        _senderDeliveries = records;
        _senderDeliveryLoadError = null;
      });
    } catch (error) {
      debugPrint('Could not load sender deliveries: $error');
      if (!mounted) return;
      setState(() {
        _senderDeliveries = const [];
        _senderDeliveryLoadError =
            'We could not load your delivery status. Please refresh or contact support.';
      });
    }
  }

  Future<void> _loadBusinessWorkspaces(String uid) async {
    if (_businessLoading) return;
    setState(() => _businessLoading = true);
    try {
      final db = FirebaseFirestore.instance;
      final userSnap = await db.collection('users').doc(uid).get();
      final userData = userSnap.data() ?? <String, dynamic>{};
      final userEmail = (_senderUser?.email ?? '').trim().toLowerCase();
      final ids = <String>{
        for (final id
            in (userData['businessWorkspaceIds'] as List? ?? const []))
          '$id',
        if ('${userData['lastBusinessWorkspaceId'] ?? ''}'.trim().isNotEmpty)
          '${userData['lastBusinessWorkspaceId']}',
      };
      final ownedAccounts = await db
          .collection('businessAccounts')
          .where('createdByUserId', isEqualTo: uid)
          .limit(20)
          .get();
      for (final doc in ownedAccounts.docs) {
        ids.add(doc.id);
      }
      final teamLookupValues = [uid, if (userEmail.isNotEmpty) userEmail];
      final teamAccounts = await db
          .collection('businessAccounts')
          .where('teamMemberIds', arrayContainsAny: teamLookupValues)
          .limit(20)
          .get();
      for (final doc in teamAccounts.docs) {
        ids.add(doc.id);
      }
      final memberships = await db
          .collection('businessMemberships')
          .where('userId', isEqualTo: uid)
          .get();
      for (final doc in memberships.docs) {
        final status = '${doc.data()['status'] ?? 'active'}';
        if (status == 'active') ids.add('${doc.data()['businessId'] ?? ''}');
      }
      ids.removeWhere((id) => id.trim().isEmpty);
      final accounts = <Map<String, dynamic>>[];
      for (final id in ids) {
        final snap = await db.collection('businessAccounts').doc(id).get();
        if (snap.exists) {
          accounts.add({'id': snap.id, ...snap.data()!});
        }
      }
      final selectedId = _selectedBusinessId != null &&
              accounts.any((account) => account['id'] == _selectedBusinessId)
          ? _selectedBusinessId!
          : accounts.isEmpty
              ? null
              : '${accounts.first['id']}';
      final invoices = <Map<String, dynamic>>[];
      final requests = <Map<String, dynamic>>[];
      final audits = <Map<String, dynamic>>[];
      Map<String, dynamic>? wallet;
      if (selectedId != null) {
        final invoiceSnap = await db
            .collection('businessInvoices')
            .where('businessId', isEqualTo: selectedId)
            .limit(80)
            .get();
        invoices.addAll(
          invoiceSnap.docs.map((doc) => {'id': doc.id, ...doc.data()}),
        );
        final requestSnap = await db
            .collection('businessJoinRequests')
            .where('businessId', isEqualTo: selectedId)
            .limit(40)
            .get();
        requests.addAll(
          requestSnap.docs.map((doc) => {'id': doc.id, ...doc.data()}),
        );
        final auditSnap = await db
            .collection('businessAuditLogs')
            .where('businessId', isEqualTo: selectedId)
            .limit(30)
            .get();
        audits.addAll(
          auditSnap.docs.map((doc) => {'id': doc.id, ...doc.data()}),
        );
        final walletSnap =
            await db.collection('business_wallets').doc(selectedId).get();
        if (walletSnap.exists) {
          wallet = {'id': walletSnap.id, ...walletSnap.data()!};
        }
      }
      invoices.sort(
        (a, b) => _timestampMillis(
          b['createdAt'],
        ).compareTo(_timestampMillis(a['createdAt'])),
      );
      audits.sort(
        (a, b) => _timestampMillis(
          b['createdAt'],
        ).compareTo(_timestampMillis(a['createdAt'])),
      );
      if (!mounted) return;
      setState(() {
        _businessAccounts = accounts;
        _selectedBusinessId = selectedId;
        _businessInvoices = invoices;
        _businessJoinRequests = requests;
        _businessAuditLogs = audits;
        _businessWallet = wallet;
        _businessLoading = false;
        Map<String, dynamic>? selectedAccount;
        for (final account in accounts) {
          if (account['id'] == selectedId) {
            selectedAccount = account;
            break;
          }
        }
        if (selectedAccount != null) {
          _populateBusinessControllers(selectedAccount);
        }
      });
    } catch (error) {
      debugPrint('Could not load Business workspaces: $error');
      if (!mounted) return;
      setState(() {
        _businessLoading = false;
        _businessMessage = 'Business could not be loaded. Try again.';
      });
    }
  }

  Map<String, dynamic>? get _selectedBusinessAccount {
    for (final account in _businessAccounts) {
      if (account['id'] == _selectedBusinessId) return account;
    }
    return _businessAccounts.isEmpty ? null : _businessAccounts.first;
  }

  void _populateBusinessControllers(Map<String, dynamic> account) {
    if (_businessCompanyName.text.trim().isEmpty) {
      _businessCompanyName.text = '${account['businessName'] ?? ''}';
    }
    if (_businessEmail.text.trim().isEmpty) {
      _businessEmail.text =
          '${account['contactEmail'] ?? account['billingEmail'] ?? ''}';
    }
    if (_businessPhone.text.trim().isEmpty) {
      _businessPhone.text = '${account['phone'] ?? ''}';
    }
    if (_businessAddress.text.trim().isEmpty) {
      _businessAddress.text = '${account['businessAddress'] ?? ''}';
    }
    if (_businessVatNumber.text.trim().isEmpty) {
      _businessVatNumber.text = '${account['vatNumber'] ?? ''}';
    }
    if (_businessWebsite.text.trim().isEmpty) {
      _businessWebsite.text = '${account['website'] ?? ''}';
    }
  }

  Future<void> _createBusinessAccount() async {
    if (_senderUser == null || _businessBusy) return;
    setState(() {
      _businessBusy = true;
      _businessMessage = 'Creating Business workspace...';
    });
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createBusinessAccount')
          .call({
        'companyName': _businessCompanyName.text.trim(),
        'businessType': _businessType.text.trim(),
        'businessEmail': _businessEmail.text.trim().isEmpty
            ? _senderUser?.email
            : _businessEmail.text.trim(),
        'businessPhone': _businessPhone.text.trim(),
        'businessAddress': _businessAddress.text.trim(),
        'vatNumber': _businessVatNumber.text.trim(),
        'businessSize': '1-10',
        'acceptTerms': true,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      _selectedBusinessId = '${data['businessId']}';
      await _loadBusinessWorkspaces(_senderUser!.uid);
      if (!mounted) return;
      setState(
        () => _businessMessage =
            'Business workspace created. Company code ${data['companyCode']}.',
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _businessMessage =
            error.message ?? 'Business workspace could not be created.',
      );
    } finally {
      if (mounted) setState(() => _businessBusy = false);
    }
  }

  Future<void> _joinBusinessByCode() async {
    if (_senderUser == null || _businessBusy) return;
    setState(() {
      _businessBusy = true;
      _businessMessage = 'Checking company code...';
    });
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final lookup = await functions
          .httpsCallable('lookupBusinessByCompanyCode')
          .call({'companyCode': _businessCompanyCode.text.trim()});
      final found = Map<String, dynamic>.from(lookup.data as Map);
      await functions.httpsCallable('requestBusinessAccess').call({
        'businessId': found['businessId'],
        'role': 'member',
      });
      if (!mounted) return;
      setState(
        () => _businessMessage =
            'Access request sent to ${found['companyName'] ?? 'the company'}.',
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _businessMessage =
            error.message ?? 'Business access request could not be sent.',
      );
    } finally {
      if (mounted) setState(() => _businessBusy = false);
    }
  }

  Future<void> _reviewBusinessRequest(String requestId, bool approved) async {
    if (_senderUser == null || _businessBusy) return;
    setState(() => _businessBusy = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('reviewBusinessAccessRequest')
          .call({'requestId': requestId, 'approved': approved});
      await _loadBusinessWorkspaces(_senderUser!.uid);
      if (!mounted) return;
      setState(
        () => _businessMessage = approved
            ? 'Business access approved.'
            : 'Business access rejected.',
      );
    } finally {
      if (mounted) setState(() => _businessBusy = false);
    }
  }

  Future<void> _saveBusinessProfile() async {
    final businessId = _selectedBusinessId;
    if (_senderUser == null || businessId == null || _businessBusy) return;
    setState(() => _businessBusy = true);
    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('updateBusinessProfile').call({
        'businessId': businessId,
        'businessName': _businessCompanyName.text.trim(),
        'businessType': _businessType.text.trim(),
        'contactEmail': _businessEmail.text.trim(),
        'billingEmail': _businessEmail.text.trim(),
        'phone': _businessPhone.text.trim(),
        'businessAddress': _businessAddress.text.trim(),
        'vatNumber': _businessVatNumber.text.trim(),
        'website': _businessWebsite.text.trim(),
      });
      await _loadBusinessWorkspaces(_senderUser!.uid);
      if (!mounted) return;
      setState(() => _businessMessage = 'Business profile saved.');
    } finally {
      if (mounted) setState(() => _businessBusy = false);
    }
  }

  Future<void> _ensureBusinessCompanyCode({bool rotate = false}) async {
    final businessId = _selectedBusinessId;
    if (_senderUser == null || businessId == null || _businessBusy) return;
    setState(() => _businessBusy = true);
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('ensureBusinessCompanyCode')
          .call<Map<String, dynamic>>({
        'businessId': businessId,
        'rotate': rotate,
      });
      final data = Map<String, dynamic>.from(result.data);
      final code = '${data['companyCode'] ?? ''}'.trim();
      if (code.isEmpty) {
        setState(
          () => _businessMessage =
              'We could not retrieve the company code just now.',
        );
        return;
      }
      setState(() {
        _businessAccounts = _businessAccounts
            .map(
              (account) => account['id'] == businessId
                  ? {...account, 'companyCode': code}
                  : account,
            )
            .toList(growable: false);
        _businessMessage = rotate
            ? 'Company code changed: $code'
            : 'Company code ready: $code';
      });
    } on FirebaseFunctionsException catch (error) {
      setState(
        () => _businessMessage =
            error.message ?? 'We could not retrieve the company code just now.',
      );
    } finally {
      if (mounted) setState(() => _businessBusy = false);
    }
  }

  Future<void> _updateBusinessMemberRole(
    String memberUserId,
    String role,
  ) async {
    final businessId = _selectedBusinessId;
    if (_senderUser == null || businessId == null || _businessBusy) return;
    setState(() => _businessBusy = true);
    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('updateBusinessMemberRole').call({
        'businessId': businessId,
        'memberUserId': memberUserId,
        'role': role,
      });
      await _loadBusinessWorkspaces(_senderUser!.uid);
      if (!mounted) return;
      setState(() => _businessMessage = 'Team role updated.');
    } finally {
      if (mounted) setState(() => _businessBusy = false);
    }
  }

  Future<void> _removeBusinessMember(String memberUserId) async {
    final businessId = _selectedBusinessId;
    if (_senderUser == null || businessId == null || _businessBusy) return;
    setState(() => _businessBusy = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('removeBusinessMember')
          .call({'businessId': businessId, 'memberUserId': memberUserId});
      await _loadBusinessWorkspaces(_senderUser!.uid);
      if (!mounted) return;
      setState(() => _businessMessage = 'Team member removed.');
    } finally {
      if (mounted) setState(() => _businessBusy = false);
    }
  }

  Future<void> _openBusinessInvoiceCheckout(
    String invoiceId, {
    bool useRoth = false,
  }) async {
    final businessId = _selectedBusinessId;
    if (businessId == null || _businessBusy) return;
    setState(() {
      _businessBusy = true;
      _businessMessage = 'Preparing invoice payment...';
    });
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createBusinessInvoiceCheckout')
          .call({
        'businessId': businessId,
        'invoiceId': invoiceId,
        'useRoth': useRoth,
        'returnUrl': 'https://circumuk.com/?app=business',
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final url = '${data['checkoutUrl'] ?? ''}';
      if (url.startsWith('http')) {
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
      } else {
        await _loadBusinessWorkspaces(_senderUser!.uid);
        if (!mounted) return;
        setState(() => _businessMessage = 'Invoice paid with Business Roth.');
      }
    } finally {
      if (mounted) setState(() => _businessBusy = false);
    }
  }

  Future<void> _downloadBusinessInvoice(Map<String, dynamic> invoice) async {
    _downloadBusinessPdf(
      _businessInvoicePdfUri(invoice),
      _businessInvoicePdfFileName(invoice),
    );
    if (!mounted) return;
    setState(() {
      _businessMessage = 'Invoice PDF downloaded. Open it to print or save.';
    });
  }

  Future<void> _openBusinessRothCheckout() async {
    final businessId = _selectedBusinessId;
    final amount = double.tryParse(_businessRothAmount.text.trim()) ?? 0;
    if (businessId == null || amount <= 0 || _businessBusy) return;
    setState(() {
      _businessBusy = true;
      _businessMessage = 'Preparing Roth checkout...';
    });
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createBusinessRothCheckout')
          .call({
        'businessId': businessId,
        'amount': amount,
        'returnUrl': 'https://circumuk.com/?app=business',
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final url = '${data['checkoutUrl'] ?? ''}';
      if (url.startsWith('http')) {
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
      }
    } finally {
      if (mounted) setState(() => _businessBusy = false);
    }
  }

  Future<void> _cancelSenderBooking(SenderDeliveryRecord delivery) async {
    final user = _senderUser;
    if (user == null ||
        !BookingCancellationPolicy.canSenderCancel(delivery.status)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text(
          'The booking will remain in your history and Circum admin records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep booking'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('cancelDelivery').call({'deliveryId': delivery.id});
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['success'] != true) {
        final decision = Map<String, dynamic>.from(
          data['decision'] as Map? ?? {},
        );
        throw StateError(
          '${decision['userFacingMessage'] ?? 'This delivery requires support review.'}',
        );
      }
      await _loadSenderDeliveries(user.uid);
      if (!mounted) return;
      setState(() {
        _selectedSenderDelivery = null;
        _senderProfileMessage = 'Booking cancelled.';
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(
        () => _senderProfileMessage = _friendlySenderFunctionMessage(
          error,
          'We could not cancel this booking. Please try again or contact Circum support.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _senderProfileMessage = _friendlySenderErrorMessage(
          error,
          'We could not cancel this booking. Please try again or contact Circum support.',
        ),
      );
    }
  }

  String _friendlySenderFunctionMessage(
    FirebaseFunctionsException error,
    String fallback,
  ) {
    final message = error.message?.trim();
    if (message != null &&
        message.isNotEmpty &&
        !_looksLikeTechnicalError(message)) {
      return message;
    }
    return fallback;
  }

  String _friendlySenderErrorMessage(Object error, String fallback) {
    final message = '$error'.replaceFirst('Bad state: ', '').trim();
    if (message.isNotEmpty && !_looksLikeTechnicalError(message)) {
      return message;
    }
    return fallback;
  }

  bool _looksLikeTechnicalError(String message) {
    final value = message.toLowerCase();
    return value.contains('firebase') ||
        value.contains('internal') ||
        value.contains('exception') ||
        value.contains('platformexception') ||
        value.contains('cloud functions') ||
        value.contains('https callable') ||
        value.contains('stack trace') ||
        value.contains('null check operator') ||
        value.contains('bad state');
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
      if (_parcelPhoto != null) {
        _parcelPhotoMessage = 'IRIS is reviewing your item...';
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final senderWeight = DeliveryPricing.parseWeightKg(
      _weight.text,
      fallbackKg: 0,
    );
    final estimate = await _estimateWeightWithIris(_irisImageInsight);
    final decision = _resolvePricingWeight(
      estimate: estimate,
      senderWeightKg: senderWeight > 0 ? senderWeight : null,
    );
    setState(() {
      _senderEnteredWeightKg = senderWeight > 0 ? senderWeight : null;
      _irisEstimatedWeightKg =
          decision.source == 'repository_match' && decision.weightKg != null
              ? math.max(estimate.weightKg, decision.weightKg!)
              : estimate.weightKg;
      _irisWeightBand = estimate.weightBand;
      _irisWeightConfidence = estimate.confidence;
      _irisWeightExplanation = estimate.explanation;
      _irisWeightSource = estimate.weightSource;
      _irisMatchedItemName = estimate.matchedItemName;
      _irisQuantity = estimate.quantity;
      _irisSingleItemWeightKg = estimate.singleItemWeightKg;
      _irisWeightConfidenceScore = estimate.confidenceScore;
      _irisHistoricalVerifiedWeightKg = estimate.historicalVerifiedWeightKg;
      _irisLearningReason = estimate.learningReason;
      _irisTypicalDimensions = estimate.typicalDimensions;
      _irisVehicleSuitability = estimate.vehicleSuitability;
      _irisFragile = estimate.fragile;
      _irisValueSensitive = estimate.valueSensitive;
      _irisVanguardRecommended = estimate.vanguardRecommended;
      _irisStackable = estimate.stackable;
      _irisHandlingNotes = estimate.handlingNotes;
      _weightVerificationRequired = decision.verificationRequired;
      _weightPricingReason = decision.reason;
      _analyzing = false;
      if (_parcelPhoto != null) {
        _parcelPhotoMessage = estimate.weightSource == 'photo_match'
            ? 'IRIS reviewed the photo and item details.'
            : 'IRIS used the photo with your item details.';
      }
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
      if (mounted) {
        setState(() {
          _checkoutState = _CheckoutState.awaitingPayment;
          _step = _SenderStep.vehicle;
        });
      }
      _logCheckoutPricing();
    }
  }

  Future<void> _pickParcelPhoto() async {
    setState(() {
      _parcelPhotoBusy = true;
      _parcelPhotoMessage = null;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 82,
      );
      if (!mounted) return;
      if (picked != null && !await _parcelPhotoIsSafe(picked)) {
        setState(() {
          _parcelPhoto = null;
          _parcelPhotoCapturedAt = null;
          _irisPhotoAnalysisId = null;
          _irisImageInsight = null;
          _parcelPhotoMessage =
              'Choose a JPG, PNG, WebP, or HEIC image under 10MB.';
        });
        return;
      }
      final insight =
          picked == null ? null : await _analyseParcelPhotoForIris(picked);
      if (!mounted) return;
      setState(() {
        _parcelPhoto = picked;
        _parcelPhotoCapturedAt = picked == null ? null : DateTime.now();
        _irisPhotoAnalysisId = insight?.analysisId;
        _irisImageInsight = insight;
        _parcelPhotoMessage = picked == null
            ? 'No parcel photo selected.'
            : 'Parcel photo added. IRIS will use it with your item details.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _parcelPhotoMessage =
            'Parcel photo could not be added. You can continue safely.';
      });
    } finally {
      if (mounted) setState(() => _parcelPhotoBusy = false);
    }
  }

  Future<bool> _parcelPhotoIsSafe(XFile photo) async {
    final name = photo.name.toLowerCase();
    final allowedExtension = name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.heic') ||
        name.endsWith('.heif');
    final mime = (photo.mimeType ?? '').toLowerCase();
    final allowedMime = mime.isEmpty ||
        mime.startsWith('image/') ||
        mime == 'application/octet-stream';
    final length = await photo.length();
    return allowedExtension && allowedMime && length <= 10 * 1024 * 1024;
  }

  Future<_IrisImageInsight> _analyseParcelPhotoForIris(XFile photo) async {
    try {
      await _ensureFirebaseReady();
      final bytes = await photo.readAsBytes();
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('analyseParcelPhotoForIris')
          .call({
        'imageBase64': base64Encode(bytes),
        'contentType': photo.mimeType,
        'fileName': photo.name,
        'description': _description.text.trim(),
        'declaredWeightText': _weight.text.trim(),
        'distanceMiles': _confirmedRouteDistanceMiles,
        'selectedSpeed': _selectedSpeed,
        'vehicleType': _effectiveVehicle.name,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return _IrisImageInsight.fromBackend(data, fallbackFileName: photo.name);
    } catch (_) {
      return _IrisImageInsight.fallback(photo.name);
    }
  }

  Future<Map<String, dynamic>> _uploadParcelPhoto(String requestId) async {
    final photo = _parcelPhoto;
    if (photo == null) {
      return {'hasPhoto': false, 'analysisStatus': 'not_provided'};
    }
    try {
      final bytes = await photo.readAsBytes();
      final safeName = photo.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final storagePath =
          'parcel_photos/$requestId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final ref = FirebaseStorage.instance.ref(storagePath);
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      return {
        'hasPhoto': true,
        'imageUrl': url,
        'photoUrl': url,
        'storagePath': storagePath,
        'capturedAt': _parcelPhotoCapturedAt == null
            ? null
            : Timestamp.fromDate(_parcelPhotoCapturedAt!),
        'uploadedAt': FieldValue.serverTimestamp(),
        'analysisStatus': 'attached_for_iris_review',
      };
    } catch (_) {
      return {
        'hasPhoto': true,
        'imageUrl': null,
        'photoUrl': null,
        'storagePath': null,
        'capturedAt': _parcelPhotoCapturedAt == null
            ? null
            : Timestamp.fromDate(_parcelPhotoCapturedAt!),
        'uploadedAt': null,
        'analysisStatus': 'upload_failed',
        'requiresIRISReview': true,
      };
    }
  }

  void _confirmIrisWeight() {
    final estimateWeight = _irisEstimatedWeightKg;
    if (estimateWeight == null || estimateWeight <= 0) return;
    final senderWeight = DeliveryPricing.parseWeightKg(
      _weight.text,
      fallbackKg: 0,
    );
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
    final typedWeight = DeliveryPricing.parseWeightKg(
      _weight.text,
      fallbackKg: 0,
    );
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
    final trustedKnownItem = estimate.confidence == 'high' &&
        (estimate.weightSource == 'known_product_lookup' ||
            estimate.weightSource == 'repository_match');
    if (trustedKnownItem) {
      final trustedDecision =
          IrisWeightEstimator.resolveTrustedKnownItemPricing(
        description: _description.text,
        quantity: estimate.quantity,
        userWeightKg: senderWeightKg ?? 0,
        trustedItemWeightKg: estimate.weightKg,
        historicalMatches: estimate.historicalVerifiedWeightKg == null
            ? const []
            : [estimate.historicalVerifiedWeightKg!],
      );
      final pricingWeight = trustedDecision.pricingWeightKg;
      return _WeightPricingDecision(
        weightKg: pricingWeight,
        weightBand: DeliveryPricing.weightBandFor(pricingWeight).category,
        source: 'repository_match',
        message: trustedDecision.explanation ??
            'IRIS used the verified item weight with a packaging allowance.',
        reason: trustedDecision.explanation ??
            'Verified catalogue weight used for pricing.',
        verificationRequired: true,
      );
    }
    final knownItemDecision = senderWeightKg != null && senderWeightKg > 0
        ? IrisWeightEstimator.resolveKnownItemWeight(
            description: _description.text,
            senderWeightKg: senderWeightKg,
          )
        : null;
    if (knownItemDecision?.unusual == true && estimate.confidence == 'high') {
      final pricingWeight = knownItemDecision!.pricingWeightKg;
      return _WeightPricingDecision(
        weightKg: pricingWeight,
        weightBand: DeliveryPricing.weightBandFor(pricingWeight).category,
        source: 'repository_match',
        message: knownItemDecision.warning!,
        reason: knownItemDecision.warning!,
        verificationRequired: true,
      );
    }
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
            ? 'Iris is not confident and the details may indicate a different weight band. Confirm your weight to continue; the Circum Rider will verify at pickup.'
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

  Future<_IrisWeightEstimate> _estimateWeightWithIris(
    _IrisImageInsight? imageInsight,
  ) async {
    final text = '${_description.text} ${_pickup.text} ${_dropoff.text}'
        .trim()
        .toLowerCase();
    final knownProduct = _knownProductWeightEstimate(text);
    if (knownProduct != null) {
      return _applyVerifiedParcelLearning(knownProduct, text);
    }

    double estimate = 2;
    final quantity = IrisWeightEstimator.extractQuantity(_description.text);
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

    final totalEstimate = estimate * quantity;
    final estimateResult = _IrisWeightEstimate(
      weightKg: totalEstimate,
      weightBand: DeliveryPricing.weightBandFor(totalEstimate).category,
      confidence: confidence,
      explanation: explanation,
      packageType: packageType,
      requiresVehicleReview: vehicleReview,
      weightSource: 'category_fallback',
      confidenceScore: _scoreForIrisConfidence(confidence),
      quantity: quantity,
      singleItemWeightKg: estimate,
    );
    return _applyVerifiedParcelLearning(
      _mergeImageInsightWithTextEstimate(estimateResult, imageInsight),
      text,
    );
  }

  _IrisWeightEstimate _mergeImageInsightWithTextEstimate(
    _IrisWeightEstimate textEstimate,
    _IrisImageInsight? imageInsight,
  ) {
    if (imageInsight == null) return textEstimate;
    final imageTotalWeight =
        imageInsight.estimatedWeightKg * textEstimate.quantity;
    final imageBand = DeliveryPricing.weightBandFor(imageTotalWeight).category;
    final textBand = DeliveryPricing.weightBandFor(textEstimate.weightKg);
    final imageBandRank =
        DeliveryPricing.weightBandFor(imageTotalWeight).maxKg ??
            double.infinity;
    final textBandRank = textBand.maxKg ?? double.infinity;
    final strongImage = imageInsight.confidenceScore >= 0.55;
    final shouldUseImage = strongImage &&
        (imageBandRank > textBandRank || textEstimate.confidence == 'low');
    if (!shouldUseImage) {
      return textEstimate.copyWith(
        explanation:
            '${textEstimate.explanation} IRIS also reviewed the photo for handling context.',
        handlingNotes: textEstimate.handlingNotes ?? imageInsight.handlingNotes,
        fragile: textEstimate.fragile || imageInsight.fragilityRisk == 'high',
        requiresVehicleReview:
            textEstimate.requiresVehicleReview || imageInsight.needsHumanReview,
      );
    }
    return textEstimate.copyWith(
      weightKg: math.max(textEstimate.weightKg, imageTotalWeight),
      weightBand: imageBand,
      confidence: imageInsight.confidenceScore >= 0.75 ? 'high' : 'medium',
      explanation:
          'IRIS reviewed the parcel photo and item details, then selected the safest visible weight class.',
      packageType: imageInsight.inferredCategory,
      requiresVehicleReview:
          imageInsight.needsHumanReview || imageTotalWeight > 10,
      weightSource: 'photo_match',
      truthBand: 'Photo Match',
      matchedItemName: imageInsight.inferredItemName,
      confidenceScore: imageInsight.confidenceScore,
      fragile: imageInsight.fragilityRisk == 'high',
      stackable: imageInsight.fragilityRisk != 'high',
      handlingNotes: imageInsight.handlingNotes,
    );
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
      final trustedKnownItem = base.confidence == 'high' &&
          (base.weightSource == 'known_product_lookup' ||
              base.weightSource == 'repository_match');
      if (trustedKnownItem) {
        final outliers = matches
            .where((weight) => weight > base.weightKg * 5)
            .toList(growable: false);
        if (outliers.isNotEmpty) {
          await FirebaseFunctions.instanceFor(
            region: 'us-central1',
          ).httpsCallable('recordIrisLearningOutlier').call({
            'description': _description.text.trim(),
            'matchedItemName': base.matchedItemName,
            'trustedWeightKg': base.weightKg,
            'outlierWeightsKg': outliers,
            'reason': 'historical_weight_above_5x_catalogue_weight',
          });
        }
        return base.copyWith(
          historicalVerifiedWeightKg: high,
          learningReason: outliers.isNotEmpty
              ? 'IRIS ignored unusually high historical matches because this item has a verified catalogue weight.'
              : 'Historical matches support the verified catalogue estimate.',
          explanation: outliers.isNotEmpty
              ? '${base.explanation} IRIS ignored unusually high historical matches because this item has a verified catalogue weight.'
              : base.explanation,
        );
      }
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
        confidence: base.confidence == 'low' ? 'medium' : base.confidence,
        confidenceScore: base.confidenceScore == null
            ? 0.7
            : base.confidenceScore!.clamp(0.7, 0.9).toDouble(),
        explanation:
            '${base.explanation} Similar completed parcels were verified at ${_formatWeight(low)}–${_formatWeight(high)}kg.',
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
      valueSensitive: product.valueSensitive,
      vanguardRecommended: product.vanguardRecommended,
      stackable: product.stackable,
      handlingNotes: product.handlingNotes,
      quantity: product.quantity,
      singleItemWeightKg: product.singleItemWeightKg,
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
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final quoteResult =
          await functions.httpsCallable('createSenderBookingQuote').call({
        'pickupAddressCanonical': _validatedPickup?.toJson(),
        'dropoffAddressCanonical': _validatedDropoff?.toJson(),
        'quoteId': id,
        'distanceMiles': _confirmedRouteDistanceMiles,
        'weightKg': _deliveryClassification.finalWeightKg,
        'selectedSpeed': _selectedSpeed,
        'vanguard': _webVanguardEnabled,
        'vanguardProtocolEnabled': _webVanguardEnabled,
        'parcel': {
          'itemName': _irisMatchedItemName ?? _inferPackageType(),
          'description': _description.text.trim(),
          'weightKg': _deliveryClassification.finalWeightKg,
        },
        if (_irisPhotoAnalysisId != null)
          'irisPhotoAnalysisId': _irisPhotoAnalysisId,
        'iris': _webCanonicalIrisPayload(),
        'clientDisplayQuote': {
          'amount': _quoteTotal,
          'amountPence': (_quoteTotal * 100).round(),
          'currency': 'GBP',
        },
      });
      final quote = Map<String, dynamic>.from(quoteResult.data as Map);
      final authoritativeTotal =
          (quote['amountDue'] as num? ?? quote['total'] as num? ?? 0)
              .toDouble();
      final difference = (authoritativeTotal - _quoteTotal).abs();
      if (difference >= 0.01) {
        final confirmed = await _confirmAuthoritativeWebQuote(
          authoritativeTotal,
        );
        if (confirmed != true) {
          if (!mounted) return;
          setState(() {
            _checkoutState = _CheckoutState.awaitingPayment;
            _firebaseError = 'Payment cancelled before charge.';
          });
          return;
        }
      }
      final parcelPhotoData = await _uploadParcelPhoto(id);
      final request = _requestPayload(id, parcelPhotoData);
      final deliveryPayload = {
        'requestId': id,
        'pickupAddressCanonical': _validatedPickup?.toJson(),
        'dropoffAddressCanonical': _validatedDropoff?.toJson(),
        'pickup': _webCanonicalPickupPayload(request),
        'dropoff': _webCanonicalDropoffPayload(request),
        'recipient': _webCanonicalRecipientPayload(request),
        'parcel': _webCanonicalParcelPayload(request),
        'iris': _webCanonicalIrisPayload(),
        'deliveryTime': _webCanonicalDeliveryTimePayload(),
      };
      final sessionResult =
          await functions.httpsCallable('createSenderPaymentSession').call({
        'quoteId': quote['quoteId'],
        'fallbackMethod': 'card',
        'rothEnabled': _deliveryUseRoth,
        'checkoutMode': 'web_checkout',
        'requestId': id,
        'idempotencyKey': id,
        'returnUrl': 'https://circum-2797c.web.app/send',
        'deliveryPayload': deliveryPayload,
      });
      final session = Map<String, dynamic>.from(sessionResult.data as Map);
      if ('${session['paymentStatus'] ?? session['status']}' == 'succeeded') {
        final paidDeliveryResult =
            await functions.httpsCallable('createSenderPaidDelivery').call({
          ...deliveryPayload,
          'quoteId': quote['quoteId'],
          'paymentSessionId': session['paymentSessionId'],
          'idempotencyKey': id,
        });
        final paidDelivery = Map<String, dynamic>.from(
          paidDeliveryResult.data as Map,
        );
        final requestId = '${paidDelivery['requestId'] ?? id}';
        _activeVanguardData = request['vanguardEnabled'] == true
            ? Map<String, dynamic>.from(request)
            : null;
        _listenToRequest(requestId);
        _listenToChat(requestId);
        if (!mounted) return;
        setState(() {
          _activeOrderId = requestId;
          _activeRequestDocId = requestId;
          _checkoutState = _CheckoutState.matchingRiders;
          _broadcasting = true;
          _firebaseOnline = true;
          _step = _SenderStep.tracking;
        });
        return;
      }
      final checkoutUrl = Uri.tryParse('${session['checkoutUrl'] ?? ''}');
      if (checkoutUrl == null || checkoutUrl.host.isEmpty) {
        throw StateError('Secure Stripe Checkout could not be opened.');
      }
      setState(() {
        _firebaseError = 'Complete payment securely with Stripe.';
      });
      final opened = await launchUrl(checkoutUrl, webOnlyWindowName: '_self');
      if (!opened) {
        throw StateError('Secure Stripe Checkout could not be opened.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkoutState = _CheckoutState.failed;
        _broadcasting = false;
        _firebaseOnline = false;
        _firebaseError =
            'Payment was not completed. Your delivery was not created.';
      });
    }
  }

  Future<bool?> _confirmAuthoritativeWebQuote(double authoritativeTotal) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm updated total'),
        content: Text(
          'The secure checkout total is £${authoritativeTotal.toStringAsFixed(2)}. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _webCanonicalPickupPayload(
    Map<String, dynamic> request,
  ) {
    final pickup = Map<String, dynamic>.from(request['pickupDetails'] as Map);
    final coordinates = Map<String, dynamic>.from(
      pickup['coordinates'] as Map? ?? const {},
    );
    return {
      'fullname': pickup['fullname'],
      'phone': pickup['phone'],
      'coordinates': coordinates,
      'instructions': pickup['moreInformation'],
      'locality': pickup['locality'],
      'address': pickup['address'],
      'subAddress': pickup['subAddress'],
      'canonicalAddress': _validatedPickup?.toJson(),
    };
  }

  Map<String, dynamic> _webCanonicalDropoffPayload(
    Map<String, dynamic> request,
  ) {
    final dropoff = Map<String, dynamic>.from(request['dropoffDetails'] as Map);
    final coordinates = Map<String, dynamic>.from(
      dropoff['coordinates'] as Map? ?? const {},
    );
    return {
      'fullname': dropoff['fullname'],
      'phone': dropoff['phone'],
      'coordinates': coordinates,
      'instructions': dropoff['moreInformation'],
      'locality': dropoff['locality'],
      'address': dropoff['address'],
      'subAddress': dropoff['subAddress'],
      'canonicalAddress': _validatedDropoff?.toJson(),
    };
  }

  Map<String, dynamic> _webCanonicalRecipientPayload(
    Map<String, dynamic> request,
  ) {
    final receiver = Map<String, dynamic>.from(
      request['receiverDetails'] as Map? ?? const {},
    );
    return {
      'name': receiver['name'] ?? request['receiverName'],
      'phone': receiver['phone'] ?? request['receiverPhone'],
      'deliveryNotes':
          (request['dropoffDetails'] as Map?)?['moreInformation'] ?? '',
    };
  }

  Map<String, dynamic> _webCanonicalParcelPayload(
    Map<String, dynamic> request,
  ) {
    return {
      'itemName': request['normalizedItemName'] ?? request['packageType'],
      'description': request['packageDescription'],
      'weightKg': request['finalWeightKg'] ?? request['weightKg'],
      'category': request['packageType'],
      'quantity': request['quantity'],
      'photoUrl': request['photoUrl'],
      'photoStoragePath': request['photoStoragePath'],
      'irisPhotoAnalysisId': request['irisPhotoAnalysisId'],
    };
  }

  Map<String, dynamic> _webCanonicalIrisPayload() {
    return {
      'itemName': _irisMatchedItemName,
      'category': _inferPackageType(),
      'irisWeightKg': _irisEstimatedWeightKg,
      'finalBillableWeightKg': _deliveryClassification.finalWeightKg,
      'weightBand': _deliveryClassification.finalWeightBand,
      'confidence': _irisWeightConfidence,
      'source': _irisWeightSource,
      'photoAnalysisId': _irisPhotoAnalysisId,
      'vanguardRequired': _webVanguardRequired,
      'vanguardRequiredReason': _webVanguardRequired
          ? 'Vanguard protection selected by item value policy.'
          : '',
    };
  }

  bool get _webVanguardEnabled => _webVanguardRequired || _webVanguardSelected;

  bool get _webVanguardRequired {
    return VanguardProtection.initialFields(
          description: _description.text.trim(),
          packageType: _inferPackageType(),
          declaredValueGbp: null,
        )['vanguardEnabled'] ==
        true;
  }

  Map<String, dynamic> _webCanonicalDeliveryTimePayload() {
    return {
      'type': _deliveryTimingType,
      'scheduledDate': _scheduledPickupDate.text.trim(),
      'scheduledWindow': _scheduledPickupWindow.text.trim(),
      'scheduledDropoffDate': _scheduledDropoffDate.text.trim(),
      'scheduledDropoffWindow': _scheduledDropoffWindow.text.trim(),
    };
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
    } else if (_validatedHealthPharmacy?.isVerified != true) {
      validationMessage =
          'Select a verified pharmacy address from the address results.';
    } else if (_healthDelivery.text.trim().isEmpty) {
      validationMessage = 'Add the delivery address.';
    } else if (_validatedHealthDelivery?.isVerified != true) {
      validationMessage =
          'Select a verified delivery address from the address results.';
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

    final quote = _healthQuote;

    setState(() {
      _healthSubmitting = true;
      _healthMessage = 'Saving your Health+ pickup and preparing payment...';
      _firebaseError = null;
    });

    try {
      await _ensureFirebaseReady();
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createHealthPlusBooking')
          .call<Map<String, dynamic>>({
        'fullName': _healthName.text.trim(),
        'phoneNumber': _healthPhone.text.trim(),
        'email': _healthEmail.text.trim(),
        'pharmacyName': _healthPharmacyName.text.trim(),
        'pharmacyAddress': _healthPharmacy.text.trim(),
        'pharmacyAddressCanonical': _validatedHealthPharmacy?.toJson(),
        'deliveryAddress': _healthDelivery.text.trim(),
        'deliveryAddressCanonical': _validatedHealthDelivery?.toJson(),
        'notes': _healthNotes.text.trim(),
        'prescriptionType': _healthPrescriptionType,
        'subscriptionPlan': _healthSubscriptionPlan,
        'healthPlusPlan': _healthSubscriptionPlan,
        'preferredDay': _healthPreferredDay.text.trim(),
        'preferredPickupDay': _healthPreferredDay.text.trim(),
        'preferredPickupTime': _healthPreferredTime.text.trim(),
        'consentConfirmed': _healthConsent,
        'frequency': _healthFrequency.value,
        'customSchedule': _healthCustomSchedule.text.trim(),
        'savedPaymentMethod': _healthSavePayment,
        'pricingInputs': {
          'distanceMiles': HealthPlusPricing.defaultDistanceMiles,
          'medicationWeightKg': HealthPlusPricing.defaultMedicationWeightKg,
        },
        'idempotencyKey':
            'web-healthplus:${FirebaseAuth.instance.currentUser?.uid}:${_healthFrequency.value}:${_healthPreferredTime.text.trim()}:$_healthSubscriptionPlan',
      });
      final data = Map<String, dynamic>.from(result.data);
      final id = '${data['profileId'] ?? ''}'.trim();
      final scheduleId = '${data['scheduleId'] ?? ''}'.trim();
      final pickupId = '${data['pickupId'] ?? ''}'.trim();
      final amount = (data['amount'] as num?)?.toDouble() ?? quote.total;
      final pickup = {
        'id': pickupId,
        'profileId': id,
        'fullName': _healthName.text.trim(),
        'phoneNumber': _healthPhone.text.trim(),
        'pharmacyName': _healthPharmacyName.text.trim(),
        'pharmacyAddress': _healthPharmacy.text.trim(),
        'pharmacyAddressCanonical': _validatedHealthPharmacy?.toJson(),
        'deliveryAddress': _healthDelivery.text.trim(),
        'deliveryAddressCanonical': _validatedHealthDelivery?.toJson(),
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
        'recurring': scheduleId.isNotEmpty,
        'customSchedule': _healthCustomSchedule.text.trim(),
        'priorityRiderMatching': _healthSubscriptionPlan == 'priority',
        'status': PickupStatus.scheduled.value,
        'price': amount,
        'currency': 'GBP',
        'pricingBreakdown': quote.toJson(),
        'type': 'health_plus_prescription_pickup',
        'source': 'circum-web',
      };
      final checkout = await _createHealthPlusCheckoutSession(
        pickupId: pickupId,
        profileId: id,
        quote: quote,
      );
      final checkoutUrl =
          checkout == null ? null : '${checkout['checkoutUrl'] ?? ''}'.trim();
      final paid = checkout != null && checkout['paid'] == true;
      final hasCheckoutUrl = checkoutUrl != null && checkoutUrl.isNotEmpty;

      if (!mounted) return;
      setState(() {
        _healthScheduleId = scheduleId.isEmpty ? null : scheduleId;
        _healthCheckoutUrl = checkoutUrl;
        _healthPickups.insert(0, pickup);
        _healthPayments.insert(0, {
          'pickupId': pickupId,
          'amount': amount,
          'status': paid
              ? 'paid'
              : !hasCheckoutUrl
                  ? 'pending_secure_checkout'
                  : 'checkout_created',
          'rothApplied': checkout?['rothApplied'],
          'cardAmount': checkout?['cardAmount'],
        });
        _healthMessage = paid
            ? 'Your Health+ pickup has been paid with Roth.'
            : !hasCheckoutUrl
                ? 'Your Health+ pickup is saved. Payment setup is not ready yet.'
                : 'Your Health+ pickup is saved. Payment is ready.';
        _firebaseOnline = true;
      });

      if (hasCheckoutUrl) {
        await launchUrl(
          Uri.parse(checkoutUrl),
          mode: LaunchMode.externalApplication,
        );
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

  Future<Map<String, dynamic>?> _createHealthPlusCheckoutSession({
    required String pickupId,
    required String profileId,
    required HealthPlusPriceBreakdown quote,
  }) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse(
          'https://us-central1-circum-2797c.cloudfunctions.net/createHealthPlusCheckoutSession',
        ),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'bookingId': pickupId,
          'profileId': profileId,
          'email': _healthEmail.text.trim(),
          'frequency': _healthFrequency == HealthPlusFrequency.every28Days
              ? HealthPlusFrequency.custom.value
              : _healthFrequency.value,
          'subscriptionPlan': _healthSubscriptionPlan,
          'prescriptionType': _healthPrescriptionType,
          'useRoth': _healthUseRoth,
          'priceBreakdown': quote.toJson(),
          'successUrl':
              'https://circum-2797c.web.app/send/health?health=success',
          'cancelUrl':
              'https://circum-2797c.web.app/send/health?health=cancelled',
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openHealthPlusCheckout() async {
    final url = _healthCheckoutUrl;
    if (url == null) {
      setState(
        () => _healthMessage =
            'Payment is not ready yet. Create or refresh the Health+ booking first.',
      );
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
    await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('updateSenderHealthPlusBooking').call({
      'action': 'pause_schedule',
      'scheduleId': scheduleId,
      'idempotencyKey': 'web-healthplus:pause:$scheduleId',
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
    await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('updateSenderHealthPlusBooking').call({
      'action': 'resume_schedule',
      'scheduleId': scheduleId,
      'idempotencyKey': 'web-healthplus:resume:$scheduleId',
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
    await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('updateSenderHealthPlusBooking').call({
      'action': 'cancel_schedule',
      'scheduleId': scheduleId,
      'idempotencyKey': 'web-healthplus:cancel-schedule:$scheduleId',
    });
    setState(() => _healthMessage = 'Your repeat Health+ pickup is cancelled.');
  }

  Future<void> _cancelNextHealthPlusPickup() async {
    if (_healthPickups.isEmpty) return;
    final pickupId = _healthPickups.first['id'] as String?;
    if (pickupId == null) return;
    await _ensureFirebaseReady();
    await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('updateSenderHealthPlusBooking').call({
      'action': 'cancel_pickup',
      'pickupId': pickupId,
      'idempotencyKey': 'web-healthplus:cancel-pickup:$pickupId',
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
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final response = await http.post(
      Uri.parse(
        'https://us-central1-circum-2797c.cloudfunctions.net/updateHealthPlusPickupStatus',
      ),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'pickupId': pickupId,
        'status': status,
        'note': 'Updated from Circum Website Health+ operations.',
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      setState(() => _healthMessage = 'Admin status update failed.');
      return;
    }
    setState(() {
      _healthPickups.first['status'] = status;
      _healthMessage = 'Admin status updated to $status.';
    });
  }

  Map<String, dynamic> _requestPayload(
    String id,
    Map<String, dynamic> parcelPhotoData,
  ) {
    final quote = _quoteBreakdown;
    final classification = _deliveryClassification;
    final pickupAddress = _validatedPickup!;
    final dropoffAddress = _validatedDropoff!;
    final distanceMiles = _confirmedRouteDistanceMiles!;
    final handling = _specialHandling;
    final standardQuote = handling.applyTo(
      DeliveryPricing.calculate(
        DeliveryPricingInput(
          distanceMiles: distanceMiles,
          weightKg: classification.finalWeightKg,
          vehicleType: _effectiveVehicle.name,
          quantity: _irisQuantity,
          singleItemWeightKg: _irisSingleItemWeightKg,
          stackable: _irisStackable,
        ),
      ),
    );
    final expressQuote = handling.applyTo(
      DeliveryPricing.calculate(
        DeliveryPricingInput(
          distanceMiles: distanceMiles,
          weightKg: classification.finalWeightKg,
          vehicleType: _effectiveVehicle.name,
          quantity: _irisQuantity,
          singleItemWeightKg: _irisSingleItemWeightKg,
          stackable: _irisStackable,
          express: true,
        ),
      ),
    );
    final selectedServiceLevel = switch (_selectedSpeed) {
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
      manuallySelected: _webVanguardSelected,
    );
    final vanguardEnabled = vanguardFields['vanguardEnabled'] == true;
    final vanguardIncluded = _webVanguardRequired;
    final vanguardAddOn =
        vanguardEnabled && !vanguardIncluded ? _webVanguardAddOnPriceGbp : 0.0;
    final customerTotal = quote.total + vanguardAddOn;
    final hasPhoto = parcelPhotoData['hasPhoto'] == true;
    final parcelPhotoUrl =
        parcelPhotoData['imageUrl'] ?? parcelPhotoData['photoUrl'];
    final suitability = _vehicleSuitability;
    final safeVehicleName = _effectiveVehicle.name;
    final irisRecommendedVehicle = suitability.recommendedVehicle;
    final vehicleWasUpgraded = DeliveryPricing.vehicleWasUpgraded(
      safeVehicleName,
      irisRecommendedVehicle,
    );
    final driverPayout = quote.totalRiderEarnings;
    final platformRevenue = quote.totalCircumRevenue + vanguardAddOn;
    final driverJobSummary = {
      'pickupDisplay': pickupAddress.compactDisplay,
      'dropoffDisplay': dropoffAddress.compactDisplay,
      'pickupAddress': pickupAddress.toJson(),
      'dropoffAddress': dropoffAddress.toJson(),
      'pickupCoordinates': pickupAddress.toPositionMap(),
      'dropoffCoordinates': dropoffAddress.toPositionMap(),
      'addressValidationStatus': 'verified',
      'addressSource': {
        'pickup': pickupAddress.provider,
        'dropoff': dropoffAddress.provider,
      },
      'estimatedDistanceMiles': distanceMiles,
      'estimatedDurationMinutes': 28,
      'scheduledPickupDate': _scheduledPickupDate.text.trim(),
      'scheduledPickupWindow': _scheduledPickupWindow.text.trim(),
      'scheduledDropoffDate': _scheduledDropoffDate.text.trim(),
      'scheduledDropoffWindow': _scheduledDropoffWindow.text.trim(),
      'deliveryTimingType': _deliveryTimingType,
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
      'originalDescription': _description.text.trim(),
      'quantity': _irisQuantity < 1 ? 1 : _irisQuantity,
      'normalizedItemName': _irisMatchedItemName,
      'singleItemWeightKg': _irisSingleItemWeightKg,
      'totalEstimatedWeightKg': _irisEstimatedWeightKg,
      'weightClass': _irisWeightBand,
      'irisRecommendedVehicle': irisRecommendedVehicle,
      'userSelectedVehicle': safeVehicleName,
      'vehicleWasUpgraded': vehicleWasUpgraded,
      'hasPhoto': hasPhoto,
      'photoUrl': parcelPhotoUrl,
      'irisImageAnalysis': _irisImageInsight?.toJson(),
      'irisPhotoAnalysisId': _irisPhotoAnalysisId,
      'imageAnalysisStatus': _irisImageInsight == null
          ? parcelPhotoData['analysisStatus']
          : 'analysed_by_iris',
      'deliveryInstructions': _description.text.trim(),
      'vehicleType': safeVehicleName,
      'totalFare': customerTotal,
      'driverPayout': driverPayout,
      'riderPayout': driverPayout,
      'baseFare': quote.total - handling.labourPremium,
      'assistedFee': quote.assistedFee,
      'heavyDutyFee': quote.heavyDutyFee,
      'twoPersonFee': quote.twoPersonFee,
      'heavyHandlingSurcharge': quote.heavyHandlingSurcharge,
      'twoPersonRecommended': quote.twoPersonRecommended,
      'twoPersonRequiredByWeight': quote.twoPersonRequiredByWeight,
      'multiTripReviewRequired': quote.multiTripReviewRequired,
      'heavyHandlingAdminReviewRequired':
          quote.heavyHandlingAdminReviewRequired,
      'riderBaseShare': quote.riderBaseShare,
      'riderLabourShare': quote.riderLabourShare,
      'totalRiderEarnings': quote.totalRiderEarnings,
      'vanguardAddOnFee': vanguardAddOn,
      'vanguardFee': vanguardAddOn,
      'specialHandlingClass': handling.handlingClass.name,
      'specialHandlingBadges': [
        if (quote.assistedFee > 0) 'Assisted Delivery',
        if (quote.heavyDutyFee > 0) 'Heavy Duty',
        if (quote.twoPersonFee > 0) 'Two Person Required',
      ],
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
          : _irisImageInsight?.riderGuidance ??
              (vanguardEnabled
                  ? 'Vanguard protected delivery. PIN verification required at pickup and delivery.'
                  : ''),
      'vanguardEnabled': vanguardEnabled,
      'vanguardProtocolEnabled': vanguardEnabled,
      'serviceType': selectedServiceLevel == 'express'
          ? 'Express Delivery'
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
      'originalDescription': _description.text.trim(),
      'quantity': _irisQuantity < 1 ? 1 : _irisQuantity,
      'normalizedItemName': _irisMatchedItemName,
      'singleItemWeightKg': _irisSingleItemWeightKg,
      'totalEstimatedWeightKg': _irisEstimatedWeightKg,
      'weightClass': _irisWeightBand,
      'irisRecommendedVehicle': irisRecommendedVehicle,
      'userSelectedVehicle': safeVehicleName,
      'vehicleWasUpgraded': vehicleWasUpgraded,
      'hasPhoto': hasPhoto,
      'imageUrl': parcelPhotoUrl,
      'photoUrl': parcelPhotoUrl,
      'photoURL': parcelPhotoUrl,
      'photoStoragePath': parcelPhotoData['storagePath'],
      'imageAnalysisStatus': _irisImageInsight == null
          ? parcelPhotoData['analysisStatus']
          : 'analysed_by_iris',
      'irisImageAnalysis': _irisImageInsight?.toJson(),
      'irisPhotoAnalysisId': _irisPhotoAnalysisId,
      'parcelPhoto': {
        ...parcelPhotoData,
        'irisImageAnalysis': _irisImageInsight?.toJson(),
        'irisDecisionStatus': hasPhoto
            ? (_irisImageInsight == null
                ? 'photo_attached_text_fallback'
                : 'photo_used_in_iris_analysis')
            : 'not_provided',
      },
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
      'irisPhotoInsight': _irisImageInsight?.toJson(),
      'irisImageConfidenceScore': _irisImageInsight?.confidenceScore,
      'irisImageNeedsHumanReview': _irisImageInsight?.needsHumanReview,
      'irisImageHandlingNotes': _irisImageInsight?.handlingNotes,
      'irisImageRiderGuidance': _irisImageInsight?.riderGuidance,
      'senderEnteredWeightKg': _senderEnteredWeightKg,
      'confirmedWeightKg': classification.finalWeightKg,
      'confirmedWeightBand': classification.finalWeightBand,
      'declaredWeightKg': _senderEnteredWeightKg,
      'driverReportedWeightKg': null,
      'driverWeightDispute': {'reported': false, 'status': 'none'},
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
      'deliveryTimingType': _deliveryTimingType,
      'weightCategory': classification.finalWeightBand,
      'vehicle': safeVehicleName,
      'selectedVehicle': safeVehicleName,
      'preferredVehicle': safeVehicleName.toLowerCase(),
      'vehicleType': safeVehicleName,
      'speed': _selectedSpeed,
      'selectedTier': selectedServiceLevel,
      'serviceLevel': selectedServiceLevel,
      'selectedServiceLevel': selectedServiceLevel,
      'standardPrice': standardQuote.total,
      'expressPrice': expressQuote.total,
      'basePrice': standardQuote.total,
      'finalPrice': customerTotal,
      'finalCustomerPrice': customerTotal,
      'assistedFee': quote.assistedFee,
      'heavyDutyFee': quote.heavyDutyFee,
      'twoPersonFee': quote.twoPersonFee,
      'heavyHandlingSurcharge': quote.heavyHandlingSurcharge,
      'twoPersonRecommended': quote.twoPersonRecommended,
      'twoPersonRequiredByWeight': quote.twoPersonRequiredByWeight,
      'multiTripReviewRequired': quote.multiTripReviewRequired,
      'heavyHandlingAdminReviewRequired':
          quote.heavyHandlingAdminReviewRequired,
      'pickupAccess': _pickupAccess.name,
      'dropoffAccess': _dropoffAccess.name,
      'specialHandlingClass': handling.handlingClass.name,
      'specialHandlingExplanation': handling.explanation,
      'riderBaseShare': quote.riderBaseShare,
      'riderLabourShare': quote.riderLabourShare,
      'circumBaseShare': quote.circumBaseShare,
      'circumLabourShare': quote.circumLabourShare,
      'totalRiderEarnings': quote.totalRiderEarnings,
      'totalCircumRevenue': platformRevenue,
      'serviceLevelSurcharge':
          serviceLevelSurcharge < 0 ? 0 : serviceLevelSurcharge,
      'priority': selectedServiceLevel == 'express',
      'matchingPriority': selectedServiceLevel == 'express' ? 'high' : 'normal',
      'broadcastRank': DeliveryPricing.matchingPriorityRank(
        selectedServiceLevel,
      ),
      'quote': customerTotal,
      'price': customerTotal,
      'fare': customerTotal,
      'driverPayout': driverPayout,
      'riderPayout': driverPayout,
      'platformRevenue': platformRevenue,
      'platformShare': DeliveryPricing.platformDeliveryFareShare,
      'driverShare': DeliveryPricing.riderDeliveryFareShare,
      'pricingBreakdown': quote.toJson(),
      ...vanguardFields,
      'vanguardProtocolEnabled': vanguardEnabled,
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
      'receiverDetails': {'name': receiverName, 'phone': receiverPhone},
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
        'validationStatus': 'verified',
        'addressSource': pickupAddress.provider,
        'placeId': pickupAddress.placeId,
        'locationId': pickupAddress.locationId,
        'coordinates': {'lat': pickupAddress.lat, 'lng': pickupAddress.lng},
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
        'validationStatus': 'verified',
        'addressSource': dropoffAddress.provider,
        'placeId': dropoffAddress.placeId,
        'locationId': dropoffAddress.locationId,
        'coordinates': {'lat': dropoffAddress.lat, 'lng': dropoffAddress.lng},
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
        .listen(
      (snapshot) {
        final data = snapshot.data();
        if (!mounted || data == null) return;
        final status = _backendStatusFromDelivery(data);
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
          _activeRequestReceivedAt = _jobReceivedDate(data);
        });
        if (driverId != null && driverId != _assignedDriverId) {
          _assignedDriverId = driverId;
          _listenToAssignedDriver(driverId, data);
        }
        if (_statusIndexFromFirebase(status) >= 3) {
          _checkExistingDriverRating();
        }
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _checkoutState = _CheckoutState.failed;
          _broadcasting = false;
          _firebaseOnline = false;
          _firebaseError = 'Could not keep this delivery up to date.';
        });
      },
    );
  }

  void _listenToLiveLocation(String deliveryId) {
    _liveLocationSub?.cancel();
    _liveLocationSub = FirebaseFirestore.instance
        .collection('deliveryRequests')
        .doc(deliveryId)
        .collection('tracking')
        .doc('liveLocation')
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _liveLocationData = snapshot.data();
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _liveLocationData = null);
      },
    );
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
      final metric = DriverPerformanceMetric.fromMap(
        driverId,
        snapshot.data(),
      );
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
        .doc(
          DriverRating.documentId(
            deliveryId: requestId,
            customerId: customerId,
          ),
        )
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
      setState(
        () => _ratingMessage =
            'You can rate the rider after delivery is complete.',
      );
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
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      await functions.httpsCallable('submitDeliveryRating').call({
        'deliveryId': requestId,
        'stars': _selectedRating,
        'feedback': _ratingFeedback.text.trim(),
        'feedbackTags': _selectedRatingTags.toList(),
      });
      if (_selectedTipAmount > 0) {
        await functions.httpsCallable('submitDeliveryTip').call({
          'deliveryId': requestId,
          'amountPence': (_selectedTipAmount * 100).round(),
          'paymentMethod': 'roth',
        });
      }
      if (!mounted) return;
      setState(() {
        _ratingSubmitted = true;
        _ratingMessage = 'Thanks. Your rating has been saved.';
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      final alreadyRated = error.code == 'already-exists';
      setState(() {
        _ratingSubmitted = alreadyRated;
        _ratingMessage = alreadyRated
            ? 'This delivery has already been rated.'
            : (error.message ?? 'We could not save the rating. Try again.');
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _ratingMessage = 'We could not save the rating. Try again.',
      );
    } finally {
      if (mounted) setState(() => _ratingSubmitting = false);
    }
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
          ..addAll(
            driverMessages.isEmpty
                ? [
                    const _ChatMessage(
                      fromMe: false,
                      text:
                          'Rider chat will open when someone accepts the job.',
                      time: 'Now',
                    ),
                  ]
                : driverMessages,
          );
        _supportMessages
          ..clear()
          ..addAll(
            supportMessages.isEmpty
                ? [
                    const _ChatMessage(
                      fromMe: false,
                      text: "Hi, this is Iris. How can we help?",
                      time: 'Now',
                    ),
                  ]
                : supportMessages,
          );
      });
    });
  }

  int _statusIndexFromFirebase(String status) {
    switch (_senderTrackingStateForBackendStatus(status)) {
      case 'finding_rider':
        return 0;
      case 'rider_assigned':
        return 1;
      case 'rider_en_route_to_pickup':
        return 2;
      case 'rider_arrived_at_pickup':
        return 3;
      case 'pickup_complete':
        return 4;
      case 'in_transit':
        return 5;
      case 'rider_arriving_at_dropoff':
        return 6;
      case 'delivered':
        return 7;
      case 'cancelled':
        return 8;
      case 'issue':
      case 'error':
        return 9;
      default:
        return 0;
    }
  }

  String _backendStatusFromDelivery(Map<String, dynamic> data) {
    return '${data['deliveryStage'] ?? data['deliveryStatus'] ?? data['trackingStatus'] ?? data['status'] ?? 'requested'}'
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[-\s]+'), '_');
  }

  String _senderTrackingStateForBackendStatus(String status) {
    final normalized = status.trim().toLowerCase().replaceAll(
          RegExp(r'[-\s]+'),
          '_',
        );
    const mapping = {
      'requested': 'finding_rider',
      'pending': 'finding_rider',
      'unmatched': 'finding_rider',
      'finding_rider': 'finding_rider',
      'awaiting_rider': 'finding_rider',
      'broadcast': 'finding_rider',
      'broadcasted': 'finding_rider',
      'accepted': 'rider_assigned',
      'rider_assigned': 'rider_assigned',
      'navigating_to_pickup': 'rider_en_route_to_pickup',
      'en_route_to_pickup': 'rider_en_route_to_pickup',
      'arrived_at_pickup': 'rider_arrived_at_pickup',
      'waiting': 'rider_arrived_at_pickup',
      'pickup_verification': 'pickup_complete',
      'pickup_verified': 'pickup_complete',
      'collected': 'pickup_complete',
      'out_for_delivery': 'in_transit',
      'outfordelivery': 'in_transit',
      'navigating_to_dropoff': 'in_transit',
      'arrived_at_dropoff': 'rider_arriving_at_dropoff',
      'pin_required': 'rider_arriving_at_dropoff',
      'handover_pending': 'rider_arriving_at_dropoff',
      'delivered': 'delivered',
      'completed': 'delivered',
      'delivery_completed': 'delivered',
      'cancelled': 'cancelled',
      'canceled': 'cancelled',
      'cancelled_verified_discrepancy': 'cancelled',
      'sender_no_show_pickup': 'cancelled',
      'issue': 'issue',
      'issue_reported': 'issue',
      'failed': 'issue',
      'failed_delivery': 'issue',
      'error': 'error',
    };
    if (normalized.isEmpty) return 'no_active_delivery';
    return mapping[normalized] ?? 'issue';
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
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('sendCircumMessage')
          .call({
        'chatId': requestId,
        'requestId': requestId,
        'message': text,
        'clientMessageId': const Uuid().v4(),
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _firebaseError = 'Message could not be sent. Please try again.',
      );
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
      _activeRequestReceivedAt = null;
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
  final DateTime? receivedAt;
  final SenderDeliveryRecord? activeDelivery;
  final String? deliveryLoadError;
  final VoidCallback onSendParcel;
  final VoidCallback onViewHistory;
  final ValueChanged<SenderDeliveryRecord> onCancelBooking;
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
    required this.receivedAt,
    required this.activeDelivery,
    required this.deliveryLoadError,
    required this.onSendParcel,
    required this.onViewHistory,
    required this.onCancelBooking,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final wideStep = switch (step) {
      _SenderStep.details ||
      _SenderStep.vehicle ||
      _SenderStep.payment ||
      _SenderStep.tracking ||
      _SenderStep.healthPlus ||
      _SenderStep.business =>
        true,
      _ => false,
    };
    if (step == _SenderStep.dashboard) {
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
              color: colors.field.withValues(alpha: colors.dark ? 0.22 : 0.38),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: deliveryLoadError != null
                    ? _DesktopDeliveryLoadError(
                        colors: colors,
                        message: deliveryLoadError!,
                      )
                    : activeDelivery == null
                        ? _DesktopNoActiveDelivery(
                            colors: colors,
                            onSendParcel: onSendParcel,
                            onViewHistory: onViewHistory,
                          )
                        : _DesktopActiveDeliveryStatus(
                            colors: colors,
                            delivery: activeDelivery!,
                            onCancelBooking: onCancelBooking,
                          ),
              ),
            ),
          ),
        ],
      );
    }
    return Container(
      color: colors.field.withValues(alpha: colors.dark ? 0.16 : 0.28),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wideStep ? 1180 : 680),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopNoActiveDelivery extends StatelessWidget {
  final _CircumColors colors;
  final VoidCallback onSendParcel;
  final VoidCallback onViewHistory;

  const _DesktopNoActiveDelivery({
    required this.colors,
    required this.onSendParcel,
    required this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.local_shipping_outlined, color: colors.text, size: 32),
          const SizedBox(height: 14),
          Text(
            'No active delivery',
            style: TextStyle(
              color: colors.text,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You do not have a live delivery at the moment. Send a parcel or choose a past delivery to view its status.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
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
                onPressed: onViewHistory,
                icon: const Icon(Icons.history),
                label: const Text('View delivery history'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopDeliveryLoadError extends StatelessWidget {
  final _CircumColors colors;
  final String message;

  const _DesktopDeliveryLoadError({
    required this.colors,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colors.text,
                height: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopActiveDeliveryStatus extends StatelessWidget {
  final _CircumColors colors;
  final SenderDeliveryRecord delivery;
  final ValueChanged<SenderDeliveryRecord> onCancelBooking;

  const _DesktopActiveDeliveryStatus({
    required this.colors,
    required this.delivery,
    required this.onCancelBooking,
  });

  @override
  Widget build(BuildContext context) {
    final receivedText = delivery.createdAt == null
        ? null
        : _jobReceivedTextFromDate(delivery.createdAt);
    final hasDriver = delivery.assignedDriverName.trim().isNotEmpty;
    return Column(
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
            _StatusPill(
              colors: colors,
              label: _displayStatusLabel(delivery.status),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Reference ${_displayDeliveryReference(delivery.trackingReference.isEmpty ? delivery.requestId : delivery.trackingReference)}',
          style: TextStyle(
            color: colors.mutedText,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (receivedText != null) ...[
          const SizedBox(height: 6),
          Text(
            receivedText,
            style: TextStyle(
              color: colors.mutedText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
                value: delivery.pickupAddress,
                iconColor: const Color(0xff2563eb),
              ),
              const SizedBox(height: 14),
              _RouteLine(
                colors: colors,
                icon: Icons.location_on,
                label: 'Drop-off',
                value: delivery.dropoffAddress,
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
              _SectionTitle(colors: colors, title: 'Price'),
              const SizedBox(height: 8),
              _PriceLine(
                colors: colors,
                label: 'Final price',
                value: delivery.pricePaid > 0
                    ? '£${delivery.pricePaid.toStringAsFixed(2)}'
                    : 'Price not confirmed',
                strong: true,
              ),
              _PriceLine(
                colors: colors,
                label: 'Payment',
                value: delivery.paymentStatus,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _GlassPanel(
          colors: colors,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasDriver ? Icons.verified_user : Icons.person_search,
                color: colors.text,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasDriver
                          ? 'Circum Rider assigned'
                          : 'Circum Rider not assigned yet',
                      style: TextStyle(
                        color: colors.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasDriver
                          ? delivery.assignedDriverName
                          : 'Circum will show Circum Rider details once this delivery has been assigned.',
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
        if (BookingCancellationPolicy.canSenderCancel(delivery.status)) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => onCancelBooking(delivery),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel Booking'),
          ),
        ],
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _CircumColors colors;
  final String label;

  const _StatusPill({required this.colors, required this.label});

  @override
  Widget build(BuildContext context) {
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
                title: signupMode ? 'Create a Circum account' : 'Circum login',
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
                  colors: colors,
                  controller: fullName,
                  hint: 'Full name',
                ),
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: phone,
                  hint: 'Phone number',
                ),
                const SizedBox(height: 10),
              ],
              _InputBox(
                colors: colors,
                controller: email,
                hint: 'Email address',
              ),
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
                  label: 'Continue as Circum',
                  onTap: onSender,
                ),
              if (roles.contains(CircumRole.rider)) ...[
                const SizedBox(height: 10),
                _RoleChoiceButton(
                  colors: colors,
                  icon: Icons.delivery_dining,
                  label: 'Continue as Circum Rider',
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
        .where(
          (address) => addressType == 'pickup'
              ? address.addressType != 'dropoff'
              : address.addressType == 'dropoff',
        )
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
                avatar: Icon(
                  Icons.place_outlined,
                  color: colors.text,
                  size: 16,
                ),
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
  final int quantity;
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
    required this.quantity,
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
              'Matched item: ${_cleanMatchedItemName(matchedItemName!)} · Quantity: $quantity · $truthBand',
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
              'Circum Rider will verify weight at pickup.',
              style: TextStyle(
                color: colors.warning,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (canConfirm) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text(
                'IRIS has calculated the pricing weight. Circum Rider will verify at collection.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _cleanMatchedItemName(String value) {
    return value
        .replaceFirst(
          RegExp(r'^(urgent|sealed|return)\s+', caseSensitive: false),
          '',
        )
        .trim();
  }

  String _confidenceDisplayText() {
    final source = weightSource.toLowerCase();
    if (truthBand == 'Exact Match') return 'Exact Match (High Confidence)';
    if (source == 'repository match') {
      return 'Repository Match (Medium Confidence)';
    }
    if (source == 'photo match') return 'Image Estimate (Medium Confidence)';
    if (source == 'customer declared') {
      return 'User Declared Only (Low Confidence)';
    }
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
  final VoidCallback onBusiness;
  final VoidCallback onProfile;
  final VoidCallback onSupport;

  const _SenderDashboardStep({
    super.key,
    required this.colors,
    required this.profile,
    required this.deliveries,
    required this.onSendParcel,
    required this.onHealthPlus,
    required this.onBusiness,
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
                    OutlinedButton.icon(
                      onPressed: onBusiness,
                      icon: const Icon(Icons.business_center_outlined),
                      label: const Text('Business Centre'),
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
                  title: Text(
                    'Profile and saved addresses',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    'Keep pickup details ready for faster booking.',
                    style: TextStyle(color: colors.mutedText),
                  ),
                  onTap: onProfile,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.support_agent, color: colors.text),
                  title: Text(
                    'Support',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    'Ask Circum for help with a delivery.',
                    style: TextStyle(color: colors.mutedText),
                  ),
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

class _BusinessCentreStep extends StatelessWidget {
  final _CircumColors colors;
  final bool loading;
  final bool busy;
  final String? message;
  final List<Map<String, dynamic>> accounts;
  final String? selectedBusinessId;
  final Map<String, dynamic>? account;
  final String? currentUserId;
  final String? currentUserEmail;
  final List<Map<String, dynamic>> invoices;
  final List<SenderDeliveryRecord> deliveries;
  final List<Map<String, dynamic>> joinRequests;
  final List<Map<String, dynamic>> auditLogs;
  final Map<String, dynamic>? wallet;
  final TextEditingController companyName;
  final TextEditingController businessType;
  final TextEditingController businessEmail;
  final TextEditingController businessPhone;
  final TextEditingController businessAddress;
  final TextEditingController vatNumber;
  final TextEditingController website;
  final TextEditingController companyCode;
  final TextEditingController rothAmount;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final ValueChanged<String> onSelectBusiness;
  final VoidCallback onCreateBusiness;
  final VoidCallback onJoinBusiness;
  final VoidCallback onEnsureCompanyCode;
  final VoidCallback onRotateCompanyCode;
  final VoidCallback onSaveProfile;
  final void Function(String requestId, bool approved) onReviewRequest;
  final void Function(String memberUserId, String role) onUpdateMemberRole;
  final ValueChanged<String> onRemoveMember;
  final ValueChanged<String> onPayInvoice;
  final ValueChanged<String> onPayInvoiceWithRoth;
  final ValueChanged<Map<String, dynamic>> onDownloadInvoice;
  final VoidCallback onBuyRoth;
  final VoidCallback onCreateDelivery;
  final VoidCallback onHealthPlus;
  final VoidCallback onGifts;

  const _BusinessCentreStep({
    super.key,
    required this.colors,
    required this.loading,
    required this.busy,
    required this.message,
    required this.accounts,
    required this.selectedBusinessId,
    required this.account,
    required this.currentUserId,
    required this.currentUserEmail,
    required this.invoices,
    required this.deliveries,
    required this.joinRequests,
    required this.auditLogs,
    required this.wallet,
    required this.companyName,
    required this.businessType,
    required this.businessEmail,
    required this.businessPhone,
    required this.businessAddress,
    required this.vatNumber,
    required this.website,
    required this.companyCode,
    required this.rothAmount,
    required this.onBack,
    required this.onRefresh,
    required this.onSelectBusiness,
    required this.onCreateBusiness,
    required this.onJoinBusiness,
    required this.onEnsureCompanyCode,
    required this.onRotateCompanyCode,
    required this.onSaveProfile,
    required this.onReviewRequest,
    required this.onUpdateMemberRole,
    required this.onRemoveMember,
    required this.onPayInvoice,
    required this.onPayInvoiceWithRoth,
    required this.onDownloadInvoice,
    required this.onBuyRoth,
    required this.onCreateDelivery,
    required this.onHealthPlus,
    required this.onGifts,
  });

  @override
  Widget build(BuildContext context) {
    final businessDeliveries = _businessDeliveries;
    final activeDeliveries = businessDeliveries
        .where((delivery) => _isActiveSenderDeliveryStatus(delivery.status))
        .toList();
    final completedDeliveries = businessDeliveries
        .where(
          (delivery) => [
            'completed',
            'delivered',
          ].contains(delivery.status.toLowerCase()),
        )
        .toList();
    final outstandingInvoices =
        invoices.where((invoice) => !_invoicePaid(invoice)).toList();
    final monthlySpend = businessDeliveries.fold<double>(
      0,
      (total, delivery) => total + delivery.pricePaid,
    );
    final members = _teamMembers;
    final accountName = '${account?['businessName'] ?? 'Circum Business'}';
    final recognitionLabel =
        account == null ? null : _businessRecognitionLabel(account!);

    final teamMemberCount =
        members.where((member) => member['status'] != 'removed').length;
    final rothBalance = _money(
      wallet?['balance'] ?? wallet?['availableBalance'],
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BusinessSenderSuiteHeader(
            colors: colors,
            accountName: account == null ? 'Circum Business' : accountName,
            accountStatus: '${account?['status'] ?? 'pending'}',
            recognitionLabel: recognitionLabel,
            accounts: accounts,
            selectedBusinessId: selectedBusinessId,
            busy: busy,
            onBack: onBack,
            onRefresh: onRefresh,
            onSelectBusiness: onSelectBusiness,
          ),
          if (message != null && message!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _BusinessNotice(colors: colors, message: message!),
          ],
          const SizedBox(height: 12),
          if (loading)
            _BusinessSkeleton(colors: colors)
          else if (account == null)
            _BusinessOnboardingPanel(
              colors: colors,
              busy: busy,
              companyName: companyName,
              businessType: businessType,
              businessEmail: businessEmail,
              businessPhone: businessPhone,
              businessAddress: businessAddress,
              vatNumber: vatNumber,
              companyCode: companyCode,
              onCreateBusiness: onCreateBusiness,
              onJoinBusiness: onJoinBusiness,
            )
          else
            _BusinessSectionTabs(
              colors: colors,
              members: members,
              joinRequests: joinRequests,
              auditLogs: auditLogs,
              deliveries: businessDeliveries,
              activeDeliveries: activeDeliveries,
              invoices: invoices,
              wallet: wallet,
              activeDeliveryCount: activeDeliveries.length,
              completedDeliveryCount: completedDeliveries.length,
              outstandingInvoiceCount: outstandingInvoices.length,
              monthlySpend: monthlySpend,
              teamMemberCount: teamMemberCount,
              rothBalance: rothBalance,
              busy: busy,
              account: account!,
              currentUserId: currentUserId,
              currentUserEmail: currentUserEmail,
              rothAmount: rothAmount,
              companyName: companyName,
              businessType: businessType,
              businessEmail: businessEmail,
              businessPhone: businessPhone,
              businessAddress: businessAddress,
              vatNumber: vatNumber,
              website: website,
              onCreateDelivery: onCreateDelivery,
              onHealthPlus: onHealthPlus,
              onGifts: onGifts,
              onBuyRoth: onBuyRoth,
              onPayInvoice: onPayInvoice,
              onPayInvoiceWithRoth: onPayInvoiceWithRoth,
              onDownloadInvoice: onDownloadInvoice,
              onReviewRequest: onReviewRequest,
              onUpdateMemberRole: onUpdateMemberRole,
              onRemoveMember: onRemoveMember,
              onEnsureCompanyCode: onEnsureCompanyCode,
              onRotateCompanyCode: onRotateCompanyCode,
              onSaveProfile: onSaveProfile,
            ),
        ],
      ),
    );
  }

  List<SenderDeliveryRecord> get _businessDeliveries {
    final businessId = selectedBusinessId;
    if (businessId == null) return const [];
    return deliveries
        .where(
          (delivery) =>
              delivery.raw['businessId'] == businessId ||
              delivery.raw['businessAccountId'] == businessId ||
              delivery.raw['businessMode'] == true,
        )
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get _teamMembers {
    final raw = account?['teamMembers'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static bool _invoicePaid(Map<String, dynamic> invoice) {
    final status =
        '${invoice['status'] ?? invoice['paymentStatus'] ?? ''}'.toLowerCase();
    return status == 'paid' || status == 'paid_manually';
  }

  static double _money(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static String? _businessRecognitionLabel(Map<String, dynamic> account) {
    final recognitions = Map<String, dynamic>.from(
      account['recognitions'] as Map? ?? {},
    );
    final patron = Map<String, dynamic>.from(
      recognitions['patron'] as Map? ?? {},
    );
    final awarded = patron['awarded'] == true || account['isPatron'] == true;
    if (!awarded) return null;
    final number = (patron['number'] as num?)?.toInt() ??
        (account['patronNumber'] as num?)?.toInt();
    return number == null
        ? 'Patron'
        : 'Patron #${number.toString().padLeft(3, '0')}';
  }
}

class _BusinessSenderSuiteHeader extends StatelessWidget {
  final _CircumColors colors;
  final String accountName;
  final String accountStatus;
  final String? recognitionLabel;
  final List<Map<String, dynamic>> accounts;
  final String? selectedBusinessId;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final ValueChanged<String> onSelectBusiness;

  const _BusinessSenderSuiteHeader({
    required this.colors,
    required this.accountName,
    required this.accountStatus,
    required this.recognitionLabel,
    required this.accounts,
    required this.selectedBusinessId,
    required this.busy,
    required this.onBack,
    required this.onRefresh,
    required this.onSelectBusiness,
  });

  @override
  Widget build(BuildContext context) {
    final initial = accountName.trim().isEmpty
        ? 'C'
        : accountName.trim().characters.first.toUpperCase();
    final active = accountStatus.toLowerCase() == 'approved' ||
        accountStatus.toLowerCase() == 'active';
    return _BusinessSurface(
      colors: colors,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: Icon(Icons.arrow_back, color: colors.text),
              ),
              const SizedBox(width: 4),
              Text(
                'CIRCUM · BUSINESS',
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh Business',
                onPressed: busy ? null : onRefresh,
                icon: Icon(Icons.refresh, color: colors.text),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (accounts.length > 1) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.field,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedBusinessId,
                    dropdownColor: colors.panel,
                    iconEnabledColor: colors.mutedText,
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w800,
                    ),
                    items: accounts
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: '${item['id']}',
                            child: Text(
                              '${item['businessName'] ?? item['id']}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) {
                            if (value != null) onSelectBusiness(value);
                          },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xff3b82f6), Color(0xff1e4fbf)],
                  ),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Good afternoon, $accountName.',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BusinessOperationalPill(
            colors: colors,
            label: active
                ? 'Active Business workspace'
                : 'Pending Circum approval',
            tone: active ? _BusinessTone.success : _BusinessTone.warning,
          ),
          if (recognitionLabel != null) ...[
            const SizedBox(height: 8),
            _BusinessOperationalPill(
              colors: colors,
              label: recognitionLabel!,
              tone: _BusinessTone.roth,
            ),
          ],
        ],
      ),
    );
  }
}

class _BusinessNotice extends StatelessWidget {
  final _CircumColors colors;
  final String message;

  const _BusinessNotice({required this.colors, required this.message});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Text(
          message,
          style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
        ),
      );
}

class _BusinessSkeleton extends StatelessWidget {
  final _CircumColors colors;

  const _BusinessSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) => _GlassPanel(
        colors: colors,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(colors: colors, title: 'Loading Business'),
            const SizedBox(height: 12),
            LinearProgressIndicator(color: colors.text),
            const SizedBox(height: 10),
            Text(
              'Loading company workspace, invoices, team and delivery records.',
              style: TextStyle(color: colors.mutedText),
            ),
          ],
        ),
      );
}

class _BusinessOnboardingPanel extends StatelessWidget {
  final _CircumColors colors;
  final bool busy;
  final TextEditingController companyName;
  final TextEditingController businessType;
  final TextEditingController businessEmail;
  final TextEditingController businessPhone;
  final TextEditingController businessAddress;
  final TextEditingController vatNumber;
  final TextEditingController companyCode;
  final VoidCallback onCreateBusiness;
  final VoidCallback onJoinBusiness;

  const _BusinessOnboardingPanel({
    required this.colors,
    required this.busy,
    required this.companyName,
    required this.businessType,
    required this.businessEmail,
    required this.businessPhone,
    required this.businessAddress,
    required this.vatNumber,
    required this.companyCode,
    required this.onCreateBusiness,
    required this.onJoinBusiness,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final twoColumn = constraints.maxWidth >= 760;
          final create = _GlassPanel(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(colors: colors, title: 'Create company'),
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: companyName,
                  hint: 'Company name',
                ),
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: businessType,
                  hint: 'Business type',
                ),
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: businessEmail,
                  hint: 'Business email',
                ),
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: businessPhone,
                  hint: 'Business phone',
                ),
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: businessAddress,
                  hint: 'Registered address',
                ),
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: vatNumber,
                  hint: 'VAT number optional',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onCreateBusiness,
                    icon: const Icon(Icons.business_center_outlined),
                    label: const Text('Create Business workspace'),
                  ),
                ),
              ],
            ),
          );
          final join = _GlassPanel(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(colors: colors, title: 'Join company'),
                const SizedBox(height: 10),
                Text(
                  'Enter the company code from your Business owner or admin.',
                  style: TextStyle(color: colors.mutedText, height: 1.4),
                ),
                const SizedBox(height: 10),
                _InputBox(
                  colors: colors,
                  controller: companyCode,
                  hint: 'Company code',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onJoinBusiness,
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Request access'),
                  ),
                ),
              ],
            ),
          );
          if (!twoColumn) {
            return Column(children: [create, const SizedBox(height: 14), join]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: create),
              const SizedBox(width: 14),
              Expanded(child: join),
            ],
          );
        },
      );
}

enum _BusinessTone { neutral, success, warning, danger, blue, roth }

class _BusinessSurface extends StatelessWidget {
  final _CircumColors colors;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _BusinessSurface({
    required this.colors,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: colors.dark
              ? const Color(0xff0d111c).withValues(alpha: 0.92)
              : colors.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: const Color(0xff3b82f6).withValues(alpha: 0.08),
              blurRadius: 26,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: child,
      );
}

class _BusinessSectionLabel extends StatelessWidget {
  final _CircumColors colors;
  final String label;

  const _BusinessSectionLabel({required this.colors, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: colors.mutedText,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      );
}

class _BusinessOperationalPill extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final _BusinessTone tone;

  const _BusinessOperationalPill({
    required this.colors,
    required this.label,
    this.tone = _BusinessTone.neutral,
  });

  Color get _toneColor {
    switch (tone) {
      case _BusinessTone.success:
        return const Color(0xff22c55e);
      case _BusinessTone.warning:
        return const Color(0xfff5a623);
      case _BusinessTone.danger:
        return const Color(0xfff0555b);
      case _BusinessTone.blue:
        return const Color(0xff3b82f6);
      case _BusinessTone.roth:
        return const Color(0xffc9a227);
      case _BusinessTone.neutral:
        return colors.mutedText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final toneColor = _toneColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: toneColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: toneColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: toneColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: toneColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessDeliveriesPanel extends StatelessWidget {
  final _CircumColors colors;
  final List<SenderDeliveryRecord> deliveries;
  final List<SenderDeliveryRecord> activeDeliveries;
  final VoidCallback onCreateDelivery;

  const _BusinessDeliveriesPanel({
    required this.colors,
    required this.deliveries,
    required this.activeDeliveries,
    required this.onCreateDelivery,
  });

  @override
  Widget build(BuildContext context) => _GlassPanel(
        colors: colors,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(colors: colors, title: 'Delivery management'),
            const SizedBox(height: 8),
            if (deliveries.isEmpty)
              _BusinessEmptyState(
                colors: colors,
                icon: Icons.local_shipping_outlined,
                title: 'No Business deliveries yet',
                body:
                    'Create a Business delivery to see live tracking, scheduled jobs, repeat jobs and history here.',
                action: 'Create delivery',
                onAction: onCreateDelivery,
              )
            else ...[
              Text(
                '${activeDeliveries.length} active · ${deliveries.length} total',
                style: TextStyle(
                  color: colors.mutedText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              ...deliveries.take(8).map(
                    (delivery) => _BusinessRecordRow(
                      colors: colors,
                      icon: Icons.route_outlined,
                      title: _displayDeliveryReference(
                        delivery.trackingReference.isEmpty
                            ? delivery.requestId
                            : delivery.trackingReference,
                      ),
                      subtitle:
                          '${delivery.pickupAddress} → ${delivery.dropoffAddress}',
                      trailing: _displayStatusLabel(delivery.status),
                    ),
                  ),
            ],
          ],
        ),
      );
}

class _BusinessInvoicesPanel extends StatelessWidget {
  final _CircumColors colors;
  final List<Map<String, dynamic>> invoices;
  final ValueChanged<String> onPayInvoice;
  final ValueChanged<String> onPayInvoiceWithRoth;
  final ValueChanged<Map<String, dynamic>> onDownloadInvoice;

  const _BusinessInvoicesPanel({
    required this.colors,
    required this.invoices,
    required this.onPayInvoice,
    required this.onPayInvoiceWithRoth,
    required this.onDownloadInvoice,
  });

  @override
  Widget build(BuildContext context) => _GlassPanel(
        colors: colors,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(colors: colors, title: 'Invoices'),
            const SizedBox(height: 8),
            if (invoices.isEmpty)
              _BusinessEmptyState(
                colors: colors,
                icon: Icons.receipt_long_outlined,
                title: 'No invoices yet',
                body:
                    'Business invoices will appear here with Stripe, Roth and part-payment actions.',
              )
            else
              ...invoices.take(10).map((invoice) {
                final id = '${invoice['id']}';
                final status =
                    '${invoice['status'] ?? invoice['paymentStatus'] ?? 'open'}';
                final total = _BusinessCentreStep._money(
                  invoice['balanceDue'] ?? invoice['total'],
                );
                final paid = status.toLowerCase() == 'paid';
                return _BusinessRecordRow(
                  colors: colors,
                  icon: Icons.receipt_long_outlined,
                  title: '${invoice['invoiceNumber'] ?? id}',
                  subtitle:
                      'Balance £${total.toStringAsFixed(2)} · ${_displayStatusLabel(status)}',
                  trailing: paid ? 'Paid' : 'Pay',
                  actions: [
                    TextButton(
                      onPressed: () => onDownloadInvoice(invoice),
                      child: const Text('Download PDF'),
                    ),
                    if (!paid) ...[
                      TextButton(
                        onPressed: () => onPayInvoice(id),
                        child: const Text('Stripe'),
                      ),
                      TextButton(
                        onPressed: () => onPayInvoiceWithRoth(id),
                        child: const Text('Roth'),
                      ),
                    ],
                  ],
                );
              }),
          ],
        ),
      );
}

class _BusinessTeamPanel extends StatelessWidget {
  final _CircumColors colors;
  final Map<String, dynamic> account;
  final String? currentUserId;
  final String? currentUserEmail;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> joinRequests;
  final bool busy;
  final void Function(String requestId, bool approved) onReviewRequest;
  final void Function(String memberUserId, String role) onUpdateMemberRole;
  final ValueChanged<String> onRemoveMember;
  final VoidCallback onEnsureCompanyCode;
  final VoidCallback onRotateCompanyCode;

  const _BusinessTeamPanel({
    required this.colors,
    required this.account,
    required this.currentUserId,
    required this.currentUserEmail,
    required this.members,
    required this.joinRequests,
    required this.busy,
    required this.onReviewRequest,
    required this.onUpdateMemberRole,
    required this.onRemoveMember,
    required this.onEnsureCompanyCode,
    required this.onRotateCompanyCode,
  });

  @override
  Widget build(BuildContext context) {
    final canManageCodes = _canManageCompanyCode;
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Team management'),
          const SizedBox(height: 8),
          if (canManageCodes) ...[
            _BusinessCompanyCodeCard(
              colors: colors,
              account: account,
              busy: busy,
              onEnsureCompanyCode: onEnsureCompanyCode,
              onRotateCompanyCode: onRotateCompanyCode,
            ),
            const SizedBox(height: 12),
          ],
          if (members.isEmpty)
            _BusinessEmptyState(
              colors: colors,
              icon: Icons.groups_outlined,
              title: 'No team records',
              body:
                  'Team members and roles appear after onboarding or access approval.',
            )
          else
            ...members.where((member) => member['status'] != 'removed').map(
                  (member) => _BusinessTeamRow(
                    colors: colors,
                    member: member,
                    busy: busy,
                    onRole: (role) =>
                        onUpdateMemberRole('${member['userId']}', role),
                    onRemove: () => onRemoveMember('${member['userId']}'),
                  ),
                ),
          if (joinRequests.any(
            (request) => '${request['status']}' == 'pending',
          )) ...[
            const SizedBox(height: 12),
            _SectionTitle(colors: colors, title: 'Access requests'),
            const SizedBox(height: 8),
            ...joinRequests
                .where((request) => '${request['status']}' == 'pending')
                .map(
                  (request) => _BusinessRecordRow(
                    colors: colors,
                    icon: Icons.person_add_alt_1_outlined,
                    title:
                        '${request['name'] ?? request['email'] ?? 'Requester'}',
                    subtitle:
                        'Requested role: ${request['roleRequested'] ?? 'member'}',
                    trailing: 'Pending',
                    actions: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => onReviewRequest('${request['id']}', true),
                        child: const Text('Approve'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => onReviewRequest('${request['id']}', false),
                        child: const Text('Reject'),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }

  bool get _canManageCompanyCode {
    final uid = (currentUserId ?? '').trim();
    final email = (currentUserEmail ?? '').trim().toLowerCase();
    if (uid.isNotEmpty &&
        (account['createdByUserId'] == uid || account['ownerUid'] == uid)) {
      return true;
    }
    for (final member in members) {
      final role = '${member['role'] ?? ''}'.trim().toLowerCase();
      final status = '${member['status'] ?? 'active'}'.trim().toLowerCase();
      final sameUser = uid.isNotEmpty && member['userId'] == uid;
      final sameEmail = email.isNotEmpty &&
          '${member['email'] ?? ''}'.trim().toLowerCase() == email;
      if ((sameUser || sameEmail) &&
          status != 'removed' &&
          status != 'rejected' &&
          (role == 'owner' || role == 'admin')) {
        return true;
      }
    }
    return false;
  }
}

class _BusinessCompanyCodeCard extends StatelessWidget {
  final _CircumColors colors;
  final Map<String, dynamic> account;
  final bool busy;
  final VoidCallback onEnsureCompanyCode;
  final VoidCallback onRotateCompanyCode;

  const _BusinessCompanyCodeCard({
    required this.colors,
    required this.account,
    required this.busy,
    required this.onEnsureCompanyCode,
    required this.onRotateCompanyCode,
  });

  @override
  Widget build(BuildContext context) {
    final code = '${account['companyCode'] ?? ''}'.trim();
    final hasCode = code.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.field.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasCode
              ? colors.adminAccent.withValues(alpha: .45)
              : colors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.adminAccent.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.group_add_outlined, color: colors.text, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Company code',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasCode
                      ? 'Share this with team members so they can request access to your business.'
                      : 'Generate a company code so team members can request access to your business.',
                  style: TextStyle(
                    color: colors.mutedText,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (hasCode) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    code,
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        if (!hasCode) {
                          onEnsureCompanyCode();
                          return;
                        }
                        await Clipboard.setData(ClipboardData(text: code));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Company code copied.')),
                        );
                      },
                icon: Icon(
                  hasCode ? Icons.copy_rounded : Icons.add_circle_outline,
                  size: 18,
                ),
                label: Text(hasCode ? 'Copy' : 'Generate code'),
              ),
              if (hasCode)
                TextButton.icon(
                  onPressed: busy ? null : onRotateCompanyCode,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Change code'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusinessTeamRow extends StatelessWidget {
  final _CircumColors colors;
  final Map<String, dynamic> member;
  final bool busy;
  final ValueChanged<String> onRole;
  final VoidCallback onRemove;

  const _BusinessTeamRow({
    required this.colors,
    required this.member,
    required this.busy,
    required this.onRole,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final role = '${member['role'] ?? 'member'}';
    final isOwner = role == 'owner';
    return _BusinessRecordRow(
      colors: colors,
      icon: Icons.badge_outlined,
      title: '${member['name'] ?? member['email'] ?? 'Team member'}',
      subtitle: '${member['email'] ?? ''} · ${_displayStatusLabel(role)}',
      trailing: '${member['status'] ?? 'active'}',
      actions: isOwner
          ? const []
          : [
              DropdownButton<String>(
                value: [
                  'admin',
                  'manager',
                  'dispatcher',
                  'finance',
                  'viewer',
                  'member',
                ].contains(role)
                    ? role
                    : 'member',
                dropdownColor: colors.panel,
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'manager', child: Text('Manager')),
                  DropdownMenuItem(
                    value: 'dispatcher',
                    child: Text('Dispatcher'),
                  ),
                  DropdownMenuItem(value: 'finance', child: Text('Finance')),
                  DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                  DropdownMenuItem(value: 'member', child: Text('Member')),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) onRole(value);
                      },
              ),
              TextButton(
                onPressed: busy ? null : onRemove,
                child: const Text('Remove'),
              ),
            ],
    );
  }
}

enum _BusinessWebSection {
  overview,
  deliveries,
  invoices,
  team,
  healthPlus,
  gifts,
  vanguard,
  analytics,
  finance,
  settings,
}

extension _BusinessWebSectionCopy on _BusinessWebSection {
  String get label {
    switch (this) {
      case _BusinessWebSection.overview:
        return 'Overview';
      case _BusinessWebSection.deliveries:
        return 'Deliveries';
      case _BusinessWebSection.invoices:
        return 'Invoices';
      case _BusinessWebSection.team:
        return 'Team';
      case _BusinessWebSection.healthPlus:
        return 'Health+';
      case _BusinessWebSection.gifts:
        return 'Gifts';
      case _BusinessWebSection.vanguard:
        return 'Vanguard';
      case _BusinessWebSection.analytics:
        return 'Analytics';
      case _BusinessWebSection.finance:
        return 'Finance';
      case _BusinessWebSection.settings:
        return 'Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case _BusinessWebSection.overview:
        return Icons.home_outlined;
      case _BusinessWebSection.deliveries:
        return Icons.local_shipping_outlined;
      case _BusinessWebSection.invoices:
        return Icons.receipt_long_outlined;
      case _BusinessWebSection.team:
        return Icons.groups_outlined;
      case _BusinessWebSection.healthPlus:
        return Icons.health_and_safety_outlined;
      case _BusinessWebSection.gifts:
        return Icons.card_giftcard_outlined;
      case _BusinessWebSection.vanguard:
        return Icons.shield_outlined;
      case _BusinessWebSection.analytics:
        return Icons.analytics_outlined;
      case _BusinessWebSection.finance:
        return Icons.account_balance_wallet_outlined;
      case _BusinessWebSection.settings:
        return Icons.settings_outlined;
    }
  }
}

class _BusinessSectionTabs extends StatefulWidget {
  final _CircumColors colors;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> joinRequests;
  final List<Map<String, dynamic>> auditLogs;
  final List<SenderDeliveryRecord> deliveries;
  final List<SenderDeliveryRecord> activeDeliveries;
  final List<Map<String, dynamic>> invoices;
  final Map<String, dynamic>? wallet;
  final int activeDeliveryCount;
  final int completedDeliveryCount;
  final int outstandingInvoiceCount;
  final double monthlySpend;
  final int teamMemberCount;
  final double rothBalance;
  final bool busy;
  final Map<String, dynamic> account;
  final String? currentUserId;
  final String? currentUserEmail;
  final TextEditingController rothAmount;
  final TextEditingController companyName;
  final TextEditingController businessType;
  final TextEditingController businessEmail;
  final TextEditingController businessPhone;
  final TextEditingController businessAddress;
  final TextEditingController vatNumber;
  final TextEditingController website;
  final VoidCallback onCreateDelivery;
  final VoidCallback onHealthPlus;
  final VoidCallback onGifts;
  final VoidCallback onBuyRoth;
  final ValueChanged<String> onPayInvoice;
  final ValueChanged<String> onPayInvoiceWithRoth;
  final ValueChanged<Map<String, dynamic>> onDownloadInvoice;
  final void Function(String requestId, bool approved) onReviewRequest;
  final void Function(String memberUserId, String role) onUpdateMemberRole;
  final ValueChanged<String> onRemoveMember;
  final VoidCallback onEnsureCompanyCode;
  final VoidCallback onRotateCompanyCode;
  final VoidCallback onSaveProfile;

  const _BusinessSectionTabs({
    required this.colors,
    required this.members,
    required this.joinRequests,
    required this.auditLogs,
    required this.deliveries,
    required this.activeDeliveries,
    required this.invoices,
    required this.wallet,
    required this.activeDeliveryCount,
    required this.completedDeliveryCount,
    required this.outstandingInvoiceCount,
    required this.monthlySpend,
    required this.teamMemberCount,
    required this.rothBalance,
    required this.busy,
    required this.account,
    required this.currentUserId,
    required this.currentUserEmail,
    required this.rothAmount,
    required this.companyName,
    required this.businessType,
    required this.businessEmail,
    required this.businessPhone,
    required this.businessAddress,
    required this.vatNumber,
    required this.website,
    required this.onCreateDelivery,
    required this.onHealthPlus,
    required this.onGifts,
    required this.onBuyRoth,
    required this.onPayInvoice,
    required this.onPayInvoiceWithRoth,
    required this.onDownloadInvoice,
    required this.onReviewRequest,
    required this.onUpdateMemberRole,
    required this.onRemoveMember,
    required this.onEnsureCompanyCode,
    required this.onRotateCompanyCode,
    required this.onSaveProfile,
  });

  @override
  State<_BusinessSectionTabs> createState() => _BusinessSectionTabsState();
}

class _BusinessSectionTabsState extends State<_BusinessSectionTabs> {
  var _section = _BusinessWebSection.overview;

  static const _sections = [
    _BusinessWebSection.overview,
    _BusinessWebSection.deliveries,
    _BusinessWebSection.invoices,
    _BusinessWebSection.team,
    _BusinessWebSection.healthPlus,
    _BusinessWebSection.gifts,
    _BusinessWebSection.vanguard,
    _BusinessWebSection.analytics,
    _BusinessWebSection.settings,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Business sections',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _sections
                  .map(
                    (section) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _BusinessTabChip(
                        colors: widget.colors,
                        selected: _section == section,
                        icon: section.icon,
                        label: section.label,
                        onPressed: () => setState(() => _section = section),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _selectedSection(),
      ],
    );
  }

  Widget _selectedSection() {
    switch (_section) {
      case _BusinessWebSection.overview:
        return _BusinessSuiteOverviewPanel(
          colors: widget.colors,
          activeDeliveryCount: widget.activeDeliveryCount,
          completedDeliveryCount: widget.completedDeliveryCount,
          outstandingInvoiceCount: widget.outstandingInvoiceCount,
          monthlySpend: widget.monthlySpend,
          teamMemberCount: widget.teamMemberCount,
          rothBalance: widget.rothBalance,
          deliveries: widget.deliveries,
          invoices: widget.invoices,
          rothAmount: widget.rothAmount,
          busy: widget.busy,
          onCreateDelivery: widget.onCreateDelivery,
          onTeam: () => setState(() => _section = _BusinessWebSection.team),
          onHealthPlus: widget.onHealthPlus,
          onGifts: widget.onGifts,
          onBuyRoth: widget.onBuyRoth,
        );
      case _BusinessWebSection.deliveries:
        return _BusinessDeliveriesPanel(
          colors: widget.colors,
          deliveries: widget.deliveries,
          activeDeliveries: widget.activeDeliveries,
          onCreateDelivery: widget.onCreateDelivery,
        );
      case _BusinessWebSection.invoices:
        return _BusinessInvoicesPanel(
          colors: widget.colors,
          invoices: widget.invoices,
          onPayInvoice: widget.onPayInvoice,
          onPayInvoiceWithRoth: widget.onPayInvoiceWithRoth,
          onDownloadInvoice: widget.onDownloadInvoice,
        );
      case _BusinessWebSection.team:
        return _BusinessTeamPanel(
          colors: widget.colors,
          account: widget.account,
          currentUserId: widget.currentUserId,
          currentUserEmail: widget.currentUserEmail,
          members: widget.members,
          joinRequests: widget.joinRequests,
          busy: widget.busy,
          onReviewRequest: widget.onReviewRequest,
          onUpdateMemberRole: widget.onUpdateMemberRole,
          onRemoveMember: widget.onRemoveMember,
          onEnsureCompanyCode: widget.onEnsureCompanyCode,
          onRotateCompanyCode: widget.onRotateCompanyCode,
        );
      case _BusinessWebSection.healthPlus:
        return _BusinessProductParityPanel(
          colors: widget.colors,
          deliveries: widget.deliveries,
          invoices: const [],
          wallet: widget.wallet,
          onCreateDelivery: widget.onCreateDelivery,
          onHealthPlus: widget.onHealthPlus,
          onGifts: widget.onGifts,
          onBuyRoth: widget.onBuyRoth,
          initialProduct: 'Health+',
        );
      case _BusinessWebSection.gifts:
        return _BusinessProductParityPanel(
          colors: widget.colors,
          deliveries: widget.deliveries,
          invoices: const [],
          wallet: widget.wallet,
          onCreateDelivery: widget.onCreateDelivery,
          onHealthPlus: widget.onHealthPlus,
          onGifts: widget.onGifts,
          onBuyRoth: widget.onBuyRoth,
          initialProduct: 'Gifts',
        );
      case _BusinessWebSection.vanguard:
        return _BusinessProductParityPanel(
          colors: widget.colors,
          deliveries: widget.deliveries,
          invoices: const [],
          wallet: widget.wallet,
          onCreateDelivery: widget.onCreateDelivery,
          onHealthPlus: widget.onHealthPlus,
          onGifts: widget.onGifts,
          onBuyRoth: widget.onBuyRoth,
          initialProduct: 'Vanguard',
        );
      case _BusinessWebSection.analytics:
        return _BusinessAnalyticsPanel(
          colors: widget.colors,
          deliveries: widget.deliveries,
          invoices: widget.invoices,
        );
      case _BusinessWebSection.finance:
        return _BusinessFinanceProductCard(
          colors: widget.colors,
          rothBalance: _BusinessCentreStep._money(
            widget.wallet?['balance'] ?? widget.wallet?['availableBalance'],
          ),
          outstandingInvoices: widget.invoices
              .where((invoice) => !_BusinessCentreStep._invoicePaid(invoice))
              .length,
          invoiceCount: widget.invoices.length,
          onBuyRoth: widget.onBuyRoth,
        );
      case _BusinessWebSection.settings:
        return Column(
          children: [
            _BusinessSettingsPanel(
              colors: widget.colors,
              busy: widget.busy,
              account: widget.account,
              companyName: widget.companyName,
              businessType: widget.businessType,
              businessEmail: widget.businessEmail,
              businessPhone: widget.businessPhone,
              businessAddress: widget.businessAddress,
              vatNumber: widget.vatNumber,
              website: widget.website,
              onSaveProfile: widget.onSaveProfile,
            ),
            const SizedBox(height: 14),
            _BusinessAuditPanel(
              colors: widget.colors,
              auditLogs: widget.auditLogs,
            ),
          ],
        );
    }
  }
}

class _BusinessTabChip extends StatelessWidget {
  final _CircumColors colors;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _BusinessTabChip({
    required this.colors,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xff3b82f6).withValues(alpha: 0.14)
                : colors.panel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0xff3b82f6).withValues(alpha: 0.5)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected ? const Color(0xffdce7ff) : colors.mutedText,
                size: 16,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xffdce7ff) : colors.mutedText,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      );
}

class _BusinessSuiteOverviewPanel extends StatelessWidget {
  final _CircumColors colors;
  final int activeDeliveryCount;
  final int completedDeliveryCount;
  final int outstandingInvoiceCount;
  final double monthlySpend;
  final int teamMemberCount;
  final double rothBalance;
  final List<SenderDeliveryRecord> deliveries;
  final List<Map<String, dynamic>> invoices;
  final TextEditingController rothAmount;
  final bool busy;
  final VoidCallback onCreateDelivery;
  final VoidCallback onTeam;
  final VoidCallback onHealthPlus;
  final VoidCallback onGifts;
  final VoidCallback onBuyRoth;

  const _BusinessSuiteOverviewPanel({
    required this.colors,
    required this.activeDeliveryCount,
    required this.completedDeliveryCount,
    required this.outstandingInvoiceCount,
    required this.monthlySpend,
    required this.teamMemberCount,
    required this.rothBalance,
    required this.deliveries,
    required this.invoices,
    required this.rothAmount,
    required this.busy,
    required this.onCreateDelivery,
    required this.onTeam,
    required this.onHealthPlus,
    required this.onGifts,
    required this.onBuyRoth,
  });

  @override
  Widget build(BuildContext context) {
    final recent = deliveries.take(2).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 14),
          child: Text(
            'Your command centre for deliveries, invoices, team access, Health+, Gifts, Vanguard and IRIS insights.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _BusinessSectionLabel(colors: colors, label: 'This month'),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 720 ? 2 : 4;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: columns == 2 ? 1.32 : 1.45,
              children: [
                _BusinessStatCard(
                  colors: colors,
                  label: 'Deliveries',
                  value: '$activeDeliveryCount',
                  delta: '$completedDeliveryCount completed',
                ),
                _BusinessStatCard(
                  colors: colors,
                  label: 'Outstanding',
                  value: '£${_outstandingAmount.toStringAsFixed(2)}',
                  delta: '$outstandingInvoiceCount invoices due',
                  tone: _BusinessTone.warning,
                ),
                _BusinessStatCard(
                  colors: colors,
                  label: 'Team members',
                  value: '$teamMemberCount',
                  delta: 'Active workspace',
                ),
                _BusinessStatCard(
                  colors: colors,
                  label: 'Roth offset',
                  value: '£${rothBalance.toStringAsFixed(2)}',
                  delta: 'Applied at invoicing',
                  tone: _BusinessTone.roth,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _BusinessSectionLabel(colors: colors, label: 'Quick actions'),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 640 ? 2 : 4;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: columns == 2 ? 1.12 : 1.08,
              children: [
                _BusinessActionTile(
                  colors: colors,
                  icon: Icons.local_shipping_outlined,
                  title: 'Book a delivery',
                  subtitle: 'New job on a default pickup address',
                  onPressed: onCreateDelivery,
                ),
                _BusinessActionTile(
                  colors: colors,
                  icon: Icons.group_add_outlined,
                  title: 'Invite teammate',
                  subtitle: 'Add booking or admin access',
                  onPressed: onTeam,
                ),
                _BusinessActionTile(
                  colors: colors,
                  icon: Icons.health_and_safety_outlined,
                  title: 'Health+ request',
                  subtitle: 'Vanguard-covered by default',
                  onPressed: onHealthPlus,
                ),
                _BusinessActionTile(
                  colors: colors,
                  icon: Icons.card_giftcard_outlined,
                  title: 'Corporate gift',
                  subtitle: 'Contents stay undisclosed',
                  onPressed: onGifts,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _BusinessSectionLabel(colors: colors, label: 'Business Roth'),
        _BusinessSurface(
          colors: colors,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                child: _InputBox(
                  colors: colors,
                  controller: rothAmount,
                  hint: 'Roth £',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onBuyRoth,
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Add Business Roth'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _BusinessSectionLabel(colors: colors, label: 'Recent activity'),
        if (recent.isEmpty)
          _BusinessEmptyState(
            colors: colors,
            icon: Icons.history_outlined,
            title: 'No Business activity yet',
            body:
                'Business deliveries, invoice events and premium service activity will appear here.',
          )
        else
          ...recent.map(
            (delivery) => _BusinessRecordRow(
              colors: colors,
              icon: _BusinessProductParityPanel._hasVanguard(delivery)
                  ? Icons.shield_outlined
                  : Icons.local_shipping_outlined,
              title: _displayDeliveryReference(
                delivery.trackingReference.isEmpty
                    ? delivery.requestId
                    : delivery.trackingReference,
              ),
              subtitle:
                  '${delivery.pickupAddress} → ${delivery.dropoffAddress}',
              trailing: _displayStatusLabel(delivery.status),
            ),
          ),
      ],
    );
  }

  double get _outstandingAmount {
    return invoices
        .where((invoice) => !_BusinessCentreStep._invoicePaid(invoice))
        .fold<double>(
          0,
          (total, invoice) =>
              total +
              _BusinessCentreStep._money(
                invoice['balanceDue'] ?? invoice['total'] ?? invoice['amount'],
              ),
        );
  }
}

class _BusinessStatCard extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;
  final String delta;
  final _BusinessTone tone;

  const _BusinessStatCard({
    required this.colors,
    required this.label,
    required this.value,
    required this.delta,
    this.tone = _BusinessTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor =
        tone == _BusinessTone.roth ? const Color(0xffc9a227) : colors.text;
    return _BusinessSurface(
      colors: colors,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.mutedText,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            delta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tone == _BusinessTone.warning
                  ? const Color(0xfff5a623)
                  : colors.mutedText,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessActionTile extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  const _BusinessActionTile({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => _BusinessSurface(
        colors: colors,
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.field,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: colors.text, size: 18),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.mutedText,
                    height: 1.3,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _BusinessProductParityPanel extends StatelessWidget {
  final _CircumColors colors;
  final List<SenderDeliveryRecord> deliveries;
  final List<Map<String, dynamic>> invoices;
  final Map<String, dynamic>? wallet;
  final VoidCallback onCreateDelivery;
  final VoidCallback onHealthPlus;
  final VoidCallback onGifts;
  final VoidCallback onBuyRoth;
  final String? initialProduct;

  const _BusinessProductParityPanel({
    required this.colors,
    required this.deliveries,
    required this.invoices,
    required this.wallet,
    required this.onCreateDelivery,
    required this.onHealthPlus,
    required this.onGifts,
    required this.onBuyRoth,
    this.initialProduct,
  });

  @override
  Widget build(BuildContext context) {
    final health = _matchingDeliveries(const [
      'health',
      'pharmacy',
      'prescription',
      'medical',
    ]);
    final gifts = _matchingDeliveries(const ['gift', 'gifts']);
    final vanguard = deliveries.where(_hasVanguard).toList(growable: false);
    final outstanding = invoices
        .where((invoice) => !_BusinessCentreStep._invoicePaid(invoice))
        .length;
    final roth = _BusinessCentreStep._money(
      wallet?['balance'] ?? wallet?['availableBalance'],
    );

    final cards = [
      _BusinessProductCard(
        colors: colors,
        icon: Icons.health_and_safety_outlined,
        title: 'Health+',
        subtitle:
            'Business prescription pickups and medical deliveries with Vanguard included.',
        primaryMetric: '${health.length}',
        primaryLabel: 'Health+ records',
        secondaryMetric:
            '${health.where((item) => _active(item.status)).length}',
        secondaryLabel: 'Active',
        actionLabel: 'New Health+ request',
        onAction: onHealthPlus,
        records: health,
        badgeLabel: 'Vanguard Included',
      ),
      _BusinessProductCard(
        colors: colors,
        icon: Icons.card_giftcard_outlined,
        title: 'Gifts',
        subtitle:
            'Corporate gift requests, recipient status and protected delivery history.',
        primaryMetric: '${gifts.length}',
        primaryLabel: 'Gift records',
        secondaryMetric:
            '${gifts.where((item) => _active(item.status)).length}',
        secondaryLabel: 'Active',
        actionLabel: 'Start corporate gift',
        onAction: onGifts,
        records: gifts,
        badgeLabel: 'Vanguard Included',
      ),
      _BusinessProductCard(
        colors: colors,
        icon: Icons.shield_outlined,
        title: 'Vanguard',
        subtitle:
            'Important deliveries with enhanced custody tracking and trusted Circum Rider prioritisation.',
        primaryMetric: '${vanguard.length}',
        primaryLabel: 'Vanguard deliveries',
        secondaryMetric:
            '${vanguard.where((item) => _active(item.status)).length}',
        secondaryLabel: 'Active',
        actionLabel: 'Create Vanguard delivery',
        onAction: onCreateDelivery,
        records: vanguard,
        badgeLabel: 'Custody tracking',
      ),
      _BusinessFinanceProductCard(
        colors: colors,
        rothBalance: roth,
        outstandingInvoices: outstanding,
        invoiceCount: invoices.length,
        onBuyRoth: onBuyRoth,
      ),
    ];
    final visibleCards = initialProduct == null
        ? cards
        : cards.where((card) {
            if (card is _BusinessProductCard) {
              return card.title == initialProduct;
            }
            return initialProduct == 'Finance';
          }).toList();

    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Business products'),
          const SizedBox(height: 8),
          Text(
            'The web centre now exposes the same operational areas as the app: Health+, Gifts, Vanguard and Finance.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 760 ? 1 : 2;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: columns == 1 ? 1.55 : 1.35,
                children: visibleCards,
              );
            },
          ),
        ],
      ),
    );
  }

  List<SenderDeliveryRecord> _matchingDeliveries(List<String> needles) {
    return deliveries.where((delivery) {
      final haystack = [
        delivery.status,
        delivery.raw['category'],
        delivery.raw['deliveryCategory'],
        delivery.raw['service'],
        delivery.raw['product'],
        delivery.raw['workflow'],
        delivery.raw['deliveryType'],
        delivery.raw['requestType'],
        delivery.raw['notes'],
      ].join(' ').toLowerCase();
      return needles.any(haystack.contains);
    }).toList(growable: false);
  }

  static bool _active(String status) {
    final normalized = status.toLowerCase();
    return !const {
      'completed',
      'delivered',
      'cancelled',
      'canceled',
      'failed',
    }.contains(normalized);
  }

  static bool _hasVanguard(SenderDeliveryRecord delivery) {
    final raw = delivery.raw;
    final category =
        '${raw['category'] ?? raw['deliveryCategory'] ?? ''}'.toLowerCase();
    final protection = raw['vanguardProtection'];
    return raw['vanguardEnabled'] == true ||
        raw['vanguardRequired'] == true ||
        category.contains('vanguard') ||
        (protection is Map && protection['enabled'] == true);
  }
}

class _BusinessProductCard extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryMetric;
  final String primaryLabel;
  final String secondaryMetric;
  final String secondaryLabel;
  final String actionLabel;
  final VoidCallback onAction;
  final List<SenderDeliveryRecord> records;
  final String? badgeLabel;

  const _BusinessProductCard({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryMetric,
    required this.primaryLabel,
    required this.secondaryMetric,
    required this.secondaryLabel,
    required this.actionLabel,
    required this.onAction,
    required this.records,
    this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.text),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (badgeLabel != null) _HealthChip(label: badgeLabel!),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: colors.mutedText,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MetricPill(
                    colors: colors,
                    label: primaryLabel,
                    value: primaryMetric,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricPill(
                    colors: colors,
                    label: secondaryLabel,
                    value: secondaryMetric,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (records.isEmpty)
              Text(
                'No ${title.toLowerCase()} records yet.',
                style: TextStyle(color: colors.mutedText),
              )
            else
              ...records.take(2).map(
                    (record) => _BusinessRecordRow(
                      colors: colors,
                      icon: Icons.route_outlined,
                      title: _displayDeliveryReference(
                        record.trackingReference.isEmpty
                            ? record.requestId
                            : record.trackingReference,
                      ),
                      subtitle: record.dropoffAddress,
                      trailing: _displayStatusLabel(record.status),
                    ),
                  ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      );
}

class _BusinessFinanceProductCard extends StatelessWidget {
  final _CircumColors colors;
  final double rothBalance;
  final int outstandingInvoices;
  final int invoiceCount;
  final VoidCallback onBuyRoth;

  const _BusinessFinanceProductCard({
    required this.colors,
    required this.rothBalance,
    required this.outstandingInvoices,
    required this.invoiceCount,
    required this.onBuyRoth,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined, color: colors.text),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Finance',
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
              'Business invoices, printable records, Stripe payment and Roth payment are available from web.',
              style: TextStyle(
                color: colors.mutedText,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MetricPill(
                    colors: colors,
                    label: 'Business Roth',
                    value: '£${rothBalance.toStringAsFixed(2)}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricPill(
                    colors: colors,
                    label: 'Outstanding',
                    value: '$outstandingInvoices',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _BusinessRecordRow(
              colors: colors,
              icon: Icons.receipt_long_outlined,
              title: 'Invoice records',
              subtitle: '$invoiceCount invoices available for print or PDF',
              trailing: '$invoiceCount',
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onBuyRoth,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('Add Business Roth'),
              ),
            ),
          ],
        ),
      );
}

class _BusinessAnalyticsPanel extends StatelessWidget {
  final _CircumColors colors;
  final List<SenderDeliveryRecord> deliveries;
  final List<Map<String, dynamic>> invoices;

  const _BusinessAnalyticsPanel({
    required this.colors,
    required this.deliveries,
    required this.invoices,
  });

  @override
  Widget build(BuildContext context) {
    final completed = deliveries
        .where(
          (delivery) => [
            'completed',
            'delivered',
          ].contains(delivery.status.toLowerCase()),
        )
        .length;
    final successRate =
        deliveries.isEmpty ? 0 : completed / deliveries.length * 100;
    final spend = deliveries.fold<double>(
      0,
      (total, delivery) => total + delivery.pricePaid,
    );
    final average = deliveries.isEmpty ? 0 : spend / deliveries.length;
    final destinations = <String, int>{};
    for (final delivery in deliveries) {
      final key = delivery.dropoffAddress.trim().isEmpty
          ? 'Unknown destination'
          : delivery.dropoffAddress;
      destinations[key] = (destinations[key] ?? 0) + 1;
    }
    final topDestinations = destinations.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Analytics'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _BusinessMiniMetric(
                colors: colors,
                label: 'Spend',
                value: '£${spend.toStringAsFixed(2)}',
              ),
              _BusinessMiniMetric(
                colors: colors,
                label: 'Deliveries',
                value: '${deliveries.length}',
              ),
              _BusinessMiniMetric(
                colors: colors,
                label: 'Success rate',
                value: '${successRate.toStringAsFixed(0)}%',
              ),
              _BusinessMiniMetric(
                colors: colors,
                label: 'Average cost',
                value: '£${average.toStringAsFixed(2)}',
              ),
              _BusinessMiniMetric(
                colors: colors,
                label: 'Invoices',
                value: '${invoices.length}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (topDestinations.isEmpty)
            Text(
              'Top destinations will appear after Business deliveries complete.',
              style: TextStyle(color: colors.mutedText),
            )
          else
            ...topDestinations.take(3).map(
                  (entry) => _BusinessRecordRow(
                    colors: colors,
                    icon: Icons.place_outlined,
                    title: entry.key,
                    subtitle: 'Destination frequency',
                    trailing: '${entry.value}',
                  ),
                ),
        ],
      ),
    );
  }
}

class _BusinessSettingsPanel extends StatelessWidget {
  final _CircumColors colors;
  final bool busy;
  final Map<String, dynamic> account;
  final TextEditingController companyName;
  final TextEditingController businessType;
  final TextEditingController businessEmail;
  final TextEditingController businessPhone;
  final TextEditingController businessAddress;
  final TextEditingController vatNumber;
  final TextEditingController website;
  final VoidCallback onSaveProfile;

  const _BusinessSettingsPanel({
    required this.colors,
    required this.busy,
    required this.account,
    required this.companyName,
    required this.businessType,
    required this.businessEmail,
    required this.businessPhone,
    required this.businessAddress,
    required this.vatNumber,
    required this.website,
    required this.onSaveProfile,
  });

  @override
  Widget build(BuildContext context) => _GlassPanel(
        colors: colors,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(colors: colors, title: 'Settings'),
            const SizedBox(height: 10),
            _InputBox(
              colors: colors,
              controller: companyName,
              hint: 'Company name',
            ),
            const SizedBox(height: 10),
            _InputBox(
              colors: colors,
              controller: businessType,
              hint: 'Business type',
            ),
            const SizedBox(height: 10),
            _InputBox(
              colors: colors,
              controller: businessEmail,
              hint: 'Billing email',
            ),
            const SizedBox(height: 10),
            _InputBox(colors: colors, controller: businessPhone, hint: 'Phone'),
            const SizedBox(height: 10),
            _InputBox(
              colors: colors,
              controller: businessAddress,
              hint: 'Business address',
            ),
            const SizedBox(height: 10),
            _InputBox(
                colors: colors, controller: vatNumber, hint: 'VAT number'),
            const SizedBox(height: 10),
            _InputBox(
              colors: colors,
              controller: website,
              hint: 'Website / brand URL',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onSaveProfile,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Business settings'),
                ),
                _StatusPill(
                  colors: colors,
                  label:
                      '${account['approvalStatus'] ?? account['status'] ?? 'pending'}',
                ),
              ],
            ),
          ],
        ),
      );
}

class _BusinessAuditPanel extends StatelessWidget {
  final _CircumColors colors;
  final List<Map<String, dynamic>> auditLogs;

  const _BusinessAuditPanel({required this.colors, required this.auditLogs});

  @override
  Widget build(BuildContext context) => _GlassPanel(
        colors: colors,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(colors: colors, title: 'Audit history'),
            const SizedBox(height: 8),
            if (auditLogs.isEmpty)
              Text(
                'Business audit events will appear here.',
                style: TextStyle(color: colors.mutedText),
              )
            else
              ...auditLogs.take(8).map(
                    (log) => _BusinessRecordRow(
                      colors: colors,
                      icon: Icons.fact_check_outlined,
                      title: '${log['action'] ?? 'Business event'}',
                      subtitle: _adminDateText(log['createdAt']),
                      trailing: '${log['actorUserId'] ?? ''}'.isEmpty
                          ? 'System'
                          : 'User',
                    ),
                  ),
          ],
        ),
      );
}

class _BusinessMiniMetric extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;

  const _BusinessMiniMetric({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        child: _MetricPill(colors: colors, label: label, value: value),
      );
}

class _BusinessRecordRow extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final List<Widget> actions;

  const _BusinessRecordRow({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.field,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: colors.text),
            const SizedBox(width: 10),
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
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(color: colors.mutedText, height: 1.35),
                  ),
                ],
              ),
            ),
            if (actions.isEmpty)
              Text(
                trailing,
                style:
                    TextStyle(color: colors.text, fontWeight: FontWeight.w900),
              )
            else
              Wrap(spacing: 4, children: actions),
          ],
        ),
      );
}

class _BusinessEmptyState extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  const _BusinessEmptyState({
    required this.colors,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.text),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(body, style: TextStyle(color: colors.mutedText, height: 1.4)),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      );
}

class _LegendBadge extends StatelessWidget {
  final int number;

  const _LegendBadge({required this.number});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xffa78bfa), Color(0xff38bdf8), Color(0xff5eead4)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'LEGEND #$number',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

class _LegendCard extends StatelessWidget {
  final _CircumColors colors;
  final String name;
  final int number;
  final DateTime? awardedAt;
  final bool celebratory;
  final VoidCallback? onClose;

  const _LegendCard({
    required this.colors,
    required this.name,
    required this.number,
    this.awardedAt,
    this.celebratory = false,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xff070b17),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xff7dd3fc)),
          boxShadow: const [
            BoxShadow(color: Color(0x5538bdf8), blurRadius: 30)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xff5eead4)),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'CIRCUM LEGEND',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
              ],
            ),
            if (celebratory) ...[
              const SizedBox(height: 14),
              const Text(
                'You’re officially a Circum Legend.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xffc084fc),
                  Color(0xff38bdf8),
                  Color(0xff5eead4)
                ],
              ).createShader(bounds),
              child: Text(
                'Legend #$number',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Awarded ${_readableDate(awardedAt)}',
              style: const TextStyle(color: Color(0xffcbd5e1)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Legend status is a recognition badge and may unlock future Circum perks. It does not represent shares, equity, ownership, or financial rights.',
              style: TextStyle(color: Color(0xff94a3b8), height: 1.4),
            ),
            if (celebratory) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onClose,
                  child: const Text('View my Legend card'),
                ),
              ),
            ],
          ],
        ),
      );
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
  final ValueChanged<SenderDeliveryRecord> onCancelBooking;

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
    required this.onCancelBooking,
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
                                : user!.email ?? 'Circum',
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
                          if (profile?.isLegend == true &&
                              profile?.legendNumber != null) ...[
                            const SizedBox(height: 7),
                            _LegendBadge(number: profile!.legendNumber!),
                          ],
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
        onCancelBooking: onCancelBooking,
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
        if (profile?.isLegend == true && profile?.legendNumber != null) ...[
          _LegendCard(
            colors: colors,
            name:
                profile!.fullName.isEmpty ? 'Circum member' : profile!.fullName,
            number: profile!.legendNumber!,
            awardedAt: profile!.legendAwardedAt,
          ),
          const SizedBox(height: 16),
        ],
        _SectionTitle(colors: colors, title: 'Profile details'),
        const SizedBox(height: 12),
        _InputBox(colors: colors, controller: fullName, hint: 'Full name'),
        const SizedBox(height: 10),
        _InputBox(colors: colors, controller: phone, hint: 'Phone number'),
        const SizedBox(height: 10),
        _InputBox(
          colors: colors,
          controller: email,
          hint: 'Email',
          enabled: false,
        ),
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
      return _empty(
        'No parcels yet',
        'When you send with Circum, your parcel history will appear here.',
      );
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
                '${delivery.pickupAddress} to ${delivery.dropoffAddress}\n${_jobReceivedTextFromDate(delivery.createdAt)}',
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
                  Text(
                    delivery.status,
                    style: TextStyle(color: colors.mutedText, fontSize: 12),
                  ),
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
    final pickupAddresses = addresses.where(
      (address) => address.addressType != 'dropoff',
    );
    final dropoffAddresses = addresses.where(
      (address) => address.addressType == 'dropoff',
    );
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
                (label) => DropdownMenuItem(value: label, child: Text(label)),
              )
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
      subtitle: Text(
        address.address,
        style: TextStyle(color: colors.mutedText),
      ),
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
      return _empty(
        'No reviews yet',
        'Ratings you leave after completed deliveries will show here.',
      );
    }
    return Column(
      children: rated
          .map(
            (delivery) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.star, color: Colors.amber.shade700),
              title: Text(
                '${delivery.ratingGiven} stars',
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(
                delivery.requestId,
                style: TextStyle(color: colors.mutedText),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _supportTab() {
    final notes = deliveries.expand((delivery) => delivery.supportNotes);
    if (notes.isEmpty) {
      return _empty(
        'No support notes',
        'If anything needs attention, Circum support notes will sit here.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: notes
          .map(
            (note) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('$note', style: TextStyle(color: colors.text)),
            ),
          )
          .toList(),
    );
  }

  Widget _empty(String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
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
  final ValueChanged<SenderDeliveryRecord> onCancelBooking;

  const _SenderDeliveryDetails({
    required this.colors,
    required this.delivery,
    required this.onClose,
    required this.onCancelBooking,
  });

  @override
  Widget build(BuildContext context) {
    final proof = proofOfDeliveryFromRecord(
      delivery.raw,
      fallbackReference: delivery.trackingReference,
    );
    final rows = {
      'Delivery reference': _displayDeliveryReference(
        delivery.trackingReference.isEmpty
            ? delivery.requestId
            : delivery.trackingReference,
      ),
      'Status': _displayStatusLabel(delivery.status),
      'Pickup': delivery.pickupAddress,
      'Drop-off': delivery.dropoffAddress,
      'Received': _jobReceivedTextFromDate(delivery.createdAt),
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
              child: _SectionTitle(colors: colors, title: delivery.requestId),
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
                Text(
                  row.key.toUpperCase(),
                  style: TextStyle(
                    color: colors.mutedText,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  row.value,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        _SenderProofOfDeliveryPanel(colors: colors, proof: proof),
        if (BookingCancellationPolicy.canSenderCancel(delivery.status)) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => onCancelBooking(delivery),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel Booking'),
          ),
        ],
      ],
    );
  }
}

class _SenderProofOfDeliveryPanel extends StatelessWidget {
  final _CircumColors colors;
  final ProofOfDeliveryDetails proof;

  const _SenderProofOfDeliveryPanel({
    required this.colors,
    required this.proof,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = proof.statusLabel.toLowerCase().contains('available')
        ? const Color(0xFF34D399)
        : proof.statusLabel.toLowerCase().contains('review')
            ? const Color(0xFFFBBF24)
            : const Color(0xFFF87171);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.field,
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
                  'Proof of Delivery',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withValues(alpha: .24)),
                ),
                child: Text(
                  proof.statusLabel,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!proof.hasAnyProof)
            Text(
              'Proof of delivery is not available for this delivery.',
              style: TextStyle(color: colors.mutedText, height: 1.45),
            )
          else ...[
            if (proof.hasPhoto) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    proof.photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: colors.border.withValues(alpha: .18),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: colors.mutedText,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: colors.appBackground,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.network(
                        proof.photoUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Proof photo could not be loaded.',
                            style: TextStyle(color: colors.text),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                icon: const Icon(Icons.open_in_full_rounded),
                label: const Text('View full proof'),
              ),
              const SizedBox(height: 10),
            ],
            for (final row in proof.visibleRows)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(color: colors.mutedText, height: 1.35),
                    children: [
                      TextSpan(
                        text: '${row.$1}: ',
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(text: row.$2),
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
          color: colors.appBackground.withValues(alpha: 0.95),
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
  final int irisQuantity;
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
  final String? deliveryTimingType;
  final ValueChanged<String> onDeliveryTimingChanged;
  final String? parcelPhotoName;
  final bool parcelPhotoBusy;
  final String? parcelPhotoMessage;
  final VoidCallback onPickParcelPhoto;
  final VoidCallback onRemoveParcelPhoto;
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
    required this.irisQuantity,
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
    required this.deliveryTimingType,
    required this.onDeliveryTimingChanged,
    required this.parcelPhotoName,
    required this.parcelPhotoBusy,
    required this.parcelPhotoMessage,
    required this.onPickParcelPhoto,
    required this.onRemoveParcelPhoto,
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
                        : deliveryTimingType == null
                            ? 'Choose delivery timing'
                            : 'Complete delivery timing';
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
                        hint: 'Circum name',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _InputBox(
                        colors: colors,
                        controller: senderPhone,
                        hint: 'Circum phone',
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
              _SectionTitle(colors: colors, title: 'When do you need this?'),
              const SizedBox(height: 12),
              _DeliveryTimingChoices(
                colors: colors,
                selected: deliveryTimingType,
                onSelected: onDeliveryTimingChanged,
              ),
              if (deliveryTimingType == 'today') ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _CompactSelectBox(
                        colors: colors,
                        controller: scheduledPickupWindow,
                        label: 'Pickup window',
                        options: _todayWindowOptions,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CompactSelectBox(
                        colors: colors,
                        controller: scheduledDropoffWindow,
                        label: 'Delivery window',
                        options: _todayWindowOptions,
                      ),
                    ),
                  ],
                ),
              ],
              if (deliveryTimingType == 'scheduled') ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ScheduleDateButton(
                        colors: colors,
                        controller: scheduledPickupDate,
                        label: 'Pickup date',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CompactSelectBox(
                        colors: colors,
                        controller: scheduledPickupWindow,
                        label: 'Pickup window',
                        options: _todayWindowOptions,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ScheduleDateButton(
                        colors: colors,
                        controller: scheduledDropoffDate,
                        label: 'Delivery date',
                        minimumDateController: scheduledPickupDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _CompactSelectBox(
                        colors: colors,
                        controller: scheduledDropoffWindow,
                        label: 'Delivery window',
                        options: _todayWindowOptions,
                      ),
                    ),
                  ],
                ),
              ],
              if (deliveryTimingType == 'asap') ...[
                const SizedBox(height: 12),
                Text(
                  'We will show delivery options now. Rider matching starts after payment and booking confirmation.',
                  style: TextStyle(
                    color: colors.mutedText,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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
                    'Describe Your Item & Quantity',
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
                hint:
                    'Examples: 1 Sofa, 3 Dining Chairs, 5 MacBooks, 2 Suitcases, 12 Boxes of Books',
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
                  _PhotoButton(
                    colors: colors,
                    fileName: parcelPhotoName,
                    busy: parcelPhotoBusy,
                    onPick: onPickParcelPhoto,
                    onRemove: onRemoveParcelPhoto,
                  ),
                ],
              ),
              if (parcelPhotoMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  parcelPhotoMessage!,
                  style: TextStyle(
                    color: colors.mutedText,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (weightMessage != null) ...[
                const SizedBox(height: 12),
                _WeightConfirmationPanel(
                  colors: colors,
                  estimatedWeightKg: irisEstimatedWeightKg,
                  weightBand: irisWeightBand,
                  confidence: irisWeightConfidence,
                  explanation: irisWeightExplanation,
                  matchedItemName: irisMatchedItemName,
                  quantity: irisQuantity,
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
              disabledBackgroundColor: colors.text.withValues(alpha: 0.45),
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

class _HealthPlusStep extends StatefulWidget {
  final _CircumColors colors;
  final TextEditingController fullName;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController pharmacyName;
  final TextEditingController pharmacyAddress;
  final TextEditingController deliveryAddress;
  final bool pharmacyVerified;
  final bool deliveryVerified;
  final TextEditingController notes;
  final TextEditingController preferredDay;
  final TextEditingController preferredTime;
  final TextEditingController customSchedule;
  final HealthPlusFrequency frequency;
  final String prescriptionType;
  final String subscriptionPlan;
  final bool consent;
  final bool savePayment;
  final bool useRoth;
  final double rothBalance;
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
  final ValueChanged<bool?> onUseRoth;
  final ValueChanged<_ValidatedAddress> onPharmacySelected;
  final ValueChanged<String> onPharmacyEdited;
  final ValueChanged<_ValidatedAddress> onDeliverySelected;
  final ValueChanged<String> onDeliveryEdited;
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
    required this.pharmacyVerified,
    required this.deliveryVerified,
    required this.notes,
    required this.preferredDay,
    required this.preferredTime,
    required this.customSchedule,
    required this.frequency,
    required this.prescriptionType,
    required this.subscriptionPlan,
    required this.consent,
    required this.savePayment,
    required this.useRoth,
    required this.rothBalance,
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
    required this.onUseRoth,
    required this.onPharmacySelected,
    required this.onPharmacyEdited,
    required this.onDeliverySelected,
    required this.onDeliveryEdited,
    required this.onSubmit,
    required this.onPauseSchedule,
    required this.onResumeSchedule,
    required this.onCancelSchedule,
    required this.onCancelPickup,
    required this.onUpdatePayment,
    required this.onAdminStatus,
  });

  @override
  State<_HealthPlusStep> createState() => _HealthPlusStepState();
}

class _HealthPlusStepState extends State<_HealthPlusStep> {
  int _currentStep = 0;

  static const _steps = [
    ('Status', 'HEALTH+', 'Your prescription pickups'),
    ('Details', 'STEP 01 - YOUR DETAILS', 'Confirm who this is for'),
    ('Pharmacy', 'STEP 02 - PHARMACY', "Where's the prescription?"),
    ('Delivery', 'STEP 03 - DELIVERY', 'Where should it go?'),
    ('Frequency', 'STEP 04 - FREQUENCY', 'How often?'),
    ('Plan', 'STEP 05 - PLAN', 'Choose your plan'),
    ('Notes', 'STEP 06 - NOTES & CONSENT', 'Anything the rider should know?'),
    ('Review', 'STEP 07 - REVIEW', 'Review your pickup'),
    ('Checkout', 'STEP 08 - CHECKOUT', 'Secure payment'),
    ('Confirmed', 'STEP 09 - CONFIRMED', 'Pickup scheduled'),
  ];

  void _goTo(int step) {
    setState(() => _currentStep = step.clamp(0, _steps.length - 1));
  }

  void _next() => _goTo(_currentStep + 1);

  void _previous() {
    if (_currentStep == 0) {
      widget.onBack();
      return;
    }
    _goTo(_currentStep - 1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final nextPickup = widget.pickups.isEmpty ? null : widget.pickups.first;
    final current = _steps[_currentStep];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTopBar(colors: colors, title: 'Health+', onBack: _previous),
        const SizedBox(height: 14),
        _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CIRCUM',
                style: TextStyle(
                  color: const Color(0xff2fae8c),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'serif',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'HEALTH+ - GUIDED PICKUP',
                style: TextStyle(
                  color: colors.mutedText,
                  letterSpacing: .12,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 14),
              _HealthGuidedProgress(
                colors: colors,
                currentStep: _currentStep,
                totalSteps: _steps.length,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _steps.length; index++)
                    _HealthGuidedChip(
                      colors: colors,
                      label:
                          '${index.toString().padLeft(2, '0')} ${_steps[index].$1}',
                      active: index == _currentStep,
                      complete: _healthStepComplete(index),
                      onTap: () => _goTo(index),
                    ),
                ],
              ),
              const SizedBox(height: 18),
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
                    child: const Icon(
                      Icons.health_and_safety,
                      color: Color(0xff16a34a),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.$2,
                          style: TextStyle(
                            color: const Color(0xff2fae8c),
                            fontSize: 11,
                            letterSpacing: .12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          current.$3,
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 26,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Guided prescription pickup, step by step, using the same Health+ pricing and checkout already live in Circum.',
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
                  _HealthChip(label: 'Vanguard Included'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildGuidedPanel(nextPickup),
        const SizedBox(height: 14),
        _HealthTrustGrid(colors: colors),
      ],
    );
  }

  bool _healthStepComplete(int step) {
    return switch (step) {
      0 => widget.pickups.isNotEmpty,
      1 => widget.fullName.text.trim().isNotEmpty &&
          widget.phone.text.trim().isNotEmpty &&
          widget.email.text.trim().isNotEmpty,
      2 => widget.pharmacyVerified,
      3 => widget.deliveryVerified,
      4 => true,
      5 => widget.subscriptionPlan.trim().isNotEmpty,
      6 => widget.notes.text.trim().isNotEmpty && widget.consent,
      7 => widget.consent,
      8 => widget.payments.isNotEmpty || widget.checkoutUrl != null,
      9 => widget.pickups.isNotEmpty,
      _ => false,
    };
  }

  Widget _buildGuidedPanel(Map<String, dynamic>? nextPickup) {
    final colors = widget.colors;
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(
              key: ValueKey(_currentStep),
              child: _stepBody(nextPickup),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (_currentStep > 0)
                OutlinedButton.icon(
                  onPressed: _previous,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Back'),
                ),
              const Spacer(),
              if (_currentStep < _steps.length - 2)
                FilledButton.icon(
                  onPressed: _next,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Continue'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBody(Map<String, dynamic>? nextPickup) {
    final colors = widget.colors;
    switch (_currentStep) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HealthDashboard(
              colors: colors,
              pickup: nextPickup,
              payments: widget.payments,
              onPauseSchedule: widget.onPauseSchedule,
              onResumeSchedule: widget.onResumeSchedule,
              onCancelSchedule: widget.onCancelSchedule,
              onCancelPickup: widget.onCancelPickup,
              onUpdatePayment: widget.onUpdatePayment,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _goTo(1),
                icon: const Icon(Icons.medical_services_outlined),
                label: const Text('Book a new pickup'),
              ),
            ),
          ],
        );
      case 1:
        return Column(
          children: [
            _InputBox(
              colors: colors,
              controller: widget.fullName,
              hint: 'Full name',
            ),
            const SizedBox(height: 10),
            _InputBox(
              colors: colors,
              controller: widget.phone,
              hint: 'Phone number',
            ),
            const SizedBox(height: 10),
            _InputBox(colors: colors, controller: widget.email, hint: 'Email'),
          ],
        );
      case 2:
        return Column(
          children: [
            _InputBox(
              colors: colors,
              controller: widget.pharmacyName,
              hint: 'Pharmacy name',
            ),
            const SizedBox(height: 10),
            _AddressField(
              colors: colors,
              icon: Icons.local_pharmacy,
              controller: widget.pharmacyAddress,
              label: 'Pharmacy pickup address',
              pharmacyMode: true,
              verified: widget.pharmacyVerified,
              verifiedMessage: 'Verified pharmacy address selected',
              onSelected: widget.onPharmacySelected,
              onEdited: widget.onPharmacyEdited,
            ),
            const SizedBox(height: 8),
            _HealthAddressVerificationHint(
              colors: colors,
              verified: widget.pharmacyVerified,
              label: 'Choose a verified address result before continuing.',
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AddressField(
              colors: colors,
              icon: Icons.home_outlined,
              controller: widget.deliveryAddress,
              label: 'Delivery address',
              verified: widget.deliveryVerified,
              verifiedMessage: 'Verified delivery address selected',
              onSelected: widget.onDeliverySelected,
              onEdited: widget.onDeliveryEdited,
            ),
            const SizedBox(height: 8),
            _HealthAddressVerificationHint(
              colors: colors,
              verified: widget.deliveryVerified,
              label: 'Choose a verified address result before continuing.',
            ),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HealthFrequencyPicker(
              colors: colors,
              selected: widget.frequency,
              onChanged: widget.onFrequency,
            ),
            const SizedBox(height: 12),
            _InputBox(
              colors: colors,
              controller: widget.preferredDay,
              hint: 'Preferred pickup day',
            ),
            const SizedBox(height: 10),
            _InputBox(
              colors: colors,
              controller: widget.preferredTime,
              hint: 'Preferred pickup time',
            ),
            if (widget.frequency == HealthPlusFrequency.custom) ...[
              const SizedBox(height: 10),
              _InputBox(
                colors: colors,
                controller: widget.customSchedule,
                hint: 'Custom pickup date or repeat pattern',
              ),
            ],
          ],
        );
      case 5:
        return _HealthPlanGrid(
          colors: colors,
          selectedPlan: widget.subscriptionPlan,
          onSelect: widget.onSubscriptionPlan,
          onStartSubscription: widget.onStartSubscription,
          onContinueOneOff: widget.onContinueOneOff,
        );
      case 6:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PrescriptionTypePicker(
              colors: colors,
              selected: widget.prescriptionType,
              onChanged: widget.onPrescriptionType,
            ),
            const SizedBox(height: 10),
            _InputBox(
              colors: colors,
              controller: widget.notes,
              hint: 'Prescription or pickup notes',
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.consent,
              onChanged: widget.onConsent,
              activeColor: colors.text,
              title: Text(
                'I confirm the prescription is valid and ready, or will be ready, for collection.',
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      case 7:
        return _HealthReviewPanel(
          colors: colors,
          frequency: widget.frequency,
          prescriptionType: widget.prescriptionType,
          subscriptionPlan: widget.subscriptionPlan,
          quote: widget.quote,
          fullName: widget.fullName.text,
          pharmacy: widget.pharmacyAddress.text,
          delivery: widget.deliveryAddress.text,
        );
      case 8:
        return _HealthCheckoutPanel(
          colors: colors,
          frequency: widget.frequency,
          quote: widget.quote,
          savePayment: widget.savePayment,
          useRoth: widget.useRoth,
          rothBalance: widget.rothBalance,
          submitting: widget.submitting,
          message: widget.message,
          checkoutUrl: widget.checkoutUrl,
          onSavePayment: widget.onSavePayment,
          onUseRoth: widget.onUseRoth,
          onSubmit: widget.onSubmit,
          onUpdatePayment: widget.onUpdatePayment,
        );
      default:
        return _HealthDashboard(
          colors: colors,
          pickup: nextPickup,
          payments: widget.payments,
          onPauseSchedule: widget.onPauseSchedule,
          onResumeSchedule: widget.onResumeSchedule,
          onCancelSchedule: widget.onCancelSchedule,
          onCancelPickup: widget.onCancelPickup,
          onUpdatePayment: widget.onUpdatePayment,
        );
    }
  }
}

class _HealthGuidedProgress extends StatelessWidget {
  final _CircumColors colors;
  final int currentStep;
  final int totalSteps;

  const _HealthGuidedProgress({
    required this.colors,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < totalSteps - 1; index++)
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: index == totalSteps - 2 ? 0 : 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: index < currentStep
                    ? const Color(0xff2fae8c)
                    : colors.border.withValues(alpha: .55),
              ),
            ),
          ),
      ],
    );
  }
}

class _HealthAddressVerificationHint extends StatelessWidget {
  final _CircumColors colors;
  final bool verified;
  final String label;

  const _HealthAddressVerificationHint({
    required this.colors,
    required this.verified,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          verified ? Icons.verified_rounded : Icons.info_outline_rounded,
          color: verified ? colors.success : colors.warning,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            verified ? 'Address verified.' : label,
            style: TextStyle(
              color: verified ? colors.success : colors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _HealthGuidedChip extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final bool active;
  final bool complete;
  final VoidCallback onTap;

  const _HealthGuidedChip({
    required this.colors,
    required this.label,
    required this.active,
    required this.complete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final health = const Color(0xff2fae8c);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? health.withValues(alpha: .14) : colors.field,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? health : colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? colors.text : colors.mutedText,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: complete ? health : const Color(0xffe0a93a),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthReviewPanel extends StatelessWidget {
  final _CircumColors colors;
  final HealthPlusFrequency frequency;
  final String prescriptionType;
  final String subscriptionPlan;
  final HealthPlusPriceBreakdown quote;
  final String fullName;
  final String pharmacy;
  final String delivery;

  const _HealthReviewPanel({
    required this.colors,
    required this.frequency,
    required this.prescriptionType,
    required this.subscriptionPlan,
    required this.quote,
    required this.fullName,
    required this.pharmacy,
    required this.delivery,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PriceLine(
          colors: colors,
          label: 'For',
          value: fullName.trim().isEmpty ? 'Not added' : fullName.trim(),
        ),
        _PriceLine(
          colors: colors,
          label: 'Pharmacy',
          value: pharmacy.trim().isEmpty ? 'Not added' : pharmacy.trim(),
        ),
        _PriceLine(
          colors: colors,
          label: 'Delivery',
          value: delivery.trim().isEmpty ? 'Not added' : delivery.trim(),
        ),
        _PriceLine(colors: colors, label: 'Frequency', value: frequency.label),
        _PriceLine(
          colors: colors,
          label: 'Prescription',
          value: prescriptionType,
        ),
        _PriceLine(
          colors: colors,
          label: 'Plan',
          value: _HealthParityMap.planLabel(subscriptionPlan),
        ),
        Divider(color: colors.border, height: 24),
        _PriceLine(
          colors: colors,
          label: frequency == HealthPlusFrequency.oneOff
              ? 'One-off total'
              : 'Recurring pickup total',
          value: '£${quote.total.toStringAsFixed(2)}',
          strong: true,
        ),
      ],
    );
  }
}

class _HealthCheckoutPanel extends StatelessWidget {
  final _CircumColors colors;
  final HealthPlusFrequency frequency;
  final HealthPlusPriceBreakdown quote;
  final bool savePayment;
  final bool useRoth;
  final double rothBalance;
  final bool submitting;
  final String? message;
  final String? checkoutUrl;
  final ValueChanged<bool?> onSavePayment;
  final ValueChanged<bool?> onUseRoth;
  final VoidCallback onSubmit;
  final VoidCallback onUpdatePayment;

  const _HealthCheckoutPanel({
    required this.colors,
    required this.frequency,
    required this.quote,
    required this.savePayment,
    required this.useRoth,
    required this.rothBalance,
    required this.submitting,
    required this.message,
    required this.checkoutUrl,
    required this.onSavePayment,
    required this.onUseRoth,
    required this.onSubmit,
    required this.onUpdatePayment,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PriceLine(
          colors: colors,
          label: 'Base pickup fee',
          value: '£${quote.delivery.baseFare.toStringAsFixed(2)}',
        ),
        _PriceLine(
          colors: colors,
          label: 'Distance estimate',
          value: '£${quote.delivery.distanceFare.toStringAsFixed(2)}',
        ),
        _PriceLine(
          colors: colors,
          label: 'Health+ care fee',
          value: '£${quote.serviceFee.toStringAsFixed(2)}',
        ),
        if (quote.priorityFee > 0)
          _PriceLine(
            colors: colors,
            label: 'Priority fee',
            value: '£${quote.priorityFee.toStringAsFixed(2)}',
          ),
        if (quote.familySupportFee > 0)
          _PriceLine(
            colors: colors,
            label: 'Family support',
            value: '£${quote.familySupportFee.toStringAsFixed(2)}',
          ),
        if (quote.recurringDiscount > 0)
          _PriceLine(
            colors: colors,
            label: 'Recurring discount',
            value: '-£${quote.recurringDiscount.toStringAsFixed(2)}',
          ),
        Divider(color: colors.border, height: 24),
        _PriceLine(
          colors: colors,
          label: frequency == HealthPlusFrequency.oneOff
              ? 'One-off total'
              : 'Recurring pickup total',
          value: '£${quote.total.toStringAsFixed(2)}',
          strong: true,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: savePayment,
          onChanged: onSavePayment,
          activeColor: colors.text,
          title: Text(
            'Save this payment method',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
          ),
        ),
        if (rothBalance > 0)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: useRoth,
            onChanged: onUseRoth,
            activeColor: colors.text,
            title: Text(
              'Apply Roth balance',
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              frequency == HealthPlusFrequency.oneOff
                  ? 'Store credit available: £${rothBalance.toStringAsFixed(2)}. Any remaining amount is paid securely by card.'
                  : 'Store credit available: £${rothBalance.toStringAsFixed(2)}. Roth applies to the first subscription payment; future renewals continue securely by card.',
              style: TextStyle(
                color: colors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              message!,
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
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
            label: Text(
              submitting
                  ? 'Setting up Health+...'
                  : 'Pay £${quote.total.toStringAsFixed(2)} securely',
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
      ],
    );
  }
}

class _HealthParityMap extends StatelessWidget {
  final _CircumColors colors;
  final HealthPlusFrequency frequency;
  final String subscriptionPlan;
  final String prescriptionType;
  final HealthPlusPriceBreakdown quote;
  final Map<String, dynamic>? pickup;
  final List<Map<String, dynamic>> payments;
  final bool hasContactDetails;
  final bool hasPharmacy;
  final bool hasDelivery;
  final bool hasNotes;
  final bool consent;
  final bool savePayment;
  final bool useRoth;
  final ValueChanged<String>? onSelectSection;

  const _HealthParityMap({
    required this.colors,
    required this.frequency,
    required this.subscriptionPlan,
    required this.prescriptionType,
    required this.quote,
    required this.pickup,
    required this.payments,
    required this.hasContactDetails,
    required this.hasPharmacy,
    required this.hasDelivery,
    required this.hasNotes,
    required this.consent,
    required this.savePayment,
    required this.useRoth,
  }) : onSelectSection = null;

  @override
  Widget build(BuildContext context) {
    final pickupStatus = pickup == null
        ? 'No active pickup'
        : _displayStatusLabel('${pickup!['status'] ?? 'scheduled'}');
    final paymentStatus = payments.isEmpty
        ? 'Ready at checkout'
        : _displayStatusLabel('${payments.first['status'] ?? 'recorded'}');
    final sections = [
      _HealthParitySection(
        icon: Icons.monitor_heart_outlined,
        title: 'Status',
        value: pickupStatus,
        complete: pickup != null,
      ),
      _HealthParitySection(
        icon: Icons.person_outline,
        title: 'Details',
        value: hasContactDetails ? 'Contact details ready' : 'Add contact',
        complete: hasContactDetails,
      ),
      _HealthParitySection(
        icon: Icons.local_pharmacy_outlined,
        title: 'Pharmacy',
        value: hasPharmacy ? 'Pickup address ready' : 'Add pharmacy',
        complete: hasPharmacy,
      ),
      _HealthParitySection(
        icon: Icons.home_outlined,
        title: 'Delivery',
        value: hasDelivery ? 'Delivery address ready' : 'Add delivery address',
        complete: hasDelivery,
      ),
      _HealthParitySection(
        icon: Icons.event_repeat_outlined,
        title: 'Frequency',
        value: frequency.label,
        complete: true,
      ),
      _HealthParitySection(
        icon: Icons.workspace_premium_outlined,
        title: 'Plan',
        value: _planLabel(subscriptionPlan),
        complete: subscriptionPlan.trim().isNotEmpty,
      ),
      _HealthParitySection(
        icon: Icons.notes_outlined,
        title: 'Notes',
        value: hasNotes ? prescriptionType : 'Optional notes',
        complete: hasNotes,
      ),
      _HealthParitySection(
        icon: Icons.fact_check_outlined,
        title: 'Review',
        value: consent ? 'Consent confirmed' : 'Consent needed',
        complete: consent,
      ),
      _HealthParitySection(
        icon: Icons.lock_outline,
        title: 'Checkout',
        value: paymentStatus,
        complete: payments.isNotEmpty,
      ),
      _HealthParitySection(
        icon: Icons.verified_outlined,
        title: 'Confirmed',
        value: pickup == null ? 'After booking' : 'Pickup saved',
        complete: pickup != null,
      ),
    ];

    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'Health+ sections'),
          const SizedBox(height: 8),
          Text(
            'The web flow exposes the same Health+ areas as the app: status, details, pharmacy, delivery, frequency, plan, notes, review, checkout and confirmation.',
            style: TextStyle(
              color: colors.mutedText,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HealthChip(label: frequency.label),
              _HealthChip(label: planLabel(subscriptionPlan)),
              if (useRoth) const _HealthChip(label: 'Roth selected'),
              if (savePayment) const _HealthChip(label: 'Saved payment ready'),
              const _HealthChip(label: 'Vanguard Included'),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 720 ? 2 : 5;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: columns,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: columns == 2 ? 1.18 : 1.08,
                children: sections
                    .map(
                      (section) => _HealthParityTile(
                        colors: colors,
                        section: section,
                        onTap: onSelectSection == null
                            ? null
                            : () => onSelectSection!(section.title),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          _PriceLine(
            colors: colors,
            label: frequency == HealthPlusFrequency.oneOff
                ? 'One-off total'
                : 'Recurring pickup total',
            value: '£${quote.total.toStringAsFixed(2)}',
            strong: true,
          ),
        ],
      ),
    );
  }

  static String _planLabel(String value) {
    switch (value) {
      case 'priority':
        return 'Priority';
      case 'family':
        return 'Family';
      case 'basic':
        return 'Basic';
      default:
        return value.trim().isEmpty ? 'Basic' : value;
    }
  }

  static String planLabel(String value) => _planLabel(value);
}

class _HealthParitySection {
  final IconData icon;
  final String title;
  final String value;
  final bool complete;

  const _HealthParitySection({
    required this.icon,
    required this.title,
    required this.value,
    required this.complete,
  });
}

class _HealthParityTile extends StatelessWidget {
  final _CircumColors colors;
  final _HealthParitySection section;
  final VoidCallback? onTap;

  const _HealthParityTile({
    required this.colors,
    required this.section,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: colors.field,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: section.complete
                  ? colors.success.withValues(alpha: .42)
                  : colors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    section.icon,
                    color: section.complete ? colors.success : colors.text,
                    size: 19,
                  ),
                  const Spacer(),
                  Icon(
                    section.complete
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: section.complete ? colors.success : colors.mutedText,
                    size: 17,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                section.title,
                style:
                    TextStyle(color: colors.text, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                section.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
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
        price: '£11/month',
        benefits: [
          '2 Health+ prescription pickups every calendar month',
          'Medicine delivery reminders',
          'Secure sealed-package handover',
        ],
      ),
      _HealthPlanCopy(
        id: 'priority',
        title: 'Health+ Priority',
        price: '£25/month',
        benefits: [
          '4 Health+ prescription pickups every calendar month',
          'Priority Circum Rider matching',
          'Faster pickup target',
          'Medicine reminders',
        ],
      ),
      _HealthPlanCopy(
        id: 'family',
        title: 'Health+ Family',
        price: '£40/month',
        benefits: [
          'Unlimited Health+ prescription pickups',
          'Family member support',
          'Shared pickup notes',
          'Repeat medicine reminders',
          'Priority support',
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
            ...plan.benefits.map(
              (benefit) => Padding(
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
              ),
            ),
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
      (Icons.verified_user, 'Verified Circum Rider'),
      (Icons.inventory_2_outlined, 'Sealed package only'),
      (Icons.handshake_outlined, 'Secure handover'),
      (Icons.medical_information_outlined, 'No medical advice provided'),
      (
        Icons.assignment_turned_in_outlined,
        'Prescription remains customer/pharmacy responsibility',
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
            child: Text(
              label,
              style: TextStyle(
                color: colors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _IrisWeightEstimate {
  final double weightKg;
  final int quantity;
  final double? singleItemWeightKg;
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
  final bool valueSensitive;
  final bool vanguardRecommended;
  final bool stackable;
  final String? handlingNotes;

  const _IrisWeightEstimate({
    required this.weightKg,
    this.quantity = 1,
    this.singleItemWeightKg,
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
    this.valueSensitive = false,
    this.vanguardRecommended = false,
    this.stackable = true,
    this.handlingNotes,
  });

  _IrisWeightEstimate copyWith({
    double? weightKg,
    int? quantity,
    double? singleItemWeightKg,
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
    bool? valueSensitive,
    bool? vanguardRecommended,
    bool? stackable,
    String? handlingNotes,
  }) {
    return _IrisWeightEstimate(
      weightKg: weightKg ?? this.weightKg,
      quantity: quantity ?? this.quantity,
      singleItemWeightKg: singleItemWeightKg ?? this.singleItemWeightKg,
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
      valueSensitive: valueSensitive ?? this.valueSensitive,
      vanguardRecommended: vanguardRecommended ?? this.vanguardRecommended,
      stackable: stackable ?? this.stackable,
      handlingNotes: handlingNotes ?? this.handlingNotes,
    );
  }
}

class _IrisImageInsight {
  final String? analysisId;
  final String inferredItemName;
  final String inferredCategory;
  final double estimatedWeightKg;
  final String weightClass;
  final double confidenceScore;
  final String fragilityRisk;
  final String valueRisk;
  final String handlingNotes;
  final String riderGuidance;
  final bool needsHumanReview;
  final String fileName;
  final int fileSizeBytes;

  const _IrisImageInsight({
    this.analysisId,
    required this.inferredItemName,
    required this.inferredCategory,
    required this.estimatedWeightKg,
    required this.weightClass,
    required this.confidenceScore,
    required this.fragilityRisk,
    required this.valueRisk,
    required this.handlingNotes,
    required this.riderGuidance,
    required this.needsHumanReview,
    required this.fileName,
    required this.fileSizeBytes,
  });

  factory _IrisImageInsight.fallback(String fileName) {
    return _IrisImageInsight(
      analysisId: null,
      inferredItemName: 'Parcel photo',
      inferredCategory: 'Parcel',
      estimatedWeightKg: 2,
      weightClass: DeliveryPricing.weightBandFor(2).category,
      confidenceScore: 0.25,
      fragilityRisk: 'medium',
      valueRisk: 'low',
      handlingNotes:
          'IRIS could not fully analyse the photo, so item details were used.',
      riderGuidance: 'Use the photo to verify condition at pickup.',
      needsHumanReview: true,
      fileName: fileName,
      fileSizeBytes: 0,
    );
  }

  factory _IrisImageInsight.fromBackend(
    Map<String, dynamic> data, {
    required String fallbackFileName,
  }) {
    final weightKg = (data['estimatedWeightKg'] as num?)?.toDouble() ?? 2.0;
    final score = (data['confidenceScore'] as num?)?.toDouble() ?? 0.25;
    return _IrisImageInsight(
      analysisId: '${data['analysisId'] ?? ''}'.trim().isEmpty
          ? null
          : '${data['analysisId']}',
      inferredItemName:
          '${data['inferredItemName'] ?? data['detectedItem'] ?? 'Parcel'}',
      inferredCategory: '${data['inferredCategory'] ?? 'Parcel'}',
      estimatedWeightKg: weightKg,
      weightClass: '${data['weightClass'] ?? ''}'.trim().isEmpty
          ? DeliveryPricing.weightBandFor(weightKg).category
          : '${data['weightClass']}',
      confidenceScore: score.clamp(0.0, 1.0),
      fragilityRisk: '${data['fragilityRisk'] ?? 'medium'}',
      valueRisk: '${data['valueRisk'] ?? 'low'}',
      handlingNotes:
          '${data['handlingNotes'] ?? 'Backend verified the parcel photo before using it as an IRIS visual signal.'}',
      riderGuidance:
          '${data['riderGuidance'] ?? 'Use the parcel photo to verify condition at pickup.'}',
      needsHumanReview: data['needsHumanReview'] == true,
      fileName: '${data['fileName'] ?? fallbackFileName}',
      fileSizeBytes: (data['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'analysisId': analysisId,
        'inferredItemName': inferredItemName,
        'inferredCategory': inferredCategory,
        'estimatedWeightKg': estimatedWeightKg,
        'weightClass': weightClass,
        'confidenceScore': confidenceScore,
        'fragilityRisk': fragilityRisk,
        'valueRisk': valueRisk,
        'handlingNotes': handlingNotes,
        'riderGuidance': riderGuidance,
        'needsHumanReview': needsHumanReview,
        'fileName': fileName,
        'fileSizeBytes': fileSizeBytes,
        'source': analysisId == null
            ? 'parcel_photo_and_item_details'
            : 'backend_parcel_photo_analysis',
      };
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

  bool get isVerified => hasCoordinates && confidence >= 0.8;

  String get confidenceBand {
    if (confidence >= 0.98) return 'exact_match';
    if (confidence >= 0.9) return 'high';
    if (confidence >= 0.8) return 'medium';
    return 'low';
  }

  String get compactDisplay {
    final primary = [
      buildingNumber,
      street,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
    final locality = [
      city,
      postcode,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
    if (primary.isNotEmpty && locality.isNotEmpty) return '$primary\n$locality';
    if (street?.trim().isNotEmpty == true &&
        postcode?.trim().isNotEmpty == true) {
      return '${street!.trim()}\n${postcode!.trim()}';
    }
    return displayAddress;
  }

  Map<String, dynamic> toJson() => {
        'rawInput': rawInput,
        'displayAddress': displayAddress,
        'postcode': postcode,
        'lat': lat,
        'lng': lng,
        'geocodeConfidence': confidence,
        'confidenceBand': confidenceBand,
        'validationStatus': isVerified ? 'verified' : 'requires_confirmation',
        'addressSource': provider,
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

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}'.trim());
}

Map<String, String> _stringComponents(Object? value) {
  if (value is! Map) return const {};
  return value.map(
    (key, item) => MapEntry('$key', '${item ?? ''}'.trim()),
  )..removeWhere((key, item) => item.isEmpty);
}

String _cleanGoogleAddress(String address) {
  return address
      .replaceAll(', UK', ', United Kingdom')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _stableLocationId(String address, double lat, double lng) {
  final normalized = address.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '-',
      );
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
  final bool locationsConfirmed;
  final bool priceReady;
  final bool weightReady;
  final SpecialHandlingResult specialHandling;
  final bool vanguardRequired;
  final bool vanguardEnabled;
  final ValueChanged<bool> onVanguardChanged;
  final DeliveryAccess pickupAccess;
  final DeliveryAccess dropoffAccess;
  final ValueChanged<DeliveryAccess> onPickupAccess;
  final ValueChanged<DeliveryAccess> onDropoffAccess;
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
    required this.locationsConfirmed,
    required this.priceReady,
    required this.weightReady,
    required this.specialHandling,
    required this.vanguardRequired,
    required this.vanguardEnabled,
    required this.onVanguardChanged,
    required this.pickupAccess,
    required this.dropoffAccess,
    required this.onPickupAccess,
    required this.onDropoffAccess,
    required this.onVehicle,
    required this.onSpeed,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final recommendedVehicleName = vehicleSuitability.recommendedVehicle;
    final vehicleValid = DeliveryPricing.vehicleCanCarryDelivery(
      selectedVehicle.name,
      vehicleSuitability,
    );
    final canContinue = vehicleValid &&
        selectedSpeed.trim().isNotEmpty &&
        locationsConfirmed &&
        weightReady &&
        priceReady;
    final disabledReason = !vehicleValid
        ? 'Choose a safe vehicle for this parcel.'
        : selectedSpeed.trim().isEmpty
            ? 'Choose a delivery speed.'
            : !locationsConfirmed
                ? 'Confirm pickup and drop-off addresses.'
                : !weightReady
                    ? 'Confirm the parcel weight.'
                    : !priceReady
                        ? 'Pricing is not ready yet.'
                        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTopBar(
          colors: colors,
          title: 'Best fit for this delivery',
          onBack: onBack,
        ),
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
                      vehicleSuitability.explanation,
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
        Text(
          'Choose your vehicle',
          style: TextStyle(
            color: colors.text,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'IRIS recommends the smallest safe vehicle. You can choose a larger vehicle if preferred.',
          style: TextStyle(
            color: colors.mutedText,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        _RouteSummary(colors: colors, pickup: pickup, dropoff: dropoff),
        const SizedBox(height: 14),
        ..._vehicles.map((vehicle) {
          final disabledReason = DeliveryPricing.vehicleDisabledReason(
            vehicle.name,
            vehicleSuitability,
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _VehicleTile(
              colors: colors,
              vehicle: vehicle,
              selected: vehicle.name == selectedVehicle.name,
              disabledReason: disabledReason,
              onTap: () => onVehicle(vehicle),
            ),
          );
        }),
        const SizedBox(height: 8),
        _SpeedToggle(
          colors: colors,
          selected: selectedSpeed,
          onChanged: onSpeed,
        ),
        const SizedBox(height: 14),
        _VanguardBookingNotice(
          colors: colors,
          selected: vanguardEnabled,
          requiredByPolicy: vanguardRequired,
          onChanged: onVanguardChanged,
        ),
        if (specialHandling.requiresAccessQuestions) ...[
          const SizedBox(height: 14),
          _GlassPanel(
            colors: colors,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Access details',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  specialHandling.explanation,
                  style: TextStyle(
                    color: colors.mutedText,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _AccessDropdown(
                  colors: colors,
                  label: 'Pickup access',
                  value: pickupAccess,
                  onChanged: onPickupAccess,
                ),
                const SizedBox(height: 10),
                _AccessDropdown(
                  colors: colors,
                  label: 'Drop-off access',
                  value: dropoffAccess,
                  onChanged: onDropoffAccess,
                ),
              ],
            ),
          ),
        ],
        if (disabledReason != null) ...[
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
                    disabledReason,
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

class _AccessDropdown extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final DeliveryAccess value;
  final ValueChanged<DeliveryAccess> onChanged;

  const _AccessDropdown({
    required this.colors,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<DeliveryAccess>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      dropdownColor: colors.panel,
      items: const [
        DropdownMenuItem(
          value: DeliveryAccess.groundFloor,
          child: Text('Ground floor'),
        ),
        DropdownMenuItem(
          value: DeliveryAccess.liftAvailable,
          child: Text('Lift available'),
        ),
        DropdownMenuItem(value: DeliveryAccess.stairs, child: Text('Stairs')),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

class _VanguardBookingNotice extends StatelessWidget {
  final _CircumColors colors;
  final bool selected;
  final bool requiredByPolicy;
  final ValueChanged<bool> onChanged;

  const _VanguardBookingNotice({
    required this.colors,
    required this.selected,
    required this.requiredByPolicy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const vanguardBlue = Color(0xff168bff);
    final borderColor = selected
        ? vanguardBlue.withValues(alpha: 0.94)
        : const Color(0xff38bdf8).withValues(alpha: 0.28);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(
          0xff0b1530,
        ).withValues(alpha: selected ? 0.92 : (colors.dark ? 0.82 : 0.08)),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: selected ? 2 : 1.2),
        boxShadow: [
          BoxShadow(
            color: vanguardBlue.withValues(alpha: selected ? 0.28 : 0.14),
            blurRadius: selected ? 34 : 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: InkWell(
        onTap: requiredByPolicy ? null : () => onChanged(!selected),
        borderRadius: BorderRadius.circular(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? vanguardBlue.withValues(alpha: 0.22)
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? vanguardBlue
                      : const Color(0xff38bdf8).withValues(alpha: 0.24),
                ),
              ),
              child: const Icon(Icons.security, color: Color(0xff93c5fd)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Vanguard',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      _VanguardBlueChip(
                        label: requiredByPolicy
                            ? 'Required'
                            : 'Optional add-on - £${_webVanguardAddOnPriceGbp.toStringAsFixed(2)}',
                      ),
                      if (selected) const _VanguardBlueChip(label: 'Selected'),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    selected
                        ? 'Vanguard will be added to this delivery.'
                        : 'Trust matters more than speed.',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add enhanced custody tracking, trusted Circum Rider prioritisation, priority support, and better handling for important items.',
                    style: TextStyle(
                      color: colors.mutedText,
                      height: 1.42,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: selected,
              onChanged: requiredByPolicy ? null : onChanged,
              activeThumbColor: vanguardBlue,
              activeTrackColor: vanguardBlue.withValues(alpha: 0.34),
            ),
          ],
        ),
      ),
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
  final SpecialHandlingResult specialHandling;
  final bool vanguardEnabled;
  final bool useRoth;
  final double rothBalance;
  final String scheduledPickupDate;
  final String scheduledPickupWindow;
  final String scheduledDropoffDate;
  final String scheduledDropoffWindow;
  final VoidCallback onBack;
  final VoidCallback onPay;
  final ValueChanged<bool?> onUseRoth;

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
    required this.specialHandling,
    required this.vanguardEnabled,
    required this.useRoth,
    required this.rothBalance,
    required this.scheduledPickupDate,
    required this.scheduledPickupWindow,
    required this.scheduledDropoffDate,
    required this.scheduledDropoffWindow,
    required this.onBack,
    required this.onPay,
    required this.onUseRoth,
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
    final rothApplied = useRoth ? math.min(rothBalance, total) : 0.0;
    final stripeAmount = math.max(total - rothApplied, 0.0);
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
              if (breakdown.assistedFee > 0)
                _PriceLine(
                  colors: colors,
                  label: 'Assisted Delivery',
                  value: '£${breakdown.assistedFee.toStringAsFixed(2)}',
                ),
              if (breakdown.heavyDutyFee > 0)
                _PriceLine(
                  colors: colors,
                  label: 'Heavy Duty',
                  value: '£${breakdown.heavyDutyFee.toStringAsFixed(2)}',
                ),
              if (breakdown.twoPersonFee > 0)
                _PriceLine(
                  colors: colors,
                  label: 'Two Person Required',
                  value: '£${breakdown.twoPersonFee.toStringAsFixed(2)}',
                ),
              if (breakdown.heavyHandlingSurcharge > 0)
                _PriceLine(
                  colors: colors,
                  label: 'Heavy Handling Surcharge',
                  value:
                      '£${breakdown.heavyHandlingSurcharge.toStringAsFixed(2)}',
                ),
              if (specialHandling.labourPremium > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    specialHandling.explanation,
                    style: TextStyle(
                      color: colors.mutedText,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                value: '£${breakdown.baseFare.toStringAsFixed(2)}',
              ),
              _PriceLine(
                colors: colors,
                label: 'Distance fare',
                value: '£${breakdown.distanceFare.toStringAsFixed(2)}',
              ),
              _PriceLine(
                colors: colors,
                label:
                    '${breakdown.weightCategory} (${weightKg.toStringAsFixed(weightKg.truncateToDouble() == weightKg ? 0 : 1)} kg)',
                value: '£${breakdown.weightSurcharge.toStringAsFixed(2)}',
              ),
              _PriceLine(
                colors: colors,
                label: '${vehicle.name} vehicle',
                value: '£${breakdown.vehicleSurcharge.toStringAsFixed(2)}',
              ),
              if (breakdown.heavyHandlingSurcharge > 0)
                _PriceLine(
                  colors: colors,
                  label: 'Heavy Handling Surcharge',
                  value:
                      '£${breakdown.heavyHandlingSurcharge.toStringAsFixed(2)}',
                ),
              if (breakdown.specialConditions > 0)
                _PriceLine(
                  colors: colors,
                  label: speed == 'Express'
                      ? 'Express service'
                      : 'Special conditions',
                  value: '£${breakdown.specialConditions.toStringAsFixed(2)}',
                ),
              if (vanguardEnabled)
                _PriceLine(
                  colors: colors,
                  label: 'Vanguard',
                  value: '£${_webVanguardAddOnPriceGbp.toStringAsFixed(2)}',
                ),
              Divider(color: colors.border, height: 26),
              _PriceLine(
                colors: colors,
                label: 'Total',
                value: '£${total.toStringAsFixed(2)}',
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
                    Icon(Icons.lock_outline, color: colors.text),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Secure Stripe Checkout',
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      'Card or Apple Pay',
                      style: TextStyle(
                        color: colors.mutedText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (rothBalance > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.field.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        color: colors.mutedText,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Apply Roth balance',
                              style: TextStyle(
                                color: colors.text,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              useRoth
                                  ? 'Store credit covers £${rothApplied.toStringAsFixed(2)}. Stripe collects £${stripeAmount.toStringAsFixed(2)} if anything remains.'
                                  : 'Store credit available: £${rothBalance.toStringAsFixed(2)}.',
                              style: TextStyle(
                                color: colors.mutedText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: useRoth,
                        onChanged: processingPayment ? null : onUseRoth,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                weightConfirmed && locationsConfirmed && !processingPayment
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
                      : weightConfirmed
                          ? stripeAmount > 0
                              ? 'Pay £${stripeAmount.toStringAsFixed(2)} & Broadcast'
                              : 'Confirm & Broadcast'
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
  final DateTime? receivedAt;
  final _ValidatedAddress? pickupAddress;
  final _ValidatedAddress? dropoffAddress;
  final Map<String, dynamic>? liveLocation;
  final Map<String, dynamic>? vanguardData;
  final String? irisItemName;
  final int irisQuantity;
  final String? irisConfidence;
  final double irisWeightKg;
  final String irisWeightBand;
  final bool irisRepositoryMatched;
  final bool irisCorrected;
  final String recommendedVehicle;
  final DeliveryPricingBreakdown breakdown;
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
  final VoidCallback onViewHistory;

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
    required this.receivedAt,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.liveLocation,
    required this.vanguardData,
    required this.irisItemName,
    required this.irisQuantity,
    required this.irisConfidence,
    required this.irisWeightKg,
    required this.irisWeightBand,
    required this.irisRepositoryMatched,
    required this.irisCorrected,
    required this.recommendedVehicle,
    required this.breakdown,
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
    required this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    final analysedItemName = irisItemName?.trim();
    final status = _trackingStatuses[
        statusIndex.clamp(0, _trackingStatuses.length - 1).toInt()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WebDeliveryStatusHeader(
          colors: colors,
          trackingReference: orderId,
          onNewOrder: onNewOrder,
        ),
        const SizedBox(height: 14),
        _WebDeliveryStatusCard(
          colors: colors,
          title: status.title,
          body: status.body,
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
        _WebDeliveryRouteCard(
          colors: colors,
          pickup: pickup.isEmpty ? 'Not yet entered' : pickup,
          dropoff: dropoff.isEmpty ? 'Not yet entered' : dropoff,
        ),
        const SizedBox(height: 14),
        _WebDeliveryPriceCard(
          colors: colors,
          breakdown: breakdown,
          weightKg: irisWeightKg,
          vehicleName: vehicle.name,
          tipAmount: selectedTipAmount,
        ),
        if (statusIndex >= 3 && analysedItemName?.isNotEmpty == true) ...[
          const SizedBox(height: 14),
          _IrisDeliveryAnalysisCard(
            colors: colors,
            itemName: analysedItemName!,
            quantity: irisQuantity,
            pricingWeightKg: irisWeightKg,
            weightBand: irisWeightBand,
            repositoryMatched: irisRepositoryMatched,
            confidence: irisConfidence,
            recommendedVehicle: recommendedVehicle,
            selectedVehicle: vehicle.name,
            corrected: irisCorrected,
          ),
        ],
        if (statusIndex >= 3) ...[
          const SizedBox(height: 14),
          _CompletedDeliveryActions(
            colors: colors,
            onBookAgain: onNewOrder,
            onViewHistory: onViewHistory,
          ),
        ],
        const SizedBox(height: 14),
        _FirebaseStatusBanner(
          colors: colors,
          online: firebaseOnline,
          error: firebaseError,
          checkoutState: checkoutState,
        ),
        const SizedBox(height: 14),
        _WebDeliveryInfoBanner(
          text: checkoutState == _CheckoutState.riderAssigned
              ? 'Tracking is live. You can message your Circum Rider or contact Circum support from here.'
              : 'Estimated rider availability: usually within 8-12 minutes in this area.',
        ),
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

class _WebDeliveryStatusHeader extends StatelessWidget {
  final _CircumColors colors;
  final String trackingReference;
  final VoidCallback onNewOrder;

  const _WebDeliveryStatusHeader({
    required this.colors,
    required this.trackingReference,
    required this.onNewOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            'Delivery status',
            style: TextStyle(
              color: colors.text,
              fontFamily: 'DM Serif Display',
              fontSize: 30,
              height: 1.15,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        Text(
          _displayDeliveryReference(trackingReference),
          style: TextStyle(
            color: colors.mutedText,
            fontFamily: 'JetBrains Mono',
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'New delivery',
          child: IconButton(
            onPressed: onNewOrder,
            icon: Icon(Icons.add_circle_outline, color: colors.mutedText),
          ),
        ),
      ],
    );
  }
}

class _WebDeliveryStatusCard extends StatelessWidget {
  final _CircumColors colors;
  final String title;
  final String body;

  const _WebDeliveryStatusCard({
    required this.colors,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return _WebDeliveryPanel(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xff3b82f6).withValues(alpha: 0.14),
              border: Border.all(
                color: const Color(0xff3b82f6).withValues(alpha: 0.40),
              ),
            ),
            child: Center(
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff60a5fa),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xff60a5fa).withValues(alpha: 0.55),
                      blurRadius: 12,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xfff5f7fb),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xff9ca3af),
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
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

class _WebDeliveryRouteCard extends StatelessWidget {
  final _CircumColors colors;
  final String pickup;
  final String dropoff;

  const _WebDeliveryRouteCard({
    required this.colors,
    required this.pickup,
    required this.dropoff,
  });

  @override
  Widget build(BuildContext context) {
    return _WebDeliveryPanel(
      child: Column(
        children: [
          _WebDeliveryRouteRow(
            label: 'Pickup',
            value: pickup,
            accent: const Color(0xff60a5fa),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Divider(
              height: 1,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          _WebDeliveryRouteRow(
            label: 'Drop-off',
            value: dropoff,
            accent: const Color(0xff22c55e),
          ),
        ],
      ),
    );
  }
}

class _WebDeliveryRouteRow extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _WebDeliveryRouteRow({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final pending = value == 'Not yet entered';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 11,
          height: 11,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent,
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.18), spreadRadius: 3),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xff9ca3af),
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  color: pending
                      ? const Color(0xff9ca3af)
                      : const Color(0xfff5f7fb),
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: pending ? FontWeight.w400 : FontWeight.w600,
                  fontStyle: pending ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WebDeliveryPriceCard extends StatelessWidget {
  final _CircumColors colors;
  final DeliveryPricingBreakdown breakdown;
  final double weightKg;
  final String vehicleName;
  final double tipAmount;

  const _WebDeliveryPriceCard({
    required this.colors,
    required this.breakdown,
    required this.weightKg,
    required this.vehicleName,
    required this.tipAmount,
  });

  @override
  Widget build(BuildContext context) {
    return _WebDeliveryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Price breakdown',
            style: TextStyle(
              color: Color(0xfff5f7fb),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _WebDeliveryPriceLine(
            label: 'Base fare',
            value: '£${breakdown.baseFare.toStringAsFixed(2)}',
          ),
          _WebDeliveryPriceLine(
            label: 'Distance fare',
            value: '£${breakdown.distanceFare.toStringAsFixed(2)}',
          ),
          _WebDeliveryPriceLine(
            label:
                '${breakdown.weightCategory} (${_webDeliveryFormatWeight(weightKg)} kg)',
            value: '£${breakdown.weightSurcharge.toStringAsFixed(2)}',
          ),
          _WebDeliveryPriceLine(
            label: '$vehicleName vehicle',
            value: '£${breakdown.vehicleSurcharge.toStringAsFixed(2)}',
          ),
          if (breakdown.heavyHandlingSurcharge > 0)
            _WebDeliveryPriceLine(
              label: 'Heavy handling',
              value: '£${breakdown.heavyHandlingSurcharge.toStringAsFixed(2)}',
            ),
          if (breakdown.specialConditions > 0)
            _WebDeliveryPriceLine(
              label: 'Special conditions',
              value: '£${breakdown.specialConditions.toStringAsFixed(2)}',
            ),
          if (tipAmount > 0)
            _WebDeliveryPriceLine(
              label: 'Circum Rider tip',
              value: '£${tipAmount.toStringAsFixed(2)}',
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 7),
            child: Divider(color: Colors.white.withValues(alpha: 0.10)),
          ),
          _WebDeliveryPriceLine(
            label: 'Total',
            value: '£${(breakdown.total + tipAmount).toStringAsFixed(2)}',
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _WebDeliveryPriceLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _WebDeliveryPriceLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: strong ? 3 : 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color:
                    strong ? const Color(0xfff5f7fb) : const Color(0xff9ca3af),
                fontSize: strong ? 16 : 13.5,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: strong ? const Color(0xfff5f7fb) : const Color(0xff9ca3af),
              fontFamily: 'JetBrains Mono',
              fontSize: strong ? 16 : 13.5,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _WebDeliveryInfoBanner extends StatelessWidget {
  final String text;

  const _WebDeliveryInfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xff3b82f6).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xff3b82f6).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xff60a5fa),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xff60a5fa),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebDeliveryPanel extends StatelessWidget {
  final Widget child;

  const _WebDeliveryPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xfff5f7fb).withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: child,
    );
  }
}

String _webDeliveryFormatWeight(double weightKg) {
  return weightKg.truncateToDouble() == weightKg
      ? weightKg.toStringAsFixed(0)
      : weightKg.toStringAsFixed(1);
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
                    'Waiting for live Circum Rider location',
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

    final destination = statusIndex < 5 ? pickup! : dropoff!;
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
                  'Live Circum Rider location',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'Updated ${_relativeSeconds(updatedAt)} ago',
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
                errorBuilder: (context, error, stackTrace) =>
                    _Timeline(colors: colors, activeIndex: statusIndex),
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
      _CheckoutState.riderAssigned =>
        'Circum Rider assigned. Tracking is live.',
      _CheckoutState.failed => error ?? 'This delivery could not be started.',
      _ => error ?? 'Estimated rider availability',
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
              healthy
                  ? 'This delivery is saved and live.'
                  : checkoutState.index < _CheckoutState.bookingCreated.index &&
                          error == null
                      ? '$message\nRider matching starts after payment and booking confirmation.'
                      : message,
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

  const _VanguardCustomerPanel({required this.colors, required this.data});

  @override
  Widget build(BuildContext context) {
    final collectionVerified = data['collectionPinVerified'] == true;
    final deliveryVerified = data['deliveryPinVerified'] == true;
    final handoffCompleted = collectionVerified && deliveryVerified;
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
                  'Vanguard Protection',
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
            handoffCompleted
                ? '✓ PIN verified\n✓ Recipient confirmed\n✓ Secure handoff completed'
                : 'Vanguard Protection Activated\n\nThis item qualifies for enhanced delivery protection.\n\n${collectionVerified ? '✓ Collection PIN verified' : '• PIN pending'}\n${deliveryVerified ? '✓ Recipient confirmed' : '• Awaiting recipient verification'}\n${deliveryVerified ? '✓ Secure handoff completed' : '• Handoff not yet completed'}\n\nGive this collection PIN to the rider only when ${collectionName.isEmpty ? 'the sender or collection contact' : collectionName} hands over the sealed parcel.',
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
            pin: collectionVerified ? 'Verified' : 'Protected',
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
            pin: deliveryVerified ? 'Verified' : 'Protected',
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
    final desktop = MediaQuery.sizeOf(context).width >= 720;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        child: Align(
          alignment: desktop ? Alignment.centerRight : Alignment.bottomCenter,
          child: Container(
            width: desktop ? 420 : double.infinity,
            height: desktop
                ? MediaQuery.sizeOf(context).height
                : MediaQuery.sizeOf(context).height * 0.92,
            decoration: BoxDecoration(
              color: colors.appBackground,
              borderRadius: desktop
                  ? const BorderRadius.horizontal(left: Radius.circular(28))
                  : const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: colors.border),
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
                    ),
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
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.46,
        size.width * 0.48,
        size.height * 0.58,
      )
      ..quadraticBezierTo(
        size.width * 0.68,
        size.height * 0.70,
        size.width * 0.90,
        size.height * 0.18,
      );
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
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.04)
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
        color: colors.panel.withValues(alpha: 0.92),
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
  final FocusNode _focusNode = FocusNode();
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
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateSuggestions);
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus || widget.controller.text.trim().isNotEmpty) {
      return;
    }
    setState(() => _suggestions = _initialPopularSuggestions());
  }

  List<_AddressSuggestion> _initialPopularSuggestions() {
    final places = widget.pharmacyMode
        ? _circumPopularPlaces.where(
            (place) => const {
              'hospital',
              'pharmacy',
              'nhs facility',
            }.contains(place.category),
          )
        : _circumPopularPlaces.where(
            (place) => const {
              'station',
              'airport',
              'landmark',
            }.contains(place.category),
          );
    return places
        .take(4)
        .map(
          (place) => _AddressSuggestion(
            displayAddress: place.displayName,
            lat: place.lat,
            lng: place.lng,
            confidence: 0.98,
            provider: 'circum_popular_place',
            sourceInput: place.displayName,
            searchText: place.formattedAddress,
            category: place.category,
          ),
        )
        .toList(growable: false);
  }

  void _updateSuggestions() {
    if (_selectingSuggestion) return;
    final value = widget.controller.text.trim();
    final requestId = ++_suggestionRequest;
    if (value.length < 3) {
      if (mounted) {
        setState(
          () => _suggestions = value.isEmpty && _focusNode.hasFocus
              ? _initialPopularSuggestions()
              : const [],
        );
      }
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
    String value,
  ) async {
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
    try {
      final response = await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('searchFreeUkAddresses').call({
        'query': input,
        'sessionToken': _placesSessionToken,
      });
      final body = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      if ('${body['status']}' != 'OK') return const [];
      final results = body['results'] as List<dynamic>? ?? const [];
      return results
          .whereType<Map>()
          .map(
            (result) => _AddressSuggestion(
              displayAddress: '${result['displayAddress'] ?? ''}',
              confidence: _asDouble(result['confidence']) ?? 0.99,
              provider: '${result['provider'] ?? 'google_places'}',
              sourceInput: input,
              placeId: '${result['placeId'] ?? result['locationId'] ?? ''}',
              components: _stringComponents(result['components']),
            ),
          )
          .where((suggestion) =>
              suggestion.displayAddress.trim().isNotEmpty &&
              suggestion.placeId?.trim().isNotEmpty == true)
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
    if (placeId == null || placeId.trim().isEmpty) {
      return suggestion;
    }
    try {
      final response = await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('resolveUkAddressPlace').call({
        'placeId': placeId,
        'sessionToken': _placesSessionToken,
      });
      final result = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final lat = _asDouble(result['lat']);
      final lng = _asDouble(result['lng']);
      if (lat == null || lng == null) return null;
      return _AddressSuggestion(
        displayAddress: _cleanGoogleAddress(
          '${result['displayAddress'] ?? suggestion.displayAddress}',
        ),
        lat: lat,
        lng: lng,
        confidence: _asDouble(result['confidence']) ?? 0.99,
        provider: '${result['provider'] ?? 'google_places'}',
        sourceInput: suggestion.sourceInput,
        placeId: placeId,
        components: _stringComponents(result['components']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<_AddressSuggestion?> _googleFindPlaceFromText(
    _AddressSuggestion suggestion,
  ) async {
    final query = suggestion.searchText ?? suggestion.displayAddress;
    try {
      final response = await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('searchFreeUkAddresses').call({
        'query': query,
        'sessionToken': _placesSessionToken,
      });
      final body = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final results = body['results'] as List<dynamic>? ?? const [];
      final typedResults = results.whereType<Map>();
      if (typedResults.isEmpty) return null;
      final first = typedResults.first;
      return _googlePlaceDetails(
        _AddressSuggestion(
          displayAddress:
              '${first['displayAddress'] ?? suggestion.displayAddress}',
          confidence: _asDouble(first['confidence']) ?? 0.99,
          provider: '${first['provider'] ?? 'google_places'}',
          sourceInput: suggestion.sourceInput,
          placeId: '${first['placeId'] ?? first['locationId'] ?? ''}',
          components: _stringComponents(first['components']),
        ),
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
          focusNode: _focusNode,
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
                                        : 'Popular place${suggestion.category == null ? '' : ' • ${suggestion.category}'}',
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
  _PopularPlace(
    displayName: 'Guy\'s Hospital',
    searchAliases: ['guys hospital', 'guys nhs', 'london bridge hospital'],
    formattedAddress:
        'Guy\'s Hospital, Great Maze Pond, London SE1 9RT, United Kingdom',
    lat: 51.5031,
    lng: -0.0870,
    category: 'hospital',
  ),
  _PopularPlace(
    displayName: 'St Thomas\' Hospital',
    searchAliases: ['st thomas hospital', 'saint thomas nhs'],
    formattedAddress:
        'St Thomas\' Hospital, Westminster Bridge Road, London SE1 7EH, United Kingdom',
    lat: 51.4989,
    lng: -0.1187,
    category: 'hospital',
  ),
  _PopularPlace(
    displayName: 'University College Hospital',
    searchAliases: ['uch', 'uclh', 'university college hospital'],
    formattedAddress:
        'University College Hospital, 235 Euston Road, London NW1 2BU, United Kingdom',
    lat: 51.5247,
    lng: -0.1361,
    category: 'hospital',
  ),
  _PopularPlace(
    displayName: 'Boots Pharmacy, Oxford Street',
    searchAliases: ['boots oxford street', 'boots pharmacy oxford street'],
    formattedAddress:
        'Boots Pharmacy, 361 Oxford Street, London W1C 2JL, United Kingdom',
    lat: 51.5148,
    lng: -0.1488,
    category: 'pharmacy',
  ),
  _PopularPlace(
    displayName: 'King\'s College Hospital',
    searchAliases: ['kings college hospital', 'kch', 'denmark hill hospital'],
    formattedAddress:
        'King\'s College Hospital, Denmark Hill, London SE5 9RS, United Kingdom',
    lat: 51.4681,
    lng: -0.0937,
    category: 'nhs facility',
  ),
];

String _normalizePlaceQuery(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r"[\u2018\u2019']"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

String? _cityFromAddress(String value) {
  final parts = value
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length >= 3) return parts[parts.length - 2];
  if (parts.length >= 2) return parts.last;
  return null;
}

bool _sameSuggestionText(String left, String right) {
  return _normalizePlaceQuery(left) == _normalizePlaceQuery(right);
}

const Map<String, (double, double)> _ukAddressSuggestionSeeds = {
  '10 Downing Street, Westminster, London SW1A 2AA, United Kingdom': (
    51.5034,
    -0.1276,
  ),
  '221B Baker Street, Marylebone, London NW1 6XE, United Kingdom': (
    51.5237,
    -0.1585,
  ),
  '1 Canada Square, Canary Wharf, London E14 5AB, United Kingdom': (
    51.5054,
    -0.0235,
  ),
  'The Shard, 32 London Bridge Street, London SE1 9SG, United Kingdom': (
    51.5045,
    -0.0865,
  ),
  'Westfield London, Ariel Way, London W12 7GF, United Kingdom': (
    51.5074,
    -0.2217,
  ),
  'Selfridges, 400 Oxford Street, London W1A 1AB, United Kingdom': (
    51.5145,
    -0.1527,
  ),
  'King\'s Cross Station, Euston Road, London N1C 4TB, United Kingdom': (
    51.5308,
    -0.1238,
  ),
  'Manchester Piccadilly Station, Manchester M1 2BN, United Kingdom': (
    53.4774,
    -2.2309,
  ),
  'Bullring, Birmingham B5 4BU, United Kingdom': (52.4776, -1.8936),
  'Cabot Circus, Bristol BS1 3BD, United Kingdom': (51.4581, -2.5837),
  'St James Quarter, Edinburgh EH1 3AD, United Kingdom': (55.9547, -3.1882),
  'Cardiff Central Station, Cardiff CF10 1EP, United Kingdom': (
    51.4755,
    -3.1780,
  ),
  'Leeds Station, New Station Street, Leeds LS1 4DY, United Kingdom': (
    53.7947,
    -1.5479,
  ),
  'Liverpool ONE, Liverpool L1 8JQ, United Kingdom': (53.4049, -2.9876),
  'Brighton Station, Queens Road, Brighton BN1 3XP, United Kingdom': (
    50.8290,
    -0.1413,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

const _todayWindowOptions = ['Morning', 'Afternoon', 'Evening'];

class _DeliveryTimingChoices extends StatelessWidget {
  final _CircumColors colors;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _DeliveryTimingChoices({
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const choices = [
      ('asap', Icons.bolt, 'ASAP', 'Book now', 'FAST'),
      ('today', Icons.schedule, 'Today', 'Pick a window', ''),
      ('scheduled', Icons.calendar_month, 'Schedule', 'Any day', ''),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 560;
        final cards = choices
            .map(
              (choice) => _DeliveryTimingCard(
                colors: colors,
                value: choice.$1,
                icon: choice.$2,
                title: choice.$3,
                subtitle: choice.$4,
                badge: choice.$5,
                selected: selected == choice.$1,
                onTap: () => onSelected(choice.$1),
              ),
            )
            .toList();
        if (stacked) {
          return Column(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                cards[index],
                if (index < cards.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              Expanded(child: cards[index]),
              if (index < cards.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _DeliveryTimingCard extends StatelessWidget {
  final _CircumColors colors;
  final String value;
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final bool selected;
  final VoidCallback onTap;

  const _DeliveryTimingCard({
    required this.colors,
    required this.value,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $subtitle',
      child: InkWell(
        key: ValueKey('delivery-timing-$value'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 102),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xff2563eb).withValues(alpha: 0.16)
                : colors.field,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? const Color(0xff60a5fa) : colors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(colors: _spectrumGradient)
                      : null,
                  color: selected ? null : colors.panel,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: selected ? Colors.white : colors.text),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (badge.isNotEmpty) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xff22c55e),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: colors.mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.chevron_right,
                color: selected ? colors.success : colors.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleDateButton extends StatefulWidget {
  final _CircumColors colors;
  final TextEditingController controller;
  final TextEditingController? minimumDateController;
  final String label;

  const _ScheduleDateButton({
    required this.colors,
    required this.controller,
    required this.label,
    this.minimumDateController,
  });

  @override
  State<_ScheduleDateButton> createState() => _ScheduleDateButtonState();
}

class _ScheduleDateButtonState extends State<_ScheduleDateButton> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final minimum = DateTime.tryParse(widget.minimumDateController?.text ?? '');
    final firstDate = minimum != null && minimum.isAfter(now) ? minimum : now;
    final current = DateTime.tryParse(widget.controller.text);
    final selected = await showDatePicker(
      context: context,
      initialDate:
          current != null && !current.isBefore(firstDate) ? current : firstDate,
      firstDate: firstDate,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (selected == null) return;
    final month = selected.month.toString().padLeft(2, '0');
    final day = selected.day.toString().padLeft(2, '0');
    widget.controller.text = '${selected.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text.trim();
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        decoration: BoxDecoration(
          color: widget.colors.field,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month, color: widget.colors.text, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.colors.mutedText,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value.isEmpty ? 'Choose date' : value,
                    style: TextStyle(
                      color: widget.colors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
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
                      child: Text(option, overflow: TextOverflow.ellipsis),
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
  final String? fileName;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _PhotoButton({
    required this.colors,
    required this.fileName,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final attached = fileName != null && fileName!.trim().isNotEmpty;
    return Tooltip(
      message: attached ? 'Remove parcel photo' : 'Add a parcel photo',
      child: InkWell(
        onTap: busy ? null : (attached ? onRemove : onPick),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: attached ? const Color(0xff2563eb) : colors.text,
            borderRadius: BorderRadius.circular(16),
          ),
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(18),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.inverseText,
                  ),
                )
              : Icon(
                  attached ? Icons.check_circle : Icons.photo_camera,
                  color: colors.inverseText,
                ),
        ),
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
        color: const Color(0xff2563eb).withValues(alpha: 0.12),
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

  const _RouteRow({required this.colors, required this.from, required this.to});

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
  final String? disabledReason;
  final VoidCallback onTap;

  const _VehicleTile({
    required this.colors,
    required this.vehicle,
    required this.selected,
    this.disabledReason,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = disabledReason == null;
    final surcharge = DeliveryPricing.calculateVehicleSurcharge(vehicle.name);
    final priceLabel = switch (vehicle.name) {
      'Motorbike' => 'No surcharge',
      'Car' => surcharge == 0
          ? 'Standard vehicle'
          : 'Standard vehicle · +£${surcharge.toStringAsFixed(2)}',
      'Van' => '+£${surcharge.toStringAsFixed(2)} surcharge',
      _ =>
        surcharge == 0 ? 'No surcharge' : '+£${surcharge.toStringAsFixed(2)}',
    };
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: enabled ? onTap : null,
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
            Opacity(
              opacity: enabled ? 1 : 0.38,
              child: Text(vehicle.emoji, style: const TextStyle(fontSize: 27)),
            ),
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
                    disabledReason ?? vehicle.caption,
                    style: TextStyle(
                      color: selected
                          ? colors.inverseText.withValues(alpha: 0.72)
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
                  priceLabel,
                  style: TextStyle(
                    color: selected
                        ? colors.inverseText.withValues(alpha: 0.72)
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
      'Standard':
          'Balanced price. Normal rider broadcast. Best for everyday deliveries.',
      'Express':
          'Priority matching. Faster pickup. Best for urgent deliveries.',
    };
    return Column(
      children: ['Standard', 'Express'].map((speed) {
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
                                ? colors.inverseText.withValues(alpha: 0.76)
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
                  color: const Color(0xff2563eb).withValues(alpha: 0.14),
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
                  vehicle.name == 'Motorbike' ? 'Honda PCX' : 'Toyota Prius',
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
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
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
    final plate = vehiclePlate.trim();
    final progress = _rankProgress(rank, tripCount);
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
          [
            rankTitle,
            '$tripCount Deliveries Completed',
            '$rating Rating',
            if (progress != null) progress,
            if (plate.isNotEmpty) 'Vehicle plate: $plate',
          ].join('\n'),
          maxLines: 6,
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

  static String? _rankProgress(String rank, int trips) {
    return switch (rank.trim().toLowerCase()) {
      'agent' => '$trips / 50 deliveries to Sentinel',
      'sentinel' => '$trips / 200 deliveries to Warden',
      'warden' => '$trips / 500 deliveries to Knight',
      'knight' => '$trips / 1000 deliveries to Veteran',
      'veteran' => 'Top Circum trust rank',
      _ => null,
    };
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
    final name = driver?.fullName ?? 'your Circum Rider';
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
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
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
                  amount == 0 ? 'No tip' : '+£${amount.toStringAsFixed(0)}',
                ),
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
              label: Text(
                submitted
                    ? 'Rating submitted'
                    : submitting
                        ? 'Saving...'
                        : 'Submit rating',
              ),
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

class _IrisDeliveryAnalysisCard extends StatelessWidget {
  final _CircumColors colors;
  final String itemName;
  final int quantity;
  final double pricingWeightKg;
  final String weightBand;
  final bool repositoryMatched;
  final String? confidence;
  final String recommendedVehicle;
  final String selectedVehicle;
  final bool corrected;

  const _IrisDeliveryAnalysisCard({
    required this.colors,
    required this.itemName,
    required this.quantity,
    required this.pricingWeightKg,
    required this.weightBand,
    required this.repositoryMatched,
    required this.confidence,
    required this.recommendedVehicle,
    required this.selectedVehicle,
    required this.corrected,
  });

  @override
  Widget build(BuildContext context) {
    final confidenceText = confidence?.trim();
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(colors: colors, title: 'IRIS Delivery Analysis'),
          const SizedBox(height: 10),
          _AnalysisLine(colors: colors, label: 'Item', value: itemName),
          _AnalysisLine(colors: colors, label: 'Quantity', value: '$quantity'),
          _AnalysisLine(
            colors: colors,
            label: 'Pricing weight',
            value: '${_formatDisplayWeight(pricingWeightKg)} · $weightBand',
          ),
          _AnalysisLine(
            colors: colors,
            label: 'Repository match',
            value: repositoryMatched ? 'Yes' : 'No',
          ),
          if (confidenceText != null && confidenceText.isNotEmpty)
            _AnalysisLine(
              colors: colors,
              label: 'Confidence',
              value: confidenceText,
            ),
          _AnalysisLine(
            colors: colors,
            label: 'Recommended vehicle',
            value: recommendedVehicle,
          ),
          _AnalysisLine(
            colors: colors,
            label: 'Selected vehicle',
            value: selectedVehicle,
          ),
          if (corrected)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'User correction applied',
                style: TextStyle(
                  color: colors.success,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _formatDisplayWeight(double value) {
    final digits = value.truncateToDouble() == value ? 0 : 1;
    return '${value.toStringAsFixed(digits)} kg';
  }
}

class _AnalysisLine extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;

  const _AnalysisLine({
    required this.colors,
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
          Icon(Icons.check_circle, color: colors.success, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(color: colors.mutedText, height: 1.3),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletedDeliveryActions extends StatelessWidget {
  final _CircumColors colors;
  final VoidCallback onBookAgain;
  final VoidCallback onViewHistory;

  const _CompletedDeliveryActions({
    required this.colors,
    required this.onBookAgain,
    required this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onBookAgain,
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('Book another delivery'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.text,
              foregroundColor: colors.inverseText,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onViewHistory,
            icon: const Icon(Icons.history),
            label: const Text('View delivery history'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.text,
              side: BorderSide(color: colors.border),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
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
          final completed = index < activeIndex || activeIndex >= 3;
          final current = index == activeIndex && !completed;
          final status = _trackingStatuses[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index == _trackingStatuses.length - 1 ? 0 : 14,
            ),
            child: Row(
              children: [
                Icon(
                  completed
                      ? Icons.check_circle
                      : current
                          ? Icons.radio_button_checked
                          : Icons.circle_outlined,
                  color: completed
                      ? colors.success
                      : current
                          ? colors.adminAccent
                          : colors.mutedText,
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
            colors.panel.withValues(alpha: colors.dark ? 0.92 : 0.96),
            colors.adminAccent.withValues(alpha: colors.dark ? 0.10 : 0.06),
            colors.panel.withValues(alpha: colors.dark ? 0.86 : 0.94),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.dark ? 0.18 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color:
                colors.adminGlow.withValues(alpha: colors.dark ? 0.12 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
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
  final Uri uri;
  final IconData icon;
  final bool dark;
  final VoidCallback onPressed;

  const _PillButton({
    required this.label,
    required this.uri,
    required this.icon,
    required this.dark,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Link(
      uri: uri,
      target: LinkTarget.self,
      builder: (context, followLink) {
        return FilledButton.icon(
          onPressed: followLink ?? onPressed,
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
      },
    );
  }
}

class _VanguardLandingPage extends StatelessWidget {
  final _CircumColors colors;
  final VoidCallback onBack;

  const _VanguardLandingPage({
    super.key,
    required this.colors,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      backgroundColor: const Color(0xff030812),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.78),
                    radius: 1.08,
                    colors: [
                      const Color(0xff0b3764).withValues(alpha: 0.74),
                      const Color(0xff07192f).withValues(alpha: 0.93),
                      const Color(0xff030812),
                    ],
                  ),
                ),
              ),
            ),
            ListView(
              padding: EdgeInsets.fromLTRB(
                narrow ? 22 : 40,
                narrow ? 42 : 30,
                narrow ? 22 : 40,
                72,
              ),
              children: [
                Row(
                  children: [
                    if (!narrow) ...[
                      IconButton(
                        tooltip: 'Back',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Image.asset(
                      'assets/images/circum_wordmark.png',
                      width: narrow ? 142 : 154,
                      errorBuilder: (context, error, stackTrace) => const Text(
                        'CIRCUM',
                        style: TextStyle(
                          color: Color(0xff0a84ff),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: narrow ? 118 : 64),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Column(
                      children: [
                        const _VanguardShieldFallback(size: 148),
                        const SizedBox(height: 54),
                        Text(
                          'Vanguard',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Georgia',
                            fontSize: narrow ? 68 : 88,
                            height: 0.96,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Vanguard gives your delivery enhanced\nhandling, priority support, trusted Circum Rider\nprioritisation, and stronger custody tracking\nfor important items.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.73),
                            fontSize: narrow ? 26 : 30,
                            height: 1.55,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Optional add-on at checkout — £1.99',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: narrow ? 20 : 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: narrow ? 88 : 78),
                        Text(
                          'Vanguard exists for\ndeliveries where trust\nmatters more than speed.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Georgia',
                            fontSize: narrow ? 45 : 62,
                            height: 1.18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 46),
                        _VanguardFeatureCard(
                          icon: Icons.verified_user_outlined,
                          title: 'Trusted Rider Prioritisation',
                          body:
                              'Circum prioritises experienced and highly trusted Circum Riders during assignment. Customers do not choose Circum Riders.',
                        ),
                        const SizedBox(height: 24),
                        _VanguardFeatureCard(
                          icon: Icons.support_agent,
                          title: 'Priority support',
                          body:
                              'Vanguard deliveries receive priority support and dispute review.',
                        ),
                        const SizedBox(height: 24),
                        _VanguardFeatureCard(
                          icon: Icons.timeline_outlined,
                          title: 'Enhanced custody tracking',
                          body:
                              'Clearer delivery milestones create stronger visibility from assignment to delivery.',
                        ),
                        const SizedBox(height: 40),
                        const _VanguardTimelineCard(),
                        const SizedBox(height: 40),
                        const _VanguardChecklistCard(
                          title: 'When to use it',
                          items: [
                            'Gifts and keepsakes',
                            'Signed documents',
                            'Passports and travel documents',
                            'Electronics and valuable items',
                            'Fragile items',
                            'Sentimental items',
                          ],
                        ),
                        const SizedBox(height: 32),
                        const _VanguardChecklistCard(
                          title: 'What £1.99 adds',
                          items: [
                            'Trusted Rider Prioritisation',
                            'Priority support',
                            'Enhanced custody tracking',
                            'Priority dispute review',
                            'Better handling for important items',
                          ],
                        ),
                        const SizedBox(height: 32),
                        const _VanguardImportantCard(),
                      ],
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

class _VanguardShieldFallback extends StatelessWidget {
  final double size;

  const _VanguardShieldFallback({this.size = 170});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            const Color(0xff1e88ff).withValues(alpha: 0.22),
            const Color(0xff1e3a8a).withValues(alpha: 0.12),
            const Color(0xff0a84ff).withValues(alpha: 0.03),
          ],
        ),
        border: Border.all(
          color: const Color(0xff0a84ff).withValues(alpha: 0.5),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0a84ff).withValues(alpha: 0.13),
            blurRadius: 48,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.shield_outlined,
          size: size * 0.48,
          color: const Color(0xff0a84ff),
        ),
      ),
    );
  }
}

class _VanguardFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _VanguardFeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: narrow ? 216 : 190),
      padding: EdgeInsets.all(narrow ? 30 : 34),
      decoration: _vanguardCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xff0a84ff), size: 34),
          const SizedBox(height: 28),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: narrow ? 26 : 30,
              height: 1.14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            body,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: narrow ? 21 : 24,
              height: 1.42,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _VanguardTimelineCard extends StatelessWidget {
  const _VanguardTimelineCard();

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    const steps = [
      'Circum Rider assigned',
      'Item collected',
      'In transit',
      'Delivery attempt',
      'Delivered',
    ];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        narrow ? 34 : 42,
        narrow ? 44 : 48,
        narrow ? 34 : 42,
        narrow ? 44 : 48,
      ),
      decoration: _vanguardCardDecoration(darker: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Custody preview',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Georgia',
              fontSize: narrow ? 42 : 52,
              height: 1.02,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 34),
          ...List.generate(steps.length, (index) {
            final last = index == steps.length - 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xff0a84ff),
                      ),
                    ),
                    if (!last)
                      Container(
                        width: 2,
                        height: 48,
                        color: const Color(0xff475569).withValues(alpha: 0.5),
                      ),
                  ],
                ),
                const SizedBox(width: 24),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    steps[index],
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: narrow ? 22 : 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _VanguardChecklistCard extends StatelessWidget {
  final String title;
  final List<String> items;

  const _VanguardChecklistCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        narrow ? 34 : 42,
        narrow ? 44 : 48,
        narrow ? 34 : 42,
        narrow ? 44 : 48,
      ),
      decoration: _vanguardCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Georgia',
              fontSize: narrow ? 42 : 52,
              height: 1.04,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 34),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xff0a84ff),
                    size: 28,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.74),
                        fontSize: narrow ? 23 : 27,
                        height: 1.18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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

class _VanguardImportantCard extends StatelessWidget {
  const _VanguardImportantCard();

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        narrow ? 34 : 42,
        narrow ? 44 : 48,
        narrow ? 34 : 42,
        narrow ? 44 : 48,
      ),
      decoration: _vanguardCardDecoration(darker: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Important',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Georgia',
              fontSize: narrow ? 42 : 52,
              height: 1.04,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Vanguard is not insurance. It does not provide reimbursement, financial cover, or guarantees.\n\nVanguard provides a higher standard of handling, visibility, verification, rider prioritisation, and support.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: narrow ? 22 : 27,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _vanguardCardDecoration({bool darker = false}) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(darker ? 0xff101722 : 0xff102845).withValues(alpha: 0.86),
        Color(darker ? 0xff0b1019 : 0xff0b1a2c).withValues(alpha: 0.92),
      ],
    ),
    borderRadius: BorderRadius.circular(28),
    border: Border.all(
      color: const Color(0xff5b7fa8).withValues(alpha: 0.34),
      width: 1.4,
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xff0a84ff).withValues(alpha: 0.08),
        blurRadius: 34,
        offset: const Offset(0, 18),
      ),
    ],
  );
}

class _LandingFooter extends StatelessWidget {
  final _CircumColors colors;
  final VoidCallback onDeliveries;
  final VoidCallback onHealthPlus;
  final VoidCallback? onGifts;
  final VoidCallback onBusiness;
  final VoidCallback onVanguard;

  const _LandingFooter({
    required this.colors,
    required this.onDeliveries,
    required this.onHealthPlus,
    required this.onGifts,
    required this.onBusiness,
    required this.onVanguard,
  });

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
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
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: [
                      _FooterServiceLink(
                        label: 'Privacy Policy',
                        uri: _CircumWebsiteAppState._canonicalWebUri(
                          '/privacy',
                        ),
                        onPressed: () {},
                      ),
                      _FooterServiceLink(
                        label: 'Terms of Service',
                        uri: _CircumWebsiteAppState._canonicalWebUri('/terms'),
                        onPressed: () {},
                      ),
                    ],
                  ),
                  Text(
                    '© ${DateTime.now().year} Circum Technologies Ltd.',
                    style: TextStyle(color: colors.mutedText),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Services',
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _FooterServiceLink(
                    label: 'Deliveries',
                    uri: _CircumWebsiteAppState._canonicalWebUri('/send'),
                    onPressed: onDeliveries,
                  ),
                  _FooterServiceLink(
                    label: 'Health+',
                    uri: _CircumWebsiteAppState._canonicalWebUri(
                      '/send/health',
                    ),
                    onPressed: onHealthPlus,
                  ),
                  if (onGifts != null)
                    _FooterServiceLink(
                      label: 'Gifts by Circum',
                      uri: _CircumWebsiteAppState._canonicalWebUri('/gifts'),
                      onPressed: onGifts!,
                    ),
                  _FooterServiceLink(
                    label: 'Business',
                    uri: _CircumWebsiteAppState._canonicalWebUri(
                      '/send/business',
                    ),
                    onPressed: onBusiness,
                  ),
                  _FooterServiceLink(
                    label: 'Vanguard',
                    uri: _CircumWebsiteAppState._canonicalWebUri('/vanguard'),
                    onPressed: onVanguard,
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

class _FooterServiceLink extends StatelessWidget {
  final String label;
  final Uri uri;
  final VoidCallback onPressed;

  const _FooterServiceLink({
    required this.label,
    required this.uri,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Link(
      uri: uri,
      target: LinkTarget.self,
      builder: (context, followLink) {
        return TextButton(
          onPressed: followLink ?? onPressed,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label),
        );
      },
    );
  }
}

class _GiftsRequestPage extends StatefulWidget {
  final _CircumColors colors;
  final VoidCallback onBack;

  const _GiftsRequestPage({
    super.key,
    required this.colors,
    required this.onBack,
  });

  @override
  State<_GiftsRequestPage> createState() => _GiftsRequestPageState();
}

class _GiftsRequestPageState extends State<_GiftsRequestPage> {
  final _previewEmail = TextEditingController();
  final _previewPassword = TextEditingController();
  final _senderName = TextEditingController();
  final _senderEmail = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _recipientEmail = TextEditingController();
  final _deliveryAddress = TextEditingController();
  final _budget = TextEditingController();
  final _personalMessage = TextEditingController();
  final _notes = TextEditingController();
  final _clothingSize = TextEditingController();
  final _shoeSize = TextEditingController();
  final _ringSize = TextEditingController();
  final _height = TextEditingController();
  final _favouriteColours = TextEditingController();
  final _likedBrands = TextEditingController();
  final _dislikedBrands = TextEditingController();
  String _preferredFit = 'Regular';
  _ValidatedAddress? _validatedGiftAddress;
  String _relationship = 'Friend';
  String _occasion = 'Birthday';
  String _timeWindow = 'Afternoon';
  String _giftMode = 'gift_someone';
  String _anonymousGiftType = 'direct';
  String _senderRevealMode = 'anonymous_until_consent';
  String _selfGiftFrequency = 'one_off';
  DateTime? _deliveryDate;
  final Set<String> _interests = {};
  XFile? _photo;
  bool _saving = false;
  bool _signingIn = false;
  String? _message;
  List<Map<String, dynamic>> _requests = const [];

  static const _relationships = [
    'Partner',
    'Husband',
    'Wife',
    'Mother',
    'Father',
    'Son',
    'Daughter',
    'Brother',
    'Sister',
    'Friend',
    'Colleague',
    'Mentor',
    'Client',
    'Teacher',
  ];
  static const _occasions = [
    'Birthday',
    'Anniversary',
    'Wedding',
    'Engagement',
    'Graduation',
    'New Baby',
    'Baby Shower',
    'Christening',
    'Baptism',
    'Confirmation',
    'Christmas',
    'Easter',
    'Eid',
    'Diwali',
    'Hanukkah',
    "Mother's Day",
    "Father's Day",
    "Valentine's Day",
    'Retirement',
    'Promotion',
    'New Job',
    'Housewarming',
    'Thank You',
    'Congratulations',
    'Get Well Soon',
    'Sympathy',
    'Apology',
    'Just Because',
    'Bank Holiday Surprise',
    'Leaving Gift',
    'Achievement Reward',
  ];
  static const _interestOptions = [
    'Fashion',
    'Beauty',
    'Makeup',
    'Skincare',
    'Tech',
    'Gaming',
    'Gym',
    'Travel',
    'Books',
    'Food',
    'Cooking',
    'Coffee',
    'Tea',
    'Christian',
    'Muslim',
    'Jewish',
    'Spiritual',
    'Charity',
    'Aviation',
    'Music',
    'Luxury',
    'Minimalist',
    'Home Decor',
    'Fragrance',
    'Art',
    'Design',
    'Architecture',
    'Gardening',
    'Film',
    'Theatre',
    'Sports',
    'Football',
    'Running',
    'Cycling',
    'Swimming',
    'Photography',
    'Cars',
    'Motorcycles',
    'Jewellery',
    'Watches',
    'Writing',
    'Animals',
    'Nature',
    'Sustainability',
    'Collectibles',
  ];

  @override
  void initState() {
    super.initState();
    _loadAccountAndRequests();
  }

  @override
  void dispose() {
    for (final controller in [
      _senderName,
      _senderEmail,
      _recipientName,
      _recipientPhone,
      _recipientEmail,
      _deliveryAddress,
      _budget,
      _personalMessage,
      _notes,
      _clothingSize,
      _shoeSize,
      _ringSize,
      _height,
      _favouriteColours,
      _likedBrands,
      _dislikedBrands,
      _previewEmail,
      _previewPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAccountAndRequests() async {
    await _ensureCircumFirebaseReady();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _senderEmail.text = user.email ?? '';
    _senderName.text = user.displayName ?? '';
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('giftRequests')
          .where('senderId', isEqualTo: user.uid)
          .limit(20)
          .get();
      if (!mounted) return;
      setState(
        () => _requests = snapshot.docs
            .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
            .toList(),
      );
      await _handleGiftPaymentReturn();
    } catch (error) {
      debugPrint('Gift request history error: $error');
    }
  }

  Future<void> _signInToPreview() async {
    if (_signingIn) return;
    final email = _previewEmail.text.trim().toLowerCase();
    setState(() {
      _signingIn = true;
      _message = null;
    });
    try {
      await _ensureCircumFirebaseReady();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _previewPassword.text,
      );
      await _loadAccountAndRequests();
      if (mounted) setState(() => _message = 'Signed in.');
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(
          () => _message = switch (error.code) {
            'invalid-credential' ||
            'wrong-password' =>
              'The email or password is incorrect.',
            'invalid-email' => 'Enter a valid email address.',
            _ => 'We could not sign you in. Please try again.',
          },
        );
      }
    } catch (error) {
      debugPrint('Gifts sign-in error: $error');
      if (mounted) {
        setState(
          () => _message = 'We could not sign you in. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _handleGiftPaymentReturn() async {
    final result = Uri.base.queryParameters['gift_payment'];
    if (result == 'cancelled') {
      if (mounted) {
        setState(
          () => _message =
              'Payment was cancelled. Your gift has not been submitted.',
        );
      }
      return;
    }
    if (result != 'success') return;
    final giftDraftId = Uri.base.queryParameters['giftDraftId'];
    final sessionId = Uri.base.queryParameters['session_id'];
    if (giftDraftId == null || sessionId == null) return;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('finalizeGiftPayment')
          .call({'giftDraftId': giftDraftId, 'sessionId': sessionId});
      if (mounted) {
        setState(
          () => _message =
              'Payment received. Your gift experience is now submitted for review.',
        );
      }
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'Gift payment finalization error: ${error.code} ${error.message}',
      );
      if (mounted) {
        setState(
          () => _message = error.message ??
              'We could not confirm payment yet. Please refresh shortly.',
        );
      }
    }
  }

  Future<void> _pickPhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _message = 'Sign in to create a gift experience.');
      return;
    }
    final grossBudget = double.tryParse(_budget.text.trim());
    final validation = GiftRequestPolicy.validate(
      senderEmail: _senderEmail.text,
      recipientName: _recipientName.text,
      recipientPhone: _recipientPhone.text,
      recipientEmail: _recipientEmail.text,
      relationship: _relationship,
      occasion: _occasion,
      deliveryAddress: _deliveryAddress.text,
      deliveryDate: _deliveryDate,
      grossBudget: grossBudget,
    );
    if (validation != null) {
      setState(() => _message = validation);
      return;
    }
    if (_validatedGiftAddress == null) {
      setState(
        () => _message =
            'Please select a verified address from the suggestions, or confirm the manual address.',
      );
      return;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review your gift experience'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Occasion: $_occasion'),
              Text('Recipient: ${_recipientName.text.trim()}'),
              Text(
                'Contact: ${_recipientPhone.text.trim()} · ${_recipientEmail.text.trim()}',
              ),
              Text('Delivery: ${_deliveryAddress.text.trim()}'),
              Text('Date: ${_adminDateText(_deliveryDate)} · $_timeWindow'),
              Text('Gift budget: £${grossBudget!.toStringAsFixed(2)}'),
              if (_personalMessage.text.trim().isNotEmpty)
                Text('Message: ${_personalMessage.text.trim()}'),
              const SizedBox(height: 12),
              const Text(
                'Gift contents remain confidential before delivery. No products, brands, retailers or basket details are shown.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Proceed to Payment'),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final giftDraftId =
          FirebaseFirestore.instance.collection('giftPaymentDrafts').doc().id;
      final photoUrls = <String>[];
      if (_photo != null) {
        final bytes = await _photo!.readAsBytes();
        if (bytes.length > 8 * 1024 * 1024) {
          throw StateError('Photo must be smaller than 8 MB.');
        }
        final ref = FirebaseStorage.instance.ref(
          'gift_requests/${user.uid}/$giftDraftId.jpg',
        );
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        photoUrls.add(await ref.getDownloadURL());
      }
      final giftDraft = {
        'senderId': user.uid,
        'senderName': _senderName.text.trim(),
        'senderEmail': _senderEmail.text.trim().toLowerCase(),
        'recipientName': _recipientName.text.trim(),
        'recipientPhone': _recipientPhone.text.trim(),
        'recipientEmail': _recipientEmail.text.trim().toLowerCase(),
        'recipientContact':
            '${_recipientPhone.text.trim()} · ${_recipientEmail.text.trim().toLowerCase()}',
        'relationship': _relationship,
        'occasion': _occasion,
        'giftMode': _giftMode,
        'anonymousGiftType':
            _giftMode == 'anonymous_gift' ? _anonymousGiftType : null,
        'senderRevealMode': _giftMode == 'anonymous_gift'
            ? _senderRevealMode
            : 'reveal_immediately',
        'senderRevealConsent':
            _giftMode == 'anonymous_gift' ? 'not_requested' : 'granted',
        'recipientRevealRequestStatus': 'none',
        'selfGiftFrequency':
            _giftMode == 'gift_myself' ? _selfGiftFrequency : null,
        'deliveryAddress': _deliveryAddress.text.trim(),
        'deliveryAddressData': _validatedGiftAddress!.toJson(),
        'deliveryPostcode': _validatedGiftAddress!.postcode,
        'deliveryCity': _validatedGiftAddress!.city,
        'deliveryCountry': _validatedGiftAddress!.country,
        'deliveryDate': Timestamp.fromDate(_deliveryDate!),
        'deliveryTimeWindow': _timeWindow,
        'budget': grossBudget,
        'grossBudget': grossBudget,
        'grossGiftBudget': grossBudget,
        'estimatedStripeFee': GiftRequestPolicy.estimatedStripeFee(
          grossBudget!,
        ),
        'netGiftBudgetAfterFees': GiftRequestPolicy.estimatedNetGiftBudget(
          grossBudget,
        ),
        'estimatedNetGiftBudget': GiftRequestPolicy.estimatedNetGiftBudget(
          grossBudget,
        ),
        'budgetStatus': 'pending_allocation',
        'personalMessage': _personalMessage.text.trim(),
        'interests': _interests.toList(),
        'photoUrls': photoUrls,
        'notes': _notes.text.trim(),
        'sizesAndPreferences': {
          'clothingSize': _clothingSize.text.trim(),
          'shoeSize': _shoeSize.text.trim(),
          'ringSize': _ringSize.text.trim(),
          'preferredFit': _preferredFit,
          'height': _height.text.trim(),
          'favouriteColours': _favouriteColours.text.trim(),
          'brandsLiked': _likedBrands.text.trim(),
          'brandsDisliked': _dislikedBrands.text.trim(),
        },
        'giftType':
            _giftMode == 'anonymous_gift' && _anonymousGiftType == 'campaign'
                ? 'campaign'
                : 'standard',
        'paymentStatus': 'payment_pending',
        'giftStatus': 'draft',
        'status': 'draft',
        'assignedAdminId': null,
        'irisSuggestion': 'Pending IRIS gift recommendation',
        'adminDecision': '',
        'internalNotes': '',
        'recipientContentConsent': 'pending',
        'senderContentConsent': 'pending',
        'consentCapturedAt': null,
        'consentVersion': 'gifts-social-v1',
        'consentNotes': '',
        'allowCircumSocialUse': false,
        'allowBrandTagging': false,
        'allowReactionRecording': false,
        'allowPublicPosting': false,
        'allowAnonymousPosting': false,
        'contentUsageScope': 'private',
        'contentConsentWithdrawnAt': null,
        'contentStatus': 'not_started',
        'campaignId':
            _anonymousGiftType == 'campaign' ? 'bringing-london-closer' : null,
        'campaignName':
            _anonymousGiftType == 'campaign' ? 'Bringing London Closer' : null,
        'campaignTagline': _anonymousGiftType == 'campaign'
            ? '100 Londoners. 100 gifts. 100 stories.'
            : null,
        'campaignType':
            _anonymousGiftType == 'campaign' ? 'anonymous_gifting' : null,
        'participantConsentRequired': _anonymousGiftType == 'campaign',
        'recordingConsentRequired': _anonymousGiftType == 'campaign',
        'mutualRevealAllowed': _anonymousGiftType == 'campaign',
        'anonymousByDefault': _giftMode == 'anonymous_gift',
      };
      final payment = await FirebaseFunctions.instance
          .httpsCallable('createGiftPayment')
          .call({'giftDraftId': giftDraftId, 'giftDraft': giftDraft});
      final paymentData = Map<String, dynamic>.from(payment.data as Map);
      final checkoutUrl = Uri.tryParse('${paymentData['url'] ?? ''}');
      if (checkoutUrl == null || checkoutUrl.host.isEmpty) {
        throw StateError(
          'Stripe Checkout could not be opened. Please try again.',
        );
      }
      setState(
        () => _message = 'Complete payment to submit your gift request.',
      );
      final opened = await launchUrl(checkoutUrl, webOnlyWindowName: '_self');
      if (!opened) {
        throw StateError(
          'Stripe Checkout could not be opened. Please try again.',
        );
      }
    } catch (error) {
      debugPrint('Gift request submit error: $error');
      if (mounted) {
        setState(
          () => _message = error is StateError
              ? error.message
              : error is FirebaseFunctionsException
                  ? (error.message ??
                      'Could not start Stripe Checkout. Please try again.')
                  : 'Could not start Stripe Checkout. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final signedIn = FirebaseAuth.instance.currentUser != null;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            narrow ? 16 : 28,
            16,
            narrow ? 16 : 28,
            48,
          ),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                Image.asset('assets/images/circum_wordmark.png', width: 126),
              ],
            ),
            const SizedBox(height: 22),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/images/gifts_by_circum_logo.jpg',
                        width: narrow ? 280 : 390,
                        semanticLabel: 'Gifts by Circum logo',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Thoughtful gifting, delivered by Circum',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.mutedText,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Tell us the occasion, the person, and your budget. Circum creates and delivers a thoughtful gift experience.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: narrow ? 25 : 34,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Chip(
                        avatar: const Icon(Icons.lock_clock, size: 18),
                        label: const Text('Early Access Beta'),
                        backgroundColor: colors.adminAccent.withValues(
                          alpha: 0.16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Center(
                      child: _HealthChip(label: 'Vanguard Included'),
                    ),
                    const SizedBox(height: 16),
                    if (!signedIn)
                      _GlassPanel(
                        colors: colors,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Sign in to Gifts',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in to create and pay for a curated gift experience.',
                              style: TextStyle(
                                color: colors.mutedText,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _giftField(
                              _previewEmail,
                              'Email address',
                              Icons.email_outlined,
                              type: TextInputType.emailAddress,
                            ),
                            _giftField(
                              _previewPassword,
                              'Password',
                              Icons.lock_outline,
                              obscure: true,
                            ),
                            if (_message != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _message!,
                                style: TextStyle(
                                  color: colors.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _signingIn ? null : _signInToPreview,
                              icon: _signingIn
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.lock_open),
                              label: Text(
                                _signingIn
                                    ? 'Signing in...'
                                    : 'Sign in and continue',
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (signedIn) ...[
                      _GlassPanel(
                        colors: colors,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'How Gifts Works',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...const [
                              '1. Tell us about the recipient.',
                              '2. Set your budget.',
                              '3. IRIS creates private recommendations.',
                              '4. The Gifts Team reviews and approves the experience.',
                              '5. We source, prepare and deliver.',
                              '6. The recipient discovers the surprise.',
                            ].map(
                              (step) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(step),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Gift contents are intentionally kept confidential before delivery. Gifts by Circum is a curated gifting experience, not a traditional online shop.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _GlassPanel(
                        colors: colors,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Create the experience',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _giftMode,
                              decoration: const InputDecoration(
                                labelText: 'Gift mode',
                              ),
                              items: const {
                                'gift_someone': 'Gift someone',
                                'gift_myself': 'Gift myself',
                                'anonymous_gift': 'Anonymous gift',
                              }
                                  .entries
                                  .map(
                                    (entry) => DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(entry.value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(
                                () => _giftMode = value ?? _giftMode,
                              ),
                            ),
                            if (_giftMode == 'anonymous_gift') ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _anonymousGiftType,
                                decoration: const InputDecoration(
                                  labelText: 'Anonymous gift type',
                                ),
                                items: const {
                                  'direct': 'Direct anonymous gift',
                                  'campaign':
                                      'Campaign · Bringing London Closer',
                                }
                                    .entries
                                    .map(
                                      (entry) => DropdownMenuItem(
                                        value: entry.key,
                                        child: Text(entry.value),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => setState(
                                  () => _anonymousGiftType =
                                      value ?? _anonymousGiftType,
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _senderRevealMode,
                                decoration: const InputDecoration(
                                  labelText: 'Identity reveal',
                                ),
                                items: const {
                                  'anonymous_forever': 'Anonymous forever',
                                  'reveal_after_delivery':
                                      'Reveal after delivery',
                                  'anonymous_until_consent':
                                      'Reveal only with later consent',
                                  'reveal_immediately': 'Reveal immediately',
                                }
                                    .entries
                                    .map(
                                      (entry) => DropdownMenuItem(
                                        value: entry.key,
                                        child: Text(entry.value),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => setState(
                                  () => _senderRevealMode =
                                      value ?? _senderRevealMode,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Circum knows who arranged the gift for safety and fraud prevention. The recipient only sees the sender identity when consent permits or disclosure is legally required.',
                                style: TextStyle(
                                  color: colors.mutedText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            if (_giftMode == 'gift_myself') ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _selfGiftFrequency,
                                decoration: const InputDecoration(
                                  labelText: 'Self-gift frequency',
                                ),
                                items: const {
                                  'one_off': 'One-off',
                                  'monthly': 'Monthly',
                                  'quarterly': 'Quarterly',
                                  'custom': 'Custom',
                                }
                                    .entries
                                    .map(
                                      (entry) => DropdownMenuItem(
                                        value: entry.key,
                                        child: Text(entry.value),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => setState(
                                  () => _selfGiftFrequency =
                                      value ?? _selfGiftFrequency,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              'Who is receiving?',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _giftField(
                              _senderName,
                              'Circum name',
                              Icons.person_outline,
                            ),
                            _giftField(
                              _senderEmail,
                              'Sender email',
                              Icons.email_outlined,
                              type: TextInputType.emailAddress,
                            ),
                            _giftField(
                              _recipientName,
                              'Recipient name',
                              Icons.redeem_outlined,
                            ),
                            _giftField(
                              _recipientPhone,
                              'Recipient phone',
                              Icons.contact_phone_outlined,
                            ),
                            _giftField(
                              _recipientEmail,
                              'Recipient email',
                              Icons.email_outlined,
                              type: TextInputType.emailAddress,
                            ),
                            Text(
                              'Tell us about them',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _relationship,
                                    decoration: const InputDecoration(
                                      labelText: 'Relationship',
                                    ),
                                    items: _relationships
                                        .map(
                                          (v) => DropdownMenuItem(
                                            value: v,
                                            child: Text(v),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(
                                      () => _relationship = v ?? _relationship,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _occasion,
                                    decoration: const InputDecoration(
                                      labelText: 'Occasion',
                                    ),
                                    items: _occasions
                                        .map(
                                          (v) => DropdownMenuItem(
                                            value: v,
                                            child: Text(v),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(
                                      () => _occasion = v ?? _occasion,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Sizes and preferences',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                SizedBox(
                                  width: 180,
                                  child: _giftField(
                                    _clothingSize,
                                    'Clothing size',
                                    Icons.checkroom,
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: _giftField(
                                    _shoeSize,
                                    'Shoe size',
                                    Icons.hiking,
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: _giftField(
                                    _ringSize,
                                    'Ring size',
                                    Icons.circle_outlined,
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: _giftField(
                                    _height,
                                    'Height',
                                    Icons.height,
                                  ),
                                ),
                              ],
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _preferredFit,
                              decoration: const InputDecoration(
                                labelText: 'Preferred fit',
                              ),
                              items: const [
                                'Slim',
                                'Regular',
                                'Relaxed',
                                'Oversized',
                              ]
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(
                                () => _preferredFit = v ?? _preferredFit,
                              ),
                            ),
                            _giftField(
                              _favouriteColours,
                              'Favourite colours',
                              Icons.palette_outlined,
                            ),
                            _giftField(
                              _likedBrands,
                              'Brands they like',
                              Icons.favorite_border,
                            ),
                            _giftField(
                              _dislikedBrands,
                              'Brands they dislike',
                              Icons.block,
                            ),
                            Text(
                              'Delivery details',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _AddressField(
                              colors: colors,
                              icon: Icons.location_on_outlined,
                              label: 'Delivery address',
                              controller: _deliveryAddress,
                              verified:
                                  _validatedGiftAddress?.isVerified == true,
                              onSelected: (address) => setState(
                                () => _validatedGiftAddress = address,
                              ),
                              onEdited: (_) =>
                                  setState(() => _validatedGiftAddress = null),
                              verifiedMessage:
                                  'Verified delivery address selected',
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final date = await showDatePicker(
                                        context: context,
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime.now().add(
                                          const Duration(days: 365),
                                        ),
                                        initialDate: _deliveryDate ??
                                            DateTime.now().add(
                                              const Duration(days: 2),
                                            ),
                                      );
                                      if (date != null) {
                                        setState(() => _deliveryDate = date);
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_month),
                                    label: Text(
                                      _deliveryDate == null
                                          ? 'Preferred delivery date'
                                          : _adminDateText(_deliveryDate),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _timeWindow,
                                    decoration: const InputDecoration(
                                      labelText: 'Time window',
                                    ),
                                    items: const [
                                      'Morning',
                                      'Afternoon',
                                      'Evening',
                                    ]
                                        .map(
                                          (v) => DropdownMenuItem(
                                            value: v,
                                            child: Text(v),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(
                                      () => _timeWindow = v ?? _timeWindow,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Gift budget',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [50, 100, 250, 500, 1000, 1500]
                                  .map(
                                    (value) => ChoiceChip(
                                      label: Text('£$value'),
                                      selected: _budget.text == '$value',
                                      onSelected: (_) => setState(
                                        () => _budget.text = '$value',
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 8),
                            _giftField(
                              _budget,
                              'Gift budget (minimum £50)',
                              Icons.payments_outlined,
                              type: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                            Text(
                              'Interests',
                              style: TextStyle(
                                color: colors.text,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _interestOptions
                                  .map(
                                    (interest) => FilterChip(
                                      label: Text(interest),
                                      selected: _interests.contains(interest),
                                      onSelected: (selected) => setState(
                                        () => selected
                                            ? _interests.add(interest)
                                            : _interests.remove(interest),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Additional information',
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _giftField(
                              _personalMessage,
                              'Personal message',
                              Icons.chat_bubble_outline,
                              lines: 3,
                            ),
                            _giftField(
                              _notes,
                              'Additional Information',
                              Icons.notes,
                              lines: 3,
                            ),
                            Text(
                              'Record allergies, medical conditions, dietary requirements, religious considerations, sensitivities, accessibility requirements, favourite colours, favourite brands, dislikes, or any special requests.',
                              style: TextStyle(
                                color: colors.mutedText,
                                fontSize: 12,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickPhoto,
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: Text(
                                _photo == null
                                    ? 'Add optional recipient photo'
                                    : 'Photo selected · Replace',
                              ),
                            ),
                            if (_photo != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _photo = null),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Remove photo'),
                                ),
                              ),
                            if (_message != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  _message!,
                                  style: TextStyle(
                                    color: colors.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _saving ? null : _submit,
                              icon: _saving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.card_giftcard),
                              label: Text(
                                _saving
                                    ? 'Preparing payment...'
                                    : 'Create Gift Experience',
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 17,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'The exact gift contents, supplier costs, and internal fulfilment plan remain private until delivery.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.mutedText,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Circum may ask to record or share a gift reaction. This is optional, and the gift can still be received if filming or public posting is declined.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.mutedText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_requests.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text(
                        'Your gift requests',
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._requests.map(
                        (request) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: colors.field,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.border),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.card_giftcard),
                            title: Text(
                              '${request['occasion']} for ${request['recipientName']}',
                            ),
                            subtitle: Text(
                              GiftRequestPolicy.senderStatus(
                                '${request['status']}',
                              ),
                            ),
                            trailing: Text(
                              '£${((request['grossBudget'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _giftField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? type,
    int lines = 1,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: type,
        maxLines: lines,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      ),
    );
  }
}

class _GiftsComingSoonPage extends StatefulWidget {
  final _CircumColors colors;
  final VoidCallback onBack;

  const _GiftsComingSoonPage({
    required this.colors,
    required this.onBack,
  });

  @override
  State<_GiftsComingSoonPage> createState() => _GiftsComingSoonPageState();
}

class _GiftsComingSoonPageState extends State<_GiftsComingSoonPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;
  String? _message;

  static const _occasions = [
    'Birthdays',
    'Anniversaries',
    'Graduations',
    'Thank You Gifts',
    'Christmas',
    'New Baby',
    'Just Because',
  ];
  static const _interests = [
    'Travel',
    'Technology',
    'Fitness',
    'Coffee',
    'Books',
    'Gaming',
    'Aviation',
  ];

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _joinWaitlist() async {
    final name = _name.text.trim();
    final email = _email.text.trim().toLowerCase();
    if (name.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _message = 'Enter your name and a valid email address.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await _ensureCircumFirebaseReady();
      await FirebaseFirestore.instance.collection('giftsWaitlist').add({
        'name': name,
        'email': email,
        'source': 'gifts-coming-soon',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _name.clear();
      _email.clear();
      setState(() => _message = 'You’re on the Gifts waitlist.');
    } catch (error) {
      debugPrint('Gifts waitlist error: $error');
      if (mounted) {
        setState(
          () => _message =
              'We could not add you just now. Please try again shortly.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            narrow ? 18 : 28,
            16,
            narrow ? 18 : 28,
            42,
          ),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to Circum',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 8),
                  Image.asset(
                    'assets/images/circum_wordmark.png',
                    width: 126,
                    height: 30,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        width: narrow ? double.infinity : 620,
                        constraints: const BoxConstraints(maxWidth: 620),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          color: Colors.black,
                          border: Border.all(
                            color: const Color(
                              0xff70f5d0,
                            ).withValues(alpha: 0.24),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xff9b72ff,
                              ).withValues(alpha: 0.24),
                              blurRadius: 46,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Semantics(
                          image: true,
                          label: 'Gifts by Circum logo',
                          child: Image.asset(
                            'assets/images/gifts_by_circum_logo.jpg',
                            fit: BoxFit.contain,
                            semanticLabel: 'Gifts by Circum logo',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Thoughtful gifting, delivered by Circum',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.mutedText,
                        fontSize: narrow ? 17 : 21,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Coming Soon',
                      style: TextStyle(
                        color: colors.text,
                        fontSize: narrow ? 38 : 56,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 9,
                      runSpacing: 9,
                      children: _occasions
                          .map((label) => Chip(label: Text(label)))
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 9,
                      runSpacing: 9,
                      children: _interests
                          .map(
                            (label) => Chip(
                              avatar: const Icon(Icons.auto_awesome, size: 16),
                              label: Text(label),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 34),
                    _GlassPanel(
                      colors: colors,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Join the waitlist',
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Be notified when Gifts launches.',
                            style: TextStyle(color: colors.mutedText),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _name,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Name',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            onSubmitted: (_) =>
                                _saving ? null : _joinWaitlist(),
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                          if (_message != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _message!,
                              style: TextStyle(
                                color: _message!.startsWith('You’re')
                                    ? Colors.greenAccent.shade400
                                    : colors.mutedText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _saving ? null : _joinWaitlist,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.card_giftcard),
                            label: Text(
                              _saving ? 'Joining...' : 'Join waitlist',
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 17),
                            ),
                          ),
                        ],
                      ),
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

class _CompanyLiveChatButton extends StatefulWidget {
  final _CircumColors colors;

  const _CompanyLiveChatButton({required this.colors});

  @override
  State<_CompanyLiveChatButton> createState() => _CompanyLiveChatButtonState();
}

class _CompanyLiveChatButtonState extends State<_CompanyLiveChatButton> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _message = TextEditingController();
  bool _open = false;
  bool _sending = false;
  String? _note;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    if (_open) {
      return Positioned.fill(
        child: Material(
          color: Colors.black.withValues(alpha: 0.46),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _open = false),
                ),
              ),
              _panel(context, colors),
            ],
          ),
        ),
      );
    }
    return Positioned(
      right: 18,
      bottom: 18,
      child: SafeArea(
        minimum: const EdgeInsets.only(bottom: 4),
        child: Tooltip(
          message: 'Live chat',
          child: Semantics(
            button: true,
            label: 'Open live chat',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _open = true),
                customBorder: const CircleBorder(),
                child: Ink(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: _spectrumGradient),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff6558f5).withValues(alpha: 0.24),
                        blurRadius: 16,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, _CircumColors colors) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 720;
    return Align(
      alignment: compact ? Alignment.bottomCenter : Alignment.centerRight,
      child: SafeArea(
        minimum: EdgeInsets.only(
          left: compact ? 10 : 0,
          right: compact ? 10 : 0,
          bottom: compact ? 10 : 0,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: compact ? double.infinity : 560,
            height: compact ? size.height * 0.92 : double.infinity,
            padding: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: const Color(0xff07090f),
              borderRadius: compact
                  ? BorderRadius.circular(24)
                  : const BorderRadius.horizontal(left: Radius.circular(24)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xff3b82f6).withValues(alpha: 0.12),
                  blurRadius: 34,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: -80,
                  top: 120,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xff3b82f6).withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Column(
                  children: [
                    Container(
                      height: 3,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: 1,
                        child: Container(color: const Color(0xff3b82f6)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: const Color(0xff3b82f6),
                              borderRadius: BorderRadius.circular(99),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xff3b82f6,
                                  ).withValues(alpha: 0.65),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Circum',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.68),
                              fontFamily: 'JetBrains Mono',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Close contact form',
                            onPressed: () => setState(() => _open = false),
                            icon: Icon(
                              Icons.close,
                              color: Colors.white.withValues(alpha: 0.68),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 52, 28, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Contact Circum',
                              style: TextStyle(
                                color: const Color(0xff60a5fa),
                                fontFamily: 'JetBrains Mono',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'How can we help you?',
                              style: TextStyle(
                                color: Color(0xfff5f7fb),
                                fontFamily: 'DM Serif Display',
                                fontSize: 34,
                                height: 1.25,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Send Circum a message about deliveries, riders, accounts, payments, partnerships, or anything else you need help with.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.62),
                                fontSize: 15,
                                height: 1.55,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (compact) ...[
                              _LiveChatField(
                                colors: colors,
                                controller: _firstName,
                                label: 'First name',
                                icon: Icons.person_outline,
                              ),
                              const SizedBox(height: 14),
                              _LiveChatField(
                                colors: colors,
                                controller: _lastName,
                                label: 'Last name',
                                icon: Icons.person_outline,
                              ),
                            ] else
                              Row(
                                children: [
                                  Expanded(
                                    child: _LiveChatField(
                                      colors: colors,
                                      controller: _firstName,
                                      label: 'First name',
                                      icon: Icons.person_outline,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: _LiveChatField(
                                      colors: colors,
                                      controller: _lastName,
                                      label: 'Last name',
                                      icon: Icons.person_outline,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 14),
                            _LiveChatField(
                              colors: colors,
                              controller: _email,
                              label: 'Email or phone',
                              icon: Icons.alternate_email,
                            ),
                            const SizedBox(height: 14),
                            _LiveChatField(
                              colors: colors,
                              controller: _message,
                              label: 'Message',
                              icon: Icons.message_outlined,
                              minLines: 4,
                              maxLines: 6,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'If your message is about an existing delivery, include your delivery reference if you have it.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.58),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_note != null) ...[
                              const SizedBox(height: 16),
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
                            const SizedBox(height: 46),
                            Container(
                              padding: const EdgeInsets.only(top: 20),
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.14),
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    'Press enter or',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.56,
                                      ),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  FilledButton.icon(
                                    onPressed: _sending ? null : _send,
                                    icon: _sending
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.arrow_forward),
                                    label: Text(
                                      _sending ? 'Sending' : 'Send message',
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xff3b82f6),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 22,
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('submitWebsiteSupportRequest').call({
        'name': [
          _firstName.text.trim(),
          _lastName.text.trim(),
        ].where((part) => part.isNotEmpty).join(' '),
        'email': contact,
        'message': message,
        'pageUrl': Uri.base.toString(),
        'participantRole': 'visitor',
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
    name: 'Motorbike',
    emoji: '🏍️',
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
    'Circum Rider assigned',
    'CIRCUM has assigned a rider to this delivery.',
  ),
  _TrackingStatus(
    'Travelling to pickup',
    'Your Circum Rider is heading to the pickup location.',
  ),
  _TrackingStatus(
    'Arrived at pickup',
    'Your Circum Rider has arrived and is waiting for collection.',
  ),
  _TrackingStatus(
    'Pickup verified',
    'Collection has been verified and the parcel is with your Circum Rider.',
  ),
  _TrackingStatus(
    'In transit',
    'Your Circum Rider is travelling to the drop-off location.',
  ),
  _TrackingStatus(
    'Arrived at drop-off',
    'Your Circum Rider is at the destination and ready for handover.',
  ),
  _TrackingStatus(
    'Delivered',
    'Delivery completed. Open the delivery record to view available proof.',
  ),
  _TrackingStatus('Closed', 'This delivery is no longer active.'),
  _TrackingStatus('Needs attention', 'Circum is reviewing this delivery.'),
];
