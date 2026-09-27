import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final website = File(
    'lib/website/shared/circum_website_app.dart',
  ).readAsStringSync();
  final manifest = File('deploy-manifest.json').readAsStringSync();

  test('Sender Web IRIS photo analysis uses the protected transport', () {
    expect(
      website,
      contains("package:circum/app/send_package/repo/iris_api.dart"),
    );
    expect(website, contains("callIris('analyseParcelPhotoForIris'"));
    expect(
      website,
      isNot(contains("httpsCallable('analyseParcelPhotoForIris')")),
    );
  });

  test('the shared IRIS transport is explicitly allowed across surfaces', () {
    expect(manifest, contains('lib/app/send_package/repo/iris_api.dart'));
    expect(manifest, contains('same first-party IRIS authority'));
  });
}
