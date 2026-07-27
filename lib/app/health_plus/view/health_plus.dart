import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../send_package/models/suggestions.m.dart';
import '../../send_package/repo/place_api.dart';
import '../health_plus_pricing.dart';
import '../models/pickup_status.dart';
import '../models/recurring_pickup_schedule.dart';

enum _HealthStep {
  status,
  details,
  pharmacy,
  delivery,
  frequency,
  plan,
  notes,
  review,
  checkout,
  confirmed,
}

extension _HealthStepCopy on _HealthStep {
  String get label {
    return switch (this) {
      _HealthStep.status => 'Status',
      _HealthStep.details => 'Details',
      _HealthStep.pharmacy => 'Pharmacy',
      _HealthStep.delivery => 'Delivery',
      _HealthStep.frequency => 'Frequency',
      _HealthStep.plan => 'Plan',
      _HealthStep.notes => 'Notes',
      _HealthStep.review => 'Review',
      _HealthStep.checkout => 'Checkout',
      _HealthStep.confirmed => 'Confirmed',
    };
  }

  String get eyebrow {
    return switch (this) {
      _HealthStep.status => 'HEALTH+',
      _HealthStep.details => 'STEP 01 - YOUR DETAILS',
      _HealthStep.pharmacy => 'STEP 02 - PHARMACY',
      _HealthStep.delivery => 'STEP 03 - DELIVERY',
      _HealthStep.frequency => 'STEP 04 - FREQUENCY',
      _HealthStep.plan => 'STEP 05 - PLAN',
      _HealthStep.notes => 'STEP 06 - NOTES & CONSENT',
      _HealthStep.review => 'STEP 07 - REVIEW',
      _HealthStep.checkout => 'STEP 08 - CHECKOUT',
      _HealthStep.confirmed => 'STEP 09 - CONFIRMED',
    };
  }

  String get question {
    return switch (this) {
      _HealthStep.status => 'Your prescription pickups',
      _HealthStep.details => 'Confirm who this is for',
      _HealthStep.pharmacy => "Where's the prescription?",
      _HealthStep.delivery => 'Where should it go?',
      _HealthStep.frequency => 'How often?',
      _HealthStep.plan => 'Choose your plan',
      _HealthStep.notes => 'Anything the Circum Rider should know?',
      _HealthStep.review => 'Review your pickup',
      _HealthStep.checkout => 'Secure payment',
      _HealthStep.confirmed => 'Pickup scheduled',
    };
  }
}

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
  final _preferredTime =
      TextEditingController(text: _defaultHealthPickupDateTime());
  final _customSchedule = TextEditingController();
  final _pharmacySearch = _HealthPlaceSearchController();
  final _deliverySearch = _HealthPlaceSearchController();

  var _step = _HealthStep.status;
  var _frequency = HealthPlusFrequency.monthly;
  var _plan = 'basic';
  var _consent = false;
  var _savePaymentMethod = true;
  var _useRoth = false;
  var _submitting = false;
  double _rothBalance = 0;
  String? _scheduleId;
  String? _message;
  String? _checkoutUrl;
  Map<String, dynamic>? _latestPickup;
  final List<Map<String, dynamic>> _payments = [];

  HealthPlusPriceBreakdown get _quote {
    return HealthPlusPricing.calculate(
      recurring: _frequency != HealthPlusFrequency.oneOff,
      subscriptionPlan: _plan,
    );
  }

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _fullName.text = user?.displayName ?? '';
    _email.text = user?.email ?? '';
    _phone.text = user?.phoneNumber ?? '';
    _loadRothBalance();
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
    _pharmacySearch.dispose();
    _deliverySearch.dispose();
    super.dispose();
  }

  void _goTo(_HealthStep step) {
    setState(() {
      _message = null;
      _step = step;
    });
  }

  void _next() {
    switch (_step) {
      case _HealthStep.status:
        _goTo(_HealthStep.details);
      case _HealthStep.details:
        if (_requireText(_fullName, 'Add your full name.') &&
            _requireText(_phone, 'Add your phone number.') &&
            _requireText(_email, 'Add your email.')) {
          _goTo(_HealthStep.pharmacy);
        }
      case _HealthStep.pharmacy:
        if (_requireText(_pharmacyAddress, 'Choose a pharmacy.')) {
          _goTo(_HealthStep.delivery);
        }
      case _HealthStep.delivery:
        if (_requireText(_deliveryAddress, 'Choose a delivery address.')) {
          _goTo(_HealthStep.frequency);
        }
      case _HealthStep.frequency:
        _goTo(_HealthStep.plan);
      case _HealthStep.plan:
        _goTo(_HealthStep.notes);
      case _HealthStep.notes:
        if (!_consent) {
          setState(() {
            _message =
                'Please confirm the prescription is valid and ready for collection.';
          });
          return;
        }
        _goTo(_HealthStep.review);
      case _HealthStep.review:
        _goTo(_HealthStep.checkout);
      case _HealthStep.checkout:
        _bookHealthPlus();
      case _HealthStep.confirmed:
        _goTo(_HealthStep.status);
    }
  }

  bool _requireText(TextEditingController controller, String message) {
    if (controller.text.trim().isNotEmpty) return true;
    setState(() => _message = message);
    return false;
  }

  Future<void> _loadRothBalance() async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getSenderRothBalance')
          .call<Map<String, dynamic>>();
      final data = Map<String, dynamic>.from(result.data);
      if (!mounted) return;
      setState(() {
        _rothBalance = (data['availableRoth'] as num?)?.toDouble() ??
            (data['balance'] as num?)?.toDouble() ??
            0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _rothBalance = 0);
    }
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
        'subscriptionPlan': _plan,
        'pricingInputs': {
          'distanceMiles': HealthPlusPricing.defaultDistanceMiles,
          'medicationWeightKg': HealthPlusPricing.defaultMedicationWeightKg,
        },
        'idempotencyKey':
            'healthplus:${FirebaseAuth.instance.currentUser?.uid}:${_frequency.value}:${_preferredTime.text.trim()}:$_plan',
      });
      final data = Map<String, dynamic>.from(result.data);
      final profileId = '${data['profileId'] ?? ''}'.trim();
      final pickupId = '${data['pickupId'] ?? ''}'.trim();
      final scheduleId = '${data['scheduleId'] ?? ''}'.trim();
      final amount = (data['amount'] as num?)?.toDouble() ?? quote.total;
      final checkout = await _createCheckoutSession(
        pickupId: pickupId,
        profileId: profileId,
        quote: quote,
      );
      final checkoutUrl =
          checkout == null ? null : '${checkout['checkoutUrl'] ?? ''}'.trim();
      final paid = checkout != null && checkout['paid'] == true;
      final hasCheckoutUrl = checkoutUrl != null && checkoutUrl.isNotEmpty;

      if (!mounted) return;
      setState(() {
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
          'status': paid
              ? 'paid'
              : !hasCheckoutUrl
                  ? 'pending_secure_checkout'
                  : 'checkout_created',
          'rothApplied': checkout?['rothApplied'],
          'cardAmount': checkout?['cardAmount'],
        });
        _message = paid
            ? 'Health+ pickup paid with Roth.'
            : !hasCheckoutUrl
                ? 'Health+ pickup saved. Secure checkout needs configuration.'
                : 'Health+ pickup saved. Secure checkout is ready.';
        _step = _HealthStep.confirmed;
      });

      if (hasCheckoutUrl) {
        await launchUrl(
          Uri.parse(checkoutUrl),
          mode: LaunchMode.externalApplication,
        );
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

  Future<Map<String, dynamic>?> _createCheckoutSession({
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
          'useRoth': _useRoth,
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
      return data;
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
    await launchUrl(
      Uri.parse(_checkoutUrl!),
      mode: LaunchMode.externalApplication,
    );
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
        'status': PickupStatus.cancelled.value,
      };
      _message = 'Next Health+ pickup cancelled.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final stepIndex = _HealthStep.values.indexOf(_step);
    return Scaffold(
      backgroundColor: _HealthTokens.bg,
      body: SafeArea(
        child: Stack(
          children: [
            const _HealthBackdrop(),
            Column(
              children: [
                _HealthTopBar(
                  canGoBack: _step != _HealthStep.status,
                  onBack: () {
                    if (_step == _HealthStep.status) {
                      Navigator.of(context).maybePop();
                      return;
                    }
                    _goTo(_HealthStep.values[stepIndex - 1]);
                  },
                  stepIndex: stepIndex,
                ),
                Expanded(
                  child: ListView(
                    key: const Key('sender-health-guided-flow'),
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                    children: [
                      _HealthStepRail(
                        selected: _step,
                        onSelected: _goTo,
                      ),
                      const SizedBox(height: 18),
                      _HealthEyebrow(_step.eyebrow),
                      const SizedBox(height: 6),
                      Text(
                        _step.question,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: _buildStep(),
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        _HealthNotice(message: _message!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      _HealthStep.status => _HealthStatusStep(
          pickup: _latestPickup,
          payments: _payments,
          onNewPickup: () => _goTo(_HealthStep.details),
          onPauseSchedule: _pauseSchedule,
          onResumeSchedule: _resumeSchedule,
          onCancelPickup: _cancelPickup,
          onOpenCheckout: _openCheckout,
        ),
      _HealthStep.details => _HealthDetailsStep(
          fullName: _fullName,
          phone: _phone,
          email: _email,
          onContinue: _next,
        ),
      _HealthStep.pharmacy => _HealthAddressStep(
          title: 'Search pharmacy or address',
          controller: _pharmacyAddress,
          search: _pharmacySearch,
          onSelected: () => _goTo(_HealthStep.delivery),
          onContinue: _next,
        ),
      _HealthStep.delivery => _HealthAddressStep(
          title: 'Search delivery address',
          controller: _deliveryAddress,
          search: _deliverySearch,
          onSelected: () => _goTo(_HealthStep.frequency),
          onContinue: _next,
        ),
      _HealthStep.frequency => _HealthFrequencyStep(
          selected: _frequency,
          customSchedule: _customSchedule,
          preferredTime: _preferredTime,
          onChanged: (value) => setState(() => _frequency = value),
          onContinue: _next,
        ),
      _HealthStep.plan => _HealthPlanStep(
          selected: _plan,
          frequency: _frequency,
          onChanged: (value) => setState(() => _plan = value),
          onContinue: _next,
        ),
      _HealthStep.notes => _HealthNotesStep(
          notes: _notes,
          consent: _consent,
          savePaymentMethod: _savePaymentMethod,
          onConsent: (value) => setState(() => _consent = value),
          onSavePayment: (value) => setState(() => _savePaymentMethod = value),
          onContinue: _next,
        ),
      _HealthStep.review => _HealthReviewStep(
          quote: _quote,
          frequency: _frequency,
          plan: _plan,
          pharmacy: _pharmacyAddress.text.trim(),
          delivery: _deliveryAddress.text.trim(),
          preferredTime: _preferredTime.text.trim(),
          onContinue: _next,
        ),
      _HealthStep.checkout => _HealthCheckoutStep(
          quote: _quote,
          submitting: _submitting,
          useRoth: _useRoth,
          rothBalance: _rothBalance,
          recurring: _frequency != HealthPlusFrequency.oneOff,
          onUseRoth: (value) => setState(() => _useRoth = value),
          onCheckout: _next,
        ),
      _HealthStep.confirmed => _HealthConfirmedStep(
          pickup: _latestPickup,
          onStatus: () => _goTo(_HealthStep.status),
          onCheckout: _openCheckout,
        ),
    };
  }
}

class _HealthPlaceSearchController {
  final provider = PlaceApiProvider(DateTime.now().microsecondsSinceEpoch);
  Timer? _debounce;
  var loading = false;
  String? error;
  List<Suggestion> suggestions = const [];

  void dispose() => _debounce?.cancel();

  void search(String query, VoidCallback onChanged) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      loading = false;
      error = null;
      suggestions = const [];
      onChanged();
      return;
    }
    loading = true;
    error = null;
    onChanged();
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        suggestions = await provider.fetchSuggestions(query, 'en');
        error = null;
      } catch (_) {
        suggestions = const [];
        error = 'Address search is unavailable. You can type the address.';
      } finally {
        loading = false;
        onChanged();
      }
    });
  }
}

class _HealthTopBar extends StatelessWidget {
  final bool canGoBack;
  final VoidCallback onBack;
  final int stepIndex;

  const _HealthTopBar({
    required this.canGoBack,
    required this.onBack,
    required this.stepIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          _HealthIconButton(
            icon: canGoBack ? Icons.arrow_back_ios_new_rounded : Icons.close,
            onTap: onBack,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: List.generate(_HealthStep.values.length - 1, (index) {
                final filled = index < stepIndex;
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(
                      right: index == _HealthStep.values.length - 2 ? 0 : 4,
                    ),
                    decoration: BoxDecoration(
                      color: filled
                          ? _HealthTokens.health
                          : Colors.white.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthStepRail extends StatelessWidget {
  final _HealthStep selected;
  final ValueChanged<_HealthStep> onSelected;

  const _HealthStepRail({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final step in _HealthStep.values) ...[
            _HealthStepChip(
              label:
                  '${_HealthStep.values.indexOf(step).toString().padLeft(2, '0')} ${step.label}',
              selected: step == selected,
              onTap: () => onSelected(step),
            ),
            if (step != _HealthStep.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _HealthStepChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HealthStepChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? _HealthTokens.health.withValues(alpha: .16)
              : Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? _HealthTokens.health
                : Colors.white.withValues(alpha: .10),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _HealthTokens.muted,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _HealthStatusStep extends StatelessWidget {
  final Map<String, dynamic>? pickup;
  final List<Map<String, dynamic>> payments;
  final VoidCallback onNewPickup;
  final VoidCallback onPauseSchedule;
  final VoidCallback onResumeSchedule;
  final VoidCallback onCancelPickup;
  final VoidCallback onOpenCheckout;

  const _HealthStatusStep({
    required this.pickup,
    required this.payments,
    required this.onNewPickup,
    required this.onPauseSchedule,
    required this.onResumeSchedule,
    required this.onCancelPickup,
    required this.onOpenCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final hasPickup = pickup != null;
    final status = PickupStatusValue.fromValue(
      '${pickup?['status'] ?? PickupStatus.scheduled.value}',
    );
    return Column(
      children: [
        _HealthGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HealthBadge(hasPickup ? status.value : 'No active pickup'),
              const SizedBox(height: 10),
              Text(
                hasPickup
                    ? '${pickup!['frequency'] ?? 'monthly'} pickup'
                    : 'Guided prescription pickup',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hasPickup
                    ? '${pickup!['pharmacyAddress'] ?? 'Pharmacy'} to ${pickup!['deliveryAddress'] ?? 'delivery address'}'
                    : 'Set up a one-off or recurring pharmacy collection in a few guided steps.',
                style: const TextStyle(
                  color: _HealthTokens.muted,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasPickup) ...[
                const SizedBox(height: 16),
                _HealthTimeline(current: status),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _HealthMiniButton('Pause', onPauseSchedule),
                    _HealthMiniButton('Resume', onResumeSchedule),
                    _HealthMiniButton('Cancel', onCancelPickup, danger: true),
                    _HealthMiniButton('Checkout', onOpenCheckout),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _HealthGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'History',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              if (payments.isEmpty)
                const Text(
                  'Pickup and payment history will appear here.',
                  style: TextStyle(color: _HealthTokens.muted),
                )
              else
                ...payments.map((payment) {
                  return _HealthReviewRow(
                    label: '${payment['status'] ?? 'Payment'}',
                    value: '£${payment['amount'] ?? '-'}',
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _HealthPrimaryButton(
          label: hasPickup ? 'Book another pickup' : 'Book a new pickup',
          icon: Icons.medical_services_outlined,
          onTap: onNewPickup,
        ),
      ],
    );
  }
}

class _HealthDetailsStep extends StatelessWidget {
  final TextEditingController fullName;
  final TextEditingController phone;
  final TextEditingController email;
  final VoidCallback onContinue;

  const _HealthDetailsStep({
    required this.fullName,
    required this.phone,
    required this.email,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return _HealthStepCard(
      children: [
        _HealthInput(controller: fullName, label: 'Full name'),
        _HealthInput(controller: phone, label: 'Phone'),
        _HealthInput(controller: email, label: 'Email'),
        _HealthPrimaryButton(label: 'Continue', onTap: onContinue),
      ],
    );
  }
}

class _HealthAddressStep extends StatefulWidget {
  final String title;
  final TextEditingController controller;
  final _HealthPlaceSearchController search;
  final VoidCallback onSelected;
  final VoidCallback onContinue;

  const _HealthAddressStep({
    required this.title,
    required this.controller,
    required this.search,
    required this.onSelected,
    required this.onContinue,
  });

  @override
  State<_HealthAddressStep> createState() => _HealthAddressStepState();
}

class _HealthAddressStepState extends State<_HealthAddressStep> {
  @override
  Widget build(BuildContext context) {
    return _HealthStepCard(
      children: [
        _HealthInput(
          controller: widget.controller,
          label: widget.title,
          prefixIcon: Icons.search_rounded,
          onChanged: (value) => widget.search.search(value, () {
            if (mounted) setState(() {});
          }),
        ),
        if (widget.search.loading)
          const _HealthInlineState('Searching addresses...')
        else if (widget.search.error != null)
          _HealthInlineState(widget.search.error!)
        else if (widget.search.suggestions.isNotEmpty)
          ...widget.search.suggestions.map(
            (suggestion) => _HealthSuggestionRow(
              suggestion: suggestion,
              onTap: () {
                widget.controller.text = suggestion.description;
                widget.onSelected();
              },
            ),
          ),
        if (widget.controller.text.trim().isNotEmpty)
          _HealthPrimaryButton(label: 'Continue', onTap: widget.onContinue),
      ],
    );
  }
}

class _HealthFrequencyStep extends StatelessWidget {
  final HealthPlusFrequency selected;
  final TextEditingController customSchedule;
  final TextEditingController preferredTime;
  final ValueChanged<HealthPlusFrequency> onChanged;
  final VoidCallback onContinue;

  const _HealthFrequencyStep({
    required this.selected,
    required this.customSchedule,
    required this.preferredTime,
    required this.onChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return _HealthStepCard(
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: HealthPlusFrequency.values.map((frequency) {
            return _HealthChoiceCard(
              title: frequency.label,
              subtitle: _frequencySubtitle(frequency),
              selected: frequency == selected,
              onTap: () => onChanged(frequency),
            );
          }).toList(),
        ),
        _HealthDateTimeInput(
          controller: preferredTime,
          label: 'Preferred pickup date and time',
        ),
        if (selected == HealthPlusFrequency.custom)
          _HealthInput(
            controller: customSchedule,
            label: 'Custom repeat schedule',
          ),
        _HealthPrimaryButton(label: 'Continue', onTap: onContinue),
      ],
    );
  }

  String _frequencySubtitle(HealthPlusFrequency frequency) {
    return switch (frequency) {
      HealthPlusFrequency.oneOff => 'Single collection',
      HealthPlusFrequency.weekly => 'Every 7 days',
      HealthPlusFrequency.everyTwoWeeks => 'Fortnightly',
      HealthPlusFrequency.every28Days => '4-week cycle',
      HealthPlusFrequency.monthly => 'Calendar month',
      HealthPlusFrequency.custom => 'Set your own repeat',
    };
  }
}

class _HealthPlanStep extends StatelessWidget {
  final String selected;
  final HealthPlusFrequency frequency;
  final ValueChanged<String> onChanged;
  final VoidCallback onContinue;

  const _HealthPlanStep({
    required this.selected,
    required this.frequency,
    required this.onChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return _HealthStepCard(
      children: [
        ..._healthPlans.map((plan) {
          final quote = HealthPlusPricing.calculate(
            recurring: frequency != HealthPlusFrequency.oneOff,
            subscriptionPlan: plan.id,
          );
          return _HealthPlanCard(
            plan: plan,
            quote: quote,
            selected: selected == plan.id,
            onTap: () => onChanged(plan.id),
          );
        }),
        _HealthPrimaryButton(
          label: frequency == HealthPlusFrequency.oneOff
              ? 'Continue one-off pickup'
              : 'Start subscription',
          onTap: onContinue,
        ),
      ],
    );
  }
}

const _healthPlans = [
  _HealthPlan(
    id: 'basic',
    title: 'Health+ Basic',
    subtitle: '',
    features: [
      'Discounted recurring pickups',
      'Medicine delivery reminders',
      'Secure sealed-package handover',
    ],
  ),
  _HealthPlan(
    id: 'priority',
    title: 'Health+ Priority',
    subtitle: 'Priority matching',
    features: [
      'Priority Circum Rider matching',
      'Faster pickup target',
      'Recurring prescription reminders',
    ],
  ),
  _HealthPlan(
    id: 'family',
    title: 'Health+ Family',
    subtitle: 'Family support',
    features: [
      'Support for elderly relatives',
      'Shared pickup notes',
      'Repeat medicine reminders',
    ],
  ),
];

String _healthPlanTitle(String id) {
  for (final plan in _healthPlans) {
    if (plan.id == id) return plan.title;
  }
  return id;
}

class _HealthPlan {
  final String id;
  final String title;
  final String subtitle;
  final List<String> features;

  const _HealthPlan({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.features,
  });
}

class _HealthNotesStep extends StatelessWidget {
  final TextEditingController notes;
  final bool consent;
  final bool savePaymentMethod;
  final ValueChanged<bool> onConsent;
  final ValueChanged<bool> onSavePayment;
  final VoidCallback onContinue;

  const _HealthNotesStep({
    required this.notes,
    required this.consent,
    required this.savePaymentMethod,
    required this.onConsent,
    required this.onSavePayment,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return _HealthStepCard(
      children: [
        _HealthInput(
          controller: notes,
          label: 'Notes for the Circum Rider (optional)',
          maxLines: 4,
        ),
        _HealthToggleRow(
          selected: consent,
          title:
              'I confirm the prescription is valid and ready or will be ready for pharmacy collection.',
          onTap: () => onConsent(!consent),
        ),
        _HealthToggleRow(
          selected: savePaymentMethod,
          title: 'Save payment method for future Health+ pickups.',
          onTap: () => onSavePayment(!savePaymentMethod),
        ),
        const _HealthDisclaimer(),
        _HealthPrimaryButton(label: 'Continue to Review', onTap: onContinue),
      ],
    );
  }
}

class _HealthReviewStep extends StatelessWidget {
  final HealthPlusPriceBreakdown quote;
  final HealthPlusFrequency frequency;
  final String plan;
  final String pharmacy;
  final String delivery;
  final String preferredTime;
  final VoidCallback onContinue;

  const _HealthReviewStep({
    required this.quote,
    required this.frequency,
    required this.plan,
    required this.pharmacy,
    required this.delivery,
    required this.preferredTime,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return _HealthStepCard(
      children: [
        _HealthReviewRow(label: 'Pharmacy', value: pharmacy),
        _HealthReviewRow(label: 'Delivery', value: delivery),
        _HealthReviewRow(label: 'Preferred time', value: preferredTime),
        _HealthReviewRow(label: 'Frequency', value: frequency.label),
        _HealthReviewRow(label: 'Plan', value: _healthPlanTitle(plan)),
        const _HealthDivider(),
        _HealthReviewRow(
            label: 'Base fare', value: _money(quote.delivery.baseFare)),
        _HealthReviewRow(
          label: 'Mileage fare',
          value: _money(quote.delivery.distanceFare),
        ),
        _HealthReviewRow(
          label: 'Medication surcharge',
          value: _money(quote.delivery.weightSurcharge),
        ),
        _HealthReviewRow(label: 'Health+ fee', value: _money(quote.serviceFee)),
        if (quote.priorityFee > 0)
          _HealthReviewRow(
              label: 'Priority fee', value: _money(quote.priorityFee)),
        if (quote.familySupportFee > 0)
          _HealthReviewRow(
            label: 'Family support',
            value: _money(quote.familySupportFee),
          ),
        if (quote.recurringDiscount > 0)
          _HealthReviewRow(
            label: 'Recurring discount',
            value: '-${_money(quote.recurringDiscount)}',
          ),
        if (quote.minimumAdjustment > 0)
          _HealthReviewRow(
            label: 'Health+ minimum adjustment',
            value: _money(quote.minimumAdjustment),
          ),
        const _HealthDivider(),
        _HealthTotalRow(total: quote.total),
        _HealthPrimaryButton(label: 'Continue to Checkout', onTap: onContinue),
      ],
    );
  }
}

class _HealthCheckoutStep extends StatelessWidget {
  final HealthPlusPriceBreakdown quote;
  final bool submitting;
  final bool useRoth;
  final double rothBalance;
  final bool recurring;
  final ValueChanged<bool> onUseRoth;
  final VoidCallback onCheckout;

  const _HealthCheckoutStep({
    required this.quote,
    required this.submitting,
    required this.useRoth,
    required this.rothBalance,
    required this.recurring,
    required this.onUseRoth,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return _HealthStepCard(
      children: [
        const _HealthSecureNote(),
        _HealthTotalRow(total: quote.total),
        _HealthToggleRow(
          selected: useRoth,
          title: recurring
              ? 'Use Roth on the first Health+ subscription payment. Available: ${_money(rothBalance)}.'
              : 'Use Roth for this Health+ pickup. Available: ${_money(rothBalance)}.',
          onTap: () => onUseRoth(!useRoth),
        ),
        if (recurring)
          const Text(
            'Future subscription renewals continue securely by card unless Roth subscription billing is enabled later.',
            style: TextStyle(
              color: _HealthTokens.muted,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        _HealthPrimaryButton(
          label: submitting
              ? 'Creating Health+...'
              : 'Pay ${_money(quote.total)} securely',
          icon: Icons.lock_outline_rounded,
          loading: submitting,
          onTap: onCheckout,
        ),
      ],
    );
  }
}

class _HealthConfirmedStep extends StatelessWidget {
  final Map<String, dynamic>? pickup;
  final VoidCallback onStatus;
  final VoidCallback onCheckout;

  const _HealthConfirmedStep({
    required this.pickup,
    required this.onStatus,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return _HealthStepCard(
      children: [
        _HealthTimeline(
          current: PickupStatusValue.fromValue(
            '${pickup?['status'] ?? PickupStatus.scheduled.value}',
          ),
        ),
        const Text(
          'Every Health+ step is saved. Nothing is lost.',
          style: TextStyle(
            color: _HealthTokens.muted,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
        _HealthPrimaryButton(label: 'Back to Status', onTap: onStatus),
        _HealthSecondaryButton(
            label: 'Open secure checkout', onTap: onCheckout),
      ],
    );
  }
}

class _HealthStepCard extends StatelessWidget {
  final List<Widget> children;

  const _HealthStepCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return _HealthGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children) ...[
            child,
            if (child != children.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _HealthInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final IconData? prefixIcon;
  final ValueChanged<String>? onChanged;

  const _HealthInput({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.prefixIcon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: _HealthTokens.muted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, color: _HealthTokens.health),
        filled: true,
        fillColor: _HealthTokens.input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _HealthTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _HealthTokens.health),
        ),
      ),
    );
  }
}

class _HealthDateTimeInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _HealthDateTimeInput({
    required this.controller,
    required this.label,
  });

  Future<void> _pick(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final initialDate = now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'Select pickup date',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _HealthTokens.health,
            surface: _HealthTokens.bg,
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (!context.mounted || date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      helpText: 'Select pickup time',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _HealthTokens.health,
            surface: _HealthTokens.bg,
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (time == null) return;

    controller.text = _formatHealthPickupDateTime(date, time);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label. ${controller.text}',
      hint: 'Opens date and time selectors',
      child: TextField(
        controller: controller,
        readOnly: true,
        onTap: () => _pick(context),
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          helperText: 'Choose day, month, year and time.',
          helperStyle: const TextStyle(
            color: _HealthTokens.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          labelStyle: const TextStyle(
            color: _HealthTokens.muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
          prefixIcon: const Icon(
            Icons.event_available_outlined,
            color: _HealthTokens.health,
          ),
          suffixIcon: const Icon(
            Icons.expand_more_rounded,
            color: _HealthTokens.muted,
          ),
          filled: true,
          fillColor: _HealthTokens.input,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _HealthTokens.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _HealthTokens.health),
          ),
        ),
      ),
    );
  }
}

class _HealthSuggestionRow extends StatelessWidget {
  final Suggestion suggestion;
  final VoidCallback onTap;

  const _HealthSuggestionRow({
    required this.suggestion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.place_outlined, color: _HealthTokens.health),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.mainText.isEmpty
                        ? suggestion.description
                        : suggestion.mainText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (suggestion.subText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      suggestion.subText,
                      style: const TextStyle(color: _HealthTokens.muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _HealthChoiceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected
              ? _HealthTokens.health.withValues(alpha: .12)
              : Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? _HealthTokens.health
                : Colors.white.withValues(alpha: .10),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _HealthTokens.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthPlanCard extends StatelessWidget {
  final _HealthPlan plan;
  final HealthPlusPriceBreakdown quote;
  final bool selected;
  final VoidCallback onTap;

  const _HealthPlanCard({
    required this.plan,
    required this.quote,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final extra = quote.priorityFee + quote.familySupportFee;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? _HealthTokens.health.withValues(alpha: .10)
              : Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? _HealthTokens.health
                : Colors.white.withValues(alpha: .10),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? _HealthTokens.health : _HealthTokens.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (plan.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      plan.subtitle,
                      style: const TextStyle(
                        color: _HealthTokens.muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ...plan.features.map(
                    (feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: _HealthTokens.health,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              feature,
                              style: const TextStyle(
                                color: _HealthTokens.muted,
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              extra == 0 ? 'Included' : '+${_money(extra)}',
              style: const TextStyle(
                color: _HealthTokens.health,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthToggleRow extends StatelessWidget {
  final bool selected;
  final String title;
  final VoidCallback onTap;

  const _HealthToggleRow({
    required this.selected,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              color: selected ? _HealthTokens.health : _HealthTokens.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFD7DEE4),
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthDisclaimer extends StatelessWidget {
  const _HealthDisclaimer();

  @override
  Widget build(BuildContext context) {
    const items = [
      'Health+ is a pickup and delivery service only.',
      'Circum does not prescribe medication.',
      'Users are responsible for valid prescriptions that are ready for collection.',
      'Drivers collect and deliver sealed pharmacy packages only.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Safety and compliance',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              '- $item',
              style: const TextStyle(
                color: _HealthTokens.muted,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HealthSecureNote extends StatelessWidget {
  const _HealthSecureNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: _HealthTokens.health),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "You'll be taken to secure Stripe Checkout, then brought straight back here.",
              style: TextStyle(
                color: Color(0xFFD7DEE4),
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthReviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _HealthReviewRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _HealthTokens.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthTotalRow extends StatelessWidget {
  final double total;

  const _HealthTotalRow({required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Total',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          _money(total),
          style: const TextStyle(
            color: _HealthTokens.health,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _HealthTimeline extends StatelessWidget {
  final PickupStatus current;

  const _HealthTimeline({required this.current});

  @override
  Widget build(BuildContext context) {
    const stages = [
      PickupStatus.scheduled,
      PickupStatus.assigned,
      PickupStatus.awaitingPharmacyCollection,
      PickupStatus.collected,
      PickupStatus.outForDelivery,
      PickupStatus.delivered,
    ];
    final currentIndex = stages.indexOf(current).clamp(0, stages.length - 1);
    return Column(
      children: [
        for (var i = 0; i < stages.length; i++)
          _HealthTimelineRow(
            label: _pickupLabel(stages[i]),
            done: i < currentIndex,
            current: i == currentIndex,
            showLine: i < stages.length - 1,
          ),
      ],
    );
  }
}

class _HealthTimelineRow extends StatelessWidget {
  final String label;
  final bool done;
  final bool current;
  final bool showLine;

  const _HealthTimelineRow({
    required this.label,
    required this.done,
    required this.current,
    required this.showLine,
  });

  @override
  Widget build(BuildContext context) {
    final active = done || current;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? _HealthTokens.health : _HealthTokens.border,
                boxShadow: current
                    ? [
                        BoxShadow(
                          color: _HealthTokens.health.withValues(alpha: .34),
                          blurRadius: 14,
                        ),
                      ]
                    : null,
              ),
            ),
            if (showLine)
              Container(
                width: 2,
                height: 24,
                color: active ? _HealthTokens.health : _HealthTokens.border,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : _HealthTokens.muted,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HealthPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;

  const _HealthPrimaryButton({
    required this.label,
    required this.onTap,
    this.icon = Icons.arrow_forward_rounded,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: loading ? null : onTap,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        backgroundColor: _HealthTokens.health,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _HealthSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _HealthSecondaryButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        foregroundColor: Colors.white,
        side: const BorderSide(color: _HealthTokens.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label),
    );
  }
}

class _HealthMiniButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _HealthMiniButton(this.label, this.onTap, {this.danger = false});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? _HealthTokens.danger : Colors.white,
        side: BorderSide(
          color: danger
              ? _HealthTokens.danger.withValues(alpha: .45)
              : _HealthTokens.border,
        ),
      ),
      child: Text(label),
    );
  }
}

class _HealthInlineState extends StatelessWidget {
  final String message;

  const _HealthInlineState(this.message);

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(
        color: _HealthTokens.muted,
        height: 1.4,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _HealthNotice extends StatelessWidget {
  final String message;

  const _HealthNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return _HealthGlassCard(
      child: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          height: 1.4,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _HealthGlassCard extends StatelessWidget {
  final Widget child;

  const _HealthGlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
        boxShadow: [
          BoxShadow(
            color: _HealthTokens.health.withValues(alpha: .08),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HealthIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HealthIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
        ),
        child: Icon(icon, color: Colors.white, size: 19),
      ),
    );
  }
}

class _HealthEyebrow extends StatelessWidget {
  final String text;

  const _HealthEyebrow(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _HealthTokens.health,
        fontSize: 11,
        letterSpacing: 1,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _HealthBadge extends StatelessWidget {
  final String label;

  const _HealthBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _HealthTokens.health.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _HealthTokens.health.withValues(alpha: .35)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _HealthTokens.health,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _HealthDivider extends StatelessWidget {
  const _HealthDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: _HealthTokens.border);
  }
}

class _HealthBackdrop extends StatelessWidget {
  const _HealthBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-.8, -1),
          radius: 1.2,
          colors: [
            Color(0x2A2FAE8C),
            _HealthTokens.bg,
          ],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _HealthTokens {
  static const bg = Color(0xFF07090F);
  static const input = Color(0xFF1F292E);
  static const border = Color(0x24FFFFFF);
  static const health = Color(0xFF2FAE8C);
  static const muted = Color(0x99FFFFFF);
  static const danger = Color(0xFFFF452B);
}

String _defaultHealthPickupDateTime() {
  return _formatHealthPickupDateTime(
    DateTime.now().add(const Duration(days: 1)),
    const TimeOfDay(hour: 10, minute: 0),
  );
}

String _formatHealthPickupDateTime(DateTime date, TimeOfDay time) {
  final weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final weekday = weekdays[date.weekday - 1];
  final month = months[date.month - 1];
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$weekday, ${date.day} $month ${date.year}, $hour:$minute';
}

String _money(double value) => '£${value.toStringAsFixed(2)}';

String _pickupLabel(PickupStatus status) {
  return switch (status) {
    PickupStatus.scheduled => 'Scheduled',
    PickupStatus.assigned => 'Assigned to a Circum Rider',
    PickupStatus.awaitingPharmacyCollection => 'Awaiting pharmacy collection',
    PickupStatus.collected => 'Collected',
    PickupStatus.outForDelivery => 'Out for delivery',
    PickupStatus.delivered => 'Delivered',
    PickupStatus.failed => 'Failed',
    PickupStatus.cancelled => 'Cancelled',
  };
}
