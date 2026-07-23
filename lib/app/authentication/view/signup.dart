import 'package:circum/app/authentication/view/verify_email.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';
import 'signup_form.dart';

class SignupView extends StatelessWidget {
  const SignupView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state.status == Status.success) {
            context.read<AuthBloc>().add(ResetStatus());
            // context.read<AuthBloc>().add(StartCountDown());
            // Navigator.push(context,
            //     MaterialPageRoute(builder: (_) => const EnterOTPView()));
          }

          if (state.status == Status.unverifiedEmail) {
            context.read<AuthBloc>().add(ResetStatus());
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VerifyEmailView()),
            );
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: MediaQuery.of(context).padding.top),
            _loader(),
            Container(
              width: MediaQuery.of(context).size.width,
              margin: const EdgeInsets.only(left: 30, top: 40),
              child: AppText.text(
                "Create Account",
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 28,
              ),
            ),
            Expanded(child: const SignupForm()),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _loader() {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        return state.status == Status.loading
            ? LinearProgressIndicator(color: AppColors.primary)
            : Container();
      },
    );
  }
}
