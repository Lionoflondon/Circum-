import 'dart:async';

import 'package:circum/app/sender_mobile/sender_startup.dart';
import 'package:circum/main.dart' show CircumStartupBlocked;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an unanswered notification prompt cannot block login', () async {
    final permission = Completer<void>();
    var appRendered = false;
    await runSenderStartup(
      renderBoot: () {},
      initialize: () async {},
      renderApp: () => appRendered = true,
      renderRecovery: () => fail('permission must not block startup'),
      afterRenderApp: () => permission.future,
    );
    expect(appRendered, isTrue);
    permission.complete();
  });

  test('notification initialization failure preserves the rendered app',
      () async {
    var appFrames = 0;
    var recoveryFrames = 0;
    Object? recordedError;
    await runSenderStartup(
      renderBoot: () {},
      initialize: () async {},
      renderApp: () => appFrames++,
      renderRecovery: () => recoveryFrames++,
      afterRenderApp: () async => throw StateError('notification permission'),
      onFailure: (stage, error, stack) {
        expect(stage, 'notifications');
        recordedError = error;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(appFrames, 1);
    expect(recoveryFrames, 0);
    expect(recordedError, isA<StateError>());
  });

  test('core initialization failure keeps app protected and records evidence',
      () async {
    final failure = StateError('Firebase initialization');
    var notificationRuns = 0;
    var recoveryFrames = 0;
    Object? recordedError;
    await runSenderStartup(
      renderBoot: () {},
      initialize: () async => throw failure,
      renderApp: () => fail('Firebase is required'),
      renderRecovery: () => recoveryFrames++,
      afterRenderApp: () async => notificationRuns++,
      onFailure: (stage, error, stack) {
        expect(stage, 'core');
        recordedError = error;
        expect(stack.toString(), isNotEmpty);
      },
    );
    expect(recoveryFrames, 1);
    expect(notificationRuns, 0);
    expect(recordedError, same(failure));
  });

  testWidgets(
      'pending notification permission remains harmless beyond boot deadline',
      (tester) async {
    final permission = Completer<void>();
    var appFrames = 0;
    var recoveryFrames = 0;
    final startup = runSenderStartup(
      renderBoot: () {},
      initialize: () async {},
      renderApp: () => appFrames++,
      renderRecovery: () => recoveryFrames++,
      afterRenderApp: () => permission.future,
    );
    await tester.pump();
    await startup;
    await tester.pump(const Duration(seconds: 21));
    expect(appFrames, 1);
    expect(recoveryFrames, 0);
    permission.complete();
    await tester.pump();
  });

  testWidgets('core recovery gives the user a working retry action',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(CircumStartupBlocked(
      message: 'Circum could not start. Please try again.',
      onRetry: () async => retries++,
    ));
    expect(
        find.text('Circum could not start. Please try again.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pump();
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });
}
