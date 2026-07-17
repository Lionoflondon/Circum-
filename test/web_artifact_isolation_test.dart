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

    test('Public and Sender hosting targets use different directories', () {
      expect(target('public')['public'], 'build/public_web');
      expect(target('app')['public'], 'build/sender_app_web');
      expect(target('public')['public'], isNot(target('app')['public']));
    });

    test('all configured hosting outputs are unique', () {
      final outputs = hosting.map((entry) => entry['public']).toList();
      expect(outputs.toSet(), hasLength(outputs.length));
      expect(outputs, contains('build/public_web'));
      expect(outputs, contains('build/sender_app_web'));
      expect(outputs, contains('build/web_admin'));
    });

    test('build scripts reference fixed entrypoints', () {
      final publicBuild =
          File('scripts/build_public_web.sh').readAsStringSync();
      final senderBuild =
          File('scripts/build_sender_app_web.sh').readAsStringSync();

      expect(publicBuild, contains('--target=lib/main_public_web.dart'));
      expect(publicBuild, contains('--dart-define=CIRCUM_WEB_SURFACE=public'));
      expect(publicBuild, contains('build/public_web'));
      expect(senderBuild, contains('--target=lib/main_sender_web.dart'));
      expect(senderBuild, contains('--dart-define=CIRCUM_WEB_SURFACE=sender'));
      expect(senderBuild, contains('build/sender_app_web'));
    });

    test('deploy scripts target only one surface each', () {
      final publicDeploy =
          File('scripts/deploy_public_web.sh').readAsStringSync();
      final senderDeploy =
          File('scripts/deploy_sender_app_web.sh').readAsStringSync();
      final oldMainDeploy =
          File('scripts/deploy_main_web.sh').readAsStringSync();

      expect(publicDeploy, contains('hosting:public'));
      expect(publicDeploy, isNot(contains('hosting:app')));
      expect(senderDeploy, contains('hosting:app'));
      expect(senderDeploy, isNot(contains('hosting:public')));
      expect(oldMainDeploy, contains('intentionally disabled'));
    });

    test('entrypoints pin their intended web surface', () {
      final publicMain = File('lib/main_public_web.dart').readAsStringSync();
      final senderMain = File('lib/main_sender_web.dart').readAsStringSync();

      expect(publicMain, contains('CircumWebSurface.public'));
      expect(senderMain, contains('CircumWebSurface.sender'));
      expect(publicMain, isNot(contains('CircumWebSurface.sender')));
      expect(senderMain, isNot(contains('CircumWebSurface.public')));
    });
  });
}
