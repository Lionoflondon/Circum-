import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../business/business_journey_context.dart';
import '../../platform/address_engine.dart';
import '../../send_package/models/suggestions.m.dart';
import '../../send_package/repo/place_api.dart';
import '../../sender_mobile/sender_finance.dart';
import '../../sender_mobile/sender_accessibility.dart';
import '../../sender_mobile/sender_wallet.dart';
import '../../sender_mobile/design_system/sender_design_system.dart';
import '../health_plus_pricing.dart';
import '../models/pickup_status.dart';
import '../models/recurring_pickup_schedule.dart';

class HealthPlusView extends HealthStatusView {
  const HealthPlusView({super.key});
}

class HealthStatusView extends StatefulWidget {
  const HealthStatusView({super.key});

  @override
  State<HealthStatusView> createState() => _HealthStatusViewState();
}

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

class _HealthStatusViewState extends State<HealthStatusView> {
  final _fullName = TextEditingController();
  final _careName = TextEditingController();
  final _careRelationship = TextEditingController();
  final _carePhone = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _pharmacyAddress = TextEditingController();
  final _deliveryAddress = TextEditingController();
  final _notes = TextEditingController();
  final _preferredDay = TextEditingController(text: 'Tuesday');
  final _preferredTime = TextEditingController(text: '10:00 AM');
  final _customSchedule = TextEditingController();
  final _pharmacySearch = TextEditingController();
  final _deliverySearch = TextEditingController();

  late final PlaceApiProvider _pharmacyLookup;
  late final PlaceApiProvider _deliveryLookup;
  var _step = _HealthStep.status;
  var _forSomeoneElse = false;
  var _frequency = HealthPlusFrequency.monthly;
  var _subscriptionPlan = HealthPlusPricing.supportedSubscriptionPlans.first;
  var _consent = false;
  var _applyRoth = false;
  var _submitting = false;
  var _financeLoading = false;
  var _searchingPharmacy = false;
  var _searchingDelivery = false;
  String? _profileId;
  String? _scheduleId;
  String? _message;
  String? _financeMessage;
  String? _checkoutUrl;
  String? _pharmacySearchError;
  String? _deliverySearchError;
  Map<String, dynamic>? _latestPickup;
  SenderPaymentProfile _paymentProfile = SenderPaymentProfile.empty();
  SenderWalletData? _wallet;
  SenderPaymentProfileOption? _selectedPaymentOption;
  List<Suggestion> _pharmacySuggestions = const [];
  List<Suggestion> _deliverySuggestions = const [];
  final List<Map<String, dynamic>> _payments = [];
  late final SenderWalletRepository _walletRepository;

  HealthPlusPriceBreakdown get _quote {
    return HealthPlusPricing.calculate(
      recurring: _frequency != HealthPlusFrequency.oneOff,
      subscriptionPlan: _subscriptionPlan,
    );
  }

  String get _paymentMethodLabel {
    if (_applyRoth && _wallet != null && _wallet!.balance > 0) {
      final selected = _selectedPaymentOption?.title;
      if (selected == null || selected == 'Roth') return 'Roth';
      return 'Roth + $selected';
    }
    return _selectedPaymentOption?.title ?? 'Default payment method';
  }

  String get _deliveryLabel {
    final text = _deliveryAddress.text.toLowerCase();
    if (text.contains('care home')) return 'Care Home';
    if (text.contains('parent')) return 'Parents';
    if (text.contains('work') || text.contains('office')) return 'Work';
    if (text.contains('home')) return 'Home';
    return 'Recent';
  }

  Map<String, dynamic> get _schedulePreference => {
        'frequency': _frequency.value,
        'preferredPickupDay': _preferredDay.text.trim(),
        'preferredPickupTime': _preferredTime.text.trim(),
        'customSchedule': _customSchedule.text.trim(),
      };

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _fullName.text = user?.displayName ?? '';
    _email.text = user?.email ?? '';
    _phone.text = user?.phoneNumber ?? '';
    _pharmacyLookup = PlaceApiProvider(Object());
    _deliveryLookup = PlaceApiProvider(Object());
    _walletRepository = FirebaseSenderWalletRepository();
    _loadFinance();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _careName.dispose();
    _careRelationship.dispose();
    _carePhone.dispose();
    _phone.dispose();
    _email.dispose();
    _pharmacyAddress.dispose();
    _deliveryAddress.dispose();
    _notes.dispose();
    _preferredDay.dispose();
    _preferredTime.dispose();
    _customSchedule.dispose();
    _pharmacySearch.dispose();
    _deliverySearch.dispose();
    super.dispose();
  }

  Future<void> _loadFinance() async {
    final platform = Theme.of(context).platform;
    setState(() {
      _financeLoading = true;
      _financeMessage = null;
    });
    try {
      final results = await Future.wait([
        _walletRepository.initialise(),
        _walletRepository.paymentMethods(),
      ]);
      if (!mounted) return;
      final wallet = results[0] as SenderWalletData;
      final profile = results[1] as SenderPaymentProfile;
      final options = senderOrderedPaymentOptions(
        profile,
        platform: platform,
        includeAddMethod: false,
      );
      setState(() {
        _wallet = wallet;
        _paymentProfile = profile;
        _selectedPaymentOption = options.isEmpty ? null : options.first;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _financeMessage =
            'Pay With could not load. You can still prepare secure checkout.';
      });
    } finally {
      if (mounted) setState(() => _financeLoading = false);
    }
  }

  void _goTo(_HealthStep step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
  }

  void _back() {
    final index = _HealthStep.values.indexOf(_step);
    if (index <= 0) {
      Navigator.of(context).maybePop();
      return;
    }
    _goTo(_HealthStep.values[index - 1]);
  }

  Future<void> _searchAddress({
    required bool pharmacy,
    required String query,
  }) async {
    setState(() {
      if (pharmacy) {
        _searchingPharmacy = true;
        _pharmacySearchError = null;
      } else {
        _searchingDelivery = true;
        _deliverySearchError = null;
      }
    });
    try {
      final suggestions = await (pharmacy ? _pharmacyLookup : _deliveryLookup)
          .fetchSuggestions(query, 'en_GB');
      if (!mounted) return;
      setState(() {
        if (pharmacy) {
          _pharmacySuggestions = suggestions;
        } else {
          _deliverySuggestions = suggestions;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (pharmacy) {
          _pharmacySearchError =
              'Address search is unavailable. You can type it manually.';
          _pharmacySuggestions = const [];
        } else {
          _deliverySearchError =
              'Address search is unavailable. You can type it manually.';
          _deliverySuggestions = const [];
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          if (pharmacy) {
            _searchingPharmacy = false;
          } else {
            _searchingDelivery = false;
          }
        });
      }
    }
  }

  void _selectSuggestion({required bool pharmacy, required Suggestion item}) {
    final display = item.description.isNotEmpty
        ? item.description
        : [item.mainText, item.subText]
            .where((part) => part.trim().isNotEmpty)
            .join(', ');
    setState(() {
      if (pharmacy) {
        _pharmacyAddress.text = display;
        _pharmacySearch.text = display;
        _pharmacySuggestions = const [];
      } else {
        _deliveryAddress.text = display;
        _deliverySearch.text = display;
        _deliverySuggestions = const [];
      }
    });
    _goTo(pharmacy ? _HealthStep.delivery : _HealthStep.frequency);
  }

  bool get _detailsReady {
    if (_fullName.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      return false;
    }
    if (!_forSomeoneElse) return true;
    return _careName.text.trim().isNotEmpty &&
        _careRelationship.text.trim().isNotEmpty &&
        _carePhone.text.trim().isNotEmpty;
  }

  bool get _pharmacyReady => _pharmacyAddress.text.trim().isNotEmpty;

  bool get _deliveryReady => _deliveryAddress.text.trim().isNotEmpty;

  bool get _notesReady => _consent;

  Future<void> _bookHealthPlus() async {
    if (_submitting) return;
    if (!_consent) {
      setState(() {
        _message =
            'Please confirm the prescription is valid and ready for collection.';
      });
      return;
    }

    final confirmed = await confirmSenderPaymentIfRequired(
      context,
      paymentMethod: _paymentMethodLabel,
      amount: HealthPlusPricing.formatGbp(_quote.total),
    );
    if (!confirmed || !mounted) return;

    final quote = _quote;
    final now = DateTime.now();
    final id = FirebaseAuth.instance.currentUser?.uid ??
        'HP-${now.millisecondsSinceEpoch.toString().substring(6)}';
    final pickupId =
        'HPP-${now.millisecondsSinceEpoch.toString().substring(6)}';
    final scheduleId = _frequency == HealthPlusFrequency.oneOff
        ? null
        : 'HPS-${now.millisecondsSinceEpoch.toString().substring(6)}';

    setState(() {
      _submitting = true;
      _message = 'Creating your Health+ pickup and secure checkout...';
    });

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final pharmacyAddress = AddressEngine.normalize(
        manualAddress: _pharmacyAddress.text.trim(),
      );
      final deliveryAddress = AddressEngine.normalize(
        manualAddress: _deliveryAddress.text.trim(),
      );
      final pharmacyDisplay = AddressEngine.display(
        pharmacyAddress,
        fallback: _pharmacyAddress.text.trim(),
      );
      final deliveryDisplay = AddressEngine.display(
        deliveryAddress,
        fallback: _deliveryAddress.text.trim(),
      );
      final paymentMethod = _paymentMethodLabel;
      final schedulePreference = _schedulePreference;
      final planDefinition = HealthPlusPricing.planFor(_subscriptionPlan);
      final business = BusinessJourneyScope.maybeOf(context);
      final businessFields = business?.toMap() ?? const <String, dynamic>{};

      final profile = {
        ...businessFields,
        'id': id,
        'fullName': _fullName.text.trim(),
        'phoneNumber': _phone.text.trim(),
        'email': _email.text.trim(),
        'careRecipientType': _forSomeoneElse ? 'someone_else' : 'me',
        'careRecipientName': _forSomeoneElse ? _careName.text.trim() : null,
        'careRecipientRelationship':
            _forSomeoneElse ? _careRelationship.text.trim() : null,
        'careRecipientPhone': _forSomeoneElse ? _carePhone.text.trim() : null,
        'pharmacyAddress': pharmacyDisplay,
        'deliveryAddress': deliveryDisplay,
        'pharmacyAddressData': pharmacyAddress,
        'deliveryAddressData': deliveryAddress,
        'recentPharmacies': FieldValue.arrayUnion([
          {
            'label': pharmacyDisplay,
            'address': pharmacyAddress,
            'lastUsedAt': DateTime.now().toUtc().toIso8601String(),
          }
        ]),
        'preferredDeliveryAddresses': FieldValue.arrayUnion([
          {
            'label': _deliveryLabel,
            'address': deliveryAddress,
            'lastUsedAt': DateTime.now().toUtc().toIso8601String(),
          }
        ]),
        'preferredSchedule': schedulePreference,
        'subscriptionPlan': _subscriptionPlan,
        'healthPlusPlan': _subscriptionPlan,
        'planType': _subscriptionPlan,
        'monthlyPrice': planDefinition.monthlyPrice,
        'includedDeliveries': planDefinition.includedDeliveries,
        'overageRate': planDefinition.overageRate,
        'notes': _notes.text.trim(),
        'consentConfirmed': _consent,
        'source': 'circum-mobile',
        'platform': Theme.of(context).platform.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final pickup = {
        ...businessFields,
        'id': pickupId,
        'profileId': id,
        'scheduleId': scheduleId,
        'fullName': _fullName.text.trim(),
        'phoneNumber': _phone.text.trim(),
        'careRecipientType': _forSomeoneElse ? 'someone_else' : 'me',
        'careRecipientName': _forSomeoneElse ? _careName.text.trim() : null,
        'careRecipientRelationship':
            _forSomeoneElse ? _careRelationship.text.trim() : null,
        'careRecipientPhone': _forSomeoneElse ? _carePhone.text.trim() : null,
        'pharmacyAddress': pharmacyDisplay,
        'deliveryAddress': deliveryDisplay,
        'pharmacyAddressData': pharmacyAddress,
        'deliveryAddressData': deliveryAddress,
        'notes': _notes.text.trim(),
        'preferredPickupDay': _preferredDay.text.trim(),
        'preferredPickupTime': _preferredTime.text.trim(),
        'preferredSchedule': schedulePreference,
        'frequency': _frequency.value,
        'subscriptionPlan': _subscriptionPlan,
        'healthPlusPlan': _subscriptionPlan,
        'planType': _subscriptionPlan,
        'monthlyPrice': planDefinition.monthlyPrice,
        'includedDeliveries': planDefinition.includedDeliveries,
        'overageRate': planDefinition.overageRate,
        'status': PickupStatus.scheduled.value,
        'price': quote.total,
        'currency': 'GBP',
        'pricingBreakdown': quote.toJson(),
        'paymentMethodLabel': paymentMethod,
        'applyRoth': _applyRoth,
        'rothBalanceAvailable': _wallet?.balance,
        'type': 'health_plus_prescription_pickup',
        'source': 'circum-mobile',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      batch.set(db.collection('healthPlusProfiles').doc(id), profile,
          SetOptions(merge: true));
      batch.set(db.collection('prescriptionPickups').doc(pickupId), pickup,
          SetOptions(merge: true));

      if (scheduleId != null) {
        batch.set(db.collection('recurringPickupSchedules').doc(scheduleId), {
          ...businessFields,
          'id': scheduleId,
          'profileId': id,
          'frequency': _frequency.value,
          'subscriptionPlan': _subscriptionPlan,
          'healthPlusPlan': _subscriptionPlan,
          'planType': _subscriptionPlan,
          'monthlyPrice': planDefinition.monthlyPrice,
          'includedDeliveries': planDefinition.includedDeliveries,
          'overageRate': planDefinition.overageRate,
          'preferredDay': _preferredDay.text.trim(),
          'preferredTime': _preferredTime.text.trim(),
          'preferredDayTime':
              '${_preferredDay.text.trim()} ${_preferredTime.text.trim()}',
          'customSchedule': _customSchedule.text.trim(),
          'paused': false,
          'nextPickupAt': _preferredTime.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      batch.set(db.collection('healthPlusPayments').doc(pickupId), {
        ...businessFields,
        'id': pickupId,
        'profileId': id,
        'pickupId': pickupId,
        'subscriptionPlan': _subscriptionPlan,
        'amount': quote.total,
        'currency': 'GBP',
        'status': 'pending_secure_checkout',
        'paymentMethodLabel': paymentMethod,
        'paymentProfileSource': 'sender_payment_profile',
        'applyRoth': _applyRoth,
        'rothBalanceAvailable': _wallet?.balance,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(db.collection('healthPlusNotifications').doc(), {
        ...businessFields,
        'profileId': id,
        'pickupId': pickupId,
        'type': 'pickup_scheduled',
        'title': 'Health+ pickup scheduled',
        'body': 'Your prescription pickup has been scheduled.',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _logUsageEvent(
        batch: batch,
        db: db,
        type: 'pickup_created',
        profileId: id,
        pickupId: pickupId,
        scheduleId: scheduleId,
        status: PickupStatus.scheduled.value,
        amount: quote.total,
      );

      await batch.commit();
      final checkoutUrl = await _createCheckoutSession(
        pickupId: pickupId,
        profileId: id,
      );

      if (!mounted) return;
      setState(() {
        _profileId = id;
        _scheduleId = scheduleId;
        _latestPickup = pickup;
        _checkoutUrl = checkoutUrl;
        _payments.insert(0, {
          'pickupId': pickupId,
          'amount': quote.total,
          'status': checkoutUrl == null
              ? 'pending_secure_checkout'
              : 'checkout_created',
        });
        _message = checkoutUrl == null
            ? 'Your Health+ pickup has been scheduled. Secure checkout needs configuration.'
            : 'Your Health+ pickup has been scheduled.';
        _step = _HealthStep.confirmed;
      });

      if (checkoutUrl != null) {
        await launchUrl(Uri.parse(checkoutUrl),
            mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message =
            'Health+ could not be saved. Check your payment setup and try again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String?> _createCheckoutSession({
    required String pickupId,
    required String profileId,
  }) async {
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) {
        setState(() {
          _message = 'Please sign in again to continue Health+ checkout.';
        });
        return null;
      }
      final response = await http.post(
        Uri.parse(
          'https://us-central1-circum-2797c.cloudfunctions.net/createHealthPlusCheckoutSession',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'bookingId': pickupId,
          'profileId': profileId,
          'email': _email.text.trim(),
          'frequency': _frequency.value,
          'subscriptionPlan': _subscriptionPlan,
          'preferredSchedule': _schedulePreference,
          'paymentMethodLabel': _paymentMethodLabel,
          'paymentProfileSource': 'sender_payment_profile',
          'applyRoth': _applyRoth,
          'rothBalanceAvailable': _wallet?.balance,
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
    await FirebaseFirestore.instance
        .collection('recurringPickupSchedules')
        .doc(_scheduleId)
        .set({'paused': true, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
    await _writeUsageEvent(
      type: 'recurring_pickup_paused',
      scheduleId: _scheduleId,
      status: 'paused',
    );
    setState(() => _message = 'Recurring Health+ pickup paused.');
  }

  Future<void> _cancelPickup() async {
    final pickupId = _latestPickup?['id']?.toString();
    if (pickupId == null) return;
    await FirebaseFirestore.instance
        .collection('prescriptionPickups')
        .doc(pickupId)
        .set({
      'status': PickupStatus.cancelled.value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _writeUsageEvent(
      type: 'pickup_cancelled',
      pickupId: pickupId,
      status: PickupStatus.cancelled.value,
    );
    setState(() {
      _latestPickup = {
        ...?_latestPickup,
        'status': PickupStatus.cancelled.value
      };
      _message = 'Next Health+ pickup cancelled.';
    });
  }

  void _useRecentPharmacy() {
    final recent = '${_latestPickup?['pharmacyAddress'] ?? ''}'.trim();
    if (recent.isEmpty) return;
    setState(() {
      _pharmacyAddress.text = recent;
      _pharmacySearch.text = recent;
    });
  }

  void _selectDeliveryLabel(String label) {
    final recent = '${_latestPickup?['deliveryAddress'] ?? ''}'.trim();
    if (label == 'Recent' && recent.isNotEmpty) {
      setState(() {
        _deliveryAddress.text = recent;
        _deliverySearch.text = recent;
      });
      return;
    }
    setState(() {
      _deliverySearch.text = label;
      _deliveryAddress.text = label;
    });
  }

  // Admin status overrides belong in Admin.

  void _logUsageEvent({
    required WriteBatch batch,
    required FirebaseFirestore db,
    required String type,
    String? profileId,
    String? pickupId,
    String? scheduleId,
    String? status,
    double? amount,
  }) {
    batch.set(db.collection('healthPlusUsageEvents').doc(), {
      'type': type,
      'profileId': profileId,
      'pickupId': pickupId,
      'scheduleId': scheduleId,
      'status': status,
      'amount': amount,
      'currency': amount == null ? null : 'GBP',
      'source': 'circum-mobile',
      'platform': Theme.of(context).platform.name,
      'userId': FirebaseAuth.instance.currentUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _writeUsageEvent({
    required String type,
    String? pickupId,
    String? scheduleId,
    String? status,
  }) async {
    await FirebaseFirestore.instance.collection('healthPlusUsageEvents').add({
      'type': type,
      'profileId': _profileId,
      'pickupId': pickupId ?? _latestPickup?['id']?.toString(),
      'scheduleId': scheduleId ?? _scheduleId,
      'status': status,
      'source': 'circum-mobile',
      'platform': Theme.of(context).platform.name,
      'userId': FirebaseAuth.instance.currentUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _HealthTokens.navy,
      body: SafeArea(
        child: Stack(
          children: [
            const _HealthBackdrop(),
            Column(
              children: [
                _HealthTopBar(
                  step: _step,
                  onBack: _back,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: [
                      _HealthHeader(step: _step),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _stepBody(),
                      ),
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

  Widget _stepBody() {
    return KeyedSubtree(
      key: ValueKey(_step),
      child: switch (_step) {
        _HealthStep.status => _statusStep(),
        _HealthStep.details => _detailsStep(),
        _HealthStep.pharmacy => _addressStep(pharmacy: true),
        _HealthStep.delivery => _addressStep(pharmacy: false),
        _HealthStep.frequency => _frequencyStep(),
        _HealthStep.plan => _planStep(),
        _HealthStep.notes => _notesStep(),
        _HealthStep.review => _reviewStep(),
        _HealthStep.checkout => _checkoutStep(),
        _HealthStep.confirmed => _confirmedStep(),
      },
    );
  }

  Widget _statusStep() {
    return Column(
      children: [
        _StatusCard(
          pickup: _latestPickup,
          payments: _payments,
          onPauseSchedule: _pauseSchedule,
          onCancelPickup: _cancelPickup,
          onUpdatePayment: _openCheckout,
        ),
        const SizedBox(height: 18),
        _PrimaryHealthButton(
          label: 'Book a new pickup',
          icon: Icons.medication_liquid_outlined,
          onTap: () => _goTo(_HealthStep.details),
        ),
        const SizedBox(height: 12),
        const _TrustStrip(),
      ],
    );
  }

  Widget _detailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CareChoice(
          selected: !_forSomeoneElse,
          title: 'Me',
          onTap: () => setState(() => _forSomeoneElse = false),
        ),
        _CareChoice(
          selected: _forSomeoneElse,
          title: 'Someone else',
          onTap: () => setState(() => _forSomeoneElse = true),
        ),
        const SizedBox(height: 10),
        _HealthInput(controller: _fullName, label: 'Full name'),
        _HealthInput(controller: _phone, label: 'Phone'),
        _HealthInput(controller: _email, label: 'Email'),
        if (_forSomeoneElse) ...[
          _HealthInput(controller: _careName, label: 'Name'),
          _HealthInput(controller: _careRelationship, label: 'Relationship'),
          _HealthInput(controller: _carePhone, label: 'Phone'),
        ],
        const SizedBox(height: 18),
        _PrimaryHealthButton(
          label: 'Continue',
          enabled: _detailsReady,
          onTap: () => _goTo(_HealthStep.pharmacy),
        ),
      ],
    );
  }

  Widget _addressStep({required bool pharmacy}) {
    final controller = pharmacy ? _pharmacySearch : _deliverySearch;
    final manual = pharmacy ? _pharmacyAddress : _deliveryAddress;
    final suggestions = pharmacy ? _pharmacySuggestions : _deliverySuggestions;
    final searching = pharmacy ? _searchingPharmacy : _searchingDelivery;
    final error = pharmacy ? _pharmacySearchError : _deliverySearchError;
    final ready = pharmacy ? _pharmacyReady : _deliveryReady;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SearchField(
          controller: controller,
          hint: pharmacy
              ? 'Search pharmacy or address'
              : 'Search delivery address',
          loading: searching,
          onChanged: (value) {
            manual.text = value;
            if (value.trim().length >= 3) {
              _searchAddress(pharmacy: pharmacy, query: value);
            } else {
              setState(() {
                if (pharmacy) {
                  _pharmacySuggestions = const [];
                } else {
                  _deliverySuggestions = const [];
                }
              });
            }
          },
        ),
        if (error != null) _HealthNote(error, warning: true),
        if (pharmacy && '${_latestPickup?['pharmacyAddress'] ?? ''}'.isNotEmpty)
          _RecentPharmacyCard(
            label: '${_latestPickup?['pharmacyAddress']}',
            onUseAgain: _useRecentPharmacy,
          ),
        if (!pharmacy) const _DeliveryAddressChoices(),
        if (!pharmacy)
          _DeliveryAddressChoiceRow(onSelected: _selectDeliveryLabel),
        ...suggestions.map(
          (item) => _SuggestionRow(
            item: item,
            onTap: () => _selectSuggestion(pharmacy: pharmacy, item: item),
          ),
        ),
        _HealthInput(
          controller: manual,
          label: pharmacy ? 'Selected pharmacy' : 'Selected delivery address',
          maxLines: 2,
        ),
        const SizedBox(height: 18),
        _PrimaryHealthButton(
          label: pharmacy ? 'Choose Pharmacy' : 'Continue to Delivery',
          enabled: ready,
          onTap: () =>
              _goTo(pharmacy ? _HealthStep.delivery : _HealthStep.frequency),
        ),
      ],
    );
  }

  Widget _frequencyStep() {
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: HealthPlusFrequency.values.map((frequency) {
            return _FrequencyCard(
              selected: _frequency == frequency,
              title: frequency.label,
              subtitle: _frequencySubtitle(frequency),
              onTap: () => setState(() => _frequency = frequency),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (_frequency != HealthPlusFrequency.oneOff) ...[
          _HealthInput(
            controller: _preferredDay,
            label: 'Preferred Pickup Day',
          ),
          _HealthInput(
            controller: _preferredTime,
            label: 'Preferred Pickup Time',
          ),
        ] else
          _HealthInput(
            controller: _preferredTime,
            label: 'Preferred pickup time',
          ),
        if (_frequency == HealthPlusFrequency.custom)
          _HealthInput(
            controller: _customSchedule,
            label: 'Custom repeat schedule',
          ),
        const SizedBox(height: 18),
        _PrimaryHealthButton(
          label: 'Continue',
          onTap: () => _goTo(_HealthStep.plan),
        ),
      ],
    );
  }

  Widget _planStep() {
    final planQuotes = HealthPlusPricing.planQuotes(
      recurring: _frequency != HealthPlusFrequency.oneOff,
    );
    return Column(
      children: [
        ...planQuotes.map((planQuote) {
          return _PlanCard(
            selected: _subscriptionPlan == planQuote.plan.value,
            title: planQuote.plan.label,
            subtitle: planQuote.plan.benefits.join(' · '),
            price: planQuote.displayPrice,
            onTap: () =>
                setState(() => _subscriptionPlan = planQuote.plan.value),
          );
        }),
        const SizedBox(height: 18),
        _PrimaryHealthButton(
          label: 'Choose Plan',
          onTap: () => _goTo(_HealthStep.notes),
        ),
      ],
    );
  }

  Widget _notesStep() {
    return Column(
      children: [
        _HealthInput(
          controller: _notes,
          label: 'Notes for the rider (optional)',
          hint: 'e.g. Leave with concierge, ring buzzer 2B',
          maxLines: 4,
        ),
        _ConsentCard(
          checked: _consent,
          onTap: () => setState(() => _consent = !_consent),
        ),
        const SizedBox(height: 18),
        _PrimaryHealthButton(
          label: 'Review Booking',
          enabled: _notesReady,
          onTap: () => _goTo(_HealthStep.review),
        ),
      ],
    );
  }

  Widget _reviewStep() {
    final quote = _quote;
    return Column(
      children: [
        _ReviewPanel(
          rows: [
            ('Pharmacy', _pharmacyAddress.text.trim()),
            ('Delivery', _deliveryAddress.text.trim()),
            ('Frequency', _frequency.label),
            ...quote
                .reviewLines(planLabel: _planTitle(_subscriptionPlan))
                .map((line) => (line.label, line.value)),
            ('Payment Method', _paymentMethodLabel),
          ],
          total: quote.total,
        ),
        const SizedBox(height: 18),
        _PrimaryHealthButton(
          label: 'Pay Securely',
          onTap: () => _goTo(_HealthStep.checkout),
        ),
      ],
    );
  }

  Widget _checkoutStep() {
    return Column(
      children: [
        _PayWithPanel(
          profile: _paymentProfile,
          wallet: _wallet,
          selected: _selectedPaymentOption,
          applyRoth: _applyRoth,
          loading: _financeLoading,
          financeMessage: _financeMessage,
          onSelect: (option) => setState(() => _selectedPaymentOption = option),
          onApplyRoth: (value) => setState(() => _applyRoth = value),
          onManage: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SenderWalletView()),
          ),
          onRetry: _loadFinance,
        ),
        const SizedBox(height: 12),
        const _CheckoutNote(),
        if (_message != null) _HealthNote(_message!),
        const SizedBox(height: 18),
        _PrimaryHealthButton(
          label: _submitting ? 'Creating Health+...' : 'Pay Securely',
          icon: Icons.lock_outline_rounded,
          enabled: !_submitting,
          onTap: _bookHealthPlus,
        ),
        if (_checkoutUrl != null) ...[
          const SizedBox(height: 10),
          _SecondaryHealthButton(
            label: 'Open secure checkout',
            icon: Icons.open_in_new_rounded,
            onTap: _openCheckout,
          ),
        ],
      ],
    );
  }

  Widget _confirmedStep() {
    return Column(
      children: [
        const _HealthTimeline(),
        const _HealthNote(
          "We'll collect your prescription and keep you updated every step of the way.",
        ),
        if (_message != null) _HealthNote(_message!),
        const SizedBox(height: 18),
        _SecondaryHealthButton(
          label: 'Back to Your Care',
          onTap: () => _goTo(_HealthStep.status),
        ),
        const SizedBox(height: 12),
        const _TrustStrip(),
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

  String _planTitle(String value) {
    return HealthPlusPricing.planFor(value).label;
  }
}

class _HealthTokens {
  static const navy = Color(0xFF07090F);
  static const input = Color(0xFF1F292E);
  static const border = Color(0x29FFFFFF);
  static const health = Color(0xFF2FAE8C);
  static const healthDeep = Color(0xFF1F7A63);
  static const muted = Color(0x99FFFFFF);
  static const soft = Color(0x6EC9D2D7);
  static const warning = Color(0xFFE0A93A);
}

class _HealthBackdrop extends StatelessWidget {
  const _HealthBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-.8, -1.1),
          radius: 1.2,
          colors: [
            _HealthTokens.health.withValues(alpha: .15),
            _HealthTokens.navy,
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _HealthTopBar extends StatelessWidget {
  final _HealthStep step;
  final VoidCallback onBack;

  const _HealthTopBar({required this.step, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final index = _HealthStep.values.indexOf(step);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          _IconGlassButton(icon: Icons.chevron_left_rounded, onTap: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: List.generate(_HealthStep.values.length - 1, (i) {
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(
                        right: i == _HealthStep.values.length - 2 ? 0 : 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: i < index
                          ? const LinearGradient(
                              colors: [
                                _HealthTokens.health,
                                _HealthTokens.healthDeep
                              ],
                            )
                          : null,
                      color: i < index
                          ? null
                          : Colors.white.withValues(alpha: .08),
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

class _HealthHeader extends StatelessWidget {
  final _HealthStep step;

  const _HealthHeader({required this.step});

  @override
  Widget build(BuildContext context) {
    final eyebrow = switch (step) {
      _HealthStep.status => 'HEALTH+',
      _HealthStep.details => 'STEP 01 — YOUR DETAILS',
      _HealthStep.pharmacy => 'STEP 02 — PHARMACY',
      _HealthStep.delivery => 'STEP 03 — DELIVERY',
      _HealthStep.frequency => 'STEP 04 — FREQUENCY',
      _HealthStep.plan => 'STEP 05 — PLAN',
      _HealthStep.notes => 'STEP 06 — NOTES & CONSENT',
      _HealthStep.review => 'STEP 07 — REVIEW',
      _HealthStep.checkout => 'STEP 08 — CHECKOUT',
      _HealthStep.confirmed => 'STEP 09 — CONFIRMED',
    };
    final title = switch (step) {
      _HealthStep.status => 'Your Care',
      _HealthStep.details => 'Who are we caring for?',
      _HealthStep.pharmacy => 'Which pharmacy has your prescription?',
      _HealthStep.delivery => 'Where should we deliver it?',
      _HealthStep.frequency => 'How should we look after this prescription?',
      _HealthStep.plan => 'Choose your plan',
      _HealthStep.notes => 'Anything we should know?',
      _HealthStep.review => 'Everything looks ready.',
      _HealthStep.checkout => 'Secure payment',
      _HealthStep.confirmed => "You're all set.",
    };
    final subtitle = step == _HealthStep.status
        ? "We'll help you stay on schedule."
        : step == _HealthStep.confirmed
            ? "We'll collect your prescription and keep you updated every step of the way."
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: _HealthTokens.health,
            fontFamily: 'JetBrains Mono',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            height: 1.16,
            fontWeight: FontWeight.w800,
            fontFamily: 'Inter',
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: _HealthTokens.muted,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _IconGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconGlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _HealthTokens.border),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool selected;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppGlassContainer(
          padding: padding,
          radius: AppTokens.radius16,
          accent: _HealthTokens.health,
          surfaceColor: selected
              ? _HealthTokens.health.withValues(alpha: .10)
              : Colors.white.withValues(alpha: .04),
          borderColor: selected ? _HealthTokens.health : _HealthTokens.border,
          child: child,
        ),
      );
}

class _CareChoice extends StatelessWidget {
  final bool selected;
  final String title;
  final VoidCallback onTap;

  const _CareChoice({
    required this.selected,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: _GlassCard(
        selected: selected,
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? _HealthTokens.health : _HealthTokens.muted,
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;

  const _HealthInput({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: _HealthTokens.input,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xE62F3B42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: _HealthTokens.soft,
              fontFamily: 'JetBrains Mono',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .6,
            ),
          ),
          TextField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white, fontFamily: 'Inter'),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _HealthTokens.muted),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool loading;
  final ValueChanged<String> onChanged;

  const _SearchField({
    required this.controller,
    required this.hint,
    required this.loading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: _HealthTokens.input,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xE62F3B42)),
      ),
      child: Row(
        children: [
          Icon(
            loading ? Icons.hourglass_top_rounded : Icons.search_rounded,
            color: _HealthTokens.health,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: _HealthTokens.muted),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final Suggestion item;
  final VoidCallback onTap;

  const _SuggestionRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined, color: _HealthTokens.health),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.mainText.isEmpty ? item.description : item.mainText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item.subText.isNotEmpty)
                    Text(
                      item.subText,
                      style: const TextStyle(
                        color: _HealthTokens.muted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentPharmacyCard extends StatelessWidget {
  final String label;
  final VoidCallback onUseAgain;

  const _RecentPharmacyCard({
    required this.label,
    required this.onUseAgain,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Row(
        children: [
          const Icon(Icons.local_pharmacy_outlined,
              color: _HealthTokens.health),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recent Pharmacy',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: _HealthTokens.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onUseAgain,
            child: const Text('Use Again'),
          ),
        ],
      ),
    );
  }
}

class _DeliveryAddressChoices extends StatelessWidget {
  const _DeliveryAddressChoices();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 12, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Favourite delivery address',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _DeliveryAddressChoiceRow extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _DeliveryAddressChoiceRow({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const labels = ['Home', 'Work', 'Parents', 'Care Home', 'Recent'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: labels
            .map(
              (label) => ActionChip(
                label: Text(label),
                onPressed: () => onSelected(label),
                backgroundColor: _HealthTokens.health.withValues(alpha: .12),
                labelStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                side: const BorderSide(color: _HealthTokens.border),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _FrequencyCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FrequencyCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: _GlassCard(
        selected: selected,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                color: _HealthTokens.muted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final String price;
  final VoidCallback onTap;

  const _PlanCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: _GlassCard(
        selected: selected,
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? _HealthTokens.health : _HealthTokens.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _HealthTokens.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              price,
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

class _ConsentCard extends StatelessWidget {
  final bool checked;
  final VoidCallback onTap;

  const _ConsentCard({required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: _GlassCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              checked ? Icons.check_box_rounded : Icons.check_box_outline_blank,
              color: checked ? _HealthTokens.health : _HealthTokens.muted,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'I confirm the prescription is valid and ready or will be ready for pharmacy collection.',
                style: TextStyle(
                  color: Color(0xFFC9D2D7),
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewPanel extends StatelessWidget {
  final List<(String, String)> rows;
  final double total;

  const _ReviewPanel({required this.rows, required this.total});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        children: [
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      style: const TextStyle(color: _HealthTokens.muted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: _HealthTokens.border),
          Row(
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
                HealthPlusPricing.formatGbp(total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckoutNote extends StatelessWidget {
  const _CheckoutNote();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.lock_outline_rounded, color: _HealthTokens.health),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "We'll use your Circum Pay With profile for secure checkout.",
              style: TextStyle(
                color: Color(0xFFC9D2D7),
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayWithPanel extends StatelessWidget {
  final SenderPaymentProfile profile;
  final SenderWalletData? wallet;
  final SenderPaymentProfileOption? selected;
  final bool applyRoth;
  final bool loading;
  final String? financeMessage;
  final ValueChanged<SenderPaymentProfileOption> onSelect;
  final ValueChanged<bool> onApplyRoth;
  final VoidCallback onManage;
  final VoidCallback onRetry;

  const _PayWithPanel({
    required this.profile,
    required this.wallet,
    required this.selected,
    required this.applyRoth,
    required this.loading,
    required this.financeMessage,
    required this.onSelect,
    required this.onApplyRoth,
    required this.onManage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final options = senderOrderedPaymentOptions(
      profile,
      platform: Theme.of(context).platform,
      includeAddMethod: false,
    );
    final balance = wallet?.balance ?? 0;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pay With',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            selected == null
                ? 'Default payment method'
                : 'Default payment method · ${selected!.title}',
            style: const TextStyle(color: _HealthTokens.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (loading)
            const _HealthNote('Loading Pay With profile...')
          else if (options.isEmpty)
            _HealthNote(
              financeMessage ??
                  'No saved payment methods yet. Manage Payment Methods in Wallet.',
              warning: true,
            )
          else
            ...options.map(
              (option) => _PayWithOptionRow(
                option: option,
                selected: selected?.title == option.title,
                onTap: () => onSelect(option),
              ),
            ),
          const Divider(color: _HealthTokens.border),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _HealthTokens.health,
            value: applyRoth,
            onChanged: balance > 0 ? onApplyRoth : null,
            title: const Text(
              'Apply Roth',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              'Available Roth · ${balance.toStringAsFixed(balance % 1 == 0 ? 0 : 2)} Roth',
              style: const TextStyle(color: _HealthTokens.muted),
            ),
          ),
          if (financeMessage != null && !loading) ...[
            const SizedBox(height: 8),
            _HealthNote(financeMessage!, warning: true),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SecondaryHealthButton(
                  label: 'Manage Payment Methods',
                  icon: Icons.account_balance_wallet_outlined,
                  onTap: onManage,
                ),
              ),
              const SizedBox(width: 10),
              _IconGlassButton(icon: Icons.refresh_rounded, onTap: onRetry),
            ],
          ),
        ],
      ),
    );
  }
}

class _PayWithOptionRow extends StatelessWidget {
  final SenderPaymentProfileOption option;
  final bool selected;
  final VoidCallback onTap;

  const _PayWithOptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (option.type) {
      SenderPaymentProfileOptionType.applePay => Icons.apple_rounded,
      SenderPaymentProfileOptionType.googlePay => Icons.android_rounded,
      SenderPaymentProfileOptionType.savedCard => Icons.credit_card_rounded,
      SenderPaymentProfileOptionType.addPaymentMethod => Icons.add_card_rounded,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: _HealthTokens.health),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (option.isDefault)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text(
                  '✓ Default',
                  style: TextStyle(
                    color: _HealthTokens.health,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? _HealthTokens.health : _HealthTokens.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthTimeline extends StatelessWidget {
  const _HealthTimeline();

  @override
  Widget build(BuildContext context) {
    const labels = [
      '💊 Prescription Ready',
      '🚴 Rider Assigned',
      '📦 Collected',
      '🚚 On The Way',
      '✅ Delivered',
    ];
    return _GlassCard(
      child: Column(
        children: List.generate(labels.length, (index) {
          final done = index == 0;
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
                      color: done ? _HealthTokens.health : _HealthTokens.border,
                      boxShadow: done
                          ? [
                              BoxShadow(
                                color:
                                    _HealthTokens.health.withValues(alpha: .32),
                                blurRadius: 12,
                              )
                            ]
                          : null,
                    ),
                  ),
                  if (index < labels.length - 1)
                    Container(
                      width: 1.5,
                      height: 26,
                      color: _HealthTokens.border,
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: done ? Colors.white : _HealthTokens.muted,
                    fontWeight: done ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final Map<String, dynamic>? pickup;
  final List<Map<String, dynamic>> payments;
  final VoidCallback onPauseSchedule;
  final VoidCallback onCancelPickup;
  final VoidCallback onUpdatePayment;

  const _StatusCard({
    required this.pickup,
    required this.payments,
    required this.onPauseSchedule,
    required this.onCancelPickup,
    required this.onUpdatePayment,
  });

  @override
  Widget build(BuildContext context) {
    if (pickup == null) {
      return const _GlassCard(
        child: Text(
          'No active pickup yet. Book your first Health+ collection and your care timeline will appear here.',
          style: TextStyle(
            color: Color(0xFFC9D2D7),
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _HealthTokens.health.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              _pickupStatusLabel(
                      '${pickup!['status'] ?? PickupStatus.scheduled.value}')
                  .toUpperCase(),
              style: const TextStyle(
                color: _HealthTokens.health,
                fontFamily: 'JetBrains Mono',
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${pickup!['frequency'] ?? 'monthly'} pickup',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${pickup!['preferredPickupTime'] ?? 'Scheduled'} · ${payments.isEmpty ? 'Checkout pending' : payments.first['status']}',
            style: const TextStyle(color: _HealthTokens.muted),
          ),
          const SizedBox(height: 12),
          _CareSummaryLine(
            label: 'Recent Pharmacy',
            value: '${pickup!['pharmacyAddress'] ?? 'Not selected'}',
          ),
          _CareSummaryLine(
            label: 'Preferred Schedule',
            value:
                '${pickup!['preferredPickupDay'] ?? pickup!['frequency'] ?? 'Scheduled'} ${pickup!['preferredPickupTime'] ?? ''}'
                    .trim(),
          ),
          _CareSummaryLine(
            label: 'Next Pickup',
            value: '${pickup!['preferredPickupTime'] ?? 'Scheduled'}',
          ),
          _CareSummaryLine(
            label: 'Current Status',
            value: _pickupStatusLabel(
                '${pickup!['status'] ?? PickupStatus.scheduled.value}'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SmallAction(label: 'Pause schedule', onTap: onPauseSchedule),
              _SmallAction(
                  label: 'Cancel', danger: true, onTap: onCancelPickup),
              _SmallAction(label: 'Update payment', onTap: onUpdatePayment),
            ],
          ),
        ],
      ),
    );
  }

  static String _pickupStatusLabel(String value) {
    return switch (PickupStatusValue.fromValue(value)) {
      PickupStatus.scheduled => 'Prescription ready',
      PickupStatus.assigned => 'Rider assigned',
      PickupStatus.awaitingPharmacyCollection => 'Rider assigned',
      PickupStatus.collected => 'Collected',
      PickupStatus.outForDelivery => 'On the way',
      PickupStatus.delivered => 'Delivered',
      PickupStatus.failed => 'Delivery update',
      PickupStatus.cancelled => 'Delivery update',
    };
  }
}

class _CareSummaryLine extends StatelessWidget {
  final String label;
  final String value;

  const _CareSummaryLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _HealthTokens.muted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value.isEmpty ? 'Scheduled' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final String label;
  final bool danger;
  final VoidCallback onTap;

  const _SmallAction({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: danger
                ? const Color(0xFFFF452B).withValues(alpha: .30)
                : _HealthTokens.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: danger ? const Color(0xFFFF452B) : const Color(0xFFC9D2D7),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PrimaryHealthButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool enabled;
  final VoidCallback onTap;

  const _PrimaryHealthButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [_HealthTokens.health, _HealthTokens.healthDeep],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryHealthButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _SecondaryHealthButton({
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _HealthTokens.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthNote extends StatelessWidget {
  final String text;
  final bool warning;

  const _HealthNote(this.text, {this.warning = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (warning ? _HealthTokens.warning : _HealthTokens.health)
            .withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (warning ? _HealthTokens.warning : _HealthTokens.health)
              .withValues(alpha: .30),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFC9D2D7), height: 1.45),
      ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.shield_outlined, color: _HealthTokens.muted, size: 14),
        SizedBox(width: 6),
        Text(
          'Every step is saved. Nothing is lost.',
          style: TextStyle(
            color: _HealthTokens.muted,
            fontFamily: 'JetBrains Mono',
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
