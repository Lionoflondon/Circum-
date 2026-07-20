import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender mobile bottom navigation matches the locked Sender contract',
      () {
    final navSource =
        File('lib/app/bottom_nav/view/app_nav.dart').readAsStringSync();
    final appSource = File('lib/app.dart').readAsStringSync();
    final senderHomeSource =
        File('lib/app/sender_mobile/sender_mobile_home.dart')
            .readAsStringSync();

    for (final label in const [
      'Home',
      'Send',
      'Activity',
      'Wallet',
      'Profile'
    ]) {
      expect(senderHomeSource, contains("'$label'"));
    }

    expect(navSource, isNot(contains("label: 'Marketplace'")));
    expect(navSource, isNot(contains("label: 'Rider'")));
    expect(navSource, isNot(contains("label: 'Live Chat'")));
    expect(navSource, isNot(contains("label: 'Health+'")));
    expect(navSource, contains('SenderMobileHome'));
    expect(appSource, contains('const SenderMobileHome()'));
    expect(appSource, isNot(contains('return AppNavView()')));
  });
}
