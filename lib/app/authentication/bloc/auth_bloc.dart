import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
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

import '../../../helper/location_helper.dart';
import '../../../extension/email_validation.dart';
// import '../../onboarding/view/onboarding.dart';

part 'auth_event.dart';
part 'auth_state.dart';
part 'signup_event.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  FirebaseAuth auth = FirebaseAuth.instance;
  FirebaseFirestore db = FirebaseFirestore.instance;
  // Init firestore and geoFlutterFire
  // final geo = GeoFlutterFire();
  LocationHelper locationHelper = LocationHelper();
  AuthBloc() : super(AuthState()) {
    void listenForPermissionStatus() async {
      final permission = await permission_handler.Permission.location.status;
      print(permission);
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
    on<DeleteAccount>(_handleDeleteAccount);
  }

  Future<void> _handleSortSessionState(
      SortSessionState event, Emitter<AuthState> emit) async {
    // FirebaseAuth auth = FirebaseAuth.instance;
    final storage = FlutterSecureStorage();

    User? user = auth.currentUser;
    if (user != null) {
      // print("User is signed in: ${user.uid}");
      final phone = (await storage.readAll())["phone"];
      // print("User is signed in: ${user.uid}");
      // You can also access user information like user.displayName, user.email, etc.
      emit(state.copyWith(
          currentState: AppState.authenticated,
          username: user.displayName,
          phoneNumber: user.phoneNumber ?? phone,
          email: user.email,
          profilePhoto: user.photoURL,
          authenticatedStatus: AuthenticatedStatus.authenticated));

      await Future.delayed(const Duration(seconds: 3));

      final creationDate = DateTime.parse('${user.metadata.creationTime}');

      final authChangeDate = DateTime.parse('2024-05-15');

      if (authChangeDate.isAfter(creationDate)) {
        add(SignOut());
      }
    } else {
      print('User not signed in');
      emit(state.copyWith(currentState: AppState.unauthenticated));
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
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider("apple.com").credential(
          idToken: appleCredential.identityToken,
          accessToken: appleCredential.authorizationCode);

      UserCredential userCredential =
          await auth.signInWithCredential(oauthCredential);

      emit(state.copyWith(
          username: userCredential.user?.displayName,
          email: userCredential.user?.email,
          profilePhoto: userCredential.user?.photoURL,
          status: Status.signedInWithOAuth,
          currentState: AppState.authenticated,
          authenticatedStatus: appleCredential.givenName == null &&
                  userCredential.user?.displayName == null
              ? AuthenticatedStatus.incompleteData
              : AuthenticatedStatus.authenticated));

      if (appleCredential.givenName != null) {
        print('New user, updating user data');
        add(UpdateUserProfile(
            username:
                "${appleCredential.givenName} ${appleCredential.familyName}"));
      }
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      print(e);
    }
  }

  void _handleRequestForOTP(
      RequestForOTP event, Emitter<AuthState> emit) async {
    var completer = Completer<bool>();

    String? _verificationId;
    int? _resendToken;

    print('>>>>>>>>>> Trying to get code');

    try {
      emit(state.copyWith(status: Status.loading));
      await auth.verifyPhoneNumber(
        phoneNumber: state.phoneNumber,
        verificationCompleted: (_) {},
        verificationFailed: (_) {
          print('Verification failed');
          print(_.message);
          print(_.code);
          print(_.stackTrace);
          throw 'Verification failed';
        },
        codeSent: (String verificationId, int? resendToken) async {
          _verificationId = verificationId;
          _resendToken = resendToken;
          print('code sent');
          completer.complete(true);
        },
        codeAutoRetrievalTimeout: (_) {
          print('Code timed out');
          print(_);
          throw 'Code timed out';
        },
      );
      await completer.future;

      emit(state.copyWith(
          verificationId: _verificationId,
          resendToken: _resendToken,
          status: Status.success));
      print('Gotten Verification ID');
      print(_verificationId);
      print(_resendToken);
    } catch (e) {
      print('Error sending code');
      print(e);
      emit(state.copyWith(
          errorMessage: e.toString().split(':').last.trim(),
          isLoading: false,
          status: Status.failure));
    }
  }

  Future<void> _handleSignInWithGoogle(
      SignInWithGoogle event, Emitter<AuthState> emit) async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    final GoogleSignInAccount? googleSignInAccount =
        await googleSignIn.signIn();

    if (googleSignInAccount != null) {
      final GoogleSignInAuthentication googleSignInAuthentication =
          await googleSignInAccount.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleSignInAuthentication.accessToken,
        idToken: googleSignInAuthentication.idToken,
      );

      // Sign in with credential
      UserCredential userCredential =
          await auth.signInWithCredential(credential);

      emit(state.copyWith(
          username: userCredential.user?.displayName,
          email: userCredential.user?.email,
          profilePhoto: userCredential.user?.photoURL,
          status: Status.signedInWithOAuth,
          currentState: AppState.authenticated,
          authenticatedStatus: AuthenticatedStatus.authenticated));

      add(UpdateUserProfile(username: userCredential.user!.displayName!));
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

      if (auth.currentUser != null) {
        await auth.currentUser?.linkWithCredential(credential);
      } else {
        final UserCredential _userCredential =
            await auth.signInWithCredential(credential);

        if (_userCredential.user?.displayName == null) {
          if (state.oAuthFirstName == null) {
            emit(state.copyWith(
                authenticatedStatus: AuthenticatedStatus.incompleteData,
                currentState: AppState.authenticated));
          } else {
            add(UpdateUserProfile(
                username: "${state.oAuthFirstName} ${state.oAuthLastName}"));
            emit(state.copyWith(
                status: Status.success,
                username: "${state.oAuthFirstName} ${state.oAuthLastName}",
                profilePhoto: state.oAuthPhotoURL,
                email: state.oAuthEmail,
                verificationId: '',
                otp: '',
                phoneNumber: _userCredential.user?.phoneNumber,
                currentState: AppState.authenticated));
          }
        } else {
          print(_userCredential.additionalUserInfo);
          print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
          print(_userCredential);
          print(_userCredential.credential?.accessToken);
          print(_userCredential.credential?.providerId);
          print(_userCredential.credential?.signInMethod);
          print(_userCredential.credential?.token);
          print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
          print(_userCredential.user);
          emit(state.copyWith(
              status: Status.success,
              username: _userCredential.user?.displayName,
              profilePhoto: _userCredential.user?.photoURL,
              email: _userCredential.user?.email,
              verificationId: '',
              otp: '',
              phoneNumber: _userCredential.user?.phoneNumber,
              authenticatedStatus: AuthenticatedStatus.authenticated,
              currentState: AppState.authenticated));
        }
      }
      // Sign the user in (or link) with the credential
    } on FirebaseException catch (e) {
      print(e.code);
      if (e.code == 'invalid-verification-code') {
        emit(state.copyWith(errorMessage: 'Invalid verification code'));
      }
    } catch (e) {
      print(e);
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
    FlutterSecureStorage storage = const FlutterSecureStorage();
    try {
      emit(state.copyWith(status: Status.loading));
      final UserCredential userCredential =
          await auth.signInWithEmailAndPassword(
              email: event.email, password: event.password);
      storage.write(key: 'password', value: event.password);

      if (auth.currentUser?.emailVerified == false) {
        print('Email not verified');
        await auth.currentUser?.sendEmailVerification();
        emit(state.copyWith(
          status: Status.unverifiedEmail,
        ));
      } else {
        if (userCredential.user?.displayName == null) {
          emit(state.copyWith(
              authenticatedStatus: AuthenticatedStatus.incompleteData,
              currentState: AppState.authenticated));
        } else {
          print(userCredential.additionalUserInfo);
          print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
          print(userCredential);
          print(userCredential.credential?.accessToken);
          print(userCredential.credential?.providerId);
          print(userCredential.credential?.signInMethod);
          print(userCredential.credential?.token);
          print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
          print(userCredential.user);
          emit(state.copyWith(
              status: Status.success,
              authenticatedStatus: AuthenticatedStatus.authenticated,
              username: userCredential.user?.displayName,
              profilePhoto: userCredential.user?.photoURL,
              email: userCredential.user?.email,
              verificationId: '',
              otp: '',
              phoneNumber: userCredential.user?.phoneNumber,
              currentState: AppState.authenticated));

          User? user = auth.currentUser;
          final documentReference = db.collection('users').doc(user?.uid);
          // Get the document snapshot
          final documentSnapshot = await documentReference.get();

          if (documentSnapshot.exists) {
            // Document exists
            final userdata = await db.collection("users").doc(user!.uid).get();
            final doc = userdata.data();

            await storage.write(key: 'phone', value: doc!['phone']);
            emit(state.copyWith(phoneNumber: doc['phone']));
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      print(e.code);
      emit(state.copyWith(status: Status.failure));
      if (e.code == 'invalid-email') {
        print('Email is invalid');
        emit(state.copyWith(errorMessage: 'Email is invalid'));
      }
      if (e.code == 'user-disabled') {
        print('User disabled');
        emit(state.copyWith(errorMessage: 'User disabled'));
      }
      if (e.code == 'user-not-found') {
        print('User not found');
        emit(state.copyWith(errorMessage: 'User not found'));
      }
      if (e.code == 'wrong-password') {
        print('Wrong password');
        emit(state.copyWith(errorMessage: 'Password incorrect'));
      }
    } catch (e) {
      print(e);
      emit(state.copyWith(status: Status.failure));
    }
  }

  void _handleSignUpWithEmail(
      SignUpWithEmail event, Emitter<AuthState> emit) async {
    FlutterSecureStorage storage = const FlutterSecureStorage();
    try {
      print('Signing up');
      emit(state.copyWith(status: Status.loading));
      await auth.createUserWithEmailAndPassword(
          email: event.email, password: event.password);

      storage.write(key: 'password', value: event.password);

      print('done');
      if (auth.currentUser?.emailVerified == false) {
        print('Email not verified');
        await auth.currentUser?.sendEmailVerification();
        emit(state.copyWith(
          status: Status.unverifiedEmail,
        ));
      }
    } on FirebaseAuthException catch (e) {
      print(e.code);
      emit(state.copyWith(status: Status.failure));
      if (e.code == 'invalid-email') {
        print('Email is invalid');
        emit(state.copyWith(errorMessage: 'Email is invalid'));
      }
      if (e.code == 'email-already-in-use') {
        print('User already exists');
        emit(state.copyWith(errorMessage: 'User already exists'));
      }
      if (e.code == 'user-not-found') {
        print('User not found');
        emit(state.copyWith(errorMessage: 'User not found'));
      }
      if (e.code == 'weak-password') {
        print('Weak password');
        emit(state.copyWith(errorMessage: 'Use a strong password'));
      }
    } catch (e) {
      print(e);
      emit(state.copyWith(status: Status.failure));
    }
  }

  void _handleConfirmEmailVerification(
      ConfirmEmailVerification event, Emitter<AuthState> emit) async {
    await auth.currentUser?.reload();
    if (auth.currentUser?.emailVerified == true) {
      print('Email Verified');
      if (auth.currentUser?.displayName == null) {
        print(auth.currentUser?.displayName);
        emit(state.copyWith(
          authenticatedStatus: AuthenticatedStatus.incompleteData,
          currentState: AppState.authenticated,
        ));
      } else {
        emit(state.copyWith(
          authenticatedStatus: AuthenticatedStatus.authenticated,
          currentState: AppState.authenticated,
          username: auth.currentUser?.displayName,
          profilePhoto: auth.currentUser?.photoURL,
        ));
      }
    } else {
      print('Email not Verified');
    }
  }

  void _handleUpdatePhoneNumber(
      UpdatePhoneNumber event, Emitter<AuthState> emit) async {
    try {
      User? user = auth.currentUser;
      FlutterSecureStorage storage = const FlutterSecureStorage();
      print(event.value);

      final documentReference = db.collection('users').doc(user?.uid);
      // Get the document snapshot
      final documentSnapshot = await documentReference.get();

      if (documentSnapshot.exists) {
        // Document exists
        // print('Document exists');
        await db.collection("users").doc(user!.uid).update({
          'phone': event.value,
        });

        await storage.write(key: 'phone', value: event.value);

        emit(state.copyWith(phoneNumber: event.value));
      }
    } catch (e) {
      print(e);
    }
  }

  void _handleUpdateUserProfilePhoto(
      UpdateUserProfilePhoto event, Emitter<AuthState> emit) async {
    try {
      User? user = auth.currentUser;
      final fileName = user!.uid;

      final storageRef = FirebaseStorage.instance;
      await storageRef.ref('profile-photos/$fileName').putData(
            event.imageBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
      final downloadUrl =
          await storageRef.ref('profile-photos/$fileName').getDownloadURL();

      print(downloadUrl);

      await user.updatePhotoURL(downloadUrl);
      emit(state.copyWith(profilePhoto: downloadUrl));
    } catch (e) {
      print(e);
    }
  }

  void _handleSignOut(SignOut event, Emitter<AuthState> emit) async {
    FlutterSecureStorage storage = const FlutterSecureStorage();
    await auth.signOut();
    emit(const AuthState());
    emit(state.copyWith(currentState: AppState.unauthenticated));
    await storage.deleteAll();
  }

  void _handleDeleteAccount(
      DeleteAccount event, Emitter<AuthState> emit) async {
    FlutterSecureStorage storage = const FlutterSecureStorage();
    final user = auth.currentUser!;
    final password = (await storage.readAll())["password"];

    // auth.currentUser.reauthenticateWithProvider(provider)

    try {
      // if(user.)

      // final AuthCredential credential = PhoneAuthProvider.credential(
      //     verificationId: state.verificationId!, smsCode: '${state.otp}');

      final AuthCredential credential = EmailAuthProvider.credential(
          email: state.email!, password: password!);

      // Reauthenticate user with phone credential
      await user.reauthenticateWithCredential(credential);

      await db.collection('users').doc(user.uid).update({'deleted': true});
      // Reauthentication successful, proceed with account deletion
      await user.delete();
      await storage.deleteAll();
      // Account deleted successfully
      // print("Account deleted successfully.");
      emit(state.copyWith(currentState: AppState.unauthenticated));
    } on FirebaseException catch (e) {
      // print(e.code);
      if (e.code == 'invalid-verification-code') {
        emit(state.copyWith(errorMessage: 'Invalid verification code'));
      }
    } catch (error) {
      // An error occurred during reauthentication or account deletion
      // print("Error deleting account: $error");
      // Handle error (e.g., display error message)
    }
  }

  void _handleResetPassword(
      ResetPassword event, Emitter<AuthState> emit) async {
    try {
      emit(state.copyWith(status: Status.loading));
      await auth.sendPasswordResetEmail(email: event.email);
      emit(state.copyWith(status: Status.passwordResetEmailSent));
    } on FirebaseAuthException catch (err) {
      emit(state.copyWith(status: Status.failure));
      print(err.code);
      if (err.code == 'invalid-email') {
        emit(state.copyWith(errorMessage: 'Invalid email'));
      }

      if (err.code == 'user-not-found') {
        emit(state.copyWith(errorMessage: 'User not found'));
      }

      throw Exception(err.message.toString());
    } catch (err) {
      emit(state.copyWith(status: Status.failure));
      print(err.toString());
      throw Exception(err.toString());
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
      Position locationData = await locationHelper.enableLocation();

      GeoFirePoint myLocation =
          GeoFirePoint(GeoPoint(locationData.latitude, locationData.longitude));
      print('Latitude: ${locationData.latitude}');
      print('Longitude: ${locationData.longitude}');
      emit(state.copyWith(
          locationData: locationData,
          hasLocationPermission: true,
          isLocationEnabled: true,
          status: Status.locationRequested,
          appLocationStatus: AppLocationStatus.available));
      await db
          .collection("users")
          .doc(user?.uid)
          .update({'position': myLocation.data}).then(
              (value) => print("DocumentSnapshot successfully updated!"),
              onError: (e) => print("Error updating document $e"));
    } catch (e) {
      print(e);
      if (e == 'Location permissions are permanently denied') {
        emit(state.copyWith(
            hasLocationPermission: false,
            status: Status.locationRequested,
            appLocationStatus: AppLocationStatus.denied));
      }
    }
  }

  void _handleUpdateUserProfile(
      UpdateUserProfile event, Emitter<AuthState> emit) async {
    try {
      emit(state.copyWith(status: Status.loading));
      final User? user = auth.currentUser;
      await user?.updateDisplayName(event.username);
      print(event.username);

      final documentReference = db.collection('users').doc(user?.uid);

      // Get the document snapshot
      final documentSnapshot = await documentReference.get();

      if (documentSnapshot.exists) {
        // Document exists
        // print('Document exists');
        await db.collection("users").doc(user?.uid).update({
          'name': event.username,
          'role': 'user',
          'roles': ['sender'],
          'userType': 'sender',
          'phone': user?.phoneNumber,
          'email': user?.email
        }).then((value) => print("DocumentSnapshot successfully updated!"),
            onError: (e) => print("Error updating document $e"));
      } else {
        // Document does not exist
        // print('Document does not exist');
        await db.collection("users").doc(user?.uid).set({
          'name': event.username,
          "role": 'user',
          'roles': ['sender'],
          'userType': 'sender',
          'phone': user?.phoneNumber,
          'email': user?.email
        }).then((value) => print("DocumentSnapshot successfully created!"),
            onError: (e) => print("Error updating document $e"));
      }

      // print(user);

      emit(state.copyWith(
          status: Status.success,
          authenticatedStatus: AuthenticatedStatus.authenticated,
          username: event.username));
    } catch (e) {
      print(e);
    }
  }

  void _handleOpenSettingsApp(
      OpenSettingsApp event, Emitter<AuthState> emit) async {
    try {
      final User? user = auth.currentUser;
      Position locationData = await locationHelper.enableLocation();

      GeoFirePoint myLocation =
          GeoFirePoint(GeoPoint(locationData.latitude, locationData.longitude));
      print('Latitude: ${locationData.latitude}');
      print('Longitude: ${locationData.longitude}');
      emit(state.copyWith(
          locationData: locationData,
          hasLocationPermission: true,
          isLocationEnabled: true,
          status: Status.locationRequested));
      await db
          .collection("users")
          .doc(user?.uid)
          .update({'position': myLocation.data}).then(
              (value) => print("DocumentSnapshot successfully updated!"),
              onError: (e) => print("Error updating document $e"));
    } catch (e) {
      print(e);
      if (e == 'Location permissions are permanently denied') {
        final _openLocationSettings = await Geolocator.openLocationSettings();
      }

      if (e == 'Location services are disabled') {
        final _openLocationSettings = await Geolocator.openAppSettings();
        print(_openLocationSettings);
      }
    }
  }

  void _handleUpdateFirstName(
      UpdateFirstName event, Emitter<AuthState> emit) async {
    try {
      User? user = auth.currentUser;
      final lastName = state.username?.trim().split(' ').last;

      if (lastName != null) {
        await user?.updateDisplayName('${event.value} $lastName');
        // print('${event.value} $lastName');
        emit(state.copyWith(username: '${event.value} $lastName'));

        final documentReference = db.collection('users').doc(user?.uid);
        // Get the document snapshot
        final documentSnapshot = await documentReference.get();

        if (documentSnapshot.exists) {
          // Document exists
          // print('Document exists');
          await db
              .collection("users")
              .doc(user?.uid)
              .update({'name': '${event.value} $lastName'});
        }
      } else {
        await user?.updateDisplayName(event.value);
        // print(user?.displayName);
        emit(state.copyWith(username: event.value));

        final documentReference = db.collection('users').doc(user?.uid);
        // Get the document snapshot
        final documentSnapshot = await documentReference.get();

        if (documentSnapshot.exists) {
          // Document exists
          // print('Document exists');
          await db.collection("users").doc(user?.uid).update({
            'name': event.value,
          });
        }
      }
    } catch (e) {
      print(e);
    }
  }

  void _handleUpdateLastName(
      UpdateLastName event, Emitter<AuthState> emit) async {
    try {
      User? user = auth.currentUser;
      final firstName = state.username?.trim().split(' ').first;

      if (firstName != null) {
        await user?.updateDisplayName('$firstName ${event.value}');
        // print(user?.displayName);
        emit(state.copyWith(username: '$firstName ${event.value}'));

        final documentReference = db.collection('users').doc(user?.uid);
        // Get the document snapshot
        final documentSnapshot = await documentReference.get();

        if (documentSnapshot.exists) {
          // Document exists
          // print('Document exists');
          await db.collection("users").doc(user?.uid).update({
            'name': '$firstName ${event.value}',
          });
        }
      } else {
        await user?.updateDisplayName(event.value);
        // print(user?.displayName);
        emit(state.copyWith(username: event.value));

        final documentReference = db.collection('users').doc(user?.uid);
        // Get the document snapshot
        final documentSnapshot = await documentReference.get();

        if (documentSnapshot.exists) {
          // Document exists
          // print('Document exists');
          await db.collection("users").doc(user?.uid).update({
            'name': event.value,
          });
        }
      }
    } catch (e) {
      print(e);
    }
  }

  void _handleSetErrorMessage(SetErrorMessage event, Emitter<AuthState> emit) {
    emit(state.copyWith(errorMessage: event.errorMessage));
  }
}
