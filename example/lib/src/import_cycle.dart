// Dart Sentinel — import_cycle rule
//
// Detects circular dependencies in the import graph.
//
// Example cycle:
//   file_a.dart → file_b.dart → file_c.dart → file_a.dart
//
// Run via CLI:
//   dart run dart_sentinel -o arch
//
// In a real project:
//
// ── lib/services/auth_service.dart ──
// import '../repositories/user_repository.dart';  // auth → user_repo
//
// ── lib/repositories/user_repository.dart ──
// import '../services/auth_service.dart';          // user_repo → auth ← CYCLE!
//
// ✅ Fix: Break the cycle by extracting a shared interface or
//    moving shared logic to a third file both can depend on.

class FileA {
  // import 'file_b.dart';
}

// In file_b.dart:
// import 'file_a.dart';  ← This creates a cycle!
