import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy Sender onboarding has no registered or executable entry point',
      () {
    final appSource = File('lib/app.dart').readAsStringSync();
    expect(appSource, isNot(contains('OnboardingView')));
    expect(appSource, isNot(contains('OnboardingSlider')));
    expect(appSource, isNot(contains('IndexPage')));
    expect(
        File('lib/app/onboarding/view/onboarding.dart').existsSync(), isFalse);
    expect(File('lib/app/onboarding/view/onboarding_slider.dart').existsSync(),
        isFalse);
    expect(File('lib/app/authentication/view/index_page.dart').existsSync(),
        isFalse);
  });

  test('Sender Android launch uses the static splash asset', () {
    final launchStyles = [
      File('android/app/src/main/res/values-v31/styles.xml'),
      File('android/app/src/main/res/values-night-v31/styles.xml'),
    ];

    for (final style in launchStyles) {
      final source = style.readAsStringSync();
      expect(source, contains('@drawable/splash'));
      expect(source, isNot(contains('@drawable/android12splash')));
    }

    final androidSplashResources =
        Directory('android/app/src/main/res').listSync(recursive: true);
    expect(
      androidSplashResources
          .whereType<File>()
          .where((file) => file.path.endsWith('/android12splash.png')),
      isEmpty,
    );
  });
}
