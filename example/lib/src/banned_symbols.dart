// Dart Sentinel — banned_symbols rule
//
// Prevents usage of specific symbols to enforce design system adoption.
//
// With this analyzer.yaml config:
//
//   architecture:
//     banned_symbols:
//       - paths: ["lib/features/**"]
//         deny: ["ElevatedButton", "TextButton", "OutlinedButton"]
//         suggest: "AppButton"
//         message: "Use AppButton from your design system."
//       - paths: ["lib/features/**"]
//         deny: ["showDialog"]
//         suggest: "AppDialog.show"
//         message: "Use AppDialog.show for consistent dialogs."
//
// Track migration progress:
//   dart run dart_sentinel -o migrations

// ignore_for_file: unused_element

// In a real Flutter project, these would be flagged:
//
// ⚠ banned_symbols: Use AppButton instead of ElevatedButton
// Widget build(BuildContext context) {
//   return ElevatedButton(onPressed: () {}, child: Text('Save'));
// }
//
// ⚠ banned_symbols: Use AppDialog.show instead of showDialog
// void onTap(BuildContext context) {
//   showDialog(context: context, builder: (_) => AlertDialog());
// }

// ✅ Correct: Use design system components
// Widget build(BuildContext context) {
//   return AppButton(onPressed: () {}, label: 'Save');
// }
