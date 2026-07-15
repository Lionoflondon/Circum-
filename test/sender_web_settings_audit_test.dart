import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String settings;

  setUpAll(() {
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    settings = source.substring(
      source.indexOf('Widget _settingsTab('),
      source.indexOf('Future<void> _confirmSignOut'),
    );
  });

  test('Sender Web Settings hides unfinished notification preferences', () {
    expect(settings, isNot(contains("title: 'Notifications'")));
    expect(settings, isNot(contains('Marketing preferences')));
    expect(settings, isNot(contains('_DisabledPreference')));
  });

  test('Sender Web Settings opens canonical Terms and Privacy pages', () {
    expect(settings, contains("_openPublicPolicy('/privacy')"));
    expect(settings, contains("_openPublicPolicy('/terms')"));
    expect(settings, contains("Uri.parse('https://circumuk.com\$path')"));
  });

  test('Sender Web Settings routes Gift Card history to Roth history', () {
    expect(settings, contains('Circum Gift Card history'));
    expect(settings, contains('onPressed: () => onTab(3)'));
  });

  test('Sender Web Settings hides unfinished data download', () {
    expect(settings, isNot(contains('Data download')));
  });
}
