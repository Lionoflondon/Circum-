import 'dart:async';
import 'dart:ui' as ui;

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

  int _tab = 0;
  bool _updatingAvailability = false;
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
                final online = presence['isOnline'] == true;
                final available = online &&
                    presence['availabilityStatus'] == 'available' &&
                    presence['busy'] != true &&
                    '${presence['activeDeliveryId'] ?? presence['currentDeliveryId'] ?? ''}'
                        .trim()
                        .isEmpty;
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _riderProfileStream(user?.uid),
                  builder: (context, profileSnapshot) {
                    final profile = _profileFromBackend(
                      profileSnapshot.data?.data(),
                      presence,
                    );
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _activeDeliveryStream(user?.uid),
                      builder: (context, activeSnapshot) {
                        final activeDelivery =
                            _firstJobFromSnapshot(activeSnapshot);
                        return StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>>(
                          stream: _offersStream(
                            riderId: user?.uid,
                            presence: presence,
                            limit: _tab == 1 ? 20 : 3,
                          ),
                          builder: (context, offersSnapshot) {
                            final offers = _offersFromSnapshot(offersSnapshot);
                            final state = RiderHomeStateMapper.fromBackend(
                              riderProfile: profile,
                              activeDelivery: activeDelivery,
                              presence: presence,
                              hasAvailableOffers: offers.isNotEmpty,
                              localGoingOnline: _updatingAvailability,
                              loading: user != null &&
                                  presenceSnapshot.connectionState ==
                                      ConnectionState.waiting,
                            );
                            return StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>>(
                              stream: user == null
                                  ? const Stream.empty()
                                  : _firestore
                                      .collection('riderEarnings')
                                      .doc(user.uid)
                                      .snapshots(),
                              builder: (context, earningsSnapshot) {
                                final earnings =
                                    earningsSnapshot.data?.data() ?? {};
                                return StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _scheduledStream(user?.uid),
                                  builder: (context, scheduledSnapshot) {
                                    final scheduled = _jobsFromSnapshot(
                                      scheduledSnapshot,
                                      limit: 1,
                                    );
                                    return StreamBuilder<
                                        QuerySnapshot<Map<String, dynamic>>>(
                                      stream: _recentStream(user?.uid),
                                      builder: (context, recentSnapshot) {
                                        final recent = _jobsFromSnapshot(
                                          recentSnapshot,
                                          limit: 2,
                                        );
                                        return StreamBuilder<
                                            QuerySnapshot<
                                                Map<String, dynamic>>>(
                                          stream: _unreadNotificationsStream(
                                              user?.uid),
                                          builder:
                                              (context, notificationSnapshot) {
                                            final unread = notificationSnapshot
                                                    .data?.docs.length ??
                                                0;
                                            final loading = presenceSnapshot
                                                        .connectionState ==
                                                    ConnectionState.waiting &&
                                                user != null;
                                            return Column(
                                              children: [
                                                Expanded(
                                                  child: AnimatedSwitcher(
                                                    duration: const Duration(
                                                        milliseconds: 240),
                                                    child: _tab == 1
                                                        ? _OffersPane(
                                                            key: const ValueKey(
                                                                'offers'),
                                                            offers: offers,
                                                            accepting:
                                                                _accepting,
                                                            onAccept: (offer) =>
                                                                _acceptOffer(
                                                              offer,
                                                              user: user,
                                                              riderProfile:
                                                                  profile,
                                                            ),
                                                          )
                                                        : _DashboardPane(
                                                            key: const ValueKey(
                                                                'dashboard'),
                                                            user: user,
                                                            state: state,
                                                            profile: profile,
                                                            presence: presence,
                                                            earnings: earnings,
                                                            offers: offers,
                                                            scheduled:
                                                                scheduled,
                                                            recent: recent,
                                                            unreadNotifications:
                                                                unread,
                                                            message: _message,
                                                            loading: loading,
                                                            updating:
                                                                _updatingAvailability,
                                                            online: online,
                                                            available:
                                                                available,
                                                            onToggleAvailability:
                                                                _toggleAvailability,
                                                            onOpenTab: _openTab,
                                                          ),
                                                  ),
                                                ),
                                                _RiderBottomNav(
                                                  selected: _tab,
                                                  online: online,
                                                  updating:
                                                      _updatingAvailability,
                                                  onSelect: _openTab,
                                                  onCentralTap:
                                                      _toggleAvailability,
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _riderProfileStream(
    String? uid,
  ) {
    if (uid == null) return const Stream.empty();
    return _firestore.collection('riderProfiles').doc(uid).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _activeDeliveryStream(
    String? uid,
  ) {
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('deliveryRequests')
        .where('riderId', isEqualTo: uid)
        .where('status', whereIn: const [
          'accepted',
          'navigating_to_pickup',
          'arrived_at_pickup',
          'waiting',
          'pickup_verification',
          'pickup_verified',
          'collected',
          'navigating_to_dropoff',
          'arrived_at_dropoff',
          'pin_required',
          'issue_reported',
        ])
        .limit(1)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _unreadNotificationsStream(
    String? uid,
  ) {
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: uid)
        .where('recipientRole', isEqualTo: 'rider')
        .where('read', isEqualTo: false)
        .limit(20)
        .snapshots();
  }

  void _openTab(int index) {
    if (index == 2) {
      _toggleAvailability();
      return;
    }
    if (index == 3 || index == 4) {
      setState(() {
        _tab = index;
        _message = index == 3
            ? 'Earnings opens from the existing rider finance route when wired.'
            : 'Profile opens from the existing rider profile route when wired.';
      });
      return;
    }
    setState(() => _tab = index);
  }

  Future<void> _toggleAvailability() async {
    final online = await _currentOnlineState();
    setState(() {
      _updatingAvailability = true;
      _message = null;
    });
    final message = online
        ? await _presenceController.goOffline()
        : await _presenceController.goOnline();
    if (!mounted) return;
    if (online) {
      _stopHeartbeat();
    } else if (message == null) {
      _startHeartbeat();
    }
    setState(() {
      _updatingAvailability = false;
      _message = message ?? (online ? 'You are offline.' : 'You are online.');
    });
  }

  Future<bool> _currentOnlineState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final snapshot =
        await _firestore.collection('riderPresence').doc(uid).get();
    return snapshot.data()?['isOnline'] == true;
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
    final result = await RiderAcceptController().acceptDelivery(
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
    required int limit,
  }) {
    final available = presence['isOnline'] == true &&
        presence['availabilityStatus'] == 'available' &&
        presence['busy'] != true &&
        '${presence['activeDeliveryId'] ?? presence['currentDeliveryId'] ?? ''}'
            .trim()
            .isEmpty;
    if (riderId == null || !available) return const Stream.empty();
    return _firestore
        .collection('deliveryRequests')
        .where('status', isEqualTo: 'requested')
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _scheduledStream(String? uid) {
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('deliveryRequests')
        .where('riderId', isEqualTo: uid)
        .where('status', isEqualTo: 'scheduled')
        .limit(1)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _recentStream(String? uid) {
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('deliveryRequests')
        .where('riderId', isEqualTo: uid)
        .where('status', isEqualTo: 'delivered')
        .limit(2)
        .snapshots();
  }

  List<RiderJobOffer> _offersFromSnapshot(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (!snapshot.hasData) return const [];
    final riderId = FirebaseAuth.instance.currentUser?.uid;
    return snapshot.data!.docs
        .map((doc) => RiderJobOffer.fromMap({...doc.data(), 'id': doc.id}))
        .where((offer) {
      final ignored = offer.raw['ignoredByRiders'];
      final rejected = offer.raw['rejectedByRiders'];
      return riderId == null ||
          !((ignored is Iterable && ignored.contains(riderId)) ||
              (rejected is Iterable && rejected.contains(riderId)));
    }).toList();
  }

  List<Map<String, dynamic>> _jobsFromSnapshot(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot, {
    required int limit,
  }) {
    if (!snapshot.hasData) return const [];
    return snapshot.data!.docs
        .take(limit)
        .map((doc) => {...doc.data(), 'id': doc.id})
        .toList();
  }

  Map<String, dynamic>? _firstJobFromSnapshot(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return null;
    final doc = snapshot.data!.docs.first;
    return {...doc.data(), 'id': doc.id};
  }

  void _syncHeartbeat(Map<String, dynamic> presence) {
    if (presence['isOnline'] == true) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }
  }

  void _startHeartbeat() {
    if (_heartbeatTimer?.isActive == true) return;
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => _presenceController.updateHeartbeat(),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Map<String, dynamic> _profileFromBackend(
    Map<String, dynamic>? profile,
    Map<String, dynamic> presence,
  ) {
    return {
      ...?profile,
      'isOnline': presence['isOnline'] == true,
      'availability':
          presence['availabilityStatus'] ?? profile?['availability'],
      'riderRank': profile?['riderRank'] ?? profile?['rank'],
      'trustPoints': profile?['trustPoints'],
    };
  }
}

class _DashboardPane extends StatelessWidget {
  final User? user;
  final RiderJobUiState state;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> presence;
  final Map<String, dynamic> earnings;
  final List<RiderJobOffer> offers;
  final List<Map<String, dynamic>> scheduled;
  final List<Map<String, dynamic>> recent;
  final int unreadNotifications;
  final String? message;
  final bool loading;
  final bool updating;
  final bool online;
  final bool available;
  final VoidCallback onToggleAvailability;
  final ValueChanged<int> onOpenTab;

  const _DashboardPane({
    super.key,
    required this.user,
    required this.state,
    required this.profile,
    required this.presence,
    required this.earnings,
    required this.offers,
    required this.scheduled,
    required this.recent,
    required this.unreadNotifications,
    required this.message,
    required this.loading,
    required this.updating,
    required this.online,
    required this.available,
    required this.onToggleAvailability,
    required this.onOpenTab,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = _firstName;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      children: [
        _GreetingCard(
          firstName: firstName,
          unread: unreadNotifications,
        ),
        const SizedBox(height: 14),
        if (loading)
          const _DashboardLoadingCard()
        else
          _OnlineStatusCard(
            online: online,
            available: available,
            updating: updating,
            state: state,
            onTap: onToggleAvailability,
          ),
        if (message != null) ...[
          const SizedBox(height: 10),
          _InfoStrip(message: message!),
        ],
        const SizedBox(height: 14),
        _RankCard(profile: profile),
        const SizedBox(height: 14),
        _TodaySummary(earnings: earnings),
        const SizedBox(height: 14),
        _PriorityOpportunities(offers: offers),
        const SizedBox(height: 14),
        _ScheduledJobCard(job: scheduled.isEmpty ? null : scheduled.first),
        const SizedBox(height: 14),
        _RecentDeliveriesCard(jobs: recent),
        const SizedBox(height: 14),
        _QuickActions(onOpenTab: onOpenTab),
      ],
    );
  }

  String get _firstName {
    final display = user?.displayName?.trim();
    if (display != null && display.isNotEmpty) {
      return display.split(RegExp(r'\s+')).first;
    }
    return 'Rider';
  }
}

class _OffersPane extends StatelessWidget {
  final List<RiderJobOffer> offers;
  final bool accepting;
  final ValueChanged<RiderJobOffer> onAccept;

  const _OffersPane({
    super.key,
    required this.offers,
    required this.accepting,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      children: [
        const _SectionHeader(
          title: 'Offers',
          subtitle:
              'Swipe to view eligible deliveries. Accept only when ready.',
        ),
        const SizedBox(height: 14),
        RiderOfferStack(
          offers: offers,
          accepting: accepting,
          onAccept: onAccept,
        ),
      ],
    );
  }
}

class _GreetingCard extends StatelessWidget {
  final String firstName;
  final int unread;

  const _GreetingCard({required this.firstName, required this.unread});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good morning, $firstName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ready to deliver',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .62),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Semantics(
          label: 'Notifications',
          button: true,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const _CircleIcon(icon: Icons.notifications_none_rounded),
              if (unread > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF4D5E),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OnlineStatusCard extends StatelessWidget {
  final bool online;
  final bool available;
  final bool updating;
  final RiderJobUiState state;
  final VoidCallback onTap;

  const _OnlineStatusCard({
    required this.online,
    required this.available,
    required this.updating,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = online ? 'ONLINE' : 'OFFLINE';
    final status = online
        ? available
            ? 'Available for dispatch'
            : 'Busy or unavailable'
        : 'Tap to start receiving jobs';
    return _GlassPanel(
      child: Semantics(
        label: online
            ? 'You are online. Tap to go offline.'
            : 'You are offline. Tap to go online.',
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: updating ? null : onTap,
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online
                      ? const Color(0xFF22C55E).withValues(alpha: .18)
                      : Colors.white.withValues(alpha: .06),
                  border: Border.all(
                    color: online
                        ? const Color(0xFF22C55E)
                        : Colors.white.withValues(alpha: .20),
                  ),
                ),
                child: updating
                    ? const Padding(
                        padding: EdgeInsets.all(15),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        online ? Icons.power_settings_new : Icons.power_off,
                        color:
                            online ? const Color(0xFF22C55E) : Colors.white70,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      updating ? 'Updating availability…' : status,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .62),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  final Map<String, dynamic> profile;

  const _RankCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final rank = '${profile['riderRank'] ?? profile['rank'] ?? ''}'.trim();
    final points = (profile['trustPoints'] as num?)?.toInt() ?? 0;
    if (rank.isEmpty && points <= 0) {
      return const _GlassPanel(
        child: _EmptyLine('Build trust with every delivery.'),
      );
    }
    final rankLabel = rank.isEmpty ? 'Agent' : rank;
    final next = _nextRank(rankLabel);
    final threshold = _rankThreshold(next);
    final previous = _rankThreshold(rankLabel);
    final progress = threshold <= previous
        ? 0.0
        : ((points - previous) / (threshold - previous)).clamp(0.0, 1.0);
    final remaining = (threshold - points).clamp(0, 99999);
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const RiderIrisOrb(size: 42, state: RiderIrisOrbState.verified),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  rank.isEmpty ? 'Build trust with every delivery.' : rank,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const _TinyPill(label: 'CURRENT RANK', color: Color(0xFF2563EB)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: .10),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF60A5FA)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            next == rank
                ? 'Top rank active'
                : '$remaining points to next rank · $next',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .64),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static String _nextRank(String rank) {
    const ranks = ['Agent', 'Sentinel', 'Warden', 'Knight', 'Veteran'];
    final index =
        ranks.indexWhere((item) => item.toLowerCase() == rank.toLowerCase());
    if (index < 0) return 'Sentinel';
    return ranks[(index + 1).clamp(0, ranks.length - 1)];
  }

  static int _rankThreshold(String rank) {
    return switch (rank.toLowerCase()) {
      'agent' => 0,
      'sentinel' => 100,
      'warden' => 300,
      'knight' => 700,
      'veteran' => 1200,
      _ => 100,
    };
  }
}

class _TodaySummary extends StatelessWidget {
  final Map<String, dynamic> earnings;

  const _TodaySummary({required this.earnings});

  @override
  Widget build(BuildContext context) {
    final today =
        ((earnings['todayEarnings'] ?? earnings['availableToday'] ?? 0) as num)
            .toDouble();
    final jobs = (earnings['todayCompletedJobs'] as num?)?.toInt() ?? 0;
    final trust = (earnings['todayTrustPoints'] as num?)?.toInt() ?? 0;
    return _MetricGlassGrid(
      title: 'Today',
      items: [
        ('£${today.toStringAsFixed(2)}', 'Earnings'),
        ('$jobs', 'Jobs completed'),
        ('$trust', 'Trust points'),
      ],
    );
  }
}

class _PriorityOpportunities extends StatelessWidget {
  final List<RiderJobOffer> offers;

  const _PriorityOpportunities({required this.offers});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Priority Opportunities',
            subtitle: 'Health+, gifts and scheduled jobs surface here.',
          ),
          const SizedBox(height: 12),
          if (offers.isEmpty)
            const _EmptyLine('No priority opportunities right now.')
          else
            SizedBox(
              height: 116,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: offers.take(3).length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final offer = offers[index];
                  final award = RiderPointsRules.awardFor(offer.categories);
                  return _MiniOpportunityCard(offer: offer, award: award);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniOpportunityCard extends StatelessWidget {
  final RiderJobOffer offer;
  final RiderPointsAward award;

  const _MiniOpportunityCard({required this.offer, required this.award});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TinyPill(label: award.label, color: const Color(0xFF3B82F6)),
          const Spacer(),
          Text(
            '£${offer.estimatedEarnings.toStringAsFixed(2)} · +${award.points} Trust',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '${offer.pickupArea} → ${offer.dropoffArea}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .62),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledJobCard extends StatelessWidget {
  final Map<String, dynamic>? job;

  const _ScheduledJobCard({required this.job});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Upcoming Scheduled Job',
            subtitle: 'Your next commitment.',
            trailing: 'View all',
          ),
          const SizedBox(height: 12),
          if (job == null)
            const _EmptyLine('No scheduled jobs yet.')
          else
            _DeliverySummaryLine(job: job!, badge: 'Scheduled'),
        ],
      ),
    );
  }
}

class _RecentDeliveriesCard extends StatelessWidget {
  final List<Map<String, dynamic>> jobs;

  const _RecentDeliveriesCard({required this.jobs});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Recent Deliveries',
            subtitle: 'Last completed jobs.',
            trailing: 'View all',
          ),
          const SizedBox(height: 12),
          if (jobs.isEmpty)
            const _EmptyLine('Completed deliveries will appear here.')
          else
            ...jobs.map((job) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DeliverySummaryLine(job: job, badge: 'Completed'),
                )),
        ],
      ),
    );
  }
}

class _DeliverySummaryLine extends StatelessWidget {
  final Map<String, dynamic> job;
  final String badge;

  const _DeliverySummaryLine({required this.job, required this.badge});

  @override
  Widget build(BuildContext context) {
    final offer = RiderJobOffer.fromMap(job);
    final award = RiderPointsRules.awardFor(offer.categories);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${offer.pickupArea} → ${offer.dropoffArea}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  '${offer.parcelSummary} · ${offer.pickupTimingLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .58),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _TinyPill(label: badge, color: const Color(0xFF2563EB)),
              const SizedBox(height: 6),
              Text(
                '£${offer.estimatedEarnings.toStringAsFixed(2)} · +${award.points}',
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final ValueChanged<int> onOpenTab;

  const _QuickActions({required this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.payments_outlined, 'Earnings', 3),
      (Icons.calendar_month_outlined, 'Schedule', 0),
      (Icons.account_balance_wallet_outlined, 'Wallet', 3),
      (Icons.verified_user_outlined, 'Trust Profile', 4),
      (Icons.support_agent_outlined, 'Support', 4),
    ];
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
              title: 'Quick Actions', subtitle: 'Jump into rider tools.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: actions.map((action) {
              return _QuickActionButton(
                icon: action.$1,
                label: action.$2,
                onTap: () => onOpenTab(action.$3),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _RiderBottomNav extends StatelessWidget {
  final int selected;
  final bool online;
  final bool updating;
  final ValueChanged<int> onSelect;
  final VoidCallback onCentralTap;

  const _RiderBottomNav({
    required this.selected,
    required this.online,
    required this.updating,
    required this.onSelect,
    required this.onCentralTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: _GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                active: selected == 0,
                onTap: () => onSelect(0)),
            _NavItem(
                icon: Icons.layers_rounded,
                label: 'Offers',
                active: selected == 1,
                onTap: () => onSelect(1)),
            Expanded(
              child: Semantics(
                button: true,
                label: online ? 'Go offline' : 'Go online',
                child: InkWell(
                  onTap: updating ? null : onCentralTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: (online
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF3B82F6))
                          .withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Center(
                      child: updating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              online ? 'Online' : 'Go Online',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            _NavItem(
                icon: Icons.payments_rounded,
                label: 'Earnings',
                active: selected == 3,
                onTap: () => onSelect(3)),
            _NavItem(
                icon: Icons.person_rounded,
                label: 'Profile',
                active: selected == 4,
                onTap: () => onSelect(4)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 54,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: active ? const Color(0xFF60A5FA) : Colors.white54,
                  size: 20),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? const Color(0xFF60A5FA) : Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricGlassGrid extends StatelessWidget {
  final String title;
  final List<(String, String)> items;

  const _MetricGlassGrid({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: title, subtitle: 'Live rider summary.'),
          const SizedBox(height: 14),
          Row(
            children: items
                .map(
                  (item) => Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.$2,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .54),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? trailing;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .56),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              color: Color(0xFF60A5FA),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }
}

class _InfoStrip extends StatelessWidget {
  final String message;

  const _InfoStrip({required this.message});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF60A5FA),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DashboardLoadingCard extends StatelessWidget {
  const _DashboardLoadingCard();

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading dashboard',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .72),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;

  const _EmptyLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: .58),
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;

  const _CircleIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _TinyPill extends StatelessWidget {
  final String label;
  final Color color;

  const _TinyPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color == const Color(0xFF22C55E)
              ? Colors.white
              : const Color(0xFFEAF2FF),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .055),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
          ),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFF60A5FA), size: 22),
              const SizedBox(height: 7),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: .16)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withValues(alpha: .12),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
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
            const Color(0xFF07090F).withValues(alpha: .42),
            Colors.transparent,
            const Color(0xFF07090F).withValues(alpha: .94),
          ],
        ),
      ),
    );
  }
}
