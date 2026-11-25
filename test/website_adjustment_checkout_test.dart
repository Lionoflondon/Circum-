import 'package:flutter_test/flutter_test.dart';
import 'package:circum/website/shared/adjustment_checkout.dart';

void main() {
  test('hosted Stripe handoff requests the web rail and never reports paid',
      () async {
    var opened = 0;
    expect(
        await WebsiteAdjustmentCheckout.pay('adj',
            call: (family, route, data) async {
          expect(family, 'delivery_adjustments');
          expect(route, 'createDeliveryAdjustmentPayment');
          expect(data, {'adjustmentId': 'adj', 'hostedCheckout': true});
          return {'checkoutUrl': 'https://checkout.stripe.com/c/pay/cs_test'};
        }, open: (uri) async {
          opened++;
          return true;
        }),
        isFalse);
    expect(opened, 1);
  });
  test('only an authoritative paid response completes without navigation',
      () async {
    expect(
        await WebsiteAdjustmentCheckout.pay('adj',
            call: (_, __, ___) async => {'paid': true, 'success': true},
            open: (_) async => throw StateError('Unexpected navigation')),
        isTrue);
  });
  test('untrusted, missing or native-only responses cannot open checkout',
      () async {
    for (final url in [
      '',
      'https://evil.test/c/pay/x',
      'http://checkout.stripe.com/c/pay/x',
      'https://user@checkout.stripe.com/c/pay/x',
      'https://checkout.stripe.com:444/c/pay/x'
    ]) {
      await expectLater(
          WebsiteAdjustmentCheckout.pay('adj',
              call: (_, __, ___) async => {'checkoutUrl': url},
              open: (_) async => throw ArgumentError('Untrusted navigation')),
          throwsStateError);
    }
  });
  test('blocked navigation and ambiguous backend failure never complete',
      () async {
    await expectLater(
        WebsiteAdjustmentCheckout.pay('adj',
            call: (_, __, ___) async =>
                {'checkoutUrl': 'https://checkout.stripe.com/c/pay/x'},
            open: (_) async => false),
        throwsStateError);
    var calls = 0;
    await expectLater(
        WebsiteAdjustmentCheckout.pay('adj', call: (_, __, ___) async {
          calls++;
          throw StateError('network');
        }),
        throwsStateError);
    expect(calls, 1);
  });
}
