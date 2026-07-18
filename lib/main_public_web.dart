import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/security/circum_app_check.dart';
import 'firebase_options.dart';
import 'website/shared/circum_website_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  final appCheckStartup = await initializeCircumAppCheck();
  if (appCheckStartup.blockStartup) {
    runApp(_PublicWebStartupBlocked(message: appCheckStartup.message));
    return;
  }
  runApp(const CircumWebsiteApp());
}

class _PublicWebStartupBlocked extends StatelessWidget {
  const _PublicWebStartupBlocked({required this.message});

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
