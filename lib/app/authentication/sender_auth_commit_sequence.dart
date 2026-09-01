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

  Future<SenderAuthCommitResult> runRecoverable({
    required Future<void> Function() ensureAccount,
    required Future<void> Function() hydrateProfile,
    required Future<void> Function() refreshToken,
  }) async {
    final operations = <(SenderAuthCommitStage, Future<void> Function())>[
      (SenderAuthCommitStage.account, ensureAccount),
      (SenderAuthCommitStage.profile, hydrateProfile),
      (SenderAuthCommitStage.token, refreshToken),
    ];
    for (final operation in operations) {
      try {
        await operation.$2().timeout(operationTimeout);
      } catch (error) {
        return SenderAuthCommitResult.failure(operation.$1, error);
      }
    }
    return const SenderAuthCommitResult.success();
  }
}

enum SenderAuthCommitStage { account, profile, token }

class SenderAuthCommitResult {
  final SenderAuthCommitStage? failedStage;
  final Object? error;

  const SenderAuthCommitResult.success() : failedStage = null, error = null;

  const SenderAuthCommitResult.failure(this.failedStage, this.error);

  bool get succeeded => failedStage == null;
}
