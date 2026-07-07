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
  final _addressSearch = PlaceApiProvider(
    'sender-mobile-gifts-delivery-address',
  );
  Timer? _addressDebounce;
  List<Suggestion> _addressSuggestions = const [];
  Suggestion? _selectedAddressSuggestion;
  bool _isAddressSearching = false;
  String _addressError = '';
  DateTime? _deliveryDate;
  String? _deliveryTimeWindow;
  bool _flexibleDelivery = false;

  bool get _canContinue =>
      _selectedAddressSuggestion != null &&
      (_flexibleDelivery ||
          (_deliveryDate != null && _deliveryTimeWindow != null));

  @override
  void initState() {
    super.initState();
    _deliveryAddressController.text = widget.draft.deliveryAddress ?? '';
    _selectedAddressSuggestion = widget.draft.deliveryAddressData;
    _deliveryDate = DateTime.tryParse(widget.draft.deliveryDate ?? '');
    _deliveryTimeWindow = widget.draft.deliveryTimeWindow;
    _flexibleDelivery = widget.draft.deliveryDate == 'Flexible' ||
        widget.draft.deliveryTimeWindow == 'Flexible';
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    _deliveryAddressController.dispose();
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

  Future<void> _pickDeliveryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Preferred delivery date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _deliveryDate = picked;
      _flexibleDelivery = false;
    });
  }

  Future<void> _pickDeliveryWindow() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF12101B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final window in senderGiftDeliveryTimeWindows)
                  ListTile(
                    title: Text(
                      window,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(window),
                  ),
                ListTile(
                  title: const Text(
                    'Pick an exact time',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop('custom_time'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    if (selected == 'custom_time') {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        helpText: 'Preferred delivery time',
      );
      if (time == null || !mounted) return;
      setState(() {
        _deliveryTimeWindow = time.format(context);
        _flexibleDelivery = false;
      });
      return;
    }
    setState(() {
      _deliveryTimeWindow = selected;
      _flexibleDelivery = false;
    });
  }

  void _setFlexibleDelivery(bool value) {
    setState(() {
      _flexibleDelivery = value;
      if (value) {
        _deliveryDate = null;
        _deliveryTimeWindow = null;
      }
    });
  }

  String get _deliveryDateLabel {
    final date = _deliveryDate;
    if (date == null) return 'Choose a date';
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
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
        _GiftPickerCard(
          label: 'PREFERRED DELIVERY DATE',
          value: _flexibleDelivery ? 'Flexible' : _deliveryDateLabel,
          icon: Icons.calendar_month_rounded,
          onTap: _flexibleDelivery ? null : _pickDeliveryDate,
        ),
        const SizedBox(height: 12),
        _GiftPickerCard(
          label: 'PREFERRED DELIVERY TIME / WINDOW',
          value: _flexibleDelivery
              ? 'Flexible'
              : (_deliveryTimeWindow ?? 'Choose a time or window'),
          icon: Icons.schedule_rounded,
          onTap: _flexibleDelivery ? null : _pickDeliveryWindow,
        ),
        const SizedBox(height: 12),
        _GiftFlexibleDeliveryCard(
          value: _flexibleDelivery,
          onChanged: _setFlexibleDelivery,
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
                        deliveryDate:
                            _flexibleDelivery ? 'Flexible' : _deliveryDateLabel,
                        deliveryTimeWindow: _flexibleDelivery
                            ? 'Flexible'
                            : _deliveryTimeWindow,
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
              ? 'Select a verified delivery address to continue.'
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

class _GiftPickerCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _GiftPickerCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .052),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFC9B8FF), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFFC9B8FF),
                      fontSize: 10.5,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: onTap == null
                  ? Colors.white.withValues(alpha: .18)
                  : const Color(0xFFC9B8FF),
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftFlexibleDeliveryCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _GiftFlexibleDeliveryCard({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFFC9B8FF),
          title: const Text(
            "I'm flexible. The Gifts Team can optimise delivery.",
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
