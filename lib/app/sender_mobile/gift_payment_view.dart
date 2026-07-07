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
          'Payment uses the existing Gifts checkout path. Admin sees the same request fields as web.',
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        _PaymentSummary(
          label: 'Gift budget',
          value: '£${widget.draft.budget.toStringAsFixed(0)}',
        ),
        const SizedBox(height: 10),
        const _PaymentSummary(
          label: 'Roth applied',
          value: '£0',
        ),
        const SizedBox(height: 10),
        _PaymentSummary(
          label: 'Card amount',
          value: '£${widget.draft.budget.toStringAsFixed(0)}',
        ),
        const SizedBox(height: 10),
        _PaymentSummary(
          label: 'Final total',
          value: '£${widget.draft.budget.toStringAsFixed(0)}',
        ),
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
      footer: GiftJourneyWidgets.primaryButton(
        enabled: !_submitting,
        label: _submitting ? 'Preparing checkout...' : 'Gift this experience',
        onTap: _submitting ? null : _submitForAdminReview,
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
        'applyRoth': false,
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
