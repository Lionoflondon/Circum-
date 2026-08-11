import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'Admin username migration control is protected and uses the canonical callable',
      () {
    final shell =
        File('lib/app/admin/admin_phase1_shell.dart').readAsStringSync();
    final backend =
        File('server/functions/username-migration.js').readAsStringSync();
    expect(shell, contains('AdminPermission.usernameMigration'));
    expect(shell, contains("httpsCallable('migrateCircumUsernames')"));
    expect(shell, contains("region: 'us-central1'"));
    expect(shell, contains('getIdToken(true)'));
    expect(shell, contains('FirebaseAppCheck.instance.getToken(true)'));
    expect(shell, contains('Sign in again to run the username migration.'));
    expect(shell, contains('Username Migration Dry Run'));
    expect(shell, contains('Execute Safe Username Migration'));
    expect(shell, contains("'Username'"));
    expect(shell, contains('canonicalUsername'));
    expect(shell, contains('usernameMigrationStatus'));
    expect(shell, contains('Not claimed'));
    expect(shell, contains('Conflict / review required'));
    expect(shell, contains("collection('usernames')"));
    expect(shell, contains('Username'));
    expect(backend, contains('enforceAppCheck: true'));
    expect(backend, contains('operations_admin'));
    expect(backend, contains('adminAuditLogs'));
  });
}
