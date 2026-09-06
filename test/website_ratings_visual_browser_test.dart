@TestOn('browser')
library;

import 'dart:convert';
import 'dart:ui_web' as ui_web;
import 'website_rating_fonts.dart';
import 'dart:ui' as ui;
import 'package:circum/website/shared/circum_website_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'Sender web rating states render as website widgets without clipping',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final feedback = TextEditingController();
    addTearDown(feedback.dispose);
    final previousEnvironment = ui_web.TestEnvironment.instance;
    ui_web.TestEnvironment.setUp(const ui_web.TestEnvironment(
      forceTestFonts: false,
      disableFontFallbacks: true,
      keepSemanticsDisabledOnUpdate: true,
      defaultToTestUrlStrategy: true,
    ));
    addTearDown(() => ui_web.TestEnvironment.setUp(previousEnvironment));
    await tester.runAsync(() async {
      if (ratingTextFont.isNotEmpty) {
        await ui.loadFontFromList(base64Decode(ratingTextFont),
            fontFamily: 'RatingVisualFont');
      }
      if (ratingIconFont.isNotEmpty) {
        await ui.loadFontFromList(base64Decode(ratingIconFont),
            fontFamily: 'MaterialIcons');
      }
    });
    ui_web.TestEnvironment.setUp(const ui_web.TestEnvironment(
      ignorePlatformMessages: true,
      forceTestFonts: false,
      disableFontFallbacks: true,
      keepSemanticsDisabledOnUpdate: true,
      defaultToTestUrlStrategy: true,
    ));
    for (final state in ['prompt', 'selected', 'support', 'confirmation']) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark()
                  .textTheme
                  .apply(fontFamily: 'RatingVisualFont')),
          home: Scaffold(
              body: RepaintBoundary(
            key: key,
            child: Center(
                child: SizedBox(
                    width: 560,
                    child: SingleChildScrollView(
                        child: senderWebRatingPromptPreview(
                      feedback: feedback,
                      stars: state == 'prompt'
                          ? 0
                          : state == 'support'
                              ? 1
                              : 5,
                      selectedTags:
                          state == 'support' ? {'safety_concern'} : {},
                      submitted: state == 'confirmation',
                      message: state == 'support'
                          ? 'Your feedback will also be sent to Circum Support.'
                          : null,
                    )))),
          ))));
      await tester.pumpAndSettle();
      debugPrint('VISUAL_STAGE:rendered-$state');

      final renderingError = tester.takeException();
      // ignore: avoid_print -- browser diagnostics.
      print('RENDER_ERROR:$renderingError');
      expect(renderingError, isNull);
      await tester.runAsync(() async {
        final picture = await (key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage()
            .timeout(const Duration(seconds: 10));
        final bytes = await picture
            .toByteData(format: ui.ImageByteFormat.png)
            .timeout(const Duration(seconds: 10));
        // ignore: avoid_print -- local screenshot capture protocol.
        print(
            'VISUAL_CAPTURE:sender-web-$state:${base64Encode(bytes!.buffer.asUint8List())}');
        picture.dispose();
      });
    }
  });
}
