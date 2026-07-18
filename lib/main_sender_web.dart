import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/sender_mobile/sender_mobile_home.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  runApp(const _SenderWebRoot());
}

class _SenderWebRoot extends StatelessWidget {
  const _SenderWebRoot();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Circum Sender',
      home: SenderMobileHome(previewAuthEnabled: true),
    );
  }
}
