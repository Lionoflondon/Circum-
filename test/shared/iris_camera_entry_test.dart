import 'dart:io';

import 'package:circum/shared/iris_camera_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  IrisCameraState state = IrisCameraState.idle,
  bool hasPhoto = false,
  required Future<void> Function() onTake,
  required Future<void> Function() onChoose,
  VoidCallback? onRemove,
  VoidCallback? onRetry,
}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: IrisCameraEntry(
        state: state,
        hasPhoto: hasPhoto,
        onTakePhoto: onTake,
        onChoosePhoto: onChoose,
        onRemove: onRemove,
        onRetry: onRetry,
      ),
    ),
  );
}

void main() {
  test('Sender never presents the deterministic estimate as visual inference',
      () {
    final source = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();

    expect(
        source,
        contains(
            "'IRIS estimate \${estimatedWeightKg!.toStringAsFixed(2)} kg.'"));
    expect(source, isNot(contains('Visual estimate')));
  });

  test('Sender bounds the inference image and records correlated timing', () {
    final source = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();

    expect(source, contains('maxWidth: 1280'));
    expect(source, isNot(contains('maxHeight: 1280')));
    expect(source, contains("'clientRequestId': clientRequestId"));
    expect(source, contains("'message': 'iris_visual_client_timing'"));
    expect(source, contains("'responseToRenderMs': responseToRenderMs"));
  });

  testWidgets('IRIS camera entry exposes Take Photo and Choose Photo',
      (tester) async {
    var tookPhoto = false;
    var chosePhoto = false;
    await tester.pumpWidget(_host(
      onTake: () async => tookPhoto = true,
      onChoose: () async => chosePhoto = true,
    ));

    expect(find.byKey(const ValueKey('iris-camera-entry')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Add parcel photo for IRIS verification'),
      findsOneWidget,
    );
    expect(tester.getSize(find.byKey(const ValueKey('iris-camera-entry'))),
        const Size(52, 52));

    await tester.tap(find.byKey(const ValueKey('iris-camera-entry')));
    await tester.pumpAndSettle();
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose Photo'), findsOneWidget);
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    expect(tookPhoto, isTrue);
    expect(chosePhoto, isFalse);

    await tester.tap(find.byKey(const ValueKey('iris-camera-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose Photo'));
    await tester.pumpAndSettle();
    expect(chosePhoto, isTrue);
  });

  testWidgets('IRIS camera entry supports completed, failed and busy states',
      (tester) async {
    var retried = false;
    Future<void> noop() async {}
    for (final state in IrisCameraState.values) {
      await tester.pumpWidget(_host(
        state: state,
        hasPhoto: state == IrisCameraState.completed,
        onTake: noop,
        onChoose: noop,
        onRetry: () => retried = true,
      ));
      expect(find.byKey(const ValueKey('iris-camera-entry')), findsOneWidget);
    }
    await tester.pumpWidget(_host(
      state: IrisCameraState.failed,
      onTake: noop,
      onChoose: noop,
      onRetry: () => retried = true,
    ));
    await tester.tap(find.byKey(const ValueKey('iris-camera-entry')));
    expect(retried, isTrue);
  });
}
