import 'dart:async';

/// Commits an authenticated Sender session only after required authority work.
class SenderAuthCommitSequence {
  final Duration operationTimeout;

  const SenderAuthCommitSequence({
    this.operationTimeout = const Duration(seconds: 20),
  });

  Future<void> run({
    required Future<void> Function() ensureAccount,
    required Future<void> Function() hydrateProfile,
    required Future<void> Function() refreshToken,
  }) async {
    await ensureAccount().timeout(operationTimeout);
    await hydrateProfile().timeout(operationTimeout);
    await refreshToken().timeout(operationTimeout);
  }
}
