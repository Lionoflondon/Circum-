class Env {
  static const String stripePublishableKey =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
  static const String paymentEnvironment =
      String.fromEnvironment('PAYMENT_ENVIRONMENT');

  static String validatedPaymentEnvironment({
    required String environment,
    required String publishableKey,
  }) {
    final normalized = environment.trim().toLowerCase();
    if (normalized != 'test' && normalized != 'live') {
      throw const FormatException(
        'Payment environment must be explicitly test or live.',
      );
    }
    final isTestKey = googlePayTestEnvironmentForKey(publishableKey);
    if ((normalized == 'test') != isTestKey) {
      throw const FormatException('Stripe payment configuration mismatch.');
    }
    return normalized;
  }

  static String get validatedPaymentMode => validatedPaymentEnvironment(
        environment: paymentEnvironment,
        publishableKey: stripePublishableKey,
      );

  static bool paymentModeMatchesBackend(String backendMode) =>
      validatedPaymentMode == backendMode.trim().toLowerCase();

  static bool googlePayTestEnvironmentForKey(String publishableKey) {
    final key = publishableKey.trim();
    final segments = key.split('_');
    if (segments.length >= 3 && segments.first == 'pk') {
      if (segments[1] == 'test') return true;
      if (segments[1] == 'live') return false;
    }
    throw const FormatException('Stripe payment configuration is unavailable.');
  }

  static bool get googlePayTestEnvironment => validatedPaymentMode == 'test';
}
