part of './main.dart';

foregoundMessage() {
  // chatBloc.add(event);
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    print('Got a message whilst in the foreground!');
    // print('Message data: ${message.data}');

    if (message.data['type'] == 'connection') {
      if (message.data['status'] == 'accepted') {
        print('accepted');
        try {
          // Remove leading and trailing whitespace
          String jsonString = message.data['data'].trim();

          // Replace single quotes with double quotes to make it valid JSON
          jsonString = jsonString.replaceAll("'", '"');
          print(jsonString);

          // Parse the modified string into a map
          Map<String, dynamic> mapData = jsonDecode(jsonString);

          sendPackageBloc.add(DeliveryAccepted(data: mapData));
        } catch (e) {
          print(e);
        }
      }
    }

    if (message.data['type'] == 'location-broadcast') {
      try {
        // Remove leading and trailing whitespace
        String jsonString = message.data['data'].trim();

        // Replace single quotes with double quotes to make it valid JSON
        jsonString = jsonString.replaceAll("'", '"');
        // print(jsonString);

        // Parse the modified string into a map
        Map<String, dynamic> mapData = jsonDecode(jsonString);

        sendPackageBloc.add(SetRiderLocation(data: mapData));
      } catch (e) {
        print(e);
      }
    }

    if (message.data['type'] == 'payment') {
      // print(message.data['data']);
      Map<String, dynamic> data = jsonDecode(message.data['data']);
      accountBloc.add(UpdatePaymentStatus(data: data));
    }

    if (message.data['type'] == 'message') {
      // Parse the modified string into a map
      Map<String, dynamic> msg = jsonDecode(message.data['data']);
      sendPackageBloc.add(IncomingMessage(data: msg));

      await ChatsHelper().storeChat(msg);
    }

    if (message.data['type'] == 'delivery-completed') {
      print('Delivery completed');
      try {
        // Remove leading and trailing whitespace
        String jsonString = message.data['data'].trim();

        // Replace single quotes with double quotes to make it valid JSON
        jsonString = jsonString.replaceAll("'", '"');
        print(jsonString);

        // Parse the modified string into a map
        Map<String, dynamic> mapData = jsonDecode(jsonString);

        sendPackageBloc.add(DeliveryCompleted(data: mapData));
      } catch (e) {
        print(e);
      }
    }
  });
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();

  print('Got a message whilst in the background!');
  // print('Message data: ${message.data}');

  if (message.data['type'] == 'connection') {
    if (message.data['status'] == 'accepted') {
      print('accepted');
      try {
        // Remove leading and trailing whitespace
        String jsonString = message.data['data'].trim();

        // Replace single quotes with double quotes to make it valid JSON
        jsonString = jsonString.replaceAll("'", '"');
        print(jsonString);

        // Parse the modified string into a map
        Map<String, dynamic> mapData = jsonDecode(jsonString);

        sendPackageBloc.add(DeliveryAccepted(data: mapData));
      } catch (e) {
        print(e);
      }
    }
  }

  if (message.data['type'] == 'message') {
    // Remove leading and trailing whitespace
    String jsonString = message.data['data'].trim();

    // Replace single quotes with double quotes to make it valid JSON
    jsonString = jsonString.replaceAll("'", '"');
    // print(jsonString);

    // Parse the modified string into a map
    Map<String, dynamic> msg = jsonDecode(jsonString);
    sendPackageBloc.add(IncomingMessage(data: msg));

    await ChatsHelper().storeChat(msg);
  }

  if (message.data['type'] == 'payment') {
    // print(message.data['data']);
    Map<String, dynamic> data = jsonDecode(message.data['data']);
    accountBloc.add(UpdatePaymentStatus(data: data));
  }

  // if (message.data['type'] == 'message') {
  //   final msg = jsonDecode(message.data['data']);
  //   sendPackageBloc.add(IncomingMessage(data: msg));

  //   await ChatsHelper().storeChat(msg);
  // }

  if (message.data['type'] == 'delivery-completed') {
    print('Delivery completed');
    try {
      // Remove leading and trailing whitespace
      String jsonString = message.data['data'].trim();

      // Replace single quotes with double quotes to make it valid JSON
      jsonString = jsonString.replaceAll("'", '"');
      print(jsonString);

      // Parse the modified string into a map
      Map<String, dynamic> mapData = jsonDecode(jsonString);

      sendPackageBloc.add(DeliveryCompleted(data: mapData));
    } catch (e) {
      print(e);
    }
  }

  return Future<void>.value();
}
