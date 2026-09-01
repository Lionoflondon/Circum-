import 'dart:async';

import 'package:circum/app/authentication/sender_auth_commit_sequence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sequence = SenderAuthCommitSequence(
    operationTimeout: Duration(milliseconds: 5),
  );

  test('commits only after account, profile, and token authority succeed',
      () async {
    final calls = <String>[];
    await sequence.run(
      ensureAccount: () async => calls.add('account'),
      hydrateProfile: () async => calls.add('profile'),
      refreshToken: () async => calls.add('token'),
    );
    expect(calls, ['account', 'profile', 'token']);
  });

  test('does not continue after account authority fails', () async {
    var hydrated = false;
    await expectLater(
      sequence.run(
        ensureAccount: () => Future<void>.error(StateError('blocked')),
        hydrateProfile: () async => hydrated = true,
        refreshToken: () async {},
      ),
      throwsStateError,
    );
    expect(hydrated, isFalse);
  });

  test('does not continue after profile authority fails or times out',
      () async {
    var refreshed = false;
    await expectLater(
      sequence.run(
        ensureAccount: () async {},
        hydrateProfile: () => Completer<void>().future,
        refreshToken: () async => refreshed = true,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(refreshed, isFalse);
  });

  test('recoverable account failure is bounded and reports its stage', () async {
    final result = await sequence.runRecoverable(
      ensureAccount: () => Completer<void>().future,
      hydrateProfile: () async {},
      refreshToken: () async {},
    );
    expect(result.succeeded, isFalse);
    expect(result.failedStage, SenderAuthCommitStage.account);
    expect(result.error, isA<TimeoutException>());
  });

  test('recoverable profile failure can be retried idempotently', () async {
    var attempts = 0;
    Future<void> profile() async {
      attempts += 1;
      if (attempts == 1) throw StateError('temporary');
    }

    final first = await sequence.runRecoverable(
      ensureAccount: () async {},
      hydrateProfile: profile,
      refreshToken: () async {},
    );
    final retry = await sequence.runRecoverable(
      ensureAccount: () async {},
      hydrateProfile: profile,
      refreshToken: () async {},
    );
    expect(first.failedStage, SenderAuthCommitStage.profile);
    expect(retry.succeeded, isTrue);
    expect(attempts, 2);
  });

  test('successful recoverable bootstrap completes every authority stage',
      () async {
    final calls = <String>[];
    final result = await sequence.runRecoverable(
      ensureAccount: () async => calls.add('account'),
      hydrateProfile: () async => calls.add('profile'),
      refreshToken: () async => calls.add('token'),
    );
    expect(result.succeeded, isTrue);
    expect(calls, ['account', 'profile', 'token']);
  });
}
