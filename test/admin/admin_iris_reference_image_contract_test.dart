import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String adminSource;

  setUpAll(() {
    adminSource = File('lib/web_sender_app.dart').readAsStringSync();
  });

  test('Admin IRIS media editor has no placeholder', () {
    expect(adminSource, isNot(contains('Upload Reference Images placeholder')));
    expect(adminSource, contains('_AdminIrisReferenceImageEditor'));
  });

  test('Admin IRIS media editor supports complete image lifecycle', () {
    expect(adminSource, contains("httpsCallable('getIrisReferenceImage')"));
    expect(
        adminSource, contains("httpsCallable('finalizeIrisReferenceImage')"));
    expect(adminSource, contains("httpsCallable('deleteIrisReferenceImage')"));
    expect(adminSource, contains("'Upload image'"));
    expect(adminSource, contains("'Replace image'"));
    expect(adminSource, contains("'Delete'"));
    expect(adminSource, contains('Image.network('));
  });

  test('Admin IRIS upload uses its dedicated secure path', () {
    expect(
      adminSource,
      contains("'irisReferenceImages/\${widget.itemId}/"),
    );
    expect(adminSource, contains('SettableMetadata(contentType: contentType)'));
  });
}
