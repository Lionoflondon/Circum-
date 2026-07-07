import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';
import 'gift_themes_view.dart';

class GiftVoiceNoteView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftVoiceNoteView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/voice-note';

  @override
  State<GiftVoiceNoteView> createState() => _GiftVoiceNoteViewState();
}

class _GiftVoiceNoteViewState extends State<GiftVoiceNoteView> {
  static const _maxDurationSeconds = 160;

  Timer? _timer;
  Timer? _playbackTimer;
  bool _permissionDenied = false;
  bool _recording = false;
  bool _playing = false;
  int _seconds = 0;
  SenderGiftVoiceNote? _voiceNote;

  @override
  void initState() {
    super.initState();
    _voiceNote = widget.draft.voiceNote;
    _seconds = _voiceNote?.durationSeconds ?? 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _playbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 05 — VOICE NOTE',
      title: 'Add your voice?',
      subtitle:
          'Record a short note for the Gifts Team. It stays attached to this gift draft.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        _VoiceNoteCard(
          permissionDenied: _permissionDenied,
          recording: _recording,
          playing: _playing,
          seconds: _seconds,
          voiceNote: _voiceNote,
          onRecord: _startRecording,
          onStop: _stopRecording,
          onCancel: _cancelRecording,
          onPlay: _play,
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
            label: 'Use this voice note',
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

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => _permissionDenied = true);
      return;
    }
    setState(() {
      _permissionDenied = false;
      _recording = true;
      _playing = false;
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
  }

  void _stopRecording() {
    _timer?.cancel();
    final duration = _seconds.clamp(1, _maxDurationSeconds);
    setState(() {
      _recording = false;
      _seconds = duration;
      _voiceNote = SenderGiftVoiceNote(
        hasVoiceNote: true,
        durationSeconds: duration,
        localPath:
            'local://sender-mobile/gifts/voice-note/${DateTime.now().millisecondsSinceEpoch}.m4a',
        createdAt: DateTime.now(),
        transcript: null,
        language: null,
      );
    });
  }

  void _cancelRecording() {
    _timer?.cancel();
    setState(() {
      _recording = false;
      _playing = false;
      _seconds = _voiceNote?.durationSeconds ?? 0;
    });
  }

  void _play() {
    if (_voiceNote == null) return;
    _playbackTimer?.cancel();
    setState(() => _playing = true);
    _playbackTimer = Timer(_voiceNoteDuration, () {
      if (mounted) setState(() => _playing = false);
    });
  }

  void _pause() {
    _playbackTimer?.cancel();
    setState(() => _playing = false);
  }

  void _delete() {
    _timer?.cancel();
    _playbackTimer?.cancel();
    setState(() {
      _recording = false;
      _playing = false;
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GiftThemesView(draft: draft),
        settings: const RouteSettings(name: GiftThemesView.routeName),
      ),
    );
  }
}

class _VoiceNoteCard extends StatelessWidget {
  final bool permissionDenied;
  final bool recording;
  final bool playing;
  final int seconds;
  final SenderGiftVoiceNote? voiceNote;
  final VoidCallback onRecord;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onDelete;
  final VoidCallback onRerecord;

  const _VoiceNoteCard({
    required this.permissionDenied,
    required this.recording,
    required this.playing,
    required this.seconds,
    required this.voiceNote,
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
            permissionDenied
                ? 'Microphone permission was denied. Enable microphone access to record a note, or skip this step.'
                : recording
                    ? 'Maximum length is 160 seconds.'
                    : hasNote
                        ? 'Transcript and language are saved as null until processing is connected.'
                        : 'Ask for microphone permission, then record a short note.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: permissionDenied
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
