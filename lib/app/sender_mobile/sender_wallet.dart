import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:intl/intl.dart';

import 'sender_finance.dart';

class SenderWalletData {
  final double balance;
  final bool frozen;
  final bool onboardingCompleted;
  final DateTime? updatedAt;

  const SenderWalletData({
    required this.balance,
    required this.frozen,
    required this.onboardingCompleted,
    this.updatedAt,
  });

  factory SenderWalletData.fromMap(Map<String, dynamic> map,
      {bool onboardingCompleted = false}) {
    final timestamp = map['updatedAt'];
    return SenderWalletData(
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      frozen: map['status'] == 'frozen',
      onboardingCompleted: onboardingCompleted,
      updatedAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}

class SenderWalletTransaction {
  final String id;
  final String description;
  final String direction;
  final String status;
  final String type;
  final double amount;
  final double balanceAfter;
  final DateTime? createdAt;

  const SenderWalletTransaction({
    required this.id,
    required this.description,
    required this.direction,
    required this.status,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.createdAt,
  });

  factory SenderWalletTransaction.fromMap(Map<String, dynamic> map) {
    final rawDate = map['createdAt'];
    return SenderWalletTransaction(
      id: '${map['transactionId'] ?? ''}',
      description: '${map['description'] ?? 'Roth activity'}',
      direction: '${map['direction'] ?? 'credit'}',
      status: '${map['status'] ?? 'completed'}',
      type: '${map['type'] ?? 'adjustment'}',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      balanceAfter: (map['balanceAfter'] as num?)?.toDouble() ?? 0,
      createdAt: rawDate is Timestamp ? rawDate.toDate() : null,
    );
  }
}

class SenderWalletPage {
  final List<SenderWalletTransaction> transactions;
  final String? nextPageToken;

  const SenderWalletPage(this.transactions, this.nextPageToken);
}

abstract class SenderWalletRepository
    implements SenderPaymentProfileRepository {
  Future<SenderWalletData> initialise();
  Stream<SenderWalletData> watch();
  Future<SenderWalletPage> transactions({String? pageToken});
  Future<void> completeOnboarding();
  Future<void> requestDebit({
    required double amount,
    required String relatedEntityId,
    required String idempotencyKey,
  });
}

class FirebaseSenderWalletRepository implements SenderWalletRepository {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  FirebaseSenderWalletRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instance;

  User get _user {
    final user = auth.currentUser;
    if (user == null) throw StateError('Sign in to access your Wallet.');
    return user;
  }

  @override
  Future<SenderWalletData> initialise() async {
    final user = _user;
    await functions.httpsCallable('initialiseSenderWallet').call();
    final results = await Future.wait([
      firestore.collection('senderWallets').doc(user.uid).get(),
      firestore.collection('users').doc(user.uid).get(),
    ]);
    final wallet = results[0].data() ?? const <String, dynamic>{};
    final profile = results[1].data() ?? const <String, dynamic>{};
    return SenderWalletData.fromMap(wallet,
        onboardingCompleted:
            profile['senderWalletOnboardingCompleted'] == true);
  }

  @override
  Stream<SenderWalletData> watch() async* {
    final user = _user;
    await for (final snapshot
        in firestore.collection('senderWallets').doc(user.uid).snapshots()) {
      final profile = await firestore.collection('users').doc(user.uid).get();
      yield SenderWalletData.fromMap(snapshot.data() ?? const {},
          onboardingCompleted:
              profile.data()?['senderWalletOnboardingCompleted'] == true);
    }
  }

  @override
  Future<SenderWalletPage> transactions({String? pageToken}) async {
    final result = await functions
        .httpsCallable('getSenderWalletTransactions')
        .call({'pageSize': 20, 'pageToken': pageToken});
    final data = Map<String, dynamic>.from(result.data as Map);
    final records = (data['transactions'] as List? ?? const [])
        .map((item) => SenderWalletTransaction.fromMap(
            Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    return SenderWalletPage(records, data['nextPageToken'] as String?);
  }

  @override
  Future<SenderPaymentMethodsData> paymentMethods() async {
    final result =
        await functions.httpsCallable('listSenderPaymentMethods').call();
    return SenderPaymentMethodsData.fromMap(
        Map<String, dynamic>.from(result.data as Map));
  }

  @override
  Future<SenderSetupIntentData> createSetupIntent() async {
    final result =
        await functions.httpsCallable('createSenderSetupIntent').call();
    return SenderSetupIntentData.fromMap(
        Map<String, dynamic>.from(result.data as Map));
  }

  @override
  Future<void> detachPaymentMethod(String paymentMethodId) async {
    await functions
        .httpsCallable('detachSenderPaymentMethod')
        .call({'paymentMethodId': paymentMethodId});
  }

  @override
  Future<void> setDefaultPaymentMethod(String paymentMethodId) async {
    await functions
        .httpsCallable('setDefaultSenderPaymentMethod')
        .call({'paymentMethodId': paymentMethodId});
  }

  @override
  Future<void> saveCheckoutPreference(
      SenderCheckoutPreference preference) async {
    await functions.httpsCallable('saveSenderCheckoutPreference').call({
      'preference': senderCheckoutPreferenceValue(preference),
    });
  }

  @override
  Future<void> completeOnboarding() async {
    await functions.httpsCallable('completeSenderWalletOnboarding').call();
  }

  @override
  Future<void> requestDebit({
    required double amount,
    required String relatedEntityId,
    required String idempotencyKey,
  }) async {
    await functions.httpsCallable('requestSenderWalletDebit').call({
      'amount': amount,
      'relatedEntityId': relatedEntityId,
      'idempotencyKey': idempotencyKey,
    });
  }
}

class SenderWalletView extends StatefulWidget {
  final SenderWalletRepository? repository;

  const SenderWalletView({super.key, this.repository});

  @override
  State<SenderWalletView> createState() => _SenderWalletViewState();
}

class _SenderWalletViewState extends State<SenderWalletView> {
  late final SenderWalletRepository _repository;
  StreamSubscription<SenderWalletData>? _subscription;
  SenderWalletData? _wallet;
  SenderPaymentMethodsData _paymentMethods = SenderPaymentMethodsData.empty();
  final List<SenderWalletTransaction> _transactions = [];
  String? _nextPage;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _paymentActionLoading = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseSenderWalletRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wallet = await _repository.initialise();
      final results = await Future.wait([
        _repository.transactions(),
        _repository.paymentMethods(),
      ]);
      final page = results[0] as SenderWalletPage;
      final methods = results[1] as SenderPaymentMethodsData;
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _paymentMethods = methods;
        _transactions
          ..clear()
          ..addAll(page.transactions);
        _nextPage = page.nextPageToken;
        _loading = false;
      });
      _subscription = _repository.watch().listen((value) {
        if (mounted) setState(() => _wallet = value);
      }, onError: (_) {});
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _continueOnboarding() async {
    try {
      await _repository.completeOnboarding();
      if (mounted) {
        setState(() => _wallet = SenderWalletData(
              balance: _wallet?.balance ?? 0,
              frozen: _wallet?.frozen ?? false,
              onboardingCompleted: true,
              updatedAt: _wallet?.updatedAt,
            ));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _loadMore() async {
    if (_nextPage == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repository.transactions(pageToken: _nextPage);
      if (mounted) {
        setState(() {
          _transactions.addAll(page.transactions);
          _nextPage = page.nextPageToken;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refreshPaymentMethods() async {
    final methods = await _repository.paymentMethods();
    if (mounted) setState(() => _paymentMethods = methods);
  }

  Future<void> _addPaymentMethod() async {
    if (_paymentActionLoading) return;
    setState(() {
      _paymentActionLoading = true;
      _error = null;
    });
    try {
      final setup = await _repository.createSetupIntent();
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          merchantDisplayName: 'Circum',
          customerId: setup.customerId,
          customerEphemeralKeySecret: setup.ephemeralKeySecret,
          setupIntentClientSecret: setup.setupIntentClientSecret,
          applePay: const PaymentSheetApplePay(merchantCountryCode: 'GB'),
          googlePay: const PaymentSheetGooglePay(
            merchantCountryCode: 'GB',
            currencyCode: 'GBP',
          ),
          style: ThemeMode.dark,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      await _refreshPaymentMethods();
      if (mounted) {
        _notice(context, 'Payment method added.');
      }
    } on StripeException catch (error) {
      if (mounted) {
        _notice(
            context, error.error.localizedMessage ?? 'Card setup cancelled.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _paymentActionLoading = false);
    }
  }

  Future<void> _setDefaultPaymentMethod(String id) async {
    if (_paymentActionLoading) return;
    setState(() => _paymentActionLoading = true);
    try {
      await _repository.setDefaultPaymentMethod(id);
      await _refreshPaymentMethods();
    } catch (error) {
      if (mounted) _notice(context, 'Could not update default card.');
    } finally {
      if (mounted) setState(() => _paymentActionLoading = false);
    }
  }

  Future<void> _removePaymentMethod(SenderPaymentMethod method) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove payment method?'),
            content: Text('${method.title} will be removed from Circum.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Remove')),
            ],
          ),
        ) ??
        false;
    if (!confirmed || _paymentActionLoading) return;
    setState(() => _paymentActionLoading = true);
    try {
      await _repository.detachPaymentMethod(method.id);
      await _refreshPaymentMethods();
    } catch (error) {
      if (mounted) _notice(context, 'Could not remove payment method.');
    } finally {
      if (mounted) setState(() => _paymentActionLoading = false);
    }
  }

  Future<void> _savePreference(SenderCheckoutPreference preference) async {
    if (_paymentActionLoading) return;
    setState(() => _paymentActionLoading = true);
    try {
      await _repository.saveCheckoutPreference(preference);
      await _refreshPaymentMethods();
    } catch (error) {
      if (mounted) _notice(context, 'Could not save checkout preference.');
    } finally {
      if (mounted) setState(() => _paymentActionLoading = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _wallet == null) {
      final permission = _error!.toLowerCase().contains('permission');
      final offline = _error!.toLowerCase().contains('network');
      return _WalletMessage(
        icon: permission
            ? Icons.lock_outline
            : offline
                ? Icons.cloud_off
                : Icons.error_outline,
        title: permission
            ? 'Wallet access unavailable'
            : offline
                ? 'You appear to be offline'
                : 'Wallet could not load',
        body: permission
            ? 'Your account does not currently have permission to view this Wallet.'
            : 'Your Roth is safe. Check your connection and try again.',
        action: _load,
      );
    }
    final wallet = _wallet!;
    if (!wallet.onboardingCompleted) {
      return _WalletOnboarding(onContinue: _continueOnboarding);
    }
    final referralTotal = _transactions
        .where((item) =>
            item.type == 'referral_reward' && item.direction == 'credit')
        .fold<double>(0, (total, item) => total + item.amount);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const Text('Wallet',
            style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('Circum Finance',
            style: TextStyle(
                color: _WalletColors.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 18),
        _PaymentMethodsSection(
          data: _paymentMethods,
          busy: _paymentActionLoading,
          onAdd: _addPaymentMethod,
          onSetDefault: _setDefaultPaymentMethod,
          onRemove: _removePaymentMethod,
        ),
        const SizedBox(height: 18),
        _CheckoutPreferenceSection(
          preference: _paymentMethods.preference,
          busy: _paymentActionLoading,
          onChanged: _savePreference,
        ),
        const SizedBox(height: 18),
        _WalletGlass(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ROTH BALANCE',
              style: TextStyle(
                  color: _WalletColors.lightBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1)),
          const SizedBox(height: 8),
          Semantics(
              label: '${wallet.balance.toStringAsFixed(0)} Roth available',
              child: Text(
                  '${wallet.balance.toStringAsFixed(wallet.balance % 1 == 0 ? 0 : 2)} Roth',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900))),
          const SizedBox(height: 8),
          Text(
              wallet.updatedAt == null
                  ? 'Ready'
                  : 'Updated ${DateFormat('d MMM, HH:mm').format(wallet.updatedAt!)}',
              style: const TextStyle(color: _WalletColors.muted, fontSize: 12)),
        ])),
        if (wallet.frozen) ...[
          const SizedBox(height: 12),
          const _WalletGlass(
              child: Row(children: [
            Icon(Icons.lock_outline, color: Color(0xFFFBBF24)),
            SizedBox(width: 12),
            Expanded(
                child: Text(
                    'This Wallet is frozen. You can view activity, but Roth cannot be spent.',
                    style: TextStyle(color: Colors.white, height: 1.4)))
          ])),
        ],
        const SizedBox(height: 18),
        const _WalletSectionTitle('Recent transactions'),
        const SizedBox(height: 10),
        _WalletGlass(
          padding: EdgeInsets.zero,
          child: _transactions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                      'No Roth activity yet. Rewards and eligible purchases will appear here.',
                      style:
                          TextStyle(color: _WalletColors.muted, height: 1.45)))
              : Column(
                  children: _transactions
                      .map((item) => _TransactionRow(item))
                      .toList()),
        ),
        if (_nextPage != null)
          TextButton(
              onPressed: _loadingMore ? null : _loadMore,
              child: Text(_loadingMore ? 'Loading…' : 'View all transactions')),
        const SizedBox(height: 18),
        const _WalletSectionTitle('Rewards'),
        const SizedBox(height: 10),
        _WalletGlass(
            child: _WalletLink(
                icon: Icons.group_add_outlined,
                title: 'Referral rewards',
                detail: '${referralTotal.toStringAsFixed(0)} Roth earned',
                onTap: () =>
                    _notice(context, 'Invite friends is coming next.'))),
        const SizedBox(height: 12),
        _WalletGlass(
            child: Column(children: [
          _WalletLink(
              icon: Icons.credit_card_outlined,
              title: 'Roth Cards',
              detail: 'Available soon',
              onTap: () => _notice(context, 'Roth Cards are available soon.')),
          const Divider(color: _WalletColors.hairline),
          _WalletLink(
              icon: Icons.help_outline,
              title: 'How Roth works',
              detail:
                  'Roth is Circum credit. It cannot be withdrawn or transferred.',
              onTap: () => _notice(context,
                  'Use Roth on eligible Circum purchases. Roth is not cash and cannot be withdrawn.')),
          const Divider(color: _WalletColors.hairline),
          _WalletLink(
              icon: Icons.shopping_bag_outlined,
              title: 'Use Roth at checkout',
              detail: 'Available for eligible Sender payments',
              onTap: () => _notice(context, 'Choose Roth on Sender checkout.')),
        ])),
      ],
    );
  }

  static void _notice(BuildContext context, String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

class SenderWalletHomeSummary extends StatefulWidget {
  final SenderWalletRepository? repository;
  final VoidCallback onOpenWallet;
  const SenderWalletHomeSummary(
      {super.key, this.repository, required this.onOpenWallet});
  @override
  State<SenderWalletHomeSummary> createState() =>
      _SenderWalletHomeSummaryState();
}

class _SenderWalletHomeSummaryState extends State<SenderWalletHomeSummary> {
  late final SenderWalletRepository _repository;
  SenderWalletData? _wallet;
  String? _error;
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseSenderWalletRepository();
    _repository.initialise().then((value) {
      if (mounted) setState(() => _wallet = value);
    }).catchError((_) {
      if (mounted) setState(() => _error = 'Unavailable');
    });
  }

  @override
  Widget build(BuildContext context) => _WalletGlass(
          child: InkWell(
        onTap: widget.onOpenWallet,
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_outlined,
              color: _WalletColors.lightBlue, size: 28),
          const SizedBox(width: 13),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Roth balance',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text('View Wallet',
                    style: TextStyle(color: _WalletColors.muted, fontSize: 12))
              ])),
          Text(
              _error ??
                  (_wallet == null
                      ? '…'
                      : '${_wallet!.balance.toStringAsFixed(_wallet!.balance % 1 == 0 ? 0 : 2)} Roth'),
              style: const TextStyle(
                  color: _WalletColors.lightBlue,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
        ]),
      ));
}

class _WalletOnboarding extends StatelessWidget {
  final VoidCallback onContinue;
  const _WalletOnboarding({required this.onContinue});
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 24),
        const Icon(Icons.account_balance_wallet_outlined,
            color: _WalletColors.lightBlue, size: 52),
        const SizedBox(height: 20),
        const Text('Meet Roth',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        const Text(
            'Roth is Circum ecosystem credit. Earn it through referrals and approved rewards, then use it on eligible Circum purchases. Roth cannot be withdrawn as cash or transferred.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _WalletColors.muted, height: 1.55)),
        const SizedBox(height: 24),
        SizedBox(
            height: 52,
            child: FilledButton(
                onPressed: onContinue,
                child: const Text('Continue to Wallet'))),
      ]);
}

class _WalletMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback action;
  const _WalletMessage(
      {required this.icon,
      required this.title,
      required this.body,
      required this.action});
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: _WalletGlass(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: _WalletColors.lightBlue, size: 36),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: _WalletColors.muted, height: 1.45)),
            const SizedBox(height: 18),
            FilledButton(onPressed: action, child: const Text('Retry'))
          ]))));
}

class _TransactionRow extends StatelessWidget {
  final SenderWalletTransaction transaction;
  const _TransactionRow(this.transaction);
  @override
  Widget build(BuildContext context) {
    final credit = transaction.direction == 'credit';
    return Semantics(
        label:
            '${credit ? 'Credit' : 'Debit'} ${transaction.amount} Roth. ${transaction.description}. ${transaction.status}',
        child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: _WalletColors.hairline))),
            child: Row(children: [
              Icon(
                  credit
                      ? Icons.add_circle_outline
                      : Icons.remove_circle_outline,
                  color: credit
                      ? const Color(0xFF34D399)
                      : const Color(0xFFFBBF24)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(transaction.description,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                        '${transaction.createdAt == null ? 'Pending date' : DateFormat('d MMM · HH:mm').format(transaction.createdAt!)} · ${transaction.status}',
                        style: const TextStyle(
                            color: _WalletColors.muted, fontSize: 11))
                  ])),
              Text(
                  '${credit ? '+' : '-'}${transaction.amount.toStringAsFixed(transaction.amount % 1 == 0 ? 0 : 2)} Roth',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900))
            ])));
  }
}

class _PaymentMethodsSection extends StatelessWidget {
  final SenderPaymentMethodsData data;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<String> onSetDefault;
  final ValueChanged<SenderPaymentMethod> onRemove;

  const _PaymentMethodsSection({
    required this.data,
    required this.busy,
    required this.onAdd,
    required this.onSetDefault,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _WalletSectionTitle('Payment methods'),
          const SizedBox(height: 10),
          _WalletGlass(
            child: Column(
              children: [
                _WalletLink(
                  icon: Icons.add_card_outlined,
                  title: busy ? 'Updating payment methods...' : 'Add card',
                  detail: 'Saved securely with Stripe',
                  onTap: busy ? () {} : onAdd,
                ),
                const Divider(color: _WalletColors.hairline),
                _WalletLink(
                  icon: Icons.apple_rounded,
                  title: 'Apple Pay',
                  detail: data.applePaySupported
                      ? 'Available on supported iOS devices'
                      : 'Unavailable on this device',
                  onTap: () => _SenderWalletViewState._notice(
                      context, 'Apple Pay appears during checkout.'),
                ),
                const Divider(color: _WalletColors.hairline),
                _WalletLink(
                  icon: Icons.android_rounded,
                  title: 'Google Pay',
                  detail: data.googlePaySupported
                      ? 'Available on supported Android devices'
                      : 'Unavailable on this device',
                  onTap: () => _SenderWalletViewState._notice(
                      context, 'Google Pay appears during checkout.'),
                ),
                if (data.methods.isEmpty) ...[
                  const Divider(color: _WalletColors.hairline),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'No saved cards yet. Add a card to make future Sender payments faster.',
                        style:
                            TextStyle(color: _WalletColors.muted, height: 1.4),
                      ),
                    ),
                  ),
                ] else
                  ...data.methods.map((method) => Column(
                        children: [
                          const Divider(color: _WalletColors.hairline),
                          _SavedCardRow(
                            method: method,
                            busy: busy,
                            onSetDefault: () => onSetDefault(method.id),
                            onRemove: () => onRemove(method),
                          ),
                        ],
                      )),
              ],
            ),
          ),
        ],
      );
}

class _SavedCardRow extends StatelessWidget {
  final SenderPaymentMethod method;
  final bool busy;
  final VoidCallback onSetDefault;
  final VoidCallback onRemove;

  const _SavedCardRow({
    required this.method,
    required this.busy,
    required this.onSetDefault,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Row(
          children: [
            const Icon(Icons.credit_card_rounded,
                color: _WalletColors.lightBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(method.title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    method.isDefault
                        ? '${method.expiry} · Default'
                        : method.expiry,
                    style: const TextStyle(
                        color: _WalletColors.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              enabled: !busy,
              icon: const Icon(Icons.more_horiz, color: _WalletColors.muted),
              onSelected: (value) {
                if (value == 'default') onSetDefault();
                if (value == 'remove') onRemove();
              },
              itemBuilder: (context) => [
                if (!method.isDefault)
                  const PopupMenuItem(
                      value: 'default', child: Text('Set as default')),
                const PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            ),
          ],
        ),
      );
}

class _CheckoutPreferenceSection extends StatelessWidget {
  final SenderCheckoutPreference preference;
  final bool busy;
  final ValueChanged<SenderCheckoutPreference> onChanged;

  const _CheckoutPreferenceSection({
    required this.preference,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _WalletSectionTitle('Checkout preferences'),
          const SizedBox(height: 10),
          _WalletGlass(
            child: DropdownButtonFormField<SenderCheckoutPreference>(
              initialValue: preference,
              dropdownColor: const Color(0xFF111827),
              decoration: const InputDecoration(
                labelText: 'Preferred payment order',
                labelStyle: TextStyle(color: _WalletColors.muted),
                border: InputBorder.none,
              ),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
              items: SenderCheckoutPreference.values
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(senderCheckoutPreferenceLabel(item)),
                      ))
                  .toList(growable: false),
              onChanged: busy
                  ? null
                  : (value) {
                      if (value != null) onChanged(value);
                    },
            ),
          ),
        ],
      );
}

class _WalletLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  const _WalletLink(
      {required this.icon,
      required this.title,
      required this.detail,
      required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Row(children: [
            Icon(icon, color: _WalletColors.lightBlue),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                  Text(detail,
                      style: const TextStyle(
                          color: _WalletColors.muted, fontSize: 11))
                ])),
            const Icon(Icons.chevron_right, color: _WalletColors.muted)
          ])));
}

class _WalletSectionTitle extends StatelessWidget {
  final String value;
  const _WalletSectionTitle(this.value);
  @override
  Widget build(BuildContext context) => Text(value,
      style: const TextStyle(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900));
}

class _WalletGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _WalletGlass(
      {required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
              padding: padding,
              decoration: BoxDecoration(
                  color: _WalletColors.glass,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _WalletColors.border)),
              child: child)));
}

class _WalletColors {
  static const lightBlue = Color(0xFF60A5FA);
  static const muted = Color(0xFF9CA3AF);
  static const glass = Color(0x0DF5F7FB);
  static const border = Color(0x29FFFFFF);
  static const hairline = Color(0x14F5F7FB);
}
