import 'dart:async';

import 'package:flutter/material.dart';

import '../send_package/models/suggestions.m.dart';
import '../send_package/repo/place_api.dart';
import 'gift_journey_draft.dart';
import 'gift_message_view.dart';
import 'gift_relationship_view.dart';

const senderGiftDeliveryAddressFieldName = 'deliveryAddress';
const senderGiftDeliveryAddressDataFieldName = 'deliveryAddressData';
const senderGiftDeliveryPostcodeFieldName = 'deliveryPostcode';
const senderGiftDeliveryCityFieldName = 'deliveryCity';
const senderGiftDeliveryCountryFieldName = 'deliveryCountry';
const senderGiftDeliveryDateFieldName = 'deliveryDate';
const senderGiftDeliveryTimeWindowFieldName = 'deliveryTimeWindow';
const senderGiftDeliveryTimeWindows = ['Morning', 'Afternoon', 'Evening'];
const senderGiftAddressLookupCallableName = 'searchFreeUkAddresses';

class GiftDeliveryView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftDeliveryView({
    super.key,
    required this.draft,
  });

  static const routeName = '/sender-mobile/gifts/delivery';

  @override
  State<GiftDeliveryView> createState() => _GiftDeliveryViewState();
}

class _GiftDeliveryViewState extends State<GiftDeliveryView> {
  final _deliveryAddressController = TextEditingController();
  final _deliveryDateController = TextEditingController();
  final _addressSearch = PlaceApiProvider(
    'sender-mobile-gifts-delivery-address',
  );
  Timer? _addressDebounce;
  List<Suggestion> _addressSuggestions = const [];
  Suggestion? _selectedAddressSuggestion;
  bool _isAddressSearching = false;
  String _addressError = '';
  String? _deliveryTimeWindow;

  bool get _canContinue =>
      _deliveryAddressController.text.trim().isNotEmpty &&
      _deliveryDateController.text.trim().isNotEmpty &&
      _deliveryTimeWindow != null;

  @override
  void initState() {
    super.initState();
    _deliveryAddressController.text = widget.draft.deliveryAddress ?? '';
    _deliveryDateController.text = widget.draft.deliveryDate ?? '';
    _selectedAddressSuggestion = widget.draft.deliveryAddressData;
    _deliveryTimeWindow = widget.draft.deliveryTimeWindow;
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    _deliveryAddressController.dispose();
    _deliveryDateController.dispose();
    super.dispose();
  }

  void _onAddressChanged(String value) {
    setState(() {
      _selectedAddressSuggestion = null;
      _addressError = '';
    });
    _addressDebounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _addressSuggestions = const [];
        _isAddressSearching = false;
      });
      return;
    }
    setState(() => _isAddressSearching = true);
    _addressDebounce = Timer(const Duration(milliseconds: 360), () async {
      try {
        final suggestions = await _addressSearch.fetchSuggestions(query, 'en');
        if (!mounted) return;
        setState(() {
          _addressSuggestions = suggestions.take(5).toList(growable: false);
          _isAddressSearching = false;
          _addressError = suggestions.isEmpty
              ? "Couldn't find matching addresses. Please continue typing or try again."
              : '';
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _addressSuggestions = const [];
          _isAddressSearching = false;
          _addressError =
              "Couldn't find matching addresses. Please continue typing or try again.";
        });
      }
    });
  }

  void _selectAddressSuggestion(Suggestion suggestion) {
    _addressDebounce?.cancel();
    _deliveryAddressController.text = suggestion.description;
    _deliveryAddressController.selection = TextSelection.collapsed(
      offset: suggestion.description.length,
    );
    setState(() {
      _selectedAddressSuggestion = suggestion;
      _addressSuggestions = const [];
      _isAddressSearching = false;
      _addressError = '';
    });
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
        _GiftAddressLookupCard(
          controller: _deliveryAddressController,
          label: 'DELIVERY ADDRESS',
          placeholder: 'Where should it arrive?',
          suggestions: _addressSuggestions,
          isSearching: _isAddressSearching,
          errorText: _addressError,
          selectedSuggestion: _selectedAddressSuggestion,
          onChanged: _onAddressChanged,
          onSuggestionSelected: _selectAddressSuggestion,
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
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: _canContinue,
        label: 'Continue',
        onTap: !_canContinue
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GiftMessageView(
                      draft: widget.draft.copyWith(
                        deliveryAddress: _deliveryAddressController.text.trim(),
                        deliveryAddressData: _selectedAddressSuggestion,
                        deliveryDate: _deliveryDateController.text.trim(),
                        deliveryTimeWindow: _deliveryTimeWindow,
                      ),
                    ),
                    settings: const RouteSettings(
                      name: GiftMessageView.routeName,
                    ),
                  ),
                ),
      ),
    );
  }
}

class _GiftAddressLookupCard extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String placeholder;
  final List<Suggestion> suggestions;
  final bool isSearching;
  final String errorText;
  final Suggestion? selectedSuggestion;
  final ValueChanged<String> onChanged;
  final ValueChanged<Suggestion> onSuggestionSelected;

  const _GiftAddressLookupCard({
    required this.controller,
    required this.label,
    required this.placeholder,
    required this.suggestions,
    required this.isSearching,
    required this.errorText,
    required this.selectedSuggestion,
    required this.onChanged,
    required this.onSuggestionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GiftJourneyWidgets.inputCard(
          controller: controller,
          label: label,
          helper: selectedSuggestion == null
              ? 'Start typing to search verified delivery addresses.'
              : 'Verified delivery address selected.',
          placeholder: placeholder,
          onChanged: onChanged,
        ),
        if (isSearching) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            minHeight: 2,
            color: Color(0xFFC9B8FF),
            backgroundColor: Colors.transparent,
          ),
        ],
        if (errorText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            errorText,
            style: const TextStyle(
              color: Color(0xFFB8AAB8),
              fontSize: 11.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final suggestion in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSuggestionSelected(suggestion),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .045),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .09),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        color: Color(0xFFC9B8FF),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              suggestion.mainText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              suggestion.subText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB8AAB8),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
