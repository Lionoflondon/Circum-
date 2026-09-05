import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'document.dart';

Future<RiderPickedDocument?> pickRiderDocument() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.pdf,.jpg,.jpeg,.png,.webp';
  final selected = Completer<web.File?>();
  input.addEventListener(
      'change',
      ((web.Event _) {
        if (!selected.isCompleted) selected.complete(input.files?.item(0));
      }).toJS);
  input.addEventListener(
      'cancel',
      ((web.Event _) {
        if (!selected.isCompleted) selected.complete(null);
      }).toJS);
  input.style.display = 'none';
  web.document.body?.appendChild(input);
  try {
    input.click();
    final file = await selected.future.timeout(const Duration(minutes: 2));
    if (file == null) return null;
    final extension = file.name.split('.').last.toLowerCase();
    final mime = const {
      'pdf': 'application/pdf',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp'
    }[extension];
    if (mime == null) {
      throw StateError('Choose a PDF, JPG, JPEG, PNG or WEBP document.');
    }
    if (file.size <= 0 || file.size > 8 * 1024 * 1024) {
      throw StateError('Documents must be between 1 byte and 8 MiB.');
    }
    final buffer =
        await file.arrayBuffer().toDart.timeout(const Duration(seconds: 20));
    return RiderPickedDocument(file.name, buffer.toDart.asUint8List(), mime);
  } finally {
    input.remove();
  }
}
