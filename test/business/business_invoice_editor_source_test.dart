import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/web_sender_app.dart').readAsStringSync();
  });

  test('Business invoice creation uses a full-page editor, not a modal', () {
    expect(source, contains('class _BusinessInvoiceEditorPage'));
    expect(
        source, contains('Navigator.of(context).push<Map<String, dynamic>>'));
    expect(source,
        isNot(contains("title: const Text('Generate Business invoice')")));
    expect(source, isNot(contains("labelText: 'Line item description'")));
  });

  test('invoice editor exposes required professional workspace controls', () {
    for (final text in [
      'Create Invoice',
      'Create a new invoice for your customer.',
      'Save Draft',
      'Preview PDF',
      'Send Invoice',
      'Business Account',
      'Invoice Number',
      'Issue Date',
      'Due Date',
      'Currency',
      'Customer',
      'VAT Scheme',
      'Payment Terms',
      'Reference (optional)',
      'Line Items',
      'Add Line Item',
      'Duplicate row',
      'Delete row',
      'Drag to reorder',
      'Invoice-wide discount',
      'Credit / Negative Adjustment',
      'Notes',
      'Drag files here or upload',
      'Invoice Summary',
      'Secure • Encrypted • Compliant',
    ]) {
      expect(source, contains(text),
          reason: 'Missing invoice editor copy: $text');
    }
  });

  test('invoice editor persists through existing invoice backend shape', () {
    expect(
        source,
        contains(
            "FirebaseFirestore.instance.collection('businessInvoices').doc()"));
    expect(source, contains("'lineItems': result['lineItems']"));
    expect(source, contains("'attachments': result['attachments']"));
    expect(source, contains("'status': status"));
    expect(source,
        contains("status == 'issued' ? 'invoice_issued' : 'invoice_created'"));
  });

  test('line item math and row operations are present', () {
    expect(source, contains('class _BusinessInvoiceLineDraft'));
    expect(source, contains('double get vatAmount => net * (vatRate / 100);'));
    expect(source, contains('double get lineTotal => net + vatAmount;'));
    expect(source, contains('void _duplicateLine(int index)'));
    expect(source, contains('void _deleteLine(int index)'));
    expect(source, contains('void _reorderLine(int oldIndex, int newIndex)'));
    expect(source, contains('ReorderableListView.builder'));
  });
}
