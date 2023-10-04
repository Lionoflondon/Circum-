import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../utils/theme/text_field.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';

class ResetPasswordView extends StatelessWidget {
  final BuildContext authBlocContext;

  const ResetPasswordView({Key? key, required this.authBlocContext})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state.status == Status.success) {
            context.read<AuthBloc>().add(ResetStatus());
            // Navigator.push(context,
            //     MaterialPageRoute(builder: (_) => const CheckYourEmailView()));
          }
        },
        child: Scaffold(
            backgroundColor: AppColors.secondary,
            body: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            width: MediaQuery.of(context).size.width,
                            margin: const EdgeInsets.only(
                              left: 30,
                              top: 80,
                            ),
                            child: AppText.text("Reset password",
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 24)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 30),
                          child: AppText.text(
                              'Please enter registered email to get\npassword reset instruction',
                              color: Colors.white),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 30, right: 30, top: 50),
                          child: _emailField(),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const SizedBox(height: 40),
                        _sendButton(),
                        Container(
                            margin: const EdgeInsets.only(top: 20),
                            width: MediaQuery.of(context).size.width,
                            child: Center(child: _alreadyHaveAnAccount())),
                        const SizedBox(height: 50),
                      ],
                    )
                  ],
                ))));
  }
}

Widget _emailField() {
  return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppText.text('Email', color: Colors.white, fontWeight: FontWeight.bold),
      const SizedBox(height: 4),
      AppTextInput.input(
        hintText: 'eg. example@gmail.com',
        onChanged: (value) => context.read<AuthBloc>().add(
              SignupEmailChanged(email: value),
            ),
      )
    ]);
  });
}

Widget _sendButton() {
  return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
    return SizedBox(
        // margin: const EdgeInsets.symmetric(horizontal: 30),
        height: 50,
        width: MediaQuery.of(context).size.width * 0.8,
        child: AppButton.button(
            onPressed: () {
              // Navigator.push(
              //     context,
              //     MaterialPageRoute(
              //         builder: (_) => const CheckYourEmailView()));
              context.read<AuthBloc>().add(ForgotPassword());
            },
            widget: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Send",
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

Widget _alreadyHaveAnAccount() {
  return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
    return GestureDetector(
        onTap: () {
          context.read<AuthBloc>().add(
                GotAnAccount(),
              );
        },
        child: SizedBox(
            child: Text.rich(
          textAlign: TextAlign.center,
          TextSpan(
            children: [
              TextSpan(text: 'Remeber your password? '),
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
