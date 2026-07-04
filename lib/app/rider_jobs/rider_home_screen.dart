import 'dart:ui' as ui;
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'rider_accept_controller.dart';
import 'rider_home_state_mapper.dart';
import 'rider_iris_orb.dart';
import 'rider_job_models.dart';
import 'rider_offer_stack.dart';
import 'rider_points_rules.dart';
import 'rider_presence_controller.dart';
import 'rider_route_map_layer.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  static const _heartbeatInterval = Duration(seconds: 60);

  bool _goingOnline = false;
  bool _goingOffline = false;
  bool _accepting = false;
  String? _message;
  Timer? _heartbeatTimer;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  RiderPresenceController get _presenceController =>
      RiderPresenceController(functions: FirebaseFunctions.instance);

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFF07090F),
      body: Stack(
        children: [
          const Positioned.fill(child: RiderRouteMapLayer()),
          const Positioned.fill(child: _MapShade()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: user == null
                    ? const Stream.empty()
                    : _firestore
                        .collection('riderPresence')
                        .doc(user.uid)
                        .snapshots(),
                builder: (context, presenceSnapshot) {
                  final presence = presenceSnapshot.data?.data() ?? {};
                  _syncHeartbeat(presence);
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _offersStream(
                      riderId: user?.uid,
                      presence: presence,
                    ),
                    builder: (context, snapshot) {
                      final offers = _offersFromSnapshot(snapshot);
                      final profile = _profileFromPresence(presence);
                      final loading = user != null &&
                          (presenceSnapshot.connectionState ==
                                  ConnectionState.waiting ||
                              snapshot.connectionState ==
                                  ConnectionState.waiting);
                      final state = RiderHomeStateMapper.fromBackend(
                        riderProfile: profile,
                        presence: presence,
                        hasAvailableOffers: offers.isNotEmpty,
                        localGoingOnline: _goingOnline || _goingOffline,
                        loading: loading,
                      );
                      return Column(
                        children: [
                          _TopStatus(
                            title: RiderHomeStateMapper.titleFor(
                              state,
                              firstName: user?.displayName?.split(' ').first ??
                                  'Jason',
                            ),
                            copy: RiderHomeStateMapper.copyFor(state),
                          ),
                          const Spacer(),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            child: state == RiderJobUiState.offerAvailable
                                ? RiderOfferStack(
                                    key: const ValueKey('offer-stack'),
                                    offers: offers,
                                    accepting: _accepting,
                                    onAccept: (offer) => _acceptOffer(
                                      offer,
                                      user: user,
                                      riderProfile: profile,
                                    ),
                                  )
                                : _HomeStateSheet(
                                    key: ValueKey(state.name),
                                    state: state,
                                    message: _message,
                                    onPrimaryAction:
                                        state == RiderJobUiState.onlineWaiting
                                            ? _goOffline
                                            : _goOnline,
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<RiderJobOffer> _offersFromSnapshot(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (!snapshot.hasData) return const [];
    final docs = snapshot.data!.docs;
    final offers = docs
        .map((doc) => RiderJobOffer.fromMap({...doc.data(), 'id': doc.id}))
        .where((offer) {
      final ignored = offer.raw['ignoredByRiders'];
      final rejected = offer.raw['rejectedByRiders'];
      final riderId = FirebaseAuth.instance.currentUser?.uid;
      return riderId == null ||
          !((ignored is Iterable && ignored.contains(riderId)) ||
              (rejected is Iterable && rejected.contains(riderId)));
    }).toList();
    return offers;
  }

  Future<void> _goOnline() async {
    setState(() {
      _goingOnline = true;
      _message = null;
    });
    final message = await _presenceController.goOnline();
    if (mounted) {
      setState(() {
        _goingOnline = false;
        _message = message ?? 'You are online and available.';
      });
      _startHeartbeat();
    }
  }

  Future<void> _goOffline() async {
    setState(() {
      _goingOffline = true;
      _message = null;
    });
    final message = await _presenceController.goOffline();
    if (mounted) {
      _stopHeartbeat();
      setState(() {
        _goingOffline = false;
        _message = message ?? 'You are offline.';
      });
    }
  }

  Future<void> _acceptOffer(
    RiderJobOffer offer, {
    required User? user,
    required Map<String, dynamic> riderProfile,
  }) async {
    if (user == null) {
      setState(() => _message = 'Sign in before accepting deliveries.');
      return;
    }
    setState(() {
      _accepting = true;
      _message = null;
    });
    final controller = RiderAcceptController();
    final result = await controller.acceptDelivery(
      deliveryId: offer.id,
      riderId: user.uid,
      riderName: user.displayName ?? 'Circum Rider',
      email: user.email,
      riderProfile: riderProfile,
      vehicle: offer.vehicleLabel,
    );
    if (!mounted) return;
    setState(() {
      _accepting = false;
      _message = result.message;
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _offersStream({
    required String? riderId,
    required Map<String, dynamic> presence,
  }) {
    final available = presence['isOnline'] == true &&
        presence['availabilityStatus'] == 'available' &&
        presence['busy'] != true;
    if (riderId == null || !available) return const Stream.empty();
    return _firestore
        .collection('deliveryRequests')
        .where('status', isEqualTo: 'requested')
        .limit(20)
        .snapshots();
  }

  void _syncHeartbeat(Map<String, dynamic> presence) {
    final online = presence['isOnline'] == true;
    if (online) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }
  }

  void _startHeartbeat() {
    if (_heartbeatTimer?.isActive == true) return;
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _presenceController.updateHeartbeat();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Map<String, dynamic> _profileFromPresence(Map<String, dynamic> presence) {
    return {
      'onboardingStatus': 'approved',
      'approvalStatus': 'approved',
      'isOnline': presence['isOnline'] == true,
      'availability': presence['availabilityStatus'],
      'riderRank': presence['riderRank'] ?? 'Sentinel',
    };
  }
}

class _TopStatus extends StatelessWidget {
  final String title;
  final String copy;

  const _TopStatus({required this.title, required this.copy});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Row(
        children: [
          const RiderIrisOrb(size: 46, state: RiderIrisOrbState.beckon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  copy,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .64),
                    height: 1.35,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeStateSheet extends StatelessWidget {
  final RiderJobUiState state;
  final String? message;
  final VoidCallback onPrimaryAction;

  const _HomeStateSheet({
    super.key,
    required this.state,
    required this.message,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final completed = state == RiderJobUiState.completed;
    final deliveryUpdate = state == RiderJobUiState.deliveryUpdate;
    final award = RiderPointsRules.awardFor(
      completed ? {RiderJobCategory.healthPlus} : const {},
    );
    return _GlassPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RiderIrisOrb(
                state: completed
                    ? RiderIrisOrbState.verified
                    : RiderIrisOrbState.rest,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  deliveryUpdate
                      ? 'Continue following instructions.'
                      : completed
                          ? '+${award.points} Trust Points'
                          : 'Today is ready when you are.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetricRow(
            values: const [
              ('£0.00', 'Today'),
              ('Sentinel', 'Rank'),
              ('0', 'Trust'),
            ],
          ),
          if (state == RiderJobUiState.pendingApproval) ...[
            const SizedBox(height: 16),
            const _Checklist(),
          ],
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(
              message!,
              style: const TextStyle(
                color: Color(0xFF60A5FA),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: state == RiderJobUiState.pendingApproval
                  ? null
                  : onPrimaryAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                state == RiderJobUiState.onlineWaiting
                    ? 'Go Offline'
                    : completed
                        ? 'Go Online Again'
                        : 'Go Online',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final List<(String, String)> values;

  const _MetricRow({required this.values});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: values.map((value) {
        return Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value.$1,
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                value.$2,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .52),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist();

  @override
  Widget build(BuildContext context) {
    const items = [
      'Phone verification',
      'Identity document',
      'Right to work',
      'Admin approval',
    ];
    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.radio_button_unchecked,
                    size: 15,
                    color: Color(0xFF60A5FA),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;

  const _GlassPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .075),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: .16)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _MapShade extends StatelessWidget {
  const _MapShade();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF07090F).withValues(alpha: .35),
            Colors.transparent,
            const Color(0xFF07090F).withValues(alpha: .90),
          ],
        ),
      ),
    );
  }
}
