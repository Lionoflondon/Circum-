import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final String? token;
  final String? image;
  final String? email;
  final String? isEmailVerified;
  final String? role;
  final String? phoneNumber;
  final String? fullname;
  final String? message;
  final dynamic data;
  final int? statusCode;
  final String? userType;

  const UserModel(
      {this.token,
      this.image,
      this.email,
      this.isEmailVerified,
      this.role,
      this.phoneNumber,
      this.fullname,
      this.message,
      this.statusCode,
      this.data,
      this.userType});

  @override
  List<Object> get props => [
        {token},
        {image},
        {email},
        {isEmailVerified},
        {role},
        {phoneNumber},
        {fullname},
        {message},
        {statusCode},
        {data},
        {userType}
      ];

  static UserModel fromJson(dynamic json, status) {
    return UserModel(
        token: json['access_token'],
        image: json['user']?['image'] ?? '',
        email: json['email'] ?? '',
        isEmailVerified: json['user']?['isEmailVerified'] ?? '',
        role: json['user']?['role'] ?? '',
        phoneNumber: json['user']?['phoneNumber'] ?? '',
        fullname: json['user']?['fullname'] ?? '',
        message: json['message'] ?? '',
        statusCode: status,
        userType: json['user_type'] ?? '');
  }

  static UserModel response(json, status) {
    return UserModel(message: json['message'], statusCode: status, data: json);
  }

  static UserModel updateUser(dynamic json) {
    return UserModel(
      image: json['image'],
      email: json['email'],
      isEmailVerified: json['isEmailVerified'],
      role: json['role'],
      phoneNumber: json['phoneNumber'],
      fullname: json['fullname'],
    );
  }

  static UserModel validateEmail(response) {
    return const UserModel();
  }

  @override
  String toString() => '''User { 
      token: $token, 
      email: $email, 
      image: $image, 
      isEmailVerified: $isEmailVerified, 
      role: $role, 
      phoneNumber:$phoneNumber, 
      fullname:$fullname,
      message:$message,
      userType: $userType,
      statusCode:$statusCode,
      data:$data
      }
''';
}
