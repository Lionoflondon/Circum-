part of 'auth_bloc.dart';

class FirstNameChanged extends AuthEvent {
  final String firstName;

  FirstNameChanged({required this.firstName});
}

class LastNameChanged extends AuthEvent {
  final String lastName;

  LastNameChanged({required this.lastName});
}

class UsernameChanged extends AuthEvent {
  final String username;
  UsernameChanged({required this.username});
}

class GenderChanged extends AuthEvent {
  final String gender;
  GenderChanged({required this.gender});
}

class SignupEmailChanged extends AuthEvent {
  final String? email;

  SignupEmailChanged({this.email});
}

class SignupPhoneNumberChanged extends AuthEvent {
  final String? phoneNumber;

  SignupPhoneNumberChanged({this.phoneNumber});
}

class SignupPasswordChanged extends AuthEvent {
  final String? password;

  SignupPasswordChanged({this.password});
}

class SignupSubmitted extends AuthEvent {}

class GotAnAccount extends AuthEvent {}

class ChangedAccountType extends AuthEvent {
  final String account;
  ChangedAccountType({required this.account});
}

class CountryChanged extends AuthEvent {
  final value;
  CountryChanged({this.value});
}

class ToggleObscure extends AuthEvent {}

class SignupUser extends AuthEvent {}

class CreateAPin extends AuthEvent {}

class ForgotPassword extends AuthEvent {}

class ResetPassword extends AuthEvent {}
