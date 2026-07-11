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

  test('Sender Hosting root resolves to the Sender app', () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    expect(source, contains('_isSenderAppHostingHostFor(uri)'));
    expect(source,
        contains("uri.host.toLowerCase() == 'circum-app-2797c.web.app'"));
    final senderHostRoute = source.substring(
      source.indexOf('if (_isSenderAppHostingHostFor(uri)'),
      source.indexOf('// Temporary architecture-preview routes'),
    );
    expect(senderHostRoute, contains('surface: CircumAppSurface.senderApp'));
    expect(
        senderHostRoute, contains('senderEntry: CircumSenderEntry.dashboard'));
    expect(senderHostRoute, contains('useSenderPreview: true'));
    expect(
        source,
        contains(
            "import 'package:circum/app/sender_mobile/sender_mobile_home.dart';"));
    expect(
        source, contains('const SenderMobileHome(previewAuthEnabled: true)'));
  });

  test('hosting aliases and build outputs are permanently isolated', () {
    final firebaserc = File('.firebaserc').readAsStringSync();
    final firebase = File('firebase.json').readAsStringSync();
    final adminDeploy = File('scripts/deploy_admin_web.sh').readAsStringSync();
    final publicDeploy = File('scripts/deploy_main_web.sh').readAsStringSync();
    final senderDeploy =
        File('scripts/deploy_sender_app.sh').readAsStringSync();

    expect(firebaserc, contains('"admin": [\n          "circum-admin-2797c"'));
    expect(firebaserc, contains('"public": [\n          "circum-2797c"'));
    expect(firebaserc, contains('"sender": [\n          "circum-app-2797c"'));
    expect(firebase, contains('"target": "admin"'));
    expect(firebase, contains('"public": "build/web_admin"'));
    expect(firebase, contains('"target": "public"'));
    expect(firebase, contains('"public": "build/web_main"'));
    expect(firebase, contains('"target": "sender"'));
    expect(firebase, contains('"public": "build/web_sender"'));
    expect(
      firebase,
      contains('node scripts/hosting_manifest.js verify admin'),
    );
    expect(
      firebase,
      contains('node scripts/hosting_manifest.js verify public'),
    );
    expect(
      firebase,
      contains('node scripts/hosting_manifest.js verify sender'),
    );
    expect(adminDeploy, contains('--target lib/main_admin.dart'));
    expect(adminDeploy, contains('hosting_manifest.js prepare admin'));
    expect(adminDeploy, contains('scripts/verify_hosting_build.sh admin'));
    expect(adminDeploy, contains('--only hosting:admin'));
    expect(publicDeploy, contains('hosting_manifest.js prepare public'));
    expect(publicDeploy, contains('scripts/verify_hosting_build.sh public'));
    expect(publicDeploy, contains('--only hosting:public'));
    expect(senderDeploy, contains('hosting_manifest.js prepare sender'));
    expect(senderDeploy, contains('scripts/verify_hosting_build.sh sender'));
    expect(senderDeploy, contains('--only hosting:sender'));
  });

  test('generic Hosting deployment entry points are absent', () {
    expect(File('scripts/deploy_all_web.sh').existsSync(), isFalse);
    final guard = File('scripts/hosting_manifest.js').readAsStringSync();
    expect(guard, contains('forbidden untargeted Hosting deployment'));
  });
}
