import 'package:flutter/material.dart';

import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';
import 'gift_voice_note_view.dart';

const senderGiftPersonalMessageFieldName = 'personalMessage';

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

  bool get _canContinue => _messageController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final existing = widget.draft.personalMessage?.trim();
    _messageController.text = existing ?? '';
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
      subtitle: 'Write the words you want the Gifts Team to understand.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        GiftJourneyWidgets.inputCard(
          controller: _messageController,
          label: 'PERSONAL MESSAGE',
          placeholder: 'Write the message in your own words',
          helper: 'The Gifts Team will preserve the feeling of your note.',
          onChanged: (_) => setState(() {}),
          maxLines: 5,
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
                        personalMessage: _messageController.text.trim(),
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
