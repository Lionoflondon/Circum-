import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../env/env.dart';

/// Probe the wallet realm used by confirmation; the SDK defaults to live.
Future<bool> senderDeviceWalletSupported({
  TargetPlatform? platform,
  bool? isWeb,
  String? environment,
  String? publishableKey,
  Future<bool> Function(IsGooglePaySupportedParams)? probe,
}) async {
  final target = platform ?? defaultTargetPlatform;
  if ((isWeb ?? kIsWeb) ||
      (target != TargetPlatform.iOS && target != TargetPlatform.android)) {
    return false;
  }
  final mode = Env.validatedPaymentEnvironment(
    environment: environment ?? Env.paymentEnvironment,
    publishableKey: publishableKey ?? Env.stripePublishableKey,
  );
  final params = IsGooglePaySupportedParams(testEnv: mode == 'test');
  return (probe ??
      (params) => Stripe.instance.isPlatformPaySupported(googlePay: params))(
    params,
  );
}
