import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';
import 'gift_style_view.dart';

class GiftIrisView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftIrisView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/iris';

  @override
  State<GiftIrisView> createState() => _GiftIrisViewState();
}

class _GiftIrisViewState extends State<GiftIrisView> {
  SenderGiftIrisBrief? _brief;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _brief = widget.draft.irisGiftBrief;
    _loading = _brief == null;
    if (_loading) {
      Timer(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() {
          _brief = widget.draft.generateIrisBrief();
          _loading = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themes = widget.draft.normalizedGiftThemes;
    final customThemes = themes
        .where((theme) => theme.source == 'custom' || !theme.knownToIris)
        .map((theme) => theme.label)
        .toList();

    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 07 — IRIS',
      title: 'How IRIS understands this moment',
      subtitle: 'IRIS is reading the moment, not building a basket.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        const _GiftIrisPulse(),
        const SizedBox(height: 18),
        if (_loading)
          const _IrisNote('Understanding the intention behind this gift...')
        else ...[
          if (customThemes.isNotEmpty)
            const _IrisNote(
              "We've saved the personal interests as context for planning.",
            ),
          const SizedBox(height: 12),
          _IrisInsightCard(
            title: "The feeling we're creating",
            body: _brief!.emotionalDirection,
          ),
          const SizedBox(height: 12),
          _IrisInsightCard(
            title: "How we'll bring it to life",
            body: _brief!.experienceDirection,
          ),
          const SizedBox(height: 12),
          _IrisInsightCard(
            title: "We'll avoid",
            body: _brief!.thingsToAvoid,
          ),
          const SizedBox(height: 12),
          _IrisInsightCard(
            title: 'Our confidence',
            body: _brief!.catalogueCoverage.isEmpty
                ? 'A real member of the Gifts Team will guide this carefully.'
                : "We're confident we've understood what matters.",
          ),
          const SizedBox(height: 12),
          const _IrisInsightCard(
            title: 'Reviewed by the Gifts Team',
            body:
                'Every experience is reviewed by a real person before sourcing begins.',
          ),
        ],
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: !_loading && _brief != null,
        label: 'Continue',
        onTap: _loading || _brief == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GiftStyleView(
                      draft: widget.draft.copyWith(irisGiftBrief: _brief),
                    ),
                    settings:
                        const RouteSettings(name: GiftStyleView.routeName),
                  ),
                ),
      ),
    );
  }
}

class _GiftIrisPulse extends StatefulWidget {
  const _GiftIrisPulse();

  @override
  State<_GiftIrisPulse> createState() => _GiftIrisPulseState();
}

class _GiftIrisPulseState extends State<_GiftIrisPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final pulse = .85 + (_controller.value * .15);
          return Transform.scale(scale: pulse, child: child);
        },
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFFA8EDEA).withValues(alpha: .72),
                const Color(0xFFC9B8FF).withValues(alpha: .22),
                Colors.transparent,
              ],
            ),
          ),
          child: Center(
            child: Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFA8EDEA),
                    Color(0xFFC9B8FF),
                    Color(0xFFFFD6E8),
                  ],
                ),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF07090F),
                size: 25,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IrisNote extends StatelessWidget {
  final String text;

  const _IrisNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFC9B8FF).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFC9B8FF).withValues(alpha: .28),
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 12,
          height: 1.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _IrisInsightCard extends StatelessWidget {
  final String title;
  final String body;

  const _IrisInsightCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFFC9B8FF),
              fontSize: 10,
              letterSpacing: .8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
