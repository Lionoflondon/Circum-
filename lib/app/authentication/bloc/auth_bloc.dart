import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:circum/utils/app_state/app_state.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
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
  AuthBloc() : super(AuthState()) {
    FirebaseAuth auth = FirebaseAuth.instance;
    FirebaseFirestore db = FirebaseFirestore.instance;
    // Init firestore and geoFlutterFire
    final geo = GeoFlutterFire();
    LocationHelper locationHelper = LocationHelper();

    void listenForPermissionStatus() async {
      final permission = await permission_handler.Permission.location.status;
      print(permission);
    }

    listenForPermissionStatus();

    on<AuthEvent>((event, emit) async {
      if (event is SortSessionState) {
        FirebaseAuth auth = FirebaseAuth.instance;
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

      if (event is ResetStatus) {
        emit(state.copyWith(status: Status.initial));
      }

      if (event is StartCountDown) {
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

      if (event is ResetCountdown) {
        if (state.countdown < 30) {
          emit(state.copyWith(countdown: 59));
          add(StartCountDown());
        } else {
          emit(state.copyWith(countdown: 30));
          add(StartCountDown());
        }
      }

      if (event is SignupEmailChanged) {
        // debugPrint(event.email);
        emit(state.copyWith(email: event.email));
        if (event.email!.isValidEmail()) {
          emit(state.copyWith(isEmailValid: true));
          // print('Valid email!');
        } else {
          emit(state.copyWith(isEmailValid: false));
          // print('Invalid email!');
        }
      }

      if (event is PhoneNumberChanged) {
        emit(state.copyWith(phoneNumber: event.phoneNumber));
      }

      if (event is SignupPasswordChanged) {
        emit(state.copyWith(password: event.password));
      }

      if (event is ConfirmPasswordChanged) {
        emit(state.copyWith(confirmPassword: event.password));
      }
      if (event is DateOfBirthChanged) {
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

      if (event is SetOTP) {
        emit(state.copyWith(otp: event.otp));
      }

      if (event is SetPin) {
        emit(state.copyWith(pin: event.pin));
        add(SubmitOTP());
      }
      if (event is SignInWithAppleAuth) {
        final rawNonce = generateNonce();
        final nonce = sha256ofString(rawNonce);
        try {
          final appleCredential = await SignInWithApple.getAppleIDCredential(
            scopes: [
              AppleIDAuthorizationScopes.email,
              AppleIDAuthorizationScopes.fullName,
            ],
            // nonce: nonce
          );

          // SignInWithApple

          // print(appleCredential);
          // print(appleCredential.email);
          // print(appleCredential.givenName);
          // print(appleCredential.familyName);

          // final GoogleSignInAuthentication googleSignInAuthentication =
          //     await googleSignInAccount.authentication;

          // Create an `OAuthCredential` from the credential returned by Apple.
          final oauthCredential = OAuthProvider("apple.com").credential(
              idToken: appleCredential.identityToken,
              accessToken: appleCredential.authorizationCode
              // rawNonce: rawNonce,
              );

          // Sign in with credential
          UserCredential userCredential =
              await auth.signInWithCredential(oauthCredential);
          // print(userCredential.user?.displayName);
          // print(userCredential.user?.email);
          // print(userCredential.user?.emailVerified);
          // print('>>>>>>>>>>>>>>>>>>>>>>>>>>>');
          // print(userCredential.user?.displayName?.split(' ').first);
          // print(userCredential.user?.displayName?.split(' ').last);

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
            // emit(state.copyWith(
            //     authenticatedStatus: AuthenticatedStatus.authenticated));
            add(UpdateUserProfile(
                username:
                    "${appleCredential.givenName} ${appleCredential.familyName}"));
          }
          await Future.delayed(const Duration(seconds: 2));

          // await googleSignIn.signOut();
        } catch (e) {
          print(e);
        }
      }
      if (event is SignInWithGoogle) {
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
          // await googleSignIn.signOut();
        }
      }

      if (event is RequestForOTP) {
        // print({'phoneNumber': state.phoneNumber, 'password': state.password});
        // emit(state.copyWith(isLoading: true, status: Status.loading));

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

      if (event is VerifySentCode) {
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
                    username:
                        "${state.oAuthFirstName} ${state.oAuthLastName}"));
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

      if (event is SubmitOTP) {
        emit(state.copyWith(isLoading: true, status: Status.success));
      }

      if (event is FirstNameChanged) {
        emit(state.copyWith(firstName: event.firstName));
      }

      if (event is LastNameChanged) {
        return emit(state.copyWith(lastName: event.lastName));
      }

      if (event is UsernameChanged) {
        return emit(state.copyWith(username: event.username));
      }

      if (event is GenderChanged) {
        return emit(state.copyWith(gender: event.gender.toUpperCase().trim()));
      }

      if (event is SetVerificationMethod) {
        emit(state.copyWith(verificationType: event.method));
        // return;
      }

      // if (event is LoginUser) {
      //   const storage = FlutterSecureStorage();
      //   await storage.write(key: 'password', value: state.password);
      //   emit(state.copyWith(isLoading: true, status: Status.loading));
      //   try {
      //     Validator.validateLogin(
      //         data: {'email': state.email, 'password': state.password});
      //   } catch (e) {
      //     emit(state.copyWith(
      //         errorMessage: e.toString().split(':').last.trim(),
      //         isLoading: false));
      //   }
      // }
      if (event is SetResetPasswordOTP) {
        emit(state.copyWith(resetPasswordOtp: event.otp));
      }

      if (event is ForgotPassword) {
        try {} catch (e) {
          emit(state.copyWith(
              errorMessage: e.toString().split(':').last.trim(),
              isLoading: false));
        }
      }

      if (event is ResetPassword) {}

      if (event is SetShowPassword) {
        emit(state.copyWith(showPassword: event.val));
      }

      if (event is ValidatePhoneNumber) {
        emit(state.copyWith(isPhoneNumberValid: event.val));
      }

      if (event is RequestLocationData) {
        try {
          final User? user = auth.currentUser;
          Position locationData = await locationHelper.enableLocation();

          GeoFirePoint myLocation = geo.point(
              latitude: locationData.latitude,
              longitude: locationData.longitude);
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

      if (event is UpdateUserProfile) {
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

      if (event is OpenSettingsApp) {
        try {
          final User? user = auth.currentUser;
          Position locationData = await locationHelper.enableLocation();

          GeoFirePoint myLocation = geo.point(
              latitude: locationData.latitude,
              longitude: locationData.longitude);
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
            final _openLocationSettings =
                await Geolocator.openLocationSettings();
          }

          if (e == 'Location services are disabled') {
            final _openLocationSettings = await Geolocator.openAppSettings();
            print(_openLocationSettings);
          }
        }
      }
    });

    on<UpdateFirstName>(((event, emit) async {
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
    }));

    on<UpdateLastName>(((event, emit) async {
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
    }));

    on<SetErrorMessage>(
      (event, emit) {
        emit(state.copyWith(errorMessage: event.errorMessage));
      },
    );

    on<SignInWithEmail>(
      (event, emit) async {
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
                // print('Document exists');
                final userdata =
                    await db.collection("users").doc(user!.uid).get();

                final doc = userdata.data();

                // print(doc?['phone']);

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
      },
    );

    on<SignUpWithEmail>(
      (event, emit) async {
        // var acs = ActionCodeSettings(
        //     // URL you want to redirect back to. The domain (www.example.com) for this
        //     // URL must be whitelisted in the Firebase Console.
        //     url: 'https://circum-2797c.firebaseapp.com',
        //     // This must be true
        //     handleCodeInApp: true,
        //     iOSBundleId: 'com.circum.app',
        //     androidPackageName: 'com.circum.app',
        //     // installIfNotAvailable
        //     androidInstallApp: true,
        //     // minimumVersion
        //     androidMinimumVersion: '12');
        FlutterSecureStorage storage = const FlutterSecureStorage();
        try {
          print('Signing up');
          emit(state.copyWith(status: Status.loading));
          final UserCredential userCredential =
              await auth.createUserWithEmailAndPassword(
                  email: event.email, password: event.password);

          storage.write(key: 'password', value: event.password);

          print('done');
          // emit(state.copyWith(status: Status.success));
          if (auth.currentUser?.emailVerified == false) {
            print('Email not verified');
            await auth.currentUser?.sendEmailVerification();
            emit(state.copyWith(
              status: Status.unverifiedEmail,
            ));

            // await auth
            // await auth.signOut();
          }
        } on FirebaseAuthException catch (e) {
          print(e.code);
          emit(state.copyWith(status: Status.failure));
          if (e.code == 'invalid-email') {
            print('Email is invalid');
            emit(state.copyWith(errorMessage: 'Email is invalid'));
          }
          if (e.code == 'email-already-in-user') {
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
      },
    );

    on<ConfirmEmailVerification>((event, emit) async {
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
    });

    on<UpdatePhoneNumber>(
      (event, emit) async {
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
      },
    );

    on<UpdateUserProfilePhoto>(
      (event, emit) async {
        // print('uploading image');
        try {
          User? user = auth.currentUser;
          final fileName = user!.uid;
          File imageFile = File(event.imagePath);

          final storageRef = FirebaseStorage.instance;
          await storageRef.ref('profile-photos/$fileName').putFile(imageFile);
          final downloadUrl =
              await storageRef.ref('profile-photos/$fileName').getDownloadURL();

          print(downloadUrl);

          await user.updatePhotoURL(downloadUrl);
          emit(state.copyWith(profilePhoto: downloadUrl));
        } catch (e) {
          print(e);
        }
      },
    );

    on<SignOut>(
      (event, emit) async {
        await auth.signOut();
        FlutterSecureStorage storage = const FlutterSecureStorage();
        emit(const AuthState());
        emit(state.copyWith(currentState: AppState.unauthenticated));
        await storage.deleteAll();
      },
    );

    on<DeleteAccount>((event, emit) async {
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
        print("Account deleted successfully.");
        emit(state.copyWith(currentState: AppState.unauthenticated));
      } on FirebaseException catch (e) {
        print(e.code);
        if (e.code == 'invalid-verification-code') {
          emit(state.copyWith(errorMessage: 'Invalid verification code'));
        }
      } catch (error) {
        // An error occurred during reauthentication or account deletion
        print("Error deleting account: $error");
        // Handle error (e.g., display error message)
      }

      // Navigator.pushNamedAndRemoveUntil(
      //     context, '/onboarding', (Route<dynamic> route) => false);
    });

    on<ResetPassword>((event, emit) async {
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
    });
  }
}

/// Generates a cryptographically secure random nonce, to be included in a
/// credential request.
String generateNonce([int length = 32]) {
  final charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(length, (_) => charset[random.nextInt(charset.length)])
      .join();
}

/// Returns the sha256 hash of [input] in hex notation.
String sha256ofString(String input) {
  final bytes = utf8.encode(input);
  final digest = sha256.convert(bytes);
  return digest.toString();
}
