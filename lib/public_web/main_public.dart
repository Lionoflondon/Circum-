import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../firebase_options.dart';
import '../shared_web/circum_web_bootstrap.dart';
import '../shared_web/circum_web_shell.dart';
import 'public_app.dart';

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
