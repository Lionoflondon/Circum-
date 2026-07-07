import 'package:flutter/material.dart';

import 'gift_journey_draft.dart';
import 'gift_privacy_view.dart';
import 'gift_relationship_view.dart';

class GiftStyleView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftStyleView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/style';

  @override
  State<GiftStyleView> createState() => _GiftStyleViewState();
}

class _GiftStyleViewState extends State<GiftStyleView> {
  late final TextEditingController _sizeController;
  late final TextEditingController _coloursController;
  late final TextEditingController _brandsController;
  final _stylePills = <String>{};

  @override
  void initState() {
    super.initState();
    _sizeController = TextEditingController(text: widget.draft.clothingSize);
    _coloursController =
        TextEditingController(text: widget.draft.favouriteColours);
    _brandsController = TextEditingController(text: widget.draft.likedBrands);
    _stylePills.addAll(widget.draft.preferredStyles);
  }

  @override
  void dispose() {
    _sizeController.dispose();
    _coloursController.dispose();
    _brandsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 08 — STYLE & SIZES',
      title: 'Help us get it right',
      subtitle:
          'Share useful sizing and style signals for the Gifts Team and IRIS.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        GiftJourneyWidgets.inputCard(
          controller: _sizeController,
          label: 'CLOTHING / SHOE / RING SIZE',
          placeholder: 'e.g. UK 10, UK 6, M',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _coloursController,
          label: 'FAVOURITE COLOURS',
          placeholder: 'e.g. sage green, terracotta',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _brandsController,
          label: 'BRANDS THEY LOVE',
          placeholder: 'e.g. Aesop, Cos',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        _PreferredStyleChips(
          selectedStyles: _stylePills,
          onToggle: (style) => setState(() {
            if (_stylePills.contains(style)) {
              _stylePills.remove(style);
            } else {
              _stylePills.add(style);
            }
          }),
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: 'Continue',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftPrivacyView(
              draft: widget.draft.copyWith(
                clothingSize: _sizeController.text.trim(),
                favouriteColours: _coloursController.text.trim(),
                likedBrands: _brandsController.text.trim(),
                preferredStyles: _stylePills.toList(),
              ),
            ),
            settings: const RouteSettings(name: GiftPrivacyView.routeName),
          ),
        ),
      ),
    );
  }
}

class _PreferredStyleChips extends StatelessWidget {
  final Set<String> selectedStyles;
  final ValueChanged<String> onToggle;

  const _PreferredStyleChips({
    required this.selectedStyles,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    const styles = [
      'Minimal',
      'Classic',
      'Modern',
      'Bold',
      'Luxury',
      'Streetwear',
      'Vintage',
      'Elegant',
      'Sporty',
      'Cosy',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PREFERRED STYLE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFFB8AAB8),
                fontWeight: FontWeight.w800,
                letterSpacing: .7,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose the styles that best describe what they enjoy wearing, collecting or surrounding themselves with.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFE4DCF5).withValues(alpha: .72),
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final style in styles)
              GiftJourneyWidgets.choiceChip(
                label: style,
                selected: selectedStyles.contains(style),
                onTap: () => onToggle(style),
              ),
          ],
        ),
      ],
    );
  }
}
