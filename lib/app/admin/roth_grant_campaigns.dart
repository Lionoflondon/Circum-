import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class RothGrantCampaignsModule extends StatefulWidget {
  const RothGrantCampaignsModule({super.key});

  @override
  State<RothGrantCampaignsModule> createState() =>
      _RothGrantCampaignsModuleState();
}

class _RothGrantCampaignsModuleState extends State<RothGrantCampaignsModule> {
  final _functions = FirebaseFunctions.instance;
  final _db = FirebaseFirestore.instance;
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController(text: '10');
  String? _campaignId;
  Map<String, dynamic>? _dryRun;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    final result = await _functions.httpsCallable(name).call(data);
    return Map<String, dynamic>.from(result.data as Map? ?? const {});
  }

  Future<void> _create() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_name.text.trim().isEmpty || amount == null || amount <= 0) {
      setState(
          () => _message = 'Enter a campaign name and a valid Roth amount.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await _call('createRothGrantCampaign', {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'rothPerUser': amount,
        'recipientScope': 'active_customers',
      });
      setState(() {
        _campaignId = '${result['campaignId']}';
        _message = 'Campaign created. Run a dry run before approval.';
      });
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Campaign creation failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runDryRun() async {
    final id = _campaignId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await _call('dryRunRothGrantCampaign', {'campaignId': id});
      setState(() {
        _dryRun = result;
        _message = 'Dry run complete. No wallets or ledgers were changed.';
      });
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Dry run failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final id = _campaignId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _call('approveRothGrantCampaign', {'campaignId': id});
      setState(() => _message = 'Campaign approved.');
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Approval failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _execute() async {
    final id = _campaignId;
    final dryRun = _dryRun;
    if (id == null || dryRun == null) return;
    final count = dryRun['eligibleRecipients'] ?? 0;
    final total = dryRun['estimatedRothLiability'] ?? 0;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Roth campaign'),
            content: Text(
                'Grant ${_amount.text} Roth to $count eligible users\n\nTotal Roth issuance: $total Roth\n\nThis action is irreversible except through an audited reversal.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Execute')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result =
          await _call('executeRothGrantCampaign', {'campaignId': id});
      setState(() => _message =
          'Execution batch: ${result['granted']} granted, ${result['failures']} failed.');
    } on FirebaseFunctionsException catch (error) {
      setState(() => _message = error.message ?? 'Execution failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Text('Roth Grant Campaigns',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
            'One-time, server-authorised gifts for eligible active CIRCUM users. Dry run and approval are required before any balance changes.'),
        const SizedBox(height: 20),
        TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Campaign name')),
        const SizedBox(height: 12),
        TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: 12),
        TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Roth per eligible user')),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add),
              label: const Text('Create campaign')),
          OutlinedButton.icon(
              onPressed: _busy ? null : _runDryRun,
              icon: const Icon(Icons.science),
              label: const Text('Run dry run')),
          OutlinedButton.icon(
              onPressed: _busy || _dryRun == null ? null : _approve,
              icon: const Icon(Icons.verified),
              label: const Text('Approve')),
          FilledButton.icon(
              onPressed: _busy || _dryRun == null ? null : _execute,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Execute batch')),
        ]),
        if (_campaignId != null) ...[
          const SizedBox(height: 16),
          Text('Campaign: $_campaignId'),
        ],
        if (_dryRun != null) ...[
          const SizedBox(height: 16),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Eligible users: ${_dryRun!['eligibleRecipients'] ?? 0}'),
                        Text(
                            'Excluded users: ${_dryRun!['excludedRecipients'] ?? 0}'),
                        Text(
                            'Estimated issuance: ${_dryRun!['estimatedRothLiability'] ?? 0} Roth'),
                        Text(
                            'Definition hash: ${_dryRun!['definitionHash'] ?? 'Unavailable'}'),
                      ]))),
        ],
        if (_message != null) ...[
          const SizedBox(height: 16),
          Text(_message!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        ],
        const SizedBox(height: 28),
        const Text('Recent campaigns',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('rothGrantCampaigns')
              .orderBy('createdAt', descending: true)
              .limit(25)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Campaign history unavailable.');
            }
            if (!snapshot.hasData) {
              return const LinearProgressIndicator();
            }
            return Column(
                children: snapshot.data!.docs.map((doc) {
              final data = doc.data();
              return ListTile(
                  title: Text('${data['name'] ?? doc.id}'),
                  subtitle: Text(
                      '${data['status'] ?? 'unknown'} · ${data['estimatedRecipients'] ?? 0} recipients'),
                  onTap: () => setState(() {
                        _campaignId = doc.id;
                        _dryRun = null;
                      }));
            }).toList());
          },
        ),
      ],
    );
  }
}
