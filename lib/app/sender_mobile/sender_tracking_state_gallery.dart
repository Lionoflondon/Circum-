import 'package:flutter/material.dart';

import '../send_package/bloc/send_package_bloc.dart';
import '../send_package/models/delivery_data.m.dart';
import 'sender_tracking_screen.dart';

void main() {
  runApp(const SenderTrackingStateGallery());
}

class SenderTrackingStateGallery extends StatefulWidget {
  const SenderTrackingStateGallery({super.key});

  @override
  State<SenderTrackingStateGallery> createState() =>
      _SenderTrackingStateGalleryState();
}

class _SenderTrackingStateGalleryState
    extends State<SenderTrackingStateGallery> {
  SenderTrackingState _state = SenderTrackingState.noActiveDelivery;

  static final _engine = SendPackageState(
    deliveryStatus: DeliveryStatus.reconnectingWithRider,
    deliveryRequestStatus: 'accepted',
    pickupLocation: 'Marylebone',
    destinationLocation: 'Chelsea',
    deliveryData: DeliveryData(
      courierName: 'Maya Stone',
      phoneNumber: '+447000000000',
      typeOfVehicle: 'Bike',
      estimatedDeliveryTime: '7 min',
      plateNumber: '',
      code: '427158',
      deliveryPin: '835246',
      rating: '4.9',
      riderId: 'rider_1',
      photoURL: null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF07090F),
        body: Stack(
          children: [
            SenderMobileTrackingScreen(
              engine: _engine,
              stateOverride: _state,
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _StateRail(
                    selected: _state,
                    onState: (state) => setState(() => _state = state),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateRail extends StatelessWidget {
  final SenderTrackingState selected;
  final ValueChanged<SenderTrackingState> onState;

  const _StateRail({required this.selected, required this.onState});

  static const _states = [
    _GalleryState('None', SenderTrackingState.noActiveDelivery),
    _GalleryState('Loading', SenderTrackingState.loading),
    _GalleryState('Finding', SenderTrackingState.findingRider),
    _GalleryState('Assigned', SenderTrackingState.riderAssigned),
    _GalleryState('To pickup', SenderTrackingState.riderEnRouteToPickup),
    _GalleryState('Arrived', SenderTrackingState.riderArrivedAtPickup),
    _GalleryState('Collected', SenderTrackingState.pickupComplete),
    _GalleryState('Transit', SenderTrackingState.inTransit),
    _GalleryState('Drop-off', SenderTrackingState.riderArrivingAtDropoff),
    _GalleryState('Done', SenderTrackingState.delivered),
    _GalleryState('Cancelled', SenderTrackingState.cancelled),
    _GalleryState('Issue', SenderTrackingState.issue),
    _GalleryState('Error', SenderTrackingState.error),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xE607090F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in _states) ...[
            _StateButton(
              label: item.label,
              selected: selected == item.state,
              onTap: () => onState(item.state),
            ),
            if (item != _states.last) const SizedBox(height: 5),
          ],
        ],
      ),
    );
  }
}

class _GalleryState {
  final String label;
  final SenderTrackingState state;

  const _GalleryState(this.label, this.state);
}

class _StateButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StateButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF3B82F6)
              : Colors.white.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFF60A5FA)
                : Colors.white.withValues(alpha: .08),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFFB7BECD),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
