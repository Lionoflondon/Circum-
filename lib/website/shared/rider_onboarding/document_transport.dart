import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Every request stays below the first-generation callable request limit.
Future<void> submitRiderDocumentTransport({
  required Map<String, dynamic> request,
  required Future<void> Function(Map<String, dynamic>) call,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  Future<void> send(Map<String, dynamic> data) async {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Document upload timed out.');
    }
    await call(data).timeout(remaining);
  }

  final raw = request['files'] is List
      ? (request['files'] as List).cast<Map<String, dynamic>>()
      : [
          {
            'side': 'primary',
            'base64': request['fileBase64'],
            'mimeType': request['contentType'],
            'fileName': request['fileName']
          },
        ];
  final files = raw
      .map((file) => (file, base64Decode(file['base64'] as String)))
      .toList();
  if (files.fold<int>(0, (size, file) => size + file.$2.length) <=
      4 * 1024 * 1024) {
    await send(request);
    return;
  }
  final manifests = <Map<String, dynamic>>[];
  for (final (file, bytes) in files) {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw StateError('Documents must be 8 MiB or smaller.');
    }
    final manifest = <String, dynamic>{
      'side': file['side'],
      'contentType': file['mimeType'],
      'fileName': file['fileName'],
      'sizeBytes': bytes.length,
      'sha256': sha256.convert(bytes).toString()
    };
    manifests.add(manifest);
    const chunkBytes = 2 * 1024 * 1024;
    for (var offset = 0; offset < bytes.length; offset += chunkBytes) {
      final end = offset + chunkBytes < bytes.length
          ? offset + chunkBytes
          : bytes.length;
      await send({
        'documentType': request['documentType'],
        'idempotencyKey': request['idempotencyKey'],
        'chunk': {
          ...manifest,
          'index': offset ~/ chunkBytes,
          'base64': base64Encode(bytes.sublist(offset, end))
        }
      });
    }
  }
  await send({
    for (final entry in request.entries)
      if (!const {'fileBase64', 'files'}.contains(entry.key))
        entry.key: entry.value,
    'stagedFiles': manifests
  });
}
