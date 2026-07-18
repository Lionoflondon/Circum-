import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('web artifact isolation configuration', () {
    late Map<String, dynamic> firebase;
    late List<Map<String, dynamic>> hosting;

    setUpAll(() {
      firebase = jsonDecode(File('firebase.json').readAsStringSync())
          as Map<String, dynamic>;
      hosting =
          (firebase['hosting'] as List<dynamic>).cast<Map<String, dynamic>>();
    });

    Map<String, dynamic> target(String name) {
      return hosting.firstWhere((entry) => entry['target'] == name);
    }

    test('Website and Admin hosting targets use different directories', () {
      expect(target('public')['public'], 'build/public_web');
      expect(target('admin')['public'], 'build/web_admin');
      expect(target('public')['public'], isNot(target('admin')['public']));
    });

    test('all configured hosting outputs are unique', () {
      final outputs = hosting.map((entry) => entry['public']).toList();
      expect(outputs.toSet(), hasLength(outputs.length));
      expect(outputs, contains('build/public_web'));
      expect(outputs, contains('build/web_admin'));
      expect(outputs, isNot(contains('build/sender_app_web')));
    });

    test('build scripts reference fixed entrypoints', () {
      final publicBuild =
          File('scripts/build_public_web.sh').readAsStringSync();

      expect(publicBuild, contains('--target=lib/main_public_web.dart'));
      expect(publicBuild, isNot(contains('CIRCUM_WEB_SURFACE')));
      expect(publicBuild,
          contains('--dart-define=CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY='));
      expect(publicBuild, contains('build/public_web'));
    });

    test('deploy scripts target the Website and legacy Sender Web is removed',
        () {
      final publicDeploy =
          File('scripts/deploy_public_web.sh').readAsStringSync();

      expect(publicDeploy, contains('hosting:public'));
      expect(publicDeploy, isNot(contains('hosting:app')));
      expect(File('scripts/deploy_sender_app_web.sh').existsSync(), isFalse);
      expect(File('scripts/build_sender_app_web.sh').existsSync(), isFalse);
      expect(File('scripts/deploy_main_web.sh').existsSync(), isFalse);
    });

    test('entrypoints keep Website separate from Sender App and Admin', () {
      final publicMain = File('lib/main_public_web.dart').readAsStringSync();
      final mobileMain = File('lib/main.dart').readAsStringSync();
      final adminMain = File('lib/main_admin_web.dart').readAsStringSync();

      expect(publicMain, contains('CircumWebsiteApp'));
      expect(publicMain, isNot(contains('initialSurface')));
      expect(File('lib/main_sender_web.dart').existsSync(), isFalse);
      expect(publicMain, isNot(contains('CircumWebSurface.sender')));
      expect(mobileMain, isNot(contains('CircumWebsiteApp')));
      expect(mobileMain, isNot(contains('website/')));
      expect(adminMain, contains('AdminRoot'));
      expect(adminMain, isNot(contains('CircumWebsiteApp')));
      expect(adminMain, isNot(contains('SenderMobileHome')));
    });
  });
}
