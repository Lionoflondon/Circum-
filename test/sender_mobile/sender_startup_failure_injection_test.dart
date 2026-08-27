import 'dart:async';
import 'dart:io';

import 'package:circum/app/sender_mobile/sender_startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> expectRecovery(Future<void> Function() failure) async {
    var normalFrames = 0;
    var recoveryFrames = 0;
    await runSenderStartup(
      renderBoot: () {},
      initialize: failure,
      renderApp: () => normalFrames++,
      renderRecovery: () => recoveryFrames++,
    );
    expect(normalFrames, 0);
    expect(recoveryFrames, 1);
  }

  test('Firebase failure is fail-visible', () async {
    await expectRecovery(() async => throw StateError('firebase'));
  });

  test('Stripe failure is fail-visible', () async {
    await expectRecovery(() async => throw StateError('stripe'));
  });

  test('notifications failure is fail-visible', () async {
    await expectRecovery(() async => throw StateError('notifications'));
  });

  test('App Check failure is fail-visible', () async {
    await expectRecovery(() async => throw StateError('app-check'));
  });

  test('multiple dependency failures still render one recovery state',
      () async {
    await expectRecovery(() async {
      try {
        throw StateError('firebase');
      } finally {
        throw StateError('app-check');
      }
    });
  });

  test('synchronous startup failure is fail-visible', () async {
    await expectRecovery(() => throw StateError('sync'));
  });

  test('async startup failure is fail-visible', () async {
    await expectRecovery(() async {
      await Future<void>.value();
      throw StateError('async');
    });
  });

  test('recovery rendering does not depend on startup services', () async {
    var recoveryFrames = 0;
    await runSenderStartup(
      renderBoot: () {},
      initialize: () async => throw StateError('startup'),
      renderApp: () => fail('normal app must not render'),
      renderRecovery: () => recoveryFrames++,
    );
    expect(recoveryFrames, 1);
  });

  test('retry reaches the normal app after the dependency recovers', () async {
    var healthy = false;
    var normalFrames = 0;
    var recoveryFrames = 0;

    Future<void> start() => runSenderStartup(
          renderBoot: () {},
          initialize: () async {
            if (!healthy) throw StateError('temporary');
          },
          renderApp: () => normalFrames++,
          renderRecovery: () => recoveryFrames++,
        );

    await start();
    expect(recoveryFrames, 1);
    healthy = true;
    await start();
    expect(normalFrames, 1);
    expect(recoveryFrames, 1);
  });

  test('renders a boot surface before a never-resolving dependency', () async {
    var bootFrames = 0;
    final neverCompletes = runSenderStartup(
      renderBoot: () => bootFrames++,
      initialize: () => Completer<void>().future,
      renderApp: () => fail('normal app must not render'),
      renderRecovery: () => fail('recovery is not expected yet'),
    );

    await Future<void>.delayed(Duration.zero);
    expect(bootFrames, 1);
    // The unresolved startup future is intentionally not awaited: rendering
    // has already happened and remains independent of the dependency.
    expect(neverCompletes, isA<Future<void>>());
  });

  test('Sender entrypoint renders before App Check initialization', () {
    final source = File('lib/main.dart').readAsStringSync();
    final bootRender = source.indexOf('renderBoot:');
    final appCheckInit = source.indexOf('initializeCircumAppCheck');
    expect(bootRender, isNonNegative);
    expect(appCheckInit, greaterThan(bootRender));
    expect(source, contains('runSenderStartup('));
  });
}
