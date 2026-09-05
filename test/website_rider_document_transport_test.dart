import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:circum/website/shared/rider_onboarding/document_transport.dart';

void main() {
  test('eight MiB stays within callable limit and finishes only after chunks',
      () async {
    final bytes = Uint8List(8 * 1024 * 1024);
    final request = <String, dynamic>{
      'documentType': 'identity',
      'idempotencyKey': 'stable-upload-key',
      'fileName': 'id.pdf',
      'contentType': 'application/pdf',
      'fileBase64': base64Encode(bytes)
    };
    final calls = <Map<String, dynamic>>[];
    await submitRiderDocumentTransport(
        request: request,
        call: (data) async {
          expect(utf8.encode(jsonEncode(data)).length, lessThan(10000000));
          calls.add(data);
        });
    expect(calls.length, 5);
    expect(calls.take(4).every((c) => c['chunk'] != null), true);
    expect(calls.last['stagedFiles'], hasLength(1));
    expect(request.containsKey('fileBase64'), true);
  });
  test(
      'failed chunk never sends final submission and retry keeps stable identity',
      () async {
    final request = <String, dynamic>{
      'documentType': 'identity',
      'idempotencyKey': 'retry-key',
      'fileName': 'id.pdf',
      'contentType': 'application/pdf',
      'fileBase64': base64Encode(Uint8List(5 * 1024 * 1024))
    };
    final calls = <Map<String, dynamic>>[];
    await expectLater(
        submitRiderDocumentTransport(
            request: request,
            call: (data) async {
              calls.add(data);
              throw StateError('offline');
            }),
        throwsStateError);
    expect(calls.length, 1);
    expect(calls.single.containsKey('stagedFiles'), false);
    Map<String, dynamic>? firstRetry;
    await submitRiderDocumentTransport(
        request: request,
        call: (data) async {
          firstRetry ??= data;
        });
    expect(firstRetry, calls.single);
  });
  test('stalled upload is bounded and surfaces timeout', () async {
    await expectLater(
        submitRiderDocumentTransport(
            request: {'fileBase64': 'AA==', 'contentType': 'application/pdf'},
            call: (_) => Completer<void>().future,
            timeout: const Duration(milliseconds: 5)),
        throwsA(isA<TimeoutException>()));
  });
}
