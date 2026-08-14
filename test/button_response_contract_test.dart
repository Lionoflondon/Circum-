import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('visible app and web buttons do not keep empty enabled callbacks', () {
    final files = [
      ...Directory('lib/app').listSync(recursive: true),
      ...Directory('lib/website').listSync(recursive: true),
    ].whereType<File>().where((file) => file.path.endsWith('.dart'));

    final emptyCallback = RegExp(
      r'(onPressed|onTap)\s*:\s*(?:\([^)]*\)|[A-Za-z0-9_]+)?\s*(?:async\s*)?'
      r'(?:=>\s*null|=>\s*\{\}|=>\s*Future\.value\(\)|\{\s*\})',
      multiLine: true,
    );
    final offenders = <String>[];

    for (final file in files) {
      final source = file.readAsStringSync();
      final uncommented = source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final match in emptyCallback.allMatches(uncommented)) {
        offenders.add('${file.path}: ${match.group(0)}');
      }
    }

    expect(offenders, isEmpty);
  });
}
