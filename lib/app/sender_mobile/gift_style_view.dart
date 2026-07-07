import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  late final TextEditingController _clothingSizeController;
  late final TextEditingController _shoeSizeController;
  late final TextEditingController _ringSizeController;
  late final TextEditingController _brandsController;
  final _stylePills = <String>{};
  final _colourPills = <String>{};

  @override
  void initState() {
    super.initState();
    _clothingSizeController =
        TextEditingController(text: widget.draft.clothingSize);
    _shoeSizeController = TextEditingController(text: widget.draft.shoeSize);
    _ringSizeController = TextEditingController(text: widget.draft.ringSize);
    _brandsController = TextEditingController(text: widget.draft.likedBrands);
    _stylePills.addAll(widget.draft.preferredStyles);
    _colourPills.addAll(
      (widget.draft.favouriteColours ?? '')
          .split(',')
          .map((colour) => colour.trim())
          .where((colour) => colour.isNotEmpty),
    );
  }

  @override
  void dispose() {
    _clothingSizeController.dispose();
    _shoeSizeController.dispose();
    _ringSizeController.dispose();
    _brandsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 8,
      eyebrow: 'STEP 08 — STYLE & SIZES',
      title: 'Their style',
      subtitle:
          'These choices help us understand what naturally feels like them.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        GiftJourneyWidgets.inputCard(
          controller: _clothingSizeController,
          label: 'CLOTHING SIZE',
          placeholder: 'e.g. UK 10, M',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _shoeSizeController,
          label: 'SHOE SIZE',
          placeholder: 'e.g. UK 6',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _ringSizeController,
          label: 'RING SIZE',
          placeholder: 'e.g. L, 52, unknown',
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
        _ColourChips(
          selectedColours: _colourPills,
          onToggle: (colour) => setState(() {
            if (_colourPills.contains(colour)) {
              _colourPills.remove(colour);
            } else {
              _colourPills.add(colour);
            }
          }),
        ),
        const SizedBox(height: 16),
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
                clothingSize: _clothingSizeController.text.trim(),
                shoeSize: _shoeSizeController.text.trim(),
                ringSize: _ringSizeController.text.trim(),
                favouriteColours: _colourPills.join(', '),
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

class _ColourChips extends StatelessWidget {
  final Set<String> selectedColours;
  final ValueChanged<String> onToggle;

  const _ColourChips({
    required this.selectedColours,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    const colours = [
      'Black',
      'White',
      'Navy',
      'Cream',
      'Sage',
      'Pink',
      'Gold',
      'Silver',
      'Brown',
      'Green',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COLOUR NOTES',
          style: GoogleFonts.jetBrainsMono(
            color: const Color(0xFFB8AAB8),
            fontSize: 10,
            letterSpacing: .7,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final colour in colours)
              GiftJourneyWidgets.choiceChip(
                label: colour,
                selected: selectedColours.contains(colour),
                onTap: () => onToggle(colour),
              ),
          ],
        ),
      ],
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
