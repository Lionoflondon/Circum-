import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

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
  static const _operationTimeout = Duration(seconds: 12);
  static const _staleFileAge = Duration(hours: 24);
  static const _directoryName = 'circum_gift_voice';

  final AudioRecorder _recorder;
  String? _activePath;

  SenderGiftVoiceRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  Future<void> start() async {
    if (!isSupported) {
      throw UnsupportedError(
          'Voice recording is unavailable on this platform.');
    }
    if (!await _recorder.hasPermission().timeout(_operationTimeout)) {
      throw StateError('Microphone permission denied.');
    }
    if (!await _recorder
        .isEncoderSupported(AudioEncoder.aacLc)
        .timeout(_operationTimeout)) {
      throw UnsupportedError('AAC voice recording is unavailable.');
    }
    final directory = await _voiceDirectory();
    await cleanupStaleFiles(directory: directory);
    final path =
        '${directory.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    _activePath = path;
    await _recorder
        .start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 96000,
            sampleRate: 44100,
            numChannels: 1,
            autoGain: true,
            echoCancel: true,
            noiseSuppress: true,
          ),
          path: path,
        )
        .timeout(_operationTimeout);
  }

  Future<SenderGiftRecordedAudio> stop() async {
    final expectedPath = _activePath;
    if (expectedPath == null) throw StateError('No active recording.');
    final stoppedPath = await _recorder.stop().timeout(_operationTimeout);
    _activePath = null;
    final path = stoppedPath ?? expectedPath;
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Recorded audio is unavailable.');
    }
    final bytes = await file.readAsBytes().timeout(_operationTimeout);
    if (bytes.isEmpty) {
      await file.delete().catchError((_) => file);
      throw StateError('Recorded audio is empty.');
    }
    return SenderGiftRecordedAudio(
      localUrl: path,
      bytes: bytes,
      mimeType: 'audio/mp4',
    );
  }

  void cancel() {
    final path = _activePath;
    _activePath = null;
    unawaited(_recorder.cancel().timeout(_operationTimeout).whenComplete(() {
      if (path != null) unawaited(_deleteIfPresent(File(path)));
    }));
  }

  Future<void> deleteLocal(String localUrl) async {
    final file = File(localUrl);
    if (file.path.contains('/$_directoryName/') && file.path.endsWith('.m4a')) {
      await _deleteIfPresent(file);
    }
  }

  void dispose() {
    cancel();
    unawaited(_recorder.dispose());
  }

  static Future<Directory> _voiceDirectory() async {
    final temp = await getTemporaryDirectory().timeout(_operationTimeout);
    final directory = Directory('${temp.path}/$_directoryName');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static Future<void> cleanupStaleFiles({Directory? directory}) async {
    final target = directory ?? await _voiceDirectory();
    if (!await target.exists()) return;
    final cutoff = DateTime.now().subtract(_staleFileAge);
    await for (final entity in target.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.m4a')) continue;
      final modified = await entity.lastModified();
      if (modified.isBefore(cutoff)) await _deleteIfPresent(entity);
    }
  }

  static Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) await file.delete();
  }
}

class SenderGiftVoicePlayback {
  final AudioPlayer _player;

  SenderGiftVoicePlayback({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  Future<void> play(String localUrl) async {
    await _player.stop();
    await _player.setFilePath(localUrl).timeout(const Duration(seconds: 12));
    await _player.play();
  }

  void pause() {
    unawaited(_player.pause());
  }

  void dispose() {
    unawaited(_player.dispose());
  }
}
