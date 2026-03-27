// Dart Sentinel — passthrough_function rule
//
// Detects functions that only delegate to another with the same arguments.
// These add indirection without value.

// ignore_for_file: unused_element

void _logMessage(String message, int level) {
  // actual implementation...
}

// ⚠ passthrough_function: Just delegates to _logMessage
void logMessage(String message, int level) => _logMessage(message, level);

String _formatDate(DateTime date, String pattern) {
  return '$pattern: ${date.toIso8601String()}';
}

// ⚠ passthrough_function: Just delegates to _formatDate
String formatDate(DateTime date, String pattern) => _formatDate(date, pattern);

// ✅ Correct: Adds default value — not a pure passthrough
void log(String message, [int level = 0]) => _logMessage(message, level);

// ✅ Correct: Transforms arguments before delegating
String formatDateISO(DateTime date) => _formatDate(date, 'ISO');
