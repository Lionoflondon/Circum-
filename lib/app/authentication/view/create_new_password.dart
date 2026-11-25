import 'package:flutter/widgets.dart';
import 'forgot_password.dart';

/// Legacy entrypoint redirects to the single secure email recovery flow.
class CreateNewPasswordView extends StatelessWidget {
  const CreateNewPasswordView({super.key});
  @override
  Widget build(BuildContext context) => const ForgotPasswordView();
}
