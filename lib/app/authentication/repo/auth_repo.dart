import '../models/user_model.dart';

class AuthRepository {
  // Create A User
  // ........................
  Future<bool> signUp() async {
    try {
      return true;
    } catch (e) {
      // print(e);
      throw Exception("Something went wrong");
    }
  }

  // User Sign in
  // ........................
  Future<bool> signIn({required String email, required String password}) async {
    try {
      return true;
    } catch (e) {
      print(e);
    }
    throw Exception("Something went wrong");
    // SubmissionFailed(Exception());
  }

  Future<UserModel> signupWithGoogle(accessToken) async {
    //
    // try {
    //   var response = await dio.post(
    //     Endpoints.baseURl + Endpoints.googleSignup,
    //     data: {
    //       'access_token': accessToken,
    //     },
    //     options: Options(
    //       followRedirects: false,
    //       validateStatus: (status) {
    //         return status! < 500;
    //       },
    //     ),
    //   );

    //   return UserModel.fromJson(response.data, response.statusCode);
    // } catch (e) {
    //   print(e);
    //   throw Exception("Something went wrong");
    // }
    return UserModel();
  }

  // Request for an OTP while registering
  // ........................
  Future<bool> requestOTP({
    required String email,
  }) async {
    try {
      return true;
    } catch (e) {
      // print(e);
      throw Exception("Something went wrong");
    }
  }

  // Verify User OTP
  // ........................
  Future<bool> verifyOTP() async {
    try {
      return true;
    } catch (e) {
      print(e);
      throw Exception("Something went wrong");
    }
  }

  // Request for an OTP while registering
  // ........................
  Future updateUser() async {}

  Future<void> signOut() async {
    await Future.delayed(Duration(seconds: 2));
  }
}
