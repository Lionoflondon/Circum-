import 'dart:async';

import 'package:circum/app/authentication/sender_account_closure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sequence = SenderAccountClosureSequence();

  Future<void> succeed() async {}

  test('closes application data before deleting the Firebase identity',
      () async {
    final steps = <String>[];

    await sequence.run(
      reauthenticate: () async => steps.add('reauthenticate'),
      refreshToken: () async => steps.add('refresh-token'),
      closeApplicationAccount: () async => steps.add('backend-closure'),
      deleteFirebaseIdentity: () async => steps.add('delete-auth'),
      clearLocalSession: () async => steps.add('clear-local-session'),
    );

    expect(steps, <String>[
      'reauthenticate',
      'refresh-token',
      'backend-closure',
      'delete-auth',
      'clear-local-session',
    ]);
  });

  test('does not delete the Firebase identity when backend closure fails',
      () async {
    var authDeleted = false;

    await expectLater(
      sequence.run(
        reauthenticate: succeed,
        refreshToken: succeed,
        closeApplicationAccount: () => Future<void>.error(StateError('down')),
        deleteFirebaseIdentity: () async => authDeleted = true,
        clearLocalSession: succeed,
      ),
      throwsA(isA<StateError>()),
    );

    expect(authDeleted, isFalse);
  });

  test('does not clear local state when Firebase identity deletion fails',
      () async {
    var localStateCleared = false;

    await expectLater(
      sequence.run(
        reauthenticate: succeed,
        refreshToken: succeed,
        closeApplicationAccount: succeed,
        deleteFirebaseIdentity: () => Future<void>.error(StateError('down')),
        clearLocalSession: () async => localStateCleared = true,
      ),
      throwsA(isA<StateError>()),
    );

    expect(localStateCleared, isFalse);
  });

  test('times out before the backend closure when reauthentication hangs',
      () async {
    const bounded = SenderAccountClosureSequence(
      operationTimeout: Duration(milliseconds: 1),
    );
    var backendCalled = false;

    await expectLater(
      bounded.run(
        reauthenticate: () => Completer<void>().future,
        refreshToken: succeed,
        closeApplicationAccount: () async => backendCalled = true,
        deleteFirebaseIdentity: succeed,
        clearLocalSession: succeed,
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(backendCalled, isFalse);
  });
}
