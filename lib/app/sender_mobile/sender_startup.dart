import 'dart:async';

typedef SenderStartupAction = Future<void> Function();
typedef SenderStartupRender = void Function();
typedef SenderStartupFailure = void Function(
  String stage,
  Object error,
  StackTrace stackTrace,
);

Future<void> runSenderStartup({
  required SenderStartupRender renderBoot,
  required SenderStartupAction initialize,
  required SenderStartupRender renderApp,
  required SenderStartupRender renderRecovery,
  SenderStartupAction? afterRenderApp,
  SenderStartupFailure? onFailure,
  SenderStartupRender? renderSlow,
}) async {
  renderBoot();
  // A Dart timeout does not cancel native initialization. Treat elapsed time
  // as a slow start, not a failed service; retain and observe the real result.
  final slowTimer = Timer(const Duration(seconds: 20), () {
    renderSlow?.call();
  });
  try {
    await initialize();
  } catch (error, stackTrace) {
    slowTimer.cancel();
    onFailure?.call('core', error, stackTrace);
    renderRecovery();
    return;
  }
  slowTimer.cancel();
  renderApp();
  // Permission dialogs depend on a human response. They cannot own the
  // startup deadline or replace a working login screen with recovery.
  if (afterRenderApp != null) {
    unawaited(Future<void>.sync(afterRenderApp).catchError(
      (Object error, StackTrace stackTrace) {
        onFailure?.call('notifications', error, stackTrace);
      },
    ));
  }
}

/// Retries join a pending native start instead of racing another initialization.
/// A completed or failed attempt releases the slot for a genuine retry.
class SenderStartupAttempt {
  Future<void>? _pending;

  Future<void> run(SenderStartupAction start) {
    if (_pending != null) return _pending!;
    final pending = Future<void>.sync(start);
    _pending = pending;
    void clear() {
      if (identical(_pending, pending)) _pending = null;
    }

    unawaited(pending.then((_) => clear(), onError: (Object _, StackTrace __) {
      clear();
    }));
    return pending;
  }
}
