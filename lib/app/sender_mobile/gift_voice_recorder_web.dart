import 'dart:async';
import 'dart:html' as html;

class SenderGiftRecordedAudio {
  final String localUrl;
  final String? mimeType;

  const SenderGiftRecordedAudio({
    required this.localUrl,
    this.mimeType,
  });
}

class SenderGiftVoiceRecorder {
  html.MediaRecorder? _recorder;
  html.MediaStream? _stream;
  final _chunks = <html.Blob>[];
  Completer<SenderGiftRecordedAudio>? _stopCompleter;

  bool get isSupported => html.window.navigator.mediaDevices != null;

  Future<void> start() async {
    if (!isSupported) {
      throw UnsupportedError('MediaRecorder is unsupported.');
    }
    _chunks.clear();
    final devices = html.window.navigator.mediaDevices;
    if (devices == null) {
      throw UnsupportedError('Microphone capture is unavailable.');
    }
    _stream = await devices.getUserMedia({'audio': true});
    final recorder = html.MediaRecorder(_stream!);
    _recorder = recorder;
    recorder.addEventListener('dataavailable', (event) {
      final data = (event as html.BlobEvent).data;
      if (data != null && data.size > 0) _chunks.add(data);
    });
    recorder.addEventListener('stop', (_) {
      final blob = html.Blob(_chunks, 'audio/webm');
      final url = html.Url.createObjectUrlFromBlob(blob);
      _stopCompleter?.complete(
        SenderGiftRecordedAudio(localUrl: url, mimeType: blob.type),
      );
      _stopCompleter = null;
      _stopTracks();
    });
    recorder.start();
  }

  Future<SenderGiftRecordedAudio> stop() {
    final recorder = _recorder;
    if (recorder == null) {
      throw StateError('No active recording.');
    }
    _stopCompleter = Completer<SenderGiftRecordedAudio>();
    recorder.stop();
    return _stopCompleter!.future;
  }

  void cancel() {
    final recorder = _recorder;
    if (recorder != null && recorder.state != 'inactive') {
      recorder.stop();
    }
    _chunks.clear();
    _stopTracks();
  }

  void dispose() {
    cancel();
  }

  void _stopTracks() {
    for (final track
        in _stream?.getTracks() ?? const <html.MediaStreamTrack>[]) {
      track.stop();
    }
    _stream = null;
    _recorder = null;
  }
}

class SenderGiftVoicePlayback {
  html.AudioElement? _audio;

  bool get isSupported => true;

  Future<void> play(String localUrl) async {
    pause();
    final audio = html.AudioElement(localUrl);
    _audio = audio;
    await audio.play();
  }

  void pause() {
    _audio?.pause();
    _audio = null;
  }

  void dispose() {
    pause();
  }
}
