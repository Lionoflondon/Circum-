import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatsHelper {
  Future<bool> storeChat(message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _chatKey(message['requestId']);
      final contents = prefs.getString(key);
      final jsonData = contents == null ? [] : jsonDecode(contents) as List;

      jsonData.add(message);
      final jsonString = jsonEncode(jsonData);

      await prefs.setString(key, jsonString);

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List> loadChat(String requestId) async {
    final prefs = await SharedPreferences.getInstance();
    final contents = prefs.getString(_chatKey(requestId));
    if (contents == null) return [];
    return jsonDecode(contents) as List;
  }

  String _chatKey(Object? requestId) => 'chat_${requestId ?? 'unknown'}';
}
