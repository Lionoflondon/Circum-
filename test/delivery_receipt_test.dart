import 'package:circum/app/delivery/delivery_receipt.dart';
import 'package:circum/app/delivery/proof_of_delivery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('receipt uses immutable quote items and authoritative paid total', () {
    final receipt = deliveryReceiptFromRecord({
      'requestId': 'sender_internal_ABC123',
      'pickupDetails': {'address': 'The Shard, London'},
      'dropoffDetails': {'address': 'Battersea Power Station, London'},
      'selectedSpeed': 'standard',
      'paidAmount': 10.66,
      'paymentStatus': 'paid',
      'paymentMethod': 'card',
      'currency': 'GBP',
      'pricingBreakdown': {
        'canonicalQuoteSnapshot': {
          'total': 999,
          'lineItems': [
            {'label': 'Base delivery', 'amount': 5},
            {'label': 'Distance', 'amount': 5.66},
            {'label': 'Road toll', 'amount': 0},
          ],
        },
      },
    }, referenceFormatter: customerFacingDeliveryReference);

    expect(receipt.reference, 'Delivery #ABC123');
    expect(receipt.pickup, 'The Shard, London');
    expect(receipt.dropoff, 'Battersea Power Station, London');
    expect(receipt.amountPaid, 10.66);
    expect(receipt.paymentStatus, 'Paid');
    expect(receipt.lineItems.map((item) => item.label),
        ['Base delivery', 'Distance']);
  });
}
