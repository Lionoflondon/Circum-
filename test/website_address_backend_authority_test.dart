import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Website address lookup uses the deployed backend authority', () {
    final source = File(
      'lib/website/shared/circum_website_app.dart',
    ).readAsStringSync();

    expect(source, contains("httpsCallable('searchFreeUkAddresses')"));
    expect(source, contains("httpsCallable('resolveUkAddressPlace')"));
    expect(source, isNot(contains("/maps/api/place/autocomplete/json")));
    expect(source, isNot(contains("/maps/api/place/details/json")));
    expect(source, isNot(contains("/maps/api/place/findplacefromtext/json")));
  });
}
