import 'package:circum/website/shared/rider_recruitment_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/link.dart';

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('recruitment actions and store links at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      var joined = false;
      var loggedIn = false;
      var vision = false;
      await tester.pumpWidget(MaterialApp(
          home: RiderRecruitmentPage(
              onBack: () {},
              onJoin: () => joined = true,
              onLogin: () => loggedIn = true,
              onVision: () => vision = true)));
      await tester.tap(find.text('Rider login'));
      expect(loggedIn, isTrue);
      await tester.scrollUntilVisible(
          find.text('Join Circum Riders').first, 250);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join Circum Riders').first);
      expect(joined, isTrue);
      await tester.ensureVisible(find.text('Explore the Rider vision'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explore the Rider vision'));
      expect(vision, isTrue);
      await tester.scrollUntilVisible(
          find.bySemanticsLabel('Get it on Google Play'), 600);
      final links =
          tester.widgetList<Link>(find.byType(Link)).map((link) => link.uri);
      expect(
          links,
          containsAll(
              [RiderRecruitmentPage.appStore, RiderRecruitmentPage.playStore]));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
