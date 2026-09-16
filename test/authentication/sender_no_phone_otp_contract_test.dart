import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final authBloc = File(
    'lib/app/authentication/bloc/auth_bloc.dart',
  ).readAsStringSync();
  final accountClosure = File(
    'lib/app/authentication/sender_account_closure.dart',
  ).readAsStringSync();

  test('Sender authentication has no active phone OTP provider path', () {
    expect(authBloc, isNot(contains('auth.verifyPhoneNumber')));
    expect(authBloc, isNot(contains('PhoneAuthProvider.credential')));
    expect(authBloc, isNot(contains('add(RequestForOTP')));
    expect(authBloc, isNot(contains('add(VerifySentCode')));
  });

  test('Sender account closure has no phone reauthentication path', () {
    expect(accountClosure, isNot(contains('closeWithPhoneCredential')));
    expect(
      accountClosure,
      isNot(contains('SenderReauthenticationProvider.phone')),
    );
  });

  test('phone remains profile data without becoming an auth provider', () {
    final phoneHandler = authBloc.substring(
      authBloc.indexOf('void _handleUpdatePhoneNumber'),
      authBloc.indexOf('void _handleUpdateUserProfilePhoto'),
    );
    expect(
      phoneHandler,
      isNot(contains('_updateSenderProfile(phone: event.value)')),
    );
    expect(phoneHandler, contains("write(key: 'phone', value: event.value)"));
    expect(phoneHandler, contains('timeout(_authOperationTimeout)'));
    expect(phoneHandler, contains('status: Status.failure'));
  });
}
