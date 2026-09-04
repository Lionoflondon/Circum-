import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../sender_mobile/gift_voice_recorder.dart';

class CircumRecordedAudio {
  const CircumRecordedAudio({
    required this.localUrl,
    required this.bytes,
    this.mimeType,
  });

  final String localUrl;
  final Uint8List bytes;
  final String? mimeType;
}

class CircumUploadedMedia {
  const CircumUploadedMedia({
    required this.storagePath,
    required this.downloadUrl,
    required this.mimeType,
    required this.uploadStatus,
    required this.retryState,
    required this.version,
    required this.ownerId,
  });

  final String storagePath;
  final String downloadUrl;
  final String mimeType;
  final String uploadStatus;
  final String retryState;
  final int version;
  final String ownerId;
}

class CircumVoiceRecorder {
  final SenderGiftVoiceRecorder _recorder = SenderGiftVoiceRecorder();

  bool get isSupported => _recorder.isSupported;

  Future<void> start() => _recorder.start();

  Future<CircumRecordedAudio> stop() async {
    final audio = await _recorder.stop();
    return CircumRecordedAudio(
      localUrl: audio.localUrl,
      bytes: audio.bytes,
      mimeType: audio.mimeType,
    );
  }

  void cancel() => _recorder.cancel();

  Future<void> deleteLocal(String localUrl) => _recorder.deleteLocal(localUrl);

  void dispose() => _recorder.dispose();
}

class CircumVoicePlayback {
  final SenderGiftVoicePlayback _playback = SenderGiftVoicePlayback();

  bool get isSupported => _playback.isSupported;

  Future<void> play(String localUrl) => _playback.play(localUrl);

  void pause() => _playback.pause();

  void dispose() => _playback.dispose();
}

class CircumMediaStorage {
  CircumMediaStorage({
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  static const voiceMetadataVersion = 1;
  static const operationTimeout = Duration(seconds: 20);
  static const maxVoiceUploadBytes = 60 * 1024 * 1024;
  static const allowedVoiceMimeTypes = {
    'audio/webm',
    'audio/mpeg',
    'audio/mp4',
    'audio/aac',
    'audio/ogg',
  };

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  Future<CircumUploadedMedia> uploadGiftVoiceNote(
    CircumRecordedAudio audio,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before saving a voice note.');
    }
    final mimeType = audio.mimeType ?? 'audio/webm';
    if (!allowedVoiceMimeTypes.contains(mimeType)) {
      throw StateError('Unsupported voice note format.');
    }
    if (audio.bytes.lengthInBytes > maxVoiceUploadBytes) {
      throw StateError('Voice note is too large.');
    }
    if (audio.bytes.isEmpty) {
      throw StateError('Voice note is empty.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final extension =
        mimeType == 'audio/mp4' || mimeType == 'audio/aac' ? 'm4a' : 'webm';
    final path = 'gift_requests/${user.uid}_$now/voice/original.$extension';
    final ref = _storage.ref(path);
    await ref
        .putData(
          audio.bytes,
          SettableMetadata(
            contentType: mimeType,
            customMetadata: {
              'purpose': 'sender_mobile_gift_voice_note',
              'uploadedBy': user.uid,
              'ownerId': user.uid,
              'version': '$voiceMetadataVersion',
              'uploadStatus': 'uploaded',
              'retryState': 'none',
            },
          ),
        )
        .timeout(operationTimeout);
    return CircumUploadedMedia(
      storagePath: path,
      downloadUrl: await ref.getDownloadURL().timeout(operationTimeout),
      mimeType: mimeType,
      uploadStatus: 'uploaded',
      retryState: 'none',
      version: voiceMetadataVersion,
      ownerId: user.uid,
    );
  }

  Future<void> deleteMedia(String? storagePath) async {
    final path = storagePath?.trim();
    if (path == null || path.isEmpty) return;
    await _storage.ref(path).delete().timeout(operationTimeout);
  }
}
