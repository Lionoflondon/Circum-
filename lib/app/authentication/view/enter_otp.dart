import 'dart:async';

import 'package:circum/app/bottom_nav/view/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pinput/pinput.dart';

import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';
import 'add_details.dart';

class EnterOTPView extends StatefulWidget {
  const EnterOTPView({Key? key}) : super(key: key);

  @override
  EnterOTPViewState createState() => EnterOTPViewState();
}

class EnterOTPViewState extends State<EnterOTPView> {
  bool _isCountdownActive = false;
  int _countdown = 30;
  Timer? _countdownTimer;

  void startCountdown() {
    if (!_isCountdownActive) {
      _isCountdownActive = true;
      _countdown = 30;
      _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        setState(() {
          if (_countdown > 0) {
            _countdown--;
          } else {
            _isCountdownActive = false;
            _countdownTimer?.cancel();
          }
        });
      });
    }
  }

  void resetOTP() {
    if (!_isCountdownActive) {
      // Simulate OTP reset logic here
      print('Resetting OTP...');
      startCountdown();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state.status == Status.success) {
            context.read<AuthBloc>().add(ResetStatus());
            // context.read<AuthBloc>().add(StartCountDown());
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => AppNavView()),
            );
          }

          if (state.status == Status.incompleteData) {
            context.read<AuthBloc>().add(ResetStatus());
            // context.read<AuthBloc>().add(StartCountDown());
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const AddDetailsView()));
          }
        },
        child: Scaffold(
            backgroundColor: AppColors.secondary,
            appBar: AppBar(
              foregroundColor: Colors.white,
              backgroundColor: AppColors.secondary,
              centerTitle: true,
              title: AppText.text('Enter 4 Digit Code',
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            body: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        sentCodeToPhone(),
                        const SizedBox(height: 24),
                        pinInput(),
                        resendOTP(),
                      ],
                    ),
                    // Column(
                    //   children: [
                    //     const SizedBox(height: 20),
                    //     _errorMessage(),
                    //     const SizedBox(height: 20),
                    //     _contiuneButton(),
                    //     Container(
                    //         margin: const EdgeInsets.only(top: 20),
                    //         width: MediaQuery.of(context).size.width,
                    //         child: Center(child: _alreadyHaveAnAccount())),
                    //     const SizedBox(height: 50),
                    //   ],
                    // )
                  ],
                ))));
  }

  Widget sentCodeToPhone() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppText.text('A code was sent to ',
                  textAlign: TextAlign.center,
                  color: Colors.white,
                  fontSize: 16),
              AppText.text('${state.phoneNumber}',
                  textAlign: TextAlign.center,
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ],
          ));
    });
  }

  Widget resendOTP() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: _countdown == 0
              ? GestureDetector(
                  onTap: () {
                    // context.read<AuthBloc>().add(RequestForOTP());
                    // context.read<AuthBloc>().add(ResetCountdown());

                    resetOTP();
                  },
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppText.text(
                          'Didn’t receive code? ',
                          color: Colors.white,
                        ),
                        AppText.text('Resend OTP',
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                      ]))
              : _countdown == 30
                  ? GestureDetector(
                      onTap: () {
                        // context.read<AuthBloc>().add(RequestForOTP());
                        // context.read<AuthBloc>().add(ResetCountdown());

                        resetOTP();
                      },
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AppText.text(
                              'Didn’t receive code? ',
                              color: Colors.white,
                            ),
                            AppText.text('Resend OTP',
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary),
                          ]))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppText.text(
                          'Didn’t receive code? ',
                          color: Colors.white,
                        ),
                        AppText.text(
                          'Resend in $_countdown seconds',
                          color: Colors.white,
                        )
                      ],
                    ));
    });
  }

  Widget pinInput() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Column(children: [
        Pinput(
          hapticFeedbackType: HapticFeedbackType.lightImpact,
          keyboardType: TextInputType.number,
          autofocus: true,
          onCompleted: (pin) {
            context.read<AuthBloc>().add(SetOTP(otp: pin));
            context.read<AuthBloc>().add(VerifySentCode());
            // resetOTP();
          },
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
          ],
          defaultPinTheme: PinTheme(
              textStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'OpenSans'),
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.zero, color: AppColors.input)),
          length: 6,
        ),
        // AppText.text('text', color: Colors.white),
        if (state.errorMessage != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppText.text('${state.errorMessage}',
                  color: const Color(0xFFFF452B)))
      ]);
    });
  }

  Widget _errorMessage() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Container(
          padding:
              EdgeInsets.symmetric(vertical: state.errorMessage == '' ? 0 : 10),
          child: Text(state.errorMessage ?? '',
              style: const TextStyle(color: Colors.red)));
    });
  }

  Widget _contiuneButton() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return SizedBox(
          // margin: const EdgeInsets.symmetric(horizontal: 30),
          height: 50,
          width: MediaQuery.of(context).size.width * 0.8,
          child: AppButton.button(
              onPressed: () {
                if (state.status != Status.loading) {
                  context.read<AuthBloc>().add(SubmitOTP());
                }
              },
              widget: const Text(
                "Continue",
                style:
                    TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
              ),
              isLoading: state.status == Status.loading));
    });
  }

  Widget _alreadyHaveAnAccount() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return GestureDetector(
          onTap: () {
            context.read<AuthBloc>().add(
                  GotAnAccount(),
                );
          },
          child: const SizedBox(
              child: Text.rich(
            textAlign: TextAlign.center,
            TextSpan(
              children: [
                TextSpan(text: 'Already have an account? '),
                TextSpan(
                  text: 'Sign in',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          )));
    });
  }
}
