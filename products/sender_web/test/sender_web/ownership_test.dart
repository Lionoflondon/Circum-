import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender package owns all runtime and deployment inputs', () {
    final source = Directory('lib').listSync(recursive: true).whereType<File>()
        .map((file) => file.readAsStringSync()).join('\n');
    expect(source, isNot(contains('shared_web/')));
    expect(source, isNot(contains('public_web/')));
    expect(File('firebase.json').readAsStringSync(), isNot(contains('hosting:public')));
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/sender/'));
  });
}
