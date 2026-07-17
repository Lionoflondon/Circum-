import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../send_package/bloc/send_package_bloc.dart';
import '../send_package/view/ride_chats.dart';
import 'design_system/sender_design_system.dart';
import 'sender_accessibility.dart';

enum SenderTrackingState {
  noActiveDelivery,
  loading,
  findingRider,
  riderAssigned,
  riderEnRouteToPickup,
  riderArrivedAtPickup,
  pickupComplete,
  inTransit,
  riderArrivingAtDropoff,
  delivered,
  cancelled,
  issue,
  error,
}

enum SenderDeliveryMapMode { bookingPlanning, liveTracking }

class SenderTrackingContent {
  final String title;
  final String body;
  final String pill;
  final int progress;
  final bool dimMap;
  final bool showRoute;
  final bool showPickupPin;
  final bool showDropoffPin;
  final bool showRider;
  final bool showAnonymousRiders;
  final bool showCollectionPin;
  final bool showReceiverPin;
  final bool showRiderCard;
  final bool showIris;
  final bool showVanguard;
  final bool quietVanguard;
  final bool issueVanguard;
  final bool deliveredVerified;
  final Offset riderPosition;
  final String eta;

  const SenderTrackingContent({
    required this.title,
    required this.body,
    required this.pill,
    required this.progress,
    required this.riderPosition,
    this.dimMap = false,
    this.showRoute = false,
    this.showPickupPin = false,
    this.showDropoffPin = false,
    this.showRider = false,
    this.showAnonymousRiders = false,
    this.showCollectionPin = false,
    this.showReceiverPin = false,
    this.showRiderCard = false,
    this.showIris = true,
    this.showVanguard = false,
    this.quietVanguard = true,
    this.issueVanguard = false,
    this.deliveredVerified = false,
    this.eta = '',
  });

  SenderTrackingContent copyWith({
    bool? showRider,
    bool? showAnonymousRiders,
    bool? showRiderCard,
  }) {
    return SenderTrackingContent(
      title: title,
      body: body,
      pill: pill,
      progress: progress,
      riderPosition: riderPosition,
      dimMap: dimMap,
      showRoute: showRoute,
      showPickupPin: showPickupPin,
      showDropoffPin: showDropoffPin,
      showRider: showRider ?? this.showRider,
      showAnonymousRiders: showAnonymousRiders ?? this.showAnonymousRiders,
      showCollectionPin: showCollectionPin,
      showReceiverPin: showReceiverPin,
      showRiderCard: showRiderCard ?? this.showRiderCard,
      showIris: showIris,
      showVanguard: showVanguard,
      quietVanguard: quietVanguard,
      issueVanguard: issueVanguard,
      deliveredVerified: deliveredVerified,
      eta: eta,
    );
  }
}

bool senderPaymentCompleteForLiveMap(Object? status) {
  return switch (_normalizeTrackingStatus(status)) {
    'paid' ||
    'payment_complete' ||
    'payment_completed' ||
    'succeeded' ||
    'success' ||
    'complete' =>
      true,
    _ => false,
  };
}

bool senderRiderAcceptedForLiveMap(SenderTrackingState state) {
  return switch (state) {
    SenderTrackingState.riderAssigned ||
    SenderTrackingState.riderEnRouteToPickup ||
    SenderTrackingState.riderArrivedAtPickup ||
    SenderTrackingState.pickupComplete ||
    SenderTrackingState.inTransit ||
    SenderTrackingState.riderArrivingAtDropoff ||
    SenderTrackingState.delivered ||
    SenderTrackingState.issue =>
      true,
    _ => false,
  };
}

SenderDeliveryMapMode senderDeliveryMapModeFor({
  required Object? paymentStatus,
  required SenderTrackingState trackingState,
}) {
  if (senderPaymentCompleteForLiveMap(paymentStatus) &&
      senderRiderAcceptedForLiveMap(trackingState)) {
    return SenderDeliveryMapMode.liveTracking;
  }
  return SenderDeliveryMapMode.bookingPlanning;
}

SenderTrackingState senderTrackingStateForEngine(SendPackageState engine) {
  final backendState = senderTrackingStateForBackendStatus(
    engine.deliveryRequestStatus,
  );
  if (backendState != null) return backendState;
  final data = engine.deliveryData;
  if (engine.senderDeliveryError.isNotEmpty) return SenderTrackingState.error;
  switch (engine.deliveryStatus) {
    case DeliveryStatus.deliveryConfirmed:
    case DeliveryStatus.reconnectingWithRider:
      return data == null
          ? SenderTrackingState.findingRider
          : SenderTrackingState.riderAssigned;
    case DeliveryStatus.deliveryOnGoing:
      return SenderTrackingState.inTransit;
    case DeliveryStatus.deliveryCompleted:
      return SenderTrackingState.delivered;
    case DeliveryStatus.inital:
    case DeliveryStatus.addressesSelected:
      return SenderTrackingState.noActiveDelivery;
  }
}

String _normalizeTrackingStatus(Object? value) => '${value ?? ''}'
    .trim()
    .toLowerCase()
    .replaceAll('-', '_')
    .replaceAll(' ', '_');

SenderTrackingState? senderTrackingStateForBackendStatus(Object? status) {
  return switch (_normalizeTrackingStatus(status)) {
    '' => null,
    'requested' ||
    'pending' ||
    'unmatched' ||
    'finding_rider' ||
    'awaiting_rider' ||
    'broadcast' ||
    'broadcasted' =>
      SenderTrackingState.findingRider,
    'accepted' || 'rider_assigned' => SenderTrackingState.riderAssigned,
    'navigating_to_pickup' ||
    'en_route_to_pickup' =>
      SenderTrackingState.riderEnRouteToPickup,
    'arrived_at_pickup' ||
    'waiting' ||
    'waiting_for_collection' ||
    'waiting_charge_active' ||
    'waiting_charges_active' ||
    'no_show_review' =>
      SenderTrackingState.riderArrivedAtPickup,
    'pickup_verification' ||
    'pickup_verified' ||
    'collected' =>
      SenderTrackingState.pickupComplete,
    'delivery_on_going' ||
    'outfordelivery' ||
    'out_for_delivery' ||
    'navigating_to_dropoff' =>
      SenderTrackingState.inTransit,
    'arrived_at_dropoff' ||
    'pin_required' ||
    'handover_pending' =>
      SenderTrackingState.riderArrivingAtDropoff,
    'delivered' ||
    'completed' ||
    'delivery_completed' =>
      SenderTrackingState.delivered,
    'cancelled' ||
    'canceled' ||
    'cancelled_verified_discrepancy' ||
    'sender_no_show_pickup' =>
      SenderTrackingState.cancelled,
    'issue' ||
    'issue_reported' ||
    'failed' ||
    'failed_delivery' =>
      SenderTrackingState.issue,
    'error' => SenderTrackingState.error,
    _ => SenderTrackingState.inTransit,
  };
}

SenderTrackingContent senderTrackingContentFor(
  SenderTrackingState state, {
  bool deliveryVerified = false,
}) {
  switch (state) {
    case SenderTrackingState.noActiveDelivery:
      return const SenderTrackingContent(
        title: 'Nothing in motion right now',
        body: 'Your next delivery will appear here.',
        pill: '',
        progress: 0,
        dimMap: true,
        showIris: false,
        riderPosition: Offset(.5, .5),
      );
    case SenderTrackingState.loading:
      return const SenderTrackingContent(
        title: 'Loading delivery',
        body: 'Checking your latest delivery status.',
        pill: '',
        progress: 0,
        dimMap: true,
        riderPosition: Offset(.5, .5),
      );
    case SenderTrackingState.findingRider:
      return const SenderTrackingContent(
        title: 'Finding your rider',
        body: 'Searching verified riders near your pickup.',
        pill: 'Searching',
        progress: 0,
        dimMap: false,
        showPickupPin: true,
        showAnonymousRiders: true,
        showVanguard: true,
        riderPosition: Offset(.34, .44),
        eta: 'Usually under 6 min',
      );
    case SenderTrackingState.riderAssigned:
      return const SenderTrackingContent(
        title: 'Your rider is on the way',
        body: 'Your rider has accepted your delivery.',
        pill: 'Assigned',
        progress: 1,
        showRoute: true,
        showPickupPin: true,
        showDropoffPin: true,
        showRider: true,
        showRiderCard: true,
        showCollectionPin: true,
        showReceiverPin: false,
        showVanguard: true,
        riderPosition: Offset(.40, .46),
        eta: '7 min',
      );
    case SenderTrackingState.riderEnRouteToPickup:
      return const SenderTrackingContent(
        title: 'Your rider is heading to pickup',
        body: 'Have your parcel ready.',
        pill: 'En route',
        progress: 1,
        showRoute: true,
        showPickupPin: true,
        showDropoffPin: true,
        showRider: true,
        showRiderCard: true,
        showCollectionPin: true,
        showReceiverPin: false,
        showVanguard: true,
        riderPosition: Offset(.32, .40),
        eta: '4 min',
      );
    case SenderTrackingState.riderArrivedAtPickup:
      return const SenderTrackingContent(
        title: 'Your rider has arrived',
        body: 'Meet your rider to hand off the parcel.',
        pill: 'Arrived',
        progress: 1,
        showRoute: true,
        showPickupPin: true,
        showDropoffPin: true,
        showRider: true,
        showRiderCard: true,
        showCollectionPin: true,
        showReceiverPin: false,
        showVanguard: true,
        riderPosition: Offset(.20, .32),
        eta: 'Arrived',
      );
    case SenderTrackingState.pickupComplete:
      return const SenderTrackingContent(
        title: 'Parcel collected',
        body: 'Your delivery is now in transit.',
        pill: 'Collected',
        progress: 2,
        showRoute: true,
        showPickupPin: true,
        showDropoffPin: true,
        showRider: true,
        showRiderCard: true,
        showCollectionPin: true,
        showReceiverPin: true,
        showVanguard: true,
        riderPosition: Offset(.24, .34),
        eta: '18 min',
      );
    case SenderTrackingState.inTransit:
      return const SenderTrackingContent(
        title: 'On the way to drop-off',
        body: "Track your parcel's journey in real time.",
        pill: 'In transit',
        progress: 3,
        showRoute: true,
        showPickupPin: true,
        showDropoffPin: true,
        showRider: true,
        showRiderCard: true,
        showCollectionPin: true,
        showReceiverPin: true,
        showVanguard: true,
        riderPosition: Offset(.46, .50),
        eta: '11 min',
      );
    case SenderTrackingState.riderArrivingAtDropoff:
      return const SenderTrackingContent(
        title: 'Your rider is almost there',
        body: 'Your parcel is arriving shortly.',
        pill: 'Arriving',
        progress: 3,
        showRoute: true,
        showPickupPin: true,
        showDropoffPin: true,
        showRider: true,
        showRiderCard: true,
        showCollectionPin: true,
        showReceiverPin: true,
        showVanguard: true,
        riderPosition: Offset(.68, .62),
        eta: '< 3 min',
      );
    case SenderTrackingState.delivered:
      return SenderTrackingContent(
        title: deliveryVerified ? 'Delivery verified' : 'Delivered',
        body: deliveryVerified
            ? 'Vanguard confirmed this delivery is complete.'
            : 'Your parcel arrived safely.',
        pill: deliveryVerified ? 'Verified' : 'Delivered',
        progress: 4,
        showRoute: true,
        showPickupPin: true,
        showDropoffPin: true,
        showRider: true,
        showRiderCard: true,
        showVanguard: true,
        quietVanguard: false,
        deliveredVerified: deliveryVerified,
        riderPosition: const Offset(.74, .66),
      );
    case SenderTrackingState.cancelled:
      return const SenderTrackingContent(
        title: 'Delivery cancelled',
        body: 'This delivery is no longer active.',
        pill: '',
        progress: 2,
        dimMap: true,
        showIris: true,
        showVanguard: true,
        quietVanguard: true,
        riderPosition: Offset(.5, .5),
      );
    case SenderTrackingState.issue:
      return const SenderTrackingContent(
        title: "There's an issue with this delivery",
        body:
            "Your rider reported a problem completing this delivery. We're looking into it now.",
        pill: 'Needs attention',
        progress: 3,
        showRoute: true,
        showPickupPin: true,
        showDropoffPin: true,
        showRider: true,
        showCollectionPin: true,
        showReceiverPin: true,
        showVanguard: true,
        issueVanguard: true,
        riderPosition: Offset(.46, .50),
      );
    case SenderTrackingState.error:
      return const SenderTrackingContent(
        title: 'Something went wrong',
        body: "We couldn't load your delivery status.",
        pill: '',
        progress: 0,
        dimMap: true,
        showIris: false,
        riderPosition: Offset(.5, .5),
      );
  }
}

String senderCollectionPinStatusFor(
  SenderTrackingState state, {
  bool verified = false,
}) {
  if (verified) return '✓ Pickup verified';
  return switch (state) {
    SenderTrackingState.pickupComplete ||
    SenderTrackingState.inTransit ||
    SenderTrackingState.riderArrivingAtDropoff ||
    SenderTrackingState.issue =>
      '✓ Pickup verified',
    _ => 'Ready for pickup',
  };
}

String senderReceiverPinStatusFor(
  SenderTrackingState state, {
  bool verified = false,
}) {
  return verified ? '✓ Delivery verified' : 'Ready for delivery';
}

bool senderVanguardCollectionPinVisible(SendPackageState engine) {
  return senderVanguardCollectionPinFor(engine) != null;
}

String? senderVanguardCollectionPinFor(SendPackageState engine) {
  final data = engine.activeDeliveryData;
  final protection = _mapFrom(data['vanguardProtection']);
  final enabled = data['vanguardEnabled'] == true ||
      data['vanguardRequired'] == true ||
      protection['enabled'] == true ||
      protection['required'] == true ||
      '${data['deliveryType'] ?? data['serviceType'] ?? ''}'
          .toLowerCase()
          .contains('vanguard');
  final pin = (engine.deliveryData?.code.trim().isNotEmpty == true
          ? engine.deliveryData?.code
          : '${data['collectionPin'] ?? data['pickupPin'] ?? protection['collectionPin'] ?? ''}')
      ?.trim();
  return enabled && pin != null && pin.isNotEmpty ? pin : null;
}

String _senderWaitingStateLabel({
  required String status,
  required bool noShowAvailable,
  required bool waitingChargesActive,
  required bool finalMinute,
  required bool customerResponded,
}) {
  if (status == 'sender_no_show_pickup' || noShowAvailable) {
    return 'No-show review';
  }
  if (waitingChargesActive) return 'Waiting charges active';
  if (customerResponded) return 'Waiting for collection';
  if (finalMinute) return 'Final minute';
  if (status == 'waiting' || status == 'waiting_for_collection') {
    return 'Waiting for collection';
  }
  return 'Rider arrived';
}

Map<String, dynamic> _mapFrom(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

({double amount, String currency})? _customerWaitingCharge(
  Map<String, dynamic> data,
  Map<String, dynamic> waiting,
) {
  final financial = _mapFrom(data['noShowFinancial']);
  final amount = _numberFrom(
    financial['amount'] ??
        waiting['noShowFeeAmount'] ??
        data['waitingCharge'] ??
        data['waitingChargeAmount'] ??
        data['pickupNoShowSurchargeGbp'],
  );
  if (amount == null || amount <= 0) return null;
  final currency =
      '${financial['currency'] ?? waiting['currency'] ?? data['currency'] ?? 'GBP'}';
  return (amount: amount, currency: currency);
}

double? _numberFrom(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

DateTime? _dateTimeFromBackend(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.round());
  }
  if (value is String) {
    final millis = int.tryParse(value);
    if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
    return DateTime.tryParse(value);
  }
  try {
    final dynamic dynamicValue = value;
    final seconds = dynamicValue.seconds;
    if (seconds is int) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    }
    final milliseconds = dynamicValue.millisecondsSinceEpoch;
    if (milliseconds is int) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
  } catch (_) {
    return null;
  }
  return null;
}

String _durationLabel(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

String _moneyText(double amount, String currency) {
  if (currency.trim().toUpperCase() == 'GBP') {
    return '£${amount.toStringAsFixed(2)}';
  }
  return '${currency.trim().toUpperCase()} ${amount.toStringAsFixed(2)}';
}

String senderActiveDeliveryIdFor(SendPackageState engine) {
  final data = engine.activeDeliveryData;
  return '${data['requestId'] ?? data['deliveryId'] ?? data['id'] ?? data['_docId'] ?? ''}'
      .trim();
}

bool senderCanCancelBeforeCollection(SenderTrackingState state) {
  return switch (state) {
    SenderTrackingState.findingRider ||
    SenderTrackingState.riderAssigned ||
    SenderTrackingState.riderEnRouteToPickup ||
    SenderTrackingState.riderArrivedAtPickup =>
      true,
    _ => false,
  };
}

String _firebaseFunctionMessage(Object error, String fallback) {
  if (error is FirebaseFunctionsException) {
    return error.message ?? fallback;
  }
  return fallback;
}

Future<Map<String, dynamic>> _callFunction(
  String name,
  Map<String, dynamic> payload,
) async {
  final result = await FirebaseFunctions.instance
      .httpsCallable(name)
      .call<Map<String, dynamic>>(payload);
  return Map<String, dynamic>.from(result.data);
}

String senderVehicleMarkerKindFor(String? vehicle) {
  final normalized = (vehicle ?? '').trim().toLowerCase();
  if (normalized.contains('bike') ||
      normalized.contains('bicycle') ||
      normalized.contains('cycle') ||
      normalized.contains('scooter') ||
      normalized.contains('moped')) {
    return 'bike';
  }
  if (normalized.contains('van')) return 'van';
  if (normalized.contains('car')) return 'car';
  return 'unknown';
}

String? senderLiveLocationStaleLabel(
  DateTime? updatedAt, {
  DateTime? now,
}) {
  if (updatedAt == null) return null;
  final age = (now ?? DateTime.now()).difference(updatedAt);
  if (age.inMinutes >= 2) return 'Last seen ${age.inMinutes} min ago';
  if (age.inSeconds >= 45) return 'Location updating…';
  return null;
}

class SenderMobileTrackingScreen extends StatefulWidget {
  final SendPackageState engine;
  final SenderTrackingState? stateOverride;
  final bool deliveryVerified;

  const SenderMobileTrackingScreen({
    super.key,
    required this.engine,
    this.stateOverride,
    this.deliveryVerified = false,
  });

  @override
  State<SenderMobileTrackingScreen> createState() =>
      _SenderMobileTrackingScreenState();
}

class _SenderMobileTrackingScreenState extends State<SenderMobileTrackingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _mapDrift;
  late final AnimationController _pulse;
  late SenderTrackingState _lastState;
  bool _motionReduced = false;

  @override
  void initState() {
    super.initState();
    _mapDrift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat(reverse: true);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _lastState =
        widget.stateOverride ?? senderTrackingStateForEngine(widget.engine);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced =
        SenderAccessibilityScope.maybeOf(context)?.settings.reduceMotion ==
            true;
    if (reduced == _motionReduced) return;
    _motionReduced = reduced;
    if (reduced) {
      _mapDrift.stop();
      _pulse.stop();
    } else {
      _mapDrift.repeat(reverse: true);
      _pulse.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SenderMobileTrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next =
        widget.stateOverride ?? senderTrackingStateForEngine(widget.engine);
    if (next == _lastState) return;
    _lastState = next;
    WidgetsBinding.instance.addPostFrameCallback((_) => _announceState(next));
  }

  Future<void> _announceState(SenderTrackingState state) async {
    if (!mounted) return;
    final controller = SenderAccessibilityScope.maybeOf(context);
    switch (state) {
      case SenderTrackingState.riderAssigned:
        await controller?.haptic(SenderFeedbackEvent.riderAccepted);
        await controller
            ?.announceDelivery(SenderDeliveryAnnouncement.riderAccepted);
      case SenderTrackingState.riderArrivedAtPickup:
        await controller?.haptic(SenderFeedbackEvent.riderArrived);
        await controller
            ?.announceDelivery(SenderDeliveryAnnouncement.riderArrived);
      case SenderTrackingState.pickupComplete:
        await controller
            ?.announceDelivery(SenderDeliveryAnnouncement.pickupComplete);
      case SenderTrackingState.delivered:
        await controller?.haptic(SenderFeedbackEvent.deliveryCompleted);
        await controller
            ?.announceDelivery(SenderDeliveryAnnouncement.deliveryCompleted);
      case SenderTrackingState.error:
      case SenderTrackingState.issue:
        await controller?.haptic(SenderFeedbackEvent.error);
      case SenderTrackingState.noActiveDelivery:
      case SenderTrackingState.loading:
      case SenderTrackingState.findingRider:
      case SenderTrackingState.riderEnRouteToPickup:
      case SenderTrackingState.inTransit:
      case SenderTrackingState.riderArrivingAtDropoff:
      case SenderTrackingState.cancelled:
        break;
    }
  }

  @override
  void dispose() {
    _mapDrift.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state =
        widget.stateOverride ?? senderTrackingStateForEngine(widget.engine);
    final content = senderTrackingContentFor(
      state,
      deliveryVerified: widget.deliveryVerified,
    );
    final mapMode = senderDeliveryMapModeFor(
      paymentStatus: widget.engine.senderPaymentStatus,
      trackingState: state,
    );
    final visibleContent = mapMode == SenderDeliveryMapMode.liveTracking
        ? content.copyWith(showAnonymousRiders: false)
        : state == SenderTrackingState.findingRider
            ? content.copyWith(
                showRider: false,
                showRiderCard: false,
              )
            : content.copyWith(
                showRider: false,
                showAnonymousRiders: false,
                showRiderCard: false,
              );
    final riderPosition = _riderPositionForEngine(widget.engine, content);
    final staleLabel = visibleContent.showRider
        ? senderLiveLocationStaleLabel(widget.engine.riderLiveLocationUpdatedAt)
        : null;
    final delivered = state == SenderTrackingState.delivered;
    final vanguardPin = senderVanguardCollectionPinFor(widget.engine);
    return Stack(
      children: [
        SenderTrackingMapLayer(
          content: visibleContent,
          riderPosition: riderPosition,
          vehicleKind: senderVehicleMarkerKindFor(
            widget.engine.deliveryData?.typeOfVehicle,
          ),
          headingDegrees: widget.engine.riderLiveLocationHeading,
          mapDrift: _mapDrift,
          pulse: _pulse,
          delivered: delivered,
        ),
        if (content.pill.isNotEmpty)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _TopStatusPill(label: content.pill),
              ),
            ),
          ),
        if (vanguardPin != null)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding:
                    EdgeInsets.only(top: content.pill.isNotEmpty ? 56 : 16),
                child: VanguardCollectionPinCard(
                  pin: vanguardPin,
                ),
              ),
            ),
          ),
        if (staleLabel != null) _StaleLocationPill(label: staleLabel),
        if (visibleContent.showRider && !delivered) const _RecenterButton(),
        if (delivered) const _DeliveredConfirmationOverlay(),
        FloatingGlassPanel(
          child: _TrackingPanelContent(
            state: state,
            content: visibleContent,
            engine: widget.engine,
            mapMode: mapMode,
            onOpenMessage: _openDeliveryChat,
            onOpenSupport: _openSupportChat,
            onCancelDelivery: () => _confirmCancelDelivery(state),
          ),
        ),
      ],
    );
  }

  void _openDeliveryChat() {
    final chatId = senderActiveDeliveryIdFor(widget.engine);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RideChatPageView(
          chatId: chatId.isEmpty ? null : chatId,
          title: 'Delivery chat',
        ),
      ),
    );
  }

  void _openSupportChat() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RideChatPageView(
          title: 'Circum Support',
          supportConversation: true,
        ),
      ),
    );
  }

  Future<void> _confirmCancelDelivery(SenderTrackingState state) async {
    if (!senderCanCancelBeforeCollection(state)) {
      _showActionMessage('This delivery can no longer be cancelled here.');
      return;
    }
    final deliveryId = senderActiveDeliveryIdFor(widget.engine);
    if (deliveryId.isEmpty) {
      _showActionMessage('Unable to identify the active delivery.');
      return;
    }
    Map<String, dynamic> quote;
    try {
      quote = await _callFunction(
        'previewSenderCancellation',
        {'deliveryId': deliveryId, 'requestId': deliveryId},
      );
    } catch (error) {
      _showActionMessage(
        _firebaseFunctionMessage(
          error,
          'Unable to retrieve the cancellation fee.',
        ),
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CancelDeliverySheet(quote: quote),
    );
    if (confirmed != true) return;
    try {
      await _callFunction(
        'requestSenderCancellation',
        {'deliveryId': deliveryId, 'requestId': deliveryId},
      );
      if (!mounted) return;
      _showActionMessage('Delivery cancellation sent.');
    } catch (error) {
      if (!mounted) return;
      _showActionMessage(
        _firebaseFunctionMessage(error, 'Cancellation could not be completed.'),
      );
    }
  }

  void _showActionMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

Offset _riderPositionForEngine(
  SendPackageState engine,
  SenderTrackingContent content,
) {
  final rider = engine.riderLocation;
  final pickup = engine.pickupDetails?.address ?? engine.pickupCoordinate;
  final dropoff = engine.dropoffDetails?.address ?? engine.desinationCoordinate;
  if (rider == null || pickup == null || dropoff == null) {
    return content.riderPosition;
  }

  final minLat = [pickup.lat, dropoff.lat].reduce((a, b) => a < b ? a : b);
  final maxLat = [pickup.lat, dropoff.lat].reduce((a, b) => a > b ? a : b);
  final minLng = [pickup.lng, dropoff.lng].reduce((a, b) => a < b ? a : b);
  final maxLng = [pickup.lng, dropoff.lng].reduce((a, b) => a > b ? a : b);
  final latSpan = (maxLat - minLat).abs();
  final lngSpan = (maxLng - minLng).abs();
  if (latSpan == 0 || lngSpan == 0) return content.riderPosition;

  final x = ((rider.lng - minLng) / lngSpan).clamp(0.0, 1.0);
  final y = (1 - ((rider.lat - minLat) / latSpan)).clamp(0.0, 1.0);
  return Offset(.20 + (x * .54), .32 + (y * .34));
}

class SenderTrackingMapLayer extends StatelessWidget {
  final SenderTrackingContent content;
  final Offset riderPosition;
  final String vehicleKind;
  final double? headingDegrees;
  final Animation<double> mapDrift;
  final Animation<double> pulse;
  final bool delivered;

  const SenderTrackingMapLayer({
    super.key,
    required this.content,
    required this.riderPosition,
    required this.vehicleKind,
    this.headingDegrees,
    required this.mapDrift,
    required this.pulse,
    this.delivered = false,
  });

  @override
  Widget build(BuildContext context) {
    final highContrast =
        SenderAccessibilityScope.maybeOf(context)?.settings.highContrast ??
            false;
    return AnimatedBuilder(
      animation: Listenable.merge([mapDrift, pulse]),
      builder: (context, _) {
        final drift = delivered ? 0.0 : (mapDrift.value - .5) * 10;
        final markerPulse = delivered ? 0.0 : pulse.value;
        return Stack(
          children: [
            Transform.translate(
              offset: Offset(drift, -drift / 2),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0A0D16), Color(0xFF07090F)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _TrackingGridPainter(
                  shimmer: delivered ? .5 : mapDrift.value,
                  route: content.showRoute,
                  searching: content.showAnonymousRiders,
                  highContrast: highContrast,
                ),
              ),
            ),
            if (content.showAnonymousRiders)
              Positioned.fill(
                child: CustomPaint(
                  painter: _SearchRingsPainter(
                    progress: markerPulse,
                    highContrast: highContrast,
                  ),
                ),
              ),
            if (content.showRoute)
              _RouteLine(completed: delivered, highContrast: highContrast),
            if (content.showPickupPin)
              Stack(
                children: [
                  _MapPin(
                    alignment: const Alignment(-.62, -.38),
                    color: const Color(0xFF34D399),
                    pulse: markerPulse,
                    strongPulse: content.showAnonymousRiders,
                    highContrast: highContrast,
                  ),
                  if (content.showAnonymousRiders && content.showVanguard)
                    const _PickupVanguardShield(
                      alignment: Alignment(-.50, -.46),
                    ),
                ],
              ),
            if (content.showDropoffPin)
              delivered
                  ? const _CompletionPulse(
                      alignment: Alignment(.48, .34),
                      color: Color(0xFF34D399),
                    )
                  : _MapPin(
                      alignment: const Alignment(.48, .34),
                      color: const Color(0xFF3B82F6),
                      pulse: markerPulse,
                      highContrast: highContrast,
                    ),
            if (content.showAnonymousRiders) ...const [
              _AnonymousRiderDot(alignment: Alignment(-.32, -.12), delay: 0),
              _AnonymousRiderDot(alignment: Alignment(.08, -.30), delay: 360),
              _AnonymousRiderDot(alignment: Alignment(.32, -.02), delay: 720),
              _AnonymousRiderDot(alignment: Alignment(-.02, .18), delay: 1080),
            ],
            if (content.showRider)
              AnimatedAlign(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                alignment: Alignment(
                  riderPosition.dx * 2 - 1,
                  riderPosition.dy * 2 - 1,
                ),
                child: Transform.scale(
                  scale: highContrast ? 1.15 : 1,
                  child: _VehicleMarker(
                    kind: vehicleKind,
                    pulse: markerPulse,
                    settled: delivered,
                    headingDegrees: headingDegrees,
                  ),
                ),
              ),
            AnimatedOpacity(
              opacity: content.dimMap ? .52 : 0,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              child: Container(color: const Color(0xFF050609)),
            ),
          ],
        );
      },
    );
  }
}

class FloatingGlassPanel extends StatelessWidget {
  final Widget child;

  const FloatingGlassPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .38,
      minChildSize: .24,
      maxChildSize: .78,
      snap: true,
      snapSizes: const [.38, .78],
      builder: (context, controller) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: AppGlassContainer(
            radius: 26,
            padding: EdgeInsets.zero,
            accent: AppTokens.primary,
            surfaceColor: Colors.white.withValues(alpha: .048),
            borderColor: const Color(0xFF3B82F6).withValues(alpha: .28),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrackingPanelContent extends StatelessWidget {
  final SenderTrackingState state;
  final SenderTrackingContent content;
  final SendPackageState engine;
  final SenderDeliveryMapMode mapMode;
  final VoidCallback onOpenMessage;
  final VoidCallback onOpenSupport;
  final VoidCallback onCancelDelivery;

  const _TrackingPanelContent({
    required this.state,
    required this.content,
    required this.engine,
    required this.mapMode,
    required this.onOpenMessage,
    required this.onOpenSupport,
    required this.onCancelDelivery,
  });

  @override
  Widget build(BuildContext context) {
    if (state == SenderTrackingState.loading) return const _LoadingTracking();
    final waiting = SenderWaitingSnapshot.fromEngine(engine);
    final hasVanguardCollectionPin = senderVanguardCollectionPinVisible(engine);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeOut,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Text(
            content.title,
            key: ValueKey(content.title),
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'DM Serif Display',
              fontSize: 24,
              height: 1.15,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          content.body,
          style: const TextStyle(
            color: _TrackingTokens.muted,
            height: 1.45,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 16),
        LiveDeliveryTimeline(
          state: state,
          issue: content.issueVanguard,
          completed: state == SenderTrackingState.delivered,
        ),
        if (state == SenderTrackingState.findingRider) ...[
          const SizedBox(height: 12),
          MatchingSearchCard(
            vanguardEnabled: content.showVanguard,
          ),
        ],
        if (mapMode == SenderDeliveryMapMode.bookingPlanning &&
            senderRiderAcceptedForLiveMap(state)) ...[
          const SizedBox(height: 8),
          const _LiveMapPendingPaymentNote(),
        ],
        if (content.showRiderCard) ...[
          const SizedBox(height: 12),
          RiderCard(engine: engine, eta: content.eta),
        ],
        if (waiting.visible) ...[
          const SizedBox(height: 12),
          SenderWaitingCard(waiting: waiting),
        ],
        if (content.showCollectionPin && !hasVanguardCollectionPin) ...[
          const SizedBox(height: 12),
          PINCard(
            pin: engine.deliveryData?.code,
            label: 'Collection PIN',
            hint: 'Give this to your rider at pickup.',
            statusLabel: senderCollectionPinStatusFor(
              state,
              verified: engine.collectionPinVerified,
            ),
            statusComplete: senderCollectionPinStatusFor(
              state,
              verified: engine.collectionPinVerified,
            ).startsWith('✓'),
            accent: const Color(0xFF3B82F6),
            icon: Icons.inventory_2_outlined,
          ),
        ],
        if (content.showReceiverPin) ...[
          const SizedBox(height: 12),
          PINCard(
            pin: engine.deliveryData?.deliveryPin,
            label: 'Receiver PIN',
            hint: 'Give this to the receiver at delivery.',
            statusLabel: senderReceiverPinStatusFor(
              state,
              verified: engine.deliveryPinVerified,
            ),
            statusComplete: senderReceiverPinStatusFor(
              state,
              verified: engine.deliveryPinVerified,
            ).startsWith('✓'),
            accent: const Color(0xFF34D399),
            icon: Icons.verified_outlined,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (state != SenderTrackingState.delivered && content.showIris)
              const IRISChip(),
            if (state != SenderTrackingState.delivered && content.showVanguard)
              VanguardChip(
                quiet: content.quietVanguard,
                issue: content.issueVanguard,
                completed: state == SenderTrackingState.delivered,
              ),
          ],
        ),
        if (state == SenderTrackingState.delivered) ...[
          const SizedBox(height: 8),
          const _DeliveredChipSequence(),
        ],
        const SizedBox(height: 16),
        _TrackingActions(
          state: state,
          onOpenMessage: onOpenMessage,
          onOpenSupport: onOpenSupport,
          onCancelDelivery: onCancelDelivery,
        ),
      ],
    );
  }
}

class _DeliveredConfirmationOverlay extends StatefulWidget {
  const _DeliveredConfirmationOverlay();

  @override
  State<_DeliveredConfirmationOverlay> createState() =>
      _DeliveredConfirmationOverlayState();
}

class _DeliveredConfirmationOverlayState
    extends State<_DeliveredConfirmationOverlay> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => _visible = true);
    });
    Future<void>.delayed(const Duration(milliseconds: 3100), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 58),
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: Duration(milliseconds: _visible ? 300 : 400),
            curve: Curves.easeOut,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF34D399).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFF34D399).withValues(alpha: .28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF34D399).withValues(alpha: .16),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Text(
                '✓ Delivery completed',
                style: TextStyle(
                  color: Color(0xFF34D399),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeliveredChipSequence extends StatelessWidget {
  const _DeliveredChipSequence();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _DelayedFadeChip(
          delay: Duration(milliseconds: 350),
          label: 'IRIS parcel confirmed',
          color: Color(0xFF3B82F6),
          glow: true,
        ),
        _DelayedFadeChip(
          delay: Duration(milliseconds: 450),
          label: 'Vanguard completed',
          color: Color(0xFF34D399),
        ),
      ],
    );
  }
}

class _DelayedFadeChip extends StatefulWidget {
  final Duration delay;
  final String label;
  final Color color;
  final bool glow;

  const _DelayedFadeChip({
    required this.delay,
    required this.label,
    required this.color,
    this.glow = false,
  });

  @override
  State<_DelayedFadeChip> createState() => _DelayedFadeChipState();
}

class _DelayedFadeChipState extends State<_DelayedFadeChip> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: widget.color.withValues(alpha: .18)),
          boxShadow: widget.glow
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: .12),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '•',
              style: TextStyle(
                color: widget.color,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              widget.label,
              style: const TextStyle(
                color: _TrackingTokens.mid,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SenderWaitingSnapshot {
  final bool visible;
  final String stateLabel;
  final String countdownLabel;
  final double progress;
  final String? chargeLabel;
  final bool noShowAvailable;
  final bool customerResponded;
  final String message;

  const SenderWaitingSnapshot({
    required this.visible,
    required this.stateLabel,
    required this.countdownLabel,
    required this.progress,
    required this.message,
    this.chargeLabel,
    this.noShowAvailable = false,
    this.customerResponded = false,
  });

  factory SenderWaitingSnapshot.fromEngine(SendPackageState engine) {
    final data = engine.activeDeliveryData;
    final waiting = _mapFrom(data['waiting']);
    final status = _normalizeTrackingStatus(
      data['status'] ?? data['deliveryStatus'] ?? engine.deliveryRequestStatus,
    );
    final visible = waiting['active'] == true ||
        status == 'arrived_at_pickup' ||
        status == 'waiting' ||
        status == 'waiting_for_collection' ||
        status == 'waiting_charge_active' ||
        status == 'waiting_charges_active' ||
        status == 'no_show_review';
    if (!visible) {
      return const SenderWaitingSnapshot(
        visible: false,
        stateLabel: '',
        countdownLabel: '',
        progress: 0,
        message: '',
      );
    }

    final freeWaitEndsAt = _dateTimeFromBackend(waiting['freeWaitEndsAt']);
    final startedAt = _dateTimeFromBackend(
      waiting['startedAt'] ?? data['pickupArrivedAt'] ?? data['arrivedAt'],
    );
    final freeWaitMinutes = _numberFrom(waiting['freeWaitMinutes']) ?? 3;
    final totalSeconds = math.max(1, (freeWaitMinutes * 60).round());
    final remaining = freeWaitEndsAt?.difference(DateTime.now()).inSeconds;
    final remainingSeconds = remaining == null ? null : math.max(0, remaining);
    final elapsedSeconds = startedAt == null
        ? null
        : math.max(0, DateTime.now().difference(startedAt).inSeconds);
    final progress = remainingSeconds == null
        ? elapsedSeconds == null
            ? 0.0
            : (elapsedSeconds / totalSeconds).clamp(0.0, 1.0)
        : ((totalSeconds - remainingSeconds) / totalSeconds).clamp(0.0, 1.0);
    final waitingContext =
        _normalizeTrackingStatus(data['waitingContextState']);
    final customerResponded = waitingContext == 'customer_responded' ||
        data['customerResponded'] == true ||
        waiting['customerResponded'] == true;
    final noShowAvailable = status == 'no_show_review' ||
        status == 'sender_no_show_pickup' ||
        data['noShowAvailable'] == true ||
        waiting['noShowAvailable'] == true;
    final waitingChargesActive = status == 'waiting_charge_active' ||
        status == 'waiting_charges_active' ||
        data['waitingChargesActive'] == true ||
        waiting['waitingChargesActive'] == true;
    final finalMinute = status == 'final_minute' ||
        data['waitingFinalMinute'] == true ||
        waiting['finalMinute'] == true;
    final charge = _customerWaitingCharge(data, waiting);
    final chargeLabel =
        charge == null ? null : _moneyText(charge.amount, charge.currency);
    final stateLabel = _senderWaitingStateLabel(
      status: status,
      noShowAvailable: noShowAvailable,
      waitingChargesActive: waitingChargesActive,
      finalMinute: finalMinute,
      customerResponded: customerResponded,
    );
    final countdown = noShowAvailable
        ? 'No-show eligible'
        : remainingSeconds == null
            ? 'Live countdown active'
            : _durationLabel(remainingSeconds);
    return SenderWaitingSnapshot(
      visible: true,
      stateLabel: stateLabel,
      countdownLabel: countdown,
      progress: progress.toDouble(),
      chargeLabel: chargeLabel,
      noShowAvailable: noShowAvailable,
      customerResponded: customerResponded,
      message: customerResponded
          ? 'Customer response received. Collection time continues.'
          : noShowAvailable
              ? 'Your rider has completed the required waiting period. Contact your rider immediately if you still require this delivery.'
              : 'Sender notified on arrival. Collection countdown is live.',
    );
  }
}

class SenderWaitingCard extends StatelessWidget {
  final SenderWaitingSnapshot waiting;

  const SenderWaitingCard({super.key, required this.waiting});

  @override
  Widget build(BuildContext context) {
    return AppGlassContainer(
      radius: 18,
      padding: const EdgeInsets.all(14),
      accent: waiting.noShowAvailable
          ? const Color(0xFFF5A623)
          : const Color(0xFF3B82F6),
      surfaceColor: Colors.white.withValues(alpha: .052),
      borderColor: (waiting.noShowAvailable
              ? const Color(0xFFF5A623)
              : const Color(0xFF3B82F6))
          .withValues(alpha: .26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WaitingCountdownRing(
            progress: waiting.progress,
            label: waiting.countdownLabel,
            warning: waiting.noShowAvailable,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '✓ Rider has arrived',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Meet your rider to hand over your parcel.',
                  style: TextStyle(
                    color: _TrackingTokens.muted,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  waiting.stateLabel,
                  style: TextStyle(
                    color: waiting.noShowAvailable
                        ? const Color(0xFFF5A623)
                        : const Color(0xFF60A5FA),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  waiting.message,
                  style: const TextStyle(
                    color: _TrackingTokens.mid,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                if (waiting.chargeLabel != null) ...[
                  const SizedBox(height: 10),
                  _WaitingChargeRow(label: waiting.chargeLabel!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CancelDeliverySheet extends StatelessWidget {
  final Map<String, dynamic> quote;

  const _CancelDeliverySheet({required this.quote});

  @override
  Widget build(BuildContext context) {
    final fee = _numberFrom(
      quote['cancellationFee'] ??
          quote['fee'] ??
          quote['amountToCharge'] ??
          quote['chargeAmount'],
    );
    final refund = _numberFrom(
      quote['amountToRefund'] ?? quote['refundAmount'] ?? quote['refund'],
    );
    final currency = '${quote['currency'] ?? 'GBP'}';
    final reason =
        '${quote['reason'] ?? quote['backendReason'] ?? 'Cancellation terms apply.'}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AppGlassContainer(
          radius: 24,
          padding: const EdgeInsets.all(18),
          accent: const Color(0xFFF87171),
          surfaceColor: const Color(0xFF07090F).withValues(alpha: .88),
          borderColor: const Color(0xFFF87171).withValues(alpha: .26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cancel this delivery?',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'DM Serif Display',
                  fontSize: 23,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The rider will be updated immediately if you confirm.',
                style: TextStyle(
                  color: _TrackingTokens.muted,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _CancellationQuoteLine(
                label: 'Cancellation fee',
                value: fee == null
                    ? 'Provided by Circum'
                    : _moneyText(fee, currency),
              ),
              _CancellationQuoteLine(label: 'Reason', value: reason),
              _CancellationQuoteLine(
                label: 'Amount to be charged/refunded',
                value: refund == null
                    ? '${quote['amountSummary'] ?? 'Circum will finalise'}'
                    : _moneyText(refund, currency),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Keep delivery'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF87171),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Confirm cancel'),
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

class _CancellationQuoteLine extends StatelessWidget {
  final String label;
  final String value;

  const _CancellationQuoteLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _TrackingTokens.muted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WaitingCountdownRing extends StatelessWidget {
  final double progress;
  final String label;
  final bool warning;

  const WaitingCountdownRing({
    super.key,
    required this.progress,
    required this.label,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = warning ? const Color(0xFFF5A623) : const Color(0xFF3B82F6);
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 5,
              backgroundColor: Colors.white.withValues(alpha: .09),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'JetBrains Mono',
                fontSize: 10,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingChargeRow extends StatelessWidget {
  final String label;

  const _WaitingChargeRow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5A623).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFF5A623).withValues(alpha: .24),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.payments_outlined,
            color: Color(0xFFF5A623),
            size: 15,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Additional waiting charge $label',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VanguardCollectionPinCard extends StatefulWidget {
  final String? pin;

  const VanguardCollectionPinCard({super.key, required this.pin});

  @override
  State<VanguardCollectionPinCard> createState() =>
      _VanguardCollectionPinCardState();
}

class _VanguardCollectionPinCardState extends State<VanguardCollectionPinCard> {
  bool _copied = false;

  Future<void> _copy() async {
    final pin = widget.pin;
    if (pin == null || pin.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: pin.trim()));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        offset: Offset.zero,
        child: AppGlassContainer(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          accent: const Color(0xFF34D399),
          surfaceColor: const Color(0xFF07090F).withValues(alpha: .72),
          borderColor: const Color(0xFF34D399).withValues(alpha: .28),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF34D399).withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF34D399).withValues(alpha: .26),
                  ),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFF34D399),
                  size: 18,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Vanguard Collection PIN',
                      style: TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'This PIN must be shown to your rider during collection.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _TrackingTokens.muted,
                        fontSize: 10.5,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      pin == null || pin.isEmpty
                          ? 'Awaiting PIN'
                          : _formatPin(pin),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'JetBrains Mono',
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: pin == null || pin.isEmpty ? null : _copy,
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 16,
                ),
                label: Text(_copied ? 'Copied' : 'Copy'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RiderCard extends StatelessWidget {
  final SendPackageState engine;
  final String eta;

  const RiderCard({super.key, required this.engine, required this.eta});

  @override
  Widget build(BuildContext context) {
    final data = engine.deliveryData;
    final name = _firstName(data?.courierName) ?? 'Your rider';
    final vehicle = data?.typeOfVehicle.trim().isNotEmpty == true
        ? data!.typeOfVehicle
        : 'Rider';
    final rating = data?.rating.trim().isNotEmpty == true ? data!.rating : '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFF1B2440),
            child: Text(
              name.isEmpty ? 'R' : name[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'DM Serif Display',
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    'Order rider',
                    if (rating.isNotEmpty) '$rating star',
                    vehicle,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _TrackingTokens.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          if (eta.isNotEmpty) ETABadge(value: eta),
        ],
      ),
    );
  }
}

class IRISChip extends StatelessWidget {
  const IRISChip({super.key});

  @override
  Widget build(BuildContext context) {
    return const _StatusChip(
        label: 'IRIS parcel confirmed', color: Color(0xFF3B82F6));
  }
}

class VanguardChip extends StatelessWidget {
  final bool quiet;
  final bool issue;
  final bool completed;

  const VanguardChip({
    super.key,
    this.quiet = true,
    this.issue = false,
    this.completed = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = issue
        ? 'Vanguard reviewing'
        : completed
            ? 'Vanguard completed'
            : 'Vanguard active';
    final color = issue
        ? const Color(0xFFF5A623)
        : quiet
            ? const Color(0xFF8B93A7)
            : const Color(0xFF34D399);
    return _StatusChip(label: label, color: color);
  }
}

class PINCard extends StatefulWidget {
  final String? pin;
  final String label;
  final String hint;
  final String statusLabel;
  final bool statusComplete;
  final Color accent;
  final IconData icon;

  const PINCard({
    super.key,
    required this.pin,
    required this.label,
    required this.hint,
    required this.statusLabel,
    required this.statusComplete,
    required this.accent,
    required this.icon,
  });

  @override
  State<PINCard> createState() => _PINCardState();
}

class _PINCardState extends State<PINCard> {
  bool _revealed = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _reveal() {
    if (widget.pin == null || widget.pin!.isEmpty) return;
    setState(() => _revealed = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _revealed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin;
    final digits = pin == null || pin.isEmpty
        ? '••••••'
        : _revealed
            ? _formatPin(pin)
            : '••••••';
    return GestureDetector(
      onTap: _reveal,
      onLongPress: _reveal,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.accent.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.accent.withValues(alpha: .34),
          ),
          boxShadow: [
            BoxShadow(
              color: widget.accent.withValues(alpha: .10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(right: 11),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.accent.withValues(alpha: .24)),
              ),
              child: Icon(widget.icon, color: widget.accent, size: 18),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.hint,
                    style: const TextStyle(
                      color: _TrackingTokens.muted,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 9),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    child: _PinStatusLabel(
                      key: ValueKey(widget.statusLabel),
                      label: widget.statusLabel,
                      complete: widget.statusComplete,
                      accent: widget.accent,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  digits,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  pin == null || pin.isEmpty
                      ? 'Awaiting PIN'
                      : _revealed
                          ? 'Auto-hides'
                          : 'Tap to reveal',
                  style: const TextStyle(
                    color: _TrackingTokens.muted,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PinStatusLabel extends StatelessWidget {
  final String label;
  final bool complete;
  final Color accent;

  const _PinStatusLabel({
    super.key,
    required this.label,
    required this.complete,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: complete ? .14 : .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: complete ? accent : _TrackingTokens.mid,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class ProgressStepper extends StatelessWidget {
  final int progress;
  final bool issue;
  final bool completed;

  const ProgressStepper(
      {super.key,
      required this.progress,
      this.issue = false,
      this.completed = false});

  @override
  Widget build(BuildContext context) {
    const labels = ['Assigned', 'Pickup', 'Transit', 'Delivered'];
    final completeColor =
        completed ? const Color(0xFF34D399) : const Color(0xFF3B82F6);
    return Column(
      children: [
        Row(
          children: List.generate(4, (index) {
            final step = index + 1;
            final filled = progress >= step;
            final active = progress == step && !issue;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                height: 3,
                margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
                decoration: BoxDecoration(
                  color: issue && progress == step
                      ? const Color(0xFFF5A623)
                      : filled
                          ? completeColor
                          : Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: completeColor.withValues(alpha: .38),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels
              .map(
                (label) => Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: _TrackingTokens.muted,
                    fontFamily: 'JetBrains Mono',
                    fontSize: 9,
                    letterSpacing: .3,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class LiveDeliveryTimeline extends StatelessWidget {
  final SenderTrackingState state;
  final bool issue;
  final bool completed;

  const LiveDeliveryTimeline({
    super.key,
    required this.state,
    this.issue = false,
    this.completed = false,
  });

  static const _labels = [
    'Searching',
    'Matching',
    'Rider accepting',
    'Assigned',
    'Travelling to pickup',
    'Collected',
    'In transit',
    'Delivered',
  ];

  int get _activeIndex {
    return switch (state) {
      SenderTrackingState.findingRider => 1,
      SenderTrackingState.riderAssigned => 3,
      SenderTrackingState.riderEnRouteToPickup ||
      SenderTrackingState.riderArrivedAtPickup =>
        4,
      SenderTrackingState.pickupComplete => 5,
      SenderTrackingState.inTransit ||
      SenderTrackingState.riderArrivingAtDropoff ||
      SenderTrackingState.issue =>
        6,
      SenderTrackingState.delivered => 7,
      SenderTrackingState.cancelled => 2,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final activeIndex = _activeIndex;
    final activeColor = issue
        ? const Color(0xFFF5A623)
        : completed
            ? const Color(0xFF34D399)
            : const Color(0xFF3B82F6);
    return Semantics(
      label: 'Delivery timeline, current step ${_labels[activeIndex]}',
      child: AppGlassContainer(
        radius: 17,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        accent: activeColor,
        surfaceColor: Colors.white.withValues(alpha: .035),
        borderColor: Colors.white.withValues(alpha: .075),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: List.generate(_labels.length, (index) {
                final active = index == activeIndex;
                final done = index < activeIndex || completed;
                final color = active || done
                    ? activeColor
                    : Colors.white.withValues(alpha: .14);
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    height: active ? 4 : 3,
                    margin: EdgeInsets.only(
                      right: index == _labels.length - 1 ? 0 : 5,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: activeColor.withValues(alpha: .30),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Text(
              _labels[activeIndex].toUpperCase(),
              style: TextStyle(
                color: activeColor,
                fontFamily: 'JetBrains Mono',
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _labels.map((label) {
                final index = _labels.indexOf(label);
                final isCurrent = index == activeIndex;
                return Text(
                  label,
                  style: TextStyle(
                    color: isCurrent
                        ? Colors.white
                        : Colors.white.withValues(alpha: .42),
                    fontSize: 10.5,
                    fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class MatchingSearchCard extends StatelessWidget {
  final bool vanguardEnabled;

  const MatchingSearchCard({
    super.key,
    required this.vanguardEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return AppGlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(15),
      accent: const Color(0xFF3B82F6),
      surfaceColor: Colors.white.withValues(alpha: .055),
      borderColor: const Color(0xFF3B82F6).withValues(alpha: .22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MatchingStatusRotator(),
          const SizedBox(height: 14),
          const Text(
            'Searching within your area',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Circum is checking nearby verified riders and preserving your booking state until a rider accepts.',
            style: TextStyle(
              color: _TrackingTokens.muted,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 13),
          const ProgressiveMatchChecklist(),
          const SizedBox(height: 13),
          _MatchAssuranceGrid(vanguardEnabled: vanguardEnabled),
        ],
      ),
    );
  }
}

class MatchingStatusRotator extends StatefulWidget {
  const MatchingStatusRotator({super.key});

  @override
  State<MatchingStatusRotator> createState() => _MatchingStatusRotatorState();
}

class _MatchingStatusRotatorState extends State<MatchingStatusRotator> {
  static const _messages = [
    'Searching nearby riders...',
    'Checking rider availability...',
    'Finding the fastest rider...',
    'Sending request...',
  ];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _messages.length);
      _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _SearchingOrb(),
        const SizedBox(width: 11),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Text(
              _messages[_index],
              key: ValueKey(_messages[_index]),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchingOrb extends StatefulWidget {
  const _SearchingOrb();

  @override
  State<_SearchingOrb> createState() => _SearchingOrbState();
}

class _SearchingOrbState extends State<_SearchingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
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
        final pulse = math.sin(_controller.value * math.pi);
        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF3B82F6).withValues(alpha: .13),
            border: Border.all(
              color:
                  const Color(0xFF3B82F6).withValues(alpha: .25 + pulse * .20),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6)
                    .withValues(alpha: .14 + pulse * .12),
                blurRadius: 16 + pulse * 10,
              ),
            ],
          ),
          child: const Icon(
            Icons.radar_rounded,
            color: Color(0xFF60A5FA),
            size: 18,
          ),
        );
      },
    );
  }
}

class ProgressiveMatchChecklist extends StatefulWidget {
  const ProgressiveMatchChecklist({super.key});

  @override
  State<ProgressiveMatchChecklist> createState() =>
      _ProgressiveMatchChecklistState();
}

class _ProgressiveMatchChecklistState extends State<ProgressiveMatchChecklist> {
  static const _items = [
    'Searching nearby riders',
    'Searching verified riders',
    'Matching based on distance',
    'Matching based on vehicle suitability',
    'Matching based on trust',
    'Matching based on availability',
  ];
  int _visibleCount = 1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      setState(() {
        _visibleCount =
            _visibleCount >= _items.length ? _items.length : _visibleCount + 1;
      });
      if (_visibleCount < _items.length) _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(_visibleCount, (index) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: 1,
          child: Padding(
            padding:
                EdgeInsets.only(bottom: index == _visibleCount - 1 ? 0 : 8),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF34D399),
                  size: 16,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _items[index],
                    style: const TextStyle(
                      color: _TrackingTokens.mid,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _MatchAssuranceGrid extends StatelessWidget {
  final bool vanguardEnabled;

  const _MatchAssuranceGrid({required this.vanguardEnabled});

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Your parcel is secured.',
        Icons.lock_outline_rounded,
        const Color(0xFF60A5FA)
      ),
      (
        'IRIS estimate confirmed.',
        Icons.auto_awesome_rounded,
        const Color(0xFF3B82F6)
      ),
      (
        'Vehicle recommendation ready.',
        Icons.pedal_bike_rounded,
        const Color(0xFF34D399)
      ),
      if (vanguardEnabled)
        (
          'Vanguard protection active.',
          Icons.shield_outlined,
          const Color(0xFF34D399)
        ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: item.$3.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: item.$3.withValues(alpha: .18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.$2, color: item.$3, size: 14),
              const SizedBox(width: 7),
              Text(
                item.$1,
                style: const TextStyle(
                  color: _TrackingTokens.mid,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class ETABadge extends StatelessWidget {
  final String value;

  const ETABadge({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      child: Text(
        value,
        key: ValueKey(value),
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'JetBrains Mono',
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TrackingActions extends StatelessWidget {
  final SenderTrackingState state;
  final VoidCallback onOpenMessage;
  final VoidCallback onOpenSupport;
  final VoidCallback onCancelDelivery;

  const _TrackingActions({
    required this.state,
    required this.onOpenMessage,
    required this.onOpenSupport,
    required this.onCancelDelivery,
  });

  @override
  Widget build(BuildContext context) {
    final delivered = state == SenderTrackingState.delivered;
    final empty = state == SenderTrackingState.noActiveDelivery;
    final finding = state == SenderTrackingState.findingRider;
    return Row(
      children: [
        Expanded(
          child: _TrackingButton(
            label: empty
                ? 'Send a parcel'
                : finding
                    ? 'Message Support'
                    : delivered
                        ? 'View receipt'
                        : 'Message',
            primary: empty,
            onTap: finding
                ? onOpenSupport
                : empty || delivered
                    ? null
                    : onOpenMessage,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TrackingButton(
            label: finding
                ? 'Cancel Delivery'
                : delivered
                    ? 'Done'
                    : 'Support',
            primary: delivered || state == SenderTrackingState.issue,
            success: delivered,
            onTap: finding
                ? onCancelDelivery
                : delivered
                    ? null
                    : onOpenSupport,
          ),
        ),
      ],
    );
  }
}

class _TrackingButton extends StatelessWidget {
  final String label;
  final bool primary;
  final bool success;
  final VoidCallback? onTap;

  const _TrackingButton({
    required this.label,
    this.primary = false,
    this.success = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: primary && !success
                      ? const Color(0xFF3B82F6)
                      : Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: success
                        ? const Color(0xFF34D399).withValues(alpha: .36)
                        : Colors.white.withValues(alpha: .08),
                  ),
                  boxShadow: success
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFF34D399).withValues(alpha: .20),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
              ),
              if (success)
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    builder: (context, value, _) {
                      return FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: value,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF34D399)
                                .withValues(alpha: .92 + value * .08),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              Positioned.fill(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: primary ? Colors.white : const Color(0xFFF2F4F8),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
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

class _CompletionPulse extends StatefulWidget {
  final Alignment alignment;
  final Color color;

  const _CompletionPulse({required this.alignment, required this.color});

  @override
  State<_CompletionPulse> createState() => _CompletionPulseState();
}

class _CompletionPulseState extends State<_CompletionPulse> {
  bool _active = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _active = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _active ? 1 : 0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        builder: (context, value, child) {
          return Container(
            width: 16 + value * 42,
            height: 16 + value * 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.color.withValues(alpha: (1 - value) * .30),
              ),
            ),
            child: child,
          );
        },
        child: Center(
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: .22),
                  spreadRadius: 6,
                  blurRadius: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: _TrackingTokens.mid,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopStatusPill extends StatelessWidget {
  final String label;

  const _TopStatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0C14).withValues(alpha: .72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: .28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF34D399),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: _TrackingTokens.mid,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaleLocationPill extends StatelessWidget {
  final String label;

  const _StaleLocationPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 58),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5A623).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFFF5A623).withValues(alpha: .34),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF5C77E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFF5C77E),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecenterButton extends StatelessWidget {
  const _RecenterButton();

  @override
  Widget build(BuildContext context) {
    final leftHanded =
        SenderAccessibilityScope.maybeOf(context)?.settings.leftHandedMode ==
            true;
    return Positioned(
      right: leftHanded ? null : 16,
      left: leftHanded ? 16 : null,
      bottom: 226,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0C14).withValues(alpha: .78),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF3B82F6).withValues(alpha: .28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .22),
                  blurRadius: 18,
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.my_location_rounded,
                  color: Color(0xFFF2F4F8),
                  size: 13,
                ),
                SizedBox(width: 6),
                Text(
                  'Recenter',
                  style: TextStyle(
                    color: Color(0xFFF2F4F8),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
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

class _LoadingTracking extends StatelessWidget {
  const _LoadingTracking();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Skeleton(widthFactor: .62, height: 18),
        SizedBox(height: 10),
        _Skeleton(widthFactor: .88),
        SizedBox(height: 10),
        _Skeleton(widthFactor: .44),
        SizedBox(height: 18),
        _Skeleton(widthFactor: 1, height: 58),
      ],
    );
  }
}

class _Skeleton extends StatefulWidget {
  final double widthFactor;
  final double height;

  const _Skeleton({required this.widthFactor, this.height = 12});

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widget.widthFactor,
      alignment: Alignment.centerLeft,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Container(
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment(-1 + _controller.value * 2, 0),
                end: Alignment(_controller.value * 2, 0),
                colors: [
                  Colors.white.withValues(alpha: .04),
                  Colors.white.withValues(alpha: .11),
                  Colors.white.withValues(alpha: .04),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LiveMapPendingPaymentNote extends StatelessWidget {
  const _LiveMapPendingPaymentNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.lock_clock_outlined,
            color: Color(0xFF60A5FA),
            size: 18,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Live tracking begins once payment is complete and your rider has accepted.',
              style: TextStyle(color: _TrackingTokens.muted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final double pulse;
  final bool strongPulse;
  final bool highContrast;

  const _MapPin({
    required this.alignment,
    required this.color,
    required this.pulse,
    this.strongPulse = false,
    this.highContrast = false,
  });

  @override
  Widget build(BuildContext context) {
    final ring = strongPulse ? 8 + pulse * 24 : 6.0;
    return Align(
      alignment: alignment,
      child: Container(
        width: highContrast ? 18 : 14,
        height: highContrast ? 18 : 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(
                alpha: highContrast ? .48 : (strongPulse ? .32 : .18),
              ),
              spreadRadius: highContrast ? ring + 2 : ring,
              blurRadius: ring * 1.6,
            ),
          ],
        ),
      ),
    );
  }
}

class _PickupVanguardShield extends StatelessWidget {
  final Alignment alignment;

  const _PickupVanguardShield({required this.alignment});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFF07090F).withValues(alpha: .78),
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF34D399).withValues(alpha: .35),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF34D399).withValues(alpha: .18),
              blurRadius: 12,
            ),
          ],
        ),
        child: const Icon(
          Icons.shield_outlined,
          color: Color(0xFF34D399),
          size: 14,
        ),
      ),
    );
  }
}

class _AnonymousRiderDot extends StatefulWidget {
  final Alignment alignment;
  final int delay;

  const _AnonymousRiderDot({required this.alignment, required this.delay});

  @override
  State<_AnonymousRiderDot> createState() => _AnonymousRiderDotState();
}

class _AnonymousRiderDotState extends State<_AnonymousRiderDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    Future<void>.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: FadeTransition(
        opacity: Tween<double>(begin: .15, end: .72).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOut),
        ),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF60A5FA).withValues(alpha: .90),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withValues(alpha: .36),
                blurRadius: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleMarker extends StatelessWidget {
  final String kind;
  final double pulse;
  final bool settled;
  final double? headingDegrees;

  const _VehicleMarker({
    required this.kind,
    required this.pulse,
    this.settled = false,
    this.headingDegrees,
  });

  @override
  Widget build(BuildContext context) {
    final size = switch (kind) {
      'van' => const Size(34, 24),
      'car' => const Size(30, 22),
      'bike' => const Size(26, 26),
      _ => const Size(25, 25),
    };
    final body = settled ? const Color(0xFF34D399) : const Color(0xFFEDF1F9);
    final headingTurns = (headingDegrees ?? 0) / 360;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 52 + pulse * 8,
            height: 52 + pulse * 8,
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: .04),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF3B82F6).withValues(alpha: .24),
              ),
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withValues(alpha: .30),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
          if (!settled)
            Transform.rotate(
              angle: headingTurns * 6.283185307179586,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: 0,
                  height: 0,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Colors.transparent, width: 7),
                      right: BorderSide(color: Colors.transparent, width: 7),
                      bottom: BorderSide(color: Color(0x453B82F6), width: 14),
                    ),
                  ),
                ),
              ),
            ),
          Container(
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              color: body,
              borderRadius: BorderRadius.circular(kind == 'bike' ? 999 : 8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .88),
                  spreadRadius: 3,
                ),
                BoxShadow(
                  color: const Color(0xFF3B82F6).withValues(alpha: .48),
                  blurRadius: 14,
                ),
              ],
            ),
            child: CustomPaint(
              painter: _VehicleIconPainter(kind: kind, settled: settled),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleIconPainter extends CustomPainter {
  final String kind;
  final bool settled;

  const _VehicleIconPainter({required this.kind, required this.settled});

  @override
  void paint(Canvas canvas, Size size) {
    final dark = Paint()
      ..color = settled ? const Color(0xFF06281E) : const Color(0xFF0B0D14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillDark = Paint()
      ..color = settled ? const Color(0xFF06281E) : const Color(0xFF0B0D14);
    final accent = Paint()..color = const Color(0xFF3B82F6);

    if (kind == 'bike') {
      final wheelRadius = size.width * .18;
      final left = Offset(size.width * .24, size.height * .66);
      final right = Offset(size.width * .76, size.height * .66);
      canvas.drawCircle(left, wheelRadius, fillDark);
      canvas.drawCircle(right, wheelRadius, fillDark);
      canvas.drawCircle(left, wheelRadius * .42, accent);
      canvas.drawCircle(right, wheelRadius * .42, accent);
      final path = Path()
        ..moveTo(left.dx, left.dy)
        ..lineTo(size.width * .44, size.height * .28)
        ..lineTo(size.width * .62, size.height * .66)
        ..lineTo(right.dx, right.dy)
        ..moveTo(size.width * .44, size.height * .28)
        ..lineTo(size.width * .58, size.height * .28)
        ..moveTo(size.width * .62, size.height * .66)
        ..lineTo(size.width * .50, size.height * .42);
      canvas.drawPath(path, dark);
      canvas.drawCircle(
        Offset(size.width * .44, size.height * .28),
        1.8,
        fillDark,
      );
      return;
    }

    if (kind == 'car') {
      final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .12,
          size.height * .28,
          size.width * .76,
          size.height * .48,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(body, fillDark);
      final glass = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .32,
          size.height * .18,
          size.width * .36,
          size.height * .28,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(
          glass, accent..color = accent.color.withValues(alpha: .55));
      canvas.drawCircle(
        Offset(size.width * .30, size.height * .78),
        2.2,
        accent..color = const Color(0xFF3B82F6),
      );
      canvas.drawCircle(
          Offset(size.width * .70, size.height * .78), 2.2, accent);
      return;
    }

    if (kind == 'van') {
      final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .08,
          size.height * .20,
          size.width * .84,
          size.height * .56,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(body, fillDark);
      final glass = Rect.fromLTWH(
        size.width * .42,
        size.height * .26,
        size.width * .30,
        size.height * .28,
      );
      canvas.drawRect(
          glass, accent..color = accent.color.withValues(alpha: .55));
      canvas.drawCircle(
        Offset(size.width * .30, size.height * .78),
        2.3,
        accent..color = const Color(0xFF3B82F6),
      );
      canvas.drawCircle(
          Offset(size.width * .72, size.height * .78), 2.3, accent);
      return;
    }

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.shortestSide * .32,
      fillDark,
    );
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '?',
        style: TextStyle(
          color: Color(0xFF3B82F6),
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _VehicleIconPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.settled != settled;
}

class _RouteLine extends StatelessWidget {
  final bool completed;
  final bool highContrast;

  const _RouteLine({this.completed = false, this.highContrast = false});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: completed ? .74 : 1, end: 1),
        duration: Duration(milliseconds: completed ? 400 : 0),
        curve: Curves.easeOut,
        builder: (context, value, _) {
          return CustomPaint(
            painter: _RouteLinePainter(
              progress: value,
              completed: completed,
              highContrast: highContrast,
            ),
          );
        },
      ),
    );
  }
}

class _TrackingGridPainter extends CustomPainter {
  final double shimmer;
  final bool route;
  final bool searching;
  final bool highContrast;

  const _TrackingGridPainter({
    required this.shimmer,
    required this.route,
    this.searching = false,
    this.highContrast = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: highContrast ? .12 : .025)
      ..strokeWidth = highContrast ? 1.35 : 1;
    for (double x = -28; x < size.width + 28; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = -28; y < size.height + 28; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF3B82F6).withValues(
            alpha: searching
                ? (highContrast ? .30 : .16)
                : (highContrast ? .22 : .10),
          ),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * (.35 + shimmer * .12), size.height * .25),
          radius: size.width * .55,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant _TrackingGridPainter oldDelegate) =>
      oldDelegate.shimmer != shimmer ||
      oldDelegate.route != route ||
      oldDelegate.searching != searching ||
      oldDelegate.highContrast != highContrast;
}

class _SearchRingsPainter extends CustomPainter {
  final double progress;
  final bool highContrast;

  const _SearchRingsPainter({
    required this.progress,
    this.highContrast = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .19, size.height * .31);
    for (var i = 0; i < 3; i += 1) {
      final phase = (progress + i / 3) % 1;
      final radius = size.shortestSide * (.10 + phase * .44);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = highContrast ? 1.6 : 1.1
        ..color = const Color(0xFF3B82F6).withValues(
          alpha: (1 - phase) * (highContrast ? .34 : .20),
        );
      canvas.drawCircle(center, radius, paint);
    }

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = highContrast ? 2.2 : 1.5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF60A5FA).withValues(
        alpha: highContrast ? .46 : .28,
      );
    final rect = Rect.fromCircle(
      center: center,
      radius: size.shortestSide * .32,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2 + progress * math.pi * 2,
      math.pi * .42,
      false,
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant _SearchRingsPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.highContrast != highContrast;
}

class _RouteLinePainter extends CustomPainter {
  final double progress;
  final bool completed;
  final bool highContrast;

  const _RouteLinePainter({
    required this.progress,
    required this.completed,
    this.highContrast = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .20, size.height * .32)
      ..quadraticBezierTo(
        size.width * .48,
        size.height * .42,
        size.width * .74,
        size.height * .66,
      );
    final metrics = path.computeMetrics().toList(growable: false);
    final visiblePath = Path();
    for (final metric in metrics) {
      visiblePath.addPath(
        metric.extractPath(0, metric.length * progress.clamp(0, 1)),
        Offset.zero,
      );
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = highContrast ? 5 : 3
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: highContrast
            ? const [
                Color(0xFF34D399),
                Color(0xFF60A5FA),
                Color(0xFF34D399),
              ]
            : const [
                Color(0x2234D399),
                Color(0xFF3B82F6),
                Color(0xFF34D399),
              ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(visiblePath, paint);
  }

  @override
  bool shouldRepaint(covariant _RouteLinePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.completed != completed ||
      oldDelegate.highContrast != highContrast;
}

BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white.withValues(alpha: .035),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: .07)),
    );

String? _firstName(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.split(RegExp(r'\s+')).first;
}

String _formatPin(String value) {
  final cleaned = value.replaceAll(RegExp(r'\s+'), '');
  if (cleaned.length == 6) {
    return '${cleaned.substring(0, 3)} ${cleaned.substring(3)}';
  }
  return cleaned.split('').join(' ');
}

class _TrackingTokens {
  static const muted = Color(0xFF8B93A7);
  static const mid = Color(0xFFB7BECD);
}
