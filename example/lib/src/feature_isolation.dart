// Dart Sentinel — feature_isolation rule
//
// Prevents features from importing directly from each other.
// Features should communicate through shared layers (core, services).
//
// With this analyzer.yaml config:
//
//   architecture:
//     feature_isolation:
//       enabled: true
//       paths: ["lib/features/*/"]
//       allow_shared:
//         - "lib/core/**"
//         - "lib/services/**"
//
// ⚠ feature_isolation: Feature "cart" importing from feature "auth"
//
// In a real project structure:
//   lib/features/cart/view/cart_page.dart
//     import '../../auth/viewmodel/auth_viewmodel.dart';  ← VIOLATION
//
// ✅ Correct: Use a shared service
//   lib/features/cart/view/cart_page.dart
//     import '../../../services/auth_service.dart';       ← OK

class CartPage {
  // This would be flagged in a real project:
  // import '../../auth/viewmodel/auth_viewmodel.dart';  ← cross-feature!

  // ✅ Correct: Depend on shared services
  // import '../../../services/auth_service.dart';
}
