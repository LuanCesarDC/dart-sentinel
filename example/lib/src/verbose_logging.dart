// Dart Sentinel — verbose_logging rule
//
// Flags 3+ consecutive print/debugPrint/log statements.
// Quick fix available: Combine into single print

// ignore_for_file: avoid_print

void debugUserLogin(String userId) {
  // ⚠ verbose_logging: 5 consecutive prints
  print('=== Login Debug ===');
  print('User ID: $userId');
  print('Timestamp: ${DateTime.now()}');
  print('Platform: android');
  print('===================');
}

void traceApiCall(String endpoint, int statusCode) {
  // ⚠ verbose_logging: 4 consecutive prints
  print('API Call:');
  print('  Endpoint: $endpoint');
  print('  Status: $statusCode');
  print('  Time: ${DateTime.now()}');
}

// ✅ Correct: Single structured log
void correctLogging(String userId) {
  print([
    '=== Login Debug ===',
    'User ID: $userId',
    'Timestamp: ${DateTime.now()}',
    'Platform: android',
    '===================',
  ].join('\n'));
}
