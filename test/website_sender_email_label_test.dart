import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender website sign-in requests email only', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();

    expect(source, isNot(contains("label: 'Email or phone'")));
    expect(source, contains("label: 'Email'"));
  });
}
