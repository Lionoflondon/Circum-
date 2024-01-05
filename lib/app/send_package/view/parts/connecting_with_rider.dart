import 'package:flutter/material.dart';

import '../../../../utils/theme/theme.dart';

class ConnectingWithARider extends StatefulWidget {
  const ConnectingWithARider({Key? key}) : super(key: key);

  @override
  State<ConnectingWithARider> createState() => _ConnectingWithARiderState();
}

class _ConnectingWithARiderState extends State<ConnectingWithARider> {
  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
        child: Column(
          children: [
            AppText.text('Connecting with courier',
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
            const SizedBox(height: 36),
            const LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: Color(0xFF1F292E),
              color: AppColors.primary,
            ),
          ],
        ));
  }
}
