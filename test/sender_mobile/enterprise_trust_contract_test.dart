import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'Business custom roles use server callables and an explicit permission UI',
      () {
    final repository =
        File('lib/app/business/business_repository.dart').readAsStringSync();
    final view = File('lib/app/business/business_view.dart').readAsStringSync();
    for (final callable in [
      'listBusinessCustomRoles',
      'saveBusinessCustomRole',
      'deleteBusinessCustomRole',
      'assignBusinessCustomRole',
    ]) {
      expect(repository, contains("httpsCallable('$callable')"));
    }
    expect(view, contains('Create custom role'));
    expect(view, contains('View Rider progress'));
    expect(view, contains("_workspace!.role == 'owner'"));
  });

  test('Sender receipt presents authoritative VAT when supplied', () {
    final receipt =
        File('lib/app/delivery/delivery_receipt.dart').readAsStringSync();
    final tracking = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();
    expect(receipt, contains("record['vatAmount'] ?? snapshot['vatAmount']"));
    expect(tracking, contains("row('VAT', money(receipt.vatAmount))"));
  });
}
