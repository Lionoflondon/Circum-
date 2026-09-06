import 'package:circum/app/sender_mobile/native_payment_return.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../env/env.dart';

const _senderTipSheetInitTimeout = Duration(seconds: 20);
const _senderTipSheetPresentTimeout = Duration(seconds: 90);

const ratingFeedbackChoices = <String>[
  'Friendly',
  'Professional',
  'Fast',
  'Excellent Communication',
  'Careful Handling',
  'Late',
  'Hard to find',
  'Damaged item',
  'Safety concern',
];

String deliveryRatingTitle(int stars) => switch (stars) {
      5 => 'Outstanding Delivery',
      4 => 'Great Delivery',
      3 => 'Good Delivery',
      2 => 'Needs Improvement',
      1 => 'Poor Experience',
      _ => 'Rate your delivery',
    };

bool ratingMethodVisible(String method, TargetPlatform platform) {
  if (method == 'apple_pay') return platform == TargetPlatform.iOS;
  if (method == 'google_pay') return platform == TargetPlatform.android;
  return true;
}

bool ratingDeliveryReady(Map<String, dynamic> delivery) {
  final statuses = [
    delivery['status'],
    delivery['deliveryStatus'],
    delivery['deliveryState']
  ].whereType<String>().map((value) => value.toLowerCase()).toList();
  if (statuses.any((value) => {
        'cancelled',
        'canceled',
        'failed',
        'rejected',
        'refunded',
        'voided'
      }.contains(value))) {
    return false;
  }
  return statuses
          .any((value) => value == 'completed' || value == 'delivered') &&
      {'paid', 'succeeded', 'success'}
          .contains('${delivery['paymentStatus']}'.toLowerCase()) &&
      [delivery['riderId'], delivery['driverId'], delivery['assignedRiderId']]
          .any((value) => value is String && value.trim().isNotEmpty) &&
      delivery['refunded'] != true &&
      delivery['isTest'] != true &&
      delivery['testData'] != true;
}

class DeliveryAppreciationService {
  DeliveryAppreciationService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> submitRating({
    required String deliveryId,
    required int stars,
    required String feedback,
    required List<String> feedbackTags,
  }) async {
    final result = await _functions.httpsCallable('submitDeliveryRating').call({
      'deliveryId': deliveryId,
      'stars': stars,
      'feedback': feedback,
      'feedbackTags': feedbackTags,
    }).timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> submitTip({
    required String deliveryId,
    required int amountPence,
    required String paymentMethod,
    String? paymentIntentId,
    String? paymentMethodId,
  }) async {
    final result = await _functions.httpsCallable('submitDeliveryTip').call({
      'deliveryId': deliveryId,
      'amountPence': amountPence,
      'paymentMethod': paymentMethod,
      if (paymentIntentId != null) 'paymentIntentId': paymentIntentId,
      if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
    }).timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(result.data as Map);
  }
}

class RatingsView extends StatefulWidget {
  const RatingsView({
    super.key,
    required this.deliveryId,
    this.initialDelivery = const {},
    this.service,
    this.deliveryStream,
  });

  final String deliveryId;
  final Map<String, dynamic> initialDelivery;
  final DeliveryAppreciationService? service;
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? deliveryStream;

  @override
  State<RatingsView> createState() => _RatingsViewState();
}

class _RatingsViewState extends State<RatingsView> {
  static const _bg = Color(0xFF0B0D12);
  static const _panel = Color(0xFF14171F);
  static const _panel2 = Color(0xFF1B1F29);
  static const _blue = Color(0xFF3B82F6);
  static const _green = Color(0xFF34D399);
  static const _amber = Color(0xFFFBBF24);

  late final DeliveryAppreciationService _service;
  final _feedback = TextEditingController();
  final _customTip = TextEditingController();
  var _stars = 0;
  var _tipPence = 0;
  var _paymentMethod = 'roth';
  var _submitting = false;
  var _complete = false;
  String? _error;
  final _tags = <String>{};

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DeliveryAppreciationService();
  }

  @override
  void dispose() {
    _feedback.dispose();
    _customTip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_complete) return _thankYou();
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.deliveryStream ??
              FirebaseFirestore.instance
                  .collection('deliveryRequests')
                  .doc(widget.deliveryId)
                  .snapshots(),
          builder: (context, snapshot) {
            final delivery = <String, dynamic>{
              ...widget.initialDelivery,
              ...?snapshot.data?.data(),
            };
            if (!ratingDeliveryReady(delivery)) {
              return Center(
                  child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.rate_review_outlined,
                      color: Colors.white70, size: 40),
                  const SizedBox(height: 16),
                  Text(
                      snapshot.hasError
                          ? 'Delivery details could not be loaded. Please reopen feedback to try again.'
                          : 'Feedback and optional tips are available after your paid delivery is completed.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 16),
                  TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Back')),
                ]),
              ));
            }
            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: _bg.withValues(alpha: .94),
                  foregroundColor: Colors.white,
                  title: const Text('Delivery complete'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
                  sliver: SliverList.list(children: [
                    _successHeader(delivery),
                    const SizedBox(height: 18),
                    _deliverySummary(delivery),
                    const SizedBox(height: 24),
                    _rating(),
                    const SizedBox(height: 22),
                    _feedbackPanel(),
                    const SizedBox(height: 22),
                    _tipPanel(),
                    if (_tipPence > 0) ...[
                      const SizedBox(height: 22),
                      _paymentPanel(),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!,
                          style: const TextStyle(color: Color(0xFFF87171))),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed:
                            (_stars == 0 && _tipPence == 0) || _submitting
                                ? null
                                : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: _blue,
                          disabledBackgroundColor: _panel2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          child: _submitting
                              ? const SizedBox.square(
                                  key: ValueKey('loading'),
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.2, color: Colors.white),
                                )
                              : const Text(
                                  'Submit Appreciation',
                                  key: ValueKey('label'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15),
                                ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white70),
                      child: const Text('Not now'),
                    ),
                  ]),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _successHeader(Map<String, dynamic> data) {
    final duration = _text(data['deliveryDurationLabel'] ??
        data['durationLabel'] ??
        data['duration']);
    return Column(children: [
      TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 320),
        tween: Tween(begin: .7, end: 1),
        curve: Curves.easeOutBack,
        builder: (_, value, child) =>
            Transform.scale(scale: value, child: child),
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
              color: _green.withValues(alpha: .12), shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: _green, size: 30),
        ),
      ),
      const SizedBox(height: 12),
      const Text('Delivery complete',
          style: TextStyle(
              color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
      if (duration.isNotEmpty) ...[
        const SizedBox(height: 5),
        Text('Delivered in $duration',
            style: TextStyle(color: Colors.white.withValues(alpha: .58))),
      ],
    ]);
  }

  Widget _deliverySummary(Map<String, dynamic> data) {
    final rider = _map(data['riderSnapshot'] ?? data['activeVehicleSnapshot']);
    final name = _text(
        data['riderName'] ??
            data['driverName'] ??
            rider['riderName'] ??
            data['courierName'],
        fallback: 'Your Circum Rider');
    final photo =
        _text(data['riderPhotoUrl'] ?? data['photoURL'] ?? rider['photoUrl']);
    final vehicle = _text(
        rider['vehicleType'] ?? data['driverVehicle'] ?? data['typeOfVehicle'],
        fallback: 'Verified Circum Rider');
    final registration = _text(rider['registration'] ??
        data['driverPlateNumber'] ??
        data['plateNumber']);
    final rank = _text(data['riderRank'] ?? rider['rank']);
    final ratingCount = data['riderTotalRatings'] ?? rider['totalRatings'] ?? 0;
    final rating = (ratingCount is num && ratingCount > 0)
        ? (data['riderAverageRating'] ??
            data['riderRating'] ??
            rider['averageRating'])
        : null;
    final pickup =
        _address(data['pickup'] ?? data['pickupData'] ?? data['pickupAddress']);
    final destination = _address(
        data['dropoff'] ?? data['dropoffData'] ?? data['dropoffAddress']);
    return _glass(
      child: Column(children: [
        Row(children: [
          _avatar(photo, name),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                    [vehicle, registration]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .62),
                        fontSize: 12.5)),
                if (rank.isNotEmpty)
                  Text(rank,
                      style: const TextStyle(
                          color: _blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
              ])),
          if (rating is num)
            Text('★ ${rating.toStringAsFixed(1)} · $ratingCount ratings',
                style: const TextStyle(
                    color: _amber, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        Divider(color: Colors.white.withValues(alpha: .08), height: 1),
        const SizedBox(height: 14),
        _routeRow(Icons.radio_button_checked_rounded, 'Pickup', pickup),
        const SizedBox(height: 10),
        _routeRow(Icons.location_on_rounded, 'Destination', destination),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _metric(
              'Distance',
              _text(
                  data['distanceLabel'] ??
                      data['deliveryDistance'] ??
                      data['distance'],
                  fallback: '—')),
          _metric(
              'Duration',
              _text(data['deliveryDurationLabel'] ?? data['duration'],
                  fallback: '—')),
          _metric(
              'Delivery total',
              _money(
                  data['finalTotal'] ?? data['price'] ?? data['deliveryFee'])),
          _metric(
              'Roth earned', _money(data['rothAwarded'] ?? data['rothEarned'])),
        ]),
        if (data['rothAppliedAmount'] is num &&
            data['remainingAmount'] is num) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _metric('Paid with Roth', _money(data['rothAppliedAmount'])),
            _metric('Paid by card', _money(data['remainingAmount'])),
          ]),
          const SizedBox(height: 8),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('Any tip is separate from this delivery payment.',
                  style: TextStyle(color: Colors.white70, height: 1.4))),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: Text(
                  'IRIS · ${_text(data['irisCategory'] ?? _map(data['iris'])['category'], fallback: 'Delivery verified')}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .6),
                      fontSize: 12))),
          if (data['vanguardEnabled'] == true || data['isVanguard'] == true)
            _badge('Vanguard', _green),
        ]),
        const SizedBox(height: 8),
        Align(
            alignment: Alignment.centerLeft,
            child: Text(
                'Ref ${_text(data['reference'] ?? data['requestId'], fallback: widget.deliveryId)}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: .42),
                    fontFamily: 'monospace',
                    fontSize: 11))),
      ]),
    );
  }

  Widget _rating() => Column(children: [
        Text(deliveryRatingTitle(_stars),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('How was your delivery?',
            style: TextStyle(color: Colors.white.withValues(alpha: .55))),
        const SizedBox(height: 14),
        Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final selected = index < _stars;
              return Semantics(
                button: true,
                selected: _stars == index + 1,
                label: '${index + 1} star',
                child: IconButton(
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _stars = index + 1),
                  iconSize: 38,
                  splashRadius: 26,
                  icon: AnimatedScale(
                    scale: selected ? 1.08 : 1,
                    duration: const Duration(milliseconds: 260),
                    child: Icon(
                        selected
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: selected
                            ? _amber
                            : Colors.white.withValues(alpha: .28)),
                  ),
                ),
              );
            })),
      ]);

  Widget _feedbackPanel() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Optional feedback — shared with your Rider',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
        const SizedBox(height: 11),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ratingFeedbackChoices.map((choice) {
              final selected = _tags.contains(choice);
              return FilterChip(
                selected: selected,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: _submitting
                    ? null
                    : (value) => setState(() {
                          value ? _tags.add(choice) : _tags.remove(choice);
                        }),
                label: Text(choice),
                backgroundColor: _panel2,
                selectedColor: const Color(0xFF183D70),
                color: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? const Color(0xFF183D70)
                        : _panel2),
                checkmarkColor: const Color(0xFFAACFFF),
                side: BorderSide(
                    color: selected
                        ? _blue.withValues(alpha: .6)
                        : Colors.white.withValues(alpha: .08)),
                labelStyle: TextStyle(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: .66)),
              );
            }).toList()),
        if (_tags.contains('Safety concern') ||
            _tags.contains('Damaged item')) ...[
          const SizedBox(height: 12),
          const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.support_agent_rounded,
                color: Color(0xFFAACFFF), size: 22),
            SizedBox(width: 10),
            Expanded(
                child: Text(
                    'Submitting this rating also sends your feedback to Circum Support.',
                    style: TextStyle(color: Color(0xFFAACFFF), height: 1.4))),
          ]),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _feedback,
          enabled: !_submitting,
          maxLength: 500,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: _input('Add feedback (optional)'),
        ),
      ]);

  Widget _tipPanel() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Leave a tip (optional)',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
        const SizedBox(height: 4),
        Text('100% of your tip goes directly to your Circum Rider.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: .55), fontSize: 12.5)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: .92,
          children: const [
            (100, 'Thanks'),
            (200, 'Nice Work'),
            (500, 'Excellent'),
            (1000, 'Exceptional')
          ].map((item) {
            final selected = _tipPence == item.$1;
            return InkWell(
              onTap: _submitting
                  ? null
                  : () => setState(() {
                        _tipPence = item.$1;
                        _customTip.clear();
                      }),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                decoration: BoxDecoration(
                  color: selected ? _blue : _panel2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: selected
                          ? _blue
                          : Colors.white.withValues(alpha: .09)),
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('£${item.$1 ~/ 100}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              fontFamily: 'monospace')),
                      const SizedBox(height: 5),
                      Text(item.$2,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .66),
                              fontSize: 10.5)),
                    ]),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: TextField(
            controller: _customTip,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: _input('Custom amount'),
            onChanged: (value) {
              final amount = double.tryParse(value);
              setState(() =>
                  _tipPence = amount == null ? 0 : (amount * 100).round());
            },
          )),
          const SizedBox(width: 10),
          TextButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                        _tipPence = 0;
                        _customTip.clear();
                      }),
              child: const Text('No tip')),
        ]),
      ]);

  Widget _paymentPanel() {
    final options = <(String, String, IconData)>[
      ('roth', 'Roth', Icons.auto_awesome_rounded),
      ('saved_card', 'Saved card', Icons.credit_card_rounded),
      ('apple_pay', 'Apple Pay', Icons.phone_iphone_rounded),
      ('google_pay', 'Google Pay', Icons.phone_android_rounded),
    ].where((item) => ratingMethodVisible(item.$1, defaultTargetPlatform));
    return _glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Payment method',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...options.map((item) {
          final selected = _paymentMethod == item.$1;
          return InkWell(
            onTap: _submitting
                ? null
                : () => setState(() => _paymentMethod = item.$1),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              decoration: BoxDecoration(
                color: selected ? _blue.withValues(alpha: .16) : _panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? _blue : Colors.white.withValues(alpha: .08),
                ),
              ),
              child: Row(children: [
                Icon(item.$3, color: _blue),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(item.$2,
                      style: const TextStyle(color: Colors.white)),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? _blue : Colors.white.withValues(alpha: .3),
                ),
              ]),
            ),
          );
        }),
      ]),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_stars > 0) {
        await _service.submitRating(
          deliveryId: widget.deliveryId,
          stars: _stars,
          feedback: _feedback.text.trim(),
          feedbackTags: _tags.toList(),
        );
      }
      if (_tipPence > 0) {
        if (_tipPence < 100 || _tipPence > 10000) {
          throw StateError('Choose a tip between £1 and £100.');
        }
        var result = await _service.submitTip(
          deliveryId: widget.deliveryId,
          amountPence: _tipPence,
          paymentMethod: _paymentMethod,
        );
        final secret = _text(result['clientSecret']);
        if (secret.isNotEmpty && result['status'] != 'succeeded') {
          await Stripe.instance
              .initPaymentSheet(
                paymentSheetParameters: SetupPaymentSheetParameters(
                  returnURL: nativePaymentReturnUrl,
                  paymentIntentClientSecret: secret,
                  customerId: _text(result['customerId']),
                  customerEphemeralKeySecret:
                      _text(result['ephemeralKeySecret']),
                  merchantDisplayName: 'Circum',
                  applePay: !kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.iOS
                      ? const PaymentSheetApplePay(merchantCountryCode: 'GB')
                      : null,
                  googlePay:
                      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                          ? PaymentSheetGooglePay(
                              merchantCountryCode: 'GB',
                              currencyCode: 'GBP',
                              testEnv: Env.googlePayTestEnvironment,
                            )
                          : null,
                  style: ThemeMode.dark,
                ),
              )
              .timeout(_senderTipSheetInitTimeout);
          await Stripe.instance
              .presentPaymentSheet()
              .timeout(_senderTipSheetPresentTimeout);
          result = await _service.submitTip(
            deliveryId: widget.deliveryId,
            amountPence: _tipPence,
            paymentMethod: _paymentMethod,
            paymentIntentId: _text(result['paymentIntentId']),
          );
        }
        if (result['status'] != 'succeeded') {
          throw StateError(
              'Your tip is still processing. You can safely try again.');
        }
      }
      if (!mounted) {
        return;
      }
      setState(() => _complete = true);
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(() => _error =
            error.message ?? 'Something went wrong. Please try again.');
      }
    } on StripeException catch (error) {
      if (mounted) {
        setState(() => _error =
            error.error.localizedMessage ?? 'Payment was not completed.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message
            : 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _thankYou() => Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 350),
                  tween: Tween(begin: .5, end: 1),
                  curve: Curves.easeOutBack,
                  builder: (_, value, child) =>
                      Transform.scale(scale: value, child: child),
                  child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _green.withValues(alpha: .14)),
                      child: const Icon(Icons.favorite_rounded,
                          color: _green, size: 38)),
                ),
                const SizedBox(height: 24),
                const Text('Thank you.',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 9),
                Text(
                    _stars == 0
                        ? 'Your tip has been sent to your Rider.'
                        : _tags.any((tag) =>
                                tag == 'Safety concern' ||
                                tag == 'Damaged item')
                            ? 'Your rating is saved. Your feedback has been sent to Circum Support.'
                            : 'Your rating and feedback have been shared with your Rider.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .62),
                        fontSize: 15)),
                const SizedBox(height: 30),
                SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                        onPressed: () => Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                        style: FilledButton.styleFrom(
                            backgroundColor: _blue,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        child: const Text('Return Home'))),
              ]),
            ),
          ),
        ),
      );

  Widget _glass({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _panel2.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .22),
                blurRadius: 24,
                offset: const Offset(0, 12))
          ],
        ),
        child: child,
      );

  Widget _avatar(String photo, String name) => CircleAvatar(
        radius: 25,
        backgroundColor: _blue.withValues(alpha: .14),
        backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
        child: photo.isEmpty
            ? Text(
                name
                    .split(RegExp(r'\s+'))
                    .take(2)
                    .map((part) => part.isEmpty ? '' : part[0])
                    .join()
                    .toUpperCase(),
                style:
                    const TextStyle(color: _blue, fontWeight: FontWeight.w800))
            : null,
      );

  Widget _routeRow(IconData icon, String label, String value) => Row(children: [
        Icon(icon, color: label == 'Pickup' ? _blue : _green, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .38),
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value.isEmpty ? 'Address unavailable' : value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .82), fontSize: 13)),
        ])),
      ]);

  Widget _metric(String label, String value) => Container(
        width: 142,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
            color: _panel, borderRadius: BorderRadius.circular(11)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .35),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace')),
        ]),
      );

  Widget _badge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .28))),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 10.5)));

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: .34)),
        filled: true,
        fillColor: _panel,
        counterStyle: TextStyle(color: Colors.white.withValues(alpha: .35)),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .08))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .08))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _blue)),
      );

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};
  static String _text(Object? value, {String fallback = ''}) {
    final result = '${value ?? ''}'.trim();
    return result.isEmpty || result == 'null' ? fallback : result;
  }

  static String _address(Object? value) {
    if (value is Map) {
      return _text(value['address'] ??
          value['formattedAddress'] ??
          value['description']);
    }
    return _text(value);
  }

  static String _money(Object? value) {
    final amount =
        value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
    return amount == null ? '—' : '£${amount.toStringAsFixed(2)}';
  }
}
