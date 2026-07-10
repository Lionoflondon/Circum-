import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonical Rider web route', () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();

    test('direct Rider route selects the authenticated Rider portal', () {
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
  });
}
