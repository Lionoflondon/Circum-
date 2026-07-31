import 'dart:async';
import 'dart:io';

import 'package:circum/app/sender_mobile/sender_mobile_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProfileRepository implements SenderMobileProfileRepository {
  SenderMobileProfileData profile;
  final _controller = StreamController<SenderMobileProfileData>.broadcast();

  _FakeProfileRepository(this.profile);

  @override
  Future<void> closeAccount() async {}

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
  Future<void> closeAccount() async {}

  @override
  Future<SenderMobileProfileData> load() {
    throw SenderMobileProfileException(
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
    final source = File('lib/app/sender_mobile/sender_mobile_profile.dart')
        .readAsStringSync();

    expect(source, contains('PROFILE_NOT_FOUND'));
    expect(source, contains('PROFILE_PERMISSION_DENIED'));
    expect(source, contains('PROFILE_UID_MISMATCH'));
    expect(source, contains('PROFILE_SCHEMA_MISMATCH'));
    expect(source, contains('PROFILE_STARTUP_RACE'));
    expect(source, contains('PROFILE_REPOSITORY_FAILURE'));
    expect(source, contains("httpsCallable('ensureSenderAccount')"));
    expect(source, contains('auth'));
    expect(source, contains('authStateChanges()'));
    expect(source, isNot(contains("'Profile unavailable'")));
  });
}
