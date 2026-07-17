import 'dart:typed_data';

class SenderGiftRecordedAudio {
  final String localUrl;
  final String? mimeType;
  final Uint8List bytes;

  const SenderGiftRecordedAudio({
    required this.localUrl,
    required this.bytes,
    this.mimeType,
  });
}

class SenderGiftVoiceRecorder {
  bool get isSupported => false;

  Future<void> start() async {
    throw UnsupportedError('Voice recording is unavailable on this platform.');
  }

  Future<SenderGiftRecordedAudio> stop() async {
    throw UnsupportedError('Voice recording is unavailable on this platform.');
  }

  void cancel() {}

  void dispose() {}
}

class SenderGiftVoicePlayback {
  bool get isSupported => false;

  Future<void> play(String localUrl) async {}

  void pause() {}

  void dispose() {}
}
