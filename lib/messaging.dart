part of './main.dart';

foregoundMessage() {
  // chatBloc.add(event);
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    // print('Message data: ${message.data}');

    if (message.data['type'] == 'connection') {
      if (message.data['status'] == 'accepted') {
        final mapData = _decodeCommunicationPayload(
          message,
          expectedType: 'connection',
          stage: 'foreground',
        );
        if (mapData != null) {
          sendPackageBloc.add(DeliveryAccepted(data: mapData));

          notifyUser(
              title: 'Circum Rider on the way!',
              body:
                  '${mapData['courierName'].split(' ').first.trim()} will be picking up your parcel soon.');
        }
      }
    }

    if (message.data['type'] == 'location-broadcast') {
      final mapData = _decodeCommunicationPayload(
        message,
        expectedType: 'location-broadcast',
        stage: 'foreground',
      );
      if (mapData != null) {
        sendPackageBloc.add(SetRiderLocation(data: mapData));
      }
    }

    if (message.data['type'] == 'payment') {
      final data = _decodeCommunicationPayload(
        message,
        expectedType: 'payment',
        stage: 'foreground',
      );
      if (data != null) {
        accountBloc.add(UpdatePaymentStatus(data: data));
      }
    }

    if (message.data['type'] == 'message') {
      final msg = _decodeCommunicationPayload(
        message,
        expectedType: 'message',
        stage: 'foreground',
      );
      if (msg == null) return;
      sendPackageBloc.add(IncomingMessage(data: msg));

      await ChatsHelper().storeChat(msg);
      notifyUser(title: 'New message', body: msg['message']);
    }

    if (message.data['type'] == 'delivery-completed') {
      final mapData = _decodeCommunicationPayload(
        message,
        expectedType: 'delivery-completed',
        stage: 'foreground',
      );
      if (mapData != null) {
        sendPackageBloc.add(DeliveryCompleted(data: mapData));
        notifyUser(title: 'Delivery completed!', body: '');
      }
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
      final mapData = _decodeCommunicationPayload(
        message,
        expectedType: 'connection',
        stage: 'background',
      );
      if (mapData != null) {
        sendPackageBloc.add(DeliveryAccepted(data: mapData));

        notifyUser(
            title: 'Circum Rider on the way!',
            body:
                '${mapData['courierName'].split(' ').first.trim()} will be picking up your parcel soon.');
      }
    }
  }

  if (message.data['type'] == 'message') {
    final msg = _decodeCommunicationPayload(
      message,
      expectedType: 'message',
      stage: 'background',
    );
    if (msg == null) return Future<void>.value();
    sendPackageBloc.add(IncomingMessage(data: msg));

    await ChatsHelper().storeChat(msg);

    notifyUser(title: 'New message', body: msg['message']);
  }

  if (message.data['type'] == 'payment') {
    final data = _decodeCommunicationPayload(
      message,
      expectedType: 'payment',
      stage: 'background',
    );
    if (data != null) {
      accountBloc.add(UpdatePaymentStatus(data: data));
    }
  }

  // if (message.data['type'] == 'message') {
  //   final msg = jsonDecode(message.data['data']);
  //   sendPackageBloc.add(IncomingMessage(data: msg));

  //   await ChatsHelper().storeChat(msg);
  // }

  if (message.data['type'] == 'delivery-completed') {
    final mapData = _decodeCommunicationPayload(
      message,
      expectedType: 'delivery-completed',
      stage: 'background',
    );
    if (mapData != null) {
      sendPackageBloc.add(DeliveryCompleted(data: mapData));

      notifyUser(title: 'Delivery completed!', body: '');
    }
  }

  return Future<void>.value();
}

Map<String, dynamic>? _decodeCommunicationPayload(
  RemoteMessage message, {
  required String expectedType,
  required String stage,
}) {
  try {
    final data = message.data['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    final jsonString = '${data ?? ''}'.trim();
    if (jsonString.isEmpty) {
      _logRecoverablePushPayload(
        expectedType: expectedType,
        stage: stage,
        reason: 'missing_data',
        messageId: message.messageId,
      );
      return null;
    }
    final decoded = jsonDecode(jsonString.replaceAll("'", '"'));
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    _logRecoverablePushPayload(
      expectedType: expectedType,
      stage: stage,
      reason: 'data_not_map',
      messageId: message.messageId,
    );
  } catch (error, stackTrace) {
    _logRecoverablePushPayload(
      expectedType: expectedType,
      stage: stage,
      reason: 'decode_failed',
      messageId: message.messageId,
      error: error,
      stackTrace: stackTrace,
    );
  }
  return null;
}

void _logRecoverablePushPayload({
  required String expectedType,
  required String stage,
  required String reason,
  String? messageId,
  Object? error,
  StackTrace? stackTrace,
}) {
  developer.log(
    'Recoverable Sender push payload discarded: '
    'type=$expectedType stage=$stage reason=$reason messageId=${messageId ?? 'unknown'}'
    '${error == null ? '' : ' error=$error'}',
    name: 'circum.sender.messaging',
    error: error,
    stackTrace: stackTrace,
  );
}

void notifyUser({required String title, required String body}) {
  _notificationService.showNotification(
    title: title,
    body: body,
  );
  return;
}
