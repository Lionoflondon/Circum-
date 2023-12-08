part of 'auth_bloc.dart';

enum Status {
  initial,
  loading,
  locationRequested,
  success,
  failure,
  incompleteData
}

enum AppLocationStatus {
  denied,
  unavailalbe,
  available,
}

abstract class AuthInitial extends Equatable {
  const AuthInitial();

  // @override
  // List<Object> get props => [];

  // @override
  // String toString() => '$runtimeType{}';
}

class AuthState extends AuthInitial {
  final bool unknownSessionState;
  final bool isAuthenticated;
  final bool isUnAuthenticated;
  final bool registerWithEmail;
  final bool isLoading;

  final String currentState;
  final String? selectedPage;
  final String? firstName;
  final String? lastName;
  final String? username;
  final String? email;
  final String? phoneNumber;
  final String? password;
  final String? confirmPassword;
  final String? dateOfBirth;
  final String? gender;
  final String? pin;
  final String? otp;
  final String? resetPasswordOtp;
  final String? errorMessage;
  final int? verificationCode;
  final String? verificationType;
  final bool showPassword;
  final bool isPhoneNumberValid;
  final String? verificationId;
  final int? resendToken;
  final Position? locationData;
  final bool? isLocationEnabled;
  final bool? hasLocationPermission;

  final Status status;
  final AppLocationStatus appLocationStatus;

  final int countdown;

  @override
  List<Object?> get props => [
        unknownSessionState,
        isAuthenticated,
        isUnAuthenticated,
        registerWithEmail,
        isLoading,
        currentState,
        selectedPage,
        firstName,
        lastName,
        username,
        email,
        phoneNumber,
        password,
        confirmPassword,
        dateOfBirth,
        gender,
        pin,
        otp,
        resetPasswordOtp,
        errorMessage,
        verificationCode,
        verificationType,
        status,
        countdown,
        showPassword,
        isPhoneNumberValid,
        verificationId,
        resendToken,
        locationData,
        isLocationEnabled,
        hasLocationPermission,
        appLocationStatus
      ];

  const AuthState(
      {this.unknownSessionState = false,
      this.isAuthenticated = false,
      this.isUnAuthenticated = true,
      this.registerWithEmail = true,
      this.currentState = AppState.unknownSessionState,
      this.selectedPage,
      this.firstName,
      this.lastName,
      this.username,
      this.email,
      this.phoneNumber,
      this.password,
      this.confirmPassword,
      this.dateOfBirth,
      this.gender,
      this.otp,
      this.resetPasswordOtp,
      this.pin,
      this.isLoading = false,
      this.errorMessage,
      this.verificationCode,
      this.verificationType,
      this.status = Status.initial,
      this.countdown = 30,
      this.showPassword = false,
      this.isPhoneNumberValid = false,
      this.verificationId,
      this.resendToken,
      this.locationData,
      this.isLocationEnabled,
      this.hasLocationPermission,
      this.appLocationStatus = AppLocationStatus.unavailalbe});

  AuthState copyWith(
      {bool? unknownSessionState,
      bool? isAuthenticated,
      bool? isUnAuthenticated,
      bool? registerWithEmail,
      String? currentState,
      String? selectedPage,
      String? firstName,
      String? lastName,
      String? username,
      String? email,
      String? phoneNumber,
      String? password,
      String? confirmPassword,
      String? dateOfBirth,
      String? gender,
      String? otp,
      String? resetPasswordOtp,
      String? pin,
      bool? isLoading,
      String? errorMessage,
      int? verificationCode,
      String? verificationType,
      Status? status,
      int? countdown,
      bool? showPassword,
      bool? isPhoneNumberValid,
      String? verificationId,
      int? resendToken,
      Position? locationData,
      bool? isLocationEnabled,
      bool? hasLocationPermission,
      AppLocationStatus? appLocationStatus}) {
    return AuthState(
        unknownSessionState: unknownSessionState ?? this.unknownSessionState,
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isUnAuthenticated: isUnAuthenticated ?? this.isUnAuthenticated,
        registerWithEmail: registerWithEmail ?? this.registerWithEmail,
        currentState: currentState ?? this.currentState,
        selectedPage: selectedPage ?? this.selectedPage,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        username: username ?? this.username,
        email: email ?? this.email,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        password: password ?? this.password,
        confirmPassword: confirmPassword ?? this.confirmPassword,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        gender: gender ?? this.gender,
        otp: otp ?? this.otp,
        resetPasswordOtp: resetPasswordOtp ?? this.resetPasswordOtp,
        pin: pin ?? this.pin,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: errorMessage,
        verificationCode: verificationCode ?? this.verificationCode,
        verificationType: verificationType ?? this.verificationType,
        status: status ?? this.status,
        countdown: countdown ?? this.countdown,
        showPassword: showPassword ?? this.showPassword,
        isPhoneNumberValid: isPhoneNumberValid ?? this.isPhoneNumberValid,
        verificationId: verificationId ?? this.verificationId,
        resendToken: resendToken ?? this.resendToken,
        locationData: locationData ?? this.locationData,
        isLocationEnabled: isLocationEnabled ?? this.isLocationEnabled,
        hasLocationPermission:
            hasLocationPermission ?? this.hasLocationPermission,
        appLocationStatus: appLocationStatus ?? this.appLocationStatus);
  }
}
