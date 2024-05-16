import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../utils/theme/text_field.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';

class ForgotPasswordView extends StatefulWidget {
  ForgotPasswordView({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.secondary,
        appBar: AppBar(
          foregroundColor: Colors.white,
          backgroundColor: AppColors.secondary,
        ),
        body: BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              if (state.status == Status.passwordResetEmailSent) {
                context.read<AuthBloc>().add(ResetStatus());
                context.read<AuthBloc>().add(SignupEmailChanged(email: ''));
                Navigator.pop(context);
                BotToast.showCustomNotification(
                    duration: const Duration(seconds: 20),
                    toastBuilder: (_) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 10),
                        margin: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: Color.fromARGB(255, 50, 152, 53),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check, color: Colors.white),
                            const SizedBox(width: 6),
                            Expanded(
                                child: AppText.text(
                                    'Password reset instructions have been sent to your email.',
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      );
                    });
              }
            },
            child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _loader(),
                  Container(
                      width: MediaQuery.of(context).size.width,
                      margin: const EdgeInsets.only(
                        left: 30,
                        top: 10,
                      ),
                      child: AppText.text("Forgot password?",
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 28)),
                  const SizedBox(height: 30),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: _emailField()),
                  const Spacer(),
                  _errorMessage(),
                  Padding(
                      padding: const EdgeInsets.only(left: 30, right: 30),
                      child: _resetPasswordButton()),
                  const SizedBox(height: 40)
                ])));
  }

  Widget _loader() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return state.status == Status.loading
          ? LinearProgressIndicator(color: AppColors.primary)
          : Container();
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

  Widget _emailField() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppText.text('Email', color: Colors.white),
        const SizedBox(height: 12),
        AppTextInput.input(
            hintText: '',
            initialValue: state.email,
            onChanged: (value) =>
                context.read<AuthBloc>().add(SignupEmailChanged(email: value)),
            surfix: Container(
                padding: const EdgeInsets.only(right: 10),
                width: 80,
                child: Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => context
                          .read<AuthBloc>()
                          .add(SetShowPassword(val: !state.showPassword)),
                      child: state.isEmailValid == true
                          ? const Icon(CupertinoIcons.check_mark_circled,
                              color: AppColors.primary)
                          : const Icon(CupertinoIcons.check_mark_circled,
                              color: Colors.transparent),
                    )))
            //  context.read<AuthBloc>().add(
            //       SignupEmailChanged(email: value),
            //     ),
            )
      ]);
    });
  }

  Widget _resetPasswordButton() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return SizedBox(
          height: 50,
          width: MediaQuery.of(context).size.width,
          child: AppButton.button(
              backgroundColor: state.isEmailValid == true
                  ? null
                  : Colors.white.withOpacity(0.3),
              onPressed: () async {
                // Navigator.push(
                //     context,
                //     MaterialPageRoute(
                //         builder: (_) =>
                //             EnterOTPView(authBlocContext: authBlocContext)));
                // context.read<AuthBloc>().add(RequestForOTP());
                // context.read<AuthBloc>().add(RequestForOTP());
                if (state.isEmailValid == false) {
                  print('Email error');
                  // print(state.isEmailValid);
                  context.read<AuthBloc>().add(const SetErrorMessage(
                      errorMessage: 'Invalid email address'));
                  return;
                } else {
                  context
                      .read<AuthBloc>()
                      .add(ResetPassword(email: state.email!));
                }
              },
              widget: AppText.text('Reset password',
                  fontWeight: FontWeight.w700, color: Colors.white),
              isLoading: state.isLoading));
    });
  }
}
