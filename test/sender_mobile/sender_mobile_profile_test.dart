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
  Future<SenderMobileProfileData> save({
    required String displayName,
    required String phone,
  }) async {
    if (failSave) throw Exception('save failed');
    profile = SenderMobileProfileData(
      userId: profile.userId,
      displayName: displayName,
      email: profile.email,
      phone: phone,
      photoUrl: profile.photoUrl,
    );
    return profile;
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
  }

  @override
  Future<SenderMobileProfileData> uploadPhoto(
    SenderProfilePhoto photo,
  ) async {
    photoUploaded = true;
    profile = SenderMobileProfileData(
      userId: profile.userId,
      displayName: profile.displayName,
      email: profile.email,
      phone: profile.phone,
      photoUrl: '',
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

void main() {
  const completeProfile = SenderMobileProfileData(
    userId: 'sender-1',
    displayName: 'Jason Adesanya',
    email: 'jason@example.com',
    phone: '+44 7700 900123',
    photoUrl: '',
  );

  testWidgets('renders Sender profile details and V1 shortcuts',
      (tester) async {
    await tester.pumpWidget(
      _app(_FakeProfileRepository(profile: completeProfile)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jason Adesanya'), findsWidgets);
    expect(find.text('jason@example.com'), findsWidgets);
    expect(find.text('+44 7700 900123'), findsOneWidget);
    expect(find.text('SENDER ACCOUNT'), findsOneWidget);
    expect(find.text('Saved addresses'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Referrals'), findsOneWidget);
    expect(find.text('Help & support'), findsOneWidget);
    expect(find.text('Legal'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('sender-profile-logout')),
      300,
    );
    expect(find.text('Log out'), findsOneWidget);
    expect(find.textContaining('Rider'), findsNothing);
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
      ),
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Add your name'), findsOneWidget);
    expect(find.text('Not added yet'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('known@example.com'), findsWidgets);
    expect(find.widgetWithText(TextField, 'Email'), findsNothing);
  });

  testWidgets('edits and saves display name and phone', (tester) async {
    final repository = _FakeProfileRepository(profile: completeProfile);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('sender-profile-name-field')),
      'Jason A',
    );
    await tester.enterText(
      find.byKey(const Key('sender-profile-phone-field')),
      '+44 7700 900456',
    );
    await tester.ensureVisible(find.byKey(const Key('sender-profile-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sender-profile-save')));
    await tester.pumpAndSettle();

    expect(repository.profile.displayName, 'Jason A');
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
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();
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
    await tester.scrollUntilVisible(
      find.byKey(const Key('sender-profile-logout')),
      300,
    );
    await tester.tap(find.byKey(const Key('sender-profile-logout')));
    await tester.pumpAndSettle();

    expect(repository.loggedOut, isTrue);
    expect(callbackCalled, isTrue);
  });
}
