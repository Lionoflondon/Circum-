import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circum/app/send_package/view/ratings.dart';

class FakeAppreciation implements DeliveryAppreciationService {
  int calls = 0;
  int tipCalls = 0;
  Completer<Map<String, dynamic>>? pendingTip;
  @override
  Future<Map<String, dynamic>> submitRating(
      {required String deliveryId,
      required int stars,
      required String feedback,
      required List<String> feedbackTags}) async {
    calls++;
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> submitTip(
      {required String deliveryId,
      required int amountPence,
      required String paymentMethod,
      String? paymentIntentId,
      String? paymentMethodId}) async {
    tipCalls++;
    return pendingTip == null
        ? {'status': 'succeeded'}
        : await pendingTip!.future;
  }
}

void main() {
  testWidgets(
      'small phone rating prompt and submission render without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final textFont = FontLoader('Roboto')
        ..addFont(
            rootBundle.load('assets/fonts/OpenSans/OpenSans-Regular.ttf'));
      await textFont.load();
      final mono = FontLoader('monospace')
        ..addFont(
            rootBundle.load('assets/fonts/OpenSans/OpenSans-Regular.ttf'));
      await mono.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    final service = FakeAppreciation();
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(
            key: key,
            child: RatingsView(
                deliveryId: 'visual',
                service: service,
                deliveryStream: const Stream.empty(),
                initialDelivery: const {
                  'status': 'completed',
                  'paymentStatus': 'paid',
                  'riderId': 'test-rider',
                  'riderName': 'Test Rider'
                }))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final picture = await boundary.toImage();
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(
            Platform.environment['RATING_VISUAL_OUTPUT'] ??
                '${Directory.systemTemp.path}/circum-rating-visuals');
        await directory.create(recursive: true);
        await File('${directory.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }

    await capture('sender-rating-prompt');
    await tester.scrollUntilVisible(find.bySemanticsLabel('5 star'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('5 star'));
    await tester.pumpAndSettle();
    await capture('sender-selected-stars');
    await tester.tap(find.bySemanticsLabel('1 star'));
    await tester.scrollUntilVisible(find.text('Safety concern'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Safety concern'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Submitting this rating also sends your feedback to Circum Support.'),
        findsOneWidget);
    await capture('sender-low-rating-support');
    final button = find.byType(FilledButton);
    await tester.scrollUntilVisible(button, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(find.text('Thank you.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture('sender-confirmation');
  });
  testWidgets(
      'a tip does not require a rating and duplicate taps cannot change a pending payment',
      (tester) async {
    final service = FakeAppreciation()
      ..pendingTip = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(MaterialApp(
        home: RatingsView(
            deliveryId: 'tip-only',
            service: service,
            deliveryStream: const Stream.empty(),
            initialDelivery: const {
          'status': 'completed',
          'paymentStatus': 'paid',
          'riderId': 'test-rider'
        })));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('£1'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('£1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('£1'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(FilledButton), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(service.calls, 0);
    expect(service.tipCalls, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    service.pendingTip!.complete({'status': 'succeeded'});
    await tester.pumpAndSettle();
    expect(find.text('Your tip has been sent to your Rider.'), findsOneWidget);
    expect(service.tipCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
