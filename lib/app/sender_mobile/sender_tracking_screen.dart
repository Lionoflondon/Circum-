import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../send_package/bloc/send_package_bloc.dart';

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
}

SenderTrackingState senderTrackingStateForEngine(SendPackageState engine) {
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

String senderCollectionPinStatusFor(SenderTrackingState state) {
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
    return Stack(
      children: [
        SenderTrackingMapLayer(
          content: content,
          mapDrift: _mapDrift,
          pulse: _pulse,
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
        FloatingGlassPanel(
          child: _TrackingPanelContent(
            state: state,
            content: content,
            engine: widget.engine,
          ),
        ),
      ],
    );
  }
}

class SenderTrackingMapLayer extends StatelessWidget {
  final SenderTrackingContent content;
  final Animation<double> mapDrift;
  final Animation<double> pulse;

  const SenderTrackingMapLayer({
    super.key,
    required this.content,
    required this.mapDrift,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([mapDrift, pulse]),
      builder: (context, _) {
        final drift = (mapDrift.value - .5) * 10;
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
                  shimmer: mapDrift.value,
                  route: content.showRoute,
                ),
              ),
            ),
            if (content.showRoute) const _RouteLine(),
            if (content.showPickupPin)
              _MapPin(
                alignment: const Alignment(-.62, -.38),
                color: const Color(0xFF34D399),
                pulse: pulse.value,
                strongPulse: content.showAnonymousRiders,
              ),
            if (content.showDropoffPin)
              _MapPin(
                alignment: const Alignment(.48, .34),
                color: const Color(0xFF3B82F6),
                pulse: pulse.value,
              ),
            if (content.showAnonymousRiders) ...const [
              _AnonymousRiderDot(alignment: Alignment(-.18, -.22), delay: 0),
              _AnonymousRiderDot(alignment: Alignment(.18, -.12), delay: 420),
              _AnonymousRiderDot(alignment: Alignment(.02, .14), delay: 840),
            ],
            if (content.showRider)
              AnimatedAlign(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                alignment: Alignment(
                  content.riderPosition.dx * 2 - 1,
                  content.riderPosition.dy * 2 - 1,
                ),
                child: _RiderMarker(pulse: pulse.value),
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .048),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFF3B82F6).withValues(alpha: .28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .34),
                      blurRadius: 34,
                      offset: const Offset(0, -10),
                    ),
                  ],
                ),
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

  const _TrackingPanelContent({
    required this.state,
    required this.content,
    required this.engine,
  });

  @override
  Widget build(BuildContext context) {
    if (state == SenderTrackingState.loading) return const _LoadingTracking();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          content.title,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'DM Serif Display',
            fontSize: 24,
            height: 1.15,
            fontWeight: FontWeight.w400,
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
            statusLabel: senderCollectionPinStatusFor(state),
            statusComplete: senderCollectionPinStatusFor(state).startsWith('✓'),
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
            statusLabel: senderReceiverPinStatusFor(state),
            statusComplete: senderReceiverPinStatusFor(state).startsWith('✓'),
            accent: const Color(0xFF34D399),
            icon: Icons.verified_outlined,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (content.showIris) const IRISChip(),
            if (content.showVanguard)
              VanguardChip(
                quiet: content.quietVanguard,
                issue: content.issueVanguard,
                completed: state == SenderTrackingState.delivered,
              ),
          ],
        ),
        const SizedBox(height: 16),
        _TrackingActions(state: state),
      ],
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: primary
            ? success
                ? const Color(0xFF34D399)
                : const Color(0xFF3B82F6)
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
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: primary ? Colors.white : const Color(0xFFF2F4F8),
          fontWeight: FontWeight.w700,
          fontSize: 13,
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

class _MapPin extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final double pulse;
  final bool strongPulse;

  const _MapPin({
    required this.alignment,
    required this.color,
    required this.pulse,
    this.strongPulse = false,
  });

  @override
  Widget build(BuildContext context) {
    final ring = strongPulse ? 8 + pulse * 24 : 6.0;
    return Align(
      alignment: alignment,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: strongPulse ? .32 : .18),
              spreadRadius: ring,
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

class _RiderMarker extends StatelessWidget {
  final double pulse;

  const _RiderMarker({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: .12),
            spreadRadius: 8 + pulse * 3,
            blurRadius: 18,
          ),
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: .55),
            blurRadius: 16,
          ),
        ],
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(painter: _RouteLinePainter()),
    );
  }
}

class _TrackingGridPainter extends CustomPainter {
  final double shimmer;
  final bool route;

  const _TrackingGridPainter({required this.shimmer, required this.route});

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = 1;
    for (double x = -28; x < size.width + 28; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = -28; y < size.height + 28; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF3B82F6).withValues(alpha: .10),
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
      oldDelegate.shimmer != shimmer || oldDelegate.route != route;
}

class _RouteLinePainter extends CustomPainter {
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
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0x223B82F6), Color(0xFF3B82F6), Color(0x223B82F6)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
