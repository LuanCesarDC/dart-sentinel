// Dart Sentinel — single_method_class rule
//
// Detects classes with only one public method.
// These are often better expressed as plain functions.

// ignore_for_file: unused_element

// ⚠ single_method_class: Only has `validate` — should be a function
class EmailValidator {
  bool validate(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }
}

// ⚠ single_method_class: Only has `format` — should be a function
class DateFormatter {
  String format(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ✅ Correct: Plain function
bool validateEmail(String email) {
  return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
}

// ✅ Correct: Class with multiple responsibilities
class UserRepository {
  Future<Map<String, dynamic>> findById(String id) async => {};
  Future<void> save(Map<String, dynamic> user) async {}
  Future<void> delete(String id) async {}
}
