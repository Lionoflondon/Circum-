class DeliveryReceiptLineItem {
  final String label;
  final double amount;

  const DeliveryReceiptLineItem({required this.label, required this.amount});
}

class DeliveryReceiptDetails {
  final String reference;
  final String pickup;
  final String dropoff;
  final String completedAt;
  final String service;
  final String currency;
  final String paymentStatus;
  final String paymentMethod;
  final double amountPaid;
  final double vatAmount;
  final double rothAppliedAmount;
  final double externalPaidAmount;
  final List<DeliveryReceiptLineItem> lineItems;

  const DeliveryReceiptDetails({
    required this.reference,
    required this.pickup,
    required this.dropoff,
    required this.completedAt,
    required this.service,
    required this.currency,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.amountPaid,
    required this.vatAmount,
    required this.rothAppliedAmount,
    required this.externalPaidAmount,
    required this.lineItems,
  });
}

DeliveryReceiptDetails deliveryReceiptFromRecord(
  Map<String, dynamic> record, {
  required String Function(String) referenceFormatter,
}) {
  final pricing = _map(record['pricingBreakdown']);
  final snapshot = _map(pricing['canonicalQuoteSnapshot']);
  final rawItems = snapshot['lineItems'] ?? pricing['lineItems'];
  final lineItems = <DeliveryReceiptLineItem>[];
  if (rawItems is Iterable) {
    for (final rawItem in rawItems) {
      final item = _map(rawItem);
      final label = _text(item['label']);
      final amount = _number(item['amount']);
      if (label.isNotEmpty && amount != null && amount != 0) {
        lineItems.add(DeliveryReceiptLineItem(label: label, amount: amount));
      }
    }
  }
  return DeliveryReceiptDetails(
    reference: referenceFormatter(
      _text(
        record['deliveryReference'] ??
            record['trackingReference'] ??
            record['requestId'] ??
            record['deliveryId'],
      ),
    ),
    pickup: _address(record['pickupDetails'], record['pickupAddress']),
    dropoff: _address(record['dropoffDetails'], record['dropoffAddress']),
    completedAt: _date(
      record['deliveredAt'] ?? record['completedAt'] ?? record['updatedAt'],
    ),
    service: _service(
      record['selectedServiceLevel'] ??
          record['selectedSpeed'] ??
          snapshot['speed'],
    ),
    currency: _text(
      record['currency'] ?? snapshot['currency'] ?? 'GBP',
    ).toUpperCase(),
    paymentStatus: _paymentStatus(record['paymentStatus']),
    paymentMethod: _paymentMethod(record['paymentMethod']),
    amountPaid:
        _number(
          record['paidAmount'] ??
              pricing['amountDue'] ??
              snapshot['amountDue'] ??
              snapshot['total'],
        ) ??
        0,
    vatAmount: _number(record['vatAmount'] ?? snapshot['vatAmount']) ?? 0,
    rothAppliedAmount: _number(record['rothAppliedAmount']) ?? 0,
    externalPaidAmount: _number(record['remainingAmount']) ?? 0,
    lineItems: lineItems,
  );
}

DeliveryReceiptDetails deliveryReceiptFromTrustProjection(
  Map<String, dynamic> projection, {
  required Map<String, dynamic> fallbackRecord,
  required String Function(String) referenceFormatter,
}) {
  final receipt = _map(projection['receipt']);
  if (receipt.isEmpty) {
    return deliveryReceiptFromRecord(
      fallbackRecord,
      referenceFormatter: referenceFormatter,
    );
  }
  final merged = <String, dynamic>{
    ...fallbackRecord,
    'deliveryReference': receipt['reference'],
    'pickupAddress': projection['pickup'],
    'dropoffAddress': projection['dropoff'],
    'deliveredAt': receipt['dateMillis'] == null
        ? fallbackRecord['deliveredAt']
        : DateTime.fromMillisecondsSinceEpoch(receipt['dateMillis'] as int),
    'selectedServiceLevel': receipt['serviceType'],
    'currency': receipt['currency'],
    'paidAmount': receipt['amountPaid'],
    'paymentStatus': receipt['paymentStatus'],
    'paymentMethod': receipt['paymentMethod'],
    'vatAmount': receipt['vatAmount'],
    'rothAppliedAmount': receipt['rothAppliedAmount'],
    'remainingAmount': receipt['externalPaidAmount'],
    'pricingBreakdown': {
      'canonicalQuoteSnapshot': {'lineItems': receipt['lineItems']},
    },
  };
  return deliveryReceiptFromRecord(
    merged,
    referenceFormatter: referenceFormatter,
  );
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

String _text(Object? value) => value is String ? value.trim() : '';

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_text(value));
}

String _address(Object? structured, Object? fallback) {
  final map = _map(structured);
  for (final value in [map['formattedAddress'], map['address'], fallback]) {
    final text = _text(value);
    if (text.isNotEmpty) return text;
  }
  return 'Address unavailable';
}

String _date(Object? value) {
  DateTime? date;
  if (value is DateTime) date = value;
  if (value is String) date = DateTime.tryParse(value);
  if (date == null && value != null) {
    try {
      final dynamic timestamp = value;
      final converted = timestamp.toDate();
      if (converted is DateTime) date = converted;
    } catch (_) {
      // Unsupported timestamp shapes remain unavailable to presentation.
    }
  }
  if (date == null) return 'Completion time unavailable';
  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}

String _service(Object? value) => switch (_text(value).toLowerCase()) {
  'economy' => 'Economy',
  'express' => 'Express',
  'standard' => 'Standard',
  _ => 'Delivery service',
};

String _paymentStatus(Object? value) => switch (_text(value).toLowerCase()) {
  'paid' || 'succeeded' || 'complete' || 'completed' => 'Paid',
  'refunded' => 'Refunded',
  _ => 'Payment status unavailable',
};

String _paymentMethod(Object? value) => switch (_text(value).toLowerCase()) {
  'card' => 'Card',
  'saved_card' => 'Saved card',
  'apple_pay' => 'Apple Pay',
  'google_pay' => 'Google Pay',
  'roth' => 'Roth',
  'roth_card' => 'Roth and card',
  'roth_saved_card' => 'Roth and saved card',
  'roth_apple_pay' => 'Roth and Apple Pay',
  'roth_google_pay' => 'Roth and Google Pay',
  '' => 'Payment method unavailable',
  _ => 'Payment method',
};
