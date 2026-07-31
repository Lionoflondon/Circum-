import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef GuardedPump = Future<void> Function();

const layoutFailurePatterns = [
  'Vertical viewport was given unbounded height',
  'Horizontal viewport was given unbounded width',
  'RenderBox was not laid out',
  'RenderFlex overflowed',
  'overflowed by',
  'BoxConstraints forces an infinite',
  'Incorrect use of ParentDataWidget',
  'Failed assertion',
];

Future<void> expectNoFlutterLayoutExceptions(
  WidgetTester tester,
  GuardedPump body,
) async {
  final previous = FlutterError.onError;
  final captured = <FlutterErrorDetails>[];
  FlutterError.onError = (details) {
    captured.add(details);
  };
  try {
    await body();
    final pending = tester.takeException();
    if (pending != null) {
      fail('Unexpected Flutter exception during first-frame render: $pending');
    }
    if (captured.isNotEmpty) {
      final summary = captured
          .map((details) =>
              '${details.exceptionAsString()}\n${details.stack ?? ''}')
          .join('\n---\n');
      fail('Unexpected FlutterError during first-frame render:\n$summary');
    }
  } finally {
    FlutterError.onError = previous;
  }
}

Matcher containsNoNestedVerticalScrollOwner() => isNot(
      anyOf(
        contains('return ListView('),
        contains('SingleChildScrollView('),
        contains('CustomScrollView('),
      ),
    );

Future<void> pumpSenderFrame(
  WidgetTester tester,
  Widget widget, {
  required Size size,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(widget);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}
