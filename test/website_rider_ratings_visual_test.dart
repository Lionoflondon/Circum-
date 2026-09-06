import 'dart:io';
import 'dart:ui' as ui;
import 'package:circum/website/shared/rating_feedback_card.dart';
import 'package:circum/website/shared/policies/driver_performance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'Rider web feedback retains its website design and reporting action',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      await (FontLoader('Roboto')
            ..addFont(
                rootBundle.load('assets/fonts/OpenSans/OpenSans-Regular.ttf')))
          .load();
    });
    final key = GlobalKey();
    var reports = 0;
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: RepaintBoundary(
              key: key,
              child: Center(
                  child: SizedBox(
                width: 560,
                child: RiderWebRatingFeedback(
                    background: const Color(0xFF151820),
                    mutedText: Colors.white70,
                    onReport: () => reports++,
                    rating: DriverRating(
                      ratingId: 'example',
                      driverId: 'rider',
                      customerId: 'sender',
                      deliveryId: 'delivery',
                      starRating: 5,
                      feedbackText: 'Very careful and professional.',
                      deliveryCategories: const ['Health+', 'Scheduled'],
                      createdAt: DateTime(2026, 9, 6),
                    )),
              ))),
        )));
    await tester.pumpAndSettle();
    expect(find.text('Health+ + Scheduled'), findsOneWidget);
    expect(find.text('6/9/2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final picture = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final output = File(
          "${Platform.environment['RATING_VISUAL_OUTPUT'] ?? '${Directory.systemTemp.path}/circum-rating-visuals'}/rider-web-feedback.png");
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
    await tester.tap(find.text('Report feedback'));
    await tester.pumpAndSettle();
    expect(reports, 1);
    expect(tester.takeException(), isNull);
  });
}
