import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'app.dart';
import 'app/sender_mobile/native_payment_return.dart';
import 'app/account/bloc/account_bloc.dart';
import 'app/security/circum_app_check.dart';
import 'app/sender_mobile/sender_notification_routing.dart';
import 'app/send_package/bloc/send_package_bloc.dart';
import 'env/env.dart';
import 'helper/chats_help.dart';
import 'helper/notifications_helper.dart';
import 'app/sender_mobile/sender_startup.dart';

part 'messaging.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final SendPackageBloc sendPackageBloc = SendPackageBloc();
final AccountBloc accountBloc = AccountBloc();
final NotificationService _notificationService = NotificationService();

const AndroidNotificationChannel _senderNotificationChannel =
    AndroidNotificationChannel(
  'circum_general',
  'Circum updates',
  description: 'Delivery, account, and service updates from Circum.',
  importance: Importance.high,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _startSender();
}

Future<FirebaseApp>? _firebaseInitialization;
bool _notificationHandlersRegistered = false;

Future<void> _startSender() => runSenderStartup(
      renderBoot: () => runApp(const CircumStartupBlocked()),
      initialize: () async {
        await _runCoreStartupStep('firebase', () async {
          if (Firebase.apps.isNotEmpty) return;
          try {
            await (_firebaseInitialization ??= Firebase.initializeApp());
          } catch (_) {
            _firebaseInitialization = null;
            rethrow;
          }
        });
        await _runCoreStartupStep('stripe', _configureStripe);
        final appCheckStartup = await initializeCircumAppCheck();
        if (appCheckStartup.blockStartup || !appCheckStartup.enabled) {
          developer.log(appCheckStartup.message, name: 'circum.sender.startup');
        }
      },
      renderApp: () => runApp(const App()),
      afterRenderApp: kIsWeb ? null : _initializeNotificationsAfterRender,
      onFailure: _recordStartupFailure,
      renderRecovery: () => runApp(
        CircumStartupBlocked(
          message: 'Circum could not start. Please try again.',
          onRetry: _startSender,
        ),
      ),
    );

Future<void> _runCoreStartupStep(
  String stage,
  Future<void> Function() initialize,
) async {
  try {
    await initialize();
  } catch (error, stackTrace) {
    _recordStartupFailure(stage, error, stackTrace);
    rethrow;
  }
}

void _recordStartupFailure(String stage, Object error, StackTrace stackTrace) {
  developer.log(
    'Sender startup failed at $stage',
    name: 'circum.sender.startup',
    error: error,
    stackTrace: stackTrace,
  );
  debugPrint('CIRCUM_STARTUP_FAILURE stage=$stage type=${error.runtimeType}');
}

Future<void> _initializeNotificationsAfterRender() async {
  await WidgetsBinding.instance.endOfFrame;
  await _configureNotifications();
  if (!_notificationHandlersRegistered) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    foregoundMessage();
    _notificationHandlersRegistered = true;
    await configureNotificationOpenRouting();
  }
  // Only FCM requests permission, after login has rendered. Local-notification
  // setup must not create a second permission prompt during application boot.
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
}

Future<void> _configureStripe() async {
  final key = Env.stripePublishableKey.trim();
  if (key.isEmpty) return;
  Stripe.publishableKey = key;
  if (!kIsWeb) {
    Stripe.merchantIdentifier = 'merchant.com.circum.app';
    Stripe.urlScheme = circumPaymentUrlScheme;
  }
  await Stripe.instance.applySettings();
}

class CircumStartupBlocked extends StatelessWidget {
  const CircumStartupBlocked({this.message, this.onRetry, super.key});

  final String? message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF07090F),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: message == null
                  ? const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF93C5FD),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (onRetry != null) ...[
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: onRetry,
                            child: const Text('Try again'),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _configureNotifications() async {
  const androidSettings = AndroidInitializationSettings(
    '@mipmap/launcher_icon',
  );
  const iOSSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  const settings = InitializationSettings(
    android: androidSettings,
    iOS: iOSSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings,
    onDidReceiveNotificationResponse: (response) {
      final rawPayload = response.payload?.trim() ?? '';
      if (rawPayload.isEmpty) return;
      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is Map) {
          SenderNotificationOpenBridge.instance.enqueue(
            SenderNotificationOpenRequest.fromPushData(
              Map<String, dynamic>.from(decoded),
            ),
          );
        }
      } catch (error, stackTrace) {
        developer.log(
          'Recoverable local notification payload discarded',
          name: 'circum.sender.messaging',
          error: error,
          stackTrace: stackTrace,
        );
      }
    },
  );
  final android =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(_senderNotificationChannel);
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
}
