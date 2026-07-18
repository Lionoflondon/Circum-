import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../send_package/bloc/send_package_bloc.dart';
import '../send_package/view/ride_chats.dart';
import 'design_system/sender_design_system.dart';
import 'sender_booking_canvas.dart';
import 'sender_accessibility.dart';
import 'sender_wallet.dart';

enum SenderActivityType { parcel, gift, health, business, roth }

class SenderActivityItem {
  final String id;
  final SenderActivityType type;
  final String title;
  final String status;
  final String destination;
  final String pickup;
  final String rider;
  final String eta;
  final double? amount;
  final double? rothAmount;
  final String rothDirection;
  final DateTime? occurredAt;
  final bool active;
  final String riderId;
  final String riderPhotoUrl;
  final String riderRank;
  final double? riderRating;
  final int trustPoints;
  final bool vanguardProtected;
  final bool irisVerified;
  final bool repeatRider;
  final bool riderTrusted;
  final bool riderVanguardApproved;
  final int? riderCompletedDeliveries;
  final DateTime? riderMemberSince;
  final List<String> riderAchievements;

  const SenderActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.status,
    required this.destination,
    this.pickup = '',
    this.rider = '',
    this.eta = '',
    this.amount,
    this.rothAmount,
    this.rothDirection = '',
    this.occurredAt,
    this.active = false,
    this.riderId = '',
    this.riderPhotoUrl = '',
    this.riderRank = '',
    this.riderRating,
    this.trustPoints = 0,
    this.vanguardProtected = false,
    this.irisVerified = false,
    this.repeatRider = false,
    this.riderTrusted = false,
    this.riderVanguardApproved = false,
    this.riderCompletedDeliveries,
    this.riderMemberSince,
    this.riderAchievements = const [],
  });

  SenderActivityItem copyWith({bool? repeatRider}) => SenderActivityItem(
        id: id,
        type: type,
        title: title,
        status: status,
        destination: destination,
        pickup: pickup,
        rider: rider,
        eta: eta,
        amount: amount,
        rothAmount: rothAmount,
        rothDirection: rothDirection,
        occurredAt: occurredAt,
        active: active,
        riderId: riderId,
        riderPhotoUrl: riderPhotoUrl,
        riderRank: riderRank,
        riderRating: riderRating,
        trustPoints: trustPoints,
        vanguardProtected: vanguardProtected,
        irisVerified: irisVerified,
        repeatRider: repeatRider ?? this.repeatRider,
        riderTrusted: riderTrusted,
        riderVanguardApproved: riderVanguardApproved,
        riderCompletedDeliveries: riderCompletedDeliveries,
        riderMemberSince: riderMemberSince,
        riderAchievements: riderAchievements,
      );
}

class SenderActivityPage {
  final List<SenderActivityItem> items;
  final String? nextPageToken;
  const SenderActivityPage(this.items, this.nextPageToken);
}

abstract class SenderActivityRepository {
  Stream<List<SenderActivityItem>> watchActive();
  Future<SenderActivityPage> history({String? pageToken});
}

class FirebaseSenderActivityRepository implements SenderActivityRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final SenderWalletRepository walletRepository;
  final Map<String, Map<String, dynamic>> _riderProfileCache = {};

  FirebaseSenderActivityRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    SenderWalletRepository? walletRepository,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        walletRepository = walletRepository ?? FirebaseSenderWalletRepository();

  String get _uid {
    final user = auth.currentUser;
    if (user == null) throw StateError('Sign in to view Activity.');
    return user.uid;
  }

  @override
  Stream<List<SenderActivityItem>> watchActive() {
    return firestore
        .collection('deliveryRequests')
        .where('senderId', isEqualTo: _uid)
        .limit(20)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map((doc) => _delivery(doc.id, doc.data()))
          .where((item) => item.active)
          .toList();
      items.sort((a, b) => (b.occurredAt ?? DateTime(1970))
          .compareTo(a.occurredAt ?? DateTime(1970)));
      return items;
    });
  }

  @override
  Future<SenderActivityPage> history({String? pageToken}) async {
    final page = int.tryParse(pageToken ?? '0') ?? 0;
    final sourceLimit = (page + 1) * 12;
    final results = await Future.wait([
      firestore
          .collection('deliveryRequests')
          .where('senderId', isEqualTo: _uid)
          .limit(sourceLimit)
          .get(),
      firestore
          .collection('giftRequests')
          .where('senderId', isEqualTo: _uid)
          .limit(sourceLimit)
          .get(),
      firestore
          .collection('prescriptionPickups')
          .where('profileId', isEqualTo: _uid)
          .limit(sourceLimit)
          .get(),
      walletRepository.transactions(),
    ]);
    final deliveries = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final gifts = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final health = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final wallet = results[3] as SenderWalletPage;
    final riderProfiles = await _riderProfiles(deliveries.docs);
    final deliveryItems = deliveries.docs
        .map((doc) => _delivery(
              doc.id,
              doc.data(),
              riderProfile: riderProfiles[_riderId(doc.data())],
            ))
        .toList();
    final riderCounts = <String, int>{};
    for (final item in deliveryItems) {
      if (item.riderId.isNotEmpty && _isCompletedStatus(item.status)) {
        riderCounts.update(item.riderId, (currentCount) => currentCount + 1,
            ifAbsent: () => 1);
      }
    }
    final merged = <SenderActivityItem>[
      ...deliveryItems.map((item) => item.copyWith(
            repeatRider: (riderCounts[item.riderId] ?? 0) > 1,
          )),
      ...gifts.docs.map((doc) => _gift(doc.id, doc.data())),
      ...health.docs.map((doc) => _health(doc.id, doc.data())),
      ...wallet.transactions.map(_roth),
    ]..removeWhere((item) => item.active);
    merged.sort((a, b) => (b.occurredAt ?? DateTime(1970))
        .compareTo(a.occurredAt ?? DateTime(1970)));
    final start = page * 20;
    final items = start >= merged.length
        ? <SenderActivityItem>[]
        : merged.skip(start).take(20).toList();
    final hasMore = merged.length > start + items.length ||
        deliveries.docs.length == sourceLimit ||
        gifts.docs.length == sourceLimit ||
        health.docs.length == sourceLimit ||
        wallet.nextPageToken != null;
    return SenderActivityPage(items, hasMore ? '${page + 1}' : null);
  }

  Future<Map<String, Map<String, dynamic>>> _riderProfiles(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> deliveries,
  ) async {
    final ids = deliveries
        .map((doc) => _riderId(doc.data()))
        .where((id) => id.isNotEmpty)
        .toSet()
        .take(30)
        .toList();
    if (ids.isEmpty) return const {};
    final missingIds = ids
        .where((id) => !_riderProfileCache.containsKey(id))
        .toList(growable: false);
    try {
      if (missingIds.isNotEmpty) {
        final snapshot = await firestore
            .collection('riderProfiles')
            .where(FieldPath.documentId, whereIn: missingIds)
            .get();
        for (final doc in snapshot.docs) {
          _riderProfileCache[doc.id] = doc.data();
        }
      }
    } catch (_) {
      // The delivery's embedded rider snapshot remains the safe fallback.
    }
    return {
      for (final id in ids)
        if (_riderProfileCache[id] case final profile?) id: profile,
    };
  }

  SenderActivityItem _delivery(
    String id,
    Map<String, dynamic> data, {
    Map<String, dynamic>? riderProfile,
  }) {
    final pickup = _map(data['pickupDetails'] ?? data['pickup']);
    final dropoff = _map(data['dropoffDetails'] ?? data['dropoff']);
    final parcel = _map(data['parcel'] ?? data['package']);
    final assignedRider = _map(data['assignedRider']);
    final embeddedProfile = _map(data['riderProfile']);
    final profile = riderProfile ?? embeddedProfile;
    final vanguard = _map(data['vanguard']);
    final iris = _map(data['iris'] ?? data['irisClassification']);
    final status = '${data['deliveryStatus'] ?? data['status'] ?? 'requested'}';
    final normalized = status.toLowerCase();
    return SenderActivityItem(
      id: id,
      type: data['businessMode'] == true ||
              '${data['businessId'] ?? ''}'.isNotEmpty
          ? SenderActivityType.business
          : SenderActivityType.parcel,
      title: _first(
          [parcel['itemName'], parcel['description'], 'Parcel delivery']),
      status: _status(status),
      pickup: _first([pickup['address'], pickup['locality']]),
      destination: _first([
        data['recipient'] is Map ? (data['recipient'] as Map)['name'] : null,
        dropoff['address'],
        dropoff['locality'],
      ]),
      rider: _riderFirstName(_first([
        profile['firstName'],
        profile['fullName'],
        profile['name'],
        assignedRider['firstName'],
        assignedRider['name'],
        data['riderName'],
        data['driverName'],
        data['courierName'],
      ])),
      eta: _first([data['estimatedDeliveryTime'], data['eta']]),
      amount:
          _number(data['paidAmount'] ?? data['price'] ?? data['totalAmount']),
      occurredAt: _date(data['updatedAt'] ?? data['createdAt']),
      active: senderActivityIsLiveDeliveryStatus(normalized),
      riderId: _riderId(data),
      riderPhotoUrl: _first([
        profile['profileThumbnailUrl'],
        profile['profilePhotoUrl'],
        profile['photoURL'],
        profile['photoUrl'],
        assignedRider['profileThumbnailUrl'],
        assignedRider['profilePhotoUrl'],
        assignedRider['photoURL'],
        data['riderPhotoURL'],
      ]),
      riderRank: _riderRankLabel(
        _first([profile['rank'], profile['riderRank'], data['riderRank']]),
      ),
      riderRating: _number(profile['averageRating'] ??
          profile['rating'] ??
          _map(profile['performance'])['averageRating'] ??
          data['riderRating']),
      trustPoints: (_number(data['trustPointsAwarded'] ??
                  data['senderTrustPointsAwarded'] ??
                  _map(data['trustAward'])['points']) ??
              0)
          .round(),
      vanguardProtected: data['vanguardEnabled'] == true ||
          data['vanguardProtected'] == true ||
          vanguard['enabled'] == true ||
          vanguard['protected'] == true,
      irisVerified: data['irisVerified'] == true ||
          data['irisClassified'] == true ||
          iris.isNotEmpty ||
          data['irisMatchedItemName'] != null ||
          data['normalizedItemName'] != null,
      riderTrusted: _riderTrusted(profile),
      riderVanguardApproved: profile['vanguardApproved'] == true ||
          '${profile['vanguardStatus'] ?? ''}'.toLowerCase() == 'approved',
      riderCompletedDeliveries: _optionalInt(profile['completedDeliveries'] ??
          _map(profile['performance'])['completedDeliveries']),
      riderMemberSince: _date(profile['memberSince'] ?? profile['createdAt']),
      riderAchievements: _safeAchievementLabels(
        profile['recentAchievements'] ?? profile['achievements'],
      ),
    );
  }

  SenderActivityItem _gift(String id, Map<String, dynamic> data) =>
      SenderActivityItem(
        id: id,
        type: SenderActivityType.gift,
        title: _first([data['occasion'], 'Gift experience']),
        status:
            _status('${data['giftStatus'] ?? data['status'] ?? 'submitted'}'),
        destination: _first([data['recipientName'], data['formattedAddress']]),
        amount: _number(data['grossGiftBudget'] ?? data['budget']),
        rothAmount: _number(data['rothApplied']),
        rothDirection: 'debit',
        occurredAt: _date(data['updatedAt'] ?? data['createdAt']),
      );

  SenderActivityItem _health(String id, Map<String, dynamic> data) =>
      SenderActivityItem(
        id: id,
        type: SenderActivityType.health,
        title: 'Health+ request',
        status: _status('${data['status'] ?? 'scheduled'}'),
        destination:
            _first([data['careRecipientName'], data['deliveryAddress']]),
        amount: _number(data['price'] ?? data['amount']),
        occurredAt: _date(data['updatedAt'] ?? data['createdAt']),
      );

  SenderActivityItem _roth(SenderWalletTransaction item) => SenderActivityItem(
        id: item.id,
        type: SenderActivityType.roth,
        title: item.description,
        status: _status(item.status),
        destination: item.paymentMethodLabel,
        rothAmount: item.amount,
        rothDirection: item.direction,
        occurredAt: item.createdAt,
      );
}

class SenderActivityView extends StatefulWidget {
  final SenderActivityRepository? repository;
  final VoidCallback onSendParcel;
  final VoidCallback onExploreGifts;

  const SenderActivityView({
    super.key,
    this.repository,
    required this.onSendParcel,
    required this.onExploreGifts,
  });

  @override
  State<SenderActivityView> createState() => _SenderActivityViewState();
}

class _SenderActivityViewState extends State<SenderActivityView> {
  late final SenderActivityRepository _repository;
  StreamSubscription<List<SenderActivityItem>>? _activeSubscription;
  final _history = <SenderActivityItem>[];
  List<SenderActivityItem> _active = const [];
  SenderActivityType? _filter;
  String _query = '';
  String? _nextPage;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _activeLoaded = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseSenderActivityRepository();
    _activeSubscription = _repository.watchActive().listen((items) {
      if (!mounted) return;
      final previousIds = _active.map((item) => item.id).toSet();
      final nextIds = items.map((item) => item.id).toSet();
      final movedToHistory =
          _activeLoaded && previousIds.any((id) => !nextIds.contains(id));
      setState(() {
        _active = items;
        _activeLoaded = true;
      });
      if (movedToHistory) unawaited(_refreshHistory());
    }, onError: (_) {});
    _load();
  }

  Future<void> _refreshHistory() async {
    try {
      final page = await _repository.history();
      if (!mounted) return;
      setState(() {
        _history
          ..clear()
          ..addAll(page.items);
        _nextPage = page.nextPageToken;
      });
    } catch (_) {
      // The current history remains visible until the next successful refresh.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repository.history();
      if (!mounted) return;
      setState(() {
        _history
          ..clear()
          ..addAll(page.items);
        _nextPage = page.nextPageToken;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_nextPage == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repository.history(pageToken: _nextPage);
      if (mounted) {
        setState(() {
          _history.addAll(page.items.where((item) => !_history.any((existing) =>
              existing.id == item.id && existing.type == item.type)));
          _nextPage = page.nextPageToken;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<SenderActivityItem> get _visible {
    final query = _query.trim().toLowerCase();
    return _history.where((item) {
      if (_filter != null && item.type != _filter) return false;
      if (query.isEmpty) return true;
      final date = item.occurredAt == null
          ? ''
          : DateFormat('d MMM yyyy').format(item.occurredAt!);
      return [
        item.id,
        item.title,
        item.status,
        item.destination,
        item.pickup,
        date,
        _typeLabel(item.type)
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _activeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        children: [
          Text(
            'Activity',
            style: GoogleFonts.dmSerifDisplay(
              color: Colors.white,
              fontSize: 32,
            ),
          ),
          const SizedBox(height: 22),
          if (_loading) const _ActivitySkeleton(),
          if (!_loading && _error != null) _ActivityError(onRetry: _load),
          if (!_loading && _error == null) ...[
            const ActivitySectionHeader(
              title: 'Live Activity',
              subtitle: 'Deliveries moving right now',
            ),
            const SizedBox(height: 12),
            if (_active.isEmpty)
              ActivityEmptyState(
                title: 'No live deliveries',
                subtitle:
                    "When you send a parcel, gift or Health+ request, you'll be able to track it here.",
                primaryLabel: 'Send a Parcel',
                onPrimary: widget.onSendParcel,
              )
            else
              ..._active.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ActivityCard.live(item: item),
                  )),
            const SizedBox(height: 24),
            const ActivitySectionHeader(
              title: 'History',
              subtitle: 'Everything across Circum',
            ),
            const SizedBox(height: 14),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search recipient, address, order ID or date',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _FilterChip('All',
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null)),
                ...SenderActivityType.values.map((type) => _FilterChip(
                      _filterLabel(type),
                      selected: _filter == type,
                      onTap: () => setState(() => _filter = type),
                    )),
              ]),
            ),
            const SizedBox(height: 18),
            if (_visible.isEmpty)
              const ActivityEmptyState(
                title: 'No matching activity.',
                subtitle: 'Try another search or filter.',
              )
            else
              ActivityTimeline(groups: _grouped(_visible)),
            if (_nextPage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child: Text(
                    _loadingMore ? 'Loading…' : 'Load more activity',
                  ),
                ),
              ),
          ],
        ],
      );
}

class ActivityCard extends StatefulWidget {
  final SenderActivityItem item;
  final bool live;

  const ActivityCard({super.key, required this.item}) : live = false;
  const ActivityCard.live({super.key, required this.item}) : live = true;

  @override
  State<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 10),
          child: child,
        ),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _hovered && !reduceMotion ? 1.01 : 1,
          duration: const Duration(milliseconds: 160),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: widget.live
                ? () => _openTracking(context, item)
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _ActivityDetail(item: item),
                      ),
                    ),
            child: _ActivityGlass(
              child: widget.live
                  ? _LiveCardContent(item: item)
                  : _HistoryCardContent(item: item),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveCardContent extends StatelessWidget {
  final SenderActivityItem item;
  const _LiveCardContent({required this.item});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ActivityIcon(
                  type: item.type, status: item.status, tracking: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.rider.isEmpty ? 'Finding your rider' : item.rider,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    ActivityStatusBadge(status: item.status, type: item.type),
                  ],
                ),
              ),
              if (item.eta.isNotEmpty)
                Text(
                  item.eta,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _RouteLine(label: 'Pickup', value: item.pickup),
          _RouteLine(label: 'Drop-off', value: item.destination),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: _progress(item.status),
              minHeight: 4,
              color: _statusColor(item.status, item.type),
              backgroundColor: Colors.white.withValues(alpha: .08),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openTracking(context, item),
                  icon: const Icon(Icons.navigation_rounded, size: 17),
                  label: const Text('Live Tracking'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => _openChat(context, item),
                child: const Text('Chat'),
              ),
            ],
          ),
        ],
      );
}

class _HistoryCardContent extends StatelessWidget {
  final SenderActivityItem item;
  const _HistoryCardContent({required this.item});

  @override
  Widget build(BuildContext context) {
    if (_isCompletedDelivery(item)) {
      return _CompletedDeliverySummary(item: item);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ActivityIcon(type: item.type, status: item.status),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              ActivityStatusBadge(status: item.status, type: item.type),
              if (item.destination.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  item.destination,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _ActivityColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 7),
              Text(
                _activityDate(item.occurredAt),
                style: GoogleFonts.inter(
                  color: _ActivityColors.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (item.amount != null)
              Text(
                '£${item.amount!.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (item.rothAmount != null && item.rothAmount! > 0) ...[
              const SizedBox(height: 5),
              Text(
                '${item.rothDirection == 'credit' ? '+' : '-'}${item.rothAmount!.toStringAsFixed(2)} Roth',
                style: GoogleFonts.inter(
                  color: _statusColor(item.status, item.type),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CompletedDeliverySummary extends StatelessWidget {
  final SenderActivityItem item;
  const _CompletedDeliverySummary({required this.item});

  @override
  Widget build(BuildContext context) {
    final riderName = item.rider.isEmpty ? 'Circum Rider' : item.rider;
    final trustLabel = item.trustPoints == 1
        ? '+1 Trust Point'
        : '+${item.trustPoints} Trust Points';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF31D17D),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'Delivered Successfully',
              style: GoogleFonts.inter(
                color: const Color(0xFF31D17D),
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            ActivityStatusBadge(status: item.status, type: item.type),
          ],
        ),
        const SizedBox(height: 18),
        _PremiumRiderSummary(item: item, riderName: riderName),
        if (item.trustPoints > 0) ...[
          const SizedBox(height: 14),
          _TrustFeature(
            icon: Icons.add_circle_outline_rounded,
            label: trustLabel,
            color: const Color(0xFF31D17D),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          item.title,
          style: GoogleFonts.dmSerifDisplay(
            color: Colors.white,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 9),
        _TrustFeature(
          icon: item.type == SenderActivityType.business
              ? Icons.apartment_rounded
              : Icons.inventory_2_outlined,
          label: item.type == SenderActivityType.business
              ? 'Business Delivery'
              : 'Parcel Delivery',
          color: item.type == SenderActivityType.business
              ? const Color(0xFF38BDF8)
              : const Color(0xFF60A5FA),
        ),
        if (item.vanguardProtected) ...[
          const SizedBox(height: 9),
          const _TrustFeature(
            icon: Icons.shield_outlined,
            label: 'Vanguard Protected',
            color: Color(0xFF60A5FA),
          ),
        ],
        if (item.irisVerified) ...[
          const SizedBox(height: 9),
          const _TrustFeature(
            icon: Icons.blur_circular_rounded,
            label: 'IRIS Verified',
            color: Color(0xFFA855F7),
          ),
        ],
        const SizedBox(height: 16),
        Divider(color: Colors.white.withValues(alpha: .08), height: 1),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delivered',
                    style: GoogleFonts.inter(
                      color: _ActivityColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _activityDate(item.occurredAt),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (item.amount != null)
              Text(
                '£${item.amount!.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ActivityReceiptView(item: item),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined, size: 17),
            label: const Text('View Receipt'),
          ),
        ),
      ],
    );
  }
}

class _PremiumRiderSummary extends StatelessWidget {
  final SenderActivityItem item;
  final String riderName;
  const _PremiumRiderSummary({required this.item, required this.riderName});

  @override
  Widget build(BuildContext context) {
    final repeatMessage = item.repeatRider && item.rider.isNotEmpty
        ? 'One of your trusted riders'
        : null;
    final trustLabel = item.riderVanguardApproved
        ? 'Vanguard Approved Rider'
        : item.riderTrusted
            ? 'Trusted Circum Rider'
            : null;
    final semantic = [
      'Delivered by $riderName',
      if (item.riderRank.isNotEmpty) item.riderRank,
      if (item.riderRating != null) 'rated ${item.riderRating}',
      if (trustLabel != null) trustLabel,
    ].join(', ');
    return Semantics(
      button: true,
      label: semantic,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showRiderProfile(context, item, riderName),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .035),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: .07),
                Colors.white.withValues(alpha: .015),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delivered by',
                style: GoogleFonts.inter(
                  color: _ActivityColors.muted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _RiderAvatar(name: riderName, photoUrl: item.riderPhotoUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          riderName,
                          style: GoogleFonts.dmSerifDisplay(
                            color: Colors.white,
                            fontSize: 20,
                          ),
                        ),
                        if (item.riderRank.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          _RiderRankBadge(rank: item.riderRank),
                        ],
                      ],
                    ),
                  ),
                  if (item.riderRating != null && item.riderRating! > 0)
                    _RiderRating(rating: item.riderRating!),
                ],
              ),
              if (trustLabel != null || repeatMessage != null) ...[
                const SizedBox(height: 12),
                if (trustLabel != null)
                  _RiderTrustBadge(
                    label: trustLabel,
                    vanguard: item.riderVanguardApproved,
                  ),
                if (repeatMessage != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    repeatMessage,
                    style: GoogleFonts.inter(
                      color: _ActivityColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RiderAvatar extends StatefulWidget {
  final String name;
  final String photoUrl;
  const _RiderAvatar({required this.name, required this.photoUrl});

  @override
  State<_RiderAvatar> createState() => _RiderAvatarState();
}

class _RiderAvatarState extends State<_RiderAvatar> {
  var _loaded = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final child = CircleAvatar(
      radius: 24,
      backgroundColor: const Color(0xFF13233F),
      child: widget.photoUrl.isEmpty
          ? Text(
              widget.name.isEmpty
                  ? 'C'
                  : widget.name.substring(0, 1).toUpperCase(),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            )
          : ClipOval(
              child: Image.network(
                widget.photoUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, _) {
                  if (frame != null && !_loaded) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _loaded = true);
                    });
                  }
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    child: child,
                  );
                },
                errorBuilder: (_, __, ___) => _RiderAvatarFallback(
                  name: widget.name,
                ),
              ),
            ),
    );
    return Semantics(
      image: true,
      label: '${widget.name} profile photo',
      child: child,
    );
  }
}

class _RiderAvatarFallback extends StatelessWidget {
  final String name;
  const _RiderAvatarFallback({required this.name});

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          name.isEmpty ? 'C' : name.substring(0, 1).toUpperCase(),
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _RiderRankBadge extends StatefulWidget {
  final String rank;
  const _RiderRankBadge({required this.rank});

  @override
  State<_RiderRankBadge> createState() => _RiderRankBadgeState();
}

class _RiderRankBadgeState extends State<_RiderRankBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _shimmer.value = 1;
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _rankColor(widget.rank);
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: .24)),
          gradient: LinearGradient(
            begin: Alignment(-1 + (_shimmer.value * 2), 0),
            end: Alignment(_shimmer.value * 2, 0),
            colors: [
              color.withValues(alpha: .06),
              Colors.white.withValues(alpha: .16 * (1 - _shimmer.value)),
              color.withValues(alpha: .06),
            ],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.rank.toLowerCase() == 'knight') ...[
              Icon(Icons.shield_outlined, color: color, size: 11),
              const SizedBox(width: 4),
            ],
            Text(
              widget.rank,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderRating extends StatelessWidget {
  final double rating;
  const _RiderRating({required this.rating});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeOut,
        builder: (context, value, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(
              5,
              (index) => Icon(
                Icons.star_rounded,
                color: const Color(0xFFF5C451).withValues(
                  alpha: value >= ((index + 1) / 5) ? 1 : .28,
                ),
                size: 11,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              rating.toStringAsFixed(2),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

class _RiderTrustBadge extends StatelessWidget {
  final String label;
  final bool vanguard;
  const _RiderTrustBadge({required this.label, required this.vanguard});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            vanguard ? Icons.shield_outlined : Icons.verified_rounded,
            color: vanguard ? const Color(0xFF60A5FA) : const Color(0xFF31D17D),
            size: 15,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.inter(
              color: const Color(0xFFD9E2F0),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
}

void _showRiderProfile(
  BuildContext context,
  SenderActivityItem item,
  String riderName,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _RiderProfileSheet(item: item, riderName: riderName),
  );
}

class _RiderProfileSheet extends StatelessWidget {
  final SenderActivityItem item;
  final String riderName;
  const _RiderProfileSheet({required this.item, required this.riderName});

  @override
  Widget build(BuildContext context) {
    final trustLabel = item.riderVanguardApproved
        ? 'Vanguard Approved Rider'
        : item.riderTrusted
            ? 'Trusted Circum Rider'
            : null;
    return Semantics(
      label: '$riderName rider profile',
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1020),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .35),
              blurRadius: 30,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 22),
              _RiderAvatar(name: riderName, photoUrl: item.riderPhotoUrl),
              const SizedBox(height: 12),
              Text(
                riderName,
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontSize: 26,
                ),
              ),
              if (item.riderRank.isNotEmpty) ...[
                const SizedBox(height: 8),
                _RiderRankBadge(rank: item.riderRank),
              ],
              if (item.riderRating != null && item.riderRating! > 0) ...[
                const SizedBox(height: 12),
                _RiderRating(rating: item.riderRating!),
              ],
              if (trustLabel != null) ...[
                const SizedBox(height: 14),
                _RiderTrustBadge(
                  label: trustLabel,
                  vanguard: item.riderVanguardApproved,
                ),
              ],
              if (item.riderCompletedDeliveries != null ||
                  item.riderMemberSince != null ||
                  item.riderAchievements.isNotEmpty) ...[
                const SizedBox(height: 22),
                Divider(color: Colors.white.withValues(alpha: .08), height: 1),
                const SizedBox(height: 16),
                if (item.riderCompletedDeliveries != null)
                  _RiderSheetLine(
                    label: 'Completed deliveries',
                    value: '${item.riderCompletedDeliveries}',
                  ),
                if (item.riderMemberSince != null)
                  _RiderSheetLine(
                    label: 'Member since',
                    value:
                        DateFormat('MMMM yyyy').format(item.riderMemberSince!),
                  ),
                if (item.riderAchievements.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Recent achievements',
                      style: GoogleFonts.inter(
                        color: _ActivityColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...item.riderAchievements.map(
                    (achievement) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_outlined,
                            color: Color(0xFF60A5FA),
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              achievement,
                              style: GoogleFonts.inter(
                                color: const Color(0xFFD9E2F0),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RiderSheetLine extends StatelessWidget {
  final String label;
  final String value;
  const _RiderSheetLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: _ActivityColors.muted,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

class _TrustFeature extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _TrustFeature({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (icon == Icons.blur_circular_rounded)
            _IrisActivityOrb(color: color)
          else
            Icon(icon, color: color, size: 15),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              color: const Color(0xFFD9E2F0),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
}

class _IrisActivityOrb extends StatefulWidget {
  final Color color;
  const _IrisActivityOrb({required this.color});

  @override
  State<_IrisActivityOrb> createState() => _IrisActivityOrbState();
}

class _IrisActivityOrbState extends State<_IrisActivityOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-.35, -.45),
              colors: [
                Colors.white.withValues(alpha: .9),
                widget.color.withValues(alpha: .72),
                const Color(0xFF60A5FA).withValues(alpha: .55),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(
                  alpha: .14 + (_controller.value * .12),
                ),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      );
}

class ActivityReceiptView extends StatelessWidget {
  final SenderActivityItem item;
  const ActivityReceiptView({super.key, required this.item});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _ActivityColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Delivery Receipt'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _ActivityGlass(
              child: Column(
                children: [
                  _Detail('Delivery', item.title),
                  _Detail('Status', item.status),
                  if (item.pickup.isNotEmpty) _Detail('Pickup', item.pickup),
                  if (item.destination.isNotEmpty)
                    _Detail('Drop-off', item.destination),
                  _Detail(
                    'Completed',
                    item.occurredAt == null
                        ? 'Pending timestamp'
                        : DateFormat('d MMMM yyyy, HH:mm')
                            .format(item.occurredAt!),
                  ),
                  if (item.amount != null)
                    _Detail(
                        'Amount paid', '£${item.amount!.toStringAsFixed(2)}'),
                  _Detail(
                    'Rider',
                    item.rider.isEmpty ? 'Circum Rider' : item.rider,
                  ),
                  if (item.vanguardProtected)
                    const _Detail('Protection', 'Vanguard Protected'),
                  if (item.irisVerified)
                    const _Detail('Classification', 'IRIS Verified'),
                ],
              ),
            ),
          ],
        ),
      );
}

class ActivityStatusBadge extends StatelessWidget {
  final String status;
  final SenderActivityType type;
  const ActivityStatusBadge({
    super.key,
    required this.status,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final highContrast =
        SenderAccessibilityScope.maybeOf(context)?.settings.highContrast ??
            false;
    final color = _statusColor(status, type);
    return Align(
      alignment: Alignment.centerLeft,
      child: AppStatusBadge(
        label: status,
        color: color,
        highContrast: highContrast,
      ),
    );
  }
}

class ActivityIcon extends StatefulWidget {
  final SenderActivityType type;
  final String status;
  final bool tracking;
  const ActivityIcon({
    super.key,
    required this.type,
    required this.status,
    this.tracking = false,
  });

  @override
  State<ActivityIcon> createState() => _ActivityIconState();
}

class _ActivityIconState extends State<ActivityIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final seconds = widget.type == SenderActivityType.gift
        ? 12
        : widget.type == SenderActivityType.health
            ? 8
            : 5;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: seconds),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highContrast =
        SenderAccessibilityScope.maybeOf(context)?.settings.highContrast ??
            false;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final completed = _isCompletedStatus(widget.status);
        final pulse = widget.type == SenderActivityType.health
            ? 1 + (.035 * (1 - ((_controller.value * 2) - 1).abs()))
            : 1.0;
        final glow = widget.type == SenderActivityType.roth
            ? .10 + (_controller.value * .08)
            : .06;
        return Transform.scale(
          scale: pulse,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: highContrast ? .11 : .05),
              border: Border.all(
                color: Colors.white.withValues(alpha: highContrast ? .22 : .08),
                width: highContrast ? 1.3 : 1,
              ),
              gradient: RadialGradient(
                center: const Alignment(-.35, -.45),
                colors: [
                  Colors.white.withValues(alpha: .11),
                  _statusColor(widget.status, widget.type)
                      .withValues(alpha: highContrast ? .32 : glow),
                  Colors.transparent,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _statusColor(widget.status, widget.type)
                      .withValues(alpha: highContrast ? .34 : glow),
                  blurRadius: highContrast ? 20 : 16,
                ),
              ],
            ),
            child: Icon(
              _activityIcon(
                type: widget.type,
                status: widget.status,
                tracking: widget.tracking,
                completed: completed,
              ),
              size: highContrast ? 23 : 21,
              color: highContrast
                  ? Colors.white
                  : _statusColor(widget.status, widget.type),
            ),
          ),
        );
      },
    );
  }
}

class ActivityTimeline extends StatelessWidget {
  final Map<String, List<SenderActivityItem>> groups;
  const ActivityTimeline({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    final highContrast =
        SenderAccessibilityScope.maybeOf(context)?.settings.highContrast ??
            false;
    return Column(
      children: groups.entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ActivitySectionHeader(title: entry.key),
                  const SizedBox(height: 12),
                  ...List.generate(entry.value.length, (index) {
                    final item = entry.value[index];
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 18,
                            child: Column(
                              children: [
                                Container(
                                  width: highContrast ? 9 : 7,
                                  height: highContrast ? 9 : 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _statusColor(item.status, item.type),
                                  ),
                                ),
                                if (index < entry.value.length - 1)
                                  Expanded(
                                    child: Container(
                                      width: highContrast ? 2 : 1,
                                      color: Colors.white.withValues(
                                        alpha: highContrast ? .28 : .09,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: ActivityCard(item: item),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class ActivitySectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const ActivitySectionHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.dmSerifDisplay(
                color: Colors.white,
                fontSize: 20,
              ),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: GoogleFonts.inter(
                color: _ActivityColors.muted,
                fontSize: 11,
              ),
            ),
        ],
      );
}

class _ActivityDetail extends StatelessWidget {
  final SenderActivityItem item;
  const _ActivityDetail({required this.item});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _ActivityColors.bg,
        appBar: AppBar(
            backgroundColor: Colors.transparent, title: Text(item.title)),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          _ActivityGlass(
              child: Column(children: [
            _Detail('Order ID', item.id),
            _Detail('Service', _typeLabel(item.type)),
            _Detail('Status', item.status),
            if (item.pickup.isNotEmpty) _Detail('Pickup', item.pickup),
            if (item.destination.isNotEmpty)
              _Detail('Destination', item.destination),
            if (item.amount != null)
              _Detail('Amount paid', '£${item.amount!.toStringAsFixed(2)}'),
            if (item.rothAmount != null)
              _Detail('Roth', '${item.rothAmount!.toStringAsFixed(2)} Roth'),
            _Detail(
                'Date',
                item.occurredAt == null
                    ? 'Pending'
                    : DateFormat('d MMM yyyy, HH:mm').format(item.occurredAt!)),
          ])),
        ]),
      );
}

class ActivityEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  const ActivityEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.primaryLabel,
    this.onPrimary,
  });

  @override
  Widget build(BuildContext context) => _ActivityGlass(
          child: Column(children: [
        const SizedBox(height: 8),
        const _AnimatedActivityPath(),
        const SizedBox(height: 18),
        Text(
          title,
          style: GoogleFonts.dmSerifDisplay(color: Colors.white, fontSize: 24),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: _ActivityColors.muted,
            height: 1.5,
          ),
        ),
        if (primaryLabel != null && onPrimary != null) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPrimary,
              child: Text(primaryLabel!),
            ),
          ),
        ],
      ]));
}

class _AnimatedActivityPath extends StatefulWidget {
  const _AnimatedActivityPath();
  @override
  State<_AnimatedActivityPath> createState() => _AnimatedActivityPathState();
}

class _AnimatedActivityPathState extends State<_AnimatedActivityPath>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 92,
      child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => CustomPaint(
              painter: _PathPainter(_controller.value),
              size: const Size(double.infinity, 92))));
}

class _PathPainter extends CustomPainter {
  final double progress;
  const _PathPainter(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(20, size.height - 18)
      ..cubicTo(size.width * .32, 8, size.width * .65, size.height - 8,
          size.width - 20, 18);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white12
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
        metric.extractPath(0, metric.length * progress),
        Paint()
          ..color = _ActivityColors.blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
    final point =
        metric.getTangentForOffset(metric.length * progress)?.position;
    if (point != null) {
      canvas.drawCircle(point, 7, Paint()..color = _ActivityColors.green);
    }
  }

  @override
  bool shouldRepaint(_PathPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();
  @override
  Widget build(BuildContext context) => Column(
      children: List.generate(
          4,
          (index) => const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _ActivityGlass(
                  child: SizedBox(
                      height: 64,
                      child: LinearProgressIndicator(
                          color: _ActivityColors.blue,
                          backgroundColor: Colors.transparent))))));
}

class _ActivityError extends StatelessWidget {
  final VoidCallback onRetry;
  const _ActivityError({required this.onRetry});
  @override
  Widget build(BuildContext context) => _ActivityGlass(
          child: Column(children: [
        const Text('Activity could not load.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Retry'))
      ]));
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(this.label, {required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
          label: Text(label), selected: selected, onSelected: (_) => onTap()));
}

class _RouteLine extends StatelessWidget {
  final String label;
  final String value;
  const _RouteLine({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(color: _ActivityColors.muted))),
        Expanded(
            child: Text(value.isEmpty ? 'Updating' : value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)))
      ]));
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;
  const _Detail(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(color: _ActivityColors.muted))),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)))
      ]));
}

class _ActivityGlass extends StatelessWidget {
  final Widget child;
  const _ActivityGlass({required this.child});
  @override
  Widget build(BuildContext context) => AppGlassContainer(
        padding: const EdgeInsets.all(AppTokens.space20),
        accent: AppTokens.primary,
        highContrast:
            SenderAccessibilityScope.maybeOf(context)?.settings.highContrast ??
                false,
        child: child,
      );
}

void _openTracking(BuildContext context, SenderActivityItem item) {
  context.read<SendPackageBloc>().add(WatchActiveDelivery(requestId: item.id));
  Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SenderBookingCanvas()));
}

void _openChat(BuildContext context, SenderActivityItem item) {
  context.read<SendPackageBloc>().add(WatchActiveDelivery(requestId: item.id));
  Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RideChatPageView(chatId: item.id)));
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
String _first(List<Object?> values) {
  for (final value in values) {
    final text = '${value ?? ''}'.trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

String _riderId(Map<String, dynamic> data) {
  final assigned = _map(data['assignedRider']);
  return _first([
    data['riderId'],
    data['driverId'],
    data['courierId'],
    assigned['userId'],
    assigned['uid'],
    assigned['id'],
  ]);
}

String _riderFirstName(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  return text.split(RegExp(r'\s+')).first;
}

String _riderRankLabel(String value) {
  const ranks = {'agent', 'sentinel', 'warden', 'knight', 'veteran'};
  final normalized = value.trim().toLowerCase();
  if (!ranks.contains(normalized)) return '';
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

Color _rankColor(String rank) => switch (rank.toLowerCase()) {
      'agent' => const Color(0xFF94A3B8),
      'sentinel' => const Color(0xFF60A5FA),
      'warden' => const Color(0xFF10B981),
      'knight' => const Color(0xFFA78BFA),
      'veteran' => const Color(0xFFF5C451),
      _ => const Color(0xFF94A3B8),
    };

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

int? _optionalInt(Object? value) {
  final parsed = _number(value)?.round();
  return parsed != null && parsed >= 0 ? parsed : null;
}

bool _riderTrusted(Map<String, dynamic> profile) {
  if (profile['approved'] == true || profile['isApproved'] == true) return true;
  final status = _first([
    profile['verificationStatus'],
    profile['approvalStatus'],
    profile['onboardingStatus'],
  ]).toLowerCase();
  return status == 'approved' || status == 'verified' || status == 'active';
}

List<String> _safeAchievementLabels(Object? value) {
  if (value is! List) return const [];
  return value
      .map((entry) => entry is Map
          ? _first([entry['label'], entry['title'], entry['name']])
          : '$entry'.trim())
      .where((label) => label.isNotEmpty && label.length <= 80)
      .take(3)
      .toList(growable: false);
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse('${value ?? ''}');
}

String _status(String value) {
  final text = value.trim().replaceAll('_', ' ');
  return text.isEmpty
      ? 'Pending'
      : text
          .split(' ')
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
}

String _typeLabel(SenderActivityType type) => switch (type) {
      SenderActivityType.parcel => 'Parcels',
      SenderActivityType.gift => 'Gifts',
      SenderActivityType.health => 'Health+',
      SenderActivityType.business => 'Business',
      SenderActivityType.roth => 'Roth'
    };
String _filterLabel(SenderActivityType type) => _typeLabel(type);
IconData _typeIcon(SenderActivityType type) => switch (type) {
      SenderActivityType.parcel => Icons.inventory_2_outlined,
      SenderActivityType.gift => Icons.redeem_rounded,
      SenderActivityType.health => Icons.health_and_safety_rounded,
      SenderActivityType.business => Icons.apartment_rounded,
      SenderActivityType.roth => Icons.blur_circular_rounded,
    };
double _progress(String status) {
  final value = status.toLowerCase();
  if (value.contains('delivered')) return 1;
  if (value.contains('transit') || value.contains('collected')) return .7;
  if (value.contains('pickup') || value.contains('arrived')) return .45;
  if (value.contains('assigned') || value.contains('accepted')) return .25;
  return .1;
}

Map<String, List<SenderActivityItem>> _grouped(List<SenderActivityItem> items) {
  final now = DateTime.now();
  final result = <String, List<SenderActivityItem>>{};
  for (final item in items) {
    final date = item.occurredAt ?? DateTime(1970);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final difference = today.difference(day).inDays;
    final key = difference == 0
        ? 'Today'
        : difference == 1
            ? 'Yesterday'
            : difference < 7
                ? 'Earlier'
                : date.year == now.year && date.month == now.month
                    ? 'This Month'
                    : 'Previous Months';
    result.putIfAbsent(key, () => []).add(item);
  }
  return result;
}

class _ActivityColors {
  static const bg = Color(0xFF07090F);
  static const blue = Color(0xFF60A5FA);
  static const green = Color(0xFF31D17D);
  static const muted = Color(0xFF9CA3AF);
}

bool senderActivityIsLiveDeliveryStatus(String value) {
  const live = {
    'requested',
    'finding_rider',
    'broadcasting',
    'accepted',
    'rider_assigned',
    'rider_en_route',
    'navigating_to_pickup',
    'arriving_at_pickup',
    'arrived_at_pickup',
    'pickup_verified',
    'picked_up',
    'pickup_complete',
    'collected',
    'in_transit',
    'navigating_to_dropoff',
    'arriving_at_dropoff',
    'arrived_at_dropoff',
    'waiting_for_recipient',
    'delivery_confirmation',
  };
  return live.contains(value.trim().toLowerCase());
}

IconData _activityIcon({
  required SenderActivityType type,
  required String status,
  required bool tracking,
  required bool completed,
}) {
  final value = status.toLowerCase();
  if (completed) return Icons.check_circle_rounded;
  if (value.contains('cancel') ||
      value.contains('failed') ||
      value.contains('reject')) {
    return Icons.close_rounded;
  }
  if (value.contains('draft')) return Icons.description_outlined;
  if (value.contains('review') || value.contains('approval')) {
    return Icons.fact_check_outlined;
  }
  if (tracking) return Icons.navigation_rounded;
  return _typeIcon(type);
}

bool _isCompletedStatus(String status) {
  final value = status.toLowerCase();
  return value.contains('delivered') || value.contains('completed');
}

bool _isCompletedDelivery(SenderActivityItem item) =>
    (item.type == SenderActivityType.parcel ||
        item.type == SenderActivityType.business) &&
    _isCompletedStatus(item.status);

Color _statusColor(String status, SenderActivityType type) {
  final value = status.toLowerCase();
  if (value.contains('cancel') ||
      value.contains('failed') ||
      value.contains('reject')) {
    return const Color(0xFFEF4444);
  }
  if (value.contains('expired') || value.contains('archived')) {
    return const Color(0xFF94A3B8);
  }
  if (value.contains('draft')) return const Color(0xFFF59E0B);
  if (_isCompletedStatus(value)) return const Color(0xFF31D17D);
  if (type == SenderActivityType.gift) return const Color(0xFFA855F7);
  if (type == SenderActivityType.health) return const Color(0xFF10B981);
  if (type == SenderActivityType.business) return const Color(0xFF38BDF8);
  return const Color(0xFF60A5FA);
}

String _activityDate(DateTime? date) {
  if (date == null) return 'Date pending';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  final time = DateFormat('HH:mm').format(date);
  if (difference == 0) return 'Today · $time';
  if (difference == 1) return 'Yesterday · $time';
  return '${DateFormat('d MMM yyyy').format(date)} · $time';
}
