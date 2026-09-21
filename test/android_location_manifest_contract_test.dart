import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final dartSources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .map((file) => file.readAsStringSync())
      .join('\n');

  test('Sender does not package an unused location foreground service', () {
    expect(
      pubspec,
      isNot(matches(RegExp(r'^\s*location:\s', multiLine: true))),
    );
    expect(dartSources, isNot(contains('package:location/')));
    expect(dartSources, isNot(contains('Geolocator.getPositionStream')));
    expect(
      manifest,
      contains('com.baseflow.geolocator.GeolocatorLocationService'),
    );
    expect(manifest, contains('tools:node="remove"'));
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_LOCATION')));
  });
}
