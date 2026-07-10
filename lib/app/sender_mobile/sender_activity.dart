import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../send_package/bloc/send_package_bloc.dart';
import '../send_package/view/ride_chats.dart';
import 'sender_booking_canvas.dart';
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
  });
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
      items.sort((a, b) => (a.occurredAt ?? DateTime(1970))
          .compareTo(b.occurredAt ?? DateTime(1970)));
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
    final merged = <SenderActivityItem>[
      ...deliveries.docs.map((doc) => _delivery(doc.id, doc.data())),
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

  SenderActivityItem _delivery(String id, Map<String, dynamic> data) {
    final pickup = _map(data['pickupDetails'] ?? data['pickup']);
    final dropoff = _map(data['dropoffDetails'] ?? data['dropoff']);
    final parcel = _map(data['parcel'] ?? data['package']);
    final status = '${data['deliveryStatus'] ?? data['status'] ?? 'requested'}';
    final normalized = status.toLowerCase();
    const terminal = {
      'delivered',
      'completed',
      'cancelled',
      'cancelled_admin',
      'failed',
      'archived_stale',
      'admin_removed_stale',
    };
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
      rider:
          _first([data['riderName'], data['driverName'], data['courierName']]),
      eta: _first([data['estimatedDeliveryTime'], data['eta']]),
      amount:
          _number(data['paidAmount'] ?? data['price'] ?? data['totalAmount']),
      occurredAt: _date(data['updatedAt'] ?? data['createdAt']),
      active: !terminal.contains(normalized),
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

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseSenderActivityRepository();
    _activeSubscription = _repository.watchActive().listen(
          (items) => mounted ? setState(() => _active = items) : null,
          onError: (_) {},
        );
    _load();
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
          const Text('Activity',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          if (_loading) const _ActivitySkeleton(),
          if (!_loading && _error != null) _ActivityError(onRetry: _load),
          if (!_loading &&
              _error == null &&
              _active.isEmpty &&
              _history.isEmpty)
            _ActivityEmpty(
                onSend: widget.onSendParcel, onGifts: widget.onExploreGifts),
          if (!_loading &&
              _error == null &&
              (_active.isNotEmpty || _history.isNotEmpty)) ...[
            if (_active.isNotEmpty) ...[
              const _ActivityHeading('Live Activity'),
              const SizedBox(height: 10),
              ..._active.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _LiveActivityCard(item: item),
                  )),
              const SizedBox(height: 10),
            ],
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
              const _ActivityGlass(
                  child: Text('No matching activity.',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)))
            else
              ..._grouped(_visible).entries.expand((entry) => [
                    _ActivityHeading(entry.key),
                    const SizedBox(height: 8),
                    ...entry.value.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ActivityCard(item: item),
                        )),
                    const SizedBox(height: 8),
                  ]),
            if (_nextPage != null)
              TextButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child:
                      Text(_loadingMore ? 'Loading…' : 'Load more activity')),
          ],
        ],
      );
}

class _LiveActivityCard extends StatelessWidget {
  final SenderActivityItem item;
  const _LiveActivityCard({required this.item});

  @override
  Widget build(BuildContext context) => _ActivityGlass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.delivery_dining_rounded,
                color: _ActivityColors.blue),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    item.rider.isEmpty ? 'Finding your rider' : item.rider,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900))),
            Text(item.eta.isEmpty ? item.status : item.eta,
                style: const TextStyle(
                    color: _ActivityColors.green, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 14),
          Text(item.status,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          _RouteLine(label: 'Pickup', value: item.pickup),
          _RouteLine(label: 'Drop-off', value: item.destination),
          const SizedBox(height: 12),
          LinearProgressIndicator(
              value: _progress(item.status),
              minHeight: 5,
              color: _ActivityColors.green,
              backgroundColor: Colors.white10),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: FilledButton(
                    onPressed: () => _openTracking(context, item),
                    child: const Text('Live Tracking'))),
            const SizedBox(width: 10),
            OutlinedButton(
                onPressed: () => _openChat(context, item),
                child: const Text('Chat')),
          ]),
        ]),
      );
}

class _ActivityCard extends StatelessWidget {
  final SenderActivityItem item;
  const _ActivityCard({required this.item});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _ActivityDetail(item: item))),
        child: _ActivityGlass(
          child: Row(children: [
            Icon(_typeIcon(item.type), color: _ActivityColors.blue),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item.title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                      [item.status, item.destination]
                          .where((value) => value.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(
                          color: _ActivityColors.muted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                      item.occurredAt == null
                          ? 'Date pending'
                          : DateFormat('d MMM · HH:mm')
                              .format(item.occurredAt!),
                      style: const TextStyle(
                          color: _ActivityColors.muted, fontSize: 11)),
                ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (item.amount != null)
                Text('£${item.amount!.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900)),
              if (item.rothAmount != null && item.rothAmount! > 0)
                Text(
                    '${item.rothDirection == 'credit' ? '+' : '-'}${item.rothAmount!.toStringAsFixed(2)} Roth',
                    style: const TextStyle(
                        color: _ActivityColors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
            ]),
          ]),
        ),
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

class _ActivityEmpty extends StatelessWidget {
  final VoidCallback onSend;
  final VoidCallback onGifts;
  const _ActivityEmpty({required this.onSend, required this.onGifts});
  @override
  Widget build(BuildContext context) => _ActivityGlass(
          child: Column(children: [
        const SizedBox(height: 8),
        const _AnimatedActivityPath(),
        const SizedBox(height: 18),
        const Text('No activity yet',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text(
            'Your deliveries, gifts, Health+ requests and business activity will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _ActivityColors.muted, height: 1.45)),
        const SizedBox(height: 20),
        SizedBox(
            width: double.infinity,
            child: FilledButton(
                onPressed: onSend, child: const Text('Send a Parcel'))),
        TextButton(onPressed: onGifts, child: const Text('Explore Gifts')),
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

class _ActivityHeading extends StatelessWidget {
  final String text;
  const _ActivityHeading(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900));
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
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .12))),
              child: child)));
}

void _openTracking(BuildContext context, SenderActivityItem item) {
  context.read<SendPackageBloc>().add(WatchActiveDelivery(requestId: item.id));
  Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SenderBookingCanvas()));
}

void _openChat(BuildContext context, SenderActivityItem item) {
  context.read<SendPackageBloc>().add(WatchActiveDelivery(requestId: item.id));
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const RideChatPageView()));
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

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');
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
      SenderActivityType.parcel => Icons.local_shipping_outlined,
      SenderActivityType.gift => Icons.card_giftcard_rounded,
      SenderActivityType.health => Icons.health_and_safety_outlined,
      SenderActivityType.business => Icons.business_center_outlined,
      SenderActivityType.roth => Icons.auto_awesome_rounded
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
                ? 'This Week'
                : 'Earlier';
    result.putIfAbsent(key, () => []).add(item);
  }
  return result;
}

class _ActivityColors {
  static const bg = Color(0xFF07090F);
  static const blue = Color(0xFF60A5FA);
  static const green = Color(0xFF34D399);
  static const muted = Color(0xFF9CA3AF);
}
