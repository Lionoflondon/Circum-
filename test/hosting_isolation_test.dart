import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public hosting never resolves the admin surface', () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    expect(source, isNot(contains("|| path == '/admin'")));
    expect(
      source,
      contains('if (adminHostingTarget && !_isPublicHostingHostFor(uri))'),
    );
  });

  test('admin hosting resolves only through the compile-time admin boundary',
      () {
    final entry = File('lib/main_admin.dart').readAsStringSync();
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    expect(entry, contains('runApp(const CircumAdminHostingApp())'));
    expect(source, contains('CIRCUM_ADMIN_PORTAL_CANONICAL_V1'));
    expect(source, contains('home: CircumAdminAppRoot('));
    expect(source, contains('return _AdminOperationsPanel('));
  });

  test('hosting aliases and build outputs are permanently isolated', () {
    final firebaserc = File('.firebaserc').readAsStringSync();
    final firebase = File('firebase.json').readAsStringSync();
    final adminDeploy = File('scripts/deploy_admin_web.sh').readAsStringSync();
    final publicDeploy = File('scripts/deploy_main_web.sh').readAsStringSync();

    expect(firebaserc, contains('"admin": [\n          "circum-admin-2797c"'));
    expect(firebaserc, contains('"public": [\n          "circum-2797c"'));
    expect(firebase, contains('"target": "admin"'));
    expect(firebase, contains('"public": "build/web_admin"'));
    expect(firebase, contains('"target": "public"'));
    expect(firebase, contains('"public": "build/web_main"'));
    expect(adminDeploy, contains('--target lib/main_admin.dart'));
    expect(adminDeploy, contains('scripts/verify_hosting_build.sh admin'));
    expect(adminDeploy, contains('--only hosting:admin'));
    expect(publicDeploy, contains('scripts/verify_hosting_build.sh public'));
    expect(publicDeploy, contains('--only hosting:public,hosting:app'));
  });
}
