import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_relationship_view.dart';
import 'sender_gifts_icon.dart';

class GiftModeView extends StatelessWidget {
  const GiftModeView({super.key});

  static const routeName = '/sender-mobile/gifts';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _GiftTokens.bg,
      body: Stack(
        children: [
          const _GiftAmbient(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              children: [
                Row(
                  children: [
                    _GiftGlassButton(
                      icon: Icons.arrow_back_rounded,
                      label: 'Back to Sender',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    Text(
                      'Gifts',
                      style: GoogleFonts.dmSerifDisplay(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                Text(
                  'Choose your gift mode.',
                  style: GoogleFonts.dmSerifDisplay(
                    color: Colors.white,
                    fontSize: 38,
                    height: 1.05,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Start with the way you want this moment to feel.',
                  style: GoogleFonts.inter(
                    color: _GiftTokens.muted,
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 26),
                _GiftModeCard(
                  iconKind: SenderGiftsIconKind.gift,
                  title: 'Gift someone',
                  subtitle: 'Create something thoughtful for another person.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const GiftRelationshipView(),
                      settings: const RouteSettings(
                        name: GiftRelationshipView.routeName,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const _GiftModeCard(
                  iconKind: SenderGiftsIconKind.self,
                  title: 'Gift myself',
                  subtitle: 'Choose a considered treat for yourself.',
                ),
                const SizedBox(height: 12),
                const _GiftModeCard(
                  iconKind: SenderGiftsIconKind.mask,
                  title: 'Anonymous gift',
                  subtitle: 'Keep the sender hidden until the right moment.',
                ),
                const SizedBox(height: 12),
                const _GiftModeCard(
                  iconKind: SenderGiftsIconKind.people,
                  title: 'Campaign',
                  subtitle: 'Begin a group or brand gifting moment.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GiftModeCard extends StatefulWidget {
  final SenderGiftsIconKind iconKind;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _GiftModeCard({
    required this.iconKind,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  State<_GiftModeCard> createState() => _GiftModeCardState();
}

class _GiftModeCardState extends State<_GiftModeCard> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.title,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          scale: _pressed ? 1.015 : 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .052),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _GiftTokens.pearlBorder),
                  boxShadow: [
                    BoxShadow(
                      color: _GiftTokens.rose.withValues(alpha: .10),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    SenderGiftsIcon(size: 52, kind: widget.iconKind),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle,
                            style: GoogleFonts.inter(
                              color: _GiftTokens.muted,
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: _GiftTokens.champagne,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GiftGlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GiftGlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .055),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _GiftTokens.pearlBorder),
          ),
          child: Icon(icon, color: Colors.white, size: 21),
        ),
      ),
    );
  }
}

class _GiftAmbient extends StatelessWidget {
  const _GiftAmbient();

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

class _GiftTokens {
  static const bg = Color(0xFF07090F);
  static const muted = Color(0xFFB8AAB8);
  static const champagne = Color(0xFFE7C88F);
  static const rose = Color(0xFFE8B4A0);
  static const pearlBorder = Color(0x24F5F0E8);
}
