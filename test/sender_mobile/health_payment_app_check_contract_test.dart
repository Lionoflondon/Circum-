import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Health+ checkout cannot bypass protected payment transport', () {
    final source = File('lib/app/health_plus/view/health_plus.dart').readAsStringSync();
    final start = source.indexOf('Future<Map<String, dynamic>?> _createCheckoutSession');
    expect(start, greaterThanOrEqualTo(0));
    final body = source.substring(start, source.indexOf('Future<void> _openCheckout', start));
    expect(body, contains('ProductionPaymentApi.call('));
    expect(body, contains("'health_plus'"));
    expect(body, contains("'createHealthPlusCheckoutSession'"));
    expect(body, contains('callable: false'));
    expect(body, isNot(contains('http.post(')));
    expect(body, isNot(contains('getIdToken()')));
  });
}
