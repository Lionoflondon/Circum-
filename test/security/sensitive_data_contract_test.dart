import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender auth and booking code do not persist or log sensitive data', () {
    final root = Directory.current;
    final sensitiveSources = <File>[
      File('${root.path}/lib/app/authentication/bloc/auth_bloc.dart'),
      File('${root.path}/lib/app/authentication/view/signin_form.dart'),
      File('${root.path}/lib/app/authentication/view/signup_form.dart'),
      File('${root.path}/lib/app/send_package/bloc/send_package_bloc.dart'),
      File('${root.path}/lib/app/sender_mobile/sender_mobile_home.dart'),
    ];

    for (final source in sensitiveSources) {
      expect(source.existsSync(), isTrue, reason: source.path);
      final body = source.readAsStringSync();

      expect(body, isNot(contains("storage.write(key: 'password'")),
          reason: source.path);
      expect(body, isNot(contains('storage.write(key: "password"')),
          reason: source.path);
      expect(body, isNot(contains('readAll())["password"]')),
          reason: source.path);
      expect(body, isNot(contains("readAll())['password']")),
          reason: source.path);
      expect(body, isNot(contains('credential?.accessToken')),
          reason: source.path);
      expect(body, isNot(contains('credential?.token')), reason: source.path);
      expect(body, isNot(contains('FCMToken:')), reason: source.path);
      expect(body, isNot(contains('apnsToken:')), reason: source.path);
      expect(body, isNot(contains('analyseIris request payload')),
          reason: source.path);
      expect(body, isNot(contains('analyseIris response payload')),
          reason: source.path);
      expect(body, isNot(contains('CircumPreview!')), reason: source.path);
    }
  });
}
