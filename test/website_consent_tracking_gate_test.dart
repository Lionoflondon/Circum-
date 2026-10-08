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
}
