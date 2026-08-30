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
}
