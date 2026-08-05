import 'package:flutter/foundation.dart';

/// Warns in debug builds when a platform view is hidden before attachment.
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
