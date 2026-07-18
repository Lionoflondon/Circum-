import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class AdminRoot extends StatelessWidget {
  const AdminRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Circum Admin',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF07090F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B8FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AdminHome(),
    );
  }
}

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  static const _sections = [
    'Deliveries',
    'Discrepancy review',
    'Riders',
    'Senders',
    'IRIS',
    'Gifts',
    'Health+',
    'Business',
    'Wallets',
    'Audit logs',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Admin surface',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      color: Color(0xFF7DD3FC),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Circum Admin',
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Operations console',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: ListView(
                      children: [
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 260,
                            mainAxisExtent: 118,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: _sections.length,
                          itemBuilder: (context, index) {
                            return _AdminSectionTile(label: _sections[index]);
                          },
                        ),
                        const SizedBox(height: 24),
                        const _DeliveryAdjustmentReviewQueue(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeliveryAdjustmentReviewQueue extends StatefulWidget {
  const _DeliveryAdjustmentReviewQueue();

  @override
  State<_DeliveryAdjustmentReviewQueue> createState() =>
      _DeliveryAdjustmentReviewQueueState();
}

class _DeliveryAdjustmentReviewQueueState
    extends State<_DeliveryAdjustmentReviewQueue> {
  String _filter = 'awaiting_admin_review';

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rider discrepancy review',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Approve, reject, or request more evidence before a sender is asked to pay an adjustment.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.70)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final status in const [
                  ('awaiting_admin_review', 'Queue'),
                  ('more_evidence_requested', 'Evidence Requested'),
                  ('awaiting_sender_payment', 'Approved'),
                  ('rejected_by_admin', 'Rejected'),
                ])
                  ChoiceChip(
                    label: Text(status.$2),
                    selected: _filter == status.$1,
                    onSelected: (_) => setState(() => _filter = status.$1),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('deliveryAdjustments')
                  .where('status', isEqualTo: _filter)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Review queue unavailable.');
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final docs = snapshot.data!.docs.toList()
                  ..sort((a, b) => _millis(b.data()['createdAt'])
                      .compareTo(_millis(a.data()['createdAt'])));
                if (docs.isEmpty) {
                  return Text(
                    'No discrepancy reports awaiting review.',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.66)),
                  );
                }
                return Column(
                  children: [
                    for (final doc in docs)
                      _DeliveryAdjustmentCard(id: doc.id, data: doc.data()),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryAdjustmentCard extends StatefulWidget {
  const _DeliveryAdjustmentCard({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;

  @override
  State<_DeliveryAdjustmentCard> createState() =>
      _DeliveryAdjustmentCardState();
}

class _DeliveryAdjustmentCardState extends State<_DeliveryAdjustmentCard> {
  bool _busy = false;
  String? _message;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _review(String decision) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('reviewDeliveryAdjustment')
          .call({
        'adjustmentId': widget.id,
        'decision': decision,
        'note':
            _note.text.trim().isEmpty ? 'Reviewed in Circum Admin' : _note.text,
      });
      if (mounted) setState(() => _message = 'Decision recorded.');
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(() => _message = error.message ?? 'Review failed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final observations = data['observations'] is Map
        ? Map<String, dynamic>.from(data['observations'] as Map)
        : const <String, dynamic>{};
    final iris = data['irisCalculationMetadata'] is Map
        ? Map<String, dynamic>.from(data['irisCalculationMetadata'] as Map)
        : const <String, dynamic>{};
    final photos = data['evidencePhotos'] is Iterable
        ? List<Object?>.from(data['evidencePhotos'] as Iterable)
        : const <Object?>[];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Adjustment ${widget.id}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _fact('Booking', data['bookingId']),
                  _fact('Sender', data['senderId']),
                  _fact('Rider', data['riderId']),
                  _fact('Status', data['status']),
                  _fact('Reason', data['riderReason']),
                  _fact('Original', '£${data['originalQuote']}'),
                  _fact('Revised', '£${data['revisedQuote']}'),
                  _fact('Additional', '£${data['additionalAmount']}'),
                  _fact('Submitted', data['createdAt']),
                  _fact('Decision', data['adminDecision']),
                  _fact('Decision time', data['adminReviewedAt']),
                  _fact('Operator', data['adminReviewedBy']),
                  _fact('Observed weight', observations['observedWeightKg']),
                  _fact('Vehicle', observations['observedVehicleType']),
                  _fact(
                      'IRIS vehicle',
                      (iris['recommendation'] is Map)
                          ? (iris['recommendation'] as Map)['vehicleType']
                          : null),
                ],
              ),
              if ('${data['riderNotes'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Rider statement: ${data['riderNotes']}'),
              ],
              if ('${data['senderNotes'] ?? data['senderStatement'] ?? ''}'
                  .trim()
                  .isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                    'Sender statement: ${data['senderNotes'] ?? data['senderStatement']}'),
              ],
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Evidence preview: ${photos.length} photo(s) attached'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final photo in photos.take(4))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          '$photo',
                          width: 92,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 92,
                            height: 72,
                            alignment: Alignment.center,
                            color: Colors.white.withValues(alpha: 0.08),
                            child:
                                const Icon(Icons.image_not_supported_rounded),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Decision notes',
                  hintText: 'Reason, requested evidence, or operator note',
                  border: OutlineInputBorder(),
                ),
              ),
              if ('${data['adminReviewNote'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Audit note: ${data['adminReviewNote']}'),
              ],
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(_message!,
                    style: const TextStyle(color: Color(0xFF7DD3FC))),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : () => _review('approve'),
                    child: const Text('Approve'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _review('reject'),
                    child: const Text('Reject'),
                  ),
                  TextButton(
                    onPressed:
                        _busy ? null : () => _review('request_more_evidence'),
                    child: const Text('Request more evidence'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _fact(String label, Object? value) {
  return Text('$label: ${value ?? 'Not recorded'}');
}

int _millis(Object? value) {
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is num) return value.toInt();
  if (value is DateTime) return value.millisecondsSinceEpoch;
  return 0;
}

class _AdminSectionTile extends StatelessWidget {
  const _AdminSectionTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}
