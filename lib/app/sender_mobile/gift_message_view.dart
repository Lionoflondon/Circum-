import 'package:flutter/material.dart';

import 'gift_relationship_view.dart';

const senderGiftPersonalMessageFieldName = 'personalMessage';

class GiftMessageView extends StatefulWidget {
  const GiftMessageView({super.key});

  static const routeName = '/sender-mobile/gifts/message';

  @override
  State<GiftMessageView> createState() => _GiftMessageViewState();
}

class _GiftMessageViewState extends State<GiftMessageView> {
  final _messageController = TextEditingController();

  bool get _canContinue => _messageController.text.trim().isNotEmpty;

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
          'This message can be reviewed later and placed into the Gift Story.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        GiftJourneyWidgets.inputCard(
          controller: _messageController,
          label: 'PERSONAL MESSAGE',
          placeholder: 'What do you want them to know?',
          maxLines: 5,
          onChanged: (_) => setState(() {}),
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: _canContinue,
        label: 'Continue',
        onTap: !_canContinue
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GiftJourneyPlaceholderView(
                      message: 'Next Gifts step coming soon',
                    ),
                    settings: const RouteSettings(
                      name: '/sender-mobile/gifts/next',
                    ),
                  ),
                ),
      ),
    );
  }
}
