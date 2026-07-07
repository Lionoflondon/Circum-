import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';

class GiftStoryView extends StatelessWidget {
  final GiftJourneyDraft draft;

  const GiftStoryView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/story';

  @override
  Widget build(BuildContext context) {
    final unlocked = draft.giftStoryUnlocked;
    final manualLock = draft.giftStoryManuallyLocked;
    return GiftJourneyWidgets.scaffold(
      activeStep: 14,
      eyebrow: 'FINALE — GIFT STORY',
      title: unlocked ? 'Your Gift Story is ready' : 'Gift Story locked',
      subtitle: unlocked
          ? 'Your gift has been delivered, so the story can now be viewed.'
          : manualLock
              ? 'This story is currently under review.'
              : 'Your story will unlock after delivery is confirmed.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        Container(
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
                unlocked ? Icons.movie_filter_outlined : Icons.lock_outline,
                color: const Color(0xFFC9B8FF).withValues(alpha: .8),
                size: 42,
              ),
              const SizedBox(height: 18),
              Text(
                unlocked
                    ? 'Story preview ready'
                    : 'Delivery confirmation needed',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                unlocked
                    ? 'Gift reveal assets can appear here now that the linked Gift Delivery is delivered.'
                    : manualLock
                        ? 'This story is currently under review.'
                        : 'Your story will unlock after delivery is confirmed.',
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
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: unlocked ? 'Done' : 'Back to status',
        onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
      ),
    );
  }
}
