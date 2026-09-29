import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../business/business_access_view.dart';
import '../health_plus/view/health_plus.dart';
import '../send_package/view/ride_chats.dart';
import 'gift_mode_view.dart';
import 'gift_journey_draft.dart';
import 'gift_story_view.dart';
import 'sender_activity.dart';
import 'sender_wallet.dart';

typedef SenderNotificationOpenHandler =
    bool Function(SenderNotificationOpenRequest request);

const senderNotificationDeepLinkVersion = 1;
const _allowedSenderNotificationRoutes = <String>{
  'tracking',
  'conversation',
  'wallet',
  'gift',
  'health',
  'business',
  'profile',
  'activity',
  'notifications',
};

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
  final rawDestination =
      payload['deepLink'] ??
      parsedData['deepLink'] ??
      payload['destination'] ??
      parsedData['destination'];
  final explicitDestination = _decodeMap(rawDestination);
  final type = _firstText([payload['type'], parsedData['type']]);

  final route = _firstText([
    explicitDestination['route'],
    payload['route'],
    payload['screen'],
    payload['destinationRoute'],
    parsedData['route'],
    parsedData['screen'],
    parsedData['destinationRoute'],
    _routeForNotificationType(type),
  ]);

  final chatId = _safeIdText([
    payload['chatId'],
    payload['conversationId'],
    parsedData['chatId'],
    parsedData['conversationId'],
  ]);
  final deliveryId = _safeIdText([
    explicitDestination['deliveryId'],
    explicitDestination['requestId'],
    payload['deliveryId'],
    payload['requestId'],
    parsedData['deliveryId'],
    parsedData['requestId'],
  ]);
  final bookingId = _safeIdText([
    explicitDestination['bookingId'],
    payload['bookingId'],
    parsedData['bookingId'],
  ]);
  final giftId = _safeIdText([payload['giftId'], parsedData['giftId']]);
  final transactionId = _safeIdText([
    explicitDestination['transactionId'],
    payload['transactionId'],
    payload['walletTransactionId'],
    parsedData['transactionId'],
    parsedData['walletTransactionId'],
  ]);
  final referralId = _safeIdText([
    explicitDestination['referralId'],
    payload['referralId'],
    parsedData['referralId'],
  ]);
  final healthPickupId = _safeIdText([
    explicitDestination['healthPickupId'],
    payload['healthPickupId'],
    parsedData['healthPickupId'],
  ]);
  final businessId = _safeIdText([
    explicitDestination['businessId'],
    payload['businessId'],
    parsedData['businessId'],
  ]);
  final invoiceId = _safeIdText([
    explicitDestination['invoiceId'],
    payload['invoiceId'],
    parsedData['invoiceId'],
  ]);
  final action = _safeIdText([
    explicitDestination['action'],
    payload['action'],
    parsedData['action'],
  ]);

  return {
    'version': senderNotificationDeepLinkVersion,
    'route': _safeRoute(
      route,
      type: type,
      hasDeliveryId: deliveryId.isNotEmpty,
    ),
    if (chatId.isNotEmpty) 'chatId': chatId,
    if (deliveryId.isNotEmpty) 'deliveryId': deliveryId,
    if (bookingId.isNotEmpty) 'bookingId': bookingId,
    if (giftId.isNotEmpty) 'giftId': giftId,
    if (transactionId.isNotEmpty) 'transactionId': transactionId,
    if (referralId.isNotEmpty) 'referralId': referralId,
    if (healthPickupId.isNotEmpty) 'healthPickupId': healthPickupId,
    if (businessId.isNotEmpty) 'businessId': businessId,
    if (invoiceId.isNotEmpty) 'invoiceId': invoiceId,
    if (action.isNotEmpty) 'action': action,
  };
}

bool openSenderNotificationDestination(
  BuildContext context,
  Map<String, dynamic> destination, {
  VoidCallback? onOpenWallet,
  VoidCallback? onOpenActivity,
  VoidCallback? onOpenNotifications,
}) {
  final route = _safeRoute(_firstText([destination['route']]));
  switch (route) {
    case 'wallet':
      final referralId = _safeIdText([destination['referralId']]);
      if (referralId.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const SenderReferralScreen(),
            settings: const RouteSettings(
              name: '/sender-mobile/wallet/referrals',
            ),
          ),
        );
        return true;
      }
      if (onOpenWallet != null) {
        onOpenWallet();
      } else {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SenderWalletView()),
        );
      }
      return true;
    case 'gift':
      final giftId = _safeIdText([destination['giftId']]);
      final action = _safeIdText([destination['action']]);
      if (giftId.isNotEmpty && action == 'story') {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GiftStoryView(
              draft: GiftJourneyDraft.forMode(SenderGiftMode.someone).copyWith(
                giftRequestId: giftId,
                linkedGiftDeliveryStatus: 'delivered',
                riderCompletionAccepted: true,
                deliveryVerificationCompleted: true,
                deliveryAuditSuccessful: true,
              ),
              senderStoryId: giftId,
            ),
            settings: const RouteSettings(name: GiftStoryView.routeName),
          ),
        );
        return true;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const GiftModeView(),
          settings: const RouteSettings(name: GiftModeView.routeName),
        ),
      );
      return true;
    case 'health':
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const HealthPlusView()));
      return true;
    case 'business':
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BusinessAccessView()),
      );
      return true;
    case 'conversation':
      final chatId = _safeIdText([destination['chatId']]);
      if (chatId.isEmpty || FirebaseAuth.instance.currentUser == null) {
        onOpenNotifications?.call();
        return true;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              RideChatPageView(chatId: chatId.isEmpty ? null : chatId),
        ),
      );
      return true;
    case 'tracking':
      final deliveryId = _safeIdText([
        destination['deliveryId'],
        destination['bookingId'],
        destination['requestId'],
      ]);
      if (deliveryId.isEmpty || FirebaseAuth.instance.currentUser == null) {
        onOpenActivity?.call();
        if (onOpenActivity == null) onOpenNotifications?.call();
        return true;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SenderDeliveryDetailView(deliveryId: deliveryId),
        ),
      );
      return true;
    case 'activity':
      if (onOpenActivity != null) {
        onOpenActivity();
      } else {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SenderActivityView(
              onSendParcel: () {},
              onExploreGifts: () {},
            ),
          ),
        );
      }
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

String _safeIdText(Iterable<Object?> values) {
  for (final value in values) {
    final text = _firstText([value]);
    if (text.isNotEmpty &&
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$').hasMatch(text)) {
      return text;
    }
  }
  return '';
}

String _safeRoute(
  String value, {
  String type = '',
  bool hasDeliveryId = false,
}) {
  final normalized = value.trim().toLowerCase();
  if (_allowedSenderNotificationRoutes.contains(normalized)) return normalized;
  final legacy = type.trim().toLowerCase();
  if (hasDeliveryId || legacy.startsWith('delivery_')) return 'tracking';
  if (legacy == 'message' || legacy == 'chat_message') return 'conversation';
  if (legacy.startsWith('gift_')) return 'gift';
  if (legacy.startsWith('health_')) return 'health';
  if (legacy.startsWith('business_')) return 'business';
  if (legacy.startsWith('wallet_') ||
      legacy.startsWith('payment_') ||
      legacy.startsWith('roth_') ||
      legacy.startsWith('referral_')) {
    return 'wallet';
  }
  return 'notifications';
}

String _routeForNotificationType(String type) {
  final normalized = type.trim().toLowerCase();
  if (normalized == 'payment' ||
      normalized == 'wallet' ||
      normalized.startsWith('payment_') ||
      normalized.startsWith('wallet_')) {
    return 'wallet';
  }
  return switch (normalized) {
    'message' || 'chat_message' => 'conversation',
    'connection' ||
    'location-broadcast' ||
    'delivery-completed' ||
    'delivery' => 'tracking',
    'gift' || 'gifts' || 'gift_story_ready' => 'gift',
    'health' || 'health_plus' => 'health',
    'business' => 'business',
    _ => 'notifications',
  };
}
