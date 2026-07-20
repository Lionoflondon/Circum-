part of './main.dart';

foregoundMessage() {
  // chatBloc.add(event);
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    // print('Message data: ${message.data}');

    if (message.data['type'] == 'connection') {
      if (message.data['status'] == 'accepted') {
        try {
          // Remove leading and trailing whitespace
          String jsonString = message.data['data'].trim();

          // Replace single quotes with double quotes to make it valid JSON
          jsonString = jsonString.replaceAll("'", '"');

          // Parse the modified string into a map
          Map<String, dynamic> mapData = jsonDecode(jsonString);

          sendPackageBloc.add(DeliveryAccepted(data: mapData));

          notifyUser(
              title: 'Rider on the way!',
              body:
                  '${mapData['courierName'].split(' ').first.trim()} will be picking up your parcel soon.');
        } catch (_) {}
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
      } catch (_) {}
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
      notifyUser(title: 'New message', body: msg['message']);
    }

    if (message.data['type'] == 'delivery-completed') {
      try {
        // Remove leading and trailing whitespace
        String jsonString = message.data['data'].trim();

        // Replace single quotes with double quotes to make it valid JSON
        jsonString = jsonString.replaceAll("'", '"');

        // Parse the modified string into a map
        Map<String, dynamic> mapData = jsonDecode(jsonString);

        sendPackageBloc.add(DeliveryCompleted(data: mapData));
        notifyUser(title: 'Delivery completed!', body: '');
      } catch (_) {}
    }
  });
}

Future<void> configureNotificationOpenRouting() async {
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    _openSenderNotification(initialMessage);
  }

  FirebaseMessaging.onMessageOpenedApp.listen(_openSenderNotification);
}

void _openSenderNotification(RemoteMessage message) {
  SenderNotificationOpenBridge.instance.enqueue(
    SenderNotificationOpenRequest.fromPushData(message.data),
  );
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  // print('Message data: ${message.data}');

  if (message.data['type'] == 'connection') {
    if (message.data['status'] == 'accepted') {
      try {
        // Remove leading and trailing whitespace
        String jsonString = message.data['data'].trim();

        // Replace single quotes with double quotes to make it valid JSON
        jsonString = jsonString.replaceAll("'", '"');

        // Parse the modified string into a map
        Map<String, dynamic> mapData = jsonDecode(jsonString);

        sendPackageBloc.add(DeliveryAccepted(data: mapData));

        notifyUser(
            title: 'Rider on the way!',
            body:
                '${mapData['courierName'].split(' ').first.trim()} will be picking up your parcel soon.');
      } catch (_) {}
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

    notifyUser(title: 'New message', body: msg['message']);
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
    try {
      // Remove leading and trailing whitespace
      String jsonString = message.data['data'].trim();

      // Replace single quotes with double quotes to make it valid JSON
      jsonString = jsonString.replaceAll("'", '"');

      // Parse the modified string into a map
      Map<String, dynamic> mapData = jsonDecode(jsonString);

      sendPackageBloc.add(DeliveryCompleted(data: mapData));

      notifyUser(title: 'Delivery completed!', body: '');
    } catch (_) {}
  }

  return Future<void>.value();
}

void notifyUser({required String title, required String body}) {
  _notificationService.showNotification(
    title: title,
    body: body,
  );
  return;
}
