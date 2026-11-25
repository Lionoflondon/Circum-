import 'dart:io';
import 'dart:ui' as ui;
import 'package:circum/website/shared/vanguard_landing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(WidgetTester tester, Size size,
      {VoidCallback? start}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(
            key: const Key('preview'),
            child:
                VanguardLandingPage(onBack: () {}, onStart: start ?? () {}))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'delivery action delegates and example explains distinct handovers',
      (tester) async {
    var calls = 0;
    await mount(tester, const Size(1280, 900), start: () => calls++);
    await tester.tap(find.text('Plan a delivery').first);
    expect(calls, 1);
    await tester.ensureVisible(find.text('See how it works'));
    await tester.tap(find.text('See how it works'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('03  Handover'));
    await tester.tap(find.text('03  Handover'));
    await tester.pumpAndSettle();
    expect(find.text('The right hands.'), findsOneWidget);
    expect(find.textContaining('receiver PIN verifies'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('mobile large text preserves pricing and insurance limitations',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await mount(tester, const Size(390, 844));
    await tester.ensureVisible(find.text('£1.99'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vanguard is not insurance.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('render Vanguard previews when requested', (tester) async {
    final destination = Platform.environment['VANGUARD_PREVIEW_DIR'];
    if (destination == null) return;
    for (final name in ['D-DIN', 'D-DIN-Bold']) {
      await tester.runAsync(() => (FontLoader(name)
            ..addFont(Future.value(ByteData.sublistView(
                File('web/fonts/d-din/$name.ttf').readAsBytesSync()))))
          .load());
    }
    await tester.runAsync(() => (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load());
    for (final size in [const Size(1280, 1000), const Size(390, 1100)]) {
      await mount(tester, size);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('preview')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$destination/vanguard-${size.width.toInt()}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
