import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/theme/theme.dart';
import '../health_plus_pricing.dart';
import '../models/pickup_status.dart';
import '../models/recurring_pickup_schedule.dart';

class HealthPlusView extends StatefulWidget {
  const HealthPlusView({super.key});

  @override
  State<HealthPlusView> createState() => _HealthPlusViewState();
}

class _HealthPlusViewState extends State<HealthPlusView> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _pharmacyAddress = TextEditingController();
  final _deliveryAddress = TextEditingController();
  final _notes = TextEditingController();
  final _preferredTime = TextEditingController(text: 'Tuesday, 10:00 AM');
  final _customSchedule = TextEditingController();

  HealthPlusFrequency _frequency = HealthPlusFrequency.monthly;
  bool _consent = false;
  bool _savePaymentMethod = true;
  bool _submitting = false;
  String? _profileId;
  String? _scheduleId;
  String? _message;
  String? _checkoutUrl;
  Map<String, dynamic>? _latestPickup;
  final List<Map<String, dynamic>> _payments = [];

  HealthPlusPriceBreakdown get _quote {
    return HealthPlusPricing.calculate(
      recurring: _frequency != HealthPlusFrequency.oneOff,
    );
  }

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _fullName.text = user?.displayName ?? '';
    _email.text = user?.email ?? '';
    _phone.text = user?.phoneNumber ?? '';
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    _pharmacyAddress.dispose();
    _deliveryAddress.dispose();
    _notes.dispose();
    _preferredTime.dispose();
    _customSchedule.dispose();
    super.dispose();
  }

  Future<void> _bookHealthPlus() async {
    if (_submitting) return;
    if (!_consent) {
      setState(() {
        _message =
            'Please confirm the prescription is valid and ready for collection.';
      });
      return;
    }

    final quote = _quote;
    setState(() {
      _submitting = true;
      _message = 'Creating your Health+ pickup and secure checkout...';
    });

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createHealthPlusBooking')
          .call<Map<String, dynamic>>({
        'fullName': _fullName.text.trim(),
        'phoneNumber': _phone.text.trim(),
        'email': _email.text.trim(),
        'pharmacyAddress': _pharmacyAddress.text.trim(),
        'deliveryAddress': _deliveryAddress.text.trim(),
        'notes': _notes.text.trim(),
        'consentConfirmed': _consent,
        'preferredPickupTime': _preferredTime.text.trim(),
        'frequency': _frequency.value,
        'customSchedule': _customSchedule.text.trim(),
        'savedPaymentMethod': _savePaymentMethod,
        'pricingInputs': {
          'distanceMiles': HealthPlusPricing.defaultDistanceMiles,
          'medicationWeightKg': HealthPlusPricing.defaultMedicationWeightKg,
        },
        'idempotencyKey':
            'healthplus:${FirebaseAuth.instance.currentUser?.uid}:${_frequency.value}:${_preferredTime.text.trim()}',
      });
      final data = Map<String, dynamic>.from(result.data);
      final profileId = '${data['profileId'] ?? ''}'.trim();
      final pickupId = '${data['pickupId'] ?? ''}'.trim();
      final scheduleId = '${data['scheduleId'] ?? ''}'.trim();
      final amount = (data['amount'] as num?)?.toDouble() ?? quote.total;
      final checkoutUrl = await _createCheckoutSession(
        pickupId: pickupId,
        profileId: profileId,
        quote: quote,
      );

      if (!mounted) return;
      setState(() {
        _profileId = profileId;
        _scheduleId = scheduleId.isEmpty ? null : scheduleId;
        _latestPickup = {
          'id': pickupId,
          'profileId': profileId,
          'scheduleId': scheduleId.isEmpty ? null : scheduleId,
          'fullName': _fullName.text.trim(),
          'pharmacyAddress': _pharmacyAddress.text.trim(),
          'deliveryAddress': _deliveryAddress.text.trim(),
          'preferredPickupTime': _preferredTime.text.trim(),
          'frequency': _frequency.value,
          'status': PickupStatus.scheduled.value,
          'price': amount,
          'currency': 'GBP',
        };
        _checkoutUrl = checkoutUrl;
        _payments.insert(0, {
          'pickupId': pickupId,
          'amount': amount,
          'status': checkoutUrl == null
              ? 'pending_secure_checkout'
              : 'checkout_created',
        });
        _message = checkoutUrl == null
            ? 'Health+ pickup saved. Secure checkout needs configuration.'
            : 'Health+ pickup saved. Secure checkout is ready.';
      });

      if (checkoutUrl != null) {
        await launchUrl(Uri.parse(checkoutUrl),
            mode: LaunchMode.externalApplication);
      }
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message ??
            'Health+ could not be saved. Please check the details and try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Health+ could not be saved. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String?> _createCheckoutSession({
    required String pickupId,
    required String profileId,
    required HealthPlusPriceBreakdown quote,
  }) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.post(
        Uri.parse(
          'https://us-central1-circum-2797c.cloudfunctions.net/createHealthPlusCheckoutSession',
        ),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'bookingId': pickupId,
          'profileId': profileId,
          'email': _email.text.trim(),
          'frequency': _frequency.value,
          'priceBreakdown': quote.toJson(),
          'successUrl':
              'https://circum-app-2797c.web.app/?app=health&health=success',
          'cancelUrl':
              'https://circum-app-2797c.web.app/?app=health&health=cancelled',
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['checkoutUrl'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openCheckout() async {
    if (_checkoutUrl == null) {
      setState(() {
        _message = 'No secure checkout link yet. Create the booking first.';
      });
      return;
    }
    await launchUrl(Uri.parse(_checkoutUrl!),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _pauseSchedule() async {
    if (_scheduleId == null) {
      setState(() => _message = 'This Health+ pickup is one-off.');
      return;
    }
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('updateSenderHealthPlusBooking')
        .call({
      'action': 'pause_schedule',
      'scheduleId': _scheduleId,
      'idempotencyKey': 'healthplus:pause:$_scheduleId',
    });
    setState(() => _message = 'Recurring Health+ pickup paused.');
  }

  Future<void> _resumeSchedule() async {
    if (_scheduleId == null) {
      setState(() => _message = 'This Health+ pickup is one-off.');
      return;
    }
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('updateSenderHealthPlusBooking')
        .call({
      'action': 'resume_schedule',
      'scheduleId': _scheduleId,
      'idempotencyKey': 'healthplus:resume:$_scheduleId',
    });
    setState(() => _message = 'Recurring Health+ pickup resumed.');
  }

  Future<void> _cancelPickup() async {
    final pickupId = _latestPickup?['id']?.toString();
    if (pickupId == null) return;
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('updateSenderHealthPlusBooking')
        .call({
      'action': 'cancel_pickup',
      'pickupId': pickupId,
      'idempotencyKey': 'healthplus:cancel:$pickupId',
    });
    setState(() {
      _latestPickup = {
        ...?_latestPickup,
        'status': PickupStatus.cancelled.value
      };
      _message = 'Next Health+ pickup cancelled.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xffdcfce7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.health_and_safety,
                      color: Color(0xff16a34a)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText.text('Health+',
                          fontSize: 28, fontWeight: FontWeight.w800),
                      const SizedBox(height: 2),
                      AppText.text('Starting from £11',
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w700),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.text('Get your meds before you need them.',
                      fontSize: 28, fontWeight: FontWeight.w900),
                  const SizedBox(height: 8),
                  AppText.text(
                    'Medication and prescription pickup management from pharmacy to door.',
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w600,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _ChipText('One-off'),
                      _ChipText('Recurring'),
                      _ChipText('Secure checkout'),
                      _ChipText('Sealed packages only'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionTitle('Enrolment details'),
            _HealthInput(controller: _fullName, hint: 'Full name'),
            _HealthInput(controller: _phone, hint: 'Phone number'),
            _HealthInput(controller: _email, hint: 'Email'),
            _HealthInput(
                controller: _pharmacyAddress,
                hint: 'Pickup address / pharmacy address'),
            _HealthInput(
                controller: _deliveryAddress, hint: 'Delivery address'),
            _HealthInput(
              controller: _notes,
              hint: 'Prescription / pickup notes',
              maxLines: 3,
            ),
            const SizedBox(height: 14),
            _SectionTitle('Pickup schedule'),
            _FrequencyPicker(
              selected: _frequency,
              onChanged: (value) => setState(() => _frequency = value),
            ),
            _HealthInput(
                controller: _preferredTime, hint: 'Preferred pickup day/time'),
            if (_frequency == HealthPlusFrequency.custom)
              _HealthInput(
                  controller: _customSchedule, hint: 'Custom repeat schedule'),
            const SizedBox(height: 14),
            _PricePanel(quote: quote, frequency: _frequency),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
              value: _savePaymentMethod,
              onChanged: (value) => setState(() => _savePaymentMethod = value),
              title: AppText.text('Save payment method for Health+',
                  fontWeight: FontWeight.w700),
            ),
            _Disclaimer(),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
              value: _consent,
              onChanged: (value) => setState(() => _consent = value ?? false),
              title: AppText.text(
                'I confirm the prescription is valid and ready or will be ready for pharmacy collection.',
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              AppText.text(_message!, fontWeight: FontWeight.w800),
            ],
            const SizedBox(height: 12),
            AppButton.button(
              isLoading: _submitting,
              onPressed: _bookHealthPlus,
              minimumSize: const Size(double.maxFinite, 54),
              widget: AppText.text(
                _submitting
                    ? 'Creating Health+...'
                    : 'Pay £${quote.total.toStringAsFixed(2)} securely',
                fontWeight: FontWeight.w800,
              ),
            ),
            if (_checkoutUrl != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openCheckout,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open secure checkout'),
              ),
            ],
            const SizedBox(height: 18),
            _Dashboard(
              pickup: _latestPickup,
              payments: _payments,
              onPauseSchedule: _pauseSchedule,
              onResumeSchedule: _resumeSchedule,
              onCancelPickup: _cancelPickup,
              onUpdatePayment: _openCheckout,
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.maxFinite,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sheetBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppText.text(title, fontSize: 18, fontWeight: FontWeight.w800),
    );
  }
}

class _HealthInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  const _HealthInput({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontFamily: 'Helvetica'),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.42)),
          filled: true,
          fillColor: AppColors.input,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}

class _FrequencyPicker extends StatelessWidget {
  final HealthPlusFrequency selected;
  final ValueChanged<HealthPlusFrequency> onChanged;

  const _FrequencyPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: HealthPlusFrequency.values.map((frequency) {
          final active = frequency == selected;
          return ChoiceChip(
            selected: active,
            label: Text(frequency.label),
            onSelected: (_) => onChanged(frequency),
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.input,
            labelStyle: TextStyle(
              color: active ? Colors.white : AppColors.textGrey,
              fontWeight: FontWeight.w800,
              fontFamily: 'Helvetica',
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          );
        }).toList(),
      ),
    );
  }
}

class _ChipText extends StatelessWidget {
  final String label;

  const _ChipText(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xffdcfce7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xff166534),
          fontWeight: FontWeight.w800,
          fontFamily: 'Helvetica',
        ),
      ),
    );
  }
}

class _PricePanel extends StatelessWidget {
  final HealthPlusPriceBreakdown quote;
  final HealthPlusFrequency frequency;

  const _PricePanel({required this.quote, required this.frequency});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Price breakdown'),
          _PriceRow('Base fare', quote.delivery.baseFare),
          _PriceRow('Mileage fare', quote.delivery.distanceFare),
          _PriceRow(
              'Medication parcel surcharge', quote.delivery.weightSurcharge),
          _PriceRow('Health+ service fee', quote.serviceFee),
          if (quote.minimumAdjustment > 0)
            _PriceRow('Health+ minimum adjustment', quote.minimumAdjustment),
          const Divider(color: AppColors.borderColor, height: 24),
          _PriceRow(
            frequency == HealthPlusFrequency.oneOff
                ? 'One-off total'
                : 'Recurring pickup total',
            quote.total,
            strong: true,
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final double value;
  final bool strong;

  const _PriceRow(this.label, this.value, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: AppText.text(label,
                color: AppColors.textGrey,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600),
          ),
          AppText.text('£${value.toStringAsFixed(2)}',
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      'Health+ is a pickup and delivery service only.',
      'Circum does not prescribe medication.',
      'Users are responsible for valid prescriptions that are ready for collection.',
      'Drivers collect and deliver sealed pharmacy packages only.',
    ];

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.text('Safety and compliance', fontWeight: FontWeight.w800),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppText.text('• $item',
                  color: AppColors.textGrey, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final Map<String, dynamic>? pickup;
  final List<Map<String, dynamic>> payments;
  final VoidCallback onPauseSchedule;
  final VoidCallback onResumeSchedule;
  final VoidCallback onCancelPickup;
  final VoidCallback onUpdatePayment;

  const _Dashboard({
    required this.pickup,
    required this.payments,
    required this.onPauseSchedule,
    required this.onResumeSchedule,
    required this.onCancelPickup,
    required this.onUpdatePayment,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.text('Your Health+ dashboard',
              fontSize: 18, fontWeight: FontWeight.w800),
          const SizedBox(height: 10),
          if (pickup == null)
            AppText.text(
              'Upcoming pickups, payment history, and recurring controls will appear here after enrolment.',
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
            )
          else ...[
            _DashboardRow('Upcoming pickup',
                pickup!['preferredPickupTime']?.toString() ?? 'Scheduled'),
            _DashboardRow(
                'Status', pickup!['status']?.toString() ?? 'scheduled'),
            _DashboardRow(
              'Payment history',
              payments.isEmpty
                  ? 'No payments yet'
                  : '£${payments.first['amount']} - ${payments.first['status']}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onPauseSchedule,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause recurring'),
                ),
                OutlinedButton.icon(
                  onPressed: onResumeSchedule,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume recurring'),
                ),
                OutlinedButton.icon(
                  onPressed: onCancelPickup,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel pickup'),
                ),
                OutlinedButton.icon(
                  onPressed: onUpdatePayment,
                  icon: const Icon(Icons.credit_card),
                  label: const Text('Update payment'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardRow extends StatelessWidget {
  final String label;
  final String value;

  const _DashboardRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
              child: AppText.text(label,
                  color: AppColors.textGrey, fontWeight: FontWeight.w700)),
          Flexible(
              child: AppText.text(value,
                  textAlign: TextAlign.right, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
