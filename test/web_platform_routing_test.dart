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

    test('privacy paths select the canonical public privacy page', () {
      for (final path in ['/privacy', '/privacy-policy', '/privacy_policy']) {
        final route = resolveCircumWebRoute(
          Uri.parse('https://circumuk.com$path'),
          adminHostingTarget: false,
          publicHostingHost: true,
        );

        expect(route.surface, CircumWebSurface.privacyPolicy);
        expect(route.canonicalPath, '/privacy_policy');
      }
    });

    test('/terms selects the consolidated public Terms & Conditions page', () {
      final route = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/terms'),
        adminHostingTarget: false,
        publicHostingHost: true,
      );

      expect(route.surface, CircumWebSurface.terms);
      expect(route.canonicalPath, '/terms');
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

    test('/vanguard selects the canonical public Vanguard page', () {
      final route = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/vanguard'),
        adminHostingTarget: false,
        publicHostingHost: true,
      );

      expect(route.surface, CircumWebSurface.vanguard);
      expect(route.canonicalPath, '/vanguard');
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

    test('hash-style feature deep links select canonical entries', () {
      final health = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/#/send/health'),
        adminHostingTarget: false,
        publicHostingHost: true,
      );
      final business = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/#/send/business'),
        adminHostingTarget: false,
        publicHostingHost: true,
      );
      final rider = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/#/rider'),
        adminHostingTarget: false,
        publicHostingHost: true,
      );

      expect(health.surface, CircumWebSurface.sender);
      expect(health.canonicalPath, '/send/health');
      expect(health.senderEntry, CircumSenderEntry.healthPlus);
      expect(business.surface, CircumWebSurface.sender);
      expect(business.canonicalPath, '/send/business');
      expect(business.senderEntry, CircumSenderEntry.business);
      expect(rider.surface, CircumWebSurface.rider);
      expect(rider.canonicalPath, '/rider');
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
      'Website bootstrap uses path resolver instead of product switching',
      () {
        expect(File('lib/web_sender_app.dart').existsSync(), isFalse);
        final source = File('lib/website/shared/circum_website_app.dart')
            .readAsStringSync();

        expect(source, contains('resolveCircumWebRoute'));
        expect(source, contains('Uri.base'));
        expect(source, isNot(contains('CIRCUM_WEB_SURFACE')));
        expect(source, isNot(contains('bool.fromEnvironment')));
        expect(
          source,
          isNot(contains("switch (Uri.base.queryParameters['app'])")),
        );
        expect(source, isNot(contains("case '?app=sender'")));
      },
    );

    test('Rider Web does not mount the standalone Rider App shell', () {
      final source =
          File('lib/website/shared/circum_website_app.dart').readAsStringSync();

      expect(source, contains('_RiderEnrollmentPortal'));
      expect(source, isNot(contains('CircumRiderApp')));
    });

    test('stable build identity markers are present', () {
      final source =
          File('lib/website/shared/circum_website_app.dart').readAsStringSync();
      final routing = File('lib/web_platform_routing.dart').readAsStringSync();

      expect(routing, contains(circumPublicWebIdentity));
      expect(routing, contains(circumSenderWebIdentity));
      expect(routing, contains(circumRiderWebIdentity));
      expect(source, contains('ValueKey(circumPublicWebIdentity)'));
      expect(source, contains('ValueKey(circumSenderWebIdentity)'));
      expect(source, contains('ValueKey(circumRiderWebIdentity)'));
    });

    test('Public homepage keeps Health Vanguard and Business entries', () {
      final source =
          File('lib/website/shared/circum_website_app.dart').readAsStringSync();

      expect(source, contains('Get started with Health+'));
      expect(source, contains('Health+'));
      expect(source, contains("_WebAppMode.rider => '/rider'"));
      expect(source, contains("_SenderStep.healthPlus => '/send/health'"));
      expect(source, contains("_SenderStep.business => '/send/business'"));
      expect(source, contains("fragment: ''"));
      expect(source, isNot(contains("label: 'Business delivery'")));
      expect(source, isNot(contains("label: 'Vanguard protection'")));
      expect(source, contains('Open Business'));
      expect(source, contains('Trust matters more than speed.'));
      expect(source, contains('Trusted Rider Prioritisation'));
      expect(source, contains('Enhanced Custody Tracking'));
      expect(source, contains('Priority Support'));
      expect(source, contains('Priority Dispute Review'));
      expect(source, contains("label: 'Vanguard'"));
      expect(source, contains("label: 'Vanguard Included'"));
      expect(source, contains('Corporate Gifts · Vanguard Included'));
      expect(source, contains('Add Vanguard for £1.99'));
      expect(source, contains('senderStep: _SenderStep.business'));
    });

    test('Business and Health web keep app-style section parity', () {
      final source =
          File('lib/website/shared/circum_website_app.dart').readAsStringSync();

      expect(source, contains('enum _BusinessWebSection'));
      for (final label in [
        'Overview',
        'Deliveries',
        'Invoices',
        'Team',
        'Health+',
        'Gifts',
        'Vanguard',
        'Analytics',
        'Finance',
        'Settings',
      ]) {
        expect(source, contains("return '$label';"));
      }
      expect(source, contains('Scrollable.ensureVisible'));
      expect(source, contains('onSelectSection'));
      expect(source, contains('Health+ sections'));
      expect(source, contains('Business sections'));
    });

    test('Sender delivery payload leaves Rider offer display aliases to backend', () {
      final source =
          File('lib/website/shared/circum_website_app.dart').readAsStringSync();
      expect(source, isNot(contains("'riderEarning': driverPayout")));
      expect(source, isNot(contains("'requiresVanguard': vanguardEnabled")));
      expect(source, contains("httpsCallable('createSenderPaidDelivery')"));
    });

    test('Vanguard copy avoids customer rider choice wording', () {
      final source =
          File('lib/website/shared/circum_website_app.dart').readAsStringSync();

      expect(source, contains('Customers do not choose riders'));
      expect(source, contains('Vanguard is not insurance'));
      expect(source, contains('Vanguard Handling'));
      expect(source, contains('Custody preview'));
      expect(source, contains('When to use it'));
      expect(source, contains('What £1.99 adds'));
      expect(source, contains('Gifts and keepsakes'));
      expect(source, contains('Passports and travel documents'));
      expect(source, contains('Better handling for important items'));
      expect(source, isNot(contains('Preferred rider matching')));
      expect(source, isNot(contains('Choose your rider')));
      expect(source, isNot(contains('Pick a rider')));
      expect(source, isNot(contains('Favourite rider')));
      expect(source, isNot(contains('Dedicated rider')));
    });

    test('Website does not compile mobile app or Admin console entrypoints',
        () {
      final source =
          File('lib/website/shared/circum_website_app.dart').readAsStringSync();

      expect(source,
          isNot(contains("package:circum/app/admin/admin_operations.dart")));
      expect(source, isNot(contains("package:circum/app/sender_mobile/")));
      expect(source, isNot(contains('SenderMobileHome')));
      expect(source, isNot(contains('_AdminOperationsPanel')));
    });
  });
}
