import 'package:circum/env/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test mode accepts only a test publishable key', () {
    expect(
      Env.validatedPaymentEnvironment(
        environment: 'test',
        publishableKey: 'pk_test_example',
      ),
      'test',
    );
    expect(
      () => Env.validatedPaymentEnvironment(
        environment: 'test',
        publishableKey: 'pk_live_example',
      ),
      throwsFormatException,
    );
  });

  test('live mode accepts only a live publishable key', () {
    expect(
      Env.validatedPaymentEnvironment(
        environment: 'live',
        publishableKey: 'pk_live_example',
      ),
      'live',
    );
    expect(
      () => Env.validatedPaymentEnvironment(
        environment: 'live',
        publishableKey: 'pk_test_example',
      ),
      throwsFormatException,
    );
  });

  test('missing or unknown mode is rejected', () {
    expect(
      () => Env.validatedPaymentEnvironment(
        environment: '',
        publishableKey: 'pk_test_example',
      ),
      throwsFormatException,
    );
  });
}
