typedef SenderStartupAction = Future<void> Function();
typedef SenderStartupRender = void Function();

Future<void> runSenderStartup({
  required SenderStartupAction initialize,
  required SenderStartupRender renderApp,
  required SenderStartupRender renderRecovery,
}) async {
  try {
    await initialize().timeout(const Duration(seconds: 20));
    renderApp();
  } catch (_) {
    renderRecovery();
  }
}
