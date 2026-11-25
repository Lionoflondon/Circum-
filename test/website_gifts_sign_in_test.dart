import 'dart:async';

import 'package:circum/website/shared/gifts_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController email;
  late TextEditingController password;
  setUp(() {
    email = TextEditingController();
    password = TextEditingController();
  });
  tearDown(() {
    email.dispose();
    password.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    required Future<void> Function() signIn,
    bool busy = false,
    String? error,
    Size size = const Size(1440, 1100),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: GiftsSignIn(
      emailController: email,
      passwordController: password,
      signingIn: busy,
      message: error,
      onSignIn: signIn,
      onBack: () {},
      onPrivacy: () {},
      onTerms: () {},
    )));
  }

  testWidgets(
      'valid credentials reach the existing callback once while pending',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await mount(tester, signIn: () {
      calls++;
      expect(email.text, 'person@example.com');
      expect(password.text, 'test-only-password');
      return pending.future;
    });
    await tester.enterText(
        find.byKey(const Key('gifts-sign-in-email')), 'person@example.com');
    await tester.enterText(
        find.byKey(const Key('gifts-sign-in-password')), 'test-only-password');
    await tester.tap(find.byKey(const Key('gifts-sign-in-submit')));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Signing in…'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('gifts-sign-in-submit')))
            .onPressed,
        isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Sign in and continue'), findsOneWidget);
  });

  testWidgets('invalid input stays local; server errors keep retry available',
      (tester) async {
    var calls = 0;
    await mount(tester, signIn: () async {
      calls++;
    });
    await tester.tap(find.byKey(const Key('gifts-sign-in-submit')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    await mount(tester, signIn: () async {
      calls++;
    }, error: 'The email or password is incorrect.');
    expect(find.text('The email or password is incorrect.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('gifts-sign-in-submit')))
            .onPressed,
        isNotNull);
  });

  testWidgets('keyboard submit and password visibility work on mobile',
      (tester) async {
    var calls = 0;
    await mount(tester, size: const Size(390, 844), signIn: () async {
      calls++;
    });
    await tester.enterText(
        find.byKey(const Key('gifts-sign-in-email')), 'person@example.com');
    await tester.enterText(
        find.byKey(const Key('gifts-sign-in-password')), 'test-only-password');
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide password'), findsOneWidget);
    await tester.showKeyboard(find.byKey(const Key('gifts-sign-in-password')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account owner busy state prevents another authentication call',
      (tester) async {
    await mount(tester, busy: true, signIn: () async {
      fail('Must not authenticate twice');
    });
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('gifts-sign-in-email')))
            .enabled,
        isFalse);
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const Key('gifts-sign-in-password')))
            .enabled,
        isFalse);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('gifts-sign-in-submit')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
}
