typedef SenderStartupAction = Future<void> Function();
typedef SenderStartupRender = void Function();

Future<void> runSenderStartup({
  required SenderStartupRender renderBoot,
  required SenderStartupAction initialize,
  required SenderStartupRender renderApp,
  required SenderStartupRender renderRecovery,
}) async {
  // Render before any remote or native dependency so startup cannot own the
  // platform splash indefinitely.
  renderBoot();
  try {
    await initialize().timeout(const Duration(seconds: 20));
    renderApp();
  } catch (_) {
    renderRecovery();
  }
}
