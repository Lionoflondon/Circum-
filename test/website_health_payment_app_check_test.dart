import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Health+ checkout cannot bypass protected payment transport', () {
    final source = File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    final start = source.indexOf('Future<Map<String, dynamic>?> _createHealthPlusCheckoutSession');
    expect(start, greaterThanOrEqualTo(0));
    final body = source.substring(start, source.indexOf('Future<void> _openHealthPlusBillingPortal', start));
    expect(body, contains('WebsiteProductionPaymentApi.call('));
    expect(body, contains("'health_plus'"));
    expect(body, contains("'createHealthPlusCheckoutSession'"));
    expect(body, contains('callable: false'));
    expect(body, isNot(contains('http.post(')));
    expect(body, isNot(contains('getIdToken()')));
  });
}
