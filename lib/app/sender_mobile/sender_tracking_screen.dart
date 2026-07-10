import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../send_package/bloc/send_package_bloc.dart';
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
    'waiting' =>
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
        body: 'Matching you with a nearby Circum rider.',
        pill: 'Matching',
        progress: 0,
        dimMap: true,
        showPickupPin: true,
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
        showReceiverPin: true,
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
        showReceiverPin: true,
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
        showReceiverPin: true,
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
        if (staleLabel != null) _StaleLocationPill(label: staleLabel),
        if (visibleContent.showRider && !delivered) const _RecenterButton(),
        if (delivered) const _DeliveredConfirmationOverlay(),
        FloatingGlassPanel(
          child: _TrackingPanelContent(
            state: state,
            content: visibleContent,
            engine: widget.engine,
            mapMode: mapMode,
          ),
        ),
      ],
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
                  highContrast: highContrast,
                ),
              ),
            ),
            if (content.showRoute)
              _RouteLine(completed: delivered, highContrast: highContrast),
            if (content.showPickupPin)
              _MapPin(
                alignment: const Alignment(-.62, -.38),
                color: const Color(0xFF34D399),
                pulse: markerPulse,
                strongPulse: content.showAnonymousRiders,
                highContrast: highContrast,
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
              _AnonymousRiderDot(alignment: Alignment(-.18, -.22), delay: 0),
              _AnonymousRiderDot(alignment: Alignment(.18, -.12), delay: 420),
              _AnonymousRiderDot(alignment: Alignment(.02, .14), delay: 840),
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

  const _TrackingPanelContent({
    required this.state,
    required this.content,
    required this.engine,
    required this.mapMode,
  });

  @override
  Widget build(BuildContext context) {
    if (state == SenderTrackingState.loading) return const _LoadingTracking();
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
        ProgressStepper(
          progress: content.progress,
          issue: content.issueVanguard,
          completed: state == SenderTrackingState.delivered,
        ),
        if (state == SenderTrackingState.findingRider) ...[
          const SizedBox(height: 8),
          const _FindingPulse(),
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
        if (content.showCollectionPin) ...[
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
        _TrackingActions(state: state),
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

  const _TrackingActions({required this.state});

  @override
  Widget build(BuildContext context) {
    final delivered = state == SenderTrackingState.delivered;
    final empty = state == SenderTrackingState.noActiveDelivery;
    return Row(
      children: [
        Expanded(
          child: _TrackingButton(
            label: empty
                ? 'Send a parcel'
                : delivered
                    ? 'View receipt'
                    : 'Message',
            primary: empty,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TrackingButton(
            label: delivered ? 'Done' : 'Support',
            primary: delivered || state == SenderTrackingState.issue,
            success: delivered,
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

  const _TrackingButton({
    required this.label,
    this.primary = false,
    this.success = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
                        color: const Color(0xFF34D399).withValues(alpha: .20),
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

class _FindingPulse extends StatelessWidget {
  const _FindingPulse();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 2400),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 22 + value * 88,
                  height: 22 + value * 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF3B82F6)
                          .withValues(alpha: (1 - value) * .45),
                    ),
                  ),
                ),
                child!,
              ],
            );
          },
          onEnd: () {},
          child: Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              color: Color(0xFF3B82F6),
              shape: BoxShape.circle,
            ),
          ),
        ),
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
            color: Colors.white.withValues(alpha: .82),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withValues(alpha: .26),
                blurRadius: 14,
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
  final bool highContrast;

  const _TrackingGridPainter({
    required this.shimmer,
    required this.route,
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
          const Color(0xFF3B82F6).withValues(alpha: highContrast ? .22 : .10),
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
