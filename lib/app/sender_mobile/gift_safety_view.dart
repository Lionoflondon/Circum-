import 'package:flutter/material.dart';

import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';
import 'gift_review_view.dart';

class GiftSafetyView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftSafetyView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/safety';

  @override
  State<GiftSafetyView> createState() => _GiftSafetyViewState();
}

class _GiftSafetyViewState extends State<GiftSafetyView> {
  late final TextEditingController _foodAllergiesController;
  late final TextEditingController _medicalAllergiesController;
  late final TextEditingController _dietaryRestrictionsController;
  late final TextEditingController _culturalConsiderationsController;
  late final TextEditingController _thingsToAvoidController;
  late final TextEditingController _giftTeamNotesController;

  @override
  void initState() {
    super.initState();
    _foodAllergiesController = TextEditingController(
      text: widget.draft.foodAllergies ?? '',
    );
    _medicalAllergiesController = TextEditingController(
      text: widget.draft.medicalAllergies ?? '',
    );
    _dietaryRestrictionsController = TextEditingController(
      text: widget.draft.dietaryRestrictions ?? '',
    );
    _culturalConsiderationsController = TextEditingController(
      text: widget.draft.culturalConsiderations ?? '',
    );
    _thingsToAvoidController = TextEditingController(
      text: widget.draft.safetyThingsToAvoid ?? '',
    );
    _giftTeamNotesController = TextEditingController(
      text: widget.draft.giftTeamNotes ?? '',
    );
  }

  @override
  void dispose() {
    _foodAllergiesController.dispose();
    _medicalAllergiesController.dispose();
    _dietaryRestrictionsController.dispose();
    _culturalConsiderationsController.dispose();
    _thingsToAvoidController.dispose();
    _giftTeamNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 11,
      eyebrow: 'SAFETY',
      title: 'Anything we need to know?',
      subtitle: 'Help the Gifts Team avoid unsuitable or unsafe gifts.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        GiftJourneyWidgets.inputCard(
          controller: _foodAllergiesController,
          label: 'FOOD ALLERGIES',
          placeholder: 'Nut allergy',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _medicalAllergiesController,
          label: 'MEDICAL ALLERGIES',
          placeholder: 'Sensitive skin',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _dietaryRestrictionsController,
          label: 'DIETARY RESTRICTIONS',
          placeholder: 'Vegan, diabetic, no alcohol',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _culturalConsiderationsController,
          label: 'RELIGIOUS OR CULTURAL CONSIDERATIONS',
          placeholder: 'Anything the Gifts Team should respect',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _thingsToAvoidController,
          label: 'THINGS TO AVOID',
          placeholder: "No perfume, no flowers, doesn't wear jewellery",
          onChanged: (_) => setState(() {}),
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _giftTeamNotesController,
          label: 'ANYTHING ELSE THE GIFTS TEAM SHOULD KNOW',
          placeholder:
              'Claustrophobic, prefers quiet experiences, anything else',
          onChanged: (_) => setState(() {}),
          maxLines: 3,
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: true,
        label: 'Continue to Review',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftReviewView(draft: _nextDraft()),
            settings: const RouteSettings(name: GiftReviewView.routeName),
          ),
        ),
      ),
    );
  }

  GiftJourneyDraft _nextDraft() {
    return widget.draft.copyWith(
      foodAllergies: _foodAllergiesController.text.trim(),
      medicalAllergies: _medicalAllergiesController.text.trim(),
      dietaryRestrictions: _dietaryRestrictionsController.text.trim(),
      culturalConsiderations: _culturalConsiderationsController.text.trim(),
      safetyThingsToAvoid: _thingsToAvoidController.text.trim(),
      giftTeamNotes: _giftTeamNotesController.text.trim(),
    );
  }
}
