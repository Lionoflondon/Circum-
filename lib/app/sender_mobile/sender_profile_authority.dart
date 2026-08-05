import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum SenderProfileDiagnosticCode {
  authUnavailable('PROFILE_AUTH_UNAVAILABLE'),
  notFound('PROFILE_NOT_FOUND'),
  permissionDenied('PROFILE_PERMISSION_DENIED'),
  uidMismatch('PROFILE_UID_MISMATCH'),
  schemaMismatch('PROFILE_SCHEMA_MISMATCH'),
  startupRace('PROFILE_STARTUP_RACE'),
  repositoryFailure('PROFILE_REPOSITORY_FAILURE');

  final String label;

  const SenderProfileDiagnosticCode(this.label);
}

class SenderProfileAuthorityException implements Exception {
  final SenderProfileDiagnosticCode code;
  final String message;
  final String phase;
  final String collection;
  final String documentId;
  final String correlationId;

  SenderProfileAuthorityException({
    required this.code,
    required this.message,
    required this.phase,
    this.collection = 'users',
    this.documentId = '',
    String? correlationId,
  }) : correlationId = correlationId ?? senderProfileCorrelationId();

  String get path =>
      documentId.trim().isEmpty ? collection : '$collection/$documentId';

  @override
  String toString() =>
      '${code.label} phase=$phase path=$path correlationId=$correlationId';
}

class SenderProfileAuthoritySnapshot {
  final User user;
  final DocumentSnapshot<Map<String, dynamic>> document;

  const SenderProfileAuthoritySnapshot({
    required this.user,
    required this.document,
  });

  Map<String, dynamic> get data => document.data() ?? const <String, dynamic>{};
}

class SenderProfileAuthority {
  static const authRestoreTimeout = Duration(seconds: 8);
  static const profileReadTimeout = Duration(seconds: 8);
  static const senderAccountEnsureTimeout = Duration(seconds: 8);

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  SenderProfileAuthority({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instance;

  Future<User> requireRestoredUser(String phase) async {
    logSenderProfileStage(
      uid: auth.currentUser?.uid,
      phase: phase,
      path: 'FirebaseAuth.currentUser',
      event: 'auth_restore_begin',
    );
    final current = auth.currentUser;
    if (current != null) {
      logSenderProfileStage(
        uid: current.uid,
        phase: phase,
        path: 'FirebaseAuth.currentUser',
        event: 'auth_restore_current_user',
      );
      return current;
    }
    try {
      final restored = await auth
          .authStateChanges()
          .where((user) => user != null)
          .cast<User>()
          .first
          .timeout(authRestoreTimeout);
      logSenderProfileStage(
        uid: restored.uid,
        phase: phase,
        path: 'FirebaseAuth.authStateChanges',
        event: 'auth_restore_stream_user',
      );
      return restored;
    } on TimeoutException {
      throw SenderProfileAuthorityException(
        code: SenderProfileDiagnosticCode.authUnavailable,
        message: profileMessageFor(SenderProfileDiagnosticCode.authUnavailable),
        phase: phase,
      );
    } catch (error, stack) {
      logSenderProfileDiagnostic(
        code: SenderProfileDiagnosticCode.repositoryFailure,
        uid: null,
        phase: phase,
        path: 'FirebaseAuth.authStateChanges',
        error: error,
        stack: stack,
      );
      throw SenderProfileAuthorityException(
        code: SenderProfileDiagnosticCode.repositoryFailure,
        message: 'Profile startup failed. Please try again.',
        phase: phase,
      );
    }
  }

  Future<void> ensureCanonicalSenderAccount(User user, String phase) async {
    logSenderProfileStage(
      uid: user.uid,
      phase: phase,
      path: 'functions/ensureSenderAccount',
      event: 'ensure_begin',
    );
    try {
      await functions
          .httpsCallable('ensureSenderAccount')
          .call<void>()
          .timeout(senderAccountEnsureTimeout);
      logSenderProfileStage(
        uid: user.uid,
        phase: phase,
        path: 'functions/ensureSenderAccount',
        event: 'ensure_complete',
      );
    } on TimeoutException catch (error, stack) {
      logSenderProfileDiagnostic(
        code: SenderProfileDiagnosticCode.startupRace,
        uid: user.uid,
        phase: phase,
        path: 'functions/ensureSenderAccount',
        error: error,
        stack: stack,
      );
      throw SenderProfileAuthorityException(
        code: SenderProfileDiagnosticCode.startupRace,
        message: profileMessageFor(SenderProfileDiagnosticCode.startupRace),
        phase: phase,
        documentId: user.uid,
      );
    } on FirebaseFunctionsException catch (error, stack) {
      final code = error.code == 'permission-denied'
          ? SenderProfileDiagnosticCode.permissionDenied
          : SenderProfileDiagnosticCode.repositoryFailure;
      logSenderProfileDiagnostic(
        code: code,
        uid: user.uid,
        phase: phase,
        path: 'functions/ensureSenderAccount',
        error: error,
        stack: stack,
      );
      throw SenderProfileAuthorityException(
        code: code,
        message: profileMessageFor(code),
        phase: phase,
        documentId: user.uid,
      );
    } catch (error, stack) {
      logSenderProfileDiagnostic(
        code: SenderProfileDiagnosticCode.repositoryFailure,
        uid: user.uid,
        phase: phase,
        path: 'functions/ensureSenderAccount',
        error: error,
        stack: stack,
      );
      throw SenderProfileAuthorityException(
        code: SenderProfileDiagnosticCode.repositoryFailure,
        message: 'Profile setup failed. Please try again.',
        phase: phase,
        documentId: user.uid,
      );
    }
  }

  Future<SenderProfileAuthoritySnapshot> load(String phase) async {
    logSenderProfileStage(
      uid: auth.currentUser?.uid,
      phase: phase,
      path: 'SenderProfileAuthority.load',
      event: 'load_begin',
    );
    final user = await requireRestoredUser('$phase.auth');
    final document = await readCanonicalProfileWithRepair(
      user,
      readPhase: '$phase.read',
      ensurePhase: '$phase.ensure',
    );
    logSenderProfileStage(
      uid: user.uid,
      phase: phase,
      path: document.reference.path,
      event: 'load_complete exists=${document.exists}',
    );
    return SenderProfileAuthoritySnapshot(user: user, document: document);
  }

  Stream<SenderProfileAuthoritySnapshot> watch(String phase) async* {
    logSenderProfileStage(
      uid: auth.currentUser?.uid,
      phase: phase,
      path: 'SenderProfileAuthority.watch',
      event: 'watch_begin',
    );
    final user = await requireRestoredUser('$phase.auth');
    await readCanonicalProfileWithRepair(
      user,
      readPhase: '$phase.initialRead',
      ensurePhase: '$phase.ensure',
    );
    logSenderProfileStage(
      uid: user.uid,
      phase: phase,
      path: canonicalProfileReference(user).path,
      event: 'listener_attach',
    );
    await for (final snapshot in canonicalProfileReference(user).snapshots()) {
      logSenderProfileStage(
        uid: user.uid,
        phase: phase,
        path: snapshot.reference.path,
        event: 'snapshot exists=${snapshot.exists} '
            'pendingWrites=${snapshot.metadata.hasPendingWrites} '
            'cache=${snapshot.metadata.isFromCache}',
      );
      if (!snapshot.exists) {
        final repaired = await readCanonicalProfileWithRepair(
          user,
          readPhase: '$phase.repairRead',
          ensurePhase: '$phase.repairEnsure',
        );
        yield SenderProfileAuthoritySnapshot(user: user, document: repaired);
        continue;
      }
      _validateProfileOwner(user, snapshot.data() ?? const {}, '$phase.read');
      yield SenderProfileAuthoritySnapshot(user: user, document: snapshot);
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> readCanonicalProfileWithRepair(
    User user, {
    required String readPhase,
    required String ensurePhase,
  }) async {
    try {
      return await readCanonicalProfile(user, readPhase);
    } on SenderProfileAuthorityException catch (error) {
      if (error.code != SenderProfileDiagnosticCode.notFound) rethrow;
      logSenderProfileStage(
        uid: user.uid,
        phase: ensurePhase,
        path: canonicalProfileReference(user).path,
        event: 'profile_missing_begin_ensure',
      );
      await ensureCanonicalSenderAccount(user, ensurePhase);
      return readCanonicalProfile(user, '$readPhase.afterEnsure');
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> readCanonicalProfile(
    User user,
    String phase,
  ) async {
    final reference = canonicalProfileReference(user);
    logSenderProfileStage(
      uid: user.uid,
      phase: phase,
      path: reference.path,
      event: 'firestore_read_begin',
    );
    var attempt = 0;
    while (true) {
      try {
        final snapshot = await reference.get().timeout(profileReadTimeout);
        logSenderProfileStage(
          uid: user.uid,
          phase: phase,
          path: reference.path,
          event: 'firestore_read_complete exists=${snapshot.exists} '
              'pendingWrites=${snapshot.metadata.hasPendingWrites} '
              'cache=${snapshot.metadata.isFromCache}',
        );
        if (!snapshot.exists) {
          throw SenderProfileAuthorityException(
            code: SenderProfileDiagnosticCode.notFound,
            message: profileMessageFor(SenderProfileDiagnosticCode.notFound),
            phase: phase,
            documentId: user.uid,
          );
        }
        _validateProfileOwner(user, snapshot.data() ?? const {}, phase);
        return snapshot;
      } on SenderProfileAuthorityException catch (error, stack) {
        logSenderProfileDiagnostic(
          code: error.code,
          uid: user.uid,
          phase: phase,
          path: error.path,
          error: error,
          stack: stack,
        );
        rethrow;
      } on TimeoutException catch (error, stack) {
        if (attempt++ == 0) {
          logSenderProfileStage(
            uid: user.uid,
            phase: phase,
            path: reference.path,
            event: 'firestore_read_retry reason=timeout',
          );
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        logSenderProfileDiagnostic(
          code: SenderProfileDiagnosticCode.repositoryFailure,
          uid: user.uid,
          phase: phase,
          path: reference.path,
          error: error,
          stack: stack,
        );
        throw SenderProfileAuthorityException(
          code: SenderProfileDiagnosticCode.repositoryFailure,
          message: 'Profile service timed out. Please try again.',
          phase: phase,
          documentId: user.uid,
        );
      } on FirebaseException catch (error, stack) {
        final retryable = <String>{
          'aborted',
          'deadline-exceeded',
          'internal',
          'resource-exhausted',
          'unavailable',
        }.contains(error.code);
        if (retryable && attempt++ == 0) {
          logSenderProfileStage(
            uid: user.uid,
            phase: phase,
            path: reference.path,
            event: 'firestore_read_retry reason=${error.code}',
          );
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        final code = error.code == 'permission-denied'
            ? SenderProfileDiagnosticCode.permissionDenied
            : SenderProfileDiagnosticCode.repositoryFailure;
        logSenderProfileDiagnostic(
          code: code,
          uid: user.uid,
          phase: phase,
          path: reference.path,
          error: error,
          stack: stack,
        );
        throw SenderProfileAuthorityException(
          code: code,
          message: profileMessageFor(code),
          phase: phase,
          documentId: user.uid,
        );
      } catch (error, stack) {
        logSenderProfileDiagnostic(
          code: SenderProfileDiagnosticCode.repositoryFailure,
          uid: user.uid,
          phase: phase,
          path: reference.path,
          error: error,
          stack: stack,
        );
        throw SenderProfileAuthorityException(
          code: SenderProfileDiagnosticCode.repositoryFailure,
          message: 'Profile refresh failed. Please try again.',
          phase: phase,
          documentId: user.uid,
        );
      }
    }
  }

  DocumentReference<Map<String, dynamic>> canonicalProfileReference(User user) {
    return firestore.collection('users').doc(user.uid);
  }

  void _validateProfileOwner(
    User user,
    Map<String, dynamic> data,
    String phase,
  ) {
    final storedUid = firstSenderProfileText([
      data['uid'],
      data['userId'],
      data['senderId'],
    ]);
    if (storedUid.isEmpty || storedUid == user.uid) return;
    throw SenderProfileAuthorityException(
      code: SenderProfileDiagnosticCode.uidMismatch,
      message: profileMessageFor(SenderProfileDiagnosticCode.uidMismatch),
      phase: phase,
      documentId: user.uid,
    );
  }
}

String profileMessageFor(SenderProfileDiagnosticCode code) {
  switch (code) {
    case SenderProfileDiagnosticCode.permissionDenied:
      return 'Profile access was denied. Please sign in again.';
    case SenderProfileDiagnosticCode.notFound:
      return 'Your profile is being prepared. Please try again.';
    case SenderProfileDiagnosticCode.uidMismatch:
      return 'Profile ownership could not be verified.';
    case SenderProfileDiagnosticCode.startupRace:
      return 'Profile setup is still completing. Please try again.';
    case SenderProfileDiagnosticCode.authUnavailable:
      return 'Sign in again to load your profile.';
    case SenderProfileDiagnosticCode.schemaMismatch:
      return 'Profile details need attention. Please try again.';
    case SenderProfileDiagnosticCode.repositoryFailure:
      return 'Profile service is temporarily unavailable. Please try again.';
  }
}

String firstSenderProfileText(Iterable<Object?> values) {
  for (final value in values) {
    final text = value == null ? '' : '$value'.trim();
    if (text.isNotEmpty && text != 'null' && text != 'undefined') {
      return text;
    }
  }
  return '';
}

String senderProfileCorrelationId() =>
    'sender-profile-${DateTime.now().microsecondsSinceEpoch}';

void logSenderProfileDiagnostic({
  required SenderProfileDiagnosticCode code,
  required String? uid,
  required String phase,
  required String path,
  required Object error,
  StackTrace? stack,
}) {
  final correlationId = senderProfileCorrelationId();
  debugPrint(
    'Sender profile diagnostic '
    'code=${code.label} '
    'uid=${uid ?? 'unknown'} '
    'path=$path '
    'phase=$phase '
    'correlationId=$correlationId '
    'error=$error',
  );
  if (stack != null) debugPrint('$stack');
}

void logSenderProfileStage({
  required String? uid,
  required String phase,
  required String path,
  required String event,
}) {
  debugPrint(
    'Sender profile lifecycle '
    'ts=${DateTime.now().toIso8601String()} '
    'uid=${uid ?? 'unknown'} '
    'phase=$phase '
    'path=$path '
    'event=$event',
  );
}
