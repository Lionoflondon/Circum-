import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'sender_accessibility.dart';
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
  final String paymentMethodLabel;
  final double amount;
  final double balanceAfter;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final String referenceId;
  final String createdBy;
  final String source;

  const SenderWalletTransaction({
    required this.id,
    required this.description,
    required this.direction,
    required this.status,
    required this.type,
    this.paymentMethodLabel = '',
    required this.amount,
    required this.balanceAfter,
    this.createdAt,
    this.completedAt,
    this.referenceId = '',
    this.createdBy = 'system',
    this.source = '',
  });

  factory SenderWalletTransaction.fromMap(Map<String, dynamic> map) {
    final rawDate = map['createdAt'];
    final rawCompletedDate =
        map['completedAt'] ?? map['updatedAt'] ?? map['createdAt'];
    final metadata = map['metadata'] is Map
        ? Map<String, dynamic>.from(map['metadata'] as Map)
        : const <String, dynamic>{};
    return SenderWalletTransaction(
      id: '${map['transactionId'] ?? ''}',
      description: '${map['description'] ?? 'Roth activity'}',
      direction: '${map['direction'] ?? 'credit'}',
      status: '${map['status'] ?? 'completed'}',
      type: '${map['type'] ?? 'adjustment'}',
      paymentMethodLabel:
          '${map['paymentMethodLabel'] ?? metadata['paymentMethodLabel'] ?? metadata['paidWith'] ?? ''}',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      balanceAfter: (map['balanceAfter'] as num?)?.toDouble() ?? 0,
      createdAt: rawDate is Timestamp ? rawDate.toDate() : null,
      completedAt:
          rawCompletedDate is Timestamp ? rawCompletedDate.toDate() : null,
      referenceId: '${map['relatedEntityId'] ?? map['referenceId'] ?? ''}',
      createdBy: '${map['createdBy'] ?? 'system'}',
      source: '${map['source'] ?? metadata['source'] ?? ''}',
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
      await _subscription?.cancel();
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

  void _openManagePayments() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => _ManagePaymentsScreen(
            repository: _repository,
            wallet: _wallet!,
          ),
          settings: const RouteSettings(name: '/sender-mobile/wallet/payments'),
        ))
        .then((_) => _refreshPaymentMethods());
  }

  void _openPaymentInformation(SenderPaymentProfileOptionType type) {
    final platform = Theme.of(context).platform;
    final appleAvailable = platform == TargetPlatform.iOS;
    final googleAvailable = platform == TargetPlatform.android;
    final title = type == SenderPaymentProfileOptionType.applePay
        ? 'Apple Pay'
        : 'Google Pay';
    final available = type == SenderPaymentProfileOptionType.applePay
        ? appleAvailable
        : googleAvailable;
    final platformName = type == SenderPaymentProfileOptionType.applePay
        ? 'an iPhone or iPad'
        : 'an Android device';
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _WalletInformationScreen(
        title: title,
        icon: type == SenderPaymentProfileOptionType.applePay
            ? Icons.apple_rounded
            : Icons.android_rounded,
        body: available
            ? '$title is available during eligible Circum checkout. Manage your preferred checkout order from Manage Payments.'
            : '$title is available when you use Circum on $platformName. Your saved cards and Roth remain available on this device.',
      ),
    ));
  }

  void _openRothInformation() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const _WalletInformationScreen(
            title: 'Roth',
            icon: Icons.auto_awesome_rounded,
            body:
                'Use Roth to reduce the cost of eligible Circum services. When Roth does not cover the full total, Circum can apply Roth first and charge the remainder to your chosen payment method.',
          ),
        ),
      );

  void _openEarnRoth() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const _EarnRothScreen(),
          settings: const RouteSettings(name: '/sender-mobile/wallet/earn'),
        ),
      );

  void _openSupport() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const _WalletSupportScreen(),
          settings: const RouteSettings(name: '/sender-mobile/wallet/support'),
        ),
      );

  Future<void> _redeemRothCard() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redeem Roth Card'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Card code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty) return;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('redeemGiftCard')
          .call({'code': code});
      await _load();
      if (mounted) _notice(context, 'Roth Card redeemed.');
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        _notice(
            context, error.message ?? 'This Roth Card could not be redeemed.');
      }
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
          wallet: wallet,
          busy: _paymentActionLoading,
          onAdd: _addPaymentMethod,
          onSetDefault: _setDefaultPaymentMethod,
          onRemove: _removePaymentMethod,
          onOpenMethod: _openPaymentInformation,
          onOpenRoth: _openRothInformation,
        ),
        const SizedBox(height: 18),
        _AvailableRothCard(wallet: wallet),
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
        const _WalletSectionTitle('Recent Activity'),
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
                      .map((item) => InkWell(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => _TransactionDetailsScreen(
                                  transaction: item,
                                ),
                              ),
                            ),
                            child: _TransactionRow(item),
                          ))
                      .toList()),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _WalletActivityScreen(
              repository: _repository,
              initialTransactions: List.of(_transactions),
              initialPageToken: _nextPage,
            ),
            settings:
                const RouteSettings(name: '/sender-mobile/wallet/activity'),
          )),
          child: const Text('View all activity'),
        ),
        const SizedBox(height: 18),
        const _WalletSectionTitle('Wallet Actions'),
        const SizedBox(height: 10),
        _WalletGlass(
            child: Column(children: [
          _WalletLink(
              icon: Icons.credit_card_outlined,
              title: 'Redeem Roth Card',
              detail: 'Apply approved Roth rewards.',
              onTap: _redeemRothCard),
          const Divider(color: _WalletColors.hairline),
          _WalletLink(
              icon: Icons.group_add_outlined,
              title: 'Earn Roth',
              detail: 'Referral Code · Invite Friends · Rewards',
              onTap: _openEarnRoth),
          const Divider(color: _WalletColors.hairline),
          _WalletLink(
              icon: Icons.tune_rounded,
              title: 'Manage Payments',
              detail: 'Default method and checkout preferences',
              onTap: _openManagePayments),
          const Divider(color: _WalletColors.hairline),
          _WalletLink(
              icon: Icons.help_outline,
              title: 'Support',
              detail: 'Get help with payments and Roth.',
              onTap: _openSupport),
        ])),
        const SizedBox(height: 18),
        const _WalletSectionTitle('Offers'),
        const SizedBox(height: 10),
        _WalletGlass(
          child: _OfferRow(
            title: 'Earn 5 Roth',
            detail:
                'Refer friends and earn 5 Roth when they complete their first successful Circum delivery.',
            onTap: _openEarnRoth,
          ),
        ),
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

class _ManagePaymentsScreen extends StatefulWidget {
  final SenderWalletRepository repository;
  final SenderWalletData wallet;

  const _ManagePaymentsScreen({
    required this.repository,
    required this.wallet,
  });

  @override
  State<_ManagePaymentsScreen> createState() => _ManagePaymentsScreenState();
}

class _ManagePaymentsScreenState extends State<_ManagePaymentsScreen> {
  SenderPaymentProfile? _profile;
  bool _loading = true;
  bool _busy = false;
  bool _businessAccount = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.repository.paymentMethods();
      var businessAccount = false;
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final owned = await FirebaseFirestore.instance
              .collection('businessAccounts')
              .where('createdByUserId', isEqualTo: user.uid)
              .limit(1)
              .get();
          businessAccount = owned.docs.isNotEmpty;
        }
      } catch (_) {
        businessAccount = false;
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _businessAccount = businessAccount;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final setup = await widget.repository.createSetupIntent();
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
      await _load();
    } on StripeException catch (error) {
      if (mounted) {
        _SenderWalletViewState._notice(
          context,
          error.error.localizedMessage ?? 'Card setup cancelled.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setDefault(String id) async {
    setState(() => _busy = true);
    try {
      await widget.repository.setDefaultPaymentMethod(id);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(SenderPaymentMethod method) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove payment method?'),
            content: Text('${method.title} will be removed from Circum.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await widget.repository.detachPaymentMethod(method.id);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePreference(SenderCheckoutPreference value) async {
    setState(() => _busy = true);
    try {
      await widget.repository.saveCheckoutPreference(value);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openMethod(SenderPaymentProfileOptionType type) {
    final apple = type == SenderPaymentProfileOptionType.applePay;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _WalletInformationScreen(
        title: apple ? 'Apple Pay' : 'Google Pay',
        icon: apple ? Icons.apple_rounded : Icons.android_rounded,
        body:
            '${apple ? 'Apple Pay' : 'Google Pay'} is offered automatically on supported devices during checkout.',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF07090F),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Manage Payments'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _WalletMessage(
                    icon: Icons.error_outline,
                    title: 'Payments could not load',
                    body: 'Check your connection and try again.',
                    action: _load,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    children: [
                      _PaymentMethodsSection(
                        sectionTitle: 'Saved Cards',
                        data: _profile!,
                        wallet: widget.wallet,
                        busy: _busy,
                        onAdd: _add,
                        onSetDefault: _setDefault,
                        onRemove: _remove,
                        onOpenMethod: _openMethod,
                        onOpenRoth: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const _WalletInformationScreen(
                              title: 'Roth',
                              icon: Icons.auto_awesome_rounded,
                              body:
                                  'Roth can be used alone or with a card when an eligible purchase costs more than your available Roth.',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _CheckoutPreferenceSection(
                        preference: _profile!.preference,
                        busy: _busy,
                        onChanged: _savePreference,
                      ),
                      const SizedBox(height: 18),
                      const _WalletSectionTitle('Split Payment'),
                      const SizedBox(height: 10),
                      const _WalletGlass(
                        child: Text(
                          'Choose Roth then card to apply available Roth first and charge only the remaining amount to your payment method.',
                          style: TextStyle(
                            color: _WalletColors.muted,
                            height: 1.45,
                          ),
                        ),
                      ),
                      if (_businessAccount) ...[
                        const SizedBox(height: 18),
                        const _WalletSectionTitle('Business payment methods'),
                        const SizedBox(height: 10),
                        const _WalletGlass(
                          child: Text(
                            'Business Finance uses this same payment profile for authorised Business checkout.',
                            style: TextStyle(
                              color: _WalletColors.muted,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
      );
}

class _EarnRothScreen extends StatefulWidget {
  const _EarnRothScreen();

  @override
  State<_EarnRothScreen> createState() => _EarnRothScreenState();
}

class _EarnRothScreenState extends State<_EarnRothScreen> {
  String _code = '';
  String _link = '';
  List<Map<String, dynamic>> _referrals = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Sign in to use referrals.');
      final result = await FirebaseFunctions.instance
          .httpsCallable('ensureReferralCode')
          .call();
      final data = Map<String, dynamic>.from(result.data as Map);
      final referrals = await FirebaseFirestore.instance
          .collection('referrals')
          .where('referrerUserId', isEqualTo: user.uid)
          .limit(100)
          .get();
      if (!mounted) return;
      setState(() {
        _code = '${data['referralCode'] ?? ''}';
        _link = '${data['referralLink'] ?? ''}';
        _referrals = referrals.docs.map((doc) => doc.data()).toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = _referrals.where((item) {
      final status = '${item['status'] ?? ''}'.toUpperCase();
      return status == 'ROTH_AWARDED' || status == 'REWARDED';
    }).length;
    final pending = _referrals.length - completed;
    return Scaffold(
      backgroundColor: const Color(0xFF07090F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Earn Roth'),
      ),
      body: _error != null
          ? _WalletMessage(
              icon: Icons.error_outline,
              title: 'Referrals could not load',
              body: 'Check your connection and try again.',
              action: _load,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              children: [
                const _WalletGlass(
                  child: Text(
                    'Earn 5 Roth when someone you invite completes their first successful Circum delivery.',
                    style: TextStyle(color: Colors.white, height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
                _WalletGlass(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Referral Code',
                          style: TextStyle(
                              color: _WalletColors.muted,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(_code.isEmpty ? 'Loading…' : _code,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 16),
                      _WalletLink(
                        icon: Icons.share_outlined,
                        title: 'Share Link',
                        detail: _link.isEmpty ? 'Preparing link' : _link,
                        onTap: _link.isEmpty
                            ? () => _SenderWalletViewState._notice(
                                  context,
                                  'Your referral link is still loading.',
                                )
                            : () => Share.share(
                                  'Join Circum with my referral link: $_link',
                                ),
                      ),
                      const Divider(color: _WalletColors.hairline),
                      _WalletLink(
                        icon: Icons.person_add_alt_1_outlined,
                        title: 'Invite Friends',
                        detail: 'Share your secure referral link',
                        onTap: _link.isEmpty
                            ? () => _SenderWalletViewState._notice(
                                  context,
                                  'Your referral link is still loading.',
                                )
                            : () => Share.share(
                                  'Join Circum with my referral link: $_link',
                                ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _WalletGlass(
                  child: Column(
                    children: [
                      _ReferralMetric('Pending Rewards', '$pending'),
                      const Divider(color: _WalletColors.hairline),
                      _ReferralMetric('Completed Rewards', '$completed'),
                      const Divider(color: _WalletColors.hairline),
                      _ReferralMetric('Referral Status',
                          _referrals.isEmpty ? 'Ready' : 'Active'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ReferralMetric extends StatelessWidget {
  final String label;
  final String value;
  const _ReferralMetric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: _WalletColors.muted)),
            ),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

class _WalletInformationScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String body;

  const _WalletInformationScreen({
    required this.title,
    required this.icon,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF07090F),
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _WalletGlass(
              child: Column(
                children: [
                  Icon(icon, color: _WalletColors.lightBlue, size: 42),
                  const SizedBox(height: 16),
                  Text(body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _WalletSupportScreen extends StatelessWidget {
  const _WalletSupportScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF07090F),
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('Wallet Support')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _WalletGlass(
              child: _WalletLink(
                icon: Icons.mail_outline,
                title: 'Contact Circum Support',
                detail: 'Get help with payments, cards or Roth',
                onTap: () => launchUrl(
                  Uri(
                    scheme: 'mailto',
                    path: 'support@circumuk.com',
                    queryParameters: {'subject': 'Wallet support'},
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _WalletActivityScreen extends StatefulWidget {
  final SenderWalletRepository repository;
  final List<SenderWalletTransaction> initialTransactions;
  final String? initialPageToken;

  const _WalletActivityScreen({
    required this.repository,
    required this.initialTransactions,
    required this.initialPageToken,
  });

  @override
  State<_WalletActivityScreen> createState() => _WalletActivityScreenState();
}

class _WalletActivityScreenState extends State<_WalletActivityScreen> {
  late final List<SenderWalletTransaction> _transactions;
  String? _nextPage;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _transactions = List.of(widget.initialTransactions);
    _nextPage = widget.initialPageToken;
  }

  Future<void> _loadMore() async {
    if (_loading || _nextPage == null) return;
    setState(() => _loading = true);
    final page = await widget.repository.transactions(pageToken: _nextPage);
    if (mounted) {
      setState(() {
        _transactions.addAll(page.transactions);
        _nextPage = page.nextPageToken;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF07090F),
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('Recent Activity')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            _WalletGlass(
              padding: EdgeInsets.zero,
              child: _transactions.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No activity yet.',
                          style: TextStyle(color: _WalletColors.muted)),
                    )
                  : Column(
                      children: _transactions
                          .map((item) => InkWell(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => _TransactionDetailsScreen(
                                      transaction: item,
                                    ),
                                  ),
                                ),
                                child: _TransactionRow(item),
                              ))
                          .toList(),
                    ),
            ),
            if (_nextPage != null)
              TextButton(
                onPressed: _loading ? null : _loadMore,
                child: Text(_loading ? 'Loading…' : 'Load more'),
              ),
          ],
        ),
      );
}

class _TransactionDetailsScreen extends StatelessWidget {
  final SenderWalletTransaction transaction;
  const _TransactionDetailsScreen({required this.transaction});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF07090F),
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('Activity Details')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _WalletGlass(
              child: Column(
                children: [
                  Text(
                    transaction.description,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DetailRow('Amount',
                      '${transaction.amount.toStringAsFixed(2)} Roth'),
                  _DetailRow('Status', _walletStatusLabel(transaction.status)),
                  _DetailRow(
                      'Completed date',
                      _walletTransactionDate(transaction,
                          includeStatus: false)),
                  _DetailRow(
                      'Reference ID',
                      transaction.referenceId.isEmpty
                          ? transaction.id
                          : transaction.referenceId),
                  _DetailRow('Created by', _walletCreatedBy(transaction)),
                  _DetailRow('Description', transaction.description),
                  _DetailRow(
                      'Transaction type', _walletCategory(transaction.type)),
                  _DetailRow('Current balance',
                      '${transaction.balanceAfter.toStringAsFixed(2)} Roth'),
                ],
              ),
            ),
          ],
        ),
      );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(color: _WalletColors.muted)),
            ),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
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
              Icon(_walletTransactionIcon(transaction.type),
                  color: _walletStatusColor(transaction.status)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Expanded(
                        child: Text(transaction.description,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (_walletCategoryBadge(transaction.type)
                          case final badge?)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                _WalletColors.lightBlue.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(badge,
                              style: const TextStyle(
                                  color: _WalletColors.lightBlue,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800)),
                        ),
                    ]),
                    const SizedBox(height: 3),
                    Text(
                        [
                          if (transaction.paymentMethodLabel.isNotEmpty)
                            'Paid with ${transaction.paymentMethodLabel}',
                          _walletTransactionDate(transaction),
                        ].join(' · '),
                        style: TextStyle(
                            color: _walletStatusColor(transaction.status),
                            fontSize: 11,
                            fontWeight: FontWeight.w600))
                  ])),
              Text(
                  '${credit ? '+' : '-'}${transaction.amount.toStringAsFixed(transaction.amount % 1 == 0 ? 0 : 2)} Roth',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900))
            ])));
  }
}

class _PaymentMethodsSection extends StatelessWidget {
  final String sectionTitle;
  final SenderPaymentMethodsData data;
  final SenderWalletData wallet;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<String> onSetDefault;
  final ValueChanged<SenderPaymentMethod> onRemove;
  final ValueChanged<SenderPaymentProfileOptionType> onOpenMethod;
  final VoidCallback onOpenRoth;

  const _PaymentMethodsSection({
    this.sectionTitle = 'Pay With',
    required this.data,
    required this.wallet,
    required this.busy,
    required this.onAdd,
    required this.onSetDefault,
    required this.onRemove,
    required this.onOpenMethod,
    required this.onOpenRoth,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WalletSectionTitle(sectionTitle),
          const SizedBox(height: 10),
          _WalletGlass(
            child: Column(
              children: [
                ...senderOrderedPaymentOptions(data)
                    .where((option) =>
                        option.type !=
                        SenderPaymentProfileOptionType.addPaymentMethod)
                    .toList(growable: false)
                    .asMap()
                    .entries
                    .map((entry) => Column(
                          children: [
                            if (entry.key > 0)
                              const Divider(color: _WalletColors.hairline),
                            _PaymentProfileOptionRow(
                              option: entry.value,
                              busy: busy,
                              showDefaultBadge: entry.value.isDefault ||
                                  (entry.key == 0 &&
                                      (entry.value.type ==
                                              SenderPaymentProfileOptionType
                                                  .applePay ||
                                          entry.value.type ==
                                              SenderPaymentProfileOptionType
                                                  .googlePay)),
                              onAdd: onAdd,
                              onSetDefault: onSetDefault,
                              onRemove: onRemove,
                              onOpenMethod: onOpenMethod,
                            ),
                          ],
                        )),
                if (data.applePaySupported ||
                    data.googlePaySupported ||
                    data.methods.isNotEmpty)
                  const Divider(color: _WalletColors.hairline),
                _RothPayWithRow(wallet: wallet, onTap: onOpenRoth),
                const Divider(color: _WalletColors.hairline),
                _PaymentProfileOptionRow(
                  option: const SenderPaymentProfileOption(
                    SenderPaymentProfileOptionType.addPaymentMethod,
                  ),
                  busy: busy,
                  showDefaultBadge: false,
                  onAdd: onAdd,
                  onSetDefault: onSetDefault,
                  onRemove: onRemove,
                  onOpenMethod: onOpenMethod,
                ),
                if (data.methods.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Add a card to make future Sender payments faster.',
                        style:
                            TextStyle(color: _WalletColors.muted, height: 1.4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
}

class _PaymentProfileOptionRow extends StatelessWidget {
  final SenderPaymentProfileOption option;
  final bool busy;
  final bool showDefaultBadge;
  final VoidCallback onAdd;
  final ValueChanged<String> onSetDefault;
  final ValueChanged<SenderPaymentMethod> onRemove;
  final ValueChanged<SenderPaymentProfileOptionType> onOpenMethod;

  const _PaymentProfileOptionRow({
    required this.option,
    required this.busy,
    required this.showDefaultBadge,
    required this.onAdd,
    required this.onSetDefault,
    required this.onRemove,
    required this.onOpenMethod,
  });

  @override
  Widget build(BuildContext context) {
    final method = option.method;
    if (option.type == SenderPaymentProfileOptionType.addPaymentMethod) {
      return _WalletLink(
        icon: Icons.add_card_outlined,
        title: busy ? 'Updating Pay With...' : '+ Add Payment Method',
        detail: 'Manage securely',
        onTap: busy
            ? () => _SenderWalletViewState._notice(
                  context,
                  'Payment methods are updating.',
                )
            : onAdd,
      );
    }
    if (option.type == SenderPaymentProfileOptionType.applePay) {
      return _WalletLink(
        icon: Icons.apple_rounded,
        title: 'Apple Pay',
        detail: showDefaultBadge ? '✓ Default' : 'Use on supported iOS devices',
        onTap: () => onOpenMethod(SenderPaymentProfileOptionType.applePay),
      );
    }
    if (option.type == SenderPaymentProfileOptionType.googlePay) {
      return _WalletLink(
        icon: Icons.android_rounded,
        title: 'Google Pay',
        detail:
            showDefaultBadge ? '✓ Default' : 'Use on supported Android devices',
        onTap: () => onOpenMethod(SenderPaymentProfileOptionType.googlePay),
      );
    }
    if (method == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Row(
        children: [
          const Icon(Icons.credit_card_rounded, color: _WalletColors.lightBlue),
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
                      ? '${method.expiry} · ✓ Default'
                      : method.expiry,
                  style:
                      const TextStyle(color: _WalletColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            enabled: !busy,
            icon: const Icon(Icons.more_horiz, color: _WalletColors.muted),
            onSelected: (value) {
              if (value == 'default') onSetDefault(method.id);
              if (value == 'remove') onRemove(method);
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
}

class _RothPayWithRow extends StatelessWidget {
  final SenderWalletData wallet;
  final VoidCallback onTap;

  const _RothPayWithRow({required this.wallet, required this.onTap});

  @override
  Widget build(BuildContext context) => _WalletLink(
        icon: Icons.auto_awesome_rounded,
        title: 'Roth',
        detail:
            '${wallet.balance.toStringAsFixed(wallet.balance % 1 == 0 ? 0 : 2)} available',
        onTap: onTap,
      );
}

class _AvailableRothCard extends StatelessWidget {
  final SenderWalletData wallet;

  const _AvailableRothCard({required this.wallet});

  @override
  Widget build(BuildContext context) {
    final highContrast =
        SenderAccessibilityScope.maybeOf(context)?.settings.highContrast ??
            false;
    return _WalletGlass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        children: [
          _RothEmblem(highContrast: highContrast),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Available Roth',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                    wallet.updatedAt == null
                        ? 'Ready'
                        : 'Updated ${DateFormat('d MMM, HH:mm').format(wallet.updatedAt!)}',
                    style: const TextStyle(
                        color: _WalletColors.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Semantics(
          label: '${wallet.balance.toStringAsFixed(0)} Roth available',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                  wallet.balance
                      .toStringAsFixed(wallet.balance % 1 == 0 ? 0 : 2),
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight:
                          highContrast ? FontWeight.w900 : FontWeight.w900,
                      shadows: highContrast
                          ? const [
                              Shadow(
                                color: Color(0x99000000),
                                blurRadius: 3,
                              ),
                            ]
                          : null)),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 7),
                child: Text('ROTH',
                    style: TextStyle(
                        color: _WalletColors.lightBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1)),
              ),
            ],
          )),
      const SizedBox(height: 10),
      const Text(
        'Use Roth to reduce the cost of eligible Circum services.',
        style: TextStyle(color: _WalletColors.muted, height: 1.45),
      ),
    ]));
  }
}

class _RothEmblem extends StatelessWidget {
  final bool highContrast;
  const _RothEmblem({this.highContrast = false});

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF60A5FA), Color(0xFF34D399)],
          ),
          boxShadow: [
            BoxShadow(
              color: _WalletColors.lightBlue
                  .withValues(alpha: highContrast ? .52 : .24),
              blurRadius: highContrast ? 28 : 20,
              spreadRadius: highContrast ? 2 : 0,
            ),
          ],
        ),
        child: const Icon(Icons.auto_awesome_rounded,
            color: Colors.white, size: 22),
      );
}

class _OfferRow extends StatelessWidget {
  final String title;
  final String detail;
  final VoidCallback onTap;

  const _OfferRow({
    required this.title,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Row(
            children: [
              const Icon(Icons.local_offer_outlined,
                  color: _WalletColors.lightBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(detail,
                        style: const TextStyle(
                            color: _WalletColors.muted, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _WalletColors.muted),
            ],
          ),
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
  Widget build(BuildContext context) {
    final highContrast =
        SenderAccessibilityScope.maybeOf(context)?.settings.highContrast ??
            false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: highContrast ? const Color(0xFA0C121C) : _WalletColors.glass,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color:
                  highContrast ? const Color(0x2EFFFFFF) : _WalletColors.border,
              width: highContrast ? 1.3 : 1,
            ),
            boxShadow: highContrast
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .58),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _WalletColors {
  static const lightBlue = Color(0xFF60A5FA);
  static const muted = Color(0xFF9CA3AF);
  static const glass = Color(0x0DF5F7FB);
  static const border = Color(0x29FFFFFF);
  static const hairline = Color(0x14F5F7FB);
}

String _walletStatusLabel(String value) {
  final status = value.trim().toLowerCase();
  if (status == 'pending' || status == 'processing') return 'Pending';
  if (status == 'failed' || status == 'failure') return 'Failed';
  if (status == 'cancelled' || status == 'canceled' || status == 'reversed') {
    return 'Cancelled';
  }
  return 'Completed';
}

Color _walletStatusColor(String value) {
  return switch (_walletStatusLabel(value)) {
    'Pending' => const Color(0xFFFBBF24),
    'Failed' => const Color(0xFFEF4444),
    'Cancelled' => const Color(0xFF9CA3AF),
    _ => const Color(0xFF34D399),
  };
}

String _walletFriendlyDate(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today • ${DateFormat('HH:mm').format(date)}';
  if (difference == 1) {
    return 'Yesterday • ${DateFormat('HH:mm').format(date)}';
  }
  return DateFormat('d MMM yyyy • HH:mm').format(date);
}

String _walletTransactionDate(
  SenderWalletTransaction transaction, {
  bool includeStatus = true,
}) {
  final status = _walletStatusLabel(transaction.status);
  if (status == 'Pending') {
    return includeStatus
        ? 'Pending • Estimated completion'
        : 'Estimated completion';
  }
  final date = transaction.completedAt ?? transaction.createdAt;
  final dateLabel =
      date == null ? 'Date unavailable' : _walletFriendlyDate(date);
  return includeStatus ? '$status • $dateLabel' : dateLabel;
}

IconData _walletTransactionIcon(String value) {
  final type = value.toLowerCase();
  if (type.contains('gift_card') || type.contains('roth_card')) {
    return Icons.card_giftcard_rounded;
  }
  if (type.contains('gift')) return Icons.redeem_rounded;
  if (type.contains('health')) return Icons.health_and_safety_outlined;
  if (type.contains('business')) return Icons.business_center_outlined;
  if (type.contains('referral')) return Icons.group_add_outlined;
  if (type.contains('refund')) return Icons.undo_rounded;
  if (type.contains('admin')) return Icons.admin_panel_settings_outlined;
  if (type.contains('adjust') || type.contains('reversal')) {
    return Icons.tune_rounded;
  }
  if (type.contains('delivery') ||
      type.contains('checkout') ||
      type.contains('spend')) {
    return Icons.local_shipping_outlined;
  }
  return Icons.receipt_long_outlined;
}

String _walletCategory(String value) {
  final type = value.toLowerCase();
  if (type.contains('gift_card') || type.contains('roth_card')) {
    return 'Gift card redemption';
  }
  if (type.contains('gift')) return 'Gift purchase';
  if (type.contains('health')) return 'Health+';
  if (type.contains('business')) return 'Business';
  if (type.contains('referral')) return 'Referral reward';
  if (type.contains('refund')) return 'Refund';
  if (type.contains('admin')) return 'Admin credit';
  if (type.contains('adjust') || type.contains('reversal')) return 'Adjustment';
  if (type.contains('delivery') ||
      type.contains('checkout') ||
      type.contains('spend')) {
    return 'Delivery payment';
  }
  return value.replaceAll('_', ' ');
}

String? _walletCategoryBadge(String type) {
  final value = type.toLowerCase();
  return value == 'admin_credit' || value == 'admin_issue'
      ? 'Admin Credit'
      : null;
}

String _walletCreatedBy(SenderWalletTransaction transaction) {
  final creator = transaction.createdBy.trim().toLowerCase();
  final type = transaction.type.toLowerCase();
  if (type.contains('referral')) return 'Referral Engine';
  if (creator == 'system' || creator.isEmpty) return 'System';
  final source = transaction.source.toLowerCase();
  if (creator == 'user' ||
      source.contains('sender_wallet') ||
      source.contains('checkout')) {
    return 'User';
  }
  return 'Admin';
}
