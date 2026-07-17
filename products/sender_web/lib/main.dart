import 'dart:convert';
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app.dart';
import 'app/account/bloc/account_bloc.dart';
import 'app/send_package/bloc/send_package_bloc.dart';
import 'sender_web/config/sender_firebase_options.dart';
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
    runApp(CircumSenderStartup(
      initializer: _initializeSenderWeb,
      appBuilder: (_) => const WebSenderApp(),
    ));
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

Future<void> _initializeSenderWeb() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app') rethrow;
  }
}

class CircumSenderStartup extends StatefulWidget {
  const CircumSenderStartup({
    super.key,
    required this.initializer,
    required this.appBuilder,
    this.timeout = const Duration(seconds: 20),
  });

  final Future<void> Function() initializer;
  final WidgetBuilder appBuilder;
  final Duration timeout;

  @override
  State<CircumSenderStartup> createState() => _CircumSenderStartupState();
}

class _CircumSenderStartupState extends State<CircumSenderStartup> {
  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _ready = false;
    });
    try {
      await widget.initializer().timeout(widget.timeout);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.appBuilder(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFF07090F),
        body: SafeArea(
          child: Center(
            child: Semantics(
              liveRegion: true,
              label:
                  _error == null ? 'Starting Circum' : 'Circum could not start',
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'CIRCUM',
                        style: TextStyle(
                          color: Color(0xFF3B82F6),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (_error == null) ...[
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Starting Circum',
                          style: TextStyle(
                            color: Color(0xFFF5F7FB),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ] else ...[
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFF87171),
                          size: 34,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Something went wrong.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFF5F7FB),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'We could not start the app. Check your connection and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF9CA8B8),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Reference: SND-START-001',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: _start,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
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
