import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../../../utils/theme/text_field.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';
import 'signin.dart';

class SignupForm extends StatefulWidget {
  SignupForm({Key? key}) : super(key: key);

  @override
  SignupFormState createState() => SignupFormState();
}

class SignupFormState extends State<SignupForm> {
  static final _formKey = GlobalKey<FormState>();

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // final BuildContext authBlocContext;

  @override
  Widget build(BuildContext context) {
    return _signupForm(context);
  }

  Widget _signupForm(context) {
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
                        // const SizedBox(height: 20),
                        _emailField(),
                        const SizedBox(height: 20),
                        _passwordField(),
                      ],
                    ))),
            Column(
              children: [
                _errorMessage(),
                const SizedBox(height: 20),
                _signupButton(),
                const SizedBox(height: 20),
                _alreadyHaveAnAccount()
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget phoneInput() {
    const _initialCountryCode = 'GB';
    var _country =
        countries.firstWhere((element) => element.code == _initialCountryCode);
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.text('Mobile Number', color: Colors.white),
          const SizedBox(height: 12),
          IntlPhoneField(
            style:
                const TextStyle(color: Colors.white, fontFamily: 'Helvetica'),
            dropdownTextStyle:
                const TextStyle(color: Colors.white, fontFamily: 'Helvetica'),
            decoration: InputDecoration(
              fillColor: AppColors.input,
              filled: true,
              labelStyle: const TextStyle(
                  fontFamily: 'Helvetica',
                  fontSize: 14.0,
                  fontWeight: FontWeight.w500,
                  color: AppColors.grey),
              // hintText: '9020020222',
              hintStyle: TextStyle(
                  color: const Color(0xFF050529).withOpacity(0.25),
                  fontFamily: 'Helvetica'),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(0)),
                borderSide: BorderSide(width: 1, color: AppColors.primary),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(0)),
                borderSide: BorderSide(color: Color(0xFF050529)),
              ),
            ),
            initialCountryCode: _initialCountryCode,
            onCountryChanged: (country) {
              print(country.name);
              _country = country;
              if (state.phoneNumber != null) {
                if (state.phoneNumber!.length - country.dialCode.length - 1 >=
                        country.minLength &&
                    state.phoneNumber!.length - country.dialCode.length - 1 <=
                        country.maxLength) {
                  context
                      .read<AuthBloc>()
                      .add(const ValidatePhoneNumber(val: true));
                  print('valid');
                } else {
                  context
                      .read<AuthBloc>()
                      .add(const ValidatePhoneNumber(val: false));
                  print('invalid');
                }
              }
            },
            onChanged: (val) {
              // print('Changed');
              if (val.number.length >= _country.minLength &&
                  val.number.length <= _country.maxLength) {
                context
                    .read<AuthBloc>()
                    .add(const ValidatePhoneNumber(val: true));
              } else {
                context
                    .read<AuthBloc>()
                    .add(const ValidatePhoneNumber(val: false));
              }
              context
                  .read<AuthBloc>()
                  .add(PhoneNumberChanged(phoneNumber: val.completeNumber));
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
            hintText: 'eg. example@gmail.com',
            controller: emailController,
            // initialValue: state.email ?? '',
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

  Widget _passwordField() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.text('Password', color: Colors.white),
          const SizedBox(height: 12),
          AppTextInput.input(
              obscureText: !state.showPassword,
              hintText: '(8+ characters)',
              maxLines: 1,
              minLines: 1,
              controller: passwordController,
              onChanged: (_) => setState(() {}),
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

  Widget _signupButton() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return SizedBox(
          height: 50,
          width: MediaQuery.of(context).size.width,
          child: AppButton.button(
            backgroundColor: state.isEmailValid == true &&
                    passwordController.text.length >= 8
                ? null
                : Colors.white.withOpacity(0.3),
            onPressed: () {
              // if (state.isPhoneNumberValid == true) {
              //   context.read<AuthBloc>().add(RequestForOTP());
              // }
              if (state.isEmailValid == false) {
                print('Email error');
                // print(state.isEmailValid);
                context.read<AuthBloc>().add(const SetErrorMessage(
                    errorMessage: 'Invalid email address'));
                return;
              }
              final password = passwordController.text;
              if (password.length >= 8) {
                context.read<AuthBloc>().add(
                    SignUpWithEmail(email: state.email!, password: password));
              }
            },
            widget: AppText.text('Create Account',
                fontWeight: FontWeight.w700, color: Colors.white),
            // isLoading: state.status == Status.loading
          ));
    });
  }

  Widget _alreadyHaveAnAccount() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return GestureDetector(
          onTap: () {
            emailController.text = '';
            passwordController.text = '';
            context.read<AuthBloc>().add(SignupEmailChanged(email: ''));
            context.read<AuthBloc>().add(SignupPasswordChanged(password: ''));
            Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SigninView()));
          },
          child: SizedBox(
              width: MediaQuery.of(context).size.width,
              child: const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: 'Already have an account? ',
                        style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Helvetica',
                            fontSize: 16)),
                    TextSpan(
                      text: 'Sign in',
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
