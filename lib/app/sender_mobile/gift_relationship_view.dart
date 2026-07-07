import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const senderGiftRelationshipOptions = [
  'Partner',
  'Parent',
  'Sibling',
  'Friend',
  'Child',
  'Colleague',
  'Client',
  'Other',
];

class GiftRelationshipView extends StatefulWidget {
  const GiftRelationshipView({super.key});

  static const routeName = '/sender-mobile/gifts/relationship';

  @override
  State<GiftRelationshipView> createState() => _GiftRelationshipViewState();
}

class _GiftRelationshipViewState extends State<GiftRelationshipView> {
  String? _selectedRelationship;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _GiftRelationshipTokens.bg,
      body: Stack(
        children: [
          const _GiftRelationshipAmbient(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _GiftRelationshipBackButton(
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(height: 34),
                Text(
                  'Who are we gifting?',
                  style: GoogleFonts.dmSerifDisplay(
                    color: Colors.white,
                    fontSize: 38,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tell IRIS who this is for so we can shape the experience.',
                  style: GoogleFonts.inter(
                    color: _GiftRelationshipTokens.muted,
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 26),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final option in senderGiftRelationshipOptions)
                      _GiftRelationshipOption(
                        label: option,
                        selected: _selectedRelationship == option,
                        onTap: () =>
                            setState(() => _selectedRelationship = option),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                _GiftRelationshipContinueButton(
                  enabled: _selectedRelationship != null,
                  onTap: _selectedRelationship == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const _GiftOccasionPlaceholder(),
                              settings: const RouteSettings(
                                name: '/sender-mobile/gifts/occasion',
                              ),
                            ),
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftRelationshipOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GiftRelationshipOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: (MediaQuery.sizeOf(context).width - 54) / 2,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: selected
                ? _GiftRelationshipTokens.rose.withValues(alpha: .14)
                : Colors.white.withValues(alpha: .052),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? _GiftRelationshipTokens.champagne.withValues(alpha: .62)
                  : _GiftRelationshipTokens.pearlBorder,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: _GiftRelationshipTokens.rose.withValues(alpha: .14),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? _GiftRelationshipTokens.champagne
                        : _GiftRelationshipTokens.muted.withValues(alpha: .52),
                    width: 1.4,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: _GiftRelationshipTokens.champagne,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GiftRelationshipContinueButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _GiftRelationshipContinueButton({
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Continue',
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
                  _GiftRelationshipTokens.iri1,
                  _GiftRelationshipTokens.iri2,
                  _GiftRelationshipTokens.iri3,
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              'Continue',
              style: GoogleFonts.inter(
                color: _GiftRelationshipTokens.ink,
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

class _GiftRelationshipBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _GiftRelationshipBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back to Gifts',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .055),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _GiftRelationshipTokens.pearlBorder),
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

class _GiftOccasionPlaceholder extends StatelessWidget {
  const _GiftOccasionPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _GiftRelationshipTokens.bg,
      body: Stack(
        children: [
          const _GiftRelationshipAmbient(),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'Occasion screen coming next',
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

class _GiftRelationshipAmbient extends StatelessWidget {
  const _GiftRelationshipAmbient();

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

class _GiftRelationshipTokens {
  static const bg = Color(0xFF07090F);
  static const muted = Color(0xFFB8AAB8);
  static const champagne = Color(0xFFE7C88F);
  static const rose = Color(0xFFE8B4A0);
  static const pearlBorder = Color(0x24F5F0E8);
  static const iri1 = Color(0xFFA8EDEA);
  static const iri2 = Color(0xFFC9B8FF);
  static const iri3 = Color(0xFFFFD6E8);
  static const ink = Color(0xFF1A1330);
}
