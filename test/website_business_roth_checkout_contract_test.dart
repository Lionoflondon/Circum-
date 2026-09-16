import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Business Roth web checkout sends a stable retry key', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();

    expect(source, contains("httpsCallable('createBusinessRothCheckout')"));
    expect(source, contains("'idempotencyKey': _businessRothCheckoutKey"));
    expect(source, contains('_businessRothCheckoutKey ??='));
    expect(source, contains("replaceAll(',', '')"));
    expect(source, contains('if (amount > 1000000)'));
    expect(
      source,
      contains(
        'Business Roth purchases above £1,000,000 require Circum review.',
      ),
    );
    expect(source, contains("'amount': rawAmount"));
    expect(source, contains('.timeout(const Duration(seconds: 20))'));
    expect(source, contains('Roth checkout timed out. Try again safely'));
    expect(source, contains('payment provider is temporarily unavailable'));
    expect(source, contains('Business Roth purchases are non-refundable.'));
    expect(source, contains('finally {'));
    expect(source, contains('_businessBusy = false'));
  });
}
