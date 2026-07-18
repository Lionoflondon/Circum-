import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../firebase_options.dart';
import '../send_package/bloc/send_package_bloc.dart';
import 'design_system/sender_design_system.dart';
import 'sender_accessibility.dart';
import 'sender_mobile_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  } else {
    await Firebase.initializeApp();
  }
  runApp(const SenderMobilePreviewApp());
}

class SenderMobilePreviewApp extends StatelessWidget {
  const SenderMobilePreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SendPackageBloc(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        builder: (context, child) => SenderAccessibilityHost(
          child: child ?? const SizedBox.shrink(),
        ),
        home: const SenderMobileHome(previewAuthEnabled: true),
      ),
    );
  }
}
