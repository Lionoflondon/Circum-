String? healthPlusStripeReturnMessage({
  required String returnState,
  String paymentStatus = '',
}) {
  final result = returnState.trim().toLowerCase();
  final status = paymentStatus.trim().toLowerCase();
  if (result == 'cancelled') {
    return 'Payment was cancelled. You are back inside Health+ and no new charge was made.';
  }
  if (result != 'success') return null;
  if (const {'paid', 'succeeded', 'checkout_completed'}.contains(status)) {
    return 'Health+ payment confirmed. Your saved pickup is up to date.';
  }
  return 'Payment returned securely. Circum is confirming your Health+ pickup.';
}
