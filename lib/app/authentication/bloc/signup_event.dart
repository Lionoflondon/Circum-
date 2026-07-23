part of 'auth_bloc.dart';

class FirstNameChanged extends AuthEvent {
  final String firstName;

  const FirstNameChanged({required this.firstName});
}

class LastNameChanged extends AuthEvent {
  final String lastName;

  const LastNameChanged({required this.lastName});
}

class UsernameChanged extends AuthEvent {
  final String username;
  const UsernameChanged({required this.username});
}

class GenderChanged extends AuthEvent {
  final String gender;
  const GenderChanged({required this.gender});
}

class SignupEmailChanged extends AuthEvent {
  final String? email;

  const SignupEmailChanged({this.email});
}

class SignupPhoneNumberChanged extends AuthEvent {
  final String? phoneNumber;

  const SignupPhoneNumberChanged({this.phoneNumber});
}

class SignupPasswordChanged extends AuthEvent {
  final String? password;

  const SignupPasswordChanged({this.password});
}

class SignupSubmitted extends AuthEvent {}

class GotAnAccount extends AuthEvent {}

class ChangedAccountType extends AuthEvent {
  final String account;
  const ChangedAccountType({required this.account});
}

class CountryChanged extends AuthEvent {
  final Object? value;
  const CountryChanged({this.value});
}

class ToggleObscure extends AuthEvent {}

class SignupUser extends AuthEvent {}

class CreateAPin extends AuthEvent {}

class ForgotPassword extends AuthEvent {}
