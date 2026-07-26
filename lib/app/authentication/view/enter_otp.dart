// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pinput/pinput.dart';

import '../../../utils/app_state/app_state.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';

class EnterOTPView extends StatefulWidget {
  final bool deleteAccount;
  const EnterOTPView({super.key, this.deleteAccount = false});

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
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
    return Scaffold(
        backgroundColor: AppColors.secondary,
        appBar: AppBar(
          foregroundColor: Colors.white,
          backgroundColor: AppColors.secondary,
          centerTitle: true,
          title: AppText.text(
              widget.deleteAccount == true
                  ? 'Enter OTP to delete account'
                  : 'Enter 6 Digit Code',
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        body: BlocListener<AuthBloc, AuthState>(
            listener: (context, state) async {
              if (state.status == Status.success &&
                  widget.deleteAccount == false) {
                context.read<AuthBloc>().add(ResetStatus());
                // context.read<AuthBloc>().add(StartCountDown());
                Navigator.popUntil(context, (route) => route.isFirst);
                // Navigator.pushReplacement(
                //   context,
                //   MaterialPageRoute(builder: (_) => AppNavView()),
                // );
              }

              if (state.authenticatedStatus ==
                  AuthenticatedStatus.incompleteData) {
                // context.read<AuthBloc>().add(ResetStatus());
                Navigator.popUntil(context, (route) => route.isFirst);
              }

              if (state.currentState == AppState.unauthenticated &&
                  widget.deleteAccount == true) {
                Navigator.popUntil(context, (route) => route.isFirst);
                // await Future.delayed(const Duration(milliseconds: 500));
                // Navigator.pushReplacement(
                //     context, MaterialPageRoute(builder: (_) => App()));
              }
            },
            child: SizedBox(
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
          onCompleted: (pin) async {
            context.read<AuthBloc>().add(SetOTP(otp: pin));
            await Future.delayed(const Duration(microseconds: 300));
            if (widget.deleteAccount == true) {
              context.read<AuthBloc>().add(DeleteAccount());
            }

            context.read<AuthBloc>().add(VerifySentCode());
            // resetOTP();
          },
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
          ],
          defaultPinTheme: const PinTheme(
              textStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Helvetica'),
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
}
