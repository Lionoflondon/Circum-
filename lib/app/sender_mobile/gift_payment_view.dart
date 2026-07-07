import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'gift_journey_draft.dart';
import 'gift_relationship_view.dart';
import 'gift_status_view.dart';

class GiftPaymentView extends StatefulWidget {
  final GiftJourneyDraft draft;

  const GiftPaymentView({super.key, required this.draft});

  static const routeName = '/sender-mobile/gifts/payment';

  @override
  State<GiftPaymentView> createState() => _GiftPaymentViewState();
}

class _GiftPaymentViewState extends State<GiftPaymentView> {
  var _submitting = false;
  String? _message;
  String? _paymentMethod;
  bool _applyRoth = false;

  double get _rothBalance => 0;
  bool get _rothCanFullyCover =>
      _rothBalance >= widget.draft.budget && widget.draft.budget > 0;
  bool get _showRothToggle =>
      _paymentMethod != null && _paymentMethod != 'Roth' && _rothBalance > 0;
  double get _rothApplied =>
      _applyRoth ? _rothBalance.clamp(0, widget.draft.budget).toDouble() : 0;
  double get _remainingCardAmount => widget.draft.budget - _rothApplied;

  @override
  void initState() {
    super.initState();
    final uri = Uri.base;
    final cancelled = uri.queryParameters['payment'] == 'cancelled' ||
        uri.fragment.contains('payment=cancelled');
    if (cancelled) {
      _message =
          'Payment cancelled. Your gift request is saved. You can try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 4,
      eyebrow: 'STEP 12 — PAYMENT',
      title: 'Secure the request',
      subtitle:
          'Choose how you would like to secure this bespoke gift experience.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        Text(
          'Gift Summary',
          style: GoogleFonts.dmSerifDisplay(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 12),
        _PaymentSummary(
          label: 'Budget',
          value: '£${widget.draft.budget.toStringAsFixed(0)}',
        ),
        const SizedBox(height: 10),
        _PaymentSummary(
          label: 'Delivery',
          value:
              '${widget.draft.deliveryDate ?? 'Date pending'} · ${widget.draft.deliveryTimeWindow ?? 'Window pending'}',
        ),
        const SizedBox(height: 10),
        const _PaymentSummary(label: 'Fees', value: '£0'),
        const SizedBox(height: 10),
        _PaymentSummary(
          label: 'Total',
          value: '£${widget.draft.budget.toStringAsFixed(0)}',
        ),
        const SizedBox(height: 22),
        Text(
          'Choose payment method',
          style: GoogleFonts.dmSerifDisplay(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 12),
        _PaymentMethodTile(
          label: 'Card',
          selected: _paymentMethod == 'Card',
          onTap: () => setState(() => _paymentMethod = 'Card'),
        ),
        const SizedBox(height: 10),
        _PaymentMethodTile(
          label: 'Apple Pay',
          selected: _paymentMethod == 'Apple Pay',
          onTap: () => setState(() => _paymentMethod = 'Apple Pay'),
        ),
        const SizedBox(height: 10),
        _PaymentMethodTile(
          label: 'Google Pay',
          selected: _paymentMethod == 'Google Pay',
          onTap: () => setState(() => _paymentMethod = 'Google Pay'),
        ),
        if (_rothCanFullyCover) ...[
          const SizedBox(height: 10),
          _PaymentMethodTile(
            label: 'Roth',
            selected: _paymentMethod == 'Roth',
            onTap: () => setState(() {
              _paymentMethod = 'Roth';
              _applyRoth = true;
            }),
          ),
        ],
        if (_showRothToggle) ...[
          const SizedBox(height: 16),
          _RothToggleCard(
            enabled: _applyRoth,
            balance: _rothBalance,
            applied: _rothApplied,
            remaining: _remainingCardAmount,
            onChanged: (value) => setState(() => _applyRoth = value),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 14),
          Text(
            _message!,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'You’re almost there.\n\nOnce payment is confirmed, our Gifts Team begins designing a completely bespoke experience for your recipient.\n\nNo catalogue.\nNo mass-produced gifts.\nOnly something created specifically for this moment.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: const Color(0xFFE4DCF5),
              fontSize: 12.5,
              height: 1.42,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Secure payment powered by Stripe.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: const Color(0xFFB8AAB8),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          GiftJourneyWidgets.primaryButton(
            enabled: !_submitting && _paymentMethod != null,
            label: _submitting
                ? 'Preparing checkout...'
                : 'Continue to Secure Payment',
            onTap: _submitting || _paymentMethod == null
                ? null
                : _submitForAdminReview,
          ),
        ],
      ),
    );
  }

  Future<void> _submitForAdminReview() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _message = 'Sign in to submit this gift request for Admin review.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      final draftRef = FirebaseFirestore.instance
          .collection(senderGiftPaymentDraftCollectionName)
          .doc();
      final payload = Map<String, Object?>.from(widget.draft.adminReviewPayload(
        senderId: user.uid,
        senderEmail: user.email ?? '',
        senderName: user.displayName,
      ));
      final parsedDeliveryDate = DateTime.tryParse(
        widget.draft.deliveryDate ?? '',
      );
      if (parsedDeliveryDate != null) {
        payload['deliveryDate'] = Timestamp.fromDate(parsedDeliveryDate);
      }
      await draftRef.set({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final payment = await FirebaseFunctions.instance
          .httpsCallable(senderGiftPaymentCallableName)
          .call({
        'giftDraftId': draftRef.id,
        'source': 'sender_mobile',
        'applyRoth': _applyRoth && _rothBalance > 0,
        'returnOrigin': Uri.base.origin,
      });
      final paymentData = Map<String, dynamic>.from(payment.data as Map);
      if (paymentData['walletPaidInFull'] == true) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftStatusView(draft: widget.draft),
            settings: const RouteSettings(name: GiftStatusView.routeName),
          ),
        );
        return;
      }
      final checkoutUrl = Uri.tryParse('${paymentData['url'] ?? ''}');
      if (checkoutUrl == null || checkoutUrl.host.isEmpty) {
        throw StateError('Stripe Checkout could not be opened.');
      }
      await launchUrl(checkoutUrl, webOnlyWindowName: '_self');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error is FirebaseFunctionsException
            ? (error.message ?? 'Could not start secure checkout.')
            : 'Could not start secure checkout.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _PaymentMethodTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFC9B8FF).withValues(alpha: .12)
              : Colors.white.withValues(alpha: .052),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFFC9B8FF).withValues(alpha: .34)
                : Colors.white.withValues(alpha: .09),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color:
                  selected ? const Color(0xFFC9B8FF) : const Color(0xFFB8AAB8),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _RothToggleCard extends StatelessWidget {
  final bool enabled;
  final double balance;
  final double applied;
  final double remaining;
  final ValueChanged<bool> onChanged;

  const _RothToggleCard({
    required this.enabled,
    required this.balance,
    required this.applied,
    required this.remaining,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            onChanged: onChanged,
            title: Text(
              'Apply Roth balance',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            _PaymentSummary(
              label: 'Roth balance',
              value: '£${balance.toStringAsFixed(0)}',
            ),
            const SizedBox(height: 8),
            _PaymentSummary(
              label: 'Roth applied',
              value: '£${applied.toStringAsFixed(0)}',
            ),
            const SizedBox(height: 8),
            _PaymentSummary(
              label: 'Remaining card amount',
              value: '£${remaining.toStringAsFixed(0)}',
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentSummary extends StatelessWidget {
  final String label;
  final String value;

  const _PaymentSummary({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .052),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFFB8AAB8),
                fontSize: 10,
                letterSpacing: .7,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
