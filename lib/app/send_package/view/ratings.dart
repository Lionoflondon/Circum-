import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/utils/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class RatingsView extends StatefulWidget {
  RatingsView({Key? key}) : super(key: key);

  @override
  State<RatingsView> createState() => _RatingsViewState();
}

class _RatingsViewState extends State<RatingsView> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: ((context, state) {
      return Scaffold(
        backgroundColor: AppColors.secondary,
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppText.text("Rate Courier’s Service",
                fontSize: 18, fontWeight: FontWeight.w600)
          ],
        ),
      );
    }));
  }
}
