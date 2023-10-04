import 'is_empty.dart';

class Validator {
  Validator();

  // Form validation for registration
  static void validateRegistration({required data}) {
    if (!IsEmpty.isEmpty(data['email'])) {
      if (!RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+')
          .hasMatch(data['email'])) {
        throw Exception('Please use a valid email');
      }
    } else {
      throw Exception('Email field cannot be empty');
    }
    if (IsEmpty.isEmpty(data['username'])) {
      throw Exception('Username cannot be empty');
    }
    if (IsEmpty.isEmpty(data['password'])) {
      throw Exception('Password cannot be empty');
    }
    if (!IsEmpty.isEmpty(data['password']) &&
        '${data['password']}'.length < 6) {
      throw Exception('Password cannot be less than six characters');
    }
    if (IsEmpty.isEmpty(data['countryCode'])) {
      throw Exception('Please select a country');
    }

    if (IsEmpty.isEmpty(data['selectedCity'])) {
      throw Exception('Please select a city');
    }
  }

  static void validateLogin({required data}) {
    if (!IsEmpty.isEmpty(data['email'])) {
      if (!RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+')
          .hasMatch(data['email'])) {
        throw Exception('Please use a valid email');
      }
    } else {
      throw Exception('Email field cannot be empty');
    }
    if (IsEmpty.isEmpty(data['password'])) {
      throw Exception('Password field cannot be empty');
    }
  }

  static void validatePasswordReset({required data}) {
    if (IsEmpty.isEmpty(data['email'])) {
      throw Exception('Email field cannot be empty');
    }
    if (IsEmpty.isEmpty(data['otp'])) {
      throw Exception('Token field cannot be empty');
    }
    if (IsEmpty.isEmpty(data['password'])) {
      throw Exception('Password field cannot be empty');
    }
    if (IsEmpty.isEmpty(data['confirmPassword'])) {
      throw Exception('Confirm Password field cannot be empty');
    }
  }

  static void validateEmail({required data}) {
    if (!IsEmpty.isEmpty(data['email'])) {
      if (!RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+')
          .hasMatch(data['email'])) {
        throw Exception('Please use a valid email');
      }
    } else {
      throw Exception('Email field cannot be empty');
    }
  }

  static void validateEmailAndPassword({required data}) {
    if (!IsEmpty.isEmpty(data['email'])) {
      if (!RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+')
          .hasMatch(data['email'])) {
        throw Exception('Please use a valid email');
      }
    } else {
      throw Exception('Email field cannot be empty');
    }

    if (IsEmpty.isEmpty(data['password'])) {
      throw Exception('Password field cannot be empty');
    }
    if (IsEmpty.isEmpty(data['confirmPassword'])) {
      throw Exception('Confirm Password field cannot be empty');
    }

    if (data['confirmPassword'] != data['password']) {
      throw Exception('Passwords do not match.');
    }
  }

  static void validatePhoneAndPassword({required data}) {
    if (IsEmpty.isEmpty(data['phoneNumber'])) {
      throw Exception('Please add a phone number');
    }

    if (IsEmpty.isEmpty(data['password'])) {
      throw Exception('Password field cannot be empty');
    }
  }

  static void validatePost({required data}) {
    if (IsEmpty.isEmpty(data['firstName'])) {
      throw Exception('Name field cannot be empty');
    }
    if (IsEmpty.isEmpty(data['localImagePath'])) {
      throw Exception('please add an image');
    }
    if (IsEmpty.isEmpty(data['caption'])) {
      throw Exception('Please add a caption');
    }
  }
}
