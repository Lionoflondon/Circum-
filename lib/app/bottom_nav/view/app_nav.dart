import 'package:flutter/material.dart';

import '../../sender_mobile/sender_mobile_home.dart';

class AppNavView extends StatelessWidget {
  const AppNavView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SenderMobileHome(previewAuthEnabled: true);
  }
}
