import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../utils/theme/text_field.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';
// import 'success_screen.dart';

class CreateNewPasswordView extends StatelessWidget {
  const CreateNewPasswordView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state.status == Status.success) {
            context.read<AuthBloc>().add(ResetStatus());
            // AppNavView()
            // AdvisorView()

            Navigator.popUntil(context, (route) => route.isFirst);
            // Navigator.push(context,
            //     MaterialPageRoute(builder: (_) => const SuccessScreenView()));
          }
        },
        child: Scaffold(
            backgroundColor: Colors.white,
            body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: SizedBox(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                            width: MediaQuery.of(context).size.width,
                            margin: const EdgeInsets.only(
                              top: 80,
                            ),
                            child: AppText.text("Create new password",
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 24)),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: MediaQuery.of(context).size.width,
                          child: AppText.text(
                            'Please create a unique password',
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 44),
                        _passwordField(),
                        const SizedBox(height: 20),
                        _confirmPasswordField(),
                        const SizedBox(height: 20),
                        _OTPField(),
                        const SizedBox(height: 20),
                        _errorMessage(),
                        const SizedBox(height: 40),
                        _resetPasswordButton(),
                      ],
                    )))));
  }
}

Widget _resetPasswordButton() {
  return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
    return SizedBox(
        // margin: const EdgeInsets.symmetric(horizontal: 30),
        height: 50,
        width: MediaQuery.of(context).size.width * 0.8,
        child: AppButton.button(
            onPressed: () {
              context.read<AuthBloc>().add(ResetPassword(email: state.email!));
            },
            widget: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Reset Password",
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Colors.white),
                ),
                state.isLoading
                    ? const SizedBox(
                        width: 20,
                      )
                    : Container(),
                state.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          color: Colors.white,
                        ))
                    : Container()
              ],
            )));
  });
}

Widget _passwordField() {
  return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppText.text('New Password',
          color: Colors.white, fontWeight: FontWeight.bold),
      const SizedBox(height: 4),
      AppTextInput.input(
        obscureText: true,
        maxLines: 1,
        minLines: 1,
        hintText: '(8+ characters)',
        onChanged: (value) => context.read<AuthBloc>().add(
              SignupPasswordChanged(password: value),
            ),
      )
    ]);
  });
}

Widget _OTPField() {
  return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppText.text('OTP', color: Colors.white, fontWeight: FontWeight.bold),
      const SizedBox(height: 4),
      AppTextInput.input(
        maxLines: 1,
        minLines: 1,
        hintText: '******',
        onChanged: (value) => context.read<AuthBloc>().add(
              SetResetPasswordOTP(otp: value),
            ),
      )
    ]);
  });
}

Widget _confirmPasswordField() {
  return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppText.text('Confirm Password',
          color: Colors.white, fontWeight: FontWeight.bold),
      const SizedBox(height: 4),
      AppTextInput.input(
        obscureText: true,
        maxLines: 1,
        minLines: 1,
        hintText: '(8+ characters)',
        onChanged: (value) => context.read<AuthBloc>().add(
              ConfirmPasswordChanged(password: value),
            ),
      )
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
