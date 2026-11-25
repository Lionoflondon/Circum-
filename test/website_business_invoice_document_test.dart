import 'package:flutter_test/flutter_test.dart';
import 'package:circum/website/shared/business_invoice_document.dart';

void main() {
  final invoice = <String, dynamic>{
    'supplier': {
      'legalName': 'Circum Technologies Ltd',
      'tradingName': 'Circum',
      'companyNumber': '13931698',
      'registeredAddress': '124 City Road, London, England EC1V 2NX',
      'vatRegistrationStatus': 'not_registered',
    },
    'tax': {'treatment': 'not_vat_registered', 'vatAmount': 0},
  };
  test('confirmed non-VAT supplier snapshot appears without zero-rating claim', () {
    final lines = businessInvoiceIdentityLines(invoice);
    expect(lines, contains('Supplier: Circum Technologies Ltd'));
    expect(lines, contains('Company number: 13931698'));
    expect(lines, contains('124 City Road, London, England EC1V 2NX'));
    expect(lines, contains('Not VAT registered. No VAT charged.'));
    expect(lines.any((line) => line.contains('0%')), isFalse);
  });
  test('historical invoice cannot inherit present-day identity or VAT status', () {
    final lines = businessInvoiceIdentityLines({});
    expect(lines.single, contains('not recorded'));
    expect(lines.any((line) => line.contains('Not VAT registered')), isFalse);
  });
  test('inconsistent or later registration cannot be described as no VAT', () {
    for (final tax in [
      {'treatment': 'vat_registered', 'vatAmount': 0},
      {'treatment': 'not_vat_registered', 'vatAmount': 10},
    ]) {
      expect(businessInvoiceIdentityLines({...invoice, 'tax': tax}),
          isNot(contains('Not VAT registered. No VAT charged.')));
    }
    expect(businessInvoiceIdentityLines({
      ...invoice,
      'supplier': {...invoice['supplier'], 'vatRegistrationStatus': 'registered'},
    }), isNot(contains('Not VAT registered. No VAT charged.')));
  });
}
