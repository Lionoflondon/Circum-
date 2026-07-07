import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_delivery_view.dart';

const senderGiftRelationshipFieldName = 'relationship';
const senderGiftOccasionFieldName = 'occasion';
const senderGiftRecipientContactFieldName = 'recipientContact';

const senderGiftRelationshipOptions = [
  'Partner',
  'Husband',
  'Wife',
  'Boyfriend',
  'Girlfriend',
  'Fiancé',
  'Fiancée',
  'Crush',
  'Date',
  'Mother',
  'Father',
  'Parent',
  'Stepmother',
  'Stepfather',
  'Son',
  'Daughter',
  'Child',
  'Brother',
  'Sister',
  'Sibling',
  'Grandmother',
  'Grandfather',
  'Grandparent',
  'Grandson',
  'Granddaughter',
  'Grandchild',
  'Aunt',
  'Uncle',
  'Niece',
  'Nephew',
  'Cousin',
  'Godmother',
  'Godfather',
  'Godchild',
  'In-law',
  'Friend',
  'Best Friend',
  'Close Friend',
  'Childhood Friend',
  'Family Friend',
  'Housemate',
  'Neighbour',
  'Colleague',
  'Manager',
  'Boss',
  'Employee',
  'Mentor',
  'Mentee',
  'Client',
  'Customer',
  'Business Partner',
  'Teacher',
  'Tutor',
  'Student',
  'Coach',
  'Team Member',
  'Church Member',
  'Pastor',
  'Community Member',
  'Volunteer',
  'Carer',
  'Support Worker',
  'Local Hero',
  'Myself',
  'Anonymous Recipient',
  'Secret Recipient',
  'Someone Special',
  'Other',
];

const senderGiftOccasionOptions = [
  'Birthday',
  'Anniversary',
  'Wedding',
  'Engagement',
  'Proposal',
  'Graduation',
  'Promotion',
  'Retirement',
  'New Job',
  'New Business',
  'Business Milestone',
  'Work Anniversary',
  'Passing Exams',
  'Academic Achievement',
  'New Baby',
  'Baby Shower',
  'Gender Reveal',
  'Adoption',
  'Housewarming',
  'First Home',
  'Moving Home',
  'Family Reunion',
  'Thank You',
  'Appreciation',
  'Recognition',
  'Well Done',
  'Congratulations',
  'Good Luck',
  'Welcome',
  'Welcome Back',
  'Get Well Soon',
  'Recovery',
  'Hospital Discharge',
  'Encouragement',
  'Thinking Of You',
  'Difficult Time',
  'Bereavement',
  'Sympathy',
  'Care Package',
  'Date Night',
  'Romantic Surprise',
  "Valentine's Day",
  'First Anniversary',
  'Reconciliation',
  'Just Because I Love You',
  'Christmas',
  'New Year',
  'Easter',
  "Mother's Day",
  "Father's Day",
  'Eid al-Fitr',
  'Eid al-Adha',
  'Diwali',
  'Hanukkah',
  'Lunar New Year',
  'Thanksgiving',
  'Halloween',
  'Baptism',
  'Christening',
  'Confirmation',
  'First Communion',
  'Bar Mitzvah',
  'Bat Mitzvah',
  'Religious Celebration',
  'First Day of School',
  'School Graduation',
  'Passing Driving Test',
  'University Acceptance',
  'Sports Achievement',
  'Anonymous Kindness',
  'Community Campaign',
  'Bringing London Together',
  'Local Hero',
  'Volunteer Recognition',
  'Just Because',
  'Random Act of Kindness',
  'Surprise Gift',
  'Missing You',
  'Friendship Celebration',
  'Apology',
  'Bank Holiday Surprise',
  'Leaving Gift',
  'Achievement Reward',
  'Other',
];

class GiftRelationshipView extends StatefulWidget {
  const GiftRelationshipView({super.key});

  static const routeName = '/sender-mobile/gifts/relationship';

  @override
  State<GiftRelationshipView> createState() => _GiftRelationshipViewState();
}

class _GiftRelationshipViewState extends State<GiftRelationshipView> {
  final _contactController = TextEditingController();
  String? _relationship;
  String? _occasion;

  bool get _canContinue =>
      _relationship != null &&
      _occasion != null &&
      _contactController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _contactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GiftJourneyScaffold(
      activeStep: 2,
      eyebrow: 'STEP 02 — RECIPIENT',
      title: 'Tell us about them',
      subtitle: 'Tell IRIS who this is for so we can shape the experience.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        _GiftGlassDropdown(
          label: 'RELATIONSHIP',
          value: _relationship,
          placeholder: 'Choose relationship',
          options: senderGiftRelationshipOptions,
          onChanged: (value) => setState(() => _relationship = value),
        ),
        const SizedBox(height: 12),
        _GiftGlassDropdown(
          label: 'OCCASION',
          value: _occasion,
          placeholder: 'Choose occasion',
          options: senderGiftOccasionOptions,
          onChanged: (value) => setState(() => _occasion = value),
        ),
        const SizedBox(height: 12),
        _GiftInputCard(
          controller: _contactController,
          label: 'PHONE & EMAIL',
          helper: 'Used for delivery updates only.',
          placeholder: 'Phone or email',
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 28),
        _GiftPrimaryButton(
          enabled: _canContinue,
          label: 'Continue',
          onTap: !_canContinue
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const GiftDeliveryView(),
                      settings: const RouteSettings(
                        name: GiftDeliveryView.routeName,
                      ),
                    ),
                  ),
        ),
      ],
    );
  }
}

class GiftJourneyPlaceholderView extends StatelessWidget {
  final String message;

  const GiftJourneyPlaceholderView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _GiftJourneyTokens.bg,
      body: Stack(
        children: [
          const _GiftJourneyAmbient(),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSerifDisplay(
                    color: Colors.white,
                    fontSize: 32,
                    height: 1.08,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GiftJourneyWidgets {
  static Widget scaffold({
    required int activeStep,
    required String eyebrow,
    required String title,
    required String subtitle,
    required VoidCallback onBack,
    required List<Widget> children,
  }) {
    return _GiftJourneyScaffold(
      activeStep: activeStep,
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      onBack: onBack,
      children: children,
    );
  }

  static Widget inputCard({
    required TextEditingController controller,
    required String label,
    required String placeholder,
    required ValueChanged<String> onChanged,
    String? helper,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return _GiftInputCard(
      controller: controller,
      label: label,
      helper: helper,
      placeholder: placeholder,
      onChanged: onChanged,
      maxLines: maxLines,
      keyboardType: keyboardType,
    );
  }

  static Widget primaryButton({
    required bool enabled,
    required String label,
    required VoidCallback? onTap,
  }) {
    return _GiftPrimaryButton(enabled: enabled, label: label, onTap: onTap);
  }

  static Widget choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return _GiftChoiceChip(label: label, selected: selected, onTap: onTap);
  }
}

class _GiftJourneyScaffold extends StatelessWidget {
  final int activeStep;
  final String eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final List<Widget> children;

  const _GiftJourneyScaffold({
    required this.activeStep,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _GiftJourneyTokens.bg,
      body: Stack(
        children: [
          const _GiftJourneyAmbient(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _GiftBackButton(onTap: onBack),
                ),
                const SizedBox(height: 28),
                _GiftStepProgress(activeStep: activeStep),
                const SizedBox(height: 20),
                Text(
                  eyebrow,
                  style: GoogleFonts.jetBrainsMono(
                    color: _GiftJourneyTokens.htmlIri2,
                    fontSize: 10.5,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: GoogleFonts.dmSerifDisplay(
                    color: Colors.white,
                    fontSize: 38,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: _GiftJourneyTokens.muted,
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 26),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftGlassDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final String placeholder;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _GiftGlassDropdown({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _GiftJourneyTokens.pearlBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              color: _GiftJourneyTokens.htmlIri2,
              fontSize: 10.5,
              letterSpacing: .8,
              fontWeight: FontWeight.w700,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: const Color(0xFF171522),
              value: value,
              hint: Text(
                placeholder,
                style: GoogleFonts.inter(
                  color: _GiftJourneyTokens.muted.withValues(alpha: .72),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              iconEnabledColor: _GiftJourneyTokens.htmlIri2,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              items: options
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(option, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (selected) {
                if (selected != null) onChanged(selected);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftInputCard extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final TextInputType keyboardType;

  const _GiftInputCard({
    required this.controller,
    required this.label,
    required this.placeholder,
    required this.onChanged,
    this.helper,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _GiftJourneyTokens.pearlBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              color: _GiftJourneyTokens.htmlIri2,
              fontSize: 10.5,
              letterSpacing: .8,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 6),
            Text(
              helper!,
              style: GoogleFonts.inter(
                color: _GiftJourneyTokens.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            minLines: maxLines,
            onChanged: onChanged,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: placeholder,
              hintStyle: GoogleFonts.inter(
                color: _GiftJourneyTokens.muted.withValues(alpha: .66),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GiftChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _GiftJourneyTokens.rose.withValues(alpha: .15)
              : Colors.white.withValues(alpha: .052),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? _GiftJourneyTokens.htmlIri2.withValues(alpha: .62)
                : _GiftJourneyTokens.pearlBorder,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _GiftPrimaryButton extends StatelessWidget {
  final bool enabled;
  final String label;
  final VoidCallback? onTap;

  const _GiftPrimaryButton({
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: enabled ? 1 : .45,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [
                  _GiftJourneyTokens.iri1,
                  _GiftJourneyTokens.iri2,
                  _GiftJourneyTokens.iri3,
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: _GiftJourneyTokens.ink,
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GiftBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _GiftBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .055),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _GiftJourneyTokens.pearlBorder),
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 21,
          ),
        ),
      ),
    );
  }
}

class _GiftStepProgress extends StatelessWidget {
  final int activeStep;

  const _GiftStepProgress({required this.activeStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var step = 1; step <= 4; step++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: step <= activeStep
                    ? const LinearGradient(
                        colors: [
                          _GiftJourneyTokens.iri1,
                          _GiftJourneyTokens.iri2,
                          _GiftJourneyTokens.iri3,
                        ],
                      )
                    : null,
                color: step <= activeStep
                    ? null
                    : Colors.white.withValues(alpha: .08),
              ),
            ),
          ),
          if (step != 4) const SizedBox(width: 5),
        ],
      ],
    );
  }
}

class _GiftJourneyAmbient extends StatelessWidget {
  const _GiftJourneyAmbient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.1,
          colors: [Color(0x26E8B4A0), Color(0x0007090F)],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _GiftJourneyTokens {
  static const bg = Color(0xFF07090F);
  static const muted = Color(0xFFB8AAB8);
  static const htmlIri2 = Color(0xFFC9B8FF);
  static const rose = Color(0xFFE8B4A0);
  static const pearlBorder = Color(0x24F5F0E8);
  static const iri1 = Color(0xFFA8EDEA);
  static const iri2 = Color(0xFFC9B8FF);
  static const iri3 = Color(0xFFFFD6E8);
  static const ink = Color(0xFF1A1330);
}
