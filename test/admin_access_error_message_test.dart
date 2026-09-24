import 'package:cloud_functions/cloud_functions.dart';
import 'package:circum/app/admin/admin_access_error_message.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps access failures to distinct safe explanations', () {
    final auth = adminAccessErrorMessage(
      FirebaseAuthException(code: 'network-request-failed'),
    );
    final missingSession = adminAccessErrorMessage(
      FirebaseFunctionsException(code: 'unauthenticated', message: ''),
    );
    final permission = adminAccessErrorMessage(
      FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'private server details',
      ),
    );
    final service = adminAccessErrorMessage(
      FirebaseFunctionsException(code: 'unavailable', message: ''),
    );

    expect(auth, contains('sign-in'));
    expect(missingSession, contains('session'));
    expect(permission, contains('denied Admin access'));
    expect(service, contains('temporarily unavailable'));
    expect({auth, missingSession, permission, service}, hasLength(4));
    expect(permission, isNot(contains('private server details')));
  });

  test('unknown callable failures do not reveal provider messages', () {
    final message = adminAccessErrorMessage(
      FirebaseFunctionsException(
        code: 'unknown',
        message: 'sensitive diagnostic payload',
      ),
    );

    expect(message, contains('could not be verified'));
    expect(message, isNot(contains('sensitive diagnostic payload')));
  });
}
