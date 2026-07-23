import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

enum SenderCheckoutPreference {
  applePayFirst,
  googlePayFirst,
  defaultCard,
  rothFirst,
  rothThenCard,
  askEveryCheckout,
}

String senderCheckoutPreferenceValue(SenderCheckoutPreference value) {
  switch (value) {
    case SenderCheckoutPreference.applePayFirst:
      return 'apple_pay_first';
    case SenderCheckoutPreference.googlePayFirst:
      return 'google_pay_first';
    case SenderCheckoutPreference.defaultCard:
      return 'default_card';
    case SenderCheckoutPreference.rothFirst:
      return 'roth_first';
    case SenderCheckoutPreference.rothThenCard:
      return 'roth_then_card';
    case SenderCheckoutPreference.askEveryCheckout:
      return 'ask_every_checkout';
  }
}

SenderCheckoutPreference senderCheckoutPreferenceFromValue(String value) {
  switch (value) {
    case 'apple_pay_first':
      return SenderCheckoutPreference.applePayFirst;
    case 'google_pay_first':
      return SenderCheckoutPreference.googlePayFirst;
    case 'default_card':
      return SenderCheckoutPreference.defaultCard;
    case 'roth_first':
      return SenderCheckoutPreference.rothFirst;
    case 'roth_then_card':
      return SenderCheckoutPreference.rothThenCard;
    default:
      return SenderCheckoutPreference.askEveryCheckout;
  }
}

String senderCheckoutPreferenceLabel(SenderCheckoutPreference value) {
  switch (value) {
    case SenderCheckoutPreference.applePayFirst:
      return 'Apple Pay first';
    case SenderCheckoutPreference.googlePayFirst:
      return 'Google Pay first';
    case SenderCheckoutPreference.defaultCard:
      return 'Default card';
    case SenderCheckoutPreference.rothFirst:
      return 'Roth first';
    case SenderCheckoutPreference.rothThenCard:
      return 'Roth then card';
    case SenderCheckoutPreference.askEveryCheckout:
      return 'Ask every checkout';
  }
}

bool senderPlatformSupportsApplePay(TargetPlatform platform) =>
    !kIsWeb && platform == TargetPlatform.iOS;

bool senderPlatformSupportsGooglePay(TargetPlatform platform) =>
    !kIsWeb && platform == TargetPlatform.android;

bool senderPaymentOptionSupportedOnPlatform(
  SenderPaymentProfileOptionType type,
  TargetPlatform platform,
) {
  switch (type) {
    case SenderPaymentProfileOptionType.applePay:
      return senderPlatformSupportsApplePay(platform);
    case SenderPaymentProfileOptionType.googlePay:
      return senderPlatformSupportsGooglePay(platform);
    case SenderPaymentProfileOptionType.savedCard:
    case SenderPaymentProfileOptionType.addPaymentMethod:
      return true;
  }
}

bool senderCheckoutPreferenceSupportedOnPlatform(
  SenderCheckoutPreference preference,
  SenderPaymentProfile profile,
  TargetPlatform platform,
) {
  switch (preference) {
    case SenderCheckoutPreference.applePayFirst:
      return profile.applePaySupported &&
          senderPlatformSupportsApplePay(platform);
    case SenderCheckoutPreference.googlePayFirst:
      return profile.googlePaySupported &&
          senderPlatformSupportsGooglePay(platform);
    case SenderCheckoutPreference.defaultCard:
      return profile.methods.isNotEmpty;
    case SenderCheckoutPreference.rothFirst:
    case SenderCheckoutPreference.rothThenCard:
    case SenderCheckoutPreference.askEveryCheckout:
      return true;
  }
}

SenderCheckoutPreference senderEffectiveCheckoutPreference(
  SenderCheckoutPreference preference,
  SenderPaymentProfile profile,
  TargetPlatform platform,
) {
  if (senderCheckoutPreferenceSupportedOnPlatform(
    preference,
    profile,
    platform,
  )) {
    return preference;
  }
  if (profile.methods.isNotEmpty) return SenderCheckoutPreference.defaultCard;
  return SenderCheckoutPreference.askEveryCheckout;
}

class SenderPaymentMethod {
  final String id;
  final String brand;
  final String last4;
  final int? expMonth;
  final int? expYear;
  final bool isDefault;

  const SenderPaymentMethod({
    required this.id,
    required this.brand,
    required this.last4,
    this.expMonth,
    this.expYear,
    this.isDefault = false,
  });

  factory SenderPaymentMethod.fromMap(Map<String, dynamic> map) {
    return SenderPaymentMethod(
      id: '${map['id'] ?? ''}',
      brand: '${map['brand'] ?? 'card'}',
      last4: '${map['last4'] ?? ''}',
      expMonth: (map['expMonth'] as num?)?.toInt(),
      expYear: (map['expYear'] as num?)?.toInt(),
      isDefault: map['isDefault'] == true,
    );
  }

  String get title =>
      '${brand.isEmpty ? 'Card' : brand[0].toUpperCase() + brand.substring(1)}${last4.isEmpty ? '' : ' •••• $last4'}';

  String get expiry {
    if (expMonth == null || expYear == null) return 'Expiry unavailable';
    return 'Expires ${expMonth.toString().padLeft(2, '0')}/$expYear';
  }
}

class SenderPaymentProfile {
  final List<SenderPaymentMethod> methods;
  final SenderCheckoutPreference preference;
  final String? defaultPaymentMethodId;
  final bool applePaySupported;
  final bool googlePaySupported;

  const SenderPaymentProfile({
    required this.methods,
    required this.preference,
    this.defaultPaymentMethodId,
    this.applePaySupported = true,
    this.googlePaySupported = true,
  });

  factory SenderPaymentProfile.empty() => const SenderPaymentProfile(
    methods: [],
    preference: SenderCheckoutPreference.askEveryCheckout,
  );

  factory SenderPaymentProfile.fromMap(Map<String, dynamic> map) {
    return SenderPaymentProfile(
      methods: (map['paymentMethods'] as List? ?? const [])
          .map(
            (item) => SenderPaymentMethod.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      preference: senderCheckoutPreferenceFromValue(
        '${map['preference'] ?? ''}',
      ),
      defaultPaymentMethodId: map['defaultPaymentMethodId'] as String?,
      applePaySupported: map['applePaySupported'] != false,
      googlePaySupported: map['googlePaySupported'] != false,
    );
  }
}

typedef SenderPaymentMethodsData = SenderPaymentProfile;

enum SenderPaymentProfileOptionType {
  applePay,
  googlePay,
  savedCard,
  addPaymentMethod,
}

class SenderPaymentProfileOption {
  final SenderPaymentProfileOptionType type;
  final SenderPaymentMethod? method;

  const SenderPaymentProfileOption(this.type, {this.method});

  String get title {
    switch (type) {
      case SenderPaymentProfileOptionType.applePay:
        return 'Apple Pay';
      case SenderPaymentProfileOptionType.googlePay:
        return 'Google Pay';
      case SenderPaymentProfileOptionType.savedCard:
        return method?.title ?? 'Saved card';
      case SenderPaymentProfileOptionType.addPaymentMethod:
        return '+ Add Payment Method';
    }
  }

  bool get isDefault => method?.isDefault == true;
}

List<SenderPaymentProfileOption> senderOrderedPaymentOptions(
  SenderPaymentProfile profile, {
  TargetPlatform? platform,
  bool includeAddMethod = true,
}) {
  final target = platform ?? defaultTargetPlatform;
  final saved = profile.methods
      .map(
        (method) => SenderPaymentProfileOption(
          SenderPaymentProfileOptionType.savedCard,
          method: method,
        ),
      )
      .toList(growable: false);
  final defaultCards = saved.where((item) => item.isDefault).toList();
  final otherCards = saved.where((item) => !item.isDefault).toList();
  final apple =
      profile.applePaySupported && senderPlatformSupportsApplePay(target)
      ? const SenderPaymentProfileOption(
          SenderPaymentProfileOptionType.applePay,
        )
      : null;
  final google =
      profile.googlePaySupported && senderPlatformSupportsGooglePay(target)
      ? const SenderPaymentProfileOption(
          SenderPaymentProfileOptionType.googlePay,
        )
      : null;
  final ordered = <SenderPaymentProfileOption>[];
  if (target == TargetPlatform.iOS) {
    if (apple != null) ordered.add(apple);
    ordered.addAll(defaultCards);
    ordered.addAll(otherCards);
  } else if (target == TargetPlatform.android) {
    if (google != null) ordered.add(google);
    ordered.addAll(defaultCards);
    ordered.addAll(otherCards);
  } else {
    ordered.addAll(defaultCards);
    ordered.addAll(otherCards);
  }
  if (includeAddMethod) {
    ordered.add(
      const SenderPaymentProfileOption(
        SenderPaymentProfileOptionType.addPaymentMethod,
      ),
    );
  }
  return ordered;
}

class SenderSetupIntentData {
  final String customerId;
  final String ephemeralKeySecret;
  final String setupIntentClientSecret;

  const SenderSetupIntentData({
    required this.customerId,
    required this.ephemeralKeySecret,
    required this.setupIntentClientSecret,
  });

  factory SenderSetupIntentData.fromMap(Map<String, dynamic> map) {
    return SenderSetupIntentData(
      customerId: '${map['customerId'] ?? ''}',
      ephemeralKeySecret: '${map['ephemeralKeySecret'] ?? ''}',
      setupIntentClientSecret: '${map['setupIntentClientSecret'] ?? ''}',
    );
  }
}

abstract class SenderPaymentProfileRepository {
  Future<SenderPaymentProfile> paymentMethods();
  Future<SenderSetupIntentData> createSetupIntent();
  Future<void> detachPaymentMethod(String paymentMethodId);
  Future<void> setDefaultPaymentMethod(String paymentMethodId);
  Future<void> saveCheckoutPreference(SenderCheckoutPreference preference);
}

class FirebaseSenderPaymentProfileRepository
    implements SenderPaymentProfileRepository {
  final FirebaseFunctions functions;

  FirebaseSenderPaymentProfileRepository({FirebaseFunctions? functions})
    : functions = functions ?? FirebaseFunctions.instance;

  @override
  Future<SenderPaymentProfile> paymentMethods() async {
    final result = await functions
        .httpsCallable('listSenderPaymentMethods')
        .call();
    return SenderPaymentProfile.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  @override
  Future<SenderSetupIntentData> createSetupIntent() async {
    final result = await functions
        .httpsCallable('createSenderSetupIntent')
        .call();
    return SenderSetupIntentData.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  @override
  Future<void> detachPaymentMethod(String paymentMethodId) async {
    await functions.httpsCallable('detachSenderPaymentMethod').call({
      'paymentMethodId': paymentMethodId,
    });
  }

  @override
  Future<void> setDefaultPaymentMethod(String paymentMethodId) async {
    await functions.httpsCallable('setDefaultSenderPaymentMethod').call({
      'paymentMethodId': paymentMethodId,
    });
  }

  @override
  Future<void> saveCheckoutPreference(
    SenderCheckoutPreference preference,
  ) async {
    await functions.httpsCallable('saveSenderCheckoutPreference').call({
      'preference': senderCheckoutPreferenceValue(preference),
    });
  }
}
