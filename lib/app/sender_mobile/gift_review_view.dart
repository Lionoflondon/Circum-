import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_journey_draft.dart';
import 'gift_payment_view.dart';
import 'gift_relationship_view.dart';

class GiftReviewView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftReviewView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/review';

  @override
  State<GiftReviewView> createState() => _GiftReviewViewState();
}

class _GiftReviewViewState extends State<GiftReviewView> {
  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final brief = draft.giftBriefPreview;
    final chosenThemes = draft.normalizedGiftThemes
        .where((theme) => theme.source == 'catalogue')
        .map((theme) => theme.label)
        .toList();
    final customThemes = draft.normalizedGiftThemes
        .where((theme) => theme.source == 'custom')
        .map((theme) => theme.label)
        .toList();
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 11 — REVIEW',
      title: 'Review before payment',
      subtitle: 'Gift contents remain confidential before delivery.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        _ReviewRow(label: 'Gift mode', value: draft.modeLabel),
        _ReviewRow(label: 'Recipient', value: draft.recipientName ?? 'Not set'),
        _ReviewRow(label: 'Occasion', value: draft.occasion ?? 'Not set'),
        _ReviewRow(
          label: 'Delivery',
          value:
              '${draft.deliveryAddress ?? 'Not set'} · ${draft.deliveryDate ?? 'Date not set'} · ${draft.deliveryTimeWindow ?? 'Window not set'}',
        ),
        _ReviewRow(
          label: 'Reveal',
          value: (senderGiftRevealModeOptions[
                  draft.senderRevealMode ?? 'reveal_immediately'] ??
              'Reveal immediately'),
        ),
        _ReviewRow(
          label: 'Voice note',
          value: draft.voiceNote?.hasVoiceNote == true
              ? 'Added · ${draft.voiceNote!.durationSeconds}s'
              : 'Skipped',
        ),
        _ReviewRow(
          label: 'Chosen themes',
          value: chosenThemes.isEmpty ? 'None' : chosenThemes.join(', '),
        ),
        _ReviewRow(
          label: 'Personal themes',
          value: customThemes.isEmpty ? 'None' : customThemes.join(', '),
        ),
        _ReviewRow(
          label: 'Allergies / medical',
          value:
              'No allergy or medical restriction fields were supplied in this mobile flow.',
        ),
        _GiftBriefCard(
          draft: draft,
          brief: brief,
        ),
        if (draft.mode == SenderGiftMode.campaign) ...[
          const _ReviewRow(
            label: 'Admin path',
            value: 'Campaign · Bringing London Closer',
          ),
          const _AdminPathNote(
            'This mobile request writes the same campaign fields Admin already reads.',
          ),
        ],
        _ReviewRow(
          label: 'Budget',
          value: '£${draft.budget.toStringAsFixed(0)}',
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: 'Continue to Secure Payment',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftPaymentView(draft: draft),
            settings: const RouteSettings(name: GiftPaymentView.routeName),
          ),
        ),
      ),
    );
  }
}

class _GiftBriefCard extends StatelessWidget {
  final GiftJourneyDraft draft;
  final SenderGiftBriefPreview brief;

  const _GiftBriefCard({required this.draft, required this.brief});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFC9B8FF).withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFC9B8FF).withValues(alpha: .26),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✨ IRIS has understood the moment',
            style: GoogleFonts.dmSerifDisplay(
              color: const Color(0xFFC9B8FF),
              fontSize: 22,
              height: 1.05,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your gift remains completely confidential until delivery.\n\nThe Gifts Team now understands the intention behind your gift — not just the budget.',
            style: GoogleFonts.inter(
              color: const Color(0xFFE4DCF5),
              fontSize: 12.5,
              height: 1.48,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _BriefLine(
              label: 'Recipient', value: draft.recipientName ?? 'Not set'),
          _BriefLine(
              label: 'Relationship', value: draft.relationship ?? 'Not set'),
          _BriefLine(label: 'Occasion', value: draft.occasion ?? 'Not set'),
          _BriefLine(
            label: 'Emotional direction',
            value: brief.emotionalDirection,
          ),
          _BriefLine(
            label: 'Experience direction',
            value: brief.experienceDirection,
          ),
          _BriefLine(label: 'Things to avoid', value: brief.thingsToAvoid),
          _BriefLine(
            label: 'Personalisation score',
            value:
                '${draft.irisGiftBrief?.personalisationScore ?? _fallbackScore(brief)}%',
          ),
          _BriefLine(
            label: 'Human review required',
            value: brief.humanReviewRequired ? 'Yes' : 'No',
          ),
        ],
      ),
    );
  }

  int _fallbackScore(SenderGiftBriefPreview brief) {
    return switch (brief.confidence) {
      'High' => 88,
      'Medium' => 74,
      _ => 62,
    };
  }
}

class _BriefLine extends StatelessWidget {
  final String label;
  final String value;

  const _BriefLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: const Color(0xFFB8AAB8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFFB8AAB8),
                fontSize: 10.5,
                letterSpacing: .7,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminPathNote extends StatelessWidget {
  final String text;

  const _AdminPathNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFA8EDEA).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFA8EDEA).withValues(alpha: .24),
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: const Color(0xFFE4DCF5),
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
