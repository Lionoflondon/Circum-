import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'gift_iris_view.dart';
import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';

class GiftThemesView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftThemesView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/themes';

  @override
  State<GiftThemesView> createState() => _GiftThemesViewState();
}

class _GiftThemesViewState extends State<GiftThemesView> {
  late final TextEditingController _customController;
  late final Set<String> _interests;
  String? _selectedInterest;

  bool get _canContinue =>
      _interests.isNotEmpty || _customController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController(
      text: widget.draft.customInterest ?? '',
    );
    _interests = {...widget.draft.interests};
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 06 — THEMES',
      title: 'What do they love?',
      subtitle:
          'Choose from the web-backed interest list, or add something personal.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        GiftJourneyWidgets.dropdown(
          label: 'ADD A THEME',
          value: _selectedInterest,
          placeholder: 'Choose from the list...',
          options: senderGiftInterestOptions
              .where((interest) => !_interests.contains(interest))
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedInterest = null;
              _interests.add(value);
            });
          },
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _customController,
          label: 'CUSTOM THEME',
          placeholder: 'Or type a custom theme...',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_interests.isEmpty)
              const _GiftMutedText('Nothing added yet')
            else
              for (final interest in _interests)
                GiftJourneyWidgets.choiceChip(
                  label: '$interest ×',
                  selected: true,
                  onTap: () => setState(() => _interests.remove(interest)),
                ),
          ],
        ),
        const SizedBox(height: 16),
        _IrisThemePanel(
          themes: [
            ..._interests,
            if (_customController.text.trim().isNotEmpty)
              _customController.text.trim(),
          ],
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: _canContinue,
        label: 'Continue',
        onTap: !_canContinue
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GiftIrisView(
                      draft: widget.draft.copyWith(
                        interests: _interests.toList(),
                        customInterest: _customController.text.trim(),
                      ),
                    ),
                    settings: const RouteSettings(name: GiftIrisView.routeName),
                  ),
                ),
      ),
    );
  }
}

class _IrisThemePanel extends StatelessWidget {
  final List<String> themes;

  const _IrisThemePanel({required this.themes});

  @override
  Widget build(BuildContext context) {
    final signals = senderGiftIrisSignalsForThemes(themes);
    final unsupported = senderGiftUnsupportedIrisThemes(themes);
    final hasThemes = themes.any((theme) => theme.trim().isNotEmpty);
    final title = !hasThemes || signals.isEmpty
        ? 'No IRIS coverage yet'
        : 'IRIS signal preview';
    final body = !hasThemes
        ? 'Add a theme to see whether IRIS has existing gift-signal coverage.'
        : signals.isEmpty
            ? senderGiftIrisUnsupportedCopy
            : 'Supported signals: ${signals.join(' · ')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFC9B8FF).withValues(alpha: .24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.inter(
              color: const Color(0xFFB8AAB8),
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (signals.isNotEmpty && unsupported.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              senderGiftIrisPartialUnsupportedCopy,
              style: GoogleFonts.inter(
                color: const Color(0xFFC9B8FF),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GiftMutedText extends StatelessWidget {
  final String text;

  const _GiftMutedText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFB8AAB8),
        fontSize: 12,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
