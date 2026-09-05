// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'gift_voice_completion.dart';

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
  static const _operationTimeout = Duration(seconds: 20);
  GiftVoiceCompletion<SenderGiftRecordedAudio>? _completion;
  int _generation = 0;

  bool get isSupported => html.window.navigator.mediaDevices != null;

  Future<void> start() async {
    cancel();
    if (!isSupported) throw UnsupportedError('MediaRecorder is unsupported.');
    final generation = _generation;
    final devices = html.window.navigator.mediaDevices!;
    try {
      final stream = await devices.getUserMedia({'audio': true}).then((stream) {
        // A permission prompt may finish after cancellation or our deadline.
        if (generation != _generation) {
          for (final track in stream.getTracks()) {
            track.stop();
          }
          throw StateError('Recording was cancelled.');
        }
        return stream;
      }).timeout(_operationTimeout);
      _stream = stream;
      final recorder = html.MediaRecorder(stream);
      _recorder = recorder;
      recorder.addEventListener('dataavailable', (event) {
        if (generation != _generation) return;
        final data = (event as html.BlobEvent).data;
        if (data != null && data.size > 0) _chunks.add(data);
      });
      recorder.addEventListener('error', (_) {
        if (generation != _generation) return;
        _completion?.fail(StateError('Could not finish recorded audio.'));
        _stopTracks();
      });
      recorder.addEventListener('stop', (_) async {
        if (generation != _generation) return;
        final completion = _completion;
        if (completion == null || completion.isCompleted) {
          _stopTracks();
          return;
        }
        String? url;
        try {
          final blob = html.Blob(_chunks, 'audio/webm');
          final bytes = await _readBlobBytes(blob);
          if (generation != _generation || completion.isCompleted) return;
          url = html.Url.createObjectUrlFromBlob(blob);
          completion.complete(SenderGiftRecordedAudio(
            localUrl: url,
            bytes: bytes,
            mimeType: blob.type,
          ));
        } catch (_) {
          if (url != null) html.Url.revokeObjectUrl(url);
          completion.fail(StateError('Could not read recorded audio.'));
        }
      });
      recorder.start();
    } catch (_) {
      if (generation == _generation) cancel();
      rethrow;
    }
  }

  Future<SenderGiftRecordedAudio> stop() {
    final existing = _completion;
    if (existing != null) return existing.future;
    final recorder = _recorder;
    if (recorder == null) throw StateError('No active recording.');
    final completion = GiftVoiceCompletion<SenderGiftRecordedAudio>(
      timeout: _operationTimeout,
      onSettled: _stopTracks,
    );
    _completion = completion;
    try {
      recorder.stop();
    } catch (_) {
      completion.fail(StateError('Could not stop recorded audio.'));
    }
    return completion.future;
  }

  void cancel() {
    _generation++;
    _completion?.fail(StateError('Recording was cancelled.'));
    _completion = null;
    final recorder = _recorder;
    if (recorder != null && recorder.state != 'inactive') recorder.stop();
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

  Future<Uint8List> _readBlobBytes(html.Blob blob) async {
    final reader = html.FileReader();
    final completer = Completer<Uint8List>();
    final loaded = reader.onLoadEnd.listen((_) {
      if (completer.isCompleted) return;
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(result.asUint8List());
      } else if (result is Uint8List) {
        completer.complete(result);
      } else {
        completer.completeError(StateError('Could not read recorded audio.'));
      }
    });
    final failed = reader.onError.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Could not read recorded audio.'));
      }
    });
    final timer = Timer(_operationTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Audio read took too long.'));
        reader.abort();
      }
    });
    try {
      reader.readAsArrayBuffer(blob);
      return await completer.future;
    } finally {
      timer.cancel();
      unawaited(loaded.cancel());
      unawaited(failed.cancel());
    }
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
