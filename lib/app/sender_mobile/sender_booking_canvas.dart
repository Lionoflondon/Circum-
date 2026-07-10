import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../business/business_journey_context.dart';
import '../send_package/bloc/send_package_bloc.dart';
import 'sender_booking_state.dart';
import 'sender_finance.dart';
import 'sender_saved_addresses.dart';
import 'sender_tracking_screen.dart';

class SenderBookingCanvas extends StatefulWidget {
  const SenderBookingCanvas({super.key});

  @override
  State<SenderBookingCanvas> createState() => _SenderBookingCanvasState();
}

class _SenderBookingCanvasState extends State<SenderBookingCanvas> {
  SenderBookingDraft _draft = const SenderBookingDraft();
  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();
  final _receiverName = TextEditingController();
  final _receiverPhone = TextEditingController();
  final _notes = TextEditingController();
  final _scheduledDate = TextEditingController();
  final _customWindowStart = TextEditingController();
  final _customWindowEnd = TextEditingController();
  final _item = TextEditingController();
  final _description = TextEditingController();
  final _weight = TextEditingController(text: '0.5');
  var _searchingPickup = true;

  @override
  void initState() {
    super.initState();
    context.read<SendPackageBloc>().add(CheckForPushToken());
    context.read<SendPackageBloc>().add(CheckForActiveRequest());
  }

  @override
  void dispose() {
    _pickup.dispose();
    _dropoff.dispose();
    _receiverName.dispose();
    _receiverPhone.dispose();
    _notes.dispose();
    _scheduledDate.dispose();
    _customWindowStart.dispose();
    _customWindowEnd.dispose();
    _item.dispose();
    _description.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _setDraft(SenderBookingDraft next) => setState(() => _draft = next);

  void _advance() {
    if (_draft.step == SenderBookingStep.payment) return;
    if (_draft.step == SenderBookingStep.parcel) {
      context.read<SendPackageBloc>().add(
            RequestCanonicalIrisEstimate(
              itemName: _item.text,
              quantity: senderQuantityFromItemName(_item.text),
              description: _description.text,
              declaredWeightText: _weight.text,
              fragile: _draft.fragile,
              highValue: _draft.highValue,
            ),
          );
    }
    if (_draft.step == SenderBookingStep.iris ||
        _draft.step == SenderBookingStep.options ||
        _draft.step == SenderBookingStep.review) {
      _requestBackendQuote(_draft);
    }
    if (_draft.step == SenderBookingStep.review) {
      context.read<SendPackageBloc>().add(const LoadSenderRothBalance());
    }
    _setDraft(_draft.next());
  }

  void _requestBackendQuote(SenderBookingDraft draft) {
    final business = BusinessJourneyScope.maybeOf(context);
    context.read<SendPackageBloc>().add(
          RequestSenderBookingQuote(
            selectedSpeed: draft.selectedOption,
            vanguardProtocolEnabled: draft.vanguard,
            itemName: draft.itemName,
            description: draft.itemDescription,
            weightKg: double.tryParse(_weight.text) ?? .5,
            fragile: draft.fragile,
            highValue: draft.highValue,
            businessContext: business?.toMap(),
          ),
        );
  }

  void _back() {
    if (_draft.step == SenderBookingStep.pickup) {
      Navigator.of(context).maybePop();
      return;
    }
    _setDraft(_draft.back());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
      builder: (context, engine) {
        final operationalStep = _stepForEngine(engine);
        if (operationalStep != null && operationalStep != _draft.step) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _setDraft(_draft.copyWith(step: operationalStep));
          });
        }
        if (_draft.step == SenderBookingStep.findingRider ||
            _draft.step == SenderBookingStep.liveTracking) {
          return Scaffold(
            backgroundColor: _Tokens.bg,
            body: SenderMobileTrackingScreen(
              engine: engine,
              stateOverride: senderTrackingStateForEngine(engine),
            ),
          );
        }
        return Scaffold(
          backgroundColor: _Tokens.bg,
          body: Stack(
            children: [
              _SenderMobileMap(
                active: true,
                showDestination: engine.desinationCoordinate != null ||
                    _dropoff.text.trim().isNotEmpty,
                showVanguardShield: _draft.vanguard,
                distanceKm: engine.distance,
              ),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(progress: _draft.progress, onBack: _back),
                    const Spacer(),
                    _BookingPanel(
                      draft: _draft,
                      engine: engine,
                      pickup: _pickup,
                      dropoff: _dropoff,
                      receiverName: _receiverName,
                      receiverPhone: _receiverPhone,
                      notes: _notes,
                      scheduledDate: _scheduledDate,
                      customWindowStart: _customWindowStart,
                      customWindowEnd: _customWindowEnd,
                      item: _item,
                      description: _description,
                      weight: _weight,
                      searchingPickup: _searchingPickup,
                      onSearchingPickupChanged: (value) =>
                          setState(() => _searchingPickup = value),
                      onDraft: _setDraft,
                      onContinue: _advance,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  SenderBookingStep? _stepForEngine(SendPackageState engine) {
    switch (engine.deliveryStatus) {
      case DeliveryStatus.deliveryConfirmed:
      case DeliveryStatus.reconnectingWithRider:
        return SenderBookingStep.findingRider;
      case DeliveryStatus.deliveryOnGoing:
      case DeliveryStatus.deliveryCompleted:
        return SenderBookingStep.liveTracking;
      case DeliveryStatus.inital:
      case DeliveryStatus.addressesSelected:
        return null;
    }
  }
}

class _TopBar extends StatelessWidget {
  final double progress;
  final VoidCallback onBack;

  const _TopBar({required this.progress, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          _RoundButton(icon: Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: progress,
                backgroundColor: Colors.white.withValues(alpha: .08),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  _Tokens.lightBlue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const _TrustPill(),
        ],
      ),
    );
  }
}

class _BookingPanel extends StatelessWidget {
  final SenderBookingDraft draft;
  final SendPackageState engine;
  final TextEditingController pickup;
  final TextEditingController dropoff;
  final TextEditingController receiverName;
  final TextEditingController receiverPhone;
  final TextEditingController notes;
  final TextEditingController scheduledDate;
  final TextEditingController customWindowStart;
  final TextEditingController customWindowEnd;
  final TextEditingController item;
  final TextEditingController description;
  final TextEditingController weight;
  final bool searchingPickup;
  final ValueChanged<bool> onSearchingPickupChanged;
  final ValueChanged<SenderBookingDraft> onDraft;
  final VoidCallback onContinue;

  const _BookingPanel({
    required this.draft,
    required this.engine,
    required this.pickup,
    required this.dropoff,
    required this.receiverName,
    required this.receiverPhone,
    required this.notes,
    required this.scheduledDate,
    required this.customWindowStart,
    required this.customWindowEnd,
    required this.item,
    required this.description,
    required this.weight,
    required this.searchingPickup,
    required this.onSearchingPickupChanged,
    required this.onDraft,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final content = _content(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: _Glass(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Column(
            key: ValueKey(draft.step),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  height: 5,
                  width: 48,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text(
                senderStepTitle(draft.step),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              content,
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    switch (draft.step) {
      case SenderBookingStep.pickup:
        return _AddressPanel(
          savedForPickup: true,
          controller: pickup,
          hint: 'Pickup address, flat or postcode',
          helperText: 'Enter a postcode, business or address.',
          suggestions: engine.suggestions,
          isSearching: engine.isAddressSearching,
          errorText: engine.addressSearchError,
          onChanged: (value) {
            onSearchingPickupChanged(true);
            _search(context, value);
            onDraft(draft.copyWith(pickupAddress: value));
          },
          onSuggestion: (suggestion) {
            context.read<SendPackageBloc>().add(
                  SetPickupAddress(
                    val: suggestion.description,
                    pickupLocationSubAddress: suggestion.subText,
                    placeId: suggestion.placeId,
                    lang: Localizations.localeOf(context).languageCode,
                  ),
                );
            pickup.text = suggestion.description;
            onDraft(draft.copyWith(pickupAddress: suggestion.description));
          },
          primaryLabel: 'Confirm pickup',
          canContinue: draft.canContinue,
          onContinue: onContinue,
        );
      case SenderBookingStep.dropoff:
        return _AddressPanel(
          savedForPickup: false,
          controller: dropoff,
          hint: 'Drop-off address, flat or postcode',
          helperText: 'Enter a postcode, business or address.',
          suggestions: engine.suggestions,
          isSearching: engine.isAddressSearching,
          errorText: engine.addressSearchError,
          onChanged: (value) {
            onSearchingPickupChanged(false);
            _search(context, value);
            onDraft(draft.copyWith(dropoffAddress: value));
          },
          onSuggestion: (suggestion) {
            context.read<SendPackageBloc>().add(
                  SetDeliveryAddress(
                    val: suggestion.description,
                    destinationLocationSubAddress: suggestion.subText,
                    placeId: suggestion.placeId,
                    lang: Localizations.localeOf(context).languageCode,
                  ),
                );
            dropoff.text = suggestion.description;
            onDraft(draft.copyWith(dropoffAddress: suggestion.description));
          },
          primaryLabel: 'Confirm drop-off',
          canContinue: draft.canContinue,
          onContinue: onContinue,
        );
      case SenderBookingStep.recipient:
        return _RecipientPanel(
          name: receiverName,
          phone: receiverPhone,
          notes: notes,
          onChanged: () => onDraft(
            draft.copyWith(
              receiverName: receiverName.text,
              receiverPhone: receiverPhone.text,
              deliveryNotes: notes.text,
            ),
          ),
          canContinue: draft.canContinue,
          onContinue: onContinue,
        );
      case SenderBookingStep.deliveryTime:
        return _DeliveryTimePanel(
          draft: draft,
          scheduledDate: scheduledDate,
          customWindowStart: customWindowStart,
          customWindowEnd: customWindowEnd,
          onDraft: onDraft,
          canContinue: draft.canContinue,
          onContinue: onContinue,
        );
      case SenderBookingStep.parcel:
        return _ParcelPanel(
          item: item,
          description: description,
          weight: weight,
          fragile: draft.fragile,
          highValue: draft.highValue,
          onChanged: () {
            final parsed = double.tryParse(weight.text) ?? .5;
            onDraft(
              draft.copyWith(
                itemName: item.text,
                itemDescription: description.text,
                weightLabel: '${parsed.toStringAsFixed(1)}kg',
              ),
            );
          },
          onFragile: (value) => onDraft(draft.copyWith(fragile: value)),
          onHighValue: (value) => onDraft(draft.copyWith(highValue: value)),
          canContinue: draft.canContinue,
          onContinue: onContinue,
        );
      case SenderBookingStep.iris:
        return _IrisPanel(engine: engine, draft: draft, onContinue: onContinue);
      case SenderBookingStep.options:
        return _OptionsPanel(
          draft: draft,
          engine: engine,
          onDraft: onDraft,
          onContinue: onContinue,
        );
      case SenderBookingStep.review:
        return _ReviewPanel(
          draft: draft,
          engine: engine,
          onContinue: onContinue,
        );
      case SenderBookingStep.payment:
        return _PaymentPanel(engine: engine, draft: draft, onDraft: onDraft);
      case SenderBookingStep.findingRider:
      case SenderBookingStep.liveTracking:
        return const SizedBox.shrink();
    }
  }

  void _search(BuildContext context, String value) {
    if (value.trim().length < 3) {
      context.read<SendPackageBloc>().add(ClearSuggestions());
      return;
    }
    context.read<SendPackageBloc>().add(
          SearchAPlaceEvent(
            query: value,
            lang: Localizations.localeOf(context).languageCode,
          ),
        );
  }
}

class _AddressPanel extends StatelessWidget {
  final bool savedForPickup;
  final TextEditingController controller;
  final String hint;
  final String helperText;
  final List suggestions;
  final bool isSearching;
  final String errorText;
  final ValueChanged<String> onChanged;
  final ValueChanged<dynamic> onSuggestion;
  final String primaryLabel;
  final bool canContinue;
  final VoidCallback onContinue;

  const _AddressPanel({
    required this.savedForPickup,
    required this.controller,
    required this.hint,
    required this.helperText,
    required this.suggestions,
    required this.isSearching,
    required this.errorText,
    required this.onChanged,
    required this.onSuggestion,
    required this.primaryLabel,
    required this.canContinue,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            helperText,
            style: const TextStyle(color: _Tokens.muted, height: 1.35),
          ),
        ),
        const SizedBox(height: 10),
        SenderSavedAddressSuggestions(
          forPickup: savedForPickup,
          onSelected: (address) => onSuggestion(address.toSuggestion()),
        ),
        _TextInput(controller: controller, hint: hint, onChanged: onChanged),
        const SizedBox(height: 10),
        if (isSearching)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: _Tokens.lightBlue,
              backgroundColor: Colors.transparent,
            ),
          ),
        if (errorText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                errorText,
                style: const TextStyle(color: _Tokens.muted, height: 1.35),
              ),
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 164),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: math.min(suggestions.length, 4),
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return _SuggestionTile(
                title: '${suggestion.mainText}',
                subtitle: '${suggestion.subText}',
                onTap: () => onSuggestion(suggestion),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _PrimaryButton(
          label: primaryLabel,
          enabled: canContinue,
          onTap: onContinue,
        ),
      ],
    );
  }
}

class _RecipientPanel extends StatelessWidget {
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController notes;
  final VoidCallback onChanged;
  final bool canContinue;
  final VoidCallback onContinue;

  const _RecipientPanel({
    required this.name,
    required this.phone,
    required this.notes,
    required this.onChanged,
    required this.canContinue,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TextInput(
          controller: name,
          hint: 'Recipient name',
          errorText:
              name.text.trim().isEmpty ? 'Recipient name is required' : null,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        _TextInput(
          controller: phone,
          hint: 'Recipient phone',
          keyboardType: TextInputType.phone,
          helperText: 'Used only if the rider needs to contact the recipient.',
          errorText:
              phone.text.trim().isEmpty ? 'Recipient phone is required' : null,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        _TextInput(
          controller: notes,
          hint: 'Delivery instructions (optional)',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        _PrimaryButton(
          label: 'Confirm recipient',
          enabled: canContinue,
          onTap: onContinue,
        ),
      ],
    );
  }
}

class _DeliveryTimePanel extends StatelessWidget {
  final SenderBookingDraft draft;
  final TextEditingController scheduledDate;
  final TextEditingController customWindowStart;
  final TextEditingController customWindowEnd;
  final ValueChanged<SenderBookingDraft> onDraft;
  final bool canContinue;
  final VoidCallback onContinue;

  const _DeliveryTimePanel({
    required this.draft,
    required this.scheduledDate,
    required this.customWindowStart,
    required this.customWindowEnd,
    required this.onDraft,
    required this.canContinue,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final scheduled =
        draft.deliveryTimingType == SenderDeliveryTimingType.scheduled;
    final pastDate = scheduled &&
        scheduledDate.text.trim().isNotEmpty &&
        !isSenderScheduledDateValid(scheduledDate.text);
    final custom = scheduled && draft.scheduledWindow == 'Custom';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose when your rider should collect and deliver your parcel.',
          style: TextStyle(color: _Tokens.muted, height: 1.35),
        ),
        const SizedBox(height: 14),
        _RadioGlassTile(
          selected: !scheduled,
          title: 'Deliver now',
          caption: 'Start finding a rider as soon as payment is complete.',
          onTap: () => onDraft(
            draft.copyWith(
              deliveryTimingType: SenderDeliveryTimingType.now,
              scheduledDate: '',
              scheduledWindow: '',
              customWindowStart: '',
              customWindowEnd: '',
            ),
          ),
        ),
        const SizedBox(height: 10),
        _RadioGlassTile(
          selected: scheduled,
          title: 'Schedule for later',
          caption: 'Choose a date and time window.',
          onTap: () => onDraft(
            draft.copyWith(
              deliveryTimingType: SenderDeliveryTimingType.scheduled,
            ),
          ),
        ),
        if (scheduled) ...[
          const SizedBox(height: 14),
          const _SectionLabel('Preferred date'),
          const SizedBox(height: 8),
          _ScheduleDateSelector(
            selectedDate: draft.scheduledDate,
            onSelected: (value) {
              scheduledDate.text = value;
              onDraft(draft.copyWith(scheduledDate: value));
            },
          ),
          if (pastDate) ...[
            const SizedBox(height: 6),
            const Text(
              'Choose today or a future date',
              style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          const _SectionLabel('Preferred collection window'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Morning', 'Afternoon', 'Evening', 'Custom'].map((
              window,
            ) {
              return _ToggleChip(
                label: window,
                selected: draft.scheduledWindow == window,
                onTap: () => onDraft(draft.copyWith(scheduledWindow: window)),
              );
            }).toList(),
          ),
          if (custom) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TextInput(
                    controller: customWindowStart,
                    hint: 'Start HH:MM',
                    keyboardType: TextInputType.datetime,
                    errorText: customWindowStart.text.trim().isNotEmpty &&
                            !RegExp(
                              r'^\d{2}:\d{2}$',
                            ).hasMatch(customWindowStart.text.trim())
                        ? 'Use HH:MM'
                        : null,
                    onChanged: (value) =>
                        onDraft(draft.copyWith(customWindowStart: value)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TextInput(
                    controller: customWindowEnd,
                    hint: 'End HH:MM',
                    keyboardType: TextInputType.datetime,
                    errorText: customWindowEnd.text.trim().isNotEmpty &&
                            !isSenderCustomWindowValid(
                              customWindowStart.text,
                              customWindowEnd.text,
                            )
                        ? 'After start'
                        : null,
                    onChanged: (value) =>
                        onDraft(draft.copyWith(customWindowEnd: value)),
                  ),
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 14),
        const _InfoNote(
          text:
              "Scheduled deliveries depend on rider availability. We'll confirm before the delivery begins.",
        ),
        const SizedBox(height: 14),
        _PrimaryButton(
          label: 'Confirm delivery time',
          enabled: canContinue,
          onTap: onContinue,
        ),
      ],
    );
  }
}

class _ScheduleDateSelector extends StatelessWidget {
  final String selectedDate;
  final ValueChanged<String> onSelected;

  const _ScheduleDateSelector({
    required this.selectedDate,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final dates = senderScheduleDateOptions();
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = dates[index];
          final value = senderScheduleDateValue(date);
          final selected = selectedDate == value;
          return _ScheduleDateCard(
            day: senderScheduleDayLabel(date),
            date: senderScheduleMonthDayLabel(date),
            selected: selected,
            onTap: () => onSelected(value),
          );
        },
      ),
    );
  }
}

class _ScheduleDateCard extends StatelessWidget {
  final String day;
  final String date;
  final bool selected;
  final VoidCallback onTap;

  const _ScheduleDateCard({
    required this.day,
    required this.date,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 84,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? _Tokens.blue.withValues(alpha: .18)
              : Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _Tokens.lightBlue : _Tokens.border,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : _Tokens.muted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? _Tokens.lightBlue : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParcelPanel extends StatelessWidget {
  final TextEditingController item;
  final TextEditingController description;
  final TextEditingController weight;
  final bool fragile;
  final bool highValue;
  final VoidCallback onChanged;
  final ValueChanged<bool> onFragile;
  final ValueChanged<bool> onHighValue;
  final bool canContinue;
  final VoidCallback onContinue;

  const _ParcelPanel({
    required this.item,
    required this.description,
    required this.weight,
    required this.fragile,
    required this.highValue,
    required this.onChanged,
    required this.onFragile,
    required this.onHighValue,
    required this.canContinue,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TextInput(
          controller: item,
          hint: 'Item name',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        _TextInput(
          controller: description,
          hint: 'Optional description',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        _TextInput(
          controller: weight,
          hint: 'Weight kg',
          keyboardType: TextInputType.number,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ToggleChip(
                label: 'Fragile',
                selected: fragile,
                onTap: () => onFragile(!fragile),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ToggleChip(
                label: 'High value',
                selected: highValue,
                onTap: () => onHighValue(!highValue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PrimaryButton(
          label: 'Ask IRIS',
          enabled: canContinue,
          onTap: onContinue,
        ),
      ],
    );
  }
}

class _IrisPanel extends StatelessWidget {
  final SendPackageState engine;
  final SenderBookingDraft draft;
  final VoidCallback onContinue;

  const _IrisPanel({
    required this.engine,
    required this.draft,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final iris = engine.canonicalIrisResult;
    return Column(
      children: [
        const _IrisOrb(),
        const SizedBox(height: 12),
        if (engine.isIrisResolving) ...[
          const LinearProgressIndicator(
            minHeight: 2,
            color: _Tokens.iris,
            backgroundColor: Colors.transparent,
          ),
          const SizedBox(height: 12),
          const Text(
            'Loading IRIS estimate...',
            style: TextStyle(color: _Tokens.muted, height: 1.35),
          ),
        ] else if (engine.irisErrorMessage.isNotEmpty) ...[
          Text(
            engine.irisErrorMessage,
            style: const TextStyle(color: _Tokens.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          _PrimaryButton(
            label: 'Retry',
            enabled: true,
            onTap: () => context.read<SendPackageBloc>().add(
                  RequestCanonicalIrisEstimate(
                    itemName: draft.itemName,
                    quantity: senderQuantityFromItemName(draft.itemName),
                    description: draft.itemDescription,
                    declaredWeightText: draft.weightLabel,
                    fragile: draft.fragile,
                    highValue: draft.highValue,
                  ),
                ),
          ),
        ] else ...[
          if (iris?.partial == true)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Some estimate details are unavailable right now.',
                style: TextStyle(color: _Tokens.muted, height: 1.35),
              ),
            ),
          _SummaryLine(
            label: 'Item & quantity',
            value: iris?.itemAndQuantity ??
                '${draft.itemName.isEmpty ? 'Parcel' : draft.itemName} ×1',
          ),
          _SummaryLine(
            label: 'Estimated total weight',
            value: iris?.totalWeightLabel ?? 'Unavailable',
          ),
          _SummaryLine(
            label: 'Recommended vehicle',
            value: iris?.recommendedVehicle?.isNotEmpty == true
                ? iris!.recommendedVehicle!
                : 'Unavailable',
          ),
          _SummaryLine(
            label: 'Confidence',
            value: iris?.confidenceLabel ?? 'Medium',
          ),
        ],
        ExpansionTile(
          collapsedIconColor: _Tokens.lightBlue,
          iconColor: _Tokens.lightBlue,
          title: const Text(
            'Why IRIS estimated this',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          children: [
            if (iris?.repositoryMatch?.isNotEmpty == true)
              _ReasonLine('Repository match: ${iris!.repositoryMatch}'),
            if (iris?.unitWeightKg != null)
              _ReasonLine('Unit weight: ${iris!.unitWeightLabel}'),
            if (iris != null)
              _ReasonLine('Quantity applied: ×${iris.quantity}'),
            if (iris?.totalWeightKg != null)
              _ReasonLine('Total estimated weight: ${iris!.totalWeightLabel}'),
            if (iris?.similarVerifiedDeliveries != null)
              _ReasonLine(
                'Similar verified deliveries: ${iris!.similarVerifiedDeliveries}',
              ),
            if (iris?.explanation?.isNotEmpty == true)
              _ReasonLine('Confidence reason: ${iris!.explanation}'),
            ...?iris?.reasons.map((reason) => _ReasonLine(reason)),
            const _ReasonLine('Rider verification still happens at collection'),
          ],
        ),
        _PrimaryButton(
          label: 'Choose options',
          enabled: true,
          onTap: onContinue,
        ),
      ],
    );
  }
}

class _OptionsPanel extends StatelessWidget {
  final SenderBookingDraft draft;
  final SendPackageState engine;
  final ValueChanged<SenderBookingDraft> onDraft;
  final VoidCallback onContinue;

  const _OptionsPanel({
    required this.draft,
    required this.engine,
    required this.onDraft,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final quoteTotal = engine.senderQuoteTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose speed first. Vanguard enables a secure delivery protocol.',
          style: TextStyle(color: _Tokens.muted, height: 1.35),
        ),
        const SizedBox(height: 14),
        const _SectionLabel('Delivery speed'),
        const SizedBox(height: 8),
        _SegmentedControl(
          values: senderDeliverySpeeds,
          selected: draft.selectedOption,
          onSelected: (value) {
            final next = draft.copyWith(selectedOption: value);
            onDraft(next);
            _requestQuote(context, next);
          },
        ),
        const SizedBox(height: 16),
        const _SectionLabel('Optional trust protocol'),
        const SizedBox(height: 8),
        _AddOnTile(
          selected: draft.vanguard,
          title: senderVanguardProtocolLabel,
          price: '£${senderVanguardAddOnPriceGbp.toStringAsFixed(2)}',
          subtitle:
              'Mandatory pickup verification, secure custody, secure transit, and secure handover.',
          icon: Icons.shield_outlined,
          onTap: () {
            final next = draft.copyWith(vanguard: !draft.vanguard);
            onDraft(next);
            _requestQuote(context, next);
          },
        ),
        if (draft.vanguard) ...[
          const SizedBox(height: 8),
          const Text(
            '✓ Vanguard Protection Active',
            style: TextStyle(
              color: _Tokens.lightBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _PaymentCard(
          child: Column(
            children: [
              if (engine.isSenderQuoteLoading)
                const _SummaryLine(label: 'Backend quote', value: 'Loading')
              else if (engine.senderQuoteError.isNotEmpty)
                _SummaryLine(
                  label: 'Backend quote',
                  value: engine.senderQuoteError,
                )
              else
                _SummaryLine(
                  label: 'Estimated total',
                  value: quoteTotal == null
                      ? 'Requesting backend quote'
                      : formatSenderCurrency(quoteTotal),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PrimaryButton(
          label: 'Review delivery',
          enabled: quoteTotal != null && !engine.isSenderQuoteLoading,
          onTap: onContinue,
        ),
      ],
    );
  }

  void _requestQuote(BuildContext context, SenderBookingDraft draft) {
    context.read<SendPackageBloc>().add(
          RequestSenderBookingQuote(
            selectedSpeed: draft.selectedOption,
            vanguardProtocolEnabled: draft.vanguard,
            itemName: draft.itemName,
            description: draft.itemDescription,
            weightKg:
                double.tryParse(draft.weightLabel.replaceAll('kg', '')) ?? .5,
            fragile: draft.fragile,
            highValue: draft.highValue,
          ),
        );
  }
}

class _ReviewPanel extends StatelessWidget {
  final SenderBookingDraft draft;
  final SendPackageState engine;
  final VoidCallback onContinue;

  const _ReviewPanel({
    required this.draft,
    required this.engine,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final total = engine.senderQuoteTotal;
    return Column(
      children: [
        _ReviewRow(
          icon: Icons.location_on_outlined,
          label: 'Pickup',
          value: engine.pickupLocation ?? draft.pickupAddress,
        ),
        _ReviewRow(
          icon: Icons.flag_outlined,
          label: 'Drop-off',
          value: engine.destinationLocation ?? draft.dropoffAddress,
        ),
        _ReviewRow(
          icon: Icons.person_outline_rounded,
          label: 'Recipient',
          value: draft.receiverName,
        ),
        _ReviewRow(
          icon: Icons.inventory_2_outlined,
          label: 'Parcel',
          value: draft.itemName,
        ),
        _ReviewRow(
          icon: Icons.schedule_rounded,
          label: 'Delivery time',
          value: draft.deliveryTimeSummary,
        ),
        _ReviewRow(
          icon: Icons.speed_rounded,
          label: 'Delivery priority',
          value: draft.selectedOption,
        ),
        _ReviewRow(
          icon: Icons.pedal_bike_rounded,
          label: 'Vehicle',
          value: engine.irisResult?.vehicleSuitability ?? draft.irisVehicle,
        ),
        if (draft.vanguard)
          _ReviewRow(
            icon: Icons.shield_outlined,
            label: senderVanguardProtocolLabel,
            value: 'Included in backend quote',
            accent: _Tokens.lightBlue,
          ),
        if (engine.senderQuoteLineItems.isNotEmpty)
          ...engine.senderQuoteLineItems.map(
            (item) => _ReviewRow(
              icon: Icons.receipt_long_outlined,
              label: '${item['label'] ?? 'Price line'}',
              value: formatSenderCurrency(
                double.tryParse('${item['amount'] ?? 0}') ?? 0,
              ),
            ),
          ),
        if (engine.senderQuoteError.isNotEmpty)
          _ReviewRow(
            icon: Icons.info_outline_rounded,
            label: 'Backend quote',
            value: engine.senderQuoteError,
          ),
        _ReviewRow(
          icon: Icons.payments_outlined,
          label: 'Estimated total due today',
          value: total == null ? 'Calculating' : '£${total.toStringAsFixed(2)}',
        ),
        const SizedBox(height: 12),
        _PrimaryButton(
          label: 'Continue to payment',
          enabled: total != null && !engine.isSenderQuoteLoading,
          onTap: onContinue,
        ),
      ],
    );
  }
}

class _PaymentPanel extends StatelessWidget {
  final SendPackageState engine;
  final SenderBookingDraft draft;
  final ValueChanged<SenderBookingDraft> onDraft;

  const _PaymentPanel({
    required this.engine,
    required this.draft,
    required this.onDraft,
  });

  @override
  Widget build(BuildContext context) {
    final total = engine.senderQuoteTotal;
    final backendRothCredits = engine.senderRothBalance;
    final rothAvailable = backendRothCredits != null;
    final availableRoth = backendRothCredits ?? 0.0;
    final split = total == null
        ? null
        : SenderPaymentSplit.calculate(
            totalDue: total,
            rothEnabled: rothAvailable && draft.rothEnabled,
            availableRothCredits: availableRoth,
            fallbackMethod: draft.selectedPaymentMethod,
          );
    final submitting =
        engine.isSenderPaymentLoading || engine.isSenderDeliveryCreating;
    final canSubmit =
        total != null && split != null && split.canSubmit && !submitting;
    if (engine.senderPaymentStatus == 'succeeded' &&
        engine.senderPaymentClientSecret == null &&
        engine.senderPaymentSessionId != null &&
        engine.senderCreatedRequestId == null &&
        !engine.isSenderDeliveryCreating &&
        engine.senderDeliveryError.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        _createPaidDelivery(context, engine);
      });
    }
    if (engine.senderPaymentClientSecret != null &&
        engine.senderPaymentSessionId != null &&
        engine.senderPaymentStatus != 'succeeded' &&
        draft.paymentStatus == SenderPaymentStatus.processing &&
        !draft.cardConfirmationStarted &&
        !engine.isSenderPaymentLoading &&
        !engine.isSenderDeliveryCreating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        onDraft(draft.copyWith(cardConfirmationStarted: true));
        _confirmCardPayment(context, engine.senderPaymentClientSecret!, engine);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Choose how you'd like to pay for this delivery.",
          style: TextStyle(color: _Tokens.muted, height: 1.35),
        ),
        const SizedBox(height: 14),
        _PaymentCard(
          child: Column(
            children: [
              _SummaryLine(
                label: 'Selected delivery class',
                value: draft.selectedOption,
              ),
              _SummaryLine(
                label: 'Base delivery',
                value: _lineAmount(engine, 'base_delivery') ??
                    (total == null ? 'Pending route' : 'Included'),
              ),
              _SummaryLine(
                label: 'Speed/class adjustment',
                value: _lineAmount(engine, 'speed_adjustment') ??
                    'Included in backend quote',
              ),
              if (draft.vanguard)
                _SummaryLine(
                  label: senderVanguardProtocolLabel,
                  value: _lineAmount(engine, 'vanguard') ?? 'Included in quote',
                ),
              _SummaryLine(
                label: 'Estimated total due today',
                value: total == null
                    ? 'Pending route'
                    : formatSenderCurrency(total),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const _InfoNote(
          text:
              'Estimated using your declared parcel details. Pickup verification may adjust the price if the parcel is heavier, larger, or different from declared.',
        ),
        const SizedBox(height: 14),
        _PaymentCard(
          tinted: true,
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: _Tokens.lightBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rothAvailable
                          ? '${formatSenderRothCredits(availableRoth)} Roth available · ${formatSenderCurrency(availableRoth * senderRothPoundValue)}'
                          : 'Roth currently unavailable',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: rothAvailable && draft.rothEnabled,
                    activeThumbColor: _Tokens.lightBlue,
                    activeTrackColor: _Tokens.blue.withValues(alpha: .40),
                    onChanged: total == null || !rothAvailable
                        ? null
                        : (value) => _setRoth(value, total, availableRoth),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Apply Roth to this payment',
                  style: TextStyle(color: _Tokens.muted, height: 1.35),
                ),
              ),
              if (!rothAvailable) ...[
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Roth balance could not be loaded from the backend, so Roth cannot be applied right now.',
                    style: TextStyle(color: _Tokens.muted, height: 1.35),
                  ),
                ),
              ],
              if (engine.isSenderRothLoading) ...[
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Loading backend Roth balance...',
                    style: TextStyle(color: _Tokens.muted, height: 1.35),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _SummaryLine(
                label: 'Roth applied',
                value: split == null
                    ? 'Pending total'
                    : '${formatSenderCurrency(split.rothAppliedAmount)} (${formatSenderRothCredits(split.rothAppliedCredits)} Roth)',
              ),
              _SummaryLine(
                label: 'Remaining due',
                value: split == null
                    ? 'Pending total'
                    : formatSenderCurrency(split.remainingAmount),
              ),
            ],
          ),
        ),
        if (split == null || split.requiresFallback) ...[
          const SizedBox(height: 14),
          Text(
            rothAvailable && draft.rothEnabled
                ? "Roth doesn't fully cover this delivery. Choose how to pay the remaining amount."
                : 'Roth is switched off. Choose how to pay the full amount.',
            style: const TextStyle(color: _Tokens.muted, height: 1.35),
          ),
          const SizedBox(height: 10),
          FutureBuilder<SenderPaymentMethodsData>(
            future: FirebaseSenderPaymentProfileRepository().paymentMethods(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _InfoNote(text: 'Loading Pay With profile...');
              }
              final profile = snapshot.data ?? SenderPaymentProfile.empty();
              final options = senderOrderedPaymentOptions(profile);
              return Column(
                children: options
                    .map((option) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _checkoutOptionTile(
                            option,
                            total,
                            availableRoth,
                          ),
                        ))
                    .toList(growable: false),
              );
            },
          ),
          if (draft.selectedPaymentMethod == SenderFallbackPaymentMethod.card &&
              draft.selectedPaymentMethodId.isEmpty) ...[
            const SizedBox(height: 2),
            CardField(
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: .055),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _Tokens.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _Tokens.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _Tokens.lightBlue),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              cursorColor: _Tokens.lightBlue,
            ),
          ],
        ],
        const SizedBox(height: 14),
        _PaymentCard(
          child: Column(
            children: [
              _SummaryLine(
                label: 'Total due today',
                value: total == null
                    ? 'Pending route'
                    : formatSenderCurrency(total),
              ),
              _SummaryLine(
                label: 'Payment split',
                value: split?.splitSummary ?? 'Waiting for route price',
              ),
            ],
          ),
        ),
        if (draft.paymentStatus == SenderPaymentStatus.failed) ...[
          const SizedBox(height: 12),
          const _GapNotice(
            title: "Payment couldn't be started",
            body:
                'Please try again. No payment has been confirmed and no rider broadcast has been created.',
          ),
        ],
        if (engine.senderPaymentError.isNotEmpty ||
            engine.senderDeliveryError.isNotEmpty) ...[
          const SizedBox(height: 12),
          _GapNotice(
            title: "Payment couldn't be completed",
            body: engine.senderPaymentError.isNotEmpty
                ? engine.senderPaymentError
                : engine.senderDeliveryError,
          ),
        ],
        if (engine.senderPaymentClientSecret != null &&
            draft.paymentStatus == SenderPaymentStatus.processing) ...[
          const SizedBox(height: 12),
          const _GapNotice(
            title: 'Confirming card payment',
            body:
                'Your delivery will only be created after Stripe confirms payment.',
          ),
        ],
        const SizedBox(height: 14),
        _PrimaryButton(
          label: submitting
              ? 'Starting payment...'
              : split?.ctaLabel ?? 'Waiting for price',
          enabled: canSubmit,
          onTap: () => _startPayment(context, total, split),
        ),
      ],
    );
  }

  void _setRoth(bool value, double total, double availableRoth) {
    final split = SenderPaymentSplit.calculate(
      totalDue: total,
      rothEnabled: value,
      availableRothCredits: availableRoth,
      fallbackMethod: draft.selectedPaymentMethod,
    );
    onDraft(
      draft.copyWith(
        rothEnabled: value,
        rothAvailableCredits: availableRoth,
        rothAppliedAmount: split.rothAppliedAmount,
        rothAppliedCredits: split.rothAppliedCredits,
        remainingAmount: split.remainingAmount,
        paymentSplitSummary: split.splitSummary,
        amountDue: total,
        clearSelectedPaymentMethod: split.fullyCoveredByRoth,
      ),
    );
  }

  void _selectMethod(
    double total,
    double availableRoth,
    SenderFallbackPaymentMethod method, {
    String paymentMethodId = '',
    String paymentMethodLabel = '',
  }) {
    final split = SenderPaymentSplit.calculate(
      totalDue: total,
      rothEnabled: draft.rothEnabled,
      availableRothCredits: availableRoth,
      fallbackMethod: method,
    );
    onDraft(
      draft.copyWith(
        selectedPaymentMethod: method,
        selectedPaymentMethodId: paymentMethodId,
        selectedPaymentMethodLabel: paymentMethodLabel,
        paymentStatus: SenderPaymentStatus.ready,
        rothAvailableCredits: availableRoth,
        rothAppliedAmount: split.rothAppliedAmount,
        rothAppliedCredits: split.rothAppliedCredits,
        remainingAmount: split.remainingAmount,
        paymentSplitSummary: split.splitSummary,
        amountDue: total,
        cardConfirmationStarted: false,
      ),
    );
  }

  Widget _checkoutOptionTile(
    SenderPaymentProfileOption option,
    double? total,
    double availableRoth,
  ) {
    switch (option.type) {
      case SenderPaymentProfileOptionType.applePay:
        return _PaymentMethodTile(
          title: 'Apple Pay${option.isDefault ? ' · Default' : ''}',
          subtitle: 'Fast checkout on supported iOS devices.',
          icon: Icons.apple_rounded,
          selected: draft.selectedPaymentMethod ==
              SenderFallbackPaymentMethod.applePay,
          onTap: total == null
              ? null
              : () => _selectMethod(
                    total,
                    availableRoth,
                    SenderFallbackPaymentMethod.applePay,
                  ),
        );
      case SenderPaymentProfileOptionType.googlePay:
        return _PaymentMethodTile(
          title: 'Google Pay${option.isDefault ? ' · Default' : ''}',
          subtitle: 'Fast checkout on supported Android devices.',
          icon: Icons.android_rounded,
          selected: draft.selectedPaymentMethod ==
              SenderFallbackPaymentMethod.googlePay,
          onTap: total == null
              ? null
              : () => _selectMethod(
                    total,
                    availableRoth,
                    SenderFallbackPaymentMethod.googlePay,
                  ),
        );
      case SenderPaymentProfileOptionType.savedCard:
        final method = option.method;
        if (method == null) return const SizedBox.shrink();
        return _PaymentMethodTile(
          title: method.isDefault ? '${method.title} · Default' : method.title,
          subtitle: method.expiry,
          icon: Icons.credit_card_rounded,
          selected: draft.selectedPaymentMethodId == method.id,
          onTap: total == null
              ? null
              : () => _selectMethod(
                    total,
                    availableRoth,
                    SenderFallbackPaymentMethod.card,
                    paymentMethodId: method.id,
                    paymentMethodLabel: method.title,
                  ),
        );
      case SenderPaymentProfileOptionType.addPaymentMethod:
        return _PaymentMethodTile(
          title: '+ Add Payment Method',
          subtitle: 'Add a card once and use it across Circum.',
          icon: Icons.add_card_outlined,
          selected:
              draft.selectedPaymentMethod == SenderFallbackPaymentMethod.card &&
                  draft.selectedPaymentMethodId.isEmpty,
          onTap: total == null
              ? null
              : () => _selectMethod(
                    total,
                    availableRoth,
                    SenderFallbackPaymentMethod.card,
                  ),
        );
    }
  }

  void _startPayment(
    BuildContext context,
    double? total,
    SenderPaymentSplit? split,
  ) {
    if (total == null || split == null || !split.canSubmit) return;
    onDraft(
      draft.copyWith(
        paymentStatus: SenderPaymentStatus.processing,
        rothAppliedAmount: split.rothAppliedAmount,
        rothAppliedCredits: split.rothAppliedCredits,
        remainingAmount: split.remainingAmount,
        paymentSplitSummary: split.splitSummary,
        amountDue: total,
      ),
    );
    context.read<SendPackageBloc>().add(
          StartSenderPaymentSession(
            rothEnabled: split.rothEnabled,
            fallbackMethod: split.fallbackMethod == null
                ? 'roth'
                : draft.selectedPaymentMethodLabel.isNotEmpty
                    ? 'saved_card'
                    : senderPaymentMethodLabel(split.fallbackMethod!),
            paymentMethodId: draft.selectedPaymentMethodId,
          ),
        );
  }

  Future<void> _confirmCardPayment(
    BuildContext context,
    String clientSecret,
    SendPackageState engine,
  ) async {
    try {
      final params = draft.selectedPaymentMethodId.isEmpty
          ? const PaymentMethodParams.card(
              paymentMethodData: PaymentMethodData(),
            )
          : PaymentMethodParams.cardFromMethodId(
              paymentMethodData: PaymentMethodDataCardFromMethod(
                paymentMethodId: draft.selectedPaymentMethodId,
              ),
            );
      final intent = await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: clientSecret,
        data: params,
      );
      if (!context.mounted) return;
      if (intent.status != PaymentIntentsStatus.Succeeded) {
        onDraft(draft.copyWith(paymentStatus: SenderPaymentStatus.failed));
        return;
      }
      onDraft(draft.copyWith(paymentStatus: SenderPaymentStatus.paid));
      _createPaidDelivery(context, engine);
    } on StripeException catch (error) {
      debugPrint('Sender mobile Stripe confirmation failed: $error');
      if (!context.mounted) return;
      onDraft(draft.copyWith(paymentStatus: SenderPaymentStatus.failed));
    } catch (error) {
      debugPrint('Sender mobile Stripe confirmation failed: $error');
      if (!context.mounted) return;
      onDraft(draft.copyWith(paymentStatus: SenderPaymentStatus.failed));
    }
  }

  void _createPaidDelivery(BuildContext context, SendPackageState engine) {
    context.read<SendPackageBloc>().add(
          CreatePaidSenderDelivery(
            bookingPayload: _bookingPayload(engine),
          ),
        );
  }

  String? _lineAmount(SendPackageState engine, String key) {
    for (final item in engine.senderQuoteLineItems) {
      if ('${item['key']}' == key) {
        return formatSenderCurrency(
          double.tryParse('${item['amount'] ?? 0}') ?? 0,
        );
      }
    }
    return null;
  }

  Map<String, dynamic> _bookingPayload(SendPackageState engine) => {
        'pickup': {
          'address': engine.pickupLocation ?? draft.pickupAddress,
          'subAddress': engine.pickupLocationSubAddress ?? '',
          'locality': engine.pickupLocality ?? '',
          'coordinates': {
            'lat': engine.pickupCoordinate?.lat ?? 0,
            'lng': engine.pickupCoordinate?.lng ?? 0,
          },
        },
        'dropoff': {
          'address': engine.destinationLocation ?? draft.dropoffAddress,
          'subAddress': engine.destinationLocationSubAddress ?? '',
          'locality': engine.destinationLocality ?? '',
          'coordinates': {
            'lat': engine.desinationCoordinate?.lat ?? 0,
            'lng': engine.desinationCoordinate?.lng ?? 0,
          },
        },
        'recipient': {
          'name': draft.receiverName,
          'phone': draft.receiverPhone,
          'deliveryNotes': draft.deliveryNotes,
        },
        'deliveryTime': {
          'type': draft.deliveryTimingType == SenderDeliveryTimingType.now
              ? 'now'
              : 'scheduled',
          'scheduledDate': draft.scheduledDate,
          'scheduledWindow': draft.scheduledWindow,
          'customWindowStart': draft.customWindowStart,
          'customWindowEnd': draft.customWindowEnd,
          'summary': draft.deliveryTimeSummary,
        },
        'parcel': {
          'itemName': draft.itemName,
          'description': draft.itemDescription,
          'weightLabel': draft.weightLabel,
          'weightKg': engine.parcelWeightKg,
          'fragile': draft.fragile,
          'highValue': draft.highValue,
        },
        'iris': {
          'itemName': engine.canonicalIrisResult?.itemName,
          'quantity': engine.canonicalIrisResult?.quantity,
          'totalWeightKg': engine.canonicalIrisResult?.totalWeightKg,
          'recommendedVehicle': engine.canonicalIrisResult?.recommendedVehicle,
          'confidence': engine.canonicalIrisResult?.confidenceLabel,
          'category': engine.canonicalIrisResult?.category,
          'vanguardRequired': engine.canonicalIrisResult?.vanguardRequired,
          'vanguardRequiredReason':
              engine.canonicalIrisResult?.vanguardRequiredReason,
        },
      };
}

class _RadioGlassTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String caption;
  final VoidCallback onTap;

  const _RadioGlassTile({
    required this.selected,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? _Tokens.blue.withValues(alpha: .14)
              : Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _Tokens.lightBlue : _Tokens.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 19,
              height: 19,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _Tokens.lightBlue : _Tokens.muted,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: _Tokens.lightBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    style: const TextStyle(color: _Tokens.muted, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  final String text;

  const _InfoNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Tokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: _Tokens.muted,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: _Tokens.muted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final Widget child;
  final bool tinted;

  const _PaymentCard({required this.child, this.tinted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tinted
            ? _Tokens.blue.withValues(alpha: .12)
            : Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: tinted
              ? _Tokens.lightBlue.withValues(alpha: .40)
              : _Tokens.border,
        ),
      ),
      child: child,
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _PaymentMethodTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected
              ? _Tokens.blue.withValues(alpha: .14)
              : Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _Tokens.lightBlue : _Tokens.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: _Tokens.lightBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: _Tokens.muted)),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? _Tokens.lightBlue : _Tokens.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final String? helperText;
  final String? errorText;
  final ValueChanged<String> onChanged;

  const _TextInput({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.helperText,
    this.errorText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _Tokens.muted),
        helperText: helperText,
        helperStyle: const TextStyle(color: _Tokens.muted, height: 1.25),
        errorText: errorText,
        errorStyle: const TextStyle(color: Color(0xFFFCA5A5), height: 1.25),
        filled: true,
        fillColor: const Color(0xAA1A2030),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      minLeadingWidth: 0,
      leading: const Icon(Icons.location_on_outlined, color: _Tokens.lightBlue),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(color: _Tokens.muted)),
      onTap: onTap,
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? _Tokens.blue.withValues(alpha: .22)
              : Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _Tokens.lightBlue : _Tokens.border,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: _Tokens.blue.withValues(alpha: .30),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ]
              : const [],
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_Tokens.lightBlue, _Tokens.blue, _Tokens.vanguard],
                )
              : null,
        ),
        child: ElevatedButton(
          onPressed: enabled ? onTap : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: enabled
                ? Colors.transparent
                : Colors.white.withValues(alpha: .10),
            disabledBackgroundColor: Colors.white.withValues(alpha: .10),
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: _Tokens.lightBlue,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;

  const _SegmentedControl({
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _Tokens.border),
      ),
      child: Row(
        children: values.map((value) {
          final active = selected == value;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onSelected(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: active
                      ? _Tokens.blue.withValues(alpha: .24)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active ? _Tokens.lightBlue : Colors.transparent,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: _Tokens.blue.withValues(alpha: .24),
                            blurRadius: 18,
                          ),
                        ]
                      : const [],
                ),
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active ? Colors.white : _Tokens.muted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AddOnTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String price;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _AddOnTile({
    required this.selected,
    required this.title,
    required this.price,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? _Tokens.vanguard.withValues(alpha: .20)
              : Colors.white.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? _Tokens.lightBlue : _Tokens.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _Tokens.vanguard.withValues(alpha: .26),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ]
              : const [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? _Tokens.lightBlue : Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        price,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _Tokens.muted, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? _Tokens.lightBlue : _Tokens.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: _Tokens.muted)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = _Tokens.lightBlue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Tokens.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: _Tokens.muted)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonLine extends StatelessWidget {
  final String text;

  const _ReasonLine(this.text);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.check_rounded, color: _Tokens.lightBlue),
      title: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}

class _GapNotice extends StatelessWidget {
  final String title;
  final String body;

  const _GapNotice({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE0A93A).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE0A93A).withValues(alpha: .35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE0A93A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(color: _Tokens.muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  final Widget child;

  const _Glass({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * .54,
          ),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _Tokens.midnight.withValues(alpha: .84),
                _Tokens.bg.withValues(alpha: .72),
                _Tokens.blue.withValues(alpha: .10),
              ],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: .18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .40),
                blurRadius: 36,
                offset: const Offset(0, 22),
              ),
              BoxShadow(
                color: _Tokens.blue.withValues(alpha: .14),
                blurRadius: 34,
              ),
            ],
          ),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _Tokens.glass,
          shape: BoxShape.circle,
          border: Border.all(color: _Tokens.border),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _TrustPill extends StatelessWidget {
  const _TrustPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _Tokens.glass,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Tokens.border),
      ),
      child: const Text(
        'IRIS',
        style: TextStyle(
          color: _Tokens.lightBlue,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _IrisOrb extends StatelessWidget {
  const _IrisOrb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [_Tokens.iris, _Tokens.vanguard, _Tokens.bg],
        ),
        boxShadow: [
          BoxShadow(color: _Tokens.iris.withValues(alpha: .24), blurRadius: 28),
        ],
      ),
      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
    );
  }
}

class _SenderMobileMap extends StatefulWidget {
  final bool active;
  final bool showDestination;
  final bool showVanguardShield;
  final double? distanceKm;

  const _SenderMobileMap({
    required this.active,
    this.showDestination = false,
    this.showVanguardShield = false,
    this.distanceKm,
  });

  @override
  State<_SenderMobileMap> createState() => _SenderMobileMapState();
}

class _SenderMobileMapState extends State<_SenderMobileMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distance = widget.distanceKm;
    final etaMinutes =
        distance == null ? null : math.max(6, distance * 4).round();
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _MapPainter(
              t: _controller.value,
              active: widget.active,
              showDestination: widget.showDestination,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        if (widget.showDestination)
          Positioned(
            left: 18,
            bottom: 24,
            child: _BookingMapMetricPill(
              distanceLabel: distance == null
                  ? 'Distance calculating'
                  : '${distance.toStringAsFixed(1)} km',
              etaLabel: etaMinutes == null
                  ? 'ETA calculating'
                  : '$etaMinutes min estimated',
            ),
          ),
        if (widget.showDestination && widget.showVanguardShield)
          const Align(
            alignment: Alignment(-.02, -.12),
            child: _BookingMapVanguardShield(),
          ),
      ],
    );
  }
}

class _BookingMapMetricPill extends StatelessWidget {
  final String distanceLabel;
  final String etaLabel;

  const _BookingMapMetricPill({
    required this.distanceLabel,
    required this.etaLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _Tokens.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Tokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .24),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            distanceLabel,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            etaLabel,
            style: const TextStyle(color: _Tokens.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BookingMapVanguardShield extends StatelessWidget {
  const _BookingMapVanguardShield();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _Tokens.glass,
        border: Border.all(color: _Tokens.lightBlue.withValues(alpha: .34)),
        boxShadow: [
          BoxShadow(
            color: _Tokens.vanguard.withValues(alpha: .16),
            blurRadius: 18,
          ),
        ],
      ),
      child: const Icon(
        Icons.shield_outlined,
        color: _Tokens.lightBlue,
        size: 18,
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final double t;
  final bool active;
  final bool showDestination;

  const _MapPainter({
    required this.t,
    required this.active,
    required this.showDestination,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_Tokens.bg, _Tokens.midnight],
        ).createShader(rect),
    );
    final drift = math.sin(t * math.pi * 2) * 8;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = 1;
    for (var x = -70.0 + drift; x < size.width + 70; x += 50) {
      canvas.drawLine(Offset(x, 0), Offset(x + 28, size.height), grid);
    }
    for (var y = -70.0 - drift; y < size.height + 70; y += 58) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 18), grid);
    }
    final pickup = Offset(size.width * .25, size.height * .30);
    final dropoff = Offset(size.width * .73, size.height * .21);
    final route = Path()
      ..moveTo(pickup.dx, pickup.dy)
      ..cubicTo(
        size.width * .23,
        size.height * .12,
        size.width * .70,
        size.height * .40,
        dropoff.dx,
        dropoff.dy,
      );
    if (showDestination) {
      canvas.drawPath(
        route,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = _Tokens.lightBlue.withValues(alpha: active ? .68 : .24),
      );
      final metrics = route.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final metric = metrics.first;
        final start = (metric.length * t) % metric.length;
        final end = math.min(metric.length, start + metric.length * .24);
        canvas.drawPath(
          metric.extractPath(start, end),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round
            ..shader = LinearGradient(
              colors: [
                _Tokens.iris.withValues(alpha: 0),
                _Tokens.iris.withValues(alpha: .72),
                _Tokens.lightBlue.withValues(alpha: 0),
              ],
            ).createShader(rect),
        );
      }
    }
    _pin(canvas, pickup, _Tokens.blue, t);
    if (showDestination) {
      _pin(canvas, dropoff, const Color(0xFF22C55E), (t + .45) % 1);
    }
  }

  void _pin(Canvas canvas, Offset point, Color color, double phase) {
    canvas.drawCircle(
      point,
      8 + phase * 20,
      Paint()..color = color.withValues(alpha: .15 * (1 - phase)),
    );
    canvas.drawCircle(point, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.active != active ||
      oldDelegate.showDestination != showDestination;
}

class _Tokens {
  static const bg = Color(0xFF07090F);
  static const midnight = Color(0xFF0B1020);
  static const blue = Color(0xFF3B82F6);
  static const lightBlue = Color(0xFF60A5FA);
  static const vanguard = Color(0xFF2563EB);
  static const iris = Color(0xFF38BDF8);
  static const muted = Color(0xFF9CA3AF);
  static const border = Color(0x29FFFFFF);
  static const glass = Color(0x12FFFFFF);
}
