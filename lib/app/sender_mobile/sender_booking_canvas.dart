import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../business/business_journey_context.dart';
import '../send_package/bloc/send_package_bloc.dart';
import 'sender_accessibility.dart';
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
  final _weight = TextEditingController();
  var _searchingPickup = true;
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    _initializeSendRoute();
  }

  void _initializeSendRoute() {
    try {
      final bloc = context.read<SendPackageBloc>();
      bloc.add(CheckForPushToken());
      bloc.add(CheckForActiveRequest());
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'sender send route',
          context: ErrorDescription('initialising SenderBookingCanvas'),
        ),
      );
      _initializationError =
          'Send could not start because its booking engine was unavailable.';
    }
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
            weightKg: _manualWeightKg(_weight.text) ?? 0,
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
    if (_initializationError != null) {
      return _SendRouteStateScaffold(
        title: 'Send unavailable',
        body: _initializationError!,
        actionLabel: 'Retry',
        onAction: () {
          setState(() => _initializationError = null);
          _initializeSendRoute();
        },
      );
    }
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
        if (_draft.step == SenderBookingStep.review) {
          return _SenderReviewDeliveryScreen(
            draft: _draft,
            engine: engine,
            onBack: _back,
            onContinue: _advance,
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

class _SendRouteStateScaffold extends StatelessWidget {
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _SendRouteStateScaffold({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Tokens.bg,
      body: Stack(
        children: [
          const _SenderMobileMap(active: false),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _Glass(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: _Tokens.lightBlue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        body,
                        style: const TextStyle(
                          color: _Tokens.muted,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PrimaryButton(
                        label: actionLabel,
                        enabled: true,
                        onTap: onAction,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
            final parsed = _manualWeightKg(weight.text);
            onDraft(
              draft.copyWith(
                itemName: item.text,
                itemDescription: description.text,
                weightLabel:
                    parsed == null ? '' : '${parsed.toStringAsFixed(1)}kg',
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
        return const SizedBox.shrink();
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

double? _manualWeightKg(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('kg', '').trim();
  if (normalized.isEmpty) return null;
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
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
          hint: 'Estimated after IRIS analysis',
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
    final vehicle = _customerVehicleLabel(iris?.recommendedVehicle);
    return Column(
      children: [
        _IrisOrb(active: engine.isIrisResolving),
        const SizedBox(height: 12),
        if (engine.isIrisResolving) ...[
          const _IrisAnalysisProgress(),
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
          if (iris != null) const _IrisSuccessPulse(),
          if (iris?.partial == true)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Some estimate details are unavailable right now.',
                style: TextStyle(color: _Tokens.muted, height: 1.35),
              ),
            ),
          _IrisResultRow(
            label: 'Item recognised',
            value: iris?.itemName.isNotEmpty == true
                ? iris!.itemName
                : (draft.itemName.isEmpty ? 'Awaiting IRIS' : draft.itemName),
          ),
          _IrisResultRow(
            label: 'Estimated weight',
            value: iris?.totalWeightKg == null
                ? 'Estimated after IRIS analysis'
                : iris!.totalWeightLabel,
          ),
          _IrisResultRow(label: 'Recommended vehicle', value: vehicle),
          _IrisResultRow(
            label: 'Handling requirements',
            value: _handlingRequirements(iris, draft),
          ),
          _IrisResultRow(
            label: 'Confidence',
            value: iris?.confidenceLabel ?? 'Awaiting IRIS',
          ),
          const _IrisResultRow(
            label: 'Rider verification at collection',
            value: 'The rider confirms the parcel before departure.',
          ),
        ],
        ExpansionTile(
          collapsedIconColor: _Tokens.lightBlue,
          iconColor: _Tokens.lightBlue,
          title: const Text(
            'How IRIS reached this estimate',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          children: [
            ..._customerIrisReasons(iris, draft).map(_ReasonLine.new),
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

class _IrisAnalysisProgress extends StatefulWidget {
  const _IrisAnalysisProgress();

  @override
  State<_IrisAnalysisProgress> createState() => _IrisAnalysisProgressState();
}

class _IrisAnalysisProgressState extends State<_IrisAnalysisProgress>
    with SingleTickerProviderStateMixin {
  static const _stages = [
    'Identifying your parcel...',
    'Comparing verified parcel data...',
    'Estimating dimensions...',
    'Calculating weight...',
    'Selecting the best vehicle...',
    'Preparing recommendation...',
    'Complete ✓',
  ];

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2450),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final index = (_controller.value * _stages.length)
            .floor()
            .clamp(0, _stages.length - 1);
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 3,
                value: (_controller.value + .08).clamp(0, 1),
                color: index == _stages.length - 1
                    ? const Color(0xFF22C55E)
                    : _Tokens.iris,
                backgroundColor: Colors.white.withValues(alpha: .06),
              ),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                _stages[index],
                key: ValueKey(_stages[index]),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _Tokens.muted,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _IrisSuccessPulse extends StatelessWidget {
  const _IrisSuccessPulse();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .86, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF22C55E).withValues(alpha: .34),
              ),
            ),
            child: const Text(
              'Complete ✓',
              style: TextStyle(
                color: Color(0xFF86EFAC),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IrisResultRow extends StatelessWidget {
  final String label;
  final String value;

  const _IrisResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF86EFAC), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _Tokens.muted),
            ),
          ),
          const SizedBox(width: 12),
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

String _customerVehicleLabel(String? raw) {
  final normalized = (raw ?? '').trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'any') {
    return 'Multiple suitable vehicles';
  }
  final vehicles = <String>[];
  void addIf(String token, String label) {
    if (normalized.contains(token) && !vehicles.contains(label)) {
      vehicles.add(label);
    }
  }

  addIf('bike', 'Bike');
  addIf('bicycle', 'Bike');
  addIf('motorbike', 'Motorbike');
  addIf('motorcycle', 'Motorbike');
  addIf('car', 'Car');
  addIf('van', 'Van');
  if (vehicles.length > 1) return 'Multiple suitable vehicles';
  if (vehicles.length == 1) return vehicles.single;
  return raw!.trim();
}

String _handlingRequirements(
  dynamic iris,
  SenderBookingDraft draft,
) {
  final requirements = <String>[
    if (draft.fragile) 'Fragile handling',
    if (draft.highValue) 'High-value care',
    if (iris?.vanguardRequired == true) 'Vanguard protection required',
  ];
  return requirements.isEmpty
      ? 'Standard parcel care'
      : requirements.join(' · ');
}

List<String> _customerIrisReasons(dynamic iris, SenderBookingDraft draft) {
  if (iris == null) {
    return const [
      'IRIS will compare your parcel with verified parcel data.',
      'Weight and vehicle guidance appear after analysis completes.',
      'Rider confirms at collection before departure.',
    ];
  }
  final item = '${iris.itemName}'.trim().isEmpty
      ? 'your parcel'
      : '${iris.itemName}'.trim();
  final reasons = <String>[
    if ('${iris.explanation}'.trim().isNotEmpty) '${iris.explanation}'.trim(),
    'Matched to a verified $item profile.',
    if (iris.totalWeightKg != null)
      'Estimated weight based on known dimensions.',
    '${_customerVehicleLabel(iris.recommendedVehicle)} selected for suitable transport.',
    'Rider confirms at collection before departure.',
  ];
  return reasons.toSet().toList(growable: false);
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
              if (engine.senderQuoteError.isNotEmpty)
                _QuoteUnavailable(onRetry: () => _requestQuote(context, draft))
              else if (engine.isSenderQuoteLoading || quoteTotal == null)
                const _QuoteSkeleton()
              else
                _BackendPricingBreakdown(engine: engine),
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
            weightKg: _manualWeightKg(draft.weightLabel) ?? 0,
            fragile: draft.fragile,
            highValue: draft.highValue,
          ),
        );
  }
}

class _SenderReviewDeliveryScreen extends StatefulWidget {
  final SenderBookingDraft draft;
  final SendPackageState engine;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _SenderReviewDeliveryScreen({
    required this.draft,
    required this.engine,
    required this.onBack,
    required this.onContinue,
  });

  @override
  State<_SenderReviewDeliveryScreen> createState() =>
      _SenderReviewDeliveryScreenState();
}

class _SenderReviewDeliveryScreenState
    extends State<_SenderReviewDeliveryScreen> {
  bool _pickupExpanded = false;
  bool _dropoffExpanded = false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final total = widget.engine.senderQuoteTotal;
    final canContinue = total != null && !widget.engine.isSenderQuoteLoading;
    final pickup = widget.engine.pickupLocation ?? widget.draft.pickupAddress;
    final dropoff =
        widget.engine.destinationLocation ?? widget.draft.dropoffAddress;
    final speed = widget.engine.senderQuoteSpeed?.trim().isNotEmpty == true
        ? widget.engine.senderQuoteSpeed!.trim()
        : widget.draft.selectedOption;

    return Scaffold(
      backgroundColor: _Tokens.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: _ReviewBackdrop()),
          SafeArea(
            child: Column(
              children: [
                _ReviewTopBar(onBack: widget.onBack),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    child: ListView(
                      key: ValueKey(widget.engine.senderQuoteId ?? speed),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        18 + media.padding.bottom,
                      ),
                      children: [
                        _ReviewRoutePanel(
                          engine: widget.engine,
                          draft: widget.draft,
                          selectedSpeed: speed,
                        ),
                        const SizedBox(height: 14),
                        _ReviewSheet(
                          child: Column(
                            children: [
                              const _ReviewGrabber(),
                              _ExpandableReviewAddressRow(
                                icon: Icons.location_on_outlined,
                                label: 'Pickup',
                                summary: _reviewAddressSummary(
                                  pickup,
                                  widget.engine.pickupLocality,
                                ),
                                fullAddress: pickup,
                                expanded: _pickupExpanded,
                                onTap: () => setState(
                                  () => _pickupExpanded = !_pickupExpanded,
                                ),
                              ),
                              _ExpandableReviewAddressRow(
                                icon: Icons.flag_outlined,
                                label: 'Drop-off',
                                summary: _reviewAddressSummary(
                                  dropoff,
                                  widget.engine.destinationLocality,
                                ),
                                fullAddress: dropoff,
                                expanded: _dropoffExpanded,
                                onTap: () => setState(
                                  () => _dropoffExpanded = !_dropoffExpanded,
                                ),
                              ),
                              _ReviewListRow(
                                icon: Icons.person_outline_rounded,
                                label: 'Recipient',
                                value: widget.draft.receiverName.trim().isEmpty
                                    ? 'Recipient pending'
                                    : widget.draft.receiverName.trim(),
                                secondary: _maskSenderPhoneForReview(
                                  widget.draft.receiverPhone,
                                ),
                              ),
                              _ReviewListRow(
                                icon: Icons.inventory_2_outlined,
                                label: 'Parcel',
                                value: widget.draft.itemName.trim().isEmpty
                                    ? 'Parcel pending'
                                    : widget.draft.itemName.trim(),
                                secondary: _reviewIrisEstimate(
                                  widget.engine,
                                  widget.draft,
                                ),
                                badge: widget.draft.vanguard
                                    ? const _VanguardReviewBadge()
                                    : null,
                              ),
                              _ReviewListRow(
                                icon: Icons.schedule_rounded,
                                label: 'Delivery time',
                                value: widget.draft.deliveryTimeSummary,
                              ),
                              _ReviewListRow(
                                icon: Icons.speed_rounded,
                                label: 'Delivery priority',
                                value: speed,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _ReviewBottomBar(
                  total: total,
                  loading: widget.engine.isSenderQuoteLoading,
                  error: widget.engine.senderQuoteError,
                  canContinue: canContinue,
                  onContinue: widget.onContinue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewBackdrop extends StatelessWidget {
  const _ReviewBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _Tokens.bg,
        gradient: RadialGradient(
          center: const Alignment(-.65, -.95),
          radius: 1.15,
          colors: [
            _Tokens.blue.withValues(alpha: .16),
            _Tokens.midnight.withValues(alpha: .70),
            _Tokens.bg,
          ],
          stops: const [0, .48, 1],
        ),
      ),
    );
  }
}

class _ReviewTopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _ReviewTopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        children: [
          _ReviewIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            label: 'Back',
            onTap: onBack,
          ),
          const Expanded(
            child: Text(
              'Review your delivery',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: .1,
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _ReviewIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ReviewIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .055),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _Tokens.border),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _ReviewRoutePanel extends StatefulWidget {
  final SendPackageState engine;
  final SenderBookingDraft draft;
  final String selectedSpeed;

  const _ReviewRoutePanel({
    required this.engine,
    required this.draft,
    required this.selectedSpeed,
  });

  @override
  State<_ReviewRoutePanel> createState() => _ReviewRoutePanelState();
}

class _ReviewRoutePanelState extends State<_ReviewRoutePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routeConfirmed = widget.engine.polylineCoordinates.isNotEmpty ||
        widget.engine.polylines.isNotEmpty ||
        widget.engine.distance != null;
    final pickup = _compactAddress(
      widget.engine.pickupLocation ?? widget.draft.pickupAddress,
    );
    final dropoff = _compactAddress(
      widget.engine.destinationLocation ?? widget.draft.dropoffAddress,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 238,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _Tokens.blue.withValues(alpha: .16),
                _Tokens.midnight.withValues(alpha: .92),
                const Color(0xFF0D111C),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .36),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: _ReviewMapGrid()),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _ReviewRoutePainter(
                    t: _controller.value,
                    routeConfirmed: routeConfirmed,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: 22,
                bottom: 30,
                child: _ReviewPinLabel(label: pickup, color: _Tokens.blue),
              ),
              Positioned(
                right: 22,
                bottom: 30,
                child:
                    _ReviewPinLabel(label: dropoff, color: Color(0xFF34D399)),
              ),
              const Positioned(top: 14, right: 14, child: _ReviewIrisBadge()),
              Positioned(
                left: 14,
                bottom: 14,
                child: _ReviewEtaChip(
                  routeConfirmed: routeConfirmed,
                  distanceKm: widget.engine.distance,
                  speed: widget.selectedSpeed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewMapGrid extends StatelessWidget {
  const _ReviewMapGrid();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ReviewMapGridPainter());
  }
}

class _ReviewMapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .06)
      ..strokeWidth = 1;
    const spacing = 28.0;
    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final shade = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          _Tokens.bg.withValues(alpha: .28),
        ],
        stops: const [.40, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, shade);
  }

  @override
  bool shouldRepaint(covariant _ReviewMapGridPainter oldDelegate) => false;
}

class _ReviewRoutePainter extends CustomPainter {
  final double t;
  final bool routeConfirmed;

  const _ReviewRoutePainter({required this.t, required this.routeConfirmed});

  @override
  void paint(Canvas canvas, Size size) {
    final route = Path()
      ..moveTo(size.width * .10, size.height * .72)
      ..cubicTo(
        size.width * .30,
        size.height * .72,
        size.width * .30,
        size.height * .30,
        size.width * .50,
        size.height * .30,
      )
      ..cubicTo(
        size.width * .70,
        size.height * .30,
        size.width * .70,
        size.height * .72,
        size.width * .90,
        size.height * .72,
      );
    final glow = Paint()
      ..color = _Tokens.blue.withValues(alpha: .16)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawPath(route, glow);
    final line = Paint()
      ..color = _Tokens.blue.withValues(alpha: routeConfirmed ? .94 : .74)
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (routeConfirmed) {
      canvas.drawPath(route, line);
      final metric = route.computeMetrics().first;
      final progress = (metric.length * t).clamp(0, metric.length).toDouble();
      canvas.drawPath(
        metric.extractPath(0, progress),
        Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: .75)
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    } else {
      _drawDashedPath(canvas, route, line, phase: t * 14);
    }
    _drawPin(canvas, Offset(size.width * .10, size.height * .72), _Tokens.blue);
    _drawPin(
      canvas,
      Offset(size.width * .90, size.height * .72),
      const Color(0xFF34D399),
    );
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double phase,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = -phase;
      while (distance < metric.length) {
        final start = math.max(0.0, distance);
        final end = math.min(metric.length, distance + 9);
        if (end > 0) canvas.drawPath(metric.extractPath(start, end), paint);
        distance += 17;
      }
    }
  }

  void _drawPin(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(
      center,
      12,
      Paint()..color = color.withValues(alpha: .14),
    );
    canvas.drawCircle(center, 6, Paint()..color = color);
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: .60),
    );
  }

  @override
  bool shouldRepaint(covariant _ReviewRoutePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.routeConfirmed != routeConfirmed;
}

class _ReviewPinLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _ReviewPinLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .58),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ],
    );
  }
}

class _ReviewIrisBadge extends StatelessWidget {
  const _ReviewIrisBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _Tokens.blue.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Tokens.blue.withValues(alpha: .30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: _Tokens.blue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'IRIS',
            style: TextStyle(
              color: _Tokens.lightBlue,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewEtaChip extends StatelessWidget {
  final bool routeConfirmed;
  final double? distanceKm;
  final String speed;

  const _ReviewEtaChip({
    required this.routeConfirmed,
    required this.distanceKm,
    required this.speed,
  });

  @override
  Widget build(BuildContext context) {
    final routeLabel = routeConfirmed
        ? distanceKm == null
            ? 'Route confirmed'
            : '${distanceKm!.toStringAsFixed(1)} km · $speed'
        : 'Route calculating · $speed';
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF0D111C).withValues(alpha: .86),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: _Tokens.lightBlue,
                size: 15,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ESTIMATED DELIVERY',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .42),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    routeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewSheet extends StatelessWidget {
  final Widget child;

  const _ReviewSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0D111C).withValues(alpha: .82),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ReviewGrabber extends StatelessWidget {
  const _ReviewGrabber();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _ReviewListRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? secondary;
  final Widget? badge;

  const _ReviewListRow({
    required this.icon,
    required this.label,
    required this.value,
    this.secondary,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: .08)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReviewRowIcon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReviewRowLabel(label),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (secondary != null && secondary!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    secondary!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .56),
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (badge != null) ...[
                  const SizedBox(height: 7),
                  badge!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandableReviewAddressRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String summary;
  final String fullAddress;
  final bool expanded;
  final VoidCallback onTap;

  const _ExpandableReviewAddressRow({
    required this.icon,
    required this.label,
    required this.summary,
    required this.fullAddress,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canExpand = fullAddress.trim().isNotEmpty;
    return Semantics(
      button: true,
      label: '$label address',
      child: InkWell(
        onTap: canExpand ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: .08)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReviewRowIcon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReviewRowLabel(label),
                      const SizedBox(height: 3),
                      Text(
                        summary,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      if (canExpand) ...[
                        const SizedBox(height: 4),
                        Text(
                          expanded ? fullAddress : 'View full address',
                          style: TextStyle(
                            color: expanded
                                ? Colors.white.withValues(alpha: .58)
                                : _Tokens.lightBlue,
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (canExpand)
                  AnimatedRotation(
                    turns: expanded ? .25 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: .36),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewRowIcon extends StatelessWidget {
  final IconData icon;

  const _ReviewRowIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: _Tokens.blue.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _Tokens.blue.withValues(alpha: .18)),
      ),
      child: Icon(icon, color: _Tokens.lightBlue, size: 16),
    );
  }
}

class _ReviewRowLabel extends StatelessWidget {
  final String label;

  const _ReviewRowLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: .40),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        fontFamily: 'JetBrains Mono',
      ),
    );
  }
}

class _VanguardReviewBadge extends StatelessWidget {
  const _VanguardReviewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF34D399).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF34D399).withValues(alpha: .25),
        ),
      ),
      child: const Text(
        'Vanguard protected',
        style: TextStyle(
          color: Color(0xFF34D399),
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }
}

class _ReviewBottomBar extends StatelessWidget {
  final double? total;
  final bool loading;
  final String error;
  final bool canContinue;
  final VoidCallback onContinue;

  const _ReviewBottomBar({
    required this.total,
    required this.loading,
    required this.error,
    required this.canContinue,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 13, 18, 12 + bottom),
          decoration: BoxDecoration(
            color: const Color(0xFF0D111C).withValues(alpha: .88),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: .10)),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 108,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'TOTAL',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .42),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: loading
                          ? const _ReviewTotalSkeleton()
                          : Text(
                              error.isNotEmpty
                                  ? 'Quote needed'
                                  : total == null
                                      ? 'Pending'
                                      : _formatQuoteAmount(total!),
                              key: ValueKey('$total$error$loading'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      const Text(
                        'Unable to retrieve your quote.',
                        style: TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: _PrimaryButton(
                    label: 'Continue to payment',
                    enabled: canContinue,
                    onTap: onContinue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewTotalSkeleton extends StatelessWidget {
  const _ReviewTotalSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('review-total-skeleton'),
      width: 72,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

String _reviewAddressSummary(String address, String? locality) {
  final compact = _compactAddress(address);
  final area = _reviewAddressArea(address, locality);
  if (area.isEmpty || area == compact) return compact;
  return '$compact, $area';
}

String _reviewAddressArea(String address, String? locality) {
  final cleanLocality = locality?.trim();
  if (cleanLocality != null && cleanLocality.isNotEmpty) return cleanLocality;
  final parts = address
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length >= 2) return parts[parts.length - 2];
  return '';
}

String _maskSenderPhoneForReview(String phone) {
  final trimmed = phone.trim();
  if (trimmed.isEmpty) return 'Phone number pending';
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.length <= 3) return 'Phone masked until rider assigned';
  final suffix = digits.substring(digits.length - 3);
  final prefix = trimmed.startsWith('+') ? '+${digits.substring(0, 2)} ' : '';
  return '$prefix•••• •••$suffix';
}

String _reviewIrisEstimate(
  SendPackageState engine,
  SenderBookingDraft draft,
) {
  final result = engine.canonicalIrisResult;
  final weight = result?.totalWeightLabel ??
      (draft.weightLabel.trim().isEmpty
          ? 'Estimated after IRIS analysis'
          : draft.weightLabel.trim());
  final vehicle = _customerVehicleLabel(
    result?.recommendedVehicle ?? draft.irisVehicle,
  );
  if (weight == 'Estimated after IRIS analysis') {
    return '$weight • $vehicle recommended';
  }
  return 'Estimated $weight • $vehicle recommended';
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
              if (engine.senderQuoteError.isNotEmpty)
                const _QuoteErrorText()
              else if (engine.isSenderQuoteLoading || total == null)
                const _QuoteSkeleton()
              else
                _BackendPricingBreakdown(engine: engine),
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
                    'Roth balance could not be loaded, so Roth cannot be applied right now.',
                    style: TextStyle(color: _Tokens.muted, height: 1.35),
                  ),
                ),
              ],
              if (engine.isSenderRothLoading) ...[
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Loading Roth balance...',
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
              final options = senderOrderedPaymentOptions(
                profile,
                platform: Theme.of(context).platform,
              );
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

  Future<void> _startPayment(
    BuildContext context,
    double? total,
    SenderPaymentSplit? split,
  ) async {
    if (total == null || split == null || !split.canSubmit) return;
    final method = split.fullyCoveredByRoth
        ? 'Roth'
        : draft.selectedPaymentMethodLabel.isNotEmpty
            ? draft.selectedPaymentMethodLabel
            : senderPaymentMethodLabel(split.fallbackMethod!);
    final confirmed = await confirmSenderPaymentIfRequired(
      context,
      paymentMethod: method,
      amount: '£${total.toStringAsFixed(2)}',
    );
    if (!confirmed || !context.mounted) return;
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
      SenderAccessibilityScope.maybeOf(context)
          ?.haptic(SenderFeedbackEvent.paymentCompleted);
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

String _compactAddress(String address) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return 'Address pending';
  final postcode = RegExp(
    r'\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b',
    caseSensitive: false,
  ).firstMatch(trimmed)?.group(0);
  if (postcode != null && postcode.trim().isNotEmpty) {
    return postcode.toUpperCase();
  }
  final parts = trimmed
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return trimmed;
  return parts.length == 1 ? parts.single : parts.last;
}

class _BackendPricingBreakdown extends StatelessWidget {
  final SendPackageState engine;

  const _BackendPricingBreakdown({required this.engine});

  @override
  Widget build(BuildContext context) {
    final lines = engine.senderQuoteLineItems
        .map(
          (item) => (
            label: _quoteLineLabel(item),
            amount: _quoteLineAmountFromItem(item),
          ),
        )
        .where((item) => item.amount != null)
        .toList(growable: false);
    return Column(
      children: [
        ...lines.map(
          (item) => _SummaryLine(label: item.label, value: item.amount!),
        ),
        if (engine.senderQuoteTotal != null)
          _SummaryLine(
            label: 'Estimated total today',
            value: _formatQuoteAmount(engine.senderQuoteTotal!),
          ),
      ],
    );
  }
}

class _QuoteSkeleton extends StatelessWidget {
  const _QuoteSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          margin: const EdgeInsets.symmetric(vertical: 7),
          height: 16,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .07 + index * .015),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _QuoteUnavailable extends StatelessWidget {
  final VoidCallback onRetry;

  const _QuoteUnavailable({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _QuoteErrorText(),
        const SizedBox(height: 10),
        _PrimaryButton(label: 'Retry', enabled: true, onTap: onRetry),
      ],
    );
  }
}

class _QuoteErrorText extends StatelessWidget {
  const _QuoteErrorText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Unable to retrieve your quote.',
      style: TextStyle(
        color: Color(0xFFFCA5A5),
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

String _quoteLineLabel(Map<String, dynamic> item) {
  final label = '${item['label'] ?? ''}'.trim();
  if (label.isNotEmpty) return label;
  return switch ('${item['key'] ?? item['type']}'.trim()) {
    'base_delivery' || 'base' => 'Base delivery',
    'distance_adjustment' || 'distance' => 'Distance adjustment',
    'weight_adjustment' || 'weight' => 'Weight adjustment',
    'speed_adjustment' || 'speed' => 'Speed adjustment',
    'economy_discount' => 'Economy discount',
    'promotional_credit' || 'promotion' => 'Promotional credit',
    'vanguard' || 'vanguard_protection' => 'Vanguard protection',
    _ => 'Quote line',
  };
}

String? _quoteLineAmountFromItem(Map<String, dynamic> item) {
  final value = item['amount'] ?? item['total'] ?? item['value'];
  if (value == null) return null;
  if (value is num) return _formatQuoteAmount(value.toDouble());
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  final parsed = double.tryParse(text);
  return parsed == null ? text : _formatQuoteAmount(parsed);
}

String _formatQuoteAmount(double value) {
  if (value < 0) return '-£${value.abs().toStringAsFixed(2)}';
  return formatSenderCurrency(value);
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
  final bool active;

  const _IrisOrb({this.active = false});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: active ? .94 : 1, end: active ? 1.08 : 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [_Tokens.iris, _Tokens.vanguard, _Tokens.bg],
          ),
          boxShadow: [
            BoxShadow(
              color: _Tokens.iris.withValues(alpha: active ? .34 : .24),
              blurRadius: active ? 34 : 28,
            ),
          ],
        ),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
      ),
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
    final highContrast =
        SenderAccessibilityScope.maybeOf(context)?.settings.highContrast ??
            false;
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _MapPainter(
              t: _controller.value,
              active: widget.active,
              showDestination: widget.showDestination,
              highContrast: highContrast,
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
  final bool highContrast;

  const _MapPainter({
    required this.t,
    required this.active,
    required this.showDestination,
    this.highContrast = false,
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
      ..color = Colors.white.withValues(alpha: highContrast ? .12 : .025)
      ..strokeWidth = highContrast ? 1.35 : 1;
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
          ..strokeWidth = highContrast ? 5 : 3
          ..strokeCap = StrokeCap.round
          ..color = _Tokens.lightBlue.withValues(
            alpha: highContrast ? .96 : (active ? .68 : .24),
          ),
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
            ..strokeWidth = highContrast ? 7 : 5
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
      (highContrast ? 11 : 8) + phase * (highContrast ? 24 : 20),
      Paint()
        ..color = color.withValues(
          alpha: (highContrast ? .26 : .15) * (1 - phase),
        ),
    );
    canvas.drawCircle(point, highContrast ? 8 : 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.active != active ||
      oldDelegate.showDestination != showDestination ||
      oldDelegate.highContrast != highContrast;
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
