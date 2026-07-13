import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app.dart';
import 'app/account/bloc/account_bloc.dart';
import 'app/send_package/bloc/send_package_bloc.dart';
import 'firebase_options.dart';
import 'helper/chats_help.dart';
import 'helper/notifications_helper.dart';
import 'web_sender_app.dart';

part 'messaging.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final SendPackageBloc sendPackageBloc = SendPackageBloc();
final AccountBloc accountBloc = AccountBloc();
final NotificationService _notificationService = NotificationService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
    } on FirebaseException catch (error) {
      if (error.code != 'duplicate-app') rethrow;
    }
    if (const bool.fromEnvironment('CIRCUM_RIDER_HOSTING')) {
      runApp(const CircumRiderWebApp());
    } else {
      runApp(const WebSenderApp());
    }
    return;
  }

  await Firebase.initializeApp();
  if (!kIsWeb) {
    await _configureNotifications();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    foregoundMessage();
  }

  runApp(const App());
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
