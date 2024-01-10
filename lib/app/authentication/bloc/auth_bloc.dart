import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:circum/utils/app_state/app_state.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart'
    as permission_handler;

import '../../../helper/image_to_base64.dart';
import '../../../helper/location_helper.dart';
import '../../../utils/validator/validator.dart';
import '../repo/auth_repo.dart';
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
        User? user = auth.currentUser;

        if (user != null) {
          print("User is signed in: ${user.uid}");
          // You can also access user information like user.displayName, user.email, etc.
          emit(state.copyWith(
            currentState: AppState.authenticated,
            username: user.displayName,
            phoneNumber: user.phoneNumber,
            email: user.email,
            profilePhoto: user.photoURL,
          ));
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
        debugPrint(event.email);
        emit(state.copyWith(email: event.email));
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

      if (event is RequestForOTP) {
        print({'phoneNumber': state.phoneNumber, 'password': state.password});
        // emit(state.copyWith(isLoading: true, status: Status.loading));

        var completer = Completer<bool>();

        String? _verificationId;
        int? _resendToken;

        try {
          await auth.verifyPhoneNumber(
            phoneNumber: state.phoneNumber,
            verificationCompleted: (_) {},
            verificationFailed: (_) {
              print('Verification failed');
              print(_);
            },
            codeSent: (String verificationId, int? resendToken) async {
              _verificationId = verificationId;
              _resendToken = resendToken;
              completer.complete(true);
            },
            codeAutoRetrievalTimeout: (_) {
              print('Code timed out');
              print(_);
            },
          );
          emit(state.copyWith(status: Status.success));
          await completer.future;
          emit(state.copyWith(
              verificationId: _verificationId, resendToken: _resendToken));
          // print(_verificationId);
          // print(_resendToken);
        } catch (e) {
          // print(e);
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

          // Sign the user in (or link) with the credential
          final UserCredential _userCredential =
              await auth.signInWithCredential(credential);

          if (_userCredential.user?.displayName == null) {
            emit(state.copyWith(status: Status.incompleteData));
          } else {
            print(_userCredential.additionalUserInfo);
            print(_userCredential.credential);
            print(_userCredential.user);
            emit(state.copyWith(
                status: Status.success,
                username: _userCredential.user?.displayName,
                profilePhoto: _userCredential.user?.photoURL,
                email: _userCredential.user?.email,
                phoneNumber: _userCredential.user?.phoneNumber));
          }
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

      if (event is LoginUser) {
        const storage = FlutterSecureStorage();
        await storage.write(key: 'password', value: state.password);
        emit(state.copyWith(isLoading: true, status: Status.loading));
        try {
          Validator.validateLogin(
              data: {'email': state.email, 'password': state.password});
        } catch (e) {
          emit(state.copyWith(
              errorMessage: e.toString().split(':').last.trim(),
              isLoading: false));
        }
      }
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
            }).then((value) => print("DocumentSnapshot successfully updated!"),
                onError: (e) => print("Error updating document $e"));
          } else {
            // Document does not exist
            // print('Document does not exist');
            await db.collection("users").doc(user?.uid).set({
              'name': event.username,
              "role": 'user',
              'phone': user?.phoneNumber,
            }).then((value) => print("DocumentSnapshot successfully created!"),
                onError: (e) => print("Error updating document $e"));
          }

          // print(user);

          emit(
              state.copyWith(status: Status.success, username: event.username));
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
        } else {
          await user?.updateDisplayName(event.value);
          // print(user?.displayName);
          emit(state.copyWith(username: event.value));
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
        } else {
          await user?.updateDisplayName(event.value);
          // print(user?.displayName);
          emit(state.copyWith(username: event.value));
        }
      } catch (e) {
        print(e);
      }
    }));

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
  }
}
