import 'package:flutter/foundation.dart';

/// The Stripe SDK consumes this callback; it never supplies payment authority.
const circumPaymentUrlScheme = 'circum';
const circumPaymentReturnUrl = 'circum://stripe-redirect';

String? get nativePaymentReturnUrl => kIsWeb ? null : circumPaymentReturnUrl;
