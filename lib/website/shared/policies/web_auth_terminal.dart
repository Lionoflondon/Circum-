const webAuthOperationTimeout = Duration(seconds: 30);

/// Keep live account subscriptions if remote sign-out fails. After confirmed
/// sign-out, local UI state must clear even if subscription cleanup fails.
Future<bool> finishWebSignOut({
  required Future<void> Function() signOut,
  required Future<void> Function() cancelSubscriptions,
  Duration timeout = webAuthOperationTimeout,
}) async {
  try {
    await signOut().timeout(timeout);
  } catch (_) {
    return false;
  }
  try {
    await cancelSubscriptions().timeout(timeout);
  } catch (_) {
    // Remote sign-out succeeded; callers must still clear local account state.
  }
  return true;
}
