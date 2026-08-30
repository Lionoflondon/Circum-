import 'dart:async';
import 'dart:io';

import 'package:circum/app/sender_mobile/sender_mobile_profile.dart';
import 'package:circum/app/sender_mobile/sender_profile_authority.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProfileRepository implements SenderMobileProfileRepository {
  SenderMobileProfileData profile;
  late final StreamController<SenderMobileProfileData> _controller;
  int activeWatchers = 0;
  int maxActiveWatchers = 0;

  _FakeProfileRepository(this.profile) {
    _controller = StreamController<SenderMobileProfileData>.broadcast(
      onListen: () {
        activeWatchers += 1;
        if (activeWatchers > maxActiveWatchers) {
          maxActiveWatchers = activeWatchers;
        }
      },
      onCancel: () {
        activeWatchers -= 1;
      },
    );
  }

  @override
  Future<SenderMobileProfileData> load() async => profile;

  @override
  Future<void> logout() async {}

  @override
  Future<SenderMobileProfileData> save({
    required String displayName,
    required String username,
    required String phone,
  }) async {
    profile = SenderMobileProfileData(
      userId: profile.userId,
      displayName: displayName,
      username: username,
      email: profile.email,
      phone: phone,
      photoUrl: profile.photoUrl,
      createdAt: profile.createdAt,
      trustScore: profile.trustScore,
      hasTrustScore: profile.hasTrustScore,
      trustTier: profile.trustTier,
      nextTier: profile.nextTier,
      pointsToNextTier: profile.pointsToNextTier,
      completedDeliveries: profile.completedDeliveries,
      hasCompletedDeliveries: profile.hasCompletedDeliveries,
      trustHistory: profile.trustHistory,
    );
    _controller.add(profile);
    return profile;
  }

  @override
  Future<SenderMobileProfileData> uploadPhoto(SenderProfilePhoto photo) async =>
      profile;

  @override
  Stream<SenderMobileProfileData> watch() => _controller.stream;

  Future<void> dispose() => _controller.close();
}

class _FailingProfileRepository implements SenderMobileProfileRepository {
  const _FailingProfileRepository();

  @override
  Future<SenderMobileProfileData> load() {
    throw SenderProfileAuthorityException(
      code: SenderProfileDiagnosticCode.authUnavailable,
      message: 'Sign in again to load your profile.',
      phase: 'test.auth',
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<SenderMobileProfileData> save({
    required String displayName,
    required String username,
    required String phone,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SenderMobileProfileData> uploadPhoto(SenderProfilePhoto photo) {
    throw UnimplementedError();
  }

  @override
  Stream<SenderMobileProfileData> watch() => const Stream.empty();
}

void main() {
  testWidgets('Sender profile shows username empty state and no trust activity',
      (tester) async {
    final repository = _FakeProfileRepository(
      SenderMobileProfileData(
        userId: 'sender-1',
        displayName: 'Jason Sender',
        email: 'jason@circum.app',
        phone: '+44 7700 900123',
        photoUrl: '',
        createdAt: DateTime(2026, 7, 15),
        trustScore: 82,
        trustTier: 'trusted',
        pointsToNextTier: 18,
        completedDeliveries: 12,
      ),
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SenderMobileProfileView(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jason Sender'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('Create Username'), findsOneWidget);
    expect(find.text('jason@circum.app'), findsOneWidget);
    expect(find.text('Circum Account'), findsOneWidget);
    expect(find.text('15 Jul 2026'), findsAtLeastNWidgets(1));
    expect(find.text('No recent trust activity.'), findsOneWidget);
    expect(find.text('Account trust baseline established'), findsNothing);
  });

  testWidgets('Sender profile displays backend username and trust activity',
      (tester) async {
    final repository = _FakeProfileRepository(
      SenderMobileProfileData(
        userId: 'sender-1',
        displayName: 'Jason Sender',
        username: 'jason',
        email: 'jason@circum.app',
        phone: '+44 7700 900123',
        photoUrl: '',
        createdAt: DateTime(2026, 7, 15),
        trustScore: 125,
        trustTier: 'priority',
        completedDeliveries: 21,
        trustHistory: [
          SenderTrustActivity(
            points: 5,
            label: 'Completed Delivery',
            occurredAt: DateTime(2026, 7, 16),
          ),
        ],
      ),
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SenderMobileProfileView(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('@jason'), findsOneWidget);
    expect(find.text('Create Username'), findsNothing);
    expect(find.text('Completed Delivery'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
  });

  testWidgets('Sender profile shows recoverable sign-in message',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SenderMobileProfileView(
            repository: _FailingProfileRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profile needs attention'), findsOneWidget);
    expect(find.text('Sign in again to load your profile.'), findsOneWidget);
    expect(find.text('We could not load your profile. Check your connection.'),
        findsNothing);
  });

  test('Sender profile diagnostics expose precise internal failure codes', () {
    final source = File('lib/app/sender_mobile/sender_profile_authority.dart')
        .readAsStringSync();

    expect(source, contains('PROFILE_NOT_FOUND'));
    expect(source, contains('PROFILE_PERMISSION_DENIED'));
    expect(source, contains('PROFILE_UID_MISMATCH'));
    expect(source, contains('PROFILE_SCHEMA_MISMATCH'));
    expect(source, contains('PROFILE_STARTUP_RACE'));
    expect(source, contains('PROFILE_REPOSITORY_FAILURE'));
    expect(source, contains('SenderProfileAuthority'));
    expect(source, isNot(contains("'Profile unavailable'")));
  });

  test('Sender profile authority reads before repairing missing profiles', () {
    final source = File('lib/app/sender_mobile/sender_profile_authority.dart')
        .readAsStringSync();
    final loadMethod = source.substring(
      source.indexOf('Future<SenderProfileAuthoritySnapshot> load'),
      source.indexOf('Stream<SenderProfileAuthoritySnapshot> watch'),
    );
    final repairMethod = source.substring(
      source.indexOf('Future<DocumentSnapshot<Map<String, dynamic>>> '
          'readCanonicalProfileWithRepair'),
      source.indexOf('Future<DocumentSnapshot<Map<String, dynamic>>> '
          'readCanonicalProfile('),
    );

    expect(loadMethod, contains('readCanonicalProfileWithRepair'));
    expect(loadMethod, isNot(contains('ensureCanonicalSenderAccount')));
    expect(
      repairMethod.indexOf('readCanonicalProfile(user, readPhase)'),
      lessThan(repairMethod.indexOf('ensureCanonicalSenderAccount')),
      reason:
          'Existing users/{uid} documents must not be hidden behind the ensure '
          'callable. Ensure is only allowed after a confirmed missing profile.',
    );
    expect(repairMethod, contains('SenderProfileDiagnosticCode.notFound'));
  });

  test('Sender profile lifecycle instrumentation covers every boundary', () {
    final authority =
        File('lib/app/sender_mobile/sender_profile_authority.dart')
            .readAsStringSync();
    final profile = File('lib/app/sender_mobile/sender_mobile_profile.dart')
        .readAsStringSync();
    final source = '$authority\n$profile';

    for (final marker in [
      'auth_restore_begin',
      'firestore_read_begin',
      'firestore_read_complete',
      'profile_missing_begin_ensure',
      'ensure_begin',
      'ensure_complete',
      'listener_attach',
      'snapshot exists=',
      'cache_hit',
      'cache_hit uid_verified',
      'cache_uid_mismatch',
      'cache_miss',
      'cache_boot_ignored_profile_already_loaded',
      'cache_write_complete',
      'repository_load_complete',
      'repository_load_error',
      'build loading=',
      'dispose listenerAttached=',
    ]) {
      expect(source, contains(marker));
    }
  });

  test('Sender profile authority is the only users/{uid} reader in Sender tabs',
      () {
    final root = Directory('lib/app/sender_mobile');
    final offenders = <String>[];
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('sender_profile_authority.dart')) continue;
      final source = file.readAsStringSync();
      if (source.contains("collection('users').doc(user.uid)") ||
          source.contains('collection("users").doc(user.uid)') ||
          source.contains("collection('users').doc(uid)") ||
          source.contains('collection("users").doc(uid)')) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty);
  });

  test('Sender profile cache cannot replace authenticated UID', () {
    final source = File('lib/app/sender_mobile/sender_mobile_profile.dart')
        .readAsStringSync();
    final cacheMethod = source.substring(
      source.indexOf('Future<SenderMobileProfileData?> _loadCachedProfile'),
      source.indexOf('Future<void> _cacheProfile'),
    );

    expect(cacheMethod,
        contains('final currentUid = _safeSenderProfileCurrentUid();'));
    expect(cacheMethod, contains('profile.userId != currentUid'));
    expect(cacheMethod, contains('cache_uid_mismatch'));
    expect(
      cacheMethod.indexOf('SenderMobileProfileData.fromCache'),
      lessThan(cacheMethod.indexOf('profile.userId != currentUid')),
      reason: 'Decoded cache must be revalidated before becoming visible.',
    );
    expect(
      cacheMethod.indexOf('profile.userId != currentUid'),
      lessThan(cacheMethod.indexOf('return profile;')),
      reason:
          'A cached profile must not be returned until UID ownership is proven.',
    );
  });

  testWidgets('Sender profile survives 100 open and dispose cycles',
      (tester) async {
    final repository = _FakeProfileRepository(
      SenderMobileProfileData(
        userId: 'sender-1',
        displayName: 'Jason Sender',
        username: 'jason',
        email: 'jason@circum.app',
        phone: '+44 7700 900123',
        photoUrl: '',
        createdAt: DateTime(2026, 7, 15),
      ),
    );
    addTearDown(repository.dispose);

    for (var cycle = 0; cycle < 100; cycle += 1) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SenderMobileProfileView(repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jason Sender'), findsOneWidget);
      expect(repository.maxActiveWatchers, lessThanOrEqualTo(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(repository.activeWatchers, 0);
    }
  });
}
