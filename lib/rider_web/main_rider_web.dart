import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../shared_web/circum_web_bootstrap.dart';
import '../shared_web/circum_web_shell.dart';
import '../web_sender_app.dart' show CircumRiderWebApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    CircumWebBootstrap(
      section: CircumWebSection.rider,
      initializer: _initializeFirebase,
      appBuilder: (_) => const CircumRiderWebApp(),
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
