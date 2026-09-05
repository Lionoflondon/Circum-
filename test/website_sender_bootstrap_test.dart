import 'package:flutter_test/flutter_test.dart';
import 'package:circum/website/shared/policies/role_access.dart';
import 'package:circum/website/shared/policies/sender_bootstrap.dart';

void main() {
  test('recognized and unknown Senders both execute backend bootstrap',
      () async {
    for (final roles in [
      {CircumRole.sender},
      {CircumRole.unknown}
    ]) {
      var calls = 0;
      expect(
          await ensureWebSenderBootstrap(
              roles: roles,
              ensureAccount: () async {
                calls++;
                return {'allowed': true};
              }),
          true);
      expect(calls, 1);
    }
  });
  test('failed setup can be retried even when a Sender role already exists',
      () async {
    var attempts = 0;
    Future<Map<String, dynamic>> ensure() async {
      if (++attempts == 1) throw StateError('temporary setup failure');
      return {'allowed': true};
    }

    await expectLater(
        ensureWebSenderBootstrap(
            roles: {CircumRole.sender}, ensureAccount: ensure),
        throwsStateError);
    expect(
        await ensureWebSenderBootstrap(
            roles: {CircumRole.sender}, ensureAccount: ensure),
        true);
    expect(attempts, 2);
  });
  test('backend denial or malformed success cannot open Sender access',
      () async {
    for (final result in <Map<String, dynamic>>[
      {'allowed': false},
      {'ok': true},
      {'allowed': 'true'}
    ]) {
      expect(
          await ensureWebSenderBootstrap(
              roles: {CircumRole.sender}, ensureAccount: () async => result),
          false);
    }
  });
  test(
      'conflicting-only roles stay excluded; mixed Sender roles still require backend approval',
      () async {
    var calls = 0;
    Future<Map<String, dynamic>> ensure() async {
      calls++;
      return {'allowed': true};
    }

    for (final role in [CircumRole.rider, CircumRole.admin]) {
      expect(
          await ensureWebSenderBootstrap(roles: {role}, ensureAccount: ensure),
          false);
    }
    expect(calls, 0);
    expect(
        await ensureWebSenderBootstrap(
            roles: {CircumRole.sender, CircumRole.rider},
            ensureAccount: ensure),
        true);
    expect(calls, 1);
  });
}
