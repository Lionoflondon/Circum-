/// A reserved delivery ID is not evidence that checkout has been paid.
String confirmedSenderPaymentRequestId(Map<String, dynamic> response) {
  final status = '${response['paymentStatus'] ?? response['status'] ?? ''}';
  if (status != 'succeeded' && status != 'paid') return '';
  return '${response['requestId'] ?? response['deliveryId'] ?? ''}'.trim();
}
