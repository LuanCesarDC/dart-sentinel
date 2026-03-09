// Test script for dispose_check_rule improvements.
// Run: dart run test/dispose_check_test.dart
//
// Creates a temporary project with synthetic Dart files and runs the
// DisposeCheckRule via a real ProjectContext to verify the three fixes:
// 1. Constructor parameter ownership (no false positives)
// 2. Indirect cleanup via helper methods
// 3. Listener target normalization

import 'dart:io';

import 'package:path/path.dart' as p;

import '../lib/src/core/project_context.dart';
import '../lib/src/rules/dispose_check_rule.dart';

Future<void> main() async {
  var passed = 0;
  var failed = 0;

  void expect(bool condition, String description) {
    if (condition) {
      print('  ✅ $description');
      passed++;
    } else {
      print('  ❌ $description');
      failed++;
    }
  }

  // Create a temp project directory
  final tmpDir = await Directory.systemTemp.createTemp('dispose_test_');
  final projectRoot = tmpDir.path;

  // Write pubspec.yaml
  File(p.join(projectRoot, 'pubspec.yaml')).writeAsStringSync('''
name: test_project
version: 1.0.0
environment:
  sdk: ">=3.0.0 <4.0.0"
''');

  // Create lib/
  final libDir = Directory(p.join(projectRoot, 'lib'));
  libDir.createSync();

  // ── File 1: Constructor param ownership ──
  File(p.join(libDir.path, 'constructor_param.dart')).writeAsStringSync('''
import 'dart:async';

class TextEditingController {
  void dispose() {}
}

class FocusNode {
  void dispose() {}
}

// Fields from constructor — should NOT warn
class MyWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  MyWidget({required this.controller, required this.focusNode});

  void dispose() {}
}

// Fields from initializer list — should NOT warn
class InitWidget {
  final TextEditingController controller;

  InitWidget(TextEditingController ctrl) : controller = ctrl;

  void dispose() {}
}
''');

  // ── File 2: Locally created fields — SHOULD warn ──
  File(p.join(libDir.path, 'local_fields.dart')).writeAsStringSync('''
import 'dart:async';

class TextEditingController {
  void dispose() {}
}

class FocusNode {
  void dispose() {}
}

class MyState {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  void dispose() {
    // Missing cleanup!
  }
}
''');

  // ── File 3: Indirect cleanup via helper ──
  File(p.join(libDir.path, 'indirect_cleanup.dart')).writeAsStringSync('''
import 'dart:async';

class MyService {
  StreamSubscription? _sub1;
  StreamSubscription? _sub2;

  void reset() {
    _sub1?.cancel();
    _sub2?.cancel();
  }

  void dispose() {
    reset();
  }
}
''');

  // ── File 4: Deep indirect cleanup ──
  File(p.join(libDir.path, 'deep_cleanup.dart')).writeAsStringSync('''
import 'dart:async';

class DeepService {
  StreamSubscription? _sub;

  void _innerCleanup() {
    _sub?.cancel();
  }

  void _outerCleanup() {
    _innerCleanup();
  }

  void dispose() {
    _outerCleanup();
  }
}
''');

  // ── File 5: Mixed constructor + local ──
  File(p.join(libDir.path, 'mixed_fields.dart')).writeAsStringSync('''
import 'dart:async';

class TextEditingController {
  void dispose() {}
}

class FocusNode {
  void dispose() {}
}

class MixedWidget {
  final TextEditingController externalController;
  final TextEditingController _localController = TextEditingController();
  final FocusNode externalFocus;

  MixedWidget({required this.externalController, required this.externalFocus});

  void dispose() {
    _localController.dispose();
  }
}
''');

  // ── File 6: Entrypoint ──
  File(p.join(libDir.path, 'main.dart')).writeAsStringSync('''
import 'constructor_param.dart';
import 'local_fields.dart';
import 'indirect_cleanup.dart';
import 'deep_cleanup.dart';
import 'mixed_fields.dart';

void main() {}
''');

  // Build context and run the rule
  final context = await ProjectContext.build(projectRoot);
  final rule = DisposeCheckRule();
  final allIssues = rule.run(context);

  // Group issues by file
  final issuesByFile = <String, List<dynamic>>{};
  for (final issue in allIssues) {
    issuesByFile.putIfAbsent(issue.file, () => []).add(issue);
  }

  // ── Test 1: Constructor param fields should NOT trigger warnings ──
  print('\n── Test 1: Constructor parameter ownership ──');
  final constructorIssues = issuesByFile['lib/constructor_param.dart'] ?? [];
  expect(
    constructorIssues.isEmpty,
    'No warnings for constructor param fields (got ${constructorIssues.length})',
  );
  for (final i in constructorIssues) {
    print('    → ${i.message}');
  }

  // ── Test 2: Locally created fields SHOULD trigger warnings ──
  print('\n── Test 2: Locally created fields require cleanup ──');
  final localIssues = issuesByFile['lib/local_fields.dart'] ?? [];
  expect(
    localIssues.length == 2,
    'Two warnings for locally created fields (got ${localIssues.length})',
  );
  for (final i in localIssues) {
    print('    → ${i.message}');
  }

  // ── Test 3: Indirect cleanup via helper method ──
  print('\n── Test 3: Indirect cleanup via helper methods ──');
  final indirectIssues = issuesByFile['lib/indirect_cleanup.dart'] ?? [];
  expect(
    indirectIssues.isEmpty,
    'No warnings when cleanup is in helper methods (got ${indirectIssues.length})',
  );
  for (final i in indirectIssues) {
    print('    → ${i.message}');
  }

  // ── Test 4: Deeply nested indirect cleanup ──
  print('\n── Test 4: Deeply nested indirect cleanup ──');
  final deepIssues = issuesByFile['lib/deep_cleanup.dart'] ?? [];
  expect(
    deepIssues.isEmpty,
    'No warnings for deeply nested cleanup (got ${deepIssues.length})',
  );
  for (final i in deepIssues) {
    print('    → ${i.message}');
  }

  // ── Test 5: Mixed — some from constructor, some local ──
  print('\n── Test 5: Mixed constructor + local fields ──');
  final mixedIssues = issuesByFile['lib/mixed_fields.dart'] ?? [];
  expect(
    mixedIssues.isEmpty,
    'No warnings when local is disposed and constructor params skipped (got ${mixedIssues.length})',
  );
  for (final i in mixedIssues) {
    print('    → ${i.message}');
  }

  // Cleanup
  await tmpDir.delete(recursive: true);

  print('\n────────────────────────────────');
  print('Passed: $passed, Failed: $failed');
  if (failed > 0) {
    print('⚠️  Some tests failed!');
    exit(1);
  } else {
    print('All tests passed!');
  }
}
