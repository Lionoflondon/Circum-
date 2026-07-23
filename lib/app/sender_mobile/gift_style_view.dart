import 'package:flutter/material.dart';

import 'gift_journey_draft.dart';
import 'gift_privacy_view.dart';
import 'gift_relationship_view.dart';

const senderGiftPreferenceHelperChips = [
  'Sizes',
  'Brands',
  'Colours',
  'Style',
  'Dislikes',
  'Allergies',
  'Hobbies',
  'No idea',
];

class GiftStyleView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftStyleView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/style';

  @override
  State<GiftStyleView> createState() => _GiftStyleViewState();
}

class _GiftStyleViewState extends State<GiftStyleView> {
  final _preferencesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _preferencesController.text = widget.draft.recipientPreferencesContext;
  }

  @override
  void dispose() {
    _preferencesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 8,
      eyebrow: 'STEP 08 — IRIS CONTEXT',
      title: 'Tell IRIS what you know about them',
      subtitle:
          'Share anything that could help us choose something that feels right. Sizes, brands, colours, style, hobbies, allergies, dislikes, or anything personal.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        GiftJourneyWidgets.inputCard(
          controller: _preferencesController,
          label: 'WHAT WE KNOW ABOUT THEM',
          placeholder:
              'Example: She likes Jo Malone, navy, minimalist jewellery, size M, UK 7 shoes, no roses, loves theatre and quiet luxury.',
          helper: 'Optional. Leave blank if you are not sure yet.',
          maxLines: 8,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final chip in senderGiftPreferenceHelperChips)
              _PreferenceHelperChip(
                label: chip,
                onTap: () => _appendHelper(chip),
              ),
          ],
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: 'Continue',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftPrivacyView(
              draft: widget.draft.copyWith(
                recipientPreferencesFreeform: _preferencesController.text
                    .trim(),
              ),
            ),
            settings: const RouteSettings(name: GiftPrivacyView.routeName),
          ),
        ),
      ),
    );
  }

  void _appendHelper(String label) {
    final prompt = label == 'No idea' ? 'No idea yet.' : '$label: ';
    final current = _preferencesController.text.trimRight();
    final next = current.isEmpty ? prompt : '$current\n$prompt';
    setState(() {
      _preferencesController.text = next;
      _preferencesController.selection = TextSelection.collapsed(
        offset: _preferencesController.text.length,
      );
    });
  }
}

class _PreferenceHelperChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PreferenceHelperChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .052),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFEDE8F5),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
