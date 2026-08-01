import 'dart:io';

import 'package:circum/app/sender_mobile/sender_ui_baseline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender UI baseline version is locked at v1.0', () {
    expect(SenderUiBaseline.version, 'Sender UI Baseline v1.0');
  });

  test('Sender baseline tokens preserve approved shell metrics', () {
    expect(SenderUiBaseline.spacing.pageHorizontal, 20);
    expect(SenderUiBaseline.spacing.pageTop, 18);
    expect(SenderUiBaseline.spacing.pageBottom, 0);
    expect(SenderUiBaseline.navigation.safeAreaMinimum.left, 10);
    expect(SenderUiBaseline.navigation.safeAreaMinimum.top, 5);
    expect(SenderUiBaseline.navigation.safeAreaMinimum.right, 10);
    expect(SenderUiBaseline.navigation.safeAreaMinimum.bottom, 7);
    expect(SenderUiBaseline.navigation.itemPadding.vertical, 16);
    expect(SenderUiBaseline.navigation.itemMargin.horizontal, 4);
    expect(SenderUiBaseline.navigation.iconLabelGap, 4);
    expect(SenderUiBaseline.navigation.labelSize, 11);
    expect(SenderUiBaseline.radius.navItem, 18);
    expect(SenderUiBaseline.motion.standard.inMilliseconds, 220);
    expect(SenderUiBaseline.motion.fast.inMilliseconds, 120);
  });

  test('Sender shell policy blocks duplicate roots and app scaling', () {
    expect(SenderUiBaseline.shell.allowNestedTabScaffold, isFalse);
    expect(SenderUiBaseline.shell.allowNavigationScaling, isFalse);
    expect(SenderUiBaseline.shell.allowPageWidthCap, isFalse);
  });

  test('Sender primary shell consumes baseline tokens', () {
    final shell = File('lib/app/sender_mobile/sender_page_shell.dart')
        .readAsStringSync();

    expect(shell, contains('SenderUiBaseline.pageHorizontal'));
    expect(shell, contains('SenderUiBaseline.pageTop'));
    expect(shell, contains('SenderUiBaseline.pageBottom'));
    expect(shell, isNot(contains('BoxConstraints(maxWidth: maxWidth)')));
    expect(shell, isNot(contains('minHeight: contentHeight')));
  });

  test('Sender bottom navigation consumes baseline tokens', () {
    final home = File('lib/app/sender_mobile/sender_mobile_home.dart')
        .readAsStringSync();
    final start = home.indexOf('class _SenderBottomNav');
    final end = home.indexOf('class _SenderAvatar');
    final nav = home.substring(start, end);

    expect(nav, contains('SenderUiBaseline.navigation.safeAreaMinimum'));
    expect(nav, contains('SenderUiBaseline.navigation.itemMargin'));
    expect(nav, contains('SenderUiBaseline.navigation.itemPadding'));
    expect(nav, contains('SenderUiBaseline.navIconLabelGap'));
    expect(nav, contains('SenderUiBaseline.navigation.labelSize'));
    expect(nav, contains('SenderUiBaseline.radius.navItem'));
    expect(nav, contains('SenderUiBaseline.motion.standard'));
    expect(nav, contains('SenderUiBaseline.motion.curve'));
    expect(nav, isNot(contains('Transform.scale')));
    expect(nav, isNot(contains('AnimatedScale')));
    expect(nav, isNot(contains('FittedBox')));
    expect(nav, isNot(contains('FractionallySizedBox')));
  });

  test('Sender UI baseline document exists and names the locked version', () {
    final doc = File('docs/sender-ui-baseline-v1.md').readAsStringSync();

    expect(doc, contains('Sender UI Baseline v1.0'));
    expect(doc, contains('One canonical Sender app scaffold'));
    expect(doc, contains('must not introduce nested `Scaffold` roots'));
  });
}
