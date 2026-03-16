// Dart Sentinel — dead_files + dead_exports rules
//
// dead_files: Detects files unreachable from any entrypoint.
// dead_exports: Detects exports that no file imports.
//
// These rules analyze the full import graph of your project.
// Run via CLI:
//   dart run dart_sentinel -o dead

// ⚠ dead_files: This file is never imported by any other file
//    reachable from main.dart — it's dead code.

// ⚠ dead_exports: The function below is exported but never imported
//    by any file in the project.

/// This class is never used anywhere.
class ObsoleteHelper {
  void doSomething() {}
}

/// This function is exported but never imported.
String deprecatedUtil() => 'unused';

// ✅ Fix: Remove the file, or add an import from an active file.
