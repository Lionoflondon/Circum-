// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

void installSenderWebErrorHooks(
  void Function(String stage, Object error, StackTrace? stackTrace) record,
) {
  html.window.onError.listen((event) {
    record('window.onerror', event.toString(), StackTrace.current);
  });

  html.window.on['unhandledrejection'].listen((event) {
    record('window.onunhandledrejection', event.toString(), StackTrace.current);
  });
}

String senderBrowserDescription() {
  final userAgent = html.window.navigator.userAgent;
  if (userAgent.contains('Edg/')) return 'Edge';
  if (userAgent.contains('Chrome/')) return 'Chrome';
  if (userAgent.contains('Safari/') && !userAgent.contains('Chrome/')) {
    return 'Safari';
  }
  if (userAgent.contains('Firefox/')) return 'Firefox';
  return 'Web';
}
