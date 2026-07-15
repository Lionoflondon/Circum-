import 'dart:typed_data';

import 'package:circum/app/sender_mobile/sender_mobile_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProfileRepository implements SenderMobileProfileRepository {
  SenderMobileProfileData profile;
  bool failLoad;
  bool failSave;
  bool loggedOut = false;
  bool photoUploaded = false;
  bool accountClosed = false;

  _FakeProfileRepository({
    required this.profile,
    this.failLoad = false,
    this.failSave = false,
  });

  @override
  Future<SenderMobileProfileData> load() async {
    if (failLoad) throw Exception('offline');
    return profile;
  }

  @override
  Stream<SenderMobileProfileData> watch() {
    if (failLoad) return Stream.error(Exception('offline'));
    return Stream.value(profile);
  }

  @override
  Future<SenderMobileProfileData> save({
    required String displayName,
    required String username,
    required String phone,
  }) async {
    if (failSave) throw Exception('save failed');
    profile = SenderMobileProfileData(
      userId: profile.userId,
      displayName: displayName,
      username: username,
      email: profile.email,
      phone: phone,
      photoUrl: profile.photoUrl,
      createdAt: profile.createdAt,
      trustScore: profile.trustScore,
      trustTier: profile.trustTier,
      nextTier: profile.nextTier,
      pointsToNextTier: profile.pointsToNextTier,
      completedDeliveries: profile.completedDeliveries,
      trustHistory: profile.trustHistory,
    );
    return profile;
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
  }

  @override
  Future<void> closeAccount() async {
    accountClosed = true;
  }

  @override
  Future<SenderMobileProfileData> uploadPhoto(
    SenderProfilePhoto photo,
  ) async {
    photoUploaded = true;
    profile = SenderMobileProfileData(
      userId: profile.userId,
      displayName: profile.displayName,
      username: profile.username,
      email: profile.email,
      phone: profile.phone,
      photoUrl: '',
      createdAt: profile.createdAt,
      trustScore: profile.trustScore,
      trustTier: profile.trustTier,
      nextTier: profile.nextTier,
      pointsToNextTier: profile.pointsToNextTier,
      completedDeliveries: profile.completedDeliveries,
      trustHistory: profile.trustHistory,
    );
    return profile;
  }
}

class _FakePhotoPicker implements SenderProfilePhotoPicker {
  @override
  Future<SenderProfilePhoto?> pick() async => SenderProfilePhoto(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'avatar.jpg',
        contentType: 'image/jpeg',
      );
}

Widget _app(
  _FakeProfileRepository repository, {
  VoidCallback? onLoggedOut,
  SenderProfilePhotoPicker? photoPicker,
}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      backgroundColor: const Color(0xFF07090F),
      body: SenderMobileProfileView(
        repository: repository,
        photoPicker: photoPicker,
        onLoggedOut: onLoggedOut,
      ),
    ),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(
    target,
    find.byKey(const Key('sender-profile-view')),
    const Offset(0, -320),
  );
  await tester.pumpAndSettle();
}

void main() {
  final completeProfile = SenderMobileProfileData(
    userId: 'sender-1',
    displayName: 'Jason Adesanya',
    username: 'jasonadesanya',
    email: 'jason@example.com',
    phone: '+44 7700 900123',
    photoUrl: '',
    createdAt: DateTime(2021, 3, 14),
    trustScore: 342,
    trustTier: 'priority_sender',
    nextTier: 'platinum_sender',
    pointsToNextTier: 408,
    completedDeliveries: 48,
    trustHistory: [
      SenderTrustActivity(points: 5, label: 'Successful Delivery'),
      SenderTrustActivity(points: 7, label: 'Referral Completed'),
      SenderTrustActivity(points: 3, label: 'Gift Delivery'),
      SenderTrustActivity(points: -3, label: 'Customer Cancellation'),
    ],
  );

  testWidgets('renders Sender profile details and V1 shortcuts',
      (tester) async {
    await tester.pumpWidget(
      _app(_FakeProfileRepository(profile: completeProfile)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jason Adesanya'), findsWidgets);
    expect(find.text('jason@example.com'), findsWidgets);
    expect(find.text('SENDER ACCOUNT'), findsOneWidget);
    expect(find.text('Member since 2021'), findsOneWidget);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('@jasonadesanya'), findsWidgets);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('342'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('408 Trust Points until Platinum'), findsOneWidget);
    await _scrollTo(tester, find.text('+44 7700 900123'));
    expect(find.text('+44 7700 900123'), findsOneWidget);
    await _scrollTo(tester, find.text('Trust'));
    expect(find.text('Trust'), findsOneWidget);
    expect(find.text('Recent Trust Activity'), findsOneWidget);
    expect(find.text('Successful Delivery'), findsOneWidget);
    expect(find.text('Referral Completed'), findsOneWidget);
    expect(find.text('Gift Delivery'), findsOneWidget);
    expect(find.text('Customer Cancellation'), findsNothing);
    expect(find.text('View Full History'), findsOneWidget);
    expect(find.text('View Trust Details →'), findsOneWidget);
    expect(find.text('Priority Sender Benefits'), findsNothing);
    expect(find.text('Regular Sender Benefits'), findsNothing);
    expect(find.text('Regular Sender benefit'), findsNothing);
    expect(find.text('Eligibility for earlier rider acceptance'), findsNothing);
    await _scrollTo(tester, find.text('Saved addresses'));
    expect(find.text('Saved addresses'), findsOneWidget);
    expect(
      find.text('No saved addresses yet.'),
      findsOneWidget,
    );
    expect(find.text('Wallet'), findsOneWidget);
    expect(
      find.text('Roth balance, rewards and transactions.'),
      findsOneWidget,
    );
    expect(find.text('Referrals'), findsOneWidget);
    expect(
        find.text('Invite friends and view referral rewards.'), findsOneWidget);
    await _scrollTo(tester, find.text('Accessibility'));
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Payment methods'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Accessibility'), findsOneWidget);
    await _scrollTo(tester, find.text('Help & Support'));
    expect(find.text('Help'), findsOneWidget);
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    await _scrollTo(tester, find.byKey(const Key('sender-profile-logout')));
    expect(find.text('Log out'), findsOneWidget);
    expect(find.textContaining('Rider'), findsNothing);
  });

  testWidgets('opens functional Sender settings screens', (tester) async {
    await tester.pumpWidget(
      _app(_FakeProfileRepository(profile: completeProfile)),
    );
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('Security'));
    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Two-Factor Authentication'), findsOneWidget);
    expect(find.text('Biometrics'), findsOneWidget);
    expect(find.text('Active Devices'), findsOneWidget);
    expect(find.text('Change email'), findsOneWidget);
    expect(find.text('Change phone number'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Language'));
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    expect(find.text('App Language'), findsOneWidget);
    expect(find.text('Device Default'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Region'), findsWidgets);
    expect(find.text('Uses device region by default'), findsOneWidget);
    expect(find.text('Date & Time Format'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('12-hour'), findsOneWidget);
    expect(find.text('24-hour'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Accessibility'));
    await tester.tap(find.text('Accessibility'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Follow System'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Text Size'), findsOneWidget);
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);
    expect(find.text('High Contrast'), findsOneWidget);
    expect(find.text('Reduce Motion'), findsOneWidget);
    expect(find.text('Screen Reader Optimisations'), findsOneWidget);
  });

  testWidgets('shows missing fields without asking for known email',
      (tester) async {
    final repository = _FakeProfileRepository(
      profile: const SenderMobileProfileData(
        userId: 'sender-2',
        displayName: '',
        email: 'known@example.com',
        phone: '',
        photoUrl: '',
        hasTrustScore: false,
        hasCompletedDeliveries: false,
      ),
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Add your name'), findsOneWidget);
    await _scrollTo(tester, find.text('Phone'));
    expect(find.text('Not added yet'), findsNWidgets(3));
    await tester.ensureVisible(
      find.byKey(const Key('sender-profile-primary-edit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sender-profile-primary-edit')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('sender-profile-view')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(find.text('known@example.com'), findsWidgets);
    expect(find.widgetWithText(TextField, 'Email'), findsNothing);
  });

  testWidgets('handles missing trust data gracefully', (tester) async {
    final repository = _FakeProfileRepository(
      profile: const SenderMobileProfileData(
        userId: 'sender-new',
        displayName: 'New Sender',
        email: 'new@example.com',
        phone: '',
        photoUrl: '',
        hasTrustScore: false,
        hasCompletedDeliveries: false,
      ),
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('New Sender'), findsWidgets);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('Trust progress unavailable'), findsOneWidget);
    await _scrollTo(tester, find.text('No recent trust activity yet.'));
    expect(find.text('No recent trust activity yet.'), findsOneWidget);
  });

  testWidgets('edits and saves name, username and phone', (tester) async {
    final repository = _FakeProfileRepository(profile: completeProfile);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sender-profile-primary-edit')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('sender-profile-name-field')));
    await tester.enterText(
      find.byKey(const Key('sender-profile-name-field')),
      'Jason A',
    );
    await tester.enterText(
      find.byKey(const Key('sender-profile-phone-field')),
      '+44 7700 900456',
    );
    await tester.enterText(
      find.byKey(const Key('sender-profile-username-field')),
      'jason-a',
    );
    await tester.ensureVisible(find.byKey(const Key('sender-profile-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sender-profile-save')));
    await tester.pumpAndSettle();

    expect(repository.profile.displayName, 'Jason A');
    expect(repository.profile.username, 'jason-a');
    expect(repository.profile.phone, '+44 7700 900456');
    expect(find.text('Profile saved.'), findsOneWidget);
  });

  testWidgets('uploads and saves a Sender profile photo', (tester) async {
    final repository = _FakeProfileRepository(profile: completeProfile);
    await tester.pumpWidget(
      _app(repository, photoPicker: _FakePhotoPicker()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sender-profile-photo-upload')));
    await tester.pumpAndSettle();

    expect(repository.photoUploaded, isTrue);
    expect(find.text('Profile photo saved.'), findsOneWidget);
  });

  testWidgets('shows save errors and keeps edit mode available',
      (tester) async {
    final repository = _FakeProfileRepository(
      profile: completeProfile,
      failSave: true,
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sender-profile-primary-edit')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('sender-profile-save')));
    await tester.ensureVisible(find.byKey(const Key('sender-profile-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sender-profile-save')));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('sender-profile-view')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Your changes could not be saved. Please try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sender-profile-save')), findsOneWidget);
  });

  testWidgets('shows offline state with retry', (tester) async {
    final repository = _FakeProfileRepository(
      profile: completeProfile,
      failLoad: true,
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Profile unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    repository.failLoad = false;
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Jason Adesanya'), findsWidgets);
  });

  testWidgets('logout uses repository and returns control to Sender shell',
      (tester) async {
    final repository = _FakeProfileRepository(profile: completeProfile);
    var callbackCalled = false;
    await tester.pumpWidget(
      _app(repository, onLoggedOut: () => callbackCalled = true),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('sender-profile-logout')));
    await tester.tap(find.byKey(const Key('sender-profile-logout')));
    await tester.pumpAndSettle();

    expect(repository.loggedOut, isTrue);
    expect(callbackCalled, isTrue);
  });

  testWidgets('uses a single-column layout on mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(_FakeProfileRepository(profile: completeProfile)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sender-profile-desktop-grid')), findsNothing);
    expect(find.byKey(const Key('sender-profile-constrained-layout')),
        findsOneWidget);
  });

  testWidgets('constrains and centres the desktop profile', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(_FakeProfileRepository(profile: completeProfile)),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('sender-profile-desktop-grid')), findsOneWidget);
    final constrained = tester.widget<ConstrainedBox>(
      find.byKey(const Key('sender-profile-constrained-layout')),
    );
    expect(constrained.constraints.maxWidth, 1040);
  });

  testWidgets('shows one edit action and one trust summary', (tester) async {
    await tester.pumpWidget(
      _app(_FakeProfileRepository(profile: completeProfile)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Trust'), findsOneWidget);
    expect(find.text('Trust Score'), findsOneWidget);
  });

  testWidgets('keeps content clear of the fixed Sender navigation',
      (tester) async {
    await tester.pumpWidget(
      _app(_FakeProfileRepository(profile: completeProfile)),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(
      find.byKey(const Key('sender-profile-view')),
    );
    final padding = list.padding! as EdgeInsets;
    expect(padding.bottom, greaterThanOrEqualTo(96));
  });

  testWidgets('account rows use transient interaction states only',
      (tester) async {
    await tester.pumpWidget(
      _app(_FakeProfileRepository(profile: completeProfile)),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('sender-profile-terms')));

    final ink = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('sender-profile-terms')),
        matching: find.byType(InkWell),
      ),
    );
    expect(ink.hoverColor, isNot(const Color(0xFF3B82F6)));
    expect(ink.focusColor, isNot(const Color(0xFF3B82F6)));
  });

  testWidgets(
      'maps internal baseline activity to customer copy and limits preview',
      (tester) async {
    final profile = SenderMobileProfileData(
      userId: completeProfile.userId,
      displayName: completeProfile.displayName,
      username: completeProfile.username,
      email: completeProfile.email,
      phone: completeProfile.phone,
      photoUrl: '',
      trustHistory: [
        SenderTrustActivity.fromMap(const {
          'label': 'System Baseline From Delivery History',
          'points': 10,
        }),
        const SenderTrustActivity(points: 2, label: 'Delivery completed'),
        const SenderTrustActivity(points: 3, label: 'Trust points added'),
        const SenderTrustActivity(points: 4, label: 'Fourth entry'),
      ],
    );
    await tester.pumpWidget(_app(_FakeProfileRepository(profile: profile)));
    await tester.pumpAndSettle();

    expect(find.text('System Baseline From Delivery History'), findsNothing);
    expect(find.text('Account trust baseline established'), findsOneWidget);
    expect(find.text('Fourth entry'), findsNothing);
  });

  testWidgets('Terms and Privacy open independent dark routes', (tester) async {
    await tester.pumpWidget(
      _app(_FakeProfileRepository(profile: completeProfile)),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('sender-profile-terms')));
    await tester.tap(find.byKey(const Key('sender-profile-terms')));
    await tester.pumpAndSettle();
    expect(find.text('Circum Terms of Service'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('sender-profile-privacy')));
    await tester.tap(find.byKey(const Key('sender-profile-privacy')));
    await tester.pumpAndSettle();
    expect(find.text('Circum Privacy Policy'), findsOneWidget);
  });

  testWidgets('account closure requires confirmation and uses repository',
      (tester) async {
    final repository = _FakeProfileRepository(profile: completeProfile);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await _scrollTo(
        tester, find.byKey(const Key('sender-profile-close-account')));
    await tester.tap(find.byKey(const Key('sender-profile-close-account')));
    await tester.pumpAndSettle();
    expect(find.text('Close your Circum account?'), findsOneWidget);
    expect(repository.accountClosed, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, 'Close account'));
    await tester.pumpAndSettle();
    expect(repository.accountClosed, isTrue);
  });
}
