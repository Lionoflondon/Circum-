import 'dart:typed_data';

class RiderPickedDocument {
  const RiderPickedDocument(this.name, this.bytes, this.contentType);
  final String name;
  final Uint8List bytes;
  final String contentType;
}
