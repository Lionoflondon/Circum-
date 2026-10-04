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
}) async {
  renderBoot();
  try {
    await initialize().timeout(const Duration(seconds: 20));
  } catch (error, stackTrace) {
    onFailure?.call('core', error, stackTrace);
    renderRecovery();
    return;
  }
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
