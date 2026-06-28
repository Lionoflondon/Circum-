class MessagingServer {
  Future<void> sendMessage({
    required Map<String, String> data,
    required String code,
    required String message,
    String? title,
  }) async {
    // Server-side FCM delivery must run from trusted backend code, not client UI.
  }
}
