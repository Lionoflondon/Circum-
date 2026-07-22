import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'sender_startup_diagnostics_web.dart'
    if (dart.library.io) 'sender_startup_diagnostics_stub.dart' as web_hooks;

const senderBuildHash = String.fromEnvironment('CIRCUM_BUILD_HASH');
const senderReleaseTag = String.fromEnvironment('CIRCUM_RELEASE_TAG');
const senderDiagnosticsPanelEnabled =
    bool.fromEnvironment('CIRCUM_WEB_DIAGNOSTICS_PANEL');

enum SenderStartupStageStatus { started, completed, failed }

@immutable
class SenderStartupDiagnosticRecord {
  const SenderStartupDiagnosticRecord({
    required this.stage,
    required this.status,
    required this.timestamp,
    required this.buildHash,
    required this.releaseTag,
    required this.browser,
    required this.platform,
    this.exception,
    this.stackTrace,
  });

  final String stage;
  final SenderStartupStageStatus status;
  final DateTime timestamp;
  final String buildHash;
  final String releaseTag;
  final String browser;
  final String platform;
  final String? exception;
  final String? stackTrace;

  bool get failed => status == SenderStartupStageStatus.failed;
}

class SenderRuntimeHealthSnapshot {
  const SenderRuntimeHealthSnapshot({
    required this.buildHash,
    required this.releaseTag,
    required this.firebaseInitialized,
    required this.appCheckState,
    required this.authInitialized,
    required this.firestoreConnected,
    required this.functionsConnected,
    required this.mapsReady,
    required this.stripeReady,
    required this.authenticated,
  });

  final String buildHash;
  final String releaseTag;
  final bool firebaseInitialized;
  final String appCheckState;
  final bool authInitialized;
  final bool firestoreConnected;
  final bool functionsConnected;
  final bool mapsReady;
  final bool stripeReady;
  final bool authenticated;
}

class SenderStartupDiagnostics extends ChangeNotifier {
  SenderStartupDiagnostics._();

  static final SenderStartupDiagnostics instance = SenderStartupDiagnostics._();

  final List<SenderStartupDiagnosticRecord> _records = [];
  final Set<String> _completedStages = {};

  SenderRuntimeHealthSnapshot _health = const SenderRuntimeHealthSnapshot(
    buildHash: senderBuildHash,
    releaseTag: senderReleaseTag,
    firebaseInitialized: false,
    appCheckState: 'Not started',
    authInitialized: false,
    firestoreConnected: false,
    functionsConnected: false,
    mapsReady: false,
    stripeReady: false,
    authenticated: false,
  );

  List<SenderStartupDiagnosticRecord> get records =>
      List.unmodifiable(_records);
  SenderRuntimeHealthSnapshot get health => _health;

  static bool get panelEnabled => kDebugMode || senderDiagnosticsPanelEnabled;

  static void installGlobalHandlers() {
    FlutterError.onError = (details) {
      instance.fail(
        'FlutterError.onError',
        details.exception,
        details.stack,
      );
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      instance.fail('PlatformDispatcher.instance.onError', error, stack);
      return false;
    };

    web_hooks.installSenderWebErrorHooks(
      (stage, error, stack) => instance.fail(stage, error, stack),
    );
  }

  void start(String stage) {
    _record(stage: stage, status: SenderStartupStageStatus.started);
  }

  void complete(String stage) {
    _completedStages.add(stage);
    _record(stage: stage, status: SenderStartupStageStatus.completed);
  }

  void completeOnce(String stage) {
    if (_completedStages.contains(stage)) return;
    complete(stage);
  }

  void fail(String stage, Object error, StackTrace? stackTrace) {
    _record(
      stage: stage,
      status: SenderStartupStageStatus.failed,
      exception: error.toString(),
      stackTrace: stackTrace?.toString(),
    );
  }

  void updateHealth(SenderRuntimeHealthSnapshot next) {
    _health = next;
    notifyListeners();
  }

  void _record({
    required String stage,
    required SenderStartupStageStatus status,
    Object? exception,
    String? stackTrace,
  }) {
    _records.add(SenderStartupDiagnosticRecord(
      stage: stage,
      status: status,
      timestamp: DateTime.now().toUtc(),
      buildHash: senderBuildHash,
      releaseTag: senderReleaseTag,
      browser: web_hooks.senderBrowserDescription(),
      platform: defaultTargetPlatform.name,
      exception: exception?.toString(),
      stackTrace: stackTrace,
    ));
    notifyListeners();
    if (kDebugMode && status == SenderStartupStageStatus.failed) {
      debugPrint('Sender startup diagnostic failed at $stage: $exception');
    }
  }
}

class SenderRuntimeHealthPanel extends StatelessWidget {
  const SenderRuntimeHealthPanel({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SenderStartupDiagnostics.panelEnabled) {
      return const SizedBox.shrink();
    }
    return Positioned(
      right: 12,
      top: MediaQuery.of(context).padding.top + 12,
      child: AnimatedBuilder(
        animation: SenderStartupDiagnostics.instance,
        builder: (context, _) {
          final health = SenderStartupDiagnostics.instance.health;
          final failures = SenderStartupDiagnostics.instance.records
              .where((record) => record.failed)
              .length;
          return Semantics(
            label: 'Sender runtime health diagnostics',
            child: Material(
              color: const Color(0xEE07111F),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 280,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x553B82F6)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.35,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Runtime Health',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _HealthLine('Build', _short(health.buildHash)),
                      _HealthLine('Release', _value(health.releaseTag)),
                      _HealthLine(
                          'Firebase', _yesNo(health.firebaseInitialized)),
                      _HealthLine('App Check', health.appCheckState),
                      _HealthLine('Auth', _yesNo(health.authInitialized)),
                      _HealthLine('Signed in', _yesNo(health.authenticated)),
                      _HealthLine(
                          'Firestore', _yesNo(health.firestoreConnected)),
                      _HealthLine(
                          'Functions', _yesNo(health.functionsConnected)),
                      _HealthLine('Maps', _yesNo(health.mapsReady)),
                      _HealthLine('Stripe', _yesNo(health.stripeReady)),
                      _HealthLine('Startup failures', '$failures'),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String _yesNo(bool value) => value ? 'Ready' : 'Not ready';
  static String _value(String value) =>
      value.trim().isEmpty ? 'unknown' : value;
  static String _short(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'unknown';
    return trimmed.length <= 12 ? trimmed : trimmed.substring(0, 12);
  }
}

class _HealthLine extends StatelessWidget {
  const _HealthLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF93C5FD)),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
