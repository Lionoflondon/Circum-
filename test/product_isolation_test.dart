import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonical Circum web platform isolation', () {
    final publicEntry =
        File('lib/public_web/main_public.dart').readAsStringSync();
    final publicApp = File('lib/public_web/public_app.dart').readAsStringSync();
    final senderEntry =
        File('lib/sender_web/main_sender_web.dart').readAsStringSync();
    final riderEntry =
        File('lib/rider_web/main_rider_web.dart').readAsStringSync();
    final firebase = jsonDecode(File('firebase.json').readAsStringSync())
        as Map<String, dynamic>;

    test('each browser product boots its own root', () {
      expect(publicEntry, contains('CircumPublicWebsiteApp'));
      expect(senderEntry, contains('WebSenderApp'));
      expect(riderEntry, contains('CircumRiderWebApp'));
      expect(publicEntry, isNot(contains('WebSenderApp')));
      expect(publicEntry, isNot(contains('CircumRiderWebApp')));
      expect(senderEntry, isNot(contains('CircumRiderWebApp')));
      expect(riderEntry, isNot(contains('WebSenderApp')));
    });

    test('public navigation enters route-mounted applications', () {
      expect(publicApp, contains("const _canonicalSenderAppUrl = '/send'"));
      expect(publicApp, contains("const _canonicalRiderWebUrl = '/rider'"));
      expect(publicApp, contains('_openExternal(_canonicalSenderAppUrl)'));
      expect(publicApp, contains('_openExternal(_canonicalRiderWebUrl)'));
    });

    test('public hosting routes Sender and Rider Web bundles independently',
        () {
      final hosting =
          (firebase['hosting'] as List).cast<Map<String, dynamic>>();
      final public = hosting.singleWhere((item) => item['target'] == 'public');
      final rewrites =
          (public['rewrites'] as List).cast<Map<String, dynamic>>();
      expect(public['public'], 'build/web_platform');
      expect(
        rewrites.any((route) =>
            route['source'] == '/send/**' &&
            route['destination'] == '/send/index.html'),
        isTrue,
      );
      expect(
        rewrites.any((route) =>
            route['source'] == '/rider/**' &&
            route['destination'] == '/rider/index.html'),
        isTrue,
      );
    });

    test('standalone Rider App hosting remains isolated', () {
      final hosting =
          (firebase['hosting'] as List).cast<Map<String, dynamic>>();
      final rider = hosting.singleWhere((item) => item['target'] == 'rider');
      expect(rider['public'], 'build/web_rider');
      expect(
        rider['predeploy'],
        contains('node scripts/block_rider_deploy_from_circum.js'),
      );
    });

    test('shared shell provides consistent cross-platform navigation', () {
      final shell =
          File('lib/shared_web/circum_web_shell.dart').readAsStringSync();
      final sender = File('lib/web_sender_app.dart').readAsStringSync();

      expect(shell, contains("label: 'Home'"));
      expect(shell, contains("label: 'Sender'"));
      expect(shell, contains("label: 'Rider'"));
      expect(shell, contains("label: 'Profile'"));
      expect(shell, contains("html.window.location.assign(path)"));
      expect(shell, contains('FirebaseAuth.instance.authStateChanges()'));
      expect(shell, contains('readCircumWebDarkMode'));
      expect(publicApp, contains('section: CircumWebSection.home'));
      expect(sender, contains('section: CircumWebSection.sender'));
      expect(sender, contains('section: CircumWebSection.rider'));
    });

    test('legacy product headers no longer render inside the shared shell', () {
      final sender = File('lib/web_sender_app.dart').readAsStringSync();
      final publicLanding = publicApp.substring(
        publicApp.indexOf('class _LandingPage'),
        publicApp.indexOf('List<String> _interests'),
      );
      final riderBuild = sender.substring(
        sender.indexOf('class _RiderEnrollmentPortalState'),
        sender.indexOf('class _RiderPublicIntro'),
      );
      expect(publicLanding, isNot(contains('_LandingNav(')));
      expect(riderBuild, isNot(contains('_PortalHeader(')));
      expect('_PortalHeader('.allMatches(sender), hasLength(1));
      expect('_LandingNav('.allMatches(publicApp), hasLength(1));
    });
  });
}
