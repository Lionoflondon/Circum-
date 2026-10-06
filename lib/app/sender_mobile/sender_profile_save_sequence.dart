import 'dart:async';

/// The canonical write was acknowledged, but its refreshed view is unavailable.
class SenderProfileRefreshPending implements Exception {
  const SenderProfileRefreshPending();
}

class SenderProfileSaveSessionChanged implements Exception {
  const SenderProfileSaveSessionChanged();
}

class SenderProfileSaveUnconfirmed implements Exception {
  const SenderProfileSaveUnconfirmed();
}

void requireSenderProfileAcknowledgement(Object? response) {
  if (response is! Map || response['ok'] != true) {
    throw const SenderProfileSaveUnconfirmed();
  }
}

Future<T> saveSenderProfileSequence<T>({
  required Future<void> Function() commitProfile,
  required Future<T> Function() readCommittedProfile,
  required Future<void> Function() mirrorDisplayName,
  required bool Function() isCurrentSession,
  void Function(Object error)? onMirrorDeferred,
  Duration mirrorTimeout = const Duration(seconds: 20),
}) async {
  void requireCurrentSession() {
    if (!isCurrentSession()) {
      throw const SenderProfileSaveSessionChanged();
    }
  }

  requireCurrentSession();
  try {
    await commitProfile();
  } on TimeoutException {
    requireCurrentSession();
    throw const SenderProfileSaveUnconfirmed();
  }
  requireCurrentSession();

  late T profile;
  try {
    profile = await readCommittedProfile();
  } catch (_) {
    requireCurrentSession();
    throw const SenderProfileRefreshPending();
  }
  requireCurrentSession();

  // Auth's display name is a secondary mirror, not the profile save authority.
  // Never retry the canonical write because this mirror is slow or unavailable.
  unawaited(() async {
    try {
      if (!isCurrentSession()) return;
      await mirrorDisplayName().timeout(mirrorTimeout);
    } catch (error) {
      if (isCurrentSession()) onMirrorDeferred?.call(error);
    }
  }());
  return profile;
}
