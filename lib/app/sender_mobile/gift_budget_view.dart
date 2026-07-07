import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';
import 'gift_review_view.dart';

class GiftBudgetView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftBudgetView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/budget';

  @override
  State<GiftBudgetView> createState() => _GiftBudgetViewState();
}

class _GiftBudgetViewState extends State<GiftBudgetView> {
  late double _budget;

  @override
  void initState() {
    super.initState();
    _budget = widget.draft.budget;
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 10 — BUDGET',
      title: 'Set a gift budget',
      subtitle:
          'Choose the experience budget. IRIS will curate the best possible gift within your chosen budget.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .052),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: .09)),
          ),
          child: Column(
            children: [
              Text(
                '£${_budget.toStringAsFixed(0)}',
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontSize: 54,
                  height: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Slider(
                value: _budget,
                min: 50,
                max: 1500,
                divisions: 145,
                activeColor: const Color(0xFFC9B8FF),
                inactiveColor: Colors.white.withValues(alpha: .12),
                onChanged: (value) => setState(() => _budget = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final amount in senderGiftBudgetOptions)
              GiftJourneyWidgets.choiceChip(
                label: '£$amount',
                selected: _budget.round() == amount,
                onTap: () => setState(() => _budget = amount.toDouble()),
              ),
          ],
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: 'Continue to Review',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftReviewView(
              draft: widget.draft.copyWith(budget: _budget.roundToDouble()),
            ),
            settings: const RouteSettings(name: GiftReviewView.routeName),
          ),
        ),
      ),
    );
  }
}
