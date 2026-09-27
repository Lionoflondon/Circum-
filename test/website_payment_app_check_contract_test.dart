import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/website/shared/production_payment_api.dart')
      .readAsStringSync();

  test('all website payment families send Firebase App Check with Auth', () {
    expect(source, contains('firebase_app_check.dart'));
    expect(source, contains('FirebaseAppCheck.instance.getToken()'));
    expect(source, contains("'X-Firebase-AppCheck': appCheckToken"));
    expect(source, contains(r"'Authorization': 'Bearer $token'"));
    expect(source, contains('appCheckToken == null'));
    expect(source, contains('appCheckToken.isEmpty'));
  });
}
