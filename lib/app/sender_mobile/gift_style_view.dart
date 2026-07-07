import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_journey_draft.dart';
import 'gift_privacy_view.dart';
import 'gift_relationship_view.dart';

const senderGiftClothingSizeOptions = ['XS', 'S', 'M', 'L', 'XL', 'Unknown'];
const senderGiftShoeSizeOptions = [
  'UK 4',
  'UK 5',
  'UK 6',
  'UK 7',
  'UK 8',
  'Unknown'
];
const senderGiftRingSizeOptions = ['J', 'K', 'L', 'M', 'N', 'Unknown'];
const senderGiftBrandOptions = [
  'Aesop',
  'COS',
  'Jo Malone',
  'Selfridges',
  'Fortnum & Mason',
  'Independent makers',
  'No preference',
];
const senderGiftColourOptions = [
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
const senderGiftPreferredStyleOptions = [
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

class GiftStyleView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftStyleView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/style';

  @override
  State<GiftStyleView> createState() => _GiftStyleViewState();
}

class _GiftStyleViewState extends State<GiftStyleView> {
  final _clothingSizeController = TextEditingController();
  final _shoeSizeController = TextEditingController();
  final _ringSizeController = TextEditingController();
  final _brandController = TextEditingController();
  final _colourController = TextEditingController();
  final _styleController = TextEditingController();
  String? _clothingSize;
  String? _shoeSize;
  String? _ringSize;
  final _brandPills = <String>{};
  final _stylePills = <String>{};
  final _colourPills = <String>{};

  bool get _usesFreeEntry => widget.draft.mode == SenderGiftMode.someone;

  @override
  void initState() {
    super.initState();
    _clothingSizeController.text = widget.draft.clothingSize ?? '';
    _shoeSizeController.text = widget.draft.shoeSize ?? '';
    _ringSizeController.text = widget.draft.ringSize ?? '';
    _brandController.text = widget.draft.likedBrands ?? '';
    _colourController.text = widget.draft.favouriteColours ?? '';
    _styleController.text = widget.draft.preferredStyles.join(', ');
    _clothingSize = _existingOrNull(
      widget.draft.clothingSize,
      senderGiftClothingSizeOptions,
    );
    _shoeSize = _existingOrNull(
      widget.draft.shoeSize,
      senderGiftShoeSizeOptions,
    );
    _ringSize = _existingOrNull(
      widget.draft.ringSize,
      senderGiftRingSizeOptions,
    );
    _brandPills
        .addAll(_existingSet(widget.draft.likedBrands, senderGiftBrandOptions));
    _stylePills.addAll(widget.draft.preferredStyles);
    _colourPills.addAll(
        _existingSet(widget.draft.favouriteColours, senderGiftColourOptions));
  }

  @override
  void dispose() {
    _clothingSizeController.dispose();
    _shoeSizeController.dispose();
    _ringSizeController.dispose();
    _brandController.dispose();
    _colourController.dispose();
    _styleController.dispose();
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
        if (_usesFreeEntry) ...[
          GiftJourneyWidgets.inputCard(
            controller: _clothingSizeController,
            label: 'CLOTHING SIZE',
            placeholder: 'Tell us what you know',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          GiftJourneyWidgets.inputCard(
            controller: _shoeSizeController,
            label: 'SHOE SIZE',
            placeholder: 'Tell us what you know',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          GiftJourneyWidgets.inputCard(
            controller: _ringSizeController,
            label: 'RING SIZE',
            placeholder: 'Tell us what you know',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          GiftJourneyWidgets.inputCard(
            controller: _brandController,
            label: 'BRANDS THEY LOVE',
            placeholder: 'Brands, shops or makers they naturally like',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          GiftJourneyWidgets.inputCard(
            controller: _colourController,
            label: 'COLOUR NOTES',
            placeholder: 'Colours, tones or materials they gravitate toward',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          GiftJourneyWidgets.inputCard(
            controller: _styleController,
            label: 'PREFERRED STYLE',
            placeholder: 'Minimal, cosy, elegant, bold, vintage...',
            helper:
                'Describe what they enjoy wearing, collecting or surrounding themselves with.',
            onChanged: (_) => setState(() {}),
            maxLines: 3,
          ),
        ] else ...[
          _FixedChoiceSection(
            label: 'CLOTHING SIZE',
            helper: 'Choose the closest known size.',
            options: senderGiftClothingSizeOptions,
            selected: _clothingSize == null ? const {} : {_clothingSize!},
            onToggle: (value) => setState(() => _clothingSize = value),
          ),
          const SizedBox(height: 14),
          _FixedChoiceSection(
            label: 'SHOE SIZE',
            helper: 'Choose the closest known size.',
            options: senderGiftShoeSizeOptions,
            selected: _shoeSize == null ? const {} : {_shoeSize!},
            onToggle: (value) => setState(() => _shoeSize = value),
          ),
          const SizedBox(height: 14),
          _FixedChoiceSection(
            label: 'RING SIZE',
            helper: 'Choose a known size or mark it unknown.',
            options: senderGiftRingSizeOptions,
            selected: _ringSize == null ? const {} : {_ringSize!},
            onToggle: (value) => setState(() => _ringSize = value),
          ),
          const SizedBox(height: 14),
          _FixedChoiceSection(
            label: 'BRANDS THEY LOVE',
            helper: 'Select any known preferences.',
            options: senderGiftBrandOptions,
            selected: _brandPills,
            onToggle: (value) => _toggle(_brandPills, value),
          ),
          const SizedBox(height: 14),
          _FixedChoiceSection(
            label: 'COLOUR NOTES',
            helper: 'Select colours that feel natural for them.',
            options: senderGiftColourOptions,
            selected: _colourPills,
            onToggle: (value) => _toggle(_colourPills, value),
          ),
          const SizedBox(height: 14),
          _FixedChoiceSection(
            label: 'PREFERRED STYLE',
            helper:
                'Choose the styles that best describe what they enjoy wearing, collecting or surrounding themselves with.',
            options: senderGiftPreferredStyleOptions,
            selected: _stylePills,
            onToggle: (value) => _toggle(_stylePills, value),
          ),
        ],
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: 'Continue',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftPrivacyView(
              draft: widget.draft.copyWith(
                clothingSize: _usesFreeEntry
                    ? _clothingSizeController.text.trim()
                    : _clothingSize,
                shoeSize: _usesFreeEntry
                    ? _shoeSizeController.text.trim()
                    : _shoeSize,
                ringSize: _usesFreeEntry
                    ? _ringSizeController.text.trim()
                    : _ringSize,
                favouriteColours: _usesFreeEntry
                    ? _colourController.text.trim()
                    : _colourPills.join(', '),
                likedBrands: _usesFreeEntry
                    ? _brandController.text.trim()
                    : _brandPills.join(', '),
                preferredStyles: _usesFreeEntry
                    ? _freeTextList(_styleController.text)
                    : _stylePills.toList(),
              ),
            ),
            settings: const RouteSettings(name: GiftPrivacyView.routeName),
          ),
        ),
      ),
    );
  }

  void _toggle(Set<String> target, String value) {
    setState(() {
      if (target.contains(value)) {
        target.remove(value);
      } else {
        target.add(value);
      }
    });
  }

  static String? _existingOrNull(String? value, List<String> options) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return options.contains(trimmed) ? trimmed : null;
  }

  static Set<String> _existingSet(String? value, List<String> options) {
    return {
      for (final item in (value ?? '').split(',').map((item) => item.trim()))
        if (item.isNotEmpty && options.contains(item)) item,
    };
  }

  static List<String> _freeTextList(String value) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}

class _FixedChoiceSection extends StatelessWidget {
  final String label;
  final String helper;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _FixedChoiceSection({
    required this.label,
    required this.helper,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFFC9B8FF),
              fontSize: 10.5,
              letterSpacing: .8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            helper,
            style: GoogleFonts.inter(
              color: const Color(0xFFB8AAB8),
              fontSize: 11.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                GiftJourneyWidgets.choiceChip(
                  label: option,
                  selected: selected.contains(option),
                  onTap: () => onToggle(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
