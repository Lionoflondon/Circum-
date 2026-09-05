import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../media/circum_media.dart';
import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';
import 'gift_themes_view.dart';

enum GiftVoiceNoteState {
  idle,
  permissionDenied,
  recording,
  recorded,
  playing,
  uploadFailed,
}

class GiftVoiceNoteView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftVoiceNoteView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/voice-note';

  @override
  State<GiftVoiceNoteView> createState() => _GiftVoiceNoteViewState();
}

class _GiftVoiceNoteViewState extends State<GiftVoiceNoteView> {
  static const _maxDurationSeconds = 60;
  Timer? _timer;
  Timer? _playbackTimer;
  late final CircumVoiceRecorder _recorder;
  late final CircumVoicePlayback _playback;
  late final CircumMediaStorage _mediaStorage;
  GiftVoiceNoteState _state = GiftVoiceNoteState.idle;
  int _seconds = 0;
  SenderGiftVoiceNote? _voiceNote;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _recorder = CircumVoiceRecorder();
    _playback = CircumVoicePlayback();
    _mediaStorage = CircumMediaStorage();
    _voiceNote = widget.draft.voiceNote;
    _seconds = _voiceNote?.durationSeconds ?? 0;
    if (_voiceNote?.hasVoiceNote == true) {
      _state = GiftVoiceNoteState.recorded;
    }
  }

  @override
  void dispose() {
    _recordingGeneration++;
    _timer?.cancel();
    _playbackTimer?.cancel();
    _playback.dispose();
    final localUrl = _voiceNote?.localUrl ?? _voiceNote?.localPath;
    if (localUrl != null) unawaited(_recorder.deleteLocal(localUrl));
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 5,
      eyebrow: 'STEP 05 — VOICE NOTE',
      title: 'Leave a personal message',
      subtitle:
          "A short voice note helps our Gifts Team understand the emotion behind your gift. It won't be shared with the recipient unless you later choose to include it in their Gift Story.",
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        _VoiceNoteCard(
          state: _state,
          seconds: _seconds,
          voiceNote: _voiceNote,
          statusMessage: _statusMessage,
          onRecord: _startRecording,
          onStop: () {
            _stopRecording();
          },
          onCancel: _cancelRecording,
          onPlay: () {
            _play();
          },
          onPause: _pause,
          onDelete: _delete,
          onRerecord: _rerecord,
        ),
      ],
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GiftJourneyWidgets.primaryButton(
            enabled: _voiceNote != null,
            label: 'Use this recording',
            onTap: _voiceNote == null
                ? null
                : () => _continue(widget.draft.copyWith(voiceNote: _voiceNote)),
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _continue(widget.draft.copyWith(clearVoiceNote: true)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Skip voice note',
                style: GoogleFonts.inter(
                  color: const Color(0xFFE4DCF5),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _recordingOperationPending = false;
  int _recordingGeneration = 0;

  Future<void> _startRecording() async {
    if (_recordingOperationPending) return;
    if (!_recorder.isSupported) {
      setState(() {
        _state = GiftVoiceNoteState.uploadFailed;
        _statusMessage =
            'Voice recording is unavailable on this device. You can skip this step.';
      });
      return;
    }
    _recordingOperationPending = true;
    final generation = _recordingGeneration;
    try {
      await _recorder.start();
      if (!mounted || generation != _recordingGeneration) return;
      setState(() {
        _state = GiftVoiceNoteState.recording;
        _statusMessage = null;
        _voiceNote = null;
        _seconds = 0;
      });
      _playbackTimer?.cancel();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_seconds + 1 >= _maxDurationSeconds) {
          _stopRecording();
          return;
        }
        setState(() => _seconds += 1);
      });
    } catch (_) {
      if (!mounted || generation != _recordingGeneration) return;
      setState(() {
        _state = GiftVoiceNoteState.permissionDenied;
        _statusMessage =
            'Microphone access is blocked. Enable it in your device settings, or skip this step.';
      });
    } finally {
      _recordingOperationPending = false;
    }
  }

  Future<void> _stopRecording() async {
    if (_recordingOperationPending) return;
    _timer?.cancel();
    final duration = _seconds.clamp(1, _maxDurationSeconds);
    _recordingOperationPending = true;
    final generation = _recordingGeneration;
    try {
      final audio = await _recorder.stop();
      if (!mounted || generation != _recordingGeneration) return;
      final uploaded = await _mediaStorage.uploadGiftVoiceNote(audio);
      if (!mounted || generation != _recordingGeneration) return;
      final uploadedAt = DateTime.now();
      setState(() {
        _state = GiftVoiceNoteState.recorded;
        _statusMessage = null;
        _seconds = duration;
        _voiceNote = SenderGiftVoiceNote(
          hasVoiceNote: true,
          durationSeconds: duration,
          localUrl: audio.localUrl,
          storagePath: uploaded.storagePath,
          downloadUrl: uploaded.downloadUrl,
          mimeType: uploaded.mimeType,
          createdAt: uploadedAt,
          transcript: null,
          language: null,
          uploadStatus: uploaded.uploadStatus,
          retryState: uploaded.retryState,
          version: uploaded.version,
          ownerId: uploaded.ownerId,
        );
      });
    } catch (_) {
      if (!mounted || generation != _recordingGeneration) return;
      setState(() {
        _state = GiftVoiceNoteState.uploadFailed;
        _statusMessage =
            'We could not upload that recording. Please try again or skip this step.';
      });
    } finally {
      _recordingOperationPending = false;
    }
  }

  void _cancelRecording() {
    _recordingGeneration++;
    _timer?.cancel();
    _recorder.cancel();
    setState(() {
      _state = _voiceNote == null
          ? GiftVoiceNoteState.idle
          : GiftVoiceNoteState.recorded;
      _seconds = _voiceNote?.durationSeconds ?? 0;
    });
  }

  Future<void> _play() async {
    final localUrl = _voiceNote?.localUrl ?? _voiceNote?.localPath;
    if (localUrl == null || localUrl.isEmpty) return;
    _playbackTimer?.cancel();
    try {
      await _playback.play(localUrl);
      setState(() => _state = GiftVoiceNoteState.playing);
      _playbackTimer = Timer(_voiceNoteDuration, () {
        _playback.pause();
        if (mounted) setState(() => _state = GiftVoiceNoteState.recorded);
      });
    } catch (_) {
      setState(() {
        _state = GiftVoiceNoteState.uploadFailed;
        _statusMessage =
            'We could not play that recording. Please try again or re-record.';
      });
    }
  }

  void _pause() {
    _playbackTimer?.cancel();
    _playback.pause();
    setState(() => _state = GiftVoiceNoteState.recorded);
  }

  void _delete() {
    final path = _voiceNote?.storagePath;
    final localUrl = _voiceNote?.localUrl ?? _voiceNote?.localPath;
    _timer?.cancel();
    _playbackTimer?.cancel();
    _playback.pause();
    _recorder.cancel();
    if (localUrl != null) unawaited(_recorder.deleteLocal(localUrl));
    unawaited(_mediaStorage.deleteMedia(path).catchError((_) {}));
    setState(() {
      _state = GiftVoiceNoteState.idle;
      _statusMessage = null;
      _voiceNote = null;
      _seconds = 0;
    });
  }

  void _rerecord() {
    _delete();
    _startRecording();
  }

  Duration get _voiceNoteDuration {
    final seconds = (_voiceNote?.durationSeconds ?? 1).clamp(1, 8);
    return Duration(seconds: seconds);
  }

  void _continue(GiftJourneyDraft draft) {
    if (draft.voiceNote == null && _voiceNote?.storagePath != null) {
      unawaited(_mediaStorage
          .deleteMedia(_voiceNote?.storagePath)
          .catchError((_) {}));
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GiftThemesView(draft: draft),
        settings: const RouteSettings(name: GiftThemesView.routeName),
      ),
    );
  }
}

class _VoiceNoteCard extends StatelessWidget {
  final GiftVoiceNoteState state;
  final int seconds;
  final SenderGiftVoiceNote? voiceNote;
  final String? statusMessage;
  final VoidCallback onRecord;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onDelete;
  final VoidCallback onRerecord;

  const _VoiceNoteCard({
    required this.state,
    required this.seconds,
    required this.voiceNote,
    required this.statusMessage,
    required this.onRecord,
    required this.onStop,
    required this.onCancel,
    required this.onPlay,
    required this.onPause,
    required this.onDelete,
    required this.onRerecord,
  });

  @override
  Widget build(BuildContext context) {
    final hasNote = voiceNote != null;
    final recording = state == GiftVoiceNoteState.recording;
    final playing = state == GiftVoiceNoteState.playing;
    final permissionDenied = state == GiftVoiceNoteState.permissionDenied;
    final uploadFailed = state == GiftVoiceNoteState.uploadFailed;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFA8EDEA).withValues(alpha: .72),
                  const Color(0xFFC9B8FF).withValues(alpha: .72),
                  const Color(0xFFFFD6E8).withValues(alpha: .72),
                ],
              ),
            ),
            child: Icon(
              recording
                  ? Icons.stop_rounded
                  : hasNote
                      ? Icons.graphic_eq_rounded
                      : Icons.mic_none_rounded,
              color: const Color(0xFF07090F),
              size: 34,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            recording
                ? 'Recording... ${_format(seconds)}'
                : hasNote
                    ? 'Voice note ready · ${_format(voiceNote!.durationSeconds)}'
                    : 'Record a voice note',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusMessage ??
                (permissionDenied
                    ? 'Microphone access is blocked. Enable it in your device settings, or skip this step.'
                    : recording
                        ? 'Maximum length is 60 seconds.'
                        : hasNote
                            ? 'Recording saved · ${voiceNote!.durationSeconds}s. You can play it back or re-record.'
                            : 'Ask for microphone permission, then record a short note.'),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: permissionDenied || uploadFailed
                  ? const Color(0xFFFFD6E8)
                  : const Color(0xFFB8AAB8),
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          if (recording)
            Row(
              children: [
                Expanded(child: _VoiceButton(label: 'Stop', onTap: onStop)),
                const SizedBox(width: 10),
                Expanded(
                  child: _VoiceButton(label: 'Cancel', onTap: onCancel),
                ),
              ],
            )
          else if (hasNote)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _VoiceButton(
                    label: playing ? 'Pause' : 'Play',
                    onTap: playing ? onPause : onPlay),
                _VoiceButton(label: 'Delete', onTap: onDelete),
                _VoiceButton(label: 'Re-record', onTap: onRerecord),
              ],
            )
          else
            _VoiceButton(label: 'Record', onTap: onRecord),
        ],
      ),
    );
  }

  static String _format(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

class _VoiceButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _VoiceButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFC9B8FF).withValues(alpha: .14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFC9B8FF).withValues(alpha: .28),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
