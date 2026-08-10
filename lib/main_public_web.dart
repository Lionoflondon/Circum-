import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'website/shared/circum_website_app.dart';
import 'website/shared/firebase/website_firebase_options.dart';
import 'website/shared/security/circum_website_app_check.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _installAppCheckStartupBoundary();
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
      final appCheckStartup = await initializeCircumAppCheck();
      runApp(appCheckStartup.blockStartup
          ? _WebsiteSecurityRecovery(message: appCheckStartup.message)
          : const CircumWebsiteApp());
    },
    (error, stack) {
      if (_isAppCheckStartupError(error)) {
        if (kDebugMode) {
          debugPrint('Website App Check startup warning: $error');
        }
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'Circum public web startup',
        ),
      );
    },
  );
}

class _WebsiteSecurityRecovery extends StatelessWidget {
  const _WebsiteSecurityRecovery({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xff020713),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.security_outlined, color: Color(0xff32d6a0), size: 40),
                  const SizedBox(height: 16),
                  const Text('Security check required', style: TextStyle(color: Colors.white, fontSize: 22)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xffb8c2d8))),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => main(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

void _installAppCheckStartupBoundary() {
  PlatformDispatcher.instance.onError = (error, stack) {
    if (!_isAppCheckStartupError(error)) return false;
    if (kDebugMode) {
      debugPrint('Website App Check startup warning: $error');
    }
    return true;
  };
}

bool _isAppCheckStartupError(Object error) {
  final message = error.toString();
  return message.contains('AppCheck') ||
      message.contains('appCheck/recaptcha-error') ||
      message.contains('app-check');
}
