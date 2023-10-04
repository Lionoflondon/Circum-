import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:circum/utils/app_state/app_state.dart';
import 'package:intl/intl.dart';

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
    on<AuthEvent>((event, emit) async {
      if (event is SortSessionState) {
        const storage = FlutterSecureStorage();
        // await storage.write(key: "token", value: null);
        var token = await storage.read(key: "token");
        var pin = await storage.read(key: "pin");
        var phone = await storage.read(key: "phoneNumber");
        if (token != null) {
          print('not null.......');
          // Navigator.pushAndRemoveUntil(
          //     event.context,
          //     MaterialPageRoute(builder: (_) => AppNavView()),
          //     (route) => false);
          emit(state.copyWith(currentState: AppState.authenticated));
        } else {
          print('unauthennticated');
          emit(state.copyWith(currentState: AppState.unauthenticated));
          // Navigator.pushAndRemoveUntil(
          //     event.context,9831
          //     MaterialPageRoute(builder: (_) => OnboardingView()),
          //     (route) => false);
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
                username: _userCredential.user?.displayName));
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

      if (event is UpdateUserProfile) {
        try {
          final User? user = auth.currentUser;
          print(event.username);

          print(user);
          await user?.updateDisplayName(event.username);
          emit(
              state.copyWith(status: Status.success, username: event.username));
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
    });
  }
}
