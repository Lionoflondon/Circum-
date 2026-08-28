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
      runApp(const CircumWebsiteApp());
      unawaited(_activateAppCheckAfterStartup());
    },
    (error, stack) {
      if (_isAppCheckStartupError(error)) {
        if (kDebugMode) {
          debugPrint('Website service protection startup warning: $error');
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

Future<void> _activateAppCheckAfterStartup() async {
  try {
    final appCheckStartup = await initializeCircumAppCheck();
    if (appCheckStartup.blockStartup && kDebugMode) {
      debugPrint(
        'Website service protection warning: ${appCheckStartup.message}',
      );
    }
  } catch (error) {
    if (kDebugMode) {
      debugPrint('Website service protection warning: $error');
    }
  }
}

void _installAppCheckStartupBoundary() {
  PlatformDispatcher.instance.onError = (error, stack) {
    if (!_isAppCheckStartupError(error)) return false;
    if (kDebugMode) {
      debugPrint('Website service protection startup warning: $error');
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
