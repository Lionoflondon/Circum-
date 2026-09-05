import 'dart:async';

/// Observes both native initiation and its callback before either can fail.
Future<void> awaitPhoneVerification<T>({
  required Future<void> Function() start,
  required Future<T> completion,
  required Duration timeout,
}) async {
  await Future.wait<Object?>(
    [Future<void>.sync(start), completion],
    eagerError: true,
  ).timeout(timeout);
}
