import 'dart:async';

/// A timeout is an unknown outcome: callers retain tracking and may retry.
Future<T> boundedCancellationCall<T>(
  Future<T> operation, {
  Duration timeout = const Duration(seconds: 20),
}) => operation.timeout(timeout);

/// Financial settlement must be confirmed before hiding the active delivery.
bool cancellationConfirmed(Map<String, dynamic> response) =>
    response['success'] == true && response['status'] == 'settled';
