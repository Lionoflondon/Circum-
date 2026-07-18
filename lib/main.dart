import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app.dart';
import 'app/account/bloc/account_bloc.dart';
import 'app/security/circum_app_check.dart';
import 'app/sender_mobile/sender_notification_routing.dart';
import 'app/send_package/bloc/send_package_bloc.dart';
import 'helper/chats_help.dart';
import 'helper/notifications_helper.dart';

part 'messaging.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final SendPackageBloc sendPackageBloc = SendPackageBloc();
final AccountBloc accountBloc = AccountBloc();
final NotificationService _notificationService = NotificationService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final appCheckStartup = await initializeCircumAppCheck();
  if (appCheckStartup.blockStartup) {
    runApp(CircumStartupBlocked(message: appCheckStartup.message));
    return;
  }
  if (!kIsWeb) {
    await _configureNotifications();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    foregoundMessage();
    configureNotificationOpenRouting();
  }

  runApp(const App());
}

class CircumStartupBlocked extends StatelessWidget {
  const CircumStartupBlocked({required this.message, super.key});

  final String message;

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
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _configureNotifications() async {
  const androidSettings =
      AndroidInitializationSettings('@mipmap/launcher_icon');
  const iOSSettings = DarwinInitializationSettings();
  const settings = InitializationSettings(
    android: androidSettings,
    iOS: iOSSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(settings);
}
