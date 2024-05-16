import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/svg.dart';

import '../../../utils/theme/theme.dart';
import '../../bottom_nav/view/app_nav.dart';
import '../bloc/auth_bloc.dart';

class EnableLocation extends StatelessWidget {
  const EnableLocation({Key? key}) : super(key: key);

  final FlutterSecureStorage storage = const FlutterSecureStorage();

  locationAllowed() async {
    await storage.write(key: 'location', value: 'allowed');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.secondary,
        body: BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              if (state.status == Status.locationRequested) {
                // print('EnableLocationlistener');
                context.read<AuthBloc>().add(ResetStatus());
                locationAllowed();
                Navigator.popUntil(context, (route) => route.isFirst);
                // context.read<AuthBloc>().add(StartCountDown());
                // Navigator.pushReplacement(
                //   context,
                //   MaterialPageRoute(builder: (_) => AppNavView()),
                // );
              }
            },
            child: WillPopScope(
              // Intercept the back button press
              onWillPop: () async {
                return false;
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset('assets/svg/map_pin.svg'),
                  const SizedBox(height: 64),
                  AppText.text(
                      'Get the most out of Circum by\nenabling location services.',
                      textAlign: TextAlign.center,
                      fontSize: 20,
                      fontWeight: FontWeight.w600),
                  const SizedBox(height: 48),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: AppButton.button(
                          widget: Center(
                            child: AppText.text('Enable',
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          onPressed: () {
                            context.read<AuthBloc>().add(RequestLocationData());
                          })),
                  const SizedBox(height: 16),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: AppButton.button(
                          backgroundColor: AppColors.secondary,
                          widget: Center(
                            child: AppText.text('Skip',
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          onPressed: () {
                            Navigator.popUntil(
                                context, (route) => route.isFirst);
                            // Navigator.pushReplacement(
                            //     context,
                            //     MaterialPageRoute(
                            //         builder: (_) => AppNavView()));
                          }))
                ],
              ),
            )));
  }
}
