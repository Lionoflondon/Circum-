import 'package:firebase_auth/firebase_auth.dart';

/// Create and sign-in are distinct actions; a failed create never signs in.
Future<UserCredential> authenticateSenderEmail({
  required FirebaseAuth auth,
  required String email,
  required String password,
  required bool createAccount,
  required Duration timeout,
}) {
  final operation = createAccount
      ? auth.createUserWithEmailAndPassword(email: email, password: password)
      : auth.signInWithEmailAndPassword(email: email, password: password);
  return operation.timeout(timeout);
}
