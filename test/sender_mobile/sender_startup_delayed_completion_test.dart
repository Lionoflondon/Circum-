import 'dart:async';

import 'package:circum/app/sender_mobile/sender_startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('slow native success reaches app without a false failure',
      (tester) async {
    final native = Completer<void>();
    final frames = <String>[];
    final start = runSenderStartup(
      renderBoot: () => frames.add('boot'),
      initialize: () => native.future,
      renderSlow: () => frames.add('slow'),
      renderApp: () => frames.add('app'),
      renderRecovery: () => frames.add('failure'),
      onFailure: (_, __, ___) => fail('elapsed time is not a native failure'),
    );
    await tester.pump(const Duration(seconds: 21));
    expect(frames, ['boot', 'slow']);
    native.complete();
    await tester.pump();
    await start;
    expect(frames, ['boot', 'slow', 'app']);
  });

  testWidgets('a real error after a slow start remains fail-visible',
      (tester) async {
    final native = Completer<void>();
    final frames = <String>[];
    Object? recorded;
    final start = runSenderStartup(
      renderBoot: () => frames.add('boot'),
      initialize: () => native.future,
      renderSlow: () => frames.add('slow'),
      renderApp: () => fail('failed initialization must not render app'),
      renderRecovery: () => frames.add('failure'),
      onFailure: (_, error, __) => recorded = error,
    );
    await tester.pump(const Duration(seconds: 21));
    final error = StateError('native Firebase error');
    native.completeError(error);
    await tester.pump();
    await start;
    expect(frames, ['boot', 'slow', 'failure']);
    expect(recorded, same(error));
  });

  testWidgets('healthy startup cancels the slow-start message', (tester) async {
    var slow = 0;
    await runSenderStartup(
      renderBoot: () {},
      initialize: () async {},
      renderSlow: () => slow++,
      renderApp: () {},
      renderRecovery: () => fail('healthy start'),
    );
    await tester.pump(const Duration(seconds: 21));
    expect(slow, 0);
  });

  test('concurrent retry joins native initialization and releases on success',
      () async {
    final attempt = SenderStartupAttempt();
    final native = Completer<void>();
    var starts = 0;
    Future<void> initialize() {
      starts++;
      return native.future;
    }

    final first = attempt.run(initialize);
    final retry = attempt.run(initialize);
    expect(identical(first, retry), isTrue);
    expect(starts, 1);
    native.complete();
    await first;
    await attempt.run(() async => starts++);
    expect(starts, 2);
  });

  test('failed attempt permits a genuine retry', () async {
    final attempt = SenderStartupAttempt();
    await expectLater(
        attempt.run(() async => throw StateError('native')), throwsStateError);
    var recovered = false;
    await attempt.run(() async => recovered = true);
    expect(recovered, isTrue);
  });
}
