import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/admin/admin_root.dart';
import 'app/admin/firebase/admin_firebase_options.dart';
import 'app/admin/security/admin_app_check.dart';

Future<void> main() async {
  await runZonedGuarded(_startAdmin, _handleAdminStartupError);
}

Future<void> _startAdmin() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installAppCheckStartupBoundary();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  if (circumWebRecaptchaEnterpriseSiteKey.trim().isEmpty) {
    runApp(
      const _AdminStartupBlocked(
        message:
            'Circum security verification is not configured for this version.',
      ),
    );
    return;
  }
  try {
    final appCheckStartup = await initializeCircumAppCheck();
    if (appCheckStartup.blockStartup) {
      runApp(_AdminStartupBlocked(message: appCheckStartup.message));
      return;
    }
    runApp(const AdminRoot());
  } catch (error) {
    runApp(
      const _AdminStartupBlocked(
        message:
            'Circum security verification could not start. Please try again.',
      ),
    );
  }
}

void _handleAdminStartupError(Object error, StackTrace stack) {
  final message = error.toString();
  final isAppCheckStartupError = message.contains('AppCheck') ||
      message.contains('appCheck/recaptcha-error') ||
      message.contains('app-check');
  if (isAppCheckStartupError) {
    if (kDebugMode) {
      debugPrint('Admin App Check warning: $message');
    }
    return;
  }
  if (kDebugMode) {
    debugPrint('Admin startup error: $message');
  }
}

void _installAppCheckStartupBoundary() {
  PlatformDispatcher.instance.onError = (error, stack) {
    final message = error.toString();
    final isAppCheckStartupError = message.contains('AppCheck') ||
        message.contains('appCheck/recaptcha-error') ||
        message.contains('app-check');
    if (!isAppCheckStartupError) return false;
    if (kDebugMode) {
      debugPrint('Admin App Check startup warning: $message');
    }
    return true;
  };
}

class _AdminStartupBlocked extends StatelessWidget {
  const _AdminStartupBlocked({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Circum Admin',
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
