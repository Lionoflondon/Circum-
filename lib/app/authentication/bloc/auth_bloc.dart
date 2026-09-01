import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:circum/utils/app_state/app_state.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
// import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart'
    as permission_handler;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../sender_mobile/sender_profile_authority.dart';
import '../../../helper/location_helper.dart';
import '../../../extension/email_validation.dart';
// import '../../onboarding/view/onboarding.dart';

part 'auth_event.dart';
part 'auth_state.dart';
part 'signup_event.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  static const _authOperationTimeout = Duration(seconds: 20);

  String _createAppleNonce([int length = 32]) {
    const alphabet =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  FirebaseAuth auth = FirebaseAuth.instance;
  FirebaseFirestore db = FirebaseFirestore.instance;
  FirebaseFunctions functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  // Init firestore and geoFlutterFire
  // final geo = GeoFlutterFire();
  LocationHelper locationHelper = LocationHelper();
  AuthBloc() : super(AuthState()) {
    void listenForPermissionStatus() async {
      await permission_handler.Permission.location.status;
    }

    listenForPermissionStatus();

    on<SortSessionState>(_handleSortSessionState);
    on<ResetStatus>(_handleResetStatus);
    on<StartCountDown>(_handleStartCountDown);
    on<ResetCountdown>(_handleResetCountdown);
    on<SignupEmailChanged>(_handleSignupEmailChanged);
    on<PhoneNumberChanged>(_handlePhoneNumberChanged);
    on<SignupPasswordChanged>(_handleSignupPasswordChanged);
    on<ConfirmPasswordChanged>(_handleConfirmPasswordChanged);
    on<DateOfBirthChanged>(_handleDateOfBirthChanged);
    on<SetOTP>(_handleSetOTP);
    on<SetPin>(_handleSetPin);
    on<SignInWithAppleAuth>(_handleSignInWithAppleAuth);
    on<SignInWithGoogle>(_handleSignInWithGoogle);
    on<RequestForOTP>(_handleRequestForOTP);
    on<VerifySentCode>(_handleVerifySentCode);
    on<SubmitOTP>(_handleSubmitOTP);
    on<FirstNameChanged>(_handleFirstNameChanged);
    on<LastNameChanged>(_handleLastNameChanged);
    on<UsernameChanged>(_handleUsernameChanged);
    on<GenderChanged>(_handleGenderChanged);
    on<SetVerificationMethod>(_handleSetVerificationMethod);
    on<SetResetPasswordOTP>(_handleSetResetPasswordOTP);
    on<ForgotPassword>(_handleForgotPassword);
    on<ResetPassword>(_handleResetPassword);
    on<SetShowPassword>(_handleSetShowPassword);
    on<ValidatePhoneNumber>(_handleValidatePhoneNumber);
    on<RequestLocationData>(_handleRequestLocationData);
    on<UpdateUserProfile>(_handleUpdateUserProfile);
    on<OpenSettingsApp>(_handleOpenSettingsApp);
    on<UpdateFirstName>(_handleUpdateFirstName);
    on<UpdateLastName>(_handleUpdateLastName);
    on<SetErrorMessage>(_handleSetErrorMessage);
    on<SignInWithEmail>(_handleSignInWithEmail);
    on<SignUpWithEmail>(_handleSignUpWithEmail);
    on<ConfirmEmailVerification>(_handleConfirmEmailVerification);
    on<UpdatePhoneNumber>(_handleUpdatePhoneNumber);
    on<UpdateUserProfilePhoto>(_handleUpdateUserProfilePhoto);
    on<SignOut>(_handleSignOut);
  }

  Future<void> _updateSenderProfile({
    String? displayName,
    String? username,
    String? phone,
  }) async {
    final payload = <String, dynamic>{
      if (displayName != null && displayName.trim().isNotEmpty)
        'displayName': displayName.trim(),
      if (username != null && username.trim().isNotEmpty)
        'username': username.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    };
    await functions
        .httpsCallable('updateSenderProfile')
        .call(payload)
        .timeout(_authOperationTimeout);
  }

  Future<void> _updateSenderLocation(Position locationData) async {
    final point =
        GeoFirePoint(GeoPoint(locationData.latitude, locationData.longitude));
    final raw = point.data;
    await functions.httpsCallable('updateSenderLocation').call({
      'position': {
        'latitude': locationData.latitude,
        'longitude': locationData.longitude,
        'geohash': raw['geohash'],
      },
    }).timeout(_authOperationTimeout);
  }

  void _logRecoverableAuthError(String step, Object error,
      [StackTrace? stack]) {
    final code = error is FirebaseException ? error.code : error.runtimeType;
    debugPrint('Sender auth recoverable failure [$step]: $code');
    if (stack != null && kDebugMode) debugPrint('$stack');
  }

  Future<String?> _hydrateSenderSession(User user, String phase) async {
    final storage = const FlutterSecureStorage();
    final profile = await SenderProfileAuthority(
      auth: auth,
      firestore: db,
      functions: functions,
    ).load(phase);
    final phone = profile.data['phone'] ?? user.phoneNumber;
    if (phone != null && '$phone'.trim().isNotEmpty) {
      await storage
          .write(key: 'phone', value: '$phone')
          .timeout(_authOperationTimeout);
      return '$phone';
    }
    return null;
  }

  Future<String?> _hydrateSenderSessionRecoverably(
      User user, String phase) async {
    try {
      return await _hydrateSenderSession(user, phase)
          .timeout(_authOperationTimeout);
    } catch (error, stack) {
      _logRecoverableAuthError('$phase.deferred', error, stack);
      return null;
    }
  }

  Future<bool> _sendVerificationEmail(User user, String phase) async {
    try {
      await user.sendEmailVerification().timeout(_authOperationTimeout);
      return true;
    } catch (error, stack) {
      _logRecoverableAuthError(phase, error, stack);
      return false;
    }
  }

  Future<void> _handleSortSessionState(
      SortSessionState event, Emitter<AuthState> emit) async {
    try {
      final user = auth.currentUser;
      if (user == null) {
        emit(state.copyWith(currentState: AppState.unauthenticated));
        return;
      }
      final phone = await _hydrateSenderSessionRecoverably(
          user, 'auth.restore.profile');
      emit(state.copyWith(
        currentState: AppState.authenticated,
        username: user.displayName,
        phoneNumber: phone,
        email: user.email,
        profilePhoto: user.photoURL,
        authenticatedStatus: user.displayName == null
            ? AuthenticatedStatus.incompleteData
            : AuthenticatedStatus.authenticated,
      ));
    } catch (error, stack) {
      _logRecoverableAuthError('session_restore', error, stack);
      emit(state.copyWith(
        currentState: AppState.unauthenticated,
        status: Status.failure,
        errorMessage:
            'Your session could not be restored. Please sign in again.',
      ));
    }
  }

  void _handleResetStatus(ResetStatus event, Emitter<AuthState> emit) {
    emit(state.copyWith(status: Status.initial));
  }

  void _handleStartCountDown(StartCountDown event, Emitter<AuthState> emit) {
    int countdown = state.countdown;
    const oneSec = Duration(seconds: 1);
    Timer.periodic(
      oneSec,
      (Timer timer) {
        if (state.countdown == 0) {
          timer.cancel();
        } else {
          emit(state.copyWith(countdown: countdown--));
        }
      },
    );
  }

  void _handleResetCountdown(ResetCountdown event, Emitter<AuthState> emit) {
    if (state.countdown < 30) {
      emit(state.copyWith(countdown: 59));
      add(StartCountDown());
    } else {
      emit(state.copyWith(countdown: 30));
      add(StartCountDown());
    }
  }

  void _handleSignupEmailChanged(
      SignupEmailChanged event, Emitter<AuthState> emit) {
    emit(state.copyWith(email: event.email));
    if (event.email!.isValidEmail()) {
      emit(state.copyWith(isEmailValid: true));
      // print('Valid email!');
    } else {
      emit(state.copyWith(isEmailValid: false));
      // print('Invalid email!');
    }
  }

  void _handlePhoneNumberChanged(
      PhoneNumberChanged event, Emitter<AuthState> emit) {
    emit(state.copyWith(phoneNumber: event.phoneNumber));
  }

  void _handleSignupPasswordChanged(
      SignupPasswordChanged event, Emitter<AuthState> emit) {
    emit(state.copyWith(password: event.password));
  }

  void _handleConfirmPasswordChanged(
      ConfirmPasswordChanged event, Emitter<AuthState> emit) {
    emit(state.copyWith(confirmPassword: event.password));
  }

  void _handleDateOfBirthChanged(
      DateOfBirthChanged event, Emitter<AuthState> emit) {
    if (event.dateOfBirth.length == 10) {
      var inputFormat = DateFormat('dd/MM/yyyy');
      var date1 = inputFormat.parse(event.dateOfBirth);

      var outputFormat = DateFormat('yyyy-MM-dd');
      var date2 = outputFormat.format(date1);
      emit(state.copyWith(dateOfBirth: date2));
    } else {
      emit(state.copyWith(dateOfBirth: event.dateOfBirth));
    }
  }

  void _handleSetOTP(SetOTP event, Emitter<AuthState> emit) {
    emit(state.copyWith(otp: event.otp));
  }

  void _handleSetPin(SetPin event, Emitter<AuthState> emit) {
    emit(state.copyWith(pin: event.pin));
    add(SubmitOTP());
  }

  Future<void> _handleSignInWithAppleAuth(
      SignInWithAppleAuth event, Emitter<AuthState> emit) async {
    try {
      emit(state.copyWith(status: Status.loading));
      final rawNonce = _createAppleNonce();
      final nonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      ).timeout(_authOperationTimeout);

      final oauthCredential = OAuthProvider("apple.com").credential(
          idToken: appleCredential.identityToken,
          rawNonce: rawNonce);

      UserCredential userCredential = await auth
          .signInWithCredential(oauthCredential)
          .timeout(_authOperationTimeout);

      final user = userCredential.user;
      if (user == null) {
        emit(state.copyWith(
          status: Status.failure,
          errorMessage:
              'Apple sign-in could not be completed. Please try again.',
        ));
        return;
      }

      final fullName = [appleCredential.givenName, appleCredential.familyName]
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .join(' ');
      if (fullName.isNotEmpty && user.displayName != fullName) {
        await user.updateDisplayName(fullName).timeout(_authOperationTimeout);
        await _updateSenderProfile(displayName: fullName);
      }
      final phone = await _hydrateSenderSessionRecoverably(
          user, 'auth.apple.profile');

      emit(state.copyWith(
          username: user.displayName ?? fullName,
          email: user.email,
          phoneNumber: phone,
          profilePhoto: user.photoURL,
          status: Status.signedInWithOAuth,
          currentState: AppState.authenticated,
          authenticatedStatus: fullName.isEmpty && user.displayName == null
              ? AuthenticatedStatus.incompleteData
              : AuthenticatedStatus.authenticated));
    } catch (e, stack) {
      _logRecoverableAuthError('apple_sign_in', e, stack);
      emit(state.copyWith(
        status: Status.failure,
        errorMessage: 'Apple sign-in could not be completed. Please try again.',
      ));
    }
  }

  void _handleRequestForOTP(
      RequestForOTP event, Emitter<AuthState> emit) async {
    final completer = Completer<bool>();

    String? verificationIdValue;
    int? resendTokenValue;

    try {
      emit(state.copyWith(status: Status.loading));
      await auth.verifyPhoneNumber(
        phoneNumber: state.phoneNumber,
        verificationCompleted: (_) {},
        verificationFailed: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
        codeSent: (String verificationId, int? resendToken) async {
          verificationIdValue = verificationId;
          resendTokenValue = resendToken;
          if (!completer.isCompleted) completer.complete(true);
        },
        codeAutoRetrievalTimeout: (_) {
          if (!completer.isCompleted) {
            completer.completeError(TimeoutException('phone_otp_request'));
          }
        },
      );
      await completer.future.timeout(_authOperationTimeout);

      emit(state.copyWith(
          verificationId: verificationIdValue,
          resendToken: resendTokenValue,
          status: Status.success));
    } catch (e, stack) {
      _logRecoverableAuthError('request_phone_otp', e, stack);
      emit(state.copyWith(
          errorMessage: 'Verification code could not be sent. Please retry.',
          isLoading: false,
          status: Status.failure));
    }
  }

  Future<void> _handleSignInWithGoogle(
      SignInWithGoogle event, Emitter<AuthState> emit) async {
    try {
      emit(state.copyWith(status: Status.loading));
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleSignInAccount =
          await googleSignIn.signIn().timeout(_authOperationTimeout);

      if (googleSignInAccount == null) {
        emit(state.copyWith(status: Status.initial));
        return;
      }
      final GoogleSignInAuthentication googleSignInAuthentication =
          await googleSignInAccount.authentication
              .timeout(_authOperationTimeout);

      final credential = GoogleAuthProvider.credential(
        accessToken: googleSignInAuthentication.accessToken,
        idToken: googleSignInAuthentication.idToken,
      );

      // Sign in with credential
      UserCredential userCredential = await auth
          .signInWithCredential(credential)
          .timeout(_authOperationTimeout);

      final user = userCredential.user;
      if (user == null) {
        emit(state.copyWith(
          status: Status.failure,
          errorMessage:
              'Google sign-in could not be completed. Please try again.',
        ));
        return;
      }

      final displayName = user.displayName?.trim();
      if (displayName != null && displayName.isNotEmpty) {
        await _updateSenderProfile(displayName: displayName);
      }
      final phone = await _hydrateSenderSessionRecoverably(
          user, 'auth.google.profile');

      emit(state.copyWith(
          username: user.displayName,
          email: user.email,
          phoneNumber: phone,
          profilePhoto: user.photoURL,
          status: Status.signedInWithOAuth,
          currentState: AppState.authenticated,
          authenticatedStatus: AuthenticatedStatus.authenticated));
    } catch (e, stack) {
      _logRecoverableAuthError('google_sign_in', e, stack);
      emit(state.copyWith(
        status: Status.failure,
        errorMessage:
            'Google sign-in could not be completed. Please try again.',
      ));
    }
  }

  Future<void> _handleVerifySentCode(
      VerifySentCode event, Emitter<AuthState> emit) async {
    try {
      // Create a PhoneAuthCredential with the code
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
          verificationId: state.verificationId!, smsCode: '${state.otp}');

      // if user is already signed in by other means, link the credentials
      // else, sign user in

      User? user = auth.currentUser;
      if (user != null) {
        await user
            .linkWithCredential(credential)
            .timeout(_authOperationTimeout);
      } else {
        final UserCredential userCredential = await auth
            .signInWithCredential(credential)
            .timeout(_authOperationTimeout);
        user = userCredential.user;
      }
      if (user == null) {
        emit(state.copyWith(
          status: Status.failure,
          errorMessage: 'Verification could not be completed.',
        ));
        return;
      }
      final phone = await _hydrateSenderSessionRecoverably(
          user, 'auth.phone.profile');
      final isIncomplete = user.displayName == null;
      emit(state.copyWith(
        status: isIncomplete ? Status.initial : Status.success,
        username: user.displayName,
        profilePhoto: user.photoURL,
        email: user.email,
        verificationId: '',
        otp: '',
        phoneNumber: phone,
        authenticatedStatus: isIncomplete
            ? AuthenticatedStatus.incompleteData
            : AuthenticatedStatus.authenticated,
        currentState: AppState.authenticated,
      ));
    } on FirebaseException catch (e) {
      if (e.code == 'invalid-verification-code') {
        emit(state.copyWith(
            status: Status.failure, errorMessage: 'Invalid verification code'));
      } else {
        _logRecoverableAuthError('verify_sent_code', e);
        emit(state.copyWith(
            status: Status.failure,
            errorMessage: 'Verification could not be completed.'));
      }
    } catch (e, stack) {
      _logRecoverableAuthError('verify_sent_code', e, stack);
      emit(state.copyWith(
          status: Status.failure,
          errorMessage: 'Verification could not be completed.'));
    }
  }

  Future<void> _handleSubmitOTP(
      SubmitOTP event, Emitter<AuthState> emit) async {
    emit(state.copyWith(isLoading: true, status: Status.success));
  }

  Future<void> _handleFirstNameChanged(
      FirstNameChanged event, Emitter<AuthState> emit) async {
    return emit(state.copyWith(firstName: event.firstName));
  }

  Future<void> _handleLastNameChanged(
      LastNameChanged event, Emitter<AuthState> emit) async {
    return emit(state.copyWith(lastName: event.lastName));
  }

  Future<void> _handleUsernameChanged(
      UsernameChanged event, Emitter<AuthState> emit) async {
    return emit(state.copyWith(username: event.username));
  }

  Future<void> _handleSetVerificationMethod(
      SetVerificationMethod event, Emitter<AuthState> emit) async {
    emit(state.copyWith(verificationType: event.method));
  }

  Future<void> _handleSetResetPasswordOTP(
      SetResetPasswordOTP event, Emitter<AuthState> emit) async {
    emit(state.copyWith(resetPasswordOtp: event.otp));
  }

  Future<void> _handleForgotPassword(
      ForgotPassword event, Emitter<AuthState> emit) async {
    try {} catch (e) {
      emit(state.copyWith(
          errorMessage: e.toString().split(':').last.trim(), isLoading: false));
    }
  }

  Future<void> _handleGenderChanged(
      GenderChanged event, Emitter<AuthState> emit) async {
    return emit(state.copyWith(gender: event.gender.toUpperCase().trim()));
  }

  void _handleSignInWithEmail(
      SignInWithEmail event, Emitter<AuthState> emit) async {
    try {
      emit(state.copyWith(status: Status.loading));
      final UserCredential userCredential = await auth
          .signInWithEmailAndPassword(
              email: event.email, password: event.password)
          .timeout(_authOperationTimeout);

      final user = userCredential.user;
      if (user == null) {
        emit(state.copyWith(
          status: Status.failure,
          errorMessage: 'Sign in could not be completed. Please try again.',
        ));
        return;
      }
      if (user.emailVerified == false) {
        final verificationSent =
            await _sendVerificationEmail(user, 'auth.email.verification');
        emit(state.copyWith(
          status: Status.unverifiedEmail,
          errorMessage: verificationSent
              ? null
              : 'Your verification email could not be sent. Please retry.',
        ));
      } else {
        final phone = await _hydrateSenderSessionRecoverably(
            user, 'auth.email.profile');
        if (user.displayName == null) {
          emit(state.copyWith(
              authenticatedStatus: AuthenticatedStatus.incompleteData,
              currentState: AppState.authenticated,
              phoneNumber: phone));
        } else {
          emit(state.copyWith(
              status: Status.success,
              authenticatedStatus: AuthenticatedStatus.authenticated,
              username: user.displayName,
              profilePhoto: user.photoURL,
              email: user.email,
              verificationId: '',
              otp: '',
              phoneNumber: phone,
              currentState: AppState.authenticated));
        }
      }
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(status: Status.failure));
      if (e.code == 'invalid-email') {
        emit(state.copyWith(errorMessage: 'Email is invalid'));
      }
      if (e.code == 'user-disabled') {
        emit(state.copyWith(errorMessage: 'User disabled'));
      }
      if (e.code == 'user-not-found') {
        emit(state.copyWith(errorMessage: 'User not found'));
      }
      if (e.code == 'wrong-password') {
        emit(state.copyWith(errorMessage: 'Password incorrect'));
      }
    } catch (error, stack) {
      _logRecoverableAuthError('email_sign_in', error, stack);
      emit(state.copyWith(
        status: Status.failure,
        errorMessage: 'Sign in could not be completed. Please try again.',
      ));
    }
  }

  void _handleSignUpWithEmail(
      SignUpWithEmail event, Emitter<AuthState> emit) async {
    try {
      emit(state.copyWith(status: Status.loading));
      final credential = await auth
          .createUserWithEmailAndPassword(
              email: event.email, password: event.password)
          .timeout(_authOperationTimeout);
      final user = credential.user;
      if (user == null) {
        emit(state.copyWith(
          status: Status.failure,
          errorMessage:
              'Account setup could not be completed. Please try again.',
        ));
        return;
      }
      await _hydrateSenderSessionRecoverably(user, 'auth.signup.profile');
      final verificationSent =
          await _sendVerificationEmail(user, 'auth.signup.verification');
      emit(state.copyWith(
        status: Status.unverifiedEmail,
        email: user.email,
        errorMessage: verificationSent
            ? null
            : 'Your account was created, but the verification email could not be sent. Please retry.',
      ));
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(status: Status.failure));
      if (e.code == 'invalid-email') {
        emit(state.copyWith(errorMessage: 'Email is invalid'));
      }
      if (e.code == 'email-already-in-use') {
        emit(state.copyWith(errorMessage: 'User already exists'));
      }
      if (e.code == 'user-not-found') {
        emit(state.copyWith(errorMessage: 'User not found'));
      }
      if (e.code == 'weak-password') {
        emit(state.copyWith(errorMessage: 'Use a strong password'));
      }
    } catch (error, stack) {
      _logRecoverableAuthError('email_sign_up', error, stack);
      emit(state.copyWith(
        status: Status.failure,
        errorMessage: 'Account setup could not be completed. Please try again.',
      ));
    }
  }

  void _handleConfirmEmailVerification(
      ConfirmEmailVerification event, Emitter<AuthState> emit) async {
    try {
      emit(state.copyWith(status: Status.loading));
      await auth.currentUser?.reload().timeout(_authOperationTimeout);
      if (auth.currentUser?.emailVerified == true) {
        if (auth.currentUser?.displayName == null) {
          emit(state.copyWith(
            authenticatedStatus: AuthenticatedStatus.incompleteData,
            currentState: AppState.authenticated,
          ));
        } else {
          emit(state.copyWith(
            status: Status.success,
            authenticatedStatus: AuthenticatedStatus.authenticated,
            currentState: AppState.authenticated,
            username: auth.currentUser?.displayName,
            profilePhoto: auth.currentUser?.photoURL,
          ));
        }
      } else {
        emit(state.copyWith(status: Status.unverifiedEmail));
      }
    } catch (error, stack) {
      _logRecoverableAuthError('confirm_email_verification', error, stack);
      emit(state.copyWith(
          status: Status.failure,
          errorMessage:
              'Email verification could not be confirmed. Please try again.'));
    }
  }

  void _handleUpdatePhoneNumber(
      UpdatePhoneNumber event, Emitter<AuthState> emit) async {
    try {
      User? user = auth.currentUser;
      FlutterSecureStorage storage = const FlutterSecureStorage();

      if (user != null) {
        await _updateSenderProfile(phone: event.value);

        await storage
            .write(key: 'phone', value: event.value)
            .timeout(_authOperationTimeout);

        emit(state.copyWith(phoneNumber: event.value));
      }
    } catch (e, stack) {
      _logRecoverableAuthError('update_phone_number', e, stack);
      emit(state.copyWith(
          status: Status.failure,
          errorMessage: 'Phone number could not be updated.'));
    }
  }

  void _handleUpdateUserProfilePhoto(
      UpdateUserProfilePhoto event, Emitter<AuthState> emit) async {
    try {
      User? user = auth.currentUser;
      if (user == null) {
        emit(state.copyWith(
          status: Status.failure,
          errorMessage: 'Sign in again before updating your profile photo.',
        ));
        return;
      }
      final fileName = user.uid;

      final storageRef = FirebaseStorage.instance;
      await storageRef
          .ref('profile-photos/$fileName')
          .putData(
            event.imageBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          )
          .timeout(_authOperationTimeout);
      final downloadUrl = await storageRef
          .ref('profile-photos/$fileName')
          .getDownloadURL()
          .timeout(_authOperationTimeout);

      await user.updatePhotoURL(downloadUrl).timeout(_authOperationTimeout);
      emit(state.copyWith(profilePhoto: downloadUrl));
    } catch (e, stack) {
      _logRecoverableAuthError('update_profile_photo', e, stack);
      emit(state.copyWith(
          status: Status.failure,
          errorMessage: 'Profile photo could not be updated.'));
    }
  }

  void _handleSignOut(SignOut event, Emitter<AuthState> emit) async {
    FlutterSecureStorage storage = const FlutterSecureStorage();
    try {
      emit(state.copyWith(status: Status.loading));
      await auth.signOut().timeout(_authOperationTimeout);
    } catch (error, stack) {
      _logRecoverableAuthError('sign_out', error, stack);
      emit(state.copyWith(
          status: Status.failure,
          errorMessage: 'Sign out could not be completed. Please try again.'));
      return;
    }

    try {
      await storage.deleteAll().timeout(_authOperationTimeout);
    } catch (error, stack) {
      _logRecoverableAuthError('sign_out_local_cleanup', error, stack);
    }
    emit(const AuthState(currentState: AppState.unauthenticated));
  }

  void _handleResetPassword(
      ResetPassword event, Emitter<AuthState> emit) async {
    try {
      emit(state.copyWith(status: Status.loading));
      await auth
          .sendPasswordResetEmail(email: event.email)
          .timeout(_authOperationTimeout);
      emit(state.copyWith(status: Status.passwordResetEmailSent));
    } on FirebaseAuthException catch (err) {
      emit(state.copyWith(status: Status.failure));
      if (err.code == 'invalid-email') {
        emit(state.copyWith(errorMessage: 'Invalid email'));
      }

      if (err.code == 'user-not-found') {
        emit(state.copyWith(errorMessage: 'User not found'));
      }
    } catch (err) {
      emit(state.copyWith(status: Status.failure));
    }
  }

  void _handleSetShowPassword(SetShowPassword event, Emitter<AuthState> emit) {
    emit(state.copyWith(showPassword: event.val));
  }

  void _handleValidatePhoneNumber(
      ValidatePhoneNumber event, Emitter<AuthState> emit) {
    emit(state.copyWith(isPhoneNumberValid: event.val));
  }

  void _handleRequestLocationData(
      RequestLocationData event, Emitter<AuthState> emit) async {
    try {
      final User? user = auth.currentUser;
      Position locationData =
          await locationHelper.enableLocation().timeout(_authOperationTimeout);

      emit(state.copyWith(
          locationData: locationData,
          hasLocationPermission: true,
          isLocationEnabled: true,
          status: Status.locationRequested,
          appLocationStatus: AppLocationStatus.available));
      if (user != null) {
        await _updateSenderLocation(locationData);
      }
    } catch (e) {
      if (e == 'Location permissions are permanently denied') {
        emit(state.copyWith(
            hasLocationPermission: false,
            status: Status.locationRequested,
            appLocationStatus: AppLocationStatus.denied));
      } else {
        _logRecoverableAuthError('request_location', e);
        emit(state.copyWith(
            hasLocationPermission: false,
            status: Status.failure,
            appLocationStatus: AppLocationStatus.denied,
            errorMessage: 'Location could not be enabled. Please try again.'));
      }
    }
  }

  void _handleUpdateUserProfile(
      UpdateUserProfile event, Emitter<AuthState> emit) async {
    try {
      emit(state.copyWith(status: Status.loading));
      final User? user = auth.currentUser;
      await user?.updateDisplayName(event.username).timeout(
            _authOperationTimeout,
          );

      await _updateSenderProfile(
        displayName: event.username,
        phone: user?.phoneNumber,
      );

      // print(user);

      emit(state.copyWith(
          status: Status.success,
          authenticatedStatus: AuthenticatedStatus.authenticated,
          username: event.username));
    } catch (e, stack) {
      _logRecoverableAuthError('update_user_profile', e, stack);
      emit(state.copyWith(
          status: Status.failure,
          errorMessage: 'Profile could not be updated.'));
    }
  }

  void _handleOpenSettingsApp(
      OpenSettingsApp event, Emitter<AuthState> emit) async {
    try {
      final User? user = auth.currentUser;
      Position locationData =
          await locationHelper.enableLocation().timeout(_authOperationTimeout);

      emit(state.copyWith(
          locationData: locationData,
          hasLocationPermission: true,
          isLocationEnabled: true,
          status: Status.locationRequested));
      if (user != null) {
        await _updateSenderLocation(locationData);
      }
    } catch (e, stack) {
      if (e == 'Location permissions are permanently denied') {
        try {
          await Geolocator.openLocationSettings()
              .timeout(_authOperationTimeout);
          emit(state.copyWith(status: Status.locationRequested));
        } catch (settingsError, settingsStack) {
          _logRecoverableAuthError(
              'open_location_settings', settingsError, settingsStack);
          emit(state.copyWith(
              status: Status.failure,
              errorMessage: 'Location settings could not be opened.'));
        }
        return;
      }

      if (e == 'Location services are disabled') {
        try {
          await Geolocator.openAppSettings().timeout(_authOperationTimeout);
          emit(state.copyWith(status: Status.locationRequested));
        } catch (settingsError, settingsStack) {
          _logRecoverableAuthError(
              'open_app_settings', settingsError, settingsStack);
          emit(state.copyWith(
              status: Status.failure,
              errorMessage: 'Location settings could not be opened.'));
        }
        return;
      }

      _logRecoverableAuthError('open_settings_location', e, stack);
      emit(state.copyWith(
          status: Status.failure,
          errorMessage: 'Location settings could not be opened.'));
    }
  }

  void _handleUpdateFirstName(
      UpdateFirstName event, Emitter<AuthState> emit) async {
    try {
      User? user = auth.currentUser;
      final lastName = state.username?.trim().split(' ').last;

      if (lastName != null) {
        await user
            ?.updateDisplayName('${event.value} $lastName')
            .timeout(_authOperationTimeout);
        // print('${event.value} $lastName');
        emit(state.copyWith(username: '${event.value} $lastName'));
        await _updateSenderProfile(displayName: '${event.value} $lastName');
      } else {
        await user
            ?.updateDisplayName(event.value)
            .timeout(_authOperationTimeout);
        // print(user?.displayName);
        emit(state.copyWith(username: event.value));
        await _updateSenderProfile(displayName: event.value);
      }
    } catch (e, stack) {
      _logRecoverableAuthError('update_first_name', e, stack);
      emit(state.copyWith(
          status: Status.failure,
          errorMessage: 'First name could not be updated.'));
    }
  }

  void _handleUpdateLastName(
      UpdateLastName event, Emitter<AuthState> emit) async {
    try {
      User? user = auth.currentUser;
      final firstName = state.username?.trim().split(' ').first;

      if (firstName != null) {
        await user
            ?.updateDisplayName('$firstName ${event.value}')
            .timeout(_authOperationTimeout);
        // print(user?.displayName);
        emit(state.copyWith(username: '$firstName ${event.value}'));
        await _updateSenderProfile(displayName: '$firstName ${event.value}');
      } else {
        await user
            ?.updateDisplayName(event.value)
            .timeout(_authOperationTimeout);
        // print(user?.displayName);
        emit(state.copyWith(username: event.value));
        await _updateSenderProfile(displayName: event.value);
      }
    } catch (e, stack) {
      _logRecoverableAuthError('update_last_name', e, stack);
      emit(state.copyWith(
          status: Status.failure,
          errorMessage: 'Last name could not be updated.'));
    }
  }

  void _handleSetErrorMessage(SetErrorMessage event, Emitter<AuthState> emit) {
    emit(state.copyWith(errorMessage: event.errorMessage));
  }
}
