class IsEmpty {
  IsEmpty();
  static bool isEmpty(value) {
    // ignore: unnecessary_null_comparison
    return value == '' || value == null || value.trim().isEmpty;
  }
}
