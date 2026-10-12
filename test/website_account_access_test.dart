import 'dart:io';
import 'dart:ui' as ui;
import 'package:circum/website/shared/account_access_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<TextEditingController> fields;
  setUp(() => fields = List.generate(5, (_) => TextEditingController()));
  tearDown(() {
    for (final field in fields) {
      field.dispose();
    }
  });

  Future<void> mount(
    WidgetTester tester, {
    bool signup = false,
    bool busy = false,
    String? message,
    VoidCallback? login,
    VoidCallback? create,
    VoidCallback? reset,
    Size size = const Size(1280, 920),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
      builder: (context, setState) => RepaintBoundary(
        key: const Key('preview'),
        child: AccountAccessPage(
          signupMode: signup,
          busy: busy,
          message: message,
          email: fields[0],
          password: fields[1],
          fullName: fields[2],
          phone: fields[3],
          referralCode: fields[4],
          onToggleMode: () => setState(() => signup = !signup),
          onLogIn: login ?? () {},
          onSignUp: create ?? () {},
          onForgotPassword: reset ?? () {},
          onBack: () {},
          onPrivacy: () {},
          onTerms: () {},
        ),
      ),
    ))));
    if (busy) {
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
      'login validates input and delegates credentials to existing owner',
      (tester) async {
    var calls = 0;
    await mount(tester, login: () => calls++, message: 'Please try again.');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    fields[0].text = 'person@example.com';
    fields[1].text = 'example-password';
    await tester.tap(find.byType(FilledButton));
    expect(calls, 1);
    expect(find.text('Please try again.'), findsOneWidget);
  });

  testWidgets('signup toggle preserves email and submits signup fields only',
      (tester) async {
    var creates = 0;
    var logins = 0;
    await mount(tester, create: () => creates++, login: () => logins++);
    fields[0].text = 'person@example.com';
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    expect(fields[0].text, 'person@example.com');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(creates, 0);
    fields[2].text = 'Test Person';
    fields[1].text = 'test-password';
    fields[3].text = '07000000000';
    fields[4].text = 'FRIEND';
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    expect(creates, 1);
    expect(logins, 0);
  });

  testWidgets(
      'password reset requires email but not password; busy disables actions',
      (tester) async {
    var calls = 0;
    await mount(tester, reset: () => calls++);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    fields[0].text = 'person@example.com';
    await tester.tap(find.text('Forgot password?'));
    expect(calls, 1);
    await mount(tester, busy: true);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Sign up'))
            .onPressed,
        isNull);
  });

  testWidgets('mobile signup scrolls to action with keyboard and large text',
      (tester) async {
    await mount(tester, signup: true, size: const Size(390, 844));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('render account design previews when requested', (tester) async {
    final destination = Platform.environment['ACCOUNT_PREVIEW_DIR'];
    if (destination == null) return;
    for (final name in ['D-DIN', 'D-DIN-Bold']) {
      final loader = FontLoader(name)
        ..addFont(Future.value(ByteData.sublistView(
            File('web/fonts/d-din/$name.ttf').readAsBytesSync())));
      await tester.runAsync(() => loader.load());
    }
    await tester.runAsync(() async {
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    for (final signup in [false, true]) {
      await mount(tester, signup: signup, size: const Size(1280, 1040));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('preview')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$destination/account-${signup ? 'signup' : 'login'}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
