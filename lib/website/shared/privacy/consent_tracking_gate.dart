/// Rechecks permission after asynchronous provider startup. Withdrawal while
/// startup is pending must never result in a later analytics request.
Future<void> runConsentedAnalytics({
  required bool Function() allowed,
  required Future<void> Function() prepare,
  required Future<void> Function() record,
}) async {
  if (!allowed()) return;
  await prepare();
  if (!allowed()) return;
  await record();
}
