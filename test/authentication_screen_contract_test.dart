import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('auth forms dispose text controllers', () {
    for (final path in [
      'lib/app/authentication/view/signin_form.dart',
      'lib/app/authentication/view/signup_form.dart',
    ]) {
      final content = source(path);
      expect(content, contains('void dispose()'));
      expect(content, contains('emailController.dispose();'));
      expect(content, contains('passwordController.dispose();'));
    }
  });

  test('auth email validity icons are passive accessibility nodes', () {
    for (final path in [
      'lib/app/authentication/view/signin_form.dart',
      'lib/app/authentication/view/signup_form.dart',
      'lib/app/authentication/view/forgot_password.dart',
    ]) {
      final content = source(path);
      expect(content, contains('child: ExcludeSemantics('));
      expect(
          content,
          isNot(contains('child: GestureDetector(\n'
              '                          onTap: () => context\n'
              '                              .read<AuthBloc>()\n'
              '                              .add(SetShowPassword')));
    }
  });

  test('password visibility controls expose accessible labels', () {
    for (final path in [
      'lib/app/authentication/view/signin_form.dart',
      'lib/app/authentication/view/signup_form.dart',
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ]) {
      final content = source(path);
      expect(content, contains('IconButton('));
      expect(content, contains("'Hide password'"));
      expect(content, contains("'Show password'"));
    }
  });

  test('sender app auth disables busy submit and validates account password',
      () {
    final content = source('lib/app/sender_mobile/sender_mobile_home.dart');
    expect(content, contains('onTap: _busy ? null : () => _submit()'));
    expect(content, contains("_password.text.length >= 6"));
    expect(content, contains("'Use at least 6 characters'"));
  });
}
