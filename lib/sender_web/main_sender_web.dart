import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../main.dart' show CircumSenderStartup;
import '../web_sender_app.dart' show WebSenderApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    CircumSenderStartup(
      initializer: _initializeFirebase,
      appBuilder: (_) => const WebSenderApp(useCanonicalSenderWeb: true),
    ),
  );
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app') rethrow;
  }
}
