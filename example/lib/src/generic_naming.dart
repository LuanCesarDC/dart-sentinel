// Dart Sentinel — generic_naming rule
//
// Catches variables and functions with low semantic specificity.
// Names like "data", "result", "temp", "handleData" tell nothing about intent.

// ignore_for_file: unused_local_variable, unused_element

// ⚠ generic_naming: "data" — what kind of data?
void processData(dynamic data) {
  // ⚠ generic_naming: "result" — result of what?
  final result = data.toString();

  // ⚠ generic_naming: "temp" — temporary what?
  final temp = result.length;

  // ⚠ generic_naming: "info" — info about what?
  final info = {'key': 'value'};
}

// ⚠ generic_naming: "handleData" — handle how? what data?
void handleData(String input) {}

// ⚠ generic_naming: "doProcess" — process what?
void doProcess() {}

// ✅ Correct: Descriptive names that reveal intent
void parseUserProfile(Map<String, dynamic> json) {
  final userName = json['name'] as String;
  final accountAge = DateTime.now().difference(
    DateTime.parse(json['created_at'] as String),
  );
}

void validateEmailFormat(String email) {}
void syncCartWithServer() {}
