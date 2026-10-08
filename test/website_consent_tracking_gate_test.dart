import 'dart:async';
import 'package:circum/website/shared/privacy/consent_tracking_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first visit and rejection never initialise or request analytics',
      () async {
    var started = false;
    var recorded = false;
    await runConsentedAnalytics(
        allowed: () => false,
        prepare: () async => started = true,
        record: () async => recorded = true);
    expect(started, isFalse);
    expect(recorded, isFalse);
  });
  test('acceptance starts analytics after provider readiness', () async {
    final events = <String>[];
    await runConsentedAnalytics(
        allowed: () => true,
        prepare: () async => events.add('ready'),
        record: () async => events.add('visit'));
    expect(events, ['ready', 'visit']);
  });
  test('withdrawal or expiry during startup blocks later requests', () async {
    var allowed = true;
    var recorded = false;
    final startup = Completer<void>();
    final operation = runConsentedAnalytics(
        allowed: () => allowed,
        prepare: () => startup.future,
        record: () async => recorded = true);
    allowed = false;
    startup.complete();
    await operation;
    expect(recorded, isFalse);
  });

  test('provider startup failure never records or retries analytics', () async {
    var preparations = 0;
    var recordings = 0;
    final failure = StateError('provider unavailable');
    await expectLater(
      runConsentedAnalytics(
        allowed: () => true,
        prepare: () async {
          preparations++;
          throw failure;
        },
        record: () async => recordings++,
      ),
      throwsA(same(failure)),
    );
    expect(preparations, 1);
    expect(recordings, 0);
  });

  test('visitor endpoint failure makes one attempt without retrying', () async {
    var preparations = 0;
    var recordings = 0;
    final failure = StateError('HTTP 500');
    await expectLater(
      runConsentedAnalytics(
        allowed: () => true,
        prepare: () async => preparations++,
        record: () async {
          recordings++;
          throw failure;
        },
      ),
      throwsA(same(failure)),
    );
    expect(preparations, 1);
    expect(recordings, 1);
  });
}
