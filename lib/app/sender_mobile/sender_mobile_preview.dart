import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../firebase_options.dart';
import '../../env/env.dart';
import '../security/circum_app_check.dart';
import '../send_package/bloc/send_package_bloc.dart';
import 'design_system/sender_design_system.dart';
import 'gift_mode_view.dart';
import 'gift_story_view.dart';
import 'sender_accessibility.dart';
import 'sender_mobile_home.dart';
import 'sender_startup_diagnostics.dart';

Future<void> main() async {
  SenderStartupDiagnostics.installGlobalHandlers();
  await runZonedGuarded<Future<void>>(_startSenderWeb, (error, stackTrace) {
    SenderStartupDiagnostics.instance.fail(
      'runZonedGuarded',
      error,
      stackTrace,
    );
    if (!_senderAppStarted) {
      _runSenderApp(const _SenderWebStartupRecovery());
    }
  });
}

var _senderAppStarted = false;
var _firebaseInitialized = false;
var _authInitialized = false;
var _firestoreConnected = false;
var _functionsConnected = false;
var _appCheckState = 'Not started';
var _stripeReady = false;

const _optionalStartupTimeout = Duration(seconds: 4);
const _requiredStartupTimeout = Duration(seconds: 12);

Future<void> _startSenderWeb() async {
  final diagnostics = SenderStartupDiagnostics.instance;
  diagnostics.start('Flutter initialization');
  WidgetsFlutterBinding.ensureInitialized();
  diagnostics.complete('Flutter initialization');

  diagnostics.start('runApp(boot)');
  _runSenderApp(const _SenderWebStartupLoading());
  diagnostics.complete('runApp(boot)');

  _stripeReady = await _runOptionalStartupStep(
    'Stripe initialization',
    _configureStripe,
    timeout: _optionalStartupTimeout,
  );
  _refreshRuntimeHealth();

  if (kIsWeb) {
    final firebaseReady = await _runRequiredStartupStep(
      'Core services initialization',
      () => Firebase.initializeApp(options: DefaultFirebaseOptions.web),
      timeout: _requiredStartupTimeout,
    );
    if (!firebaseReady) return;
    _firebaseInitialized = true;
    _refreshRuntimeHealth();

    _appCheckState = 'Starting';
    _refreshRuntimeHealth();
    final appCheckStartup = await _runRequiredStartupValue(
      'Service protection initialization',
      initializeCircumAppCheck,
      timeout: _requiredStartupTimeout,
    );
    if (appCheckStartup == null) {
      _appCheckState = 'Startup failed';
      _refreshRuntimeHealth();
      return;
    }
    if (appCheckStartup.blockStartup) {
      _appCheckState = 'Blocking failure';
      diagnostics.fail(
        'Service protection initialization',
        appCheckStartup.message,
        StackTrace.current,
      );
      _refreshRuntimeHealth();
      return;
    }
    _appCheckState = 'Ready';
    _refreshRuntimeHealth();

    final authReady = await _runRequiredStartupStep(
      'Authentication initialization',
      () async => FirebaseAuth.instance,
      timeout: _requiredStartupTimeout,
    );
    if (!authReady) return;
    _authInitialized = true;
    _refreshRuntimeHealth();

    final firestoreReady = await _runRequiredStartupStep(
      'Data service initialization',
      () async => FirebaseFirestore.instance,
      timeout: _requiredStartupTimeout,
    );
    if (!firestoreReady) return;
    _firestoreConnected = true;
    _refreshRuntimeHealth();

    final functionsReady = await _runRequiredStartupStep(
      'Secure service connection',
      () async => FirebaseFunctions.instance,
      timeout: _requiredStartupTimeout,
    );
    if (!functionsReady) return;
    _functionsConnected = true;
    _refreshRuntimeHealth();
  } else {
    final firebaseReady = await _runRequiredStartupStep(
      'Core services initialization',
      Firebase.initializeApp,
      timeout: _requiredStartupTimeout,
    );
    if (!firebaseReady) return;
    _firebaseInitialized = true;
    _refreshRuntimeHealth();
  }

  diagnostics.start('runApp()');
  _runSenderApp(const SenderMobilePreviewApp());
  diagnostics.complete('runApp()');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    diagnostics.completeOnce('First frame rendered');
    _refreshRuntimeHealth();
  });
}

Future<void> _configureStripe() async {
  final key = Env.stripePublishableKey.trim();
  if (key.isEmpty) return;
  Stripe.publishableKey = key;
  await Stripe.instance.applySettings();
}

Future<bool> _runOptionalStartupStep(
  String stage,
  Future<void> Function() step, {
  required Duration timeout,
}) async {
  final diagnostics = SenderStartupDiagnostics.instance;
  diagnostics.start(stage);
  try {
    await step().timeout(timeout);
    diagnostics.complete(stage);
    return true;
  } catch (error, stackTrace) {
    diagnostics.fail(stage, error, stackTrace);
    return false;
  }
}

Future<bool> _runRequiredStartupStep<T>(
  String stage,
  Future<T> Function() step, {
  required Duration timeout,
}) async {
  final result = await _runRequiredStartupValue(stage, step, timeout: timeout);
  return result != null;
}

Future<T?> _runRequiredStartupValue<T>(
  String stage,
  Future<T> Function() step, {
  required Duration timeout,
}) async {
  final diagnostics = SenderStartupDiagnostics.instance;
  diagnostics.start(stage);
  try {
    final result = await step().timeout(timeout);
    diagnostics.complete(stage);
    return result;
  } catch (error, stackTrace) {
    diagnostics.fail(stage, error, stackTrace);
    _runSenderStartupRecovery();
    return null;
  }
}

void _runSenderStartupRecovery() {
  _runSenderApp(const _SenderWebStartupRecovery());
}

void _runSenderApp(Widget app) {
  _senderAppStarted = true;
  runApp(app);
}

void _refreshRuntimeHealth() {
  var authenticated = false;
  if (_authInitialized) {
    try {
      authenticated = FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      authenticated = false;
    }
  }
  SenderStartupDiagnostics.instance.updateHealth(
    SenderRuntimeHealthSnapshot(
      buildHash: senderBuildHash,
      releaseTag: senderReleaseTag,
      firebaseInitialized: _firebaseInitialized,
      appCheckState: _appCheckState,
      authInitialized: _authInitialized,
      firestoreConnected: _firestoreConnected,
      functionsConnected: _functionsConnected,
      mapsReady: false,
      stripeReady: _stripeReady,
      authenticated: authenticated,
    ),
  );
}

class SenderMobilePreviewApp extends StatelessWidget {
  const SenderMobilePreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    SenderStartupDiagnostics.instance.start('Router construction');
    final initialRouteName = _initialSenderRouteName(Uri.base);
    final initialIndex =
        int.tryParse(Uri.base.queryParameters['tab'] ?? '')?.clamp(0, 4) ?? 0;
    final home = SenderMobileHome(
      initialAuthenticated: false,
      senderAuthEnabled: true,
      initialIndex: initialIndex,
      initialRouteName: initialRouteName,
    );
    SenderStartupDiagnostics.instance.completeOnce('Router construction');
    return BlocProvider(
      create: (_) => SendPackageBloc(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        initialRoute: Navigator.defaultRouteName,
        routes: {Navigator.defaultRouteName: (_) => home},
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute<void>(
            builder: (_) => home,
            settings: const RouteSettings(name: Navigator.defaultRouteName),
          ),
        ],
        theme: AppTheme.dark(),
        builder: (context, child) {
          return Stack(
            children: [
              SenderAccessibilityHost(
                repository: const _PreviewSenderAccessibilityRepository(),
                child: child ?? const SizedBox.shrink(),
              ),
              const SenderRuntimeHealthPanel(),
            ],
          );
        },
      ),
    );
  }
}

String? _initialSenderRouteName(Uri uri) {
  final fragment = uri.fragment.trim();
  if (fragment == GiftModeView.routeName ||
      fragment == '#${GiftModeView.routeName}') {
    return GiftModeView.routeName;
  }
  if (fragment == GiftStoryView.routeName ||
      fragment == '#${GiftStoryView.routeName}') {
    return GiftStoryView.routeName;
  }
  return null;
}

class _PreviewSenderAccessibilityRepository
    implements SenderAccessibilityRepository {
  const _PreviewSenderAccessibilityRepository();

  @override
  Future<void> save(SenderAccessibilitySettings settings) async {}

  @override
  Stream<SenderAccessibilitySettings> watch() =>
      Stream.value(const SenderAccessibilitySettings());
}

class _SenderWebStartupLoading extends StatelessWidget {
  const _SenderWebStartupLoading();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Circum Sender',
      home: Scaffold(
        backgroundColor: const Color(0xFF07090F),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF60A5FA)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x663B82F6), blurRadius: 28),
                    ],
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF93C5FD),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Starting Circum',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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

class _SenderWebStartupRecovery extends StatelessWidget {
  const _SenderWebStartupRecovery();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Circum Sender',
      home: Scaffold(
        backgroundColor: const Color(0xFF07090F),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "We're having trouble starting Circum.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Please try again.\n\nIf the problem continues,\ncontact support.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFD6E4FF),
                        fontSize: 16,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        _senderAppStarted = false;
                        unawaited(_startSenderWeb());
                      },
                      child: const Text('Retry'),
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
