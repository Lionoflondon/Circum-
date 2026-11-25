import 'package:url_launcher/url_launcher.dart';

import 'production_payment_api.dart';

typedef AdjustmentPaymentCall = Future<Map<String, dynamic>> Function(
    String family, String route, Map<String, dynamic> data);

class WebsiteAdjustmentCheckout {
  const WebsiteAdjustmentCheckout._();

  /// True only after the server confirms payment; opening Checkout is not paid.
  static Future<bool> pay(
    String adjustmentId, {
    AdjustmentPaymentCall? call,
    Future<bool> Function(Uri)? open,
  }) async {
    final result = await (call ?? WebsiteProductionPaymentApi.call)(
      'delivery_adjustments',
      'createDeliveryAdjustmentPayment',
      {'adjustmentId': adjustmentId, 'hostedCheckout': true},
    ).timeout(const Duration(seconds: 20));
    if (result['paid'] == true && result['success'] == true) return true;
    final uri = Uri.tryParse('${result['checkoutUrl'] ?? ''}');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'checkout.stripe.com' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !uri.path.startsWith('/c/pay/')) {
      throw StateError('Secure adjustment checkout was not returned.');
    }
    final opened = await (open ??
        (uri) => launchUrl(uri, webOnlyWindowName: '_self'))(uri);
    if (!opened) throw StateError('Secure checkout could not be opened.');
    return false;
  }
}
