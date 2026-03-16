// Dart Sentinel — layer_dependency + banned_imports rules
//
// This file simulates a ViewModel importing directly from a data layer,
// violating the architecture defined in analyzer.yaml.
//
// With this analyzer.yaml config:
//
//   architecture:
//     layers:
//       viewmodel:
//         paths: ["lib/features/**/viewmodel/**"]
//         can_depend_on: ["service", "core"]
//       service:
//         paths: ["lib/services/**"]
//         can_depend_on: ["repository", "core"]
//
//     banned_imports:
//       - paths: ["lib/features/**/viewmodel/**"]
//         deny: ["package:cloud_firestore/**"]
//         message: "ViewModels must not access Firestore directly."
//
// ⚠ layer_dependency: ViewModel importing from data layer
// ⚠ banned_imports: ViewModel importing cloud_firestore
//
// These rules require an `analyzer.yaml` config and only run via CLI:
//   dart run dart_sentinel -o arch

class UserViewModel {
  // In a real project, this import would be flagged:
  // import 'package:cloud_firestore/cloud_firestore.dart';
  // import '../../repositories/user_repository.dart';

  // ✅ Correct: ViewModel depends on Service, not Repository/Firestore
  // import '../../services/user_service.dart';
}
