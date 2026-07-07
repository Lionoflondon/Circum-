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
  late final List<SenderGiftTheme> _themes;
  String? _selectedInterest;

  bool get _canContinue => _themes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController(
      text: '',
    );
    _themes = [...widget.draft.normalizedGiftThemes];
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
              .where((interest) => !_hasTheme(interest))
              .toList(),
          onChanged: (value) {
            _selectedInterest = null;
            _addTheme(SenderGiftTheme.catalogue(value));
          },
        ),
        const SizedBox(height: 12),
        _CustomThemeInput(
          controller: _customController,
          onChanged: _handleCustomChanged,
          onAdd: _addCustomTheme,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_themes.isEmpty)
              const _GiftMutedText('Nothing added yet')
            else
              for (final theme in _themes)
                GiftJourneyWidgets.choiceChip(
                  label: '${theme.label} ×',
                  selected: true,
                  onTap: () => setState(() => _themes.remove(theme)),
                ),
          ],
        ),
        const SizedBox(height: 16),
        _IrisThemePanel(themes: _themes),
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
                        interests: _themes
                            .where((theme) => theme.source == 'catalogue')
                            .map((theme) => theme.label)
                            .toList(),
                        customInterest: _themes
                            .where((theme) => theme.source == 'custom')
                            .map((theme) => theme.label)
                            .join(', '),
                        giftThemes: _themes,
                      ),
                    ),
                    settings: const RouteSettings(name: GiftIrisView.routeName),
                  ),
                ),
      ),
    );
  }

  void _handleCustomChanged(String value) {
    if (value.contains(',')) {
      final parts = value.split(',');
      for (final part in parts.take(parts.length - 1)) {
        _addTheme(SenderGiftTheme.custom(part), refresh: false);
      }
      _customController.text = parts.last.trimLeft();
      _customController.selection = TextSelection.collapsed(
        offset: _customController.text.length,
      );
    }
    setState(() {});
  }

  void _addCustomTheme() {
    _addTheme(SenderGiftTheme.custom(_customController.text));
    _customController.clear();
  }

  void _addTheme(SenderGiftTheme theme, {bool refresh = true}) {
    final label = theme.label.trim();
    if (label.isEmpty || _hasTheme(label)) return;
    _themes.add(theme);
    if (refresh) setState(() {});
  }

  bool _hasTheme(String label) {
    return _themes.any(
      (theme) => theme.label.toLowerCase() == label.trim().toLowerCase(),
    );
  }
}

class _IrisThemePanel extends StatelessWidget {
  final List<SenderGiftTheme> themes;

  const _IrisThemePanel({required this.themes});

  @override
  Widget build(BuildContext context) {
    final signals = senderGiftIrisSignalsForThemes(
      themes.map((theme) => theme.label),
    );
    final customThemes = themes
        .where((theme) => theme.source == 'custom' || !theme.knownToIris)
        .map((theme) => theme.label)
        .toList();
    final hasThemes = themes.isNotEmpty;
    final title = !hasThemes || signals.isEmpty
        ? 'No IRIS coverage yet'
        : 'IRIS signal preview';
    final body = !hasThemes
        ? 'Add a theme to see whether IRIS has existing gift-signal coverage.'
        : customThemes.isNotEmpty && signals.isEmpty
            ? 'Custom interest saved. IRIS will use it as personal context.'
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
          if (signals.isNotEmpty && customThemes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Custom interest saved. IRIS will use it as personal context.',
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

class _CustomThemeInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;

  const _CustomThemeInput({
    required this.controller,
    required this.onChanged,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CUSTOM THEME',
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFFC9B8FF),
              fontSize: 10.5,
              letterSpacing: .8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  onChanged: onChanged,
                  onSubmitted: (_) => onAdd(),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Or type a custom theme...',
                    hintStyle: GoogleFonts.inter(
                      color: const Color(0xFFB8AAB8).withValues(alpha: .66),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onAdd,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC9B8FF).withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFC9B8FF).withValues(alpha: .28),
                    ),
                  ),
                  child: Text(
                    'Add',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
