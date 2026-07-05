import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../rider_marketplace/rider_onboarding_policy.dart';
import 'rider_accept_controller.dart';
import 'rider_home_state_mapper.dart';
import 'rider_iris_orb.dart';
import 'rider_job_models.dart';
import 'rider_offer_stack.dart';
import 'rider_points_rules.dart';
import 'rider_presence_controller.dart';
import 'rider_route_map_layer.dart';

class RiderHomeScreen extends StatefulWidget {
  final int initialTab;
  final bool enableLocalPreview;
  final Map<String, dynamic> localPreviewProfile;
  final Map<String, dynamic> localPreviewPresence;
  final Map<String, dynamic> localPreviewEarnings;
  final Map<String, dynamic> localPreviewRothWallet;
  final List<Map<String, dynamic>> localPreviewTransactions;
  final List<Map<String, dynamic>> localPreviewPayouts;
  final List<Map<String, dynamic>> localPreviewReferrals;

  const RiderHomeScreen({
    super.key,
    this.initialTab = 0,
    this.enableLocalPreview = false,
    this.localPreviewProfile = const {},
    this.localPreviewPresence = const {},
    this.localPreviewEarnings = const {},
    this.localPreviewRothWallet = const {},
    this.localPreviewTransactions = const [],
    this.localPreviewPayouts = const [],
    this.localPreviewReferrals = const [],
  });

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
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null && _localPreviewAllowed) {
      return _buildLocalPreview(context);
    }
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
                                                        : _tab == 3
                                                            ? _FinanceHubPane(
                                                                key: const ValueKey(
                                                                    'finance'),
                                                                user: user,
                                                                profile:
                                                                    profile,
                                                                earnings:
                                                                    earnings,
                                                                firestore:
                                                                    _firestore,
                                                                onOpenTab:
                                                                    _openTab,
                                                              )
                                                            : _DashboardPane(
                                                                key: const ValueKey(
                                                                    'dashboard'),
                                                                user: user,
                                                                state: state,
                                                                profile:
                                                                    profile,
                                                                presence:
                                                                    presence,
                                                                earnings:
                                                                    earnings,
                                                                offers: offers,
                                                                scheduled:
                                                                    scheduled,
                                                                recent: recent,
                                                                unreadNotifications:
                                                                    unread,
                                                                message:
                                                                    _message,
                                                                loading:
                                                                    loading,
                                                                updating:
                                                                    _updatingAvailability,
                                                                online: online,
                                                                available:
                                                                    available,
                                                                onToggleAvailability:
                                                                    _toggleAvailability,
                                                                onOpenTab:
                                                                    _openTab,
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

  bool get _localPreviewAllowed {
    final host = Uri.base.host;
    return kDebugMode &&
        widget.enableLocalPreview &&
        (host == 'localhost' || host == '127.0.0.1' || host.isEmpty);
  }

  Widget _buildLocalPreview(BuildContext context) {
    final profile = _profileFromBackend(
      {
        'id': 'local-preview-rider',
        'fullName': 'Jason Rider',
        'firstName': 'Jason',
        'email': 'local-rider@circum.test',
        'onboardingStatus': 'approved',
        'approvalStatus': 'approved',
        'verificationStatus': 'approved',
        'riderRank': 'Knight',
        'trustPoints': 245,
        'stripeStatus': 'payouts_enabled',
        'stripeAccountId': 'acct_local_preview',
        'stripePayoutsEnabled': true,
        'stripeDetailsSubmitted': true,
        ...widget.localPreviewProfile,
      },
      {
        'isOnline': false,
        'availabilityStatus': 'offline',
        ...widget.localPreviewPresence,
      },
    );
    final presence = {
      'isOnline': false,
      'availabilityStatus': 'offline',
      ...widget.localPreviewPresence,
    };
    final earnings = {
      'availableBalance': 184.25,
      'pendingBalance': 42.5,
      'todayEarnings': 36.8,
      'weeklyEarnings': 218.4,
      'monthlyEarnings': 940.75,
      'lifetimeEarnings': 7412.2,
      'todayCompletedJobs': 3,
      'todayTrustPoints': 11,
      ...widget.localPreviewEarnings,
    };
    final finance = _FinanceSnapshot.from(
      earnings: earnings,
      profile: profile,
      rothWallet: {
        'balanceRoth': 28,
        ...widget.localPreviewRothWallet,
      },
      riderTransactions: widget.localPreviewTransactions.isEmpty
          ? const [
              {
                'type': 'Health+',
                'description': 'Prescription delivery completed',
                'amount': 26.2,
                '_financeKind': 'cash',
              },
              {
                'type': 'Standard Delivery',
                'description': 'Parcel delivery completed',
                'amount': 18.5,
                '_financeKind': 'cash',
              },
            ]
          : widget.localPreviewTransactions,
      walletTransactions: const [
        {
          'type': 'referral_reward',
          'description': 'Rider referral reward',
          'amount': 5,
          'balanceType': 'rothCredit',
        },
        {
          'type': 'admin_reward',
          'description': 'Admin reward',
          'amount': 10,
          'balanceType': 'rothCredit',
        },
      ],
      payouts: widget.localPreviewPayouts.isEmpty
          ? const [
              {
                'type': 'withdrawal',
                'status': 'paid',
                'description': 'Stripe Express payout',
                'amount': 120,
                '_financeKind': 'withdrawal',
              },
            ]
          : widget.localPreviewPayouts,
      referrals: widget.localPreviewReferrals.isEmpty
          ? const [
              {
                'status': 'completed',
                'rewardRoth': 5,
                'firstDeliveryCompletedAt': true,
              },
              {
                'status': 'pending',
                'signedUpAt': true,
              },
            ]
          : widget.localPreviewReferrals,
    );
    final state = RiderHomeStateMapper.fromBackend(
      riderProfile: profile,
      presence: presence,
      hasAvailableOffers: false,
    );
    final online = presence['isOnline'] == true;
    final available = online && presence['availabilityStatus'] == 'available';
    return Scaffold(
      backgroundColor: const Color(0xFF07090F),
      body: Stack(
        children: [
          const Positioned.fill(child: RiderRouteMapLayer()),
          const Positioned.fill(child: _MapShade()),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: _tab == 3
                      ? _FinanceHubPreviewPane(
                          finance: finance,
                          profile: profile,
                          onOpenTab: _openTab,
                        )
                      : _DashboardPane(
                          user: null,
                          firstNameOverride: '${profile['firstName']}',
                          state: state,
                          profile: profile,
                          presence: presence,
                          earnings: earnings,
                          offers: const [],
                          scheduled: const [],
                          recent: const [],
                          unreadNotifications: 1,
                          message:
                              'Local Rider preview. Production auth is not bypassed.',
                          loading: false,
                          updating: false,
                          online: online,
                          available: available,
                          onToggleAvailability: () => setState(
                            () => _message =
                                'Preview only. Use the app to change live presence.',
                          ),
                          onOpenTab: _openTab,
                        ),
                ),
                _RiderBottomNav(
                  selected: _tab,
                  online: online,
                  updating: false,
                  onSelect: _openTab,
                  onCentralTap: () => setState(
                    () => _message =
                        'Preview only. Use the app to change live presence.',
                  ),
                ),
              ],
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
    if (index == 4) {
      setState(() {
        _tab = index;
        _message =
            'Profile opens from the existing rider profile route when wired.';
      });
      return;
    }
    setState(() {
      _tab = index;
      if (index == 0 || index == 1 || index == 3) _message = null;
    });
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
  final String? firstNameOverride;
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
    this.firstNameOverride,
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
    final preview = firstNameOverride?.trim();
    if (preview != null && preview.isNotEmpty) return preview;
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

class _FinanceHubPane extends StatelessWidget {
  final User? user;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> earnings;
  final FirebaseFirestore firestore;
  final ValueChanged<int> onOpenTab;

  const _FinanceHubPane({
    super.key,
    required this.user,
    required this.profile,
    required this.earnings,
    required this.firestore,
    required this.onOpenTab,
  });

  @override
  Widget build(BuildContext context) {
    final uid = user?.uid;
    if (uid == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        children: const [
          _SectionHeader(
            title: 'Finance',
            subtitle: 'Sign in to view rider earnings and wallet activity.',
          ),
        ],
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collectionGroup('wallets')
          .where('walletType', isEqualTo: 'rider')
          .limit(20)
          .snapshots(),
      builder: (context, rothSnapshot) {
        final rothWallet = _roleRothWallet(rothSnapshot, uid);
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firestore
              .collection('riderWalletTransactions')
              .where('riderId', isEqualTo: uid)
              .limit(20)
              .snapshots(),
          builder: (context, riderTxSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firestore
                  .collection('walletTransactions')
                  .where('userId', isEqualTo: uid)
                  .limit(20)
                  .snapshots(),
              builder: (context, walletTxSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: firestore
                      .collection('payoutRequests')
                      .where('riderId', isEqualTo: uid)
                      .limit(20)
                      .snapshots(),
                  builder: (context, payoutSnapshot) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: firestore
                          .collection('referrals')
                          .where('referrerUserId', isEqualTo: uid)
                          .limit(20)
                          .snapshots(),
                      builder: (context, referralSnapshot) {
                        final riderTransactions = _docs(riderTxSnapshot);
                        final walletTransactions = _docs(walletTxSnapshot);
                        final payouts = _docs(payoutSnapshot);
                        final referrals = _docs(referralSnapshot);
                        final finance = _FinanceSnapshot.from(
                          earnings: earnings,
                          profile: profile,
                          rothWallet: rothWallet,
                          riderTransactions: riderTransactions,
                          walletTransactions: walletTransactions,
                          payouts: payouts,
                          referrals: referrals,
                        );
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                          children: [
                            const _SectionHeader(
                              title: 'Finance',
                              subtitle:
                                  'Cash, Roth, withdrawals and rank progress.',
                            ),
                            const SizedBox(height: 14),
                            _FinanceOverview(finance: finance),
                            const SizedBox(height: 14),
                            _FinanceEarnings(finance: finance),
                            const SizedBox(height: 14),
                            _RothWalletSection(finance: finance),
                            const SizedBox(height: 14),
                            _ReferralRothSection(finance: finance),
                            const SizedBox(height: 14),
                            _WithdrawSection(
                              finance: finance,
                              profile: profile,
                            ),
                            const SizedBox(height: 14),
                            _TransactionHistory(finance: finance),
                            const SizedBox(height: 14),
                            _FinanceRankSection(profile: profile),
                            const SizedBox(height: 14),
                            _InsightsSection(finance: finance),
                            const SizedBox(height: 14),
                            _NextMilestoneSection(finance: finance),
                            const SizedBox(height: 14),
                            _QuickActions(onOpenTab: onOpenTab),
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
  }

  static Map<String, dynamic>? _roleRothWallet(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
    String uid,
  ) {
    if (!snapshot.hasData) return null;
    for (final doc in snapshot.data!.docs) {
      final data = doc.data();
      final owner =
          '${data['userId'] ?? doc.reference.parent.parent?.id ?? ''}';
      if (owner == uid) return {'id': doc.id, ...data};
    }
    return null;
  }

  static List<Map<String, dynamic>> _docs(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
  ) {
    if (!snapshot.hasData) return const [];
    return snapshot.data!.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList(growable: false);
  }
}

class _FinanceHubPreviewPane extends StatelessWidget {
  final _FinanceSnapshot finance;
  final Map<String, dynamic> profile;
  final ValueChanged<int> onOpenTab;

  const _FinanceHubPreviewPane({
    required this.finance,
    required this.profile,
    required this.onOpenTab,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      children: [
        const _SectionHeader(
          title: 'Finance',
          subtitle: 'Local Rider preview · production auth untouched.',
        ),
        const SizedBox(height: 14),
        _FinanceOverview(finance: finance),
        const SizedBox(height: 14),
        _FinanceEarnings(finance: finance),
        const SizedBox(height: 14),
        _RothWalletSection(finance: finance),
        const SizedBox(height: 14),
        _ReferralRothSection(finance: finance),
        const SizedBox(height: 14),
        _WithdrawSection(
          finance: finance,
          profile: profile,
          previewEmail: '${profile['email'] ?? ''}',
        ),
        const SizedBox(height: 14),
        _TransactionHistory(finance: finance),
        const SizedBox(height: 14),
        _FinanceRankSection(profile: profile),
        const SizedBox(height: 14),
        _InsightsSection(finance: finance),
        const SizedBox(height: 14),
        _NextMilestoneSection(finance: finance),
        const SizedBox(height: 14),
        _QuickActions(onOpenTab: onOpenTab),
      ],
    );
  }
}

class _FinanceSnapshot {
  final double availableCash;
  final double pendingCash;
  final double today;
  final double week;
  final double month;
  final double lifetime;
  final double processingWithdrawals;
  final double completedWithdrawals;
  final double rothBalance;
  final int trustPoints;
  final String rank;
  final List<Map<String, dynamic>> riderTransactions;
  final List<Map<String, dynamic>> walletTransactions;
  final List<Map<String, dynamic>> payouts;
  final List<Map<String, dynamic>> referrals;

  const _FinanceSnapshot({
    required this.availableCash,
    required this.pendingCash,
    required this.today,
    required this.week,
    required this.month,
    required this.lifetime,
    required this.processingWithdrawals,
    required this.completedWithdrawals,
    required this.rothBalance,
    required this.trustPoints,
    required this.rank,
    required this.riderTransactions,
    required this.walletTransactions,
    required this.payouts,
    required this.referrals,
  });

  factory _FinanceSnapshot.from({
    required Map<String, dynamic> earnings,
    required Map<String, dynamic> profile,
    required Map<String, dynamic>? rothWallet,
    required List<Map<String, dynamic>> riderTransactions,
    required List<Map<String, dynamic>> walletTransactions,
    required List<Map<String, dynamic>> payouts,
    required List<Map<String, dynamic>> referrals,
  }) {
    final processing = payouts.where((item) {
      final status = '${item['status'] ?? ''}'.toLowerCase();
      return status == 'requested' ||
          status == 'approved' ||
          status == 'pending' ||
          status == 'processing';
    }).fold<double>(0, (total, item) => total + _num(item['amount']));
    final completed = payouts.where((item) {
      final status = '${item['status'] ?? ''}'.toLowerCase();
      return status == 'completed' || status == 'paid';
    }).fold<double>(0, (total, item) => total + _num(item['amount']));
    return _FinanceSnapshot(
      availableCash: _num(earnings['availableBalance'] ??
          earnings['availableEarnings'] ??
          earnings['accountBalance']),
      pendingCash: _num(earnings['pendingBalance'] ??
          earnings['pendingEarnings'] ??
          earnings['pendingWithdrawal']),
      today: _num(earnings['todayEarnings'] ?? earnings['availableToday']),
      week: _num(earnings['weeklyEarnings'] ?? earnings['thisWeekEarnings']),
      month: _num(earnings['monthlyEarnings'] ?? earnings['thisMonthEarnings']),
      lifetime:
          _num(earnings['lifetimeEarnings'] ?? earnings['totalAmountEarned']),
      processingWithdrawals: processing,
      completedWithdrawals:
          completed > 0 ? completed : _num(earnings['withdrawnEarnings']),
      rothBalance: _num(rothWallet?['balanceRoth'] ??
          rothWallet?['balance'] ??
          rothWallet?['rothCredit']),
      trustPoints: _num(profile['trustPoints']).toInt(),
      rank: '${profile['riderRank'] ?? profile['rank'] ?? ''}'.trim(),
      riderTransactions: riderTransactions,
      walletTransactions: walletTransactions,
      payouts: payouts,
      referrals: referrals,
    );
  }

  List<Map<String, dynamic>> get combinedTransactions {
    final rows = <Map<String, dynamic>>[
      ...riderTransactions.map((item) => {...item, '_financeKind': 'cash'}),
      ...walletTransactions.map((item) {
        final balanceType = '${item['balanceType'] ?? ''}'.toLowerCase();
        final type = '${item['type'] ?? ''}'.toLowerCase();
        return {
          ...item,
          '_financeKind': balanceType.contains('roth') ||
                  type.contains('roth') ||
                  type.contains('referral') ||
                  type.contains('gift_card')
              ? 'roth'
              : 'cash',
        };
      }),
      ...payouts.map((item) => {...item, '_financeKind': 'withdrawal'}),
    ];
    rows.sort((a, b) => _millis(b).compareTo(_millis(a)));
    return rows.take(8).toList(growable: false);
  }

  static int _millis(Map<String, dynamic> item) {
    final value = item['createdAt'] ?? item['updatedAt'] ?? item['paidAt'];
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    return 0;
  }

  static double _num(Object? value) => value is num ? value.toDouble() : 0;
}

class _FinanceOverview extends StatelessWidget {
  final _FinanceSnapshot finance;

  const _FinanceOverview({required this.finance});

  @override
  Widget build(BuildContext context) {
    return _MetricGlassGrid(
      title: 'Overview',
      items: [
        (_money(finance.availableCash), 'Available Cash'),
        ('${finance.rothBalance.toStringAsFixed(0)} Roth', 'Roth Balance'),
        (_money(finance.today), 'Today'),
        ('${finance.trustPoints}', 'Trust Points'),
        (finance.rank.isEmpty ? 'Rank building' : finance.rank, 'Current Rank'),
      ],
    );
  }
}

class _FinanceEarnings extends StatelessWidget {
  final _FinanceSnapshot finance;

  const _FinanceEarnings({required this.finance});

  @override
  Widget build(BuildContext context) {
    return _MetricGlassGrid(
      title: 'Earnings',
      items: [
        (_money(finance.today), 'Today'),
        (_money(finance.week), 'This Week'),
        (_money(finance.month), 'This Month'),
        (_money(finance.lifetime), 'Lifetime'),
        (_money(finance.pendingCash), 'Pending'),
        (_money(finance.availableCash), 'Available to Withdraw'),
        (_money(finance.processingWithdrawals), 'Processing'),
        (_money(finance.completedWithdrawals), 'Completed Withdrawals'),
      ],
    );
  }
}

class _RothWalletSection extends StatelessWidget {
  final _FinanceSnapshot finance;

  const _RothWalletSection({required this.finance});

  @override
  Widget build(BuildContext context) {
    final rothRows = finance.walletTransactions
        .where((item) =>
            '${item['_financeKind'] ?? item['balanceType'] ?? item['type']}'
                .toLowerCase()
                .contains('roth'))
        .take(4)
        .toList(growable: false);
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Roth Wallet',
            subtitle:
                'Roth is internal Circum credit, separate from cash earnings.',
          ),
          const SizedBox(height: 12),
          Text(
            '${finance.rothBalance.toStringAsFixed(0)} Roth',
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const _EmptyLine(
            'Roth is an internal Circum credit that can be used across supported Circum services. Roth is separate from cash earnings and cannot be withdrawn as cash.',
          ),
          const SizedBox(height: 12),
          if (rothRows.isEmpty)
            const _EmptyLine('No recent Roth activity yet.')
          else
            ...rothRows.map(_FinanceTransactionRow.new),
        ],
      ),
    );
  }
}

class _ReferralRothSection extends StatelessWidget {
  final _FinanceSnapshot finance;

  const _ReferralRothSection({required this.finance});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Rider Referral Roth',
            subtitle:
                'Rewards unlock after approval, activation and first qualifying delivery.',
          ),
          const SizedBox(height: 12),
          if (finance.referrals.isEmpty)
            const _EmptyLine('Referral progress will appear here.')
          else
            ...finance.referrals.take(4).map((item) {
              final status = _referralStatus(item);
              final amount = _FinanceSnapshot._num(
                item['rewardRoth'] ?? item['amountRoth'] ?? item['amount'],
              );
              return _FinanceLine(
                icon: Icons.group_add_rounded,
                title: 'Rider Referral Reward',
                subtitle: 'Status: $status',
                value: amount > 0 ? '+${amount.toStringAsFixed(0)} Roth' : '',
              );
            }),
        ],
      ),
    );
  }

  static String _referralStatus(Map<String, dynamic> item) {
    final raw = '${item['status'] ?? ''}'.toLowerCase();
    if (raw == 'completed' || raw == 'rewarded') return 'Completed';
    if (item['firstDeliveryCompletedAt'] != null) return 'Completed';
    if (item['approvedAt'] != null || item['activatedAt'] != null) {
      return 'Awaiting first completed delivery';
    }
    if (item['signedUpAt'] != null || raw == 'pending') {
      return 'Awaiting approval';
    }
    return 'Signed up';
  }
}

class _WithdrawSection extends StatelessWidget {
  final _FinanceSnapshot finance;
  final Map<String, dynamic> profile;
  final String? previewEmail;

  const _WithdrawSection({
    required this.finance,
    required this.profile,
    this.previewEmail,
  });

  @override
  Widget build(BuildContext context) {
    final ready = RiderOnboardingPolicy.canWithdraw(
      email: previewEmail ?? FirebaseAuth.instance.currentUser?.email,
      profile: profile,
    );
    final accountId =
        '${profile['stripeAccountId'] ?? profile['stripeConnectAccountId'] ?? ''}'
            .trim();
    final stripeStatus = '${profile['stripeStatus'] ?? ''}'.trim();
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Withdraw',
            subtitle: 'Stripe Express payout status and withdrawal history.',
          ),
          const SizedBox(height: 12),
          _FinanceLine(
            icon: Icons.payments_rounded,
            title: 'Available Withdrawal Balance',
            subtitle: 'Cash earnings only. Roth cannot be withdrawn.',
            value: _money(finance.availableCash),
          ),
          _FinanceLine(
            icon: Icons.account_balance_rounded,
            title: accountId.isEmpty ? 'Stripe not started' : 'Stripe Express',
            subtitle: _stripeCopy(profile),
            value:
                stripeStatus.isEmpty ? 'Not started' : _titleCase(stripeStatus),
          ),
          _FinanceLine(
            icon: Icons.schedule_rounded,
            title: 'Estimated Arrival',
            subtitle: 'Shown after an approved Stripe payout is processed.',
            value: ready ? 'Stripe schedule' : 'Locked',
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: null,
              child: Text(
                ready ? 'Withdraw via existing payout flow' : 'Withdraw locked',
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (finance.payouts.isEmpty)
            const _EmptyLine('No withdrawal history yet.')
          else
            ...finance.payouts.take(4).map(_FinanceTransactionRow.new),
        ],
      ),
    );
  }

  static String _stripeCopy(Map<String, dynamic> profile) {
    if (profile['payoutPaused'] == true) return 'Payouts paused.';
    if (profile['stripeStatus'] == 'payouts_enabled' ||
        profile['stripePayoutsEnabled'] == true) {
      return 'Payouts Enabled. Bank account linked through Stripe.';
    }
    if ('${profile['stripeAccountId'] ?? ''}'.trim().isNotEmpty) {
      return 'Stripe account exists. Action may be required before withdrawal.';
    }
    return 'Set up Stripe payouts before requesting cash withdrawal.';
  }
}

class _TransactionHistory extends StatelessWidget {
  final _FinanceSnapshot finance;

  const _TransactionHistory({required this.finance});

  @override
  Widget build(BuildContext context) {
    final rows = finance.combinedTransactions;
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Transactions',
            subtitle: 'All · Cash · Roth · Deliveries · Withdrawals · Rewards',
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const _EmptyLine('Transactions will appear here.')
          else
            ...rows.map(_FinanceTransactionRow.new),
        ],
      ),
    );
  }
}

class _FinanceRankSection extends StatelessWidget {
  final Map<String, dynamic> profile;

  const _FinanceRankSection({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Rank Progression',
            subtitle: 'Agent → Sentinel → Warden → Knight → Veteran',
          ),
          const SizedBox(height: 12),
          _RankCard(profile: profile),
          const SizedBox(height: 12),
          const _EmptyLine(
            'Higher ranks unlock greater priority for eligible delivery opportunities as defined by Circum dispatch policy.',
          ),
        ],
      ),
    );
  }
}

class _InsightsSection extends StatelessWidget {
  final _FinanceSnapshot finance;

  const _InsightsSection({required this.finance});

  @override
  Widget build(BuildContext context) {
    final insight = finance.week > 0 && finance.lifetime > finance.week
        ? 'This week is contributing to your lifetime earnings.'
        : finance.trustPoints > 0
            ? 'You are building trust with every completed delivery.'
            : '';
    if (insight.isEmpty) return const SizedBox.shrink();
    return _GlassPanel(
      child: _FinanceLine(
        icon: Icons.insights_rounded,
        title: 'Insights',
        subtitle: insight,
        value: '',
      ),
    );
  }
}

class _NextMilestoneSection extends StatelessWidget {
  final _FinanceSnapshot finance;

  const _NextMilestoneSection({required this.finance});

  @override
  Widget build(BuildContext context) {
    final rank = finance.rank.isEmpty ? 'Agent' : finance.rank;
    final next = _RankCard._nextRank(rank);
    final remaining =
        (_RankCard._rankThreshold(next) - finance.trustPoints).clamp(0, 99999);
    final copy = finance.availableCash <= 0
        ? 'Complete 1 more delivery to build your withdrawal balance.'
        : remaining > 0
            ? 'Earn $remaining more Trust Points to reach $next.'
            : finance.referrals.isEmpty
                ? 'Invite one Rider to earn referral Roth after their first qualifying delivery.'
                : 'Keep completing deliveries to strengthen your rider profile.';
    return _GlassPanel(
      child: _FinanceLine(
        icon: Icons.flag_rounded,
        title: 'Next Milestone',
        subtitle: copy,
        value: '',
      ),
    );
  }
}

class _FinanceLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;

  const _FinanceLine({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          _CircleIcon(icon: icon),
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
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .58),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFF60A5FA),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _FinanceTransactionRow extends StatelessWidget {
  final Map<String, dynamic> item;

  const _FinanceTransactionRow(this.item);

  @override
  Widget build(BuildContext context) {
    final kind = '${item['_financeKind'] ?? item['type'] ?? 'transaction'}';
    final isRoth = kind.toLowerCase().contains('roth') ||
        '${item['type'] ?? ''}'.toLowerCase().contains('referral') ||
        '${item['balanceType'] ?? ''}'.toLowerCase().contains('roth');
    final amount = _FinanceSnapshot._num(
      item['amount'] ?? item['tipAmount'] ?? item['riderNetPayout'],
    );
    final sign = amount < 0 || kind == 'withdrawal' ? '-' : '+';
    final value = isRoth
        ? '$sign${amount.abs().toStringAsFixed(0)} Roth'
        : '$sign£${amount.abs().toStringAsFixed(2)}';
    return _FinanceLine(
      icon: isRoth
          ? Icons.stars_rounded
          : kind == 'withdrawal'
              ? Icons.account_balance_wallet_rounded
              : Icons.receipt_long_rounded,
      title: _titleCase('${item['type'] ?? item['status'] ?? 'Transaction'}'),
      subtitle:
          '${item['description'] ?? item['reason'] ?? item['status'] ?? 'Recorded'} · ${_date(item)}',
      value: value,
    );
  }

  static String _date(Map<String, dynamic> item) {
    final value = item['createdAt'] ?? item['updatedAt'] ?? item['paidAt'];
    if (value is Timestamp) {
      final date = value.toDate();
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    }
    return 'Pending date';
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
          Wrap(
            spacing: 12,
            runSpacing: 14,
            children: items
                .map(
                  (item) => SizedBox(
                    width: 132,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

String _money(double value) => '£${value.toStringAsFixed(2)}';

String _titleCase(String value) {
  return value
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
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
