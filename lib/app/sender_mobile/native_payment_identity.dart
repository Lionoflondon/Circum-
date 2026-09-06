import 'dart:async';
import 'dart:convert';

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
  static Future<Map<String, dynamic>?> deliverySnapshot(String uid) =>
      _serial(() async {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('${_key(uid, 'delivery')}.snapshot');
        if (raw == null) return null;
        final value = jsonDecode(raw);
        if (value is! Map ||
            value['uid'] != uid ||
            value['quoteId'] is! String ||
            value['draft'] is! Map ||
            value['deliveryPayload'] is! Map ||
            value['total'] is! num ||
            !(value['total'] as num).isFinite ||
            value['lineItems'] is! List) {
          throw StateError('Saved payment needs review.');
        }
        return Map<String, dynamic>.from(value);
      });

  static Future<void> saveDeliverySnapshot(
    String uid,
    Map<String, dynamic> snapshot,
  ) =>
      _serial(() async {
        final prefs = await SharedPreferences.getInstance();
        final key = '${_key(uid, 'delivery')}.snapshot';
        final old = prefs.getString(key);
        if (old != null && jsonDecode(old)['quoteId'] != snapshot['quoteId']) {
          throw StateError(
              'Resume the saved payment before starting another booking.');
        }
        if (old == null &&
            !await prefs.setString(
                key, jsonEncode({...snapshot, 'uid': uid}))) {
          throw StateError('Could not save payment recovery state.');
        }
      });

  static Future<void> resolveDeliverySnapshot(String uid, String quoteId) =>
      _serial(() async {
        final prefs = await SharedPreferences.getInstance();
        final key = '${_key(uid, 'delivery')}.snapshot';
        final raw = prefs.getString(key);
        if (raw != null && jsonDecode(raw)['quoteId'] == quoteId) {
          if (!await prefs.remove(key)) {
            throw StateError('Could not clear payment recovery state.');
          }
        }
      });
}
