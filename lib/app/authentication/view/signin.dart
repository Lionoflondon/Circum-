import 'package:circum/app/authentication/view/verify_email.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';
import 'enable_location.dart';
import 'signin_form.dart';

class SigninView extends StatelessWidget {
  const SigninView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.secondary,
        body: BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              if (state.status == Status.success) {
                context.read<AuthBloc>().add(ResetStatus());
                // Navigator.popUntil(context, (route) => route.isFirst);
                // Navigator.push(
                //   context,
                //   MaterialPageRoute(builder: (_) => const EnableLocation()),
                // );
              }

              if (state.status == Status.unverifiedEmail) {
                context.read<AuthBloc>().add(ResetStatus());
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const VerifyEmailView()));
              }
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  height: MediaQuery.of(context).padding.top,
                ),
                _loader(),
                Container(
                    width: MediaQuery.of(context).size.width,
                    margin: const EdgeInsets.only(
                      left: 30,
                      top: 40,
                    ),
                    child: AppText.text("Sign In",
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 28)),
                Expanded(
                  child: SigninForm(),
                ),
                const SizedBox(height: 40),
              ],
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
