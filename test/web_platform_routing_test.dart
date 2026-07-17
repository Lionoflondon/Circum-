import 'dart:io';

import 'package:circum/web_platform_routing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Circum Web Platform path routing', () {
    test('/ selects Public Web', () {
      final route = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/'),
        adminHostingTarget: false,
        publicHostingHost: true,
      );

      expect(route.surface, CircumWebSurface.public);
      expect(route.canonicalPath, '/');
    });

    test('/send and /send/... select Sender Web', () {
      for (final path in ['/send', '/send/', '/send/profile']) {
        final route = resolveCircumWebRoute(
          Uri.parse('https://circumuk.com$path'),
          adminHostingTarget: false,
          publicHostingHost: true,
        );

        expect(route.surface, CircumWebSurface.sender);
      }
    });

    test('/rider and /rider/... select Rider Web', () {
      for (final path in ['/rider', '/rider/', '/rider/jobs']) {
        final route = resolveCircumWebRoute(
          Uri.parse('https://circumuk.com$path'),
          adminHostingTarget: false,
          publicHostingHost: true,
        );

        expect(route.surface, CircumWebSurface.rider);
      }
    });

    test('Sender feature deep links select canonical Sender entry', () {
      final health = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/send/health'),
        adminHostingTarget: false,
        publicHostingHost: true,
      );
      final business = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/send/business'),
        adminHostingTarget: false,
        publicHostingHost: true,
      );
      final profile = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/send/profile'),
        adminHostingTarget: false,
        publicHostingHost: true,
      );

      expect(health.senderEntry, CircumSenderEntry.healthPlus);
      expect(business.senderEntry, CircumSenderEntry.business);
      expect(profile.senderEntry, CircumSenderEntry.profile);
    });

    test('legacy app query URLs request one canonical redirect', () {
      final sender = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/?app=sender'),
        adminHostingTarget: false,
        publicHostingHost: true,
      );
      final rider = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/?app=rider'),
        adminHostingTarget: false,
        publicHostingHost: true,
      );

      expect(sender.surface, CircumWebSurface.sender);
      expect(sender.legacyRedirectPath, '/send');
      expect(rider.surface, CircumWebSurface.rider);
      expect(rider.legacyRedirectPath, '/rider');
    });

    test('admin hosting remains compile-time isolated', () {
      final route = resolveCircumWebRoute(
        Uri.parse('https://circum-admin-2797c.web.app/send'),
        adminHostingTarget: true,
        publicHostingHost: false,
      );

      expect(route.surface, CircumWebSurface.admin);
    });
  });

  group('Circum Web Platform source guards', () {
    test(
      'web bootstrap uses path resolver instead of query root selection',
      () {
        final source = File('lib/web_sender_app.dart').readAsStringSync();

        expect(source, contains('resolveCircumWebRoute'));
        expect(source, contains('Uri.base'));
        expect(
          source,
          isNot(contains("switch (Uri.base.queryParameters['app'])")),
        );
        expect(source, isNot(contains("case '?app=sender'")));
      },
    );

    test('Rider Web does not mount the standalone Rider App host', () {
      final source = File('lib/web_sender_app.dart').readAsStringSync();

      expect(source, contains('_RiderEnrollmentPortal'));
      expect(source, isNot(contains('circum-rider-2797c.web.app')));
      expect(source, isNot(contains('CircumRiderApp')));
    });

    test('stable build identity markers are present', () {
      final source = File('lib/web_sender_app.dart').readAsStringSync();
      final routing = File('lib/web_platform_routing.dart').readAsStringSync();

      expect(routing, contains(circumPublicWebIdentity));
      expect(routing, contains(circumSenderWebIdentity));
      expect(routing, contains(circumRiderWebIdentity));
      expect(source, contains('ValueKey(circumPublicWebIdentity)'));
      expect(source, contains('ValueKey(circumSenderWebIdentity)'));
      expect(source, contains('ValueKey(circumRiderWebIdentity)'));
    });
  });
}
