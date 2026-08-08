import 'package:flutter/foundation.dart';

/// Debug-only guard for Flutter Web platform views that must attach visibly.
void assertPlatformViewAttachVisibility({
  required String viewName,
  required double opacity,
  required bool attached,
}) {
  assert(() {
    if (!attached && opacity == 0) {
      debugPrint(
        'Platform view warning: $viewName is hidden at opacity 0 '
        'before attachment completed.',
      );
    }
    return true;
  }());
}
