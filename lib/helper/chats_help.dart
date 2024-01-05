import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ChatsHelper {
  Future<bool> storeChat(message) async {
    try {
      // final messageJson = jsonDecode(message.data['data']);

      print('In chats Helper');

      final directory = await getApplicationDocumentsDirectory();
      final chats = File('${directory.path}/${message['requestId']}.json');
      List jsonData = [];
      if (await chats.exists()) {
        final contents = await chats.readAsString();
        final parsingData = await jsonDecode(contents) as List;
        jsonData = [...parsingData];
      }
      jsonData.add(message);
      // final jsonDataa = jsonData.map((message) => message.toJson()).toList();
      final jsonString = jsonEncode(jsonData);

      await chats.writeAsString(jsonString);

      // print('Handling a background message ${message.messageId}');
      print('New message');
      print(message);

      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }
}
