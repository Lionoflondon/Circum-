import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender source does not import Website, Admin, or Rider products', () {
    final senderRoots = <String>[
      'lib/main.dart',
      'lib/app.dart',
      'lib/messaging.dart',
      'lib/app/sender_mobile',
      'lib/app/send_package',
      'lib/app/business',
      'lib/app/health_plus',
      'lib/app/gifts',
      'lib/app/support',
      'lib/app/account',
      'lib/app/history',
    ];
    final forbidden = <Pattern>[
      'package:circum/website/',
      'lib/website/',
      '../website/',
      'app/admin/',
      'package:circum/app/admin/',
      'main_admin_web',
      'main_public_web',
      'Circum-Rider',
    ];

    final files = senderRoots.expand((root) {
      final type = FileSystemEntity.typeSync(root);
      if (type == FileSystemEntityType.file) return [File(root)];
      if (type != FileSystemEntityType.directory) return const <File>[];
      return Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
    });

    final offenders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final pattern in forbidden) {
        if (source.contains(pattern)) {
          offenders.add('${file.path}: $pattern');
        }
      }
    }

    expect(offenders, isEmpty);
  });
}
