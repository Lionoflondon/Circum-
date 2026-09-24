import 'dart:io';

import 'package:circum/website/shared/newsletter/newsletter_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget signup(NewsletterCall call, {String source = 'homepage'}) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NewsletterSignupSection(
              background: Colors.black,
              panel: Colors.black87,
              text: Colors.white,
              mutedText: Colors.white70,
              border: Colors.blue,
              onPrivacy: Uri.parse('https://circumuk.com/privacy_policy'),
              call: call,
              source: source,
            ),
          ),
        ),
      );

  test('newsletter marketing entry is dormant in the default build', () {
    expect(newsletterSignupEnabled, isFalse);
  });

  test('Mailchimp site tracking is present but consent-gated', () {
    final shell = File('web/index.html').readAsStringSync();
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    const trackingUrl =
        'https://chimpstatic.com/mcjs-connected/js/users/b21e126d2912f3a0d50cc2727/ab39fe9ec15e5ad7acd1bc638.js';

    expect(shell, contains('id="mcjs" type="text/plain"'));
    expect(shell, contains('data-circum-consent="optional-analytics"'));
    expect(shell, contains(trackingUrl));
    expect(source, contains('_enableMailchimpSiteTracking()'));
    expect(source, contains("existing.getAttribute('type') != 'text/plain'"));
    expect(source, contains(trackingUrl));
  });

  test('preference tokens are removed from visitor and support URL metadata',
      () {
    for (final value in [
      'https://circumuk.com/unsubscribe?token=private-token&utm_source=email',
      'https://circumuk.com/#/unsubscribe?token=private-token',
    ]) {
      final safe = newsletterPublicPageUri(Uri.parse(value));
      expect(safe.toString(), isNot(contains('private-token')));
      expect(safe.queryParameters, isNot(contains('token')));
    }
    final safe = newsletterPublicPageUri(Uri.parse(
        'https://circumuk.com/unsubscribe?token=private-token&utm_source=email'));
    expect(safe.queryParameters['utm_source'], 'email');
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    expect(source, contains("'url': pageUri.toString()"));
    expect(source, contains("'query': pageUri.queryParameters"));
    expect(source,
        contains("'pageUrl': newsletterPublicPageUri(Uri.base).toString()"));
    expect(source, isNot(contains("'url': Uri.base.toString()")));
  });

  Widget preferences(NewsletterCall call) => MaterialApp(
        home: NewsletterPreferencesPage(
          background: Colors.black,
          text: Colors.white,
          mutedText: Colors.white70,
          token: 'test-unsubscribe-token',
          call: call,
        ),
      );

  testWidgets('mobile signup validates and records only the selected interests',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(signup((name, data) async {
      if (name == 'submitNewsletterSignup') calls.add(data);
      return {'ok': true};
    }));
    await tester.tap(find.text('Join CIRCUM →'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(calls, isEmpty);
    await tester.enterText(find.byType(TextField), 'hello@example.com');
    await tester.tap(find.text('Choose what you hear about'));
    await tester.pumpAndSettle();
    final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
    expect(chips.where((chip) => chip.selected).length, 1);
    await tester.tap(find.text('Join CIRCUM →'));
    await tester.pumpAndSettle();
    expect(calls.single['consent'], isTrue);
    expect(calls.single['categories'], ['circum_updates']);
    expect(find.text('You’re in. Welcome to CIRCUM.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving preferences retains the unsubscribe action',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(preferences((name, data) async {
      calls.add(name);
      return {
        'ok': true,
        'status': 'active',
        'categories': ['circum_updates']
      };
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();
    expect(find.text('Unsubscribe from all'), findsOneWidget);
    await tester.tap(find.text('Unsubscribe from all'));
    await tester.pumpAndSettle();
    expect(calls, contains('unsubscribeNewsletter'));
    expect(find.text('Unsubscribe from all'), findsNothing);
    expect(
        find.text(
            'You’ve been unsubscribed. You won’t receive further CIRCUM marketing emails.'),
        findsOneWidget);
  });

  testWidgets('footer attribution and optional offers survive a signup retry',
      (tester) async {
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(signup((name, data) async {
      if (name == 'submitNewsletterSignup') {
        calls.add(data);
        if (calls.length == 1) throw Exception('network failure');
      }
      return {'ok': true};
    }, source: 'footer'));
    await tester.enterText(find.byType(TextField), 'footer@example.com');
    await tester.tap(find.text('Choose what you hear about'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offers & Rewards'));
    await tester.tap(find.text('Join CIRCUM →'));
    await tester.pumpAndSettle();
    expect(find.text('Could not join right now. Try again.'), findsOneWidget);
    await tester.tap(find.text('Join CIRCUM →'));
    await tester.pumpAndSettle();
    expect(calls.length, 2);
    expect(calls.last['source'], 'footer');
    expect(calls.last['categories'], ['circum_updates', 'offers_rewards']);
    expect(find.text('You’re in. Welcome to CIRCUM.'), findsOneWidget);
  });

  testWidgets('network failure preserves withdrawal retry action',
      (tester) async {
    await tester.pumpWidget(preferences((name, data) async {
      if (name == 'unsubscribeNewsletter') throw Exception('offline');
      return {
        'status': 'active',
        'categories': ['circum_updates']
      };
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsubscribe from all'));
    await tester.pumpAndSettle();
    expect(find.text('Could not update your preferences. Try again.'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Unsubscribe from all'))
            .onPressed,
        isNotNull);
  });

  testWidgets('empty preferences do not silently opt back into Updates',
      (tester) async {
    var updates = 0;
    await tester.pumpWidget(preferences((name, data) async {
      if (name == 'updateNewsletterPreferences') updates++;
      return {
        'status': 'active',
        'categories': ['circum_updates']
      };
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CIRCUM Updates'));
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();
    expect(updates, 0);
    expect(find.text('Choose an interest or select Unsubscribe from all.'),
        findsOneWidget);
    expect(find.text('Unsubscribe from all'), findsOneWidget);
  });
}
