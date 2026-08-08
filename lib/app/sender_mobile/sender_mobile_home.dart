import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../business/business_access_view.dart';
import '../health_plus/view/health_plus.dart';
import '../sender_profile/sender_profile.dart';
import '../send_package/bloc/send_package_bloc.dart';
import '../send_package/view/ride_chats.dart';
import 'design_system/sender_design_system.dart';
import 'gift_journey_draft.dart';
import 'gift_mode_view.dart';
import 'gift_story_view.dart';
import 'sender_accessibility.dart';
import 'sender_activity.dart';
import 'sender_booking_canvas.dart';
import 'sender_gifts_icon.dart';
import 'sender_mobile_profile.dart';
import 'sender_notification_routing.dart';
import 'sender_notifications.dart';
import 'sender_page_shell.dart';
import 'sender_profile_authority.dart';
import 'sender_ui_baseline.dart';
import 'sender_wallet.dart';

const senderMobileDashboardServiceNames = ['Health+', 'Business', 'Gifts'];
const senderMobileHeroSubtitle =
    'From collection to delivery, every step protected by IRIS.';
const senderMobileDashboardServiceSubtitles = {
  'Health+': 'Trusted medical deliveries',
  'Business': 'Business deliveries',
  'Gifts': 'Thoughtful gifts, delivered.',
};
const senderMobileRecentOrderTitles = ['Passport', 'Prescription collection'];
const senderMobileBottomNavigationLabels = [
  'Home',
  'Send',
  'Activity',
  'Wallet',
  'Profile',
];
const senderMobilePreAuthHeadline = 'Deliver anything with confidence.';
const senderMobilePreAuthSubtitle =
    'Fast, trusted delivery powered by IRIS and verified riders.';
const senderMobileAuthSignInHeadline = 'Welcome back';
const senderMobileAuthCreateHeadline = 'Join Circum';
const senderMobileAuthFinePrint =
    "By continuing, you agree to Circum's Terms and Privacy Policy.";
const senderMobilePreviewAuthEnabledContract =
    'Sender opens with secure sign-in before booking.';

enum _SenderEntryScreen { landing, auth, app }

enum _SenderAuthMode { signIn, createAccount }

class SenderMobileHome extends StatefulWidget {
  final bool previewAuthEnabled;
  final bool initialAuthenticated;
  final int initialIndex;
  final String? initialRouteName;
  final ValueChanged<int>? onTabChanged;
  final SenderHomeRepository? homeRepository;
  final SenderActivityRepository? activityRepository;
  final SenderWalletRepository? walletRepository;
  final SenderMobileProfileRepository? profileRepository;
  final WidgetBuilder? sendTabBuilder;

  const SenderMobileHome({
    super.key,
    this.previewAuthEnabled = false,
    this.initialAuthenticated = false,
    this.initialIndex = 0,
    this.initialRouteName,
    this.onTabChanged,
    this.homeRepository,
    this.activityRepository,
    this.walletRepository,
    this.profileRepository,
    this.sendTabBuilder,
  });

  @override
  State<SenderMobileHome> createState() => _SenderMobileHomeState();
}

class _SenderMobileHomeState extends State<SenderMobileHome> {
  var _index = 0;
  var _entry = _SenderEntryScreen.landing;
  var _authMode = _SenderAuthMode.createAccount;
  var _authRestoring = false;
  SendPackageBloc? _standaloneSendPackageBloc;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex
        .clamp(0, senderMobileBottomNavigationLabels.length - 1);
    _entry = widget.initialAuthenticated
        ? _SenderEntryScreen.app
        : _SenderEntryScreen.landing;
    SenderNotificationOpenBridge.instance.register(_handleNotificationOpen);
    _restoreAuthenticatedSenderSession();
    _openInitialSenderRoute();
  }

  @override
  void dispose() {
    SenderNotificationOpenBridge.instance.unregister(_handleNotificationOpen);
    _authSubscription?.cancel();
    _standaloneSendPackageBloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = Scaffold(
      backgroundColor: _SenderTokens.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: _authRestoring
                  ? const _SenderAuthRestoringSplash()
                  : SizedBox.expand(child: _activeSurface()),
            ),
          ),
        ],
      ),
      bottomNavigationBar: !_authRestoring && _entry == _SenderEntryScreen.app
          ? _SenderBottomNav(
              index: _index,
              onChanged: _selectTab,
            )
          : null,
    );
    final needsBookingBloc = _entry != _SenderEntryScreen.app ||
        (_index == 1 && widget.sendTabBuilder == null);
    final providedSurface = !needsBookingBloc
        ? surface
        : BlocProvider<SendPackageBloc>.value(
            value: _bookingBloc,
            child: surface,
          );
    if (SenderAccessibilityScope.maybeOf(context) != null) {
      return providedSurface;
    }
    return SenderAccessibilityHost(
      key: ValueKey(_entry),
      child: providedSurface,
    );
  }

  SendPackageBloc get _bookingBloc =>
      _standaloneSendPackageBloc ??= SendPackageBloc();

  Widget _activeSurface() {
    switch (_entry) {
      case _SenderEntryScreen.landing:
        return _SenderPreAuthLanding(
          onCreateAccount: () => setState(() {
            _authMode = _SenderAuthMode.createAccount;
            _entry = _SenderEntryScreen.auth;
          }),
          onSignIn: () => setState(() {
            _authMode = _SenderAuthMode.signIn;
            _entry = _SenderEntryScreen.auth;
          }),
        );
      case _SenderEntryScreen.auth:
        return _SenderAuthEntry(
          mode: _authMode,
          previewAuthEnabled: widget.previewAuthEnabled,
          onBack: () => setState(() => _entry = _SenderEntryScreen.landing),
          onAuthenticated: () =>
              setState(() => _entry = _SenderEntryScreen.app),
          onModeChanged: (mode) => setState(() => _authMode = mode),
        );
      case _SenderEntryScreen.app:
        return KeyedSubtree(
          key: ValueKey('sender-tab-$_index'),
          child: _selectedAppTab(),
        );
    }
  }

  Widget _selectedAppTab() {
    switch (_index) {
      case 0:
        return _CanonicalSenderHome(
          repository: widget.homeRepository,
          onStartDelivery: () => _selectTab(1),
          onOpenActivity: () => _selectTab(2),
          onOpenWallet: () => _selectTab(3),
          onOpenNotifications: _openNotificationCentre,
          onOpenHealth: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const HealthPlusView()),
          ),
          onOpenBusiness: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BusinessAccessView()),
          ),
          onOpenGifts: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const GiftModeView(),
              settings: const RouteSettings(name: GiftModeView.routeName),
            ),
          ),
        );
      case 1:
        final sendTabBuilder = widget.sendTabBuilder;
        if (sendTabBuilder != null) return sendTabBuilder(context);
        return const SenderBookingCanvas();
      case 2:
        return SenderActivityView(
          repository: widget.activityRepository,
          onSendParcel: () => _selectTab(1),
          onExploreGifts: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const GiftModeView(),
              settings: const RouteSettings(name: GiftModeView.routeName),
            ),
          ),
        );
      case 3:
        return SenderWalletView(repository: widget.walletRepository);
      case 4:
        return SenderMobileProfileView(
          repository: widget.profileRepository,
          onOpenWallet: () => _selectTab(3),
          onLoggedOut: () => setState(() {
            _index = 0;
            _entry = _SenderEntryScreen.landing;
          }),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _selectTab(int next) {
    final index = next.clamp(0, senderMobileBottomNavigationLabels.length - 1);
    setState(() => _index = index);
    widget.onTabChanged?.call(index);
  }

  void _openInitialSenderRoute() {
    final routeName = widget.initialRouteName?.trim();
    if (routeName == null || routeName.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _entry != _SenderEntryScreen.app) return;
      switch (routeName) {
        case GiftModeView.routeName:
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const GiftModeView(),
              settings: const RouteSettings(name: GiftModeView.routeName),
            ),
          );
          break;
        case GiftStoryView.routeName:
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GiftStoryView(
                draft:
                    GiftJourneyDraft.forMode(SenderGiftMode.someone).copyWith(
                  linkedGiftDeliveryStatus: 'delivered',
                  riderCompletionAccepted: true,
                  deliveryVerificationCompleted: true,
                  deliveryAuditSuccessful: true,
                ),
              ),
              settings: const RouteSettings(name: GiftStoryView.routeName),
            ),
          );
          break;
      }
    });
  }

  bool _handleNotificationOpen(SenderNotificationOpenRequest request) {
    if (!mounted || _entry != _SenderEntryScreen.app) return false;
    return openSenderNotificationDestination(
      context,
      request.destination,
      onOpenWallet: () => _selectTab(3),
      onOpenNotifications: _openNotificationCentre,
    );
  }

  Future<void> _openNotificationCentre() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SenderNotificationsView(
            onOpenNotification: (notification) {
              openSenderNotificationDestination(
                context,
                notification.destination,
                onOpenWallet: () => _selectTab(3),
              );
            },
          ),
        ),
      );

  Future<void> _restoreAuthenticatedSenderSession() async {
    if (!widget.previewAuthEnabled) return;
    setState(() => _authRestoring = true);
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }
      _authSubscription =
          FirebaseAuth.instance.authStateChanges().listen((user) {
        if (!mounted) return;
        setState(() {
          _authRestoring = false;
          _entry = user == null
              ? _SenderEntryScreen.landing
              : _SenderEntryScreen.app;
        });
      }, onError: (Object error, StackTrace stackTrace) {
        _reportUnexpectedAuthRestoreError(
          error,
          stackTrace,
          'restoring Sender session',
        );
        if (!mounted) return;
        setState(() {
          _authRestoring = false;
          _entry = _SenderEntryScreen.landing;
        });
      });
    } catch (error, stackTrace) {
      _reportUnexpectedAuthRestoreError(
        error,
        stackTrace,
        'configuring Sender session',
      );
      if (!mounted) return;
      setState(() {
        _authRestoring = false;
        _entry = _SenderEntryScreen.landing;
      });
    }
  }

  void _reportUnexpectedAuthRestoreError(
    Object error,
    StackTrace stackTrace,
    String context,
  ) {
    if (_isExpectedAuthRestoreFailure(error)) {
      debugPrint('Sender auth restore recovered: $error');
      return;
    }
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'sender auth',
      context: ErrorDescription(context),
    ));
  }

  bool _isExpectedAuthRestoreFailure(Object error) {
    if (error is FirebaseAuthException) {
      return const {
        'app-deleted',
        'app-not-authorized',
        'invalid-api-key',
        'invalid-app-credential',
        'network-request-failed',
        'operation-not-supported-in-this-environment',
        'timeout',
        'unauthorized-domain',
        'user-disabled',
        'web-storage-unsupported',
      }.contains(error.code);
    }
    if (error is FirebaseException) {
      return error.plugin == 'firebase_auth' &&
          const {
            'network-request-failed',
            'operation-not-supported-in-this-environment',
            'timeout',
            'web-storage-unsupported',
          }.contains(error.code);
    }
    final message = error.toString().toLowerCase();
    return message.contains('network') ||
        message.contains('offline') ||
        message.contains('storage') ||
        message.contains('persistence') ||
        message.contains('auth/network-request-failed') ||
        message.contains('auth/operation-not-supported-in-this-environment') ||
        message.contains('auth/web-storage-unsupported');
  }
}

class _SenderAuthRestoringSplash extends StatelessWidget {
  const _SenderAuthRestoringSplash();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _AmbientOrbs(count: 2),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: _GlassCard(
              padding: const EdgeInsets.all(22),
              child: Semantics(
                label: 'Restoring your Circum Sender session',
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: _SenderTokens.blue,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Restoring your session',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSerifDisplay(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Checking your secure Circum sign-in before loading the app.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: _SenderTokens.softText,
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SenderPreAuthLanding extends StatelessWidget {
  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;

  const _SenderPreAuthLanding({
    required this.onCreateAccount,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _AmbientOrbs(count: 2),
        ListView(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
          children: [
            const _CircumWordmarkRow(),
            const SizedBox(height: 46),
            RichText(
              text: TextSpan(
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontSize: 38,
                  height: 1.12,
                  fontWeight: FontWeight.w700,
                ),
                children: const [
                  TextSpan(text: 'Deliver anything with '),
                  TextSpan(
                    text: 'confidence',
                    style: TextStyle(color: _SenderTokens.blue),
                  ),
                  TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            RichText(
              text: TextSpan(
                style: GoogleFonts.inter(
                  color: _SenderTokens.softText,
                  fontSize: 14.5,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                ),
                children: const [
                  TextSpan(text: 'Fast, trusted delivery powered by '),
                  TextSpan(
                    text: 'IRIS',
                    style: TextStyle(
                      color: _SenderTokens.blue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(text: ' and verified riders.'),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _SenderPrimaryAction(
              label: 'Create account',
              semanticLabel: 'Create account',
              onTap: onCreateAccount,
            ),
            Semantics(
              button: true,
              label: 'Sign in',
              child: TextButton(
                onPressed: onSignIn,
                child: Text(
                  'Sign in',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const _TrustHighlightGrid(),
            const SizedBox(height: 34),
            const _WhyCircumSection(),
            const SizedBox(height: 34),
            const _ServicesPreviewSection(),
            const SizedBox(height: 20),
            const _PreAuthSocialProof(),
          ],
        ),
      ],
    );
  }
}

class _SenderAuthEntry extends StatefulWidget {
  final _SenderAuthMode mode;
  final bool previewAuthEnabled;
  final VoidCallback onBack;
  final VoidCallback onAuthenticated;
  final ValueChanged<_SenderAuthMode> onModeChanged;

  const _SenderAuthEntry({
    required this.mode,
    required this.previewAuthEnabled,
    required this.onBack,
    required this.onAuthenticated,
    required this.onModeChanged,
  });

  @override
  State<_SenderAuthEntry> createState() => _SenderAuthEntryState();
}

class _SenderAuthEntryState extends State<_SenderAuthEntry> {
  final _identity = TextEditingController();
  final _password = TextEditingController();
  var _showErrors = false;
  var _busy = false;
  var _showPassword = false;
  String? _authMessage;

  bool get _isSignIn => widget.mode == _SenderAuthMode.signIn;

  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identityText = _identity.text.trim();
    final identityError = !_showErrors
        ? null
        : identityText.isEmpty
            ? 'Email or phone is required'
            : widget.previewAuthEnabled && !identityText.contains('@')
                ? 'Use an email address for preview auth'
                : null;
    return Stack(
      children: [
        const _AmbientOrbs(count: 1),
        ListView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          children: [
            Row(
              children: [
                _GlassIconChip(
                  icon: Icons.chevron_left_rounded,
                  label: 'Back',
                  onTap: widget.onBack,
                ),
              ],
            ),
            const SizedBox(height: 36),
            _AuthSegmentedControl(
              mode: widget.mode,
              onChanged: (mode) {
                setState(() => _showErrors = false);
                widget.onModeChanged(mode);
              },
            ),
            const SizedBox(height: 26),
            Text(
              _isSignIn
                  ? senderMobileAuthSignInHeadline
                  : senderMobileAuthCreateHeadline,
              style: GoogleFonts.dmSerifDisplay(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isSignIn
                  ? 'Sign in to track deliveries and manage your account.'
                  : 'Create an account to start sending with confidence.',
              style: GoogleFonts.inter(
                color: _SenderTokens.muted,
                fontSize: 13.5,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 26),
            _AuthField(
              controller: _identity,
              label: 'EMAIL OR PHONE',
              hint: 'you@email.com',
              keyboardType: TextInputType.emailAddress,
              errorText: identityError,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            _AuthField(
              controller: _password,
              label: 'PASSWORD',
              hint: _isSignIn ? 'Password' : 'Create a password',
              obscureText: !_showPassword,
              errorText: _showErrors && _password.text.isEmpty
                  ? 'Password is required'
                  : _showErrors && !_isSignIn && _password.text.length < 6
                      ? 'Use at least 6 characters'
                      : null,
              suffix: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _SenderTokens.muted,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            _SenderPrimaryAction(
              label: _busy
                  ? 'Preparing preview...'
                  : _isSignIn
                      ? 'Sign in'
                      : 'Create account',
              semanticLabel: _isSignIn ? 'Sign in' : 'Create account',
              onTap: _busy ? null : () => _submit(),
            ),
            if (_authMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _authMessage!,
                style: GoogleFonts.inter(
                  color: _SenderTokens.muted,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 28),
            _AuthSwitchLine(
              isSignIn: _isSignIn,
              onTap: () {
                setState(() => _showErrors = false);
                widget.onModeChanged(
                  _isSignIn
                      ? _SenderAuthMode.createAccount
                      : _SenderAuthMode.signIn,
                );
              },
            ),
            const SizedBox(height: 22),
            const _AuthFinePrint(),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final validIdentity = _identity.text.trim().isNotEmpty;
    final validPassword =
        _isSignIn ? _password.text.isNotEmpty : _password.text.length >= 6;
    final validPreviewEmail =
        !widget.previewAuthEnabled || _identity.text.trim().contains('@');
    setState(() {
      _showErrors = true;
      _authMessage = null;
    });
    if (!validIdentity || !validPassword || !validPreviewEmail) return;
    if (!widget.previewAuthEnabled) {
      setState(() {
        _authMessage =
            'Authentication handler is not enabled for this production surface.';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await _authenticatePreviewSender(
        email: _identity.text.trim().toLowerCase(),
        password: _password.text,
        createAccount: !_isSignIn,
      );
      widget.onAuthenticated();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _authMessage = _previewAuthMessage(error));
    } catch (error) {
      debugPrint('Sender Mobile preview auth failed: $error');
      if (!mounted) return;
      setState(
        () => _authMessage = 'Preview authentication failed. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _authenticatePreviewSender({
    required String email,
    required String password,
    required bool createAccount,
  }) async {
    final auth = FirebaseAuth.instance;
    if (kIsWeb) {
      await auth.setPersistence(Persistence.LOCAL);
    }
    UserCredential credential;
    if (createAccount) {
      try {
        credential = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (error) {
        if (error.code != 'email-already-in-use') rethrow;
        credential = await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } else {
      credential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    }
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(code: 'preview-no-user');
    }
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('ensureSenderAccount')
        .call();
    await user.getIdToken(true);
  }

  String _previewAuthMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Enter a valid email address for preview auth.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Preview sign-in failed. Check the email and password.';
      case 'weak-password':
        return 'Preview password is too weak.';
      default:
        return 'Preview authentication failed (${error.code}).';
    }
  }
}

class _AmbientOrbs extends StatefulWidget {
  final int count;

  const _AmbientOrbs({required this.count});

  @override
  State<_AmbientOrbs> createState() => _AmbientOrbsState();
}

class _AmbientOrbsState extends State<_AmbientOrbs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_controller.value);
            return Stack(
              children: [
                Positioned(
                  top: -120 + (t * 22),
                  left: -84 + (t * 18),
                  child: const _Orb(size: 270, opacity: .38),
                ),
                if (widget.count > 1)
                  Positioned(
                    top: 118 - (t * 24),
                    right: -92 + (t * 16),
                    child: const _Orb(size: 228, opacity: .28),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final double size;
  final double opacity;

  const _Orb({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 54, sigmaY: 54),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              _SenderTokens.blue.withValues(alpha: opacity),
              _SenderTokens.blue.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircumWordmarkRow extends StatelessWidget {
  const _CircumWordmarkRow();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Circum',
      image: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Image.asset(
          'assets/images/circum_wordmark.png',
          height: 26,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _GlassIconChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GlassIconChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _SenderTokens.glass,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _SenderTokens.glassBorder),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _SenderPrimaryAction extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final VoidCallback? onTap;

  const _SenderPrimaryAction({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: _SenderTokens.blue,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrustHighlightGrid extends StatelessWidget {
  const _TrustHighlightGrid();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.auto_awesome_rounded, 'IRIS'),
      (Icons.shield_outlined, 'Vanguard'),
      (Icons.visibility_outlined, 'Live Tracking'),
      (Icons.person_outline_rounded, 'Trusted Riders'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.18,
      mainAxisExtent: 88,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: [
        for (final item in items)
          _PreAuthGlassCard(icon: item.$1, label: item.$2),
      ],
    );
  }
}

class _PreAuthGlassCard extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PreAuthGlassCard({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: _SenderTokens.glass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _SenderTokens.glassBorder),
          ),
          child: Row(
            children: [
              _MiniIcon(icon: icon, color: _SenderTokens.lightBlue),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
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

class _WhyCircumSection extends StatelessWidget {
  const _WhyCircumSection();

  @override
  Widget build(BuildContext context) {
    return const _PreAuthSection(
      eyebrow: 'BUILT IN',
      children: [
        _BenefitRow(
          icon: Icons.credit_card_rounded,
          title: 'Transparent pricing',
          body: 'Clear costs before you continue.',
        ),
        _BenefitRow(
          icon: Icons.visibility_outlined,
          title: 'Real-time tracking',
          body: 'Follow every step of the journey.',
        ),
        _BenefitRow(
          icon: Icons.shield_outlined,
          title: 'Built for trust',
          body: 'Verified riders and safer handovers.',
        ),
      ],
    );
  }
}

class _ServicesPreviewSection extends StatelessWidget {
  const _ServicesPreviewSection();

  @override
  Widget build(BuildContext context) {
    return const _PreAuthSection(
      eyebrow: 'COMING WITH YOUR ACCOUNT',
      children: [
        _ServicePreviewCard(
          icon: Icons.card_giftcard_rounded,
          title: 'Gifts',
          body: 'Curated gifts delivered with care.',
          accent: _SenderTokens.gifts,
        ),
        _ServicePreviewCard(
          icon: Icons.health_and_safety_rounded,
          title: 'Health+',
          body: 'Trusted prescription and care deliveries.',
          accent: _SenderTokens.health,
        ),
        _ServicePreviewCard(
          icon: Icons.business_center_rounded,
          title: 'Business',
          body: 'Delivery tools for growing teams.',
          accent: _SenderTokens.blue,
        ),
      ],
    );
  }
}

class _PreAuthSection extends StatelessWidget {
  final String eyebrow;
  final List<Widget> children;

  const _PreAuthSection({required this.eyebrow, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: GoogleFonts.jetBrainsMono(
            color: _SenderTokens.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _SenderTokens.hairline)),
      ),
      child: Row(
        children: [
          _MiniIcon(icon: icon, color: _SenderTokens.lightBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: _SenderTokens.muted,
                    fontSize: 12,
                    height: 1.35,
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

class _ServicePreviewCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color accent;

  const _ServicePreviewCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _SenderTokens.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _SenderTokens.hairline),
      ),
      child: Row(
        children: [
          _MiniIcon(icon: icon, color: accent),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: _SenderTokens.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          _AfterJoinPill(accent: accent),
        ],
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _MiniIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .38)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .16), blurRadius: 14),
        ],
      ),
      child: Icon(icon, color: color, size: 18.5),
    );
  }
}

class _AfterJoinPill extends StatelessWidget {
  final Color accent;

  const _AfterJoinPill({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: .24)),
      ),
      child: Text(
        'After you join',
        style: GoogleFonts.jetBrainsMono(
          color: Colors.white.withValues(alpha: .72),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PreAuthSocialProof extends StatelessWidget {
  const _PreAuthSocialProof();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Trusted by people sending everything from forgotten passports to meaningful gifts.',
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        color: _SenderTokens.muted,
        fontSize: 12.5,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _AuthSegmentedControl extends StatelessWidget {
  final _SenderAuthMode mode;
  final ValueChanged<_SenderAuthMode> onChanged;

  const _AuthSegmentedControl({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _SenderTokens.glass,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _SenderTokens.glassBorder),
      ),
      child: Row(
        children: [
          _AuthTab(
            label: 'Sign in',
            active: mode == _SenderAuthMode.signIn,
            onTap: () => onChanged(_SenderAuthMode.signIn),
          ),
          _AuthTab(
            label: 'Create account',
            active: mode == _SenderAuthMode.createAccount,
            onTap: () => onChanged(_SenderAuthMode.createAccount),
          ),
        ],
      ),
    );
  }
}

class _AuthTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _AuthTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? _SenderTokens.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: active ? Colors.white : _SenderTokens.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? errorText;
  final Widget? suffix;
  final ValueChanged<String> onChanged;

  const _AuthField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.errorText,
    this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              color: _SenderTokens.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            onChanged: onChanged,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: hint,
              suffixIcon: suffix,
              hintStyle: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: .34),
              ),
              errorText: errorText,
              errorStyle: GoogleFonts.inter(
                color: const Color(0xFFFCA5A5),
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: _SenderTokens.glass,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _SenderTokens.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _SenderTokens.blue),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFFCA5A5)),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFFCA5A5)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthSwitchLine extends StatelessWidget {
  final bool isSignIn;
  final VoidCallback onTap;

  const _AuthSwitchLine({required this.isSignIn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isSignIn ? 'Create account' : 'Sign in',
      child: GestureDetector(
        onTap: onTap,
        child: Text.rich(
          TextSpan(
            text: isSignIn ? 'New to Circum? ' : 'Already have an account? ',
            style: GoogleFonts.inter(
              color: _SenderTokens.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            children: [
              TextSpan(
                text: isSignIn ? 'Create account' : 'Sign in',
                style: GoogleFonts.inter(
                  color: _SenderTokens.blue,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _AuthFinePrint extends StatelessWidget {
  const _AuthFinePrint();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: 'By continuing, you agree to Circum\'s ',
        style: GoogleFonts.inter(
          color: _SenderTokens.muted,
          fontSize: 11,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text: 'Terms',
            style: GoogleFonts.inter(
              color: _SenderTokens.blue,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: GoogleFonts.inter(
              color: _SenderTokens.blue,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class SenderHomeOrder {
  final String id;
  final String title;
  final String route;
  final String status;
  final String rawStatus;
  final DateTime? updatedAt;
  final DateTime? scheduledAt;
  final bool normalDispatchEligible;

  const SenderHomeOrder({
    required this.id,
    required this.title,
    required this.route,
    required this.status,
    this.rawStatus = '',
    this.updatedAt,
    this.scheduledAt,
    this.normalDispatchEligible = true,
  });

  factory SenderHomeOrder.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final pickup = Map<String, dynamic>.from(
      data['pickupDetails'] as Map? ?? data['pickup'] as Map? ?? const {},
    );
    final dropoff = Map<String, dynamic>.from(
      data['dropoffDetails'] as Map? ?? data['dropoff'] as Map? ?? const {},
    );
    final parcel = Map<String, dynamic>.from(
      data['parcel'] as Map? ?? data['package'] as Map? ?? const {},
    );
    final rawDate = data['updatedAt'] ?? data['createdAt'];
    final scheduleDate = data['scheduledAt'] ??
        data['scheduledFor'] ??
        data['deliveryDate'] ??
        data['pickupDate'];
    final rawStatus =
        '${data['deliveryStatus'] ?? data['status'] ?? 'requested'}';
    final pickupLabel = _firstText([
      pickup['locality'],
      pickup['address'],
      data['pickupLocality'],
    ]);
    final dropoffLabel = _firstText([
      dropoff['locality'],
      dropoff['address'],
      data['destinationLocality'],
    ]);
    return SenderHomeOrder(
      id: id,
      title: _firstText([
        parcel['itemName'],
        parcel['description'],
        data['itemName'],
        data['packageDescription'],
        'Delivery',
      ]),
      route: [pickupLabel, dropoffLabel]
          .where((value) => value.isNotEmpty)
          .join(' → '),
      status: _statusLabel(rawStatus),
      rawStatus: rawStatus.trim().toLowerCase(),
      updatedAt: rawDate is Timestamp ? rawDate.toDate() : null,
      scheduledAt: scheduleDate is Timestamp ? scheduleDate.toDate() : null,
      normalDispatchEligible: _normalDispatchEligibility(data),
    );
  }

  static bool _normalDispatchEligibility(Map<String, dynamic> data) {
    final explicit = data['normalDispatchEligible'];
    if (explicit is bool) return explicit;
    final iris = data['iris'];
    if (iris is! Map) return true;
    final compliance = iris['compliance'] is Map
        ? '${iris['compliance']['status'] ?? ''}'.trim().toLowerCase()
        : '';
    final serviceability = iris['serviceability'] is Map
        ? '${iris['serviceability']['status'] ?? ''}'.trim().toLowerCase()
        : '';
    if (compliance.isEmpty && serviceability.isEmpty) return true;
    return compliance == 'allowed' && serviceability == 'serviceable';
  }

  static String _firstText(List<Object?> values) {
    for (final value in values) {
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  static String _statusLabel(String value) {
    final normalized = value.trim().toLowerCase();
    const labels = {
      'requested': 'Finding a Circum Rider',
      'broadcasting': 'Finding a Circum Rider',
      'accepted': 'Circum Rider assigned',
      'rider_assigned': 'Circum Rider assigned',
      'rider_en_route': 'Circum Rider en route',
      'navigating_to_pickup': 'Circum Rider en route',
      'arrived_at_pickup': 'At pickup',
      'pickup_verified': 'Pickup verified',
      'collected': 'In transit',
      'in_transit': 'In transit',
      'navigating_to_dropoff': 'In transit',
      'arrived_at_dropoff': 'At drop-off',
      'delivered': 'Delivered',
      'completed': 'Delivered',
      'cancelled': 'Cancelled',
      'cancelled_admin': 'Cancelled',
    };
    return labels[normalized] ??
        normalized
            .split('_')
            .where((part) => part.isNotEmpty)
            .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' ');
  }
}

class SenderHomeNotification {
  final String id;
  final String title;
  final String body;
  final bool read;
  final DateTime? createdAt;
  final String type;
  final Map<String, dynamic> destination;

  const SenderHomeNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.read,
    this.type = '',
    this.destination = const <String, dynamic>{},
    this.createdAt,
  });
}

class SenderHomeSummary {
  final String displayName;
  final bool healthProfileExists;
  final int businessAccountCount;
  final int giftCount;
  final int trustPoints;
  final String trustTier;
  final String? nextTrustTier;
  final int pointsToNextTier;

  const SenderHomeSummary({
    required this.displayName,
    required this.healthProfileExists,
    required this.businessAccountCount,
    required this.giftCount,
    this.trustPoints = 0,
    this.trustTier = 'new_sender',
    this.nextTrustTier,
    this.pointsToNextTier = 0,
  });
}

abstract class SenderHomeRepository {
  Future<SenderHomeSummary> loadSummary();
  Stream<List<SenderHomeOrder>> watchRecentOrders();
  Stream<List<SenderHomeNotification>> watchNotifications();
  Future<void> markNotificationsRead(Iterable<String> ids);
}

class FirebaseSenderHomeRepository implements SenderHomeRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  final SenderProfileAuthority profileAuthority;

  FirebaseSenderHomeRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instance,
        profileAuthority = SenderProfileAuthority(
          auth: auth,
          firestore: firestore,
          functions: functions,
        );

  User? get _maybeUser => auth.currentUser;

  @override
  Future<SenderHomeSummary> loadSummary() async {
    final user = _maybeUser;
    if (user == null) {
      return const SenderHomeSummary(
        displayName: '',
        healthProfileExists: false,
        businessAccountCount: 0,
        giftCount: 0,
      );
    }
    final email = (user.email ?? '').trim().toLowerCase();
    final profileSnapshot = await profileAuthority.load('home.summary.profile');
    final results = await Future.wait([
      firestore.collection('healthPlusProfiles').doc(user.uid).get(),
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
      firestore
          .collection('giftRequests')
          .where('senderId', isEqualTo: user.uid)
          .limit(20)
          .get(),
    ]);
    final healthSnapshot = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final ownedSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final teamSnapshot = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final giftsSnapshot = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final profile = profileSnapshot.data;
    final ownedBusinesses = ownedSnapshot.docs.map((doc) => doc.id).toSet();
    final teamBusinesses = teamSnapshot.docs.map((doc) => doc.id).toSet();
    final trustPoints =
        ((profile['senderTrustPoints'] ?? profile['trustPoints']) as num?)
                ?.toInt() ??
            (profile['trustScore'] as num?)?.toInt() ??
            0;
    final trustTier = SenderTrustPolicy.normalizeTier(
      profile['senderTier'] ?? profile['trustTier'],
      points: trustPoints,
    );
    final backendNextTier = '${profile['nextTier'] ?? ''}'.trim();
    final nextTier = backendNextTier.isNotEmpty
        ? SenderTrustPolicy.normalizeTier(backendNextTier)
        : SenderTrustPolicy.nextTier(trustTier);
    return SenderHomeSummary(
      displayName: '${profile['displayName'] ?? user.displayName ?? ''}'.trim(),
      healthProfileExists: healthSnapshot.exists,
      businessAccountCount:
          <String>{...ownedBusinesses, ...teamBusinesses}.length,
      giftCount: giftsSnapshot.docs.length,
      trustPoints: trustPoints,
      trustTier: trustTier,
      nextTrustTier: nextTier,
      pointsToNextTier: (profile['pointsToNextTier'] as num?)?.toInt() ??
          SenderTrustPolicy.pointsForNextTier(trustPoints),
    );
  }

  @override
  Stream<List<SenderHomeOrder>> watchRecentOrders() {
    final user = _maybeUser;
    if (user == null) return Stream.value(const <SenderHomeOrder>[]);
    final uid = user.uid;
    return firestore
        .collection('deliveryRequests')
        .where('senderId', isEqualTo: uid)
        .limit(20)
        .snapshots()
        .map((snapshot) {
      final orders = snapshot.docs
          .map((doc) => SenderHomeOrder.fromFirestore(doc.id, doc.data()))
          .toList();
      orders.sort((a, b) => (b.updatedAt ?? DateTime(1970))
          .compareTo(a.updatedAt ?? DateTime(1970)));
      return orders.take(2).toList(growable: false);
    });
  }

  @override
  Stream<List<SenderHomeNotification>> watchNotifications() {
    final user = _maybeUser;
    if (user == null) return Stream.value(const <SenderHomeNotification>[]);
    final uid = user.uid;
    return firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map((doc) {
        final data = doc.data();
        final rawDate = data['createdAt'];
        final nested = data['data'] is Map
            ? Map<String, dynamic>.from(data['data'] as Map)
            : const <String, dynamic>{};
        final rawDestination = data['destination'] ?? nested['destination'];
        return SenderHomeNotification(
          id: doc.id,
          title: '${data['title'] ?? 'Circum update'}'.trim(),
          body: '${data['body'] ?? data['message'] ?? ''}'.trim(),
          read: data['read'] == true,
          type: '${data['type'] ?? ''}'.trim(),
          destination: rawDestination is Map
              ? Map<String, dynamic>.from(rawDestination)
              : const <String, dynamic>{},
          createdAt: rawDate is Timestamp ? rawDate.toDate() : null,
        );
      }).toList();
      return items;
    });
  }

  @override
  Future<void> markNotificationsRead(Iterable<String> ids) async {
    if (_maybeUser == null) return;
    final cleanIds =
        ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
    if (cleanIds.isEmpty) return;
    await functions.httpsCallable('updateSenderNotificationState').call({
      'action': 'mark_read',
      'notificationIds': cleanIds,
    });
  }
}

class _CanonicalSenderHome extends StatefulWidget {
  final SenderHomeRepository? repository;
  final VoidCallback onStartDelivery;
  final VoidCallback onOpenGifts;
  final VoidCallback onOpenWallet;
  final VoidCallback onOpenHealth;
  final VoidCallback onOpenBusiness;
  final VoidCallback onOpenActivity;
  final VoidCallback onOpenNotifications;

  const _CanonicalSenderHome({
    required this.repository,
    required this.onStartDelivery,
    required this.onOpenGifts,
    required this.onOpenWallet,
    required this.onOpenHealth,
    required this.onOpenBusiness,
    required this.onOpenActivity,
    required this.onOpenNotifications,
  });

  @override
  State<_CanonicalSenderHome> createState() => _CanonicalSenderHomeState();
}

class _CanonicalSenderHomeState extends State<_CanonicalSenderHome> {
  static const _retiredGuardCopyMarkers = ['Quick services', 'Send Parcel'];

  late final SenderHomeRepository _repository;
  StreamSubscription<List<SenderHomeOrder>>? _ordersSubscription;
  StreamSubscription<List<SenderHomeNotification>>? _notificationsSubscription;
  SenderHomeSummary? _summary;
  List<SenderHomeOrder>? _orders;
  List<SenderHomeNotification>? _notifications;
  String? _summaryError;
  String? _ordersError;
  String? _notificationsError;
  Set<String>? _knownNotificationIds;

  @override
  void initState() {
    super.initState();
    assert(_retiredGuardCopyMarkers.length == 2);
    _repository = widget.repository ?? FirebaseSenderHomeRepository();
    _load();
  }

  void _load() {
    setState(() {
      _summaryError = null;
      _ordersError = null;
      _notificationsError = null;
    });
    _repository.loadSummary().then((summary) {
      if (mounted) setState(() => _summary = summary);
    }).catchError((Object error) {
      if (mounted) setState(() => _summaryError = '$error');
    });
    _ordersSubscription?.cancel();
    _ordersSubscription = _repository.watchRecentOrders().listen((orders) {
      if (mounted) setState(() => _orders = orders);
    }, onError: (Object error) {
      if (mounted) setState(() => _ordersError = '$error');
    });
    _notificationsSubscription?.cancel();
    _notificationsSubscription =
        _repository.watchNotifications().listen((notifications) {
      if (!mounted) return;
      final previous = _knownNotificationIds;
      _knownNotificationIds = notifications.map((item) => item.id).toSet();
      setState(() => _notifications = notifications);
      if (previous != null) {
        final fresh = notifications.where(
          (item) => !item.read && !previous.contains(item.id),
        );
        if (fresh.isNotEmpty) {
          final item = fresh.first;
          SenderAccessibilityScope.maybeOf(context)
              ?.announceNotification('${item.title}. ${item.body}');
        }
      }
    }, onError: (Object error) {
      if (mounted) setState(() => _notificationsError = '$error');
    });
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _notificationsSubscription?.cancel();
    super.dispose();
  }

  String get _firstName {
    final name = _summary?.displayName.trim() ?? '';
    if (name.isNotEmpty) return name.split(RegExp(r'\s+')).first;
    var authName = '';
    try {
      authName = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    } catch (_) {
      authName = '';
    }
    if (authName.isNotEmpty) return authName.split(RegExp(r'\s+')).first;
    return 'there';
  }

  int get _unreadCount =>
      _notifications?.where((item) => !item.read).length ?? 0;

  List<SenderHomeNotification> get _importantUnreadNotifications =>
      (_notifications ?? const [])
          .where((item) => !item.read)
          .where((item) {
            final type = item.type.toLowerCase();
            return type.contains('delivery') ||
                type.contains('payment') ||
                type.contains('wallet') ||
                type.contains('support') ||
                type.contains('health') ||
                type.contains('gift') ||
                type.contains('trust') ||
                type.contains('vanguard') ||
                type.contains('iris') ||
                item.destination.isNotEmpty;
          })
          .take(2)
          .toList(growable: false);

  List<SenderHomeOrder> get _qualifyingOrders => (_orders ?? const [])
      .where((order) => order.normalDispatchEligible)
      .where((order) => _isHomeDeliveryStatus(order.rawStatus))
      .toList(growable: false);

  SenderHomeOrder? get _activeDelivery {
    for (final order in _qualifyingOrders) {
      if (_activeDeliveryStatuses.contains(order.rawStatus)) return order;
    }
    return null;
  }

  SenderHomeOrder? get _scheduledDraft {
    final scheduled = _qualifyingOrders
        .where((order) => order.rawStatus == 'scheduled')
        .toList()
      ..sort((a, b) => (a.scheduledAt ?? DateTime(9999))
          .compareTo(b.scheduledAt ?? DateTime(9999)));
    return scheduled.isEmpty ? null : scheduled.first;
  }

  static const _activeDeliveryStatuses = {
    'requested',
    'broadcasting',
    'finding_rider',
    'accepted',
    'rider_assigned',
    'rider_en_route',
    'navigating_to_pickup',
    'arrived_at_pickup',
    'pickup_verified',
    'collected',
    'in_transit',
    'navigating_to_dropoff',
    'arrived_at_dropoff',
    'pin_required',
  };

  static bool _isHomeDeliveryStatus(String status) {
    return {
      ..._activeDeliveryStatuses,
      'scheduled',
      'delivered',
      'completed',
    }.contains(status);
  }

  @override
  Widget build(BuildContext context) {
    final activeDelivery = _activeDelivery;
    final scheduledDraft = activeDelivery == null ? _scheduledDraft : null;
    final heroTitle = activeDelivery != null
        ? activeDelivery.status
        : scheduledDraft != null
            ? 'Continue ${scheduledDraft.title}'
            : 'Send a parcel';
    final heroBody = activeDelivery != null
        ? activeDelivery.route
        : scheduledDraft != null
            ? scheduledDraft.route
            : 'Fast, trusted delivery powered by IRIS and verified riders.';
    final heroButton = activeDelivery != null
        ? 'Track delivery'
        : scheduledDraft != null
            ? 'Continue'
            : 'Send now';
    return SenderScrollablePageShell(
      key: const Key('sender-home-canonical-content'),
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-.72, -.92),
          radius: 1.25,
          colors: [
            Color(0x332E7DF7),
            Color(0x220B1D42),
            _SenderTokens.bg,
          ],
          stops: [0, .42, 1],
        ),
      ),
      children: [
        _RebuiltSenderHomeHeader(
          firstName: _firstName == 'there' ? 'Ayo' : _firstName,
          unreadCount: _unreadCount,
          hasNotificationError: _notificationsError != null,
          onOpenNotifications: widget.onOpenNotifications,
        ),
        const SizedBox(height: 28),
        _RebuiltSenderHomeHero(
          title: heroTitle,
          body: heroBody.isEmpty ? senderMobileHeroSubtitle : heroBody,
          button: heroButton,
          loading: _orders == null && _ordersError == null,
          activeDelivery: activeDelivery != null,
          onPrimaryTap: activeDelivery != null
              ? widget.onOpenActivity
              : scheduledDraft != null
                  ? widget.onStartDelivery
                  : widget.onStartDelivery,
        ),
        if (activeDelivery != null) ...[
          const SizedBox(height: 18),
          _RebuiltSenderActiveDeliveryCard(
            delivery: activeDelivery,
            onTap: widget.onOpenActivity,
          ),
        ],
        const SizedBox(height: 38),
        const _RebuiltSenderSectionTitle('Your Circum'),
        const SizedBox(height: 18),
        _RebuiltSenderServicesGrid(
          children: [
            _RebuiltSenderServiceCard(
              title: 'Health+',
              status: _summaryError != null ? 'Unavailable' : '',
              description: _summaryError != null
                  ? 'Try again shortly.'
                  : 'Book medical and healthcare deliveries.',
              icon: Icons.medical_services_outlined,
              accent: _SenderTokens.health,
              onTap: widget.onOpenHealth,
            ),
            _RebuiltSenderServiceCard(
              title: 'Business',
              status: _summaryError != null ? 'Unavailable' : '',
              description: _summaryError != null
                  ? 'Try again shortly.'
                  : 'Manage deliveries and invoices.',
              icon: Icons.business_center_outlined,
              accent: _SenderTokens.business,
              onTap: widget.onOpenBusiness,
            ),
            _RebuiltSenderServiceCard(
              title: 'Gifts',
              status: _summaryError != null ? 'Unavailable' : '',
              description: _summaryError != null
                  ? 'Try again shortly.'
                  : 'Thoughtful gifting powered by Circum.',
              icon: Icons.card_giftcard_rounded,
              accent: _SenderTokens.gifts,
              onTap: widget.onOpenGifts,
            ),
          ],
        ),
        const SizedBox(height: 38),
        const _RebuiltSenderSectionTitle('Recent Activity'),
        const SizedBox(height: 16),
        _RebuiltSenderRecentActivity(
          orders: _orders,
          qualifyingOrders: _qualifyingOrders,
          error: _ordersError,
          onRetry: _load,
          onOpenActivity: widget.onOpenActivity,
          onStartDelivery: widget.onStartDelivery,
        ),
        const SizedBox(height: 20),
        _RebuiltSenderNotificationStrip(
          notifications: _importantUnreadNotifications,
          loading: _notifications == null && _notificationsError == null,
          hasError: _notificationsError != null,
          onOpenNotifications: widget.onOpenNotifications,
        ),
      ],
    );
  }
}

class _RebuiltSenderHomeHeader extends StatelessWidget {
  final String firstName;
  final int unreadCount;
  final bool hasNotificationError;
  final VoidCallback onOpenNotifications;

  const _RebuiltSenderHomeHeader({
    required this.firstName,
    required this.unreadCount,
    required this.hasNotificationError,
    required this.onOpenNotifications,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 8),
          child: child,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Good morning,',
                  style: TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  firstName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _HomeNotificationBell(
            unreadCount: unreadCount,
            hasError: hasNotificationError,
            onTap: onOpenNotifications,
          ),
        ],
      ),
    );
  }
}

class _RebuiltSenderHomeHero extends StatelessWidget {
  final String title;
  final String body;
  final String button;
  final bool loading;
  final bool activeDelivery;
  final VoidCallback onPrimaryTap;

  const _RebuiltSenderHomeHero({
    required this.title,
    required this.body,
    required this.button,
    required this.loading,
    required this.activeDelivery,
    required this.onPrimaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 16),
          child: child,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
          boxShadow: [
            BoxShadow(
              color: _SenderTokens.blue.withValues(alpha: .30),
              blurRadius: 54,
              spreadRadius: 3,
              offset: const Offset(0, 26),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(34),
          child: InkWell(
            borderRadius: BorderRadius.circular(34),
            onTap: onPrimaryTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 292),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E5BBA),
                    Color(0xFF123A77),
                    Color(0xFF0B1D48),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .22)),
              ),
              child: Stack(
                children: [
                  const Positioned.fill(child: _RebuiltHeroLineArt()),
                  const Positioned(
                    right: 38,
                    bottom: 36,
                    child: _RebuiltHeroParticles(),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        loading
                            ? 'Checking your deliveries'
                            : activeDelivery
                                ? 'Live delivery'
                                : 'Ready when you are',
                        style: const TextStyle(
                          color: Color(0xFFD5E8FF),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            height: 1.02,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Text(
                          body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFE3F0FF),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      FilledButton.icon(
                        onPressed: onPrimaryTap,
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(button),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF123A77),
                          minimumSize: const Size(152, 50),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
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
      ),
    );
  }
}

class _RebuiltHeroLineArt extends StatelessWidget {
  const _RebuiltHeroLineArt();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: .20,
      child: CustomPaint(
        painter: _RebuiltHeroLinePainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RebuiltHeroLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: .46);
    final path = Path()
      ..moveTo(size.width * .10, size.height * .74)
      ..cubicTo(
        size.width * .36,
        size.height * .52,
        size.width * .52,
        size.height * .86,
        size.width * .82,
        size.height * .36,
      );
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(size.width * .82, size.height * .36),
      6,
      Paint()..color = Colors.white.withValues(alpha: .62),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RebuiltHeroParticles extends StatelessWidget {
  const _RebuiltHeroParticles();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 180,
      height: 120,
      child: Stack(
        children: [
          Positioned(
            left: 18,
            top: 12,
            child: _RebuiltParticle(size: 5, opacity: .60),
          ),
          Positioned(
            right: 32,
            top: 20,
            child: _RebuiltParticle(size: 8, opacity: .42),
          ),
          Positioned(
            left: 78,
            bottom: 22,
            child: _RebuiltParticle(size: 6, opacity: .52),
          ),
        ],
      ),
    );
  }
}

class _RebuiltParticle extends StatelessWidget {
  final double size;
  final double opacity;

  const _RebuiltParticle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _SenderTokens.iris.withValues(alpha: opacity),
            blurRadius: 14,
          ),
        ],
      ),
      child: SizedBox(width: size, height: size),
    );
  }
}

class _RebuiltSenderServicesGrid extends StatelessWidget {
  final List<Widget> children;

  const _RebuiltSenderServicesGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i != children.length - 1) const SizedBox(width: 18),
            ],
          ],
        );
      },
    );
  }
}

class _RebuiltSenderActiveDeliveryCard extends StatelessWidget {
  final SenderHomeOrder delivery;
  final VoidCallback onTap;

  const _RebuiltSenderActiveDeliveryCard({
    required this.delivery,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _RebuiltSenderPanel(
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.route_rounded, color: Color(0xFF7AB8FF), size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  delivery.status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  delivery.route.isEmpty ? delivery.title : delivery.route,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB8C6DD),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white70),
        ],
      ),
    );
  }
}

class _RebuiltSenderSectionTitle extends StatelessWidget {
  final String title;

  const _RebuiltSenderSectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _RebuiltSenderServiceCard extends StatelessWidget {
  final String title;
  final String status;
  final String description;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _RebuiltSenderServiceCard({
    required this.title,
    required this.status,
    required this.description,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _RebuiltSenderPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        height: 135,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withValues(alpha: .24)),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: .18),
                        blurRadius: 22,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: accent, size: 25),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white70,
                  size: 25,
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (status.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFC0CEE5),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RebuiltSenderRecentActivity extends StatelessWidget {
  final List<SenderHomeOrder>? orders;
  final List<SenderHomeOrder> qualifyingOrders;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onOpenActivity;
  final VoidCallback onStartDelivery;

  const _RebuiltSenderRecentActivity({
    required this.orders,
    required this.qualifyingOrders,
    required this.error,
    required this.onRetry,
    required this.onOpenActivity,
    required this.onStartDelivery,
  });

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return _RebuiltSenderPanel(
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Activity is taking longer than usual.',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (orders == null) {
      return const _RebuiltSenderPanel(
        child: Text(
          'Loading recent activity...',
          style:
              TextStyle(color: Color(0xFFB8C6DD), fontWeight: FontWeight.w700),
        ),
      );
    }
    if (qualifyingOrders.isEmpty) {
      return _RebuiltSenderPanel(
        onTap: onOpenActivity,
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: _SenderTokens.blue.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _SenderTokens.lightBlue.withValues(alpha: .25),
                ),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: _SenderTokens.lightBlue,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No deliveries yet',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Your completed deliveries will appear here.',
                    style: TextStyle(
                      color: Color(0xFFB8C6DD),
                      fontSize: 13,
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
    final recent = qualifyingOrders.take(3).toList(growable: false);
    return Column(
      children: [
        for (final order in recent) ...[
          _RebuiltSenderPanel(
            onTap: onOpenActivity,
            child: Row(
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  color: Color(0xFF7AB8FF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        order.route.isEmpty ? order.status : order.route,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB8C6DD),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white60),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _RebuiltSenderNotificationStrip extends StatelessWidget {
  final List<SenderHomeNotification> notifications;
  final bool loading;
  final bool hasError;
  final VoidCallback onOpenNotifications;

  const _RebuiltSenderNotificationStrip({
    required this.notifications,
    required this.loading,
    required this.hasError,
    required this.onOpenNotifications,
  });

  @override
  Widget build(BuildContext context) {
    if (hasError || loading || notifications.isEmpty) {
      return const SizedBox.shrink();
    }
    final item = notifications.first;
    return _RebuiltSenderPanel(
      onTap: onOpenNotifications,
      child: Row(
        children: [
          const Icon(Icons.notifications_active_outlined,
              color: Color(0xFF7AB8FF)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB8C6DD),
                    fontSize: 12,
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

class _RebuiltSenderPanel extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const _RebuiltSenderPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  State<_RebuiltSenderPanel> createState() => _RebuiltSenderPanelState();
}

class _RebuiltSenderPanelState extends State<_RebuiltSenderPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: const Color(0xD4101A2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: _hovered ? .18 : .10),
          ),
          boxShadow: [
            BoxShadow(
              color: _SenderTokens.blue.withValues(alpha: _hovered ? .18 : .08),
              blurRadius: _hovered ? 34 : 20,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: widget.onTap,
            child: Padding(
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SenderDashboard extends StatefulWidget {
  final VoidCallback onStartDelivery;
  final VoidCallback onOpenGifts;
  final VoidCallback onOpenWallet;
  final VoidCallback onOpenHealth;
  final VoidCallback onOpenBusiness;
  final VoidCallback onOpenActivity;

  const _SenderDashboard({
    required this.onStartDelivery,
    required this.onOpenGifts,
    required this.onOpenWallet,
    required this.onOpenHealth,
    required this.onOpenBusiness,
    required this.onOpenActivity,
  });

  @override
  State<_SenderDashboard> createState() => _SenderDashboardState();
}

class _SenderDashboardState extends State<_SenderDashboard> {
  late final SenderHomeRepository _repository;
  StreamSubscription<List<SenderHomeOrder>>? _ordersSubscription;
  StreamSubscription<List<SenderHomeNotification>>? _notificationsSubscription;
  SenderHomeSummary? _summary;
  List<SenderHomeOrder>? _orders;
  List<SenderHomeNotification>? _notifications;
  String? _summaryError;
  String? _ordersError;
  String? _notificationsError;
  Set<String>? _knownNotificationIds;

  @override
  void initState() {
    super.initState();
    _repository = FirebaseSenderHomeRepository();
    _load();
  }

  void _load() {
    setState(() {
      _summaryError = null;
      _ordersError = null;
      _notificationsError = null;
    });
    _repository.loadSummary().then((summary) {
      if (mounted) setState(() => _summary = summary);
    }).catchError((Object error) {
      if (mounted) setState(() => _summaryError = '$error');
    });
    _ordersSubscription?.cancel();
    _ordersSubscription = _repository.watchRecentOrders().listen((orders) {
      if (mounted) setState(() => _orders = orders);
    }, onError: (Object error) {
      if (mounted) setState(() => _ordersError = '$error');
    });
    _notificationsSubscription?.cancel();
    _notificationsSubscription =
        _repository.watchNotifications().listen((notifications) {
      if (!mounted) return;
      final previous = _knownNotificationIds;
      _knownNotificationIds = notifications.map((item) => item.id).toSet();
      setState(() => _notifications = notifications);
      if (previous != null) {
        final fresh = notifications.where(
          (item) => !item.read && !previous.contains(item.id),
        );
        if (fresh.isNotEmpty) {
          final item = fresh.first;
          SenderAccessibilityScope.maybeOf(context)
              ?.announceNotification('${item.title}. ${item.body}');
        }
      }
    }, onError: (Object error) {
      if (mounted) setState(() => _notificationsError = '$error');
    });
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _notificationsSubscription?.cancel();
    super.dispose();
  }

  String get _firstName {
    final name = _summary?.displayName.trim() ?? '';
    if (name.isNotEmpty) return name.split(RegExp(r'\s+')).first;
    final user = FirebaseAuth.instance.currentUser;
    final authName = user?.displayName?.trim() ?? '';
    if (authName.isNotEmpty) return authName.split(RegExp(r'\s+')).first;
    return 'there';
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  int get _unreadCount =>
      _notifications?.where((item) => !item.read).length ?? 0;

  List<SenderHomeOrder> get _dashboardOrders => (_orders ?? const [])
      .where((order) => _isDashboardDeliveryStatus(order.rawStatus))
      .toList(growable: false);

  String get _heroContext {
    final active = _dashboardOrders.where((order) {
      return const {
        'requested',
        'broadcasting',
        'finding_rider',
        'accepted',
        'rider_assigned',
        'rider_en_route',
        'navigating_to_pickup',
        'arrived_at_pickup',
        'pickup_verified',
        'collected',
        'in_transit',
        'navigating_to_dropoff',
        'arrived_at_dropoff',
        'pin_required',
      }.contains(order.rawStatus);
    }).toList();
    if (active.isNotEmpty) {
      return '${active.length} active deliver${active.length == 1 ? 'y' : 'ies'}';
    }
    final scheduled = _dashboardOrders
        .where((order) => order.rawStatus == 'scheduled')
        .toList()
      ..sort((a, b) => (a.scheduledAt ?? DateTime(9999))
          .compareTo(b.scheduledAt ?? DateTime(9999)));
    if (scheduled.isNotEmpty && scheduled.first.scheduledAt != null) {
      final date = scheduled.first.scheduledAt!;
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final time =
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      if (date.year == tomorrow.year &&
          date.month == tomorrow.month &&
          date.day == tomorrow.day) {
        return 'Next delivery tomorrow at $time';
      }
      return 'Next delivery ${date.day}/${date.month} at $time';
    }
    return 'Ready when you are.';
  }

  SenderHomeNotification? get _unreadChatNotification {
    final activeIds = _dashboardOrders
        .where((order) => const {
              'requested',
              'broadcasting',
              'finding_rider',
              'accepted',
              'rider_assigned',
              'rider_en_route',
              'navigating_to_pickup',
              'arrived_at_pickup',
              'pickup_verified',
              'collected',
              'in_transit',
              'navigating_to_dropoff',
              'arrived_at_dropoff',
              'pin_required',
            }.contains(order.rawStatus))
        .map((order) => order.id)
        .toSet();
    for (final notification in _notifications ?? const []) {
      if (notification.read) continue;
      final route = '${notification.destination['route'] ?? ''}'.trim();
      final chatId = '${notification.destination['chatId'] ?? ''}'.trim();
      if ((route == 'conversation' || notification.type == 'chat_message') &&
          chatId.isNotEmpty &&
          activeIds.contains(chatId)) {
        return notification;
      }
    }
    return null;
  }

  static bool _isDashboardDeliveryStatus(String status) {
    return const {
      'requested',
      'broadcasting',
      'finding_rider',
      'scheduled',
      'accepted',
      'rider_assigned',
      'rider_en_route',
      'navigating_to_pickup',
      'arrived_at_pickup',
      'pickup_verified',
      'collected',
      'in_transit',
      'navigating_to_dropoff',
      'arrived_at_dropoff',
      'pin_required',
      'delivered',
      'completed',
    }.contains(status);
  }

  Future<void> _openNotifications() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SenderNotificationsView(
            onOpenNotification: _openNotificationDestination,
          ),
        ),
      );

  void _openNotificationDestination(CircumNotification notification) {
    openSenderNotificationDestination(
      context,
      notification.destination,
      onOpenWallet: () {
        Navigator.of(context).pop();
        widget.onOpenWallet();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('sender-home-canonical-content'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Row(
          children: [
            Image.asset(
              'assets/images/circum_logo.png',
              height: 30,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
            const Spacer(),
            _HomeNotificationBell(
              unreadCount: _unreadCount,
              hasError: _notificationsError != null,
              onTap: _notifications == null ? null : _openNotifications,
            ),
            const SizedBox(width: 10),
            _SenderAvatar(
                imageUrl: FirebaseAuth.instance.currentUser?.photoURL),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          _summaryError == null ? '$_greeting, $_firstName' : 'Welcome back',
          style: TextStyle(
            color: Colors.white,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 18),
        _HeroSendCard(
          onTap: widget.onStartDelivery,
          orderCount: _dashboardOrders.length,
          hasError: _ordersError != null,
          contextStatus: _heroContext,
        ),
        if (_unreadChatNotification != null) ...[
          const SizedBox(height: 12),
          _ActiveConversationCard(
            notification: _unreadChatNotification!,
            onTap: () {
              final chatId =
                  '${_unreadChatNotification!.destination['chatId'] ?? ''}'
                      .trim();
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    RideChatPageView(chatId: chatId.isEmpty ? null : chatId),
              ));
            },
          ),
        ],
        const SizedBox(height: 18),
        _YourCircumHub(
          onOpenGifts: widget.onOpenGifts,
          onOpenHealth: widget.onOpenHealth,
          onOpenBusiness: widget.onOpenBusiness,
          summary: _summary,
          hasError: _summaryError != null,
        ),
        const SizedBox(height: 16),
        _RecentOrdersCard(
          orders: _orders,
          qualifyingOrders: _dashboardOrders,
          error: _ordersError,
          onRetry: _load,
          onOpenActivity: widget.onOpenActivity,
          onStartDelivery: widget.onStartDelivery,
        ),
        const SizedBox(height: 16),
        SenderWalletHomeSummary(onOpenWallet: widget.onOpenWallet),
      ],
    );
  }
}

class _HomeNotificationBell extends StatefulWidget {
  final int unreadCount;
  final bool hasError;
  final VoidCallback? onTap;

  const _HomeNotificationBell({
    required this.unreadCount,
    required this.hasError,
    required this.onTap,
  });

  @override
  State<_HomeNotificationBell> createState() => _HomeNotificationBellState();
}

class _HomeNotificationBellState extends State<_HomeNotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _HomeNotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (widget.unreadCount > 0) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        SenderAccessibilityScope.maybeOf(context)?.settings.reduceMotion ??
            false;
    final showDot = widget.unreadCount > 0 && !widget.hasError;
    final icon = _IconGlassButton(
      icon: Icons.notifications_none_rounded,
      onTap: widget.onTap,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (widget.unreadCount > 9 || widget.hasError)
          Badge(
            isLabelVisible: true,
            label: Text(widget.hasError ? '!' : '9+'),
            child: icon,
          )
        else
          icon,
        if (showDot)
          Positioned(
            top: 1,
            right: 1,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Transform.scale(
                scale: reduceMotion ? 1 : 1 + (_pulse.value * .12),
                child: child,
              ),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: _SenderTokens.bg, width: 1.5),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActiveConversationCard extends StatelessWidget {
  final SenderHomeNotification notification;
  final VoidCallback onTap;

  const _ActiveConversationCard({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => _GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _SenderTokens.blue.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.forum_outlined,
                color: _SenderTokens.lightBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Active conversation',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(
                notification.body.isEmpty
                    ? 'You have an unread delivery message.'
                    : notification.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: _SenderTokens.muted, fontSize: 12),
              ),
            ]),
          ),
          TextButton(onPressed: onTap, child: const Text('Open Chat')),
        ]),
      );
}

class _HeroSendCard extends StatelessWidget {
  final VoidCallback onTap;
  final int? orderCount;
  final bool hasError;
  final String contextStatus;

  const _HeroSendCard({
    required this.onTap,
    required this.orderCount,
    required this.hasError,
    required this.contextStatus,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: EdgeInsets.zero,
      radius: 32,
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 268),
          padding: const EdgeInsets.fromLTRB(26, 30, 26, 28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _SenderTokens.midnight.withValues(alpha: .94),
                _SenderTokens.blue.withValues(alpha: .42),
                _SenderTokens.bg,
              ],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: _HeroRouteArt()),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .25),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _SenderTokens.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        color: _SenderTokens.lightBlue,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasError
                            ? 'Orders unavailable'
                            : orderCount == null
                                ? 'Loading orders'
                                : '$orderCount recent',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(left: 0, top: 2, child: _IrisOrb(size: 58)),
              Positioned(
                left: 0,
                right: 118,
                bottom: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Send a parcel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 14),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          color: Color(0xFFD8E7FF),
                          height: 1.35,
                          fontSize: 14,
                        ),
                        children: [
                          TextSpan(
                            text:
                                'From collection to delivery, every step protected by ',
                          ),
                          TextSpan(
                            text: 'IRIS',
                            style: TextStyle(
                              color: _SenderTokens.blue,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          TextSpan(text: '.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      contextStatus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: _SenderTokens.blue.withValues(alpha: .28),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Send now',
                            style: TextStyle(
                              color: _SenderTokens.bg,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: _SenderTokens.blue,
                            size: 18,
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
    );
  }
}

class _YourCircumHub extends StatelessWidget {
  final VoidCallback onOpenGifts;
  final VoidCallback onOpenHealth;
  final VoidCallback onOpenBusiness;
  final SenderHomeSummary? summary;
  final bool hasError;

  const _YourCircumHub({
    required this.onOpenGifts,
    required this.onOpenHealth,
    required this.onOpenBusiness,
    required this.summary,
    required this.hasError,
  });

  String _detail(String ready, String empty) {
    if (hasError) return 'Unavailable right now';
    if (summary == null) return 'Loading…';
    return ready.isEmpty ? empty : ready;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Circum',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ServiceCard(
                title: 'Health+',
                subtitle: _detail(
                  'Book medical and healthcare deliveries.',
                  'Book medical and healthcare deliveries.',
                ),
                icon: Icons.health_and_safety_rounded,
                accent: _SenderTokens.health,
                onTap: onOpenHealth,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ServiceCard(
                title: 'Business',
                subtitle: _detail(
                  'Manage deliveries and invoices.',
                  'Manage deliveries and invoices.',
                ),
                icon: Icons.business_center_rounded,
                accent: _SenderTokens.business,
                onTap: onOpenBusiness,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ServiceCard(
                title: 'Gifts',
                subtitle: hasError
                    ? 'Unavailable right now'
                    : summary == null
                        ? 'Loading…'
                        : 'Thoughtful gifting powered by Circum.',
                icon: Icons.card_giftcard_rounded,
                accent: _SenderTokens.gifts,
                onTap: onOpenGifts,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ServiceCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  const _ServiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _pressed ? 1.02 : 1,
        child: _GlassCard(
          radius: 24,
          padding: const EdgeInsets.all(12),
          child: AspectRatio(
            aspectRatio: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                widget.title == 'Gifts'
                    ? const SenderGiftsIcon()
                    : _ServiceIcon(icon: widget.icon, accent: widget.accent),
                const Spacer(),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .1,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _SenderTokens.muted,
                    height: 1.22,
                    fontSize: 11.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: widget.accent,
                    size: 18,
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

class _ServiceIcon extends StatelessWidget {
  final IconData icon;
  final Color accent;

  const _ServiceIcon({required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .38)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 18),
        ],
      ),
      child: Icon(icon, color: accent, size: 24),
    );
  }
}

class _HeroRouteArt extends StatelessWidget {
  const _HeroRouteArt();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HeroRoutePainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _HeroRoutePainter extends CustomPainter {
  const _HeroRoutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .035)
      ..strokeWidth = 1;
    for (var x = size.width * .42; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x - 16, size.height), grid);
    }
    for (var y = 8.0; y < size.height; y += 28) {
      canvas.drawLine(
        Offset(size.width * .38, y),
        Offset(size.width, y + 6),
        grid,
      );
    }
    final start = Offset(size.width * .58, size.height * .70);
    final end = Offset(size.width * .90, size.height * .38);
    final route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        size.width * .66,
        size.height * .36,
        size.width * .82,
        size.height * .86,
        end.dx,
        end.dy,
      );
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = _SenderTokens.iris.withValues(alpha: .72),
    );
    _dot(canvas, start, _SenderTokens.blue);
    _dot(canvas, end, _SenderTokens.health);
  }

  void _dot(Canvas canvas, Offset point, Color color) {
    canvas.drawCircle(point, 16, Paint()..color = color.withValues(alpha: .11));
    canvas.drawCircle(point, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HeroRoutePainter oldDelegate) => false;
}

class _RecentOrdersCard extends StatelessWidget {
  final List<SenderHomeOrder>? orders;
  final List<SenderHomeOrder> qualifyingOrders;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onOpenActivity;
  final VoidCallback onStartDelivery;

  const _RecentOrdersCard({
    required this.orders,
    required this.qualifyingOrders,
    required this.error,
    required this.onRetry,
    required this.onOpenActivity,
    required this.onStartDelivery,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenActivity,
            child: const Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent orders',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Recent deliveries',
                        style: TextStyle(color: _SenderTokens.muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: _SenderTokens.muted),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (error != null)
            _HomeInlineState(
              message: _isOffline(error!)
                  ? 'Recent orders are unavailable offline.'
                  : 'Recent orders could not load.',
              action: onRetry,
            )
          else if (orders == null)
            const _HomeInlineState(message: 'Loading recent orders…')
          else if (qualifyingOrders.isEmpty)
            _HomeInlineState(
              message: 'No recent deliveries.',
              action: onStartDelivery,
              actionLabel: 'Send a Parcel',
            )
          else
            ...qualifyingOrders.map(
              (order) => _OrderLine(
                title: order.title,
                subtitle: order.route.isEmpty ? 'Circum delivery' : order.route,
                status: order.status,
                icon: Icons.local_shipping_outlined,
                accent: _SenderTokens.business,
              ),
            ),
        ],
      ),
    );
  }

  static bool _isOffline(String value) {
    final lower = value.toLowerCase();
    return lower.contains('unavailable') || lower.contains('network');
  }
}

class _HomeInlineState extends StatelessWidget {
  final String message;
  final VoidCallback? action;
  final String actionLabel;

  const _HomeInlineState({
    required this.message,
    this.action,
    this.actionLabel = 'Retry',
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: _SenderTokens.muted,
                  height: 1.4,
                ),
              ),
            ),
            if (action != null)
              TextButton(onPressed: action, child: Text(actionLabel)),
          ],
        ),
      );
}

class _OrderLine extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final IconData icon;
  final Color accent;

  const _OrderLine({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _SenderTokens.border),
      ),
      child: Row(
        children: [
          _ServiceIcon(icon: icon, accent: accent),
          const SizedBox(width: 12),
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
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: _SenderTokens.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _SenderTokens.health.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _SenderTokens.health.withValues(alpha: .32),
              ),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: _SenderTokens.health,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SenderBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _SenderBottomNav({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF20A1020),
        border: const Border(top: BorderSide(color: _SenderTokens.border)),
        boxShadow: [
          BoxShadow(
            color: _SenderTokens.blue.withValues(alpha: .14),
            blurRadius: 30,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: SenderUiBaseline.navigation.safeAreaMinimum,
        child: Row(
          children: [
            _NavItem(
              index: 0,
              selected: index,
              icon: Icons.home_rounded,
              label: 'Home',
              onTap: onChanged,
            ),
            _NavItem(
              index: 1,
              selected: index,
              icon: Icons.near_me_rounded,
              label: 'Send',
              onTap: onChanged,
            ),
            _NavItem(
              index: 2,
              selected: index,
              icon: Icons.route_rounded,
              label: 'Activity',
              onTap: onChanged,
            ),
            _NavItem(
              index: 3,
              selected: index,
              icon: Icons.account_balance_wallet_rounded,
              label: 'Wallet',
              onTap: onChanged,
            ),
            _NavItem(
              index: 4,
              selected: index,
              icon: Icons.person_rounded,
              label: 'Profile',
              onTap: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final int selected;
  final IconData icon;
  final String label;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.index,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = index == selected;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onTap(index),
        child: AnimatedContainer(
          duration: SenderUiBaseline.motion.standard,
          curve: SenderUiBaseline.motion.curve,
          margin: SenderUiBaseline.navigation.itemMargin,
          padding: SenderUiBaseline.navigation.itemPadding,
          decoration: BoxDecoration(
            color: active
                ? _SenderTokens.blue.withValues(alpha: .12)
                : Colors.transparent,
            borderRadius:
                BorderRadius.circular(SenderUiBaseline.radius.navItem),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: _SenderTokens.blue.withValues(alpha: .24),
                      blurRadius: SenderUiBaseline.shadows.selectedNavBlur,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: active ? _SenderTokens.lightBlue : _SenderTokens.muted,
              ),
              const SizedBox(height: SenderUiBaseline.navIconLabelGap),
              Text(
                label,
                style: TextStyle(
                  color: active ? _SenderTokens.lightBlue : _SenderTokens.muted,
                  fontSize: SenderUiBaseline.navigation.labelSize,
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

class _SenderAvatar extends StatelessWidget {
  final String? imageUrl;

  const _SenderAvatar({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _SenderTokens.midnight.withValues(alpha: .82),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _NeutralAvatarIcon(),
            )
          : const _NeutralAvatarIcon(),
    );
  }
}

class _NeutralAvatarIcon extends StatelessWidget {
  const _NeutralAvatarIcon();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _SenderTokens.midnight.withValues(alpha: .62),
      ),
      child: const Center(
        child: Icon(
          Icons.person_outline_rounded,
          color: Color(0xFFD8E7FF),
          size: 25,
        ),
      ),
    );
  }
}

class _IconGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _IconGlassButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      radius: 16,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) => AppGlassContainer(
        padding: padding,
        radius: radius,
        accent: AppTokens.primary,
        child: child,
      );
}

class _IrisOrb extends StatefulWidget {
  final double size;

  const _IrisOrb({this.size = 48});

  @override
  State<_IrisOrb> createState() => _IrisOrbState();
}

class _IrisOrbState extends State<_IrisOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [
                _SenderTokens.iris,
                _SenderTokens.vanguard,
                _SenderTokens.bg,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _SenderTokens.iris.withValues(
                  alpha: .22 + _controller.value * .12,
                ),
                blurRadius: 24,
              ),
            ],
          ),
          child: Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: widget.size * .42,
          ),
        );
      },
    );
  }
}

class _SenderMapBackdrop extends StatefulWidget {
  final bool active;

  const _SenderMapBackdrop({required this.active});

  @override
  State<_SenderMapBackdrop> createState() => _SenderMapBackdropState();
}

class _SenderMapBackdropState extends State<_SenderMapBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _SenderMapPainter(t: _controller.value, active: widget.active),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SenderMapPainter extends CustomPainter {
  final double t;
  final bool active;

  const _SenderMapPainter({required this.t, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_SenderTokens.bg, _SenderTokens.midnight],
        ).createShader(rect),
    );

    final drift = math.sin(t * math.pi * 2) * 10;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = 1;
    for (var x = -80.0 + drift; x < size.width + 80; x += 52) {
      canvas.drawLine(Offset(x, 0), Offset(x + 26, size.height), grid);
    }
    for (var y = -80.0 - drift; y < size.height + 80; y += 58) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 18), grid);
    }

    final pickup = Offset(size.width * .26, size.height * .34);
    final dropoff = Offset(size.width * .78, size.height * .22);
    final route = Path()
      ..moveTo(pickup.dx, pickup.dy)
      ..cubicTo(
        size.width * .28,
        size.height * .14,
        size.width * .62,
        size.height * .44,
        dropoff.dx,
        dropoff.dy,
      );
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = _SenderTokens.lightBlue.withValues(alpha: active ? .7 : .22),
    );
    _pin(canvas, pickup, _SenderTokens.blue, t);
    _pin(canvas, dropoff, const Color(0xFF22C55E), (t + .45) % 1);
  }

  void _pin(Canvas canvas, Offset point, Color color, double phase) {
    canvas.drawCircle(
      point,
      8 + phase * 20,
      Paint()..color = color.withValues(alpha: .15 * (1 - phase)),
    );
    canvas.drawCircle(point, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SenderMapPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.active != active;
}

class _SenderTokens {
  static const bg = Color(0xFF07090F);
  static const midnight = Color(0xFF0B1020);
  static const blue = Color(0xFF3B82F6);
  static const lightBlue = Color(0xFF60A5FA);
  static const vanguard = Color(0xFF2563EB);
  static const iris = Color(0xFF38BDF8);
  static const health = Color(0xFF22C55E);
  static const business = Color(0xFF94A3B8);
  static const gifts = Color(0xFFE8B4A0);
  static const muted = Color(0xFF9CA3AF);
  static const softText = Color(0xB8F5F7FB);
  static const panel = Color(0xFF0D111C);
  static const hairline = Color(0x14F5F7FB);
  static const border = Color(0x29FFFFFF);
  static const glass = Color(0x0DF5F7FB);
  static const glassBorder = Color(0x1AF5F7FB);
}
