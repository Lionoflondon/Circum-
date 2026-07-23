import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_journey_draft.dart';
import 'gift_payment_view.dart';
import 'gift_relationship_view.dart';

class GiftPrePaymentView extends StatelessWidget {
  final GiftJourneyDraft draft;

  const GiftPrePaymentView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/pre-payment';

  @override
  Widget build(BuildContext context) {
    final brief = draft.irisGiftBrief ?? draft.generateIrisBrief();
    return GiftJourneyWidgets.scaffold(
      activeStep: 11,
      eyebrow: 'BEFORE PAYMENT',
      title: "We've understood the moment",
      subtitle:
          'Every experience is reviewed by a real member of our Gifts Team before sourcing begins.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        _MomentRow(label: 'Recipient', value: draft.recipientName ?? 'Not set'),
        _MomentRow(label: 'Occasion', value: draft.occasion ?? 'Not set'),
        _MomentRow(
          label: 'Delivery Date',
          value: draft.deliveryDate ?? 'Date not set',
        ),
        _MomentRow(
          label: 'Budget',
          value: '£${draft.budget.toStringAsFixed(0)}',
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFC9B8FF).withValues(alpha: .08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFC9B8FF).withValues(alpha: .24),
            ),
          ),
          child: Text(
            'IRIS believes this occasion deserves a thoughtful experience centred around ${brief.emotionalDirection.toLowerCase()}',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: 'Continue',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                GiftPaymentView(draft: draft.copyWith(irisGiftBrief: brief)),
            settings: const RouteSettings(name: GiftPaymentView.routeName),
          ),
        ),
      ),
    );
  }
}

class _MomentRow extends StatelessWidget {
  final String label;
  final String value;

  const _MomentRow({required this.label, required this.value});

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
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
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
