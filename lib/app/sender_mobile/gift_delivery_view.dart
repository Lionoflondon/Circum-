import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/address_engine.dart';
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
const senderGiftAddressLookupCallableName = 'searchFreeUkAddresses';
const senderGiftAddressResolveCallableName = 'resolveUkAddressPlace';

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
      AddressEngine.hasRequiredFields(
        suggestion: _selectedAddressSuggestion,
        manualAddress: _deliveryAddressController.text,
      ) &&
      !_isAddressSearching &&
      _deliveryDate != null &&
      (_flexibleDelivery || _deliveryTimeWindow != null);

  @override
  void initState() {
    super.initState();
    _deliveryAddressController.text = widget.draft.deliveryAddress ?? '';
    _selectedAddressSuggestion = widget.draft.deliveryAddressData;
    _deliveryDate = DateTime.tryParse(widget.draft.deliveryDate ?? '');
    _deliveryTimeWindow = widget.draft.deliveryTimeWindow;
    _flexibleDelivery = widget.draft.flexibleDelivery ||
        widget.draft.deliveryDate == 'Flexible' ||
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
          _addressSuggestions = suggestions
              .map(AddressEngine.cleanSuggestion)
              .take(5)
              .toList(growable: false);
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

  Future<void> _selectAddressSuggestion(Suggestion suggestion) async {
    _addressDebounce?.cancel();
    final cleanSuggestion = AddressEngine.cleanSuggestion(suggestion);
    _deliveryAddressController.text = cleanSuggestion.description;
    _deliveryAddressController.selection = TextSelection.collapsed(
      offset: cleanSuggestion.description.length,
    );
    setState(() {
      _selectedAddressSuggestion = null;
      _addressSuggestions = const [];
      _isAddressSearching = true;
      _addressError = '';
    });
    try {
      final resolved = await _addressSearch.resolveSuggestion(
        cleanSuggestion.placeId,
        'en',
      );
      if (!mounted) return;
      setState(() {
        _selectedAddressSuggestion = resolved;
        _isAddressSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAddressSearching = false;
        _addressError =
            'That address could not be resolved. Choose another suggestion.';
      });
    }
  }

  Future<Suggestion?> _resolveDeliveryAddressForContinue() async {
    final selected = _selectedAddressSuggestion;
    if (selected != null && selected.lat != null && selected.lng != null) {
      return selected;
    }
    final address = _deliveryAddressController.text.trim();
    if (!AddressEngine.hasRequiredFields(manualAddress: address)) {
      setState(() {
        _addressError =
            'Add a full delivery address with house or flat, town and postcode.';
      });
      return null;
    }

    _addressDebounce?.cancel();
    setState(() {
      _isAddressSearching = true;
      _addressError = '';
      _addressSuggestions = const [];
    });

    try {
      final resolved = AddressEngine.cleanSuggestion(
        await _addressSearch.resolveTypedAddress(address, 'en'),
      );
      if (!mounted) return null;
      _deliveryAddressController.text = resolved.description;
      _deliveryAddressController.selection = TextSelection.collapsed(
        offset: resolved.description.length,
      );
      setState(() {
        _selectedAddressSuggestion = resolved;
        _isAddressSearching = false;
      });
      return resolved;
    } catch (_) {
      if (!mounted) return null;
      setState(() {
        _isAddressSearching = false;
        _addressError =
            'That address could not be verified. Check the house or flat number, street, town and postcode.';
      });
      return null;
    }
  }

  Future<void> _pickDeliveryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Preferred delivery date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _deliveryDate = picked;
    });
  }

  Future<void> _pickDeliveryTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Preferred delivery time',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _deliveryTimeWindow = picked.format(context);
      _flexibleDelivery = false;
    });
  }

  void _setFlexibleDelivery(bool value) {
    setState(() {
      _flexibleDelivery = value;
      if (value) {
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

  String get _deliverySummaryDateLabel {
    final date = _deliveryDate;
    if (date == null) return 'Choose a date';
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdays[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 3,
      eyebrow: 'STEP 03 — DELIVERY',
      title: 'Where and when?',
      subtitle:
          'Choose where this gift should arrive and when it should happen.',
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
          value: _deliveryDateLabel,
          icon: Icons.calendar_month_rounded,
          onTap: _pickDeliveryDate,
        ),
        const SizedBox(height: 12),
        _GiftPickerCard(
          label: 'PREFERRED DELIVERY TIME',
          value: _flexibleDelivery
              ? 'Flexible delivery selected'
              : (_deliveryTimeWindow ?? 'Choose a time'),
          icon: Icons.schedule_rounded,
          onTap: _flexibleDelivery ? null : _pickDeliveryTime,
        ),
        const SizedBox(height: 12),
        _GiftFlexibleDeliveryCard(
          value: _flexibleDelivery,
          onChanged: _setFlexibleDelivery,
        ),
        const SizedBox(height: 12),
        _GiftDeliverySummaryCard(
          flexibleDelivery: _flexibleDelivery,
          dateLabel: _deliverySummaryDateLabel,
          timeLabel: _deliveryTimeWindow,
        ),
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: _canContinue,
        label: 'Continue',
        onTap: !_canContinue
            ? null
            : () async {
                final navigator = Navigator.of(context);
                final resolvedAddress =
                    await _resolveDeliveryAddressForContinue();
                if (!mounted || resolvedAddress == null) return;
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => GiftMessageView(
                      draft: widget.draft.copyWith(
                        deliveryAddress: resolvedAddress.description,
                        deliveryAddressData: resolvedAddress,
                        deliveryDate:
                            _deliveryDate == null ? null : _deliveryDateLabel,
                        deliveryTimeWindow:
                            _flexibleDelivery ? null : _deliveryTimeWindow,
                        flexibleDelivery: _flexibleDelivery,
                      ),
                    ),
                    settings: const RouteSettings(
                      name: GiftMessageView.routeName,
                    ),
                  ),
                );
              },
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
              ? 'Enter a full address or choose a suggestion. We will verify it before continuing.'
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
            "I'm flexible. Let the Gifts Team choose the best delivery time.",
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

class _GiftDeliverySummaryCard extends StatelessWidget {
  final bool flexibleDelivery;
  final String dateLabel;
  final String? timeLabel;

  const _GiftDeliverySummaryCard({
    required this.flexibleDelivery,
    required this.dateLabel,
    required this.timeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasDate = dateLabel != 'Choose a date';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFC9B8FF).withValues(alpha: .07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFC9B8FF).withValues(alpha: .22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery',
            style: TextStyle(
              color: Color(0xFFC9B8FF),
              fontSize: 10.5,
              letterSpacing: .8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (flexibleDelivery) ...[
            const Text(
              'Flexible delivery selected',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasDate
                  ? '$dateLabel\nThe Gifts Team will optimise delivery.'
                  : 'The Gifts Team will optimise delivery.',
              style: const TextStyle(
                color: Color(0xFFE4DCF5),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            Text(
              hasDate ? dateLabel : 'Choose a delivery date',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              timeLabel ?? 'Choose a delivery time',
              style: const TextStyle(
                color: Color(0xFFE4DCF5),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
