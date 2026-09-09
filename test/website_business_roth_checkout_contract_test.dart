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
  });
}
