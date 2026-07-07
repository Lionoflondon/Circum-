import 'package:flutter/material.dart';

import 'gift_message_view.dart';
import 'gift_relationship_view.dart';

const senderGiftDeliveryAddressFieldName = 'deliveryAddress';
const senderGiftDeliveryDateFieldName = 'deliveryDate';
const senderGiftDeliveryTimeWindowFieldName = 'deliveryTimeWindow';
const senderGiftDeliveryTimeWindows = ['Morning', 'Afternoon', 'Evening'];

class GiftDeliveryView extends StatefulWidget {
  const GiftDeliveryView({super.key});

  static const routeName = '/sender-mobile/gifts/delivery';

  @override
  State<GiftDeliveryView> createState() => _GiftDeliveryViewState();
}

class _GiftDeliveryViewState extends State<GiftDeliveryView> {
  final _deliveryAddressController = TextEditingController();
  final _deliveryDateController = TextEditingController();
  String? _deliveryTimeWindow;

  bool get _canContinue =>
      _deliveryAddressController.text.trim().isNotEmpty &&
      _deliveryDateController.text.trim().isNotEmpty &&
      _deliveryTimeWindow != null;

  @override
  void dispose() {
    _deliveryAddressController.dispose();
    _deliveryDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 3,
      eyebrow: 'STEP 03 — DELIVERY',
      title: 'Where and when?',
      subtitle:
          'Choose where this gift should arrive and the preferred window.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        GiftJourneyWidgets.inputCard(
          controller: _deliveryAddressController,
          label: 'DELIVERY ADDRESS',
          placeholder: 'Where should it arrive?',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        GiftJourneyWidgets.inputCard(
          controller: _deliveryDateController,
          label: 'PREFERRED DATE',
          placeholder: 'Choose a date',
          keyboardType: TextInputType.datetime,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final window in senderGiftDeliveryTimeWindows)
              GiftJourneyWidgets.choiceChip(
                label: window,
                selected: _deliveryTimeWindow == window,
                onTap: () => setState(() => _deliveryTimeWindow = window),
              ),
          ],
        ),
        const SizedBox(height: 28),
        GiftJourneyWidgets.primaryButton(
          enabled: _canContinue,
          label: 'Continue',
          onTap: !_canContinue
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const GiftMessageView(),
                      settings: const RouteSettings(
                        name: GiftMessageView.routeName,
                      ),
                    ),
                  ),
        ),
      ],
    );
  }
}
