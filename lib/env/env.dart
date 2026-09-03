class Env {
  static const String stripePublishableKey =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');

  static bool googlePayTestEnvironmentForKey(String publishableKey) {
    final key = publishableKey.trim();
    final segments = key.split('_');
    if (segments.length >= 3 && segments.first == 'pk') {
      if (segments[1] == 'test') return true;
      if (segments[1] == 'live') return false;
    }
    throw const FormatException('Stripe payment configuration is unavailable.');
  }

  static bool get googlePayTestEnvironment =>
      googlePayTestEnvironmentForKey(stripePublishableKey);
}
