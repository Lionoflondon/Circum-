import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_delivery_view.dart';
import 'gift_journey_draft.dart';

const senderGiftRelationshipFieldName = 'relationship';
const senderGiftOccasionFieldName = 'occasion';
const senderGiftRecipientNameFieldName = 'recipientName';
const senderGiftRecipientPhoneFieldName = 'recipientPhone';
const senderGiftRecipientEmailFieldName = 'recipientEmail';
const senderGiftRecipientContactFieldName = 'recipientContact';
const senderGiftRecipientNotesFieldName = 'notes';

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
  final GiftJourneyDraft draft;

  const GiftRelationshipView({
    super.key,
    this.draft = const GiftJourneyDraft(mode: SenderGiftMode.someone),
  });

  static const routeName = '/sender-mobile/gifts/relationship';

  @override
  State<GiftRelationshipView> createState() => _GiftRelationshipViewState();
}

class _GiftRelationshipViewState extends State<GiftRelationshipView> {
  late final TextEditingController _nameController;
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();
  late String? _relationship;
  late String? _occasion;
  late String? _senderRevealMode;
  late String? _selfGiftFrequency;

  bool get _canContinue =>
      _nameController.text.trim().isNotEmpty &&
      _relationship != null &&
      _occasion != null &&
      _phoneController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.draft.recipientName ?? '',
    );
    _phoneController.text = widget.draft.recipientPhone ?? '';
    _emailController.text = widget.draft.recipientEmail ?? '';
    _notesController.text = widget.draft.notes ?? '';
    _relationship = widget.draft.relationship;
    _occasion = widget.draft.occasion;
    _senderRevealMode = widget.draft.senderRevealMode;
    _selfGiftFrequency = widget.draft.selfGiftFrequency;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GiftJourneyScaffold(
      activeStep: 2,
      eyebrow: 'STEP 02 — RECIPIENT',
      title: _title,
      subtitle: _subtitle,
      onBack: () => Navigator.of(context).maybePop(),
      footer: _GiftPrimaryButton(
        enabled: _canContinue,
        label: 'Continue',
        onTap: !_canContinue
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GiftDeliveryView(
                      draft: widget.draft.copyWith(
                        recipientName: _nameController.text.trim(),
                        relationship: _relationship,
                        occasion: _occasion,
                        recipientPhone: _phoneController.text.trim(),
                        recipientEmail: _emailController.text.trim(),
                        notes: _notesController.text.trim(),
                        senderRevealMode: _senderRevealMode,
                        selfGiftFrequency: _selfGiftFrequency,
                      ),
                    ),
                    settings: const RouteSettings(
                      name: GiftDeliveryView.routeName,
                    ),
                  ),
                ),
      ),
      children: [
        _GiftInputCard(
          controller: _nameController,
          label: _nameLabel,
          placeholder: _namePlaceholder,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
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
        if (widget.draft.mode == SenderGiftMode.myself) ...[
          const SizedBox(height: 12),
          _GiftGlassDropdown(
            label: 'SELF-GIFT FREQUENCY',
            value: _selfGiftFrequency,
            placeholder: 'Choose frequency',
            options: senderGiftSelfFrequencyOptions.values.toList(),
            onChanged: (value) {
              final entry = senderGiftSelfFrequencyOptions.entries.firstWhere(
                (entry) => entry.value == value,
              );
              setState(() => _selfGiftFrequency = entry.key);
            },
            displayValue: _selfGiftFrequency == null
                ? null
                : senderGiftSelfFrequencyOptions[_selfGiftFrequency],
          ),
        ],
        const SizedBox(height: 12),
        _GiftContactCard(
          phoneController: _phoneController,
          emailController: _emailController,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _GiftInputCard(
          controller: _notesController,
          label: widget.draft.mode == SenderGiftMode.myself
              ? 'WHAT MAKES YOU SPECIAL?'
              : 'TELL US ABOUT THEM',
          placeholder: widget.draft.mode == SenderGiftMode.myself
              ? 'What makes you special?'
              : 'What makes them special?',
          maxLines: 5,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  String get _title => switch (widget.draft.mode) {
        SenderGiftMode.myself => 'Tell us about yourself',
        SenderGiftMode.anonymous => 'Keep it thoughtful',
        SenderGiftMode.campaign => 'Shape the campaign',
        SenderGiftMode.someone => 'Tell us about them',
      };

  String get _subtitle => switch (widget.draft.mode) {
        SenderGiftMode.myself =>
          'Tell IRIS what would make this feel considered.',
        SenderGiftMode.anonymous =>
          'Circum keeps your identity private while Admin can still review the request safely.',
        SenderGiftMode.campaign =>
          'Use the Bringing London Closer campaign path already defined in Gifts.',
        SenderGiftMode.someone =>
          'Tell IRIS who this is for so we can shape the experience.',
      };

  String get _nameLabel => switch (widget.draft.mode) {
        SenderGiftMode.myself => 'YOUR NAME',
        SenderGiftMode.campaign => 'RECIPIENT OR GROUP',
        _ => 'RECIPIENT NAME',
      };

  String get _namePlaceholder => switch (widget.draft.mode) {
        SenderGiftMode.myself => 'What should we call you?',
        SenderGiftMode.campaign => 'Who is this campaign for?',
        _ => "Who's receiving this?",
      };
}

class _GiftContactCard extends StatelessWidget {
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final ValueChanged<String> onChanged;

  const _GiftContactCard({
    required this.phoneController,
    required this.emailController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _GiftJourneyTokens.pearlBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PHONE & EMAIL',
            style: GoogleFonts.jetBrainsMono(
              color: _GiftJourneyTokens.htmlIri2,
              fontSize: 10.5,
              letterSpacing: .8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Used for delivery updates only.',
            style: GoogleFonts.inter(
              color: _GiftJourneyTokens.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          _GiftInlineTextField(
            controller: phoneController,
            placeholder: 'Phone number',
            keyboardType: TextInputType.phone,
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: Colors.white.withValues(alpha: .08)),
          const SizedBox(height: 12),
          _GiftInlineTextField(
            controller: emailController,
            placeholder: 'Email address',
            keyboardType: TextInputType.emailAddress,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _GiftInlineTextField extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;
  final TextInputType keyboardType;
  final ValueChanged<String> onChanged;

  const _GiftInlineTextField({
    required this.controller,
    required this.placeholder,
    required this.keyboardType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
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
    Widget? footer,
  }) {
    return _GiftJourneyScaffold(
      activeStep: activeStep,
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      onBack: onBack,
      footer: footer,
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

  static Widget dropdown({
    required String label,
    required String? value,
    required String placeholder,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return _GiftGlassDropdown(
      label: label,
      value: value,
      placeholder: placeholder,
      options: options,
      onChanged: onChanged,
    );
  }
}

class _GiftJourneyScaffold extends StatelessWidget {
  final int activeStep;
  final String eyebrow;
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final List<Widget> children;
  final Widget? footer;

  const _GiftJourneyScaffold({
    required this.activeStep,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.children,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _GiftJourneyTokens.bg,
      body: Stack(
        children: [
          const _GiftJourneyAmbient(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _GiftBackButton(onTap: onBack),
                      ),
                      const SizedBox(height: 34),
                      _GiftStepProgress(activeStep: activeStep),
                      const SizedBox(height: 24),
                      Text(
                        eyebrow,
                        style: GoogleFonts.jetBrainsMono(
                          color: _GiftJourneyTokens.htmlIri2,
                          fontSize: 10.5,
                          letterSpacing: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        style: GoogleFonts.dmSerifDisplay(
                          color: Colors.white,
                          fontSize: 44,
                          height: 1.04,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          color: _GiftJourneyTokens.muted,
                          fontSize: 15,
                          height: 1.55,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 34),
                      ...children,
                    ],
                  ),
                ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
                    child: footer,
                  ),
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
  final String? displayValue;

  const _GiftGlassDropdown({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.options,
    required this.onChanged,
    this.displayValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 12, 14),
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
              value: displayValue ?? value,
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
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
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
          const SizedBox(height: 16),
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
