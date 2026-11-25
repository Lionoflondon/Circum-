import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'roth_central_staging_gate.dart';

const bool _centralRothStagingEnabled = bool.fromEnvironment(
  'ROTH_CENTRAL_STAGING_ENABLED',
  defaultValue: false,
);
const String _centralRothStagingProject = String.fromEnvironment(
  'ROTH_COMPANY_STAGING_PROJECT',
  defaultValue: '',
);

bool isRothCentralStagingEnabled(String firebaseProjectId) =>
    rothCentralStagingEnabledFor(
      firebaseProjectId: firebaseProjectId,
      enabled: _centralRothStagingEnabled,
      configuredProjectId: _centralRothStagingProject,
    );

class CircumRothCentralLinkScreen extends StatefulWidget {
  const CircumRothCentralLinkScreen({super.key});

  @override
  State<CircumRothCentralLinkScreen> createState() =>
      _CircumRothCentralLinkScreenState();
}

class _CircumRothCentralLinkScreenState
    extends State<CircumRothCentralLinkScreen> {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );
  String? _linkCode;
  int? _availablePence;
  int? _reservedPence;
  String? _message;
  bool _busy = false;
  DateTime? _expiresAt;
  Timer? _expiryTimer;

  Future<void> _createLink() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _linkCode = null;
    });
    try {
      final response = await _functions
          .httpsCallable('beginRothAccountLink')
          .call()
          .timeout(const Duration(seconds: 20));
      final data = Map<String, dynamic>.from(response.data as Map);
      final code = data['code'];
      final seconds = data['expiresInSeconds'];
      if (code is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(code)) {
        throw StateError('ROTH returned an invalid link code.');
      }
      final lifetime = seconds is int && seconds > 0 && seconds <= 300
          ? seconds
          : 300;
      if (!mounted) return;
      _expiryTimer?.cancel();
      setState(() {
        _linkCode = code;
        _expiresAt = DateTime.now().add(Duration(seconds: lifetime));
        _message = 'This code expires in five minutes.';
      });
      _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return timer.cancel();
        if (_isExpired) {
          timer.cancel();
          setState(() {
            _linkCode = null;
            _message = 'The link code expired. Create a new code to continue.';
          });
        } else {
          setState(() {});
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'ROTH linking is unavailable in this staging environment. Try again later.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyCode() async {
    final code = _linkCode;
    if (code == null || _isExpired) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) setState(() => _message = 'Secure link code copied.');
  }

  Future<void> _refreshBalance() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await _functions
          .httpsCallable('getRothCentralCompanyBalance')
          .call()
          .timeout(const Duration(seconds: 20));
      final data = Map<String, dynamic>.from(response.data as Map);
      final available = data['allocatedPence'];
      final reserved = data['reservedPence'];
      if (available is! int ||
          available < 0 ||
          reserved is! int ||
          reserved < 0) {
        throw StateError('ROTH returned an invalid balance.');
      }
      if (!mounted) return;
      setState(() {
        _availablePence = available;
        _reservedPence = reserved;
        _message = 'Central ROTH balance refreshed.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'The central ROTH allocation could not be refreshed. If you just linked, wait a moment and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _isExpired =>
      _expiresAt != null && DateTime.now().isAfter(_expiresAt!);

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ROTH account')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.account_balance_wallet_outlined, size: 40),
        const SizedBox(height: 16),
        Text(
          'Link your central ROTH wallet',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Linking connects your verified CIRCUM account to the central ROTH wallet. Your balance remains held by ROTH.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _createLink,
          icon: const Icon(Icons.link),
          label: Text(_busy ? 'Working…' : 'Create secure link code'),
        ),
        if (_linkCode != null) ...[
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('One-time link code'),
                  const SizedBox(height: 8),
                  SelectableText(
                    _isExpired ? 'Expired' : _linkCode!,
                    key: const ValueKey('roth-link-code'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'In the ROTH app, choose “Link a company account”, select CIRCUM, and enter this code. It expires after five minutes.',
                  ),
                  TextButton.icon(
                    onPressed: _isExpired ? null : _copyCode,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy code'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _busy ? null : _refreshBalance,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh CIRCUM ROTH allocation'),
        ),
        if (_availablePence != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Available in CIRCUM'),
              subtitle: Text(
                '${_formatPence(_availablePence!)} available · ${_formatPence(_reservedPence!)} reserved',
              ),
            ),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(_message!)),
        ],
      ],
    ),
  );
}

String _formatPence(int value) =>
    '£${(value ~/ 100)}.${(value % 100).toString().padLeft(2, '0')}';
