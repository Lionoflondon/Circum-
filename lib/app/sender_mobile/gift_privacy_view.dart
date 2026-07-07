import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_budget_view.dart';
import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';

class GiftPrivacyView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftPrivacyView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/privacy';

  @override
  State<GiftPrivacyView> createState() => _GiftPrivacyViewState();
}

class _GiftPrivacyViewState extends State<GiftPrivacyView> {
  late String _revealMode;

  @override
  void initState() {
    super.initState();
    _revealMode = widget.draft.senderRevealMode ?? 'reveal_immediately';
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 07 — REVEAL & PRIVACY',
      title: 'How should we handle privacy?',
      subtitle:
          'These choices map to the same reveal and consent fields used by Gifts on web.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        for (final entry in senderGiftRevealModeOptions.entries) ...[
          _RevealCard(
            title: entry.value,
            subtitle: _subtitleFor(entry.key),
            selected: _revealMode == entry.key,
            onTap: () => setState(() => _revealMode = entry.key),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        Text(
          'Circum knows who arranged the gift for safety and fraud prevention. Recipient identity reveal follows your selected consent mode.',
          style: GoogleFonts.inter(
            color: const Color(0xFFB8AAB8),
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: 'Continue',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftBudgetView(
              draft: widget.draft.copyWith(senderRevealMode: _revealMode),
            ),
            settings: const RouteSettings(name: GiftBudgetView.routeName),
          ),
        ),
      ),
    );
  }

  String _subtitleFor(String key) => switch (key) {
        'anonymous_forever' => 'Recipient never learns who sent this.',
        'reveal_after_delivery' => 'Your name appears once the gift arrives.',
        'reveal_immediately' => 'Recipient sees your name straight away.',
        _ => '',
      };
}

class _RevealCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RevealCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFC9B8FF).withValues(alpha: .13)
              : Colors.white.withValues(alpha: .052),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFFC9B8FF).withValues(alpha: .62)
                : Colors.white.withValues(alpha: .09),
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFC9B8FF)),
                color: selected ? const Color(0xFFC9B8FF) : Colors.transparent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: const Color(0xFFB8AAB8),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
