typedef SenderStartupAction = Future<void> Function();
typedef SenderStartupRender = void Function();

Future<void> runSenderStartup({
  required SenderStartupAction initialize,
  required SenderStartupRender renderApp,
  required SenderStartupRender renderRecovery,
}) async {
  try {
    await initialize();
    renderApp();
  } catch (_) {
    renderRecovery();
  }
}
