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
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'FINALE — GIFT STORY',
      title: 'The story, delivered',
      subtitle:
          'Gift Story is a future build. This placeholder shows where the story preview will live.',
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
                Icons.movie_filter_outlined,
                color: const Color(0xFFC9B8FF).withValues(alpha: .8),
                size: 42,
              ),
              const SizedBox(height: 18),
              Text(
                'Story preview disabled',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No real video generation, music upload, or story publishing is active in this pass.',
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
        label: 'Done',
        onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
      ),
    );
  }
}
