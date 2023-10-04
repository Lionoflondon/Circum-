import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';
import 'enter_otp.dart';
import 'signup_form.dart';

class SignupView extends StatelessWidget {
  const SignupView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state.status == Status.success) {
            context.read<AuthBloc>().add(ResetStatus());
            // context.read<AuthBloc>().add(StartCountDown());
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const EnterOTPView()));
          }
        },
        child: Scaffold(
            backgroundColor: AppColors.secondary,
            body: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                    width: MediaQuery.of(context).size.width,
                    margin: EdgeInsets.only(
                      left: 30,
                      top: 40 + MediaQuery.of(context).padding.top,
                    ),
                    child: AppText.text("Create Account",
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 28)),
                const Expanded(
                  child: SignupForm(),
                ),
                const SizedBox(height: 40),
              ],
            )));
  }
}
