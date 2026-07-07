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
  late final TextEditingController _shoeController;
  late final TextEditingController _ringController;
  late final TextEditingController _coloursController;
  late final TextEditingController _brandsController;

  @override
  void initState() {
    super.initState();
    _sizeController = TextEditingController(text: widget.draft.clothingSize);
    _shoeController = TextEditingController(text: widget.draft.shoeSize);
    _ringController = TextEditingController(text: widget.draft.ringSize);
    _coloursController =
        TextEditingController(text: widget.draft.favouriteColours);
    _brandsController = TextEditingController(text: widget.draft.likedBrands);
  }

  @override
  void dispose() {
    _sizeController.dispose();
    _shoeController.dispose();
    _ringController.dispose();
    _coloursController.dispose();
    _brandsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 06 — STYLE & SIZES',
      title: 'Help us get it right',
      subtitle:
          'Share useful sizing and style signals for the Gifts Team and IRIS.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        GiftJourneyWidgets.inputCard(
          controller: _sizeController,
          label: 'CLOTHING SIZE',
          placeholder: 'e.g. UK 10, M',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _shoeController,
          label: 'SHOE SIZE',
          placeholder: 'e.g. UK 6',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _ringController,
          label: 'RING SIZE',
          placeholder: 'Optional',
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
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: 'Continue',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftPrivacyView(
              draft: widget.draft.copyWith(
                clothingSize: _sizeController.text.trim(),
                shoeSize: _shoeController.text.trim(),
                ringSize: _ringController.text.trim(),
                favouriteColours: _coloursController.text.trim(),
                likedBrands: _brandsController.text.trim(),
              ),
            ),
            settings: const RouteSettings(name: GiftPrivacyView.routeName),
          ),
        ),
      ),
    );
  }
}
