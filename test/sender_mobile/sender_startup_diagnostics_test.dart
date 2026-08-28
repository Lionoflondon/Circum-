import 'dart:io';

import 'package:circum/app/sender_mobile/sender_startup_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender startup diagnostics records failed stages with metadata', () {
    final diagnostics = SenderStartupDiagnostics.instance;
    final before = diagnostics.records.length;

    diagnostics.fail(
      'test stage',
      StateError('startup failed'),
      StackTrace.current,
    );

    final record = diagnostics.records.skip(before).single;
    expect(record.stage, 'test stage');
    expect(record.status, SenderStartupStageStatus.failed);
    expect(record.exception, contains('startup failed'));
    expect(record.timestamp.isUtc, isTrue);
    expect(record.platform, isNotEmpty);
  });

  test('Sender runtime health can be updated without exposing customer UI', () {
    final diagnostics = SenderStartupDiagnostics.instance;
    diagnostics.updateHealth(
      const SenderRuntimeHealthSnapshot(
        buildHash: 'abc123',
        releaseTag: 'rc1.1',
        firebaseInitialized: true,
        appCheckState: 'Ready',
        authInitialized: true,
        firestoreConnected: true,
        functionsConnected: true,
        mapsReady: false,
        stripeReady: false,
        authenticated: false,
      ),
    );

    expect(diagnostics.health.buildHash, 'abc123');
    expect(diagnostics.health.releaseTag, 'rc1.1');
    expect(diagnostics.health.appCheckState, 'Ready');
    expect(diagnostics.health.firebaseInitialized, isTrue);
  });

  test('production diagnostics copy is provider-neutral', () {
    final diagnosticsSource = File(
      'lib/app/sender_mobile/sender_startup_diagnostics.dart',
    ).readAsStringSync();
    final previewSource = File(
      'lib/app/sender_mobile/sender_mobile_preview.dart',
    ).readAsStringSync();

    final visibleSources = [
      diagnosticsSource,
      previewSource,
    ].join('\n');

    expect(visibleSources, contains('Core services'));
    expect(visibleSources, contains('Data service'));
    expect(visibleSources, contains('Service protection'));
    expect(visibleSources, contains('Secure service connection'));
    expect(visibleSources, isNot(contains("'Firebase'")));
    expect(visibleSources, isNot(contains("'Firestore'")));
    expect(visibleSources, isNot(contains("'App Check'")));
    expect(visibleSources, isNot(contains("'Backend'")));
    expect(visibleSources, isNot(contains("'Callable initialization'")));
  });
}
