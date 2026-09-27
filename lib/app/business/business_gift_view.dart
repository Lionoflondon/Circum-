import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../sender_mobile/design_system/sender_design_system.dart';
import 'business_models.dart';
import 'business_repository.dart';

class BusinessGiftView extends StatefulWidget {
  final BusinessAccount account;
  final BusinessRepository repository;

  const BusinessGiftView({
    super.key,
    required this.account,
    required this.repository,
  });

  @override
  State<BusinessGiftView> createState() => _BusinessGiftViewState();
}

class _BusinessGiftViewState extends State<BusinessGiftView> {
  static const _approvedBudgets = [50, 100, 250, 500, 1000, 1500];
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _recipientEmail = TextEditingController();
  final _deliveryAddress = TextEditingController();
  final _timeWindow = TextEditingController();
  final _idempotencyKey = const Uuid().v4();
  DateTime? _deliveryDate;
  double? _budget;
  var _paymentRail = 'card';
  var _working = false;
  String? _message;

  @override
  void dispose() {
    _recipientName.dispose();
    _recipientPhone.dispose();
    _recipientEmail.dispose();
    _deliveryAddress.dispose();
    _timeWindow.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_working &&
      _budget != null &&
      _recipientName.text.trim().isNotEmpty &&
      (_recipientPhone.text.trim().isNotEmpty ||
          _recipientEmail.text.trim().isNotEmpty) &&
      _deliveryAddress.text.trim().isNotEmpty &&
      _deliveryDate != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.background,
      appBar: AppBar(
        title: const Text('Business Gift'),
        backgroundColor: AppTokens.background,
        foregroundColor: AppTokens.text,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            Text(
              'Create a corporate gift for ${widget.account.name}',
              style: const TextStyle(
                color: AppTokens.text,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Business Gifts are paid and fulfilled through the protected Business order authority. Recipient value stays visible to the sender only.',
              style: TextStyle(color: AppTokens.mutedText, height: 1.45),
            ),
            const SizedBox(height: 20),
            _field(_recipientName, 'Recipient name'),
            _field(_recipientPhone, 'Recipient phone (or use email)',
                keyboardType: TextInputType.phone),
            _field(_recipientEmail, 'Recipient email (or use phone)',
                keyboardType: TextInputType.emailAddress),
            _field(_deliveryAddress, 'Delivery address'),
            _field(_timeWindow, 'Delivery window (optional)'),
            const SizedBox(height: 6),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Delivery date'),
              subtitle: Text(_deliveryDate == null
                  ? 'Choose a future date'
                  : DateFormat.yMMMMd().format(_deliveryDate!)),
              trailing: const Icon(Icons.calendar_today_rounded),
              onTap: _working ? null : _pickDate,
            ),
            const SizedBox(height: 12),
            const Text('Gift budget',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in _approvedBudgets)
                  ChoiceChip(
                    label: Text('£$value'),
                    selected: _budget == value.toDouble(),
                    onSelected: _working
                        ? null
                        : (_) => setState(() => _budget = value.toDouble()),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Payment rail',
                style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final rail in const {
                  'card': 'Card / Stripe',
                  'invoice': 'Business invoice',
                  'roth': 'Business Roth',
                }.entries)
                  ChoiceChip(
                    label: Text(rail.value),
                    selected: _paymentRail == rail.key,
                    onSelected: _working ? null : (_) => _selectRail(rail.key),
                  ),
              ],
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _message!,
                  style:
                      const TextStyle(color: AppTokens.mutedText, height: 1.4),
                ),
              ),
            const SizedBox(height: 18),
            AppButton(
              label: _working
                  ? 'Securing Business Gift...'
                  : 'Create Business Gift',
              icon: Icons.lock_outline_rounded,
              onPressed: _canSubmit ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  void _selectRail(String? value) {
    if (value != null) setState(() => _paymentRail = value);
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: today.add(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 365)),
      initialDate: _deliveryDate ?? today.add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _deliveryDate = picked);
  }

  Future<void> _submit() async {
    if (!_canSubmit || _deliveryDate == null || _budget == null) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final result = await widget.repository
          .createBusinessGiftOrder(
            account: widget.account,
            budgetGbp: _budget!,
            paymentRail: _paymentRail,
            idempotencyKey: _idempotencyKey,
            recipientName: _recipientName.text,
            recipientPhone: _recipientPhone.text,
            recipientEmail: _recipientEmail.text,
            deliveryAddress: _deliveryAddress.text,
            deliveryDate: _deliveryDate!.toIso8601String(),
            deliveryTimeWindow: _timeWindow.text,
          )
          .timeout(businessOperationTimeout);
      if (!mounted) return;
      if (result.checkoutUrl != null) {
        final opened = await launchUrl(
          result.checkoutUrl!,
          mode: LaunchMode.externalApplication,
        ).timeout(businessOperationTimeout);
        if (!opened) throw StateError('Business Gift checkout could not open.');
        setState(() => _message =
            'Secure checkout is open. Return to Business after payment to verify the Gift order.');
      } else if (result.paymentRail == 'invoice') {
        setState(() => _message =
            'The Business Gift invoice is ready for the Business billing workflow. The Gift will be created after authoritative payment.');
      } else if (result.giftRequestId != null) {
        setState(
            () => _message = 'Business Gift secured and submitted for review.');
      } else {
        setState(() => _message =
            'Business Gift payment is being verified. Refresh Business before trying again.');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _message =
            'Business Gift is taking longer than expected. Refresh Business before trying again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Business Gift could not be secured. No duplicate order was created.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}
