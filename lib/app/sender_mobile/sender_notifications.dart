import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'design_system/sender_design_system.dart';

const _notificationFilters = <String>[
  'All',
  'Deliveries',
  'Wallet',
  'Health+',
  'Gifts',
  'Business',
  'System',
];

class CircumNotification {
  final String id;
  final String title;
  final String body;
  final String category;
  final bool read;
  final bool archived;
  final DateTime? createdAt;
  final Map<String, dynamic> destination;

  const CircumNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.read,
    required this.archived,
    required this.destination,
    this.createdAt,
  });

  factory CircumNotification.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final rawDestination = data['destination'] ??
        (data['data'] is Map ? (data['data'] as Map)['destination'] : null);
    return CircumNotification(
      id: document.id,
      title: '${data['title'] ?? 'Circum update'}'.trim(),
      body: '${data['body'] ?? data['message'] ?? ''}'.trim(),
      category: '${data['category'] ?? 'system'}'.trim().toLowerCase(),
      read: data['read'] == true,
      archived: data['archived'] == true || data['deletedAt'] != null,
      destination: rawDestination is Map
          ? Map<String, dynamic>.from(rawDestination)
          : const <String, dynamic>{},
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class SenderNotificationsRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  SenderNotificationsRepository(
      {FirebaseAuth? auth,
      FirebaseFirestore? firestore,
      FirebaseFunctions? functions})
      : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instance;

  Stream<List<CircumNotification>> watchNotifications() {
    final uid = auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return firestore
        .collection('notifications')
        .where('recipientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      final results = snapshot.docs
          .map(CircumNotification.fromDocument)
          .where((notification) => !notification.archived)
          .toList();
      return results;
    });
  }

  Future<void> markRead(String id) => _updateNotificationState(
        action: 'mark_read',
        ids: [id],
      );

  Future<void> markAllRead(Iterable<String> ids) => _updateNotificationState(
        action: 'mark_read',
        ids: ids,
      );

  Future<void> archive(String id) => _updateNotificationState(
        action: 'archive',
        ids: [id],
      );

  Future<void> delete(String id) => _updateNotificationState(
        action: 'delete',
        ids: [id],
      );

  Future<void> _updateNotificationState({
    required String action,
    required Iterable<String> ids,
  }) async {
    final cleanIds =
        ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
    if (cleanIds.isEmpty) return;
    await functions.httpsCallable('updateSenderNotificationState').call({
      'action': action,
      'notificationIds': cleanIds,
    });
  }
}

class SenderNotificationsView extends StatefulWidget {
  final SenderNotificationsRepository? repository;
  final ValueChanged<CircumNotification>? onOpenNotification;

  const SenderNotificationsView({
    super.key,
    this.repository,
    this.onOpenNotification,
  });

  @override
  State<SenderNotificationsView> createState() =>
      _SenderNotificationsViewState();
}

class _SenderNotificationsViewState extends State<SenderNotificationsView> {
  late final SenderNotificationsRepository _repository;
  var _filter = 'All';

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SenderNotificationsRepository();
  }

  String _categoryForFilter(String label) => switch (label) {
        'Health+' => 'health',
        'Deliveries' => 'deliveries',
        _ => label.toLowerCase(),
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTokens.background,
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            StreamBuilder<List<CircumNotification>>(
              stream: _repository.watchNotifications(),
              builder: (context, snapshot) {
                final unread = (snapshot.data ?? const [])
                    .where((item) => !item.read)
                    .map((item) => item.id);
                return TextButton(
                  onPressed: unread.isEmpty
                      ? null
                      : () => _repository.markAllRead(unread),
                  child: const Text('Mark all read'),
                );
              },
            ),
          ],
        ),
        body: StreamBuilder<List<CircumNotification>>(
          stream: _repository.watchNotifications(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AppEmptyState(
                title: 'Notifications are unavailable',
                body: 'Check your connection and try again.',
                icon: Icons.notifications_off_outlined,
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final notifications = snapshot.data!;
            final visible = _filter == 'All'
                ? notifications
                : notifications
                    .where(
                        (item) => item.category == _categoryForFilter(_filter))
                    .toList();
            return Column(
              children: [
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.space16),
                    itemCount: _notificationFilters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final label = _notificationFilters[index];
                      return ChoiceChip(
                        label: Text(label),
                        selected: _filter == label,
                        onSelected: (_) => setState(() => _filter = label),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? const AppEmptyState(
                          title: 'No notifications yet',
                          body:
                              'Delivery, Wallet, Gifts and Health+ updates will appear here.',
                          icon: Icons.notifications_none_rounded,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppTokens.space16),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) => _NotificationCard(
                            notification: visible[index],
                            onOpen: () async {
                              await _repository.markRead(visible[index].id);
                              if (mounted) {
                                widget.onOpenNotification?.call(visible[index]);
                              }
                            },
                            onArchive: () =>
                                _repository.archive(visible[index].id),
                            onDelete: () =>
                                _repository.delete(visible[index].id),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      );
}

class _NotificationCard extends StatelessWidget {
  final CircumNotification notification;
  final VoidCallback onOpen;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _NotificationCard({
    required this.notification,
    required this.onOpen,
    required this.onArchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Dismissible(
        key: ValueKey(notification.id),
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          color: AppTokens.warning,
          child: const Icon(Icons.archive_outlined),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          color: AppTokens.danger,
          child: const Icon(Icons.delete_outline),
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            onArchive();
          } else {
            onDelete();
          }
          return false;
        },
        child: AppCard(
          onTap: onOpen,
          child: Semantics(
            button: true,
            label:
                '${notification.read ? 'Read' : 'Unread'} notification. ${notification.title}. ${notification.body}',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NotificationTypeIcon(category: notification.category),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                                letterSpacing: .1,
                              ),
                            ),
                          ),
                          if (!notification.read)
                            Container(
                              margin: const EdgeInsets.only(left: 10, top: 3),
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: AppTokens.primaryLight,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTokens.primary
                                        .withValues(alpha: .28),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (notification.body.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(notification.body,
                            style: const TextStyle(
                                color: AppTokens.mutedText, height: 1.4)),
                      ],
                      if (notification.createdAt != null) ...[
                        const SizedBox(height: 10),
                        Text(_relativeDate(notification.createdAt!),
                            style: const TextStyle(
                              color: AppTokens.mutedText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  static IconData _iconFor(String category) => switch (category) {
        'deliveries' => Icons.local_shipping_outlined,
        'delivery' => Icons.local_shipping_outlined,
        'parcel' => Icons.inventory_2_outlined,
        'wallet' => Icons.account_balance_wallet_outlined,
        'trust' => Icons.verified_user_outlined,
        'health' => Icons.health_and_safety_outlined,
        'gifts' => Icons.card_giftcard_outlined,
        'gift' => Icons.card_giftcard_outlined,
        'business' => Icons.business_outlined,
        _ => Icons.info_outline_rounded,
      };

  static String _relativeDate(DateTime value) {
    final now = DateTime.now();
    final day = DateTime(value.year, value.month, value.day);
    if (day == DateTime(now.year, now.month, now.day)) {
      return 'Today';
    }
    if (day ==
        DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    return '${value.day}/${value.month}/${value.year}';
  }
}

class _NotificationTypeIcon extends StatelessWidget {
  final String category;

  const _NotificationTypeIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    final icon = _NotificationCard._iconFor(category);
    final accent = _accentFor(category);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withValues(alpha: .22)),
      ),
      child: Icon(icon, color: accent, size: 22),
    );
  }

  static Color _accentFor(String category) => switch (category) {
        'deliveries' => AppTokens.primaryLight,
        'delivery' => AppTokens.primaryLight,
        'parcel' => AppTokens.primaryLight,
        'wallet' => AppTokens.success,
        'gifts' => AppTokens.warning,
        'gift' => AppTokens.warning,
        'business' => AppTokens.primary,
        'trust' => AppTokens.warning,
        _ => AppTokens.mutedText,
      };
}
