part of 'auth_bloc.dart';

enum Status {
  initial,
  loading,
  locationRequested,
  success,
  failure,
  unverifiedEmail,
  signedInWithOAuth,
  passwordResetEmailSent,
}

enum AuthenticatedStatus { initial, incompleteData, authenticated }

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
  final String? errorMessage;
  final bool showPassword;
  final bool isPhoneNumberValid;
  final bool isEmailValid;
  final Position? locationData;
  final bool? isLocationEnabled;
  final bool? hasLocationPermission;
  final String? profilePhoto;

  // information extracted when the uses 0Auth sign in method
  final String? oAuthFirstName;
  final String? oAuthLastName;
  final String? oAuthEmail;
  final String? oAuthPhotoURL;

  final Status status;
  final AppLocationStatus appLocationStatus;
  final AuthenticatedStatus authenticatedStatus;

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
        errorMessage,
        status,
        showPassword,
        isPhoneNumberValid,
        isEmailValid,
        locationData,
        isLocationEnabled,
        hasLocationPermission,
        appLocationStatus,
        authenticatedStatus,
        profilePhoto,
        oAuthFirstName,
        oAuthLastName,
        oAuthEmail,
        oAuthPhotoURL
      ];

  const AuthState({
    this.unknownSessionState = false,
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
    this.pin,
    this.isLoading = false,
    this.errorMessage,
    this.status = Status.initial,
    this.showPassword = false,
    this.isPhoneNumberValid = false,
    this.isEmailValid = false,
    this.locationData,
    this.isLocationEnabled,
    this.hasLocationPermission,
    this.appLocationStatus = AppLocationStatus.unavailalbe,
    this.authenticatedStatus = AuthenticatedStatus.initial,
    this.profilePhoto,
    this.oAuthFirstName,
    this.oAuthLastName,
    this.oAuthEmail,
    this.oAuthPhotoURL,
  });

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
      String? pin,
      bool? isLoading,
      String? errorMessage,
      Status? status,
      bool? showPassword,
      bool? isPhoneNumberValid,
      bool? isEmailValid,
      Position? locationData,
      bool? isLocationEnabled,
      bool? hasLocationPermission,
      AppLocationStatus? appLocationStatus,
      AuthenticatedStatus? authenticatedStatus,
      String? profilePhoto,
      String? oAuthFirstName,
      String? oAuthLastName,
      String? oAuthEmail,
      String? oAuthPhotoURL}) {
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
        pin: pin ?? this.pin,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: errorMessage,
        status: status ?? this.status,
        showPassword: showPassword ?? this.showPassword,
        isPhoneNumberValid: isPhoneNumberValid ?? this.isPhoneNumberValid,
        isEmailValid: isEmailValid ?? this.isEmailValid,
        locationData: locationData ?? this.locationData,
        isLocationEnabled: isLocationEnabled ?? this.isLocationEnabled,
        hasLocationPermission:
            hasLocationPermission ?? this.hasLocationPermission,
        appLocationStatus: appLocationStatus ?? this.appLocationStatus,
        authenticatedStatus: authenticatedStatus ?? this.authenticatedStatus,
        profilePhoto: profilePhoto ?? this.profilePhoto,
        oAuthFirstName: oAuthFirstName ?? this.oAuthFirstName,
        oAuthLastName: oAuthLastName ?? this.oAuthLastName,
        oAuthEmail: oAuthEmail ?? this.oAuthEmail,
        oAuthPhotoURL: oAuthPhotoURL ?? this.oAuthPhotoURL);
  }
}
