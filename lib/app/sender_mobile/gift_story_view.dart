import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../gifts/gift_story_studio_policy.dart';
import 'gift_journey_draft.dart';
import '../media/circum_media.dart';
import 'gift_relationship_view.dart';

class GiftStoryView extends StatefulWidget {
  final GiftJourneyDraft draft;
  final String? senderStoryId;

  const GiftStoryView({super.key, required this.draft, this.senderStoryId});

  static const routeName = '/sender-mobile/gifts/story';

  @override
  State<GiftStoryView> createState() => _GiftStoryViewState();
}

class _GiftStoryViewState extends State<GiftStoryView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  late List<GiftStorySlide> _slides;
  var _index = 0;
  var _paused = false;
  var _soundOn = true;
  var _actionBusy = false;
  var _thankYouSent = false;
  var _storySaved = false;
  var _viewerAuthenticated = FirebaseAuth.instance.currentUser != null;
  var _showJoinPrompt = false;
  var _storyLoading = false;
  String? _storyError;

  @override
  void initState() {
    super.initState();
    _slides = _slidesFromDraft(widget.draft);
    _progress = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _slides.first.durationMs),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    if (widget.draft.giftStoryUnlocked) _run();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _resolveStoryFromBackend();
      await _loadActionState();
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _run() {
    _progress
      ..duration = Duration(milliseconds: _slides[_index].durationMs)
      ..forward(from: 0);
  }

  void _pause() {
    if (!widget.draft.giftStoryUnlocked) return;
    setState(() => _paused = true);
    _progress.stop();
  }

  void _resume() {
    if (!widget.draft.giftStoryUnlocked) return;
    setState(() => _paused = false);
    _progress.forward();
  }

  void _next() {
    if (!mounted || !widget.draft.giftStoryUnlocked) return;
    if (_index >= _slides.length - 1) {
      if (_isGuestViewer) setState(() => _showJoinPrompt = true);
      return;
    }
    setState(() => _index += 1);
    _run();
    if (_index == _slides.length - 1 && _isGuestViewer) {
      setState(() => _showJoinPrompt = true);
      _recordGuestEvent('guest_completed_video');
    }
  }

  void _previous() {
    if (!widget.draft.giftStoryUnlocked) return;
    setState(() {
      if (_progress.value < .18 && _index > 0) {
        _index -= 1;
      }
    });
    _run();
  }

  void _replay() {
    setState(() {
      _index = 0;
      _showJoinPrompt = false;
    });
    _run();
  }

  bool get _hasToken => _actionPayload.containsKey('token');

  bool get _isGuestViewer => _hasToken && !_viewerAuthenticated;

  List<GiftStorySlide> _slidesFromDraft(GiftJourneyDraft draft) {
    return GiftStoryStudioPolicy.buildSlides(
      recipientName: draft.recipientName ?? 'you',
      senderName: 'Someone special',
      senderNote: draft.personalMessage ?? '',
      senderVoiceNoteUrl: draft.voiceNote?.downloadUrl,
      giftItems: [
        {
          'name': draft.mode == SenderGiftMode.campaign
              ? 'Your campaign gift'
              : 'Your gift',
          'why': draft.irisGiftBrief?.experienceDirection ??
              'Because this moment deserved something thoughtful.',
        },
      ],
      canRevealSender: false,
    );
  }

  List<GiftStorySlide> _slidesFromStory(Map<String, dynamic> story) {
    final slides = story['giftStorySlides'];
    if (slides is List && slides.isNotEmpty) {
      return slides
          .whereType<Map>()
          .map((slide) => _slideFromMap(Map<String, dynamic>.from(slide)))
          .toList(growable: false);
    }
    final voice = story['voiceNote'];
    final voiceUrl = voice is Map
        ? '${voice['downloadUrl'] ?? story['giftStorySenderVoiceNoteUrl'] ?? ''}'
        : '${story['giftStorySenderVoiceNoteUrl'] ?? ''}';
    return GiftStoryStudioPolicy.buildSlides(
      recipientName: '${story['recipientName'] ?? 'you'}',
      senderName: '${story['senderName'] ?? 'Someone special'}',
      senderNote:
          '${story['personalMessage'] ?? story['senderMessageText'] ?? ''}',
      senderVoiceNoteUrl: voiceUrl.trim().isEmpty ? null : voiceUrl,
      giftItems: [
        {
          'name': '${story['giftItemsSummary'] ?? 'Your gift'}',
          'why': '${story['giftStoryCircumMessage'] ?? 'Chosen with care.'}',
        },
      ],
      canRevealSender: false,
    );
  }

  GiftStorySlide _slideFromMap(Map<String, dynamic> slide) {
    final typeValue = '${slide['type'] ?? ''}'.trim();
    final type = GiftStorySlideType.values.firstWhere(
      (candidate) => candidate.value == typeValue,
      orElse: () => GiftStorySlideType.whyChosen,
    );
    return GiftStorySlide(
      type: type,
      eyebrow: '${slide['eyebrow'] ?? ''}',
      headline: '${slide['headline'] ?? ''}',
      body: '${slide['body'] ?? ''}',
      mediaUrl: '${slide['mediaUrl'] ?? slide['imageUrl'] ?? ''}'.trim(),
      durationMs: int.tryParse('${slide['durationMs'] ?? ''}') ?? 5200,
    );
  }

  Future<void> _resolveStoryFromBackend() async {
    final token = _actionPayload['token'];
    final senderStoryId = _actionPayload['senderStoryId'];
    if ((token == null || token.isEmpty) &&
        (senderStoryId == null || senderStoryId.isEmpty)) {
      return;
    }
    setState(() {
      _storyLoading = true;
      _storyError = null;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(senderStoryId != null && senderStoryId.isNotEmpty
              ? 'getSenderGiftStory'
              : 'resolveGiftStoryAccess')
          .call<Map<String, dynamic>>(senderStoryId != null && senderStoryId.isNotEmpty
              ? {'giftRequestId': senderStoryId}
              : {'token': token});
      final data = Map<String, dynamic>.from(result.data);
      final story = Map<String, dynamic>.from(data['story'] as Map);
      if (!mounted) return;
      setState(() {
        _slides = _slidesFromStory(story);
        _index = 0;
        _storyLoading = false;
      });
      _recordGuestEvent('guest_viewed_story');
      _run();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _storyLoading = false;
        _storyError = _actionError(error);
      });
    }
  }

  Map<String, String> get _actionPayload {
    final giftRequestId = widget.draft.giftRequestId?.trim() ?? '';
    final token = Uri.base.queryParameters['giftStoryToken']?.trim() ?? '';
    return {
      if (giftRequestId.isNotEmpty) 'giftRequestId': giftRequestId,
      if (token.isNotEmpty) 'token': token,
      if (widget.senderStoryId?.trim().isNotEmpty == true)
        'senderStoryId': widget.senderStoryId!.trim(),
    };
  }

  Future<Map<String, dynamic>> _callAction(String name) async {
    if (_actionPayload.isEmpty) {
      throw StateError('Gift Story access could not be verified.');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable(name)
        .call<Map<String, dynamic>>(_actionPayload);
    return Map<String, dynamic>.from(result.data);
  }

  Future<void> _loadActionState() async {
    if (!mounted || !widget.draft.giftStoryUnlocked || _actionPayload.isEmpty) {
      return;
    }
    try {
      final data = await _callAction('getGiftStoryActionState');
      if (!mounted) return;
      setState(() {
        _thankYouSent = data['thanked'] == true;
        _storySaved = data['saved'] == true;
        _viewerAuthenticated = data['authenticated'] == true;
      });
    } catch (_) {
      // The action buttons retain their own retry and error handling.
    }
  }

  Future<void> _sendThankYou() async {
    if (_actionBusy || _thankYouSent) return;
    if (!await _ensureAccountForOwnership()) return;
    setState(() => _actionBusy = true);
    try {
      await _callAction('acknowledgeGiftStory');
      if (!mounted) return;
      setState(() => _thankYouSent = true);
      _showConfirmation('Your thank you has been sent.');
    } catch (error) {
      if (mounted) _showConfirmation(_actionError(error));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _keepStory() async {
    if (_actionBusy || _storySaved) return;
    if (!await _ensureAccountForOwnership()) return;
    setState(() => _actionBusy = true);
    try {
      await _callAction('saveGiftStoryToVault');
      await _recordGuestEvent('guest_claimed_gift_story');
      if (!mounted) return;
      setState(() => _storySaved = true);
      _showConfirmation('This Gift Story is saved to your Vault.');
    } catch (error) {
      if (mounted) _showConfirmation(_actionError(error));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<bool> _ensureAccountForOwnership() async {
    if (_viewerAuthenticated) return true;
    setState(() => _showJoinPrompt = true);
    if (FirebaseAuth.instance.currentUser == null) {
      final authenticated = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _GiftStoryAuthDialog(),
      );
      if (authenticated != true || !mounted) return false;
    }
    await _loadActionState();
    await _recordGuestEvent('guest_registered');
    return _viewerAuthenticated;
  }

  Future<void> _recordGuestEvent(String event) async {
    final token = _actionPayload['token'];
    if (token == null || token.isEmpty) return;
    try {
      await http.post(
        Uri.parse(
          'https://us-central1-circum-2797c.cloudfunctions.net/'
          'recordGiftStoryGuestEvent',
        ),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'token': token, 'event': event}),
      );
    } catch (_) {
      // Guest analytics must never interrupt Gift Story playback.
    }
  }

  String _actionError(Object error) {
    if (error is FirebaseFunctionsException && error.message != null) {
      return error.message!;
    }
    return 'Something went wrong. Please try again.';
  }

  void _showConfirmation(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = widget.draft.giftStoryUnlocked;
    final manualLock = widget.draft.giftStoryManuallyLocked;
    if (!unlocked) {
      return GiftJourneyWidgets.scaffold(
        activeStep: 14,
        eyebrow: 'FINALE — GIFT STORY',
        title: 'Gift Story locked',
        subtitle: manualLock
            ? 'This story is currently under review.'
            : 'Your story will unlock after delivery is confirmed.',
        onBack: () => Navigator.of(context).maybePop(),
        children: const [
          _LockedStoryCard(),
        ],
        footer: GiftJourneyWidgets.primaryButton(
          enabled: true,
          label: 'Back to status',
          onTap: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF090B1D),
      body: SafeArea(
        child: Semantics(
          label: 'Your Gift Story is ready',
          child: Center(
            child: _storyLoading
                ? const CircularProgressIndicator()
                : _storyError != null
                    ? _StoryLoadError(message: _storyError!)
                    : _buildStoryPlayer(),
          ),
        ),
      ),
    );
  }

  Widget _buildStoryPlayer() {
    return AspectRatio(
      aspectRatio: 294 / 600,
      child: GestureDetector(
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onTapUp: (details) {
          final width = context.size?.width ?? 1;
          if (details.localPosition.dx < width / 2) {
            _previous();
          } else {
            _next();
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            children: [
              _StorySkinBackground(skin: GiftStorySkin.iridescent),
              _StoryProgress(
                count: _slides.length,
                index: _index,
                progress: _progress,
              ),
              Positioned(
                top: 24,
                left: 14,
                right: 14,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const _StoryAvatar(),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Gifts by Circum',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'just now',
                              style: GoogleFonts.jetBrainsMono(
                                color: Colors.white.withValues(alpha: .55),
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _soundOn = !_soundOn),
                      icon: Icon(
                        _soundOn
                            ? Icons.volume_up_outlined
                            : Icons.volume_off_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _StorySlideView(
                  key: ValueKey(_index),
                  slide: _slides[_index],
                  recipientName: widget.draft.recipientName ?? 'you',
                  onReplay: _replay,
                  onThankYou: _sendThankYou,
                  onKeepStory: _keepStory,
                  thankYouSent: _thankYouSent,
                  storySaved: _storySaved,
                  actionBusy: _actionBusy,
                ),
              ),
              if (_paused)
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .34),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .18),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      child: Text(
                        'Paused',
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_showJoinPrompt && _isGuestViewer)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 18,
                  child: _GiftStoryJoinPrompt(
                    onJoin: _keepStory,
                    onMaybeLater: () => setState(() => _showJoinPrompt = false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedStoryCard extends StatelessWidget {
  const _LockedStoryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            color: const Color(0xFFC9B8FF).withValues(alpha: .8),
            size: 42,
          ),
          const SizedBox(height: 18),
          Text(
            'Delivery confirmation needed',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your story will unlock after delivery is confirmed.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: const Color(0xFFB8AAB8),
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryLoadError extends StatelessWidget {
  final String message;

  const _StoryLoadError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.card_giftcard_outlined,
            color: Color(0xFFC9B8FF),
            size: 38,
          ),
          const SizedBox(height: 16),
          Text(
            'Gift Story unavailable',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSerifDisplay(
              color: Colors.white,
              fontSize: 30,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: .64),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftStoryJoinPrompt extends StatelessWidget {
  final VoidCallback onJoin;
  final VoidCallback onMaybeLater;

  const _GiftStoryJoinPrompt({
    required this.onJoin,
    required this.onMaybeLater,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xDD10122A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC9B8FF).withValues(alpha: .16),
            blurRadius: 28,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _SlideEyebrow('Your Gift Story is ready.'),
            _SlideBody(
              'Create your free Circum account to save this Gift Story forever in your Vault, rewatch it anytime, send your own Gift Stories, thank the sender, leave a message, and build your own collection of memories.',
            ),
            const SizedBox(height: 10),
            _StoryButton(label: 'Join Circum', onTap: onJoin),
            const SizedBox(height: 8),
            _StoryButton(
              label: 'Maybe later',
              onTap: onMaybeLater,
              secondary: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryProgress extends StatelessWidget {
  final int count;
  final int index;
  final Animation<double> progress;

  const _StoryProgress({
    required this.count,
    required this.index,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  height: 2.5,
                  color: Colors.white.withValues(alpha: .22),
                  alignment: Alignment.centerLeft,
                  child: i < index
                      ? Container(color: Colors.white)
                      : i == index
                          ? AnimatedBuilder(
                              animation: progress,
                              builder: (_, __) => FractionallySizedBox(
                                widthFactor: progress.value,
                                child: Container(
                                  color: const Color(0xFFC9B8FF),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                ),
              ),
            ),
            if (i != count - 1) const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }
}

class _StorySlideView extends StatelessWidget {
  final GiftStorySlide slide;
  final String recipientName;
  final VoidCallback onReplay;
  final VoidCallback onThankYou;
  final VoidCallback onKeepStory;
  final bool thankYouSent;
  final bool storySaved;
  final bool actionBusy;

  const _StorySlideView({
    super.key,
    required this.slide,
    required this.recipientName,
    required this.onReplay,
    required this.onThankYou,
    required this.onKeepStory,
    required this.thankYouSent,
    required this.storySaved,
    required this.actionBusy,
  });

  @override
  Widget build(BuildContext context) {
    return switch (slide.type) {
      GiftStorySlideType.arrival => _ArrivalSlide(slide: slide),
      GiftStorySlideType.note => _NoteSlide(
          slide: slide,
        ),
      GiftStorySlideType.voiceNote => _VoiceNoteSlide(slide: slide),
      GiftStorySlideType.giftReveal => _RevealSlide(slide: slide),
      GiftStorySlideType.whyChosen => _TextSlide(slide: slide),
      GiftStorySlideType.finale => _FinaleSlide(
          onReplay: onReplay,
          onThankYou: onThankYou,
          onKeepStory: onKeepStory,
          thankYouSent: thankYouSent,
          storySaved: storySaved,
          actionBusy: actionBusy,
        ),
    };
  }
}

class _ArrivalSlide extends StatelessWidget {
  final GiftStorySlide slide;
  const _ArrivalSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Orb(),
            const SizedBox(height: 26),
            _SlideHeadline(slide.headline, centered: true),
            _SlideBody(slide.body, centered: true),
          ],
        ),
      ),
    );
  }
}

class _VoiceNoteSlide extends StatefulWidget {
  final GiftStorySlide slide;
  const _VoiceNoteSlide({required this.slide});

  @override
  State<_VoiceNoteSlide> createState() => _VoiceNoteSlideState();
}

class _VoiceNoteSlideState extends State<_VoiceNoteSlide> {
  late final CircumVoicePlayback _playback;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _playback = CircumVoicePlayback();
  }

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.slide.mediaUrl?.trim();
    if (url == null || url.isEmpty) return;
    if (_playing) {
      _playback.pause();
      setState(() => _playing = false);
      return;
    }
    await _playback.play(url);
    if (mounted) setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = widget.slide.mediaUrl?.trim().isNotEmpty == true;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white.withValues(alpha: .14)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.slide.headline,
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                  fontSize: 18,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.slide.body,
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white.withValues(alpha: .58),
                  fontSize: 10.5,
                  letterSpacing: .4,
                ),
              ),
              const SizedBox(height: 18),
              Semantics(
                button: true,
                label: _playing
                    ? 'Pause sender voice note'
                    : 'Play sender voice note',
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: hasAudio ? _toggle : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC9B8FF).withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFC9B8FF).withValues(alpha: .28),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hasAudio
                              ? (_playing
                                  ? 'Pause voice note'
                                  : 'Play voice note')
                              : 'Voice note unavailable',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteSlide extends StatelessWidget {
  final GiftStorySlide slide;
  const _NoteSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white.withValues(alpha: .14)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slide.headline,
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                  fontSize: 18,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                slide.body,
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white.withValues(alpha: .58),
                  fontSize: 10.5,
                  letterSpacing: .4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevealSlide extends StatelessWidget {
  final GiftStorySlide slide;
  const _RevealSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 76, 20, 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _Candle(),
          Column(
            children: [
              _SlideEyebrow(slide.eyebrow),
              _SlideHeadline(slide.headline, centered: true),
              _SlideBody(slide.body, centered: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _TextSlide extends StatelessWidget {
  final GiftStorySlide slide;
  const _TextSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 70, 24, 34),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SlideEyebrow(slide.eyebrow),
          _SlideHeadline(slide.headline),
          _SlideBody(slide.body),
        ],
      ),
    );
  }
}

class _FinaleSlide extends StatelessWidget {
  final VoidCallback onReplay;
  final VoidCallback onThankYou;
  final VoidCallback onKeepStory;
  final bool thankYouSent;
  final bool storySaved;
  final bool actionBusy;

  const _FinaleSlide({
    required this.onReplay,
    required this.onThankYou,
    required this.onKeepStory,
    required this.thankYouSent,
    required this.storySaved,
    required this.actionBusy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 84, 22, 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SlideEyebrow('Finale'),
          _SlideHeadline('Tell sender thank you'),
          _SlideBody(
            'Keep this story in the Circum app. Download Circum to save your gift story, replay it anytime, and keep thank-you messages in one place.',
          ),
          const SizedBox(height: 18),
          _StoryButton(
            label: thankYouSent ? 'Thank you sent' : 'Tell sender thank you',
            onTap: actionBusy || thankYouSent ? null : onThankYou,
          ),
          const SizedBox(height: 10),
          _StoryButton(label: 'Replay story', onTap: onReplay, secondary: true),
          const SizedBox(height: 10),
          _StoryButton(
            label: 'Keep this story in the Circum app',
            onTap: actionBusy || storySaved ? null : onKeepStory,
            secondary: true,
          ),
        ],
      ),
    );
  }
}

class _StoryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool secondary;
  const _StoryButton({
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor:
            secondary ? Colors.white.withValues(alpha: .08) : Colors.white,
        foregroundColor: secondary ? Colors.white : const Color(0xFF090B1D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}

class _GiftStoryAuthDialog extends StatefulWidget {
  const _GiftStoryAuthDialog();

  @override
  State<_GiftStoryAuthDialog> createState() => _GiftStoryAuthDialogState();
}

class _GiftStoryAuthDialogState extends State<_GiftStoryAuthDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _createAccount = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_createAccount) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim().toLowerCase(),
          password: _password.text,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim().toLowerCase(),
          password: _password.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? 'Authentication failed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF10122A),
      title: const Text('Keep this Gift Story'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Gift Stories are stored securely in your Circum account.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() => _createAccount = !_createAccount),
          child: Text(_createAccount ? 'Sign In' : 'Create Account'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy
              ? 'Please wait...'
              : _createAccount
                  ? 'Create Account'
                  : 'Sign In'),
        ),
      ],
    );
  }
}

class _SlideEyebrow extends StatelessWidget {
  final String text;
  const _SlideEyebrow(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.jetBrainsMono(
        color: const Color(0xFFC9B8FF),
        fontSize: 10,
        letterSpacing: 1,
      ),
    );
  }
}

class _SlideHeadline extends StatelessWidget {
  final String text;
  final bool centered;
  const _SlideHeadline(this.text, {this.centered = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: GoogleFonts.dmSerifDisplay(
        color: Colors.white,
        fontSize: 28,
        height: 1.14,
      ),
    );
  }
}

class _SlideBody extends StatelessWidget {
  final String text;
  final bool centered;
  const _SlideBody(this.text, {this.centered = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: .64),
          fontSize: 13,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StorySkinBackground extends StatelessWidget {
  final GiftStorySkin skin;
  const _StorySkinBackground({required this.skin});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF090B1D),
        gradient: RadialGradient(
          center: Alignment(-.35, -.88),
          radius: 1.1,
          colors: [
            Color(0x3328EDE5),
            Color(0x1AFFD6E8),
            Color(0xFF090B1D),
          ],
          stops: [0, .42, 1],
        ),
      ),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFFA8EDEA),
            Color(0xFFC9B8FF),
            Color(0xFFFFD6E8),
            Color(0xFFB8F0D8),
            Color(0xFFA8EDEA),
          ],
        ),
      ),
    );
  }
}

class _Orb extends StatefulWidget {
  const _Orb();

  @override
  State<_Orb> createState() => _OrbState();
}

class _OrbState extends State<_Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _spin,
      builder: (_, child) => Transform.rotate(
        angle: _spin.value * math.pi * 2,
        child: child,
      ),
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [
              Color(0xFFA8EDEA),
              Color(0xFFFFD6E8),
              Color(0xFFB8F0D8),
              Color(0xFFC9B8FF),
              Color(0xFFA8EDEA),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFA8EDEA).withValues(alpha: .45),
              blurRadius: 60,
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xEE090B1D),
            ),
          ),
        ),
      ),
    );
  }
}

class _Candle extends StatelessWidget {
  const _Candle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 118,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFFD6E8).withValues(alpha: .18),
                  const Color(0xFFA8EDEA).withValues(alpha: .14),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: .18)),
            ),
          ),
          Positioned(
            bottom: 6,
            left: 6,
            right: 6,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFD4849F),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned(
            bottom: 44,
            child:
                Container(width: 2, height: 14, color: const Color(0xFF3A2C22)),
          ),
          const Positioned(bottom: 56, child: _Flame()),
        ],
      ),
    );
  }
}

class _Flame extends StatefulWidget {
  const _Flame();

  @override
  State<_Flame> createState() => _FlameState();
}

class _FlameState extends State<_Flame> with SingleTickerProviderStateMixin {
  late final AnimationController _flicker;

  @override
  void initState() {
    super.initState();
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flicker,
      builder: (_, child) {
        final scale = 0.94 + _flicker.value * .12;
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: 9,
        height: 16,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.elliptical(9, 16)),
          gradient: RadialGradient(
            center: Alignment(0, .7),
            colors: [Colors.white, Color(0xFFC9B8FF), Color(0xFFD4C5FF)],
          ),
        ),
      ),
    );
  }
}
