import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender mobile bottom navigation matches the locked Sender contract',
      () {
    final source =
        File('lib/app/bottom_nav/view/app_nav.dart').readAsStringSync();

    for (final label in const [
      'Home',
      'Send',
      'Activity',
      'Wallet',
      'Profile'
    ]) {
      expect(source, contains("label: '$label'"));
    }

    expect(source, isNot(contains("label: 'Marketplace'")));
    expect(source, isNot(contains("label: 'Rider'")));
    expect(source, isNot(contains("label: 'Live Chat'")));
    expect(source, isNot(contains("label: 'Health+'")));
    expect(source, contains('const WalletView()'));
  });
}
