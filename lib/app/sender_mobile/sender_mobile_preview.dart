import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../firebase_options.dart';
import '../security/circum_app_check.dart';
import '../send_package/bloc/send_package_bloc.dart';
import 'design_system/sender_design_system.dart';
import 'gift_mode_view.dart';
import 'sender_accessibility.dart';
import 'sender_mobile_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
    final appCheckStartup = await initializeCircumAppCheck();
    if (appCheckStartup.blockStartup) {
      runApp(_SenderWebStartupBlocked(message: appCheckStartup.message));
      return;
    }
  } else {
    await Firebase.initializeApp();
  }
  runApp(const SenderMobilePreviewApp());
}

class SenderMobilePreviewApp extends StatelessWidget {
  const SenderMobilePreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final initialRouteName = _initialSenderRouteName(Uri.base);
    final initialIndex =
        int.tryParse(Uri.base.queryParameters['tab'] ?? '')?.clamp(0, 4) ?? 0;
    final home = SenderMobileHome(
      initialAuthenticated: true,
      previewAuthEnabled: false,
      initialIndex: initialIndex,
      initialRouteName: initialRouteName,
    );
    return BlocProvider(
      create: (_) => SendPackageBloc(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        initialRoute: Navigator.defaultRouteName,
        routes: {Navigator.defaultRouteName: (_) => home},
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute<void>(
            builder: (_) => home,
            settings: const RouteSettings(name: Navigator.defaultRouteName),
          ),
        ],
        theme: AppTheme.dark(),
        builder: (context, child) => SenderAccessibilityHost(
          repository: const _PreviewSenderAccessibilityRepository(),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

String? _initialSenderRouteName(Uri uri) {
  final fragment = uri.fragment.trim();
  if (fragment == GiftModeView.routeName ||
      fragment == '#${GiftModeView.routeName}') {
    return GiftModeView.routeName;
  }
  return null;
}

class _PreviewSenderAccessibilityRepository
    implements SenderAccessibilityRepository {
  const _PreviewSenderAccessibilityRepository();

  @override
  Future<void> save(SenderAccessibilitySettings settings) async {}

  @override
  Stream<SenderAccessibilitySettings> watch() =>
      Stream.value(const SenderAccessibilitySettings());
}

class _SenderWebStartupBlocked extends StatelessWidget {
  const _SenderWebStartupBlocked({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final blocked = Scaffold(
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
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: Navigator.defaultRouteName,
      routes: {Navigator.defaultRouteName: (_) => blocked},
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute<void>(
          builder: (_) => blocked,
          settings: const RouteSettings(name: Navigator.defaultRouteName),
        ),
      ],
      title: 'Circum Sender',
    );
  }
}
