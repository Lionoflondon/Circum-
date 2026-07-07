import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';
import 'gift_story_view.dart';

class GiftStatusView extends StatelessWidget {
  final GiftJourneyDraft draft;

  const GiftStatusView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/status';

  static const statusLabels = [
    'Request received',
    'Planning begins',
    'Experience prepared',
    'Quality review',
    'Awaiting rider',
    'Out for delivery',
    'Delivered',
    'Gift Story rendering',
    'Gift Story ready',
  ];

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 13 — STATUS',
      title: 'Your gift is in safe hands.',
      subtitle:
          "We'll quietly take care of everything behind the scenes.\n\nYou'll only hear from us when there's something meaningful to share.",
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        for (var i = 0; i < statusLabels.length; i++)
          _StatusRow(
            label: _dateAwareLabel(statusLabels[i]),
            active: i <= 1,
            last: i == statusLabels.length - 1,
          ),
        const SizedBox(height: 14),
        const _GiftTeamFooter(),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: 'Preview Gift Story',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftStoryView(draft: draft),
            settings: const RouteSettings(name: GiftStoryView.routeName),
          ),
        ),
      ),
    );
  }

  String _dateAwareLabel(String label) {
    if (label == 'Planning begins' && (draft.deliveryDate ?? '').isNotEmpty) {
      return 'Planning begins around ${draft.deliveryDate}';
    }
    return label;
  }
}

class _GiftTeamFooter extends StatelessWidget {
  const _GiftTeamFooter();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Curated by the Gifts Team\nSupported by IRIS\nEvery experience is reviewed by a real person before sourcing begins.',
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        color: const Color(0xFFB8AAB8),
        fontSize: 12,
        height: 1.45,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final bool active;
  final bool last;

  const _StatusRow({
    required this.label,
    required this.active,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: active
                    ? const LinearGradient(
                        colors: [
                          Color(0xFFA8EDEA),
                          Color(0xFFC9B8FF),
                          Color(0xFFFFD6E8),
                        ],
                      )
                    : null,
                color: active ? null : Colors.white.withValues(alpha: .12),
              ),
            ),
            if (!last)
              Container(
                width: 1,
                height: 34,
                color: Colors.white.withValues(alpha: .12),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: active ? Colors.white : const Color(0xFFB8AAB8),
                fontSize: 14,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
