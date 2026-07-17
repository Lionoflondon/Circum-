import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'public_web/config/public_firebase_options.dart';
import 'public_web/bootstrap/public_web_bootstrap.dart';
import 'public_web/shell/public_web_shell.dart';
import 'public_web/public_app.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    CircumWebBootstrap(
      section: CircumWebSection.home,
      showSectionNavigation: false,
      initializer: _initializePublicFirebase,
      appBuilder: (_) => const CircumPublicWebsiteApp(),
    ),
  );
}

Future<void> _initializePublicFirebase() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app') rethrow;
  }
}
