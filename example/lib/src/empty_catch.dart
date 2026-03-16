// Dart Sentinel — empty_catch rule
//
// Detects empty catch blocks and catch blocks that only print the error.
// Quick fix available: Add `rethrow`

// ignore_for_file: unused_local_variable

void emptyCatchBlock() {
  try {
    final data = fetchFromApi();
  } catch (e) {
    // ⚠ empty_catch: Exception silently swallowed
  }
}

void catchAndPrintOnly() {
  try {
    final data = fetchFromApi();
  } catch (e) {
    print(e); // ⚠ empty_catch: Catch only prints — error is still lost
  }
}

// ✅ Correct: re-throw, log properly, or handle the error
void correctCatch() {
  try {
    final data = fetchFromApi();
  } catch (e) {
    print('Failed to fetch: $e');
    rethrow;
  }
}

String fetchFromApi() => 'data';
