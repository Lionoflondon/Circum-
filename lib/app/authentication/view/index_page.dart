import 'package:flutter/material.dart';
// import 'package:flutter_svg/svg.dart';

import '../../../utils/theme/colors.dart';

class IndexPage extends StatelessWidget {
  const IndexPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: Center(
        child: Image.asset(
          'assets/images/splash.png',
          fit: BoxFit.fitWidth,
        ),
      ),
    );
  }
}
