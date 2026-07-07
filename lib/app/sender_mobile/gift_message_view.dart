import 'package:flutter/material.dart';

import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';
import 'gift_voice_note_view.dart';

const senderGiftPersonalMessageFieldName = 'personalMessage';
const senderGiftPersonalMessageOptions = [
  'You mean more to me than I say often enough.',
  'I wanted this to feel thoughtful, personal and completely yours.',
  'Thank you for being someone I can always count on.',
  'I hope this brings a little joy to your day.',
  'This is a small way of celebrating everything you are.',
];

class GiftMessageView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftMessageView({
    super.key,
    required this.draft,
  });

  static const routeName = '/sender-mobile/gifts/message';

  @override
  State<GiftMessageView> createState() => _GiftMessageViewState();
}

class _GiftMessageViewState extends State<GiftMessageView> {
  final _messageController = TextEditingController();
  String? _selectedMessage;

  bool get _usesFreeEntry => widget.draft.mode == SenderGiftMode.someone;
  bool get _canContinue => _usesFreeEntry
      ? _messageController.text.trim().isNotEmpty
      : _selectedMessage != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.draft.personalMessage?.trim();
    _messageController.text = existing ?? '';
    if (existing != null &&
        senderGiftPersonalMessageOptions.contains(existing)) {
      _selectedMessage = existing;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 04 — YOUR MESSAGE',
      title: 'Write something from the heart',
      subtitle:
          'Choose the message direction. You can refine the exact wording with the Gifts Team later.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        if (_usesFreeEntry)
          GiftJourneyWidgets.inputCard(
            controller: _messageController,
            label: 'PERSONAL MESSAGE',
            placeholder: 'Write the message in your own words',
            helper: 'The Gifts Team will preserve the feeling of your note.',
            onChanged: (_) => setState(() {}),
            maxLines: 5,
          )
        else
          for (final message in senderGiftPersonalMessageOptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GiftMessageOptionCard(
                message: message,
                selected: _selectedMessage == message,
                onTap: () => setState(() => _selectedMessage = message),
              ),
            ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: _canContinue,
        label: 'Continue',
        onTap: !_canContinue
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GiftVoiceNoteView(
                      draft: widget.draft.copyWith(
                        personalMessage: _usesFreeEntry
                            ? _messageController.text.trim()
                            : _selectedMessage,
                      ),
                    ),
                    settings: const RouteSettings(
                      name: GiftVoiceNoteView.routeName,
                    ),
                  ),
                ),
      ),
    );
  }
}

class _GiftMessageOptionCard extends StatelessWidget {
  final String message;
  final bool selected;
  final VoidCallback onTap;

  const _GiftMessageOptionCard({
    required this.message,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFC9B8FF).withValues(alpha: .13)
              : Colors.white.withValues(alpha: .052),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFFC9B8FF).withValues(alpha: .55)
                : Colors.white.withValues(alpha: .09),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color:
                  selected ? const Color(0xFFC9B8FF) : const Color(0xFFB8AAB8),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
