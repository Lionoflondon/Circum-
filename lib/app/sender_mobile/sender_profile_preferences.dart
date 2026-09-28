import 'package:firebase_auth/firebase_auth.dart';

import 'account_bootstrap_api.dart';
import 'sender_profile_authority.dart';

class SenderNotificationPreferences {
  final bool deliveryUpdates;
  final bool accountAlerts;
  final bool marketing;

  const SenderNotificationPreferences({
    this.deliveryUpdates = true,
    this.accountAlerts = true,
    this.marketing = false,
  });

  factory SenderNotificationPreferences.fromMap(Map<String, dynamic>? raw) {
    final data = raw ?? const <String, dynamic>{};
    return SenderNotificationPreferences(
      deliveryUpdates: data['deliveryUpdates'] != false,
      accountAlerts: data['accountAlerts'] != false,
      marketing: data['marketing'] == true,
    );
  }

  Map<String, bool> toMap() => {
        'deliveryUpdates': deliveryUpdates,
        'accountAlerts': accountAlerts,
        'marketing': marketing,
      };

  SenderNotificationPreferences copyWith({
    bool? deliveryUpdates,
    bool? accountAlerts,
    bool? marketing,
  }) {
    return SenderNotificationPreferences(
      deliveryUpdates: deliveryUpdates ?? this.deliveryUpdates,
      accountAlerts: accountAlerts ?? this.accountAlerts,
      marketing: marketing ?? this.marketing,
    );
  }
}

class SenderProfilePreferences {
  final String language;
  final String timeFormat;
  final SenderNotificationPreferences notifications;

  const SenderProfilePreferences({
    this.language = 'en',
    this.timeFormat = 'automatic',
    this.notifications = const SenderNotificationPreferences(),
  });

  factory SenderProfilePreferences.fromMap(Map<String, dynamic>? raw) {
    final data = raw ?? const <String, dynamic>{};
    final notificationData = data['notificationPreferences'];
    return SenderProfilePreferences(
      language: _language(data['language']),
      timeFormat: _timeFormat(data['timeFormat']),
      notifications: SenderNotificationPreferences.fromMap(
        notificationData is Map
            ? Map<String, dynamic>.from(notificationData)
            : null,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'language': language,
        'timeFormat': timeFormat,
        'notificationPreferences': notifications.toMap(),
      };

  SenderProfilePreferences copyWith({
    String? language,
    String? timeFormat,
    SenderNotificationPreferences? notifications,
  }) {
    return SenderProfilePreferences(
      language: language ?? this.language,
      timeFormat: timeFormat ?? this.timeFormat,
      notifications: notifications ?? this.notifications,
    );
  }

  static String _language(Object? value) =>
      value == 'device_default' ? 'device_default' : 'en';

  static String _timeFormat(Object? value) =>
      const {'automatic', '12_hour', '24_hour'}.contains(value)
          ? '$value'
          : 'automatic';
}

abstract class SenderProfilePreferencesRepository {
  Future<SenderProfilePreferences> load();
  Future<SenderProfilePreferences> save(SenderProfilePreferences value);
}

class FirebaseSenderProfilePreferencesRepository
    implements SenderProfilePreferencesRepository {
  final FirebaseAuth auth;
  final SenderProfileAuthority profileAuthority;

  FirebaseSenderProfilePreferencesRepository({
    FirebaseAuth? auth,
    SenderProfileAuthority? profileAuthority,
  })  : auth = auth ?? FirebaseAuth.instance,
        profileAuthority =
            profileAuthority ?? SenderProfileAuthority(auth: auth);

  @override
  Future<SenderProfilePreferences> load() async {
    final snapshot = await profileAuthority.load('profile.preferences.load');
    return SenderProfilePreferences.fromMap(
      snapshot.data['preferences'] as Map<String, dynamic>?,
    );
  }

  @override
  Future<SenderProfilePreferences> save(SenderProfilePreferences value) async {
    final result = await callAccountBootstrap(
            'updateSenderPreferences',
            {
              'language': value.language,
              'timeFormat': value.timeFormat,
              'notificationPreferences': value.notifications.toMap(),
            },
            auth: auth)
        .timeout(SenderProfileAuthority.senderAccountEnsureTimeout);
    final data = result;
    if (data['preferences'] is Map) {
      return SenderProfilePreferences.fromMap(
        Map<String, dynamic>.from(data['preferences'] as Map),
      );
    }
    final user = await profileAuthority.requireRestoredUser(
      'profile.preferences.save.read',
    );
    final snapshot = await profileAuthority.readCanonicalProfile(
      user,
      'profile.preferences.save.read',
    );
    return SenderProfilePreferences.fromMap(
      snapshot.data()?['preferences'] as Map<String, dynamic>?,
    );
  }
}
