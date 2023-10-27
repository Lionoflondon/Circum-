part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object> get props => [];
}

class SortSessionState extends AuthEvent {
  // BuildContext context;
  // SortSessionState({required this.context});
}

class ChangeAppState extends AuthEvent {
  final String state;
  ChangeAppState({required this.state});
}

class ChangeSelectedPage extends AuthEvent {
  final String page;
  ChangeSelectedPage({required this.page});
}

class AccountRegistrationType extends AuthEvent {
  final bool isemail;
  final dynamic focusManager;
  final dynamic focusNode;
  AccountRegistrationType(
      {required this.isemail, this.focusManager, this.focusNode});
}

class EmailChanged extends AuthEvent {
  final String email;
  EmailChanged({required this.email});
}

class PhoneNumberChanged extends AuthEvent {
  final String phoneNumber;
  PhoneNumberChanged({required this.phoneNumber});
}

class ConfirmPasswordChanged extends AuthEvent {
  final String password;
  ConfirmPasswordChanged({required this.password});
}

class DateOfBirthChanged extends AuthEvent {
  final String dateOfBirth;
  DateOfBirthChanged({required this.dateOfBirth});
}

class VerificationCodeChanged extends AuthEvent {
  final int verificationCode;
  VerificationCodeChanged({required this.verificationCode});
}

class VerifyEmail extends AuthEvent {}

class SetOTP extends AuthEvent {
  final String otp;
  SetOTP({required this.otp});
}

class SetResetPasswordOTP extends AuthEvent {
  final String otp;
  SetResetPasswordOTP({required this.otp});
}

class SubmitOTP extends AuthEvent {}

class SubmitRegistrationDetails extends AuthEvent {}

class SetVerificationMethod extends AuthEvent {
  final String method;
  SetVerificationMethod({required this.method});
}

class RequestForOTP extends AuthEvent {}

class RegisterUser extends AuthEvent {}

class LoginUser extends AuthEvent {}

class SetPin extends AuthEvent {
  final String pin;
  const SetPin({required this.pin});
}

class CreateAuthPin extends AuthEvent {
  final String pin;
  const CreateAuthPin({required this.pin});
}

class UpdatePhone extends AuthEvent {}

class HandleUserLogin extends AuthEvent {
  final data;
  const HandleUserLogin({required this.data});
}

class ResetStatus extends AuthEvent {}

class StartCountDown extends AuthEvent {}

class ResetCountdown extends AuthEvent {}

class SetShowPassword extends AuthEvent {
  final bool val;
  SetShowPassword({required this.val});
}

class ValidatePhoneNumber extends AuthEvent {
  final bool val;

  const ValidatePhoneNumber({required this.val});
}

class VerifySentCode extends AuthEvent {}

class UpdateUserProfile extends AuthEvent {
  final String username;
  const UpdateUserProfile({required this.username});
}

class RequestLocationData extends AuthEvent {}

class OpenSettingsApp extends AuthEvent {}
