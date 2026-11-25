/// Formats only the identity and tax snapshot saved on this invoice.
/// Historical invoices must not inherit today's registration status.
List<String> businessInvoiceIdentityLines(Map<String, dynamic> invoice) {
  final supplier = invoice['supplier'];
  final tax = invoice['tax'];
  if (supplier is! Map || '${supplier['legalName'] ?? ''}'.trim().isEmpty) {
    return const ['Supplier details not recorded. Contact Circum Operations.'];
  }
  final legalName = '${supplier['legalName']}'.trim();
  final tradingName = '${supplier['tradingName'] ?? ''}'.trim();
  final companyNumber = '${supplier['companyNumber'] ?? ''}'.trim();
  final address = '${supplier['registeredAddress'] ?? ''}'.trim();
  final notRegistered =
      supplier['vatRegistrationStatus'] == 'not_registered' &&
      tax is Map &&
      tax['treatment'] == 'not_vat_registered' &&
      tax['vatAmount'] == 0;
  return [
    'Supplier: $legalName',
    if (tradingName.isNotEmpty && tradingName != legalName)
      'Trading as: $tradingName',
    if (companyNumber.isNotEmpty) 'Company number: $companyNumber',
    if (address.isNotEmpty) address,
    if (notRegistered) 'Not VAT registered. No VAT charged.',
    if (!notRegistered) 'See the recorded tax details for this invoice.',
  ];
}
