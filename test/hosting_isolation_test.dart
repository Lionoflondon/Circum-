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
    expect(senderHostRoute, contains('senderEntry: _senderEntryFromPath'));
    expect(senderHostRoute, contains('routeDeliveryId: routeDeliveryId'));
    expect(senderHostRoute,
        contains('useSenderMobileApp: routeDeliveryId == null'));
    expect(source, contains("'send' || 'booking' || 'book'"));
    expect(source, contains("'/send' || '/booking' || '/book'"));
    expect(source, contains("'/wallet'"));
    expect(source, contains("'/activity' || '/history'"));
    expect(
      source,
      contains("'/profile' || '/account' => CircumSenderEntry.account"),
    );
    expect(source, contains('initialIndex: _senderMobileIndexForEntry'));
    expect(
        source,
        contains(
            "import 'package:circum/app/sender_mobile/sender_mobile_home.dart';"));
    expect(source, contains('SenderMobileHome('));
    expect(source, contains('previewAuthEnabled: true'));
    expect(source, isNot(contains('useSenderPreview')));
    expect(source, isNot(contains('_SenderArchitecturePreviewApp(')));
  });

  test('hosting aliases and build outputs are permanently isolated', () {
    final firebaserc = File('.firebaserc').readAsStringSync();
    final firebase = File('firebase.json').readAsStringSync();
    final adminDeploy = File('scripts/deploy_admin_web.sh').readAsStringSync();
    final publicDeploy = File('scripts/deploy_main_web.sh').readAsStringSync();
    final senderDeploy =
        File('scripts/deploy_sender_app.sh').readAsStringSync();
    final riderDeploy = File('scripts/deploy_rider_web.sh').readAsStringSync();

    expect(firebaserc, contains('"admin": [\n          "circum-admin-2797c"'));
    expect(firebaserc, contains('"public": [\n          "circum-2797c"'));
    expect(firebaserc, contains('"sender": [\n          "circum-app-2797c"'));
    expect(firebaserc, contains('"rider": [\n          "circum-rider-2797c"'));
    expect(firebase, contains('"target": "admin"'));
    expect(firebase, contains('"public": "build/web_admin"'));
    expect(firebase, contains('"target": "public"'));
    expect(firebase, contains('"public": "build/web_main"'));
    expect(firebase, contains('"target": "sender"'));
    expect(firebase, contains('"public": "build/web_sender"'));
    expect(firebase, contains('"target": "rider"'));
    expect(firebase, contains('"public": "build/web_rider"'));
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
    expect(
      firebase,
      contains('node scripts/hosting_manifest.js verify rider'),
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
    expect(riderDeploy, contains('--target lib/main_rider.dart'));
    expect(riderDeploy, contains('hosting_manifest.js prepare rider'));
    expect(riderDeploy, contains('scripts/verify_hosting_build.sh rider'));
    expect(riderDeploy, contains('--only hosting:rider'));
    expect(riderDeploy, isNot(contains('CIRCUM_RIDER_HOSTING')));
  });

  test('Rider app has a dedicated root with no workspace selector', () {
    final entry = File('lib/main_rider.dart').readAsStringSync();
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    final riderRoot = source.substring(
      source.indexOf('class CircumRiderApp'),
      source.indexOf('class _WebSenderAppState'),
    );
    final riderPortal = source.substring(
      source.indexOf('class _RiderEnrollmentPortal'),
      source.indexOf('class _RiderPublicIntro'),
    );
    final guard = File('scripts/hosting_manifest.js').readAsStringSync();

    expect(entry, contains('runApp(const _RiderStartup())'));
    expect(entry, contains('return const CircumRiderApp()'));
    expect(entry, isNot(contains('WebSenderApp')));
    expect(entry, isNot(contains('CircumAdminAppRoot')));
    expect(riderRoot, contains("ValueKey('rider-app-root')"));
    expect(riderRoot, isNot(contains('onRoleSelected')));
    expect(riderPortal, isNot(contains('_MultiRoleChoicePanel')));
    expect(riderPortal, isNot(contains('Choose how to continue')));
    expect(riderPortal, isNot(contains('Continue as Sender')));
    expect(riderPortal, isNot(contains('Continue as Admin')));
    expect(riderPortal, contains("path == '/jobs'"));
    expect(riderPortal, contains("path == '/schedule'"));
    expect(riderPortal, contains("path == '/earnings'"));
    expect(riderPortal, contains("path == '/profile'"));
    expect(guard, contains("product: 'Circum Rider App'"));
    expect(guard, contains("buildIdentity: 'CIRCUM_BUILD_ID=rider-app'"));
    expect(guard, contains("'Continue as Sender'"));
    expect(guard, contains("'Continue as Admin'"));
  });

  test('generic Hosting deployment entry points are absent', () {
    expect(File('scripts/deploy_all_web.sh').existsSync(), isFalse);
    final guard = File('scripts/hosting_manifest.js').readAsStringSync();
    expect(guard, contains('forbidden untargeted Hosting deployment'));
  });

  test('domain guard verifies each product manifest explicitly', () {
    final guard = File('scripts/verify_hosting_domains.sh').readAsStringSync();
    expect(guard, contains('https://circumuk.com/deployment-manifest.json'));
    expect(
        guard, contains('https://www.circumuk.com/deployment-manifest.json'));
    expect(guard,
        contains('https://circum-app-2797c.web.app/deployment-manifest.json'));
    expect(
        guard,
        contains(
            'https://circum-rider-2797c.web.app/deployment-manifest.json'));
    expect(guard, contains('"Circum Web"'));
    expect(guard, contains('"circum-2797c" "public"'));
    expect(guard, contains('"Circum Sender App"'));
    expect(guard, contains('"circum-app-2797c" "sender"'));
    expect(guard, contains('"Circum Rider App"'));
    expect(guard, contains('"circum-rider-2797c" "rider"'));
  });
}
