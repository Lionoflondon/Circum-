import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../gifts/gift_story_studio_policy.dart';
import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';

class GiftStoryView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftStoryView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/story';

  @override
  State<GiftStoryView> createState() => _GiftStoryViewState();
}

class _GiftStoryViewState extends State<GiftStoryView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  late final List<GiftStorySlide> _slides;
  var _index = 0;
  var _paused = false;
  var _soundOn = true;

  @override
  void initState() {
    super.initState();
    _slides = GiftStoryStudioPolicy.buildSlides(
      recipientName: widget.draft.recipientName ?? 'you',
      senderName: 'Someone special',
      senderNote: widget.draft.personalMessage ?? '',
      senderVoiceNoteUrl: widget.draft.voiceNote?.downloadUrl,
      giftItems: [
        {
          'name': widget.draft.mode == SenderGiftMode.campaign
              ? 'Your campaign gift'
              : 'Your gift',
          'why': widget.draft.irisGiftBrief?.experienceDirection ??
              'Because this moment deserved something thoughtful.',
        },
      ],
      canRevealSender: false,
    );
    _progress = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _slides.first.durationMs),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    if (widget.draft.giftStoryUnlocked) _run();
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
    if (_index >= _slides.length - 1) return;
    setState(() => _index += 1);
    _run();
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
    setState(() => _index = 0);
    _run();
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
          child: Center(child: _buildStoryPlayer()),
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

  const _StorySlideView({
    super.key,
    required this.slide,
    required this.recipientName,
    required this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    return switch (slide.type) {
      GiftStorySlideType.arrival => _ArrivalSlide(slide: slide),
      GiftStorySlideType.note || GiftStorySlideType.voiceNote => _NoteSlide(
          slide: slide,
        ),
      GiftStorySlideType.giftReveal => _RevealSlide(slide: slide),
      GiftStorySlideType.whyChosen => _TextSlide(slide: slide),
      GiftStorySlideType.finale => _FinaleSlide(onReplay: onReplay),
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
  const _FinaleSlide({required this.onReplay});

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
          _StoryButton(label: 'Tell sender thank you', onTap: () {}),
          const SizedBox(height: 10),
          _StoryButton(label: 'Replay story', onTap: onReplay, secondary: true),
          const SizedBox(height: 10),
          _StoryButton(
            label: 'Keep this story in the Circum app',
            onTap: () {},
            secondary: true,
          ),
        ],
      ),
    );
  }
}

class _StoryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
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
