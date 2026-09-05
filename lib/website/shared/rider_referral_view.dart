import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'rider_referral.dart';

class RiderReferralView extends StatelessWidget {
  const RiderReferralView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rider Referrals')),
        body: const SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: RiderReferralPanel(),
        ),
      );
}

class RiderReferralPanel extends StatefulWidget {
  const RiderReferralPanel({
    super.key,
    this.signedIn,
    this.loadCode,
    this.attachCode,
  });
  final bool? signedIn;
  final Future<Map<String, dynamic>> Function()? loadCode;
  final Future<String> Function(String)? attachCode;

  @override
  State<RiderReferralPanel> createState() => _RiderReferralPanelState();
}

class _RiderReferralPanelState extends State<RiderReferralPanel> {
  final _code = TextEditingController();
  Map<String, dynamic>? _ownCode;
  String? _error;
  String? _message;
  bool _loading = false;
  bool _attaching = false;
  bool get _signedIn =>
      widget.signedIn ?? FirebaseAuth.instance.currentUser != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_signedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await (widget.loadCode?.call() ?? _fetchCode()).timeout(
        const Duration(seconds: 15),
      );
      if (mounted) setState(() => _ownCode = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FirebaseFunctionsException &&
                  error.code == 'permission-denied'
              ? 'Rider approval is required to share a referral code.'
              : 'Could not load your referral code. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _fetchCode() async {
    final result = await FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('ensureRiderReferralCode').call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> _attach() async {
    if (!_signedIn || _attaching) return;
    setState(() => _attaching = true);
    final message = await applyRiderReferral(
      code: _code.text,
      attach: widget.attachCode ??
          (code) async {
            final result =
                await FirebaseFunctions.instanceFor(region: 'us-central1')
                    .httpsCallable('attachReferralCode')
                    .call({'referralCode': code, 'program': 'rider'});
            return '${(result.data as Map)['status']}';
          },
    );
    if (mounted) {
      setState(() {
        _message = message;
        _attaching = false;
      });
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_signedIn) return const Text('Sign in as a Rider to use referrals.');
    final code = _ownCode?['referralCode']?.toString() ?? '';
    final link = _ownCode?['referralLink']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(riderReferralRewardCopy),
        const SizedBox(height: 16),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null) Text(_error!),
        if (!_loading && code.isEmpty)
          TextButton(onPressed: _load, child: const Text('Retry loading code')),
        if (code.isNotEmpty) ...[
          SelectableText(code),
          SelectableText(link),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _copy(code),
                child: const Text('Copy code'),
              ),
              TextButton(
                onPressed: () => _copy(link),
                child: const Text('Copy link'),
              ),
              TextButton(
                onPressed: () => Share.share('$riderReferralRewardCopy\n$link'),
                child: const Text('Share'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'REFERRAL CODE (OPTIONAL)',
            helperText: riderReferralHelper,
            helperMaxLines: 3,
          ),
        ),
        TextButton(
          onPressed: _attaching ? null : _attach,
          child: Text(_attaching ? 'Verifying…' : 'Apply referral code'),
        ),
        if (_message != null) Text(_message!, semanticsLabel: _message),
      ],
    );
  }
}
