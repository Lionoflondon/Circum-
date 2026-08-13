import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'gift_mode_view.dart';
import 'gift_relationship_view.dart';
import 'sender_stripe_return_routing.dart';

class GiftPaymentReturnView extends StatefulWidget {
  const GiftPaymentReturnView({super.key});

  static const routeName = senderGiftPaymentReturnRouteName;

  @override
  State<GiftPaymentReturnView> createState() => _GiftPaymentReturnViewState();
}

class _GiftPaymentReturnViewState extends State<GiftPaymentReturnView> {
  var _confirming = false;
  var _confirmed = false;
  var _loadingDraft = false;
  String? _error;
  String? _draftError;
  Map<String, dynamic>? _gift;

  Map<String, String> get _parameters => senderStripeReturnParameters(Uri.base);

  bool get _cancelled =>
      _parameters['gift_payment']?.toLowerCase() == 'cancelled';

  @override
  void initState() {
    super.initState();
    if (_cancelled) {
      _loadSavedDraft();
    } else {
      _confirmPayment();
    }
  }

  Future<void> _loadSavedDraft() async {
    final giftDraftId = _parameters['giftDraftId']?.trim() ?? '';
    final user = FirebaseAuth.instance.currentUser;
    if (giftDraftId.isEmpty || user == null) {
      setState(() => _draftError = 'Your saved gift could not be identified.');
      return;
    }
    setState(() => _loadingDraft = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('giftPaymentDrafts')
          .doc(giftDraftId)
          .get();
      final data = snapshot.data();
      if (!snapshot.exists || data == null || data['senderId'] != user.uid) {
        throw StateError('Your saved gift could not be restored.');
      }
      if (!mounted) return;
      setState(() => _gift = data);
    } catch (_) {
      if (mounted) {
        setState(() => _draftError = 'Your saved gift could not be restored.');
      }
    } finally {
      if (mounted) setState(() => _loadingDraft = false);
    }
  }

  Future<void> _confirmPayment() async {
    final giftDraftId = _parameters['giftDraftId']?.trim() ?? '';
    final sessionId = _parameters['session_id']?.trim() ?? '';
    if (giftDraftId.isEmpty || sessionId.isEmpty) {
      setState(() => _error =
          'We could not identify this payment return. Open Gifts to review your request.');
      return;
    }
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('finalizeGiftPayment')
          .call({'giftDraftId': giftDraftId, 'sessionId': sessionId});
      final data = Map<String, dynamic>.from(result.data as Map);
      if (!mounted) return;
      setState(() {
        _confirmed = data['paymentStatus'] == 'paid';
        if (!_confirmed) {
          _error =
              'Payment is still being confirmed. Please try again shortly.';
        }
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ??
          'Payment is still being confirmed. Please try again shortly.');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _openGifts() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const GiftModeView(),
        settings: const RouteSettings(name: GiftModeView.routeName),
      ),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _cancelled
        ? 'Payment cancelled'
        : _confirmed
            ? 'Payment received'
            : 'Confirming payment';
    final subtitle = _cancelled
        ? 'You are back inside Circum. Your saved gift request was not submitted.'
        : _confirmed
            ? 'Your gift experience has been submitted for review.'
            : 'Circum is checking the secure Stripe confirmation.';
    return GiftJourneyWidgets.scaffold(
      activeStep: _cancelled ? 12 : 13,
      eyebrow: 'GIFTS — PAYMENT',
      title: title,
      subtitle: subtitle,
      onBack: _openGifts,
      children: [
        if (_confirming) const Center(child: CircularProgressIndicator()),
        if (_loadingDraft) const Center(child: CircularProgressIndicator()),
        if (_cancelled && _gift != null) ...[
          Text(
            '${_gift!['occasion'] ?? 'Gift'} for ${_gift!['recipientName'] ?? 'your recipient'} · £${(_gift!['grossGiftBudget'] ?? _gift!['grossBudget'] ?? _gift!['budget'] ?? 0)}',
            style: const TextStyle(color: Colors.white, height: 1.45),
          ),
        ],
        if (_draftError != null) ...[
          Text(
            _draftError!,
            style: const TextStyle(color: Color(0xFFFFC2C7), height: 1.45),
          ),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFFFC2C7), height: 1.45),
          ),
          const SizedBox(height: 12),
          if (!_cancelled)
            OutlinedButton(
              onPressed: _confirmPayment,
              child: const Text('Check again'),
            ),
        ],
      ],
      footer: GiftJourneyWidgets.primaryButton(
        enabled: !_confirming,
        label: 'Back to Gifts',
        onTap: _openGifts,
      ),
    );
  }
}
