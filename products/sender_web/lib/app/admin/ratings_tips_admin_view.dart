import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'admin_operations.dart';

class AdminRatingsTipsView extends StatefulWidget {
  const AdminRatingsTipsView({super.key, this.embedded = false});

  static const routeName = '/ratings-tips';
  final bool embedded;

  @override
  State<AdminRatingsTipsView> createState() => _AdminRatingsTipsViewState();
}

class _AdminRatingsTipsViewState extends State<AdminRatingsTipsView> {
  final _search = TextEditingController();
  int? _stars;
  var _filter = AdminRatingTipFilter.all;
  String? _message;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _body();
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: const Color(0xFF07090F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D111C),
        foregroundColor: Colors.white,
        title: const Text('Ratings & Tips'),
      ),
      body: body,
    );
  }

  Widget _body() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('driverRatings')
            .limit(250)
            .snapshots(),
        builder: (context, ratingSnapshot) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('deliveryTips')
                .limit(250)
                .snapshots(),
            builder: (context, tipSnapshot) {
              if (ratingSnapshot.hasError || tipSnapshot.hasError) {
                return _state(
                  Icons.error_outline_rounded,
                  'Ratings are unavailable',
                  'Check your Admin access and try again.',
                );
              }
              if (!ratingSnapshot.hasData || !tipSnapshot.hasData) {
                return _state(
                  Icons.hourglass_top_rounded,
                  'Loading ratings and tips',
                  'Secure records are being prepared.',
                  loading: true,
                );
              }
              final tips = {
                for (final doc in tipSnapshot.data!.docs)
                  '${doc.data()['deliveryId'] ?? doc.id}': doc.data(),
              };
              final records = ratingSnapshot.data!.docs
                  .map((doc) => AdminRatingTipRecord.fromBackend(
                        ratingId: doc.id,
                        rating: doc.data(),
                        tip: tips['${doc.data()['deliveryId'] ?? doc.id}'] ??
                            const {},
                      ))
                  .toList();
              final visible = AdminRatingsTipsPolicy.filter(
                records,
                search: _search.text,
                stars: _stars,
                filter: _filter,
              );
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text('Ratings & Tips Management',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                        'Review immutable Sender appreciation, payment status and moderation history.',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .58)),
                      ),
                      const SizedBox(height: 20),
                      _filters(),
                      if (_message != null) ...[
                        const SizedBox(height: 10),
                        Text(_message!,
                            style: const TextStyle(color: Color(0xFF34D399))),
                      ],
                      const SizedBox(height: 18),
                      if (visible.isEmpty)
                        _state(
                          Icons.star_outline_rounded,
                          'No matching appreciation',
                          'Try another Rider, Sender, delivery or filter.',
                        )
                      else
                        ...visible.map(_record),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

  Widget _filters() => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              decoration: _input('Search Rider, Sender or delivery',
                  icon: Icons.search_rounded),
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<int?>(
              initialValue: _stars,
              dropdownColor: const Color(0xFF141A29),
              style: const TextStyle(color: Colors.white),
              decoration: _input('Stars'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All stars')),
                ...List.generate(
                  5,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('${index + 1} stars'),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _stars = value),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<AdminRatingTipFilter>(
              initialValue: _filter,
              dropdownColor: const Color(0xFF141A29),
              style: const TextStyle(color: Colors.white),
              decoration: _input('Tip status'),
              items: const [
                DropdownMenuItem(
                    value: AdminRatingTipFilter.all, child: Text('All')),
                DropdownMenuItem(
                    value: AdminRatingTipFilter.tipped, child: Text('Tipped')),
                DropdownMenuItem(
                    value: AdminRatingTipFilter.notTipped,
                    child: Text('Not tipped')),
                DropdownMenuItem(
                    value: AdminRatingTipFilter.reported,
                    child: Text('Reported')),
              ],
              onChanged: (value) => setState(() => _filter = value!),
            ),
          ),
        ],
      );

  Widget _record(AdminRatingTipRecord record) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xE6141926),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Wrap(
          runSpacing: 14,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(List.filled(record.stars, '★').join(),
                        style: const TextStyle(
                            color: Color(0xFFFBBF24), fontSize: 18)),
                    const SizedBox(width: 10),
                    Text('Ref ${record.deliveryId}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                      record.feedback.isEmpty
                          ? 'No written feedback'
                          : record.feedback,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .68),
                          fontStyle: record.feedback.isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal)),
                  const SizedBox(height: 10),
                  Text(
                    'Rider ${record.riderId}  ·  Sender ${record.senderId}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .38),
                        fontSize: 11),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 170,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      record.tipped
                          ? '£${record.tipAmount.toStringAsFixed(2)} tip'
                          : 'No tip',
                      style: TextStyle(
                          color: record.tipped
                              ? const Color(0xFF34D399)
                              : Colors.white,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(
                      record.paymentMethod.isEmpty
                          ? 'No payment'
                          : record.paymentMethod.replaceAll('_', ' '),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .45),
                          fontSize: 11)),
                  if (record.reported) ...[
                    const SizedBox(height: 5),
                    Text(record.reportStatus,
                        style: const TextStyle(color: Color(0xFFFBBF24))),
                  ],
                ],
              ),
            ),
            Wrap(spacing: 7, children: [
              OutlinedButton(
                onPressed: () => _moderate(record, 'investigate'),
                child: const Text('Investigate'),
              ),
              OutlinedButton(
                onPressed: () => _moderate(record, 'hide'),
                child: const Text('Hide abusive review'),
              ),
              IconButton(
                tooltip: 'Audit history',
                onPressed: () => _audit(record),
                icon: const Icon(Icons.history_rounded),
              ),
            ]),
          ],
        ),
      );

  Future<void> _moderate(AdminRatingTipRecord record, String action) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141A29),
        title: Text(action == 'hide' ? 'Hide review' : 'Investigate review'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Reason'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Confirm')),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    try {
      final input = AdminRatingsTipsPolicy.moderationRequest(
        ratingId: record.ratingId,
        action: action,
        reason: reason,
      );
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('reportRating')
          .call(input);
      if (mounted) setState(() => _message = 'Rating moderation saved.');
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(() => _message = error.message ?? 'Moderation failed.');
      }
    }
  }

  Future<void> _audit(AdminRatingTipRecord record) async {
    final audit = await FirebaseFirestore.instance
        .collection('adminAuditLogs')
        .where('recordId', isEqualTo: record.ratingId)
        .limit(20)
        .get();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141A29),
        title: const Text('Audit history'),
        content: SizedBox(
          width: 520,
          child: audit.docs.isEmpty
              ? const Text('No moderation actions recorded.')
              : ListView(
                  shrinkWrap: true,
                  children: audit.docs
                      .map((doc) => ListTile(
                            title:
                                Text('${doc.data()['actionType'] ?? 'Action'}'),
                            subtitle:
                                Text('${doc.data()['newValue'] ?? const {}}'),
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _state(IconData icon, String title, String body,
          {bool loading = false}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (loading)
              const CircularProgressIndicator()
            else
              Icon(icon, color: const Color(0xFF3B82F6), size: 40),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: .54))),
          ]),
        ),
      );

  InputDecoration _input(String label, {IconData? icon}) => InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
        filled: true,
        fillColor: const Color(0xFF141A29),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
