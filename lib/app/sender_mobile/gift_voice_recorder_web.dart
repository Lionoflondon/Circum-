// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
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
    recorder.addEventListener('stop', (_) async {
      final blob = html.Blob(_chunks, 'audio/webm');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final bytes = await _readBlobBytes(blob);
      _stopCompleter?.complete(
        SenderGiftRecordedAudio(
          localUrl: url,
          bytes: bytes,
          mimeType: blob.type,
        ),
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

  Future<void> deleteLocal(String localUrl) async {
    if (localUrl.startsWith('blob:')) html.Url.revokeObjectUrl(localUrl);
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

  Future<Uint8List> _readBlobBytes(html.Blob blob) {
    final reader = html.FileReader();
    final completer = Completer<Uint8List>();
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(result.asUint8List());
      } else if (result is Uint8List) {
        completer.complete(result);
      } else {
        completer.completeError(StateError('Could not read recorded audio.'));
      }
    });
    reader.onError.listen((_) {
      completer.completeError(StateError('Could not read recorded audio.'));
    });
    reader.readAsArrayBuffer(blob);
    return completer.future;
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
