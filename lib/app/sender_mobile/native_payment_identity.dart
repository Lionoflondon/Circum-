import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Only identity is retained. A callback or local record never proves payment.
class NativePaymentIdentity {
  static Future<void> _tail = Future<void>.value();

  static String _key(String uid, String flow) {
    if (uid.isEmpty || !{'gift', 'delivery'}.contains(flow)) {
      throw ArgumentError('A signed-in payment surface is required.');
    }
    return 'circum.pending-payment.v1.$uid.$flow';
  }

  static Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<String> reserve({
    required String uid,
    required String flow,
    required String candidate,
  }) =>
      _serial(() async {
        final key = _key(uid, flow);
        if (candidate.isEmpty) {
          throw ArgumentError('Payment identity required.');
        }
        final prefs = await SharedPreferences.getInstance();
        final existing = prefs.getString(key);
        if (existing != null && existing.isNotEmpty) return existing;
        if (!await prefs.setString(key, candidate)) {
          throw StateError('Could not save payment recovery identity.');
        }
        return candidate;
      });

  /// Call only after backend-confirmed completion or terminal cancellation.
  /// A stale callback must not erase a newer payment's recovery identity.
  static Future<void> resolve({
    required String uid,
    required String flow,
    required String expected,
  }) =>
      _serial(() async {
        final prefs = await SharedPreferences.getInstance();
        final key = _key(uid, flow);
        if (prefs.getString(key) == expected && !await prefs.remove(key)) {
          throw StateError('Could not clear completed payment identity.');
        }
      });
}
