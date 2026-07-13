import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sender/Public product isolation', () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    final firebase = File('firebase.json').readAsStringSync();

    test('direct Rider path stays inside public website routing', () {
      final riderRoute = source.substring(
        source.indexOf("if (path == '/rider')"),
        source.indexOf("if (path == '/gifts')"),
      );

      expect(riderRoute, contains('surface: CircumAppSurface.publicWebsite'));
      expect(riderRoute, isNot(contains('CircumAppSurface.riderApp')));
      expect(riderRoute, isNot(contains('circum-rider-2797c.web.app')));
    });

    test('legacy Rider app aliases do not select Rider UI', () {
      final riderAliases = source.substring(
        source.indexOf("'rider' ||"),
        source.indexOf("'gifts' =>"),
      );

      expect(riderAliases, contains('surface: CircumAppSurface.publicWebsite'));
      expect(riderAliases, isNot(contains('CircumAppSurface.riderApp')));
      expect(riderAliases, isNot(contains('CircumRiderAppRoot')));
    });

    test('public and sender hosting do not redirect to Rider app', () {
      final config = jsonDecode(firebase) as Map<String, dynamic>;
      final hosting = (config['hosting'] as List).cast<Map<String, dynamic>>();
      for (final target in const ['public', 'sender']) {
        final site = hosting.singleWhere((item) => item['target'] == target);
        final redirects =
            (site['redirects'] as List?)?.cast<Map<String, dynamic>>() ??
                const <Map<String, dynamic>>[];
        expect(
          redirects.any((redirect) =>
              '${redirect['source']}'.contains('rider') ||
              '${redirect['destination']}'.contains('circum-rider')),
          isFalse,
        );
      }
    });

    test('Sender/Public bundle has no hosted Rider app UI redirect root', () {
      expect(source, isNot(contains('const _canonicalRiderAppUrl')));
      expect(source, isNot(contains('CircumRiderAppRoot')));
      expect(source, isNot(contains('html.window.location.replace')));
      expect(source, isNot(contains('CircumAppSurface.riderApp')));
      expect(source, isNot(contains('CircumAppSurface.riderStripeConnect')));
    });
  });
}
