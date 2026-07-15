import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('IRIS reference images are restricted to IRIS admins', () {
    final storage = File('storage.rules').readAsStringSync();
    expect(storage, contains('match /irisReferenceImages/{itemId}/{fileName}'));
    expect(storage,
        contains("hasRole('super_admin') || hasRole('operations_admin')"));
    expect(storage, contains('request.resource.size <= 10 * 1024 * 1024'));
    expect(storage, contains('image/jpeg|image/png|image/webp'));
    expect(storage, contains('allow delete: if false;'));
  });

  test('IRIS reference metadata is backend writable only', () {
    final firestore = File('firestore.rules').readAsStringSync();
    expect(firestore, contains('match /irisReferenceImages/{itemId}'));
    expect(firestore, contains('allow read: if isIrisAdmin();'));
    expect(firestore, contains('allow write: if false;'));
  });
}
