import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../business/business_access_view.dart';
import '../health_plus/view/health_plus.dart';
import '../send_package/view/ride_chats.dart';
import 'gift_mode_view.dart';
import 'sender_booking_canvas.dart';
import 'sender_wallet.dart';

typedef SenderNotificationOpenHandler = bool Function(
  SenderNotificationOpenRequest request,
);

class SenderNotificationOpenRequest {
  final Map<String, dynamic> destination;

  const SenderNotificationOpenRequest({required this.destination});

  factory SenderNotificationOpenRequest.fromPushData(
    Map<String, dynamic> data,
  ) {
    return SenderNotificationOpenRequest(
      destination: parseSenderNotificationDestination(data),
    );
  }
}

class SenderNotificationOpenBridge {
  SenderNotificationOpenBridge._();

  static final instance = SenderNotificationOpenBridge._();

  SenderNotificationOpenHandler? _handler;
  SenderNotificationOpenRequest? _pending;

  void enqueue(SenderNotificationOpenRequest request) {
    final handler = _handler;
    if (handler == null || !handler(request)) {
      _pending = request;
    }
  }

  void register(SenderNotificationOpenHandler handler) {
    _handler = handler;
    final pending = _pending;
    if (pending == null) return;
    scheduleMicrotask(() {
      if (_handler == handler && handler(pending)) {
        _pending = null;
      }
    });
  }

  void unregister(SenderNotificationOpenHandler handler) {
    if (_handler == handler) {
      _handler = null;
    }
  }
}

Map<String, dynamic> parseSenderNotificationDestination(
  Map<String, dynamic> payload,
) {
  final parsedData = _decodeMap(payload['data']);
  final rawDestination = payload['destination'] ?? parsedData['destination'];
  final destination = _decodeMap(rawDestination);
  if (destination.isNotEmpty) return destination;

  final route = _firstText([
    payload['route'],
    payload['screen'],
    payload['destinationRoute'],
    parsedData['route'],
    parsedData['screen'],
    parsedData['destinationRoute'],
    _routeForNotificationType(
        _firstText([payload['type'], parsedData['type']])),
  ]);

  final chatId = _firstText([
    payload['chatId'],
    payload['conversationId'],
    parsedData['chatId'],
    parsedData['conversationId'],
  ]);
  final deliveryId = _firstText([
    payload['deliveryId'],
    parsedData['deliveryId'],
  ]);

  return {
    if (route.isNotEmpty) 'route': route,
    if (chatId.isNotEmpty) 'chatId': chatId,
    if (deliveryId.isNotEmpty) 'deliveryId': deliveryId,
  };
}

bool openSenderNotificationDestination(
  BuildContext context,
  Map<String, dynamic> destination, {
  VoidCallback? onOpenWallet,
  VoidCallback? onOpenNotifications,
}) {
  final route = _firstText([destination['route']]);
  switch (route) {
    case 'wallet':
      if (onOpenWallet != null) {
        onOpenWallet();
      } else {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const SenderWalletView(),
        ));
      }
      return true;
    case 'gift':
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const GiftModeView(),
        settings: const RouteSettings(name: GiftModeView.routeName),
      ));
      return true;
    case 'health':
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const HealthPlusView()),
      );
      return true;
    case 'business':
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BusinessAccessView()),
      );
      return true;
    case 'conversation':
      final chatId = _firstText([destination['chatId']]);
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            RideChatPageView(chatId: chatId.isEmpty ? null : chatId),
      ));
      return true;
    case 'tracking':
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SenderBookingCanvas()),
      );
      return true;
    case 'notifications':
      onOpenNotifications?.call();
      return true;
    default:
      onOpenNotifications?.call();
      return true;
  }
}

Map<String, dynamic> _decodeMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value.trim().replaceAll("'", '"'));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const {};
    }
  }
  return const {};
}

String _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = '${value ?? ''}'.trim();
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

String _routeForNotificationType(String type) => switch (type) {
      'payment' || 'wallet' => 'wallet',
      'message' || 'chat_message' => 'conversation',
      'connection' ||
      'location-broadcast' ||
      'delivery-completed' ||
      'delivery' =>
        'tracking',
      'gift' || 'gifts' => 'gift',
      'health' || 'health_plus' => 'health',
      'business' => 'business',
      _ => 'notifications',
    };
