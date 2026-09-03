import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../env/env.dart';
import '../business/business_view.dart';
import '../send_package/view/ride_chats.dart';
import 'design_system/sender_design_system.dart';
import 'sender_accessibility.dart';
import 'sender_finance.dart';
import 'sender_page_shell.dart';
import 'sender_profile_authority.dart';

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
      updatedAt: _walletDateTime(timestamp),
    );
  }

  Map<String, dynamic> toCacheMap() => {
        'balance': balance,
        'status': frozen ? 'frozen' : 'active',
        'onboardingCompleted': onboardingCompleted,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
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
      createdAt: _walletDateTime(rawDate),
      completedAt: _walletDateTime(rawCompletedDate),
      referenceId: '${map['relatedEntityId'] ?? map['referenceId'] ?? ''}',
      createdBy: '${map['createdBy'] ?? 'system'}',
      source: '${map['source'] ?? metadata['source'] ?? ''}',
    );
  }

  Map<String, dynamic> toCacheMap() => {
        'transactionId': id,
        'description': description,
        'direction': direction,
        'status': status,
        'type': type,
        'paymentMethodLabel': paymentMethodLabel,
        'amount': amount,
        'balanceAfter': balanceAfter,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        'referenceId': referenceId,
        'createdBy': createdBy,
        'source': source,
      };
}

DateTime? _walletDateTime(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String? _senderWalletCacheKey() {
  String? uid;
  try {
    uid = FirebaseAuth.instance.currentUser?.uid;
  } catch (_) {
    uid = null;
  }
  return uid == null ? null : 'senderWalletSnapshot:$uid';
}

const _senderWalletActionTimeout = Duration(seconds: 15);

Future<SenderPaymentProfile> _withDeviceWalletSupport(
    SenderPaymentProfile profile) async {
  if (kIsWeb) {
    return profile.withPlatformPaySupport(applePay: false, googlePay: false);
  }
  var supported = false;
  try {
    supported = await Stripe.instance
        .isPlatformPaySupported()
        .timeout(const Duration(seconds: 4));
  } catch (error) {
    debugPrint(
        'Sender Wallet device-pay readiness unavailable: ${error.runtimeType}');
  }
  return profile.withPlatformPaySupport(
    applePay: defaultTargetPlatform == TargetPlatform.iOS && supported,
    googlePay:
        defaultTargetPlatform == TargetPlatform.android && supported,
  );
}

class _CachedSenderWalletSnapshot {
  final SenderWalletData wallet;
  final List<SenderWalletTransaction> transactions;
  final String? nextPageToken;
  final DateTime cachedAt;

  const _CachedSenderWalletSnapshot({
    required this.wallet,
    required this.transactions,
    required this.nextPageToken,
    required this.cachedAt,
  });

  Map<String, dynamic> toMap() => {
        'wallet': wallet.toCacheMap(),
        'transactions': transactions
            .map((transaction) => transaction.toCacheMap())
            .toList(),
        if (nextPageToken != null) 'nextPageToken': nextPageToken,
        'cachedAt': cachedAt.toIso8601String(),
      };

  static _CachedSenderWalletSnapshot? fromMap(Map<String, dynamic> data) {
    final walletData = data['wallet'];
    if (walletData is! Map) return null;
    final transactions = (data['transactions'] as List? ?? const [])
        .whereType<Map>()
        .map((item) =>
            SenderWalletTransaction.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    return _CachedSenderWalletSnapshot(
      wallet: SenderWalletData.fromMap(
        Map<String, dynamic>.from(walletData),
        onboardingCompleted: walletData['onboardingCompleted'] == true,
      ),
      transactions: transactions,
      nextPageToken: data['nextPageToken'] as String?,
      cachedAt: _walletDateTime(data['cachedAt']) ?? DateTime.now(),
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
  static const _firebaseReadTimeout = Duration(seconds: 8);

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  final SenderProfileAuthority profileAuthority;

  FirebaseSenderWalletRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : auth = auth ?? FirebaseAuth.instance,
        firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instance,
        profileAuthority = SenderProfileAuthority(
          auth: auth,
          firestore: firestore,
          functions: functions,
        );

  User get _user {
    final user = auth.currentUser;
    if (user == null) throw StateError('Sign in to access your Wallet.');
    return user;
  }

  @override
  Future<SenderWalletData> initialise() async {
    final user = _user;
    try {
      await functions
          .httpsCallable('initialiseSenderWallet')
          .call()
          .timeout(_firebaseReadTimeout);
    } catch (error) {
      debugPrint('Sender Wallet service initialization unavailable: $error');
    }
    final walletSnapshot = await firestore
        .collection('senderWallets')
        .doc(user.uid)
        .get()
        .timeout(_firebaseReadTimeout);
    final wallet = walletSnapshot.data() ?? const <String, dynamic>{};
    var profile = const <String, dynamic>{};
    try {
      profile = (await profileAuthority.load('wallet.initialise.profile')).data;
    } catch (error) {
      debugPrint('Sender Wallet profile flag unavailable: $error');
    }
    return SenderWalletData.fromMap(wallet,
        onboardingCompleted:
            profile['senderWalletOnboardingCompleted'] == true);
  }

  @override
  Stream<SenderWalletData> watch() {
    final user = _user;
    final controller = StreamController<SenderWalletData>();
    DocumentSnapshot<Map<String, dynamic>>? latestWallet;
    SenderProfileAuthoritySnapshot? latestProfile;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? walletSub;
    StreamSubscription<SenderProfileAuthoritySnapshot>? profileSub;

    void emitIfReady() {
      final wallet = latestWallet;
      if (wallet == null) return;
      final profile = latestProfile;
      controller.add(SenderWalletData.fromMap(
        wallet.data() ?? const {},
        onboardingCompleted:
            profile?.data['senderWalletOnboardingCompleted'] == true,
      ));
    }

    controller.onListen = () {
      walletSub = firestore
          .collection('senderWallets')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        latestWallet = snapshot;
        emitIfReady();
      }, onError: (error) {
        debugPrint('Sender Wallet live balance unavailable: $error');
      });
      profileSub = profileAuthority.watch('wallet.watch.profile').listen(
        (snapshot) {
          latestProfile = snapshot;
          emitIfReady();
        },
        onError: (error) {
          debugPrint('Sender Wallet live profile flag unavailable: $error');
        },
      );
    };
    controller.onCancel = () async {
      await walletSub?.cancel();
      await profileSub?.cancel();
    };
    return controller.stream;
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
  static const _walletOperationTimeout = _senderWalletActionTimeout;

  late final SenderWalletRepository _repository;
  StreamSubscription<SenderWalletData>? _subscription;
  SenderWalletData? _wallet;
  SenderPaymentMethodsData _paymentMethods = SenderPaymentMethodsData.empty();
  final List<SenderWalletTransaction> _transactions = [];
  String? _nextPage;
  String? _error;
  bool _refreshing = false;
  bool _showingCachedWallet = false;
  bool _paymentActionLoading = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseSenderWalletRepository();
    unawaited(_loadCachedSnapshot());
    _load();
  }

  Future<void> _loadCachedSnapshot() async {
    final key = _senderWalletCacheKey();
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final snapshot = _CachedSenderWalletSnapshot.fromMap(
        Map<String, dynamic>.from(decoded),
      );
      if (snapshot == null || !mounted) return;
      setState(() {
        _wallet = snapshot.wallet;
        _transactions
          ..clear()
          ..addAll(snapshot.transactions);
        _nextPage = snapshot.nextPageToken;
        _showingCachedWallet = true;
      });
    } catch (error) {
      debugPrint('Sender Wallet cache unavailable: $error');
    }
  }

  Future<void> _cacheSnapshot(
    SenderWalletData wallet,
    List<SenderWalletTransaction> transactions,
    String? nextPageToken,
  ) async {
    final key = _senderWalletCacheKey();
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = _CachedSenderWalletSnapshot(
        wallet: wallet,
        transactions: transactions.take(20).toList(growable: false),
        nextPageToken: nextPageToken,
        cachedAt: DateTime.now().toUtc(),
      );
      await prefs.setString(key, jsonEncode(snapshot.toMap()));
    } catch (error) {
      debugPrint('Sender Wallet cache save failed: $error');
    }
  }

  Future<void> _load() async {
    if (_refreshing) return;
    final generation = ++_loadGeneration;
    Future<T> withWalletTimeout<T>(Future<T> operation) =>
        operation.timeout(_walletOperationTimeout);

    final startedAt = DateTime.now();
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final wallet = await withWalletTimeout(_repository.initialise());
      SenderWalletPage? page;
      var methods = SenderPaymentMethodsData.empty();
      try {
        page = await withWalletTimeout(_repository.transactions());
      } catch (error) {
        debugPrint('Sender Wallet transactions unavailable: $error');
      }
      try {
        methods = await _withDeviceWalletSupport(
            await withWalletTimeout(_repository.paymentMethods()));
      } catch (error) {
        debugPrint('Sender Wallet payment methods unavailable: $error');
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _wallet = wallet;
        _paymentMethods = methods;
        if (page != null) {
          _transactions
            ..clear()
            ..addAll(page.transactions);
          _nextPage = page.nextPageToken;
        }
        _refreshing = false;
        _showingCachedWallet = false;
      });
      unawaited(_cacheSnapshot(wallet, _transactions, _nextPage));
      _walletTelemetry('fresh_load', startedAt);
      await _subscription?.cancel();
      _subscription = _repository
          .watch()
          .timeout(_walletOperationTimeout, onTimeout: (sink) => sink.close())
          .listen((value) {
        if (!mounted) return;
        setState(() {
          _wallet = value;
          _showingCachedWallet = false;
        });
        unawaited(_cacheSnapshot(value, _transactions, _nextPage));
      }, onError: (_) {});
    } on TimeoutException {
      _walletTelemetry('timeout', startedAt);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _wallet ??= const SenderWalletData(
            balance: 0,
            frozen: false,
            onboardingCompleted: true,
          );
          _error =
              "You're offline or the network is slow. Showing your most recent wallet.";
          _refreshing = false;
          _showingCachedWallet = _wallet != null;
        });
        _scheduleWalletRetry();
      }
    } catch (error) {
      _walletTelemetry('failed', startedAt, error: error);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _wallet ??= const SenderWalletData(
            balance: 0,
            frozen: false,
            onboardingCompleted: true,
          );
          _error = '$error';
          _refreshing = false;
        });
        _scheduleWalletRetry();
      }
    }
  }

  void _scheduleWalletRetry() {
    Future<void>.delayed(const Duration(seconds: 6), () {
      if (!mounted || _refreshing) return;
      unawaited(_load());
    });
  }

  void _walletTelemetry(String event, DateTime startedAt, {Object? error}) {
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    debugPrint(
      'wallet_telemetry event=$event durationMs=$elapsed cached=$_showingCachedWallet error=${error == null ? '' : error.runtimeType}',
    );
  }

  Future<void> _refreshPaymentMethods() async {
    final methods = await _withDeviceWalletSupport(
        await _repository.paymentMethods().timeout(_walletOperationTimeout));
    if (mounted) setState(() => _paymentMethods = methods);
  }

  Future<void> _addPaymentMethod() async {
    if (_paymentActionLoading) return;
    setState(() {
      _paymentActionLoading = true;
      _error = null;
    });
    try {
      final setup = await _repository
          .createSetupIntent()
          .timeout(_walletOperationTimeout);
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          merchantDisplayName: 'Circum',
          customerId: setup.customerId,
          customerEphemeralKeySecret: setup.ephemeralKeySecret,
          setupIntentClientSecret: setup.setupIntentClientSecret,
          applePay: senderPlatformSupportsApplePay(defaultTargetPlatform)
              ? const PaymentSheetApplePay(merchantCountryCode: 'GB')
              : null,
          googlePay: senderPlatformSupportsGooglePay(defaultTargetPlatform)
              ? PaymentSheetGooglePay(
                  merchantCountryCode: 'GB',
                  currencyCode: 'GBP',
                  testEnv: Env.googlePayTestEnvironment,
                )
              : null,
          style: ThemeMode.dark,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      await _refreshPaymentMethods();
      if (mounted) {
        _notice(context, 'Payment method added.');
      }
    } on StripeException catch (_) {
      if (mounted) {
        _notice(context, 'Card setup was cancelled or could not be completed.');
      }
    } on TimeoutException {
      if (mounted) _notice(context, 'Card setup timed out. Please try again.');
    } catch (_) {
      if (mounted) _notice(context, 'Card setup could not be completed.');
    } finally {
      if (mounted) setState(() => _paymentActionLoading = false);
    }
  }

  Future<void> _setDefaultPaymentMethod(String id) async {
    if (_paymentActionLoading) return;
    setState(() => _paymentActionLoading = true);
    try {
      await _repository
          .setDefaultPaymentMethod(id)
          .timeout(_walletOperationTimeout);
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
      await _repository
          .detachPaymentMethod(method.id)
          .timeout(_walletOperationTimeout);
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
            icon: Icons.account_balance_wallet_outlined,
            body:
                'Use Roth to reduce the cost of eligible Circum services. When Roth does not cover the full total, Circum can apply Roth first and charge the remainder to your chosen payment method.',
          ),
        ),
      );

  void _openEarnRoth() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SenderReferralScreen(),
          settings: const RouteSettings(name: '/sender-mobile/wallet/earn'),
        ),
      );

  // ignore: unused_element
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
          .call({'code': code})
          .timeout(_walletOperationTimeout);
      await _load();
      if (mounted) _notice(context, 'Roth Card redeemed.');
    } on FirebaseFunctionsException catch (_) {
      if (mounted) {
        _notice(context, 'This Roth Card could not be redeemed.');
      }
    } on TimeoutException {
      if (mounted) _notice(context, 'Redemption timed out. Please try again.');
    } catch (_) {
      if (mounted) _notice(context, 'This Roth Card could not be redeemed.');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_wallet == null) {
      return _WalletPageShell(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const Text(
                'Wallet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Loading your most recent wallet safely.',
                style: TextStyle(
                  color: _WalletColors.muted,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 26),
              const _WalletSkeletonCard(height: 170),
              const SizedBox(height: 20),
              const _WalletSkeletonCard(height: 120),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _WalletInlineStatus(
                  icon: Icons.cloud_off_outlined,
                  message: _walletSafeError(_error!),
                  actionLabel: 'Retry',
                  onAction: _load,
                ),
              ],
            ],
          ),
        ),
      );
    }
    final wallet = _wallet!;
    final recentTransactions = _transactions.take(5).toList(growable: false);
    return _WalletPageShell(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const Text(
              'Wallet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Manage your Roth balance, payments and rewards.',
              style: TextStyle(
                color: _WalletColors.muted,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 26),
            if (_refreshing || _showingCachedWallet || _error != null) ...[
              _WalletInlineStatus(
                icon: _error == null
                    ? Icons.sync_rounded
                    : Icons.cloud_off_outlined,
                message: _error == null
                    ? 'Updating wallet...'
                    : _walletSafeError(_error!),
                actionLabel: _error == null ? null : 'Retry',
                onAction: _error == null ? null : _load,
              ),
              const SizedBox(height: 14),
            ],
            _AvailableRothCard(wallet: wallet),
            if (wallet.frozen) ...[
              const SizedBox(height: 12),
              const _WalletGlass(
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: Color(0xFFFBBF24)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This Wallet is frozen. You can view activity, but Roth cannot be spent.',
                        style: TextStyle(color: Colors.white, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            _PaymentMethodsSection(
              sectionTitle: 'Payment Methods',
              data: _paymentMethods,
              wallet: wallet,
              busy: _paymentActionLoading,
              onAdd: _addPaymentMethod,
              onSetDefault: _setDefaultPaymentMethod,
              onRemove: _removePaymentMethod,
              onOpenMethod: _openPaymentInformation,
              onOpenRoth: _openRothInformation,
            ),
            const SizedBox(height: 20),
            _WalletActionGrid(
              onRedeem: _redeemRothCard,
              onAddCard: _addPaymentMethod,
              onManagePayments: _openManagePayments,
            ),
            const SizedBox(height: 22),
            const _WalletSectionTitle('Recent Activity'),
            const SizedBox(height: 10),
            _WalletGlass(
              padding: EdgeInsets.zero,
              child: recentTransactions.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No Roth activity yet. Rewards and eligible purchases will appear here.',
                        style:
                            TextStyle(color: _WalletColors.muted, height: 1.45),
                      ),
                    )
                  : Column(
                      children: recentTransactions
                          .map(
                            (item) => Padding(
                              padding: EdgeInsets.only(
                                left: 12,
                                right: 12,
                                top: item == recentTransactions.first ? 12 : 0,
                                bottom: 12,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => _TransactionDetailsScreen(
                                      transaction: item,
                                    ),
                                  ),
                                ),
                                child: _WalletTransactionCard(item),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _WalletActivityScreen(
                      repository: _repository,
                      initialTransactions: List.of(_transactions),
                      initialPageToken: _nextPage,
                    ),
                    settings: const RouteSettings(
                        name: '/sender-mobile/wallet/activity'),
                  ),
                ),
                child: const Text('View all activity'),
              ),
            ),
            const SizedBox(height: 10),
            const _WalletSectionTitle('Rewards & Offers'),
            const SizedBox(height: 10),
            _WalletGlass(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: _OfferRow(
                title: 'Rewards & Offers',
                detail: 'Invite friends and earn 5 Roth.',
                onTap: _openEarnRoth,
              ),
            ),
          ],
        ),
      ),
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
      final profile = await _withDeviceWalletSupport(await widget.repository
          .paymentMethods()
          .timeout(_senderWalletActionTimeout));
      var businessAccount = false;
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final owned = await FirebaseFirestore.instance
              .collection('businessAccounts')
              .where('createdByUserId', isEqualTo: user.uid)
              .limit(1)
              .get()
              .timeout(_senderWalletActionTimeout);
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
      final setup = await widget.repository
          .createSetupIntent()
          .timeout(_senderWalletActionTimeout);
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          merchantDisplayName: 'Circum',
          customerId: setup.customerId,
          customerEphemeralKeySecret: setup.ephemeralKeySecret,
          setupIntentClientSecret: setup.setupIntentClientSecret,
          applePay: senderPlatformSupportsApplePay(defaultTargetPlatform)
              ? const PaymentSheetApplePay(merchantCountryCode: 'GB')
              : null,
          googlePay: senderPlatformSupportsGooglePay(defaultTargetPlatform)
              ? PaymentSheetGooglePay(
                  merchantCountryCode: 'GB',
                  currencyCode: 'GBP',
                  testEnv: Env.googlePayTestEnvironment,
                )
              : null,
          style: ThemeMode.dark,
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      await _load();
    } on StripeException catch (_) {
      if (mounted) {
        _SenderWalletViewState._notice(
          context,
          'Card setup was cancelled or could not be completed.',
        );
      }
    } on TimeoutException {
      if (mounted) {
        _SenderWalletViewState._notice(
            context, 'Card setup timed out. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        _SenderWalletViewState._notice(
            context, 'Card setup could not be completed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setDefault(String id) async {
    setState(() => _busy = true);
    try {
      await widget.repository
          .setDefaultPaymentMethod(id)
          .timeout(_senderWalletActionTimeout);
      await _load();
    } catch (_) {
      if (mounted) {
        _SenderWalletViewState._notice(
            context, 'Could not update the default card. Please try again.');
      }
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
      await widget.repository
          .detachPaymentMethod(method.id)
          .timeout(_senderWalletActionTimeout);
      await _load();
    } catch (_) {
      if (mounted) {
        _SenderWalletViewState._notice(context,
            'Could not remove the payment method. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePreference(SenderCheckoutPreference value) async {
    setState(() => _busy = true);
    try {
      await widget.repository
          .saveCheckoutPreference(value)
          .timeout(_senderWalletActionTimeout);
      await _load();
    } catch (_) {
      if (mounted) {
        _SenderWalletViewState._notice(context,
            'Could not update checkout preferences. Please try again.');
      }
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

  Future<void> _rename(SenderPaymentMethod method) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename payment method'),
        content: Text(
          '${method.title} is securely managed by its payment provider. Custom card names are not available yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
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
                        premiumCards: true,
                        onAdd: _add,
                        onSetDefault: _setDefault,
                        onRemove: _remove,
                        onRename: _rename,
                        onOpenMethod: _openMethod,
                        onOpenRoth: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const _WalletInformationScreen(
                              title: 'Roth',
                              icon: Icons.account_balance_wallet_outlined,
                              body:
                                  'Roth can be used alone or with a card when an eligible purchase costs more than your available Roth.',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _CheckoutPreferenceSection(
                        preference: _profile!.preference,
                        profile: _profile!,
                        busy: _busy,
                        onChanged: _savePreference,
                      ),
                      const SizedBox(height: 18),
                      const _WalletSectionTitle('Split Payment'),
                      const SizedBox(height: 10),
                      _SplitPaymentPreview(
                        preference: _profile!.preference,
                        profile: _profile!,
                        wallet: widget.wallet,
                      ),
                      const SizedBox(height: 18),
                      _BusinessPaymentProfileCard(
                        connected: _businessAccount,
                        onOpenBusiness: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const BusinessView(),
                          ),
                        ),
                      ),
                    ],
                  ),
      );
}

class SenderReferralScreen extends StatefulWidget {
  const SenderReferralScreen({super.key});

  @override
  State<SenderReferralScreen> createState() => _SenderReferralScreenState();
}

class _SenderReferralScreenState extends State<SenderReferralScreen> {
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
          .call()
          .timeout(_senderWalletActionTimeout);
      final data = Map<String, dynamic>.from(result.data as Map);
      final referrals = await FirebaseFirestore.instance
          .collection('referrals')
          .where('referrerUserId', isEqualTo: user.uid)
          .limit(100)
          .get()
          .timeout(_senderWalletActionTimeout);
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
                icon: Icons.forum_outlined,
                title: 'Contact Circum Support',
                detail: 'Open an in-app conversation about payments or Roth',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RideChatPageView(
                      title: 'Circum Support',
                      supportConversation: true,
                      initialMessage: 'Hi, I need help with my wallet.',
                    ),
                    settings: RouteSettings(
                      name: '/sender-mobile/support/wallet',
                    ),
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
    try {
      final page = await widget.repository
          .transactions(pageToken: _nextPage)
          .timeout(_senderWalletActionTimeout);
      if (mounted) {
        setState(() {
          _transactions.addAll(page.transactions);
          _nextPage = page.nextPageToken;
        });
      }
    } catch (_) {
      if (mounted) {
        _SenderWalletViewState._notice(context,
            'More wallet activity could not be loaded. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
  Widget build(BuildContext context) {
    final title = _walletTransactionDisplayTitle(transaction);
    final description = _walletTransactionDisplayDescription(transaction);
    final completedDate =
        _walletTransactionDate(transaction, includeStatus: false);
    return Scaffold(
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
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                _DetailRow(
                    'Amount', '${transaction.amount.toStringAsFixed(2)} Roth'),
                _DetailRow('Status', _walletStatusLabel(transaction.status)),
                if (completedDate != null)
                  _DetailRow('Completed date', completedDate),
                _DetailRow(
                    'Reference ID',
                    transaction.referenceId.isEmpty
                        ? transaction.id
                        : transaction.referenceId),
                _DetailRow('Created by', _walletCreatedBy(transaction)),
                _DetailRow('Description', description),
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
    _loadCachedSummary();
    _repository.initialise().timeout(const Duration(seconds: 10)).then((value) {
      if (mounted) setState(() => _wallet = value);
      unawaited(_cacheSummary(value));
    }).catchError((_) {
      if (mounted && _wallet == null) setState(() => _error = 'Offline');
    });
  }

  Future<void> _loadCachedSummary() async {
    final key = _senderWalletCacheKey();
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final snapshot = _CachedSenderWalletSnapshot.fromMap(
        Map<String, dynamic>.from(decoded),
      );
      if (snapshot == null || !mounted) return;
      setState(() => _wallet = snapshot.wallet);
    } catch (_) {}
  }

  Future<void> _cacheSummary(SenderWalletData wallet) async {
    final key = _senderWalletCacheKey();
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(key);
      final existingSnapshot = existing == null
          ? null
          : _CachedSenderWalletSnapshot.fromMap(
              Map<String, dynamic>.from(jsonDecode(existing) as Map),
            );
      final snapshot = _CachedSenderWalletSnapshot(
        wallet: wallet,
        transactions: existingSnapshot?.transactions ?? const [],
        nextPageToken: existingSnapshot?.nextPageToken,
        cachedAt: DateTime.now().toUtc(),
      );
      await prefs.setString(key, jsonEncode(snapshot.toMap()));
    } catch (_) {}
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

class _WalletInlineStatus extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _WalletInlineStatus({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return _WalletGlass(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: _WalletColors.lightBlue, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: _WalletColors.muted,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 10),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _WalletSkeletonCard extends StatelessWidget {
  final double height;

  const _WalletSkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return _WalletGlass(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WalletSkeletonLine(width: 120),
            const SizedBox(height: 16),
            _WalletSkeletonLine(width: double.infinity, height: 26),
            const SizedBox(height: 12),
            _WalletSkeletonLine(width: 180),
          ],
        ),
      ),
    );
  }
}

class _WalletSkeletonLine extends StatelessWidget {
  final double width;
  final double height;

  const _WalletSkeletonLine({
    required this.width,
    this.height = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final SenderWalletTransaction transaction;
  const _TransactionRow(this.transaction);
  @override
  Widget build(BuildContext context) {
    final credit = transaction.direction == 'credit';
    final title = _walletTransactionDisplayTitle(transaction);
    final status = _walletStatusLabel(transaction.status);
    final date = _walletTransactionDate(transaction);
    final statusLine = date == null ? status : '$status · $date';
    return Semantics(
        label:
            '${credit ? 'Credit' : 'Debit'} ${transaction.amount} Roth. $title. ${transaction.status}',
        child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: _WalletColors.hairline))),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _walletStatusColor(transaction.status)
                      .withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _walletTransactionIcon(transaction.type),
                  color: _walletStatusColor(transaction.status),
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(statusLine,
                        style: TextStyle(
                            color: _walletStatusColor(transaction.status),
                            fontSize: 11,
                            fontWeight: FontWeight.w600))
                  ])),
              const SizedBox(width: 8),
              Text(
                  '${credit ? '+' : '-'}${transaction.amount.toStringAsFixed(transaction.amount % 1 == 0 ? 0 : 2)} Roth',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: _WalletColors.muted, size: 20),
            ])));
  }
}

class _PaymentMethodsSection extends StatelessWidget {
  final String sectionTitle;
  final SenderPaymentMethodsData data;
  final SenderWalletData wallet;
  final bool busy;
  final bool premiumCards;
  final VoidCallback onAdd;
  final ValueChanged<String> onSetDefault;
  final ValueChanged<SenderPaymentMethod> onRemove;
  final ValueChanged<SenderPaymentMethod>? onRename;
  final ValueChanged<SenderPaymentProfileOptionType> onOpenMethod;
  final VoidCallback onOpenRoth;

  const _PaymentMethodsSection({
    this.sectionTitle = 'Pay With',
    required this.data,
    required this.wallet,
    required this.busy,
    this.premiumCards = false,
    required this.onAdd,
    required this.onSetDefault,
    required this.onRemove,
    this.onRename,
    required this.onOpenMethod,
    required this.onOpenRoth,
  });

  @override
  Widget build(BuildContext context) {
    final options = senderOrderedPaymentOptions(
      data,
      platform: Theme.of(context).platform,
    )
        .where((option) =>
            option.type != SenderPaymentProfileOptionType.addPaymentMethod)
        .toList(growable: false);
    final cards = options
        .where((item) => item.type == SenderPaymentProfileOptionType.savedCard)
        .toList(growable: false);
    final otherMethods = options
        .where((item) => item.type != SenderPaymentProfileOptionType.savedCard)
        .toList(growable: false);

    Widget optionRow(SenderPaymentProfileOption option, int index,
            {bool premium = false}) =>
        _PaymentProfileOptionRow(
          option: option,
          busy: busy,
          premiumCard: premium,
          showDefaultBadge: option.isDefault ||
              (index == 0 &&
                  (option.type == SenderPaymentProfileOptionType.applePay ||
                      option.type == SenderPaymentProfileOptionType.googlePay)),
          onAdd: onAdd,
          onSetDefault: onSetDefault,
          onRemove: onRemove,
          onRename: onRename,
          onOpenMethod: onOpenMethod,
        );

    final standardRows = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _RothPayWithRow(wallet: wallet, onTap: onOpenRoth),
      ),
      ...options.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: optionRow(entry.value, entry.key),
            ),
          ),
      Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: optionRow(
          const SenderPaymentProfileOption(
            SenderPaymentProfileOptionType.addPaymentMethod,
          ),
          options.length,
        ),
      ),
      if (data.methods.isEmpty)
        const Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Add a card to make future Circum payments faster.',
              style: TextStyle(color: _WalletColors.muted, height: 1.4),
            ),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WalletSectionTitle(sectionTitle),
        const SizedBox(height: 10),
        if (!premiumCards)
          _WalletGlass(
            padding: const EdgeInsets.all(12),
            child: Column(children: standardRows),
          ),
        if (premiumCards) ...[
          ...cards.map((card) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: optionRow(
                  card,
                  options.indexOf(card),
                  premium: true,
                ),
              )),
          _WalletGlass(
            child: Column(
              children: [
                ...otherMethods.asMap().entries.expand((entry) => [
                      if (entry.key > 0)
                        const Divider(color: _WalletColors.hairline),
                      optionRow(entry.value, entry.key),
                    ]),
                if (otherMethods.isNotEmpty)
                  const Divider(color: _WalletColors.hairline),
                _RothPayWithRow(wallet: wallet, onTap: onOpenRoth),
                const Divider(color: _WalletColors.hairline),
                optionRow(
                  const SenderPaymentProfileOption(
                    SenderPaymentProfileOptionType.addPaymentMethod,
                  ),
                  otherMethods.length,
                ),
                if (data.methods.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Add a card to make future Circum payments faster.',
                        style: TextStyle(
                          color: _WalletColors.muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PaymentProfileOptionRow extends StatelessWidget {
  final SenderPaymentProfileOption option;
  final bool busy;
  final bool showDefaultBadge;
  final bool premiumCard;
  final VoidCallback onAdd;
  final ValueChanged<String> onSetDefault;
  final ValueChanged<SenderPaymentMethod> onRemove;
  final ValueChanged<SenderPaymentMethod>? onRename;
  final ValueChanged<SenderPaymentProfileOptionType> onOpenMethod;

  const _PaymentProfileOptionRow({
    required this.option,
    required this.busy,
    required this.showDefaultBadge,
    this.premiumCard = false,
    required this.onAdd,
    required this.onSetDefault,
    required this.onRemove,
    this.onRename,
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
    final cardRow = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Row(
        children: [
          const Icon(Icons.credit_card_rounded, color: _WalletColors.lightBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    premiumCard
                        ? (method.brand.isEmpty
                            ? 'Card'
                            : _titleCase(method.brand))
                        : method.title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  '•••• ${method.last4.isEmpty ? '----' : method.last4}',
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
              if (value == 'rename') onRename?.call(method);
              if (value == 'remove') onRemove(method);
            },
            itemBuilder: (context) => [
              if (!method.isDefault)
                const PopupMenuItem(
                    value: 'default', child: Text('Set as default')),
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        ],
      ),
    );
    if (!premiumCard) return cardRow;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label:
          '${method.title}, ${method.isDefault ? 'default payment method' : 'available payment method'}, ${method.expiry}',
      button: true,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : AppTokens.standard,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: method.isDefault ? .08 : .045),
          borderRadius: BorderRadius.circular(AppTokens.radius16),
          border: Border.all(
            color: method.isDefault
                ? _WalletColors.lightBlue.withValues(alpha: .62)
                : Colors.white.withValues(alpha: .12),
          ),
          boxShadow: method.isDefault
              ? [
                  BoxShadow(
                    color: _WalletColors.lightBlue.withValues(alpha: .14),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  method.brand.isEmpty ? 'Card' : _titleCase(method.brand),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (method.isDefault) const AppStatusBadge(label: 'Default'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '•••• ${method.last4.isEmpty ? '----' : method.last4}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  method.expiry,
                  style: const TextStyle(
                    color: _WalletColors.muted,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  enabled: !busy,
                  icon:
                      const Icon(Icons.more_horiz, color: _WalletColors.muted),
                  onSelected: (value) {
                    if (value == 'default') onSetDefault(method.id);
                    if (value == 'rename') onRename?.call(method);
                    if (value == 'remove') onRemove(method);
                  },
                  itemBuilder: (context) => [
                    if (!method.isDefault)
                      const PopupMenuItem(
                        value: 'default',
                        child: Text('Set as default'),
                      ),
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
              ],
            ),
          ],
        ),
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
        icon: Icons.account_balance_wallet_outlined,
        title: 'Roth',
        detail:
            '${wallet.balance.toStringAsFixed(wallet.balance % 1 == 0 ? 0 : 2)} available',
        onTap: onTap,
      );
}

class _WalletPageShell extends StatelessWidget {
  final Widget child;

  const _WalletPageShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return SenderPrimaryPageShell(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-.75, -.95),
          radius: 1.35,
          colors: [
            Color(0x302E7DF7),
            Color(0x180D2A59),
            Color(0xFF050913),
          ],
          stops: [0, .42, 1],
        ),
      ),
      child: child,
    );
  }
}

class _AvailableRothCard extends StatelessWidget {
  final SenderWalletData wallet;

  const _AvailableRothCard({required this.wallet});

  @override
  Widget build(BuildContext context) {
    final updated = wallet.updatedAt == null
        ? 'Updated'
        : 'Updated ${DateFormat('d MMM, HH:mm').format(wallet.updatedAt!)}';
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _WalletColors.lightBlue.withValues(alpha: .18),
            blurRadius: 34,
            spreadRadius: 1,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 238),
        padding: const EdgeInsets.fromLTRB(26, 28, 26, 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _WalletColors.lightBlue.withValues(alpha: .20),
              const Color(0xFF101A2F).withValues(alpha: .88),
              const Color(0xFF071020).withValues(alpha: .96),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .16)),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 8,
              right: -42,
              child: Transform.rotate(
                angle: -.32,
                child: Container(
                  width: 210,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: .10),
                        _WalletColors.lightBlue.withValues(alpha: .08),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 8,
              child: Text(
                'Roth',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .07),
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Available Roth',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .15),
                        ),
                      ),
                      child: Text(
                        updated,
                        style: const TextStyle(
                          color: Color(0xFFDDEBFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Semantics(
                  label: '${wallet.balance.toStringAsFixed(0)} Roth available',
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: wallet.balance),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            value.toStringAsFixed(
                              wallet.balance % 1 == 0 ? 0 : 2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 62,
                              fontWeight: FontWeight.w900,
                              height: .94,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'ROTH',
                            style: TextStyle(
                              color: _WalletColors.lightBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Use Roth to reduce the cost of eligible Circum services.',
                  style: TextStyle(
                    color: Color(0xFFD1DDF1),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletActionGrid extends StatelessWidget {
  final VoidCallback onRedeem;
  final VoidCallback onAddCard;
  final VoidCallback onManagePayments;

  const _WalletActionGrid({
    required this.onRedeem,
    required this.onAddCard,
    required this.onManagePayments,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WalletSectionTitle('Wallet Actions'),
        const SizedBox(height: 10),
        Column(
          children: [
            _WalletActionCard(
              icon: Icons.credit_card_outlined,
              title: 'Redeem Roth',
              detail: 'Apply approved Roth credit.',
              onTap: onRedeem,
            ),
            const SizedBox(height: 12),
            _WalletActionCard(
              icon: Icons.add_card_rounded,
              title: 'Add Card',
              detail: 'Save a payment card.',
              onTap: onAddCard,
            ),
            const SizedBox(height: 12),
            _WalletActionCard(
              icon: Icons.tune_rounded,
              title: 'Manage Payments',
              detail: 'Cards and checkout.',
              onTap: onManagePayments,
            ),
          ],
        ),
      ],
    );
  }
}

class _WalletActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  const _WalletActionCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _WalletGlass(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _WalletColors.lightBlue.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: .10)),
                ),
                child: Icon(icon, color: _WalletColors.lightBlue, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _WalletColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletPaymentItem extends StatelessWidget {
  final Widget child;

  const _WalletPaymentItem({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: child,
    );
  }
}

class _WalletTransactionCard extends StatelessWidget {
  final SenderWalletTransaction transaction;

  const _WalletTransactionCard(this.transaction);

  @override
  Widget build(BuildContext context) {
    final credit = transaction.direction == 'credit';
    final title = _walletTransactionDisplayTitle(transaction);
    final color = credit ? const Color(0xFF34D399) : const Color(0xFFF87171);
    final date = _walletTransactionDate(transaction);
    final amount =
        '${credit ? '+' : '-'}${transaction.amount.toStringAsFixed(transaction.amount % 1 == 0 ? 0 : 2)}';
    return Semantics(
      label:
          '${credit ? 'Credit' : 'Debit'} ${transaction.amount} Roth. $title. ${transaction.status}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                _walletTransactionIcon(transaction.type),
                color: color,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
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
                  if (date != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _WalletColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$amount Roth',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.chevron_right_rounded,
                color: _WalletColors.muted, size: 20),
          ],
        ),
      ),
    );
  }
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
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _WalletColors.lightBlue.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.local_offer_outlined,
                    color: _WalletColors.lightBlue),
              ),
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
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0B1D48),
                  minimumSize: const Size(78, 40),
                ),
                child: const Text('Invite'),
              ),
            ],
          ),
        ),
      );
}

class _CheckoutPreferenceSection extends StatelessWidget {
  final SenderCheckoutPreference preference;
  final SenderPaymentProfile profile;
  final bool busy;
  final ValueChanged<SenderCheckoutPreference> onChanged;

  const _CheckoutPreferenceSection({
    required this.preference,
    required this.profile,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final availablePreferences = [
      SenderCheckoutPreference.askEveryCheckout,
      SenderCheckoutPreference.rothFirst,
      SenderCheckoutPreference.rothThenCard,
      if (senderCheckoutPreferenceSupportedOnPlatform(
        SenderCheckoutPreference.applePayFirst,
        profile,
        platform,
      ))
        SenderCheckoutPreference.applePayFirst,
      if (senderCheckoutPreferenceSupportedOnPlatform(
        SenderCheckoutPreference.googlePayFirst,
        profile,
        platform,
      ))
        SenderCheckoutPreference.googlePayFirst,
      if (profile.methods.isNotEmpty) SenderCheckoutPreference.defaultCard,
    ];
    final effectivePreference =
        senderEffectiveCheckoutPreference(preference, profile, platform);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WalletSectionTitle('Preferred Checkout Behaviour'),
        const SizedBox(height: 10),
        _WalletGlass(
          child: Column(
            children: availablePreferences
                .map(
                  (item) => _PaymentPriorityOption(
                    preference: item,
                    selected: item == effectivePreference,
                    enabled: !busy,
                    onChanged: () => onChanged(item),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _PaymentPriorityOption extends StatelessWidget {
  final SenderCheckoutPreference preference;
  final bool selected;
  final bool enabled;
  final VoidCallback onChanged;

  const _PaymentPriorityOption({
    required this.preference,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  String get _label => switch (preference) {
        SenderCheckoutPreference.askEveryCheckout => 'Ask every checkout',
        SenderCheckoutPreference.rothFirst => 'Use Roth first',
        SenderCheckoutPreference.rothThenCard => 'Use Roth then card',
        SenderCheckoutPreference.applePayFirst => 'Use Apple Pay first',
        SenderCheckoutPreference.googlePayFirst => 'Use Google Pay first',
        SenderCheckoutPreference.defaultCard => 'Use saved card first',
      };

  String? get _detail => switch (preference) {
        SenderCheckoutPreference.rothThenCard =>
          'Apply Roth, then charge the remainder automatically.',
        SenderCheckoutPreference.askEveryCheckout =>
          'Choose how to pay when you check out.',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label:
          '$_label, ${selected ? 'selected' : 'not selected'}, ${enabled ? 'available' : 'updating'}',
      inMutuallyExclusiveGroup: true,
      selected: selected,
      child: InkWell(
        onTap: enabled ? onChanged : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : AppTokens.fast,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? _WalletColors.lightBlue.withValues(alpha: .11)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? _WalletColors.lightBlue : _WalletColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    if (_detail != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        _detail!,
                        style: const TextStyle(
                          color: _WalletColors.muted,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitPaymentPreview extends StatelessWidget {
  final SenderCheckoutPreference preference;
  final SenderPaymentProfile profile;
  final SenderWalletData wallet;

  const _SplitPaymentPreview({
    required this.preference,
    required this.profile,
    required this.wallet,
  });

  String _paymentLabel(BuildContext context) {
    final effectivePreference = senderEffectiveCheckoutPreference(
      preference,
      profile,
      Theme.of(context).platform,
    );
    return switch (effectivePreference) {
      SenderCheckoutPreference.applePayFirst => 'Apple Pay',
      SenderCheckoutPreference.googlePayFirst => 'Google Pay',
      SenderCheckoutPreference.defaultCard => 'Saved Card',
      SenderCheckoutPreference.askEveryCheckout => 'Choose at checkout',
      _ => profile.methods.isNotEmpty ? 'Saved Card' : 'Payment Method',
    };
  }

  bool get _usesRoth =>
      preference == SenderCheckoutPreference.rothFirst ||
      preference == SenderCheckoutPreference.rothThenCard;

  @override
  Widget build(BuildContext context) {
    const total = 58.50;
    final paymentLabel = _paymentLabel(context);
    final rothAmount = _usesRoth ? wallet.balance.clamp(0, 40.0) : 0.0;
    final remaining = (total - rothAmount).clamp(0, total);
    return _WalletGlass(
      child: Semantics(
        label:
            'Split payment visual example. Delivery total £58.50. ${_usesRoth ? 'Roth ${rothAmount.toStringAsFixed(2)}. $paymentLabel £${remaining.toStringAsFixed(2)}.' : '$paymentLabel £58.50.'}',
        child: Column(
          children: [
            _PaymentBreakdownRow(label: 'Delivery Total', value: '£58.50'),
            const _PaymentBreakdownArrow(),
            if (_usesRoth) ...[
              _PaymentBreakdownRow(
                label: 'Roth',
                value: '−${rothAmount.toStringAsFixed(2)} Roth',
                accent: _WalletColors.lightBlue,
              ),
              const _PaymentBreakdownArrow(),
            ],
            _PaymentBreakdownRow(
              label: paymentLabel,
              value: '£${remaining.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 12),
            const Text(
              'Remaining charged automatically',
              style: TextStyle(
                color: _WalletColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentBreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  const _PaymentBreakdownRow({
    required this.label,
    required this.value,
    this.accent,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: accent ?? Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );
}

class _PaymentBreakdownArrow extends StatelessWidget {
  const _PaymentBreakdownArrow();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 7),
        child: Icon(
          Icons.south_rounded,
          size: 18,
          color: _WalletColors.muted,
        ),
      );
}

class _BusinessPaymentProfileCard extends StatelessWidget {
  final bool connected;
  final VoidCallback onOpenBusiness;

  const _BusinessPaymentProfileCard({
    required this.connected,
    required this.onOpenBusiness,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _WalletSectionTitle('Business Payment Profile'),
          const SizedBox(height: 10),
          _WalletGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      connected
                          ? Icons.verified_outlined
                          : Icons.business_outlined,
                      color: connected
                          ? const Color(0xFF34D399)
                          : _WalletColors.muted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        connected
                            ? 'Connected'
                            : 'No Business payment profile connected.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  connected
                      ? 'Business Finance uses your approved payment profile during authorised Business checkouts.'
                      : 'Create or join a Circum Business account to manage authorised Business payments.',
                  style: const TextStyle(
                    color: _WalletColors.muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: onOpenBusiness,
                  icon: Icon(connected
                      ? Icons.arrow_forward_rounded
                      : Icons.add_business_outlined),
                  label: Text(connected
                      ? 'Manage Business Payments'
                      : 'Create Business Account'),
                ),
              ],
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

  const _WalletLink({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => _WalletPaymentItem(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 62),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _WalletColors.lightBlue.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: _WalletColors.lightBlue, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
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
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _WalletColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: _WalletColors.muted),
                ],
              ),
            ),
          ),
        ),
      );
}

class _WalletSectionTitle extends StatelessWidget {
  final String value;
  const _WalletSectionTitle(this.value);
  @override
  Widget build(BuildContext context) => Text(value,
      style: const TextStyle(
          color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800));
}

class _WalletGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _WalletGlass(
      {required this.child, this.padding = const EdgeInsets.all(14)});
  @override
  Widget build(BuildContext context) => AppGlassContainer(
        padding: padding,
        accent: AppTokens.primaryLight,
        highContrast:
            SenderAccessibilityScope.maybeOf(context)?.settings.highContrast ??
                false,
        child: child,
      );
}

class _WalletColors {
  static const lightBlue = Color(0xFF60A5FA);
  static const muted = Color(0xFF9CA3AF);
  static const hairline = Color(0x14F5F7FB);
}

String _walletSafeError(String error) {
  final lower = error.toLowerCase();
  if (lower.contains('permission') || lower.contains('denied')) {
    return 'Wallet access is unavailable for this account right now.';
  }
  if (lower.contains('network') ||
      lower.contains('offline') ||
      lower.contains('timeout') ||
      lower.contains('unavailable')) {
    return "You're offline. Showing your most recent wallet.";
  }
  if (lower.contains('sign in')) {
    return 'Sign in again to refresh your wallet.';
  }
  return 'Wallet refresh failed. Your Roth is safe and you can retry.';
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

String _titleCase(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Card';
  return '${trimmed[0].toUpperCase()}${trimmed.substring(1).toLowerCase()}';
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

String? _walletTransactionDate(
  SenderWalletTransaction transaction, {
  bool includeStatus = true,
}) {
  final status = _walletStatusLabel(transaction.status);
  final date = transaction.completedAt ?? transaction.createdAt;
  if (status == 'Pending') {
    if (date != null) {
      final dateLabel = _walletFriendlyDate(date);
      return includeStatus ? '$status • $dateLabel' : dateLabel;
    }
    return includeStatus
        ? 'Pending • Estimated completion'
        : 'Estimated completion';
  }
  if (date == null) return null;
  final dateLabel = _walletFriendlyDate(date);
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
  if (type.contains('admin')) return Icons.auto_awesome_rounded;
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

bool _walletTransactionIssuedByCircum(String value) {
  final type = value.toLowerCase();
  return type == 'admin_credit' ||
      type == 'admin_issue' ||
      type == 'admin_adjustment' ||
      type == 'manual_credit' ||
      type.contains('admin_credit') ||
      type.contains('manual_credit');
}

String _walletTransactionDisplayTitle(SenderWalletTransaction transaction) {
  return _walletTransactionIssuedByCircum(transaction.type)
      ? 'Issued by Circum'
      : transaction.description;
}

String _walletTransactionDisplayDescription(
    SenderWalletTransaction transaction) {
  return _walletTransactionIssuedByCircum(transaction.type)
      ? 'This Roth has been added to your account by the Circum team.'
      : transaction.description;
}

String _walletCategory(String value) {
  final type = value.toLowerCase();
  if (_walletTransactionIssuedByCircum(value)) return 'Issued by Circum';
  if (type.contains('gift_card') || type.contains('roth_card')) {
    return 'Gift card redemption';
  }
  if (type.contains('gift')) return 'Gift purchase';
  if (type.contains('health')) return 'Health+';
  if (type.contains('business')) return 'Business';
  if (type.contains('referral')) return 'Referral reward';
  if (type.contains('refund')) return 'Refund';
  if (type.contains('adjust') || type.contains('reversal')) return 'Adjustment';
  if (type.contains('delivery') ||
      type.contains('checkout') ||
      type.contains('spend')) {
    return 'Delivery payment';
  }
  return value.replaceAll('_', ' ');
}

String _walletCreatedBy(SenderWalletTransaction transaction) {
  final creator = transaction.createdBy.trim().toLowerCase();
  final type = transaction.type.toLowerCase();
  if (type.contains('referral')) return 'Referral Engine';
  if (_walletTransactionIssuedByCircum(type)) return 'Circum';
  if (creator == 'system' || creator.isEmpty) return 'System';
  final source = transaction.source.toLowerCase();
  if (creator == 'user' ||
      source.contains('sender_wallet') ||
      source.contains('checkout')) {
    return 'User';
  }
  return 'Admin';
}
