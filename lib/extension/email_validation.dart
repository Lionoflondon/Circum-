extension EmailValidation on String {
  bool isValidEmail() {
    // Updated regular expression pattern for email validation
    final emailRegex = RegExp(r'^[\w-\.]+(\+[\w-]+)*@([\w-]+\.)+[\w-]{2,4}$');
    
    return emailRegex.hasMatch(this);
  }
}