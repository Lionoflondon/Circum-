import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matching search animation keeps its green orbit and status signal', () {
    final source = File(
      'lib/app/sender_mobile/sender_tracking_screen.dart',
    ).readAsStringSync();

    final orbStart = source.indexOf('class _SearchingOrbState');
    final checklistStart = source.indexOf('class ProgressiveMatchChecklist');
    expect(orbStart, greaterThanOrEqualTo(0));
    expect(checklistStart, greaterThan(orbStart));

    final orb = source.substring(orbStart, checklistStart);
    expect(orb, contains('const green = Color(0xFF34D399)'));
    expect(orb, contains('final orbitAngle = _controller.value * math.pi * 2'));
    expect(orb, contains('math.cos(orbitAngle) * orbitRadius'));
    expect(orb, contains('math.sin(orbitAngle) * orbitRadius'));
  });
}
