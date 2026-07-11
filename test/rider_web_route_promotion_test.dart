import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonical Rider web route', () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    final firebase = File('firebase.json').readAsStringSync();

    test('direct Rider route selects the dedicated Rider application', () {
      final riderRoute = source.substring(
        source.indexOf("if (path == '/rider')"),
        source.indexOf("if (path == '/gifts')"),
      );

      expect(riderRoute, contains('surface: CircumAppSurface.riderApp'));
      expect(riderRoute, isNot(contains('useRiderPreview: true')));
    });

    test('Rider query aliases do not select the architecture preview', () {
      final riderAliases = source.substring(
        source.indexOf("'rider' ||"),
        source.indexOf("'gifts' =>"),
      );

      expect(riderAliases, contains('surface: CircumAppSurface.riderApp'));
      expect(riderAliases, isNot(contains('useRiderPreview: true')));
    });

    test('main hosting redirects Rider surfaces to the canonical Rider site',
        () {
      expect(
        source,
        contains(
            "const _canonicalRiderAppUrl = 'https://circum-rider-2797c.web.app'"),
      );
      final riderRoot = source.substring(
        source.indexOf('class CircumRiderAppRoot'),
        source.indexOf('class CircumRiderStripeConnectRoute'),
      );

      expect(riderRoot,
          contains('html.window.location.replace(_canonicalRiderAppUrl)'));
      expect(riderRoot, isNot(contains('_RiderEnrollmentPortal(')));
      expect(riderRoot, isNot(contains('_RiderArchitecturePreviewApp(')));
    });

    test('public hosting redirects the exact Rider entry before app boot', () {
      expect(firebase, contains('"source": "/rider"'));
      expect(firebase,
          contains('"destination": "https://circum-rider-2797c.web.app"'));
      expect(firebase, contains('"type": 302'));
    });
  });
}
