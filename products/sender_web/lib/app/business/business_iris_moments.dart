import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

const _panel = Color(0xFF0D111C);
const _field = Color(0xFF161B2C);
const _border = Color(0xFF212842);
const _blue = Color(0xFF60A5FA);
const _text = Color(0xFFF5F7FB);
const _muted = Color(0xFF8992AB);

class BusinessIrisMomentsPanel extends StatelessWidget {
  final String businessName;
  final List<Map<String, dynamic>> moments;
  final bool canOperate;
  final VoidCallback onAddMoment;
  final VoidCallback onSendGift;
  final VoidCallback onCreateDelivery;
  final VoidCallback onScheduleHealthPlus;

  const BusinessIrisMomentsPanel({
    super.key,
    required this.businessName,
    required this.moments,
    required this.canOperate,
    required this.onAddMoment,
    required this.onSendGift,
    required this.onCreateDelivery,
    required this.onScheduleHealthPlus,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = moments.map(Map<String, dynamic>.from).toList()
      ..sort((a, b) => momentDate(a).compareTo(momentDate(b)));
    final open = sorted
        .where((moment) => momentStatus(moment) != 'completed')
        .toList(growable: false);
    final thisWeek = open
        .where((moment) => {'today', 'week'}.contains(momentBucket(moment)))
        .toList(growable: false);
    final today = open
        .where((moment) => momentBucket(moment) == 'today')
        .toList(growable: false);
    final week = open
        .where((moment) => momentBucket(moment) == 'week')
        .toList(growable: false);
    final month = open
        .where((moment) => momentBucket(moment) == 'month')
        .toList(growable: false);
    final completed = sorted
        .where((moment) => momentStatus(moment) == 'completed')
        .take(3)
        .toList(growable: false);
    final suggested = [...open]..sort((a, b) =>
        momentRecommendationConfidence(b, sorted)
            .compareTo(momentRecommendationConfidence(a, sorted)));

    return _Glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('IRIS Moments',
                  style:
                      GoogleFonts.dmSerifDisplay(fontSize: 22, color: _text)),
              const SizedBox(height: 5),
              const Text(
                'Relationship intelligence for birthdays, renewals, Health+ reminders and company milestones.',
                style: TextStyle(color: _muted, fontSize: 12.5, height: 1.45),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: canOperate ? onAddMoment : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Moment'),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2E).withValues(alpha: .62),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _blue.withValues(alpha: .20)),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF3B82F6).withValues(alpha: .10),
                  blurRadius: 30,
                  offset: const Offset(0, 14))
            ],
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${businessTimeGreeting()}, $businessName.',
                style: GoogleFonts.dmSerifDisplay(
                    fontSize: 25, color: _text, height: 1.05)),
            const SizedBox(height: 8),
            const Text('IRIS has reviewed your upcoming moments.',
                style: TextStyle(color: _muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const Text('This week you have:',
                style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _Metric(value: '${thisWeek.length}', label: 'Upcoming Moments'),
              _Metric(
                  value: '${thisWeek.where(momentIsGiftOpportunity).length}',
                  label: 'Gift Opportunities'),
              _Metric(
                  value: '${thisWeek.where(momentIsHealth).length}',
                  label: 'Health+ Reminder'),
              _Metric(
                  value: '${thisWeek.where(momentIsDelivery).length}',
                  label: 'Delivery Reminder'),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        if (sorted.isEmpty)
          _Empty(onAddMoment: onAddMoment)
        else ...[
          _Bucket(
              title: 'Today', moments: today, emptyText: 'No moments today.'),
          const SizedBox(height: 10),
          _Bucket(
              title: 'This Week',
              moments: week,
              emptyText: 'Nothing due this week.'),
          const SizedBox(height: 10),
          _Bucket(
              title: 'This Month',
              moments: month,
              emptyText: 'No later moments this month.'),
          const SizedBox(height: 16),
          const _Heading('IRIS Recommendations'),
          const SizedBox(height: 10),
          if (suggested.isEmpty)
            const _Message(
                'No recommendations are ready yet. IRIS will act once a moment becomes relevant.')
          else
            ...suggested.take(5).map((moment) => _Suggestion(
                  moment: moment,
                  allMoments: sorted,
                  onSendGift: onSendGift,
                  onCreateDelivery: onCreateDelivery,
                  onScheduleHealthPlus: onScheduleHealthPlus,
                  onCreateReminder: onAddMoment,
                )),
          const SizedBox(height: 16),
          _RelationshipHealth(
            moments: sorted,
            onSendGift: onSendGift,
            onCreateDelivery: onCreateDelivery,
            onDismiss: onAddMoment,
          ),
          const SizedBox(height: 16),
          const _Heading('Recently Completed'),
          const SizedBox(height: 10),
          if (completed.isEmpty)
            const _Message(
                'Completed gifts, deliveries, cards and reminders will appear here.')
          else
            ...completed.map((moment) => _MomentLine(moment: moment)),
        ],
      ]),
    );
  }
}

class BusinessMomentDialog extends StatefulWidget {
  const BusinessMomentDialog({super.key});

  @override
  State<BusinessMomentDialog> createState() => _BusinessMomentDialogState();
}

class _BusinessMomentDialogState extends State<BusinessMomentDialog> {
  final _name = TextEditingController();
  final _relationship = TextEditingController();
  final _date = TextEditingController();
  var _type = 'Employee Birthday';
  var _action = 'Send Gift';

  static const types = [
    'Birthday',
    'Wedding',
    'Engagement',
    'Anniversary',
    'New Baby',
    'Graduation',
    'Promotion',
    'Retirement',
    'New Home',
    'Thank You',
    'Congratulations',
    'Get Well Soon',
    'Sympathy / Condolence',
    'Welcome',
    'Farewell',
    'Religious Celebration',
    'Cultural Celebration',
    'Employee Birthday',
    'Employee Work Anniversary',
    'Client Birthday',
    'Client Anniversary',
    'Supplier Anniversary',
    'Investor Milestone',
    'Company Milestone',
    'Contract Renewal',
    'Partnership Anniversary',
    'Customer Appreciation',
    'Staff Recognition',
    'Health+ Reminder',
    'Delivery Reminder',
    'Custom Reminder',
  ];
  static const actions = [
    'Send Gift',
    'Create Delivery',
    'Schedule Health+ Delivery',
    'Create Reminder',
    'Send Card',
    'Snooze',
  ];

  @override
  void dispose() {
    _name.dispose();
    _relationship.dispose();
    _date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsedDate = DateTime.tryParse(_date.text.trim());
    final valid = _name.text.trim().isNotEmpty && parsedDate != null;
    return AlertDialog(
      backgroundColor: const Color(0xFF101826),
      title: Text('Add IRIS Moment',
          style: GoogleFonts.dmSerifDisplay(color: _text)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Add a person, company date or reminder. IRIS will suggest the best Circum action when it becomes relevant.',
            style: TextStyle(
                color: _muted, height: 1.4, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration:
                  const InputDecoration(labelText: 'Person or company')),
          const SizedBox(height: 12),
          TextField(
              controller: _relationship,
              decoration:
                  const InputDecoration(labelText: 'Relationship optional')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Moment type'),
            items: types
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(growable: false),
            onChanged: (value) => setState(() => _type = value ?? _type),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _date,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Date', hintText: 'YYYY-MM-DD')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _action,
            decoration: const InputDecoration(labelText: 'Preferred action'),
            items: actions
                .map((value) =>
                    DropdownMenuItem(value: value, child: Text(value)))
                .toList(growable: false),
            onChanged: (value) => setState(() => _action = value ?? _action),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, {
                    'momentId': const Uuid().v4(),
                    'name': _name.text.trim(),
                    'relationship': _relationship.text.trim(),
                    'type': _type,
                    'eventDate': Timestamp.fromDate(parsedDate),
                    'preferredAction': _action,
                    'status': 'upcoming',
                    'createdAt': Timestamp.now(),
                    'lastUpdated': Timestamp.now(),
                  })
              : null,
          child: const Text('Add Moment'),
        ),
      ],
    );
  }
}

class _Suggestion extends StatelessWidget {
  final Map<String, dynamic> moment;
  final List<Map<String, dynamic>> allMoments;
  final VoidCallback onSendGift;
  final VoidCallback onCreateDelivery;
  final VoidCallback onScheduleHealthPlus;
  final VoidCallback onCreateReminder;
  const _Suggestion(
      {required this.moment,
      required this.allMoments,
      required this.onSendGift,
      required this.onCreateDelivery,
      required this.onScheduleHealthPlus,
      required this.onCreateReminder});

  @override
  Widget build(BuildContext context) {
    final recommendation = momentRecommendation(moment, allMoments);
    final confidence = momentRecommendationConfidence(moment, allMoments);
    final confidenceLabel = confidence >= .82
        ? 'High confidence'
        : confidence >= .66
            ? 'Medium confidence'
            : 'Low confidence';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _box(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.psychology_alt_outlined, color: _blue, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(recommendation.$1,
                  style: const TextStyle(fontWeight: FontWeight.w900))),
          _Badge(momentCountdown(moment).toUpperCase()),
        ]),
        const SizedBox(height: 8),
        Text(momentRecommendedService(moment),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(recommendation.$2,
            style: const TextStyle(
                color: _muted, height: 1.42, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Badge(confidenceLabel),
          _Badge('WHY: ${momentWhy(moment, allMoments).toUpperCase()}')
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (momentIsGiftOpportunity(moment)) ...[
            _Action(
                'Open Gift Portal', Icons.card_giftcard_outlined, onSendGift),
            _Action('Send Card', Icons.mail_outline_rounded, onSendGift),
          ] else if (momentIsHealth(moment))
            _Action('Launch Health+ Delivery', Icons.health_and_safety_outlined,
                onScheduleHealthPlus)
          else if (momentIsDelivery(moment))
            _Action('Launch Delivery', Icons.local_shipping_outlined,
                onCreateDelivery)
          else
            _Action('Create Reminder', Icons.notifications_active_outlined,
                onCreateReminder),
          _Action('Remind Tomorrow', Icons.today_outlined, onCreateReminder),
          _Action('Snooze', Icons.snooze_outlined, onCreateReminder),
          _Action('Dismiss', Icons.close_rounded, onCreateReminder),
        ]),
      ]),
    );
  }
}

class _RelationshipHealth extends StatelessWidget {
  final List<Map<String, dynamic>> moments;
  final VoidCallback onSendGift;
  final VoidCallback onCreateDelivery;
  final VoidCallback onDismiss;
  const _RelationshipHealth(
      {required this.moments,
      required this.onSendGift,
      required this.onCreateDelivery,
      required this.onDismiss});
  @override
  Widget build(BuildContext context) {
    final rows = relationshipHealthRows(moments).take(3);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Heading('Relationship Health'),
      const SizedBox(height: 10),
      if (rows.isEmpty)
        const _Message(
            'IRIS will surface relationship health once moments or completed actions exist.')
      else
        ...rows.map((row) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: _box(),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text('${row['name']}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900))),
                      _Badge('${row['status']}')
                    ]),
                    const SizedBox(height: 6),
                    Text('${row['detail']}',
                        style: const TextStyle(
                            color: _muted,
                            height: 1.4,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text('IRIS: "${row['insight']}"',
                        style: const TextStyle(
                            height: 1.4, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _Action('Open Gift Portal', Icons.card_giftcard_outlined,
                          onSendGift),
                      _Action('Launch Delivery', Icons.local_shipping_outlined,
                          onCreateDelivery),
                      _Action('Dismiss', Icons.close_rounded, onDismiss),
                    ]),
                  ]),
            )),
    ]);
  }
}

class _Glass extends StatelessWidget {
  final Widget child;
  const _Glass({required this.child});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
      child: child);
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  const _Metric({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Container(
      width: 142,
      padding: const EdgeInsets.all(12),
      decoration: _box(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                color: _muted, fontSize: 11, fontWeight: FontWeight.w800))
      ]));
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontWeight: FontWeight.w900));
}

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _box(),
      child: Text(text,
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)));
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: _field,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: _border)),
      child: Text(text,
          style: GoogleFonts.jetBrainsMono(fontSize: 8.5, color: _muted)));
}

class _Action extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _Action(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label));
}

class _MomentLine extends StatelessWidget {
  final Map<String, dynamic> moment;
  const _MomentLine({required this.moment});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 7),
            decoration:
                const BoxDecoration(color: _blue, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(momentName(moment),
              style: const TextStyle(fontWeight: FontWeight.w900)),
          Text('${momentTypeLabel(moment)} · ${momentDateLabel(moment)}',
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.35))
        ]))
      ]));
}

class _Bucket extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> moments;
  final String emptyText;
  const _Bucket(
      {required this.title, required this.moments, required this.emptyText});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: _box(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_outlined, color: _blue, size: 18),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900))
        ]),
        const SizedBox(height: 10),
        if (moments.isEmpty)
          Text(emptyText, style: const TextStyle(color: _muted, fontSize: 12))
        else
          ...moments.take(3).map((moment) => _MomentLine(moment: moment))
      ]));
}

class _Empty extends StatelessWidget {
  final VoidCallback onAddMoment;
  const _Empty({required this.onAddMoment});
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _box(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('No upcoming moments.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text(
            'Create important moments once and let IRIS remind you at the right time with intelligent Circum recommendations.',
            style: TextStyle(
                color: _muted, height: 1.42, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        FilledButton.icon(
            onPressed: onAddMoment,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add First Moment'))
      ]));
}

BoxDecoration _box() => BoxDecoration(
    color: Colors.white.withValues(alpha: .045),
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: Colors.white.withValues(alpha: .10)));

DateTime momentDate(Map<String, dynamic> moment) {
  final raw = moment['eventDate'] ??
      moment['date'] ??
      moment['dueAt'] ??
      moment['reminderAt'] ??
      moment['createdAt'];
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  return DateTime.tryParse('$raw') ?? DateTime.fromMillisecondsSinceEpoch(0);
}

String momentStatus(Map<String, dynamic> moment) =>
    '${moment['status'] ?? 'upcoming'}'.trim().toLowerCase();
String momentName(Map<String, dynamic> moment) {
  final name =
      '${moment['name'] ?? moment['personName'] ?? moment['companyName'] ?? ''}'
          .trim();
  return name.isEmpty ? 'Important moment' : name;
}

String momentTypeLabel(Map<String, dynamic> moment) {
  final type =
      '${moment['type'] ?? moment['eventType'] ?? 'Custom reminder'}'.trim();
  return type.isEmpty ? 'Custom reminder' : type;
}

String momentDateLabel(Map<String, dynamic> moment) {
  final date = momentDate(moment);
  if (date.millisecondsSinceEpoch == 0) return 'Date to confirm';
  final now = DateTime.now();
  final diff = DateTime(date.year, date.month, date.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff > 1 && diff < 7) return 'In $diff days';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String momentBucket(Map<String, dynamic> moment) {
  final date = momentDate(moment);
  if (date.millisecondsSinceEpoch == 0) return 'later';
  final now = DateTime.now();
  final diff = DateTime(date.year, date.month, date.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (diff == 0) return 'today';
  if (diff > 0 && diff < 7) return 'week';
  if (diff >= 7 && diff < 31) return 'month';
  return 'later';
}

String businessTimeGreeting() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  if (hour >= 17 && hour < 22) return 'Good evening';
  return 'Working late';
}

String momentCountdown(Map<String, dynamic> moment) =>
    momentDateLabel(moment).toLowerCase();
bool momentIsHealth(Map<String, dynamic> moment) {
  final text = '${momentTypeLabel(moment)} ${moment['preferredAction'] ?? ''}'
      .toLowerCase();
  return text.contains('health') ||
      text.contains('medication') ||
      text.contains('prescription');
}

bool momentIsDelivery(Map<String, dynamic> moment) {
  final text = '${momentTypeLabel(moment)} ${moment['preferredAction'] ?? ''}'
      .toLowerCase();
  return text.contains('delivery') && !momentIsHealth(moment);
}

bool momentIsGiftOpportunity(Map<String, dynamic> moment) {
  if (momentIsHealth(moment) || momentIsDelivery(moment)) return false;
  final text = '${momentTypeLabel(moment)} ${moment['preferredAction'] ?? ''}'
      .toLowerCase();
  const signals = [
    'birthday',
    'wedding',
    'engagement',
    'anniversary',
    'baby',
    'graduation',
    'promotion',
    'retirement',
    'home',
    'thank',
    'congratulations',
    'get well',
    'sympathy',
    'condolence',
    'welcome',
    'farewell',
    'celebration',
    'milestone',
    'appreciation',
    'recognition',
    'gift',
    'card'
  ];
  return signals.any(text.contains);
}

String momentRecommendedService(Map<String, dynamic> moment) {
  final type = momentTypeLabel(moment);
  if (momentIsHealth(moment)) return 'Launch a Health+ Delivery request.';
  if (momentIsDelivery(moment)) return 'Launch a Delivery request.';
  if (momentIsGiftOpportunity(moment)) {
    final clean =
        type.replaceAll(RegExp(r'\s+'), ' ').replaceAll('/', '').trim();
    return 'Launch a $clean Gift request via the Circum Gift Portal.';
  }
  return 'Create a reminder and choose the next Circum action.';
}

(String, String) momentRecommendation(
    Map<String, dynamic> moment, List<Map<String, dynamic>> all) {
  final name = momentName(moment);
  final service = momentRecommendedService(moment);
  if (momentIsHealth(moment)) {
    return (
      '$name has a Health+ reminder ${momentCountdown(moment).toLowerCase()}.',
      'Launch a Health+ Delivery request. ${momentWhy(moment, all)}.'
    );
  }
  if (momentIsDelivery(moment)) {
    return (
      '$name has a delivery reminder ${momentCountdown(moment).toLowerCase()}.',
      'Launch a Delivery request. ${momentWhy(moment, all)}.'
    );
  }
  if (momentIsGiftOpportunity(moment)) {
    return (
      '$name has an important relationship moment ${momentCountdown(moment).toLowerCase()}.',
      '$service ${momentWhy(moment, all)}.'
    );
  }
  return (
    '$name has a saved moment ${momentCountdown(moment).toLowerCase()}.',
    '$service ${momentWhy(moment, all)}.'
  );
}

String momentWhy(Map<String, dynamic> moment, List<Map<String, dynamic>> all) {
  final type = momentTypeLabel(moment).toLowerCase();
  final name = momentName(moment);
  final same = all.any((item) =>
      momentStatus(item) == 'completed' &&
      momentTypeLabel(item).toLowerCase() == type);
  final accepted = all.any((item) =>
      '${item['lastAction'] ?? item['completedAction'] ?? item['preferredAction'] ?? ''}'
          .trim()
          .isNotEmpty &&
      momentStatus(item) == 'completed');
  if (momentIsHealth(moment)) return 'Based on a saved Health+ schedule';
  if (momentIsDelivery(moment)) {
    return 'Based on a user-created delivery reminder';
  }
  if (same) return 'Based on previous Circum activity';
  if (accepted) return 'Based on previous business behaviour';
  if (type.contains('policy')) return 'Based on company policy';
  if (type.contains('birthday')) return 'Upcoming birthday';
  if (type.contains('anniversary')) return 'Upcoming anniversary';
  if (type.contains('milestone')) return 'Company milestone';
  return 'User-created reminder for $name';
}

double momentRecommendationConfidence(
    Map<String, dynamic> moment, List<Map<String, dynamic>> all) {
  var score =
      momentIsGiftOpportunity(moment) || momentIsHealth(moment) ? .72 : .62;
  final type = momentTypeLabel(moment).toLowerCase();
  final completed = all
      .where((item) =>
          momentStatus(item) == 'completed' &&
          momentTypeLabel(item).toLowerCase() == type)
      .length;
  final dismissed = all
      .where((item) =>
          momentTypeLabel(item).toLowerCase() == type &&
          {'dismissed', 'snoozed'}.contains(momentStatus(item)))
      .length;
  score += (completed * .06).clamp(0, .18);
  score -= (dismissed * .08).clamp(0, .24);
  if ('${moment['preferredAction'] ?? ''}'.trim().isNotEmpty) score += .04;
  if (momentBucket(moment) == 'today') score += .05;
  return score.clamp(.32, .94).toDouble();
}

List<Map<String, dynamic>> relationshipHealthRows(
    List<Map<String, dynamic>> moments) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final moment in moments) {
    grouped.putIfAbsent(momentName(moment), () => []).add(moment);
  }
  final rows = <Map<String, dynamic>>[];
  for (final entry in grouped.entries) {
    final completed = entry.value
        .where((item) => momentStatus(item) == 'completed')
        .toList()
      ..sort((a, b) => momentDate(b).compareTo(momentDate(a)));
    final upcoming = entry.value
        .where((item) => momentStatus(item) != 'completed')
        .toList()
      ..sort((a, b) => momentDate(a).compareTo(momentDate(b)));
    final last = completed.isEmpty ? null : momentDate(completed.first);
    final days = last == null ? null : DateTime.now().difference(last).inDays;
    final status = days == null
        ? (upcoming.isEmpty ? 'Growing' : 'Strong')
        : days > 300
            ? 'Needs Attention'
            : days > 150
                ? 'Growing'
                : 'Strong';
    final detail = days == null
        ? (upcoming.isEmpty
            ? 'No completed Circum activity recorded yet.'
            : 'Next moment: ${momentTypeLabel(upcoming.first)} ${momentDateLabel(upcoming.first).toLowerCase()}.')
        : 'Last appreciation action: $days days ago.';
    final insight = status == 'Needs Attention'
        ? 'This relationship may benefit from renewed engagement.'
        : status == 'Growing'
            ? 'A thoughtful Circum action could strengthen this relationship.'
            : 'Recent activity suggests this relationship is being maintained.';
    rows.add({
      'name': entry.key,
      'status': status,
      'detail': detail,
      'insight': insight
    });
  }
  const priority = {'Needs Attention': 0, 'Growing': 1, 'Strong': 2};
  rows.sort((a, b) =>
      (priority[a['status']] ?? 9).compareTo(priority[b['status']] ?? 9));
  return rows;
}
