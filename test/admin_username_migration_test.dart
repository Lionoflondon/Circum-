import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Admin username migration control is protected and uses the canonical callable', () {
    final shell = File('lib/app/admin/admin_phase1_shell.dart').readAsStringSync();
    final backend = File('server/functions/username-migration.js').readAsStringSync();
    expect(shell, contains('AdminPermission.usernameMigration'));
    expect(shell, contains("httpsCallable('migrateCircumUsernames')"));
    expect(shell, contains('Username Migration Dry Run'));
    expect(shell, contains('Execute Safe Username Migration'));
    expect(backend, contains('enforceAppCheck: true'));
    expect(backend, contains('operations_admin'));
    expect(backend, contains('adminAuditLogs'));
  });
}
