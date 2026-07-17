import 'dart:async';

import 'package:circum/app/authentication/view/add_details.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';
import 'enter_otp.dart';
import 'signup_form.dart';

class VerifyEmailView extends StatefulWidget {
  const VerifyEmailView({Key? key}) : super(key: key);

  @override
  VerifyEmailViewState createState() => VerifyEmailViewState();
}

class VerifyEmailViewState extends State<VerifyEmailView> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    setTimerForAutoRedirect();
  }

  setTimerForAutoRedirect() {
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      print('timer active');
      context.read<AuthBloc>().add(ConfirmEmailVerification());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.secondary,
        appBar: AppBar(
          backgroundColor: AppColors.secondary,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: BlocListener<AuthBloc, AuthState>(listener: (context, state) {
          if (state.status == Status.success) {
            _timer.cancel();
            context.read<AuthBloc>().add(ResetStatus());
            Navigator.popUntil(context, (route) => route.isFirst);
          }

          if (state.authenticatedStatus == AuthenticatedStatus.incompleteData) {
            _timer.cancel();
            context.read<AuthBloc>().add(ResetStatus());
            Navigator.popUntil(context, (route) => route.isFirst);
          }
        }, child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SizedBox(
                //   height: MediaQuery.of(context).padding.top,
                // ),
                _loader(),
                Container(
                    width: MediaQuery.of(context).size.width,
                    margin: const EdgeInsets.only(left: 30, top: 30),
                    child: AppText.text("Verify your email \naddress",
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 28)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                  child: Icon(
                    CupertinoIcons.envelope,
                    color: AppColors.primary,
                    size: 40,
                  ),
                ),
                Padding(
                    padding: const EdgeInsets.only(left: 30, bottom: 10),
                    child: AppText.text(state.email!,
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: AppText.text(
                        'Please check your email and click on the link to verify your email address.')),
                const SizedBox(height: 40),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: AppText.text(
                        'If not automatically redirected after verification,\nclick continue')),
                const SizedBox(height: 20),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: AppButton.button(
                        widget: Center(
                            child: AppText.text("I've verified my email")),
                        onPressed: () {
                          context
                              .read<AuthBloc>()
                              .add(ConfirmEmailVerification());
                        })),
                const SizedBox(height: 20),
                GestureDetector(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: AppText.text('Resend E-mail',
                          color: AppColors.primary)),
                ),
                const SizedBox(height: 40),
              ],
            );
          },
        )));
  }

  Widget _loader() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return state.status == Status.loading
          ? LinearProgressIndicator(color: AppColors.primary)
          : Container();
    });
  }
}
