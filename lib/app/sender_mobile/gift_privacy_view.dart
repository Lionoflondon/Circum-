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
  late bool _allowCircumSocialUse;
  late bool _allowBrandTagging;
  late bool _allowPublicPosting;

  @override
  void initState() {
    super.initState();
    _revealMode = widget.draft.senderRevealMode ?? 'reveal_immediately';
    _allowCircumSocialUse = widget.draft.allowCircumSocialUse;
    _allowBrandTagging = widget.draft.allowBrandTagging;
    _allowPublicPosting = widget.draft.allowPublicPosting;
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 9,
      eyebrow: 'STEP 09 — REVEAL & PRIVACY',
      title: 'How should we handle privacy?',
      subtitle:
          'Choose when, or if, the recipient learns this gift is from you.',
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
        _GiftConsentToggle(
          label: 'Allow Circum story use',
          value: _allowCircumSocialUse,
          onChanged: (value) => setState(() => _allowCircumSocialUse = value),
        ),
        const SizedBox(height: 10),
        _GiftConsentToggle(
          label: 'Allow brand tagging',
          value: _allowBrandTagging,
          onChanged: (value) => setState(() => _allowBrandTagging = value),
        ),
        const SizedBox(height: 10),
        _GiftConsentToggle(
          label: 'Allow public posting',
          value: _allowPublicPosting,
          onChanged: (value) => setState(() => _allowPublicPosting = value),
        ),
        const SizedBox(height: 14),
        Text(
          'Circum knows who arranged the gift for safety and fraud prevention. Recipient identity reveal follows your selected consent mode.',
          style: GoogleFonts.inter(
            color: const Color(0xFFB8AAB8),
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "We'll take every dietary and medical preference into account during curation.",
          style: GoogleFonts.inter(
            color: const Color(0xFFE4DCF5),
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: 'Continue',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftBudgetView(
              draft: widget.draft.copyWith(
                senderRevealMode: _revealMode,
                allowCircumSocialUse: _allowCircumSocialUse,
                allowBrandTagging: _allowBrandTagging,
                allowPublicPosting: _allowPublicPosting,
              ),
            ),
            settings: const RouteSettings(name: GiftBudgetView.routeName),
          ),
        ),
      ),
    );
  }

  String _subtitleFor(String key) => switch (key) {
    'anonymous_forever' => 'Your identity will remain private.',
    'reveal_after_delivery' =>
      "We'll reveal your name once the gift has safely arrived.",
    'reveal_immediately' =>
      'The recipient will know you sent the gift straight away.',
    _ => '',
  };
}

class _GiftConsentToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _GiftConsentToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFFC9B8FF),
            activeTrackColor: const Color(0xFFC9B8FF).withValues(alpha: .28),
            inactiveThumbColor: const Color(0xFFB8AAB8),
            inactiveTrackColor: Colors.white.withValues(alpha: .12),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
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
