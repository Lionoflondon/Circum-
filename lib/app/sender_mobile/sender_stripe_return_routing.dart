const senderGiftPaymentReturnRouteName = '/sender-mobile/gifts/return';
const senderHealthReturnRouteName = '/sender-mobile/health';
const senderBusinessReturnRouteName = '/sender-mobile/business';
const senderWalletReturnRouteName = '/sender-mobile/wallet';

Map<String, String> senderStripeReturnParameters(Uri uri) {
  final parameters = <String, String>{...uri.queryParameters};
  final fragment = uri.fragment.trim();
  if (fragment.isNotEmpty) {
    final fragmentUri = Uri.tryParse(fragment);
    if (fragmentUri != null) {
      parameters.addAll(fragmentUri.queryParameters);
      if (fragmentUri.path.endsWith('/gifts/confirmation')) {
        parameters.putIfAbsent('gift_payment', () => 'success');
      } else if (fragmentUri.path.endsWith('/gifts/payment')) {
        parameters.putIfAbsent(
          'gift_payment',
          () => fragmentUri.queryParameters['payment'] ?? 'cancelled',
        );
      }
    }
  }
  return parameters;
}

String? resolveSenderInitialRouteName(Uri uri) {
  final fragment = uri.fragment.trim();
  final fragmentUri = fragment.isEmpty ? null : Uri.tryParse(fragment);
  final fragmentPath = fragmentUri?.path ?? fragment;
  if (fragmentPath == '/sender-mobile/gifts' ||
      fragmentPath == '#/sender-mobile/gifts') {
    return '/sender-mobile/gifts';
  }
  if (fragmentPath == '/sender-mobile/gifts/story' ||
      fragmentPath == '#/sender-mobile/gifts/story') {
    return '/sender-mobile/gifts/story';
  }

  final parameters = senderStripeReturnParameters(uri);
  final app = parameters['app']?.trim().toLowerCase();
  final giftResult = parameters['gift_payment']?.trim().toLowerCase();
  if ((app == 'gifts' || fragmentPath.contains('/gifts/')) &&
      (giftResult == 'success' || giftResult == 'cancelled')) {
    return senderGiftPaymentReturnRouteName;
  }
  if (app == 'health' && parameters.containsKey('health')) {
    return senderHealthReturnRouteName;
  }
  if (app == 'business') {
    return senderBusinessReturnRouteName;
  }
  final walletResult = parameters['wallet_topup']?.trim().toLowerCase();
  if (app == 'sender' &&
      parameters['section']?.trim().toLowerCase() == 'wallet' &&
      (walletResult == 'success' || walletResult == 'cancelled')) {
    return senderWalletReturnRouteName;
  }
  return null;
}

String? senderWalletStripeReturnMessage(Uri uri) {
  final result =
      senderStripeReturnParameters(uri)['wallet_topup']?.trim().toLowerCase();
  return switch (result) {
    'success' =>
      'Roth top-up returned securely. Your Wallet is refreshing while Stripe confirmation completes.',
    'cancelled' => 'Roth top-up was cancelled. No new charge was made.',
    _ => null,
  };
}
