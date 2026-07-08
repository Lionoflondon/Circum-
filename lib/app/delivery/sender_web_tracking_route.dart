String? senderDeliveryRouteIdFromUri(Uri uri) {
  for (final key in const ['deliveryId', 'purchaseId', 'reference']) {
    final value = uri.queryParameters[key]?.trim();
    if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
      return value;
    }
  }
  return null;
}
