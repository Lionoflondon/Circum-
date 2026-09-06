import 'package:circum/app/sender_mobile/native_payment_return.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../env/env.dart';
import 'native_payment_identity.dart';
import 'sender_accessibility.dart';
import 'sender_finance.dart';
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
  late String _giftDraftId;
  var _submitting = false;
  var _paymentComplete = false;
  var _rothLoading = true;
  var _rothUnavailable = false;
  String? _message;
  String? _paymentMethod;
  bool _applyRoth = false;
  bool _platformPaySupported = false;
  List<SenderPaymentMethod> _savedMethods = const [];
  String? _selectedPaymentMethodId;

  static const _backendTimeout = Duration(seconds: 20);
  static const _paymentSheetInitTimeout = Duration(seconds: 20);
  static const _paymentSheetPresentTimeout = Duration(seconds: 90);

  double _rothBalance = 0;
  bool get _rothCanFullyCover =>
      _rothBalance >= widget.draft.budget && widget.draft.budget > 0;
  bool get _showRothToggle =>
      _paymentMethod != null && _paymentMethod != 'Roth' && _rothBalance > 0;
  double get _rothApplied =>
      _applyRoth ? _rothBalance.clamp(0, widget.draft.budget).toDouble() : 0;
  double get _remainingCardAmount => widget.draft.budget - _rothApplied;
  String get _verifiedPaymentMethod {
    if (_rothApplied >= widget.draft.budget && widget.draft.budget > 0) {
      return 'roth';
    }
    final selected = switch (_paymentMethod) {
      'Apple Pay' => 'apple_pay',
      'Google Pay' => 'google_pay',
      'Saved card' => 'saved_card',
      _ => 'card',
    };
    if (_rothApplied > 0) return 'roth_$selected';
    return selected;
  }

  List<String> get _availablePaymentMethods {
    final methods = <String>[];
    if (_platformPaySupported &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS) {
      methods.add('Apple Pay');
    } else if (_platformPaySupported &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      methods.add('Google Pay');
    }
    methods.add('Card');
    return methods;
  }

  @override
  void initState() {
    super.initState();
    _giftDraftId = FirebaseFirestore.instance
        .collection(senderGiftPaymentDraftCollectionName)
        .doc()
        .id;
    final uri = Uri.base;
    final cancelled = uri.queryParameters['payment'] == 'cancelled' ||
        uri.fragment.contains('payment=cancelled');
    if (cancelled) {
      _message =
          'Payment cancelled. Your gift request is saved. You can try again.';
    }
    _loadRothBalance();
    _loadPaymentOptions();
  }

  Future<void> _loadPaymentOptions() async {
    try {
      final profile = await FirebaseSenderPaymentProfileRepository()
          .paymentMethods()
          .timeout(_backendTimeout);
      final platformPay = kIsWeb
          ? false
          : await Stripe.instance.isPlatformPaySupported().timeout(
                const Duration(seconds: 4),
              );
      if (!mounted) return;
      setState(() {
        _savedMethods = profile.methods;
        _platformPaySupported = platformPay;
      });
    } catch (_) {
      if (mounted) setState(() => _platformPaySupported = false);
    }
  }

  Future<void> _loadRothBalance() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(senderGiftRothBalanceCallableName)
          .call()
          .timeout(_backendTimeout);
      final data = Map<String, dynamic>.from(result.data as Map);
      final balance = (data['availableRoth'] ?? data['balance'] ?? 0) as num;
      if (!mounted) return;
      setState(() {
        _rothBalance = balance.toDouble();
        _rothLoading = false;
        _rothUnavailable = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rothBalance = 0;
        _rothLoading = false;
        _rothUnavailable = true;
      });
    }
  }

  void _selectPaymentMethod(String method) {
    setState(() {
      _paymentMethod = method;
      if (method != 'Saved card') _selectedPaymentMethodId = null;
      if (method == 'Roth') {
        _applyRoth = _rothCanFullyCover;
      } else if (_rothBalance <= 0) {
        _applyRoth = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GiftJourneyWidgets.scaffold(
      activeStep: 12,
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
        const SizedBox(height: 10),
        _RothBalanceSummary(
          loading: _rothLoading,
          unavailable: _rothUnavailable,
          balance: _rothBalance,
          applied: _rothApplied,
          remaining: _remainingCardAmount,
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
        ..._availablePaymentMethods.expand(
          (method) => [
            if (method == 'Apple Pay' || method == 'Google Pay')
              SizedBox(
                height: 48,
                child: PlatformPayButton(
                  key: ValueKey(
                    method == 'Apple Pay'
                        ? 'giftApplePayButton'
                        : 'giftGooglePayButton',
                  ),
                  type: PlatformButtonType.pay,
                  appearance: PlatformButtonStyle.black,
                  borderRadius: 6,
                  onPressed: () => _selectPaymentMethod(method),
                ),
              )
            else
              _PaymentMethodTile(
                label: method,
                selected: _paymentMethod == method,
                onTap: () => _selectPaymentMethod(method),
              ),
            const SizedBox(height: 10),
          ],
        ),
        ..._savedMethods.expand(
          (method) => [
            _PaymentMethodTile(
              label:
                  method.isDefault ? '${method.title} · Default' : method.title,
              selected: _selectedPaymentMethodId == method.id,
              onTap: () => setState(() {
                _paymentMethod = 'Saved card';
                _selectedPaymentMethodId = method.id;
              }),
            ),
            const SizedBox(height: 10),
          ],
        ),
        if (_rothCanFullyCover) ...[
          const SizedBox(height: 10),
          _PaymentMethodTile(
            label: 'Roth',
            selected: _paymentMethod == 'Roth',
            onTap: () => _selectPaymentMethod('Roth'),
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
            'You’re almost there.\n\nYour payment reserves this request with the Gifts Team.\n\nWe prepare everything around your chosen delivery date.\n\nNo catalogue.\nNo mass-produced gifts.\nOnly something created specifically for this moment.',
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
            onTap: _submitting || _paymentComplete || _paymentMethod == null
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
    if (_submitting || _paymentComplete) return;
    final confirmed = await confirmSenderPaymentIfRequired(
      context,
      paymentMethod: _verifiedPaymentMethod == 'roth'
          ? 'Roth'
          : _verifiedPaymentMethod == 'roth_card'
              ? 'Roth and card'
              : (_paymentMethod ?? 'card'),
      amount: '£${widget.draft.budget.toStringAsFixed(2)}',
    );
    if (!confirmed || !mounted || _submitting) return;
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      if (!kIsWeb) {
        _giftDraftId = await NativePaymentIdentity.reserve(
          uid: user.uid,
          flow: 'gift',
          candidate: _giftDraftId,
        ).timeout(_backendTimeout);
        if (FirebaseAuth.instance.currentUser?.uid != user.uid) return;
        if (await _recoverExistingNativeGift(user)) return;
      }
      final modeResult = await FirebaseFunctions.instance
          .httpsCallable('getSenderPaymentMode')
          .call()
          .timeout(_backendTimeout);
      final modeData = Map<String, dynamic>.from(modeResult.data as Map);
      if (!Env.paymentModeMatchesBackend('${modeData['mode'] ?? ''}')) {
        throw StateError('Gift payment configuration is unavailable.');
      }
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) return;
      final payload = Map<String, Object?>.from(
        widget.draft.adminReviewPayload(
          senderId: user.uid,
          senderEmail: user.email ?? '',
          senderName: user.displayName,
        ),
      );
      payload.addAll({
        'applyRoth': _applyRoth && _rothBalance > 0,
        'paymentMethod': _verifiedPaymentMethod,
        'grossGiftBudget': widget.draft.budget,
        'paymentStatus': 'payment_pending',
      });
      final parsedDeliveryDate = DateTime.tryParse(
        widget.draft.deliveryDate ?? '',
      );
      if (parsedDeliveryDate != null) {
        payload['deliveryDate'] = Timestamp.fromDate(parsedDeliveryDate);
      }
      final payment = await FirebaseFunctions.instance
          .httpsCallable(senderGiftPaymentCallableName)
          .call({
        'giftDraftId': _giftDraftId,
        'giftDraft': payload,
        'source': 'sender_mobile',
        'applyRoth': _applyRoth && _rothBalance > 0,
        'paymentMethod': _verifiedPaymentMethod,
        if (_selectedPaymentMethodId != null)
          'paymentMethodId': _selectedPaymentMethodId,
        'checkoutMode': kIsWeb ? 'web_checkout' : 'payment_intent',
        'idempotencyKey': 'gift_${user.uid}_$_giftDraftId',
        'returnOrigin': Uri.base.origin,
      }).timeout(_backendTimeout);
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) return;
      final paymentData = Map<String, dynamic>.from(payment.data as Map);
      if (paymentData['walletPaidInFull'] == true) {
        if (!kIsWeb) {
          await NativePaymentIdentity.resolve(
            uid: user.uid,
            flow: 'gift',
            expected: _giftDraftId,
          ).timeout(_backendTimeout);
        }
        if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) {
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftStatusView(draft: widget.draft),
            settings: const RouteSettings(name: GiftStatusView.routeName),
          ),
        );
        return;
      }
      if (!kIsWeb) {
        if (paymentData['requiresConfirmation'] != false) {
          await _confirmNativeGiftPayment(paymentData);
        }
        if (FirebaseAuth.instance.currentUser?.uid != user.uid) return;
        final finalized = await FirebaseFunctions.instance
            .httpsCallable('finalizeGiftPayment')
            .call({
          'giftDraftId': _giftDraftId,
          'paymentIntentId': paymentData['paymentIntentId'],
        }).timeout(_backendTimeout);
        final finalData = Map<String, dynamic>.from(finalized.data as Map);
        if (finalData['paymentStatus'] != 'paid') {
          throw StateError('Gift payment is still being verified.');
        }
        await NativePaymentIdentity.resolve(
          uid: user.uid,
          flow: 'gift',
          expected: _giftDraftId,
        ).timeout(_backendTimeout);
        if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) {
          return;
        }
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
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _message =
            'Payment is taking longer than expected. We will verify it before another attempt.';
      });
    } on StripeException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.error.code == FailureCode.Canceled
            ? 'Payment was cancelled. Your Gift request remains saved.'
            : 'Payment could not be completed. No duplicate request will be created.';
      });
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

  Future<bool> _recoverExistingNativeGift(User user) async {
    final db = FirebaseFirestore.instance;
    Future<QuerySnapshot<Map<String, dynamic>>> owned(String collection) => db
        .collection(collection)
        .where('senderId', isEqualTo: user.uid)
        .where(FieldPath.documentId, isEqualTo: _giftDraftId)
        .limit(1)
        .get(const GetOptions(source: Source.server))
        .timeout(_backendTimeout);
    final completed = await owned('giftRequests');
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) return true;
    var paid = completed.docs.isNotEmpty &&
        completed.docs.single.data()['paymentStatus'] == 'paid';
    if (!paid) {
      final drafts = await owned(senderGiftPaymentDraftCollectionName);
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) return true;
      if (drafts.docs.isNotEmpty) {
        final stored = drafts.docs.single.data();
        final intent = '${stored['stripePaymentIntentId'] ?? ''}';
        if (intent.isNotEmpty) {
          try {
            final result = await FirebaseFunctions.instance
                .httpsCallable('finalizeGiftPayment')
                .call({
              'giftDraftId': _giftDraftId,
              'paymentIntentId': intent,
            }).timeout(_backendTimeout);
            paid = (result.data as Map)['paymentStatus'] == 'paid';
          } on FirebaseFunctionsException catch (error) {
            if (error.code != 'failed-precondition') rethrow;
          }
        }
      }
    }
    if (!paid) return false;
    await NativePaymentIdentity.resolve(
      uid: user.uid,
      flow: 'gift',
      expected: _giftDraftId,
    ).timeout(_backendTimeout);
    if (mounted && FirebaseAuth.instance.currentUser?.uid == user.uid) {
      setState(() {
        _paymentComplete = true;
        _message =
            'Your saved Gift payment is confirmed. No further payment is needed.';
      });
    }
    return true;
  }

  Future<void> _confirmNativeGiftPayment(
    Map<String, dynamic> paymentData,
  ) async {
    final clientSecret = '${paymentData['clientSecret'] ?? ''}'.trim();
    if (clientSecret.isEmpty) {
      throw StateError('Gift payment confirmation is unavailable.');
    }
    if (_paymentMethod == 'Apple Pay') {
      final amount = (paymentData['remainingAmount'] as num?)?.toDouble() ?? 0;
      await Stripe.instance
          .confirmPlatformPayPaymentIntent(
            clientSecret: clientSecret,
            confirmParams: PlatformPayConfirmParams.applePay(
              applePay: ApplePayParams(
                merchantCountryCode: 'GB',
                currencyCode: 'GBP',
                cartItems: [
                  ApplePayCartSummaryItem.immediate(
                    label: 'Circum Gift',
                    amount: amount.toStringAsFixed(2),
                  ),
                ],
              ),
            ),
          )
          .timeout(_paymentSheetPresentTimeout);
      return;
    }
    if (_paymentMethod == 'Google Pay') {
      await Stripe.instance
          .confirmPlatformPayPaymentIntent(
            clientSecret: clientSecret,
            confirmParams: PlatformPayConfirmParams.googlePay(
              googlePay: GooglePayParams(
                merchantCountryCode: 'GB',
                currencyCode: 'GBP',
                merchantName: 'Circum',
                testEnv: Env.googlePayTestEnvironment,
              ),
            ),
          )
          .timeout(_paymentSheetPresentTimeout);
      return;
    }
    await Stripe.instance
        .initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            returnURL: nativePaymentReturnUrl,
            paymentIntentClientSecret: clientSecret,
            merchantDisplayName: 'Circum',
            customerId: '${paymentData['customerId'] ?? ''}',
            customerEphemeralKeySecret:
                '${paymentData['ephemeralKeySecret'] ?? ''}',
            style: ThemeMode.dark,
          ),
        )
        .timeout(_paymentSheetInitTimeout);
    await Stripe.instance.presentPaymentSheet().timeout(
          _paymentSheetPresentTimeout,
        );
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

class _RothBalanceSummary extends StatelessWidget {
  final bool loading;
  final bool unavailable;
  final double balance;
  final double applied;
  final double remaining;

  const _RothBalanceSummary({
    required this.loading,
    required this.unavailable,
    required this.balance,
    required this.applied,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    final balanceText = loading
        ? 'Loading...'
        : unavailable
            ? 'Unavailable'
            : '£${balance.toStringAsFixed(0)}';
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
          _PaymentSummaryRow(
            label: 'Available Roth balance',
            value: balanceText,
          ),
          const SizedBox(height: 8),
          _PaymentSummaryRow(
            label: 'Amount covered by Roth',
            value: '£${applied.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 8),
          _PaymentSummaryRow(
            label: 'Remaining card amount',
            value: '£${remaining.toStringAsFixed(0)}',
          ),
          if (unavailable) ...[
            const SizedBox(height: 10),
            Text(
              'Roth is currently unavailable. You can continue securely by card.',
              style: GoogleFonts.inter(
                color: const Color(0xFFB8AAB8),
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
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
          Expanded(child: _PaymentLabel(label)),
          _PaymentValue(value),
        ],
      ),
    );
  }
}

class _PaymentSummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _PaymentSummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _PaymentLabel(label)),
        _PaymentValue(value),
      ],
    );
  }
}

class _PaymentLabel extends StatelessWidget {
  final String label;

  const _PaymentLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.jetBrainsMono(
        color: const Color(0xFFB8AAB8),
        fontSize: 10,
        letterSpacing: .7,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _PaymentValue extends StatelessWidget {
  final String value;

  const _PaymentValue(this.value);

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
