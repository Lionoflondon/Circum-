import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';
import 'gift_themes_view.dart';

class GiftVoiceNoteView extends StatelessWidget {
  final GiftJourneyDraft draft;

  const GiftVoiceNoteView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/voice-note';

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 05 — VOICE NOTE',
      title: 'Add your voice?',
      subtitle:
          'Voice notes will become part of the Gifts experience later. You can skip this for now.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        Container(
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
                child: const Icon(
                  Icons.mic_none_rounded,
                  color: Color(0xFF07090F),
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Voice note capacity is ready.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Recording and upload will be added when the Gift Story flow is supplied.',
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
        label: 'Skip for now',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftThemesView(draft: draft),
            settings: const RouteSettings(name: GiftThemesView.routeName),
          ),
        ),
      ),
    );
  }
}
