import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../../../utils/theme/text_field.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';
import 'forgot_password.dart';
import 'signup.dart';

class SigninForm extends StatefulWidget {
  const SigninForm({Key? key}) : super(key: key);

  @override
  SigninFormState createState() => SigninFormState();
}

class SigninFormState extends State<SigninForm> {
  static final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return _signupForm();
  }

  Widget _signupForm() {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 30),
                        // phoneInput(),
                        _emailField(),
                        const SizedBox(height: 20),
                        _passwordField(),
                      ],
                    ))),
            Column(
              children: [
                _errorMessage(),
                const SizedBox(height: 10),
                _signinButton(),
                const SizedBox(height: 20),
                _dontHaveAnAccount()
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget phoneInput() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.text('Mobile Number',
              color: Colors.white, fontWeight: FontWeight.bold),
          const SizedBox(height: 4),
          IntlPhoneField(
            style: const TextStyle(color: Colors.white, fontFamily: 'OpenSans'),
            dropdownTextStyle:
                const TextStyle(color: Colors.white, fontFamily: 'OpenSans'),
            decoration: InputDecoration(
              fillColor: AppColors.input,
              filled: true,
              labelStyle: const TextStyle(
                  fontFamily: 'OpenSans',
                  fontSize: 14.0,
                  fontWeight: FontWeight.w500,
                  color: AppColors.grey),
              // hintText: '9020020222',
              hintStyle: TextStyle(
                  color: const Color(0xFF050529).withOpacity(0.25),
                  fontFamily: 'OpenSans'),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(0)),
                borderSide: BorderSide(width: 1, color: AppColors.primary),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(0)),
                borderSide: BorderSide(color: Color(0xFF050529)),
              ),
            ),
            initialCountryCode: 'GB',
            onChanged: (phone) {
              // print(phone.completeNumber);
              context
                  .read<AuthBloc>()
                  .add(PhoneNumberChanged(phoneNumber: phone.completeNumber));
            },
          )
        ],
      );
    });
  }

  Widget _emailField() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppText.text('Email', color: Colors.white),
        const SizedBox(height: 12),
        AppTextInput.input(
            hintText: '',
            // initialValue: state.email,
            controller: emailController,
            onChanged: (value) =>
                context.read<AuthBloc>().add(SignupEmailChanged(email: value)),
            surfix: Container(
                padding: const EdgeInsets.only(right: 10),
                width: 60,
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

  Widget _passwordField() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.text('Password', color: Colors.white),
          const SizedBox(height: 12),
          AppTextInput.input(
              obscureText: !state.showPassword,
              hintText: '',
              maxLines: 1,
              minLines: 1,
              controller: passwordController,
              onChanged: (value) => context
                  .read<AuthBloc>()
                  .add(SignupPasswordChanged(password: value)),
              surfix: Container(
                  padding: const EdgeInsets.only(right: 10),
                  width: 80,
                  child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => context
                            .read<AuthBloc>()
                            .add(SetShowPassword(val: !state.showPassword)),
                        child: state.showPassword == true
                            ? const Icon(CupertinoIcons.eye,
                                color: AppColors.primary)
                            : const Icon(CupertinoIcons.eye_slash,
                                color: Color(0xFF415058)),
                      )))),
          const SizedBox(height: 20),
          GestureDetector(
              onTap: () {
                emailController.text = '';
                passwordController.text = '';
                context.read<AuthBloc>().add(SignupEmailChanged(email: ''));
                context
                    .read<AuthBloc>()
                    .add(SignupPasswordChanged(password: ''));
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ForgotPasswordView()));
              },
              child: AppText.text('Forgot password?',
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold))
        ],
      );
    });
  }

  Widget _confirmPasswordField() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.text('Confirm Password',
              color: Colors.white, fontWeight: FontWeight.bold),
          const SizedBox(
            height: 4,
          ),
          const SizedBox(height: 10),
          AppTextInput.input(
              obscureText: true,
              hintText: '(8+ characters)',
              maxLines: 1,
              minLines: 1,
              onChanged: (value) => context
                  .read<AuthBloc>()
                  .add(ConfirmPasswordChanged(password: value))
              // context.read<AuthBloc>().add(
              //       ConfirmPasswordChanged(password: value),
              //     ),
              )
        ],
      );
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

  Widget _signinButton() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return SizedBox(
          height: 50,
          width: MediaQuery.of(context).size.width,
          child: AppButton.button(
              backgroundColor: state.isEmailValid == true &&
                      state.password != null &&
                      state.password!.length >= 8
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
                }
                if (state.password != null && state.password!.length >= 8) {
                  context.read<AuthBloc>().add(SignInWithEmail(
                      email: state.email!, password: state.password!));
                }
              },
              widget: AppText.text('Sign In',
                  fontWeight: FontWeight.w700, color: Colors.white),
              isLoading: state.isLoading));
    });
  }

  Widget _dontHaveAnAccount() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return GestureDetector(
          onTap: () {
            emailController.text = '';
            passwordController.text = '';
            context.read<AuthBloc>().add(SignupEmailChanged(email: ''));
            context.read<AuthBloc>().add(SignupPasswordChanged(password: ''));
            Navigator.pop(context);
          },
          child: SizedBox(
              width: MediaQuery.of(context).size.width,
              child: const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: 'New to Circum? ',
                        style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'OpenSans',
                            fontSize: 16)),
                    TextSpan(
                      text: 'Create Account',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )));
    });
  }
}
